"use client";
import Link from "next/link";
import type { ReactNode } from "react";
import type { LessonItem } from "@/lib/learn-catalog";
import { LearnIcon } from "./icon";
import { forgetAll, useProgress } from "./progress";

export type Progress = ReturnType<typeof useProgress>;

export const passedCount = (progress: Progress, course: string, lessons: LessonItem[]) => progress ? lessons.reduce((count, lesson) => count + (progress[`${course}/${lesson.id}`] ? 1 : 0), 0) : 0;

/** Marks the parts of a title that match the search words. */
export function Highlight({ text, terms }: { text: string; terms?: string[] }): ReactNode {
  if (!terms?.length) return text;
  const pattern = new RegExp(`(${terms.map(term => term.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")).join("|")})`, "gi");
  return text.split(pattern).map((part, index) => index % 2 ? <mark key={index}>{part}</mark> : part);
}

/** A thin bar for lessons passed out of a total. The text beside it carries the numbers. */
export function ProgressBar({ done, total }: { done: number; total: number }) {
  return <span className={`learn-bar${done >= total && total > 0 ? " complete" : ""}`} aria-hidden="true"><span style={{ width: `${total ? Math.min(100, done / total * 100) : 0}%` }} /></span>;
}

/**
 * Numbered lesson rows with a check on those passed in this browser. `only` limits the
 * rows to some lessons (a search) while each keeps its number in the course.
 */
export function LessonLinks({ course, lessons, progress, only, terms, rows }: { course: string; lessons: LessonItem[]; progress: Progress; only?: LessonItem[]; terms?: string[]; rows?: boolean }) {
  return <ol className={`learn-lesson-list${rows ? " rows" : ""}`}>{(only ?? lessons).map((lesson, index) => {
    const number = only ? lessons.indexOf(lesson) + 1 : index + 1, done = !!progress?.[`${course}/${lesson.id}`];
    return <li key={lesson.id} value={only ? number : undefined}><Link href={`/learn/${course}/${lesson.id}/`} className={`learn-lesson${done ? " done" : ""}`}>
      <span className="learn-lesson-number" aria-hidden="true">{done ? <LearnIcon name="check" size={15} /> : number}</span>
      <span className="learn-lesson-body">
        <span className="learn-lesson-title">{done ? <span className="visually-hidden">Passed: </span> : null}<Highlight text={lesson.title} terms={terms} /></span>
        {lesson.app || lesson.meta ? <span className="learn-lesson-meta">
          {lesson.meta ? <span>{lesson.meta}</span> : null}
          {lesson.app ? <span className="learn-app"><LearnIcon name="phone" size={13} />App required</span> : null}
        </span> : null}
      </span>
    </Link></li>;
  })}</ol>;
}

export function ProgressNote() {
  const progress = useProgress(), count = progress ? Object.keys(progress).length : 0;
  return <p className="storage-note">Progress and your code are kept in this browser only{count ? ` · ${count} lesson${count === 1 ? "" : "s"} passed here · ` : "."}{count ? <button type="button" className="link-button" onClick={() => { if (window.confirm("Forget progress and lesson code kept in this browser?")) forgetAll(); }}>Forget</button> : null}</p>;
}
