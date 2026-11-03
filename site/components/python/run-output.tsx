"use client";

import { useEffect, useRef, useState } from "react";
import type { TranscriptPart } from "./use-python-runtime";
import { runtimeSummary, type Diagnostic, type RunResult } from "@/lib/python-runtime";

const verb = { run: "Ran", check: "Checked", test: "Tested" } as const;

/** Where, on what and for which source a result was produced. */
export function RunFooter({ result }: { result: Pick<RunResult, "operation" | "ranOn" | "runtime" | "revision" | "startedAt" | "durationMs" | "status" | "exitCode"> }) {
  const time = new Date(result.startedAt).toLocaleTimeString([], { hour: "2-digit", minute: "2-digit", second: "2-digit" });
  return <div className="run-footer">
    {verb[result.operation]} {result.ranOn.here ? <>in <strong>this browser</strong></> : <>on <strong>{result.ranOn.kind === "browser" ? `${result.ranOn.name}'s browser` : result.ranOn.name}</strong></>} · {result.runtime}<br />
    {result.revision ? <>Revision <code>{result.revision.slice(0, 6)}</code> · </> : null}{time} · {runtimeSummary(result)}
  </div>;
}

export function Diagnostics({ items, onOpen }: { items: Diagnostic[]; onOpen?: (file: string, line?: number | null) => void }) {
  if (!items.length) return null;
  return <ul className="diagnostics">{items.map((item, index) => <li key={index} className={item.level}>
    {item.file ? onOpen ? <button type="button" onClick={() => onOpen(item.file!, item.line)}>{item.file}{item.line ? `:${item.line}` : ""}</button> : <span>{item.file}{item.line ? `:${item.line}` : ""}</span> : null}
    <span>{item.message}</span>
  </li>)}</ul>;
}

export function Transcript({ parts, empty }: { parts: TranscriptPart[]; empty?: string }) {
  const end = useRef<HTMLPreElement>(null);
  useEffect(() => { const element = end.current; if (element) element.scrollTop = element.scrollHeight; }, [parts]);
  if (!parts.length) return empty ? <p className="output-empty">{empty}</p> : null;
  return <pre className="transcript" ref={end}>{parts.map((part, index) => <span key={index} className={part.stream}>{part.text}</span>)}</pre>;
}

export function InputLine({ onSubmit }: { onSubmit: (text: string | null) => void }) {
  const [text, setText] = useState(""), field = useRef<HTMLInputElement>(null);
  useEffect(() => { field.current?.focus(); }, []);
  return <form className="input-line" onSubmit={event => { event.preventDefault(); onSubmit(text); setText(""); }}>
    <label className="visually-hidden" htmlFor="program-input">Input for the program</label>
    <input id="program-input" ref={field} value={text} onChange={event => setText(event.target.value)} placeholder="The program is waiting for input" autoComplete="off" spellCheck={false} />
    <button type="submit" className="pill-button">Send</button>
    <button type="button" className="pill-button" onClick={() => onSubmit(null)} title="End of input (EOF)">End</button>
  </form>;
}
