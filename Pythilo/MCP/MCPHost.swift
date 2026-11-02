import CryptoKit
import Foundation
import Network
import Observation
import PythiloGit
import UIKit

enum MCPPermission: String, CaseIterable, Identifiable, Sendable {
    case read, edit, run, packages, commit, push

    var id: String { rawValue }

    var title: String {
        switch self {
        case .read: "Read project files"
        case .edit: "Edit files"
        case .run: "Run, test, debug"
        case .packages: "Install packages"
        case .commit: "Git commit"
        case .push: "Git push"
        }
    }
}

enum MCPGrant: String, CaseIterable, Identifiable, Sendable {
    case allow, ask, deny

    var id: String { rawValue }

    var title: String {
        switch self {
        case .allow: "Allowed"
        case .ask: "Ask each time"
        case .deny: "Not allowed"
        }
    }
}

struct MCPApprovalRequest: Identifiable {
    let id = UUID()
    let permission: MCPPermission
    let summary: String
    let detail: String
    let answer: (Bool) -> Void
}

struct MCPActivity: Identifiable {
    let id = UUID()
    let date = Date()
    let text: String
}

/// The AI connection. The app itself is the MCP server, reached over the local
/// network with Streamable HTTP, so no cloud service or account sits in between.
/// Access covers one chosen project, for as long as the app keeps it open.
@MainActor
@Observable
final class MCPHost {
    static let shared = MCPHost()

    private(set) var project: Project?
    private(set) var port: UInt16?
    private(set) var token = ""
    private(set) var failure: String?
    private(set) var clientName: String?
    private(set) var activity: [MCPActivity] = []
    private(set) var pending: [MCPApprovalRequest] = []
    var grants: [MCPPermission: MCPGrant] = [
        .read: .allow, .edit: .allow, .run: .ask, .packages: .ask, .commit: .ask, .push: .deny,
    ]
    /// Set by the open workspace, so edits reach its buffers at once.
    weak var workspace: WorkspaceModel?
    var allowsLoopbackOnly = false

    private var listener: NWListener?
    private let queue = DispatchQueue(label: "pythilo.mcp")
    private var revision = 0

    var isRunning: Bool { port != nil }

    var address: String? {
        guard let port else { return nil }
        return "http://\(Self.localAddress() ?? "127.0.0.1"):\(port)/mcp"
    }

    func command(for client: String) -> String {
        guard let address else { return "" }
        switch client {
        case "codex":
            return "codex mcp add pythilo --url \(address) --bearer-token-env-var PYTHILO_TOKEN"
        default:
            return "claude mcp add --transport http pythilo \(address) --header \"Authorization: Bearer \(token)\""
        }
    }

