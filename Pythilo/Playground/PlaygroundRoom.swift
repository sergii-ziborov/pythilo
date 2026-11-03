import Foundation
import Observation
import UIKit

struct PlaygroundParticipant: Identifiable, Equatable {
    let id: String
    let name: String
    let detail: String
    let access: String
    let isSelf: Bool
}

/// One live room bound to one project folder. Remote edits are written to the folder
/// and reach the open editor; edits made in the app go back to the room.
@MainActor
@Observable
final class PlaygroundRoom: Identifiable {
    nonisolated let id: String
    let session: PlaygroundLiveSession
    let host: PlaygroundRuntimeHost
    let isOwner: Bool
    /// The link handed out lets people edit, rather than only view.
    let sharesEditing: Bool
    let leftOut: [PlaygroundLeftOut]
    private(set) var project: Project?
    private(set) var failure: String?

    private var people: [UInt32: Seen] = [:]
    @ObservationIgnored private var mirrored: [String: String] = [:]
    @ObservationIgnored private var applying = false
    @ObservationIgnored private var sync: Task<Void, Never>?

    private init(session: PlaygroundLiveSession, project: Project?, isOwner: Bool, sharesEditing: Bool, policy: PlaygroundRunPolicy, leftOut: [PlaygroundLeftOut]) {
        id = session.link.id
        self.session = session
        self.project = project
        self.isOwner = isOwner
        self.sharesEditing = sharesEditing
        self.leftOut = leftOut
        host = PlaygroundRuntimeHost(session: session, policy: session.link.isReadOnly ? .off : policy)
        session.onDocument = { [weak self] document in self?.received(document) }
        let hosting = session.onRuntimeFrames
        session.onRuntimeFrames = { [weak self] frames in
            self?.learn(frames)
            hosting?(frames)
        }
    }

    static func share(_ project: Project, selection: PlaygroundProjectFiles.Selection, lifetimeSeconds: Int, editing: Bool,
                      policy: PlaygroundRunPolicy, origin: URL, codecURL: URL? = nil) async throws -> PlaygroundRoom {
        let session = try await PlaygroundLiveSession.create(document: selection.document, lifetimeSeconds: lifetimeSeconds, origin: origin, codecURL: codecURL)
        let room = PlaygroundRoom(session: session, project: project, isOwner: true, sharesEditing: editing, policy: policy, leftOut: selection.leftOut)
        room.mirrored = selection.document.files
        room.begin()
        return room
    }

    static func join(_ link: PlaygroundLink, origin: URL, codecURL: URL? = nil) throws -> PlaygroundRoom {
        let session = try PlaygroundLiveSession(link: link, origin: origin, codecURL: codecURL)
        let room = PlaygroundRoom(session: session, project: nil, isOwner: false, sharesEditing: !link.isReadOnly, policy: .ask, leftOut: [])
        room.begin()
        return room
    }

