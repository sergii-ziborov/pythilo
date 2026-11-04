import SwiftUI
import UIKit

enum PlaygroundRoute: Hashable {
    case room(String)
    case connection
}

struct PlaygroundView: View {
    let store: ProjectStore
    let onOpen: (Project) -> Void
    @Binding var incomingLink: String?
    @State private var rooms = PlaygroundRooms.shared
    @State private var host = MCPHost.shared
    @State private var path: [PlaygroundRoute] = []
    @State private var sharing = false
    @State private var joining = false
    @State private var joinLink: String?

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Work on one project with another person or an AI client. Edits and running code are separate permissions.")
                        .font(.system(size: 15))
                        .foregroundStyle(AppTheme.secondary)
                    Button {
                        sharing = true
                    } label: {
                        Label("Share a project", systemImage: "plus")
                            .playgroundButton(.primary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("room-share")
                    Button {
                        joinLink = nil
                        joining = true
                    } label: {
                        Text("Join with a link").playgroundButton(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("room-join")
                    if let reason = rooms.unavailableReason {
                        Text(reason).font(.system(size: 13)).foregroundStyle(AppTheme.muted)
                    }
                    connectionCard
                    if !rooms.live.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("ACTIVE ROOMS").sectionLabel()
                            ForEach(rooms.live) { room in
                                NavigationLink(value: PlaygroundRoute.room(room.id)) { RoomRow(room: room) }
                                    .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
            .background(AppTheme.background)
            .navigationTitle("Playground")
            .onAppear(perform: store.refresh)
            .navigationDestination(for: PlaygroundRoute.self) { route in
                switch route {
                case let .room(id):
                    if let room = rooms.rooms.first(where: { $0.id == id }) {
                        RoomView(room: room, onOpen: onOpen)
                    }
                case .connection:
                    MCPConnectionView(store: store)
                }
            }
            .sheet(isPresented: $sharing) {
                ShareProjectSheet(store: store) { room, connect in
                    sharing = false
                    path = [.room(room.id)] + (connect ? [.connection] : [])
                }
            }
            .sheet(isPresented: $joining) {
                JoinRoomSheet(initialLink: joinLink, onJoined: { room in
                    joining = false
                    path = [.room(room.id)]
                }, onSnapshot: { snapshot in
                    joining = false
                    if let project = try? snapshot.createProject(in: store) { onOpen(project) }
                })
            }
            #if DEBUG
            .task {
                // For screenshots: -roomSheet share | join
                switch UserDefaults.standard.string(forKey: "roomSheet") {
                case "share": sharing = true
                case "join": joining = true
                default: break
                }
                // -roomCreate <project>: share it at once and leave the link in Caches/room-link.
                // -roomPolicy ask | allow | off picks who may run code here.
                let policy = UserDefaults.standard.string(forKey: "roomPolicy").flatMap(PlaygroundRunPolicy.init(rawValue:)) ?? .ask
                if let name = UserDefaults.standard.string(forKey: "roomCreate"), let project = store.projects.first(where: { $0.name == name }),
                   let selection = try? PlaygroundProjectFiles.collect(from: project.url, name: project.name),
                   let room = try? await rooms.share(project, selection: selection, lifetimeSeconds: 14_400, editing: true, policy: policy) {
                    let file = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appending(path: "room-link")
                    try? room.shareURL.absoluteString.write(to: file, atomically: true, encoding: .utf8)
                    path = [.room(room.id)]
                }
            }
            #endif
            .onChange(of: incomingLink, initial: true) { _, link in
                guard let link else { return }
                incomingLink = nil
                sharing = false
                joinLink = link
                joining = true
            }
        }
    }

    private var connectionCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(AppTheme.violet)
                    .frame(width: 40, height: 40)
                    .background(AppTheme.violet.opacity(0.16), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text("AI client over MCP").font(.system(size: 16, weight: .bold))
                    Text("Claude, Codex or any MCP client").font(.system(size: 13)).foregroundStyle(AppTheme.muted)
                }
                Spacer(minLength: 4)
                Text(host.clientName != nil ? "1 connected" : host.isRunning ? "Waiting" : "Off")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(host.clientName != nil ? AppTheme.mint : host.isRunning ? AppTheme.amber : AppTheme.muted)
            }
            NavigationLink(value: PlaygroundRoute.connection) {
                Text("Manage connection").font(.system(size: 15, weight: .semibold))
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(AppTheme.raised, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("mcp-manage")
        }
        .padding(14)
        .panelCard(cornerRadius: 16)
    }
}

private struct RoomRow: View {
    let room: PlaygroundRoom

    var body: some View {
        HStack(spacing: 10) {
            FileIconView(name: "", isDirectory: true, isOpen: true)
            VStack(alignment: .leading, spacing: 1) {
                Text(room.name).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                Text(room.summary).font(.system(size: 13)).foregroundStyle(AppTheme.muted).lineLimit(2)
            }
            Spacer(minLength: 4)
            TimelineView(.periodic(from: .now, by: 30)) { context in
                Text("Ends in " + RoomTime.remaining(until: room.session.link.expiresAt, now: context.date))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppTheme.amber)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(minHeight: 64)
        .panelCard()
    }
}

enum RoomTime {
    /// "3 h 12 min", "42 min", "under a minute"
    static func remaining(until date: Date, now: Date = Date()) -> String {
        let minutes = Int(date.timeIntervalSince(now) / 60)
        if minutes < 1 { return "under a minute" }
        if minutes < 60 { return "\(minutes) min" }
        return minutes % 60 == 0 ? "\(minutes / 60) h" : "\(minutes / 60) h \(minutes % 60) min"
    }
}

enum PlaygroundButtonKind { case primary, secondary }

extension View {
    func playgroundButton(_ kind: PlaygroundButtonKind, height: CGFloat = 52) -> some View {
        font(.system(size: 16, weight: kind == .primary ? .bold : .semibold))
            .foregroundStyle(kind == .primary ? AppTheme.onBlue : AppTheme.primary)
            .frame(maxWidth: .infinity, minHeight: height)
            .background(kind == .primary ? AppTheme.blue : AppTheme.raised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .contentShape(Rectangle())
    }
}

/// A row of equal choices on a sunken track, as on the design's share sheet.
struct SegmentedChoice<Value: Hashable>: View {
    let label: String
    let options: [(Value, String)]
    @Binding var selection: Value

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options, id: \.0) { value, title in
                Button {
                    selection = value
                } label: {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(selection == value ? AppTheme.primary : AppTheme.muted)
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .background(selection == value ? AppTheme.raised : .clear, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == value ? .isSelected : [])
            }
        }
        .padding(4)
        .background(AppTheme.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
    }
}

/// Pick a project, then share it.
struct ShareProjectSheet: View {
    let store: ProjectStore
    let onCreated: (PlaygroundRoom, Bool) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    Text("CHOOSE A PROJECT").sectionLabel()
                    if store.projects.isEmpty {
                        Text("Create a project first.").font(.system(size: 15)).foregroundStyle(AppTheme.muted)
                    }
                    ForEach(store.projects) { project in
                        NavigationLink {
                            RoomShareForm(project: project, onCreated: onCreated)
                        } label: {
                            HStack(spacing: 12) {
                                FileIconView(name: "", isDirectory: true, isOpen: true)
                                Text(project.name).font(.system(size: 15.5, weight: .semibold))
                                Spacer()
                                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(AppTheme.muted)
                            }
                            .padding(.horizontal, 12)
                            .frame(minHeight: 52)
                            .panelCard()
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("room-share-\(project.name)")
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(AppTheme.panel)
            .navigationTitle("Share a project")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .onAppear(perform: store.refresh)
            #if DEBUG
            .navigationDestination(item: $preselected) { project in RoomShareForm(project: project, onCreated: onCreated) }
            .task {
                // For screenshots: -roomProject <name>
                if let name = UserDefaults.standard.string(forKey: "roomProject") { preselected = store.projects.first { $0.name == name } }
            }
            #endif
        }
    }

    #if DEBUG
    @State private var preselected: Project?
    #endif
}

/// Lifetime, access and who may run code here, then create the room.
struct RoomShareForm: View {
    let project: Project
    let onCreated: (PlaygroundRoom, Bool) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var rooms = PlaygroundRooms.shared
    @State private var lifetime = 14_400
    @State private var editing = true
    @State private var policy = PlaygroundRunPolicy.ask
    @State private var selection: PlaygroundProjectFiles.Selection?
    @State private var failure: String?
    @State private var creating = false

    private var device: String { UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Share \(project.name)").font(.system(size: 21, weight: .bold)).lineLimit(2)
                    if let selection {
                        Text("\(selection.document.files.count) file\(selection.document.files.count == 1 ? "" : "s") · \(ByteCountFormatter.string(fromByteCount: Int64(selection.bytes), countStyle: .file)) of text")
                            .font(.system(size: 13.5)).foregroundStyle(AppTheme.muted)
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("ROOM CLOSES AFTER").sectionLabel()
                    SegmentedChoice(label: "Room lifetime", options: [(3_600, "1 h"), (14_400, "4 h"), (43_200, "12 h"), (86_400, "24 h")], selection: $lifetime)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("PEOPLE WITH THE LINK CAN").sectionLabel()
                    SegmentedChoice(label: "Access", options: [(true, "Edit"), (false, "Only view")], selection: $editing)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("HOW IT WORKS").sectionLabel()
                    Text("The link carries the key, so the relay only ever sees encrypted text. Code runs where someone presses Run: in a browser, or on this \(device) if you allow it.")
                        .font(.system(size: 14))
                        .foregroundStyle(AppTheme.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppTheme.background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(AppTheme.border, lineWidth: 1) }
                RunPolicyRow(policy: $policy, device: device)
                if let selection, !selection.leftOut.isEmpty { LeftOutList(files: selection.leftOut) }
                if let failure {
                    Text(failure).font(.system(size: 14)).foregroundStyle(AppTheme.coralInk)
                }
                if let reason = rooms.unavailableReason {
                    Text(reason).font(.system(size: 13)).foregroundStyle(AppTheme.muted)
                }
                VStack(spacing: 8) {
                    Button { create(connect: false) } label: {
                        Text(creating ? "Encrypting and creating…" : "Create room and copy link").playgroundButton(.primary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("room-create")
                    Button { create(connect: true) } label: {
                        Text("Create room and connect an AI client").font(.system(size: 15.5, weight: .semibold)).playgroundButton(.secondary, height: 48)
                    }
                    .buttonStyle(.plain)
                }
                .disabled(creating || selection == nil || !rooms.isAvailable)
                .opacity(creating || selection == nil || !rooms.isAvailable ? 0.5 : 1)
            }
            .padding(16)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(AppTheme.panel)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: load)
    }

    private func load() {
        guard selection == nil else { return }
        do {
            selection = try PlaygroundProjectFiles.collect(from: project.url, name: project.name)
        } catch {
            failure = error.localizedDescription
        }
    }

    private func create(connect: Bool) {
        guard let selection, !creating else { return }
        creating = true
        failure = nil
        Task {
            do {
                let room = try await rooms.share(project, selection: selection, lifetimeSeconds: lifetime, editing: editing, policy: policy)
                UIPasteboard.general.string = room.shareURL.absoluteString
                if let workspace = rooms.workspace, workspace.project.id == project.id { workspace.saveAll() }
                onCreated(room, connect)
            } catch {
                failure = error.localizedDescription
            }
            creating = false
        }
    }
}

struct RunPolicyRow: View {
    @Binding var policy: PlaygroundRunPolicy
    let device: String

    private var detail: String {
        switch policy {
        case .ask: "You approve each run on this \(device)"
        case .allow: "Runs start without asking while the room is open"
        case .off: "Code runs only where people press Run"
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "play.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(AppTheme.run)
                .frame(width: 40, height: 40)
                .background(AppTheme.warnPanel, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text("Others may run code here").font(.system(size: 15, weight: .semibold))
                Text(detail).font(.system(size: 13)).foregroundStyle(AppTheme.muted)
            }
            Spacer(minLength: 4)
            Menu {
                Picker("Others may run code here", selection: $policy) {
                    ForEach(PlaygroundRunPolicy.allCases) { Text($0.title).tag($0) }
                }
            } label: {
                Text(policy.short).font(.system(size: 13.5, weight: .semibold)).foregroundStyle(policy.tint)
                    .frame(minWidth: 44, minHeight: 44)
            }
            .accessibilityIdentifier("room-policy")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(AppTheme.background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(AppTheme.border, lineWidth: 1) }
    }
}

extension PlaygroundRunPolicy {
    var tint: Color {
        switch self {
        case .ask: AppTheme.amber
        case .allow: AppTheme.mint
        case .off: AppTheme.coralInk
        }
    }
}

struct LeftOutList: View {
    let files: [PlaygroundLeftOut]
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                expanded.toggle()
            } label: {
                HStack {
                    Text("LEFT OUT · \(files.count) FILE\(files.count == 1 ? "" : "S")").sectionLabel()
                    Spacer()
                    Image(systemName: expanded ? "chevron.up" : "chevron.down").font(.system(size: 12, weight: .semibold)).foregroundStyle(AppTheme.muted)
                }
                .frame(minHeight: 32)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            ForEach(expanded ? files : Array(files.prefix(3))) { file in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(file.path).font(.system(size: 13, design: .monospaced)).lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 4)
                    Text(file.reason).font(.system(size: 12.5)).foregroundStyle(AppTheme.muted).multilineTextAlignment(.trailing)
                }
            }
            if !expanded, files.count > 3 {
                Text("and \(files.count - 3) more").font(.system(size: 12.5)).foregroundStyle(AppTheme.muted)
            }
        }
    }
}

/// Paste a link, or arrive from a pythilo:// link, and join.
struct JoinRoomSheet: View {
    var initialLink: String?
    let onJoined: (PlaygroundRoom) -> Void
    /// A link that carries the files themselves opens as a new project, no room needed.
    var onSnapshot: ((ShareSnapshot) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var rooms = PlaygroundRooms.shared
    @State private var text = ""
    @State private var joining = false
    @State private var failure: String?

    private var device: String { UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone" }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Joining makes a new project on this \(device) with the room's files. Nothing runs until you press Run, or allow someone else to.")
                        .font(.system(size: 15))
                        .foregroundStyle(AppTheme.secondary)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("ROOM LINK").sectionLabel()
                        TextField("Paste the link someone sent you", text: $text, axis: .vertical)
                            .font(.system(size: 14, design: .monospaced))
                            .lineLimit(2...5)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .padding(10)
                            .background(AppTheme.background, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                            .overlay { RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(AppTheme.border, lineWidth: 1) }
                            .accessibilityIdentifier("room-link")
                        Button("Paste") {
                            if let value = UIPasteboard.general.string { text = value }
                        }
                        .font(.system(size: 14, weight: .semibold))
                        .frame(minHeight: 44)
                    }
                    if let failure {
                        Text(failure).font(.system(size: 14)).foregroundStyle(AppTheme.coralInk)
                    }
                    if let reason = rooms.unavailableReason {
                        Text(reason).font(.system(size: 13)).foregroundStyle(AppTheme.muted)
                    }
                    Button(action: join) {
                        Text(joining ? "Joining · decrypting files…" : "Join room").playgroundButton(.primary)
                    }
                    .buttonStyle(.plain)
                    .disabled(joining || text.isEmpty || !rooms.isAvailable)
                    .opacity(joining || text.isEmpty || !rooms.isAvailable ? 0.5 : 1)
                    .accessibilityIdentifier("room-join-confirm")
                }
                .padding(16)
                .frame(maxWidth: 760, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .background(AppTheme.panel)
            .navigationTitle("Join with a link")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .onAppear {
                guard let initialLink, text.isEmpty else { return }
                text = initialLink
                if rooms.isAvailable { join() }
            }
        }
    }

