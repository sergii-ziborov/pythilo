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

    func testTerminalUndoesTheKeyboardsSmartPunctuation() {
        // What the iOS keyboard makes of `python --version` and `echo "a b"`.
        XCTAssertEqual(WorkspaceModel.plainCommand("python \u{2014}version"), "python --version")
        XCTAssertEqual(WorkspaceModel.plainCommand("echo \u{201C}a b\u{201D}"), "echo \"a b\"")
        XCTAssertEqual(WorkspaceModel.plainCommand("echo 1990\u{2013}2000"), "echo 1990\u{2013}2000")
    }

    func testPythonAndPipAnswerHelpAndVersion() async throws {
        for (line, expected) in [("python --version", "Python 3.14"), ("python -V", "Python 3.14"), ("python --help", "python -m module"), ("pip --version", "pip 26")] {
            let outcome = try await shell(line)
            XCTAssertEqual(outcome.status, "finished", "\(line): \(outputText())")
            XCTAssertTrue(outputText().contains(expected), "\(line): \(outputText())")
        }
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

    func testDebuggerStopsInAWebHandlerThreadAndInAsyncCode() async throws {
        let path = try write("serve.py", """
        import asyncio, threading, urllib.request
        from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler

        class Handler(BaseHTTPRequestHandler):
            def do_GET(self):
                name = self.path.strip("/")
                self.send_response(200); self.end_headers(); self.wfile.write(f"hello {name}".encode())
            def log_message(self, *args):
                pass

        async def later(x):
            await asyncio.sleep(0)
            y = x + 1
            return y

        server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        threading.Thread(target=server.serve_forever, daemon=True).start()
        print(urllib.request.urlopen(f"http://127.0.0.1:{server.server_port}/ada").read().decode())
        server.shutdown()
        print("async", asyncio.run(later(4)))
        """)
        _ = try await runJob(["kind": "debug", "path": path, "root": root.path, "cwd": root.path, "breakpoints": [path: [7, 14]]], timeout: 60) {
            try await self.waitUntil(timeout: 30) { self.session.debugPause?.line == 7 }
            XCTAssertTrue(self.session.debugPause?.thread?.contains("process_request_thread") == true, self.session.debugPause?.thread ?? "no thread")
            XCTAssertEqual(self.session.debugPause?.frames.first?.locals.first { $0.name == "name" }?.value, "'ada'")
            self.session.debug("continue")
            try await self.waitUntil(timeout: 30) { self.session.debugPause?.line == 14 }
            XCTAssertEqual(self.session.debugPause?.thread, "MainThread")
            XCTAssertEqual(self.session.debugPause?.frames.first?.locals.first { $0.name == "x" }?.value, "4")
            self.session.debug("continue")
        }
        XCTAssertTrue(outputText().contains("hello ada"), outputText())
        XCTAssertTrue(outputText().contains("async 5"), outputText())
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

    func testReactAndFastAPIInstallBuildAndServe() async throws {
        for (path, text) in ProjectTemplate.reactFastAPI.files {
            let url = root.appending(path: path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: url, atomically: true, encoding: .utf8)
        }
        let installed = try await shell("npm install", timeout: 240)
        XCTAssertEqual(installed.code, 0, outputText())
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appending(path: "node_modules/react-dom/package.json").path), outputText())
        XCTAssertTrue(outputText().contains("Integrity checked"), outputText())

        let model = WorkspaceModel(project: Project(url: root), session: session)
        await NpmScripts.run("npm run build", in: model)
        let bundle = root.appending(path: "static/assets/main.js")
        let size = (try? FileManager.default.attributesOfItem(atPath: bundle.path)[.size] as? Int) ?? 0
        XCTAssertGreaterThan(size, 100_000, "React and the app, minified: \(session.terminalOutput.map(\.text).joined())")
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appending(path: "static/assets/main.css").path))

        var page = "", script = "", api = ""
        _ = try await shell("uvicorn main:app --port 18090", timeout: 60) {
            page = try await self.fetchWhenReady("http://127.0.0.1:18090/")
            script = try await self.fetchWhenReady("http://127.0.0.1:18090/assets/main.js")
            api = try await self.fetchWhenReady("http://127.0.0.1:18090/api/tasks")
            self.session.stop()
        }
        XCTAssertTrue(page.contains("<div id=\"root\">"), page)
        XCTAssertTrue(script.contains("createRoot") || script.count > 100_000, "the built bundle is what the site serves")
        XCTAssertTrue(api.contains("Try the React page"), api)
    }

    func testCoreMLRunsTheSampleOnEachComputeUnitAndAgrees() async throws {
        let outcome = try await run("""
        import numpy
        from pythilo import coreml
        info = coreml.devices()
        print("devices", info["devices"], "neural", info["neuralEngine"])
        with coreml.sample(compute="cpu") as model:
            out = model.predict({"image": numpy.ones((3, 224, 224), "float32")})["probabilities"]
            print("shape", out.shape, "sum", round(float(out.sum()), 3), "ms", model.last_milliseconds > 0)
        rows = coreml.benchmark(runs=2)
        print("rows", [row["compute"] for row in rows], "agree", all(row["max_difference"] < 0.05 for row in rows))
        try:
            coreml.load("missing.mlpackage")
        except RuntimeError as error:
            print("missing:", error)
        """, timeout: 120)
        XCTAssertEqual(outcome.code, 0, outputText())
        XCTAssertTrue(outputText().contains("'CPU'"), outputText())
        XCTAssertTrue(outputText().contains("shape (10,) sum 1.0 ms True"), outputText())
        XCTAssertTrue(outputText().contains("rows ['cpu', 'gpu', 'ane', 'all'] agree True"), outputText())
        XCTAssertTrue(outputText().contains("missing: No model at"), outputText())
    }

    func testPyTorchTrainsAModelAndTalksToNumPy() async throws {
        let outcome = try await run("""
        import io, time
        import numpy
        import torch
        from torch import nn
        print("torch", torch.__version__, "threads", torch.get_num_threads() > 0)
        torch.manual_seed(0)
        x = torch.randn(256, 4)
        y = (x @ torch.tensor([1.5, -2.0, 0.5, 3.0]) + 0.25).unsqueeze(1)
        model = nn.Sequential(nn.Linear(4, 16), nn.ReLU(), nn.Linear(16, 1))
        optimizer = torch.optim.Adam(model.parameters(), lr=0.03)
        first = None
        start = time.perf_counter()
        for step in range(300):
            optimizer.zero_grad()
            loss = nn.functional.mse_loss(model(x), y)
            loss.backward()
            optimizer.step()
            first = first if first is not None else loss.item()
        print("learned", loss.item() < first / 50, "in", round(time.perf_counter() - start, 2), "s")
        a = numpy.arange(6, dtype="float32").reshape(2, 3)
        t = torch.from_numpy(a)
        print("numpy", t.sum().item(), (t * 2).numpy().tolist())
        m = torch.tensor([[4.0, 1.0], [2.0, 3.0]])
        print("solve", [round(v, 4) for v in torch.linalg.solve(m, torch.tensor([1.0, 2.0])).tolist()])
        print("conv", nn.Conv2d(3, 8, 3)(torch.randn(2, 3, 32, 32)).shape)
        u, w = torch.tensor([1.0, 2.0, 3.0]), torch.tensor([4.0, 5.0, 6.0])
        print("dot", torch.dot(u, w).item(), (u @ w).item(), torch.dot(u.double(), w.double()).item())
        buffer = io.BytesIO()
        torch.save(model.state_dict(), buffer)
        buffer.seek(0)
        copy = nn.Sequential(nn.Linear(4, 16), nn.ReLU(), nn.Linear(16, 1))
        copy.load_state_dict(torch.load(buffer))
        print("saved", torch.equal(copy(x), model(x)))
        """, timeout: 240)
        XCTAssertEqual(outcome.code, 0, outputText())
        XCTAssertTrue(outputText().contains("torch 2.15.0 threads True"), outputText())
        XCTAssertTrue(outputText().contains("learned True"), outputText())
        XCTAssertTrue(outputText().contains("numpy 15.0 [[0.0, 2.0, 4.0], [6.0, 8.0, 10.0]]"), outputText())
        XCTAssertTrue(outputText().contains("solve [0.1, 0.6]"), outputText())
        XCTAssertTrue(outputText().contains("conv torch.Size([2, 8, 30, 30])"), outputText())
        XCTAssertTrue(outputText().contains("dot 32.0 32.0 32.0"), outputText())
        XCTAssertTrue(outputText().contains("saved True"), outputText())
    }

    func testThePyTorchTemplateLearnsTheSpirals() async throws {
        let outcome = try await run(ProjectTemplate.pyTorch.files["main.py"]!, timeout: 240)
        XCTAssertEqual(outcome.code, 0, outputText())
        let last = outputText().components(separatedBy: "\n").last { $0.hasPrefix("epoch 400") } ?? ""
        let accuracy = Int(last.components(separatedBy: "accuracy ").last?.dropLast() ?? "") ?? 0
        XCTAssertGreaterThanOrEqual(accuracy, 95, outputText())
        XCTAssertTrue(outputText().contains("Saved the weights to spirals.pt"), outputText())
    }

    /// torch-ios's conformance suite, run here and compared with the same suite on the
    /// Mac (`build/torch-conformance-mac.json`, made with the Mac's torch of the same
    /// version). The simulator reads and writes the Mac's files directly.
    func testPyTorchMatchesTheReferenceBuild() async throws {
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let suite = repository.appending(path: "build/torch-ios/tests")
        let reference = repository.appending(path: "build/torch-conformance-mac.json")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: reference.path), "Make the Mac reference first")
        let candidate = repository.appending(path: "build/torch-conformance-ios.json")
        let outcome = try await run("""
        import runpy, sys
        sys.path.insert(0, \(String(reflecting: suite.path)))
        suite = runpy.run_path(\(String(reflecting: suite.appending(path: "conformance.py").path)))
        suite["main"](\(String(reflecting: candidate.path)))
        compare = runpy.run_path(\(String(reflecting: suite.appending(path: "compare.py").path)))
        sys.exit(compare["main"](\(String(reflecting: reference.path)), \(String(reflecting: candidate.path))))
        """, timeout: 600)
        XCTAssertEqual(outcome.code, 0, outputText())
    }

    func testPyTorchCoversTheRestOfTheLibrary() async throws {
        let outcome = try await run("""
        import torch
        from torch import nn
        from torch.utils.data import DataLoader, TensorDataset
        x = torch.linspace(-1, 1, 5)
        print("func", torch.func.grad(lambda v: (v ** 3).sum())(x).tolist() == (3 * x ** 2).tolist(),
              torch.func.vmap(torch.dot)(torch.ones(3, 4), torch.ones(3, 4)).tolist())
        print("fft", [round(v, 3) for v in torch.fft.rfft(torch.tensor([1.0, 0.0, -1.0, 0.0])).abs().tolist()])
        normal = torch.distributions.Normal(0.0, 1.0)
        print("distributions", round(normal.log_prob(torch.tensor(0.0)).item(), 4))
        traced = torch.jit.trace(nn.Linear(3, 2), torch.ones(1, 3))
        print("trace", tuple(traced(torch.ones(4, 3)).shape))
        @torch.jit.script
        def twice(v: torch.Tensor) -> torch.Tensor:
            return v * 2
        print("script", twice(torch.ones(2)).tolist())
        loader = DataLoader(TensorDataset(torch.arange(10.0)), batch_size=4, shuffle=True)
        print("loader", sorted(int(v) for (batch,) in loader for v in batch) == list(range(10)))
        print("half", (torch.ones(2, dtype=torch.float16) + 1).tolist(), torch.ones(2, dtype=torch.bfloat16).sum().item())
        print("linalg", [round(v, 3) for v in torch.linalg.svdvals(torch.tensor([[3.0, 0.0], [0.0, 4.0]])).tolist()])
        print("mps", torch.backends.mps.is_available(), "cuda", torch.cuda.is_available())
        try:
            torch.compile(lambda v: v + 1)(torch.ones(1))
            print("compile ran")
        except Exception as error:
            print("compile refused:", type(error).__name__)
        """, timeout: 240)
        XCTAssertEqual(outcome.code, 0, outputText())
        XCTAssertTrue(outputText().contains("func True [4.0, 4.0, 4.0]"), outputText())
        XCTAssertTrue(outputText().contains("fft [0.0, 2.0, 0.0]"), outputText())
        XCTAssertTrue(outputText().contains("distributions -0.9189"), outputText())
        XCTAssertTrue(outputText().contains("trace (4, 2)"), outputText())
        XCTAssertTrue(outputText().contains("script [2.0, 2.0]"), outputText())
        XCTAssertTrue(outputText().contains("loader True"), outputText())
        XCTAssertTrue(outputText().contains("half [2.0, 2.0] 2.0"), outputText())
        XCTAssertTrue(outputText().contains("linalg [4.0, 3.0]"), outputText())
        XCTAssertTrue(outputText().contains("mps False cuda False"), outputText())
        XCTAssertTrue(outputText().contains("compile refused:"), outputText())
    }

    func testAnEsbuildScriptIsRunAndANodeToolIsExplained() throws {
        let build = try NpmScripts.parse(["src/main.jsx", "--bundle", "--minify", "--outdir=static/assets", "--loader:.svg=file", "--target=es2020"])
        XCTAssertEqual(build.entryPoints, ["src/main.jsx"])
        XCTAssertEqual(build.outdir, "static/assets")
        XCTAssertTrue(build.minify)
        XCTAssertEqual(build.loader, [".svg": "file"])
        XCTAssertEqual(build.options["mode"] as? String, "production")
        XCTAssertEqual(try NpmScripts.parse(["src/main.jsx", "--watch"]).options["mode"] as? String, "development")
        XCTAssertThrowsError(try NpmScripts.parse(["--bundle"]))
    }

    func testAServerSaysWhereItListens() async throws {
        let source = """
        from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler
        server = ThreadingHTTPServer(("0.0.0.0", 0), BaseHTTPRequestHandler)
        print("port", server.server_port, flush=True)
        try:
            server.serve_forever()
        finally:
            server.server_close()
        """
        try await run(source) {
            try await self.waitUntil(timeout: 30) { self.session.listening != nil && self.outputText().contains("port") }
            let printed = self.outputText().firstMatch(of: /port (\d+)/).map { Int($0.1) }
            XCTAssertEqual(self.session.listening?.port, printed ?? -1)
            XCTAssertEqual(self.session.listening?.url?.host(), "127.0.0.1", "a server on every interface is opened through loopback")
            self.session.stop()
        }
        XCTAssertNil(session.listening, "the address ends with the run")
    }

    func testCompletionKnowsTheProjectsOwnModules() async throws {
        _ = try write("shapes.py", "def area_of_circle(r):\n    return 3.14 * r * r\n\ndef area_of_square(side):\n    return side * side\n")
        let source = "import shapes\nimport collections\nshapes.area_\ncollections.Ord"
        var found: [String: [PythonCompletion]] = [:]
        session.onCompletions = { token, items in found[token] = items }
        defer { session.onCompletions = nil }
        session.analyze(["action": "complete", "token": "module", "root": root.path, "path": root.appending(path: "main.py").path, "source": source, "line": 3, "column": 12])
        session.analyze(["action": "complete", "token": "stdlib", "root": root.path, "path": root.appending(path: "main.py").path, "source": source, "line": 4, "column": 15])
        try await waitUntil(timeout: 60) { found.count == 2 }
        XCTAssertEqual(Set(found["module"]?.map(\.label) ?? []), ["area_of_circle", "area_of_square"])
        XCTAssertTrue(found["stdlib"]?.contains { $0.label == "OrderedDict" } == true, "\(found["stdlib"] ?? [])")
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
        // pip runs in the same interpreter: nothing it set up may police later imports.
        let later = try await self.run("import email.mime.text, jedi, pyflakes.api\nprint('imported')\n")
        XCTAssertEqual(later.status, "finished", outputText())
        XCTAssertFalse(outputText().contains("after pip install started"), outputText())
    }
}
