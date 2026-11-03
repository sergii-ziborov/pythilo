import Foundation
import Observation

/// One encrypted room connection: create or join, post updates and presence, and
/// read the relay's event stream in order, reconnecting until the room expires.
/// Joining never runs code by itself.
@MainActor
@Observable
final class PlaygroundLiveSession {
    private(set) var status = "Connecting…"
    private(set) var document: PlaygroundDocument?
    private(set) var selections: [PlaygroundRemoteSelection] = []
    private(set) var localSelection: PlaygroundRemoteSelection?
    private(set) var participants = 1
    private(set) var connected = false
    private(set) var expired = false
    private(set) var runtimeFrames: [PlaygroundCodec.RuntimePresenceFrame] = []

    var isEditable: Bool { !link.isReadOnly && !expired }
    /// Formats this app reads, declared to the relay on every request.
    static let codecs = "1"
    static let codecHeader = "X-Pythilo-Codecs"

    let link: PlaygroundLink
    let origin: URL
    private(set) var owner: String?
    private(set) var viewAccess: String?

    @ObservationIgnored var onDocument: ((PlaygroundDocument) -> Void)?
    @ObservationIgnored var onRuntimeFrames: (([PlaygroundCodec.RuntimePresenceFrame]) -> Void)?
    @ObservationIgnored var onRuntimeReset: (() -> Void)?
    @ObservationIgnored var onRuntimeSourceChanged: (() -> Void)?

    var runtimeConnected: Bool { connected && !stopped && !expired }
    var runtimeEpoch: UInt64 { runtimeConnection }
    var runtimeEditConfirmed: Bool {
        connected && !stopped && !expired && !link.isReadOnly && link.expiresAt > Date() && confirmedRuntimeConnection == runtimeConnection
    }

    @ObservationIgnored private let codec: PlaygroundCodec
    @ObservationIgnored private let network: URLSession
    @ObservationIgnored private let peer = PlaygroundEncryption.newSecret()
    @ObservationIgnored private var sequence = 0
    @ObservationIgnored private var stopped = false
    @ObservationIgnored private var streamTask: Task<Void, Never>?
    @ObservationIgnored private var flushTask: Task<Void, Never>?
    @ObservationIgnored private var presenceTask: Task<Void, Never>?
    @ObservationIgnored private var heartbeatTask: Task<Void, Never>?
    @ObservationIgnored private var snapshotTask: Task<Void, Never>?
    @ObservationIgnored private var pending: [(id: String, bytes: Data)] = []
    /// The relay refused an update until the room is compacted, so a snapshot may not
    /// wait for pending edits: those are what cannot be delivered.
    @ObservationIgnored private var snapshotOverdue = false
    @ObservationIgnored private var presence: Data?
    @ObservationIgnored private var runtimeConnection: UInt64 = 0
    @ObservationIgnored private var confirmedRuntimeConnection: UInt64?

    init(link: PlaygroundLink, origin: URL, codecURL: URL? = nil) throws {
        self.link = link
        self.origin = origin
        codec = try PlaygroundCodec(resourceURL: codecURL)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 86_400
        network = URLSession(configuration: configuration)
    }

    static func create(document: PlaygroundDocument, lifetimeSeconds: Int, origin: URL, codecURL: URL? = nil) async throws -> PlaygroundLiveSession {
        _ = try document.validated()
        guard (60...86_400).contains(lifetimeSeconds) else { throw PlaygroundFailure("Choose a lifetime up to 24 hours.") }
        let codec = try PlaygroundCodec(resourceURL: codecURL)
        _ = try codec.initialize(document)
        let snapshot = try PlaygroundCodec.bytes(codec.call(["type": "snapshot"]).snapshot)
        let key = PlaygroundEncryption.newSecret()
        let packet = try PlaygroundEncryption.seal(snapshot, secret: key)
        var request = URLRequest(url: origin.appending(path: "api/playground/rooms/"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(codecs, forHTTPHeaderField: codecHeader)
        request.httpBody = try JSONSerialization.data(withJSONObject: ["snapshot": ["iv": packet.iv, "data": packet.data], "lifetimeSeconds": lifetimeSeconds])
        let creating = URLSession(configuration: .ephemeral)
        defer { creating.finishTasksAndInvalidate() }
        let (data, response) = try await creating.data(for: request)
        try check(response, data: data)
        struct Created: Decodable { let id: String; let edit: String; let owner: String; let view: String; let expiresAt: Double }
        let value = try JSONDecoder().decode(Created.self, from: data)
        let link = PlaygroundLink(id: value.id, key: key, access: value.edit, expiresAt: Date(timeIntervalSince1970: value.expiresAt / 1000), isReadOnly: false)
        // Refuse anything the relay returns that a link could not carry.
        _ = try PlaygroundLink.parse(link.appURL.absoluteString, origin: origin)
        let session = try PlaygroundLiveSession(link: link, origin: origin, codecURL: codecURL)
        // Keep the exact CRDT IDs of the encrypted initial snapshot.
        try session.absorb(session.codec.call(["type": "state", "snapshot": snapshot.base64EncodedString(), "events": [String](), "codec": 1]))
        session.owner = value.owner
        session.viewAccess = value.view
        return session
    }

    func start() {
        guard streamTask == nil, !stopped else { return }
        heartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                guard let self, !stopped, !Task.isCancelled else { return }
                do {
                    try absorb(codec.call(["type": "tick"]))
                    schedulePresence()
                } catch {
                    status = error.localizedDescription
                }
                if Date() >= link.expiresAt {
                    expire()
                    return
                }
            }
        }
        streamTask = Task { [weak self] in
            guard let self else { return }
            while !stopped, !Task.isCancelled, Date() < link.expiresAt {
                do { try await stream() } catch {
                    if !stopped && !Task.isCancelled { status = "Reconnecting · your changes are kept. " + error.localizedDescription }
                }
                resetRuntime()
                connected = false
                if !stopped && !Task.isCancelled { try? await Task.sleep(for: .seconds(2)) }
            }
            if !stopped && !Task.isCancelled { expire() }
        }
    }

