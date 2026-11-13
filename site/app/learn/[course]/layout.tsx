import type { ReactNode } from "react";
import { JsonLd } from "@/components/site/json-ld";
import { courseById } from "@/lib/courses";
import { PUBLISHER, absoluteUrl, breadcrumbList, describe } from "@/lib/seo";

/** Structured data for a course: what it is, who provides it, and where it sits on the site. */
export default async function CourseLayout({ children, params }: { children: ReactNode; params: Promise<{ course: string }> }) {
  const course = courseById((await params).course);
  if (!course) return children;
  const url = absoluteUrl(`/learn/${course.id}/`);
  return <>
    <JsonLd data={{
      "@context": "https://schema.org", "@type": "Course", "@id": url, url,
      name: course.title, description: describe(course.summary, 300), inLanguage: "en", isAccessibleForFree: true,
      provider: PUBLISHER, numberOfLessons: course.lessons.length, teaches: "Python",
      offers: { "@type": "Offer", price: "0", priceCurrency: "USD", category: "Free" },
      hasCourseInstance: { "@type": "CourseInstance", courseMode: "Online", courseWorkload: `PT${Math.max(1, Math.round(course.lessons.reduce((total, lesson) => total + (lesson.minutes ?? 10), 0) / 60))}H` },
    }} />
    <JsonLd data={breadcrumbList([["Learn", "/learn/"], [course.title, `/learn/${course.id}/`]])} />
    {children}
  </>;
}
