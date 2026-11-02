import Foundation
@preconcurrency import CLibgit2

public struct GitFailure: LocalizedError, Sendable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

public struct GitCredential: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    let username: String
    let token: String
    public init(username: String, token: String) {
        self.username = username
        self.token = token
    }
    public var description: String { "GitCredential(<redacted>)" }
    public var debugDescription: String { description }
}

public struct GitFileChange: Identifiable, Sendable, Equatable {
    public enum Kind: String, Sendable { case added, modified, deleted, renamed, conflicted, untracked }
    public let path: String
    public let kind: Kind
    public let staged: Bool
    public let unstaged: Bool
    public var id: String { path }
}

public struct GitSnapshot: Sendable, Equatable {
    public let branch: String
    public let head: String?
    public let changes: [GitFileChange]
    public let remoteURL: String?
    public let ahead: Int?
    public let behind: Int?
}

public struct GitCommitSummary: Identifiable, Sendable, Equatable {
    public let id: String
    public let message: String
    public let author: String
    public let date: Date
    public var shortID: String { String(id.prefix(8)) }
}

/// One repository, opened for each call. The worktree is the project folder.
public struct ProjectRepository: Sendable {
    public let worktree: URL

    private static let ready: Int32 = {
        let status = git_libgit2_init()
        return status < 0 ? status : pythilo_git_network_limits()
    }()

    public init(worktree: URL) {
        self.worktree = worktree
    }

    public var exists: Bool {
        FileManager.default.fileExists(atPath: worktree.appending(path: ".git/HEAD").path)
    }

    @discardableResult
    private static func check(_ result: Int32) throws -> Int32 {
        guard result >= 0 else {
            if let error = git_error_last(), let pointer = error.pointee.message {
                throw GitFailure(String(cString: pointer))
            }
            throw GitFailure("Git operation failed.")
        }
        return result
    }

    private func open<T>(_ body: (OpaquePointer) throws -> T) throws -> T {
        try Self.check(Self.ready)
        guard exists else { throw GitFailure("This project has no Git repository yet. Run git init.") }
        var repository: OpaquePointer?
        try Self.check(git_repository_open(&repository, worktree.path))
        guard let repository else { throw GitFailure("Could not open the repository.") }
        defer { git_repository_free(repository) }
        return try body(repository)
    }

    public func initialize(initialBranch: String = "main") throws {
        try Self.check(Self.ready)
        var options = git_repository_init_options()
        try Self.check(git_repository_init_options_init(&options, UInt32(GIT_REPOSITORY_INIT_OPTIONS_VERSION)))
        options.flags = UInt32(GIT_REPOSITORY_INIT_MKPATH.rawValue)
        var repository: OpaquePointer?
        try initialBranch.withCString { name in
            options.initial_head = name
            try Self.check(git_repository_init_ext(&repository, worktree.path, &options))
        }
        git_repository_free(repository)
        try excludeWorkspaceFiles()
    }

    /// Pythilo's own folder is never part of the user's history.
    private func excludeWorkspaceFiles() throws {
        let info = worktree.appending(path: ".git/info")
        try FileManager.default.createDirectory(at: info, withIntermediateDirectories: true)
        let exclude = info.appending(path: "exclude")
        let existing = (try? String(contentsOf: exclude, encoding: .utf8)) ?? ""
        guard !existing.contains(".pythilo/") else { return }
        try (existing + ".pythilo/\n__pycache__/\n").write(to: exclude, atomically: true, encoding: .utf8)
    }

