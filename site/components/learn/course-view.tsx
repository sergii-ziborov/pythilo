"use client";
import Link from "next/link";
import { useMemo } from "react";
import type { CourseItem } from "@/lib/learn-catalog";
import { nextLesson } from "@/lib/learn-tracks";
import { LearnIcon } from "./icon";
import { LessonLinks, passedCount, ProgressBar, ProgressNote } from "./lesson-links";
import { useProgress } from "./progress";

/** A course page below its header: progress, the lesson to open next, and the numbered lessons. */
export function CourseView({ course, after }: { course: CourseItem; after?: { id: string; title: string } }) {
  const progress = useProgress();
  const total = course.lessons.length, done = passedCount(progress, course.id, course.lessons), unit = course.unit, Unit = unit === "task" ? "Task" : "Lesson";
  const next = useMemo(() => nextLesson([{ id: course.id, lessons: course.lessons.map(lesson => lesson.id) }], progress ?? {}), [course, progress]);
  return <>
    <section className="learn-course-status" aria-label="Your progress">
      <div className="learn-course-progress">
        <ProgressBar done={done} total={total} />
        <p><strong>{done}</strong> of {total} {unit}s passed{next?.started ? <> · next: {course.lessons[next.index].title}</> : null}</p>
      </div>
      {next
        ? <Link className="big-button primary" href={`/learn/${course.id}/${next.lesson}/`}><LearnIcon name="play" size={18} /><span>{next.started ? `Continue: ${Unit} ${next.index + 1}` : `Start ${unit} 1`}</span></Link>
        : after ? <Link className="big-button primary" href={`/learn/${after.id}/`}><span>Next: {after.title}</span><LearnIcon name="arrow-right" size={18} /></Link> : null}
    </section>
    <section className="learn-course-lessons" aria-labelledby="course-lessons">
      <h2 id="course-lessons" className="learn-section-title">{Unit}s</h2>
      <ProgressNote />
      <LessonLinks rows course={course.id} lessons={course.lessons} progress={progress} />
    </section>
  </>;
}
