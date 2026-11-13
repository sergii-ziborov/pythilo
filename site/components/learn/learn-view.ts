"use client";
import { useEffect, useSyncExternalStore } from "react";

/**
 * The Learn index filter: one track and a search. It is kept in the URL fragment
 * (#track=ml&q=async), so Back returns to the same list, a link can carry it, and
 * the server never sees it. The server and the first paint always show everything.
 */
export type LearnView = { track: string; query: string };

const EMPTY: LearnView = { track: "", query: "" };
let current = EMPTY;
/** The fragment `current` was read from or written to; null before the first read. */
let seen: string | null = null;
let timer: ReturnType<typeof setTimeout> | undefined;
const listeners = new Set<() => void>();

function parse(hash: string): LearnView | null {
  if (!/[#&](track|q)=/.test(hash)) return null;
  const params = new URLSearchParams(hash.slice(1));
  return { track: params.get("track") ?? "", query: params.get("q") ?? "" };
}

function format(view: LearnView) {
  const params = new URLSearchParams();
  if (view.track) params.set("track", view.track);
  if (view.query.trim()) params.set("q", view.query);
  const text = params.toString();
  return text ? `#${text}` : "";
}

function snapshot() {
  const hash = window.location.hash;
  if (hash !== seen) {
    seen = hash;
    // Another fragment (the skip link, a section anchor) leaves the filter as it is.
    current = parse(hash) ?? (hash ? current : EMPTY);
  }
  return current;
}

function write() {
  timer = undefined;
  const hash = format(current);
  if (hash === window.location.hash) { seen = hash; return; }
  try {
    window.history.replaceState(null, "", window.location.pathname + window.location.search + hash);
    seen = window.location.hash;
  } catch { /* Browsers limit how often the address may change. The list is filtered either way. */ }
}

/** Applies a filter now. `typing` delays the address update until the typing pauses. */
export function setLearnView(next: LearnView, typing = false) {
  current = next;
  for (const notify of listeners) notify();
  clearTimeout(timer);
  if (typing) timer = setTimeout(write, 200); else write();
}

/** Writes a delayed address update at once, before the page is left. */
export function flushLearnView() {
  if (timer !== undefined) { clearTimeout(timer); write(); }
}

/**
 * A fragment typed into the address bar makes a history entry the router knows nothing
 * about, and Back to such an entry would change the address but not the page. Replacing
 * the entry with itself hands it to the router.
 */
function adopt() {
  if (window.history.state !== null) return;
  try { window.history.replaceState(null, "", window.location.href); } catch { /* See write(). */ }
}

function subscribe(notify: () => void) {
  const changed = () => { adopt(); notify(); };
  listeners.add(notify);
  window.addEventListener("popstate", notify);
  window.addEventListener("hashchange", changed);
  return () => { listeners.delete(notify); window.removeEventListener("popstate", notify); window.removeEventListener("hashchange", changed); };
}

export function useLearnView(): LearnView {
  // Leaving the page forgets the filter, so the next visit reads the address again.
  useEffect(() => () => { clearTimeout(timer); timer = undefined; current = EMPTY; seen = null; }, []);
  return useSyncExternalStore(subscribe, snapshot, () => EMPTY);
}
