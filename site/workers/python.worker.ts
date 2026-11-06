/// <reference lib="webworker" />
import type { PyodideAPI } from "pyodide";
import type { PyCallable } from "pyodide/ffi";
import checker from "../content/lessons-checker.json" with { type: "json" };
import { LESSON_SHIM, RUNNER_SOURCE, SHIM_ROOT } from "../lib/python-runner";
import { BROWSER_CHECKER, BROWSER_LOCKFILE, BROWSER_RUNTIME, PYODIDE_VERSION, explainRuntimeError, stdinLayout, type Diagnostic, type LessonCheckResult, type RunResult, type WorkerReply, type WorkerRequest } from "../lib/python-runtime";

const worker = self as unknown as DedicatedWorkerGlobalScope;
const post = (message: WorkerReply) => worker.postMessage(message);
const OUTPUT_LIMIT = 1024 * 1024;
let pyodide: PyodideAPI | undefined;
let interrupt: Uint8Array | null = null, stdin: SharedArrayBuffer | null = null;
let runner: Record<"run" | "check" | "test" | "lesson_check" | "imports", PyCallable> | undefined;
// With stack switching, asyncio.run works, but only below a promising call.
const stackSwitching = "Suspending" in WebAssembly || "Suspender" in WebAssembly;
const call = async (name: keyof NonNullable<typeof runner>, ...args: unknown[]): Promise<string> => stackSwitching ? runner![name].callPromising(...args) : runner![name](...args);

// Output reaches the page while Python runs: the worker is busy, so timers cannot flush it.
type Capture = { id: string; stdout: string; stderr: string; bytes: number; truncated: boolean; pending: Record<"stdout" | "stderr", string>; sentAt: number };
let capture: Capture | null = null;
const decoders = { stdout: new TextDecoder(), stderr: new TextDecoder() };
function flush() {
  if (!capture) return;
  for (const stream of ["stdout", "stderr"] as const) if (capture.pending[stream]) { post({ type: "output", id: capture.id, stream, text: capture.pending[stream] }); capture.pending[stream] = ""; }
  capture.sentAt = Date.now();
}
function writer(stream: "stdout" | "stderr") {
  return { isatty: false, write(buffer: Uint8Array) {
    const text = decoders[stream].decode(buffer, { stream: true });
    if (!capture) return buffer.length;
    if (capture.bytes + buffer.length > OUTPUT_LIMIT) { capture.truncated = true; return buffer.length; }
    capture.bytes += buffer.length; capture[stream] += text; capture.pending[stream] += text;
    if (Date.now() - capture.sentAt > 50 || capture.pending[stream].length > 8192) flush();
    return buffer.length;
  } };
}

function readLine(): string | null {
  if (!capture) return null;
  flush();
  if (!stdin) { const text = "input() needs a cross-origin isolated page; no input was read.\n"; capture.stderr += text; capture.pending.stderr += text; return null; }
  const { header, data } = stdinLayout(stdin);
  Atomics.store(header, 0, 0);
  post({ type: "input", id: capture.id });
  while (Atomics.load(header, 0) === 0) {
    Atomics.wait(header, 0, 0, 100);
    // Stop while waiting for input raises KeyboardInterrupt in the program.
    if (interrupt && interrupt[0] !== 0) { pyodide!.checkInterrupt(); }
  }
  if (Atomics.load(header, 0) === 2) { Atomics.store(header, 0, 0); return null; }
  const text = new TextDecoder().decode(data.slice(0, Atomics.load(header, 1)));
  Atomics.store(header, 0, 0);
  capture.stdout += text + "\n"; capture.pending.stdout += text + "\n";
  return text;
}

async function initialize() {
  if (pyodide) return;
  post({ type: "stage", label: "Loading Python in this browser" });
  const base = new URL("/pyodide/", worker.location.origin).href;
  const { loadPyodide } = await import(/* webpackIgnore: true */ /* turbopackIgnore: true */ base + "pyodide.mjs") as typeof import("pyodide");
  const instance = await loadPyodide({ indexURL: base, lockFileURL: new URL(BROWSER_LOCKFILE, worker.location.origin).href, env: { HOME: "/home/pyodide", PYTHONHASHSEED: "0" } });
  if (instance.version !== PYODIDE_VERSION) throw new Error(`Pyodide ${instance.version} does not match this site's ${PYODIDE_VERSION}.`);
  instance.setStdout(writer("stdout")); instance.setStderr(writer("stderr"));
  instance.setStdin({ stdin: readLine, isatty: false });
  if (interrupt) instance.setInterruptBuffer(interrupt);
  instance.FS.mkdirTree(SHIM_ROOT + "/pythilo_runtime");
  instance.FS.writeFile(SHIM_ROOT + "/pythilo_runtime/__init__.py", LESSON_SHIM);
  instance.FS.writeFile(SHIM_ROOT + "/pythilo_runtime/lessons.py", checker.source);
  instance.runPython(`import sys, types\nsys.path.append(${JSON.stringify(SHIM_ROOT)})\n_pythilo_web = types.ModuleType("_pythilo_web")\nexec(compile(${JSON.stringify(RUNNER_SOURCE)}, "<pythilo>", "exec"), _pythilo_web.__dict__)\nsys.modules["_pythilo_web"] = _pythilo_web`);
  const module = instance.pyimport("_pythilo_web");
  runner = { run: module.run, check: module.check, test: module.test, lesson_check: module.lesson_check, imports: module.imports };
  pyodide = instance;
  post({ type: "ready", runtime: BROWSER_RUNTIME });
}