    public func snapshot() throws -> GitSnapshot {
        try open { repository in
            var options = git_status_options()
            try Self.check(git_status_options_init(&options, UInt32(GIT_STATUS_OPTIONS_VERSION)))
            options.flags = UInt32(
                GIT_STATUS_OPT_INCLUDE_UNTRACKED.rawValue
                    | GIT_STATUS_OPT_RECURSE_UNTRACKED_DIRS.rawValue
                    | GIT_STATUS_OPT_RENAMES_HEAD_TO_INDEX.rawValue
            )
            var list: OpaquePointer?
            try Self.check(git_status_list_new(&list, repository, &options))
            defer { git_status_list_free(list) }

            var changes: [GitFileChange] = []
            for position in 0..<git_status_list_entrycount(list) {
                guard let entry = git_status_byindex(list, position)?.pointee else { continue }
                let delta = entry.index_to_workdir ?? entry.head_to_index
                guard let raw = delta?.pointee.new_file.path ?? delta?.pointee.old_file.path else { continue }
                let flags = entry.status.rawValue
                changes.append(
                    GitFileChange(
                        path: String(cString: raw),
                        kind: Self.kind(flags),
                        staged: flags & Self.indexMask != 0,
                        unstaged: flags & Self.worktreeMask != 0
                    )
                )
            }

            let branch = Self.currentBranch(repository)
            let head = Self.headOID(repository)
            var remoteURL: String?
            var remote: OpaquePointer?
            if git_remote_lookup(&remote, repository, "origin") >= 0 {
                defer { git_remote_free(remote) }
                if let url = git_remote_url(remote) { remoteURL = String(cString: url) }
            } else {
            }

            var ahead: Int?
            var behind: Int?
            if var local = head {
                var upstream = git_oid()
                if git_reference_name_to_id(&upstream, repository, "refs/remotes/origin/" + branch) >= 0 {
                    var aheadCount = 0
                    var behindCount = 0
                    if git_graph_ahead_behind(&aheadCount, &behindCount, repository, &local, &upstream) >= 0 {
                        ahead = aheadCount
                        behind = behindCount
                    }
                } else {
                }
            }
            return GitSnapshot(
                branch: branch,
                head: head.map(Self.string),
                changes: changes.sorted { $0.path < $1.path },
                remoteURL: remoteURL,
                ahead: ahead,
                behind: behind
            )
        }
    }

    private static let indexMask = UInt32(
        GIT_STATUS_INDEX_NEW.rawValue | GIT_STATUS_INDEX_MODIFIED.rawValue | GIT_STATUS_INDEX_DELETED.rawValue
            | GIT_STATUS_INDEX_RENAMED.rawValue | GIT_STATUS_INDEX_TYPECHANGE.rawValue
    )
    private static let worktreeMask = UInt32(
        GIT_STATUS_WT_NEW.rawValue | GIT_STATUS_WT_MODIFIED.rawValue | GIT_STATUS_WT_DELETED.rawValue
            | GIT_STATUS_WT_RENAMED.rawValue | GIT_STATUS_WT_TYPECHANGE.rawValue
    )

    private static func kind(_ flags: UInt32) -> GitFileChange.Kind {
        if flags & GIT_STATUS_CONFLICTED.rawValue != 0 { return .conflicted }
        if flags & (GIT_STATUS_WT_DELETED.rawValue | GIT_STATUS_INDEX_DELETED.rawValue) != 0 { return .deleted }
        if flags & (GIT_STATUS_WT_RENAMED.rawValue | GIT_STATUS_INDEX_RENAMED.rawValue) != 0 { return .renamed }
        if flags & GIT_STATUS_INDEX_NEW.rawValue != 0 { return .added }
        if flags & GIT_STATUS_WT_NEW.rawValue != 0 { return .untracked }
        return .modified
    }

    private static func currentBranch(_ repository: OpaquePointer) -> String {
        var head: OpaquePointer?
        let result = git_repository_head(&head, repository)
        if result >= 0, let head {
            defer { git_reference_free(head) }
            if git_repository_head_detached(repository) == 1 { return "HEAD" }
            if let name = git_reference_shorthand(head) { return String(cString: name) }
        }
        // An unborn branch has no reference yet, only the symbolic name in HEAD.
        var symbolic: OpaquePointer?
        if git_reference_lookup(&symbolic, repository, "HEAD") >= 0, let symbolic {
            defer { git_reference_free(symbolic) }
            if let target = git_reference_symbolic_target(symbolic) {
                return String(cString: target).replacingOccurrences(of: "refs/heads/", with: "")
            }
        }
        return "main"
    }

