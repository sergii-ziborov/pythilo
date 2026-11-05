"use client";

import { useEffect, useLayoutEffect, useRef, useState, type ReactNode } from "react";
import { Icon, type IconName } from "./icons";

export type MenuItem =
  | { label: string; icon?: IconName; shortcut?: string; onSelect: () => void; disabled?: boolean; danger?: boolean; title?: string }
  | { separator: true }
  | { note: ReactNode };

/** Where the menu opens: under a button, or at the pointer for a right click. */
export type MenuAnchor = { element: HTMLElement; align?: "start" | "end" } | { x: number; y: number };

/** A popup menu with arrow keys, Home/End, Escape and type-ahead, kept inside the viewport. */
export function Menu({ items, anchor, onClose, label }: { items: MenuItem[]; anchor: MenuAnchor; onClose: (restoreFocus: boolean) => void; label: string }) {
  const list = useRef<HTMLDivElement>(null);
  const [position, setPosition] = useState<{ left: number; top: number } | null>(null);
  const closeRef = useRef(onClose); closeRef.current = onClose;

  useLayoutEffect(() => {
    const menu = list.current; if (!menu) return;
    const width = menu.offsetWidth, height = menu.offsetHeight, margin = 8;
    let left: number, top: number;
    if ("element" in anchor) {
      const rect = anchor.element.getBoundingClientRect();
      left = anchor.align === "start" ? rect.left : rect.right - width; top = rect.bottom + 4;
      if (top + height > innerHeight - margin && rect.top - height - 4 > margin) top = rect.top - height - 4;
    } else { left = anchor.x; top = anchor.y; if (top + height > innerHeight - margin) top = anchor.y - height; }
    setPosition({ left: Math.max(margin, Math.min(left, innerWidth - width - margin)), top: Math.max(margin, Math.min(top, innerHeight - height - margin)) });
    menu.querySelector<HTMLElement>('[role="menuitem"]:not(:disabled)')?.focus();
  }, [anchor]);

  useEffect(() => {
    const away = (event: PointerEvent) => { if (!list.current?.contains(event.target as Node) && !("element" in anchor && anchor.element.contains(event.target as Node))) closeRef.current(false); };
    const scroll = (event: Event) => { if (!list.current?.contains(event.target as Node)) closeRef.current(false); };
    const resize = () => closeRef.current(false);
    document.addEventListener("pointerdown", away, true); window.addEventListener("resize", resize); document.addEventListener("scroll", scroll, true);
    return () => { document.removeEventListener("pointerdown", away, true); window.removeEventListener("resize", resize); document.removeEventListener("scroll", scroll, true); };
  }, [anchor]);

  const keyDown = (event: React.KeyboardEvent) => {
    const buttons = Array.from(list.current?.querySelectorAll<HTMLButtonElement>('[role="menuitem"]:not(:disabled)') ?? []);
    const index = buttons.indexOf(document.activeElement as HTMLButtonElement);
    const go = (next: number) => { event.preventDefault(); buttons[(next + buttons.length) % buttons.length]?.focus(); };
    if (event.key === "ArrowDown") go(index + 1);
    else if (event.key === "ArrowUp") go(index - 1);
    else if (event.key === "Home") go(0);
    else if (event.key === "End") go(buttons.length - 1);
    else if (event.key === "Escape") { event.preventDefault(); event.stopPropagation(); onClose(true); }
    else if (event.key === "Tab") { event.preventDefault(); onClose(true); }
    else if (event.key.length === 1 && /\S/.test(event.key)) {
      const start = index + 1, letter = event.key.toLowerCase();
      const match = [...buttons.slice(start), ...buttons.slice(0, start)].find(button => button.textContent?.trim().toLowerCase().startsWith(letter));
      if (match) { event.preventDefault(); match.focus(); }
    }
  };

  return <div ref={list} className="pg-menu" role="menu" aria-label={label} onKeyDown={keyDown} style={position ? { left: position.left, top: position.top } : { visibility: "hidden" }}>
    {items.map((item, index) => "separator" in item ? <div key={index} className="pg-menu-separator" role="separator" />
      : "note" in item ? <p key={index} className="pg-menu-note">{item.note}</p>
      : <button key={index} type="button" role="menuitem" className={item.danger ? "danger" : undefined} disabled={item.disabled} title={item.title} onClick={() => { onClose(false); item.onSelect(); }}>
        <span className="pg-menu-icon">{item.icon ? <Icon name={item.icon} /> : null}</span>
        <span className="pg-menu-label">{item.label}</span>
        {item.shortcut ? <kbd>{item.shortcut}</kbd> : null}
      </button>)}
  </div>;
}

/** Ctrl on Windows and Linux, ⌘ on Apple devices. */
export const isApple = () => typeof navigator !== "undefined" && /Mac|iPhone|iPad|iPod/.test(navigator.platform || navigator.userAgent);
export const modKey = () => isApple() ? "⌘" : "Ctrl+";
