import { describe } from "@/lib/seo";
import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { SiteFooter, SiteHeader } from "@/components/site-header";
import { CourseView } from "@/components/learn/course-view";
import { accentStyle, LearnIcon } from "@/components/learn/icon";
import { courseById, courseLabel, courses } from "@/lib/courses";
import { courseItem, coursePlace } from "@/lib/learn-catalog";
import { courseIcon } from "@/lib/learn-tracks";
import "../learn.css";

export const dynamicParams = false;
export function generateStaticParams() { return courses.map(course => ({ course: course.id })); }

export async function generateMetadata({ params }: { params: Promise<{ course: string }> }): Promise<Metadata> {
  const course = courseById((await params).course);
  return course ? { title: `${course.title}: Python course`, description: describe(`${course.title}: ${course.lessons.length} ${course.kind === "interview" ? "tasks" : "lessons"}. ${course.summary}`) } : {};
}

export default async function CoursePage({ params }: { params: Promise<{ course: string }> }) {
  const course = courseById((await params).course);
  if (!course) notFound();
  const item = courseItem(course), { track, index, count, previous, next } = coursePlace(course), units = `${item.unit}s`;
  return <>
    <SiteHeader current="learn" />
    <main className="page learn-page" style={accentStyle(track.accent)}>
      <header className="learn-course-head">
        <nav aria-label="Breadcrumb"><ol className="learn-crumbs" role="list">
          <li><Link href="/learn/">Learn</Link></li>
          {count > 1 ? <li><Link href={`/learn/#track-${track.id}`}>{track.title}</Link></li> : null}
          <li aria-current="page">{course.title}</li>
        </ol></nav>
        <div className="learn-course-title">
          <span className="learn-icon large"><LearnIcon name={item.icon} size={30} /></span>
          <div>
            <p className="label">{course.kind === "interview" ? courseLabel(course) : `${track.title} · Course ${index + 1} of ${count}`}</p>
            <h1>{course.title}</h1>
          </div>
        </div>
        <p className="learn-course-summary">{course.summary}</p>
        <ul className="learn-course-facts" role="list">
          <li>{item.lessons.length} {units}</li>
          {item.level ? <li>{item.level}</li> : null}
          {item.time ? <li><LearnIcon name="clock" size={15} />{item.time}</li> : null}
          {item.appCount ? <li className="learn-app" title={`${item.appCount} of ${item.lessons.length} ${units} run only in the Pythilo app`}><LearnIcon name="phone" size={15} />App required{item.appCount < item.lessons.length ? ` · ${item.appCount}` : ""}</li> : null}
        </ul>
      </header>
      <CourseView course={item} after={next ? { id: next.id, title: next.title } : undefined} />
      {previous || next ? <nav className="learn-pager" aria-label={`More in ${track.title}`}>
        {previous ? <Link href={`/learn/${previous.id}/`} className="previous"><LearnIcon name="chevron-left" size={20} /><span className="learn-icon"><LearnIcon name={courseIcon(previous)} size={22} /></span><span><small>Previous course</small><strong>{previous.title}</strong></span></Link> : null}
        {next ? <Link href={`/learn/${next.id}/`} className="next"><span><small>Next course</small><strong>{next.title}</strong></span><span className="learn-icon"><LearnIcon name={courseIcon(next)} size={22} /></span><LearnIcon name="chevron-right" size={20} /></Link> : null}
      </nav> : null}
      <p className="learn-back"><Link href="/learn/"><LearnIcon name="chevron-left" size={18} />All courses</Link></p>
    </main>
    <SiteFooter />
  </>;
}
