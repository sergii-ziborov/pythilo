import PythiloGit
import XCTest
@testable import Pythilo

/// End-to-end gates for everything around the runtime, in the real app process.
@MainActor
final class FeatureGateTests: XCTestCase {
    private var session: RunSession { RunSession.shared }
    private var root: URL!
    private var offlineAudit: Bool { name.contains("testEveryDownloadedLesson") || name.contains("testEveryAdvancedStarter") || name.contains("testEveryReadingExample") }

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appending(path: "feature-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try await DownloadTestSupport.ensureAll()
        try await waitUntil(timeout: 60) { self.session.pythonVersion != nil && self.session.phase == .idle }
        session.clearOutput()
        if offlineAudit { try await OfflineTestSupport.start() }
    }

    override func tearDown() async throws {
        if offlineAudit { try await OfflineTestSupport.stop() }
        MCPHost.shared.stop()
        session.onCustom = nil
        session.onCell = nil
        try? FileManager.default.removeItem(at: root)
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

    private func project(_ name: String = "demo") throws -> Project {
        let url = root.appending(path: name)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return Project(url: url)
    }

    // MARK: Workspace

    func testNestedCreateRenameMoveDeleteKeepTabsRight() throws {
        let project = try project()
        try "print('x')\n".write(to: project.url.appending(path: "main.py"), atomically: true, encoding: .utf8)
        let model = WorkspaceModel(project: project)
        let created = try model.create(path: "a/b/c/note.py", in: nil, isDirectory: false, contents: "x = 1\n")
        XCTAssertEqual(created, "a/b/c/note.py")
        XCTAssertTrue(model.expanded.isSuperset(of: ["a", "a/b", "a/b/c"]))
        XCTAssertEqual(model.selectedPath, created)
        let inFolder = try model.create(path: "d/e", in: "a/b", isDirectory: true)
        XCTAssertEqual(inFolder, "a/b/d/e")
        XCTAssertTrue(FileManager.default.fileExists(atPath: project.url.appending(path: "a/b/d/e").path))
        XCTAssertThrowsError(try model.create(path: "../escape.py", in: nil, isDirectory: false))
        XCTAssertThrowsError(try model.create(path: "a/b/c/note.py", in: nil, isDirectory: false))

        model.setText("x = 2\n", for: created)
        try model.rename(created, to: "renamed.py")
        XCTAssertEqual(model.selectedPath, "a/b/c/renamed.py")
        XCTAssertEqual(try String(contentsOf: project.url.appending(path: "a/b/c/renamed.py"), encoding: .utf8), "x = 2\n", "unsaved text must survive a rename")

        try model.move("a/b/c", to: "z/c")
        XCTAssertEqual(model.selectedPath, "z/c/renamed.py", "a tab follows its folder")
        try model.duplicate("z/c/renamed.py")
        XCTAssertTrue(FileManager.default.fileExists(atPath: project.url.appending(path: "z/c/renamed copy.py").path))
        try model.delete("z")
        XCTAssertFalse(model.tabs.contains("z/c/renamed.py"))
        XCTAssertFalse(model.tree.contains { $0.path == "z" })
    }

    func testTemplatesAllRunOrCompile() async throws {
        let store = ProjectStore(root: root.appending(path: "library"))
        let project = try store.create(name: "csv", template: .csvCleaner)
        let id = session.submit(["kind": "shell", "line": "pytest -q", "root": project.url.path, "cwd": project.url.path], label: "t")
        try await waitUntil(timeout: 60) { self.session.lastOutcome?.id == id && self.session.phase == .idle }
        XCTAssertEqual(session.lastOutcome?.code, 0, session.output.map(\.text).joined())

        let notes = try store.create(name: "notes", template: .djangoNotes)
        let migrate = session.submit(["kind": "shell", "line": "python manage.py migrate --verbosity 0", "root": notes.url.path, "cwd": notes.url.path], label: "m")
        try await waitUntil(timeout: 60) { self.session.lastOutcome?.id == migrate && self.session.phase == .idle }
        XCTAssertEqual(session.lastOutcome?.status, "finished", session.output.map(\.text).joined())
        XCTAssertTrue(FileManager.default.fileExists(atPath: notes.url.appending(path: "db.sqlite3").path))
    }

    // MARK: Git

    func testGitRepositoryIsAnOrdinaryOne() throws {
        let project = try project()
        let repository = ProjectRepository(worktree: project.url)
        XCTAssertFalse(repository.exists)
        try repository.initialize()
        XCTAssertTrue(FileManager.default.fileExists(atPath: project.url.appending(path: ".git/HEAD").path))
        try "one\n".write(to: project.url.appending(path: "a.txt"), atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: project.url.appending(path: ".pythilo"), withIntermediateDirectories: true)
        try "secret".write(to: project.url.appending(path: ".pythilo/x"), atomically: true, encoding: .utf8)
        var snapshot = try repository.snapshot()
        XCTAssertEqual(snapshot.branch, "main")
        XCTAssertEqual(snapshot.changes.map(\.path), ["a.txt"], ".pythilo stays out of history")
        XCTAssertThrowsError(try repository.commit(message: "empty", author: "A", email: "a@b.c"))
        try repository.stage(["a.txt"])
        let first = try repository.commit(message: "First", author: "Ada", email: "ada@example.com")
        XCTAssertEqual(try repository.snapshot().changes.count, 0)
        XCTAssertEqual(try repository.history().first?.id, first.id)

        try "two\n".write(to: project.url.appending(path: "a.txt"), atomically: true, encoding: .utf8)
        let diff = try repository.diff(path: "a.txt")
        XCTAssertTrue(diff.contains("-one") && diff.contains("+two"), diff)

        try repository.createBranch("feature")
        XCTAssertEqual(try repository.branches(), ["feature", "main"])
        XCTAssertThrowsError(try repository.switchBranch("nope"))
        try repository.stage([])
        try repository.commit(message: "Second", author: "Ada", email: "ada@example.com")
        try repository.switchBranch("feature")
        XCTAssertEqual(try String(contentsOf: project.url.appending(path: "a.txt"), encoding: .utf8), "one\n")
        snapshot = try repository.snapshot()
        XCTAssertEqual(snapshot.branch, "feature")
        try repository.switchBranch("main")
        XCTAssertEqual(try String(contentsOf: project.url.appending(path: "a.txt"), encoding: .utf8), "two\n")

        // A local edit that a switch would overwrite is refused, not lost.
        try "mine\n".write(to: project.url.appending(path: "a.txt"), atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try repository.switchBranch("feature"))
        XCTAssertEqual(try String(contentsOf: project.url.appending(path: "a.txt"), encoding: .utf8), "mine\n")
    }

    func testGitCloneFromGitHub() async throws {
        let target = root.appending(path: "cloned")
        do {
            try await Task.detached {
                try ProjectRepository.clone(url: "https://github.com/octocat/Hello-World.git", into: target, credential: nil)
            }.value
        } catch {
            throw XCTSkip("Network unavailable: \(error.localizedDescription)")
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: target.appending(path: "README").path))
        let snapshot = try ProjectRepository(worktree: target).snapshot()
        XCTAssertEqual(snapshot.remoteURL, "https://github.com/octocat/Hello-World.git")
        XCTAssertFalse(try ProjectRepository(worktree: target).history(limit: 1).isEmpty)
    }