    func start(project: Project) {
        stop()
        self.project = project
        failure = nil
        token = Self.newToken()
        do {
            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true
            let listener = try NWListener(using: parameters, on: 18765)
            listener.stateUpdateHandler = { [weak self] state in
                let snapshot: (UInt16?, String?) = switch state {
                case .ready: (listener.port?.rawValue, nil)
                case let .failed(error): (nil, "The connection could not start: \(error.localizedDescription)")
                default: (nil, nil)
                }
                Task { @MainActor in
                    if let port = snapshot.0 { self?.port = port }
                    if let message = snapshot.1 {
                        self?.failure = message
                        self?.port = nil
                    }
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                self?.accept(connection)
            }
            listener.start(queue: queue)
            self.listener = listener
            log("Waiting for a client on \(project.name)")
        } catch {
            failure = error.localizedDescription
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        port = nil
        clientName = nil
        token = ""
        for request in pending { request.answer(false) }
        pending = []
    }

    func log(_ text: String) {
        activity.insert(MCPActivity(text: text), at: 0)
        if activity.count > 50 { activity.removeLast() }
    }

    func answer(_ request: MCPApprovalRequest, allow: Bool) {
        pending.removeAll { $0.id == request.id }
        log("\(allow ? "Allowed" : "Denied"): \(request.summary)")
        request.answer(allow)
    }

    // MARK: HTTP

    private nonisolated func accept(_ connection: NWConnection) {
        connection.start(queue: DispatchQueue(label: "pythilo.mcp.connection"))
        receive(connection, buffer: Data())
    }

    private nonisolated func receive(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1 << 20) { [weak self] data, _, complete, error in
            guard let self else { return }
            var buffer = buffer
            if let data { buffer.append(data) }
            if let request = HTTPRequest(parsing: buffer) {
                Task { @MainActor in
                    let response = await self.respond(to: request)
                    connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
                }
                return
            }
            if complete || error != nil || buffer.count > 16 << 20 {
                connection.cancel()
                return
            }
            self.receive(connection, buffer: buffer)
        }
    }

    private func respond(to request: HTTPRequest) async -> Data {
        guard request.path == "/mcp" || request.path == "/" else {
            return HTTPRequest.response(status: "404 Not Found", body: Data("{}".utf8))
        }
        guard !token.isEmpty, Self.constantTimeEquals(request.headers["authorization"] ?? "", "Bearer \(token)") else {
            return HTTPRequest.response(status: "401 Unauthorized", body: Data(#"{"error":"A valid bearer token is required."}"#.utf8))
        }
        switch request.method {
        case "POST":
            break
        case "DELETE":
            clientName = nil
            log("Client disconnected")
            return HTTPRequest.response(status: "200 OK", body: Data())
        default:
            // Streamable HTTP lets a server decline the optional event stream.
            return HTTPRequest.response(status: "405 Method Not Allowed", body: Data())
        }
        guard let object = try? JSONSerialization.jsonObject(with: request.body) as? [String: Any] else {
            return HTTPRequest.response(status: "400 Bad Request", body: Self.encode(Self.rpcError(nil, -32700, "Parse error")))
        }
        guard let reply = await handle(object) else {
            return HTTPRequest.response(status: "202 Accepted", body: Data())
        }
        return HTTPRequest.response(status: "200 OK", body: Self.encode(reply))
    }

    // MARK: JSON-RPC

    private func handle(_ message: [String: Any]) async -> [String: Any]? {
        let id = message["id"]
        let method = message["method"] as? String ?? ""
        let params = message["params"] as? [String: Any] ?? [:]
        guard id != nil else { return nil }
        switch method {
        case "initialize":
            let info = params["clientInfo"] as? [String: Any]
            clientName = info?["name"] as? String ?? "AI client"
            log("\(clientName ?? "Client") connected")
            return Self.rpcResult(id, [
                "protocolVersion": params["protocolVersion"] as? String ?? "2025-06-18",
                "capabilities": ["tools": ["listChanged": false]],
                "serverInfo": ["name": "pythilo", "version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"],
                "instructions": "This is one Python project on the user's iPhone or iPad. Code runs on the device, in CPython 3.14, with no subprocesses. Call capabilities first. Writes need the revision a read returned.",
            ])
        case "ping":
            return Self.rpcResult(id, [:])
        case "tools/list":
            return Self.rpcResult(id, ["tools": MCPTools.definitions])
        case "tools/call":
            let name = params["name"] as? String ?? ""
            let arguments = params["arguments"] as? [String: Any] ?? [:]
            do {
                let result = try await call(name, arguments)
                let text = String(decoding: Self.encode(result), as: UTF8.self)
                return Self.rpcResult(id, ["content": [["type": "text", "text": text]], "structuredContent": result, "isError": false])
            } catch {
                return Self.rpcResult(id, ["content": [["type": "text", "text": error.localizedDescription]], "isError": true])
            }
        default:
            return Self.rpcError(id, -32601, "Unknown method \(method)")
        }
    }

    private func require(_ permission: MCPPermission, _ summary: String, detail: String) async throws {
        switch grants[permission] ?? .deny {
        case .allow:
            return
        case .deny:
            throw MCPFailure("The user has not allowed this: \(permission.title).")
        case .ask:
            let allowed = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
                let request = MCPApprovalRequest(permission: permission, summary: summary, detail: detail) { continuation.resume(returning: $0) }
                pending.append(request)
                let id = request.id
                Task { [weak self] in
                    try? await Task.sleep(for: .seconds(120))
                    if let self, let stale = self.pending.first(where: { $0.id == id }) {
                        self.answer(stale, allow: false)
                    }
                }
            }
            guard allowed else { throw MCPFailure("The user did not approve this: \(summary).") }
        }
    }

    private func root() throws -> URL {
        guard let project else { throw MCPFailure("No project is shared.") }
        return project.url
    }

    private func call(_ name: String, _ arguments: [String: Any]) async throws -> [String: Any] {
        let root = try root()
        workspace?.saveAll()
        switch name {
        case "capabilities":
            return [
                "project": root.lastPathComponent,
                "device": UIDevice.current.model,
                "python": RunSession.shared.pythonVersion ?? "starting",
                "runtime_fingerprint": Self.fingerprint(),
                "limits": ["no subprocess or multiprocessing", "compiled packages only if bundled", "stops when iOS suspends the app"],
                "permissions": Dictionary(uniqueKeysWithValues: MCPPermission.allCases.map { ($0.rawValue, (grants[$0] ?? .deny).rawValue) }),
                "running": RunSession.shared.isBusy,
            ]
        case "list_files":
            try await require(.read, "List files", detail: root.lastPathComponent)
            log("Listed files")
            return ["files": MCPTools.listFiles(in: root)]
        case "read_file":
            try await require(.read, "Read a file", detail: "")
            let path = try MCPTools.safePath(arguments["path"], root: root)
            let text = try String(contentsOf: root.appending(path: path), encoding: .utf8)
            log("Read \(path)")
            return ["path": path, "text": text, "revision": MCPTools.revision(text)]
        case "write_file":
            let path = try MCPTools.safePath(arguments["path"], root: root)
            guard let text = arguments["text"] as? String else { throw MCPFailure("text is required.") }
            try await require(.edit, "Edit \(path)", detail: "\(text.utf8.count) bytes")
            let url = root.appending(path: path)
            let existing = try? String(contentsOf: url, encoding: .utf8)
            if let existing {
                guard let expected = arguments["expected_revision"] as? String else {
                    throw MCPFailure("\(path) exists. Read it first and send expected_revision.")
                }
                guard expected == MCPTools.revision(existing) else {
                    throw MCPFailure("Conflict: \(path) changed since that revision. Read it again. Nothing was written.")
                }
            }
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: url, atomically: true, encoding: .utf8)
            workspace?.reloadTree()
            workspace?.reloadChangedBuffers()
            workspace?.refreshGit()
            revision += 1
            log("Edited \(path)")
            return ["path": path, "revision": MCPTools.revision(text)]
        case "diagnostics":
            try await require(.read, "Read diagnostics", detail: "")
            let path = try MCPTools.safePath(arguments["path"], root: root)
            let text = try String(contentsOf: root.appending(path: path), encoding: .utf8)
            return ["path": path, "problems": try await MCPTools.check(text, path: path)]
        case "run":
            let path = try MCPTools.safePath(arguments["path"], root: root)
            try await require(.run, "Run \(path)", detail: "python \(path)")
            log("Ran \(path)")
            return try await execute(["kind": "script", "path": root.appending(path: path).path, "root": root.path, "cwd": root.path], label: path, timeout: arguments["timeout_seconds"] as? Double)
        case "test":
            let args = arguments["args"] as? String ?? "-q"
            try await require(.run, "Run tests", detail: "pytest \(args)")
            log("Ran pytest \(args)")
            return try await execute(["kind": "shell", "line": "pytest \(args)", "root": root.path, "cwd": root.path], label: "pytest", timeout: arguments["timeout_seconds"] as? Double)
        case "stop":
            try await require(.run, "Stop the running code", detail: "")
            RunSession.shared.stop()
            return ["phase": String(describing: RunSession.shared.phase)]
        case "output":
            try await require(.read, "Read output", detail: "")
            return ["phase": String(describing: RunSession.shared.phase), "output": MCPTools.outputText()]
        case "package_install":
            guard let package = arguments["package"] as? String, !package.isEmpty, !package.contains(" ") else {
                throw MCPFailure("package is required, as one requirement.")
            }
            try await require(.packages, "Install \(package)", detail: "pip install \(package)")
            log("Installed \(package)")
            return try await execute(["kind": "shell", "line": "pip install \(package)", "root": root.path, "cwd": root.path], label: "pip", timeout: 300)
        case "git_status":
            try await require(.read, "Read Git status", detail: "")
            let repository = ProjectRepository(worktree: root)
            guard repository.exists else { return ["repository": false] }
            let snapshot = try repository.snapshot()
            return [
                "repository": true,
                "branch": snapshot.branch,
                "head": snapshot.head ?? NSNull(),
                "changes": snapshot.changes.map { ["path": $0.path, "kind": $0.kind.rawValue, "staged": $0.staged] },
                "remote": snapshot.remoteURL ?? NSNull(),
            ]
        case "git_diff":
            try await require(.read, "Read Git diff", detail: "")
            return ["diff": try ProjectRepository(worktree: root).diff(path: arguments["path"] as? String)]
        case "git_commit":
            guard let message = arguments["message"] as? String else { throw MCPFailure("message is required.") }
            try await require(.commit, "Commit: \(message)", detail: "All changed files")
            let repository = ProjectRepository(worktree: root)
            try repository.stage([])
            let commit = try repository.commit(message: message, author: GitTerminal.author, email: GitTerminal.email)
            workspace?.refreshGit()
            log("Committed \(commit.shortID)")
            return ["commit": commit.id]
        case "git_push":
            try await require(.push, "Push to origin", detail: (try? ProjectRepository(worktree: root).snapshot().remoteURL) ?? "")
            let repository = ProjectRepository(worktree: root)
            let credential = GitCredentialVault.credential(for: try repository.snapshot().remoteURL)
            let text = try await Task.detached { try repository.push(credential: credential) }.value
            log("Pushed")
            return ["result": text]
        default:
            throw MCPFailure("Unknown tool \(name).")
        }
    }

    private func execute(_ job: [String: Any], label: String, timeout: Double?) async throws -> [String: Any] {
        let session = RunSession.shared
        guard session.phase == .idle else {
            throw MCPFailure("Python is busy. Call stop or output first.")
        }
        session.clearOutput()
        guard let id = session.submit(job, label: label) else {
            throw MCPFailure("Python is busy.")
        }
        let deadline = Date().addingTimeInterval(min(timeout ?? 60, 300))
        while session.lastOutcome?.id != id, Date() < deadline {
            try await Task.sleep(for: .milliseconds(100))
        }
        let base: [String: Any] = [
            "run_id": id,
            "executed_on": UIDevice.current.model,
            "runtime_fingerprint": Self.fingerprint(),
            "output": MCPTools.outputText(),
        ]
        guard let outcome = session.lastOutcome, outcome.id == id else {
            return base.merging(["status": "still_running"]) { $1 }
        }
        workspace?.reloadTree()
        workspace?.refreshGit()
        var result = base
        result["status"] = outcome.status
        result["exit_code"] = outcome.code
        result["duration_seconds"] = outcome.duration ?? 0
        if let error = outcome.error {
            result["error"] = ["type": error.type, "message": error.message, "file": error.file ?? "", "line": error.line]
        }
        return result
    }

    // MARK: Helpers

    nonisolated static func fingerprint() -> String {
        let packages = (try? FileManager.default.contentsOfDirectory(atPath: Bundle.main.bundleURL.appending(path: "app_packages").path)) ?? []
        let joined = packages.filter { $0.hasSuffix(".dist-info") }.sorted().joined(separator: ",")
        let digest = SHA256.hash(data: Data(joined.utf8)).prefix(6).map { String(format: "%02x", $0) }.joined()
        return "cpython-3.14-ios-\(digest)"
    }

    private nonisolated static func newToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 24)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private nonisolated static func constantTimeEquals(_ left: String, _ right: String) -> Bool {
        let a = Array(left.utf8), b = Array(right.utf8)
        guard a.count == b.count else { return false }
        var difference: UInt8 = 0
        for index in a.indices { difference |= a[index] ^ b[index] }
        return difference == 0
    }