    private static func headOID(_ repository: OpaquePointer) -> git_oid? {
        var reference: OpaquePointer?
        guard git_repository_head(&reference, repository) >= 0 else {
            return nil
        }
        defer { git_reference_free(reference) }
        return git_reference_target(reference)?.pointee
    }

    private static func string(_ oid: git_oid) -> String {
        var oid = oid
        var buffer = [CChar](repeating: 0, count: 41)
        git_oid_tostr(&buffer, buffer.count, &oid)
        return String(cString: buffer)
    }

    public func stage(_ paths: [String]) throws {
        try open { repository in
            var index: OpaquePointer?
            try Self.check(git_repository_index(&index, repository))
            defer { git_index_free(index) }
            if paths.isEmpty {
                try Self.check(git_index_add_all(index, nil, 0, nil, nil))
                try Self.check(git_index_update_all(index, nil, nil, nil))
            } else {
                for path in paths {
                    if FileManager.default.fileExists(atPath: worktree.appending(path: path).path) {
                        try Self.check(git_index_add_bypath(index, path))
                    } else {
                        try Self.check(git_index_remove_bypath(index, path))
                    }
                }
            }
            try Self.check(git_index_write(index))
        }
    }

    public func unstage(_ paths: [String]) throws {
        try open { repository in
            var target: OpaquePointer?
            if var head = Self.headOID(repository) {
                try Self.check(git_object_lookup(&target, repository, &head, GIT_OBJECT_COMMIT))
            }
            defer { git_object_free(target) }
            let copies = paths.map { strdup($0) }
            defer { copies.forEach { free($0) } }
            var pointers: [UnsafeMutablePointer<CChar>?] = copies
            try pointers.withUnsafeMutableBufferPointer { buffer in
                var specs = git_strarray(strings: buffer.baseAddress, count: buffer.count)
                try Self.check(git_reset_default(repository, target, &specs))
            }
        }
    }

    @discardableResult
    public func commit(message: String, author: String, email: String) throws -> GitCommitSummary {
        let cleanMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanMessage.isEmpty else { throw GitFailure("A commit needs a message.") }
        guard !author.isEmpty, !email.isEmpty, !author.contains("\n"), !email.contains("\n") else {
            throw GitFailure("Set a Git name and email first, in Settings or with git config.")
        }
        return try open { repository in
            var index: OpaquePointer?
            try Self.check(git_repository_index(&index, repository))
            defer { git_index_free(index) }
            var treeID = git_oid()
            try Self.check(git_index_write_tree(&treeID, index))
            let parentID = Self.headOID(repository)
            var tree: OpaquePointer?
            var parent: OpaquePointer?
            try Self.check(git_tree_lookup(&tree, repository, &treeID))
            defer {
                git_tree_free(tree)
                git_commit_free(parent)
            }
            if var parentID {
                try Self.check(git_commit_lookup(&parent, repository, &parentID))
                if let parentTree = git_commit_tree_id(parent), git_oid_equal(parentTree, &treeID) == 1 {
                    throw GitFailure("Nothing is staged. Stage a file first.")
                }
            } else if git_index_entrycount(index) == 0 {
                throw GitFailure("Nothing is staged. Stage a file first.")
            }
            var signature: UnsafeMutablePointer<git_signature>?
            try Self.check(git_signature_now(&signature, author, email))
            defer { git_signature_free(signature) }
            var created = git_oid()
            var parentPointer = parent
            try withUnsafeMutablePointer(to: &parentPointer) { parents in
                try Self.check(
                    git_commit_create(
                        &created, repository, "HEAD", signature, signature, nil,
                        cleanMessage, tree, parentID == nil ? 0 : 1, parents
                    )
                )
            }
            return GitCommitSummary(id: Self.string(created), message: cleanMessage, author: author, date: Date())
        }
    }