    func testGitAddressRefusesEmbeddedTokenAndHTTP() throws {
        let project = try project()
        let repository = ProjectRepository(worktree: project.url)
        try repository.initialize()
        XCTAssertThrowsError(try repository.setRemote(url: "https://user:secret@github.com/a/b.git"))
        XCTAssertThrowsError(try repository.setRemote(url: "http://github.com/a/b.git"))
        XCTAssertNoThrow(try repository.setRemote(url: "https://example.com/a/b.git"))
    }

    // MARK: Lessons, labs, notebooks

    func testLessonCheckReportsEachCheck() async throws {
        let path = root.appending(path: "solution.py")
        try "def add(a, b):\n    return a + b\nprint('hi')\n".write(to: path, atomically: true, encoding: .utf8)
        var report: LessonReport?
        session.onCustom = { kind, data in
            if kind == "lesson_result" { report = try? JSONDecoder().decode(LessonReport.self, from: data) }
        }
        session.submit(
            [
                "kind": "lesson_check", "path": path.path, "root": root.path, "cwd": root.path,
                "checks": [
                    ["name": "adds", "code": "assert add(1, 2) == 3"],
                    ["name": "wrong", "code": "assert add(1, 2) == 4, 'expected four'"],
                    ["name": "stdout", "code": "assert _stdout == 'hi\\n'"],
                    ["name": "bare value", "code": "assert add(1, 1) == 3, add(1, 1)"],
                ],
            ],
            label: "lesson"
        )
        try await waitUntil(timeout: 30) { report != nil && self.session.phase == .idle }
        XCTAssertEqual(report?.results.map(\.ok), [true, false, true, false])
        XCTAssertEqual(report?.results[1].message, "expected four\nadd(1, 2) returned 3, expected 4.")
        XCTAssertEqual(report?.results[3].message, "add(1, 1) returned 2, expected 3.")
    }

