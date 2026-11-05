import type { Metadata } from "next";
import Link from "next/link";
import { SiteFooter, SiteHeader, APP_URL } from "@/components/site-header";
import { PythonCode } from "@/components/python-code";
import { Gallery } from "@/components/site/gallery";
import { DeviceShot } from "@/components/site/phone";
import { courses } from "@/lib/courses";
import { labCount, labGroups } from "@/lib/labs";
import { PRICE } from "@/lib/site-info";
import { PYODIDE_VERSION } from "@/lib/python-runtime";
import { gallery, shots } from "@/lib/shots";
import "./site.css";

export const metadata: Metadata = {
  title: { absolute: "Pythilo — Real Python on your iPhone and iPad" },
  description: "Pythilo is a Python IDE, a course and algorithm labs in one app. CPython 3.14 runs on the device: projects, a terminal, a debugger, pytest, Django, FastAPI, PyTorch and Git, offline.",
};

const sample = `def running_total():
    total = 0
    def add(n):
        nonlocal total
        total += n
        return total
    return add

add = running_total()
print(add(5), add(3))`;

const Arrow = () => <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.4" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><path d="M5 12h14M13 6l6 6-6 6" /></svg>;

export default function Home() {
  const path = courses.filter(course => course.kind !== "interview");
  const lessons = path.reduce((sum, course) => sum + course.lessons.length, 0);
  const tasks = courses.filter(course => course.kind === "interview").reduce((sum, course) => sum + course.lessons.length, 0);
  const first = courses[0], lesson = first?.lessons[0];
  return <>
    <SiteHeader />
    <main className="page" style={{ gap: 88 }}>
      <section className="home-hero" aria-labelledby="hero-title">
        <span className="eyebrow"><span className="dot" aria-hidden="true" />In beta on TestFlight · iPhone and iPad</span>
        <h1 id="hero-title">Real Python, <span className="accent">on your iPhone and iPad</span></h1>
        <p className="lead">Pythilo is a Python IDE, a course and a set of algorithm labs in one app. CPython 3.14 runs on the device itself: your code, your tests, your Django site and your debugger session never leave the phone, and none of it needs a network.</p>
        <div className="button-row center">
          <a href={APP_URL} className="big-button primary">Get the app<Arrow /></a>
          <Link href="/guide/" className="big-button">Read the guide</Link>
        </div>
        <p className="hero-note">No account, no analytics, no ads. Free while in beta.</p>
      </section>

      <Gallery slides={gallery} label="Screenshots of Pythilo on iPhone" />

      <section aria-label="Pythilo in numbers" className="stats">
        <div><strong>3.14</strong><span>CPython, embedded and offline</span></div>
        <div><strong>{lessons}</strong><span>lessons in {path.length} courses</span></div>
        <div><strong>{tasks}</strong><span>timed interview tasks</span></div>
        <div><strong>{labCount}</strong><span>labs that trace your own code</span></div>
        <div><strong>0</strong><span>accounts, trackers or ads</span></div>
      </section>

      <section className="feature" aria-labelledby="f-workspace">
        <div className="feature-text">
          <span className="label">A real workspace</span>
          <h2 id="f-workspace">Projects, an editor, a terminal and a debugger</h2>
          <p>Not a web view and not a cloud box. The interpreter ships inside the app, with real files, <code>input()</code>, tracebacks that point at your line, and a Stop button that works on endless loops, <code>sleep</code>, blocking sockets and asyncio.</p>
          <ul className="ticks">
            <li>Projects with many files and nested folders, kept as ordinary folders you also see in the Files app.</li>
            <li>An editor made for touch: a key bar with Python symbols, completion from Jedi that knows your own modules, and problems from pyflakes as you type.</li>
            <li>A debugger with breakpoints, stepping, the call stack, variables and an evaluate field. It also stops inside threads, request handlers and async code.</li>
            <li>A terminal that reads lines like bash, with pipes, redirects and about 60 built-in commands, plus <code>python</code>, <code>pip</code>, <code>pytest</code>, <code>sqlite3</code>, <code>git</code> and <code>npm</code>.</li>
            <li>Tap a SQLite database to browse its tables, filter and edit rows, read the schema and run SQL.</li>
          </ul>
          <Link href="/guide/editor/" className="arrow-link">The editor and the key bar</Link>
        </div>
        <div className="feature-media"><DeviceShot shot={shots.editor} /><DeviceShot shot={shots.terminal} /></div>
      </section>

      <section className="feature flip" aria-labelledby="f-web">
        <div className="feature-text">
          <span className="label">Web servers on the phone</span>
          <h2 id="f-web">Django, Flask and FastAPI, served from your pocket</h2>
          <p>Start a server and Pythilo says so, with an <span className="ui">Open site</span> button. The preview goes to any path, such as <code>/admin/</code>. The framework&apos;s own commands sit one tap away above the terminal.</p>
          <ul className="ticks">
            <li>Django with SQLite and migrations. When migrations are missing, <span className="ui">Migrate &amp; restart</span> applies them and starts the server again.</li>
            <li>Flask, FastAPI with Pydantic validation and WebSockets, and Starlette on Uvicorn.</li>
            <li>npm installs packages from the npm registry, and esbuild, running inside the app, builds a React front end that FastAPI serves.</li>
          </ul>
          <Link href="/guide/web-servers/" className="arrow-link">Servers and the preview</Link>
        </div>
        <div className="feature-media"><DeviceShot shot={shots.django} /><DeviceShot shot={shots.preview} /></div>
      </section>

      <section className="feature" aria-labelledby="f-ml">
        <div className="feature-text">
          <span className="label">Packages and machine learning</span>
          <h2 id="f-ml">NumPy and PyTorch, bundled. pip for the rest.</h2>
          <p>PyTorch 2.15 is built for iOS from source and ships in the app, so the machine learning lessons train real networks offline. pip installs pure-Python packages from PyPI into each project&apos;s own folder.</p>
          <ul className="ticks">
            <li>Bundled: NumPy, PyTorch, Django, Flask, FastAPI, Pydantic, Starlette, Uvicorn, Requests, httpx, pytest, SymPy, NetworkX and more.</li>
            <li><code>pythilo.coreml</code> runs a Core ML model on the CPU, the GPU or the Neural Engine, times each one and checks they agree.</li>
            <li>Notebooks open and save ordinary <code>.ipynb</code> files, with cells that share one namespace.</li>
          </ul>
          <Link href="/guide/packages/" className="arrow-link">Packages, PyTorch and Core ML</Link>
        </div>
        <div className="feature-media"><DeviceShot shot={shots.torch} /><DeviceShot shot={shots.notebook} /></div>
      </section>

      <section className="feature flip" aria-labelledby="f-learn">
        <div className="feature-text">
          <span className="label">Learn</span>
          <h2 id="f-learn">{lessons} lessons, checked by running your code</h2>
          <p>{path.length} courses take you from values and names to clean code, testing, architecture, async, the web, data, PyTorch and language models from the inside. Plus {tasks} interview tasks with a timer and hints.</p>
          <ul className="ticks">
            <li>Every check runs your code on the device. When one fails it says what came back and what was expected.</li>
            <li>On a phone, reading and coding take turns on the whole screen. On an iPad they sit side by side.</li>
            <li><span className="ui">Debug in a project</span> turns a lesson into a project with tests, so you can step through it like any other code.</li>
          </ul>
          <Link href="/guide/learn/" className="arrow-link">Courses, checks and interview practice</Link>
        </div>
        <div className="feature-media"><DeviceShot shot={shots.learn} /><DeviceShot shot={shots.check} /></div>
      </section>

      <section className="feature" aria-labelledby="f-labs">
        <div className="feature-text">
          <span className="label">Labs</span>
          <h2 id="f-labs">Watch your algorithm work, then time it</h2>
          <p>{labCount} labs cover basics, data structures, algorithms and machine learning. Trace your own code, replay each step, then see how it scales on the device.</p>
          <ul className="ticks">
            {labGroups.map(group => <li key={group.title}><strong>{group.title}</strong>: {group.labs.map(lab => lab.title).join(", ")}.</li>)}
          </ul>
          <Link href="/guide/learn/#labs" className="arrow-link">How the labs work</Link>
        </div>
        <div className="feature-media"><DeviceShot shot={shots.graphLab} /><DeviceShot shot={shots.dpLab} /></div>
      </section>

      <section className="feature flip" aria-labelledby="f-together">
        <div className="feature-text">
          <span className="label">Work with others, and with AI</span>
          <h2 id="f-together">Share a project, keep the keys</h2>
          <p>A shared room puts a project in front of a browser or an AI client by link, with live edits and cursors. It is end-to-end encrypted, so the relay only sees ciphertext. Code runs where someone asks it to, and every result says where.</p>
          <ul className="ticks">
            <li>Nobody runs code on your iPhone unless you allow it: once, for the room, or never.</li>
            <li>An AI client on your computer, such as Claude Code or Codex, can work on one project over your local network. Reading, editing, running, installing and committing are separate permissions.</li>
            <li>Git, for real, in an ordinary <code>.git</code> folder: commit, branches, diff, merge with conflict markers, rebase, and HTTPS clone.</li>
          </ul>
          <Link href="/guide/rooms/" className="arrow-link">Rooms and permissions</Link>
        </div>
        <div className="feature-media"><DeviceShot shot={shots.room} /><DeviceShot shot={shots.files} /></div>
      </section>

      <section aria-labelledby="f-shapes" style={{ display: "flex", flexDirection: "column", gap: 32 }}>
        <div className="section-intro center">
          <span className="label">Every shape</span>
          <h2 id="f-shapes">Made for the phone, roomy on the iPad</h2>
          <p>Layouts for the iPhone held either way, the iPad with or without a keyboard, and the folding iPhone in each of its poses. On a phone the IDE uses the whole screen: buttons sit beside the camera and code runs to the bottom edge.</p>
        </div>
        <div className="ipad-row">
          {[shots.ipadDjango, shots.ipadLesson].map(shot => <figure key={shot.file}><DeviceShot shot={shot} /><figcaption><strong>{shot.title}</strong>{shot.caption}</figcaption></figure>)}
        </div>
      </section>

      <section aria-labelledby="f-limits" style={{ display: "flex", flexDirection: "column", gap: 24 }}>
        <div className="section-intro">
          <span className="label">Honest limits</span>
          <h2 id="f-limits">What it does not do (yet)</h2>
          <p>iOS lets an app run its own code, not start other programs. Pythilo says so instead of pretending.</p>
        </div>
        <div className="card-grid">
          <div className="card"><h3>No pandas, Matplotlib or SciPy</h3><p>Nobody publishes iOS builds of them for Python 3.14 yet.</p></div>
          <div className="card"><h3>PyTorch on the CPU</h3><p>No MPS and no <code>torch.compile</code>. The Neural Engine is reached through Core ML.</p></div>
          <div className="card"><h3>pip installs pure Python</h3><p>Compiled packages work only when Pythilo bundles them.</p></div>
          <div className="card"><h3>No Node</h3><p>npm installs packages and esbuild builds them, but Vite or webpack cannot run on an iPhone.</p></div>
          <div className="card"><h3>No Jupyter server</h3><p>Notebooks run on Pythilo&apos;s own kernel.</p></div>
          <div className="card"><h3>Servers run while Pythilo is open</h3><p>iOS pauses apps in the background, and their servers with them.</p></div>
        </div>
      </section>

      <section className="feature" aria-labelledby="f-web-site">
        <div className="feature-text">
          <span className="label">Also in your browser</span>
          <h2 id="f-web-site">Try the lessons here, no install</h2>
          <p>The same lessons run on this site with Pyodide, checked by the same checker the app uses. The playground opens rooms that the app can join.</p>
          <div className="button-row">
            <Link href={lesson ? `/learn/${first.id}/${lesson.id}/` : "/learn/"} className="big-button run">Start the first lesson<Arrow /></Link>
            <Link href="/playground/" className="big-button">Open the playground</Link>
          </div>
        </div>
        <figure className="code-figure">
          <div className="code-figure-bar"><span className="file-badge python" aria-hidden="true">py</span>main.py<span>Runs in this browser</span></div>
          <PythonCode code={sample} />
          <div className="code-figure-output">5 8<div>Ran in this browser · Pyodide {PYODIDE_VERSION} · exit 0</div></div>
        </figure>
      </section>

      <section id="app" className="band" aria-labelledby="f-get">
        <div>
          <h2 id="f-get">Free while in beta</h2>
          <p>Pythilo is in beta on TestFlight. There is nothing to pay while it is in beta, and no account to make. The planned App Store price is {PRICE}, paid once.</p>
        </div>
        <div className="button-row"><Link href="/pricing/" className="big-button primary">Pricing and beta</Link><Link href="/support/" className="big-button">Support</Link></div>
      </section>
    </main>
    <SiteFooter />
  </>;
}