    public func history(limit: Int = 100) throws -> [GitCommitSummary] {
        try open { repository in
            guard Self.headOID(repository) != nil else { return [] }
            var walker: OpaquePointer?
            try Self.check(git_revwalk_new(&walker, repository))
            defer { git_revwalk_free(walker) }
            try Self.check(git_revwalk_sorting(walker, UInt32(GIT_SORT_TIME.rawValue)))
            try Self.check(git_revwalk_push_head(walker))
            var result: [GitCommitSummary] = []
            var id = git_oid()
            while result.count < limit, git_revwalk_next(&id, walker) == 0 {
                var commit: OpaquePointer?
                try Self.check(git_commit_lookup(&commit, repository, &id))
                defer { git_commit_free(commit) }
                let message = git_commit_summary(commit).map { String(cString: $0) } ?? ""
                let author = git_commit_author(commit)?.pointee.name.map { String(cString: $0) } ?? ""
                result.append(
                    GitCommitSummary(
                        id: Self.string(id),
                        message: message,
                        author: author,
                        date: Date(timeIntervalSince1970: TimeInterval(git_commit_time(commit)))
                    )
                )
            }
            return result
        }
    }

    public func branches() throws -> [String] {
        try open { repository in
            var iterator: OpaquePointer?
            try Self.check(git_branch_iterator_new(&iterator, repository, GIT_BRANCH_LOCAL))
            defer { git_branch_iterator_free(iterator) }
            var names: [String] = []
            var reference: OpaquePointer?
            var type = GIT_BRANCH_LOCAL
            while git_branch_next(&reference, &type, iterator) == 0 {
                defer { git_reference_free(reference) }
                var name: UnsafePointer<CChar>?
                if git_branch_name(&name, reference) >= 0, let name { names.append(String(cString: name)) }
            }
            return names.sorted()
        }
    }

    public func createBranch(_ name: String) throws {
        try open { repository in
            guard var head = Self.headOID(repository) else { throw GitFailure("Make a first commit before creating a branch.") }
            var commit: OpaquePointer?
            try Self.check(git_commit_lookup(&commit, repository, &head))
            defer { git_commit_free(commit) }
            var created: OpaquePointer?
            try Self.check(git_branch_create(&created, repository, name, commit, 0))
            git_reference_free(created)
        }
    }

    /// Refuses, like `git switch`, when the change would overwrite local edits.
    public func switchBranch(_ name: String) throws {
        try open { repository in
            var target: OpaquePointer?
            try Self.check(git_revparse_single(&target, repository, "refs/heads/" + name))
            defer { git_object_free(target) }
            var options = git_checkout_options()
            try Self.check(git_checkout_options_init(&options, UInt32(GIT_CHECKOUT_OPTIONS_VERSION)))
            options.checkout_strategy = UInt32(GIT_CHECKOUT_SAFE.rawValue)
            try Self.check(git_checkout_tree(repository, target, &options))
            try Self.check(git_repository_set_head(repository, "refs/heads/" + name))
        }
    }

    /// Unified diff of the working folder against HEAD, optionally for one path.
    public func diff(path: String? = nil) throws -> String {
        try open { repository in
            var tree: OpaquePointer?
            if var head = Self.headOID(repository) {
                var commit: OpaquePointer?
                try Self.check(git_commit_lookup(&commit, repository, &head))
                defer { git_commit_free(commit) }
                try Self.check(git_commit_tree(&tree, commit))
            }
            defer { git_tree_free(tree) }
            var options = git_diff_options()
            try Self.check(git_diff_options_init(&options, UInt32(GIT_DIFF_OPTIONS_VERSION)))
            options.flags = UInt32(GIT_DIFF_INCLUDE_UNTRACKED.rawValue | GIT_DIFF_SHOW_UNTRACKED_CONTENT.rawValue | GIT_DIFF_RECURSE_UNTRACKED_DIRS.rawValue)
            let spec = path.map { strdup($0) } ?? nil
            defer { free(spec) }
            var pointer: UnsafeMutablePointer<CChar>? = spec
            return try withUnsafeMutablePointer(to: &pointer) { strings -> String in
                if spec != nil {
                    options.pathspec = git_strarray(strings: strings, count: 1)
                    options.flags |= UInt32(GIT_DIFF_DISABLE_PATHSPEC_MATCH.rawValue)
                }
                var diff: OpaquePointer?
                try Self.check(git_diff_tree_to_workdir_with_index(&diff, repository, tree, &options))
                defer { git_diff_free(diff) }
                var buffer = git_buf()
                try Self.check(git_diff_to_buf(&buffer, diff, GIT_DIFF_FORMAT_PATCH))
                defer { git_buf_dispose(&buffer) }
                guard let bytes = buffer.ptr else { return "" }
                return String(decoding: Data(bytes: bytes, count: buffer.size), as: UTF8.self)
            }
        }
    }