    func testProjectExitCallbacksDoNotFinalizeLiveTorchLibraries() async throws {
        let first = root.appending(path: "first.py")
        let second = root.appending(path: "second.py")
        let third = root.appending(path: "third.py")
        try """
        import atexit, pathlib, torch, weakref
        import torch._prims
        class Resource: pass
        torch._pythilo_exit_resource = Resource()
        weakref.finalize(torch._pythilo_exit_resource, pathlib.Path('process-finalized').write_text, 'done')
        def record(value):
            with open('exit-order', 'a') as handle: handle.write(value)
        atexit.register(record, 'first')
        atexit.register(record, 'removed')
        atexit.unregister(record)
        assert atexit.register(record, 'first') is record
        atexit.register(record, 'second')
        assert hasattr(torch.ops.prims, 'device_put')
        """.write(to: first, atomically: true, encoding: .utf8)
        try """
        import pathlib, torch
        from torch import nn
        assert pathlib.Path('exit-order').read_text() == 'secondfirst'
        assert not pathlib.Path('process-finalized').exists()
        assert hasattr(torch.ops.prims, 'device_put')
        model = nn.Linear(2, 1)
        example = torch.ones(1, 2)
        program = torch.export.export(model, (example,))
        assert torch.allclose(program.module()(example), model(example))
        """.write(to: second, atomically: true, encoding: .utf8)
        try """
        import gc, pathlib, torch
        assert pathlib.Path('exit-order').read_text() == 'secondfirst'
        assert not pathlib.Path('process-finalized').exists()
        del torch._pythilo_exit_resource
        gc.collect()
        assert pathlib.Path('process-finalized').read_text() == 'done'
        """.write(to: third, atomically: true, encoding: .utf8)
        for path in [first, second, third] {
            let id = session.submit(["kind": "script", "path": path.path, "root": root.path, "cwd": root.path], label: "Exit ownership")
            try await waitUntil(timeout: 60) { self.session.lastOutcome?.id == id && self.session.phase == .idle }
            XCTAssertEqual(session.lastOutcome?.code, 0, session.output.map(\.text).joined())
        }
    }

    func testEveryDownloadedLessonSolutionPassesOnTheDevice() async throws {
        let library = CourseLibrary()
        try XCTSkipIf(library.courses.isEmpty, "Courses are not in this build yet")
        var failures: [String] = []
        var count = 0
        for course in library.courses {
            for lesson in course.lessons {
                let folder = root.appending(path: lesson.id)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let path = folder.appending(path: "solution.py")
                try lesson.solution.write(to: path, atomically: true, encoding: .utf8)
                var report: LessonReport?
                session.onCustom = { kind, data in
                    if kind == "lesson_result" { report = try? JSONDecoder().decode(LessonReport.self, from: data) }
                }
                session.submit(
                    [
                        "kind": "lesson_check", "path": path.path, "root": folder.path, "cwd": folder.path,
                        "checks": lesson.checks.map { ["name": $0.name, "code": $0.code] },
                    ],
                    label: lesson.id
                )
                try await waitUntil(timeout: 60) { report != nil && self.session.phase == .idle }
                count += 1
                if let error = report?.error { failures.append("\(lesson.id): \(error)") }
                if report?.results.count != lesson.checks.count { failures.append("\(lesson.id): missing check results") }
                for result in report?.results ?? [] where !result.ok {
                    failures.append("\(lesson.id) / \(result.name): \(result.message)")
                }
            }
        }
        XCTAssertEqual(count, 530)
        XCTAssertEqual(failures, [], failures.joined(separator: "\n"))
    }

