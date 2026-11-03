import Foundation

/// What the bundled policy needs to know about this device, built locally only.
struct PlaygroundRuntimePolicyContext: Codable, Sendable {
    struct Job: Codable, Sendable {
        let id: String
        let grant: String
        let revision: String
        let operation: String
        let state: String
    }

    let room: String, target: String, scope: String, revision: String, editCapability: String
    let expires: Int64
    var foreground: Bool, connected: Bool, editConfirmed: Bool, ready: Bool, busy: Bool
    var jobs: [Job] = []
}

struct PlaygroundRuntimePolicyReply: Decodable, Sendable {
    struct Grant: Decodable, Sendable, Equatable {
        let id: String
        let controller: String
        let name: String
        let operations: [String]
        let expires: Int64
    }
    struct Request: Decodable, Sendable, Equatable {
        let controller: String
        let requestID: String
        let name: String
        let operations: [String]
        let expires: Int64
    }
    struct Revoked: Decodable, Sendable { let grant: String; let reason: String }
    struct Admission: Decodable, Sendable { let kind: String; let requestID: String; let reason: String? }
    struct Verified: Decodable, Sendable { let sender: String; let requestID: String; let operation: String; let revision: String; let job: String; let payloadJSON: String }

    let grant: Grant?
    let requests: [Request]
    let revoked: [Revoked]
    let admission: Admission?
    let verified: Verified?
    let error: String?
}

struct PlaygroundRuntimeHostReply: Decodable, Sendable {
    struct Fields: Decodable, Sendable {
        let kind: String
        let room: String
        let target: String
        let requestID: String
        let operation: String
        let revision: String?
        let job: String?
    }
    struct Publication: Decodable, Sendable { let fields: Fields; let payloadJSON: String; let proof: Bool }
    struct Effect: Decodable, Sendable { let type: String; let job: String; let revision: String; let operation: String }
    struct Job: Decodable, Sendable, Equatable { let id: String; let revision: String; let operation: String; let state: String; let stage: String; let controller: String? }
    struct SharedOutput: Decodable, Sendable, Equatable {
        let id: String
        let sender: String
        let name: String
        let revision: String
        let stdout: String
        let stderr: String
        let truncated: Bool
        let succeeded: Bool
        let exitCode: Int?
    }

    let sharedOutput: SharedOutput?
    let grant: PlaygroundRuntimePolicyReply.Grant?
    let requests: [PlaygroundRuntimePolicyReply.Request]?
    let jobs: [Job]?
    let publications: [Publication]?
    let effects: [Effect]?
    let error: String?
}

/// One JavaScriptCore callback, resumed once, with a timeout.
@MainActor
final class PlaygroundRuntimeCall<Value: Sendable> {
    private var continuation: CheckedContinuation<Value, any Error>?
    private var result: Swift.Result<Value, any Error>?
    var timeout: Task<Void, Never>?

    func attach(_ continuation: CheckedContinuation<Value, any Error>) {
        if let result { continuation.resume(with: result) } else { self.continuation = continuation }
    }

    func finish(_ result: Swift.Result<Value, any Error>) {
        guard self.result == nil else { return }
        self.result = result
        timeout?.cancel()
        timeout = nil
        continuation?.resume(with: result)
        continuation = nil
    }

    deinit { timeout?.cancel() }
}