    public func setRemote(url: String) throws {
        let address = try Self.validatedAddress(url)
        try open { repository in
            var existing: OpaquePointer?
            if git_remote_lookup(&existing, repository, "origin") >= 0 {
                git_remote_free(existing)
                try Self.check(git_remote_set_url(repository, "origin", address))
            } else {
                var created: OpaquePointer?
                try Self.check(git_remote_create(&created, repository, "origin", address))
                git_remote_free(created)
            }
        }
    }

    static func validatedAddress(_ raw: String) throws -> String {
        guard let value = URLComponents(string: raw), value.scheme == "https", value.host != nil else {
            throw GitFailure("Use an HTTPS repository address. SSH is not available in this build.")
        }
        guard value.user == nil, value.password == nil else {
            throw GitFailure("Do not put a token in the address. Pythilo keeps Git tokens in the Keychain.")
        }
        return raw
    }

    public static func clone(url: String, into destination: URL, credential: GitCredential?) throws {
        try check(ready)
        let address = try validatedAddress(url)
        let context = GitTransfer(address: address, credential: credential)
        var options = git_clone_options()
        try check(git_clone_options_init(&options, UInt32(GIT_CLONE_OPTIONS_VERSION)))
        options.checkout_opts.checkout_strategy = UInt32(GIT_CHECKOUT_SAFE.rawValue)
        options.fetch_opts.callbacks = context.callbacks
        var repository: OpaquePointer?
        let result = withExtendedLifetime(context) { git_clone(&repository, address, destination.path, &options) }
        git_repository_free(repository)
        try context.check(result)
        try ProjectRepository(worktree: destination).excludeWorkspaceFiles()
    }

    private func withRemote(credential: GitCredential?, _ body: (OpaquePointer, OpaquePointer, GitTransfer) throws -> Void) throws {
        try open { repository in
            var remote: OpaquePointer?
            let found = git_remote_lookup(&remote, repository, "origin")
            guard found >= 0, let remote, let url = git_remote_url(remote) else {
                throw GitFailure("This repository has no origin. Add one with git remote add origin <https url>.")
            }
            defer { git_remote_free(remote) }
            let context = GitTransfer(address: String(cString: url), credential: credential)
            try withExtendedLifetime(context) { try body(repository, remote, context) }
        }
    }

    public func fetch(credential: GitCredential?) throws {
        try withRemote(credential: credential) { _, remote, context in
            var options = git_fetch_options()
            try Self.check(git_fetch_options_init(&options, UInt32(GIT_FETCH_OPTIONS_VERSION)))
            options.callbacks = context.callbacks
            try context.check(git_remote_fetch(remote, nil, &options, "Pythilo fetch"))
        }
    }

    /// Fast-forward only. Divergent history is reported, never merged silently.
    public func pull(credential: GitCredential?) throws -> String {
        try fetch(credential: credential)
        return try open { repository in
            let branch = Self.currentBranch(repository)
            var upstream = git_oid()
            guard git_reference_name_to_id(&upstream, repository, "refs/remotes/origin/" + branch) >= 0 else {
                throw GitFailure("origin has no branch named \(branch).")
            }
            guard var local = Self.headOID(repository) else {
                throw GitFailure("This branch has no commits yet. Clone instead, or commit first.")
            }
            var ahead = 0
            var behind = 0
            try Self.check(git_graph_ahead_behind(&ahead, &behind, repository, &local, &upstream))
            if behind == 0 { return "Already up to date." }
            guard ahead == 0 else {
                throw GitFailure("Local and remote history diverged. Nothing was changed. Merge or rebase this repository on a computer.")
            }
            var target: OpaquePointer?
            try Self.check(git_object_lookup(&target, repository, &upstream, GIT_OBJECT_COMMIT))
            defer { git_object_free(target) }
            var options = git_checkout_options()
            try Self.check(git_checkout_options_init(&options, UInt32(GIT_CHECKOUT_OPTIONS_VERSION)))
            options.checkout_strategy = UInt32(GIT_CHECKOUT_SAFE.rawValue)
            try Self.check(git_checkout_tree(repository, target, &options))
            var reference: OpaquePointer?
            var updated: OpaquePointer?
            try Self.check(git_reference_lookup(&reference, repository, "refs/heads/" + branch))
            defer {
                git_reference_free(reference)
                git_reference_free(updated)
            }
            try Self.check(git_reference_set_target(&updated, reference, &upstream, "Pythilo fast-forward"))
            return "Fast-forwarded \(branch) to \(Self.string(upstream).prefix(8))."
        }
    }

