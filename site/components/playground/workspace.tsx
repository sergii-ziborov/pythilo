"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import * as Y from "yjs";
import { strToU8 } from "fflate";
import { createPresence, remoteSelections } from "@/lib/playground-presence";
import { documentFromY, updateYDocument } from "@/lib/playground-collab";
import { documentRevision, exportArchive, fileText, readView, type ProjectView } from "@/lib/playground-project";
import { committedProjectName, newPlaygroundDocument, PLAYGROUND_LIMITS, sourceBytes, validatePlaygroundDocument, type PlaygroundDocument } from "@/lib/playground-document";
import { newEncryptionSecret } from "@/lib/playground-crypto";
import { appLink, createPlayground, parsePlaygroundLink, playgroundLink, PlaygroundSession, type PlaygroundLink, type CreatedPlayground } from "@/lib/playground-session";
import { forgetOwnerCapabilities, rememberOwnerCapabilities, restoreOwnerCapabilities } from "@/lib/playground-client";
import { ancestors, isDestructiveInSharedRoom, planFileOperation, type FileOperation, type FilePlan, type TreeNode } from "@/lib/playground-file-ops";
import { deleteDraft, KEEP_DRAFTS_KEY, listDrafts, saveDraft, type StoredDraft } from "@/lib/playground-drafts";
import { parseShareLink, sharePayloadFromHash } from "@/lib/playground-share-link";
import { readUploads } from "@/lib/playground-upload";
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
import { FileBadge, FileTree, type TreeApi } from "./file-tree";
import { ConnectAIDialog } from "./connect-ai-dialog";
import { ShareDialog } from "./share-dialog";
import { Icon } from "./icons";
import { Menu, modKey, type MenuAnchor, type MenuItem } from "./menu";

type Modal = "share" | "connect" | "drafts" | "leave" | "open" | "shortcuts" | null;
type Pane = "files" | "code" | "output";
type Toast = { id: number; text: string; action?: { label: string; run: () => void }; tone?: "error" };
type RemoteRun = { target: string; name: string; operation: RuntimeAction; stage: string; job?: string; revision?: string; error?: string };
const NAME_KEY = "pythilo.playground.name.v1";
const verbs: Record<RuntimeAction, string> = { check: "Check", run: "Run", test: "Test" };
const LOCKED = "Rename, move and delete are off in a shared room, so nobody's unsent edit is lost. Copy the room to a local draft to reorganise it.";

function download(name: string, bytes: Uint8Array, type: string) {
  const blob = new Blob([new Uint8Array(bytes)], { type });
  const url = URL.createObjectURL(blob), anchor = document.createElement("a");
  anchor.href = url; anchor.download = name; anchor.click(); setTimeout(() => URL.revokeObjectURL(url), 60_000);
}
function storedName(): string {
  try { const name = localStorage.getItem(NAME_KEY)?.trim(); return name && name.length <= 30 && !/[\u0000-\u001f\u007f]/.test(name) ? name : ""; } catch { return ""; }
}
const isTyping = (target: EventTarget | null) => target instanceof HTMLElement && (target.isContentEditable || /^(INPUT|TEXTAREA|SELECT)$/.test(target.tagName));
const message = (error: unknown) => error instanceof Error ? error.message : String(error);
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
type OpenOptions = { notice: string; draftId?: string; unsaved: boolean; url?: string };
type LocalCopy = { key: number; seed?: PlaygroundDocument; notice?: string; draftId?: string; unsaved?: boolean };

/** Remounts with a fresh document, so a copy cannot keep any of a room's session state. */
export default function PlaygroundWorkspace() {
  const [instance, setInstance] = useState<LocalCopy>({ key: 0 });
  const openLocal = useCallback((seed: PlaygroundDocument, options: OpenOptions) => {
    // Removes the room's secret fragment, so a reload cannot rejoin the room.
    history.replaceState(null, "", options.url ?? "/playground/");
    setInstance(previous => ({ key: previous.key + 1, seed, ...options }));
  }, []);
  return <Workspace key={instance.key} seed={instance.seed} seedNotice={instance.notice} seedDraftId={instance.draftId} seedUnsaved={instance.unsaved} onOpenLocal={openLocal} />;
}

