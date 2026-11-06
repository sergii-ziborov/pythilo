import XCTest
@testable import Pythilo

@MainActor enum DownloadTestSupport {
    static func ensureAll() async throws {
        let store = ContentStore.shared
        for pack in store.catalog.packs { store.download(pack.id) }
        let deadline = Date().addingTimeInterval(300)
        while !store.catalog.packs.allSatisfy({ store.ready($0.id) }) {
            for pack in store.catalog.packs {
                if case .failed(let message) = store.phase(pack.id) {
                    XCTFail("\(pack.id): \(message)")
                    throw ContentFailure.invalid(message)
                }
            }
            guard Date() < deadline else { throw ContentFailure.invalid("Timed out downloading test content") }
            try await Task.sleep(for: .milliseconds(100))
        }
        CourseLibrary.shared.reload()
        for pack in store.catalog.packs where pack.kind == "runtime" {
            let folder = try XCTUnwrap(store.location(pack.id))
            for file in pack.files where file.path.hasSuffix(".fwork") {
                let marker = try String(contentsOf: folder.appending(path: file.path), encoding: .utf8)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard marker.hasPrefix("Frameworks/"), ContentInstaller.safePath(marker),
                      FileManager.default.fileExists(atPath: Bundle.main.bundleURL.appending(path: marker).path) else {
                    throw ContentFailure.invalid("\(pack.id): native backend marker does not resolve: \(marker)")
                }
            }
        }
    }
}
