import type { Metadata } from "next";
import Link from "next/link";
import { GuideHeader, Note, Pager, Table, Toc } from "@/components/guide/doc";
import { DeviceShot } from "@/components/site/phone";
import { courses } from "@/lib/courses";
import { shots } from "@/lib/shots";

export const metadata: Metadata = { title: "Courses, labs and interview practice", description: "How Pythilo's Python courses work on iPhone and iPad: lessons, checks that run your code, hints, Debug in a project, timed interview tasks and four algorithm labs." };

export default function Page() {
  const path = courses.filter(course => course.kind !== "interview");
  const interview = courses.find(course => course.kind === "interview");
  const lessons = path.reduce((sum, course) => sum + course.lessons.length, 0);
  return <>
    <GuideHeader slug="learn" />
    <Toc items={[["path", "The path"], ["lesson", "A lesson"], ["checks", "Checks"], ["hints", "Hints and the solution"], ["debug", "Debug in a project"], ["progress", "Progress"], ["interview", "Interview practice"], ["labs", "Labs"], ["web", "On the website"]]} />

    <h2 id="path">The path</h2>
    <p>The <span className="ui">Learn</span> tab starts with a card to <span className="ui">Start lesson</span> or <span className="ui">Continue lesson</span>, then <span className="ui">Your path</span>: {path.length} courses and {lessons} lessons in order, each with a ring that fills as you finish lessons. Below them, <span className="ui">Practice</span> holds the interview tasks.</p>
    <Table head={["#", "Course", "Lessons"]} rows={path.map((course, index) => [String(index + 1), <Link key="c" href={`/learn/${course.id}/`}>{course.title}</Link>, String(course.lessons.length)])} />
    <p>A course screen shows how many lessons it has, the time they take, how many you have done, and a timeline of lessons with their length, parts and number of checks. The next one is marked <em>Up next</em>.</p>

    <h2 id="lesson">A lesson</h2>
    <p>A lesson is split into short parts. Chips at the top jump between them: the first is <span className="ui">Idea</span>, the last is <span className="ui">Your task</span>. Code in the text has <span className="ui">Run example</span>, which runs it on the device and shows the output in place.</p>
    <ul>
      <li>On an iPhone, <span className="ui">Lesson</span> and <span className="ui">Code</span> at the bottom switch between reading and writing, each on the whole screen. The task stays at the top of the code, folded or open.</li>
      <li>On an iPad, reading and code sit side by side.</li>
    </ul>
    <p>The code view has your <code>solution.py</code>, with long lines wrapped, and three buttons: the lightbulb for hints, ▶ to run your code, and <span className="ui">Check</span>.</p>
    <figure><DeviceShot shot={shots.lesson} /><DeviceShot shot={shots.check} /><figcaption>A lesson, and the check sheet after a first try.</figcaption></figure>

    <h2 id="checks">Checks</h2>
    <p><span className="ui">Check</span> runs your code on the device against the lesson&apos;s checks and shows a sheet: <em>N of M checks passed</em>, each with ✓ or ✗. A failed check says what came back and what was expected, for example <code>describe(3) returned None, expected &apos;int: 3&apos;. Is a return missing?</code>, and the sheet shows what your code printed. When everything passes you get <em>Why this works</em>, a short explanation, and <span className="ui">Next</span> to the following lesson.</p>

    <h2 id="hints">Hints and the solution</h2>
    <p>The lightbulb shows the lesson&apos;s hints one at a time (<em>Hint 1 of 3</em>…). After the last hint it offers <span className="ui">Show the solution</span>.</p>

    <h2 id="debug">Debug in a project</h2>
    <p>From the check sheet, <span className="ui">Debug in a project</span> (or <span className="ui">Keep as a project</span> once it passes) turns the lesson into a normal project with <code>solution.py</code>, a <code>test_solution.py</code> holding each check as a test, and a README. It opens in the workspace, where you can set breakpoints, step through, and run <code>pytest</code>.</p>

    <h2 id="progress">Progress</h2>
    <p>A lesson is done when every check passes. Progress and your code for each lesson are kept on the device, so you can leave a lesson and come back to it. Nothing is sent anywhere.</p>

    <h2 id="interview">Interview practice</h2>
    <p>{interview ? <>{interview.lessons.length} tasks, marked Easy, Medium or Hard. </> : null}A task opens straight in the code view with a countdown timer in the toolbar, set to the task&apos;s time. Hints work as in lessons, and <span className="ui">Test</span> runs real tests against your solution.</p>

    <h2 id="labs">Labs</h2>
    <p>The <span className="ui">Labs</span> tab has four labs that trace your own code while it runs, then measure it on the device. Correctness first, then time. Timings come from this device: they suggest a growth rate, they do not prove Big O.</p>
    <Table head={["Lab", "You write", "You see"]} rows={[
      [<strong key="l">Sorting Bench</strong>, <><code>my_sort(items)</code></>, <><span className="ui">Trace</span> steps through every read and write your sort makes. <span className="ui">Measure</span> times it on random, sorted, reversed and duplicate-heavy input, five runs each, median in milliseconds.</>],
      [<strong key="l">Graph Explorer</strong>, "BFS, DFS or Dijkstra", <>Your search expanding a grid, a tree, or a sparse or dense random graph, step by step. A DFS is judged as any valid depth-first order, not one fixed answer.</>],
      [<strong key="l">Search &amp; Hashing</strong>, <>A <code>Table</code> class with <code>put</code> and <code>get</code></>, <><span className="ui">Run 400 keys</span> fills it with words, sequential, random or deliberately colliding keys, then shows the buckets, comparisons per lookup and the longest bucket, and times yours against a <code>dict</code>.</>],
      [<strong key="l">Dynamic Programming</strong>, "Stairs, coins or edit distance", <>How many calls a plain recursion makes and how many repeat, what <code>@cache</code> saves, and a table filling cell by cell.</>],
    ]} />
    <figure><DeviceShot shot={shots.graphLab} /><DeviceShot shot={shots.dpLab} /><figcaption>Graph Explorer tracing a BFS, and Dynamic Programming counting repeated calls.</figcaption></figure>

    <h2 id="web">On the website</h2>
    <Note>The same lessons run in your browser at <Link href="/learn/">Learn</Link>, on Pyodide, with the same checker. Lessons that need PyTorch, Flask, threads or packages the browser lacks say they need the app. Progress on the website is kept in your browser and is separate from the app&apos;s.</Note>
    <Pager slug="learn" />
  </>;
}
