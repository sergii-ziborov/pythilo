import "server-only";
import snapshot from "@/content/courses.json";

export type Section = { title: string; chip: string; markdown: string };
export type Check = { name: string; code: string };
export type Lesson = {
  id: string; title: string; level?: string; minutes?: number; sections: Section[]; task: string; starter: string; solution: string;
  checks: Check[]; hints: string[]; explanation: string; imports: string[]; packages: string[]; missing: string[];
};
export type Course = { id: string; title: string; summary: string; kind: string; order: number; lessons: Lesson[] };

/** Built by scripts/prepare-assets.mjs from Pythilo/Resources/Courses at build time. */
export const courses = snapshot.courses as Course[];

export const courseById = (id: string) => courses.find(course => course.id === id);
export const lessonById = (course: Course, id: string) => course.lessons.find(lesson => lesson.id === id);
export const courseLabel = (course: Course) => course.kind === "interview" ? `Practice · ${course.lessons.length} tasks` : `${pathNumber(course)} · ${course.lessons.length} lessons`;
export const pathNumber = (course: Course) => courses.filter(item => item.kind !== "interview").indexOf(course) + 1;

/** Package names as people write them, for notices. */
export const packageName = (name: string) => ({ flask: "Flask", numpy: "NumPy", django: "Django", pandas: "pandas", requests: "Requests" } as Record<string, string>)[name] ?? name;
