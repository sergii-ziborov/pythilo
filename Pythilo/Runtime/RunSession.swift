import Foundation
import Observation

/// What the interpreter is doing. Never moves to `.idle` until Python says the
/// run has ended, so the Stop button cannot claim something that has not happened.
enum RunPhase: Equatable, Sendable {
    case starting
    case idle
    case running
    case waitingForInput
    case paused
    case cancelling
    /// Python did not respond to repeated interrupts. Only ending the app can
    /// stop a native call or code that swallows KeyboardInterrupt.
    case unresponsive
}

struct OutputChunk: Identifiable, Equatable, Sendable {
    enum Kind: Sendable { case stdout, stderr, input, system }
    let id: Int
    let kind: Kind
    var text: String
}

/// Owns the single run the interpreter can do at a time. One per app.
@MainActor
@Observable
final class RunSession {
    static let shared = RunSession(engine: .shared)

    /// Output kept for display. A program printing forever must not fill memory.
    private static let maximumOutput = 400_000

    private(set) var phase: RunPhase = .starting
    private(set) var pythonVersion: String?
    private(set) var hostError: String?
    private(set) var output: [OutputChunk] = []
    private(set) var droppedCharacters = 0
    private(set) var lastOutcome: RunOutcome?
    private(set) var debugPause: DebugPause?
    private(set) var debugEvaluations: [DebugEvaluation] = []
    private(set) var runLabel: String?
    private(set) var activeRunID: String?

    /// A project's terminal keeps its directory between commands.
    var onRunEnded: ((RunOutcome) -> Void)?
    var onProblems: ((String, String, [PythonProblem]) -> Void)?
    var onCompletions: ((String, [PythonCompletion]) -> Void)?
    var onCell: ((CellEvent) -> Void)?

    private let engine: PythonEngine
    private var nextChunk = 0
    private var outputCount = 0
    private var escalation: Task<Void, Never>?
    private let pendingLock = PendingOutput()

    init(engine: PythonEngine) {
        self.engine = engine
        let pending = pendingLock
        engine.addListener { [weak self] event in
            if case let .stream(stream, text) = event {
                // Output can arrive far faster than the screen can draw it, so it
                // is batched here rather than hopping to the main actor per print.
                if pending.append(stream, text) {
                    Task { @MainActor [weak self] in self?.flushOutput() }
                }
                return
            }
            Task { @MainActor [weak self] in self?.handle(event) }
        }
        engine.start()
    }

    var isBusy: Bool {
        switch phase {
        case .idle, .starting: false
        default: true
        }
    }

    private func flushOutput() {
        for (stream, text) in pendingLock.drain() {
            append(stream == .stdout ? .stdout : .stderr, text)
        }
    }

    private func handle(_ event: PythonEvent) {
        flushOutput()
        switch event {
        case let .ready(version):
            pythonVersion = version
            if phase == .starting { phase = .idle }
        case let .hostError(message):
            hostError = message
            append(.system, "Python host error: \(message)\n")
        case let .runStarted(id):
            activeRunID = id
            if phase != .cancelling { phase = .running }
        case .stream:
            break
        case .inputWait:
            if phase == .running { phase = .waitingForInput }
        case .inputDone:
            if phase == .waitingForInput { phase = .running }
        case let .debugPaused(pause):
            debugPause = pause
            if phase != .cancelling { phase = .paused }
        case .debugResumed:
            debugPause = nil
            if phase == .paused { phase = .running }
        case let .debugEvaluation(evaluation):
            debugEvaluations.append(evaluation)
        case let .runEnded(outcome):
            escalation?.cancel()
            escalation = nil
            debugPause = nil
            activeRunID = nil
            lastOutcome = outcome
            phase = .idle
            onRunEnded?(outcome)
        case let .problems(token, path, problems):
            onProblems?(token, path, problems)
        case let .completions(token, items):
            onCompletions?(token, items)
        case let .cell(cell):
            onCell?(cell)
        }
    }

    private func append(_ kind: OutputChunk.Kind, _ text: String) {
        if let last = output.indices.last, output[last].kind == kind, output[last].text.utf8.count < 16_000 {
            output[last].text += text
        } else {
            output.append(OutputChunk(id: nextChunk, kind: kind, text: text))
            nextChunk += 1
        }
        outputCount += text.utf8.count
        while outputCount > Self.maximumOutput, output.count > 1 {
            let removed = output.removeFirst()
            outputCount -= removed.text.utf8.count
            droppedCharacters += removed.text.utf8.count
        }
    }

    func clearOutput() {
        output = []
        outputCount = 0
        droppedCharacters = 0
    }

    func note(_ text: String) {
        append(.system, text)
    }

    func echoInput(_ text: String) {
        append(.input, text)
    }

    @discardableResult
    func submit(_ job: [String: Any], label: String) -> String? {
        guard phase == .idle else { return nil }
        let id = UUID().uuidString
        var job = job
        job["id"] = id
        phase = .running
        runLabel = label
        debugEvaluations = []
        activeRunID = id
        engine.submit(job)
        return id
    }

    /// Asks Python to stop and reports what really happens. Repeats because code
    /// can catch one KeyboardInterrupt, and gives up honestly after that.
    func stop() {
        guard isBusy, phase != .cancelling, phase != .unresponsive else { return }
        let wasPaused = phase == .paused
        phase = .cancelling
        if wasPaused { engine.sendDebugCommand("quit") }
        engine.interrupt()
        escalation = Task { [weak self, engine] in
            for delay in [1.0, 2.0, 3.0, 4.0] {
                try? await Task.sleep(for: .seconds(delay))
                if Task.isCancelled { return }
                engine.interrupt()
            }
            try? await Task.sleep(for: .seconds(2))
            if Task.isCancelled { return }
            self?.markUnresponsive()
        }
    }

    private func markUnresponsive() {
        if phase == .cancelling { phase = .unresponsive }
    }

    func sendInput(_ line: String) {
        echoInput(line + "\n")
        engine.sendInput(line + "\n")
    }

    func sendEndOfInput() {
        engine.sendEndOfInput()
    }

    func debug(_ command: String) {
        guard phase == .paused else { return }
        engine.sendDebugCommand(command)
    }

    func evaluate(_ expression: String) {
        guard phase == .paused else { return }
        engine.sendDebugCommand("eval " + expression.replacingOccurrences(of: "\n", with: " "))
    }

    func analyze(_ request: [String: Any]) {
        engine.analyze(request)
    }
}

/// Collects output from the Python thread between main-actor flushes.
final class PendingOutput: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [(RunStream, String)] = []
    private var size = 0
    private var dropped = 0
    private static let cap = 1_000_000

    /// Returns true when the main actor needs to be told there is output.
    func append(_ stream: RunStream, _ text: String) -> Bool {
        lock.withLock {
            let wasEmpty = items.isEmpty
            if size + text.utf8.count > Self.cap {
                dropped += text.utf8.count
                return wasEmpty
            }
            if let last = items.indices.last, items[last].0 == stream {
                items[last].1 += text
            } else {
                items.append((stream, text))
            }
            size += text.utf8.count
            return wasEmpty
        }
    }

    func drain() -> [(RunStream, String)] {
        lock.withLock {
            var result = items
            if dropped > 0 {
                result.append((.stderr, "\n[Pythilo skipped \(dropped) characters of output the screen could not keep up with]\n"))
            }
            items = []
            size = 0
            dropped = 0
            return result
        }
    }
}
