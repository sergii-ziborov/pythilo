"use client";
import Link from "next/link";
import { useDeferredValue, useEffect, useMemo, useRef, useState, type ReactNode } from "react";
import type { CourseItem, LessonItem, TrackItem } from "@/lib/learn-catalog";
import type { LearnIconName } from "@/lib/learn-icons";
import { nextLesson } from "@/lib/learn-tracks";
import { accentStyle, LearnIcon } from "./icon";
import { flushLearnView, setLearnView, useLearnView } from "./learn-view";
import { Highlight, LessonLinks, passedCount, ProgressBar, type Progress } from "./lesson-links";
import { useProgress } from "./progress";

const plural = (count: number, word: string) => `${count} ${word}${count === 1 ? "" : "s"}`;
const matches = (text: string, terms: string[]) => { const lower = text.toLowerCase(); return terms.every(term => lower.includes(term)); };
const lessonTotal = (courses: CourseItem[], unit: CourseItem["unit"]) => courses.reduce((total, course) => total + (course.unit === unit ? course.lessons.length : 0), 0);
/** "9 courses · 153 lessons", "100 tasks" and the like. */
const contents = (courses: CourseItem[], task = "task") => {
  const paths = courses.filter(course => course.unit === "lesson").length, lessons = lessonTotal(courses, "lesson"), tasks = lessonTotal(courses, "task");
  return [paths ? plural(paths, "course") : "", lessons ? plural(lessons, "lesson") : "", tasks ? plural(tasks, task) : ""].filter(Boolean).join(" · ");
};

/**
 * The Learn index: where to start or continue, a search, track filters, and every course
 * with its lessons. The server renders all of it with every lesson list collapsed.
 */
