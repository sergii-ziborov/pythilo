import CryptoKit
import XCTest
@testable import Pythilo

/// Room links, encryption, the Python document rules, project files and the bundled codec.
@MainActor
final class PlaygroundTests: XCTestCase {
    private let origin = URL(string: "http://127.0.0.1:3212")!
    private var root: URL!

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appending(path: "rooms-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func link(readOnly: Bool = false) -> PlaygroundLink {
        PlaygroundLink(id: String(repeating: "a", count: 24), key: PlaygroundEncryption.newSecret(), access: PlaygroundEncryption.newSecret(),
                       expiresAt: Date(timeIntervalSince1970: 1_793_200_000), isReadOnly: readOnly)
    }

    // MARK: Links

    func testLinksComeFromTheConfiguredOriginOrThePythiloScheme() throws {
        let value = link(readOnly: true)
        let web = value.url(origin: origin)
        XCTAssertEqual(web.absoluteString.components(separatedBy: "#").first, "http://127.0.0.1:3212/playground/room/\(value.id)/")
        XCTAssertNil(URLComponents(url: web, resolvingAgainstBaseURL: false)?.query, "The key and capability stay in the fragment")
        XCTAssertEqual(try PlaygroundLink.parse(web.absoluteString, origin: origin), value)
        XCTAssertEqual(try PlaygroundLink.parse(value.appURL.absoluteString, origin: nil), value)
        XCTAssertTrue(value.appURL.absoluteString.hasPrefix("pythilo://playground/room/\(value.id)/#key="))
        XCTAssertTrue(try PlaygroundLink.parse(value.appURL.absoluteString, origin: nil).isReadOnly)
        let fragment = web.fragment ?? ""
        XCTAssertThrowsError(try PlaygroundLink.parse(web.absoluteString, origin: nil))
        XCTAssertThrowsError(try PlaygroundLink.parse("https://evil.example/playground/room/\(value.id)/#" + fragment, origin: origin))
        XCTAssertThrowsError(try PlaygroundLink.parse("http://127.0.0.1:3213/playground/room/\(value.id)/#" + fragment, origin: origin))
        XCTAssertThrowsError(try PlaygroundLink.parse("http://127.0.0.1:3212/playground/room/\(value.id)/", origin: origin))
        XCTAssertThrowsError(try PlaygroundLink.parse("http://127.0.0.1:3212/playground/room/short/#" + fragment, origin: origin))
        XCTAssertThrowsError(try PlaygroundLink.parse("pythilo://playground/room/\(value.id)/#" + fragment.replacingOccurrences(of: "mode=view", with: "mode=run"), origin: nil))
    }

    func testCrabrixLinksAreRefused() throws {
        let value = link()
        let fragment = value.appURL.fragment ?? ""
        XCTAssertThrowsError(try PlaygroundLink.parse("crabrix://playground/room/\(value.id)/#" + fragment, origin: origin))
        XCTAssertThrowsError(try PlaygroundLink.parse("https://crabrix.com/playground/room/\(value.id)/#" + fragment, origin: origin))
        XCTAssertThrowsError(try PlaygroundLink.parse("https://crabrix.com/playground/room/\(value.id)/#" + fragment, origin: URL(string: "https://pythilo.example")!))
    }

    func testRelayOriginIsAnHTTPSOriginOrThisDeviceInDebug() {
        XCTAssertEqual(PlaygroundRelayConfiguration.normalized("https://Rooms.Example/")?.absoluteString, "https://rooms.example")
        XCTAssertEqual(PlaygroundRelayConfiguration.normalized("https://rooms.example:443")?.absoluteString, "https://rooms.example")
        XCTAssertNil(PlaygroundRelayConfiguration.normalized(""))
        XCTAssertNil(PlaygroundRelayConfiguration.normalized("http://127.0.0.1:3212"))
        XCTAssertEqual(PlaygroundRelayConfiguration.normalized("http://127.0.0.1:3212", allowsLoopbackHTTP: true)?.absoluteString, "http://127.0.0.1:3212")
        XCTAssertNil(PlaygroundRelayConfiguration.normalized("http://rooms.example", allowsLoopbackHTTP: true))
        XCTAssertNil(PlaygroundRelayConfiguration.normalized("https://user@rooms.example"))
        XCTAssertNil(PlaygroundRelayConfiguration.normalized("https://rooms.example/api"))
        XCTAssertNil(PlaygroundRelayConfiguration.normalized("https://rooms.example/?a=1"))
        XCTAssertNil(PlaygroundRelayConfiguration.origin, "The shipped Info.plist has no relay yet")
    }

