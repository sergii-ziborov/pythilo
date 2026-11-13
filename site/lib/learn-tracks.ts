import type { LearnIconName } from "./learn-icons";

/**
 * The Learn tracks: the grouping and order the app uses (LearnTrack in
 * Pythilo/UI/Learn/LearnViews.swift), with the icon and accent colour of each.
 * The order inside a track is the order to take its courses.
 */
export type LearnTrackId = "python" | "web" | "ml" | "ai" | "projects" | "interview" | "more";
export type LearnTrack = {
  id: LearnTrackId; title: string;
  /** For filter chips. */
  short: string;
  blurb: string; icon: LearnIconName; accent: string;
  /** Course ids in order. Empty for the two tracks filled by rule: interview practice and "More". */
  courses: readonly string[];
};

export const learnTracks: readonly LearnTrack[] = [
  { id: "python", title: "Python", short: "Python", icon: "code", accent: "#5AA9FF",
    blurb: "From first values to concurrency, transactions and resilient services.",
    courses: ["foundations", "deeper", "clean-code", "testing", "tools", "architecture", "async", "python-runtime", "python-systems"] },
  { id: "web", title: "Web, data & APIs", short: "Web & data", icon: "globe", accent: "#5FD6A8",
    blurb: "HTTP and APIs, validation, files and formats, and tests for real components.",
    courses: ["web", "data", "pydantic", "fastapi-httpx", "data-formats", "data-practice", "testing-practice", "reliable-python"] },
  { id: "ml", title: "Machine learning", short: "ML", icon: "brain", accent: "#B79CFF",
    blurb: "The mathematics, PyTorch, honest evaluation and the path to production.",
    courses: ["math", "ml", "ml-practice", "ml-evaluation", "ml-statistics", "ml-production", "ml-systems", "deep-learning-practice", "pytorch-training", "robust-ml-engineering"] },
  { id: "ai", title: "AI & transformers", short: "AI", icon: "sparkles", accent: "#FF7A70",
    blurb: "Language models from the inside, retrieval, tools, transformers and fine-tuning.",
    courses: ["llm", "ai", "ai-building-blocks", "ai-production", "ai-systems", "transformer-engineering", "finetuning-projects", "alignment-engineering"] },
  { id: "projects", title: "Algorithms & projects", short: "Algorithms", icon: "puzzle", accent: "#F2C25A",
    blurb: "Data structures, recurring patterns and larger projects that combine them.",
    courses: ["algorithms", "algorithm-patterns", "senior-projects"] },
  { id: "interview", title: "Interview practice", short: "Interview", icon: "stopwatch", accent: "#F58FC5",
    blurb: "Timed coding problems with hints, worked solutions and edge-case checks.",
    courses: [] },
  { id: "more", title: "More", short: "More", icon: "dots", accent: "#C9D2DC",
    blurb: "Courses outside the main tracks.",
    courses: [] },
];

/** A course's own icon. A course without one takes the icon of its track. */
const courseIcons: Record<string, LearnIconName> = {
  foundations: "terminal", deeper: "layers", "clean-code": "braces", testing: "checks", tools: "toolbox", architecture: "diagram", async: "split", "python-runtime": "cpu", "python-systems": "database",
  web: "server", data: "table", pydantic: "shield-check", "fastapi-httpx": "exchange", "data-formats": "file", "data-practice": "funnel", "testing-practice": "clipboard-check", "reliable-python": "refresh",
  math: "sigma", ml: "flame", "ml-practice": "scatter", "ml-evaluation": "bars", "ml-statistics": "distribution", "ml-production": "box", "ml-systems": "workflow", "deep-learning-practice": "loss-curve", "pytorch-training": "dumbbell", "robust-ml-engineering": "error-bars",
  llm: "tokens", ai: "chat", "ai-building-blocks": "blocks", "ai-production": "lock", "ai-systems": "nodes", "transformer-engineering": "attention", "finetuning-projects": "sliders", "alignment-engineering": "scale",
  algorithms: "tree", "algorithm-patterns": "steps", "senior-projects": "flag",
  interview: "stopwatch",
};

type CourseRef = { id: string; kind: string };
const track = (id: LearnTrackId) => learnTracks.find(item => item.id === id)!;

/** Interview practice is its own track; a course no track lists goes to "More". */
export function trackOf(course: CourseRef): LearnTrack {
  if (course.kind === "interview") return track("interview");
  return learnTracks.find(item => item.courses.includes(course.id)) ?? track("more");
}

export const courseIcon = (course: CourseRef): LearnIconName => courseIcons[course.id] ?? trackOf(course).icon;
export const courseIconIds = Object.keys(courseIcons);

/** Every course once, grouped by track in track order. Tracks without courses are left out. */
export function groupByTrack<T extends CourseRef>(courses: readonly T[]): { track: LearnTrack; courses: T[] }[] {
  return learnTracks.map(item => {
    const own = courses.filter(course => trackOf(course) === item);
    return { track: item, courses: item.courses.length ? item.courses.flatMap(id => own.filter(course => course.id === id)) : own };
  }).filter(group => group.courses.length > 0);
}

export type CourseOutline = { id: string; lessons: readonly string[] };
export type NextLesson = { course: string; lesson: string; index: number; started: boolean };

/**
 * The lesson to open next. With nothing passed, the first lesson of the first course.
 * Otherwise the first lesson not yet passed after the one passed most recently: later in
 * the same course, then earlier in it, then in the courses that follow. Null when all are passed.
 */
export function nextLesson(order: readonly CourseOutline[], progress: Record<string, { passed?: number } | undefined>): NextLesson | null {
  const done = (course: CourseOutline, lesson: string) => progress[`${course.id}/${lesson}`] != null;
  let last: { course: number; lesson: number; at: number } | null = null;
  order.forEach((course, courseIndex) => course.lessons.forEach((lesson, lessonIndex) => {
    if (!done(course, lesson)) return;
    const at = Number(progress[`${course.id}/${lesson}`]?.passed) || 0;
    if (!last || at >= last.at) last = { course: courseIndex, lesson: lessonIndex, at };
  }));
  const found = last as { course: number; lesson: number } | null;
  const first = (course: CourseOutline, from = 0): NextLesson | null => {
    for (let step = 0; step < course.lessons.length; step++) {
      const index = (from + step) % course.lessons.length;
      if (!done(course, course.lessons[index])) return { course: course.id, lesson: course.lessons[index], index, started: found !== null };
    }
    return null;
  };
  if (!found) return order.map(course => first(course)).find(Boolean) ?? null;
  for (let step = 0; step < order.length; step++) {
    const course = order[(found.course + step) % order.length];
    const next = first(course, step === 0 ? found.lesson + 1 : 0);
    if (next) return next;
  }
  return null;
}
