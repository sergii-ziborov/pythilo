import runtime from "../content/runtime.json" with { type: "json" };
import type { RuntimeAction } from "./playground-runtime-authority.ts";

/** Pyodide and Python versions of the self-hosted runtime, fixed at build time. */
export const PYODIDE_VERSION: string = runtime.pyodide;
export const PYTHON_VERSION: string = runtime.python;
export const BROWSER_LOCKFILE: string = runtime.lockFile;
export const BROWSER_RUNTIME = `Pyodide ${runtime.pyodide} · Python ${runtime.python}`;
/** `pyflakes` when Pyodide ships it, otherwise a compile check only. */
export const BROWSER_CHECKER: "pyflakes" | "compile" = runtime.checker === "pyflakes" ? "pyflakes" : "compile";
export const BROWSER_PACKAGES: Record<string, string> = runtime.packages;
export const JOB_LIMIT_MS = 120_000;

export type Diagnostic = { level: "error" | "warning"; message: string; file?: string; line?: number | null; column?: number | null };
export type RunLocation = { name: string; kind: "browser" | "ios"; here: boolean };
export type RunStatus = "succeeded" | "failed" | "stopped";
/** Every result says where it ran, on what, for which source and how it ended. */
export type RunResult = {
  operation: RuntimeAction; status: RunStatus; exitCode: number | null; stdout: string; stderr: string; diagnostics: Diagnostic[];
  ranOn: RunLocation; runtime: string; revision: string; startedAt: number; durationMs: number;
  truncated?: boolean; note?: string; framework?: "pytest" | "unittest"; checker?: "pyflakes" | "compile";
};
export type LessonCheckResult = { results: { name: string; ok: boolean; message: string }[]; error: string | null; stopped: boolean; stdout: string; stderr: string; runtime: string; startedAt: number; durationMs: number };

/** Messages the page sends to the Python worker. */
export type WorkerRequest =
  | { type: "initialize"; interrupt: SharedArrayBuffer | null; stdin: SharedArrayBuffer | null }
  | { type: "run" | "check" | "test"; id: string; files: Record<string, string>; entry: string; revision: string; startedAt: number }
  | { type: "lesson-check"; id: string; code: string; checks: { name: string; code: string }[]; startedAt: number };
/** Messages the worker sends back. */
export type WorkerReply =
  | { type: "stage"; label: string }
  | { type: "ready"; runtime: string }
  | { type: "output"; id: string; stream: "stdout" | "stderr"; text: string }
  | { type: "input"; id: string }
  | { type: "result"; id: string; result: RunResult }
  | { type: "lesson-result"; id: string; result: LessonCheckResult }
  | { type: "error"; id?: string; error: string };

/** asyncio.run blocks on the browser's event loop, which needs WebAssembly stack switching (JSPI). */
export const STACK_SWITCHING_NOTE = "asyncio.run needs WebAssembly stack switching, which this browser does not have. Chrome and Edge have it, and the Pythilo app runs it too.";
export const explainRuntimeError = (text: string) => /stack switching not supported/i.test(text) ? STACK_SWITCHING_NOTE : undefined;

export const runtimeSummary = (result: Pick<RunResult, "status" | "exitCode" | "durationMs">) =>
  `${result.status === "stopped" ? "stopped" : `exit ${result.exitCode ?? "?"}`} · ${(result.durationMs / 1000).toFixed(2)} s`;

export function stdinLayout(buffer: SharedArrayBuffer) {
  // [state, length] then UTF-8 bytes. state 1 means a line is waiting for the worker.
  return { header: new Int32Array(buffer, 0, 2), data: new Uint8Array(buffer, 8) };
}
export const STDIN_BYTES = 64 * 1024;
