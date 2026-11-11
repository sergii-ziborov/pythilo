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

enum OutputChannel: Sendable {
    case output
    case terminal
}

struct OutputChunk: Identifiable, Equatable, Sendable {
    enum Kind: Sendable { case stdout, stderr, input, system }
    let id: Int
    let kind: Kind
    var text: String
}

/// Where a terminal command's output goes: one terminal tab.
@MainActor
protocol TerminalOutputSink: AnyObject {
    func appendOutput(_ kind: OutputChunk.Kind, _ text: String)
}

/// A bounded run of output chunks, as a terminal tab keeps it.
@MainActor
struct OutputBuffer {
    private(set) var chunks: [OutputChunk] = []
    private(set) var revision = 0
    private var count = 0
    private static var nextID = 1_000_000_000

    mutating func append(_ kind: OutputChunk.Kind, _ text: String) {
        guard !text.isEmpty else { return }
        var next = Self.nextID
        var dropped = 0
        RunSession.add(kind, text, to: &chunks, count: &count, dropped: &dropped, next: &next)
        Self.nextID = next
        revision += 1
    }

    mutating func clear() {
        chunks = []
        count = 0
        revision += 1
    }
}

/// Owns the single run the interpreter can do at a time. One per app.
@MainActor
@Observable
final class RunSession {
    static let shared = RunSession(engine: .shared)

    /// Output kept for display. A program printing forever must not fill memory.
    nonisolated private static let maximumOutput = 400_000

    private(set) var phase: RunPhase = .starting
    private(set) var pythonVersion: String?
    private(set) var hostError: String?
    private(set) var output: [OutputChunk] = []
    private(set) var terminalOutput: [OutputChunk] = []
    /// Bumps on every change, so a text view can tell an append from a clear.
    private(set) var outputRevision = 0
    private(set) var terminalRevision = 0
    private(set) var droppedCharacters = 0
    private(set) var activeChannel: OutputChannel = .output
    private(set) var runStartedAt: Date?
    private(set) var lastOutcome: RunOutcome?
    private(set) var debugPause: DebugPause?
    private(set) var debugEvaluations: [DebugEvaluation] = []
    private(set) var runLabel: String?
    private(set) var activeRunID: String?
    /// Where the running program listens, once it does. Ends with the run.
    private(set) var listening: ListeningServer?

    /// A project's terminal keeps its directory between commands.
    var onRunEnded: ((RunOutcome) -> Void)?
    var onProblems: ((String, String, [PythonProblem]) -> Void)?
    var onCompletions: ((String, [PythonCompletion]) -> Void)?
    var onCell: ((CellEvent) -> Void)?
    var onCustom: ((String, Data) -> Void)?

    /// Terminal tabs run here when the main thread is busy: lanes 1, 2 and 3.
    let lanes: [RunLane]
    /// The terminal tab a note or an unaddressed terminal job writes to: the one on screen.
    weak var defaultTerminalSink: (any TerminalOutputSink)?
    /// The tab whose command runs on the main thread now.
    private(set) weak var terminalSink: (any TerminalOutputSink)?
    var onLaneRunEnded: ((Int, RunOutcome) -> Void)?

    private let engine: PythonEngine
    private var nextChunk = 0
    private var outputCount = 0
    private var terminalCount = 0
    private var escalation: Task<Void, Never>?
    private let pendingLock = PendingOutput()

    init(engine: PythonEngine) {
        self.engine = engine
        lanes = (1...PythonEngine.extraLanes).map { RunLane(index: $0, engine: engine) }
        let pending = pendingLock
        engine.addListener { [weak self] event in
            // Output can arrive far faster than the screen can draw it, so it
            // is batched here rather than hopping to the main actor per print.
            if case let .stream(stream, text) = event {
                if pending.append(0, stream, text) {
                    Task { @MainActor [weak self] in self?.flushOutput() }
                }
                return
            }
            if case let .lane(lane, .stream(stream, text)) = event {
                if pending.append(lane, stream, text) {
                    Task { @MainActor [weak self] in self?.flushOutput() }
                }
                return
            }
            Task { @MainActor [weak self] in self?.handle(event) }
        }
        for lane in lanes {
            lane.onEnded = { [weak self] lane, outcome in self?.onLaneRunEnded?(lane, outcome) }
        }
        engine.start()
    }