    // MARK: Encryption

    func testEncryptionUsesThePythiloNamespaceAndRefusesCrabrixPackets() throws {
        let key = PlaygroundEncryption.newSecret()
        let packet = try PlaygroundEncryption.seal(Data("print('🐍')".utf8), secret: key)
        XCTAssertEqual(try PlaygroundEncryption.open(packet, secret: key), Data("print('🐍')".utf8))
        XCTAssertThrowsError(try PlaygroundEncryption.open(packet, secret: PlaygroundEncryption.newSecret()))
        let symmetric = SymmetricKey(data: try XCTUnwrap(Data(base64URL: key)))
        let crabrix = try AES.GCM.seal(Data("fn main() {}".utf8), using: symmetric, authenticating: Data("crabrix-playground-v1".utf8))
        let foreign = PlaygroundEncryptedPacket(iv: crabrix.nonce.withUnsafeBytes { Data($0).base64URL }, data: (crabrix.ciphertext + crabrix.tag).base64URL)
        XCTAssertThrowsError(try PlaygroundEncryption.open(foreign, secret: key), "A Crabrix packet must not open as a Pythilo one")
        let box = try AES.GCM.SealedBox(nonce: AES.GCM.Nonce(data: try XCTUnwrap(Data(base64URL: packet.iv))),
                                        ciphertext: try XCTUnwrap(Data(base64URL: packet.data)).dropLast(16), tag: try XCTUnwrap(Data(base64URL: packet.data)).suffix(16))
        XCTAssertThrowsError(try AES.GCM.open(box, using: symmetric, authenticating: Data("crabrix-playground-v1".utf8)))
    }

    // MARK: Document rules

    func testPythonDocumentRules() throws {
        for path in ["main.py", "pkg/mod.pyi", "data/table.csv", "notes.MD", "requirements.txt", "LICENSE", "README", ".gitignore", "web/index.html", "q.sql", "conf/app.yaml"] {
            XCTAssertTrue(PlaygroundDocument.allows(path: path), path)
        }
        for path in ["main.rs", "Cargo.toml.bak", "image.png", ".env", "docs/LICENSE", "../main.py", "/main.py", "a\\b.py", "c:main.py", "__pycache__/m.py",
                     ".venv/lib/x.py", "venv/x.py", "lib/site-packages/x.py", ".git/x.txt", ".pythilo/room.txt", "node_modules/x.js", ".pytest_cache/v.txt",
                     "a//b.py", "./main.py", "__proto__/x.py", String(repeating: "a", count: 178) + ".py"] {
            XCTAssertFalse(PlaygroundDocument.allows(path: path), path)
        }
        XCTAssertNoThrow(try PlaygroundDocument(name: "ok", entryFile: "main.py", files: ["main.py": "print(1)\n"]).validated())
        XCTAssertThrowsError(try PlaygroundDocument(name: "no", entryFile: "notes.md", files: ["notes.md": "# x"]).validated(), "The entry file is Python")
        XCTAssertThrowsError(try PlaygroundDocument(name: "no", entryFile: "main.py", files: ["other.py": ""]).validated())
        XCTAssertThrowsError(try PlaygroundDocument(name: " ", entryFile: "main.py", files: ["main.py": ""]).validated())
        XCTAssertThrowsError(try PlaygroundDocument(name: "no", entryFile: "main.py", files: ["main.py": "\0"]).validated())
        XCTAssertThrowsError(try PlaygroundDocument(name: "no", entryFile: "main.py", files: ["main.py": String(repeating: "🐍", count: 16_385)]).validated(), "64 KiB is counted in UTF-8")
        var many = ["main.py": ""]
        for index in 0..<16 { many["m\(index).py"] = "" }
        XCTAssertThrowsError(try PlaygroundDocument(name: "no", entryFile: "main.py", files: many).validated())
        let large = String(repeating: "x", count: 60_000)
        XCTAssertThrowsError(try PlaygroundDocument(name: "no", entryFile: "main.py", files: ["main.py": large, "b.py": large, "c.py": large]).validated(), "128 KiB in all")
        XCTAssertThrowsError(try PlaygroundDocument(name: "no", entryFile: "main.py", files: ["main.py": "", "Main.py": ""]).validated(), "Case-insensitive file systems")
        XCTAssertThrowsError(try PlaygroundDocument(name: "no", entryFile: "main.py", files: ["main.py": "", "README": "", "readme/x.py": ""]).validated(), "A file and a folder with one name")
        XCTAssertThrowsError(try PlaygroundDocument(name: "no", entryFile: "main.py", files: ["main.py": "", "pkg/a.py": "", "Pkg/b.py": ""]).validated())
        XCTAssertNoThrow(try PlaygroundDocument(name: "o", entryFile: "main.py", files: ["main.py": ""], origin: .init(url: "https://github.com/octocat/Hello-World")).validated())
        XCTAssertThrowsError(try PlaygroundDocument(name: "o", entryFile: "main.py", files: ["main.py": ""], origin: .init(url: "https://play.rust-lang.org/")).validated())
    }

