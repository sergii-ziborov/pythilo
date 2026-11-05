"use client";

import { useEffect, useMemo, useRef, useState, type DragEvent, type KeyboardEvent, type RefObject } from "react";
import { ancestors, buildFileTree, fileIconKind, flattenTree, folderPaths, matchingPaths, moveOperation, type FileIconKind, type FileOperation, type TreeNode } from "@/lib/playground-file-ops";
import { isValidSourcePath } from "@/lib/playground-document";
import { Icon } from "./icons";
import { Menu, type MenuAnchor, type MenuItem } from "./menu";

const badges: Record<FileIconKind, string> = { python: "py", package: "pk", test: "✓", csv: "csv", json: "{}", toml: "cfg", requirements: "req", markdown: "md", html: "<>", css: "#", database: "sql", git: "git", script: "js", text: "txt" };

export function FileBadge({ path }: { path: string }) {
  const kind = fileIconKind(path);
  return <span className={`file-badge ${kind}`} aria-hidden="true">{badges[kind]}</span>;
}

function loadExpanded(key: string): Set<string> {
  try { const saved = JSON.parse(sessionStorage.getItem(key) ?? "[]"); return new Set(Array.isArray(saved) ? saved.filter(item => typeof item === "string") : []); }
  catch { return new Set(); }
}

const DRAG_TYPE = "application/x-pythilo-path";
const parentOf = (path: string) => path.includes("/") ? path.slice(0, path.lastIndexOf("/")) : "";
const joined = (folder: string, name: string) => folder ? `${folder}/${name}` : name;

type Editing = { mode: "create"; kind: "file" | "folder"; folder: string } | { mode: "rename"; node: TreeNode };

/** What the workspace can ask of the tree: buttons and shortcuts outside it start inline editing here. */
export type TreeApi = { create: (kind: "file" | "folder", folder?: string) => void; rename: (path: string) => void };

type Props = {
  paths: string[]; emptyFolders: string[]; selected: string; entryFile?: string; readOnly: boolean;
  /** A shared room, where rename, move and delete need a local copy. */
  shared: boolean;
  /** Files other participants have open, with their colour. */
  present?: ReadonlyMap<string, { name: string; color: string }>;
  /** Keeps a room's open folders apart from every other room's. */
  storageKey: string;
  api: RefObject<TreeApi | null>;
  /** Plans an operation against the live project and throws the problem to show. */
  check: (operation: FileOperation) => void;
  onOpen: (path: string) => void;
  onApply: (operation: FileOperation) => void;
  onCreateFolder: (path: string) => void;
  onDelete: (node: TreeNode) => void;
  onUpload: (files: File[], folder: string) => void;
  onPickUpload: (folder: string) => void;
  onDownload: (path: string) => void;
  onNotice: (text: string) => void;
};

