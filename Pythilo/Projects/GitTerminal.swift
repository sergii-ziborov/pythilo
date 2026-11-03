import Foundation
import PythiloGit

/// `git` typed in the terminal. Each subcommand maps onto libgit2; anything else
/// says it is not available instead of pretending.
@MainActor
enum GitTerminal {
    static var author: String { UserDefaults.standard.string(forKey: "pythilo.gitName") ?? "" }
    static var email: String { UserDefaults.standard.string(forKey: "pythilo.gitEmail") ?? "" }

    static func run(_ line: String, in model: WorkspaceModel) async {
        let session = model.session
        let words = split(line)
        let repository = model.repository
        do {
            let text = try await perform(Array(words.dropFirst()), repository: repository, model: model)
            if !text.isEmpty { session.noteTerminal(text.hasSuffix("\n") ? text : text + "\n", kind: .stdout) }
        } catch {
            session.noteTerminal("git: \(error.localizedDescription)\n", kind: .stderr)
        }
        model.reloadTree()
        model.reloadChangedBuffers()
        model.refreshGit()
    }

    /// Splits like a shell, so a commit message can be quoted.
    static func split(_ line: String) -> [String] {
        var words: [String] = []
        var current = ""
        var quote: Character?
        var hasWord = false
        for character in line {
            if let active = quote {
                if character == active { quote = nil } else { current.append(character) }
            } else if character == "\"" || character == "'" {
                quote = character
                hasWord = true
            } else if character == " " {
                if hasWord || !current.isEmpty { words.append(current) }
                current = ""
                hasWord = false
            } else {
                current.append(character)
            }
        }
        if hasWord || !current.isEmpty { words.append(current) }
        return words
    }

    private static func perform(_ args: [String], repository: ProjectRepository, model: WorkspaceModel) async throws -> String {
        guard let command = args.first else { return usage }
        let rest = Array(args.dropFirst())
        switch command {
        case "init":
            try repository.initialize()
            return "Initialized a Git repository on main."
        case "status":
            var text = describe(try repository.snapshot())
            if repository.isMerging {
                text += "\nMerging. Fix the conflicted files, git add them, then git commit. git merge --abort undoes the merge."
            }
            return text
        case "add":
            let all = rest.isEmpty || rest.contains(".") || rest.contains("-A")
            try repository.stage(all ? [] : rest)
            return ""
        case "reset", "restore":
            let paths = rest.filter { !$0.hasPrefix("-") && $0 != "HEAD" }
            try repository.unstage(paths)
            return ""
        case "commit":
            guard let flag = rest.firstIndex(of: "-m"), flag + 1 < rest.count else {
                throw GitFailure("Use git commit -m \"message\".")
            }
            let commit = try repository.commit(message: rest[flag + 1], author: author, email: email)
            return "[\(try repository.snapshot().branch) \(commit.shortID)] \(commit.message)"
        case "log":
            let commits = try repository.history(limit: 30)
            return commits.map { "\($0.shortID) \($0.message)  (\($0.author))" }.joined(separator: "\n")
        case "diff":
            return try repository.diff(path: rest.first)
        case "branch":
            if let name = rest.first, !name.hasPrefix("-") {
                try repository.createBranch(name)
                return ""
            }
            let current = try repository.snapshot().branch
            return try repository.branches().map { ($0 == current ? "* " : "  ") + $0 }.joined(separator: "\n")
        case "switch", "checkout":
            var names = rest
            if names.first == "-c" || names.first == "-b" {
                names.removeFirst()
                guard let name = names.first else { throw GitFailure("Name the new branch.") }
                try repository.createBranch(name)
            }
            guard let name = names.first else { throw GitFailure("Name a branch.") }
            model.saveAll()
            try repository.switchBranch(name)
            return "Switched to \(name)."
        case "merge":
            if rest.first == "--abort" {
                try repository.abortMerge()
                return "Merge aborted. Tracked files are back as they were at the last commit."
            }
            guard let name = rest.first(where: { !$0.hasPrefix("-") }) else {
                throw GitFailure("Name the branch to merge, for example git merge feature.")
            }
            model.saveAll()
            let outcome = try repository.merge(name, author: author, email: email)
            return ([outcome.message] + outcome.conflicts.map { "  both modified: \($0)" }).joined(separator: "\n")
        case "rebase":
            guard let name = rest.first(where: { !$0.hasPrefix("-") }) else {
                throw GitFailure("Name the branch to replay onto, for example git rebase main.")
            }
            model.saveAll()
            return try repository.rebase(onto: name, author: author, email: email)
        case "remote":
            if rest.first == "add" || rest.first == "set-url", rest.count >= 3 {
                try repository.setRemote(url: rest[2])
                return ""
            }
            return try repository.snapshot().remoteURL.map { "origin  \($0)" } ?? ""
        case "fetch", "pull", "push":
            let address = try repository.snapshot().remoteURL
            let credential = GitCredentialVault.credential(for: address)
            return try await Task.detached { () throws -> String in
                switch command {
                case "fetch":
                    try repository.fetch(credential: credential)
                    return "Fetched origin."
                case "pull":
                    return try repository.pull(credential: credential)
                default:
                    return try repository.push(credential: credential)
                }
            }.value
        case "config":
            if rest.count == 2, rest[0] == "user.name" {
                UserDefaults.standard.set(rest[1], forKey: "pythilo.gitName")
                return ""
            }
            if rest.count == 2, rest[0] == "user.email" {
                UserDefaults.standard.set(rest[1], forKey: "pythilo.gitEmail")
                return ""
            }
            throw GitFailure("git config handles user.name and user.email here.")
        case "--version", "version":
            return "Pythilo Git, libgit2 1.9.7"
        default:
            throw GitFailure("\(command) is not available here. \(usage)")
        }
    }

    private static let usage = "Available: init status add reset commit log diff branch switch merge rebase remote fetch pull push config"

    static func describe(_ snapshot: GitSnapshot) -> String {
        var lines = ["On branch \(snapshot.branch)"]
        if let ahead = snapshot.ahead, let behind = snapshot.behind, ahead + behind > 0 {
            lines.append("\(ahead) ahead and \(behind) behind origin/\(snapshot.branch)")
        }
        let staged = snapshot.changes.filter(\.staged)
        let unstaged = snapshot.changes.filter { !$0.staged && $0.kind != .untracked || $0.unstaged && $0.kind != .untracked }
        let untracked = snapshot.changes.filter { $0.kind == .untracked }
        if !staged.isEmpty {
            lines.append("Staged:")
            lines += staged.map { "  \($0.kind.rawValue): \($0.path)" }
        }
        if !unstaged.isEmpty {
            lines.append("Not staged:")
            lines += unstaged.map { "  \($0.kind.rawValue): \($0.path)" }
        }
        if !untracked.isEmpty {
            lines.append("Untracked:")
            lines += untracked.map { "  \($0.path)" }
        }
        if snapshot.changes.isEmpty { lines.append("Nothing to commit, working tree clean.") }
        return lines.joined(separator: "\n")
    }
}
