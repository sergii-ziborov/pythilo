import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { SiteFooter, SiteHeader } from "@/components/site-header";
import { LessonLinks, ProgressNote } from "@/components/learn/lesson-links";
import { courseById, courseLabel, courses } from "@/lib/courses";

export const dynamicParams = false;
export function generateStaticParams() { return courses.map(course => ({ course: course.id })); }

export async function generateMetadata({ params }: { params: Promise<{ course: string }> }): Promise<Metadata> {
  const course = courseById((await params).course);
  return course ? { title: course.title, description: course.summary } : {};
}

export default async function CoursePage({ params }: { params: Promise<{ course: string }> }) {
  const course = courseById((await params).course);
  if (!course) notFound();
  return <>
    <SiteHeader current="learn" />
    <main className="page">
      <section className="course-section">
        <nav aria-label="Breadcrumb" className="storage-note"><Link href="/learn/">Learn</Link> / {course.title}</nav>
        <div className={`label${course.kind === "interview" ? " practice" : ""}`}>{courseLabel(course)}</div>
        <h1 style={{ fontSize: 32, lineHeight: "38px", margin: 0 }}>{course.title}</h1>
        <p>{course.summary}</p>
        <ProgressNote />
        <LessonLinks lessons={course.lessons.map(lesson => ({ course: course.id, id: lesson.id, title: lesson.title, appRequired: lesson.missing.length > 0, ...(lesson.level ? { meta: `${lesson.level} · ${lesson.minutes} min` } : {}) }))} />
      </section>
    </main>
    <SiteFooter />
  </>;
}
