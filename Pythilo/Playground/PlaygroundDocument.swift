import Foundation

/// The room's text-only project: map `meta` and map `files` in the Yjs document.
struct PlaygroundDocument: Codable, Equatable, Sendable {
    struct Origin: Codable, Equatable, Sendable {
        let url: String
        var commit: String?
    }

    var schemaVersion = 1
    var name: String
    var entryFile: String
    var files: [String: String]
    var origin: Origin?

    static let maximumFiles = 16
    static let maximumFileBytes = 65_536
    static let maximumTotalBytes = 131_072
    static let extensions: Set<String> = ["py", "pyi", "txt", "md", "rst", "csv", "tsv", "json", "toml", "cfg", "ini", "yaml", "yml", "html", "css", "js", "sql"]
    static let names: Set<String> = ["requirements.txt", "LICENSE", "NOTICE", "README", ".gitignore"]
    static let refusedFolders: Set<String> = ["__pycache__", ".venv", "venv", ".git", ".pythilo", "site-packages", "node_modules", ".mypy_cache", ".pytest_cache"]
    private static let reserved: Set<String> = ["__proto__", "constructor", "prototype", ".", "..", ""]

    /// Whether a path may be in a room at all, before its size is counted. Extensions
    /// count anywhere; the extensionless names only at the project root.
    static func allows(path: String) -> Bool {
        guard path.utf16.count <= 180, !path.hasPrefix("/"), !path.contains("\\"), !path.contains(":"),
              !path.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 }) else { return false }
        let components = path.components(separatedBy: "/")
        guard components.count <= 32, !components.contains(where: { reserved.contains($0) || $0.utf8.count > 255 || refusedFolders.contains($0.lowercased()) }) else { return false }
        let lowered = path.lowercased()
        return extensions.contains { lowered.hasSuffix("." + $0) } || names.contains { $0.lowercased() == lowered }
    }

    func validated() throws -> Self {
        guard schemaVersion == 1, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name.utf16.count <= 80,
              !name.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 }),
              (1...Self.maximumFiles).contains(files.count), files[entryFile] != nil, entryFile.hasSuffix(".py") else {
            throw PlaygroundFailure("A room holds 1 to 16 text files and a Python entry file.")
        }
        var total = 0
        // The device's file system ignores case and Unicode composition, as the website checks.
        func canonical(_ path: String) -> String { path.precomposedStringWithCanonicalMapping.lowercased() }
        var paths: Set<String> = []
        var directories: [String: String] = [:]
        for (path, text) in files {
            guard Self.allows(path: path), !text.contains("\0"), text.utf8.count <= Self.maximumFileBytes else {
                throw PlaygroundFailure("Rooms carry Python source and small text files only, at most 64 KiB each. \(path) does not fit.")
            }
            guard paths.insert(canonical(path)).inserted else { throw PlaygroundFailure("Two file names differ only in case or accents.") }
            let parts = path.components(separatedBy: "/")
            for depth in 1..<max(1, parts.count) {
                let parent = parts.prefix(depth).joined(separator: "/")
                if let previous = directories[canonical(parent)], previous.precomposedStringWithCanonicalMapping != parent.precomposedStringWithCanonicalMapping {
                    throw PlaygroundFailure("Two folder names differ only in case.")
                }
                directories[canonical(parent)] = parent
            }
            total += text.utf8.count
        }
        guard paths.isDisjoint(with: directories.keys) else { throw PlaygroundFailure("A file and a folder have the same name.") }
        guard total <= Self.maximumTotalBytes else { throw PlaygroundFailure("The shared files exceed 128 KiB in all.") }
        if let origin {
            guard let url = URL(string: origin.url), url.scheme == "https", ["github.com", "gist.github.com"].contains(url.host),
                  url.user == nil, url.password == nil else { throw PlaygroundFailure("Invalid project origin.") }
        }
        return self
    }
}

struct PlaygroundFailure: LocalizedError, Sendable {
    let message: String
    /// The relay's HTTP status, when the failure came from a relay response.
    let status: Int?
    init(_ message: String, status: Int? = nil) {
        self.message = message
        self.status = status
    }
    var errorDescription: String? { message }
}

/// A file the room could not take, and why.
struct PlaygroundLeftOut: Equatable, Sendable, Identifiable {
    let path: String
    let reason: String
    var id: String { path }
}

/// Moves text between a project folder and a room document.
enum PlaygroundProjectFiles {
    struct Selection: Equatable, Sendable {
        let document: PlaygroundDocument
        let leftOut: [PlaygroundLeftOut]
        var bytes: Int { document.files.values.reduce(0) { $0 + $1.utf8.count } }
    }

    /// Pythilo's own and generated folders are skipped without a word.
    private static let quiet: Set<String> = [".git", ".pythilo", "__pycache__", ".mypy_cache", ".pytest_cache", ".DS_Store"]

