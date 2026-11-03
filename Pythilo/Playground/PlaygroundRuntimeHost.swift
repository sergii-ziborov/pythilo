import Foundation
import Observation
import UIKit

enum PlaygroundRunPolicy: String, CaseIterable, Identifiable, Sendable {
    case ask, allow, off

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ask: "Ask each time"
        case .allow: "Allowed in this room"
        case .off: "Not allowed"
        }
    }

    var short: String {
        switch self {
        case .ask: "Ask"
        case .allow: "Allowed"
        case .off: "Off"
        }
    }
}

/// A run or test someone in the room wants on this device, waiting for its owner.
struct PlaygroundRunApproval: Identifiable, Equatable {
    let id: String
    let requester: String
    /// "from a browser"
    let origin: String
    let operation: String
    let command: String
    let revision: String
}

struct PlaygroundJobRecord: Identifiable, Equatable {
    let id: String
    let requester: String
    let command: String
    let revision: String
    let status: String
    let exitCode: Int?
    let duration: TimeInterval
    let started: Date
}

/// This device as a Python host for one room. The bundled policy authenticates every
/// signed request and holds grants; this class asks the owner, runs jobs on the
/// embedded interpreter and reports where and how they ran.
@MainActor
@Observable
final class PlaygroundRuntimeHost {
    private(set) var grant: PlaygroundRuntimePolicyReply.Grant?
    private(set) var approvals: [PlaygroundRunApproval] = []
    private(set) var history: [PlaygroundJobRecord] = []
    private(set) var running: PlaygroundRunApproval?
    private(set) var notice: String?
    var policy: PlaygroundRunPolicy {
        didSet {
            guard policy != oldValue else { return }
            if policy == .off {
                for approval in approvals { deny(approval) }
                revoke()
            } else if policy == .allow {
                for approval in approvals { approve(approval) }
            }
            schedule()
        }
    }

    let fingerprint: String
    let displayName: String
    /// Read each time: Python reports its exact version after the app starts.
    var runtime: String { Self.runtimeFingerprint }
    static let kind = "ios"

    @ObservationIgnored private let signer: PlaygroundRuntimeSigner
    @ObservationIgnored private let session: PlaygroundLiveSession
    @ObservationIgnored private var foreground = true
    @ObservationIgnored private var stopped = false
    @ObservationIgnored private var initialized = false
    @ObservationIgnored private var epoch: UInt64 = 0
    @ObservationIgnored private var queue: Task<Void, Never>?
    @ObservationIgnored private var timer: Task<Void, Never>?
    @ObservationIgnored private var frames: [PlaygroundCodec.RuntimePresenceFrame] = []
    @ObservationIgnored private var seen: [UInt32: UInt64] = [:]
    @ObservationIgnored private var requests: [PlaygroundRuntimePolicyReply.Request] = []
    @ObservationIgnored private var jobs: [PlaygroundRuntimeHostReply.Job] = []
    @ObservationIgnored private var waiting: [String: PlaygroundRuntimeHostReply.Effect] = [:]
    @ObservationIgnored private var active: (id: String, cancelled: Bool)?
    @ObservationIgnored private var localGeneration = 0
    @ObservationIgnored private var progressSent = Date.distantPast

    init(session: PlaygroundLiveSession, policy: PlaygroundRunPolicy) {
        self.session = session
        self.policy = policy
        let signer = PlaygroundRuntimeSigner()
        self.signer = signer
        fingerprint = signer.fingerprint
        displayName = Self.deviceName
        session.onRuntimeFrames = { [weak self] frames in
            self?.frames = frames
            self?.schedule()
        }
        session.onRuntimeReset = { [weak self] in self?.reset() }
        session.onRuntimeSourceChanged = { [weak self] in self?.schedule() }
        timer = Task { [weak self] in
            while !Task.isCancelled {
                self?.schedule()
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
            }
        }
    }