    /// The main thread, then any free lane: where a terminal command can start now.
    var freeTerminalLane: Int? {
        if phase == .idle || phase == .starting { return 0 }
        return lanes.first { !$0.isBusy }?.index
    }

    /// Anything running anywhere, terminal lanes included.
    var isAnythingRunning: Bool { isBusy || lanes.contains { $0.isBusy } }

    func lane(_ index: Int) -> RunLane? {
        index > 0 && index <= lanes.count ? lanes[index - 1] : nil
    }

    /// Runs a terminal command for one tab: on the main thread when it is free, so
    /// signals and Stop behave as on a desktop, otherwise beside it on a free lane.
    /// Returns the lane and the run's id, or nil when every lane is busy.
    func submitTerminal(_ job: [String: Any], label: String, sink: any TerminalOutputSink) -> (lane: Int, id: String)? {
        if phase == .idle || phase == .starting {
            terminalSink = sink
            guard let id = submit(job, label: label, channel: .terminal) else { terminalSink = nil; return nil }
            return (0, id)
        }
        guard let lane = lanes.first(where: { !$0.isBusy }) else { return nil }
        guard missingPackagesNote(for: job, sink: sink) == nil else { return nil }
        var job = job
        job["packagePaths"] = ContentStore.shared.packagePaths
        var environment = ContentStore.shared.assetEnvironment
        environment.merge(job["env"] as? [String: String] ?? [:]) { _, explicit in explicit }
        job["env"] = environment
        return lane.submit(job, label: label, sink: sink).map { (lane.index, $0) }
    }

    /// Stops whatever runs on a lane: the main thread's run for 0.
    func stop(lane: Int) {
        if lane == 0 { stop() } else { self.lane(lane)?.stop() }
    }

    func sendInput(_ line: String, lane: Int) {
        if lane == 0 { sendInput(line) } else { self.lane(lane)?.sendInput(line) }
    }

    func sendEndOfInput(lane: Int) {
        if lane == 0 { sendEndOfInput() } else { self.lane(lane)?.sendEndOfInput() }
    }

    func phase(lane: Int) -> RunPhase {
        lane == 0 ? phase : self.lane(lane)?.phase ?? .idle
    }

    func listening(lane: Int) -> ListeningServer? {
        lane == 0 ? listening : self.lane(lane)?.listening
    }

    /// The offline packages a job needs and does not have. Says so in the sink.
    private func missingPackagesNote(for job: [String: Any], sink: (any TerminalOutputSink)?) -> String? {
        guard let root = job["root"] as? String else { return nil }
        let project = Project(url: URL(filePath: root))
        let projectsRoot = ProjectStore.shared.root.standardizedFileURL.path + "/"
        let requirements = project.url.standardizedFileURL.path.hasPrefix(projectsRoot)
            ? ProjectDependencies.refresh(project) : project.requiredPacks
        guard requirements.contains(where: { !ContentStore.shared.ready($0) }) else { return nil }
        let note = "This project's offline packages are not downloaded. Open Project downloads and tap Download project packages. Nothing is downloaded by Run. Once the download finishes, this project can run offline.\n"
        sink?.appendOutput(.system, note)
        return note
    }

    var isBusy: Bool {
        switch phase {
        case .idle, .starting: false
        default: true
        }
    }

    private func flushOutput() {
        for (lane, stream, text) in pendingLock.drain() {
            let kind: OutputChunk.Kind = stream == .stdout ? .stdout : .stderr
            if lane == 0 {
                append(kind, Self.withoutTerminalColors(text))
            } else {
                self.lane(lane)?.sink?.appendOutput(kind, Self.withoutTerminalColors(text))
            }
        }
    }

