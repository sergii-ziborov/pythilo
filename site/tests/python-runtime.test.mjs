import { test, before } from "node:test";
import assert from "node:assert/strict";
import { existsSync, readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { loadPyodide } from "pyodide";
import { createHash } from "node:crypto";
import { LESSON_SHIM, RUNNER_SOURCE, SHIM_ROOT } from "../lib/python-runner.ts";
import { browserLabs, labFiles, readLabResult } from "../lib/browser-labs.ts";
import { parseInline, parseMarkdown } from "../lib/markdown.ts";
import { highlightPython } from "../lib/python-highlight.ts";
import { browserSourceMissing } from "../lib/python-source-support.ts";

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

test("a fresh runtime discovers new libraries from imports and versions its cached catalog", async () => {
  const runtime = JSON.parse(readFileSync(new URL("../content/runtime.json", import.meta.url), "utf8"));
  const hash = createHash("sha256").update(readFileSync(lock)).digest("hex").slice(0, 16);
  assert.equal(runtime.lockFile, `/pyodide/pyodide-lock.json?v=${hash}`);
  const fresh = await loadPyodide({ indexURL: site + "node_modules/pyodide/", lockFileURL: fileURLToPath(lock), packageCacheDir: site + "public/pyodide/" });
  assert.equal(fresh.runPython("import importlib.util; importlib.util.find_spec('pydantic') is None"), true);
  const source = "from pydantic import BaseModel\nfrom fastapi import FastAPI\nimport httpx\nclass Count(BaseModel):\n    value: int\nassert Count(value='12').value == 12\nassert FastAPI().title == 'FastAPI'\nassert httpx.Response(200, json={'ok': True}).json() == {'ok': True}\n";
  await fresh.loadPackagesFromImports(source, { messageCallback: () => {} });
  fresh.runPython(source);
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
  assert.ok(checked > 400);
  console.log(`Browser lesson solutions verified: ${checked}`);
});

test("the checker's messages are the app's: a failing starter explains what came back", () => {
  const lesson = courses.find(course => course.id === "deeper").lessons.find(item => item.id === "functions-that-return-functions");
  const result = JSON.parse(runner.lesson_check(lesson.starter, JSON.stringify(lesson.checks)));
  take();
  assert.equal(result.results[0].ok, false);
  assert.equal(result.results[0].message, "second call\nadd(3) returned 3, expected 8.");
});

test("lesson checks register their module and restore module/path state on success or failure", async () => {
  await pyodide.loadPackage("pydantic", { messageCallback: () => {} });
  pyodide.runPython("import sys, types\n_saved_module = types.ModuleType('previous_lesson')\nsys.modules['solution_under_test'] = _saved_module\n_saved_path = sys.path[:]");
  try {
    const source = "import sys\nfrom pydantic import RootModel\nclass Numbers(RootModel[list[int]]):\n    pass\nregistered = sys.modules[__name__].__dict__ is globals()\nvalue = Numbers.model_validate(['2', 3]).root\n";
    const checked = JSON.parse(runner.lesson_check(source, JSON.stringify([{ name: "real module", code: "assert registered and value == [2, 3]" }])));
    assert.equal(checked.error, null);
    assert.deepEqual(checked.results.map(item => item.ok), [true]);
    assert.equal(pyodide.runPython("sys.modules['solution_under_test'] is _saved_module and sys.path == _saved_path"), true);
    runner.lesson_check("raise ValueError('bad input')", "[]");
    assert.equal(pyodide.runPython("sys.modules['solution_under_test'] is _saved_module and sys.path == _saved_path"), true);
  } finally {
    pyodide.runPython("sys.modules.pop('solution_under_test', None)");
    take();
  }
});

test("course content is built from the app's files, and lessons needing missing packages say so", () => {
  assert.deepEqual(courses.map(course => course.id), ["foundations", "deeper", "clean-code", "testing", "tools", "architecture", "async", "web", "data", "math", "ml", "llm", "ai", "interview", "algorithm-patterns", "data-practice", "reliable-python", "ml-practice", "ml-evaluation", "ai-building-blocks", "pydantic", "fastapi-httpx", "testing-practice", "data-formats", "python-runtime", "python-systems", "ml-statistics", "ml-production", "ai-production", "deep-learning-practice", "senior-projects"]);
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


test("all browser labs trace actual edited code, accept worked answers and reject starters in Pyodide", () => {
  for (const lab of browserLabs) {
    for (const [source,correct] of [[lab.answer,true],[lab.starter,false]]) {
      const response=JSON.parse(runner.run(JSON.stringify(labFiles(lab.id,source)), "main.py"));
      const output=take();
      assert.equal(response.exitCode,0,`${lab.id}: ${output.err}`);
      assert.ok(new TextEncoder().encode(output.out).length < 1024*1024, `${lab.id}: trace must fit worker output limit`);
      const report=readLabResult(output.out);
      assert.equal(report.correct,correct,`${lab.id}: ${report.message}`);
      assert.ok(report.checks.length>=3,lab.id);
      if(correct){assert.equal(report.truncated,false,`${lab.id}: worked example must replay to completion`);assert.ok(report.frames.length>=3,lab.id);assert.ok(report.frames.every(frame=>frame.panels.length));}
      else assert.ok(report.checks.some(check=>!check.ok),lab.id);
    }
  }
});

test("every Python example in the six practical blog articles runs in Pyodide", async () => {
  const { allPosts } = await import('../app/blog/_lib/posts.ts');
  const posts = allPosts().filter(post => !post.slug.includes('news-november'));
  assert.equal(posts.length, 6);
  let count = 0;
  for (const post of posts) for (const block of post.blocks) {
    if (block.kind !== 'code' || block.language !== 'python') continue;
    const response = JSON.parse(runner.run(JSON.stringify({ 'example.py': block.code }), 'example.py'));
    const output = take();
    assert.equal(response.exitCode, 0, `${post.slug}: ${output.err}`);
    count++;
  }
  assert.ok(count >= 8);
});


test("every browser-compatible reading example in all courses runs independently", async () => {
  let checked = 0, unavailable = 0;
  const failures = [];
  for (const course of courses) for (const lesson of course.lessons) for (const section of lesson.sections) for (const block of parseMarkdown(section.markdown)) {
    if (block.kind !== "code" || block.language !== "python") continue;
    const missing = browserSourceMissing(block.code);
    if (missing.length) { unavailable++; continue; }
    await pyodide.loadPackagesFromImports(block.code, { messageCallback: () => {} });
    const files = JSON.stringify({ "example.py": block.code });
    const response = JSON.parse(stackSwitching ? await runner.run.callPromising(files, "example.py") : runner.run(files, "example.py"));
    const output = take();
    if (response.exitCode !== 0) failures.push(`${course.id}/${lesson.id}: ${output.err}`);
    checked++;
  }
  assert.deepEqual(failures, []);
  assert.equal(checked + unavailable, 539);
  assert.ok(checked > 400);
  console.log(`Reading examples verified in browser: ${checked}; app-only: ${unavailable}`);
});

test("all 52 new lessons and their examples are browser compatible", () => {
  const added = courses.filter(course => course.order >= 21 && course.order <= 24);
  assert.equal(added.flatMap(course => course.lessons).length, 52);
  for (const course of added) for (const lesson of course.lessons) {
    assert.deepEqual(lesson.missing, [], lesson.id);
    for (const section of lesson.sections) for (const block of parseMarkdown(section.markdown)) {
      if (block.kind === "code" && block.language === "python") assert.deepEqual(browserSourceMissing(block.code), [], lesson.id);
    }
  }
  assert.deepEqual(browserSourceMissing("from django.urls import path"), ["django"]);
  assert.deepEqual(browserSourceMissing("import threading\nthreading.Thread(target=print).start()"), ["threads"]);
});
