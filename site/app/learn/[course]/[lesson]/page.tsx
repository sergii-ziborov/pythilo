import { describe } from "@/lib/seo";
import type { Metadata } from "next";
import Link from "next/link";
import { allLabs } from "@/lib/browser-labs";
import { notFound } from "next/navigation";
import { Inline, Markdown } from "@/components/markdown";
import { PythonCode } from "@/components/python-code";
import { ExampleBlock, LessonWorkspace } from "@/components/learn/lesson-workspace";
import { courseById, courses, lessonById, packageName } from "@/lib/courses";
import "../../learn.css";

export const dynamicParams = false;
export function generateStaticParams() { return courses.flatMap(course => course.lessons.map(lesson => ({ course: course.id, lesson: lesson.id }))); }

type Params = { params: Promise<{ course: string; lesson: string }> };
export async function generateMetadata({ params }: Params): Promise<Metadata> {
  const { course: courseId, lesson: lessonId } = await params, course = courseById(courseId), lesson = course && lessonById(course, lessonId);
  return lesson ? { title: `${lesson.title}: ${course.title}`, description: describe(lesson.task) } : {};
}

export default async function LessonPage({ params }: Params) {
  const { course: courseId, lesson: lessonId } = await params;
  const course = courseById(courseId), lesson = course && lessonById(course, lessonId);
  if (!course || !lesson) notFound();
  const index = course.lessons.indexOf(lesson), next = course.lessons[index + 1];
  const project = ({'project-torchbertfull':'full','project-torchbertlora':'lora','project-torchbertdomain':'domain','project-torchbertcompare':'compare','project-torchbertresume':'resume','project-torchbertmerge':'merge'} as Record<string,string>)[lesson.id];
  let example = 0;
  // Python blocks get a Run button; the rest of the reading is static.
  const code = (source: string, language: string) => language === "python" || language === "py"
    ? <ExampleBlock code={source} index={example++}><PythonCode code={source} /></ExampleBlock>
    : <pre className="code-block"><code>{source}</code></pre>;
  const position = course.kind === "interview" ? `${lesson.level ?? ""}${lesson.minutes ? ` · ${lesson.minutes} min` : ""} · Task ${index + 1} of ${course.lessons.length}` : `Lesson ${index + 1} of ${course.lessons.length}`;
  return <LessonWorkspace
    practice={<>{allLabs.filter(lab => lab.lessons?.includes(lesson.id)).map(lab => <p key={lab.id}><Link className="pill-button" href={`/labs/${lab.id}/`}>Practice in Lab: {lab.title} →</Link></p>)}{project && <p><a className="pill-button" href={`/projects/bert-${project}.zip`} download>Download complete project source →</a></p>}</>}
    course={course.id} lesson={lesson.id} breadcrumb={{ courseTitle: course.title, lessonTitle: lesson.title }} position={position.replace(/^ · /, "")}
    sections={lesson.sections.map(section => ({ chip: section.chip, title: section.title, content: <Markdown source={section.markdown} code={code} /> }))}
    task={<Inline text={lesson.task} />} starter={lesson.starter} checks={lesson.checks}
    hints={lesson.hints.map((hint, hintIndex) => <Inline key={hintIndex} text={hint} />)} explanation={<Markdown source={lesson.explanation} code={code} />}
    next={next ? { href: `/learn/${course.id}/${next.id}/`, title: next.title } : null}
    missing={lesson.missing.map(packageName)} packages={lesson.packages} />;
}