    // MARK: Project files

    private func write(_ files: [String: String]) throws {
        for (path, text) in files {
            let url = root.appending(path: path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    func testSharingTakesTextFilesThatFitAndSaysWhatWasLeftOut() throws {
        var files = ["main.py": "import helper\n", "helper.py": "X = 1\n", "data/table.csv": "a,b\n1,2\n", "README.md": "# Hi\n", ".env": "TOKEN=secret\n",
                     ".venv/lib/site.py": "", "__pycache__/main.cpython-314.pyc": "", ".pythilo/site-packages/pkg.py": "", "big.py": String(repeating: "#", count: 70_000)]
        for index in 0..<14 { files["extra/m\(String(format: "%02d", index)).py"] = "N = \(index)\n" }
        try write(files)
        try Data([0x89, 0x50, 0x4E, 0x47, 0, 1, 2]).write(to: root.appending(path: "logo.png"))
        try Data([0xFF, 0xFE, 0x00, 0x41]).write(to: root.appending(path: "latin.txt"))
        let selection = try PlaygroundProjectFiles.collect(from: root, name: "  demo  ")
        XCTAssertEqual(selection.document.name, "demo")
        XCTAssertEqual(selection.document.entryFile, "main.py")
        XCTAssertEqual(selection.document.files.count, 16)
        XCTAssertNotNil(selection.document.files["main.py"])
        XCTAssertNotNil(selection.document.files["helper.py"])
        XCTAssertNil(selection.document.files[".env"], "Secrets in dotfiles never join a room")
        let reasons = Dictionary(uniqueKeysWithValues: selection.leftOut.map { ($0.path, $0.reason) })
        XCTAssertEqual(reasons["big.py"], "Larger than 64 KiB")
        XCTAssertEqual(reasons["logo.png"], "Not a source or text file a room carries")
        XCTAssertEqual(reasons[".env"], "Not a source or text file a room carries")
        XCTAssertEqual(reasons["latin.txt"], "Not UTF-8 text")
        XCTAssertEqual(reasons[".venv/"], "Installed packages and environments stay on this device")
        XCTAssertNil(reasons["__pycache__/main.cpython-314.pyc"], "Generated folders are skipped without a word")
        XCTAssertNil(reasons[".pythilo/site-packages/pkg.py"])
        // Python first: the 16 places go to the entry file and Python source before CSV and Markdown.
        XCTAssertEqual(Set(selection.leftOut.filter { $0.reason == "Over the 16-file limit" }.map(\.path)), ["README.md", "data/table.csv"])
        XCTAssertThrowsError(try PlaygroundProjectFiles.collect(from: root.appending(path: "data"), name: "no python"))
    }

    func testRoomFilesAreWrittenAndRemovedOnlyInsideTheProject() throws {
        try write(["main.py": "old\n", "gone.py": "remove me\n", "local.txt": "not shared\n"])
        let outside = FileManager.default.temporaryDirectory.appending(path: "outside-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outside) }
        try FileManager.default.createSymbolicLink(at: root.appending(path: "linked"), withDestinationURL: outside)
        let document = PlaygroundDocument(name: "p", entryFile: "main.py", files: ["main.py": "new 🐍\n", "pkg/added.py": "A = 1\n", "linked/escape.py": "x\n"])
        let touched = try PlaygroundProjectFiles.write(document, to: root, removing: ["gone.py", "main.py"])
        XCTAssertEqual(try String(contentsOf: root.appending(path: "main.py"), encoding: .utf8), "new 🐍\n")
        XCTAssertEqual(try String(contentsOf: root.appending(path: "pkg/added.py"), encoding: .utf8), "A = 1\n")
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appending(path: "gone.py").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appending(path: "local.txt").path), "Files that were never in the room stay")
        XCTAssertFalse(FileManager.default.fileExists(atPath: outside.appending(path: "escape.py").path), "A symlinked folder cannot carry a write outside")
        XCTAssertEqual(touched, ["main.py", "pkg/added.py", "gone.py"])
        XCTAssertEqual(try PlaygroundProjectFiles.write(document, to: root, removing: []), [], "Unchanged text is not rewritten")
    }

    // MARK: Codec

    func testRuntimeSourceIdentityMatchesTheWebsiteAndIgnoresOrigin() throws {
        var document = PlaygroundDocument(name: "Unicode 🐍", entryFile: "main.py", files: ["🐍.py": "N = 1\n", "main.py": "print(\"🐍\")\n", "é.py": "# café\n"])
        let codec = try PlaygroundCodec()
        _ = try codec.initialize(document)
        let original = try codec.runtimeSourceIdentity()
        // sha256(JSON.stringify(["pythilo-runtime-source-v1", name, entryFile, sortedEntries])) in Node.
        XCTAssertEqual(original.revision, "5e41cbb94303bb6b4a412a98f5547e49754572ca5a9bcb52a844bb1f780fec74")
        XCTAssertEqual(original.paths, ["main.py", "é.py", "🐍.py"])
        document.origin = .init(url: "https://github.com/example/source", commit: String(repeating: "a", count: 40))
        _ = try codec.replace(document)
        XCTAssertEqual(try codec.runtimeSourceIdentity(), original)
        document.name = "Renamed"
        _ = try codec.replace(document)
        XCTAssertNotEqual(try codec.runtimeSourceIdentity().revision, original.revision)
        document.name = "Unicode 🐍"
        document.files["é.py"] = "# cafe\u{301}\n"
        _ = try codec.replace(document)
        XCTAssertNotEqual(try codec.runtimeSourceIdentity().revision, original.revision, "Exact source bytes, not normalized text")
    }

    func testCollidingUnicodeOrCasePathIsRefusedWithoutChangingSource() throws {
        let codec = try PlaygroundCodec()
        let source = PlaygroundDocument(name: "kept", entryFile: "main.py", files: ["main.py": "pass\n", "é.py": "original\n"])
        _ = try codec.initialize(source)
        let original = try codec.runtimeSourceIdentity()
        XCTAssertThrowsError(try codec.call(["type": "file", "path": "e\u{301}.py", "text": "ambiguous\n"]))
        XCTAssertThrowsError(try codec.call(["type": "file", "path": "MAIN.py", "text": "ambiguous\n"]))
        XCTAssertEqual(try codec.call(["type": "document"]).document, source)
        XCTAssertEqual(try codec.runtimeSourceIdentity(), original)
    }

    func testCrabrixDocumentIsRefusedByTheCodec() throws {
        let codec = try PlaygroundCodec()
        let crabrix: [String: Any] = ["schemaVersion": 1, "name": "rust", "entryFile": "main.rs", "edition": "2024", "files": ["main.rs": "fn main() {}"]]
        XCTAssertThrowsError(try codec.call(["type": "initialize", "document": crabrix]))
        XCTAssertThrowsError(try codec.call(["type": "state", "snapshot": "", "events": [String](), "codec": 2]), "Only format v1")
    }

    func testFragmentsStayOutOfHTTPAndTheCodecRoundTripsUnicode() throws {
        let value = link(readOnly: true)
        let source = try PlaygroundDocument(name: "Unicode", entryFile: "main.py", files: ["main.py": "print(\"🐍 Привет\")\n"]).validated()
        let codec = try PlaygroundCodec()
        _ = try codec.initialize(source)
        let snapshot = try XCTUnwrap(try codec.call(["type": "snapshot"]).snapshot)
        let packet = try PlaygroundEncryption.seal(PlaygroundCodec.bytes(snapshot), secret: value.key)
        let restored = try PlaygroundEncryption.open(packet, secret: value.key)
        let other = try PlaygroundCodec()
        XCTAssertEqual(try other.call(["type": "state", "snapshot": restored.base64EncodedString(), "events": [String](), "codec": 1]).document, source)
        XCTAssertThrowsError(try PlaygroundEncryption.open(packet, secret: PlaygroundEncryption.newSecret()))
    }

    func testConcurrentEditsAndSelectionsUseStableTextPositions() throws {
        let first = try PlaygroundCodec(), second = try PlaygroundCodec()
        _ = try first.initialize(PlaygroundDocument(name: "merge", entryFile: "main.py", files: ["main.py": "hello 🐍 world"]))
        let snapshot = try XCTUnwrap(try first.call(["type": "snapshot"]).snapshot)
        _ = try second.call(["type": "state", "snapshot": snapshot, "events": [String]()])
        let selection = try XCTUnwrap(try second.call(["type": "selection", "file": "main.py", "anchor": 6, "head": 8]).presence)
        _ = try first.call(["type": "presence", "bytes": selection])
        let left = try XCTUnwrap(try first.call(["type": "file", "path": "main.py", "text": "prefix hello 🐍 world"]).update)
        let right = try XCTUnwrap(try second.call(["type": "file", "path": "main.py", "text": "hello 🐍 world suffix"]).update)
        let a = try first.call(["type": "update", "bytes": right])
        let b = try second.call(["type": "update", "bytes": left])
        XCTAssertEqual(a.document, b.document)
        XCTAssertEqual(a.document?.files["main.py"], "prefix hello 🐍 world suffix")
        XCTAssertEqual(a.selections?.first?.anchor, 13)
        XCTAssertEqual(a.selections?.first?.head, 15)
    }

    func testChangingAnEmojiDoesNotSplitItsUTF16Pair() throws {
        let codec = try PlaygroundCodec()
        _ = try codec.initialize(PlaygroundDocument(name: "emoji", entryFile: "main.py", files: ["main.py": "# 🐍 Python 🐍"]))
        XCTAssertEqual(try codec.call(["type": "file", "path": "main.py", "text": "# 🦎 Python 🐉"]).document?.files["main.py"], "# 🦎 Python 🐉")
    }

    func testCodecKeepsSourceOriginsAndRejectsCredentials() throws {
        for url in ["https://github.com/octocat/Hello-World", "https://gist.github.com/example/0123456789abcdef"] {
            let source = PlaygroundDocument(name: "origin", entryFile: "main.py", files: ["main.py": "pass\n"], origin: .init(url: url))
            let first = try PlaygroundCodec()
            XCTAssertEqual(try first.initialize(source).document?.origin, source.origin)
            let snapshot = try XCTUnwrap(try first.call(["type": "snapshot"]).snapshot)
            XCTAssertEqual(try PlaygroundCodec().call(["type": "state", "snapshot": snapshot, "events": [String]()]).document?.origin, source.origin)
        }
        let codec = try PlaygroundCodec()
        for origin in ["https://user:password@github.com/repository", "https://evil.example/repository", "http://github.com/repository", "https://play.rust-lang.org/"] {
            let document: [String: Any] = ["schemaVersion": 1, "name": "invalid", "entryFile": "main.py", "files": ["main.py": "pass\n"], "origin": ["url": origin]]
            XCTAssertThrowsError(try codec.call(["type": "initialize", "document": document]), origin)
        }
    }

    func testDisplayNameReachesOtherParticipants() throws {
        let first = try PlaygroundCodec(), second = try PlaygroundCodec()
        _ = try first.initialize(PlaygroundDocument(name: "names", entryFile: "main.py", files: ["main.py": "print('hi')\n"]))
        let snapshot = try XCTUnwrap(try first.call(["type": "snapshot"]).snapshot)
        _ = try second.call(["type": "state", "snapshot": snapshot, "events": [String]()])
        _ = try first.call(["type": "identity", "name": "Serhii"])
        let presence = try XCTUnwrap(try first.call(["type": "selection", "file": "main.py", "anchor": 0, "head": 5]).presence)
        let received = try second.call(["type": "presence", "bytes": presence])
        XCTAssertEqual(received.selections?.first?.name, "Serhii")
        XCTAssertEqual(received.participants, 2)
        XCTAssertThrowsError(try first.call(["type": "identity", "name": String(repeating: "x", count: 41)]))
    }

    func testNearbyParticipantBadgesStayInsideCanvasWithoutCoveringEachOther() throws {
        for width in [CGFloat(240), 402, 1024] {
            let bounds = CGRect(x: 0, y: 0, width: width, height: 200)
            var frames: [CGRect] = []
            for nameWidth in [CGFloat(95), 130, 170] {
                let frame = try XCTUnwrap(PlaygroundSelectionOverlay.badgeFrame(preferred: CGRect(x: width - 60, y: 0, width: nameWidth, height: 16), inside: bounds, occupied: frames))
                XCTAssertTrue(bounds.contains(frame))
                XCTAssertTrue(frames.allSatisfy { !$0.intersects(frame) })
                frames.append(frame)
            }
        }
        XCTAssertNil(PlaygroundSelectionOverlay.badgeFrame(preferred: CGRect(x: 0, y: 0, width: 120, height: 16), inside: .zero, occupied: []))
    }
}
