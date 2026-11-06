import XCTest
@testable import Pythilo

/// Every lab on the shared engine, on the device: the answer traces and passes its checks,
/// and the starter fails with a message a learner can act on.
@MainActor
final class LabsTests: XCTestCase {
    private var session: RunSession { RunSession.shared }

    override func setUp() async throws {
        try await DownloadTestSupport.ensureAll()
        try await waitUntil(timeout: 60) { self.session.pythonVersion != nil && self.session.phase == .idle }
        session.clearOutput()
    }

    override func tearDown() async throws {
        session.onCustom = nil
    }

    private func waitUntil(timeout: TimeInterval, _ condition: @escaping @MainActor () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline {
                XCTFail("Timed out. Output: \(session.output.map(\.text).joined())")
                throw CancellationError()
            }
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    private func trace(_ lab: String, _ variant: String, _ source: String) async throws -> LabFrames? {
        var result: LabFrames?
        session.onCustom = { kind, data in
            if kind == "lab_frames" {
                do { result = try JSONDecoder().decode(LabFrames.self, from: data) } catch { XCTFail("\(lab).\(variant): \(error)") }
            }
        }
        session.clearOutput()
        session.submit(["kind": "lab_run", "lab": lab, "variant": variant, "source": source], label: "\(lab).\(variant)")
        try await waitUntil(timeout: 120) { result != nil && self.session.phase == .idle }
        return result
    }

    private var everyVariant: [(LabInfo, LabVariant)] {
        LabCatalog.all.flatMap { lab in lab.variants.map { (lab, $0) } }
    }

    func testTheCatalogHasSectionsAndManyLabs() {
        XCTAssertEqual(LabCatalog.all.count, 120)
        XCTAssertEqual(LabCatalog.all.filter { $0.section == .learning }.count, 57)
        XCTAssertEqual(LabCatalog.all.filter { $0.section == .intelligence }.count, 40)
        XCTAssertNotNil(LabCatalog.lab("attention"))
        XCTAssertNotNil(LabCatalog.lab("bellmanford"))
        XCTAssertNotNil(LabCatalog.lab("logistic"))
        for section in LabInfo.Section.allCases {
            XCTAssertGreaterThanOrEqual(LabCatalog.all.filter { $0.section == section }.count, 4, section.rawValue)
        }
        XCTAssertEqual(Set(LabCatalog.all.map(\.id)).count, LabCatalog.all.count, "ids are unique")
        XCTAssertEqual(LabCatalog.topics.count, 15)
        for lab in LabCatalog.all {
            XCTAssertEqual(LabCatalog.topic(for: lab)?.section, lab.section, "\(lab.id) must have one topic in its section")
        }
        XCTAssertEqual(LabCatalog.all.filter { LabCatalog.topic(for: $0)?.id == "pytorch-training" }.count, 9)
        XCTAssertEqual(LabCatalog.all.filter { LabCatalog.topic(for: $0)?.id == "transformer-projects" }.count, 3)
        let lessonIDs = Set(CourseLibrary.shared.courses.flatMap { $0.lessons.map(\.id) })
        for lab in LabCatalog.all {
            for id in lab.lessons ?? [] { XCTAssertTrue(lessonIDs.contains(id), "\(lab.id): missing lesson \(id)") }
        }
        for (lab, variant) in everyVariant {
            XCTAssertFalse(LabCatalog.code(lab.id, variant.id, .starter).contains("missing from the app"), "\(lab.id).\(variant.id) starter")
            XCTAssertFalse(LabCatalog.code(lab.id, variant.id, .answer).contains("missing from the app"), "\(lab.id).\(variant.id) answer")
        }
    }

    func testEveryAnswerTracesAndPassesItsChecks() async throws {
        var failures: [String] = []
        for (lab, variant) in everyVariant {
            let result = try await trace(lab.id, variant.id, LabCatalog.code(lab.id, variant.id, .answer))
            guard let result else { failures.append("\(lab.id).\(variant.id): no result"); continue }
            if !result.correct { failures.append("\(lab.id).\(variant.id): \(result.message)") }
            if result.frames.count < 3 { failures.append("\(lab.id).\(variant.id): only \(result.frames.count) steps") }
            if result.checks.isEmpty { failures.append("\(lab.id).\(variant.id): no checks") }
        }
        XCTAssertEqual(failures, [], failures.joined(separator: "\n"))
    }

    func testPyTorchLabsShareRunnableLessonContracts() async throws {
        let tensorLabs = LabCatalog.all.filter { $0.id.hasPrefix("torch") }
        XCTAssertEqual(tensorLabs.count, 24)
        var checkCount = 0
        for lab in tensorLabs {
            let lessons = CourseLibrary.shared.courses.flatMap(\.lessons).filter { lab.lessons?.contains($0.id) == true }
            XCTAssertEqual(lessons.count, 1, lab.id)
            guard let lesson = lessons.first else { continue }
            let answer = LabCatalog.code(lab.id, "practice", .answer)
            XCTAssertEqual(answer, lesson.solution, lab.id)
            let result = try await trace(lab.id, "practice", answer)
            XCTAssertEqual(result?.correct, true, "\(lab.id): \(result?.message ?? "no result")")
            XCTAssertEqual(result?.checks.map(\.name), lesson.checks.map(\.name), lab.id)
            XCTAssertEqual(result?.truncated, false, lab.id)
            checkCount += result?.checks.count ?? 0
        }
        XCTAssertEqual(checkCount, 103)
    }

    func testEveryStarterFailsWithAReadableMessage() async throws {
        var failures: [String] = []
        for (lab, variant) in everyVariant {
            let result = try await trace(lab.id, variant.id, LabCatalog.code(lab.id, variant.id, .starter))
            guard let result else { failures.append("\(lab.id).\(variant.id): no result"); continue }
            if result.correct { failures.append("\(lab.id).\(variant.id): the starter passed") }
            let message = result.message
            if message.count < 20 || message.contains("Traceback") {
                failures.append("\(lab.id).\(variant.id): unhelpful message \(message)")
            }
            if result.frames.isEmpty { failures.append("\(lab.id).\(variant.id): the starter drew nothing to look at") }
        }
        XCTAssertEqual(failures, [], failures.joined(separator: "\n"))
    }

    func testBinarySearchTraceShowsThePointersClosingIn() async throws {
        let result = try await trace("binsearch", "search", LabCatalog.code("binsearch", "search", .answer))
        let pointers = result?.frames.compactMap { $0.panels.first?.pointers?.map(\.name) }.filter { !$0.isEmpty } ?? []
        XCTAssertTrue(pointers.contains { $0.contains("mid") && $0.contains("lo") && $0.contains("hi") })
        XCTAssertTrue(result?.frames.contains { $0.note.contains("returned 11") } == true)
    }

    func testASyntaxErrorIsExplained() async throws {
        let result = try await trace("heap", "push", "def push(heap, value)\n    pass\n")
        XCTAssertEqual(result?.correct, false)
        XCTAssertTrue(result?.message.contains("SyntaxError on line 1") == true, result?.message ?? "")
    }

    func testHowItScalesSaysWhatItRanAndWhatItSuggests() async throws {
        var scale: LabScaleResult?
        session.onCustom = { kind, data in
            if kind == "lab_scale" { scale = try? JSONDecoder().decode(LabScaleResult.self, from: data) }
        }
        session.submit(["kind": "lab_scale", "lab": "window", "variant": "unique", "source": LabCatalog.code("window", "unique", .answer),
                        "sizes": [500, 1000, 2000, 4000, 8000]], label: "scale")
        try await waitUntil(timeout: 120) { scale != nil && self.session.phase == .idle }
        XCTAssertTrue(scale?.what.contains("n characters") == true, scale?.what ?? "")
        XCTAssertEqual(scale?.series.first?.points.count, 5)
        XCTAssertTrue(scale?.takeaway.hasPrefix("Doubling n") == true, scale?.takeaway ?? "")

        scale = nil
        session.submit(["kind": "lab_scale", "lab": "binsearch", "variant": "search", "source": LabCatalog.code("binsearch", "search", .starter)], label: "scale")
        try await waitUntil(timeout: 120) { scale != nil && self.session.phase == .idle }
        XCTAssertTrue(scale?.stopped.contains("wrong answer") == true, "a wrong answer is not timed: \(scale?.stopped ?? "")")
    }

    func testOldLabsScaleToo() async throws {
        var scale: LabScaleResult?
        session.onCustom = { kind, data in
            if kind == "lab_scale" { scale = try? JSONDecoder().decode(LabScaleResult.self, from: data) }
        }
        session.submit(["kind": "lab_graph_measure", "algorithm": "bfs", "source": GraphLabView.templates[.bfs]!, "topology": "sparse", "sizes": [100, 200, 400, 800]], label: "g")
        try await waitUntil(timeout: 90) { scale != nil && self.session.phase == .idle }
        XCTAssertEqual(scale?.series.first?.points.count, 4, scale?.stopped ?? "")

        scale = nil
        session.submit(["kind": "lab_dp_measure", "problem": "stairs", "source": DPLabView.templates[.stairs]!], label: "d")
        try await waitUntil(timeout: 90) { scale != nil && self.session.phase == .idle }
        XCTAssertGreaterThanOrEqual(scale?.series.first?.points.count ?? 0, 3, scale?.stopped ?? "")

        scale = nil
        session.submit(["kind": "lab_hash_scale", "source": HashLabView.template, "workload": "words", "sizes": [250, 500, 1000]], label: "h")
        try await waitUntil(timeout: 90) { scale != nil && self.session.phase == .idle }
        XCTAssertEqual(scale?.series.map(\.name), ["your Table", "dict"])
    }
}