    private func join() {
        guard !joining else { return }
        failure = nil
        if let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)), let onSnapshot {
            do {
                if let snapshot = try ShareSnapshot.from(url: url) {
                    onSnapshot(snapshot)
                    return
                }
            } catch {
                failure = error.localizedDescription
                return
            }
        }
        let link: PlaygroundLink
        do {
            link = try PlaygroundLink.parse(text, origin: rooms.origin)
        } catch {
            failure = error.localizedDescription
            return
        }
        joining = true
        Task {
            do {
                let room = try await rooms.join(link)
                onJoined(room)
            } catch {
                failure = error.localizedDescription
            }
            joining = false
        }
    }
}

/// The local-network MCP path: an AI client on the same network reaches this device.
struct MCPConnectionView: View {
    let store: ProjectStore
    var room: PlaygroundRoom?
    @State private var host = MCPHost.shared
    @State private var copied = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if host.isRunning, room == nil || host.project?.id == room?.project?.id {
                    MCPActiveCard(host: host)
                } else if let project = room?.project {
                    Text("It sees only \(project.name), and only while you share it. It reaches this device over your local network, with no account or cloud service.")
                        .font(.system(size: 15))
                        .foregroundStyle(AppTheme.secondary)
                    Button {
                        start(project)
                    } label: {
                        Text(host.isRunning ? "Switch the connection to \(project.name)" : "Connect an AI client on this network").playgroundButton(.primary)
                    }
                    .buttonStyle(.plain)
                } else {
                    Text("Work on one project with an AI client on your computer. It reaches this device over your local network, with no account or cloud service. Editing and running code are separate permissions.")
                        .font(.system(size: 15))
                        .foregroundStyle(AppTheme.secondary)
                    Text("SHARE A PROJECT").sectionLabel()
                    if store.projects.isEmpty {
                        Text("Create a project first.").font(.system(size: 15)).foregroundStyle(AppTheme.muted)
                    }
                    VStack(spacing: 8) {
                        ForEach(store.projects) { project in
                            Button {
                                start(project)
                            } label: {
                                HStack(spacing: 12) {
                                    FileIconView(name: "", isDirectory: true, isOpen: true)
                                    Text(project.name).font(.system(size: 15.5, weight: .semibold))
                                    Spacer()
                                    Text("Connect").font(.system(size: 14, weight: .semibold)).foregroundStyle(AppTheme.blue)
                                }
                                .padding(.horizontal, 12)
                                .frame(minHeight: 52)
                                .panelCard()
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("mcp-share-\(project.name)")
                        }
                    }
                }
                if let failure = host.failure {
                    Text(failure).font(.system(size: 14)).foregroundStyle(AppTheme.coralInk)
                }
                if let room {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("AN AI CLIENT ELSEWHERE").sectionLabel()
                        Text("Give the room link to an AI client that has the Pythilo MCP bridge. It joins the room like a person, and runs code here only as this room allows.")
                            .font(.system(size: 14))
                            .foregroundStyle(AppTheme.secondary)
                        Button(copied ? "Copied" : "Copy room link") {
                            UIPasteboard.general.string = room.shareURL.absoluteString
                            copied = true
                        }
                        .font(.system(size: 14, weight: .semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(AppTheme.raised, in: RoundedRectangle(cornerRadius: 10))
                        .buttonStyle(.plain)
                    }
                    .padding(12)
                    .panelCard()
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .background(AppTheme.background)
        .navigationTitle(room == nil ? "AI client over MCP" : "Connect an AI client")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            store.refresh()
            if let project = room?.project, !host.isRunning { start(project) }
        }
    }

    private func start(_ project: Project) {
        host.start(project: project)
        if let workspace = PlaygroundRooms.shared.workspace, workspace.project.id == project.id { host.workspace = workspace }
    }
}

/// Connection details, permissions, approvals and what the client did.
struct MCPActiveCard: View {
    @Bindable var host: MCPHost
    @State private var client = "claude"
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Circle().fill(host.clientName == nil ? AppTheme.amber : AppTheme.mint).frame(width: 10, height: 10)
                VStack(alignment: .leading, spacing: 1) {
                    Text(host.clientName ?? "Waiting for a client").font(.system(size: 20, weight: .bold))
                    Text("Sharing \(host.project?.name ?? "") · keep Pythilo open").font(.system(size: 13.5)).foregroundStyle(AppTheme.muted)
                }
                Spacer()
                Button("Stop sharing") { host.stop() }
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(AppTheme.coralInk)
                    .padding(.horizontal, 12)
                    .frame(height: 44)
                    .background(AppTheme.coralFill, in: Capsule())
                    .overlay { Capsule().stroke(AppTheme.coral, lineWidth: 1) }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("mcp-stop")
            }

