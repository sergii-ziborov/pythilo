"use client";
import Link from "next/link";
import { forgetAll, useProgress } from "./progress";

export type LessonLink = { course: string; id: string; title: string; meta?: string };

/** Lesson rows with a check for those passed in this browser. */
export function LessonLinks({ lessons }: { lessons: LessonLink[] }) {
  const progress = useProgress();
  return <ol className="lesson-list">{lessons.map((lesson, index) => {
    const done = !!progress?.[`${lesson.course}/${lesson.id}`];
    return <li key={lesson.id}><Link href={`/learn/${lesson.course}/${lesson.id}/`}>
      <span className={`lesson-number${done ? " done" : ""}`} aria-label={done ? "Passed" : undefined}>{done ? "✓" : index + 1}</span>{lesson.title}{lesson.meta ? <span className="lesson-meta">{lesson.meta}</span> : null}
    </Link></li>;
  })}</ol>;
}

export function ProgressNote() {
  const progress = useProgress(), count = progress ? Object.keys(progress).length : 0;
  return <p className="storage-note">Progress and your code are kept in this browser only{count ? ` · ${count} lesson${count === 1 ? "" : "s"} passed here · ` : "."}{count ? <button type="button" className="link-button" onClick={() => { if (window.confirm("Forget progress and lesson code kept in this browser?")) forgetAll(); }}>Forget</button> : null}</p>;
}
