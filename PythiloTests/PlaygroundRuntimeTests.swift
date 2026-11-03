import CryptoKit
import XCTest
@testable import Pythilo

/// The signed runtime protocol, profile python3-v1, the bundled policy and host,
/// and shared jobs on the embedded interpreter.
@MainActor
final class PlaygroundRuntimeTests: XCTestCase {
    private typealias Wire = PlaygroundRuntimeProtocol
    private let now: Int64 = 1_000_000
    private let room = String(repeating: "a", count: 24), target = String(repeating: "b", count: 64)
    // Public test vector capability, never a room credential.
    private let capability = String(repeating: "A", count: 43)
    private var fields: Wire.Fields { .init(kind: "command", room: room, target: target, requestID: "runtime-request-0001", operation: "check", revision: String(repeating: "c", count: 64)) }
    private var context: Wire.VerificationContext { .init(room: room, target: target, editCapability: capability, requireEditProof: true) }
    private let payload = Data("{\"text\":\"🐍 Привет\"}".utf8)

    private func signed(_ signer: PlaygroundRuntimeSigner, at time: Int64? = nil) throws -> Data {
        try signer.sign(fields, payload: payload, editCapability: capability, now: time ?? now)
    }

    private func altered(_ original: Data, _ edit: (inout [String: Any]) -> Void) throws -> Data {
        var value = try XCTUnwrap(try JSONSerialization.jsonObject(with: original) as? [String: Any])
        edit(&value)
        return try JSONSerialization.data(withJSONObject: value)
    }

    // MARK: Envelope

    func testWebCryptoVectorVerifiesInCryptoKit() throws {
        let vector = Data(Self.webCryptoVector.utf8)
        let frame = try Wire.verify(vector, context: context, clock: { self.now })
        XCTAssertEqual(String(data: frame.payload, encoding: .utf8), "{\"text\":\"WebCrypto → CryptoKit 🐍\"}")
        XCTAssertEqual(frame.header.operation, "run")
        XCTAssertEqual(frame.header.requestID, "signed-vector-0001")
        XCTAssertTrue(frame.editAccessProved)
        var wrong = context
        wrong.editCapability = PlaygroundEncryption.newSecret()
        XCTAssertThrowsError(try Wire.verify(vector, context: wrong, clock: { self.now }))
    }

    func testCrabrixEnvelopesAreRefused() throws {
        // A genuine Crabrix envelope, valid in its own namespace.
        XCTAssertThrowsError(try Wire.verify(Data(Self.crabrixVector.utf8), context: context, clock: { self.now }))
        let signer = PlaygroundRuntimeSigner()
        defer { signer.destroy() }
        let renamed = try altered(try signed(signer)) { value in
            var header = value["header"] as! [Any]
            header[0] = "crabrix-runtime-v1"
            value["header"] = header
        }
        XCTAssertThrowsError(try Wire.verify(renamed, context: context, clock: { self.now }))
        // Crabrix's build and debug are not part of python3-v1; test is.
        for operation in ["build", "debug", "step", "locals"] {
            XCTAssertThrowsError(try signer.sign(.init(kind: "command", room: room, target: target, requestID: "runtime-request-0002", operation: operation), payload: payload, now: now))
        }
        XCTAssertNoThrow(try signer.sign(.init(kind: "command", room: room, target: target, requestID: "runtime-request-0003", operation: "test"), payload: payload, now: now))
    }

    func testSignerUsesRawKeysSignaturesAndOwnedUnicodeBytes() throws {
        let signer = PlaygroundRuntimeSigner(), data = try signed(signer)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(Data(base64URL: try XCTUnwrap(object["key"] as? String))?.count, 65)
        XCTAssertEqual(Data(base64URL: try XCTUnwrap(object["signature"] as? String))?.count, 64)
        XCTAssertEqual(Data(base64URL: try XCTUnwrap(object["editProof"] as? String))?.count, 32)
        XCTAssertEqual((object["header"] as? [Any])?.first as? String, "pythilo-runtime-v1")
        let frame = try Wire.verify(data, context: context, clock: { self.now })
        XCTAssertEqual(frame.payload, payload)
        XCTAssertEqual(frame.header.sender, signer.fingerprint)
        XCTAssertTrue(frame.editAccessProved)
        let withoutProof = try signer.sign(fields, payload: payload, now: now)
        XCTAssertFalse(try Wire.verify(withoutProof, context: .init(room: room, target: target), clock: { self.now }).editAccessProved)
        signer.destroy()
        XCTAssertThrowsError(try signed(signer))
    }

