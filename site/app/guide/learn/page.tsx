import type { Metadata } from "next";
import Link from "next/link";
import { GuideHeader, Note, Pager, Table, Toc } from "@/components/guide/doc";
import { DeviceShot } from "@/components/site/phone";
import { courses } from "@/lib/courses";
import { labCount, labGroups } from "@/lib/labs";
import { shots } from "@/lib/shots";

export const metadata: Metadata = { title: "Courses, labs and interview practice", description: "How Pythilo's Python courses work on iPhone and iPad: lessons, checks that run your code, hints, Debug in a project, timed interview tasks and interactive labs." };

export default function Page() {
  const path = courses.filter(course => course.kind !== "interview");
  const interview = courses.find(course => course.kind === "interview");
  const lessons = path.reduce((sum, course) => sum + course.lessons.length, 0);
  return <>
    <GuideHeader slug="learn" />
    <Toc items={[["path", "The path"], ["manage", "Download, remove and hide"], ["lesson", "A lesson"], ["checks", "Checks"], ["hints", "Hints and the solution"], ["debug", "Debug in a project"], ["progress", "Progress"], ["interview", "Interview practice"], ["labs", "Labs"], ["web", "On the website"]]} />

    <h2 id="path">The path</h2>
    <p>The <span className="ui">Learn</span> tab starts with a card to <span className="ui">Start lesson</span> or <span className="ui">Continue lesson</span>, then your progress, <span className="ui">Interview practice</span> and the courses: {path.length} courses and {lessons} lessons in tracks (Python, Web &amp; data, ML, AI and Algorithms), each course with a ring that fills as you finish lessons and a check once it is downloaded. Tap a track chip to see only its courses, or search every lesson by name.</p>
    <Table head={["#", "Course", "Lessons"]} rows={path.map((course, index) => [String(index + 1), <Link key="c" href={`/learn/${course.id}/`}>{course.title}</Link>, String(course.lessons.length)])} />
    <p>A course screen shows how many lessons it has, the time they take, how many you have done, and a timeline of lessons with their length, parts and number of checks. The next one is marked <em>Up next</em>.</p>

    <h2 id="manage">Download, remove and hide</h2>
    <p>Touch and hold a course for <span className="ui">Download course</span> (or <span className="ui">Remove download</span> once it is on the device) and <span className="ui">Hide course</span>. A course screen has the same actions in its <span className="ui">⋯</span> menu, and each track has <span className="ui">Download all</span> for its courses. In <span className="ui">Labs</span>, touch and hold a topic for the same actions.</p>
    <p>A hidden course or topic leaves its list and is left out of <span className="ui">Download all</span>; its download, progress and drafts stay. <span className="ui">Show N hidden courses</span> at the end of the list brings them back, dimmed and marked <em>Hidden</em>, so you can show them again. <span className="ui">Remove download</span> asks first, deletes the content from the device and keeps your progress and lesson drafts; you can download it again at any time.</p>

    <h2 id="lesson">A lesson</h2>
    <p>Courses and Lab topics download separately in the app, only when you choose Download. Download entire course saves every lesson, example and check with all its required packages, data and models. Download entire category prepares every Lab in that category. Downloads also offers Download everything, progress, pause and resume. After completion, the selected course or category works entirely offline, including code execution, checks and model training. Opening a lesson or pressing Run never downloads anything. Removing downloads preserves your project code, lesson drafts and progress.</p>
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
    <p>The <span className="ui">Labs</span> tab has {labCount} labs in five sections. Write the Python yourself and choose <span className="ui">Trace</span> to run it and record what changes. The step player lets you play, pause, go back, or jump to a step while the editor highlights the line that ran.</p>
    <p>Thirty labs also run here on the website, with an editor, checks and step-by-step replay. <Link href="/labs/">Open the browser labs</Link>.</p>
    {labGroups.map(group => <section key={group.title} aria-label={group.title}>
      <h3>{group.title}</h3>
      <Table head={["Lab", "What you explore"]} rows={group.labs.map(lab => [<strong key={lab.id}>{lab.title}</strong>, lab.summary])} />
    </section>)}
    <h3>How it scales</h3>
    <p>For labs with growing inputs, <span className="ui">How it scales</span> checks correctness and then times the code without the tracer. The chart compares input size with runtime and explains the observed growth. Results come from this device; they suggest a growth rate and do not prove Big O. Labs that follow a fixed training run instead show its learning steps.</p>
    <p>Sorting Bench compares random, sorted, reversed and duplicate-heavy input. Graph Explorer accepts any valid DFS order. Search &amp; Hashing counts comparisons made by the keys themselves, and Dynamic Programming shows repeated recursive calls and what a cache saves.</p>
    <figure><DeviceShot shot={shots.graphLab} /><DeviceShot shot={shots.dpLab} /><figcaption>Graph Explorer tracing a BFS, and Dynamic Programming counting repeated calls.</figcaption></figure>

    <h2 id="web">On the website</h2>
    <Note>The same lessons run in your browser at <Link href="/learn/">Learn</Link>, on Pyodide, with the same checker. Lessons that need PyTorch, Flask, threads or packages the browser lacks say they need the app. Progress on the website is kept in your browser and is separate from the app&apos;s.</Note>
    <Pager slug="learn" />
  </>;
}
