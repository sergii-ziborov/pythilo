import type { Metadata } from "next";
import Link from "next/link";
import { SiteFooter, SiteHeader } from "@/components/site-header";
import { LessonLinks, ProgressNote } from "@/components/learn/lesson-links";
import { courseLabel, courses } from "@/lib/courses";
import { BROWSER_RUNTIME } from "@/lib/python-runtime";
import { browserLabs } from "@/lib/browser-labs";

export const metadata: Metadata = { title: "Learn Python", description: "Python lessons that run in your browser: read, write code, run it and check it, with no account." };

export default function LearnPage() {
  const newCourses = courses.filter(course => course.order >= 25);
  const newLessonCount = newCourses.reduce((total, course) => total + course.lessons.length, 0);
  return <>
    <SiteHeader current="learn" />
    <main className="page">
      <section className="learn-intro">
        <h1>Learn Python</h1>
        <p>Read every lesson here and run browser-compatible exercises with {BROWSER_RUNTIME}. Read a part, try the examples, then write the solution and check it with the same checks the app uses. Exercises that need PyTorch, threads or unavailable packages are marked App required.</p>
        <ProgressNote />
      </section>
      <section className="course-section" aria-labelledby="new-courses"><div className="label">NEW · {newLessonCount} LESSONS</div><h2 id="new-courses">Practice Python, ML and AI engineering</h2><p>{newCourses.length} advanced courses cover concurrency, transactions, statistical evaluation, ML operations, AI boundaries, PyTorch correctness and integration projects. Train models, audit held-out data boundaries, build authorized retrieval and review the behavior your code proves.</p><p><Link href="/learn/senior/">Senior Python, ML and AI: paths and review criteria →</Link></p><div className="new-course-links">{newCourses.map(course=><Link key={course.id} href={`/learn/${course.id}/`}><strong>{course.title}</strong><span>{course.summary}</span></Link>)}</div><p><Link href="/labs/">Put the patterns to work in {browserLabs.length} interactive browser labs →</Link></p></section>
      {courses.map(course => <section key={course.id} className="course-section" aria-labelledby={`course-${course.id}`}>
        <div className={`label${course.kind === "interview" ? " practice" : ""}`}>{courseLabel(course)}</div>
        <h2 id={`course-${course.id}`}><Link href={`/learn/${course.id}/`} style={{ color: "inherit" }}>{course.title}</Link></h2>
        <p>{course.summary}</p>
        <LessonLinks lessons={course.lessons.map(lesson => ({ course: course.id, id: lesson.id, title: lesson.title, appRequired: lesson.missing.length > 0, ...(lesson.level ? { meta: `${lesson.level} · ${lesson.minutes} min` } : {}) }))} />
      </section>)}
    </main>
    <SiteFooter />
  </>;
}
