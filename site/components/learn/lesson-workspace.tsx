"use client";

import Link from "next/link";
import { createContext, useCallback, useContext, useEffect, useMemo, useRef, useState, type ReactNode } from "react";
import { usePythonRuntime, type PythonRuntime } from "@/components/python/use-python-runtime";
import { PlainEditor } from "@/components/python/plain-editor";
import { InputLine, RunFooter, Transcript } from "@/components/python/run-output";
import { BROWSER_RUNTIME, PYODIDE_VERSION, explainRuntimeError, type LessonCheckResult } from "@/lib/python-runtime";
import { markPassed, readDraft, writeDraft } from "./progress";

type Owner = "solution" | `example:${number}`;
type LessonContextValue = { python: PythonRuntime; owner: Owner | null; run: (owner: Owner, code: string) => void; blocked: boolean };
const LessonContext = createContext<LessonContextValue | null>(null);

export type LessonSection = { chip: string; title: string; content: ReactNode };
type Props = {
  course: string; lesson: string; breadcrumb: { courseTitle: string; lessonTitle: string }; position: string;
  sections: LessonSection[]; task: ReactNode; starter: string; checks: { name: string; code: string }[]; hints: ReactNode[]; explanation: ReactNode;
  next: { href: string; title: string } | null; missing: string[]; packages: string[];
};

/** "Run example" under a code block in the reading. Its output appears under the block. */
export function ExampleBlock({ code, index, children }: { code: string; index: number; children: ReactNode }) {
  const context = useContext(LessonContext)!, mine = context.owner === `example:${index}`, python = context.python;
  return <figure className="example">
    {children}
    <button type="button" className="example-run" disabled={context.python.busy || context.blocked} onClick={() => context.run(`example:${index}`, code)}><svg width="12" height="14" viewBox="0 0 14 16" fill="currentColor" aria-hidden="true"><path d="M1 1.8c0-.8.9-1.3 1.6-.9l10 6.2c.6.4.6 1.4 0 1.8l-10 6.2c-.7.4-1.6-.1-1.6-.9z" /></svg>{mine && python.busy ? python.stage || "Running…" : "Run example"}</button>
    {mine && (python.transcript.length || python.result) ? <figcaption className="example-output">
      <Transcript parts={python.transcript} empty="(no output)" />
      {python.waitingForInput ? <InputLine onSubmit={python.provideInput} /> : null}
      {python.result && !python.busy ? <RunFooter result={python.result} /> : null}
    </figcaption> : null}
  </figure>;
}