    func testEveryAdvancedStarterIsRejectedOnTheDevice() async throws {
        let library = CourseLibrary()
        try XCTSkipIf(library.courses.isEmpty, "Courses are not in this build yet")
        var failures: [String] = []
        var count = 0
        for course in library.courses where ["python-runtime", "python-systems", "ml-statistics", "ml-production", "ai-production", "deep-learning-practice", "senior-projects", "ml-systems", "ai-systems", "pytorch-training", "transformer-engineering", "finetuning-projects"].contains(course.id) {
            for lesson in course.lessons {
                let folder = root.appending(path: lesson.id)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let path = folder.appending(path: "solution.py")
                try lesson.starter.write(to: path, atomically: true, encoding: .utf8)
                var report: LessonReport?
                session.onCustom = { kind, data in
                    if kind == "lesson_result" { report = try? JSONDecoder().decode(LessonReport.self, from: data) }
                }
                session.submit(
                    [
                        "kind": "lesson_check", "path": path.path, "root": folder.path, "cwd": folder.path,
                        "checks": lesson.checks.map { ["name": $0.name, "code": $0.code] },
                    ],
                    label: lesson.id
                )
                try await waitUntil(timeout: 60) { report != nil && self.session.phase == .idle }
                count += 1
                if report?.error == nil && !(report?.results.contains(where: { !$0.ok }) ?? false) {
                    failures.append("\(lesson.id): starter passed or produced no failure evidence")
                }
            }
        }
        XCTAssertEqual(count, 122)
        XCTAssertEqual(failures, [], failures.joined(separator: "\n"))
    }

    func testEveryReadingExampleRunsIndependentlyOnTheDevice() async throws {
        let library = CourseLibrary()
        let pattern = try NSRegularExpression(pattern: "```python\\n([\\s\\S]*?)```")
        var failures: [String] = []
        var count = 0
        for course in library.courses {
            for lesson in course.lessons {
                let body = lesson.body as NSString
                let matches = pattern.matches(in: lesson.body, range: NSRange(location: 0, length: body.length))
                XCTAssertFalse(matches.isEmpty, lesson.id)
                for (index, match) in matches.enumerated() {
                    let path = root.appending(path: "\(lesson.id)-\(index).py")
                    try body.substring(with: match.range(at: 1)).write(to: path, atomically: true, encoding: .utf8)
                    session.clearOutput()
                    let id = session.submit(["kind": "script", "path": path.path, "root": root.path, "cwd": root.path], label: "Reading example")
                    try await waitUntil(timeout: 30) { self.session.lastOutcome?.id == id && self.session.phase == .idle }
                    if session.lastOutcome?.code != 0 {
                        failures.append("\(course.id)/\(lesson.id) example \(index): \(session.output.map(\.text).joined())")
                    }
                    count += 1
                }
            }
        }
        let audit = try JSONSerialization.data(withJSONObject: ["count": count, "failures": failures], options: [.prettyPrinted])
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        try audit.write(to: documents.appending(path: "reading-audit.json"))
        XCTAssertEqual(count, 587)
        XCTAssertEqual(failures, [], failures.joined(separator: "\n"))
    }

    private let insertion = """
    def my_sort(items):
        for i in range(1, len(items)):
            key = items[i]
            j = i - 1
            while j >= 0 and items[j] > key:
                items[j + 1] = items[j]
                j -= 1
            items[j + 1] = key

    """

