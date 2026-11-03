import type { Metadata } from "next";
import Link from "next/link";
import { SiteFooter, SiteHeader } from "@/components/site-header";
import { LessonLinks, ProgressNote } from "@/components/learn/lesson-links";
import { courseLabel, courses } from "@/lib/courses";
import { BROWSER_RUNTIME } from "@/lib/python-runtime";

export const metadata: Metadata = { title: "Learn Python", description: "Python lessons that run in your browser: read, write code, run it and check it, with no account." };

export default function LearnPage() {
  return <>
    <SiteHeader current="learn" />
    <main className="page">
      <section className="learn-intro">
        <h1>Learn Python</h1>
        <p>Every lesson runs in this browser with {BROWSER_RUNTIME}. Read a part, try the examples, then write the solution and check it with the same checks the app uses.</p>
        <ProgressNote />
      </section>
      {courses.map(course => <section key={course.id} className="course-section" aria-labelledby={`course-${course.id}`}>
        <div className={`label${course.kind === "interview" ? " practice" : ""}`}>{courseLabel(course)}</div>
        <h2 id={`course-${course.id}`}><Link href={`/learn/${course.id}/`} style={{ color: "inherit" }}>{course.title}</Link></h2>
        <p>{course.summary}</p>
        <LessonLinks lessons={course.lessons.map(lesson => ({ course: course.id, id: lesson.id, title: lesson.title, ...(lesson.level ? { meta: `${lesson.level} · ${lesson.minutes} min` } : {}) }))} />
      </section>)}
    </main>
    <SiteFooter />
  </>;
}
