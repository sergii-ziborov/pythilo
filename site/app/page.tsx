import Link from "next/link";
import { SiteFooter, SiteHeader } from "@/components/site-header";
import { PythonCode } from "@/components/python-code";
import { courseLabel, courses } from "@/lib/courses";
import { PYODIDE_VERSION } from "@/lib/python-runtime";

const sample = `def running_total():
    total = 0
    def add(n):
        nonlocal total
        total += n
        return total
    return add

add = running_total()
print(add(5), add(3))`;

export default function Home() {
  const first = courses[0], lesson = first?.lessons[0];
  return <>
    <SiteHeader />
    <main className="page">
      <section className="hero">
        <div>
          <h1>Learn Python and run it right here</h1>
          <p>Lessons and a playground that run Python in your browser, with no account. The iPhone and iPad app opens the same projects and runs them with full CPython, offline.</p>
          <div className="hero-actions">
            <Link href={lesson ? `/learn/${first.id}/${lesson.id}/` : "/learn/"} className="big-button primary">Start the first lesson<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.4" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><path d="M5 12h14M13 6l6 6-6 6" /></svg></Link>
            <Link href="/playground/" className="big-button">Open the playground</Link>
          </div>
        </div>
        <figure className="code-figure">
          <div className="code-figure-bar"><span className="file-badge python" aria-hidden="true">py</span>main.py<span>Runs in this browser</span></div>
          <PythonCode code={sample} />
          <div className="code-figure-output">5 8<div>Ran in this browser · Pyodide {PYODIDE_VERSION} · exit 0</div></div>
        </figure>
      </section>
      <section aria-labelledby="courses-title">
        <div className="section-heading"><h2 id="courses-title">The path</h2><Link href="/learn/">All lessons</Link></div>
        <div className="course-grid">
          {courses.map(course => <Link key={course.id} href={`/learn/${course.id}/`} className="course-card">
            <span className={`label${course.kind === "interview" ? " practice" : ""}`}>{courseLabel(course)}</span>
            <strong>{course.kind === "interview" ? "Interview tasks" : course.title}</strong>
            <span>{course.summary}</span>
          </Link>)}
        </div>
      </section>
      <section className="callout-band">
        <div><h2>Work on one project together</h2><p>Share a room by link with a person or an AI client. Edits merge live, and every run says where it ran: this browser, or an iPhone that agreed to run it.</p></div>
        <Link href="/playground/" className="big-button">Open a room</Link>
      </section>
      <section id="app" className="callout-band">
        <div><h2>Pythilo for iPhone and iPad</h2><p>A Python IDE and the same course, with full CPython that runs offline. It opens rooms from this site and can run their code when you allow it.</p></div>
      </section>
    </main>
    <SiteFooter />
  </>;
}