    static func entryFile(in paths: [String]) -> String? {
        for name in ["main.py", "app.py", "manage.py", "hello.py"] where paths.contains(name) { return name }
        return paths.filter { $0.hasSuffix(".py") }.sorted { ($0.split(separator: "/").count, $0) < ($1.split(separator: "/").count, $1) }.first
    }

    /// Every text file that fits, entry file first, then Python, then the rest.
    static func collect(from root: URL, name: String, entryFile preferred: String? = nil) throws -> Selection {
        var candidates: [(path: String, text: String)] = []
        var leftOut: [PlaygroundLeftOut] = []
        let base = root.standardizedFileURL.resolvingSymlinksInPath().path + "/"
        if let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey]) {
            for case let url as URL in walker {
                let full = url.standardizedFileURL.resolvingSymlinksInPath().path
                let path = full.hasPrefix(base) ? String(full.dropFirst(base.count)) : url.lastPathComponent
                let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey])
                if quiet.contains(url.lastPathComponent) {
                    walker.skipDescendants()
                    continue
                }
                if values?.isDirectory == true {
                    if PlaygroundDocument.refusedFolders.contains(url.lastPathComponent.lowercased()) {
                        walker.skipDescendants()
                        leftOut.append(PlaygroundLeftOut(path: path + "/", reason: "Installed packages and environments stay on this device"))
                    }
                    continue
                }
                guard values?.isRegularFile == true, values?.isSymbolicLink != true, full.hasPrefix(base) else { continue }
                guard PlaygroundDocument.allows(path: path) else {
                    leftOut.append(PlaygroundLeftOut(path: path, reason: "Not a source or text file a room carries"))
                    continue
                }
                guard (values?.fileSize ?? 0) <= PlaygroundDocument.maximumFileBytes else {
                    leftOut.append(PlaygroundLeftOut(path: path, reason: "Larger than 64 KiB"))
                    continue
                }
                guard let data = try? Data(contentsOf: url), let text = String(data: data, encoding: .utf8), !text.contains("\0") else {
                    leftOut.append(PlaygroundLeftOut(path: path, reason: "Not UTF-8 text"))
                    continue
                }
                guard text.utf8.count <= PlaygroundDocument.maximumFileBytes else {
                    leftOut.append(PlaygroundLeftOut(path: path, reason: "Larger than 64 KiB"))
                    continue
                }
                candidates.append((path, text))
            }
        }
        let paths = candidates.map(\.path)
        guard let entry = preferred.flatMap({ paths.contains($0) ? $0 : nil }) ?? entryFile(in: paths) else {
            throw PlaygroundFailure("A room needs at least one Python file of 64 KiB or less.")
        }
        func rank(_ path: String) -> Int { path == entry ? 0 : path.hasSuffix(".py") ? 1 : 2 }
        candidates.sort { (rank($0.path), $0.path) < (rank($1.path), $1.path) }
        var files: [String: String] = [:]
        var total = 0
        for candidate in candidates {
            let size = candidate.text.utf8.count
            if files.count >= PlaygroundDocument.maximumFiles {
                leftOut.append(PlaygroundLeftOut(path: candidate.path, reason: "Over the 16-file limit"))
            } else if total + size > PlaygroundDocument.maximumTotalBytes {
                leftOut.append(PlaygroundLeftOut(path: candidate.path, reason: "Over the 128 KiB limit for all files"))
            } else {
                files[candidate.path] = candidate.text
                total += size
            }
        }
        let title = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
        let document = try PlaygroundDocument(name: title.isEmpty ? "project" : title, entryFile: entry, files: files).validated()
        return Selection(document: document, leftOut: leftOut.sorted { $0.path < $1.path })
    }

    /// The URL for a room path, only when it stays inside the folder.
    static func url(for path: String, in root: URL) -> URL? {
        guard PlaygroundDocument.allows(path: path) else { return nil }
        let base = root.standardizedFileURL.resolvingSymlinksInPath().path + "/"
        let url = root.appending(path: path)
        let parent = url.deletingLastPathComponent().standardizedFileURL.resolvingSymlinksInPath().path + "/"
        guard parent.hasPrefix(base) else { return nil }
        if (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == true { return nil }
        return url
    }

    /// Writes what changed and removes files that left the room. Returns the paths it touched.
    @discardableResult
    static func write(_ document: PlaygroundDocument, to root: URL, removing removed: Set<String>) throws -> Set<String> {
        let document = try document.validated()
        var touched: Set<String> = []
        for (path, text) in document.files {
            guard let url = url(for: path, in: root) else { continue }
            if let data = try? Data(contentsOf: url), String(data: data, encoding: .utf8) == text { continue }
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: url, atomically: true, encoding: .utf8)
            touched.insert(path)
        }
        for path in removed where document.files[path] == nil {
            guard let url = url(for: path, in: root), FileManager.default.fileExists(atPath: url.path) else { continue }
            try FileManager.default.removeItem(at: url)
            touched.insert(path)
        }
        return touched
    }
}