    func testWrongRoomTargetIdentityPayloadHeaderAndEditProofAreRefused() throws {
        let signer = PlaygroundRuntimeSigner(), original = try signed(signer)
        var wrong = context
        wrong.target = String(repeating: "d", count: 64)
        XCTAssertThrowsError(try Wire.verify(original, context: wrong, clock: { self.now }))
        wrong = .init(room: String(repeating: "d", count: 24))
        XCTAssertThrowsError(try Wire.verify(original, context: wrong, clock: { self.now }))
        wrong = context
        wrong.sender = String(repeating: "d", count: 64)
        XCTAssertThrowsError(try Wire.verify(original, context: wrong, clock: { self.now }))
        let other = PlaygroundRuntimeSigner()
        let changes: [(inout [String: Any]) -> Void] = [
            { $0["key"] = other.key }, { $0["payload"] = Data("{}".utf8).base64URL },
            { value in var h = value["header"] as! [Any]; h[6] = "run"; value["header"] = h },
            { $0.removeValue(forKey: "editProof") }, { $0["editProof"] = PlaygroundEncryption.newSecret() },
        ]
        for change in changes { XCTAssertThrowsError(try Wire.verify(try altered(original, change), context: context, clock: { self.now })) }
        signer.destroy()
        other.destroy()
    }

    func testTimeAndProofAreRecheckedWithoutAcceptingBooleanOrUnsafeIntegers() throws {
        let signer = PlaygroundRuntimeSigner()
        let short = try signer.sign(fields, payload: payload, editCapability: capability, now: now, lifetime: 100)
        XCTAssertThrowsError(try Wire.verify(short, context: context, clock: { self.now + 100 }))
        var calls = 0
        XCTAssertThrowsError(try Wire.verify(short, context: context, clock: { calls += 1; return self.now + (calls == 1 ? 0 : 100) }))
        XCTAssertThrowsError(try Wire.verify(try signed(signer, at: now + 6_000), context: context, clock: { self.now }))
        XCTAssertThrowsError(try signer.sign(fields, payload: payload, now: now, lifetime: 15_001))
        XCTAssertThrowsError(try signer.sign(fields, payload: payload, now: Int64.max))
        let good = try signed(signer)
        for badTime: Any in [true, -1, 1.25, 9_007_199_254_740_992 as Int64] {
            let changed = try altered(good) { value in var h = value["header"] as! [Any]; h[10] = badTime; value["header"] = h }
            XCTAssertThrowsError(try Wire.verify(changed, context: context, clock: { self.now }))
        }
        signer.destroy()
    }

    func testStrictEnvelopeEncodingKindsAndPayloadBudget() throws {
        let signer = PlaygroundRuntimeSigner(), good = try signed(signer)
        let changes: [(inout [String: Any]) -> Void] = [
            { $0["v"] = true }, { $0["extra"] = "not allowed" }, { $0["key"] = 123 }, { $0["editProof"] = NSNull() },
            { $0["signature"] = ($0["signature"] as! String) + "=" },
            { value in var h = value["header"] as! [Any]; h[1] = "capabilities"; value["header"] = h },
            { value in var h = value["header"] as! [Any]; h[9] = String(repeating: "A", count: 42) + "B"; value["header"] = h },
        ]
        for change in changes { XCTAssertThrowsError(try Wire.verify(try altered(good, change), context: context, clock: { self.now })) }
        XCTAssertThrowsError(try Wire.verify(Data(repeating: 32, count: 2_401), context: context, clock: { self.now }))
        let exact = Data(("\"" + String(repeating: "a", count: 766) + "\"").utf8)
        XCTAssertEqual(exact.count, Wire.payloadBytes)
        _ = try signer.sign(fields, payload: exact, now: now)
        XCTAssertThrowsError(try signer.sign(fields, payload: Data(("\"" + String(repeating: "a", count: 767) + "\"").utf8), now: now))
        XCTAssertThrowsError(try signer.sign(fields, payload: Data("not JSON".utf8), now: now))
        signer.destroy()
    }

