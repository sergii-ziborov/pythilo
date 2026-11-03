"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import * as Y from "yjs";
import { createPresence, remoteSelections } from "@/lib/playground-presence";
import { documentFromY, updateYDocument } from "@/lib/playground-collab";
import { documentRevision, exportArchive, fileText, readView, type ProjectView } from "@/lib/playground-project";
import { committedProjectName, newPlaygroundDocument, sourceBytes, validatePlaygroundDocument, type PlaygroundDocument } from "@/lib/playground-document";
import { newEncryptionSecret } from "@/lib/playground-crypto";
import { appLink, createPlayground, parsePlaygroundLink, playgroundLink, PlaygroundSession, type PlaygroundLink, type CreatedPlayground } from "@/lib/playground-session";
import { forgetOwnerCapabilities, rememberOwnerCapabilities, restoreOwnerCapabilities } from "@/lib/playground-client";
import { isDestructiveInSharedRoom, planFileOperation, type FileOperation, type TreeNode } from "@/lib/playground-file-ops";
import { deleteDraft, KEEP_DRAFTS_KEY, listDrafts, saveDraft, type StoredDraft } from "@/lib/playground-drafts";
import { RuntimePresenceChannel } from "@/lib/playground-runtime-channel";
import { runtimeSourceRevision } from "@/lib/playground-runtime-source";
import { runtimeActions, type RuntimeAction } from "@/lib/playground-runtime-authority";
import type { RuntimeClient } from "@/lib/playground-runtime-controller";
import { BROWSER_RUNTIME, PYODIDE_VERSION, type Diagnostic, type RunResult } from "@/lib/python-runtime";
import { usePythonRuntime, type TranscriptPart } from "@/components/python/use-python-runtime";
import { Diagnostics, InputLine, RunFooter, Transcript } from "@/components/python/run-output";
import { BrandMark } from "@/components/site-header";
import { createFileEditorState, PlaygroundCodeEditor, type FileEditorState } from "./code-editor";
import { useRuntimeHost } from "./use-runtime-host";
import { useRuntimeController } from "./use-runtime-controller";
import { RuntimePermissions } from "./runtime-permissions";
import { FileTree, type TreeAction } from "./file-tree";
import { FileDialog, fileDialogTitle, type FileRequest } from "./file-dialog";
import { ConnectAIDialog } from "./connect-ai-dialog";

type Modal = "share" | "connect" | "drafts" | "file" | "leave" | null;
type RemoteRun = { target: string; name: string; operation: RuntimeAction; stage: string; job?: string; revision?: string; error?: string };
const NAME_KEY = "pythilo.playground.name.v1";
const lifetimes: [number, string][] = [[3600, "1 hour"], [14400, "4 hours"], [43200, "12 hours"], [86400, "24 hours"]];
const verbs: Record<RuntimeAction, string> = { check: "Check", run: "Run", test: "Test" };