    func testSortingBenchTracesRealRunAndCatchesAWrongSort() async throws {
        var trace: LabTrace?
        session.onCustom = { kind, data in
            if kind == "lab_trace" { trace = try? JSONDecoder().decode(LabTrace.self, from: data) }
        }
        session.submit(["kind": "lab_trace", "source": insertion], label: "t")
        try await waitUntil(timeout: 30) { trace != nil && self.session.phase == .idle }
        XCTAssertEqual(trace?.correct, true)
        XCTAssertGreaterThan(trace?.steps.count ?? 0, 20)
        XCTAssertEqual(trace?.steps.last?.values, trace?.steps.last?.values.sorted())
        XCTAssertNotEqual(trace?.steps.first?.values, trace?.steps.first?.values.sorted())

        trace = nil
        session.submit(["kind": "lab_trace", "source": "def my_sort(items):\n    items[0] = items[1]\n"], label: "t")
        try await waitUntil(timeout: 30) { trace != nil && self.session.phase == .idle }
        XCTAssertEqual(trace?.correct, false, "a wrong sort must not look like a sorted one")
    }

    func testSortingBenchShowsHowItScales() async throws {
        var scale: LabScaleResult?
        session.onCustom = { kind, data in
            if kind == "lab_scale" { scale = try? JSONDecoder().decode(LabScaleResult.self, from: data) }
        }
        session.submit(["kind": "lab_measure", "source": insertion, "sizes": [100, 200, 400, 800]], label: "m")
        try await waitUntil(timeout: 90) { scale != nil && self.session.phase == .idle }
        XCTAssertEqual(scale?.series.map(\.name), ["your sort, random", "your sort, sorted", "your sort, reversed", "sorted(), random"])
        XCTAssertEqual(scale?.series.first?.ok, true)
        XCTAssertFalse(scale?.what.isEmpty ?? true, "it says what it ran")
        XCTAssertFalse(scale?.takeaway.isEmpty ?? true, "it says what the times suggest")
    }

    func testGraphExplorerTracesEachAlgorithmAndJudgesIt() async throws {
        var trace: GraphLabTrace?
        session.onCustom = { kind, data in
            if kind == "lab_graph_trace" { trace = try? JSONDecoder().decode(GraphLabTrace.self, from: data) }
        }
        for algorithm in GraphLabView.Algorithm.allCases {
            trace = nil
            session.submit(["kind": "lab_graph_trace", "algorithm": algorithm.rawValue, "source": GraphLabView.templates[algorithm]!, "topology": "sparse", "size": 16], label: "t")
            try await waitUntil(timeout: 30) { trace != nil && self.session.phase == .idle }
            XCTAssertEqual(trace?.correct, true, "\(algorithm): \(trace?.message ?? "no trace")")
            XCTAssertEqual(trace?.steps.count, 16, "every reachable node is expanded once")
        }
        trace = nil
        let wrong = GraphLabView.templates[.bfs]!.replacingOccurrences(of: "def bfs", with: "def dijkstra")
        session.submit(["kind": "lab_graph_trace", "algorithm": "dijkstra", "source": wrong, "topology": "grid", "size": 16], label: "t")
        try await waitUntil(timeout: 30) { trace != nil && self.session.phase == .idle }
        XCTAssertEqual(trace?.correct, false)
        XCTAssertTrue(trace?.message.contains("(node, weight) pairs") == true, trace?.message ?? "")
    }

    func testHashingLabCountsComparisonsAndCollisions() async throws {
        var result: HashLabResult?
        session.onCustom = { kind, data in
            if kind == "lab_hash" { result = try? JSONDecoder().decode(HashLabResult.self, from: data) }
        }
        session.submit(["kind": "lab_hash", "source": HashLabView.template, "workload": "colliding", "count": 200], label: "h")
        try await waitUntil(timeout: 30) { result != nil && self.session.phase == .idle }
        XCTAssertEqual(result?.correct, true, result?.message ?? "")
        XCTAssertEqual(result?.longest, 200, "multiples of the bucket count share one bucket")
        XCTAssertGreaterThan(result?.averageProbes ?? 0, 50)
    }

