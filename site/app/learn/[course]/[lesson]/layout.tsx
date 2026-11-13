import type { ReactNode } from "react";
import { JsonLd } from "@/components/site/json-ld";
import { courseById, lessonById } from "@/lib/courses";
import { PUBLISHER, absoluteUrl, breadcrumbList, describe } from "@/lib/seo";

/** Structured data for a lesson: a free learning resource that is part of its course. */
export default async function LessonLayout({ children, params }: { children: ReactNode; params: Promise<{ course: string; lesson: string }> }) {
  const { course: courseId, lesson: lessonId } = await params;
  const course = courseById(courseId), lesson = course && lessonById(course, lessonId);
  if (!course || !lesson) return children;
  const path = `/learn/${course.id}/${lesson.id}/`;
  return <>
    <JsonLd data={{
      "@context": "https://schema.org", "@type": "LearningResource", "@id": absoluteUrl(path), url: absoluteUrl(path),
      name: lesson.title, description: describe(lesson.task, 300), learningResourceType: course.kind === "interview" ? "Practice problem" : "Lesson",
      inLanguage: "en", isAccessibleForFree: true, teaches: "Python", provider: PUBLISHER,
      isPartOf: { "@type": "Course", name: course.title, url: absoluteUrl(`/learn/${course.id}/`) },
    }} />
    <JsonLd data={breadcrumbList([["Learn", "/learn/"], [course.title, `/learn/${course.id}/`], [lesson.title, path]])} />
    {children}
  </>;
}