    public func push(credential: GitCredential?) throws -> String {
        var pushed = ""
        try withRemote(credential: credential) { repository, remote, context in
            let branch = Self.currentBranch(repository)
            var options = git_push_options()
            try Self.check(git_push_options_init(&options, UInt32(GIT_PUSH_OPTIONS_VERSION)))
            options.callbacks = context.callbacks
            options.pb_parallelism = 1
            let spec = strdup("refs/heads/\(branch):refs/heads/\(branch)")
            defer { free(spec) }
            var pointer: UnsafeMutablePointer<CChar>? = spec
            try withUnsafeMutablePointer(to: &pointer) { strings in
                var refspecs = git_strarray(strings: strings, count: 1)
                try context.check(git_remote_push(remote, &refspecs, &options))
            }
            if context.pushRejected {
                throw GitFailure("The server rejected the push. Your local commits were kept.")
            }
            pushed = "Pushed \(branch) to origin."
        }
        return pushed
    }
}

/// Lives for one synchronous libgit2 transfer. Certificates stay with the system.
final class GitTransfer: @unchecked Sendable {
    private let credential: GitCredential?
    private let address: String
    private let lock = NSLock()
    private var attempts = 0
    private var rejected = false

    init(address: String, credential: GitCredential?) {
        self.address = address
        self.credential = credential
    }

    var pushRejected: Bool { lock.withLock { rejected } }

    func check(_ result: Int32) throws {
        guard result >= 0 else {
            var text = "Git network operation failed."
            if let error = git_error_last(), let pointer = error.pointee.message {
                text = String(cString: pointer)
            }
            if let token = credential?.token {
                text = text.replacingOccurrences(of: token, with: "<redacted>")
            }
            throw GitFailure(text)
        }
    }

    fileprivate func acquire(_ output: UnsafeMutablePointer<UnsafeMutablePointer<git_credential>?>, allowed: UInt32) -> Int32 {
        lock.withLock {
            guard let credential, attempts < 2, allowed & UInt32(GIT_CREDENTIAL_USERPASS_PLAINTEXT.rawValue) != 0 else {
                return GIT_EAUTH.rawValue
            }
            attempts += 1
            return git_credential_userpass_plaintext_new(output, credential.username, credential.token)
        }
    }

    fileprivate func noteRejection() {
        lock.withLock { rejected = true }
    }

    var callbacks: git_remote_callbacks {
        var value = git_remote_callbacks()
        git_remote_init_callbacks(&value, UInt32(GIT_REMOTE_CALLBACKS_VERSION))
        value.payload = Unmanaged.passUnretained(self).toOpaque()
        value.credentials = { output, _, _, allowed, payload in
            guard let payload, let output else { return GIT_EAUTH.rawValue }
            return Unmanaged<GitTransfer>.fromOpaque(payload).takeUnretainedValue().acquire(output, allowed: allowed)
        }
        value.push_update_reference = { _, status, payload in
            guard let payload else { return GIT_EUSER.rawValue }
            if status != nil {
                Unmanaged<GitTransfer>.fromOpaque(payload).takeUnretainedValue().noteRejection()
            }
            return 0
        }
        return value
    }
}