    private func begin() {
        session.setDisplayName(PlaygroundRuntimeHost.ownerName ?? PlaygroundRuntimeHost.deviceName)
        session.start()
        sync = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(1.5)) } catch { return }
                guard let self, !session.expired else { return }
                guard !applying else { continue }
                applying = true
                pushLocalChanges()
                applying = false
            }
        }
    }

    var name: String { session.document?.name ?? project?.name ?? "Room" }
    var ended: Bool { session.expired }

    /// The link to hand out: editing, or the view-only capability the relay issued.
    var shareLink: PlaygroundLink {
        if isOwner, !sharesEditing, let view = session.viewAccess { return session.link.readOnly(access: view) }
        return session.link
    }

    var shareURL: URL { shareLink.url(origin: session.origin) }

    var revision: String? { (try? session.runtimeSourceIdentity().revision).map { String($0.prefix(6)) } }

    func end() async throws {
        if isOwner, !session.expired { try await session.closeRoom() }
        close()
    }

    func close() {
        sync?.cancel()
        host.stop()
        session.stop()
        try? FileManager.default.removeItem(at: PlaygroundPythonJob.folder(room: id))
    }

    func setForeground(_ value: Bool) { host.setForeground(value) }

    // MARK: Files

    /// Typing in the open editor reaches the room at once, not at the next save.
    func edited(path: String, text: String) {
        guard session.isEditable, session.document?.files[path] != nil, !applying else { return }
        // The buffer already holds this text and saves it itself.
        applying = true
        session.edit(file: path, text: text)
        applying = false
    }

    func select(path: String, range: NSRange) {
        session.select(file: path, range: range)
    }

    private func received(_ document: PlaygroundDocument) {
        guard !applying else { return }
        applying = true
        defer { applying = false }
        guard let project else {
            createProject(from: document)
            return
        }
        // Local changes not yet sent go into the shared document first, so writing
        // the merged result cannot overwrite them.
        pushLocalChanges()
        let latest = session.document ?? document
        let removed = Set(mirrored.keys).subtracting(latest.files.keys)
        let added = Set(latest.files.keys).subtracting(mirrored.keys)
        do {
            let touched = try PlaygroundProjectFiles.write(latest, to: project.url, removing: removed)
            mirrored = latest.files
            if !touched.isEmpty, let workspace = PlaygroundRooms.shared.workspace, workspace.project.id == project.id {
                workspace.roomChanged(latest.files, treeChanged: !removed.isEmpty || !added.isEmpty)
            }
        } catch {
            failure = "Could not write the room's files: \(error.localizedDescription)"
        }
    }

    private func createProject(from document: PlaygroundDocument) {
        let store = ProjectStore.shared
        store.refresh()
        let existing = store.projects.first { Self.roomTag(of: $0.url) == id }
        let url = existing?.url ?? store.root.appending(path: store.uniqueName(document.name))
        do {
            try FileManager.default.createDirectory(at: url.appending(path: ".pythilo"), withIntermediateDirectories: true)
            try PlaygroundProjectFiles.write(document, to: url, removing: [])
            try id.write(to: url.appending(path: ".pythilo/room"), atomically: true, encoding: .utf8)
            mirrored = document.files
            project = Project(url: url, modified: Date())
            store.refresh()
        } catch {
            failure = "Could not create a project from the room: \(error.localizedDescription)"
        }
    }

    static func roomTag(of url: URL) -> String? {
        (try? String(contentsOf: url.appending(path: ".pythilo/room"), encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Files changed on disk by the app, a program or an AI client go to the room.
    /// A new file joins if it fits the room's limits; a file left out when sharing stays out.
    private func pushLocalChanges() {
        guard let project, session.isEditable, let current = session.document else { return }
        var next = current
        var changed: [String: String] = [:]
        for (path, known) in mirrored {
            guard let url = PlaygroundProjectFiles.url(for: path, in: project.url) else { continue }
            if let data = try? Data(contentsOf: url) {
                guard let text = String(data: data, encoding: .utf8), text != known, !text.contains("\0"),
                      text.utf8.count <= PlaygroundDocument.maximumFileBytes else { continue }
                if text == current.files[path] {
                    // Typed in the editor and already sent; now saved.
                    mirrored[path] = text
                    continue
                }
                next.files[path] = text
                changed[path] = text
            } else if !FileManager.default.fileExists(atPath: url.path), path != current.entryFile {
                next.files[path] = nil
            }
        }
        let skipped = Set(leftOut.map(\.path))
        var total = next.files.values.reduce(0) { $0 + $1.utf8.count }
        for path in Self.candidatePaths(in: project.url) where next.files[path] == nil && mirrored[path] == nil && !skipped.contains(path) {
            guard next.files.count < PlaygroundDocument.maximumFiles, let url = PlaygroundProjectFiles.url(for: path, in: project.url),
                  let data = try? Data(contentsOf: url), data.count <= PlaygroundDocument.maximumFileBytes,
                  total + data.count <= PlaygroundDocument.maximumTotalBytes,
                  let text = String(data: data, encoding: .utf8), !text.contains("\0") else { continue }
            next.files[path] = text
            changed[path] = text
            total += data.count
        }
        guard next != current else { return }
        do {
            try session.replace(next.validated())
            for (path, text) in changed { mirrored[path] = text }
            for path in mirrored.keys where next.files[path] == nil { mirrored[path] = nil }
            failure = nil
        } catch {
            failure = "A change could not join the room: \(error.localizedDescription)"
        }
    }

    private static func candidatePaths(in root: URL) -> [String] {
        let base = root.standardizedFileURL.resolvingSymlinksInPath().path + "/"
        guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey]) else { return [] }
        var result: [String] = []
        for case let url as URL in walker {
            let name = url.lastPathComponent
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey])
            if values?.isDirectory == true {
                if PlaygroundDocument.refusedFolders.contains(name.lowercased()) { walker.skipDescendants() }
                continue
            }
            guard values?.isRegularFile == true else { continue }
            let full = url.standardizedFileURL.resolvingSymlinksInPath().path
            guard full.hasPrefix(base) else { continue }
            let path = String(full.dropFirst(base.count))
            if PlaygroundDocument.allows(path: path) { result.append(path) }
            if result.count > 256 { break }
        }
        return result.sorted()
    }

    // MARK: People

    /// What each participant last said it is. A browser that both hosts and asks other
    /// devices to run code alternates its one runtime presence field between the two.
    private struct Seen {
        var host: (name: String, detail: String)?
        var controller: String?
        var canEdit = false
    }

    private func learn(_ frames: [PlaygroundCodec.RuntimePresenceFrame]) {
        let capability = session.link.isReadOnly ? nil : session.link.access
        let live = Set(frames.map(\.clientID))
        people = people.filter { live.contains($0.key) }
        for frame in frames {
            guard let verified = try? PlaygroundRuntimeProtocol.identify(Data(frame.envelope.utf8), room: id, editCapability: capability),
                  verified.header.kind == "capabilities",
                  let payload = (try? JSONSerialization.jsonObject(with: verified.payload)) as? [String: Any],
                  let name = (payload["name"] as? String).map({ String($0.prefix(60)) }), !name.isEmpty else { continue }
            var seen = people[frame.clientID] ?? Seen()
            if payload["role"] as? String == "host" {
                let kind = switch payload["kind"] as? String {
                case "browser": "Browser"
                case "ios": "iPhone or iPad"
                default: "Device"
                }
                seen.host = (name, [kind, (payload["runtime"] as? String).map { String($0.prefix(60)) }].compactMap { $0 }.joined(separator: " · "))
            } else {
                seen.controller = name
            }
            seen.canEdit = seen.canEdit || verified.editAccessProved
            people[frame.clientID] = seen
        }
    }

    var participants: [PlaygroundParticipant] {
        let device = UIDevice.current.userInterfaceIdiom == .pad ? "This iPad" : "This iPhone"
        let python = (RunSession.shared.pythonVersion ?? "3.14").split(separator: ".").prefix(2).joined(separator: ".")
        var result = [PlaygroundParticipant(id: "self", name: "You", detail: "\(device) · CPython \(python)",
                                            access: isOwner ? "Owner" : session.link.isReadOnly ? "Can view" : "Can edit", isSelf: true)]
        var listed: Set<UInt64> = []
        for (client, seen) in people.sorted(by: { $0.key < $1.key }) {
            let editing = session.selections.first { $0.clientID == UInt64(client) }
            let controller = seen.controller.map(PlaygroundController.init)
            let name = seen.host?.name ?? controller?.name ?? editing?.name ?? "Participant"
            let detail = seen.host?.detail ?? controller?.kind ?? "In the room"
            listed.insert(UInt64(client))
            result.append(PlaygroundParticipant(id: "client-\(client)", name: name, detail: detail + (editing.map { " · editing \($0.file)" } ?? ""),
                                                access: seen.canEdit ? "Can edit" : "", isSelf: false))
        }
        for selection in session.selections where !listed.contains(selection.clientID) {
            listed.insert(selection.clientID)
            result.append(PlaygroundParticipant(id: "client-\(selection.clientID)", name: String(selection.name.prefix(40)),
                                                detail: "Editing \(selection.file)", access: "", isSelf: false))
        }
        let others = session.participants - result.count
        if others > 0 {
            result.append(PlaygroundParticipant(id: "others", name: others == 1 ? "1 more person" : "\(others) more people",
                                                detail: "Connected, not editing", access: "", isSelf: false))
        }
        return result
    }

    /// "You, Claude · code runs on this iPhone"
    var summary: String {
        let names = ["You"] + participants.filter { !$0.isSelf && $0.id != "others" }.map(\.name)
        let device = UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone"
        let running = host.policy == .off ? "code runs where people press Run" : "code runs on this \(device)"
        return names.prefix(3).joined(separator: ", ") + " · " + running
    }
}