    nonisolated static func localAddress() -> String? {
        var pointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&pointer) == 0, let first = pointer else { return nil }
        defer { freeifaddrs(pointer) }
        var fallback: String?
        for entry in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let interface = entry.pointee
            guard let address = interface.ifa_addr, address.pointee.sa_family == UInt8(AF_INET) else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 else { continue }
            let text = String(cString: host)
            let name = String(cString: interface.ifa_name)
            if name == "en0" { return text }
            if name.hasPrefix("en"), fallback == nil { fallback = text }
        }
        return fallback
    }

    private nonisolated static func rpcResult(_ id: Any?, _ result: [String: Any]) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id ?? NSNull(), "result": result]
    }

    private nonisolated static func rpcError(_ id: Any?, _ code: Int, _ message: String) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id ?? NSNull(), "error": ["code": code, "message": message]]
    }

    private nonisolated static func encode(_ object: [String: Any]) -> Data {
        (try? JSONSerialization.data(withJSONObject: object)) ?? Data("{}".utf8)
    }
}

struct MCPFailure: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

struct HTTPRequest: Sendable {
    let method: String
    let path: String
    let headers: [String: String]
    let body: Data

    /// Nil until the whole request has arrived.
    init?(parsing data: Data) {
        guard let end = data.range(of: Data("\r\n\r\n".utf8)),
              let head = String(data: data[data.startIndex..<end.lowerBound], encoding: .utf8) else { return nil }
        let lines = head.components(separatedBy: "\r\n")
        let parts = lines.first?.split(separator: " ") ?? []
        guard parts.count >= 2 else { return nil }
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            headers[line[..<colon].lowercased()] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        let length = Int(headers["content-length"] ?? "0") ?? 0
        let bodyStart = end.upperBound
        guard data.distance(from: bodyStart, to: data.endIndex) >= length else { return nil }
        method = String(parts[0])
        path = String(parts[1].split(separator: "?").first ?? "")
        self.headers = headers
        body = data[bodyStart..<data.index(bodyStart, offsetBy: length)]
    }

    static func response(status: String, body: Data) -> Data {
        var head = "HTTP/1.1 \(status)\r\nContent-Type: application/json\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        if status.hasPrefix("405") { head = head.replacingOccurrences(of: "Connection:", with: "Allow: POST, DELETE\r\nConnection:") }
        return Data(head.utf8) + body
    }
}
