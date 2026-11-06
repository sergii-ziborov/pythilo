import XCTest
import ZIPFoundation
@testable import Pythilo

final class ContentDownloadTests: XCTestCase {
    private func temporary() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func fixture(_ entries: [(String, Data)], inventory: [(String, Data)]? = nil) throws -> (URL, ContentPack, URL) {
        let root = try temporary(), archiveURL = root.appending(path: "fixture.zip")
        let archive = try Archive(url: archiveURL, accessMode: .create)
        for (name, data) in entries {
            try archive.addEntry(with: name, type: .file, uncompressedSize: Int64(data.count), compressionMethod: .deflate) { position, size in
                data.subdata(in: Int(position)..<min(data.count, Int(position) + size))
            }
        }
        let data = try Data(contentsOf: archiveURL)
        let pack = ContentPack(id: "test", title: "Test", kind: "course", url: URL(string: "https://pythilo.com/test.zip")!, bytes: data.count,
            sha256: ContentInstaller.digest(data), files: (inventory ?? entries).map { .init(path: $0.0, bytes: $0.1.count, sha256: ContentInstaller.digest($0.1)) }, dependencies: [])
        return (archiveURL, pack, root.appending(path: "installed"))
    }

    func testVerifiesEveryFileBeforeActivatingAndRejectsCorruption() throws {
        let (zip, pack, root) = try fixture([("course.json", Data("{}".utf8)), ("sub/code.py", Data("print(42)".utf8))])
        let target = try ContentInstaller.install(zip, pack: pack, root: root)
        XCTAssertEqual(ContentInstaller.installed(pack, root: root), target)
        try Data("oops".utf8).write(to: target.appending(path: "course.json"))
        XCTAssertNil(ContentInstaller.installed(pack, root: root))
        try Data("corrupt zip".utf8).write(to: zip)
        XCTAssertThrowsError(try ContentInstaller.install(zip, pack: pack, root: root))
    }

    func testTraversalAndExtraOrMissingFilesNeverActivate() throws {
        for entries in [[("../escape", Data("x".utf8))], [("unlisted.py", Data("x".utf8))], []] {
            let (zip, pack, root) = try fixture(entries, inventory: [("course.json", Data("{}".utf8))])
            XCTAssertThrowsError(try ContentInstaller.install(zip, pack: pack, root: root))
            XCTAssertNil(ContentInstaller.installed(pack, root: root))
            XCTAssertFalse(FileManager.default.fileExists(atPath: root.deletingLastPathComponent().appending(path: "escape").path))
        }
        for path in ["/tmp/a", "a/../b", "a//b", "a\\b", ".", "a/./b", "a\0b"] { XCTAssertFalse(ContentInstaller.safePath(path), path) }
    }

    func testCatalogPreviewsContainNoLessonCodeAndEveryDependencyExists() throws {
        let catalog = DownloadCatalog.bundled
        XCTAssertGreaterThan(catalog.packs.count, 50)
        for course in catalog.courses {
            XCTAssertNotNil(catalog.pack("course-\(course.id)"))
            for lesson in course.lessons { XCTAssertTrue(lesson.body.isEmpty && lesson.solution.isEmpty && lesson.checks.isEmpty) }
        }
        for pack in catalog.packs {
            try ContentInstaller.validate(pack)
            XCTAssertTrue(PackDownloader.allowed(pack.url))
            for dependency in pack.dependencies { XCTAssertNotNil(catalog.pack(dependency)) }
            XCTAssertFalse(pack.files.contains { ["so", "dylib", "a"].contains(($0.path as NSString).pathExtension) })
        }
        for url in ["http://pythilo.com/a", "https://evil.com/a", "https://pythilo.com.evil.com/a", "https://u:p@pythilo.com/a"] {
            XCTAssertFalse(PackDownloader.allowed(URL(string: url)!))
        }
        XCTAssertTrue(PackDownloader.allowed(URL(string: "https://us.aws.cdn.hf.co/model")!))
    }

    func testRealCourseResumesFromPartialAndInstalls() async throws {
        let root = try temporary()
        let pack = try XCTUnwrap(DownloadCatalog.bundled.pack("course-foundations"))
        let (full, response) = try await URLSession.shared.data(from: pack.url)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertEqual(ContentInstaller.digest(full), pack.sha256)
        let partial = root.appending(path: "partial")
        try full.prefix(max(1, full.count / 3)).write(to: partial)
        let result = try await PackDownloader.fetch(pack, partial: partial) { _ in }
        XCTAssertEqual(try Data(contentsOf: result), full)
        let installed = try ContentInstaller.install(result, pack: pack, root: root.appending(path: "packs"))
        let course = try JSONDecoder().decode(Course.self, from: Data(contentsOf: installed.appending(path: "course.json")))
        XCTAssertEqual(course.id, "foundations"); XCTAssertFalse(course.lessons[0].solution.isEmpty)
    }

    @MainActor func testTemplateCodeExistsBeforePackagesFinishAndRemovalPreservesDrafts() throws {
        XCTAssertEqual(ProjectTemplate.pyTorch.requiredPacks, ["runtime-torch"])
        let store = ProjectStore(root: try temporary())
        let project = try store.create(name: "train", template: .pyTorch)
        XCTAssertTrue(FileManager.default.fileExists(atPath: project.url.appending(path: "main.py").path))
        XCTAssertEqual(project.requiredPacks, ["runtime-torch"])
        let draft = try temporary().appending(path: "draft.py")
        try Data("my code".utf8).write(to: draft)
        let downloads = ContentStore(root: try temporary())
        try downloads.remove("runtime-torch")
        XCTAssertEqual(try String(contentsOf: draft, encoding: .utf8), "my code")
    }

    @MainActor func testPauseImmediatelyResumesWithoutConcurrentPartialWriters() async throws {
        let pack = try XCTUnwrap(DownloadCatalog.bundled.pack("runtime-torch"))
        let catalog = DownloadCatalog(schema: 1, packs: [pack], courses: [])
        let store = ContentStore(catalog: catalog, root: try temporary())
        store.download(pack.id)
        let deadline = Date().addingTimeInterval(120)
        while (store.received[pack.id] ?? 0) < 64 * 1024 {
            if case .failed(let message) = store.phase(pack.id) { XCTFail(message); return }
            guard Date() < deadline else { XCTFail("No streamed progress"); return }
            try await Task.sleep(for: .milliseconds(10))
        }
        store.pause(pack.id)
        XCTAssertEqual(store.phase(pack.id), .paused)
        // Resume before the cancelled URLSession has necessarily finished unwinding.
        store.download(pack.id)
        while store.phase(pack.id) != .installed {
            if case .failed(let message) = store.phase(pack.id) { XCTFail(message); return }
            guard Date() < deadline else { XCTFail("Resume timed out"); return }
            try await Task.sleep(for: .milliseconds(30))
        }
        let location = try XCTUnwrap(store.location(pack.id))
        XCTAssertTrue(FileManager.default.fileExists(atPath: location.appending(path: "app_packages/torch/__init__.py").path))
        for file in pack.files where file.path.hasSuffix(".fwork") {
            let marker = try String(contentsOf: location.appending(path: file.path), encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
            XCTAssertTrue(FileManager.default.fileExists(atPath: Bundle.main.bundleURL.appending(path: marker).path), marker)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.root.appending(path: "partials/\(pack.sha256)").path))
        try store.remove(pack.id)
        XCTAssertNil(store.location(pack.id))
    }
}
