import Foundation

struct ContentPack: Codable, Identifiable, Sendable, Hashable {
    struct File: Codable, Sendable, Hashable {
        let path: String
        let bytes: Int
        let sha256: String
    }
    let id: String
    let title: String
    let kind: String
    let url: URL
    let bytes: Int
    let sha256: String
    let files: [File]
    let dependencies: [String]
    var format: String? = nil
}

struct DownloadCatalog: Decodable, Sendable {
    let schema: Int
    let packs: [ContentPack]
    let courses: [Course]

    static let bundled: DownloadCatalog = {
        guard let url = Bundle.main.url(forResource: "catalog", withExtension: "json", subdirectory: "ContentCatalog"),
              let data = try? Data(contentsOf: url),
              let catalog = try? JSONDecoder().decode(DownloadCatalog.self, from: data), catalog.schema == 1 else {
            return DownloadCatalog(schema: 1, packs: [], courses: [])
        }
        return catalog
    }()

    func pack(_ id: String) -> ContentPack? { packs.first { $0.id == id } }

    func closure(_ id: String) -> [ContentPack] {
        var result: [ContentPack] = [], seen = Set<String>()
        func visit(_ key: String) {
            guard seen.insert(key).inserted, let entry = pack(key) else { return }
            // Fetch readable content first; its execution dependencies follow.
            result.append(entry)
            for dependency in entry.dependencies { visit(dependency) }
        }
        visit(id)
        return result
    }
}

enum ContentFailure: LocalizedError {
    case invalid(String)
    var errorDescription: String? {
        switch self { case .invalid(let message): message }
    }
}