    func testDynamicProgrammingLabCountsRepeatedCallsAndTableWrites() async throws {
        var trace: DPLabTrace?
        session.onCustom = { kind, data in
            if kind == "lab_dp_trace" { trace = try? JSONDecoder().decode(DPLabTrace.self, from: data) }
        }
        session.submit(["kind": "lab_dp_trace", "problem": "stairs", "source": DPLabView.templates[.stairs]!], label: "d")
        try await waitUntil(timeout: 30) { trace != nil && self.session.phase == .idle }
        XCTAssertEqual(trace?.calls, 177)
        XCTAssertEqual(trace?.distinct, 11)
        XCTAssertEqual(trace?.repeated.first?.args, "ways(1)")

        trace = nil
        session.submit(["kind": "lab_dp_trace", "problem": "edit", "source": DPLabView.templates[.edit]!], label: "d")
        try await waitUntil(timeout: 30) { trace != nil && self.session.phase == .idle }
        XCTAssertEqual(trace?.correct, true, trace?.message ?? "")
        XCTAssertEqual(trace?.rows, 7)
        XCTAssertEqual(trace?.columns, 8)
        XCTAssertEqual(trace?.writes.count, 57)
    }

    func testATerminalCommandWhileAServerRunsRestartsTheServerAroundIt() async throws {
        let project = try project("serve")
        try """
        import http.server
        server = http.server.HTTPServer(("127.0.0.1", 0), http.server.SimpleHTTPRequestHandler)
        print("serving", flush=True)
        server.serve_forever()
        """.write(to: project.url.appending(path: "serve.py"), atomically: true, encoding: .utf8)
        try "note\n".write(to: project.url.appending(path: "note.txt"), atomically: true, encoding: .utf8)
        let model = WorkspaceModel(project: project)
        model.runTerminal("python serve.py")
        try await waitUntil(timeout: 30) { self.session.listening != nil }
        model.runTerminal("cat note.txt")
        let text = { self.session.terminalOutput.map(\.text).joined() }
        try await waitUntil(timeout: 30) { text().contains("Stopping the server") && text().contains("note\n") }
        try await waitUntil(timeout: 30) { self.session.listening != nil && text().components(separatedBy: "serving").count == 3 }
        XCTAssertFalse(text().contains("Python is busy"), text())
        session.stop()
        try await waitUntil(timeout: 30) { !self.session.isBusy }
    }

    func testEachWebTemplateOffersItsFrameworksCommands() throws {
        let store = ProjectStore(root: root.appending(path: "library"))
        let expected: [(ProjectTemplate, ProjectCommands.Framework, String)] = [
            (.djangoNotes, .django, "python manage.py runserver"),
            (.flaskAPI, .flask, "flask --app hello run"),
            (.fastAPI, .asgi, "uvicorn main:app"),
            (.asgiAPI, .asgi, "uvicorn main:app"),
        ]
        for (template, framework, server) in expected {
            let project = try store.create(name: template.id, template: template)
            let commands = ProjectCommands.detect(root: project.url, djangoNames: [])
            XCTAssertEqual(commands.framework, framework, template.id)
            XCTAssertEqual(commands.featured.first { $0.servesSite }?.line, server, template.id)
        }
        let csv = try store.create(name: "csv", template: .csvCleaner)
        XCTAssertNil(ProjectCommands.detect(root: csv.url, djangoNames: []).framework)
        XCTAssertEqual(ProjectCommands.detect(root: csv.url, djangoNames: []).featured.map(\.line), ["pytest -q"])
    }

    func testDjangosOwnCommandListBecomesTheTerminalsCommands() throws {
        let help = """
        Type 'manage.py help <subcommand>' for help on a specific subcommand.

        Available subcommands:

        [auth]
            changepassword
            createsuperuser

        [django]
            check
            migrate
            startapp

        [staticfiles]
            runserver
        """
        let found = try XCTUnwrap(ProjectCommands.djangoCommands(in: help))
        XCTAssertEqual(found.map(\.name), ["changepassword", "createsuperuser", "check", "migrate", "startapp", "runserver"])
        XCTAssertEqual(found.first?.group, "auth")
        let project = try ProjectStore(root: root.appending(path: "library")).create(name: "notes", template: .djangoNotes)
        let commands = ProjectCommands.detect(root: project.url, djangoNames: found)
        XCTAssertEqual(commands.all.count, 6)
        XCTAssertEqual(commands.featured.map(\.title), ["runserver", "migrate", "createsuperuser", "check"])
        XCTAssertEqual(commands.all.first { $0.title == "startapp" }?.needsArgument, true, "startapp needs a name, so its chip only fills the input")
        XCTAssertNil(ProjectCommands.djangoCommands(in: "Hello\nAvailable subcommands:\n\nnothing here"))
    }