export function LearnBrowser({ tracks, intro }: { tracks: TrackItem[]; intro: ReactNode }) {
  const progress = useProgress(), view = useLearnView();
  const active = tracks.find(item => item.id === view.track);
  const query = useDeferredValue(view.query);
  const terms = useMemo(() => query.toLowerCase().split(/\s+/).filter(Boolean), [query]);
  const [open, setOpen] = useState<Record<string, boolean>>({});
  // A search opens the courses whose lessons match. One the visitor closes stays closed until the search changes.
  const [closed, setClosed] = useState<Record<string, boolean>>({});
  const groups = useMemo(() => tracks.filter(item => !active || item === active).map(item => ({
    track: item,
    courses: item.courses.map(course => ({ course, hits: terms.length ? course.lessons.filter(lesson => matches(lesson.title, terms)) : [] }))
      .filter(entry => !terms.length || entry.hits.length > 0 || matches(entry.course.title, terms)),
  })).filter(group => group.courses.length > 0), [tracks, active, terms]);

  // On a phone the chips are one scrolling row: keep the chosen one in view without moving the page.
  const chips = useRef<HTMLDivElement>(null), activeId = active?.id;
  useEffect(() => {
    const row = chips.current, chip = row?.querySelector<HTMLElement>('[aria-pressed="true"]');
    if (!row || !chip || row.scrollWidth <= row.clientWidth) return;
    const left = chip.offsetLeft - row.offsetLeft, edge = 48;
    if (left < row.scrollLeft + edge) row.scrollLeft = left - edge;
    else if (left + chip.offsetWidth > row.scrollLeft + row.clientWidth - edge) row.scrollLeft = left + chip.offsetWidth - row.clientWidth + edge;
  }, [activeId]);

  const shown = groups.flatMap(group => group.courses);
  const hitCount = (unit: CourseItem["unit"]) => shown.reduce((total, entry) => total + (entry.course.unit === unit ? entry.hits.length : 0), 0);
  const hits = [hitCount("lesson") ? plural(hitCount("lesson"), "lesson") : "", hitCount("task") ? plural(hitCount("task"), "task") : ""].filter(Boolean).join(" and ");
  const where = `“${query.trim()}”${active ? ` in ${active.title}` : ""}`;
  const status = !terms.length ? `${active ? `${active.title}: ` : ""}${contents(shown.map(entry => entry.course), "interview task")}`
    : shown.length ? `${hits ? `${hits} in ` : ""}${plural(shown.length, "course")} match${(hits ? hitCount("lesson") + hitCount("task") : shown.length) === 1 ? "es" : ""} ${where}`
    : `Nothing matches ${where}`;

  return <>
    <section className="learn-hero">
      <div className="learn-hero-text">{intro}</div>
      <LearnStart tracks={tracks} progress={progress} />
    </section>

    <div className="learn-tools">
      <div className="learn-search">
        <LearnIcon name="search" size={20} />
        <input type="search" aria-label="Search courses and lessons" placeholder="Search courses and lessons" autoComplete="off" spellCheck={false} enterKeyHint="search"
          value={view.query} onChange={event => { setLearnView({ track: view.track, query: event.target.value }, true); setClosed({}); }} onBlur={flushLearnView} />
        {view.query ? <button type="button" aria-label="Clear search" onClick={() => { setLearnView({ track: view.track, query: "" }); setClosed({}); }}><LearnIcon name="close" size={18} /></button> : null}
      </div>
      <div className="learn-chips" role="group" aria-label="Filter by track" ref={chips}>
        <Chip label="All" icon="grid" count={tracks.reduce((total, item) => total + item.courses.reduce((sum, course) => sum + course.lessons.length, 0), 0)} unit="lessons and tasks" pressed={!active} onPress={() => setLearnView({ track: "", query: view.query })} />
        {tracks.map(item => <Chip key={item.id} label={item.short} icon={item.icon} color={item.accent}
          count={item.courses.reduce((sum, course) => sum + course.lessons.length, 0)} unit={item.courses.every(course => course.unit === "task") ? "tasks" : "lessons"}
          pressed={item === active} onPress={() => setLearnView({ track: item === active ? "" : item.id, query: view.query })} />)}
      </div>
      {/* Counts repeat the track headers, so only a search shows them; screen readers hear every change. */}
      <p className={terms.length ? "learn-status" : "visually-hidden"} role="status">{status}</p>
    </div>

    {groups.map(({ track, courses }) => {
      const all = courses.map(entry => entry.course), done = all.reduce((total, course) => total + passedCount(progress, course.id, course.lessons), 0);
      return <section key={track.id} className="learn-track" id={`track-${track.id}`} style={accentStyle(track.accent)} aria-labelledby={`track-${track.id}-title`}>
        <header className="learn-track-head">
          <span className="learn-icon"><LearnIcon name={track.icon} /></span>
          <div className="learn-track-title"><h2 id={`track-${track.id}-title`}>{track.title}</h2><p>{track.blurb}</p></div>
          <p className="learn-track-count">{contents(all)}{done ? <span> · {done} passed</span> : null}</p>
        </header>
        <ol className="learn-cards" role="list">{courses.map(({ course, hits }) => {
          const searching = hits.length > 0, isOpen = searching ? !closed[course.id] : !!open[course.id];
          return <CourseCard key={course.id} course={course} hits={hits} terms={terms} progress={progress} open={isOpen}
            onToggle={next => searching ? setClosed(current => ({ ...current, [course.id]: !next })) : setOpen(current => ({ ...current, [course.id]: next }))} />;
        })}</ol>
      </section>;
    })}

    {groups.length === 0 ? <div className="learn-empty">
      <p>No course or lesson title matches {where}.</p>
      <div>
        {active ? <button type="button" className="pill-button" onClick={() => setLearnView({ track: "", query: view.query })}>Search all tracks</button> : null}
        <button type="button" className="pill-button" onClick={() => { setLearnView({ track: view.track, query: "" }); setClosed({}); }}>Clear search</button>
      </div>
    </div> : null}
  </>;
}

function Chip({ label, icon, color, count, unit, pressed, onPress }: { label: string; icon: LearnIconName; color?: string; count: number; unit: string; pressed: boolean; onPress: () => void }) {
  return <button type="button" className="learn-chip" style={color ? accentStyle(color) : undefined} aria-pressed={pressed} onClick={onPress}>
    <LearnIcon name={icon} size={17} />{label}<span className="learn-chip-count">{count}<span className="visually-hidden"> {unit}</span></span>
  </button>;
}

