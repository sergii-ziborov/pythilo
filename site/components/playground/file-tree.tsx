"use client";

import { useEffect, useMemo, useRef, useState, type KeyboardEvent } from "react";
import { ancestors, buildFileTree, fileIconKind, flattenTree, matchingPaths, type FileIconKind, type TreeNode } from "@/lib/playground-file-ops";

export type TreeAction = "new-file" | "new-folder" | "rename" | "move" | "duplicate" | "delete" | "copy-path" | "set-entry";

const badges: Record<FileIconKind, string> = { python: "py", package: "pk", test: "✓", csv: "csv", json: "{}", toml: "cfg", requirements: "req", markdown: "md", html: "<>", css: "#", database: "sql", git: "git", script: "js", text: "txt" };

export function FileBadge({ path, folder, open }: { path: string; folder?: boolean; open?: boolean }) {
  if (folder) return <span className="file-badge folder" aria-hidden="true">{open ? "▾" : "▸"}</span>;
  const kind = fileIconKind(path);
  return <span className={`file-badge ${kind}`} aria-hidden="true">{badges[kind]}</span>;
}

function loadExpanded(key: string): Set<string> {
  try { const saved = JSON.parse(sessionStorage.getItem(key) ?? "[]"); return new Set(Array.isArray(saved) ? saved.filter(item => typeof item === "string") : []); }
  catch { return new Set(); }
}

type Props = {
  paths: string[]; selected: string; entryFile?: string; readOnly: boolean;
  /** A shared room, where rename, move and delete need a local copy. */
  shared: boolean;
  /** Files other participants have open, with their colour. */
  present?: ReadonlyMap<string, { name: string; color: string }>;
  /** Keeps a room's open folders apart from every other room's. */
  storageKey: string;
  onOpen: (path: string) => void;
  onAction: (action: TreeAction, node: TreeNode) => void;
};

export function FileTree({ paths, selected, entryFile, readOnly, shared, present, storageKey, onOpen, onAction }: Props) {
  const [expanded, setExpanded] = useState(() => loadExpanded(storageKey));
  const [query, setQuery] = useState(""), [focused, setFocused] = useState(selected), [menu, setMenu] = useState<string | null>(null);
  const container = useRef<HTMLDivElement>(null), restoreFocus = useRef(false);
  const tree = useMemo(() => buildFileTree(paths), [paths]);

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
  }, [active, rows]);

  const moveTo = (path: string | undefined) => { if (path) { restoreFocus.current = true; setFocused(path); } };
  const setOpen = (path: string, open: boolean) => setExpanded(previous => { const next = new Set(previous); if (open) next.add(path); else next.delete(path); return next; });

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
      case "F2": handled(); if (!readOnly) onAction("rename", node); break;
      case "Delete": handled(); if (!readOnly) onAction("delete", node); break;
      case "Escape": if (menu) { handled(); setMenu(null); } break;
    }
  };

  const items = (node: TreeNode): [TreeAction, string, boolean][] => {
    const destructive = readOnly || shared;
    const actions = node.kind === "folder"
      ? [["new-file", "New file inside", readOnly], ["new-folder", "New folder and file inside", readOnly], ["rename", "Rename folder", destructive], ["move", "Move folder", destructive], ["delete", "Delete contents", destructive]] as [TreeAction, string, boolean][]
      : [...(node.path.endsWith(".py") && node.path !== entryFile ? [["set-entry", "Set as entry", readOnly] as [TreeAction, string, boolean]] : []), ["rename", "Rename", destructive], ["move", "Move", destructive], ["duplicate", "Duplicate", readOnly], ["delete", "Delete", destructive]] as [TreeAction, string, boolean][];
    return [...actions, ["copy-path", "Copy relative path", false]];
  };

  return <div className="pg-tree-wrap" ref={container}>
    {paths.length > 6 ? <label className="pg-tree-search"><span className="visually-hidden">Find a file by name or path</span>
      <input type="search" value={query} placeholder="Find file" onChange={event => setQuery(event.target.value)} onKeyDown={event => { if (event.key === "Escape") { event.stopPropagation(); setQuery(""); } if (event.key === "ArrowDown") { event.preventDefault(); moveTo(rows[0]?.node.path); } }} />
    </label> : null}
    <div className="pg-file-list" role="tree" aria-label="Project files">
      {rows.map(({ node, depth, parent }, index) => {
        const open = node.kind === "folder" && shownExpanded.has(node.path), isSelected = node.kind === "file" && node.path === selected, here = present?.get(node.path);
        return <div key={node.path} className={`pg-tree-row${isSelected ? " pg-file-active" : ""}`} role="treeitem" aria-level={depth + 1} aria-selected={isSelected} aria-expanded={node.kind === "folder" ? open : undefined} tabIndex={node.path === active ? 0 : -1} title={node.path} style={{ "--pg-depth": depth } as React.CSSProperties}
          onFocus={event => { if (event.target === event.currentTarget) setFocused(node.path); }} onKeyDown={event => { if (event.target === event.currentTarget) keyDown(event, node, index, parent); }}>
          <button type="button" tabIndex={-1} className="pg-tree-open" onClick={() => { setFocused(node.path); if (node.kind === "file") onOpen(node.path); else if (!matches) setOpen(node.path, !open); }}>
            <FileBadge path={node.path} folder={node.kind === "folder"} open={open} />
            <span className="pg-tree-name">{node.name}</span>
            {node.path === entryFile ? <span className="pg-entry-badge">Entry</span> : null}
            {here ? <span className="pg-presence-dot" style={{ background: here.color }} title={`${here.name} is here`} /> : null}
          </button>
          <button type="button" tabIndex={node.path === active ? 0 : -1} className="pg-tree-menu-button" aria-label={`Actions for ${node.path}`} aria-haspopup="menu" aria-expanded={menu === node.path} onClick={() => setMenu(menu === node.path ? null : node.path)} onKeyDown={event => { if (event.key === "Escape") { event.stopPropagation(); setMenu(null); } }}>⋯</button>
          {menu === node.path ? <div className="pg-tree-menu" role="menu" onKeyDown={event => { event.stopPropagation(); if (event.key === "Escape") { setMenu(null); moveTo(node.path); } }}>
            {items(node).map(([action, label, disabled]) => <button key={action} role="menuitem" type="button" disabled={disabled} autoFocus={action === items(node)[0][0]} onClick={() => { setMenu(null); onAction(action, node); }}>{label}</button>)}
            {shared ? <p>Rename, move and delete need a local copy in a shared room, so nobody's unsent edit is lost.</p> : null}
          </div> : null}
        </div>;
      })}
      {!rows.length ? <p className="pg-tree-empty">{query ? "No file matches this search." : "No files yet."}</p> : null}
    </div>
  </div>;
}