export function FileTree(props: Props) {
  const { paths, emptyFolders, selected, entryFile, readOnly, shared, present, storageKey, api, check, onOpen, onApply, onCreateFolder, onDelete, onUpload, onPickUpload, onDownload, onNotice } = props;
  const [expanded, setExpanded] = useState(() => loadExpanded(storageKey));
  const [query, setQuery] = useState(""), [focused, setFocused] = useState(selected);
  const [menu, setMenu] = useState<{ node: TreeNode | null; anchor: MenuAnchor; move?: boolean } | null>(null);
  const [editing, setEditing] = useState<Editing | null>(null), [draft, setDraft] = useState("");
  const [dropTarget, setDropTarget] = useState<string | null>(null);
  const container = useRef<HTMLDivElement>(null), restoreFocus = useRef(false), input = useRef<HTMLInputElement>(null);
  const tree = useMemo(() => buildFileTree(paths, emptyFolders), [paths, emptyFolders]);
  const canChange = !readOnly && !shared;
  const lockedNote = "Rename, move and delete are off in a shared room, so nobody's unsent edit is lost. Copy the room to a local draft to reorganise it.";

  useEffect(() => { try { sessionStorage.setItem(storageKey, JSON.stringify(Array.from(expanded))); } catch { /* Open folders only last for this view. */ } }, [expanded, storageKey]);
  // Opening a file from anywhere, such as a traceback, reveals its folder.
  useEffect(() => { setFocused(selected); setExpanded(previous => { const missing = ancestors(selected).filter(item => !previous.has(item)); return missing.length ? new Set([...previous, ...missing]) : previous; }); }, [selected]);

  const matches = useMemo(() => query.trim() ? matchingPaths(paths, query) : null, [paths, query]);
  const shownTree = useMemo(() => matches ? buildFileTree(matches) : tree, [matches, tree]);
  const shownExpanded = useMemo(() => matches ? new Set(matches.flatMap(ancestors)) : expanded, [matches, expanded]);
  const rows = useMemo(() => flattenTree(shownTree, shownExpanded), [shownTree, shownExpanded]);
  const active = rows.some(row => row.node.path === focused) ? focused : rows[0]?.node.path;

  useEffect(() => {
    if (!restoreFocus.current) return;
    restoreFocus.current = false;
    container.current?.querySelector<HTMLElement>('[role="treeitem"][tabindex="0"]')?.focus();
  }, [active, rows, editing]);

  const moveTo = (path: string | undefined) => { if (path) { restoreFocus.current = true; setFocused(path); } };
  const setOpen = (path: string, open: boolean) => setExpanded(previous => { const next = new Set(previous); if (open) next.add(path); else next.delete(path); return next; });

  const startCreate = (kind: "file" | "folder", folder = "") => {
    if (readOnly) return;
    setQuery(""); if (folder) setOpen(folder, true);
    setEditing({ mode: "create", kind, folder }); setDraft("");
  };
  const startRename = (node: TreeNode) => {
    if (!canChange) { onNotice(shared ? lockedNote : "This project is read-only."); return; }
    setEditing({ mode: "rename", node }); setDraft(node.name);
  };
  api.current = { create: startCreate, rename: path => { const node = rows.find(row => row.node.path === path)?.node; if (node) startRename(node); } };

  // Selects the name without its extension, as most editors do.
  useEffect(() => {
    const field = input.current; if (!field || !editing) return;
    field.focus();
    const dot = field.value.lastIndexOf(".");
    if (editing.mode === "rename" && editing.node.kind === "file" && dot > 0) field.setSelectionRange(0, dot); else field.select();
  }, [editing]);

  /** The operation the inline field describes, and the problem to show for it. */
  const pending = useMemo((): { operation: FileOperation | null; folder?: string; problem: string } => {
    if (!editing) return { operation: null, problem: "" };
    const name = draft.trim().replace(/^\/+|\/+$/g, "");
    if (!name) return { operation: null, problem: "" };
    if (editing.mode === "create" && editing.kind === "folder") {
      const path = joined(editing.folder, name);
      if (!isValidSourcePath(`${path}/__init__.py`)) return { operation: null, problem: "Use letters, digits, - and _ for a folder name." };
      if (paths.some(item => item.toLowerCase() === path.toLowerCase())) return { operation: null, problem: "A file has this name." };
      if (folderPaths(paths).concat(emptyFolders).some(item => item.toLowerCase() === path.toLowerCase())) return { operation: null, problem: "This folder already exists." };
      return { operation: null, folder: path, problem: "" };
    }
    let operation: FileOperation;
    if (editing.mode === "create") {
      const path = joined(editing.folder, name);
      if (!/\.[A-Za-z0-9]+$/.test(name) && !/^(LICENSE|NOTICE|README|requirements\.txt|\.gitignore)$/.test(name.split("/").at(-1)!)) return { operation: null, problem: "Add an extension, such as .py, .txt, .csv or .json." };
      operation = { kind: "create", path };
    } else {
      const to = joined(parentOf(editing.node.path), name);
      if (to === editing.node.path) return { operation: null, problem: "" };
      operation = editing.node.kind === "folder" ? { kind: "rename-folder", from: editing.node.path, to } : { kind: "rename", from: editing.node.path, to };
    }
    try { check(operation); return { operation, problem: "" }; }
    catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      return { operation: null, problem: /Unsupported source path/.test(message) ? "Playgrounds hold text files: .py, .txt, .md, .csv, .json, .toml, .yaml, .html, .css, .js or .sql." : message };
    }
  }, [editing, draft, check, paths, emptyFolders]);

  const finishEditing = (commit: boolean) => {
    const current = editing; if (!current) return;
    setEditing(null); restoreFocus.current = true;
    if (!commit) return;
    if (pending.folder) { onCreateFolder(pending.folder); setOpen(pending.folder, true); setTimeout(() => startCreate("file", pending.folder), 0); return; }
    if (pending.operation) {
      onApply(pending.operation);
      if (pending.operation.kind === "create") setFocused(pending.operation.path);
      if (pending.operation.kind === "rename-folder") setExpanded(previous => new Set([...previous, (pending.operation as { to: string }).to]));
    }
  };

  const keyDown = (event: KeyboardEvent, node: TreeNode, index: number, parent: string | null) => {
    const handled = () => { event.preventDefault(); event.stopPropagation(); };
    switch (event.key) {
      case "ArrowDown": handled(); moveTo(rows[index + 1]?.node.path); break;
      case "ArrowUp": handled(); moveTo(rows[index - 1]?.node.path); break;
      case "Home": handled(); moveTo(rows[0]?.node.path); break;
      case "End": handled(); moveTo(rows.at(-1)?.node.path); break;
      case "ArrowRight":
        handled();
        if (node.kind === "folder") { if (shownExpanded.has(node.path)) moveTo(rows[index + 1]?.node.path); else if (!matches) setOpen(node.path, true); }
        break;
      case "ArrowLeft":
        handled();
        if (node.kind === "folder" && shownExpanded.has(node.path) && !matches) setOpen(node.path, false);
        else if (parent) moveTo(parent);
        break;
      case "Enter": case " ":
        handled();
        if (node.kind === "file") onOpen(node.path); else if (!matches) setOpen(node.path, !expanded.has(node.path));
        break;
      case "F2": handled(); startRename(node); break;
      case "Delete": handled(); if (canChange) onDelete(node); else onNotice(shared ? lockedNote : "This project is read-only."); break;
      case "Backspace": if (event.metaKey) { handled(); if (canChange) onDelete(node); } break;
      case "ContextMenu": handled(); setMenu({ node, anchor: { element: event.currentTarget as HTMLElement, align: "start" } }); break;
      case "F10": if (event.shiftKey) { handled(); setMenu({ node, anchor: { element: event.currentTarget as HTMLElement, align: "start" } }); } break;
    }
  };

  const copyPath = (path: string) => void navigator.clipboard.writeText(path).then(() => onNotice(`Copied ${path}`), () => onNotice(path));
  const moveTargets = (node: TreeNode) => ["", ...folderPaths(paths), ...emptyFolders].filter((folder, index, all) => all.indexOf(folder) === index && folder !== parentOf(node.path) && !(node.kind === "folder" && (folder === node.path || folder.startsWith(node.path + "/"))));
  const items = (node: TreeNode | null, move = false): MenuItem[] => {
    if (move && node) {
      const targets = moveTargets(node);
      return targets.length ? targets.map(folder => ({ label: folder ? `${folder}/` : "Project root", icon: "folder" as const, onSelect: () => { const operation = moveOperation(node, folder); if (operation) onApply(operation); } }))
        : [{ note: "Create a folder first, then move files into it." }];
    }
    if (!node) return [
      { label: "New file", icon: "new-file", shortcut: "Alt+N", onSelect: () => startCreate("file"), disabled: readOnly },
      { label: "New folder", icon: "new-folder", shortcut: "⇧Alt+N", onSelect: () => startCreate("folder"), disabled: readOnly },
      { label: "Upload files…", icon: "upload", onSelect: () => onPickUpload(""), disabled: readOnly },
    ];
    const locked = { disabled: !canChange, title: shared ? lockedNote : undefined };
    const common: MenuItem[] = [
      { label: "Rename", icon: "rename", shortcut: "F2", onSelect: () => startRename(node), ...locked },
      { label: "Move to…", icon: "folder", onSelect: () => setTimeout(() => setMenu({ node, anchor: menu?.anchor ?? { x: 0, y: 0 }, move: true }), 0), ...locked },
    ];
    const folderItems: MenuItem[] = node.kind === "folder" ? [
      { label: "New file here", icon: "new-file", onSelect: () => startCreate("file", node.path), disabled: readOnly },
      { label: "New folder here", icon: "new-folder", onSelect: () => startCreate("folder", node.path), disabled: readOnly },
      { label: "Upload here…", icon: "upload", onSelect: () => onPickUpload(node.path), disabled: readOnly },
      { separator: true },
    ] : [];
    const fileItems: MenuItem[] = node.kind === "file" ? [
      ...(node.path.endsWith(".py") && node.path !== entryFile ? [{ label: "Use as main file", icon: "entry", onSelect: () => onApply({ kind: "add-files", files: {}, entryFile: node.path }), disabled: readOnly } as MenuItem] : []),
      { label: "Duplicate", icon: "copy", onSelect: () => { const dot = node.path.lastIndexOf("."); const base = dot > node.path.lastIndexOf("/") + 1 ? node.path.slice(0, dot) : node.path, ext = base === node.path ? "" : node.path.slice(dot); let to = `${base}_copy${ext}`; for (let n = 2; paths.includes(to); n++) to = `${base}_copy${n}${ext}`; onApply({ kind: "duplicate", from: node.path, to }); }, disabled: readOnly },
      { label: "Download", icon: "download", onSelect: () => onDownload(node.path) },
    ] : [];
    return [
      ...folderItems, ...common, ...fileItems,
      { label: "Copy path", icon: "link", onSelect: () => copyPath(node.path) },
      { separator: true },
      { label: node.kind === "folder" ? "Delete folder" : "Delete", icon: "trash", shortcut: "Del", danger: true, onSelect: () => onDelete(node), ...locked },
      ...(shared ? [{ note: lockedNote } as MenuItem] : []),
    ];
  };

  // Moving by drag; files dragged in from the computer upload into the folder under the pointer.
  const dragOver = (event: DragEvent, folder: string) => {
    const types = Array.from(event.dataTransfer.types);
    if (readOnly || !(types.includes(DRAG_TYPE) && canChange || types.includes("Files"))) return;
    event.preventDefault(); event.stopPropagation();
    event.dataTransfer.dropEffect = types.includes("Files") ? "copy" : "move";
    setDropTarget(folder);
  };
  const drop = (event: DragEvent, folder: string) => {
    if (readOnly) return;
    event.preventDefault(); event.stopPropagation(); setDropTarget(null);
    if (event.dataTransfer.files.length) { onUpload(Array.from(event.dataTransfer.files), folder); return; }
    const from = event.dataTransfer.getData(DRAG_TYPE); if (!from || !canChange) return;
    const node = rows.find(row => row.node.path === from)?.node ?? { kind: "file" as const, name: from.split("/").at(-1)!, path: from };
    const isFolder = node.kind === "folder" || paths.some(path => path.startsWith(from + "/"));
    const operation = moveOperation({ kind: isFolder ? "folder" : "file", path: from }, folder);
    if (!operation) return;
    onApply(operation);
    if (folder) setOpen(folder, true);
  };

  const inputRow = (depth: number) => <div className="pg-tree-row pg-tree-editing" style={{ "--pg-depth": depth } as React.CSSProperties}>
    <span className="pg-tree-twist" aria-hidden="true" />
    {editing?.mode === "create" && editing.kind === "folder" ? <Icon name="folder" className="pg-tree-folder-icon" /> : <FileBadge path={draft.trim() || "x.py"} />}
    <EditField input={input} value={draft} onChange={setDraft} problem={pending.problem} label={editing?.mode === "create" ? (editing.kind === "folder" ? "New folder name" : "New file name") : "New name"} placeholder={editing?.mode === "create" ? (editing.kind === "folder" ? "folder" : "name.py") : ""} onDone={finishEditing} />
  </div>;

  const rowsOut: React.ReactNode[] = [];
  if (editing?.mode === "create" && !editing.folder) rowsOut.push(<div key="\u0000create">{inputRow(0)}</div>);
  rows.forEach(({ node, depth, parent }, index) => {
    const open = node.kind === "folder" && shownExpanded.has(node.path), isSelected = node.kind === "file" && node.path === selected, here = present?.get(node.path);
    const renaming = editing?.mode === "rename" && editing.node.path === node.path;
    const folderForDrop = node.kind === "folder" ? node.path : parentOf(node.path);
    const empty = node.kind === "folder" && open && node.children.length === 0 && !(editing?.mode === "create" && editing.folder === node.path);
    rowsOut.push(renaming ? <div key={node.path}>{inputRow(depth)}</div> : <div key={node.path} className={`pg-tree-row${isSelected ? " pg-file-active" : ""}${dropTarget === node.path && node.kind === "folder" ? " pg-drop" : ""}`} role="treeitem" aria-level={depth + 1} aria-selected={isSelected} aria-expanded={node.kind === "folder" ? open : undefined}
      tabIndex={node.path === active ? 0 : -1} title={node.path} style={{ "--pg-depth": depth } as React.CSSProperties}
      draggable={canChange && !matches} onDragStart={event => { event.dataTransfer.setData(DRAG_TYPE, node.path); event.dataTransfer.effectAllowed = "move"; }} onDragEnd={() => setDropTarget(null)}
      onDragOver={event => dragOver(event, folderForDrop)} onDragLeave={() => setDropTarget(null)} onDrop={event => drop(event, folderForDrop)}
      onContextMenu={event => { event.preventDefault(); setFocused(node.path); setMenu({ node, anchor: { x: event.clientX, y: event.clientY } }); }}
      onFocus={event => { if (event.target === event.currentTarget) setFocused(node.path); }} onKeyDown={event => { if (event.target === event.currentTarget) keyDown(event, node, index, parent); }}
      onClick={() => { setFocused(node.path); if (node.kind === "file") onOpen(node.path); else if (!matches) setOpen(node.path, !open); }}>
      <span className="pg-tree-twist" aria-hidden="true">{node.kind === "folder" ? <Icon name="chevron" className={open ? "pg-open" : undefined} size={12} /> : null}</span>
      {node.kind === "folder" ? <Icon name={open ? "folder-open" : "folder"} className="pg-tree-folder-icon" /> : <FileBadge path={node.path} />}
      <span className="pg-tree-name">{node.name}</span>
      {node.path === entryFile ? <span className="pg-entry-mark" title="Main file: Run starts here"><Icon name="entry" size={12} /><span className="visually-hidden">, main file</span></span> : null}
      {here ? <span className="pg-presence-dot" style={{ background: here.color }} title={`${here.name} is here`} /> : null}
      <span className="pg-tree-actions" onClick={event => event.stopPropagation()}>
        {canChange ? <button type="button" tabIndex={-1} className="pg-tree-action pg-hover-only" aria-label={`Rename ${node.path}`} title="Rename (F2)" onClick={() => startRename(node)}><Icon name="rename" size={14} /></button> : null}
        {canChange ? <button type="button" tabIndex={-1} className="pg-tree-action pg-hover-only" aria-label={`Delete ${node.path}`} title="Delete (Del)" onClick={() => onDelete(node)}><Icon name="trash" size={14} /></button> : null}
        <button type="button" tabIndex={node.path === active ? 0 : -1} className="pg-tree-action" aria-label={`More actions for ${node.path}`} aria-haspopup="menu" aria-expanded={menu?.node?.path === node.path}
          onClick={event => setMenu(menu?.node?.path === node.path ? null : { node, anchor: { element: event.currentTarget, align: "end" } })}><Icon name="more" size={14} /></button>
      </span>
    </div>);
    if (empty) rowsOut.push(<p key={node.path + "\u0000empty"} className="pg-tree-hint" style={{ "--pg-depth": depth + 1 } as React.CSSProperties}>Empty. Add a file to keep this folder.</p>);
    if (editing?.mode === "create" && editing.folder === node.path) rowsOut.push(<div key={node.path + "\u0000create"}>{inputRow(depth + 1)}</div>);
  });

  return <div className="pg-explorer" ref={container}>
    <div className="pg-explorer-head">
      <h2 className="label" id="pg-files-label">Files</h2>
      <div className="pg-explorer-tools">
        <button type="button" className="pg-tool" disabled={readOnly} onClick={() => startCreate("file", selectedFolder(paths, emptyFolders, focused))} aria-label="New file" title="New file (Alt+N)"><Icon name="new-file" /></button>
        <button type="button" className="pg-tool" disabled={readOnly} onClick={() => startCreate("folder", selectedFolder(paths, emptyFolders, focused))} aria-label="New folder" title="New folder (Shift+Alt+N)"><Icon name="new-folder" /></button>
        <button type="button" className="pg-tool" disabled={readOnly} onClick={() => onPickUpload("")} aria-label="Upload files" title="Upload files or a ZIP"><Icon name="upload" /></button>
        <button type="button" className="pg-tool" disabled={!expanded.size} onClick={() => setExpanded(new Set())} aria-label="Collapse folders" title="Collapse folders"><Icon name="collapse" /></button>
      </div>
    </div>
    {paths.length > 8 ? <label className="pg-tree-search"><Icon name="search" size={14} /><span className="visually-hidden">Find a file by name or path</span>
      <input type="search" value={query} placeholder="Find a file" onChange={event => setQuery(event.target.value)} onKeyDown={event => { if (event.key === "Escape") { event.stopPropagation(); setQuery(""); } if (event.key === "ArrowDown") { event.preventDefault(); moveTo(rows[0]?.node.path); } }} />
    </label> : null}
    <div className={`pg-file-list${dropTarget === "" ? " pg-drop" : ""}`} role="tree" aria-labelledby="pg-files-label"
      onDragOver={event => dragOver(event, "")} onDragLeave={event => { if (event.currentTarget === event.target) setDropTarget(null); }} onDrop={event => drop(event, "")}
      onContextMenu={event => { if (event.target === event.currentTarget) { event.preventDefault(); setMenu({ node: null, anchor: { x: event.clientX, y: event.clientY } }); } }}>
      {rowsOut}
      {!rows.length && !editing ? <p className="pg-tree-hint">{query ? "No file matches this search." : "No files yet."}</p> : null}
    </div>
    {menu ? <Menu label={menu.move ? `Move ${menu.node?.path} to` : menu.node ? `Actions for ${menu.node.path}` : "Files"} items={items(menu.node, menu.move)} anchor={menu.anchor} onClose={restore => { setMenu(null); if (restore) moveTo(menu.node?.path ?? active); }} /> : null}
  </div>;
}

