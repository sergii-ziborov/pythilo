import Foundation
import Observation

@MainActor @Observable
final class ContentStore {
    static let shared = ContentStore()
    enum Phase: Equatable { case absent, queued, downloading, installing, paused, installed, failed(String) }
    private(set) var phases: [String: Phase] = [:]
    private(set) var received: [String: Int] = [:]
    private(set) var revision = 0
    private var locations: [String: URL] = [:]
    private var queue: [String] = []
    private var worker: Task<Void, Never>?
    private var active: String?
    private var generation = UUID()
    private var cancelled = Set<String>()
    let catalog: DownloadCatalog
    let root: URL
    private var partials: URL { root.appending(path: "partials", directoryHint: .isDirectory) }

    init(catalog: DownloadCatalog = .bundled, root: URL? = nil) {
        self.catalog = catalog
        self.root = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "DownloadedContent", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: self.root, withIntermediateDirectories: true)
        var backupValues = URLResourceValues(); backupValues.isExcludedFromBackup = true
        var downloadRoot = self.root; try? downloadRoot.setResourceValues(backupValues)
        // A newer signed app may pin new package versions. Reclaim obsolete downloads,
        // never project folders, lesson drafts or completion records.
        if !catalog.packs.isEmpty {
            let currentHashes = Set(catalog.packs.map(\.sha256))
            for folder in (try? FileManager.default.contentsOfDirectory(at: self.root, includingPropertiesForKeys: nil)) ?? [] {
                let name = folder.lastPathComponent
                if name.hasPrefix(".install-") || name.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil && !currentHashes.contains(name) {
                    try? FileManager.default.removeItem(at: folder)
                }
            }
            for partial in (try? FileManager.default.contentsOfDirectory(at: self.root.appending(path: "partials"), includingPropertiesForKeys: nil)) ?? [] where !currentHashes.contains(partial.lastPathComponent) {
                try? FileManager.default.removeItem(at: partial)
            }
        }
        for pack in catalog.packs {
            if let url = ContentInstaller.installed(pack, root: self.root) {
                locations[pack.id] = url; phases[pack.id] = .installed
            } else {
                let partial = self.root.appending(path: "partials/\(pack.sha256)")
                let count = ((try? FileManager.default.attributesOfItem(atPath: partial.path)[.size]) as? NSNumber)?.intValue ?? 0
                if count > 0 { phases[pack.id] = .paused; received[pack.id] = count }
            }
        }
    }

    func phase(_ id: String) -> Phase { phases[id] ?? .absent }
    func location(_ id: String) -> URL? { _ = revision; return locations[id] }
    func ready(_ id: String) -> Bool { catalog.pack(id) != nil && catalog.closure(id).allSatisfy { locations[$0.id] != nil } }
    func missingBytes(_ id: String) -> Int { catalog.closure(id).filter { locations[$0.id] == nil }.reduce(0) { $0 + max(0, $1.bytes - (received[$1.id] ?? 0)) } }
    var installedBytes: Int { catalog.packs.filter { locations[$0.id] != nil }.reduce(0) { $0 + $1.files.reduce(0) { $0 + $1.bytes } } }
    var packagePaths: [String] { catalog.packs.filter { $0.kind == "runtime" }.compactMap { locations[$0.id]?.appending(path: "app_packages").path } }
    var assetEnvironment: [String: String] {
        var result: [String: String] = [:]
        if let url = locations["assets-finetune-data"] { result["PYTHILO_FINETUNE_DATA"] = url.path }
        if let url = locations["assets-bert-weights"] { result["PYTHILO_BERT_WEIGHTS"] = url.appending(path: "model.safetensors").path }
        return result
    }

    func download(_ id: String) {
        for pack in catalog.closure(id) where locations[pack.id] == nil {
            guard phases[pack.id] != .downloading, phases[pack.id] != .installing else { continue }
            if !queue.contains(pack.id) { queue.append(pack.id) }
            phases[pack.id] = .queued
        }
        startWorker()
    }

    func pause(_ id: String) {
        guard phases[id] != .installing else { return }
        queue.removeAll { $0 == id }
        if active == id { worker?.cancel() }
        if locations[id] == nil { phases[id] = .paused }
        startWorker()
    }

    func cancel(_ id: String) {
        guard phases[id] != .installing else { return }
        pause(id)
        if active == id { cancelled.insert(id) }
        else if let pack = catalog.pack(id) { try? FileManager.default.removeItem(at: partials.appending(path: pack.sha256)) }
        received[id] = nil; phases[id] = locations[id] == nil ? .absent : .installed
    }

    func remove(_ id: String) throws {
        guard phases[id] != .installing else { throw ContentFailure.invalid("Wait for verification to finish before removing this download.") }
        guard RunSession.shared.phase == .idle || RunSession.shared.phase == .starting else {
            throw ContentFailure.invalid("Stop the current Python run before removing downloaded content.")
        }
        cancel(id)
        if let url = locations[id] { try FileManager.default.removeItem(at: url) }
        locations[id] = nil; phases[id] = .absent; revision += 1
        CourseLibrary.shared.reload()
    }

    private func startWorker() {
        guard worker == nil, !queue.isEmpty else { return }
        let id = queue.removeFirst()
        guard let pack = catalog.pack(id) else { startWorker(); return }
        let token = UUID(); generation = token; active = id; phases[id] = .downloading
        let partial = partials.appending(path: pack.sha256), destinationRoot = root
        worker = Task { [weak self] in
            do {
                let file = try await PackDownloader.fetch(pack, partial: partial) { [weak self] count in
                    await self?.update(id, token: token, count: count)
                }
                try Task.checkCancellation()
                guard let self, self.generation == token else { return }
                self.phases[id] = .installing
                let url = try await Task.detached(priority: .utility) {
                    try ContentInstaller.install(file, pack: pack, root: destinationRoot)
                }.value
                guard self.generation == token else { return }
                self.locations[id] = url; self.phases[id] = .installed; self.received[id] = pack.bytes
                try? FileManager.default.removeItem(at: partial)
                self.revision += 1
                CourseLibrary.shared.reload()
            } catch {
                guard let self, self.generation == token else { return }
                if Task.isCancelled || error is CancellationError { self.phases[id] = .paused }
                else {
                    // A complete but corrupt partial must not become a permanent retry loop.
                    if (self.received[id] ?? 0) >= pack.bytes {
                        try? FileManager.default.removeItem(at: partial); self.received[id] = 0
                    }
                    self.phases[id] = .failed(error.localizedDescription)
                }
            }
            guard let self, self.generation == token else { return }
            if self.cancelled.remove(id) != nil {
                try? FileManager.default.removeItem(at: partial); self.received[id] = nil; self.phases[id] = .absent
            } else if self.queue.contains(id) { self.phases[id] = .queued }
            self.worker = nil; self.active = nil; self.startWorker()
        }
    }

    private func update(_ id: String, token: UUID, count: Int) {
        guard generation == token else { return }; received[id] = count
    }
}
