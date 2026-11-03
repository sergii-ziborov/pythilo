"use client";
import { useCallback, useEffect, useRef, useState } from "react";
import type { RuntimeAction } from "@/lib/playground-runtime-authority";
import type { RuntimeJobUpdate } from "@/lib/playground-runtime-host";
import pythonWorker from "@/content/worker.json";
import { JOB_LIMIT_MS, STDIN_BYTES, stdinLayout, type LessonCheckResult, type RunResult, type WorkerReply, type WorkerRequest } from "@/lib/python-runtime";

export type TranscriptPart = { stream: "stdout" | "stderr" | "stdin"; text: string };
type SharedObserver = { id: string; update: (value: RuntimeJobUpdate) => void };
type Pending = { id: string; kind: "project" | "lesson"; resolve: (value: RunResult | LessonCheckResult) => void; reject: (error: Error) => void; shared?: SharedObserver; operation?: RuntimeAction };
export type PythonActivity = "idle" | "loading" | "running";

const newID = () => Array.from(crypto.getRandomValues(new Uint8Array(12)), byte => byte.toString(16).padStart(2, "0")).join("");

/** One Pyodide worker per page. Python never runs on the main thread. */
export function usePythonRuntime() {
  const worker = useRef<Worker | null>(null), loading = useRef<Promise<void> | null>(null), pending = useRef<Pending | null>(null);
  const interrupt = useRef<Uint8Array | null>(null), stdin = useRef<SharedArrayBuffer | null>(null);
  const stopTimer = useRef<ReturnType<typeof setTimeout> | undefined>(undefined), limitTimer = useRef<ReturnType<typeof setTimeout> | undefined>(undefined);
  const [ready, setReady] = useState(false), [activity, setActivity] = useState<PythonActivity>("idle"), [stage, setStage] = useState("");
  const [transcript, setTranscript] = useState<TranscriptPart[]>([]), [waitingForInput, setWaitingForInput] = useState(false), [error, setError] = useState("");
  const [result, setResult] = useState<RunResult | null>(null);
  const append = useCallback((part: TranscriptPart) => setTranscript(previous => {
    const last = previous.at(-1);
    return last && last.stream === part.stream ? [...previous.slice(0, -1), { stream: part.stream, text: last.text + part.text }] : [...previous, part];
  }), []);

  const terminate = useCallback((reason: string) => {
    worker.current?.terminate(); worker.current = null; loading.current = null; setReady(false);
    const job = pending.current; pending.current = null;
    if (stopTimer.current) clearTimeout(stopTimer.current); if (limitTimer.current) clearTimeout(limitTimer.current);
    setWaitingForInput(false); setActivity("idle"); setStage(reason);
    job?.shared?.update({ state: "finished", succeeded: false, exitCode: null, stage: reason });
    job?.reject(new Error(reason));
  }, []);

  const finish = useCallback(() => {
    if (stopTimer.current) clearTimeout(stopTimer.current); if (limitTimer.current) clearTimeout(limitTimer.current);
    pending.current = null; setWaitingForInput(false); setActivity("idle");
  }, []);

  const load = useCallback((): Promise<void> => {
    if (loading.current) return loading.current;
    setActivity(previous => previous === "idle" ? "loading" : previous); setStage("Loading Python in this browser");
    const isolated = globalThis.crossOriginIsolated === true && typeof SharedArrayBuffer !== "undefined";
    if (isolated) {
      const buffer = new SharedArrayBuffer(1); interrupt.current = new Uint8Array(buffer);
      stdin.current = new SharedArrayBuffer(8 + STDIN_BYTES);
    }
    // Built by scripts/prepare-assets.mjs: Pyodide needs a module worker.
    const instance = new Worker(pythonWorker.url, { type: "module" });
    worker.current = instance;
    loading.current = new Promise<void>((resolve, reject) => {
      instance.onmessage = ({ data }: MessageEvent<WorkerReply>) => {
        if (worker.current !== instance) return;
        if (data.type === "ready") { setReady(true); setStage(`Python is ready in this browser`); setActivity(previous => previous === "loading" ? "idle" : previous); resolve(); }
        else if (data.type === "stage") { setStage(data.label); pending.current?.shared?.update({ state: "progress", stage: data.label }); }
        else if (data.type === "output") { if (pending.current?.id === data.id) append({ stream: data.stream, text: data.text }); }
        else if (data.type === "input") { if (pending.current?.id === data.id) setWaitingForInput(true); }
        else if (data.type === "result" || data.type === "lesson-result") {
          const job = pending.current; if (!job || job.id !== data.id) return;
          finish();
          if (data.type === "result") {
            setResult(data.result); setStage(data.result.status === "stopped" ? "Stopped." : "Finished in this browser.");
            job.shared?.update({ state: "finished", succeeded: data.result.status === "succeeded", exitCode: data.result.exitCode, stdout: data.result.stdout, stderr: data.result.stderr, diagnostics: data.result.diagnostics, durationMs: data.result.durationMs, stage: data.result.status === "stopped" ? "Stopped" : "Finished" });
          } else setStage(data.result.stopped ? "Stopped." : "Checked in this browser.");
          job.resolve(data.result);
        } else if (data.type === "error") {
          if (!data.id) { reject(new Error(data.error)); terminate(data.error); setError(data.error); return; }
          const job = pending.current; if (!job || job.id !== data.id) return;
          finish(); setError(data.error); setStage("");
          job.shared?.update({ state: "finished", succeeded: false, exitCode: null, stage: data.error });
          job.reject(new Error(data.error));
        }
      };
      instance.onerror = () => { if (worker.current !== instance) return; const message = "Python stopped unexpectedly in this browser. Your code is still in the editor."; reject(new Error(message)); terminate(message); setError(message); };
    });
    instance.postMessage({ type: "initialize", interrupt: interrupt.current ? interrupt.current.buffer as SharedArrayBuffer : null, stdin: stdin.current } satisfies WorkerRequest);
    return loading.current;
  }, [append, finish, terminate]);

  const stop = useCallback(() => {
    if (!pending.current) return;
    setStage("Stopping…");
    if (interrupt.current) {
      interrupt.current[0] = 2;
      // A program stuck outside Python bytecode cannot see the interrupt; end the worker.
      stopTimer.current = setTimeout(() => terminate("Stopped. Python was restarted in this browser."), 2000);
    } else terminate("Stopped. Python was restarted in this browser.");
  }, [terminate]);

  const begin = useCallback(async (request: WorkerRequest & { id: string }, kind: Pending["kind"], shared?: SharedObserver, operation?: RuntimeAction) => {
    if (pending.current) throw new Error("Python in this browser is busy.");
    setError(""); setTranscript([]); setWaitingForInput(false); if (kind === "project") setResult(null);
    const promise = new Promise<RunResult | LessonCheckResult>((resolve, reject) => { pending.current = { id: request.id, kind, resolve, reject, shared, operation }; });
    setActivity("running");
    try { await load(); }
    catch (failure) { const job = pending.current as Pending | null; finish(); job?.reject(failure instanceof Error ? failure : new Error(String(failure))); return promise; }
    if ((pending.current as Pending | null)?.id !== request.id) return promise;
    limitTimer.current = setTimeout(() => { setError("Stopped at the two-minute limit."); stop(); }, JOB_LIMIT_MS);
    worker.current!.postMessage(request);
    return promise;
  }, [finish, load, stop]);

  const run = useCallback((operation: RuntimeAction, files: Record<string, string>, entry: string, revision: string, shared?: SharedObserver): Promise<RunResult> =>
    begin({ type: operation, id: shared?.id ?? newID(), files, entry, revision, startedAt: Date.now() }, "project", shared, operation) as Promise<RunResult>, [begin]);
  const checkLesson = useCallback((code: string, checks: { name: string; code: string }[]): Promise<LessonCheckResult> =>
    begin({ type: "lesson-check", id: newID(), code, checks, startedAt: Date.now() }, "lesson") as Promise<LessonCheckResult>, [begin]);

  const provideInput = useCallback((text: string | null) => {
    const buffer = stdin.current; if (!buffer || !waitingForInput) return;
    const { header, data } = stdinLayout(buffer);
    if (text === null) Atomics.store(header, 0, 2);
    else {
      const bytes = new TextEncoder().encode(text).subarray(0, data.length);
      data.set(bytes); Atomics.store(header, 1, bytes.length); Atomics.store(header, 0, 1);
    }
    Atomics.notify(header, 0); setWaitingForInput(false);
  }, [waitingForInput]);

  const stopOwned = useCallback((id: string) => { if (pending.current?.shared?.id === id) stop(); }, [stop]);
  useEffect(() => () => { worker.current?.terminate(); if (stopTimer.current) clearTimeout(stopTimer.current); if (limitTimer.current) clearTimeout(limitTimer.current); }, []);

  return { ready, activity, busy: activity === "running", stage, transcript, waitingForInput, error, result, setResult, load, run, checkLesson, stop, stopOwned, provideInput, clearError: () => setError(""), isolated: typeof globalThis.crossOriginIsolated === "boolean" && globalThis.crossOriginIsolated };
}
export type PythonRuntime = ReturnType<typeof usePythonRuntime>;
