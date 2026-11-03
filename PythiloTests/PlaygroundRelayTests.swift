import XCTest
@testable import Pythilo

/// Against the website's relay on this Mac (http://127.0.0.1:3212). Skipped when it is not running.
@MainActor
final class PlaygroundRelayTests: XCTestCase {
    private let origin = URL(string: "http://127.0.0.1:3212")!
    private var cleanup: [URL] = []

    override func setUp() async throws {
        var request = URLRequest(url: origin.appending(path: "healthz/"))
        request.timeoutInterval = 2
        guard let (_, response) = try? await URLSession.shared.data(for: request), (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw XCTSkip("The relay is not running on 127.0.0.1:3212.")
        }
    }

    override func tearDown() async throws {
        for url in cleanup { try? FileManager.default.removeItem(at: url) }
        ProjectStore.shared.refresh()
    }

    private func wait(_ what: String, timeout: TimeInterval = 20, _ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            guard Date() < deadline else { throw PlaygroundFailure("Timed out waiting for \(what).") }
            try await Task.sleep(for: .milliseconds(50))
        }
    }

    private func project(_ files: [String: String]) throws -> Project {
        let url = FileManager.default.temporaryDirectory.appending(path: "relay-\(UUID().uuidString)")
        cleanup.append(url)
        for (path, text) in files {
            try FileManager.default.createDirectory(at: url.appending(path: path).deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: url.appending(path: path), atomically: true, encoding: .utf8)
        }
        return Project(url: url)
    }

    func testShareJoinAndEditBothWaysThroughTheRelay() async throws {
        let owned = try project(["main.py": "print('owner 🐍')\n", "helper.py": "X = 1\n"])
        let selection = try PlaygroundProjectFiles.collect(from: owned.url, name: "relay-loopback")
        let owner = try await PlaygroundRoom.share(owned, selection: selection, lifetimeSeconds: 120, editing: true, policy: .off, origin: origin)
        defer { owner.close() }
        let link = try PlaygroundLink.parse(owner.shareURL.absoluteString, origin: origin)
        XCTAssertEqual(link, owner.session.link)
        let guest = try PlaygroundRoom.join(try PlaygroundLink.parse(link.appURL.absoluteString, origin: nil), origin: origin)
        defer { guest.close() }
        try await wait("the guest's project") { guest.project != nil }
        let joined = try XCTUnwrap(guest.project)
        cleanup.append(joined.url)
        XCTAssertEqual(try String(contentsOf: joined.url.appending(path: "main.py"), encoding: .utf8), "print('owner 🐍')\n")
        XCTAssertEqual(PlaygroundRoom.roomTag(of: joined.url), link.id)

        // A file changed on the owner's disk reaches the guest's folder.
        try "print('changed on disk')\n".write(to: owned.url.appending(path: "main.py"), atomically: true, encoding: .utf8)
        try await wait("the disk change") { (try? String(contentsOf: joined.url.appending(path: "main.py"), encoding: .utf8)) == "print('changed on disk')\n" }
        // Typing on the guest reaches the owner's folder; a new file joins.
        guest.edited(path: "helper.py", text: "X = 2\n")
        try "N = 3\n".write(to: joined.url.appending(path: "added.py"), atomically: true, encoding: .utf8)
        try await wait("the guest's edits") {
            (try? String(contentsOf: owned.url.appending(path: "helper.py"), encoding: .utf8)) == "X = 2\n"
                && (try? String(contentsOf: owned.url.appending(path: "added.py"), encoding: .utf8)) == "N = 3\n"
        }
        // A deletion travels too.
        try FileManager.default.removeItem(at: owned.url.appending(path: "added.py"))
        try await wait("the deletion") { !FileManager.default.fileExists(atPath: joined.url.appending(path: "added.py").path) }
        XCTAssertEqual(owner.session.participants, 2)

        try await owner.end()
        try await wait("the guest to see the end") { guest.ended }
    }

    func testDeviceRunsACommandForAControllerAndSaysWhereItRan() async throws {
        let deadline = Date().addingTimeInterval(60)
        while RunSession.shared.pythonVersion == nil || RunSession.shared.phase != .idle {
            guard Date() < deadline else { throw XCTSkip("Python did not start") }
            try await Task.sleep(for: .milliseconds(50))
        }
        let owned = try project(["main.py": "print('ran for the room')\n"])
        let selection = try PlaygroundProjectFiles.collect(from: owned.url, name: "relay-host")
        let owner = try await PlaygroundRoom.share(owned, selection: selection, lifetimeSeconds: 120, editing: true, policy: .ask, origin: origin)
        defer { owner.close() }
        let controller = try PlaygroundLiveSession(link: owner.session.link, origin: origin)
        let signer = PlaygroundRuntimeSigner()
        defer { controller.stop(); signer.destroy() }
        controller.start()
        try await wait("both connections") { owner.session.connected && controller.connected }
        try await controller.confirmRuntimeEditAccess()
        let room = owner.id

        // The host advertises itself: kind, name, runtime fingerprint and operations.
        var host: String?
        try await wait("the host's capabilities") {
            for frame in controller.runtimeFrames {
                guard let verified = try? PlaygroundRuntimeProtocol.verify(Data(frame.envelope.utf8), context: .init(room: room, editCapability: controller.link.access)),
                      verified.header.kind == "capabilities",
                      let payload = (try? JSONSerialization.jsonObject(with: verified.payload)) as? [String: Any],
                      payload["role"] as? String == "host", payload["kind"] as? String == "ios",
                      payload["operations"] as? [String] == ["check", "run", "test"],
                      (payload["runtime"] as? String)?.hasPrefix("CPython 3.14") == true else { continue }
                host = verified.header.sender
                return true
            }
            return false
        }
        let target = try XCTUnwrap(host)
        let revision = try controller.runtimeSourceIdentity().revision

        func exchange(_ kind: String, _ operation: String, job: String = "", payload: [String: Any]) async throws -> [String: Any] {
            let requestID = PlaygroundEncryption.newSecret().prefix(24).description
            let envelope = try signer.sign(.init(kind: kind, room: room, target: target, requestID: requestID, operation: operation, revision: revision, job: job),
                                           payload: try JSONSerialization.data(withJSONObject: payload), editCapability: controller.link.access)
            var reply: [String: Any]?
            var sent = Date.distantPast
            try await wait("a reply to \(operation)", timeout: 30) {
                if Date().timeIntervalSince(sent) > 1.5 {
                    try? controller.publishRuntimePresence(envelope)
                    sent = Date()
                }
                for frame in controller.runtimeFrames {
                    guard let verified = try? PlaygroundRuntimeProtocol.verify(Data(frame.envelope.utf8), context: .init(room: room, target: signer.fingerprint, sender: target, editCapability: controller.link.access)),
                          verified.header.kind == "response", verified.header.requestID == requestID else { continue }
                    reply = (try? JSONSerialization.jsonObject(with: verified.payload)) as? [String: Any]
                    return true
                }
                return false
            }
            return try XCTUnwrap(reply)
        }

        let granted = try await exchange("permission-request", "grant", payload: ["name": "Claude · MCP", "operations": ["check", "run"]])
        XCTAssertEqual(granted["ok"] as? Bool, true, "\(granted)")
        let grant = try XCTUnwrap(granted["grant"] as? String)
        XCTAssertEqual(granted["profile"] as? String, "python3-v1")
        let started = try await exchange("command", "run", payload: ["grant": grant])
        XCTAssertEqual(started["ok"] as? Bool, true, "\(started)")
        let job = try XCTUnwrap(started["job"] as? String)

        // Ask each time: nothing runs until the owner presses Run once.
        try await wait("the owner's approval card") { !owner.host.approvals.isEmpty }
        let approval = try XCTUnwrap(owner.host.approvals.first)
        XCTAssertEqual(approval.requester, "Claude · MCP")
        XCTAssertEqual(approval.command, "python main.py")
        XCTAssertTrue(owner.host.history.isEmpty)
        owner.host.approve(approval)
        try await wait("the run to finish", timeout: 60) { owner.host.history.first?.id == job }
        var status = try await exchange("command", "status", job: job, payload: ["grant": grant])
        for _ in 0..<10 where status["state"] as? String != "finished" {
            try await Task.sleep(for: .seconds(1))
            status = try await exchange("command", "status", job: job, payload: ["grant": grant])
        }
        XCTAssertEqual(status["state"] as? String, "finished", "\(status)")
        XCTAssertEqual(status["exitCode"] as? Int, 0)
        XCTAssertEqual(status["revision"] as? String, revision)
        XCTAssertEqual((status["ranOn"] as? [String: Any])?["kind"] as? String, "ios")
        XCTAssertEqual((status["ranOn"] as? [String: Any])?["name"] as? String, PlaygroundRuntimeHost.deviceName)
        XCTAssertTrue((status["runtime"] as? String)?.hasPrefix("CPython 3.14") == true)
        let output = try await exchange("command", "stdout", job: job, payload: ["grant": grant])
        XCTAssertEqual(output["text"] as? String, "ran for the room\n")
        XCTAssertEqual(try String(contentsOf: owned.url.appending(path: "main.py"), encoding: .utf8), "print('ran for the room')\n")
    }
}