/// The rooms this device is in, and the open workspace they write to.
@MainActor
@Observable
final class PlaygroundRooms {
    static let shared = PlaygroundRooms()

    private(set) var rooms: [PlaygroundRoom] = []
    @ObservationIgnored weak var workspace: WorkspaceModel?

    var origin: URL? { PlaygroundRelayConfiguration.origin }
    var isAvailable: Bool { origin != nil && PlaygroundCodec.bundledURL != nil }

    var unavailableReason: String? {
        if origin == nil { return "Shared rooms need a relay, and none is set up in this build yet." }
        if PlaygroundCodec.bundledURL == nil { return "This build has no collaboration codec, so rooms are unavailable." }
        return nil
    }

    var live: [PlaygroundRoom] { rooms.filter { !$0.ended } }

    func room(for project: Project) -> PlaygroundRoom? {
        live.first { $0.project?.id == project.id }
    }

    func share(_ project: Project, selection: PlaygroundProjectFiles.Selection, lifetimeSeconds: Int, editing: Bool, policy: PlaygroundRunPolicy) async throws -> PlaygroundRoom {
        guard let origin else { throw PlaygroundFailure(unavailableReason ?? "Rooms are unavailable.") }
        if let existing = room(for: project) { return existing }
        let room = try await PlaygroundRoom.share(project, selection: selection, lifetimeSeconds: lifetimeSeconds, editing: editing, policy: policy, origin: origin)
        rooms.insert(room, at: 0)
        return room
    }

