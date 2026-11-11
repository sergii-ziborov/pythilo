import Foundation
import Observation

/// One terminal tab in a project: its own folder, history, prompt and output.
///
/// A tab's command runs on Python's main thread when that is free, and otherwise on
/// one of the lanes beside it, so a server in one tab never blocks another tab.
@MainActor
@Observable
final class TerminalTab: Identifiable, TerminalOutputSink {
    let id = UUID()
    let number: Int
    private(set) var buffer = OutputBuffer()
    var directory: URL
    /// Kept with the tab so a new layout cannot discard the prompt.
    var input = ""
    var history: [String] = []
    var historyIndex: Int?
    /// Text a chip puts into the input for the user to finish.
    var draft: String?
    /// Where the running command is: 0 is the main thread. nil when the prompt is free.
    fileprivate(set) var lane: Int?
    fileprivate(set) var jobID: String?
    /// The command running now, or the last one.
    fileprivate(set) var command: String?
    /// The command that started this tab's server, so it can start again after a migration.
    var serverLine: String?
    /// Commands to run one after another once the current one ends.
    var queuedLines: [String] = []
    /// Where the current command's output begins.
    fileprivate(set) var commandOutputStart = 0
    /// Django said "You have N unapplied migration(s)" while starting the server.
    var unappliedMigrations = 0
    /// A migrate in any tab has since applied them; the old warning stays in the log.
    var migrationsApplied = false

    init(number: Int, directory: URL) {
        self.number = number
        self.directory = directory
    }

    var output: [OutputChunk] { buffer.chunks }
    var revision: Int { buffer.revision }

    /// Told after new output lands, to look for a server's address or Django's warnings.
    var onOutput: ((TerminalTab) -> Void)?

    func appendOutput(_ kind: OutputChunk.Kind, _ text: String) {
        buffer.append(kind, text)
        onOutput?(self)
    }

    func clear() {
        buffer.clear()
        commandOutputStart = 0
    }

    /// The tab's name: its number, then what runs in it.
    var title: String {
        guard lane != nil, let command else { return "Terminal \(number)" }
        let words = command.split(separator: " ")
        if let index = words.firstIndex(where: { ["runserver", "run"].contains($0) }), index > 0 {
            return "\(number) · \(words[index])"
        }
        // python file.py → file.py, python -m pytest → pytest, python -c "…" → python.
        var program = words.first.map(String.init) ?? ""
        if ["python", "python3"].contains(program), words.count > 1 {
            if words[1] == "-m", words.count > 2 { program = String(words[2]) }
            else if !words[1].hasPrefix("-") { program = String(words[1]) }
        }
        return "\(number) · \((program as NSString).lastPathComponent)"
    }

    func began(_ line: String, lane: Int, id: String) {
        self.lane = lane
        jobID = id
        command = line
        commandOutputStart = buffer.chunks.count
        migrationsApplied = false
    }

    func ended() {
        lane = nil
        jobID = nil
    }
}