    /// The owner's first name, from the name chosen for rooms or for Git.
    static var ownerName: String? {
        let defaults = UserDefaults.standard
        let chosen = (defaults.string(forKey: "pythilo.roomName") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let git = (defaults.string(forKey: "pythilo.gitName") ?? "").split(separator: " ").first.map(String.init) ?? ""
        let owner = String((chosen.isEmpty ? git : chosen).prefix(30))
        return owner.isEmpty ? nil : owner
    }

    /// "Serhii's iPhone"
    static var deviceName: String {
        let device = UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone"
        if let owner = ownerName { return "\(owner)'s \(device)" }
        let name = UIDevice.current.name
        return name.isEmpty || name == UIDevice.current.model ? "Pythilo on \(device)" : String(name.prefix(60))
    }

    /// `CPython 3.14.0 · iOS 26`
    static var runtimeFingerprint: String {
        let python = RunSession.shared.pythonVersion ?? "3.14"
        let system = UIDevice.current.systemVersion.split(separator: ".").first.map(String.init) ?? UIDevice.current.systemVersion
        return "CPython \(python) · iOS \(system)"
    }

    var waitingForOwner: Bool { !approvals.isEmpty }

    func setForeground(_ value: Bool) {
        foreground = value
        if !value { revoke() }
        schedule()
    }

    func stop() {
        guard !stopped else { return }
        stopped = true
        localGeneration += 1
        active?.cancelled = true
        for approval in approvals { waiting[approval.id] = nil }
        approvals = []
        timer?.cancel()
        queue?.cancel()
        signer.destroy()
        try? session.publishRuntimePresence(nil)
    }

    /// Ends the current grant. A controller has to ask again.
    func revoke() {
        active?.cancelled = true
        localGeneration += 1
        grant = nil
        requests = []
        Task { try? await call("revoke") }
    }

    func approve(_ approval: PlaygroundRunApproval) {
        approvals.removeAll { $0.id == approval.id }
        guard let effect = waiting.removeValue(forKey: approval.id) else { return }
        begin(effect, requester: approval.requester)
    }

    func deny(_ approval: PlaygroundRunApproval) {
        approvals.removeAll { $0.id == approval.id }
        guard let effect = waiting.removeValue(forKey: approval.id) else { return }
        complete(effect, requester: approval.requester, result: .init(status: "denied", exitCode: nil, stderr: "The owner of \(displayName) did not allow this run. Nothing ran.\n", started: Date(), duration: 0))
    }

    // MARK: Policy

    private func reset() {
        initialized = false
        epoch = session.runtimeEpoch
        seen = [:]
        localGeneration += 1
        active?.cancelled = true
        for approval in approvals { waiting[approval.id] = nil }
        approvals = []
        grant = nil
        requests = []
    }

    private func context() throws -> [String: Any] {
        let identity = try session.runtimeSourceIdentity(), document = try session.localCopy()
        let python = RunSession.shared
        return [
            "room": session.link.id, "target": fingerprint, "scope": "ios-room:" + String(session.runtimeEpoch), "revision": identity.revision,
            "editCapability": session.link.access, "expires": Int64(session.link.expiresAt.timeIntervalSince1970 * 1000),
            "foreground": foreground && policy != .off && UIApplication.shared.applicationState == .active,
            "connected": session.runtimeConnected, "editConfirmed": session.runtimeEditConfirmed,
            "ready": python.pythonVersion != nil, "busy": python.isBusy || active != nil,
            "name": displayName, "kind": Self.kind, "runtime": runtime, "profile": PlaygroundRuntimeProtocol.profile,
            "operations": PlaygroundRuntimeProtocol.startOperations, "debug": false, "profileReady": true,
            "paths": identity.paths, "lines": identity.paths.map { (document.files[$0] ?? "").components(separatedBy: "\n").count },
        ]
    }

    private func call(_ action: String, extra: [String: Any] = [:]) async throws {
        guard !stopped, session.document != nil else { return }
        var request = extra
        request["action"] = action
        request["context"] = try context()
        let generation = localGeneration
        let reply = try await session.runtimeHostCall(request)
        guard !stopped, generation == localGeneration else { return }
        if let error = reply.error { throw PlaygroundFailure(error) }
        if grant != reply.grant { grant = reply.grant }
        requests = reply.requests ?? []
        jobs = reply.jobs ?? []
        for effect in reply.effects ?? [] where effect.type != "start" { apply(effect) }
        do {
            for publication in reply.publications ?? [] {
                let f = publication.fields
                let envelope = try signer.sign(
                    .init(kind: f.kind, room: f.room, target: f.target, requestID: f.requestID, operation: f.operation, revision: f.revision ?? "", job: f.job ?? ""),
                    payload: Data(publication.payloadJSON.utf8), editCapability: publication.proof ? session.link.access : nil)
                try session.publishRuntimePresence(envelope)
            }
        } catch {
            for effect in reply.effects ?? [] where effect.type == "start" {
                complete(effect, requester: grant?.name ?? "Someone", result: .init(status: "error", exitCode: nil, stderr: "The start acknowledgement could not be sent. Nothing ran.\n", started: Date(), duration: 0))
            }
            throw error
        }
        for effect in reply.effects ?? [] where effect.type == "start" { apply(effect) }
    }

    private func schedule() {
        guard queue == nil, !stopped, session.document != nil else { return }
        queue = Task { [weak self] in
            guard let self else { return }
            defer { queue = nil }
            do {
                if session.runtimeConnected, foreground, policy != .off, !session.link.isReadOnly, !session.runtimeEditConfirmed,
                   frames.contains(where: { $0.envelope.contains("permission-request") }) {
                    try await session.confirmRuntimeEditAccess()
                }
                if !initialized || epoch != session.runtimeEpoch {
                    epoch = session.runtimeEpoch
                    try await call("initialize")
                    initialized = true
                } else {
                    try await call("tick")
                }
                let incoming = frames
                let live = Set(incoming.map(\.clientID))
                seen = seen.filter { live.contains($0.key) }
                for frame in incoming where seen[frame.clientID] != frame.clock {
                    seen[frame.clientID] = frame.clock
                    do { try await call("frame", extra: ["envelope": frame.envelope]) } catch {
                        // Invalid peer traffic has no authority here and nothing to show.
                    }
                }
                try await grantRequest()
            } catch {
                // The room reports reconnection and view-only state itself.
            }
        }
    }

    /// The owner chose this room's policy when sharing, so a verified controller gets
    /// the channel; in Ask mode every run and test still waits for the owner here.
    /// A grant held by a controller with unfinished work is not taken away.
    private func grantRequest() async throws {
        guard policy != .off, foreground, session.runtimeEditConfirmed, let request = requests.first else { return }
        if let grant, grant.controller != request.controller, jobs.contains(where: { $0.state != "finished" }) { return }
        let operations = PlaygroundRuntimeProtocol.startOperations.filter { request.operations.contains($0) }
        guard !operations.isEmpty else { return }
        try await call("allow", extra: ["controller": request.controller, "requestID": request.requestID, "operations": operations])
        notice = "\(PlaygroundController(request.name).name) can ask to run code here for up to 10 minutes."
    }

    // MARK: Jobs

    private func apply(_ effect: PlaygroundRuntimeHostReply.Effect) {
        guard effect.type == "start" else {
            guard effect.type == "stop" else { return }
            if active?.id == effect.job {
                active?.cancelled = true
            } else if let approval = approvals.first(where: { $0.id == effect.job }) {
                approvals.removeAll { $0.id == effect.job }
                waiting[effect.job] = nil
                complete(effect, requester: approval.requester, result: .init(status: "cancelled", exitCode: nil, stderr: "Stopped before it ran.\n", started: Date(), duration: 0))
            } else {
                Task { await update(effect.job, ["state": "finished", "succeeded": false, "stage": "Stopped before it started"]) }
            }
            return
        }
        let controller = jobs.first { $0.id == effect.job }?.controller
        let requester = grant.flatMap { controller == nil || $0.controller == controller ? PlaygroundController($0.name).name : nil } ?? "Someone in the room"
        let origin = grant.map { PlaygroundController($0.name).from } ?? ""
        guard active == nil, !RunSession.shared.isBusy, RunSession.shared.pythonVersion != nil, foreground, policy != .off,
              UIApplication.shared.applicationState == .active, session.runtimeEditConfirmed,
              let identity = try? session.runtimeSourceIdentity(), identity.revision == effect.revision,
              let document = try? session.localCopy(), PlaygroundPythonJob.Operation(rawValue: effect.operation) != nil else {
            complete(effect, requester: requester, result: .init(status: "error", exitCode: nil, stderr: "The room or this device changed before the job started. Nothing ran.\n", started: Date(), duration: 0))
            return
        }
        guard effect.operation == "check" || policy == .allow else {
            let approval = PlaygroundRunApproval(id: effect.job, requester: requester, origin: origin, operation: effect.operation,
                                                 command: PlaygroundPythonJob.command(effect.operation, entryFile: document.entryFile), revision: effect.revision)
            waiting[effect.job] = effect
            approvals.append(approval)
            Task { await update(effect.job, ["state": "progress", "stage": "Waiting for approval on \(displayName)"]) }
            return
        }
        begin(effect, requester: requester)
    }

    private func begin(_ effect: PlaygroundRuntimeHostReply.Effect, requester: String) {
        guard !stopped, active == nil, !RunSession.shared.isBusy,
              let identity = try? session.runtimeSourceIdentity(), identity.revision == effect.revision,
              let document = try? session.localCopy(), let operation = PlaygroundPythonJob.Operation(rawValue: effect.operation) else {
            complete(effect, requester: requester, result: .init(status: "error", exitCode: nil, stderr: "The room or this device changed before the job started. Nothing ran.\n", started: Date(), duration: 0))
            return
        }
        let command = PlaygroundPythonJob.command(effect.operation, entryFile: document.entryFile)
        let job = PlaygroundPythonJob(operation: operation, document: document, paths: identity.paths, folder: PlaygroundPythonJob.folder(room: session.link.id))
        active = (effect.job, false)
        running = PlaygroundRunApproval(id: effect.job, requester: requester, origin: "", operation: effect.operation, command: command, revision: effect.revision)
        progressSent = .distantPast
        Task { [self] in
            let result = await job.execute(isCancelled: { [weak self] in
                guard let self else { return true }
                return stopped || active?.id != effect.job || active?.cancelled == true
            }, onOutput: { [weak self] stdout, stderr in
                guard let self, Date().timeIntervalSince(progressSent) >= 0.5 else { return }
                progressSent = Date()
                Task {
                    await self.update(effect.job, ["state": "progress", "stage": "Running on \(self.displayName)",
                                                   "stdout": Self.clip(stdout, 65_536), "stderr": Self.clip(stderr, 65_536)])
                }
            })
            if active?.id == effect.job {
                active = nil
                running = nil
            }
            complete(effect, requester: requester, result: result)
        }
    }

    private func complete(_ effect: PlaygroundRuntimeHostReply.Effect, requester: String, result: PlaygroundPythonJob.Result) {
        guard !stopped else { return }
        let seconds = String(format: "%.2f", result.duration)
        let exit = result.exitCode.map { "exit \($0)" } ?? result.status
        let stage = "\(result.status == "denied" ? "Denied" : "Ran") on \(displayName) · \(runtime) · \(exit) · \(seconds) s"
        let diagnostics: [[String: Any]] = result.diagnostics.map {
            ["level": $0.level, "message": Self.clip($0.message, 2048), "file": $0.file, "line": $0.line, "column": $0.column + 1]
        }
        let value: [String: Any] = [
            "state": "finished", "status": result.status, "stage": stage, "succeeded": result.succeeded,
            "exitCode": result.exitCode.map { $0 as Any } ?? NSNull(), "durationMs": result.duration * 1000,
            "startedAt": Int64(result.started.timeIntervalSince1970 * 1000), "revision": effect.revision,
            "stdout": Self.clip(result.stdout, 65_536), "stderr": Self.clip(result.stderr, 65_536), "diagnostics": diagnostics,
            "host": ["name": displayName, "kind": Self.kind, "runtime": runtime],
        ]
        Task { await update(effect.job, value) }
        let record = PlaygroundJobRecord(id: effect.job, requester: requester, command: PlaygroundPythonJob.command(effect.operation, entryFile: session.document?.entryFile ?? "main.py"),
                                         revision: effect.revision, status: result.status, exitCode: result.exitCode, duration: result.duration, started: result.started)
        history.insert(record, at: 0)
        if history.count > 20 { history.removeLast() }
    }

    private func update(_ job: String, _ value: [String: Any]) async {
        try? await call("update", extra: ["job": job, "update": value])
    }

    static func clip(_ text: String, _ limit: Int) -> String {
        var bytes = Array(text.utf8.prefix(limit))
        while String(bytes: bytes, encoding: .utf8) == nil && !bytes.isEmpty { bytes.removeLast() }
        return String(decoding: bytes, as: UTF8.self)
    }
}
