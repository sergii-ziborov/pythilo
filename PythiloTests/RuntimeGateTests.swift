import XCTest
@testable import Pythilo

/// The runtime gate from the plan: each case is run for real inside the app
/// process, against the embedded interpreter.
@MainActor
final class RuntimeGateTests: XCTestCase {
    private var session: RunSession { RunSession.shared }
    private var root: URL!

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appending(path: "gate-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try await waitUntil(timeout: 60) { self.session.pythonVersion != nil && self.session.phase == .idle }
        session.clearOutput()
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func waitUntil(timeout: TimeInterval, _ condition: @escaping @MainActor () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline {
                XCTFail("Timed out. Phase \(session.phase). Output: \(outputText())")
                throw CancellationError()
            }
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    private func outputText() -> String {
        session.output.map(\.text).joined()
    }

    private func write(_ name: String, _ source: String, in folder: URL? = nil) throws -> String {
        let url = (folder ?? root).appending(path: name)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try source.write(to: url, atomically: true, encoding: .utf8)
        return url.path
    }

    @discardableResult
    private func run(_ source: String, timeout: TimeInterval = 60, whileRunning: (() async throws -> Void)? = nil) async throws -> RunOutcome {
        let path = try write("main.py", source)
        return try await runJob(["kind": "script", "path": path, "root": root.path, "cwd": root.path], timeout: timeout, whileRunning: whileRunning)
    }

    @discardableResult
    private func shell(_ line: String, timeout: TimeInterval = 120, whileRunning: (() async throws -> Void)? = nil) async throws -> RunOutcome {
        try await runJob(["kind": "shell", "line": line, "root": root.path, "cwd": root.path], timeout: timeout, whileRunning: whileRunning)
    }

    private func runJob(_ job: [String: Any], timeout: TimeInterval, whileRunning: (() async throws -> Void)? = nil) async throws -> RunOutcome {
        session.clearOutput()
        let id = session.submit(job, label: "gate")
        XCTAssertNotNil(id)
        try await whileRunning?()
        try await waitUntil(timeout: timeout) { self.session.phase == .idle && self.session.lastOutcome?.id == id }
        return session.lastOutcome!
    }

    func testTerminalColorsAreRemovedFromOutput() {
        XCTAssertEqual(RunSession.withoutTerminalColors("\u{1B}[31m\u{1B}[1mWARNING\u{1B}[0m plain"), "WARNING plain")
        XCTAssertEqual(RunSession.withoutTerminalColors("plain [31m"), "plain [31m")
    }

    func testPrintAndFileAndVersion() async throws {
        let outcome = try await run("""
        import sys, os
        print("hello from", sys.version_info[:2], sys.platform)
        open("note.txt", "w").write("kept")
        print(os.getcwd() == os.environ["PYTHILO_PROJECT"])
        """)
        XCTAssertEqual(outcome.status, "finished")
        XCTAssertTrue(outputText().contains("hello from (3, 14) ios"), outputText())
        XCTAssertTrue(outputText().contains("True"))
        XCTAssertEqual(try String(contentsOf: root.appending(path: "note.txt"), encoding: .utf8), "kept")
    }

    func testExceptionReportsSourceLine() async throws {
        let outcome = try await run("x = 1\nraise ValueError('boom')\n")
        XCTAssertEqual(outcome.status, "failed")
        XCTAssertEqual(outcome.error?.type, "ValueError")
        XCTAssertEqual(outcome.error?.line, 2)
        XCTAssertTrue(outputText().contains("ValueError: boom"))
        XCTAssertFalse(outputText().contains("pythilo_runtime"), outputText())
    }

    func testSyntaxErrorPointsAtLine() async throws {
        let outcome = try await run("x = 1\ndef broken(:\n")
        XCTAssertEqual(outcome.status, "failed")
        XCTAssertEqual(outcome.error?.type, "SyntaxError")
        XCTAssertEqual(outcome.error?.line, 2)
    }

    func testSystemExitCodes() async throws {
        var outcome = try await run("import sys\nsys.exit(0)\n")
        XCTAssertEqual(outcome.status, "finished")
        outcome = try await run("import sys\nsys.exit(3)\n")
        XCTAssertEqual(outcome.status, "failed")
        XCTAssertEqual(outcome.code, 3)
        outcome = try await run("import os\nos._exit(4)\n")
        XCTAssertEqual(outcome.code, 4, "os._exit must not end the app")
    }

    func testInputRoundTripAndEndOfInput() async throws {
        try await run("""
        name = input("name? ")
        print("hi", name)
        try:
            input()
        except EOFError:
            print("eof")
        """) {
            try await self.waitUntil(timeout: 20) { self.session.phase == .waitingForInput }
            self.session.sendInput("Ada")
            try await self.waitUntil(timeout: 20) { self.outputText().contains("hi Ada") && self.session.phase == .waitingForInput }
            self.session.sendEndOfInput()
        }
        XCTAssertTrue(outputText().contains("name? "))
        XCTAssertTrue(outputText().contains("eof"))
    }

    private func assertStops(_ source: String, startedMarker: String) async throws {
        let outcome = try await run(source) {
            try await self.waitUntil(timeout: 30) { self.outputText().contains(startedMarker) }
            self.session.stop()
            XCTAssertEqual(self.session.phase, .cancelling)
        }
        XCTAssertEqual(outcome.status, "cancelled", outputText())
    }

    func testStopInfiniteLoop() async throws {
        try await assertStops("print('go', flush=True)\nwhile True:\n    pass\n", startedMarker: "go")
    }

    func testStopSleep() async throws {
        try await assertStops("import time\nprint('go', flush=True)\ntime.sleep(600)\n", startedMarker: "go")
    }

    func testStopWaitingForInput() async throws {
        let outcome = try await run("print('go')\ninput()\n") {
            try await self.waitUntil(timeout: 30) { self.session.phase == .waitingForInput }
            self.session.stop()
        }
        XCTAssertEqual(outcome.status, "cancelled")
    }

    func testStopBlockingSocket() async throws {
        try await assertStops("""
        import socket
        server = socket.socket()
        server.bind(("127.0.0.1", 0))
        server.listen()
        print("go", flush=True)
        server.accept()
        """, startedMarker: "go")
    }

    func testStopEscalatesPastOneCaughtInterrupt() async throws {
        try await assertStops("""
        print("go", flush=True)
        try:
            while True:
                pass
        except KeyboardInterrupt:
            pass
        while True:
            pass
        """, startedMarker: "go")
    }

    func testStopAsyncio() async throws {
        try await assertStops("""
        import asyncio
        async def main():
            print("go", flush=True)
            await asyncio.sleep(600)
        asyncio.run(main())
        """, startedMarker: "go")
    }

    func testLargeOutputIsBoundedAndDoesNotHang() async throws {
        let outcome = try await run("for i in range(200000):\n    print('line', i)\nprint('END')\n", timeout: 120)
        XCTAssertEqual(outcome.status, "finished")
        XCTAssertLessThan(outputText().utf8.count, 2_000_000)
        XCTAssertTrue(outputText().contains("END"))
    }

    func testRepeatedRunStopCycles() async throws {
        for cycle in 0..<5 {
            try await assertStops("print('go', flush=True)\nwhile True:\n    pass\n", startedMarker: "go")
            let outcome = try await run("print('fine \(cycle)')\n")
            XCTAssertEqual(outcome.status, "finished")
            XCTAssertTrue(outputText().contains("fine \(cycle)"))
        }
    }

    func testProjectSwitchDoesNotLeakModulesOrState() async throws {
        let a = root.appending(path: "a")
        let b = root.appending(path: "b")
        _ = try write("settings.py", "NAME = 'A'\n", in: a)
        _ = try write("settings.py", "NAME = 'B'\n", in: b)
        let pathA = try write("main.py", "import settings, sys, os\nos.environ['LEAK'] = '1'\nsys.path.append('/leak')\nprint('project', settings.NAME)\n", in: a)
        let pathB = try write("main.py", "import settings, sys, os\nprint('project', settings.NAME, 'LEAK' in os.environ, '/leak' in sys.path)\n", in: b)
        _ = try await runJob(["kind": "script", "path": pathA, "root": a.path, "cwd": a.path], timeout: 30)
        XCTAssertTrue(outputText().contains("project A"))
        _ = try await runJob(["kind": "script", "path": pathB, "root": b.path, "cwd": b.path], timeout: 30)
        XCTAssertTrue(outputText().contains("project B False False"), outputText())
        _ = try await runJob(["kind": "script", "path": pathA, "root": a.path, "cwd": a.path], timeout: 30)
        XCTAssertTrue(outputText().contains("project A"))
    }

    func testLeftoverThreadIsReported() async throws {
        let outcome = try await run("""
        import threading, time
        threading.Thread(target=time.sleep, args=(3,), name="worker", daemon=True).start()
        """)
        XCTAssertEqual(outcome.threads, ["worker"])
    }

    func testNumpyWorksAcrossRuns() async throws {
        for _ in 0..<2 {
            let outcome = try await run("""
            import numpy as np
            a = np.arange(1_000_000, dtype=np.float64)
            print("sum", int(a.sum()), np.linalg.det(np.eye(3)))
            """)
            XCTAssertEqual(outcome.status, "finished", outputText())
            XCTAssertTrue(outputText().contains("sum 499999500000 1.0"), outputText())
        }
    }

    func testDebuggerBreakpointStepAndLocals() async throws {
        let path = try write("debug.py", """
        def add(a, b):
            total = a + b
            return total

        result = add(2, 3)
        print("result", result)
        """)
        _ = try await runJob(["kind": "debug", "path": path, "root": root.path, "cwd": root.path, "breakpoints": [path: [2]]], timeout: 30) {
            try await self.waitUntil(timeout: 30) { self.session.phase == .paused }
            let first = self.session.debugPause
            XCTAssertEqual(first?.line, 2)
            XCTAssertEqual(first?.frames.first?.name, "add")
            XCTAssertEqual(first?.frames.first?.locals.first { $0.name == "a" }?.value, "2")
            self.session.evaluate("a * 10")
            try await self.waitUntil(timeout: 10) { self.session.debugEvaluations.first?.value == "20" }
            self.session.debug("next")
            try await self.waitUntil(timeout: 10) { self.session.debugPause?.line == 3 }
            XCTAssertEqual(self.session.debugPause?.frames.first?.locals.first { $0.name == "total" }?.value, "5")
            self.session.debug("continue")
        }
        XCTAssertTrue(outputText().contains("result 5"), outputText())
    }

    func testStopWhilePausedInDebugger() async throws {
        let path = try write("debug.py", "x = 1\ny = 2\n")
        let outcome = try await runJob(["kind": "debug", "path": path, "root": root.path, "cwd": root.path, "breakpoints": [path: [1]]], timeout: 30) {
            try await self.waitUntil(timeout: 30) { self.session.phase == .paused }
            self.session.stop()
        }
        XCTAssertEqual(outcome.status, "cancelled")
    }

    func testShellBuiltinsAndUnsupportedFlag() async throws {
        var outcome = try await shell("mkdir -p pkg/sub")
        XCTAssertEqual(outcome.status, "finished")
        outcome = try await shell("echo hello > pkg/sub/a.txt")
        XCTAssertEqual(outcome.status, "finished")
        outcome = try await shell("cat pkg/sub/a.txt")
        XCTAssertTrue(outputText().contains("hello"))
        outcome = try await shell("cd pkg")
        XCTAssertTrue(outcome.cwd?.hasSuffix("/pkg") == true, "\(outcome.cwd ?? "")")
        outcome = try await shell("ls --color")
        XCTAssertEqual(outcome.status, "failed")
        XCTAssertTrue(outputText().contains("not supported"))
        outcome = try await shell("docker ps")
        XCTAssertEqual(outcome.code, 127)
        outcome = try await shell("rm -rf .")
        XCTAssertEqual(outcome.status, "failed", "must refuse to remove the project")
    }

    func testPytestRunsAndReportsFailure() async throws {
        _ = try write("test_sample.py", "def test_ok():\n    assert 1 + 1 == 2\n\ndef test_bad():\n    assert 1 + 1 == 3\n")
        let outcome = try await shell("pytest -q")
        XCTAssertEqual(outcome.code, 1, outputText())
        XCTAssertTrue(outputText().contains("1 failed, 1 passed"), outputText())
    }

    func testAnalysisRunsDuringALongRun() async throws {
        var problems: [PythonProblem]?
        session.onProblems = { _, _, found in problems = found }
        defer { session.onProblems = nil }
        try await assertStopsWhile("import time\nprint('go', flush=True)\ntime.sleep(600)\n", marker: "go") {
            self.session.analyze(["action": "check", "token": "t", "path": "x.py", "source": "import os\nprint(undefined_name)\n"])
            try await self.waitUntil(timeout: 30) { problems != nil }
        }
        XCTAssertEqual(problems?.count, 2, "\(problems ?? [])")
    }

    private func assertStopsWhile(_ source: String, marker: String, _ body: @escaping () async throws -> Void) async throws {
        try await run(source) {
            try await self.waitUntil(timeout: 30) { self.outputText().contains(marker) }
            try await body()
            self.session.stop()
        }
    }

    func testDjangoServesRealHTTPThenStops() async throws {
        let body = try await serve(setup: {
            _ = try self.write("manage.py", """
            import os, sys
            os.environ.setdefault("DJANGO_SETTINGS_MODULE", "site_settings")
            from django.core.management import execute_from_command_line
            execute_from_command_line(sys.argv)
            """)
            _ = try self.write("site_settings.py", """
            SECRET_KEY = "gate"
            DEBUG = True
            ALLOWED_HOSTS = ["*"]
            ROOT_URLCONF = "site_urls"
            DATABASES = {"default": {"ENGINE": "django.db.backends.sqlite3", "NAME": "db.sqlite3"}}
            INSTALLED_APPS = ["django.contrib.contenttypes", "django.contrib.auth"]
            USE_TZ = True
            """)
            _ = try self.write("site_urls.py", """
            from django.http import HttpResponse
            from django.urls import path
            from django.contrib.auth.models import User
            def home(request):
                return HttpResponse(f"users={User.objects.count()}")
            urlpatterns = [path("", home)]
            """)
            let migrate = try await self.shell("python manage.py migrate --verbosity 0")
            XCTAssertEqual(migrate.status, "finished", self.outputText())
        }, command: "python manage.py runserver 127.0.0.1:18080", url: "http://127.0.0.1:18080/")
        XCTAssertEqual(body, "users=0")
    }

    func testFlaskServesRealHTTPThenStops() async throws {
        let body = try await serve(setup: {
            _ = try self.write("hello.py", """
            from flask import Flask, jsonify
            app = Flask(__name__)
            @app.get("/")
            def home():
                return jsonify(ok=True)
            """)
        }, command: "flask --app hello run --port 18081", url: "http://127.0.0.1:18081/")
        XCTAssertTrue(body.contains("\"ok\""), body)
    }

    func testStarletteOnUvicornServesRealHTTPThenStops() async throws {
        let body = try await serve(setup: {
            _ = try self.write("asgi_app.py", """
            from starlette.applications import Starlette
            from starlette.responses import JSONResponse
            from starlette.routing import Route
            async def home(request):
                return JSONResponse({"answer": 42})
            app = Starlette(routes=[Route("/", home)])
            """)
        }, command: "uvicorn asgi_app:app --port 18082", url: "http://127.0.0.1:18082/")
        XCTAssertEqual(body, "{\"answer\":42}")
    }

    /// Starts a server, makes real HTTP requests, stops it, then checks the port
    /// was given back by starting again.
    private func serve(setup: () async throws -> Void, command: String, url: String) async throws -> String {
        try await setup()
        var body = ""
        for _ in 0..<2 {
            let outcome = try await shell(command, timeout: 60) {
                body = try await self.fetchWhenReady(url)
                self.session.stop()
            }
            XCTAssertNotEqual(outcome.status, "failed", outputText())
        }
        return body
    }

    private func fetchWhenReady(_ address: String) async throws -> String {
        let deadline = Date().addingTimeInterval(45)
        var last: Error?
        while Date() < deadline {
            do {
                var request = URLRequest(url: URL(string: address)!)
                request.timeoutInterval = 5
                let (data, _) = try await URLSession.shared.data(for: request)
                return String(decoding: data, as: UTF8.self)
            } catch {
                last = error
                try await Task.sleep(for: .milliseconds(250))
            }
        }
        XCTFail("Server never answered: \(String(describing: last)). Output: \(outputText())")
        throw CancellationError()
    }

    func testPipInstallsPureWheelFromPyPI() async throws {
        let outcome = try await shell("pip install tomli-w==1.2.0", timeout: 180)
        if outcome.status != "finished", outputText().contains("Could not find a version") || outputText().contains("Temporary failure") || outputText().contains("NewConnectionError") {
            throw XCTSkip("PyPI unavailable: \(outputText())")
        }
        XCTAssertEqual(outcome.status, "finished", outputText())
        let run = try await run("import tomli_w\nprint(tomli_w.dumps({'a': 1}))\n")
        XCTAssertEqual(run.status, "finished", outputText())
        XCTAssertTrue(outputText().contains("a = 1"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appending(path: ".pythilo/environment.json").path))
    }
}
