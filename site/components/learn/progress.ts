"use client";
import { useEffect, useState } from "react";

// Progress and lesson drafts live in this browser's localStorage only.
const PROGRESS_KEY = "pythilo.learn.progress.v1";
const draftKey = (course: string, lesson: string) => `pythilo.learn.draft.v1.${course}/${lesson}`;
type Progress = Record<string, { passed: number }>;

export function readProgress(): Progress {
  try { const value = JSON.parse(localStorage.getItem(PROGRESS_KEY) ?? "{}"); return value && typeof value === "object" && !Array.isArray(value) ? value : {}; } catch { return {}; }
}
export function markPassed(course: string, lesson: string) {
  try { const progress = readProgress(); progress[`${course}/${lesson}`] = { passed: Date.now() }; localStorage.setItem(PROGRESS_KEY, JSON.stringify(progress)); window.dispatchEvent(new Event("pythilo-progress")); } catch {}
}
export function readDraft(course: string, lesson: string): string | null {
  try { return localStorage.getItem(draftKey(course, lesson)); } catch { return null; }
}
export function writeDraft(course: string, lesson: string, code: string | null) {
  try { if (code === null) localStorage.removeItem(draftKey(course, lesson)); else localStorage.setItem(draftKey(course, lesson), code); } catch {}
}
export function forgetAll() {
  try { for (const key of Object.keys(localStorage)) if (key === PROGRESS_KEY || key.startsWith("pythilo.learn.draft.v1.")) localStorage.removeItem(key); window.dispatchEvent(new Event("pythilo-progress")); } catch {}
}

export function useProgress(): Progress | null {
  const [progress, setProgress] = useState<Progress | null>(null);
  useEffect(() => {
    const update = () => setProgress(readProgress());
    update(); window.addEventListener("pythilo-progress", update); window.addEventListener("storage", update);
    return () => { window.removeEventListener("pythilo-progress", update); window.removeEventListener("storage", update); };
  }, []);
  return progress;
}
