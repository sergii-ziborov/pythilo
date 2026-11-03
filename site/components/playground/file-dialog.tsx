"use client";

import { useMemo, useState } from "react";
import { insideFolder, type FileOperation } from "@/lib/playground-file-ops";
import type { PlaygroundDocument } from "@/lib/playground-document";
import type { TreeAction } from "./file-tree";

export type FileRequest = { action: Exclude<TreeAction, "copy-path" | "set-entry">; folder: boolean; path: string };

const titles = { "new-file": "New file", "new-folder": "New folder and file", rename: "Rename", move: "Move", duplicate: "Duplicate", delete: "Delete" } as const;
export const fileDialogTitle = (request: FileRequest) => titles[request.action];

const suggestedCopy = (path: string) => { const dot = path.lastIndexOf("."); return dot > path.lastIndexOf("/") + 1 ? `${path.slice(0, dot)}_copy${path.slice(dot)}` : `${path}_copy`; };

/** `check` plans the operation against the live project and throws the problem to show. */
export type FileCheck = (operation: FileOperation) => { movesPythonSource: boolean };

export function FileDialog({ request, source, check, onSubmit, onCancel }: { request: FileRequest; source: PlaygroundDocument; check: FileCheck; onSubmit: (operation: FileOperation) => void; onCancel: () => void }) {
  const initial = request.action === "new-file" ? (request.path ? `${request.path}/` : "") : request.action === "new-folder" ? "" : request.action === "duplicate" ? suggestedCopy(request.path) : request.path;
  const [path, setPath] = useState(initial), [fileName, setFileName] = useState("__init__.py"), [entry, setEntry] = useState("");
  const prefix = request.action === "new-folder" && request.path ? `${request.path}/` : "";
  const deleted = request.action === "delete" ? (request.folder ? Object.keys(source.files).filter(item => insideFolder(item, request.path)) : [request.path]) : [];
  const entryChoices = deleted.includes(source.entryFile) ? Object.keys(source.files).filter(item => item.endsWith(".py") && !deleted.includes(item)).sort() : [];

  const operation = useMemo((): FileOperation | null => {
    switch (request.action) {
      case "new-file": return { kind: "create", path };
      case "new-folder": return path.trim() ? { kind: "create", path: `${prefix}${path.trim().replace(/\/+$/, "")}/${fileName.trim()}` } : null;
      case "rename": case "move": return request.folder ? { kind: "rename-folder", from: request.path, to: path } : { kind: "rename", from: request.path, to: path };
      case "duplicate": return { kind: "duplicate", from: request.path, to: path };
      case "delete": return request.folder ? { kind: "delete-folder", path: request.path, entryFile: entry || undefined } : { kind: "delete-file", path: request.path, entryFile: entry || undefined };
    }
  }, [request, path, prefix, fileName, entry]);

  const { plan, problem } = useMemo(() => {
    if (!operation) return { plan: null, problem: "Enter a folder name." };
    try { return { plan: check(operation), problem: "" }; }
    catch (error) { return { plan: null, problem: error instanceof Error ? error.message : String(error) }; }
  }, [operation, check]);
  const untouched = path === initial && (request.action === "new-file" || request.action === "new-folder" || request.action === "rename" || request.action === "move");

  return <form className="dialog-body" onSubmit={event => { event.preventDefault(); if (operation && plan) onSubmit(operation); }}>
    {request.action === "delete" ? <>
      <p>{request.folder ? `Delete ${deleted.length} file${deleted.length === 1 ? "" : "s"} in ${request.path}?` : `Delete ${request.path}?`} Download a copy first if you may need {deleted.length === 1 ? "it" : "them"}.</p>
      {request.folder ? <ul className="plain-list">{deleted.map(item => <li key={item}>{item}</li>)}</ul> : null}
      {entryChoices.length ? <label className="field">New entry file<select value={entry} autoFocus onChange={event => setEntry(event.target.value)}><option value="">Choose…</option>{entryChoices.map(item => <option key={item}>{item}</option>)}</select></label> : null}
    </> : <>
      <label className="field">{request.action === "new-folder" ? `Folder name${prefix ? ` inside ${prefix}` : ""}` : "Path"}<input autoFocus value={path} spellCheck={false} autoCapitalize="off" onChange={event => setPath(event.target.value)} placeholder={request.action === "new-folder" ? "cleaner" : "helpers.py"} aria-invalid={!untouched && !!problem} aria-describedby="file-problem" /></label>
      {request.action === "new-folder" ? <><label className="field">First file<input value={fileName} spellCheck={false} autoCapitalize="off" onChange={event => setFileName(event.target.value)} /></label><p className="field-note">A project stores files, so a folder is created together with its first file.</p></> : null}
    </>}
    <p id="file-problem" className="field-problem" role="status">{untouched ? "" : problem}</p>
    {plan?.movesPythonSource ? <p className="field-note">Imports that name the old path are not rewritten. Run Check after moving.</p> : null}
    <div className="dialog-actions">
      <button type="button" className="pill-button" onClick={onCancel}>Cancel</button>
      <button type="submit" className={request.action === "delete" ? "pill-button danger" : "pill-button primary"} disabled={!plan || untouched}>{titles[request.action]}</button>
    </div>
  </form>;
}