function download(name: string, bytes: Uint8Array, type: string) {
  const blob = new Blob([new Uint8Array(bytes)], { type });
  const url = URL.createObjectURL(blob), anchor = document.createElement("a");
  anchor.href = url; anchor.download = name; anchor.click(); setTimeout(() => URL.revokeObjectURL(url), 60_000);
}
function storedName(): string {
  try { const name = localStorage.getItem(NAME_KEY)?.trim(); return name && name.length <= 30 && !/[\u0000-\u001f\u007f]/.test(name) ? name : ""; } catch { return ""; }
}
export const hostLabel = (client: Pick<RuntimeClient, "name" | "kind">) => client.kind === "browser" ? `${client.name}'s browser` : client.name;
const ownerOf = (client: Pick<RuntimeClient, "name" | "kind">) => client.kind === "browser" ? client.name : client.name.match(/^(.+?)['’]s\s+(?:iPhone|iPad)/)?.[1] ?? "its owner";
const shortRuntime = (runtime: string) => runtime.replace(/^(CPython \d+\.\d+)\.\d+(.*)$/, "$1$2").replace(/ · iOS$/, "");
const diagnosticsOf = (items: unknown[]): Diagnostic[] => items.flatMap(item => {
  const value = item as Record<string, unknown>;
  return value && typeof value.message === "string" ? [{ level: value.level === "warning" ? "warning" : "error", message: value.message, ...(typeof value.file === "string" ? { file: value.file } : {}), ...(Number.isSafeInteger(value.line) ? { line: value.line as number } : {}) } as Diagnostic] : [];
});

// Survives a move to another page within this visit, so an unsaved draft is not lost
// even when the browser's back button leaves without any chance to ask first.
let unmountedDraft: { document: PlaygroundDocument; draftId: string } | null = null;
type LocalCopy = { key: number; seed?: PlaygroundDocument; notice?: string; draftId?: string; unsaved?: boolean };

/** Remounts with a fresh document, so a copy cannot keep any of a room's session state. */
export default function PlaygroundWorkspace() {
  const [instance, setInstance] = useState<LocalCopy>({ key: 0 });
  const openLocal = useCallback((seed: PlaygroundDocument, options: { notice: string; draftId?: string; unsaved: boolean }) => {
    // Removes the room's secret fragment, so a reload cannot rejoin the room.
    history.replaceState(null, "", "/playground/");
    setInstance(previous => ({ key: previous.key + 1, seed, ...options }));
  }, []);
  return <Workspace key={instance.key} seed={instance.seed} seedNotice={instance.notice} seedDraftId={instance.draftId} seedUnsaved={instance.unsaved} onOpenLocal={openLocal} />;
}

function Workspace({ seed, seedNotice, seedDraftId, seedUnsaved, onOpenLocal }: { seed?: PlaygroundDocument; seedNotice?: string; seedDraftId?: string; seedUnsaved?: boolean; onOpenLocal: (seed: PlaygroundDocument, options: { notice: string; draftId?: string; unsaved: boolean }) => void }) {
  const [displayName, setDisplayName] = useState(storedName);
  const [doc] = useState(() => new Y.Doc()), [awareness] = useState(() => createPresence(doc, displayName || undefined));
  const name = displayName || (awareness.getLocalState()?.user?.name as string) || "Guest";
  const [source, setSource] = useState<PlaygroundDocument | null>(null), [view, setView] = useState<ProjectView | null>(null);
  const [selected, setSelected] = useState("main.py"), [modal, setModal] = useState<Modal>(null), dialog = useRef<HTMLDialogElement>(null);
  const [link, setLink] = useState<PlaygroundLink | null>(null), [created, setCreated] = useState<CreatedPlayground | null>(null);
  const session = useRef<PlaygroundSession | null>(null), [connection, setConnection] = useState("Local draft · nothing leaves this browser");
  const [liveSession, setLiveSession] = useState<PlaygroundSession | null>(null);
  const [expiresAt, setExpiresAt] = useState<number | null>(null), [now, setNow] = useState(() => Date.now());
  const [lifetime, setLifetime] = useState(3600), [expired, setExpired] = useState(false), [sharing, setSharing] = useState(false);
  const [notice, setNotice] = useState(""), [filePane, setFilePane] = useState(false), [nameDraft, setNameDraft] = useState<string | null>(null);
  const [fileRequest, setFileRequest] = useState<FileRequest | null>(null), [leaveTo, setLeaveTo] = useState<string | null>(null);
  const [keepDrafts, setKeepDrafts] = useState(false), [drafts, setDrafts] = useState<StoredDraft[]>([]), [draftStatus, setDraftStatus] = useState("");
  const [revision, setRevision] = useState(""), [lastEdit, setLastEdit] = useState<{ name: string; path: string; at: number } | null>(null);
  const [participants, setParticipants] = useState<{ id: number; name: string; color: string; local: boolean; file?: string }[]>([]);
  const [resultSource, setResultSource] = useState<string | null>(null);
  const editorStates = useRef(new Map<string, FileEditorState>()), [draftId] = useState(() => seedDraftId ?? newEncryptionSecret());
  const unsaved = useRef(!!seedUnsaved), guard = useRef({ link: false, expired: false });
  const disposal = useRef<ReturnType<typeof setTimeout> | undefined>(undefined);

  const python = usePythonRuntime(), stopPython = python.stop;
  const channel = useMemo(() => liveSession ? new RuntimePresenceChannel(awareness) : null, [liveSession, awareness]);
  useEffect(() => () => channel?.close(), [channel]);
  const sourceOf = useCallback(() => readView(doc).document, [doc]);
  const host = useRuntimeHost(liveSession, awareness, channel, sourceOf, python, name);
  const control = useRuntimeController(liveSession, awareness, channel, sourceOf, name);
  const [target, setTarget] = useState("here"), [remote, setRemote] = useState<RemoteRun | null>(null), [remoteResult, setRemoteResult] = useState<RunResult | null>(null);
  const controlStatus = useRef(control.status); controlStatus.current = control.status;

  useEffect(() => {
    if (disposal.current) clearTimeout(disposal.current);
    try { setKeepDrafts(localStorage.getItem(KEEP_DRAFTS_KEY) === "true"); } catch {}
    const update = (transaction: Y.Transaction) => {
      try {
        if (transaction.changed.size > 0 && transaction.origin !== "initial" && !guard.current.link) unsaved.current = true;
        const value = readView(doc); setView(value); setSource(value.document);
        setSelected(previous => value.files.some(file => file.key === previous) ? previous : value.entryKey ?? value.files[0]?.key ?? previous);
        // Who changed which file, for "Claude edited cleaner.py".
        if (transaction.origin === session.current && session.current && transaction.changed.size) {
          const files = doc.getMap<Y.Text>("files");
          let path: string | undefined;
          transaction.changed.forEach((keys, type) => { if (!path && type instanceof Y.Text && type.parent === files) path = type._item?.parentSub ?? undefined; else if (!path && (type as unknown) === files) path = [...keys].find(Boolean) ?? undefined; });
          const author = [...transaction.afterState].find(([client, clock]) => client !== doc.clientID && clock > (transaction.beforeState.get(client) ?? 0))?.[0];
          const user = author === undefined ? undefined : awareness.getStates().get(author)?.user as { name?: string } | undefined;
          if (path && user?.name) setLastEdit({ name: user.name, path, at: Date.now() });
        }
      } catch { /* Joining an empty document waits for its authenticated snapshot. */ }
    };
    doc.on("afterTransaction", update);
    const people = () => {
      const files = new Map(remoteSelections(doc, awareness, true).map(selection => [selection.clientID, selection.file]));
      setParticipants(Array.from(awareness.getStates(), ([id, state]) => ({ id, name: String(state.user?.name ?? "Guest"), color: String(state.user?.color ?? "#5AA9FF"), local: id === awareness.clientID, file: files.get(id) })));
    };
    awareness.on("change", people); people();
    try {
      const initial = parsePlaygroundLink(new URL(location.href));
      if (initial) {
        setLink(initial); setCreated(restoreOwnerCapabilities(initial)); setExpiresAt(initial.expiresAt); setConnection("Decrypting the room…");
        const connection = new PlaygroundSession(doc, initial, setConnection, () => setExpired(true), awareness);
        session.current = connection; setLiveSession(connection); void connection.start();
      } else {
        const restored = seed ? null : unmountedDraft;
        unmountedDraft = null;
        updateYDocument(doc, seed ?? restored?.document ?? newPlaygroundDocument(), "initial");
        if (seedNotice) setNotice(seedNotice);
        else if (restored) { unsaved.current = true; setNotice("Your unsaved draft from this visit is back."); }
      }
    } catch (error) { setNotice(error instanceof Error ? error.message : String(error)); }
    return () => {
      session.current?.stop(); doc.off("afterTransaction", update); awareness.off("change", people);
      if (unsaved.current && !guard.current.link) { try { unmountedDraft = { document: documentFromY(doc), draftId }; } catch { /* Nothing valid to keep. */ } }
      disposal.current = setTimeout(() => { awareness.destroy(); doc.destroy(); }, 0);
    };
  }, [doc, awareness]); // eslint-disable-line react-hooks/exhaustive-deps

  guard.current = { link: !!link, expired };
  const hasUnsavedWork = useCallback(() => guard.current.link ? guard.current.expired || (session.current?.pending.length ?? 0) > 0 : unsaved.current, []);
  // Reloading or closing asks the browser. Links inside the site ask in this page.
  useEffect(() => {
    const beforeUnload = (event: BeforeUnloadEvent) => { if (hasUnsavedWork()) event.preventDefault(); };
    const click = (event: MouseEvent) => {
      if (event.defaultPrevented || event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey || !hasUnsavedWork()) return;
      const anchor = (event.target as Element | null)?.closest?.("a[href]") as HTMLAnchorElement | null;
      if (!anchor || anchor.target === "_blank" || anchor.hasAttribute("download") || anchor.origin !== location.origin || anchor.pathname === location.pathname) return;
      event.preventDefault(); event.stopPropagation();
      setLeaveTo(anchor.href); setModal("leave");
    };
    window.addEventListener("beforeunload", beforeUnload); document.addEventListener("click", click, true);
    return () => { window.removeEventListener("beforeunload", beforeUnload); document.removeEventListener("click", click, true); };
  }, [hasUnsavedWork]);

  useEffect(() => {
    if (!keepDrafts || link || !source) return;
    const timer = setTimeout(() => {
      saveDraft(draftId, source).then(() => { unsaved.current = false; setDraftStatus("Kept in this browser"); }, error => setDraftStatus("Draft not kept: " + (error instanceof Error ? error.message : String(error))));
    }, 800);
    return () => clearTimeout(timer);
  }, [keepDrafts, link, source, draftId]);
  useEffect(() => { if (modal === "drafts") listDrafts().then(setDrafts, () => setDraftStatus("Browser storage is unavailable.")); }, [modal]);
  useEffect(() => { if (!source) return; let current = true; void runtimeSourceRevision(source).then(value => { if (current) setRevision(value); }, () => {}); return () => { current = false; }; }, [source]);
  useEffect(() => { const timer = setInterval(() => setNow(Date.now()), 1000); return () => clearInterval(timer); }, []);
  useEffect(() => {
    if (link && expiresAt !== null && now >= expiresAt && !expired) { setExpired(true); session.current?.stop(); stopPython(); }
  }, [link, now, expiresAt, expired, stopPython]);
  useEffect(() => { if (expired && link) forgetOwnerCapabilities(link.id); }, [expired, link]);
  useEffect(() => {
    if (modal && !dialog.current?.open) dialog.current?.showModal();
    if (!modal && dialog.current?.open) dialog.current.close();
    // autoFocus runs before the dialog opens, and opening focuses the close button.
    if (modal === "file") dialog.current?.querySelector<HTMLElement>("form input, form select")?.focus();
  }, [modal]);
  // A host that left the room cannot stay selected.
  useEffect(() => { if (target !== "here" && control.status && !control.status.clients.some(client => client.fingerprint === target) && !remote) setTarget("here"); }, [control.status, target, remote]);

  const rename = (value: string) => {
    const next = value.trim().slice(0, 30);
    setDisplayName(next);
    try { if (next) localStorage.setItem(NAME_KEY, next); else localStorage.removeItem(NAME_KEY); } catch {}
    const user = awareness.getLocalState()?.user ?? {};
    if (next && !/[\u0000-\u001f\u007f]/.test(next)) awareness.setLocalStateField("user", { ...user, name: next });
  };

  /** Starts a separate local project from the text in this one. The room itself is left alone. */
  const copyToLocal = useCallback((notice = "This is your own local copy. The room is unchanged, and edits here stay in this browser until you share them.") => {
    try { const value = documentFromY(doc); session.current?.stop(); stopPython(); onOpenLocal(value, { notice, unsaved: true }); }
    catch (error) { setNotice(error instanceof Error ? error.message : String(error)); }
  }, [doc, stopPython, onOpenLocal]);

  const share = useCallback(async (): Promise<PlaygroundLink> => {
    if (link) return link;
    if (expired) throw new Error("This room has closed. Download your code and start a new room.");
    setSharing(true); setNotice("");
    try {
      const result = await createPlayground(doc, lifetime);
      setCreated(result); setLink(result); setExpiresAt(result.expiresAt); rememberOwnerCapabilities(result);
      unsaved.current = false;
      const connection = new PlaygroundSession(doc, result, setConnection, () => setExpired(true), awareness);
      session.current = connection; setLiveSession(connection); void connection.start();
      history.replaceState(null, "", playgroundLink(result));
      return result;
    } finally { setSharing(false); }
  }, [doc, link, lifetime, expired, awareness]);

  const openInApp = async () => {
    try {
      const shared = await share();
      location.href = appLink(shared);
      setTimeout(() => { if (document.visibilityState === "visible") setNotice("If Pythilo did not open, install it on this iPhone or iPad, or download the source ZIP and open it from Files."); }, 1800);
    } catch (error) { setNotice(error instanceof Error ? error.message : String(error)); }
  };
  const save = () => {
    if (!source) return;
    try {
      download(validatePlaygroundDocument(source).name.replace(/[^a-z0-9_-]/gi, "-") + ".zip", exportArchive(source), "application/zip");
      setNotice("Downloaded the source as a ZIP. Pythilo on iPhone and iPad opens it from Files.");
      unsaved.current = false;
    } catch (error) { setNotice(error instanceof Error ? error.message : String(error)); }
  };
  const treeAction = (action: TreeAction, node: TreeNode) => {
    if (action === "copy-path") { void navigator.clipboard.writeText(node.path).then(() => setNotice(`Copied ${node.path}`), () => setNotice(node.path)); return; }
    if (action === "set-entry") { if (!readOnly && node.path.endsWith(".py")) doc.getMap("meta").set("entryFile", node.path); return; }
    if (link && (action === "rename" || action === "move" || action === "delete")) { setNotice("Rename, move and delete need a local copy in a shared room, so nobody's unsent edit is lost."); return; }
    setFileRequest({ action, folder: node.kind === "folder", path: node.path }); setModal("file");
  };
  const checkFile = useCallback((operation: FileOperation) => planFileOperation(documentFromY(doc), operation), [doc]);
  const applyFilePlan = (operation: FileOperation) => {
    try {
      // Computed again from the live document: another participant may have typed since the dialog opened.
      const plan = planFileOperation(documentFromY(doc), operation);
      if (link && isDestructiveInSharedRoom(operation)) throw new Error("This needs a local copy in a shared room.");
      setSelected(previous => plan.added[0] ?? plan.moved[previous] ?? (plan.removed.includes(previous) ? plan.document.entryFile : previous));
      updateYDocument(doc, plan.document, "structure");
      for (const path of [...plan.removed, ...Object.keys(plan.moved)]) { editorStates.current.get(path)?.undo.destroy(); editorStates.current.delete(path); }
      if (plan.added.length) setFilePane(false);
      if (plan.movesPythonSource) setNotice("Moved. Imports that name the old path are not rewritten, so run Check.");
    } catch (error) { setNotice(error instanceof Error ? error.message : String(error)); }
    setModal(null); setFileRequest(null);
  };
  const setDraftKeeping = (value: boolean) => {
    setKeepDrafts(value);
    try { localStorage.setItem(KEEP_DRAFTS_KEY, String(value)); } catch { setDraftStatus("Browser storage is unavailable."); }
    if (!value) setDraftStatus("");
  };

  const waitFor = async (test: (client: RuntimeClient & { grant: unknown }) => boolean, timeoutMs: number, failure: string, target: string) => {
    const deadline = Date.now() + timeoutMs;
    while (Date.now() < deadline) {
      const client = controlStatus.current?.clients.find(item => item.fingerprint === target);
      if (!client) throw new Error("That device left the room.");
      if (test(client)) return client;
      await new Promise(resolve => setTimeout(resolve, 300));
    }
    throw new Error(failure);
  };
  const runRemote = async (operation: RuntimeAction) => {
    const client = control.status?.clients.find(item => item.fingerprint === target);
    if (!client) { setNotice("That device left the room."); setTarget("here"); return; }
    const name = hostLabel(client), owner = ownerOf(client);
    setRemote({ target, name, operation, stage: `Asking ${name}` }); setRemoteResult(null);
    try {
      if (!client.operations.includes(operation)) throw new Error(`${name} does not offer ${verbs[operation]}.`);
      const ask = async (used?: string) => {
        await control.ask(target, [...runtimeActions]);
        setRemote(previous => previous && { ...previous, stage: `Waiting for ${owner} to allow it on ${name}` });
        await waitFor(item => { const grant = item.grant as { id: string; operations: string[] } | null; return !!grant && grant.id !== used && grant.operations.includes(operation); }, 120_000, `Nobody allowed it on ${name} within two minutes.`, target);
      };
      if (!client.grant?.operations.includes(operation)) await ask();
      setRemote(previous => previous && { ...previous, stage: `Waiting for Python on ${name}` });
      await waitFor(item => item.ready && !item.busy, 90_000, `Python on ${name} did not become ready.`, target);
      const follow = () => control.follow(target, operation, (stage, job) => setRemote(previous => previous && { ...previous, stage, job }));
      // A grant for one job is spent after it: ask the owner again.
      const result = await follow().catch(async (error: Error) => {
        const used = controlStatus.current?.clients.find(item => item.fingerprint === target)?.grant?.id;
        if (!/one job/.test(error.message) || !used) throw error;
        await ask(used); return follow();
      });
      setRemoteResult({ operation, status: result.stopped ? "stopped" : result.succeeded ? "succeeded" : "failed", exitCode: result.exitCode, stdout: result.stdout, stderr: result.stderr, diagnostics: diagnosticsOf(result.diagnostics),
        ranOn: { ...result.ranOn, here: false }, runtime: result.runtime, revision: result.revision, startedAt: result.startedAt, durationMs: result.durationMs, truncated: result.truncated,
        ...(result.truncated ? { note: `Output is longer than this page reads. The complete output stays on ${name}.` } : {}) });
      setResultSource(source ? documentRevision(source) : null);
      setRemote(null);
    } catch (error) { setRemote(previous => previous && { ...previous, stage: "", error: error instanceof Error ? error.message : String(error) }); }
  };
  const runHere = async (operation: RuntimeAction) => {
    try {
      const value = validatePlaygroundDocument(documentFromY(doc));
      setRemoteResult(null); setRemote(null); setResultSource(documentRevision(value));
      await python.run(operation, value.files, value.entryFile, await runtimeSourceRevision(value));
    } catch (error) { if (!/^Stopped/.test(error instanceof Error ? error.message : "")) setNotice(error instanceof Error ? error.message : String(error)); }
  };
  const start = (operation: RuntimeAction) => { if (!source || expired) return; if (target === "here") void runHere(operation); else void runRemote(operation); };
  const stop = () => {
    if (remote) { if (remote.job) { void control.stop(remote.target, revision, remote.job); setRemote({ ...remote, stage: "Stopping…" }); } else setRemote(null); return; }
    python.stop();
  };

  const current = view?.files.find(file => file.key === selected), selectedPath = current?.path ?? selected;
  const text = view ? fileText(doc, view, selected) : null;
  let fileState: FileEditorState | null = null;
  if (text) {
    fileState = editorStates.current.get(selected) ?? null;
    if (fileState?.text !== text) { fileState?.undo.destroy(); fileState = createFileEditorState(text); editorStates.current.set(selected, fileState); }
  }
  const readOnly = expired || link?.mode === "view";
  const busy = python.busy || !!remote && !remote.error;
  const shown = remoteResult ?? python.result;
  const transcript: TranscriptPart[] = remoteResult ? [...(remoteResult.stdout ? [{ stream: "stdout" as const, text: remoteResult.stdout }] : []), ...(remoteResult.stderr ? [{ stream: "stderr" as const, text: remoteResult.stderr }] : [])] : python.transcript;
  const stale = !!shown && !!source && !!resultSource && documentRevision(source) !== resultSource;
  const commitName = () => {
    if (nameDraft === null) return;
    setNameDraft(null);
    if (!source || readOnly) return;
    try { const value = committedProjectName(nameDraft, source.name); if (value) doc.getMap("meta").set("name", value); }
    catch (error) { setNotice(error instanceof Error ? error.message : String(error)); }
  };
  const minutesLeft = expiresAt !== null ? Math.max(0, Math.ceil((expiresAt - now) / 60_000)) : null;
  const closes = minutesLeft === null ? "" : expired ? "closed" : minutesLeft >= 60 ? `closes in ${Math.floor(minutesLeft / 60)} h ${minutesLeft % 60} min` : `closes in ${minutesLeft} min`;
  const clients = control.status?.clients ?? [];
  const shared = host.status?.sharedOutput;
  const present = new Map(participants.filter(person => !person.local && person.file).map(person => [person.file!, { name: person.name, color: person.color }]));
  const lastEditText = lastEdit && now - lastEdit.at < 3_600_000 ? `${lastEdit.name} edited ${lastEdit.path} · ${now - lastEdit.at < 60_000 ? "just now" : `${Math.floor((now - lastEdit.at) / 60_000)} min ago`}` : "";

  return <div className="pg">
    <header className="pg-header">
      <a href="/" aria-label="Pythilo home" className="brand"><BrandMark /></a>
      <div className="pg-title">
        <input className="pg-name" value={nameDraft ?? source?.name ?? ""} maxLength={80} disabled={!source || readOnly} aria-label="Project name" onChange={event => setNameDraft(event.target.value)} onBlur={commitName} onKeyDown={event => { if (event.key === "Enter") event.currentTarget.blur(); }} size={Math.max(8, (nameDraft ?? source?.name ?? "").length)} />
        <div className="pg-subline">{link ? <>Room{link.mode === "view" ? " · view only" : ""}{revision ? <> · revision {revision.slice(0, 6)}</> : null} · <span className={expired ? "pg-closed" : "pg-closes"}>{closes}</span></> : <>Local draft · {keepDrafts ? draftStatus || "kept in this browser" : "only in this tab"}</>}</div>
      </div>
      {link ? <ul aria-label="In the room" className="pg-people">{participants.map(person => <li key={person.id} title={`${person.name}${person.local ? ", this browser" : ""}`} style={{ color: person.color, background: `color-mix(in srgb, ${person.color} 18%, #0B1016)` }}>{person.name.trim().charAt(0).toUpperCase() || "?"}</li>)}</ul> : null}
      <span className="pg-spacer" />
      {!link ? <button type="button" className="pill-button" onClick={() => setModal("drafts")}>Drafts</button> : null}
      <button type="button" className="pill-button" onClick={() => setModal("connect")} disabled={!source || expired}>Connect AI</button>
      <button type="button" className="pill-button pg-wide" onClick={save} disabled={!source}>Export .zip</button>
      <button type="button" className="pill-button primary" onClick={() => setModal("share")} disabled={!source}>Share</button>
    </header>
    {link ? <div className="pg-status" role="status">{connection}</div> : null}
    {notice || python.error ? <div className="pg-notice" role="alert"><span>{notice || python.error}</span><button type="button" className="icon-button" aria-label="Dismiss notice" onClick={() => { setNotice(""); python.clearError(); }}>×</button></div> : null}
    <div className="pg-work">
      <aside className={`pg-tree${filePane ? " pg-tree-open" : ""}`} aria-label="Files">
        <FileTree paths={view?.files.map(file => file.path) ?? []} selected={selectedPath} entryFile={source?.entryFile} readOnly={readOnly} shared={!!link} present={present} storageKey={`pythilo.playground.tree.${link?.id ?? draftId}`} onOpen={path => { setSelected(path); setFilePane(false); }} onAction={treeAction} />
        <button type="button" className="pg-new-file" disabled={readOnly || !source} onClick={() => { setFileRequest({ action: "new-file", folder: false, path: "" }); setModal("file"); }}>+ New file</button>
        <p className="pg-budget">{source ? `${Object.keys(source.files).length}/16 files · ${(sourceBytes(source.files) / 1024).toFixed(1)}/128 KiB` : ""}</p>
      </aside>
      <section className="pg-editor" aria-label={selectedPath}>
        <div className="pg-file-bar"><button type="button" className="pg-files-toggle" onClick={() => setFilePane(!filePane)} aria-expanded={filePane}>Files</button><span className="pg-path">{selectedPath}</span>{lastEditText ? <span className="pg-last-edit">{lastEditText}</span> : null}</div>
        <div className="pg-editor-area">{fileState ? <PlaygroundCodeEditor filePath={selectedPath} awareness={awareness} maximumBytes={Math.min(65536, 131072 - sourceBytes(source?.files ?? {}) + new TextEncoder().encode(current?.text ?? "").length)} fileState={fileState} readOnly={readOnly} onLimit={() => setNotice("Source limit: 64 KiB per file and 128 KiB for the whole project.")} /> : <div className="pg-empty">{link ? "Waiting for the encrypted source…" : "Preparing the editor…"}</div>}</div>
      </section>
      <section className="pg-run" aria-label="Run">
        <div className="pg-run-top">
          <div className="label">Run on</div>
          <div role="radiogroup" aria-label="Run on" className="run-targets">
            <button type="button" role="radio" aria-checked={target === "here"} onClick={() => setTarget("here")} disabled={busy}><span className="radio" aria-hidden="true" /><span><strong>This browser</strong><small>Pyodide {PYODIDE_VERSION} · no sockets or servers</small></span></button>
            {clients.map(client => <button key={client.fingerprint} type="button" role="radio" aria-checked={target === client.fingerprint} onClick={() => setTarget(client.fingerprint)} disabled={busy}>
              <span className="radio" aria-hidden="true" />
              <span><strong>{hostLabel(client)}</strong><small>{shortRuntime(client.runtime)} · {client.grant ? `allowed until ${new Date(client.grant.expires).toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" })}` : `${ownerOf(client)} decides who may run code there`}{client.busy ? " · busy" : ""}</small></span>
            </button>)}
          </div>
          {!link ? <p className="field-note">Share this project to run it on an iPhone or iPad with the Pythilo app.</p> : link.mode === "view" ? <p className="field-note">A view-only link can run here, but not ask other devices.</p> : null}
          {busy ? <button type="button" className="run-button stop" onClick={stop}><span aria-hidden="true">■</span>Stop</button>
            : <button type="button" className="run-button" onClick={() => start("run")} disabled={!source || expired}><svg width="14" height="16" viewBox="0 0 14 16" fill="currentColor" aria-hidden="true"><path d="M1 1.8c0-.8.9-1.3 1.6-.9l10 6.2c.6.4.6 1.4 0 1.8l-10 6.2c-.7.4-1.6-.1-1.6-.9z" /></svg>Run {source?.entryFile ?? "main.py"}</button>}
          <div className="run-secondary"><button type="button" className="pill-button" onClick={() => start("check")} disabled={!source || expired || busy}>Check</button><button type="button" className="pill-button" onClick={() => start("test")} disabled={!source || expired || busy}>Test</button></div>
        </div>
        {liveSession ? <RuntimePermissions runtime={host} compact /> : null}
        <div className="pg-output">
          <div className="label">Output</div>
          {remote ? <p className={remote.error ? "output-error" : "output-stage"} role="status">{remote.error ?? `${verbs[remote.operation]} on ${remote.name}: ${remote.stage}`}</p> : python.busy || python.activity === "loading" ? <p className="output-stage" role="status">{python.stage}</p> : null}
          {shown?.note ? <p className="output-note">{shown.note}</p> : null}
          <Transcript parts={transcript} empty={busy ? undefined : python.result || remoteResult ? "(no output)" : `Run executes ${source?.entryFile ?? "main.py"} with Python ${BROWSER_RUNTIME.split("Python ")[1]} in this browser. Check compiles every file; Test runs pytest.`} />
          {python.waitingForInput && !remoteResult ? <InputLine onSubmit={python.provideInput} /> : null}
          {shown ? <Diagnostics items={shown.diagnostics} onOpen={path => { if (view?.files.some(file => file.path === path)) setSelected(path); }} /> : null}
          {shown && !busy ? <RunFooter result={shown} /> : null}
          {stale && !busy ? <p className="output-note">The source changed after this result.</p> : null}
          {shared && !busy && !(shown && shared.startedAt === shown.startedAt && shared.name === shown.ranOn.name) ? <article className="shared-output"><div className="label">Latest run by {shared.kind === "browser" ? `${shared.name}'s browser` : shared.name}</div><pre className="transcript">{shared.stdout ? <span className="stdout">{shared.stdout}</span> : null}{shared.stderr ? <span className="stderr">{shared.stderr}</span> : null}{!shared.stdout && !shared.stderr ? "(no output)" : null}</pre>
            <RunFooter result={{ operation: (runtimeActions as readonly string[]).includes(shared.operation) ? shared.operation as RuntimeAction : "run", ranOn: { name: shared.name, kind: shared.kind, here: false }, runtime: shared.runtime, revision: shared.revision, startedAt: shared.startedAt, durationMs: shared.durationMs, status: shared.succeeded ? "succeeded" : "failed", exitCode: shared.exitCode }} />
            {shared.truncated ? <p className="field-note">Preview shortened; the complete output stays on that device.</p> : null}</article> : null}
        </div>
      </section>
    </div>
    <dialog ref={dialog} className="dialog" aria-labelledby="dialog-title" onCancel={() => { setModal(null); setFileRequest(null); }}>
      {modal === "connect" ? <ConnectAIDialog link={link} created={created} projectName={source?.name ?? ""} sharing={sharing} share={share} lifetime={lifetime} setLifetime={setLifetime} onClose={() => setModal(null)} /> : modal ? <>
        <div className="dialog-heading"><h2 id="dialog-title">{modal === "share" ? link ? "Share this room" : "Share this project" : modal === "drafts" ? "Drafts in this browser" : modal === "file" && fileRequest ? fileDialogTitle(fileRequest) : "Leave this page?"}</h2><button type="button" className="icon-button" aria-label="Close" onClick={() => { setModal(null); setFileRequest(null); }}>×</button></div>
        {modal === "share" ? <div className="dialog-body">
          <p>Anyone with the link joins this room: up to four people, AI clients or devices. The key is in the link, so the relay only ever holds ciphertext.</p>
          {!link ? <><fieldset className="field"><legend>The room closes after</legend><div className="chip-row">{lifetimes.map(([seconds, label]) => <button key={seconds} type="button" role="radio" aria-checked={lifetime === seconds} onClick={() => setLifetime(seconds)}>{label}</button>)}</div></fieldset>
            <button type="button" className="pill-button primary" disabled={sharing || expired} onClick={() => void share().catch(error => setNotice(error instanceof Error ? error.message : String(error)))}>{sharing ? "Encrypting source…" : "Create room link"}</button></> : <>
            <label className="field">{link.mode === "view" ? "View-only link" : "Room link · anyone with it can edit"}<textarea readOnly value={playgroundLink(link)} onFocus={event => event.target.select()} /></label>
            <div className="dialog-actions start"><button type="button" className="pill-button primary" onClick={() => void navigator.clipboard.writeText(playgroundLink(link)).then(() => setNotice("Room link copied."), () => setNotice("Select and copy the link above."))}>Copy link</button><button type="button" className="pill-button" onClick={() => void openInApp()}>Open in the Pythilo app</button></div>
            {created ? <label className="field">View-only link<textarea readOnly value={playgroundLink({ ...created, access: created.view, mode: "view" })} onFocus={event => event.target.select()} /></label> : null}
            <p className="field-note">{closes ? `This room ${closes}` : ""}{expiresAt ? ` · ${new Date(expiresAt).toLocaleString()}` : ""}. Opening a link does not renew it.</p>
          </>}
          <label className="field">Your name in this room<input value={displayName} maxLength={30} placeholder={name} onChange={event => rename(event.target.value)} /></label>
          {liveSession ? <RuntimePermissions runtime={host} /> : null}
          <div className="dialog-actions start">
            <button type="button" className="pill-button" onClick={save}>Download source ZIP</button>
            {link ? <button type="button" className="pill-button" onClick={() => { setModal(null); copyToLocal(); }}>Copy to a local draft</button> : null}
            {created && !expired ? <button type="button" className="pill-button danger" onClick={async () => { if (!window.confirm("End this room for everyone? Downloaded copies stay.")) return; try { const response = await fetch(`/api/playground/rooms/${created.id}/`, { method: "DELETE", headers: { Authorization: "Bearer " + created.owner }, credentials: "omit" }); if (!response.ok) throw new Error("Could not end this room."); session.current?.stop(); setExpired(true); } catch (error) { setNotice(error instanceof Error ? error.message : String(error)); } }}>End room for everyone</button> : null}
          </div>
        </div> : null}
        {modal === "drafts" ? <div className="dialog-body">
          <label className="check-row"><input type="checkbox" checked={keepDrafts} onChange={event => setDraftKeeping(event.target.checked)} />Keep drafts in this browser</label>
          <p className="field-note">Drafts are kept in this browser&apos;s storage only, as source with no room links or permissions. Without this, a draft lasts until you leave the page, and Export .zip is your copy.</p>
          {draftStatus ? <p className="field-note" role="status">{draftStatus}</p> : null}
          {drafts.length ? <ul className="draft-list">{drafts.map(draft => <li key={draft.id}><span>{draft.name}<small>{new Date(draft.updatedAt).toLocaleString()}</small></span><span><button type="button" className="pill-button" disabled={draft.id === draftId} onClick={() => { setModal(null); onOpenLocal(draft.document, { notice: `Opened your draft ${draft.name}.`, draftId: draft.id, unsaved: false }); }}>Open</button><button type="button" className="pill-button danger" onClick={() => void deleteDraft(draft.id).then(() => listDrafts()).then(setDrafts, () => setDraftStatus("Browser storage is unavailable."))}>Delete</button></span></li>)}</ul> : <p>No drafts kept yet.</p>}
          <div className="dialog-actions start"><button type="button" className="pill-button primary" onClick={() => { setModal(null); onOpenLocal(newPlaygroundDocument(), { notice: "A fresh main.py.", unsaved: false }); }}>Start from a fresh main.py</button></div>
        </div> : null}
        {modal === "file" && fileRequest && source ? <FileDialog key={`${fileRequest.action}:${fileRequest.path}`} request={fileRequest} source={source} check={checkFile} onSubmit={applyFilePlan} onCancel={() => { setModal(null); setFileRequest(null); }} /> : null}
        {modal === "leave" ? <div className="dialog-body"><p>{link ? "Some of this room's source has not reached the relay, or the room has closed. Leaving now can lose it." : "This draft is only in this page. Download it to keep a copy."}</p><div className="dialog-actions"><button type="button" className="pill-button" onClick={() => setModal(null)}>Stay</button><button type="button" className="pill-button" onClick={() => { const target = leaveTo; unsaved.current = false; guard.current = { link: false, expired: false }; if (target) location.assign(target); }}>Leave without saving</button><button type="button" className="pill-button primary" onClick={() => { const target = leaveTo; save(); guard.current = { link: false, expired: false }; if (target) location.assign(target); }}>Download and leave</button></div></div> : null}
      </> : null}
    </dialog>
  </div>;
}
