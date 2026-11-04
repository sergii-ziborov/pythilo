import Foundation
import Observation
import PythiloGit

struct FileNode: Identifiable, Hashable, Sendable {
    let path: String
    let name: String
    let isDirectory: Bool
    var children: [FileNode]
    var id: String { path }
}

enum WorkspacePanel: String, CaseIterable, Identifiable, Sendable {
    case code, problems, output, terminal, debug

    var id: String { rawValue }

    var title: String {
        switch self {
        case .code: "Code"
        case .problems: "Problems"
        case .output: "Output"
        case .terminal: "Terminal"
        case .debug: "Debug"
        }
    }

    var systemImage: String {
        switch self {
        case .code: "chevron.left.forwardslash.chevron.right"
        case .problems: "exclamationmark.triangle"
        case .output: "text.alignleft"
        case .terminal: "terminal"
        case .debug: "ladybug"
        }
    }
}

struct WorkspaceProblem: Identifiable, Hashable, Sendable {
    let path: String
    let line: Int
    let column: Int
    let severity: String
    let message: String
    let source: String
    var id: String { "\(path):\(line):\(column):\(message)" }
}

/// One open project: its tree, buffers, breakpoints and what its panels show.
@MainActor
@Observable
final class WorkspaceModel {
    let project: Project
    let session: RunSession

    private(set) var tree: [FileNode] = []
    var expanded: Set<String> = []
    private(set) var tabs: [String] = []
    private(set) var selectedPath: String?
    private(set) var buffers: [String: String] = [:]
    private var savedText: [String: String] = [:]
    var breakpoints: [String: Set<Int>] = [:]
    private(set) var lintProblems: [String: [WorkspaceProblem]] = [:]
    private(set) var runProblems: [WorkspaceProblem] = []
    var panel: WorkspacePanel = .code
    var drawerOpen = false
    var cursorOffset = 0
    var navigation: EditorNavigationTarget?
    private(set) var terminalDirectory: URL
    private(set) var gitSnapshot: GitSnapshot?
    private(set) var previewURL: URL?
    var previewOpen = false
    /// The framework's commands, offered as chips in the terminal.
    private(set) var commands = ProjectCommands.none
    /// Text a chip puts into the terminal's input for the user to finish.
    var terminalDraft: String?
    private var djangoNames: [(group: String, name: String)] = []
    /// Django said "You have N unapplied migration(s)" while starting the server.
    private(set) var unappliedMigrations = 0
    private var serverLine: String?
    /// Where the current command's output begins in the terminal.
    private(set) var commandOutputStart = 0
    /// Commands to run one after another once the current one ends.
    private var queuedLines: [String] = []
    private(set) var completions: [PythonCompletion] = []
    private(set) var runLabel = ""

    private var autosave: Task<Void, Never>?
    private var lint: Task<Void, Never>?
    private var completion: Task<Void, Never>?
    private var completionToken = ""

    init(project: Project, session: RunSession? = nil) {
        self.project = project
        self.session = session ?? RunSession.shared
        terminalDirectory = project.url
        reloadTree()
        let root = tree
        if let first = Self.firstEntry(in: root) { open(first) }
        self.session.onProblems = { [weak self] token, path, problems in
            self?.receive(path: path, problems: problems, token: token)
        }
        self.session.onCompletions = { [weak self] token, items in
            guard let self, token == self.completionToken else { return }
            self.completions = items
        }
        self.session.onRunEnded = { [weak self] outcome in
            self?.runEnded(outcome)
        }
        refreshGit()
        PlaygroundRooms.shared.workspace = self
    }

    private static func firstEntry(in nodes: [FileNode]) -> String? {
        for name in ["main.py", "manage.py", "hello.py", "app.py"] {
            if nodes.contains(where: { $0.path == name }) { return name }
        }
        return nodes.first { !$0.isDirectory && !$0.name.hasPrefix(".") }?.path
    }