            ForEach(host.pending) { request in
                VStack(alignment: .leading, spacing: 8) {
                    Text("WANTS TO: \(request.permission.title.uppercased())").font(.system(size: 12, weight: .bold)).foregroundStyle(AppTheme.amber)
                    Text(request.summary).font(.system(size: 15, weight: .semibold))
                    if !request.detail.isEmpty {
                        Text(request.detail)
                            .font(.system(size: 13, design: .monospaced))
                            .padding(9)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(AppTheme.background, in: RoundedRectangle(cornerRadius: 9))
                    }
                    if request.permission == .run || request.permission == .packages {
                        Text("Code here can read files and the network like any code in this app.")
                            .font(.system(size: 13.5))
                            .foregroundStyle(AppTheme.secondary)
                    }
                    HStack(spacing: 8) {
                        Button("Deny") { host.answer(request, allow: false) }
                            .font(.system(size: 15, weight: .semibold))
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(AppTheme.raised, in: RoundedRectangle(cornerRadius: 11))
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("mcp-deny")
                        Button("Allow once") { host.answer(request, allow: true) }
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(AppTheme.onRun)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(AppTheme.run, in: RoundedRectangle(cornerRadius: 11))
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("mcp-allow")
                    }
                }
                .padding(12)
                .background(AppTheme.warnPanel, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            if host.clientName == nil {
                VStack(alignment: .leading, spacing: 8) {
                    Picker("Client", selection: $client) {
                        Text("Claude Code").tag("claude")
                        Text("Codex").tag("codex")
                    }
                    .pickerStyle(.segmented)
                    Text("ON YOUR COMPUTER, ON THE SAME NETWORK").sectionLabel()
                    Text(host.command(for: client))
                        .font(.system(size: 12.5, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(AppTheme.background, in: RoundedRectangle(cornerRadius: 9))
                        .accessibilityIdentifier("mcp-command")
                    if client == "codex" {
                        Text("Set PYTHILO_TOKEN to \(host.token)")
                            .font(.system(size: 12.5, design: .monospaced))
                            .textSelection(.enabled)
                    }
                    Button(copied ? "Copied" : "Copy command") {
                        UIPasteboard.general.string = host.command(for: client)
                        copied = true
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(AppTheme.raised, in: RoundedRectangle(cornerRadius: 10))
                    .buttonStyle(.plain)
                    Text("Any other MCP client: Streamable HTTP at \(host.address ?? ""), with the same bearer token. The token ends when you stop sharing.")
                        .font(.system(size: 13))
                        .foregroundStyle(AppTheme.muted)
                }
                .padding(12)
                .panelCard()
            }

            VStack(spacing: 0) {
                Text("WHAT IT MAY DO").sectionLabel().frame(maxWidth: .infinity, alignment: .leading).padding(12)
                ForEach(MCPPermission.allCases) { permission in
                    Rectangle().fill(AppTheme.border).frame(height: 1)
                    HStack {
                        Text(permission.title).font(.system(size: 15))
                        Spacer()
                        Picker(permission.title, selection: Binding(
                            get: { host.grants[permission] ?? .deny },
                            set: { host.grants[permission] = $0 }
                        )) {
                            ForEach(MCPGrant.allCases) { Text($0.title).tag($0) }
                        }
                        .labelsHidden()
                    }
                    .padding(.horizontal, 12)
                    .frame(minHeight: 44)
                }
            }
            .panelCard()

            if !host.activity.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("RECENT").sectionLabel()
                    ForEach(host.activity.prefix(8)) { item in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(item.date, style: .time).foregroundStyle(AppTheme.muted)
                            Text(item.text)
                        }
                        .font(.system(size: 13.5))
                    }
                }
            }
        }
    }
}