    func testFastAPITemplatePassesItsTestsOnTheDevice() async throws {
        let store = ProjectStore(root: root.appending(path: "library"))
        let project = try store.create(name: "tasks", template: .fastAPI)
        let id = session.submit(["kind": "shell", "line": "pytest -q", "root": project.url.path, "cwd": project.url.path], label: "t")
        try await waitUntil(timeout: 90) { self.session.lastOutcome?.id == id && self.session.phase == .idle }
        let output = session.output.map(\.text).joined()
        XCTAssertEqual(session.lastOutcome?.code, 0, output)
        XCTAssertTrue(output.contains("3 passed"), output)
    }

    func testNotebookCellsShareNamespaceAndRoundTrip() async throws {
        let path = root.appending(path: "n.ipynb")
        try ProjectTemplate.notebook.files["study.ipynb"]!.write(to: path, atomically: true, encoding: .utf8)
        let document = NotebookDocument(url: path)
        XCTAssertEqual(document.cells.count, 3)
        session.onCell = { [weak document] event in document?.receive(event) }
        let code = document.cells.filter { $0.kind == "code" }
        for cell in code {
            document.begin(cell.id)
            let id = session.submit(["kind": "notebook", "cell": cell.id, "path": path.path, "source": cell.source, "root": root.path, "cwd": root.path], label: "cell")
            try await waitUntil(timeout: 60) { self.session.lastOutcome?.id == id && self.session.phase == .idle }
        }
        let first = try XCTUnwrap(document.cells.first { $0.id == code[0].id })
        let data = first.outputs.first?["data"] as? [String: Any]
        XCTAssertEqual(data?["text/plain"] as? String, "np.float64(57.25)", "\(first.outputs)")
        let second = try XCTUnwrap(document.cells.first { $0.id == code[1].id })
        XCTAssertEqual(second.outputs.first?["output_type"] as? String, "stream", "the second cell sees the first cell's name")
        document.setSource("rain.max()", for: code[0].id)
        XCTAssertTrue(document.cells.first { $0.id == code[0].id }?.isStale == true)
        document.saveNow()
        let saved = try JSONSerialization.jsonObject(with: Data(contentsOf: path)) as? [String: Any]
        XCTAssertEqual(saved?["nbformat"] as? Int, 4)
        let reopened = NotebookDocument(url: path)
        XCTAssertEqual(reopened.cells.count, 3)
        XCTAssertEqual(reopened.cells.first { $0.id == code[0].id }?.source, "rain.max()")
    }

    // MARK: MCP

    private func post(_ body: [String: Any], token: String?) async throws -> (Int, [String: Any]) {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:18765/mcp")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 30
        let (data, response) = try await URLSession.shared.data(for: request)
        let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        return ((response as? HTTPURLResponse)?.statusCode ?? 0, object)
    }

    private struct ToolReply: @unchecked Sendable {
        let result: [String: Any]
        let isError: Bool
        let text: String
    }

    private func call(_ name: String, _ arguments: [String: Any] = [:], token: String) async throws -> ToolReply {
        let (_, reply) = try await post(["jsonrpc": "2.0", "id": 9, "method": "tools/call", "params": ["name": name, "arguments": arguments]], token: token)
        let result = reply["result"] as? [String: Any] ?? [:]
        let content = (result["content"] as? [[String: Any]])?.first?["text"] as? String ?? ""
        return ToolReply(result: result["structuredContent"] as? [String: Any] ?? [:], isError: result["isError"] as? Bool ?? true, text: content)
    }