    func testDuplicateMessagesStayDuplicateUnderNonceFloodAndExpiredEntriesArePruned() throws {
        let signer = PlaygroundRuntimeSigner(), replay = PlaygroundRuntimeReplayWindow()
        let first = try Wire.verify(try signed(signer), context: context, clock: { self.now })
        XCTAssertEqual(try replay.consume(first, now: now), .new)
        XCTAssertEqual(try replay.consume(first, now: now), .duplicate)
        for _ in 1..<Wire.replayEntries {
            let next = try Wire.verify(try signed(signer), context: context, clock: { self.now })
            XCTAssertEqual(try replay.consume(next, now: now), .new)
        }
        let overflow = try Wire.verify(try signed(signer), context: context, clock: { self.now })
        XCTAssertThrowsError(try replay.consume(overflow, now: now))
        XCTAssertEqual(try replay.consume(first, now: now), .duplicate)
        let later = now + Wire.lifetimeMilliseconds + 1
        XCTAssertThrowsError(try replay.consume(first, now: later))
        let fresh = try Wire.verify(try signed(signer, at: later), context: context, clock: { later })
        XCTAssertEqual(try replay.consume(fresh, now: later), .new)
        signer.destroy()
    }

    func testIdentifyShowsWhoIsThereWithoutTrustingAnUncheckedEditProof() throws {
        let signer = PlaygroundRuntimeSigner()
        defer { signer.destroy() }
        let live = Wire.milliseconds()
        let envelope = try signer.sign(.init(kind: "capabilities", room: room, target: "", requestID: "identify-request-0001", operation: "discover"),
                                       payload: Data("{\"role\":\"controller\",\"name\":\"Claude · MCP\"}".utf8), editCapability: capability, now: live)
        XCTAssertTrue(try Wire.identify(envelope, room: room, editCapability: capability).editAccessProved)
        XCTAssertFalse(try Wire.identify(envelope, room: room, editCapability: nil).editAccessProved)
        XCTAssertFalse(try Wire.identify(envelope, room: room, editCapability: PlaygroundEncryption.newSecret()).editAccessProved)
        XCTAssertThrowsError(try Wire.identify(envelope, room: String(repeating: "d", count: 24), editCapability: nil))
    }