    func edit(file: String, text: String) {
        guard isEditable, !stopped, document?.files[file] != text else { return }
        do {
            try absorb(codec.call(["type": "file", "path": file, "text": text]))
            scheduleFlush()
        } catch {
            status = error.localizedDescription
        }
    }

    func replace(_ source: PlaygroundDocument) throws {
        guard isEditable, !stopped else { throw PlaygroundFailure("This room is view only or has ended.") }
        guard source != document else { return }
        try absorb(codec.replace(source))
        scheduleFlush()
    }

    func select(file: String, range: NSRange) {
        guard !expired, !stopped, document?.files[file] != nil else { return }
        do {
            try absorb(codec.call(["type": "selection", "file": file, "anchor": range.location, "head": NSMaxRange(range)]))
            schedulePresence()
        } catch {
            status = error.localizedDescription
        }
    }

    /// The name others see beside this device's cursor.
    func setDisplayName(_ name: String) {
        let clean = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))
        guard !clean.isEmpty, !stopped else { return }
        do {
            try absorb(codec.call(["type": "identity", "name": clean]))
            schedulePresence()
        } catch {
            // An older codec keeps its generated guest name.
        }
    }

    func localCopy() throws -> PlaygroundDocument {
        guard let value = document else { throw PlaygroundFailure("Wait for the encrypted files to arrive.") }
        return try value.validated()
    }

    func runtimeSourceIdentity() throws -> PlaygroundCodec.RuntimeSourceIdentity { try codec.runtimeSourceIdentity() }

    func runtimeHostCall(_ request: [String: Any]) async throws -> PlaygroundRuntimeHostReply { try await codec.runtimeHostCall(request) }

    func publishRuntimePresence(_ envelope: Data?) throws {
        guard !stopped, !expired else { throw PlaygroundFailure("This room is disconnected.") }
        if let envelope, envelope.count > PlaygroundRuntimeProtocol.envelopeBytes { throw PlaygroundFailure("Oversized runtime presence.") }
        let value: Any = try envelope.map { try JSONSerialization.jsonObject(with: $0) } ?? NSNull()
        try absorb(codec.call(["type": "runtime-presence", "envelope": value]))
        schedulePresence()
    }

    /// Proves to the relay that this connection holds the edit capability.
    func confirmRuntimeEditAccess() async throws {
        guard connected, !stopped, !expired, !link.isReadOnly, link.expiresAt > Date() else {
            throw PlaygroundFailure("Running code needs a connected room you can edit.")
        }
        if runtimeEditConfirmed { return }
        let generation = runtimeConnection
        let packet = try PlaygroundEncryption.seal(Data([0, 0]), secret: link.key)
        let (data, _) = try await post(["type": "update", "peer": peer, "messageID": PlaygroundEncryption.newSecret(), "packet": ["iv": packet.iv, "data": packet.data]])
        struct Confirmation: Decodable { let sequence: Int }
        let response = try JSONDecoder().decode(Confirmation.self, from: data)
        guard response.sequence > 0, generation == runtimeConnection, connected, !stopped, !expired, link.expiresAt > Date() else {
            throw PlaygroundFailure("The room connection changed while confirming edit access.")
        }
        confirmedRuntimeConnection = generation
    }

    func stop() {
        guard !stopped else { return }
        stopped = true
        connected = false
        resetRuntime()
        runtimeFrames = []
        onRuntimeFrames?([])
        streamTask?.cancel(); flushTask?.cancel(); presenceTask?.cancel(); heartbeatTask?.cancel(); snapshotTask?.cancel()
        network.invalidateAndCancel()
        selections = []
        status = expired ? "Room ended · your copy stays on this device" : "Disconnected · your copy stays on this device"
    }

    func closeRoom() async throws {
        guard let owner else { throw PlaygroundFailure("Only the device that created this room can end it early.") }
        var request = request()
        request.httpMethod = "DELETE"
        request.setValue("Bearer " + owner, forHTTPHeaderField: "Authorization")
        // Stopping the stream invalidates `network`; DELETE keeps its own session.
        let closing = URLSession(configuration: .ephemeral)
        defer { closing.finishTasksAndInvalidate() }
        let (data, response) = try await closing.data(for: request)
        try Self.check(response, data: data)
        expire()
    }

    // MARK: Transport

    private func resetRuntime() {
        runtimeConnection &+= 1
        confirmedRuntimeConnection = nil
        onRuntimeReset?()
    }

    private func expire() {
        expired = true
        stop()
    }

    private func request(_ suffix: String = "") -> URLRequest {
        var request = URLRequest(url: URL(string: "/api/playground/rooms/\(link.id)/" + suffix, relativeTo: origin)!.absoluteURL)
        request.setValue("Bearer " + link.access, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(Self.codecs, forHTTPHeaderField: Self.codecHeader)
        return request
    }

    private static func check(_ response: URLResponse, data: Data) throws {
        guard let response = response as? HTTPURLResponse else { throw PlaygroundFailure("The relay did not answer.") }
        guard (200...299).contains(response.statusCode) else {
            struct Failure: Decodable { let error: String }
            let message = (try? JSONDecoder().decode(Failure.self, from: data))?.error ?? "The relay refused the request (\(response.statusCode))."
            throw PlaygroundFailure(message, status: response.statusCode)
        }
    }

    private func post(_ body: [String: Any]) async throws -> (Data, Int) {
        var request = request()
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await network.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        if code == 410 { expire() }
        try Self.check(response, data: data)
        return (data, code)
    }

    private func absorb(_ value: PlaygroundCodec.Result) throws {
        if let next = value.document, document != next {
            document = next
            onRuntimeSourceChanged?()
            onDocument?(next)
        }
        if let next = value.selections, selections != next { selections = next }
        if let selection = value.localSelection, selection != localSelection { localSelection = selection }
        if let count = value.participants, count != participants { participants = count }
        if let update = try? PlaygroundCodec.bytes(value.update), update.count > 2 { pending.append((PlaygroundEncryption.newSecret(), update)) }
        if let bytes = value.presence { presence = Data(bytes) }
        if let frames = value.runtimeFrames, frames != runtimeFrames {
            runtimeFrames = frames
            onRuntimeFrames?(frames)
        }
    }

    private var connectedStatus: String {
        link.isReadOnly ? "Connected · view only · encrypted" : "Connected · editing together · encrypted"
    }

    private func stream() async throws {
        let (bytes, response) = try await network.bytes(for: request("events/?peer=" + peer + "&codecs=" + Self.codecs))
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        if code == 410 {
            expire()
            return
        }
        guard code == 200 else {
            // The relay explains a refusal, such as a room in a newer format (426).
            var body = Data()
            for try await byte in bytes {
                body.append(byte)
                if body.count > 4096 { break }
            }
            struct Failure: Decodable { let error: String }
            throw PlaygroundFailure((try? JSONDecoder().decode(Failure.self, from: body))?.error ?? "The room connection is unavailable.", status: code)
        }
        var event = ""
        for try await line in bytes.lines {
            if stopped || Task.isCancelled { return }
            guard line.utf8.count <= 2_000_000 else { throw PlaygroundFailure("Oversized room message.") }
            // AsyncBytes.lines skips empty lines. Each relay event has exactly one
            // data line, so it is handled as soon as it arrives.
            if line.hasPrefix("event: ") {
                event = String(line.dropFirst(7))
            } else if line.hasPrefix("data: ") {
                try receive(event: event, data: Data(line.dropFirst(6).utf8))
            }
        }
    }

    private struct State: Decodable { let codec: Int?; let expiresAt: Double; let sequence: Int; let snapshot: PlaygroundEncryptedPacket; let events: [Update]; let presence: [Presence]? }
    private struct Update: Decodable { let sequence: Int; let packet: PlaygroundEncryptedPacket }
    private struct Presence: Decodable { let packet: PlaygroundEncryptedPacket }

    private func receive(event: String, data: Data) throws {
        switch event {
        case "expired", "closed":
            expire()
        case "ping":
            return
        case "state":
            resetRuntime()
            let state = try JSONDecoder().decode(State.self, from: data)
            guard abs(state.expiresAt - link.expiresAt.timeIntervalSince1970 * 1000) < 1 else { throw PlaygroundFailure("The room's lifetime does not match the link.") }
            guard (state.codec ?? 1) == 1 else { throw PlaygroundFailure("This room uses a newer format. Update Pythilo to open it.") }
            let snapshot = try PlaygroundEncryption.open(state.snapshot, secret: link.key, maximum: 262_144)
            let events = try state.events.map { try PlaygroundEncryption.open($0.packet, secret: link.key, maximum: 196_608).base64EncodedString() }
            try absorb(codec.call(["type": "state", "snapshot": snapshot.base64EncodedString(), "events": events, "codec": 1]))
            for item in state.presence ?? [] { receivePresence(item.packet) }
            sequence = state.sequence
            connected = true
            status = connectedStatus
            scheduleFlush()
            schedulePresence()
        case "update":
            let value = try JSONDecoder().decode(Update.self, from: data)
            if value.sequence <= sequence { return }
            guard value.sequence == sequence + 1 else { throw PlaygroundFailure("Resynchronizing room changes.") }
            let bytes = try PlaygroundEncryption.open(value.packet, secret: link.key, maximum: 196_608)
            try absorb(codec.call(["type": "update", "bytes": bytes.base64EncodedString()]))
            sequence = value.sequence
            scheduleSnapshot()
        case "presence":
            receivePresence(try JSONDecoder().decode(Presence.self, from: data).packet)
        default:
            return
        }
    }

    private func receivePresence(_ packet: PlaygroundEncryptedPacket) {
        do {
            let bytes = try PlaygroundEncryption.open(packet, secret: link.key, maximum: 4000)
            try absorb(codec.call(["type": "presence", "bytes": Array(bytes)]))
        } catch {
            // Malformed transient presence is dropped; the shared files stay connected.
        }
    }

    private func scheduleFlush() {
        guard flushTask == nil, connected, !stopped, !link.isReadOnly else { return }
        flushTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(200))
            guard let self else { return }
            while connected, !stopped, !Task.isCancelled, !pending.isEmpty {
                do {
                    if pending.count > 1 {
                        let bytes = try PlaygroundCodec.bytes(codec.call(["type": "merge", "updates": pending.map { $0.bytes.base64EncodedString() }]).merged)
                        pending = [(PlaygroundEncryption.newSecret(), bytes)]
                    }
                    guard let item = pending.first else { break }
                    guard item.bytes.count <= 196_592 else { throw PlaygroundFailure("This change is larger than a room accepts.") }
                    let packet = try PlaygroundEncryption.seal(item.bytes, secret: link.key)
                    _ = try await post(["type": "update", "peer": peer, "messageID": item.id, "packet": ["iv": packet.iv, "data": packet.data]])
                    pending.removeFirst()
                    scheduleSnapshot()
                } catch {
                    if stopped || Task.isCancelled { break }
                    if (error as? PlaygroundFailure)?.status == 409 {
                        snapshotOverdue = true
                        scheduleSnapshot()
                    }
                    status = "Changes waiting to send. " + error.localizedDescription
                    try? await Task.sleep(for: .seconds(2))
                }
            }
            flushTask = nil
        }
    }

    private func schedulePresence() {
        guard connected, !stopped, presenceTask == nil, presence != nil else { return }
        presenceTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            guard let self, !stopped, !Task.isCancelled, let bytes = presence else {
                self?.presenceTask = nil
                return
            }
            presence = nil
            do {
                let packet = try PlaygroundEncryption.seal(bytes, secret: link.key)
                _ = try await post(["type": "presence", "peer": peer, "packet": ["iv": packet.iv, "data": packet.data]])
            } catch {
                // Presence is transient; file updates retry on their own.
            }
            presenceTask = nil
            if presence != nil { schedulePresence() }
        }
    }

    private func scheduleSnapshot() {
        guard snapshotTask == nil, !stopped, !link.isReadOnly else { return }
        snapshotTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard let self, !stopped, !Task.isCancelled else { return }
            snapshotTask = nil
            guard connected, pending.isEmpty || snapshotOverdue else { return }
            do {
                let currentSequence = sequence
                let bytes = try PlaygroundCodec.bytes(codec.call(["type": "snapshot"]).snapshot)
                let packet = try PlaygroundEncryption.seal(bytes, secret: link.key)
                _ = try await post(["type": "snapshot", "sequence": currentSequence, "packet": ["iv": packet.iv, "data": packet.data]])
                snapshotOverdue = false
            } catch {
                if !stopped { scheduleSnapshot() }
            }
        }
    }
}