    /// Servers colour their logs for a terminal. This view has no such codes.
    nonisolated static func withoutTerminalColors(_ text: String) -> String {
        guard text.contains("\u{1B}") else { return text }
        return text.replacing(/\x{1B}\[[0-9;]*[A-Za-z]/, with: "")
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
            listening = nil
            lastOutcome = outcome
            phase = .idle
            onRunEnded?(outcome)
        case let .problems(token, path, problems):
            onProblems?(token, path, problems)
        case let .completions(token, items):
            onCompletions?(token, items)
        case let .cell(cell):
            onCell?(cell)
        case let .custom(kind, data):
            if kind == "server_listening" {
                listening = try? JSONDecoder().decode(ListeningServer.self, from: data)
                return
            }
            onCustom?(kind, data)
        case let .lane(index, event):
            lane(index)?.handle(event)
        }
    }

    private func append(_ kind: OutputChunk.Kind, _ text: String, channel: OutputChannel? = nil) {
        switch channel ?? activeChannel {
        case .output:
            Self.add(kind, text, to: &output, count: &outputCount, dropped: &droppedCharacters, next: &nextChunk)
            outputRevision += 1
        case .terminal:
            if let sink = terminalSink ?? defaultTerminalSink {
                sink.appendOutput(kind, text)
                return
            }
            var dropped = 0
            Self.add(kind, text, to: &terminalOutput, count: &terminalCount, dropped: &dropped, next: &nextChunk)
            terminalRevision += 1
        }
    }

    nonisolated static func add(
        _ kind: OutputChunk.Kind,
        _ text: String,
        to chunks: inout [OutputChunk],
        count: inout Int,
        dropped: inout Int,
        next: inout Int
    ) {
        if let last = chunks.indices.last, chunks[last].kind == kind, chunks[last].text.utf8.count < 16_000 {
            chunks[last].text += text
        } else {
            chunks.append(OutputChunk(id: next, kind: kind, text: text))
            next += 1
        }
        count += text.utf8.count
        while count > maximumOutput, chunks.count > 1 {
            let removed = chunks.removeFirst()
            count -= removed.text.utf8.count
            dropped += removed.text.utf8.count
        }
    }

    func clearOutput() {
        output = []
        outputCount = 0
        droppedCharacters = 0
        outputRevision += 1
    }

    func clearTerminal() {
        terminalOutput = []
        terminalCount = 0
        terminalRevision += 1
    }

    /// App-side lines in a terminal tab: the one given, or the one on screen.
    func noteTerminal(_ text: String, kind: OutputChunk.Kind = .system, to sink: (any TerminalOutputSink)? = nil) {
        if let sink = sink ?? defaultTerminalSink {
            sink.appendOutput(kind, text)
            return
        }
        var dropped = 0
        Self.add(kind, text, to: &terminalOutput, count: &terminalCount, dropped: &dropped, next: &nextChunk)
        terminalRevision += 1
    }

    func note(_ text: String) {
        append(.system, text)
    }

    func echoInput(_ text: String) {
        append(.input, text)
    }

