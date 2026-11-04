import { test, before } from "node:test";
import assert from "node:assert/strict";
import { existsSync, readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { loadPyodide } from "pyodide";
import { LESSON_SHIM, RUNNER_SOURCE, SHIM_ROOT } from "../lib/python-runner.ts";
import { parseInline, parseMarkdown } from "../lib/markdown.ts";
import { highlightPython } from "../lib/python-highlight.ts";

// The worker's Python code, run in the same Pyodide build under Node.
const site = fileURLToPath(new URL("..", import.meta.url));
const courses = JSON.parse(readFileSync(new URL("../content/courses.json", import.meta.url), "utf8")).courses;
const lock = new URL("../public/pyodide/pyodide-lock.json", import.meta.url);
let pyodide, runner, out = "", err = "";
// As in the worker: asyncio.run works only below a promising call, where the engine has stack switching.
const stackSwitching = "Suspending" in WebAssembly || "Suspender" in WebAssembly;
const take = () => { const value = { out, err }; out = err = ""; return value; };

before(async () => {
  pyodide = await loadPyodide({ indexURL: site + "node_modules/pyodide/", ...(existsSync(lock) ? { lockFileURL: fileURLToPath(lock), packageCacheDir: site + "public/pyodide/" } : {}) });
  pyodide.setStdout({ write: bytes => { out += new TextDecoder().decode(bytes); return bytes.length; } });
  pyodide.setStderr({ write: bytes => { err += new TextDecoder().decode(bytes); return bytes.length; } });
  pyodide.FS.mkdirTree(SHIM_ROOT + "/pythilo_runtime");
  pyodide.FS.writeFile(SHIM_ROOT + "/pythilo_runtime/__init__.py", LESSON_SHIM);
  pyodide.FS.writeFile(SHIM_ROOT + "/pythilo_runtime/lessons.py", JSON.parse(readFileSync(new URL("../content/lessons-checker.json", import.meta.url), "utf8")).source);
  pyodide.runPython(`import sys, types\nsys.path.append(${JSON.stringify(SHIM_ROOT)})\nm = types.ModuleType("_pythilo_web")\nexec(compile(${JSON.stringify(RUNNER_SOURCE)}, "<pythilo>", "exec"), m.__dict__)\nsys.modules["_pythilo_web"] = m`);
  runner = pyodide.pyimport("_pythilo_web");
});

test("run imports project modules, separates stdout and stderr and reports exit codes", () => {
  const files = { "main.py": "import sys\nfrom helper import twice\nprint(twice(21))\nprint('careful', file=sys.stderr)\n", "helper.py": "def twice(x):\n    return x * 2\n" };
  assert.deepEqual(JSON.parse(runner.run(JSON.stringify(files), "main.py")), { exitCode: 0, stopped: false, diagnostics: [] });
  assert.deepEqual(take(), { out: "42\n", err: "careful\n" });
  // An edited helper is imported again on the next run.
  runner.run(JSON.stringify({ ...files, "helper.py": "def twice(x):\n    return x + x + 1\n" }), "main.py");
  assert.equal(take().out, "43\n");
  assert.equal(JSON.parse(runner.run(JSON.stringify({ "main.py": "raise SystemExit(3)\n" }), "main.py")).exitCode, 3);
  take();
});

test("a traceback names project files, not the browser's paths", () => {
  const result = JSON.parse(runner.run(JSON.stringify({ "main.py": "def f():\n    return 1 / 0\n\nf()\n" }), "main.py"));
  const { err: text } = take();
  assert.equal(result.exitCode, 1);
  assert.deepEqual(result.diagnostics, [{ level: "error", file: "main.py", line: 2, message: "ZeroDivisionError: division by zero" }]);
  assert.match(text, /File "main.py", line 4, in <module>/);
  assert.doesNotMatch(text, /home\/pyodide|runpy/);
});

test("check compiles every file and says which checker ran", () => {
  const result = JSON.parse(runner.check(JSON.stringify({ "main.py": "print(\n", "ok.py": "x = 1\n", "notes.md": "(" }), false));
  assert.equal(result.exitCode, 1);
  assert.deepEqual(result.diagnostics.map(item => [item.file, item.line, item.level]), [["main.py", 1, "error"]]);
  const runtime = JSON.parse(readFileSync(new URL("../content/runtime.json", import.meta.url), "utf8"));
  assert.equal(runtime.checker, "compile", "pyflakes is not one of Pyodide's packages");
});

test("test runs pytest when it is available and unittest discovery otherwise", { skip: !existsSync(lock) && "Run pnpm build once to fetch pytest" }, async () => {
  const files = { "calc.py": "def add(a, b):\n    return a + b\n", "test_calc.py": "import unittest\nfrom calc import add\n\ndef test_add():\n    assert add(2, 2) == 4\n\nclass Calc(unittest.TestCase):\n    def test_wrong(self):\n        self.assertEqual(add(1, 1), 3)\n" };
  await pyodide.loadPackage("pytest", { messageCallback: () => {} });
  const pytest = JSON.parse(runner.test(JSON.stringify(files), "pytest"));
  assert.deepEqual([pytest.exitCode, pytest.framework], [1, "pytest"]);
  assert.match(take().out, /1 failed, 1 passed/);
  const unittest = JSON.parse(runner.test(JSON.stringify(files), "unittest"));
  assert.deepEqual([unittest.exitCode, unittest.framework], [1, "unittest"]);
  assert.match(take().out, /Ran 1 test/);
});

test("imports names what this browser lacks, not project modules or the standard library", () => {
  assert.deepEqual(JSON.parse(runner.imports(JSON.stringify({ "main.py": "import json, flask\nfrom helper import x\nfrom . import y\n", "helper.py": "" }))), ["flask"]);
});

test("every lesson's solution passes the app's own checker in Pyodide", { skip: !existsSync(lock) && "Run pnpm build once to fetch numpy" }, async () => {
  const failures = [];
  let checked = 0;
  for (const course of courses) for (const lesson of course.lessons) {
    if (lesson.missing.length) continue;
    if (lesson.packages.length) await pyodide.loadPackage(lesson.packages, { messageCallback: () => {} });
    const result = JSON.parse(stackSwitching ? await runner.lesson_check.callPromising(lesson.solution, JSON.stringify(lesson.checks)) : runner.lesson_check(lesson.solution, JSON.stringify(lesson.checks)));
    take(); checked++;
    if (result.error || result.results.length !== lesson.checks.length || result.results.some(item => !item.ok)) failures.push(`${course.id}/${lesson.id}: ${result.error ?? result.results.filter(item => !item.ok).map(item => `${item.name}: ${item.message}`).join("; ")}`);
  }
  assert.deepEqual(failures, []);
  assert.ok(checked > 50);
});

test("the checker's messages are the app's: a failing starter explains what came back", () => {
  const lesson = courses.find(course => course.id === "deeper").lessons.find(item => item.id === "functions-that-return-functions");
  const result = JSON.parse(runner.lesson_check(lesson.starter, JSON.stringify(lesson.checks)));
  take();
  assert.equal(result.results[0].ok, false);
  assert.equal(result.results[0].message, "second call\nadd(3) returned 3, expected 8.");
});

test("course content is built from the app's files, and lessons needing missing packages say so", () => {
  assert.deepEqual(courses.map(course => course.id), ["foundations", "deeper", "clean-code", "testing", "tools", "architecture", "async", "web", "data", "ml", "llm", "ai", "interview"]);
  const all = courses.flatMap(course => course.lessons);
  assert.ok(all.every(lesson => lesson.sections[0].chip === "Idea" && lesson.checks.length && lesson.starter));
  const lessonsOf = id => courses.find(course => course.id === id).lessons;
  // The Python courses run in the browser; torch lessons send the learner to the app.
  assert.deepEqual(["foundations", "deeper", "clean-code"].flatMap(id => lessonsOf(id)).filter(lesson => lesson.missing.length).map(lesson => lesson.id), []);
  assert.ok(lessonsOf("ml").every(lesson => lesson.missing.includes("torch")));
  assert.ok(all.filter(lesson => lesson.missing.length).every(lesson => lesson.missing.every(name => typeof name === "string" && name)));
  assert.ok(all.find(lesson => lesson.id === "flask-routes").missing.includes("flask"));
  assert.ok(lessonsOf("data").some(lesson => lesson.packages.includes("numpy")));
});

test("lesson Markdown keeps sections, fenced Python and inline code", () => {
  const blocks = parseMarkdown("Text with `code`.\n\n```python\nprint(1)\n```\n\n- one\n- two\n  continued\n");
  assert.deepEqual(blocks, [{ kind: "paragraph", text: "Text with `code`." }, { kind: "code", language: "python", code: "print(1)" }, { kind: "list", ordered: false, items: ["one", "two continued"] }]);
  assert.deepEqual(parseInline("**a** *b* [c](https://x.test) [d](javascript:x)").map(part => part.kind), ["strong", "text", "em", "text", "link", "text", "text"]);
  const tokens = highlightPython("def f():\n    return 'x'  # c").flat();
  assert.deepEqual(tokens.filter(token => token.className).map(token => [token.text, token.className]), [["def", "py-keyword"], ["f", "py-function"], ["return", "py-keyword"], ["'x'", "py-string"], ["# c", "py-comment"]]);
});
