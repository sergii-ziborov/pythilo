import type { Metadata } from 'next';
import Link from 'next/link';
import { SiteFooter, SiteHeader } from '@/components/site-header';
import { courses } from '@/lib/courses';
import { seniorPaths } from '@/lib/senior-paths';
import { browserLabs } from '@/lib/browser-labs';
import '../learn.css';

export const metadata: Metadata = { title: 'Senior Python, ML and AI practice paths', description: 'Three advanced practice paths with runnable lessons, linked labs, integration projects and explicit production experience requirements.' };
const byId = (id: string) => courses.find(course => course.id === id)!;
export default function SeniorPathsPage() {
  const advanced = courses.filter(course => course.order >= 25);
  const projects = advanced.flatMap(course => course.lessons).filter(lesson => lesson.title.startsWith('Project:'));
  const labs = browserLabs.filter(lab => lab.lessons?.some(id => advanced.some(course => course.lessons.some(lesson => lesson.id === id))));
  return <><SiteHeader current="learn" /><main className="page">
    <section className="learn-intro"><div className="label">ADVANCED PRACTICE</div><h1>Build evidence for senior work</h1><p>{advanced.reduce((n, course) => n + course.lessons.length, 0)} advanced lessons (including {projects.length} integration projects), plus {labs.length} companion Labs extend the Python, mathematics, ML and LLM foundations. Examples execute with real Python. PyTorch exercises run in the app; compatible lessons and Labs run here.</p><p>Completing a course does not certify seniority. Use the checks to establish concrete behavior, then explain the design and its limits. The production work below requires real services, datasets, model providers or hardware and is not claimed to have run on an iPhone.</p></section>
    {seniorPaths.map(path => <section key={path.id} className="course-section" id={path.id}>
      <h2>{path.title}</h2><p>{path.outcome}</p>
      <h3>Foundation</h3><p>{path.prerequisites.map(id => <Link key={id} href={`/learn/${id}/`} style={{ marginRight: 16 }}>{byId(id).title}</Link>)}</p>
      <h3>Advanced study</h3><ul>{path.courses.map(id => <li key={id}><Link href={`/learn/${id}/`}>{byId(id).title}</Link> — {byId(id).lessons.length} lessons</li>)}</ul>
      <h3>Integration projects</h3><ul>{path.projects.map(id => { const course = courses.find(item => item.lessons.some(lesson => lesson.id === id))!, lesson = course.lessons.find(item => item.id === id)!; return <li key={id}><Link href={`/learn/${course.id}/${id}/`}>{lesson.title}</Link></li>; })}</ul>
      <h3>Review your evidence</h3><ul>{path.review.map(item => <li key={item}>{item}</li>)}</ul>
      <h3>Required production practice</h3><ul>{path.fieldwork.map(item => <li key={item}>{item}</li>)}</ul>
    </section>)}
    <section className="course-section"><h2>Move between a lesson and its Lab</h2><p>The {labs.length} companion Labs replay your own implementation, compare it with independent checks and link back to the corresponding lesson. Larger projects replay their main orchestration function; helper computations execute and are checked separately. The iOS app provides the same links in both directions. A passing trace proves the listed cases, not arbitrary production behavior.</p><div className="new-course-links">{labs.map(lab => <Link key={lab.id} href={`/labs/${lab.id}/`}><strong>{lab.title}</strong><span>{lab.section}</span></Link>)}</div></section>
    <p><Link href="/learn/">Browse every course →</Link></p>
  </main><SiteFooter /></>;
}