    func testMCPSpeaksProtocolAndEnforcesPermissions() async throws {
        let project = try project()
        try "print('from mcp', 6 * 7)\n".write(to: project.url.appending(path: "main.py"), atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: project.url.appending(path: ".pythilo"), withIntermediateDirectories: true)
        let host = MCPHost.shared
        host.start(project: project)
        try await waitUntil(timeout: 10) { host.isRunning }
        let token = host.token
        XCTAssertFalse(token.isEmpty)

        // No token, wrong token.
        var (status, _) = try await post(["jsonrpc": "2.0", "id": 1, "method": "ping"], token: nil)
        XCTAssertEqual(status, 401)
        (status, _) = try await post(["jsonrpc": "2.0", "id": 1, "method": "ping"], token: "nope")
        XCTAssertEqual(status, 401)

        // The handshake a real client does.
        let (_, hello) = try await post([
            "jsonrpc": "2.0", "id": 1, "method": "initialize",
            "params": ["protocolVersion": "2025-06-18", "capabilities": [String: Any](), "clientInfo": ["name": "Gate", "version": "1"]],
        ], token: token)
        let info = hello["result"] as? [String: Any]
        XCTAssertEqual(info?["protocolVersion"] as? String, "2025-06-18")
        XCTAssertEqual(host.clientName, "Gate")
        (status, _) = try await post(["jsonrpc": "2.0", "method": "notifications/initialized"], token: token)
        XCTAssertEqual(status, 202)
        let (_, list) = try await post(["jsonrpc": "2.0", "id": 2, "method": "tools/list"], token: token)
        let tools = ((list["result"] as? [String: Any])?["tools"] as? [[String: Any]])?.compactMap { $0["name"] as? String } ?? []
        XCTAssertTrue(Set(["read_file", "write_file", "run", "git_push"]).isSubset(of: tools), "\(tools)")

        // Reads and revision-checked writes.
        let read = try await call("read_file", ["path": "main.py"], token: token)
        XCTAssertFalse(read.isError, read.text)
        let revision = try XCTUnwrap(read.result["revision"] as? String)
        var write = try await call("write_file", ["path": "main.py", "text": "print('from mcp', 6 * 7)\nprint('edited')\n"], token: token)
        XCTAssertTrue(write.isError, "an existing file needs a revision")
        write = try await call("write_file", ["path": "main.py", "text": "print('from mcp', 6 * 7)\nprint('edited')\n", "expected_revision": revision], token: token)
        XCTAssertFalse(write.isError, write.text)
        write = try await call("write_file", ["path": "main.py", "text": "lost", "expected_revision": revision], token: token)
        XCTAssertTrue(write.isError, "a stale revision is a conflict")
        XCTAssertTrue(write.text.contains("Conflict"), write.text)
        XCTAssertFalse(try String(contentsOf: project.url.appending(path: "main.py"), encoding: .utf8).contains("lost"))

        // Paths stay inside the project.
        for path in ["../x.py", "/etc/passwd", ".git/config", ".pythilo/environment.json"] {
            let escaped = try await call("read_file", ["path": path], token: token)
            XCTAssertTrue(escaped.isError, path)
        }

        // Edit never grants run: it asks, and a denial runs nothing.
        let denied = Task { try await self.call("run", ["path": "main.py"], token: token) }
        try await waitUntil(timeout: 10) { !host.pending.isEmpty }
        XCTAssertEqual(host.pending.first?.permission, .run)
        host.answer(host.pending[0], allow: false)
        let deniedResult = try await denied.value
        XCTAssertTrue(deniedResult.isError)
        XCTAssertEqual(session.phase, .idle)

        let allowed = Task { try await self.call("run", ["path": "main.py"], token: token) }
        try await waitUntil(timeout: 10) { !host.pending.isEmpty }
        host.answer(host.pending[0], allow: true)
        let ran = try await allowed.value
        XCTAssertFalse(ran.isError, ran.text)
        XCTAssertEqual(ran.result["status"] as? String, "finished")
        XCTAssertTrue((ran.result["output"] as? String)?.contains("from mcp 42") == true, ran.text)
        XCTAssertNotNil(ran.result["runtime_fingerprint"])
        XCTAssertNotNil(ran.result["executed_on"])

        // Push is off by default, and asks nobody.
        let push = try await call("git_push", token: token)
        XCTAssertTrue(push.isError)
        XCTAssertTrue(host.pending.isEmpty)

        let diagnostics = try await call("diagnostics", ["path": "main.py"], token: token)
        XCTAssertFalse(diagnostics.isError, diagnostics.text)

        // Stopping ends the token.
        host.stop()
        XCTAssertFalse(host.isRunning)
        XCTAssertTrue(host.token.isEmpty)
    }
}
