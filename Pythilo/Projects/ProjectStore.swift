import Foundation
import Observation
import PythiloGit

struct Project: Identifiable, Hashable, Sendable {
    let url: URL
    var modified: Date = .distantPast
    var id: String { url.path }
    var name: String { url.lastPathComponent }
}

/// Projects are ordinary folders in the app's Documents, visible in the Files app.
@MainActor
@Observable
final class ProjectStore {
    static let shared = ProjectStore()

    private(set) var projects: [Project] = []
    let root: URL

    init(root: URL? = nil) {
        self.root = root
            ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appending(path: "Projects")
        try? FileManager.default.createDirectory(at: self.root, withIntermediateDirectories: true)
        refresh()
    }

    func refresh() {
        let folders = (try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        projects = folders.compactMap { url in
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .contentModificationDateKey])
            guard values?.isDirectory == true else { return nil }
            return Project(url: url, modified: values?.contentModificationDate ?? .distantPast)
        }
        .sorted { $0.modified > $1.modified }
    }

    func uniqueName(_ base: String) -> String {
        let clean = base.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-")
        let start = clean.isEmpty ? "project" : clean
        var name = start
        var suffix = 2
        while FileManager.default.fileExists(atPath: root.appending(path: name).path) {
            name = "\(start)-\(suffix)"
            suffix += 1
        }
        return name
    }

    @discardableResult
    func create(name: String, template: ProjectTemplate) throws -> Project {
        let url = root.appending(path: uniqueName(name))
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        for (path, text) in template.files {
            let file = url.appending(path: path)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: file, atomically: true, encoding: .utf8)
        }
        if !template.requiredPacks.isEmpty {
            let data = try JSONEncoder().encode(template.requiredPacks)
            try data.write(to: url.appending(path: "pythilo-packages.json"), options: .atomic)
        }
        refresh()
        return Project(url: url, modified: Date())
    }

    @discardableResult
    func importFolder(from source: URL) throws -> Project {
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        let url = root.appending(path: uniqueName(source.lastPathComponent))
        try FileManager.default.copyItem(at: source, to: url)
        refresh()
        return Project(url: url, modified: Date())
    }

    func clone(address: String, credential: GitCredential?) async throws -> Project {
        let base = (address as NSString).lastPathComponent.replacingOccurrences(of: ".git", with: "")
        let url = root.appending(path: uniqueName(base))
        do {
            try await Task.detached { try ProjectRepository.clone(url: address, into: url, credential: credential) }.value
        } catch {
            try? FileManager.default.removeItem(at: url)
            throw error
        }
        refresh()
        return Project(url: url, modified: Date())
    }

    func delete(_ project: Project) throws {
        try FileManager.default.removeItem(at: project.url)
        refresh()
    }

    func rename(_ project: Project, to name: String) throws {
        let target = root.appending(path: uniqueName(name))
        try FileManager.default.moveItem(at: project.url, to: target)
        refresh()
    }

    /// A project's name is enough to describe it on the list.
    nonisolated static func describe(_ url: URL) -> String {
        let has = { (name: String) in FileManager.default.fileExists(atPath: url.appending(path: name).path) }
        if has("manage.py") { return "Django" }
        if has("app.py") || has("hello.py") { return "Web" }
        if (try? FileManager.default.contentsOfDirectory(atPath: url.path))?.contains(where: { $0.hasSuffix(".ipynb") }) == true {
            return "Notebook"
        }
        return "Python"
    }
}

extension Project {
    var requiredPacks: [String] {
        guard let data = try? Data(contentsOf: url.appending(path: "pythilo-packages.json")),
              data.count < 16_384, let ids = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return Array(Set(ids)).sorted()
    }
}