async function prepare(sources: string, packages: string[] = []) {
  const message = (label: string) => post({ type: "stage", label: label.replace(/^Loading /, "Loading package ") });
  if (packages.length) await pyodide!.loadPackage(packages, { messageCallback: message, errorCallback: message });
  await pyodide!.loadPackagesFromImports(sources, { messageCallback: message, errorCallback: message });
}

function begin(id: string) {
  if (interrupt) interrupt[0] = 0;
  capture = { id, stdout: "", stderr: "", bytes: 0, truncated: false, pending: { stdout: "", stderr: "" }, sentAt: Date.now() };
}
function end() { const done = capture!; flush(); for (const stream of ["stdout", "stderr"] as const) decoders[stream].decode(); capture = null; return done; }

async function project(request: Extract<WorkerRequest, { type: "run" | "check" | "test" }>): Promise<RunResult> {
  const files = JSON.stringify(request.files), started = performance.now();
  const python = Object.entries(request.files).filter(([path]) => path.endsWith(".py")).map(([, text]) => text).join("\n");
  let framework: "pytest" | "unittest" | undefined;
  if (request.type === "test") {
    post({ type: "stage", label: "Loading pytest" });
    try { await pyodide!.loadPackage("pytest", { messageCallback: () => {}, errorCallback: () => {} }); framework = "pytest"; } catch { framework = "unittest"; }
  }
  if (request.type !== "check") await prepare(python);
  const missing: string[] = request.type === "check" ? [] : JSON.parse(await call("imports", files));
  const note = missing.length ? `${missing.join(", ")} ${missing.length === 1 ? "is" : "are"} not available in this browser's Python. Run this project in the Pythilo app to use ${missing.length === 1 ? "it" : "them"}.` : request.type === "check" ? (BROWSER_CHECKER === "pyflakes" ? "Compiled every file and ran pyflakes." : "Compiled every file. pyflakes is not part of Pyodide's packages, so this is a syntax check only.") : undefined;
  post({ type: "stage", label: request.type === "check" ? "Checking in this browser" : request.type === "test" ? `Running ${framework} in this browser` : `Running ${request.entry} in this browser` });
  begin(request.id);
  let reply: { exitCode: number; stopped?: boolean; diagnostics: Diagnostic[] };
  try {
    reply = JSON.parse(request.type === "run" ? await call("run", files, request.entry) : request.type === "test" ? await call("test", files, framework) : await call("check", files, BROWSER_CHECKER === "pyflakes"));
  } catch (error) {
    const stopped = /KeyboardInterrupt/.test(String(error));
    reply = { exitCode: stopped ? 130 : 1, stopped, diagnostics: [] };
    if (!stopped) capture!.stderr += String(error) + "\n";
  }
  const output = end(), explained = explainRuntimeError(output.stderr);
  return {
    operation: request.type, status: reply.stopped ? "stopped" : reply.exitCode === 0 ? "succeeded" : "failed", exitCode: reply.exitCode,
    stdout: output.stdout, stderr: output.stderr, diagnostics: reply.diagnostics, truncated: output.truncated,
    ranOn: { name: "This browser", kind: "browser", here: true }, runtime: BROWSER_RUNTIME, revision: request.revision,
    startedAt: request.startedAt, durationMs: Math.round(performance.now() - started), ...(note || explained ? { note: [note, explained].filter(Boolean).join(" ") } : {}), ...(framework ? { framework } : {}), ...(request.type === "check" ? { checker: BROWSER_CHECKER } : {}),
  };
}

async function lesson(request: Extract<WorkerRequest, { type: "lesson-check" }>): Promise<LessonCheckResult> {
  const started = performance.now();
  await prepare([request.code, ...request.checks.map(check => check.code)].join("\n"));
  post({ type: "stage", label: "Checking in this browser" });
  begin(request.id);
  let reply: { results: LessonCheckResult["results"]; error: string | null; stopped: boolean };
  try { reply = JSON.parse(await call("lesson_check", request.code, JSON.stringify(request.checks))); }
  catch (error) { const stopped = /KeyboardInterrupt/.test(String(error)); reply = { results: [], error: stopped ? null : String(error), stopped }; }
  const output = end();
  return { ...reply, stdout: output.stdout, stderr: output.stderr, runtime: BROWSER_RUNTIME, startedAt: request.startedAt, durationMs: Math.round(performance.now() - started) };
}

worker.onmessage = async ({ data }: MessageEvent<WorkerRequest>) => {
  try {
    if (data.type === "initialize") {
      interrupt = data.interrupt ? new Uint8Array(data.interrupt) : null; stdin = data.stdin;
      await initialize(); return;
    }
    if (!pyodide || !runner) throw new Error("Python is not loaded yet.");
    if (data.type === "lesson-check") post({ type: "lesson-result", id: data.id, result: await lesson(data) });
    else post({ type: "result", id: data.id, result: await project(data) });
  } catch (error) {
    capture = null;
    post({ type: "error", ...("id" in data ? { id: data.id } : {}), error: error instanceof Error ? error.message : String(error) });
  }
};