function Workspace({ seed, seedNotice, seedDraftId, seedUnsaved, onOpenLocal }: { seed?: PlaygroundDocument; seedNotice?: string; seedDraftId?: string; seedUnsaved?: boolean; onOpenLocal: (seed: PlaygroundDocument, options: OpenOptions) => void }) {
  const [displayName, setDisplayName] = useState(storedName);
  const [doc] = useState(() => new Y.Doc()), [awareness] = useState(() => createPresence(doc, displayName || undefined));
  const name = displayName || (awareness.getLocalState()?.user?.name as string) || "Guest";
  const [source, setSource] = useState<PlaygroundDocument | null>(null), [view, setView] = useState<ProjectView | null>(null);
  const [selected, setSelected] = useState("main.py"), [modal, setModal] = useState<Modal>(null), dialog = useRef<HTMLDialogElement>(null);
  const [link, setLink] = useState<PlaygroundLink | null>(null), [created, setCreated] = useState<CreatedPlayground | null>(null);
  const session = useRef<PlaygroundSession | null>(null), [connection, setConnection] = useState("Connecting…");
  const [liveSession, setLiveSession] = useState<PlaygroundSession | null>(null);
  const [expiresAt, setExpiresAt] = useState<number | null>(null), [now, setNow] = useState(() => Date.now());
  const [lifetime, setLifetime] = useState(3600), [expired, setExpired] = useState(false), [sharing, setSharing] = useState(false);
  const [toasts, setToasts] = useState<Toast[]>([]), [pane, setPane] = useState<Pane>("code"), [nameDraft, setNameDraft] = useState<string | null>(null);
  const [leaveTo, setLeaveTo] = useState<string | null>(null), [emptyFolders, setEmptyFolders] = useState<string[]>([]);
  const [keepDrafts, setKeepDrafts] = useState(false), [drafts, setDrafts] = useState<StoredDraft[]>([]), [draftStatus, setDraftStatus] = useState("");
  const [revision, setRevision] = useState(""), [lastEdit, setLastEdit] = useState<{ name: string; path: string; at: number } | null>(null);
  const [participants, setParticipants] = useState<{ id: number; name: string; color: string; local: boolean; file?: string }[]>([]);
  const [resultSource, setResultSource] = useState<string | null>(null), [cleared, setCleared] = useState<unknown>(null), [unread, setUnread] = useState(false);
  const [menu, setMenu] = useState<MenuAnchor | null>(null), [openText, setOpenText] = useState(""), [openProblem, setOpenProblem] = useState("");
  const editorStates = useRef(new Map<string, FileEditorState>()), [draftId] = useState(() => seedDraftId ?? newEncryptionSecret());
  const unsaved = useRef(!!seedUnsaved), guard = useRef({ link: false, expired: false });
  const disposal = useRef<ReturnType<typeof setTimeout> | undefined>(undefined);
  const tree = useRef<TreeApi | null>(null), upload = useRef<HTMLInputElement>(null), uploadFolder = useRef(""), focusEditor = useRef(false), toastId = useRef(0);

  const readOnly = expired || link?.mode === "view";
  const python = usePythonRuntime(), stopPython = python.stop;
  const channel = useMemo(() => liveSession ? new RuntimePresenceChannel(awareness) : null, [liveSession, awareness]);
  useEffect(() => () => channel?.close(), [channel]);
  const sourceOf = useCallback(() => readView(doc).document, [doc]);
  const host = useRuntimeHost(liveSession, awareness, channel, sourceOf, python, name);
  const control = useRuntimeController(liveSession, awareness, channel, sourceOf, name);
  const [target, setTarget] = useState("here"), [remote, setRemote] = useState<RemoteRun | null>(null), [remoteResult, setRemoteResult] = useState<RunResult | null>(null);
  const controlStatus = useRef(control.status); controlStatus.current = control.status;

  const dismiss = useCallback((id: number) => setToasts(previous => previous.filter(toast => toast.id !== id)), []);
  const notify = useCallback((text: string, options: { action?: Toast["action"]; tone?: Toast["tone"]; ms?: number } = {}) => {
    if (!text) return;
    const id = ++toastId.current;
    setToasts(previous => [...previous.filter(toast => toast.text !== text).slice(-2), { id, text, action: options.action, tone: options.tone }]);
    setTimeout(() => dismiss(id), options.ms ?? (options.action ? 9000 : options.tone === "error" ? 9000 : 5000));
  }, [dismiss]);
  const fail = useCallback((error: unknown) => notify(message(error), { tone: "error" }), [notify]);

  useEffect(() => {
    if (disposal.current) clearTimeout(disposal.current);
    try { setKeepDrafts(localStorage.getItem(KEEP_DRAFTS_KEY) === "true"); } catch {}
    const update = (transaction: Y.Transaction) => {
      try {
        if (transaction.changed.size > 0 && transaction.origin !== "initial" && !guard.current.link) {
          unsaved.current = true;
          // A share link shows the code as it was shared; once edited, a reload must not bring that back silently.
          if (sharePayloadFromHash(location.hash) !== null) history.replaceState(null, "", "/playground/");
        }
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
    let opened: PlaygroundDocument | null = null, linkProblem = "";
    try { if (!seed) opened = parseShareLink(new URL(location.href)); }
    catch (error) { linkProblem = message(error); history.replaceState(null, "", "/playground/"); }
    try {
      const initial = parsePlaygroundLink(new URL(location.href));
      if (initial) {
        setLink(initial); setCreated(restoreOwnerCapabilities(initial)); setExpiresAt(initial.expiresAt); setConnection("Decrypting the room…");
        const connection = new PlaygroundSession(doc, initial, setConnection, () => setExpired(true), awareness);
        session.current = connection; setLiveSession(connection); void connection.start();
      } else if (opened) {
        unmountedDraft = null;
        updateYDocument(doc, opened, "initial");
        notify(`Opened ${opened.name} from a link. This is your own copy: edits stay in this browser until you share them.`, { ms: 9000 });
      } else {
        const restored = seed ? null : unmountedDraft;
        unmountedDraft = null;
        updateYDocument(doc, seed ?? restored?.document ?? newPlaygroundDocument(), "initial");
        if (linkProblem) notify(linkProblem, { tone: "error" });
        else if (seedNotice) notify(seedNotice);
        else if (restored) { unsaved.current = true; notify("Your unsaved draft from this visit is back."); }
      }
    } catch (error) { fail(error); }
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

  /** Opens a project from a link or a file as a fresh local copy, asking first when this one has unsaved work. */
  const openProject = useCallback((value: PlaygroundDocument, notice: string, url?: string) => {
    if (hasUnsavedWork() && !window.confirm("Open this project? Unsaved changes here are lost unless you download them first.")) return false;
    session.current?.stop(); stopPython(); unsaved.current = false; guard.current = { link: false, expired: false };
    onOpenLocal(value, { notice, unsaved: false, url });
    return true;
  }, [hasUnsavedWork, onOpenLocal, stopPython]);

  // A share link pasted into the address bar of an open playground only changes the fragment.
  useEffect(() => {
    const changed = () => {
      if (sharePayloadFromHash(location.hash) === null) return;
      const url = location.href;
      try { const value = parseShareLink(new URL(url)); if (value && !openProject(value, `Opened ${value.name} from a link. This is your own copy.`, url)) history.replaceState(null, "", "/playground/"); }
      catch (error) { fail(error); history.replaceState(null, "", "/playground/"); }
    };
    window.addEventListener("hashchange", changed);
    return () => window.removeEventListener("hashchange", changed);
  }, [openProject, fail]);

  useEffect(() => {
    if (!keepDrafts || link || !source) return;
    const timer = setTimeout(() => {
      saveDraft(draftId, source).then(() => { unsaved.current = false; setDraftStatus("Kept in this browser"); }, error => setDraftStatus("Draft not kept: " + message(error)));
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
    if (modal === "open") dialog.current?.querySelector<HTMLElement>("form input")?.focus();
  }, [modal]);
  // A host that left the room cannot stay selected.
  useEffect(() => { if (target !== "here" && control.status && !control.status.clients.some(client => client.fingerprint === target) && !remote) setTarget("here"); }, [control.status, target, remote]);
  // An empty folder stops being "empty" once a file lands in it.
  useEffect(() => { if (!source) return; const real = new Set(Object.keys(source.files).flatMap(ancestors)); setEmptyFolders(previous => previous.some(folder => real.has(folder)) ? previous.filter(folder => !real.has(folder)) : previous); }, [source]);
  // New files open with the cursor in them.
  useEffect(() => {
    if (!focusEditor.current) return;
    focusEditor.current = false;
    requestAnimationFrame(() => document.querySelector<HTMLElement>(".pg-code-editor .cm-content")?.focus());
  }, [selected, source]);

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
    catch (error) { fail(error); }
  }, [doc, stopPython, onOpenLocal, fail]);

  const share = useCallback(async (): Promise<PlaygroundLink> => {
    if (link) return link;
    if (expired) throw new Error("This room has closed. Download your code and start a new room.");
    setSharing(true);
    try {
      const result = await createPlayground(doc, lifetime);
      setCreated(result); setLink(result); setExpiresAt(result.expiresAt); rememberOwnerCapabilities(result);
      unsaved.current = false; setConnection("Connecting…");
      const connection = new PlaygroundSession(doc, result, setConnection, () => setExpired(true), awareness);
      session.current = connection; setLiveSession(connection); void connection.start();
      history.replaceState(null, "", playgroundLink(result));
      return result;
    } finally { setSharing(false); }
  }, [doc, link, lifetime, expired, awareness]);

  const openRoomInApp = async () => {
    try {
      const shared = await share();
      location.href = appLink(shared);
      setTimeout(() => { if (document.visibilityState === "visible") notify("If Pythilo did not open, install it on this iPhone or iPad, or download the ZIP and open it from Files."); }, 1800);
    } catch (error) { fail(error); }
  };
  const endRoom = async () => {
    if (!created || !window.confirm("End this room for everyone? Downloaded copies stay.")) return;
    try {
      const response = await fetch(`/api/playground/rooms/${created.id}/`, { method: "DELETE", headers: { Authorization: "Bearer " + created.owner }, credentials: "omit" });
      if (!response.ok) throw new Error("Could not end this room.");
      session.current?.stop(); setExpired(true);
    } catch (error) { fail(error); }
  };
  const save = () => {
    if (!source) return;
    try {
      download(validatePlaygroundDocument(source).name.replace(/[^a-z0-9_-]/gi, "-") + ".zip", exportArchive(source), "application/zip");
      notify("Downloaded a ZIP. Pythilo on iPhone and iPad opens it from Files.");
      unsaved.current = false;
    } catch (error) { fail(error); }
  };
  const saveToDrafts = () => {
    if (link) { notify("A room saves as you type. Download a ZIP for your own copy."); return; }
    if (!source) return;
    saveDraft(draftId, source).then(() => { unsaved.current = false; notify("Saved to Drafts in this browser."); }, fail);
  };
  const newProject = () => openProject(newPlaygroundDocument(), "A fresh main.py.");

  // ---- Files ----
  const checkFile = useCallback((operation: FileOperation) => {
    if (operation.kind === "rename-folder" && emptyFolders.includes(operation.from)) {
      if (Object.keys(documentFromY(doc).files).some(path => path.toLowerCase() === operation.to.toLowerCase() || path.toLowerCase().startsWith(operation.to.toLowerCase() + "/"))) throw new Error("This name is taken.");
      return;
    }
    if (link && isDestructiveInSharedRoom(operation)) throw new Error(LOCKED);
    planFileOperation(documentFromY(doc), operation);
  }, [doc, emptyFolders, link]);

  const applyOperation = useCallback((operation: FileOperation, quiet = false): FilePlan | null => {
    try {
      if (operation.kind === "rename-folder" && emptyFolders.includes(operation.from)) {
        setEmptyFolders(previous => previous.map(folder => folder === operation.from ? operation.to : folder.startsWith(operation.from + "/") ? operation.to + folder.slice(operation.from.length) : folder));
        return null;
      }
      if (readOnly) throw new Error("This project is read-only.");
      if (link && isDestructiveInSharedRoom(operation)) throw new Error(LOCKED);
      // Computed again from the live document: another participant may have typed since.
      const plan = planFileOperation(documentFromY(doc), operation);
      setSelected(previous => plan.added[0] ?? plan.moved[previous] ?? (plan.removed.includes(previous) ? plan.document.entryFile : previous));
      updateYDocument(doc, plan.document, "structure");
      for (const path of [...plan.removed, ...Object.keys(plan.moved)]) { editorStates.current.get(path)?.undo.destroy(); editorStates.current.delete(path); }
      if (operation.kind === "create" || operation.kind === "duplicate") { focusEditor.current = true; setPane("code"); }
      if (!quiet && (operation.kind === "rename" || operation.kind === "rename-folder")) {
        const from = operation.from, to = operation.to.trim().replace(/^\/+|\/+$/g, "");
        const moved = from.split("/").slice(0, -1).join("/") !== to.split("/").slice(0, -1).join("/");
        notify(`${moved ? "Moved" : "Renamed"} ${from} to ${to}.${plan.movesPythonSource ? " Imports that name the old path are not rewritten." : ""}`,
          { action: { label: "Undo", run: () => applyOperation(operation.kind === "rename" ? { kind: "rename", from: to, to: from } : { kind: "rename-folder", from: to, to: from }, true) } });
      }
      return plan;
    } catch (error) { fail(error); return null; }
  }, [doc, emptyFolders, link, readOnly, notify, fail]);

  const deleteNode = (node: TreeNode) => {
    if (node.kind === "folder" && emptyFolders.includes(node.path) && !source?.files[node.path]) {
      const inside = Object.keys(source?.files ?? {}).some(path => path.startsWith(node.path + "/"));
      if (!inside) { setEmptyFolders(previous => previous.filter(folder => folder !== node.path && !folder.startsWith(node.path + "/"))); return; }
    }
    if (!source) return;
    const before = source;
    const plan = applyOperation(node.kind === "folder" ? { kind: "delete-folder", path: node.path } : { kind: "delete-file", path: node.path });
    if (!plan) return;
    const files = Object.fromEntries(plan.removed.map(path => [path, before.files[path]]));
    const entryMoved = plan.document.entryFile !== before.entryFile;
    notify(`Deleted ${node.kind === "folder" ? `${node.path}/ (${plan.removed.length} file${plan.removed.length === 1 ? "" : "s"})` : node.path}.${entryMoved ? ` ${plan.document.entryFile} is now the main file.` : ""}`,
      { action: { label: "Undo", run: () => { if (applyOperation({ kind: "add-files", files, entryFile: entryMoved ? before.entryFile : undefined }, true)) setSelected(plan.removed[0]); } } });
  };

  const uploadFiles = async (list: File[], folder: string) => {
    if (!source || readOnly) return;
    try {
      const uploads = await Promise.all(list.map(async file => ({ name: file.name, bytes: new Uint8Array(await file.arrayBuffer()) })));
      const { files, skipped } = readUploads(uploads, folder);
      const paths = Object.keys(files);
      const skippedText = skipped.length ? ` Skipped ${skipped.length === 1 ? skipped[0] : `${skipped.length} files`}: only text files up to 64 KiB with a supported name are kept.` : "";
      if (!paths.length) { notify(`Nothing to add.${skippedText}`, { tone: "error" }); return; }
      const replaced = paths.filter(path => path in source.files);
      if (replaced.length && !window.confirm(`Replace ${replaced.length === 1 ? replaced[0] : `${replaced.length} files`} with the uploaded version?`)) return;
      const plan = applyOperation({ kind: "add-files", files }, true);
      if (plan) { if (folder) setEmptyFolders(previous => previous.filter(item => item !== folder)); notify(`Added ${paths.length === 1 ? paths[0] : `${paths.length} files`}.${skippedText}`); setSelected(paths.find(path => path.endsWith(".py")) ?? paths[0]); }
    } catch (error) { fail(error); }
  };
  const pickUpload = (folder: string) => { uploadFolder.current = folder; upload.current?.click(); };
  const downloadFile = (path: string) => { const text = source?.files[path]; if (text !== undefined) download(path.split("/").at(-1)!, strToU8(text), "text/plain;charset=utf-8"); };

  const setDraftKeeping = (value: boolean) => {
    setKeepDrafts(value);
    try { localStorage.setItem(KEEP_DRAFTS_KEY, String(value)); } catch { setDraftStatus("Browser storage is unavailable."); }
    if (!value) setDraftStatus("");
  };

  // ---- Running ----
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
    if (!client) { notify("That device left the room."); setTarget("here"); return; }
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
    } catch (error) { setRemote(previous => previous && { ...previous, stage: "", error: message(error) }); }
  };
  const runHere = async (operation: RuntimeAction) => {
    try {
      const value = validatePlaygroundDocument(documentFromY(doc));
      setRemoteResult(null); setRemote(null); setResultSource(documentRevision(value));
      await python.run(operation, value.files, value.entryFile, await runtimeSourceRevision(value));
    } catch (error) { if (!/^Stopped/.test(message(error))) fail(error); }
  };
  const busy = python.busy || !!remote && !remote.error;
  const start = (operation: RuntimeAction) => {
    if (!source || expired || busy) return;
    setCleared(null); setPane("output"); setUnread(false);
    if (target === "here") void runHere(operation); else void runRemote(operation);
  };
  const stop = () => {
    if (remote) { if (remote.job) { void control.stop(remote.target, revision, remote.job); setRemote({ ...remote, stage: "Stopping…" }); } else setRemote(null); return; }
    python.stop();
  };
  const startRef = useRef(start); startRef.current = start;
  const stopRef = useRef(stop); stopRef.current = stop;
  const saveRef = useRef(saveToDrafts); saveRef.current = saveToDrafts;
  const busyRef = useRef(busy); busyRef.current = busy;

  // Shortcuts work everywhere on the page, including inside the editor.
  useEffect(() => {
    const key = (event: KeyboardEvent) => {
      const mod = event.metaKey || event.ctrlKey;
      if (dialog.current?.open) return;
      if (mod && event.key === "Enter") { event.preventDefault(); event.stopPropagation(); if (busyRef.current) return; startRef.current(event.shiftKey ? "test" : "run"); }
      else if (mod && event.key === ".") { if (busyRef.current) { event.preventDefault(); stopRef.current(); } }
      else if (mod && !event.shiftKey && !event.altKey && event.key.toLowerCase() === "s") { event.preventDefault(); saveRef.current(); }
      else if (event.altKey && !mod && event.code === "KeyN") { event.preventDefault(); setPane("files"); tree.current?.create(event.shiftKey ? "folder" : "file"); }
      else if (event.key === "?" && !mod && !isTyping(event.target)) { event.preventDefault(); setModal("shortcuts"); }
    };
    window.addEventListener("keydown", key, true);
    return () => window.removeEventListener("keydown", key, true);
  }, []);

  // ---- Derived view ----
  const current = view?.files.find(file => file.key === selected), selectedPath = current?.path ?? selected;
  const text = view ? fileText(doc, view, selected) : null;
  let fileState: FileEditorState | null = null;
  if (text) {
    fileState = editorStates.current.get(selected) ?? null;
    if (fileState?.text !== text) { fileState?.undo.destroy(); fileState = createFileEditorState(text); editorStates.current.set(selected, fileState); }
  }
  const shown = remoteResult ?? python.result;
  const rawTranscript: TranscriptPart[] = remoteResult ? [...(remoteResult.stdout ? [{ stream: "stdout" as const, text: remoteResult.stdout }] : []), ...(remoteResult.stderr ? [{ stream: "stderr" as const, text: remoteResult.stderr }] : [])] : python.transcript;
  const isCleared = cleared !== null && cleared === (remoteResult ?? python.result ?? python.transcript);
  const transcript = isCleared ? [] : rawTranscript;
  const stale = !!shown && !!source && !!resultSource && documentRevision(source) !== resultSource;
  useEffect(() => { if (pane !== "output" && (python.transcript.length || python.result || remoteResult)) setUnread(true); }, [python.transcript, python.result, remoteResult]); // eslint-disable-line react-hooks/exhaustive-deps
  useEffect(() => { if (pane === "output") setUnread(false); }, [pane]);
  useEffect(() => { if (python.waitingForInput) setPane("output"); }, [python.waitingForInput]);
  const commitName = () => {
    if (nameDraft === null) return;
    setNameDraft(null);
    if (!source || readOnly) return;
    try { const value = committedProjectName(nameDraft, source.name); if (value) doc.getMap("meta").set("name", value); }
    catch (error) { fail(error); }
  };
  const minutesLeft = expiresAt !== null ? Math.max(0, Math.ceil((expiresAt - now) / 60_000)) : null;
  const closes = minutesLeft === null ? "" : expired ? "closed" : minutesLeft >= 60 ? `closes in ${Math.floor(minutesLeft / 60)} h ${minutesLeft % 60} min` : `closes in ${minutesLeft} min`;
  const clients = control.status?.clients ?? [];
  const shared = host.status?.sharedOutput;
  const present = new Map(participants.filter(person => !person.local && person.file).map(person => [person.file!, { name: person.name, color: person.color }]));
  const lastEditText = lastEdit && now - lastEdit.at < 3_600_000 ? `${lastEdit.name} edited ${lastEdit.path} · ${now - lastEdit.at < 60_000 ? "just now" : `${Math.floor((now - lastEdit.at) / 60_000)} min ago`}` : "";
  const entry = source?.entryFile ?? "main.py";
  const fileCount = source ? Object.keys(source.files).length : 0, bytes = source ? sourceBytes(source.files) : 0;
  const mod = modKey();

  const runButton = (className: string) => busy
    ? <button type="button" className={`pg-run-button stop ${className}`} onClick={stop} title={`Stop (${mod}.)`}><Icon name="stop" size={14} />Stop</button>
    : <button type="button" className={`pg-run-button ${className}`} onClick={() => start("run")} disabled={!source || expired} title={`Run ${entry} (${mod}Enter)`}><Icon name="play" size={14} />Run<span className="pg-run-file">{entry.split("/").at(-1)}</span></button>;

  const menuItems: MenuItem[] = [
    { label: "New project", icon: "plus", onSelect: newProject },
    { label: "Open a link…", icon: "open", onSelect: () => { setOpenText(""); setOpenProblem(""); setModal("open"); } },
    { label: "Upload files or ZIP…", icon: "upload", onSelect: () => pickUpload(""), disabled: readOnly },
    { label: "Download ZIP", icon: "download", onSelect: save, disabled: !source },
    { separator: true },
    ...(link ? [{ label: "Copy to a local draft", icon: "copy", onSelect: () => copyToLocal() } as MenuItem] : [
      { label: "Save to Drafts", icon: "drafts", shortcut: `${mod}S`, onSelect: saveToDrafts, disabled: !source } as MenuItem,
      { label: "Drafts…", icon: "files", onSelect: () => setModal("drafts") } as MenuItem,
    ]),
    { label: "Connect an AI…", icon: "sparkle", onSelect: () => setModal("connect"), disabled: !source || expired },
    { separator: true },
    { label: "Keyboard shortcuts", icon: "keyboard", shortcut: "?", onSelect: () => setModal("shortcuts") },
  ];

  const closeModal = () => setModal(null);
  const submitOpen = () => {
    const raw = openText.trim();
    if (!raw) return;
    try {
      const url = new URL(raw, location.origin);
      const project = parseShareLink(url);
      if (project) { if (openProject(project, `Opened ${project.name} from a link. This is your own copy.`)) setModal(null); return; }
      if (parsePlaygroundLink(url)) {
        if (url.origin !== location.origin) throw new Error("This room is on another Pythilo server. Open the link itself in the browser.");
        setModal(null); location.assign(url.href); return;
      }
      throw new Error("Paste a Pythilo playground link: one with #code= or a room link.");
    } catch (error) { setOpenProblem(error instanceof TypeError ? "Paste a complete link, starting with https://" : message(error)); }
  };

  return <div className="pg" data-pane={pane}>
    <header className="pg-header">
      <h1 className="visually-hidden">Python Playground</h1>
      <a href="/" aria-label="Pythilo home" className="pg-brand"><BrandMark size={28} /></a>
      <div className="pg-title">
        <input className="pg-name" value={nameDraft ?? source?.name ?? ""} maxLength={80} disabled={!source || readOnly} aria-label="Project name" title="Rename project" onChange={event => setNameDraft(event.target.value)} onBlur={commitName} onKeyDown={event => { if (event.key === "Enter") event.currentTarget.blur(); if (event.key === "Escape") { setNameDraft(null); event.currentTarget.blur(); } }} size={Math.max(6, Math.min(28, (nameDraft ?? source?.name ?? "").length))} />
        {link ? <button type="button" className={`pg-chip ${expired ? "pg-chip-stop" : "pg-chip-live"}`} onClick={() => setModal("share")} title={connection}>{expired ? "Room closed" : <><span className="pg-live-dot" aria-hidden="true" />Live{link.mode === "view" ? " · view only" : ""} · {closes.replace("closes in ", "")}</>}</button>
          : <span className="pg-chip" title={keepDrafts ? "Kept in this browser's Drafts" : "Only in this tab until you share, save or download it"}>{keepDrafts ? "Draft · saved here" : "Draft"}</span>}
      </div>
      {link && participants.length ? <ul aria-label="In the room" className="pg-people">{participants.map(person => <li key={person.id} title={`${person.name}${person.local ? " (you)" : ""}`} style={{ color: person.color, background: `color-mix(in srgb, ${person.color} 18%, #0B1016)` }}>{person.name.trim().charAt(0).toUpperCase() || "?"}</li>)}</ul> : null}
      <span className="pg-spacer" />
      {runButton("pg-desktop-only")}
      <button type="button" className="pg-share-button" aria-label="Share" onClick={() => setModal("share")} disabled={!source}><Icon name="share" /><span>Share</span></button>
      <button type="button" className="pg-tool pg-tool-lg" aria-label="More options" aria-haspopup="menu" aria-expanded={!!menu} title="More options" onClick={event => setMenu(menu ? null : { element: event.currentTarget, align: "end" })}><Icon name="more" size={18} /></button>
    </header>

    <nav className="pg-tabs" aria-label="Playground views">
      <div role="tablist" aria-label="Show">
        {([["files", "files", "Files"], ["code", "code", selectedPath.split("/").at(-1) ?? "Code"], ["output", "terminal", "Output"]] as const).map(([key, icon, label]) =>
          <button key={key} type="button" role="tab" aria-selected={pane === key} aria-controls={`pg-pane-${key}`} onClick={() => setPane(key)}><Icon name={icon} />{label}{key === "output" && unread ? <span className="pg-unread" aria-label="new output" /> : null}</button>)}
      </div>
      {runButton("")}
    </nav>

    <main className="pg-work">
      <aside className="pg-tree" id="pg-pane-files" aria-label="Files">
        <FileTree paths={view?.files.map(file => file.path) ?? []} emptyFolders={emptyFolders} selected={selectedPath} entryFile={source?.entryFile} readOnly={readOnly || !source} shared={!!link} present={present}
          storageKey={`pythilo.playground.tree.${link?.id ?? draftId}`} api={tree} check={checkFile}
          onOpen={path => { setSelected(path); setPane("code"); }} onApply={operation => { applyOperation(operation); }} onCreateFolder={path => setEmptyFolders(previous => [...previous, path])}
          onDelete={deleteNode} onUpload={(files, folder) => void uploadFiles(files, folder)} onPickUpload={pickUpload} onDownload={downloadFile} onNotice={text => notify(text)} />
        <p className="pg-budget" title={`Up to ${PLAYGROUND_LIMITS.files} files and 128 KiB`}>
          <span>{fileCount} of {PLAYGROUND_LIMITS.files} files</span><span>{(bytes / 1024).toFixed(1)} of 128 KiB</span>
          <span className="pg-meter" aria-hidden="true"><span style={{ width: `${Math.min(100, Math.max(fileCount / PLAYGROUND_LIMITS.files, bytes / PLAYGROUND_LIMITS.sourceBytes) * 100)}%` }} /></span>
        </p>
      </aside>

      <section className="pg-editor" id="pg-pane-code" aria-label={`Editor: ${selectedPath}`}>
        <div className="pg-file-bar">
          <FileBadge path={selectedPath} />
          <span className="pg-path">{selectedPath.split("/").map((part, index, parts) => <span key={index} className={index === parts.length - 1 ? "pg-path-file" : "pg-path-folder"}>{part}{index < parts.length - 1 ? <span className="pg-path-sep">/</span> : null}</span>)}</span>
          {selectedPath === entry ? <span className="pg-chip pg-chip-main" title="Run starts here">Main file</span>
            : selectedPath.endsWith(".py") && !readOnly ? <button type="button" className="pg-text-button" onClick={() => applyOperation({ kind: "add-files", files: {}, entryFile: selectedPath }, true)} title="Make Run start from this file">Use as main file</button> : null}
          {lastEditText ? <span className="pg-last-edit">{lastEditText}</span> : null}
          {readOnly ? <span className="pg-chip">Read-only</span> : null}
        </div>
        <div className="pg-editor-area">{fileState ? <PlaygroundCodeEditor filePath={selectedPath} awareness={awareness} maximumBytes={Math.min(65536, 131072 - sourceBytes(source?.files ?? {}) + new TextEncoder().encode(current?.text ?? "").length)} fileState={fileState} readOnly={readOnly} onLimit={() => notify("Source limit: 64 KiB per file and 128 KiB for the whole project.", { tone: "error" })} /> : <div className="pg-empty">{link ? "Waiting for the encrypted source…" : "Preparing the editor…"}</div>}</div>
      </section>

      <section className="pg-run" id="pg-pane-output" aria-label="Output">
        <div className="pg-run-head">
          <h2 className="label">Output</h2>
          {clients.length ? <label className="pg-target"><span>on</span><select value={target} onChange={event => setTarget(event.target.value)} disabled={busy} aria-label="Run on">
            <option value="here">This browser</option>
            {clients.map(client => <option key={client.fingerprint} value={client.fingerprint}>{hostLabel(client)}{client.busy ? " (busy)" : ""}</option>)}
          </select></label> : null}
          <span className="pg-spacer" />
          <button type="button" className="pg-text-button" onClick={() => start("check")} disabled={!source || expired || busy} title="Compile every file and look for mistakes">Check</button>
          <button type="button" className="pg-text-button" onClick={() => start("test")} disabled={!source || expired || busy} title={`Run the tests with pytest (${mod}⇧Enter)`}>Test</button>
          <button type="button" className="pg-tool" onClick={() => setCleared(remoteResult ?? python.result ?? python.transcript)} disabled={busy || (!transcript.length && !shown) || isCleared} aria-label="Clear output" title="Clear output"><Icon name="clear" /></button>
        </div>
        {target !== "here" ? (() => { const client = clients.find(item => item.fingerprint === target); return client ? <p className="pg-target-note">{shortRuntime(client.runtime)} · {client.grant ? `allowed until ${new Date(client.grant.expires).toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" })}` : `${ownerOf(client)} decides who may run code there`}</p> : null; })() : null}
        {link?.mode === "view" && clients.length ? <p className="pg-target-note">A view-only link can run here, but not ask other devices.</p> : null}
        {liveSession ? <RuntimePermissions runtime={host} compact /> : null}
        <div className="pg-output" aria-live="polite">
          {remote ? <p className={remote.error ? "output-error" : "output-stage"} role="status">{remote.error ?? `${verbs[remote.operation]} on ${remote.name}: ${remote.stage}`}</p> : python.busy || python.activity === "loading" ? <p className="output-stage pg-stage" role="status"><span className="pg-spinner" aria-hidden="true" />{python.stage}</p> : null}
          {python.error && !remote ? <p className="output-error" role="alert">{python.error}</p> : null}
          {shown?.note && !isCleared ? <p className="output-note">{shown.note}</p> : null}
          <Transcript parts={transcript} empty={busy ? undefined : (python.result || remoteResult) && !isCleared ? "(no output)" : `Press Run (${mod}Enter) to start ${entry} with Python ${BROWSER_RUNTIME.split("Python ")[1]} in this browser. Check looks for mistakes in every file; Test runs pytest.`} />
          {python.waitingForInput && !remoteResult ? <InputLine onSubmit={python.provideInput} /> : null}
          {shown && !isCleared ? <Diagnostics items={shown.diagnostics} onOpen={path => { if (view?.files.some(file => file.path === path)) { setSelected(path); setPane("code"); } }} /> : null}
          {shown && !busy && !isCleared ? <RunFooter result={shown} /> : null}
          {stale && !busy && !isCleared ? <p className="output-note">The code changed after this result.</p> : null}
          {shared && !busy && !(shown && shared.startedAt === shown.startedAt && shared.name === shown.ranOn.name) ? <article className="shared-output"><div className="label">Latest run by {shared.kind === "browser" ? `${shared.name}'s browser` : shared.name}</div><pre className="transcript">{shared.stdout ? <span className="stdout">{shared.stdout}</span> : null}{shared.stderr ? <span className="stderr">{shared.stderr}</span> : null}{!shared.stdout && !shared.stderr ? "(no output)" : null}</pre>
            <RunFooter result={{ operation: (runtimeActions as readonly string[]).includes(shared.operation) ? shared.operation as RuntimeAction : "run", ranOn: { name: shared.name, kind: shared.kind, here: false }, runtime: shared.runtime, revision: shared.revision, startedAt: shared.startedAt, durationMs: shared.durationMs, status: shared.succeeded ? "succeeded" : "failed", exitCode: shared.exitCode }} />
            {shared.truncated ? <p className="field-note">Preview shortened; the complete output stays on that device.</p> : null}</article> : null}
        </div>
      </section>
    </main>

    <footer className="pg-statusbar">
      <span>{link ? <><span className={expired ? "pg-closed" : "pg-ok"}>{expired ? "Room closed" : connection}</span>{revision ? <> · revision {revision.slice(0, 6)}</> : null}</> : keepDrafts ? draftStatus || "Draft kept in this browser" : "Draft in this tab · Share, save or download to keep it"}</span>
      <span className="pg-spacer" />
      <span>Pyodide {PYODIDE_VERSION}</span>
      <button type="button" className="pg-status-button" onClick={() => setModal("shortcuts")}><Icon name="keyboard" size={14} />Shortcuts</button>
    </footer>

    <input ref={upload} type="file" multiple hidden accept=".py,.pyi,.txt,.md,.rst,.csv,.tsv,.json,.toml,.cfg,.ini,.yaml,.yml,.html,.css,.js,.sql,.zip,text/*" onChange={event => { const files = Array.from(event.target.files ?? []); event.target.value = ""; if (files.length) void uploadFiles(files, uploadFolder.current); }} />

    <div className="pg-toasts" aria-live="polite">
      {toasts.map(toast => <div key={toast.id} className={`pg-toast${toast.tone === "error" ? " pg-toast-error" : ""}`} role={toast.tone === "error" ? "alert" : "status"}>
        <span>{toast.text}</span>
        {toast.action ? <button type="button" className="pg-toast-action" onClick={() => { dismiss(toast.id); toast.action!.run(); }}>{toast.action.label}</button> : null}
        <button type="button" className="pg-toast-close" aria-label="Dismiss" onClick={() => dismiss(toast.id)}><Icon name="close" size={14} /></button>
      </div>)}
    </div>

    {menu ? <Menu label="More options" items={menuItems} anchor={menu} onClose={restore => { const anchor = menu; setMenu(null); if (restore && "element" in anchor) anchor.element.focus(); }} /> : null}

    <dialog ref={dialog} className={`dialog pg-dialog${modal === "share" ? " pg-dialog-wide" : ""}`} aria-labelledby="dialog-title" onCancel={closeModal} onClick={event => {
      // A click on the backdrop lands on the dialog itself, outside its box.
      const box = event.currentTarget.getBoundingClientRect();
      if (event.target === event.currentTarget && (event.clientX < box.left || event.clientX > box.right || event.clientY < box.top || event.clientY > box.bottom)) closeModal();
    }}>
      {modal === "connect" ? <ConnectAIDialog link={link} created={created} projectName={source?.name ?? ""} sharing={sharing} share={share} lifetime={lifetime} setLifetime={setLifetime} onClose={closeModal} />
      : modal === "share" && source ? <ShareDialog source={source} link={link} created={created} expired={expired} closes={closes} expiresAt={expiresAt} lifetime={lifetime} setLifetime={setLifetime} sharing={sharing}
          onStartRoom={share} onOpenRoomInApp={() => void openRoomInApp()} onEndRoom={() => void endRoom()} onCopyToLocal={() => { setModal(null); copyToLocal(); }} onDownload={save}
          displayName={displayName} namePlaceholder={name} onRename={rename} permissions={liveSession ? <RuntimePermissions runtime={host} /> : null} onClose={closeModal} />
      : modal ? <>
        <div className="dialog-heading"><h2 id="dialog-title">{modal === "drafts" ? "Drafts in this browser" : modal === "open" ? "Open a link" : modal === "shortcuts" ? "Keyboard shortcuts" : "Leave this page?"}</h2><button type="button" className="icon-button" aria-label="Close" onClick={closeModal}><Icon name="close" /></button></div>
        {modal === "drafts" ? <div className="dialog-body">
          <label className="check-row"><input type="checkbox" checked={keepDrafts} onChange={event => setDraftKeeping(event.target.checked)} />Save drafts automatically as I type</label>
          <p className="field-note">Drafts stay in this browser&apos;s storage only, as source with no room links or permissions. {mod}S saves the current draft at any time.</p>
          {draftStatus ? <p className="field-note" role="status">{draftStatus}</p> : null}
          {drafts.length ? <ul className="draft-list">{drafts.map(draft => <li key={draft.id}><span>{draft.name}{draft.id === draftId ? " (open)" : ""}<small>{Object.keys(draft.document.files).length} files · {new Date(draft.updatedAt).toLocaleString([], { dateStyle: "medium", timeStyle: "short" })}</small></span><span><button type="button" className="pill-button" disabled={draft.id === draftId} onClick={() => { if (hasUnsavedWork() && !window.confirm("Open this draft? Unsaved changes here are lost unless you download them first.")) return; setModal(null); unsaved.current = false; onOpenLocal(draft.document, { notice: `Opened your draft ${draft.name}.`, draftId: draft.id, unsaved: false }); }}>Open</button><button type="button" className="pill-button danger" onClick={() => { if (!window.confirm(`Delete the draft ${draft.name}?`)) return; void deleteDraft(draft.id).then(() => listDrafts()).then(setDrafts, () => setDraftStatus("Browser storage is unavailable.")); }}>Delete</button></span></li>)}</ul> : <p className="field-note">No drafts saved yet.</p>}
          <div className="dialog-actions start"><button type="button" className="pill-button" onClick={() => { setModal(null); newProject(); }}><Icon name="plus" />New project</button></div>
        </div> : null}
        {modal === "open" ? <form className="dialog-body" onSubmit={event => { event.preventDefault(); submitOpen(); }}>
          <p>Paste a Pythilo link: a link to code (it has <code>#code=</code>) opens as your own copy, and a room link joins the room.</p>
          <label className="field">Link<input value={openText} onChange={event => { setOpenText(event.target.value); setOpenProblem(""); }} placeholder="https://pythilo.com/playground/#code=…" spellCheck={false} autoCapitalize="off" autoCorrect="off" aria-invalid={!!openProblem} aria-describedby="pg-open-problem" /></label>
          <p id="pg-open-problem" className="field-problem" role="status">{openProblem}</p>
          <div className="dialog-actions"><button type="button" className="pill-button" onClick={closeModal}>Cancel</button><button type="submit" className="pill-button primary" disabled={!openText.trim()}>Open</button></div>
        </form> : null}
        {modal === "shortcuts" ? <div className="dialog-body"><dl className="pg-shortcuts">
          {[[`${mod}Enter`, "Run the main file"], [`${mod}⇧Enter`, "Run the tests"], [`${mod}.`, "Stop"], [`${mod}S`, "Save to Drafts in this browser"], ["Alt+N", "New file"], ["⇧Alt+N", "New folder"], ["F2", "Rename the file in the list"], ["Del", "Delete the file in the list (with Undo)"], ["↑ ↓ ← →", "Move around the file list"], ["Shift+F10", "Actions for the file in the list"], ["Tab", "Indent in the editor; Esc then Tab leaves it"], ["?", "This list"]].map(([keys, label]) => <div key={keys}><dt><kbd>{keys}</kbd></dt><dd>{label}</dd></div>)}
        </dl></div> : null}
        {modal === "leave" ? <div className="dialog-body"><p>{link ? "Some of this room's code has not reached the relay, or the room has closed. Leaving now can lose it." : "This draft is only in this page. Download it or save it to Drafts to keep it."}</p><div className="dialog-actions"><button type="button" className="pill-button" onClick={closeModal}>Stay</button><button type="button" className="pill-button" onClick={() => { const target = leaveTo; unsaved.current = false; guard.current = { link: false, expired: false }; if (target) location.assign(target); }}>Leave without saving</button><button type="button" className="pill-button primary" onClick={() => { const target = leaveTo; save(); guard.current = { link: false, expired: false }; if (target) location.assign(target); }}>Download and leave</button></div></div> : null}
      </> : null}
    </dialog>
  </div>;
}