    @discardableResult
    func submit(_ job: [String: Any], label: String, channel: OutputChannel = .output) -> String? {
        // A job sent while Python starts waits in the host's queue.
        guard phase == .idle || phase == .starting else { return nil }
        if channel == .output { terminalSink = nil }
        if channel == .terminal, terminalSink == nil { terminalSink = defaultTerminalSink }
        if let root = job["root"] as? String {
            let project = Project(url: URL(filePath: root))
            let projectsRoot = ProjectStore.shared.root.standardizedFileURL.path + "/"
            let requirements = project.url.standardizedFileURL.path.hasPrefix(projectsRoot)
                ? ProjectDependencies.refresh(project) : project.requiredPacks
            let missing = requirements.filter { !ContentStore.shared.ready($0) }
            if !missing.isEmpty {
                let text = "This project's offline packages are not downloaded. Open Project downloads and tap Download project packages. Nothing is downloaded by Run. Once the download finishes, this project can run offline.\n"
                if channel == .terminal { noteTerminal(text, to: terminalSink) } else { note(text) }
                terminalSink = nil
                return nil
            }
        }
        activeChannel = channel
        runStartedAt = Date()
        let id = UUID().uuidString
        var job = job
        job["id"] = id
        job["packagePaths"] = ContentStore.shared.packagePaths
        var environment = ContentStore.shared.assetEnvironment
        environment.merge(job["env"] as? [String: String] ?? [:]) { _, explicit in explicit }
        job["env"] = environment
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

/// Collects output from the Python threads between main-actor flushes.
final class PendingOutput: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [(Int, RunStream, String)] = []
    private var size = 0
    private var dropped: [Int: Int] = [:]
    private static let cap = 1_000_000

    /// Returns true when the main actor needs to be told there is output.
    func append(_ lane: Int, _ stream: RunStream, _ text: String) -> Bool {
        lock.withLock {
            let wasEmpty = items.isEmpty
            if size + text.utf8.count > Self.cap {
                dropped[lane, default: 0] += text.utf8.count
                return wasEmpty
            }
            if let last = items.indices.last, items[last].0 == lane, items[last].1 == stream {
                items[last].2 += text
            } else {
                items.append((lane, stream, text))
            }
            size += text.utf8.count
            return wasEmpty
        }
    }

    func drain() -> [(Int, RunStream, String)] {
        lock.withLock {
            var result = items
            for (lane, count) in dropped where count > 0 {
                result.append((lane, .stderr, "\n[Pythilo skipped \(count) characters of output the screen could not keep up with]\n"))
            }
            items = []
            size = 0
            dropped = [:]
            return result
        }
    }
}

/// One terminal lane beside the main thread: its phase, its server and its Stop.
@MainActor
@Observable
final class RunLane: Identifiable {
    let index: Int
    private(set) var phase: RunPhase = .idle
    private(set) var listening: ListeningServer?
    private(set) var lastOutcome: RunOutcome?
    private(set) var activeRunID: String?
    private(set) var label: String?
    private(set) weak var sink: (any TerminalOutputSink)?
    var onEnded: ((Int, RunOutcome) -> Void)?

    private let engine: PythonEngine
    private var escalation: Task<Void, Never>?

    nonisolated var id: Int { index }

    init(index: Int, engine: PythonEngine) {
        self.index = index
        self.engine = engine
    }

    var isBusy: Bool { phase != .idle && phase != .starting }

    func submit(_ job: [String: Any], label: String, sink: any TerminalOutputSink) -> String? {
        guard !isBusy else { return nil }
        let id = UUID().uuidString
        var job = job
        job["id"] = id
        self.sink = sink
        self.label = label
        activeRunID = id
        phase = .running
        engine.submit(job, lane: index)
        return id
    }

    func handle(_ event: LaneEvent) {
        switch event {
        case let .started(id):
            activeRunID = id
            if phase != .cancelling { phase = .running }
        case .stream:
            break
        case .inputWait:
            if phase == .running { phase = .waitingForInput }
        case .inputDone:
            if phase == .waitingForInput { phase = .running }
        case let .listening(server):
            listening = server
        case let .ended(outcome):
            escalation?.cancel()
            escalation = nil
            activeRunID = nil
            listening = nil
            lastOutcome = outcome
            phase = .idle
            onEnded?(index, outcome)
        }
    }

    /// The same escalation as the main thread: repeat, then say honestly that it did not stop.
    func stop() {
        guard isBusy, phase != .cancelling, phase != .unresponsive else { return }
        phase = .cancelling
        engine.interrupt(lane: index)
        escalation = Task { [weak self, engine, index] in
            for delay in [1.0, 2.0, 3.0, 4.0] {
                try? await Task.sleep(for: .seconds(delay))
                if Task.isCancelled { return }
                engine.interrupt(lane: index)
            }
            try? await Task.sleep(for: .seconds(2))
            if Task.isCancelled { return }
            if self?.phase == .cancelling { self?.phase = .unresponsive }
        }
    }

    func sendInput(_ line: String) {
        sink?.appendOutput(.input, line + "\n")
        engine.sendInput(line + "\n", lane: index)
    }

    func sendEndOfInput() {
        engine.sendInput("\u{04}", lane: index)
    }
}