export function LessonWorkspace({ course, lesson, breadcrumb, position, sections, task, starter, checks, hints, explanation, next, missing, packages }: Props) {
  const python = usePythonRuntime();
  const [section, setSection] = useState(0), [owner, setOwner] = useState<Owner | null>(null);
  const [code, setCode] = useState(starter), [version, setVersion] = useState(0), [restored, setRestored] = useState(false);
  const [hintsShown, setHintsShown] = useState(0), [checked, setChecked] = useState<LessonCheckResult | null>(null), [failure, setFailure] = useState("");
  const saveTimer = useRef<ReturnType<typeof setTimeout> | undefined>(undefined);
  const blocked = missing.length > 0;
  const taskIndex = sections.length;

  useEffect(() => { const draft = readDraft(course, lesson); if (draft !== null && draft !== starter) { setCode(draft); setVersion(value => value + 1); setRestored(true); } }, [course, lesson, starter]);
  const change = useCallback((value: string) => {
    setCode(value); setChecked(null);
    if (saveTimer.current) clearTimeout(saveTimer.current);
    saveTimer.current = setTimeout(() => writeDraft(course, lesson, value === starter ? null : value), 400);
  }, [course, lesson, starter]);
  const run = useCallback((who: Owner, source: string) => {
    setOwner(who); setFailure("");
    if (who === "solution") setChecked(null);
    void python.run("run", { "solution.py": source }, "solution.py", "").catch(error => { if (!/^Stopped/.test(error.message)) setFailure(error.message); });
  }, [python]);
  const check = async () => {
    setOwner("solution"); setFailure(""); setChecked(null);
    try {
      const result = await python.checkLesson(code, checks);
      setChecked(result);
      if (!result.stopped && !result.error && result.results.length && result.results.every(item => item.ok)) { markPassed(course, lesson); setSection(taskIndex); }
    } catch (error) { if (!/^Stopped/.test(error instanceof Error ? error.message : "")) setFailure(error instanceof Error ? error.message : String(error)); }
  };
  const context = useMemo(() => ({ python, owner, run, blocked }), [python, owner, run, blocked]);
  const passed = checked && !checked.stopped && !checked.error && checked.results.length > 0 && checked.results.every(item => item.ok);
  const failed = checked?.results.filter(item => !item.ok) ?? [];
  const solutionOutput = owner === "solution";
  const missingText = missing.join(" and ");

  return <LessonContext.Provider value={context}>
    <div className="lesson-shell">
      <header className="lesson-header">
        <Link href="/" className="brand"><span aria-hidden="true" className="brand-mark" style={{ width: 28, height: 28, fontSize: 12 }}>py</span>Pythilo</Link>
        <nav aria-label="Breadcrumb" className="lesson-breadcrumb"><Link href="/learn/">Learn</Link> / <Link href={`/learn/${course}/`}>{breadcrumb.courseTitle}</Link> / <span>{breadcrumb.lessonTitle}</span></nav>
        <span className="lesson-position">{position} · progress kept in this browser</span>
      </header>
      <div className="lesson">
        <article className="lesson-reading">
          <nav aria-label="Lesson parts" className="lesson-chips">
            {sections.map((item, index) => <button key={index} type="button" aria-current={section === index ? "step" : undefined} onClick={() => setSection(index)}><span>{index + 1}</span>{item.chip}</button>)}
            <button type="button" aria-current={section === taskIndex ? "step" : undefined} onClick={() => setSection(taskIndex)}>Your task</button>
          </nav>
          {sections.map((item, index) => <section key={index} hidden={section !== index} aria-labelledby={`part-${index}`}>
            <h1 id={`part-${index}`}>{item.title}</h1>
            <div className="lesson-prose">{item.content}</div>
            <div className="lesson-continue"><button type="button" className="pill-button" onClick={() => setSection(index + 1)}>{index + 1 < sections.length ? `Next: ${sections[index + 1].chip}` : "Next: Your task"}</button></div>
          </section>)}
          <section hidden={section !== taskIndex} aria-labelledby="part-task">
            <h1 id="part-task">Your task</h1>
            <div className="lesson-prose"><p>{task}</p>
              {hintsShown ? <><h2>Hints</h2><ol>{hints.slice(0, hintsShown).map((hint, index) => <li key={index}>{hint}</li>)}</ol></> : null}
              {passed ? <><h2>Why it works</h2>{explanation}</> : <p className="storage-note">The explanation opens here once every check passes.</p>}
            </div>
          </section>
        </article>
        <section aria-label="Your solution" className="lesson-solution">
          <div className="lesson-task">
            <div className="label">Your task</div>
            <p>{task}</p>
            {blocked ? <p className="lesson-blocked" role="note">This lesson uses {missingText}, which Python in this browser does not include. Read it here, and run and check it in the Pythilo app on iPhone or iPad.</p>
              : packages.length ? <p className="field-note">The first run loads {packages.map(name => name === "numpy" ? "NumPy" : name).join(", ")} into this browser.</p> : null}
            {restored ? <p className="field-note">Your code from an earlier visit, kept in this browser. <button type="button" className="link-button" onClick={() => { writeDraft(course, lesson, null); setCode(starter); setVersion(value => value + 1); setRestored(false); setChecked(null); }}>Start over</button></p> : null}
          </div>
          <div className="lesson-editor"><PlainEditor value={code} onChange={change} label="Your solution" version={version} /></div>
          <div className="lesson-results" aria-live="polite">
            {hintsShown ? <div className="lesson-hint"><strong>Hint {hintsShown} of {hints.length}</strong><p>{hints[hintsShown - 1]}</p></div> : null}
            {solutionOutput && python.busy ? <p className="output-stage" role="status">{python.stage}</p> : null}
            {failure ? <p className="output-error" role="alert">{failure}</p> : null}
            {checked ? passed ? <div role="status" className="check-card ok">
              <strong>All {checked.results.length} checks passed</strong>
              <span>{checked.results.map(item => item.name).join(" · ")}</span>
              <small>Checked in this browser · Pyodide {PYODIDE_VERSION} · {(checked.durationMs / 1000).toFixed(2)} s</small>
            </div> : checked.stopped ? <div role="status" className="check-card">Stopped.</div> : <div role="status" className="check-card fail">
              <strong>{checked.error ? "Your code did not finish loading" : `${checked.results.length - failed.length} of ${checked.results.length} checks passed`}</strong>
              {checked.error ? <span className="check-message">{checked.error}</span> : <ul>{failed.map(item => <li key={item.name}><b>{item.name}</b><span className="check-message">{item.message}</span></li>)}</ul>}
              {explainRuntimeError([checked.error ?? "", ...failed.map(item => item.message)].join("\n")) ? <span>{explainRuntimeError([checked.error ?? "", ...failed.map(item => item.message)].join("\n"))}</span> : null}
              <small>Checked in this browser · {BROWSER_RUNTIME}</small>
            </div> : null}
            {solutionOutput && (python.transcript.length || (python.result && !checked)) ? <div className="lesson-output"><div className="label">Output</div><Transcript parts={python.transcript} empty="(no output)" />{python.result && !checked && !python.busy ? <RunFooter result={python.result} /> : null}</div> : null}
            {solutionOutput && python.waitingForInput ? <InputLine onSubmit={python.provideInput} /> : null}
          </div>
          <div className="lesson-bar">
            <button type="button" className="pill-button hint" disabled={hintsShown >= hints.length} onClick={() => setHintsShown(count => Math.min(hints.length, count + 1))}>Hint</button>
            {python.busy ? <button type="button" className="pill-button danger" onClick={python.stop}>Stop</button> : <button type="button" className="pill-button" disabled={blocked} onClick={() => run("solution", code)}>Run</button>}
            {next ? <Link href={next.href} className="lesson-next">Next: {next.title}</Link> : <Link href={`/learn/${course}/`} className="lesson-next">All lessons</Link>}
            <button type="button" className="lesson-check" disabled={blocked || python.busy} onClick={() => void check()}><svg width="17" height="17" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="3" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><path d="M5 12l5 5 9-10" /></svg>Check</button>
          </div>
        </section>
      </div>
    </div>
  </LessonContext.Provider>;
}
