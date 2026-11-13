import type { MetadataRoute } from "next";
import { allLabs } from "@/lib/browser-labs";
import { courses } from "@/lib/courses";
import { guidePages } from "@/lib/guide";
import { LEGAL_PAGES } from "@/lib/legal";
import { LEGAL_UPDATED, RELEASED } from "@/lib/site-info";
import { absolute, allPosts } from "./blog/_lib/posts";

type Entry = MetadataRoute.Sitemap[number];

/** Every indexable page once, with the canonical trailing-slash URL and a date where a real one exists. */
export default function sitemap(): MetadataRoute.Sitemap {
  const posts = allPosts();
  const newest = posts.reduce((latest, post) => (post.updated || post.date) > latest ? (post.updated || post.date) : latest, RELEASED);
  const page = (path: string, extra: Partial<Entry> = {}): Entry => ({ url: absolute(path), ...extra });
  const entries: Entry[] = [
    page("/", { lastModified: newest, changeFrequency: "weekly", priority: 1 }),
    page("/pricing/", { lastModified: RELEASED, priority: 0.8 }),
    page("/learn/", { changeFrequency: "weekly", priority: 0.9 }),
    page("/learn/senior/", { priority: 0.6 }),
    page("/labs/", { changeFrequency: "weekly", priority: 0.9 }),
    page("/playground/", { priority: 0.7 }),
    page("/ai/", { priority: 0.5 }),
    page("/guide/", { priority: 0.7 }),
    page("/blog/", { lastModified: newest, changeFrequency: "weekly", priority: 0.8 }),
    ...guidePages.map(item => page(`/guide/${item.slug}/`, { priority: 0.6 })),
    ...LEGAL_PAGES.map(([href]) => page(href, { lastModified: LEGAL_UPDATED, priority: 0.3 })),
    ...courses.map(course => page(`/learn/${course.id}/`, { priority: 0.8 })),
    ...courses.flatMap(course => course.lessons.map(lesson => page(`/learn/${course.id}/${lesson.id}/`, { priority: 0.6 }))),
    ...allLabs.map(lab => page(`/labs/${lab.id}/`, { priority: 0.7 })),
    ...posts.map(post => page(`/blog/${post.slug}/`, { lastModified: post.updated || post.date, priority: 0.7 })),
  ];
  const seen = new Set<string>();
  return entries.filter(entry => !seen.has(entry.url) && seen.add(entry.url));
}