/** New files go next to the focused file, or into the focused folder. */
function selectedFolder(paths: string[], emptyFolders: string[], focused: string | undefined): string {
  if (!focused) return "";
  if (emptyFolders.includes(focused) || paths.some(path => path.startsWith(focused + "/"))) return focused;
  return parentOf(focused);
}

function EditField({ input, value, onChange, problem, label, placeholder, onDone }: { input: RefObject<HTMLInputElement | null>; value: string; onChange: (value: string) => void; problem: string; label: string; placeholder: string; onDone: (commit: boolean) => void }) {
  const done = useRef(false);
  useEffect(() => { done.current = false; }, []);
  const finish = (commit: boolean) => { if (done.current) return; done.current = true; onDone(commit); };
  return <span className="pg-tree-field">
    <input ref={input} value={value} aria-label={label} placeholder={placeholder} spellCheck={false} autoCapitalize="off" autoCorrect="off" autoComplete="off" enterKeyHint="done"
      aria-invalid={!!problem} aria-describedby={problem ? "pg-tree-problem" : undefined}
      onChange={event => onChange(event.target.value)}
      onKeyDown={event => { event.stopPropagation(); if (event.key === "Enter") { event.preventDefault(); if (!problem) finish(true); } else if (event.key === "Escape") { event.preventDefault(); finish(false); } }}
      onBlur={() => finish(!problem && !!value.trim())} />
    {problem ? <span id="pg-tree-problem" className="pg-tree-problem" role="alert">{problem}</span> : null}
  </span>;
}
