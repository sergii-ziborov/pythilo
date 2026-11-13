import type { Metadata } from "next";
import Link from "next/link";
import { APP_URL, SiteFooter, SiteHeader } from "@/components/site-header";
import { LearnIcon } from "@/components/learn/icon";
import { LearnBrowser } from "@/components/learn/learn-browser";
import { ProgressNote } from "@/components/learn/lesson-links";
import { courses } from "@/lib/courses";
import { learnCatalog } from "@/lib/learn-catalog";
import { BROWSER_RUNTIME } from "@/lib/python-runtime";
import { browserLabs } from "@/lib/browser-labs";
import "./learn.css";

export const metadata: Metadata = { title: "Learn Python", description: "Python lessons that run in your browser: read, write code, run it and check it, with no account." };

export default function LearnPage() {
  const paths = courses.filter(course => course.kind !== "interview"), practice = courses.filter(course => course.kind === "interview");
  const count = (list: typeof courses) => list.reduce((total, course) => total + course.lessons.length, 0);
  const appCount = courses.flatMap(course => course.lessons).filter(lesson => lesson.missing.length > 0).length;
  return <>
    <SiteHeader current="learn" />
    <main className="page learn-page">
      {/* Search and filters need JavaScript. Without it every track and lesson list is still on the page. */}
      <noscript><style>{".learn-tools { display: none; }"}</style></noscript>
      <LearnBrowser tracks={learnCatalog()} intro={<>
        <h1>Learn Python</h1>
        <p>Read every lesson here and run browser-compatible exercises with {BROWSER_RUNTIME}. Read a part, try the examples, then write the solution and check it with the same checks the app uses. Exercises that need PyTorch, threads or unavailable packages are marked App required.</p>
        <ul className="learn-facts" role="list">
          <li><strong>{paths.length}</strong> courses</li>
          <li><strong>{count(paths)}</strong> lessons</li>
          {practice.length ? <li><strong>{count(practice)}</strong> interview tasks</li> : null}
        </ul>
        <p className="learn-also">
          <Link href="/learn/senior/" className="pill-button"><LearnIcon name="route" size={18} />Senior paths</Link>
          <Link href="/labs/" className="pill-button"><LearnIcon name="flask" size={18} />Labs</Link>
        </p>
        <ProgressNote />
      </>} />

      <section className="learn-more" aria-labelledby="learn-more-title">
        <h2 id="learn-more-title">Go further</h2>
        <div className="learn-more-grid">
          <Link href="/learn/senior/" className="learn-more-card">
            <span className="learn-icon"><LearnIcon name="route" /></span>
            <strong>Senior Python, ML and AI</strong>
            <span>Three practice paths through the advanced courses, with integration projects and review criteria.</span>
            <span className="learn-more-link">Paths and review criteria <LearnIcon name="arrow-right" size={16} /></span>
          </Link>
          <Link href="/labs/" className="learn-more-card">
            <span className="learn-icon"><LearnIcon name="flask" /></span>
            <strong>Interactive Labs</strong>
            <span>Put the patterns to work in {browserLabs.length} interactive browser labs: write code, replay each step and check it.</span>
            <span className="learn-more-link">Open Labs <LearnIcon name="arrow-right" size={16} /></span>
          </Link>
          <a href={APP_URL} className="learn-more-card">
            <span className="learn-icon"><LearnIcon name="phone" /></span>
            <strong>App required lessons</strong>
            <span>{appCount} lessons use PyTorch, threads or packages a browser cannot run. They run in Pythilo on iPhone and iPad.</span>
            <span className="learn-more-link">Get the app <LearnIcon name="arrow-right" size={16} /></span>
          </a>
        </div>
      </section>
    </main>
    <SiteFooter />
  </>;
}
