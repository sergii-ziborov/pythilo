import Foundation

/// Everything the interpreter tells the app. Delivered on the main actor, in order.
enum PythonEvent: Sendable {
    case ready(version: String)
    case hostError(String)
    case runStarted(id: String)
    case stream(RunStream, String)
    case inputWait
    case inputDone
    case debugPaused(DebugPause)
    case debugResumed
    case debugEvaluation(DebugEvaluation)
    case runEnded(RunOutcome)
    case problems(token: String, path: String, [PythonProblem])
    case completions(token: String, [PythonCompletion])
    case cell(CellEvent)
    case custom(kind: String, data: Data)
}

enum RunStream: Sendable {
    case stdout
    case stderr
}

struct RunFrame: Codable, Sendable, Hashable {
    let file: String
    let line: Int
    let name: String
}

struct RunError: Codable, Sendable, Equatable {
    let type: String
    let message: String
    let file: String?
    let line: Int
    let frames: [RunFrame]
}

struct RunOutcome: Decodable, Sendable, Equatable {
    let id: String
    let status: String
    let code: Int
    let error: RunError?
    let cwd: String?
    let threads: [String]?
    let duration: Double?
    let recovery: String?
}

struct DebugVariable: Decodable, Sendable, Hashable, Identifiable {
    let name: String
    let type: String
    let value: String
    var id: String { name }
}

struct DebugFrame: Decodable, Sendable, Hashable, Identifiable {
    let file: String
    let line: Int
    let name: String
    let locals: [DebugVariable]
    var id: String { "\(file):\(line):\(name)" }
}

struct DebugPause: Decodable, Sendable, Equatable {
    let reason: String
    let file: String
    let line: Int
    let frames: [DebugFrame]
}

struct DebugEvaluation: Decodable, Sendable, Equatable {
    let expression: String
    let type: String?
    let value: String?
    let error: String?
}

struct PythonProblem: Decodable, Sendable, Hashable, Identifiable {
    let line: Int
    let column: Int
    let severity: String
    let message: String
    let code: String
    var id: String { "\(line):\(column):\(code):\(message)" }
}

struct PythonCompletion: Decodable, Sendable, Hashable, Identifiable {
    let label: String
    let insert: String
    let kind: String
    var id: String { label }
}

enum CellEvent: Sendable {
    case started(cell: String, count: Int)
    case output(cell: String, json: Data)
    case ended(cell: String, ok: Bool)
}

/// The app's single route to CPython. Holds no state about what is running;
/// `RunSession` owns that.
final class PythonEngine: @unchecked Sendable {
    static let shared = PythonEngine()

    private let lock = NSLock()
    private var listeners: [UUID: @Sendable (PythonEvent) -> Void] = [:]

    private init() {
        pyhost_set_event_callback { kind, payload, length in
            guard let kind, let payload else { return }
            let name = String(cString: kind)
            let data = Data(bytes: payload, count: length)
            PythonEngine.shared.receive(kind: name, data: data)
        }
    }

    func start() {
        let bundle = Bundle.main.bundlePath
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appending(path: "python")
        try? FileManager.default.createDirectory(at: caches, withIntermediateDirectories: true)
        pyhost_start(bundle, caches.path)
    }

    @discardableResult
    func addListener(_ listener: @escaping @Sendable (PythonEvent) -> Void) -> UUID {
        let id = UUID()
        lock.withLock { listeners[id] = listener }
        return id
    }

    func removeListener(_ id: UUID) {
        lock.withLock { _ = listeners.removeValue(forKey: id) }
    }

    private func send(_ event: PythonEvent) {
        let current = lock.withLock { Array(listeners.values) }
        for listener in current { listener(event) }
    }

    private func receive(kind: String, data: Data) {
        guard let event = Self.decode(kind: kind, data: data) else { return }
        send(event)
    }

    private static func decode(kind: String, data: Data) -> PythonEvent? {
        let decoder = JSONDecoder()
        let text = { String(decoding: data, as: UTF8.self) }
        switch kind {
        case "stdout": return .stream(.stdout, text())
        case "stderr": return .stream(.stderr, text())
        case "input_wait": return .inputWait
        case "input_done": return .inputDone
        case "host_error": return .hostError(text())
        case "ready":
            struct Ready: Decodable { let python: String }
            return (try? decoder.decode(Ready.self, from: data)).map { .ready(version: $0.python) }
        case "run_start":
            struct Start: Decodable { let id: String }
            return (try? decoder.decode(Start.self, from: data)).map { .runStarted(id: $0.id) }
        case "run_end":
            return (try? decoder.decode(RunOutcome.self, from: data)).map { .runEnded($0) }
        case "debug_pause":
            return (try? decoder.decode(DebugPause.self, from: data)).map { .debugPaused($0) }
        case "debug_resume": return .debugResumed
        case "debug_eval":
            return (try? decoder.decode(DebugEvaluation.self, from: data)).map { .debugEvaluation($0) }
        case "analysis_problems":
            struct Report: Decodable { let token: String?; let path: String; let problems: [PythonProblem] }
            return (try? decoder.decode(Report.self, from: data)).map { .problems(token: $0.token ?? "", path: $0.path, $0.problems) }
        case "analysis_completions":
            struct Report: Decodable { let token: String?; let items: [PythonCompletion] }
            return (try? decoder.decode(Report.self, from: data)).map { .completions(token: $0.token ?? "", $0.items) }
        case "cell_start":
            struct Start: Decodable { let cell: String; let count: Int }
            return (try? decoder.decode(Start.self, from: data)).map { .cell(.started(cell: $0.cell, count: $0.count)) }
        case "cell_output":
            struct Output: Decodable { let cell: String }
            return (try? decoder.decode(Output.self, from: data)).map { .cell(.output(cell: $0.cell, json: data)) }
        case "cell_end":
            struct End: Decodable { let cell: String; let ok: Bool }
            return (try? decoder.decode(End.self, from: data)).map { .cell(.ended(cell: $0.cell, ok: $0.ok)) }
        default:
            return .custom(kind: kind, data: data)
        }
    }

    func submit(_ job: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: job),
              let text = String(data: data, encoding: .utf8) else { return }
        pyhost_submit(text)
    }

    func analyze(_ request: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: request),
              let text = String(data: data, encoding: .utf8) else { return }
        pyhost_analyze(text)
    }

    func interrupt() {
        pyhost_send_interrupt()
    }

    func sendInput(_ line: String) {
        pyhost_write_input(line)
    }

    /// Ctrl-D: the program sees the end of its input.
    func sendEndOfInput() {
        pyhost_write_input("\u{04}")
    }

    func sendDebugCommand(_ command: String) {
        pyhost_write_debug_command(command + "\n")
    }
}
