import "server-only";
import { courses, type Course } from "@/lib/courses";
import type { LearnIconName } from "@/lib/learn-icons";
import { courseIcon, groupByTrack, trackOf, type LearnTrack } from "@/lib/learn-tracks";

/** What the Learn index and course pages show of a lesson, a course and a track. */
export type LessonItem = { id: string; title: string; app?: true; meta?: string };
export type CourseItem = {
  id: string; title: string; summary: string; unit: "lesson" | "task"; icon: LearnIconName; lessons: LessonItem[];
  /** Lessons that run only in the app. */
  appCount: number;
  level?: string; time?: string;
};
export type TrackItem = Pick<LearnTrack, "id" | "title" | "short" | "blurb" | "icon" | "accent"> & { courses: CourseItem[] };

const hours = (minutes: number) => minutes >= 90 ? `${Math.round(minutes / 60)} h` : `${minutes} min`;

export function courseItem(course: Course): CourseItem {
  const levels = [...new Set(course.lessons.flatMap(lesson => lesson.level ? [lesson.level] : []))];
  const minutes = course.lessons.reduce((total, lesson) => total + (lesson.minutes ?? 0), 0);
  return {
    id: course.id, title: course.title, summary: course.summary, unit: course.kind === "interview" ? "task" : "lesson", icon: courseIcon(course),
    lessons: course.lessons.map(lesson => ({
      id: lesson.id, title: lesson.title,
      ...(lesson.missing.length ? { app: true as const } : {}),
      ...(lesson.level ? { meta: lesson.minutes ? `${lesson.level} · ${lesson.minutes} min` : lesson.level } : {}),
    })),
    appCount: course.lessons.filter(lesson => lesson.missing.length > 0).length,
    ...(levels.length ? { level: levels.length > 1 ? `${levels[0]} to ${levels[levels.length - 1]}` : levels[0] } : {}),
    ...(minutes ? { time: hours(minutes) } : {}),
  };
}

const trackItem = ({ id, title, short, blurb, icon, accent }: LearnTrack, items: CourseItem[]): TrackItem => ({ id, title, short, blurb, icon, accent, courses: items });

/** Every course, grouped by track in the order the Learn index shows them. */
export const learnCatalog = (): TrackItem[] => groupByTrack(courses).map(group => trackItem(group.track, group.courses.map(courseItem)));

/** A course's track, its place in it and its neighbours there. */
export function coursePlace(course: Course) {
  const track = trackOf(course), siblings = groupByTrack(courses).find(group => group.track === track)?.courses ?? [course], index = siblings.indexOf(course);
  return { track, index, count: siblings.length, previous: siblings[index - 1], next: siblings[index + 1] };
}