    func testNativeCryptographicServicesAreBoundedVerificationOnly() throws {
        let digest = PlaygroundRuntimeCryptography.call("{\"op\":\"digest\",\"data\":[97,98,99]}")
        let value = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(digest.utf8)) as? [String: Any])
        let bytes = try XCTUnwrap(value["bytes"] as? [UInt8])
        XCTAssertEqual(bytes.map { String(format: "%02x", $0) }.joined(), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        for invalid in ["{\"op\":\"execute\",\"data\":[]}", "{\"op\":\"digest\",\"data\":[true]}", "{\"op\":\"digest\",\"data\":[256]}", String(repeating: " ", count: 16_385)] {
            XCTAssertTrue(PlaygroundRuntimeCryptography.call(invalid).contains("error"))
        }
        let oversized = try JSONSerialization.data(withJSONObject: ["op": "digest", "data": [UInt8](repeating: 1, count: 2_049)])
        XCTAssertTrue(PlaygroundRuntimeCryptography.call(String(decoding: oversized, as: UTF8.self)).contains("error"))
    }

    // MARK: Bundled policy and host

    private func hostContext(_ host: PlaygroundRuntimeSigner, revision: String, busy: Bool = false, editConfirmed: Bool = true) -> [String: Any] {
        ["room": room, "target": host.fingerprint, "scope": "ios-room:1", "revision": revision, "editCapability": capability,
         "expires": Wire.milliseconds() + 3_600_000, "foreground": true, "connected": true, "editConfirmed": editConfirmed, "ready": true, "busy": busy,
         "name": "Serhii's iPhone", "kind": "ios", "runtime": "CPython 3.14.0 · iOS 26", "profile": Wire.profile,
         "operations": Wire.startOperations, "debug": false, "profileReady": true, "paths": ["main.py"], "lines": [1]]
    }

    private func response(_ publication: PlaygroundRuntimeHostReply.Publication) throws -> [String: Any] {
        try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(publication.payloadJSON.utf8)) as? [String: Any])
    }

    func testHostCoreGrantsRunsAndReportsWhereAJobRan() async throws {
        let codec = try PlaygroundCodec(), controller = PlaygroundRuntimeSigner(), host = PlaygroundRuntimeSigner()
        defer { controller.destroy(); host.destroy() }
        _ = try codec.initialize(PlaygroundDocument(name: "hosted", entryFile: "main.py", files: ["main.py": "print('hi')\n"]))
        let revision = try codec.runtimeSourceIdentity().revision
        let context = hostContext(host, revision: revision)
        let initialized = try await codec.runtimeHostCall(["action": "initialize", "context": context])
        XCTAssertNil(initialized.error)
        let advertised = try XCTUnwrap(initialized.publications?.first { $0.fields.kind == "capabilities" })
        let capabilities = try response(advertised)
        XCTAssertEqual(capabilities["kind"] as? String, "ios")
        XCTAssertEqual(capabilities["name"] as? String, "Serhii's iPhone")
        XCTAssertEqual(capabilities["runtime"] as? String, "CPython 3.14.0 · iOS 26")
        XCTAssertEqual(capabilities["profile"] as? String, "python3-v1")
        XCTAssertEqual(capabilities["operations"] as? [String], ["check", "run", "test"])

        let request = try controller.sign(.init(kind: "permission-request", room: room, target: host.fingerprint, requestID: "native-permission-001", operation: "grant", revision: revision),
                                          payload: Data("{\"name\":\"Claude · MCP\",\"operations\":[\"check\",\"run\"]}".utf8), editCapability: capability)
        let pending = try await codec.runtimeHostCall(["action": "frame", "context": context, "envelope": String(decoding: request, as: UTF8.self)])
        XCTAssertNil(pending.grant, "A request alone grants nothing")
        XCTAssertEqual(pending.requests?.first?.name, "Claude · MCP")
        let allowed = try await codec.runtimeHostCall(["action": "allow", "context": context, "controller": controller.fingerprint, "requestID": "native-permission-001", "operations": ["run"], "lifetimeMs": 600_000])
        let grant = try XCTUnwrap(allowed.grant)
        XCTAssertEqual(grant.operations, ["run"])
        XCTAssertLessThanOrEqual(grant.expires, Wire.milliseconds() + 600_000)

        let start = try controller.sign(.init(kind: "command", room: room, target: host.fingerprint, requestID: "native-run-0000001", operation: "run", revision: revision),
                                        payload: try JSONSerialization.data(withJSONObject: ["grant": grant.id]), editCapability: capability)
        let started = try await codec.runtimeHostCall(["action": "frame", "context": context, "envelope": String(decoding: start, as: UTF8.self)])
        let effect = try XCTUnwrap(started.effects?.first)
        XCTAssertEqual(effect.type, "start")
        XCTAssertEqual(effect.operation, "run")
        XCTAssertEqual(started.jobs?.first?.controller, controller.fingerprint)
        let check = try controller.sign(.init(kind: "command", room: room, target: host.fingerprint, requestID: "native-check-000001", operation: "check", revision: revision),
                                        payload: try JSONSerialization.data(withJSONObject: ["grant": grant.id]), editCapability: capability)
        let refused = try await codec.runtimeHostCall(["action": "frame", "context": context, "envelope": String(decoding: check, as: UTF8.self)])
        XCTAssertTrue(refused.effects?.isEmpty == true, "An operation that was not granted never starts")

        _ = try await codec.runtimeHostCall(["action": "update", "context": context, "job": effect.job, "update": [
            "state": "finished", "stage": "Ran on Serhii's iPhone · exit 0", "succeeded": true, "exitCode": 0, "durationMs": 42, "stdout": "hi\n", "stderr": "",
        ]])
        let status = try controller.sign(.init(kind: "command", room: room, target: host.fingerprint, requestID: "native-status-00001", operation: "status", revision: revision, job: effect.job),
                                         payload: try JSONSerialization.data(withJSONObject: ["grant": grant.id]), editCapability: capability)
        let reply = try await codec.runtimeHostCall(["action": "frame", "context": context, "envelope": String(decoding: status, as: UTF8.self)])
        let publication = try XCTUnwrap(reply.publications?.first { $0.fields.kind == "response" && $0.fields.operation == "status" })
        let result = try response(publication)
        XCTAssertEqual(result["state"] as? String, "finished")
        XCTAssertEqual(result["exitCode"] as? Int, 0)
        XCTAssertEqual(result["durationMs"] as? Int, 42)
        XCTAssertEqual(result["revision"] as? String, revision)
        XCTAssertEqual(result["runtime"] as? String, "CPython 3.14.0 · iOS 26")
        XCTAssertEqual((result["ranOn"] as? [String: Any])?["kind"] as? String, "ios")
        XCTAssertEqual((result["ranOn"] as? [String: Any])?["name"] as? String, "Serhii's iPhone")
        XCTAssertNotNil(result["startedAt"] as? Int64 ?? (result["startedAt"] as? NSNumber)?.int64Value)
    }

    func testHostDisplaysSignedPeerOutputWithoutAnyExecutionOrGrant() async throws {
        let codec = try PlaygroundCodec(), peer = PlaygroundRuntimeSigner(), host = PlaygroundRuntimeSigner()
        defer { peer.destroy(); host.destroy() }
        let document = PlaygroundDocument(name: "passive", entryFile: "main.py", files: ["main.py": "print(1)\n"])
        _ = try codec.initialize(document)
        let revision = try codec.runtimeSourceIdentity().revision
        var local = hostContext(host, revision: revision, editConfirmed: false)
        local["editCapability"] = String(repeating: "V", count: 43)
        _ = try await codec.runtimeHostCall(["action": "initialize", "context": local])
        let payload: [String: Any] = ["role": "host", "kind": "browser", "name": "Ada", "runtime": "Pyodide 314.0.7 · Python 3.14", "profile": "python3-v1",
                                      "output": ["id": "peer-output-12345678", "operation": "run", "startedAt": 1, "durationMs": 5, "stdout": "hello 🐍", "stderr": "", "truncated": false, "succeeded": true, "exitCode": 0]]
        let envelope = try peer.sign(.init(kind: "capabilities", room: room, target: "", requestID: "passive-output-123456", operation: "discover", revision: revision),
                                     payload: JSONSerialization.data(withJSONObject: payload), editCapability: capability)
        let reply = try await codec.runtimeHostCall(["action": "frame", "context": local, "envelope": String(decoding: envelope, as: UTF8.self)])
        XCTAssertEqual(reply.sharedOutput?.stdout, "hello 🐍")
        XCTAssertEqual(reply.sharedOutput?.name, "Ada")
        XCTAssertTrue(reply.effects?.isEmpty == true)
        XCTAssertTrue(reply.jobs?.isEmpty == true)
        XCTAssertNil(reply.grant)
        local["busy"] = true
        let busy = try await codec.runtimeHostCall(["action": "tick", "context": local])
        XCTAssertNil(busy.sharedOutput)
        XCTAssertEqual(try codec.call(["type": "document"]).document, document)
    }

    func testPolicyVerifiesThroughCryptoKitAndRequiresLocalAllow() async throws {
        let codec = try PlaygroundCodec(), controller = PlaygroundRuntimeSigner(), host = PlaygroundRuntimeSigner()
        defer { controller.destroy(); host.destroy() }
        let source = PlaygroundDocument(name: "policy", entryFile: "main.py", files: ["main.py": "print('local 🐍')\n"])
        _ = try codec.initialize(source)
        let before = try codec.call(["type": "snapshot"]).snapshot
        let revision = try codec.runtimeSourceIdentity().revision
        var local = PlaygroundRuntimePolicyContext(room: room, target: host.fingerprint, scope: "native-project-connection-1", revision: revision, editCapability: capability,
                                                   expires: Wire.milliseconds() + 3_600_000, foreground: true, connected: true, editConfirmed: true, ready: true, busy: false)
        let initialized = try await codec.runtimePolicy(action: "initialize", local: local)
        XCTAssertNil(initialized.error)
        XCTAssertNil(initialized.grant)
        let requestID = "native-permission-001"
        let request = try controller.sign(.init(kind: "permission-request", room: room, target: host.fingerprint, requestID: requestID, operation: "grant", revision: revision),
                                          payload: Data("{\"name\":\"Claude · MCP\",\"operations\":[\"check\",\"run\"]}".utf8), editCapability: capability)
        let pending = try await codec.runtimePolicy(action: "request", local: local, envelope: request)
        XCTAssertNil(pending.error)
        XCTAssertNil(pending.grant)
        XCTAssertEqual(pending.requests.first?.controller, controller.fingerprint)
        let allowed = try await codec.runtimePolicy(action: "allow", local: local, controller: controller.fingerprint, requestID: requestID, operations: ["check"], lifetimeMilliseconds: 60_000)
        XCTAssertNil(allowed.error)
        let grant = try XCTUnwrap(allowed.grant)
        XCTAssertEqual(grant.operations, ["check"])
        let payload = try JSONSerialization.data(withJSONObject: ["grant": grant.id])
        let check = try controller.sign(.init(kind: "command", room: room, target: host.fingerprint, requestID: "native-check-00001", operation: "check", revision: revision), payload: payload, editCapability: capability)
        let first = try await codec.runtimePolicy(action: "admit", local: local, envelope: check)
        XCTAssertNil(first.error)
        XCTAssertEqual(first.admission?.kind, "new")
        let duplicate = try await codec.runtimePolicy(action: "admit", local: local, envelope: check)
        XCTAssertEqual(duplicate.admission?.kind, "duplicate")
        let run = try controller.sign(.init(kind: "command", room: room, target: host.fingerprint, requestID: "native-run-000001", operation: "run", revision: revision), payload: payload, editCapability: capability)
        let denied = try await codec.runtimePolicy(action: "admit", local: local, envelope: run)
        XCTAssertEqual(denied.admission?.kind, "denied")
        let noProof = try controller.sign(.init(kind: "command", room: room, target: host.fingerprint, requestID: "native-noproof-001", operation: "check", revision: revision), payload: payload)
        let invalid = try await codec.runtimePolicy(action: "admit", local: local, envelope: noProof)
        XCTAssertNotNil(invalid.error)
        XCTAssertNil(invalid.verified)
        XCTAssertEqual(invalid.grant?.id, grant.id)
        local.foreground = false
        let background = try await codec.runtimePolicy(action: "status", local: local)
        XCTAssertNil(background.grant)
        XCTAssertEqual(background.revoked.map(\.grant), [grant.id])
        XCTAssertEqual(try codec.call(["type": "document"]).document, source)
        XCTAssertEqual(try codec.call(["type": "snapshot"]).snapshot, before, "Permission policy must never change or run source")
    }

    func testSignedRuntimePresenceKeepsSelectionsAndDoesNotChangeSource() throws {
        let source = PlaygroundDocument(name: "presence", entryFile: "main.py", files: ["main.py": "print(\"🐍\")\n"])
        let first = try PlaygroundCodec(), second = try PlaygroundCodec()
        _ = try first.initialize(source)
        let snapshot = try XCTUnwrap(try first.call(["type": "snapshot"]).snapshot)
        _ = try second.call(["type": "state", "snapshot": snapshot, "events": [String]()])
        _ = try first.call(["type": "selection", "file": "main.py", "anchor": 7, "head": 9])
        let signer = PlaygroundRuntimeSigner()
        let envelope = try signed(signer)
        let object = try JSONSerialization.jsonObject(with: envelope)
        let outgoing = try XCTUnwrap(try first.call(["type": "runtime-presence", "envelope": object]).presence)
        XCTAssertLessThanOrEqual(outgoing.count, 4_000)
        let received = try second.call(["type": "presence", "bytes": outgoing])
        let frame = try XCTUnwrap(received.runtimeFrames?.first)
        XCTAssertEqual(try Wire.verify(Data(frame.envelope.utf8), context: context, clock: { self.now }).payload, payload)
        XCTAssertTrue(received.selections?.contains { $0.anchor == 7 && $0.head == 9 } == true)
        XCTAssertEqual(try first.call(["type": "snapshot"]).snapshot, snapshot)
        XCTAssertEqual(try second.runtimeSourceIdentity(), try first.runtimeSourceIdentity())
        let repeated = try XCTUnwrap(try first.call(["type": "runtime-presence", "envelope": object]).presence)
        let retransmitted = try XCTUnwrap(try second.call(["type": "presence", "bytes": repeated]).runtimeFrames?.first)
        XCTAssertEqual(retransmitted.envelope, frame.envelope)
        XCTAssertGreaterThan(retransmitted.clock, frame.clock)
        let cleared = try XCTUnwrap(try first.call(["type": "runtime-presence", "envelope": NSNull()]).presence)
        let after = try second.call(["type": "presence", "bytes": cleared])
        XCTAssertEqual(after.runtimeFrames, [])
        XCTAssertTrue(after.selections?.contains { $0.anchor == 7 && $0.head == 9 } == true)
        signer.destroy()
    }

    func testClaimedLocalPresenceIDCannotCorruptTheCursorOrLoseTheNextChange() throws {
        let codec = try PlaygroundCodec(), other = try PlaygroundCodec()
        let initialized = try codec.initialize(.init(name: "protected", entryFile: "main.py", files: ["main.py": "pass\n"]))
        let client = try XCTUnwrap(initialized.clientID)
        let snapshot = try XCTUnwrap(try codec.call(["type": "snapshot"]).snapshot)
        _ = try other.call(["type": "state", "snapshot": snapshot, "events": [String]()])
        _ = try codec.call(["type": "selection", "file": "main.py", "anchor": 0, "head": 3])
        let malicious = try JSONSerialization.data(withJSONObject: ["user": ["name": "spoofed\0", "color": "invalid"], "cursor": ["anchor": NSNull(), "head": NSNull()], "runtime": ["forged": true]])
        var packet: [UInt8] = []
        func varuint(_ value: UInt64) { var n = value; while n >= 128 { packet.append(UInt8(n & 127) | 128); n >>= 7 }; packet.append(UInt8(n)) }
        varuint(1); varuint(UInt64(client)); varuint(1_000_000); varuint(UInt64(malicious.count)); packet.append(contentsOf: malicious)
        let received = try codec.call(["type": "presence", "bytes": packet])
        XCTAssertEqual(received.localSelection?.anchor, 0)
        XCTAssertEqual(received.localSelection?.head, 3)
        let update = try XCTUnwrap(try codec.call(["type": "file", "path": "main.py", "text": "print('retained')\n"]).update)
        XCTAssertEqual(try other.call(["type": "update", "bytes": update]).document?.files["main.py"], "print('retained')\n")
    }

    func testMalformedPeerUnicodeCannotPoisonLaterDecoding() throws {
        let codec = try PlaygroundCodec()
        let source = PlaygroundDocument(name: "Unicode host", entryFile: "main.py", files: ["main.py": "pass\n"])
        let client = try XCTUnwrap(try codec.initialize(source).clientID)
        let malformed = Data(##"{"user":{"name":"bad\ud800","color":"#2876bd"},"cursor":null}"##.utf8)
        var packet: [UInt8] = []
        func varuint(_ value: UInt64) { var n = value; while n >= 128 { packet.append(UInt8(n & 127) | 128); n >>= 7 }; packet.append(UInt8(n)) }
        varuint(1); varuint(UInt64(client ^ 1)); varuint(1_000_000); varuint(UInt64(malformed.count)); packet.append(contentsOf: malformed)
        XCTAssertThrowsError(try codec.call(["type": "presence", "bytes": packet]))
        XCTAssertEqual(try codec.call(["type": "document"]).document, source)
        XCTAssertEqual(try codec.call(["type": "file", "path": "main.py", "text": "print('safe')\n"]).document?.files["main.py"], "print('safe')\n")
    }

    func testOversizedRuntimePresenceCannotReplaceASelectionOrSource() throws {
        let codec = try PlaygroundCodec()
        let source = PlaygroundDocument(name: "retained", entryFile: "main.py", files: ["main.py": "pass\n"])
        _ = try codec.initialize(source)
        _ = try codec.call(["type": "selection", "file": "main.py", "anchor": 0, "head": 3])
        XCTAssertThrowsError(try codec.call(["type": "runtime-presence", "envelope": ["oversized": String(repeating: "🐍", count: 1_000)]]))
        let after = try codec.call(["type": "document"])
        XCTAssertEqual(after.document, source)
        XCTAssertEqual(after.localSelection?.anchor, 0)
        XCTAssertEqual(after.localSelection?.head, 3)
        XCTAssertEqual(after.runtimeFrames, [])
    }

    // MARK: Jobs on the embedded interpreter

    private func waitForPython() async throws {
        let deadline = Date().addingTimeInterval(60)
        while RunSession.shared.pythonVersion == nil || RunSession.shared.phase != .idle {
            guard Date() < deadline else { throw XCTSkip("Python did not start") }
            try await Task.sleep(for: .milliseconds(50))
        }
    }

    private func job(_ operation: PlaygroundPythonJob.Operation, _ files: [String: String]) throws -> PlaygroundPythonJob {
        let document = try PlaygroundDocument(name: "job", entryFile: "main.py", files: files).validated()
        let folder = FileManager.default.temporaryDirectory.appending(path: "room-job-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        return PlaygroundPythonJob(operation: operation, document: document, paths: document.files.keys.sorted(), folder: folder)
    }

    func testSharedRunSeesOnlyTheRoomFilesAndReportsItsOutput() async throws {
        try await waitForPython()
        let run = try job(.run, [
            "main.py": "import os, sys, helper\nprint(helper.greet('room'))\nprint(sorted(os.listdir('.')))\nprint('to stderr', file=sys.stderr, flush=True)\nimport time\ntime.sleep(0.8)\nsys.exit(3)\n",
            "helper.py": "def greet(name):\n    return f'hello {name} 🐍'\n",
        ])
        let streamed = OutputRecorder()
        let result = await run.execute(isCancelled: { false }, onOutput: { stdout, _ in streamed.stdout = stdout })
        XCTAssertEqual(result.status, "failed")
        XCTAssertEqual(result.exitCode, 3)
        XCTAssertTrue(result.stdout.contains("hello room 🐍"), result.stdout + result.stderr)
        XCTAssertTrue(result.stdout.contains("['helper.py', 'main.py']"), result.stdout)
        XCTAssertTrue(result.stderr.contains("to stderr"))
        XCTAssertFalse(streamed.stdout.isEmpty, "Output streams while the job runs")
        XCTAssertGreaterThan(result.duration, 0)
    }

    func testSharedTestRunsPytestAndCheckPointsAtTheFile() async throws {
        try await waitForPython()
        let tests = try job(.test, ["main.py": "def add(a, b):\n    return a + b\n", "test_main.py": "from main import add\n\ndef test_add():\n    assert add(2, 3) == 5\n"])
        let passed = await tests.execute(isCancelled: { false }, onOutput: { _, _ in })
        XCTAssertEqual(passed.exitCode, 0, passed.stdout + passed.stderr)
        XCTAssertTrue(passed.stdout.contains("1 passed"), passed.stdout)
        let check = try job(.check, ["main.py": "import os\nprint(undefined_name)\n", "util.py": "def broken(:\n    pass\n"])
        let found = await check.execute(isCancelled: { false }, onOutput: { _, _ in })
        XCTAssertEqual(found.status, "failed")
        XCTAssertEqual(found.exitCode, 1)
        XCTAssertTrue(found.diagnostics.contains { $0.file == 0 && $0.line == 2 }, "\(found.diagnostics)")
        XCTAssertTrue(found.diagnostics.contains { $0.file == 1 && $0.level == "error" }, "\(found.diagnostics)")
        XCTAssertTrue(found.stdout.contains("util.py:1:"), found.stdout)
    }

    func testSharedRunStopsWhenTheRoomCancelsIt() async throws {
        try await waitForPython()
        let run = try job(.run, ["main.py": "import time\nprint('started', flush=True)\nwhile True:\n    time.sleep(0.05)\n"])
        let started = Date()
        let result = await run.execute(isCancelled: { Date().timeIntervalSince(started) > 1.5 }, onOutput: { _, _ in })
        XCTAssertEqual(result.status, "cancelled")
        XCTAssertLessThan(Date().timeIntervalSince(started), 20)
        XCTAssertTrue(result.stdout.contains("started"))
        XCTAssertEqual(RunSession.shared.phase, .idle)
    }

    // Pythilo namespace, signed with WebCrypto in Node (scratch script, not the website).
    private static let webCryptoVector = #"{"v":1,"key":"BOnoxShqbUOcwr7jMWIX0pxn-nuAtFSlnYlVGxHGRykeP2m6MvnKga6p1p0Yn7KtLo9jmFEB1uoCoikCC8IPKCQ","header":["pythilo-runtime-v1","command","aaaaaaaaaaaaaaaaaaaaaaaa","52065726cf2e1eb190d10729cd423c8f25cc72974633cbab96b40a94a97dbe14","bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","signed-vector-0001","run","cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc","","1rKgB5Q_fGF7Upsw7B6yDty1WqPJBuWn4iywU2Un-B8",1000000,1015000,"7fe1326425c90045130102437b77c8a2cd1b9ef345524fdcbfea154af3818ce2"],"payload":"eyJ0ZXh0IjoiV2ViQ3J5cHRvIOKGkiBDcnlwdG9LaXQg8J-QjSJ9","signature":"FPfJUNPbEzvUXDJRnu8QiYdOOWbLRabKy5XZ352M9uTB0Du5QumQsfi9fn9vp1ixrkN3dAMOMhl0VmZxwK9OoQ","editProof":"UXJ5JsRLrSasNl5pnwQnm5s0aDecYu1_fG-8TfWds8E"}"#

    // Crabrix's own interoperability vector, valid under crabrix-runtime-v1.
    private static let crabrixVector = #"{"v":1,"key":"BJklp5ciV6OfAJLYkAmofu35dfASqSXVngByHdaMIj7KUYkhtSFu4RpAe8hnuX3xPegYtc7SdqqH1ghBVBsBrk4","header":["crabrix-runtime-v1","command","aaaaaaaaaaaaaaaaaaaaaaaa","8834b55504e5ffc7122ee1bbf3f26d6c755110f534345b19ede9158379b9edb9","bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","signed-vector-0001","check","cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc","","TnRKZvdXMKcpQIn-HNsM-MyWd_x5jE_TPEzsQ23Et-k",1000000,1015000,"228cf50113bec2fb43a9b0271348bd143365b99d218ee7d3d4e04d1c1c01689e"],"payload":"eyJ0ZXh0IjoiV2ViQ3J5cHRvIOKGkiBDcnlwdG9LaXQg8J-mgCJ9","signature":"5N2ETD5k1H90Zy_Uok19q3Kr0o4Hp4n6pcA7AvEls84sWPZDGu21VFRwoTY8_WUatT-XJAvtZsW6EMHx8t_XDA","editProof":"GMfY2NbnyiZAWmf0XuXpa6E6Fv8ZH8mfXeQ3eNCmqFM"}"#
}

@MainActor
private final class OutputRecorder {
    var stdout = ""
}
