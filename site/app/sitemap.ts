import type { MetadataRoute } from "next";
import { allLabs } from "@/lib/browser-labs";
import { courses } from "@/lib/courses";
import { guidePages } from "@/lib/guide";
import { LEGAL_PAGES } from "@/lib/legal";
import { absolute, allPosts } from "./blog/_lib/posts";

export default function sitemap(): MetadataRoute.Sitemap {
  const paths = new Set([
    "/", "/learn/", "/learn/senior/", "/labs/",
    ...allLabs.map(lab => `/labs/${lab.id}/`), "/playground/", "/ai/", "/guide/", "/pricing/", "/blog/",
    ...LEGAL_PAGES.map(([href]) => href),
    ...guidePages.map(page => `/guide/${page.slug}/`),
    ...courses.flatMap(course => [`/learn/${course.id}/`, ...course.lessons.map(lesson => `/learn/${course.id}/${lesson.id}/`)]),
  ]);
  return [
    ...[...paths].map(path => ({ url: absolute(path) })),
    ...allPosts().map(post => ({ url: absolute(`/blog/${post.slug}/`), lastModified: post.updated || post.date })),
  ];
}
