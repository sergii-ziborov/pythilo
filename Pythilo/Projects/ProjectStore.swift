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
    /// Folder name -> category the person chose. Kept on this device, outside the
    /// project folders, so it never shows up in a repository or an exported project.
    private(set) var categories: [String: String] = [:]
    let root: URL
    private let defaults: UserDefaults
    private static let categoriesKey = "pythilo.projectCategories"

    init(root: URL? = nil, defaults: UserDefaults = .standard) {
        self.root = root
            ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appending(path: "Projects")
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.categoriesKey),
           let saved = try? JSONDecoder().decode([String: String].self, from: data) {
            categories = saved
        }
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
        setCategory(nil, for: project)
        refresh()
    }

    func rename(_ project: Project, to name: String) throws {
        let target = root.appending(path: uniqueName(name))
        try FileManager.default.moveItem(at: project.url, to: target)
        if let category = categories.removeValue(forKey: project.name) {
            categories[target.lastPathComponent] = category
            saveCategories()
        }
        refresh()
    }

    // MARK: Categories

    func category(of project: Project) -> String? { categories[project.name] }

    /// Every category in use, sorted by name.
    var categoryNames: [String] {
        let present = Set(projects.map(\.name))
        return Set(categories.filter { present.contains($0.key) }.values)
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    func setCategory(_ category: String?, for project: Project) {
        let clean = category?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let clean, !clean.isEmpty {
            categories[project.name] = String(clean.prefix(40))
        } else {
            categories.removeValue(forKey: project.name)
        }
        saveCategories()
    }

    func renameCategory(_ old: String, to new: String) {
        let clean = new.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        for (name, value) in categories where value == old { categories[name] = String(clean.prefix(40)) }
        saveCategories()
    }

    func removeCategory(_ category: String) {
        categories = categories.filter { $0.value != category }
        saveCategories()
    }

    private func saveCategories() {
        if let data = try? JSONEncoder().encode(categories) { defaults.set(data, forKey: Self.categoriesKey) }
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