    func fileURL(_ path: String) -> URL {
        project.url.appending(path: path)
    }

    // MARK: Tree

    private nonisolated static let hidden: Set<String> = [".git", ".pythilo", "__pycache__", ".DS_Store"]

    func reloadTree() {
        tree = Self.scan(project.url, prefix: "")
        pruneOpenTabs()
        if djangoNames.isEmpty, let saved = try? Data(contentsOf: djangoCommandsURL),
           let pairs = try? JSONDecoder().decode([[String]].self, from: saved) {
            djangoNames = pairs.compactMap { $0.count == 2 ? (group: $0[0], name: $0[1]) : nil }
        }
        commands = ProjectCommands.detect(root: project.url, djangoNames: djangoNames)
    }

    private var djangoCommandsURL: URL { project.url.appending(path: ".pythilo/django-commands.json") }

    /// Django lists its commands when manage.py runs without one; from then on
    /// the terminal offers all of them, and remembers them for this project.
    func noticeCommandList(in text: String) {
        guard commands.framework == .django, let found = ProjectCommands.djangoCommands(in: text),
              found.map(\.name) != djangoNames.map(\.name) else { return }
        djangoNames = found
        commands = ProjectCommands.detect(root: project.url, djangoNames: found)
        try? FileManager.default.createDirectory(at: djangoCommandsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(found.map { [$0.group, $0.name] }).write(to: djangoCommandsURL)
    }

    /// A command chip: runs it in the terminal, or fills the input when the
    /// command needs a name typed after it.
    func use(_ command: ProjectCommands.Command) {
        panel = .terminal
        // A build runs beside a busy Python; anything else waits in the input.
        if command.needsArgument || (session.isBusy && !NpmScripts.handles(command.line)) {
            terminalDraft = command.line
        } else {
            runTerminal(command.line)
        }
    }

    private nonisolated static func scan(_ folder: URL, prefix: String) -> [FileNode] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        var nodes: [FileNode] = []
        for name in names where !hidden.contains(name) {
            let url = folder.appending(path: name)
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { continue }
            let path = prefix.isEmpty ? name : "\(prefix)/\(name)"
            nodes.append(
                FileNode(
                    path: path,
                    name: name,
                    isDirectory: isDirectory.boolValue,
                    children: isDirectory.boolValue ? scan(url, prefix: path) : []
                )
            )
        }
        return nodes.sorted {
            if $0.isDirectory != $1.isDirectory { return $0.isDirectory }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    private func pruneOpenTabs() {
        let fm = FileManager.default
        for path in tabs where !fm.fileExists(atPath: fileURL(path).path) {
            close(path, saving: false)
        }
    }

    /// Creates a file or folder. Slashes in the path make the folders on the way.
    @discardableResult
    func create(path: String, in folder: String?, isDirectory: Bool, contents: String = "") throws -> String {
        let clean = path.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "/")))
        guard !clean.isEmpty, !clean.split(separator: "/").contains("..") else {
            throw WorkspaceFailure("Enter a name inside this project.")
        }
        let relative = folder.map { "\($0)/\(clean)" } ?? clean
        let url = fileURL(relative)
        guard !FileManager.default.fileExists(atPath: url.path) else {
            throw WorkspaceFailure("\(relative) already exists.")
        }
        if isDirectory {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        } else {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try contents.write(to: url, atomically: true, encoding: .utf8)
        }
        var ancestor = relative
        while ancestor.contains("/") {
            ancestor = (ancestor as NSString).deletingLastPathComponent
            expanded.insert(ancestor)
        }
        if isDirectory { expanded.insert(relative) }
        reloadTree()
        if !isDirectory { open(relative) }
        refreshGit()
        return relative
    }

    func rename(_ path: String, to name: String) throws {
        let target = ((path as NSString).deletingLastPathComponent as NSString).appendingPathComponent(name)
        try move(path, to: target)
    }

    func move(_ path: String, to target: String) throws {
        let clean = target.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !clean.isEmpty, !clean.split(separator: "/").contains("..") else {
            throw WorkspaceFailure("Enter a path inside this project.")
        }
        guard !FileManager.default.fileExists(atPath: fileURL(clean).path) else {
            throw WorkspaceFailure("\(clean) already exists.")
        }
        saveAll()
        try FileManager.default.createDirectory(at: fileURL(clean).deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: fileURL(path), to: fileURL(clean))
        for old in tabs where old == path || old.hasPrefix(path + "/") {
            let moved = clean + old.dropFirst(path.count)
            if let index = tabs.firstIndex(of: old) { tabs[index] = moved }
            buffers[moved] = buffers.removeValue(forKey: old)
            savedText[moved] = savedText.removeValue(forKey: old)
            breakpoints[moved] = breakpoints.removeValue(forKey: old)
            if selectedPath == old { selectedPath = moved }
        }
        reloadTree()
        refreshGit()
    }

    func duplicate(_ path: String) throws {
        saveAll()
        let source = path as NSString
        let stem = (source.lastPathComponent as NSString).deletingPathExtension
        let suffix = source.pathExtension.isEmpty ? "" : ".\(source.pathExtension)"
        var copy = (source.deletingLastPathComponent as NSString).appendingPathComponent("\(stem) copy\(suffix)")
        var number = 2
        while FileManager.default.fileExists(atPath: fileURL(copy).path) {
            copy = (source.deletingLastPathComponent as NSString).appendingPathComponent("\(stem) copy \(number)\(suffix)")
            number += 1
        }
        try FileManager.default.copyItem(at: fileURL(path), to: fileURL(copy))
        reloadTree()
        refreshGit()
    }

    func delete(_ path: String) throws {
        for tab in tabs where tab == path || tab.hasPrefix(path + "/") {
            close(tab, saving: false)
        }
        try FileManager.default.removeItem(at: fileURL(path))
        reloadTree()
        refreshGit()
    }

    func toggle(folder path: String) {
        if expanded.contains(path) { expanded.remove(path) } else { expanded.insert(path) }
    }

    // MARK: Buffers

    func open(_ path: String, line: Int? = nil) {
        if buffers[path] == nil, !isNotebook(path) {
            guard let data = try? Data(contentsOf: fileURL(path)),
                  let text = String(data: data, encoding: .utf8) else {
                if !tabs.contains(path) { tabs.append(path) }
                selectedPath = path
                panel = .code
                return
            }
            buffers[path] = text
            savedText[path] = text
        }
        if !tabs.contains(path) { tabs.append(path) }
        selectedPath = path
        panel = .code
        completions = []
        checkSelected()
        if let line {
            navigation = EditorNavigationTarget(filePath: path, line: line, column: 1)
        }
    }

    func isNotebook(_ path: String) -> Bool {
        path.lowercased().hasSuffix(".ipynb")
    }

    func isText(_ path: String) -> Bool {
        buffers[path] != nil
    }

    func isUnsaved(_ path: String) -> Bool {
        guard let text = buffers[path] else { return false }
        return text != savedText[path]
    }

    func close(_ path: String, saving: Bool = true) {
        if saving { save(path) }
        tabs.removeAll { $0 == path }
        buffers[path] = nil
        savedText[path] = nil
        if selectedPath == path { selectedPath = tabs.last }
    }

    func text(_ path: String) -> String {
        buffers[path] ?? ""
    }

    func setText(_ text: String, for path: String) {
        guard buffers[path] != text else { return }
        buffers[path] = text
        PlaygroundRooms.shared.edited(project: project, path: path, text: text)
        scheduleAutosave()
        scheduleLint(path)
    }

    func save(_ path: String) {
        guard let text = buffers[path], text != savedText[path] else { return }
        do {
            try text.write(to: fileURL(path), atomically: true, encoding: .utf8)
            savedText[path] = text
            if bundleWatch != nil, ["js", "jsx", "ts", "tsx", "mjs", "css", "json"].contains((path as NSString).pathExtension) {
                scheduleRebuild()
            }
        } catch {
            session.note("Could not save \(path): \(error.localizedDescription)\n")
        }
    }

    /// `npm run dev` leaves this set: every save of a script or stylesheet rebuilds.
    var bundleWatch: NpmScripts.Build?
    private var rebuild: Task<Void, Never>?

    private func scheduleRebuild() {
        rebuild?.cancel()
        rebuild = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard let self, !Task.isCancelled, let build = self.bundleWatch else { return }
            self.session.noteTerminal("Rebuilding after a save…\n", kind: .stdout)
            await NpmScripts.bundle(build, in: self)
        }
    }

    func saveAll() {
        for path in buffers.keys { save(path) }
    }

    private func scheduleAutosave() {
        autosave?.cancel()
        autosave = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            self?.saveAll()
            self?.refreshGit()
        }
    }

    // MARK: Analysis

    private func scheduleLint(_ path: String) {
        lint?.cancel()
        lint = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            self?.check(path)
        }
    }

    func checkSelected() {
        if let selectedPath { check(selectedPath) }
    }

    private func check(_ path: String) {
        guard path.hasSuffix(".py"), let source = buffers[path] else { return }
        session.analyze(["action": "check", "token": "lint", "path": path, "source": source])
    }

    private func receive(path: String, problems: [PythonProblem], token: String) {
        guard token == "lint" else { return }
        lintProblems[path] = problems.map {
            WorkspaceProblem(path: path, line: $0.line, column: $0.column, severity: $0.severity, message: $0.message, source: $0.code == "syntax" ? "Python" : "pyflakes")
        }
    }

    var problems: [WorkspaceProblem] {
        runProblems + lintProblems.keys.sorted().flatMap { lintProblems[$0] ?? [] }
    }

    func diagnostics(for path: String) -> [EditorDiagnostic] {
        (lintProblems[path] ?? []).map { problem in
            let id = UUID(uuidString: "00000000-0000-0000-0000-\(String(format: "%012x", abs(problem.id.hashValue) % 0xFFFF_FFFF_FFFF))") ?? UUID()
            return EditorDiagnostic(
                id: id,
                level: problem.severity,
                message: problem.message,
                spans: [
                    EditorDiagnostic.Span(
                        fileName: path,
                        lineStart: problem.line,
                        lineEnd: problem.line,
                        columnStart: problem.column + 1,
                        columnEnd: problem.column + 2,
                        isPrimary: true,
                        label: nil,
                        sourceLine: ""
                    )
                ]
            )
        }
    }

    func requestCompletions() {
        completion?.cancel()
        guard let path = selectedPath, path.hasSuffix(".py"), let source = buffers[path] else {
            completions = []
            return
        }
        let offset = cursorOffset
        completion = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled, let self else { return }
            let text = source as NSString
            guard offset > 0, offset <= text.length else {
                self.completions = []
                return
            }
            let before = text.substring(with: NSRange(location: offset - 1, length: 1))
            guard before == "." || before.rangeOfCharacter(from: .alphanumerics) != nil || before == "_" else {
                self.completions = []
                return
            }
            let head = text.substring(to: offset)
            let lines = head.components(separatedBy: "\n")
            let token = UUID().uuidString
            self.completionToken = token
            self.session.analyze([
                "action": "complete",
                "token": token,
                "source": source,
                "path": self.fileURL(path).path,
                "root": self.project.url.path,
                "line": lines.count,
                "column": (lines.last ?? "" as String).utf16.count,
            ])
        }
    }

    func clearCompletions() {
        completion?.cancel()
        completionToken = ""
        completions = []
    }

    func acceptCompletion(_ item: PythonCompletion) {
        guard let path = selectedPath, var text = buffers[path] else { return }
        let index = String.Index(utf16Offset: min(cursorOffset, text.utf16.count), in: text)
        text.insert(contentsOf: item.insert, at: index)
        cursorOffset += item.insert.utf16.count
        setText(text, for: path)
        clearCompletions()
    }

    // MARK: Running

    func runSelected() {
        saveAll()
        guard let path = runnablePath else {
            session.note("Open a Python file to run it.\n")
            panel = .output
            return
        }
        runProblems = []
        session.clearOutput()
        panel = .output
        runLabel = path
        session.submit(
            ["kind": "script", "path": fileURL(path).path, "root": project.url.path, "cwd": project.url.path],
            label: path
        )
    }

    func debugSelected() {
        saveAll()
        guard let path = runnablePath else { return }
        runProblems = []
        session.clearOutput()
        runLabel = path
        panel = .debug
        var absolute: [String: [Int]] = [:]
        for (file, lines) in breakpoints where !lines.isEmpty {
            absolute[fileURL(file).path] = Array(lines)
        }
        session.submit(
            ["kind": "debug", "path": fileURL(path).path, "root": project.url.path, "cwd": project.url.path, "breakpoints": absolute],
            label: path
        )
    }

    /// The iOS keyboard turns `--` into a dash and straight quotes into curly
    /// ones, which no command understands. A dash that starts a word was two
    /// hyphens; curly double quotes come in pairs, so they can be put back too.
    static func plainCommand(_ line: String) -> String {
        var text = line.replacingOccurrences(of: "\u{201C}", with: "\"").replacingOccurrences(of: "\u{201D}", with: "\"")
        text = text.replacingOccurrences(of: #"(^|\s)[\x{2014}\x{2013}]"#, with: "$1--", options: .regularExpression)
        return text
    }

    private var runnablePath: String? {
        if let selectedPath, selectedPath.hasSuffix(".py") { return selectedPath }
        return Self.firstEntry(in: tree).flatMap { $0.hasSuffix(".py") ? $0 : nil }
    }

    func runTerminal(_ line: String) {
        let trimmed = Self.plainCommand(line).trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        saveAll()
        session.noteTerminal("\(terminalDirectory.lastPathComponent) $ \(trimmed)\n", kind: .input)
        if trimmed == "clear" {
            session.clearTerminal()
            return
        }
        if trimmed == "git" || trimmed.hasPrefix("git ") {
            Task { await GitTerminal.run(trimmed, in: self) }
            return
        }
        // Builds run in a web view, not in Python, so they work beside a running server.
        if NpmScripts.handles(trimmed) {
            Task { await NpmScripts.run(trimmed, in: self) }
            return
        }
        guard session.phase == .idle || session.phase == .starting else {
            // Python runs one program at a time. A server started here is stopped,
            // the command runs, and the server starts again, as after a migration.
            if session.listening != nil, session.activeChannel == .terminal, let server = serverLine {
                session.noteTerminal("Stopping the server to run this; it starts again afterwards.\n")
                queuedLines = trimmed == server ? [server] : [trimmed, server]
                session.stop()
                return
            }
            session.noteTerminal("Python is busy. Stop the running program first.\n", kind: .stderr)
            return
        }
        unappliedMigrations = 0
        serverLine = trimmed
        commandOutputStart = session.terminalOutput.count
        session.submit(
            ["kind": "shell", "line": trimmed, "root": project.url.path, "cwd": terminalDirectory.path],
            label: trimmed,
            channel: .terminal
        )
    }

    func openREPL() {
        runTerminal("python")
    }

    /// Stops the server, applies the migrations Django listed, then starts the
    /// same command again.
    func migrateAndRestart() {
        guard let line = serverLine else { return }
        queuedLines = ["python manage.py migrate", line]
        session.stop()
    }

    private func runEnded(_ outcome: RunOutcome) {
        if !queuedLines.isEmpty {
            let next = queuedLines.removeFirst()
            // The stopped server ends as cancelled; any other failure, such as a
            // migrate that fails, stays on screen instead of going on.
            let failed = outcome.code != 0 && outcome.status != "cancelled"
            if failed { queuedLines = [] } else {
                Task { @MainActor [weak self] in self?.runTerminal(next) }
            }
        }
        if session.activeChannel == .terminal, let cwd = outcome.cwd {
            let url = URL(fileURLWithPath: cwd)
            if url.path.hasPrefix(project.url.resolvingSymlinksInPath().path) || url.path.hasPrefix(project.url.path) {
                terminalDirectory = url
            }
            session.noteTerminal(outcome.code == 0 ? "" : "[exit \(outcome.code)]\n")
        }
        if let error = outcome.error, let file = error.file {
            let root = project.url.resolvingSymlinksInPath().path + "/"
            let path = file.hasPrefix(root) ? String(file.dropFirst(root.count)) : (file as NSString).lastPathComponent
            runProblems = [
                WorkspaceProblem(path: path, line: error.line, column: 0, severity: "error", message: "\(error.type): \(error.message)", source: "last run")
            ]
        }
        if session.activeChannel == .output {
            let seconds = String(format: "%.2f", outcome.duration ?? 0)
            switch outcome.status {
            case "cancelled": session.note("\nStopped after \(seconds) s\n")
            case "failed": session.note("\nExited with code \(outcome.code) after \(seconds) s\n")
            default: session.note("\nFinished in \(seconds) s\n")
            }
            if let threads = outcome.threads, !threads.isEmpty {
                session.note("Still running in the background: \(threads.joined(separator: ", ")). Python keeps them until the app closes.\n")
            }
        }
        reloadTree()
        reloadChangedBuffers()
        refreshGit()
    }

    /// A program, pip or Git can change files that are open in tabs.
    func reloadChangedBuffers() {
        for path in buffers.keys where !isUnsaved(path) {
            guard let data = try? Data(contentsOf: fileURL(path)),
                  let text = String(data: data, encoding: .utf8), text != buffers[path] else { continue }
            buffers[path] = text
            savedText[path] = text
        }
    }

    /// A shared room wrote these files. Open tabs take the room's text as saved text.
    func roomChanged(_ files: [String: String], treeChanged: Bool) {
        for (path, text) in files where buffers[path] != nil {
            if buffers[path] != text { buffers[path] = text }
            savedText[path] = text
        }
        if treeChanged { reloadTree() }
        if let selectedPath, files[selectedPath] != nil { scheduleLint(selectedPath) }
    }

    /// The address of the server the project started. The runtime reports the
    /// socket it listens on; a printed address is the fallback, and also keeps
    /// a path the program printed, such as /admin/.
    func updatePreview(from text: String) {
        guard let match = text.firstMatch(of: /http:\/\/(?:127\.0\.0\.1|localhost|0\.0\.0\.0|\[::\]):\d+[^\s"']*/) else { return }
        let address = String(match.0).replacingOccurrences(of: "0.0.0.0", with: "127.0.0.1").replacingOccurrences(of: "[::]", with: "127.0.0.1")
        previewURL = URL(string: address)
    }

    func noticeMigrationWarning(in text: String) {
        guard serverLine?.contains("runserver") == true, unappliedMigrations == 0, let match = text.firstMatch(of: /You have (\d+) unapplied migration/), let count = Int(match.1) else { return }
        unappliedMigrations = count
    }

    func serverStarted(_ server: ListeningServer?) {
        guard let url = server?.url else { return }
        if previewURL?.port != url.port { previewURL = url }
    }

    func clearPreview() {
        previewURL = nil
        previewOpen = false
    }

    // MARK: Git

    var repository: ProjectRepository {
        ProjectRepository(worktree: project.url)
    }

    func refreshGit() {
        let repository = repository
        Task { [weak self] in
            let snapshot = await Task.detached { repository.exists ? try? repository.snapshot() : nil }.value
            self?.gitSnapshot = snapshot
        }
    }
}

struct WorkspaceFailure: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