    /// Joins and waits until the room's files are in a new project folder.
    func join(_ link: PlaygroundLink) async throws -> PlaygroundRoom {
        guard let origin else { throw PlaygroundFailure(unavailableReason ?? "Rooms are unavailable.") }
        if let existing = live.first(where: { $0.id == link.id }) { return existing }
        guard link.expiresAt > Date() else { throw PlaygroundFailure("This room has already ended.") }
        let room = try PlaygroundRoom.join(link, origin: origin)
        let deadline = Date().addingTimeInterval(30)
        while room.project == nil {
            if room.ended || Date() > deadline || room.failure != nil {
                let reason = room.failure ?? (room.ended ? "This room has ended." : room.session.status)
                room.close()
                throw PlaygroundFailure(reason)
            }
            try await Task.sleep(for: .milliseconds(150))
        }
        rooms.insert(room, at: 0)
        return room
    }

    func end(_ room: PlaygroundRoom) async throws {
        try await room.end()
        rooms.removeAll { $0 === room }
    }

    func edited(project: Project, path: String, text: String) {
        room(for: project)?.edited(path: path, text: text)
    }

    func setForeground(_ value: Bool) {
        for room in live { room.setForeground(value) }
    }
}

/// A controller's name as the website and the MCP bridge send it: "Ada · website" is a
/// person in a browser; anything else is an AI client through the Pythilo MCP bridge.
struct PlaygroundController {
    let name: String
    let isBrowser: Bool

    init(_ raw: String) {
        let suffix = " · website"
        isBrowser = raw.hasSuffix(suffix)
        name = isBrowser ? String(raw.dropLast(suffix.count)) : raw
    }

    var kind: String { isBrowser ? "Browser" : "AI client over MCP" }
    var from: String { isBrowser ? "from a browser" : "from an AI client" }
}
