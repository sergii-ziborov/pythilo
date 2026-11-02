import CryptoKit
import Foundation

@MainActor
enum MCPTools {
    private static func tool(_ name: String, _ description: String, _ properties: [String: [String: Any]] = [:], required: [String] = [], readOnly: Bool = false) -> [String: Any] {
        [
            "name": name,
            "description": description,
            "inputSchema": ["type": "object", "properties": properties, "required": required],
            "annotations": ["readOnlyHint": readOnly],
        ]
    }

    static let definitions: [[String: Any]] = [
        tool("capabilities", "What this device can run, and which actions the user allows. Call this first.", readOnly: true),
        tool("list_files", "List the shared project's files.", readOnly: true),
        tool("read_file", "Read a text file. Returns its revision, which write_file needs.", ["path": ["type": "string"]], required: ["path"], readOnly: true),
        tool("write_file", "Create or replace a text file. An existing file needs expected_revision from read_file, and a stale revision is a conflict that writes nothing.", ["path": ["type": "string"], "text": ["type": "string"], "expected_revision": ["type": "string"]], required: ["path", "text"]),
        tool("diagnostics", "Syntax errors and pyflakes findings for a Python file.", ["path": ["type": "string"]], required: ["path"], readOnly: true),
        tool("run", "Run a Python file on the device. Returns its output, exit code, and where it ran. May ask the user first.", ["path": ["type": "string"], "timeout_seconds": ["type": "number"]], required: ["path"]),
        tool("test", "Run pytest on the device. May ask the user first.", ["args": ["type": "string"], "timeout_seconds": ["type": "number"]]),
        tool("stop", "Ask the running code to stop. Reports the real state afterwards through output."),
        tool("output", "The current run's phase and output.", readOnly: true),
        tool("package_install", "Install a pure-Python package into this project. Compiled packages only work if the app bundles them. May ask the user first.", ["package": ["type": "string"]], required: ["package"]),
        tool("git_status", "Branch, head and changed files.", readOnly: true),
        tool("git_diff", "Unified diff of the working folder against HEAD.", ["path": ["type": "string"]], readOnly: true),
        tool("git_commit", "Stage all changes and commit. May ask the user first.", ["message": ["type": "string"]], required: ["message"]),
        tool("git_push", "Push the current branch to origin. Off unless the user allows it."),
    ]

    private nonisolated static let hidden: Set<String> = [".git", ".pythilo", "__pycache__", ".DS_Store"]

    static func listFiles(in root: URL) -> [String] {
        var result: [String] = []
        let base = root.resolvingSymlinksInPath().path + "/"
        guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey]) else { return [] }
        for case let url as URL in walker {
            if hidden.contains(url.lastPathComponent) {
                walker.skipDescendants()
                continue
            }
            if (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true {
                let full = url.resolvingSymlinksInPath().path
                result.append(full.hasPrefix(base) ? String(full.dropFirst(base.count)) : url.lastPathComponent)
            }
            if result.count >= 5000 { break }
        }
        return result.sorted()
    }

    /// Every path stays inside the project and out of Pythilo's own folders.
    static func safePath(_ value: Any?, root: URL) throws -> String {
        guard let raw = value as? String, !raw.isEmpty else { throw MCPFailure("path is required.") }
        let parts = raw.split(separator: "/")
        guard !raw.hasPrefix("/"), !parts.contains(".."), !parts.contains(where: { hidden.contains(String($0)) }) else {
            throw MCPFailure("\(raw) is outside the shared project.")
        }
        let target = root.appending(path: raw).standardizedFileURL.path
        guard target.hasPrefix(root.standardizedFileURL.path + "/") else {
            throw MCPFailure("\(raw) is outside the shared project.")
        }
        return parts.joined(separator: "/")
    }

    static func revision(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).prefix(12).map { String(format: "%02x", $0) }.joined()
    }

    static func outputText(limit: Int = 40_000) -> String {
        let text = RunSession.shared.output.map(\.text).joined()
        return text.count > limit ? "[earlier output trimmed]\n" + text.suffix(limit) : text
    }

    static func check(_ source: String, path: String) async throws -> [[String: Any]] {
        let token = UUID().uuidString
        let session = RunSession.shared
        let previous = session.onProblems
        defer { session.onProblems = previous }
        let problems: [PythonProblem] = await withCheckedContinuation { continuation in
            var resumed = false
            session.onProblems = { received, receivedPath, found in
                if received == token, !resumed {
                    resumed = true
                    continuation.resume(returning: found)
                } else {
                    previous?(received, receivedPath, found)
                }
            }
            session.analyze(["action": "check", "token": token, "path": path, "source": source])
        }
        return problems.map { ["line": $0.line, "column": $0.column, "severity": $0.severity, "message": $0.message] }
    }
}