/** "Start here" for a new visitor; "Continue" with the next lesson not yet passed once there is progress. */
function LearnStart({ tracks, progress }: { tracks: TrackItem[]; progress: Progress }) {
  const next = useMemo(() => nextLesson(tracks.flatMap(item => item.courses).map(course => ({ id: course.id, lessons: course.lessons.map(lesson => lesson.id) })), progress ?? {}), [tracks, progress]);
  const track = next ? tracks.find(item => item.courses.some(course => course.id === next.course)) : undefined;
  const course = next ? track?.courses.find(item => item.id === next.course) : undefined;
  if (!next || !track || !course) return <aside className="learn-start" aria-label="Progress">
    <p className="learn-start-label">All passed</p>
    <div className="learn-start-course"><span className="learn-icon large"><LearnIcon name="check" size={28} /></span><div><h2>Every lesson here is passed</h2><p>Open any lesson again to practise, or trace your own code in Labs.</p></div></div>
    <div className="learn-start-actions"><Link className="big-button primary" href="/labs/">Open Labs</Link></div>
  </aside>;
  const lesson: LessonItem = course.lessons[next.index], total = course.lessons.length, done = passedCount(progress, course.id, course.lessons);
  return <aside className="learn-start" style={accentStyle(track.accent)} aria-label={next.started ? "Continue" : "Start here"}>
    <p className="learn-start-label">{next.started ? "Continue" : "Start here"}</p>
    <div className="learn-start-course">
      <span className="learn-icon large"><LearnIcon name={course.icon} size={28} /></span>
      <div><h2>{course.title}</h2><p>{course.unit === "task" ? "Task" : "Lesson"} {next.index + 1} of {total} · {lesson.title}</p></div>
    </div>
    <div className="learn-start-progress">{next.started
      ? <><ProgressBar done={done} total={total} /><span aria-hidden="true">{done}/{total}</span><span className="visually-hidden">{done} of {total} passed</span></>
      : <span>No account. Lessons run in this browser.</span>}</div>
    <div className="learn-start-actions">
      <Link className="big-button primary" href={`/learn/${course.id}/${lesson.id}/`}><LearnIcon name="play" size={18} />{next.started ? "Continue" : "Start lesson 1"}</Link>
      <Link className="learn-start-more" href={`/learn/${course.id}/`}>Course overview</Link>
    </div>
  </aside>;
}

function CourseCard({ course, hits, terms, progress, open, onToggle }: { course: CourseItem; hits: LessonItem[]; terms: string[]; progress: Progress; open: boolean; onToggle: (open: boolean) => void }) {
  const total = course.lessons.length, done = passedCount(progress, course.id, course.lessons), units = `${course.unit}s`, complete = done >= total;
  return <li className={`learn-card${complete ? " complete" : ""}`} id={`course-${course.id}`}>
    <div className="learn-card-head">
      <span className="learn-icon"><LearnIcon name={course.icon} size={22} /></span>
      <div className="learn-card-text">
        <h3><Link href={`/learn/${course.id}/`}><Highlight text={course.title} terms={terms} /></Link></h3>
        <p>{course.summary}</p>
      </div>
      <div className="learn-card-facts">
        <p className="learn-card-meta">
          <span className="learn-card-count">{complete ? <LearnIcon name="check" size={14} /> : null}<span aria-hidden="true">{done ? `${done}/${total}` : total} {units}</span><span className="visually-hidden">{done} of {total} {units} passed</span></span>
          {course.level ? <span>{course.level}</span> : null}
          {course.time ? <span>{course.time}</span> : null}
          {course.appCount ? <span className="learn-app" title={`${course.appCount} of ${total} ${units} run only in the Pythilo app`}><LearnIcon name="phone" size={13} />App required{course.appCount < total ? ` · ${course.appCount}` : ""}</span> : null}
        </p>
        <ProgressBar done={done} total={total} />
      </div>
    </div>
    <details className="learn-lessons" open={open} onToggle={event => { if (event.currentTarget.open !== open) onToggle(event.currentTarget.open); }}>
      <summary><span>{hits.length ? `${hits.length} found` : course.unit === "task" ? "Tasks" : "Lessons"}<span className="visually-hidden"> in {course.title}</span></span><LearnIcon name="chevron-down" size={18} /></summary>
      {hits.length ? <p className="learn-lessons-note">{hits.length} of {total} {units} match. <Link href={`/learn/${course.id}/`}>See the whole course</Link></p> : null}
      <LessonLinks course={course.id} lessons={course.lessons} only={hits.length ? hits : undefined} terms={terms} progress={progress} />
    </details>
  </li>;
}
