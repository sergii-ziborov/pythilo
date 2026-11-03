import Foundation
import UIKit

/// One shared check, run or test on the embedded interpreter, against an isolated copy
/// of the room's files: no local-only file, package or setting reaches the result.
@MainActor
struct PlaygroundPythonJob {
    enum Operation: String, Sendable {
        case check, run, test
    }

    struct Result: Sendable {
        var status: String
        var exitCode: Int?
        var stdout = ""
        var stderr = ""
        var diagnostics: [Diagnostic] = []
        var started: Date
        var duration: TimeInterval
        var truncated = false

        var succeeded: Bool { status == "finished" && exitCode == 0 }
    }

    struct Diagnostic: Sendable, Equatable {
        let file: Int
        let line: Int
        let column: Int
        let level: String
        let message: String
    }

    static let timeLimit: TimeInterval = 120

    let operation: Operation
    let document: PlaygroundDocument
    let paths: [String]
    let folder: URL

    /// What the owner is asked to allow, as a command line.
    static func command(_ operation: String, entryFile: String) -> String {
        switch operation {
        case "run": "python \(entryFile)"
        case "test": "pytest -q"
        default: "compile and pyflakes"
        }
    }

    static func folder(room: String) -> URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appending(path: "PythiloRooms/\(room)")
    }

    func execute(session: RunSession = .shared, isCancelled: @escaping @MainActor () -> Bool,
                 onOutput: @escaping @MainActor (String, String) -> Void) async -> Result {
        let started = Date()
        switch operation {
        case .check:
            var diagnostics: [Diagnostic] = []
            var lines: [String] = []
            for (index, path) in paths.enumerated() where path.hasSuffix(".py") {
                if isCancelled() { break }
                let problems = (try? await MCPTools.check(document.files[path] ?? "", path: path)) ?? []
                for problem in problems.prefix(max(0, 64 - diagnostics.count)) {
                    let line = problem["line"] as? Int ?? 0, column = problem["column"] as? Int ?? 0
                    let level = problem["severity"] as? String ?? "error", message = problem["message"] as? String ?? ""
                    diagnostics.append(Diagnostic(file: index, line: line, column: column, level: level, message: message))
                    lines.append("\(path):\(line):\(column + 1): \(level): \(message)")
                }
            }
            let failed = diagnostics.contains { $0.level == "error" }
            return Result(status: isCancelled() ? "cancelled" : failed ? "failed" : "finished", exitCode: failed ? 1 : 0,
                          stdout: lines.joined(separator: "\n") + (lines.isEmpty ? "" : "\n"), diagnostics: diagnostics,
                          started: started, duration: Date().timeIntervalSince(started))
        case .run, .test:
            do {
                try prepareFolder()
            } catch {
                return Result(status: "error", exitCode: nil, stderr: "Could not prepare the shared files: \(error.localizedDescription)\n", started: started, duration: 0)
            }
            guard session.phase == .idle else {
                return Result(status: "error", exitCode: nil, stderr: "Python is busy on this device. Nothing ran.\n", started: started, duration: 0)
            }
            session.clearOutput()
            session.note("Room · \(Self.command(operation.rawValue, entryFile: document.entryFile))\n")
            let job: [String: Any] = operation == .run
                ? ["kind": "script", "path": folder.appending(path: document.entryFile).path, "root": folder.path, "cwd": folder.path]
                : ["kind": "shell", "line": "pytest -q", "root": folder.path, "cwd": folder.path]
            guard let id = session.submit(job, label: "Room · \(operation == .run ? document.entryFile : "pytest")") else {
                return Result(status: "error", exitCode: nil, stderr: "Python is busy on this device. Nothing ran.\n", started: started, duration: 0)
            }
            let deadline = started.addingTimeInterval(Self.timeLimit)
            var timedOut = false
            var lastRevision = -1
            while session.lastOutcome?.id != id {
                if (isCancelled() || Date() > deadline), session.phase != .cancelling, session.phase != .unresponsive, session.isBusy {
                    timedOut = Date() > deadline
                    session.stop()
                }
                if session.outputRevision != lastRevision {
                    lastRevision = session.outputRevision
                    let output = Self.output(session)
                    onOutput(output.stdout, output.stderr)
                }
                if session.phase == .unresponsive { break }
                try? await Task.sleep(for: .milliseconds(250))
            }
            let output = Self.output(session)
            let outcome = session.lastOutcome?.id == id ? session.lastOutcome : nil
            var status = outcome?.status ?? "cancelled"
            if timedOut { status = "timeout" }
            return Result(status: status, exitCode: outcome?.code, stdout: output.stdout, stderr: output.stderr, started: started,
                          duration: outcome?.duration ?? Date().timeIntervalSince(started), truncated: session.droppedCharacters > 0)
        }
    }

    private func prepareFolder() throws {
        try? FileManager.default.removeItem(at: folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try PlaygroundProjectFiles.write(document, to: folder, removing: [])
    }

    private static func output(_ session: RunSession) -> (stdout: String, stderr: String) {
        var stdout = "", stderr = ""
        for chunk in session.output {
            switch chunk.kind {
            case .stdout: stdout += chunk.text
            case .stderr: stderr += chunk.text
            default: break
            }
        }
        return (stdout, stderr)
    }
}