/// Rooms and the AI connection from inside a project.
struct RoomSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var model: WorkspaceModel
    @State private var host = MCPHost.shared
    @State private var rooms = PlaygroundRooms.shared
    @State private var sharing = false

    var body: some View {
        NavigationStack {
            Group {
                if let room = rooms.room(for: model.project) {
                    RoomView(room: room, onOpen: nil)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Share \(model.project.name) as a live room with people in a browser or another device, or let an AI client on your computer work on it over your local network.")
                                .font(.system(size: 15))
                                .foregroundStyle(AppTheme.secondary)
                            Button {
                                model.saveAll()
                                sharing = true
                            } label: {
                                Label("Share as a room", systemImage: "plus").playgroundButton(.primary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("workspace-room-share")
                            if let reason = rooms.unavailableReason {
                                Text(reason).font(.system(size: 13)).foregroundStyle(AppTheme.muted)
                            }
                            Text("AI CLIENT ON THIS NETWORK").sectionLabel().padding(.top, 6)
                            if host.isRunning, host.project?.id == model.project.id {
                                MCPActiveCard(host: host)
                            } else {
                                Button {
                                    host.start(project: model.project)
                                    host.workspace = model
                                } label: {
                                    Text("Connect an AI client").playgroundButton(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(16)
                        .frame(maxWidth: 760, alignment: .leading)
                        .frame(maxWidth: .infinity)
                    }
                    .background(AppTheme.background)
                    .navigationTitle("Share")
                    .navigationBarTitleDisplayMode(.inline)
                }
            }
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .navigationDestination(isPresented: $sharing) {
                RoomShareForm(project: model.project) { _, _ in sharing = false }
            }
            .onAppear {
                if host.project?.id == model.project.id { host.workspace = model }
                rooms.workspace = model
            }
        }
    }
}
