import type { Metadata } from "next";
import Link from "next/link";
import { GuideHeader, Note, Pager, Table, Toc } from "@/components/guide/doc";
import { DeviceShot } from "@/components/site/phone";
import { shots } from "@/lib/shots";

export const metadata: Metadata = { title: "The terminal", description: "Pythilo's terminal on iPhone and iPad: a small bash with pipes, redirects and about 60 built-in commands, plus python, pip, pytest, sqlite3, git, npm, Django, Flask and Uvicorn." };

export default function Page() {
  return <>
    <GuideHeader slug="terminal" />
    <Toc items={[["how", "How it works"], ["keys", "Keys, history and Ctrl-C"], ["shell", "Pipes, redirects and variables"], ["files", "File commands"], ["text", "Text tools"], ["network", "curl and wget"], ["python", "python"], ["frameworks", "Django, Flask and Uvicorn"], ["chips", "Framework chips"], ["other", "pip, pytest, sqlite3, git and npm"], ["servers-busy", "While a server runs"]]} />

    <h2 id="how">How it works</h2>
    <p>iOS does not let an app start other programs, so Pythilo&apos;s terminal is a small bash built into the app. It reads a line the way bash does (quotes, variables, globs, pipes and lists) and runs each command as part of Pythilo, on the real files of your project and with the same Python that runs your code. A command or option that is not built in says so, rather than being ignored. Type <code>help</code> for the list, and <code>COMMAND --help</code> for a command&apos;s options.</p>
    <p>The prompt shows the folder you are in. <code>cd</code> moves around inside the project and stays where you left it; <code>cd</code> on its own goes back to the project root. A non-zero exit code is shown as <code>[exit N]</code>. Smart punctuation from the iOS keyboard is undone before a line runs, so a long dash typed by the keyboard becomes <code>--</code> again and curly quotes become straight ones.</p>
    <figure><DeviceShot shot={shots.terminal} /><DeviceShot shot={shots.django} /><figcaption>pytest in the terminal, and a Django project with its command chips.</figcaption></figure>

    <h2 id="keys">Keys, history and Ctrl-C</h2>
    <p>Above the input line is a row of keys: <code>python</code>, <code>pip</code>, <code>npm</code>, <code>pytest</code>, <code>git</code> and <code>ls</code> type the word and a space; <span className="ui">Ctrl-C</span> stops what is running; <span className="ui">↑</span> steps back through the commands you ran since you opened the panel. While something runs, the field reads <em>Running. Ctrl-C stops it</em>; you can type the next line already and it waits for Return. When a program asks for <code>input()</code>, the prompt changes to <code>&gt;</code> and the line you type goes to the program.</p>

    <h2 id="shell">Pipes, redirects and variables</h2>
    <Table head={["Write", "Means"]} rows={[
      [<code key="c">ls | grep py</code>, "A pipe: the first command's output is the second one's input."],
      [<><code>pytest &amp;&amp; git commit -m ok</code>, <code>a || b</code>, <code>a ; b</code></>, "Run the next command if this one succeeded, if it failed, or either way."],
      [<><code>&gt; file</code>, <code>&gt;&gt; file</code>, <code>&lt; file</code></>, "Write output to a file, append to it, or read input from it."],
      [<><code>2&gt; file</code>, <code>2&gt;&amp;1</code>, <code>&amp;&gt; file</code></>, "Send errors to a file, together with the output, or both to a file."],
      [<><code>$NAME</code>, <code>~</code>, <code>*.py</code></>, <>Variables, the home folder and globs expand. <code>export</code>, <code>unset</code> and <code>NAME=value command</code> set variables; <code>$?</code> is the last exit code.</>],
    ]} />
    <p>Background jobs (<code>&amp;</code>) and programs that are not built in are not available.</p>

    <h2 id="files">File commands</h2>
    <Table head={["Commands", "Notes"]} rows={[
      [<><code>ls</code>, <code>cd</code>, <code>pwd</code>, <code>tree</code></>, <><code>ls -a</code> shows hidden files, <code>-l</code> sizes and dates.</>],
      [<><code>cat</code>, <code>less</code>, <code>head</code>, <code>tail</code></>, <><code>head</code> and <code>tail</code> take <code>-n N</code>.</>],
      [<><code>find</code>, <code>stat</code>, <code>du</code>, <code>file</code></>, <><code>find . -name &quot;*.py&quot;</code>, sizes, and what kind of file something is.</>],
      [<><code>touch</code>, <code>mkdir</code>, <code>rm</code>, <code>rmdir</code>, <code>mv</code>, <code>cp</code>, <code>ln</code>, <code>chmod</code></>, <><code>mkdir -p</code>, <code>rm -r</code>, <code>cp -r</code>. <code>rm</code> refuses to delete the project itself.</>],
      [<><code>basename</code>, <code>dirname</code>, <code>realpath</code></>, "Parts of paths."],
      [<><code>zip</code>, <code>unzip</code>, <code>tar</code>, <code>gzip</code>, <code>gunzip</code></>, "Pack and unpack archives."],
    ]} />

    <h2 id="text">Text tools</h2>
    <p><code>echo</code>, <code>printf</code>, <code>grep</code>, <code>sed</code>, <code>awk</code>, <code>sort</code>, <code>uniq</code>, <code>cut</code>, <code>tr</code>, <code>wc</code>, <code>diff</code>, <code>tee</code>, <code>seq</code>, <code>rev</code>, <code>nl</code>, <code>xargs</code>, <code>base64</code>, <code>sha256sum</code> and <code>md5sum</code> work on files and in pipes, for example:</p>
    <pre><code>{`grep -rn "TODO" . | sort | uniq -c
cut -d, -f1 people.csv | sort | uniq
ls *.py | xargs wc -l`}</code></pre>
    <p>Also there: <code>env</code>, <code>printenv</code>, <code>date</code>, <code>sleep</code>, <code>time</code>, <code>whoami</code>, <code>uname</code>, <code>which</code>, <code>clear</code> and <code>help</code>.</p>

    <h2 id="network">curl and wget</h2>
    <p><code>curl URL</code> prints a response and <code>wget URL</code> saves it to a file, so you can try your API or download data. They also reach your own server while it runs, for example <code>curl http://127.0.0.1:8000/api/tasks</code>.</p>

    <h2 id="python">python</h2>
    <p><code>python</code> and <code>python3</code> are the same interpreter, the one inside the app.</p>
    <ul>
      <li><code>python</code> with nothing after it opens an interactive prompt. Stop ends the session.</li>
      <li><code>python file.py</code> runs a file; a folder with <code>__main__.py</code> runs too.</li>
      <li><code>python -m module</code> runs a module: <code>pip</code>, <code>pytest</code>, <code>http.server</code>, <code>json.tool</code>…</li>
      <li><code>python -c &quot;code&quot;</code> runs code given as text, and <code>python -</code> runs code piped in: <code>cat script.py | python -</code>.</li>
      <li><code>-i</code> opens the interactive prompt after the program, with its variables; <code>-q</code> skips the banner; <code>-W</code> sets a warning filter; <code>-X</code> sets an option; <code>-B</code> writes no <code>.pyc</code> files. <code>python --version</code> prints the version.</li>
      <li><code>python -m venv</code> is not needed and says so: each project already has its own package folder.</li>
    </ul>

    <h2 id="frameworks">Django, Flask and Uvicorn</h2>
    <ul>
      <li><code>python manage.py &lt;command&gt;</code> and <code>django-admin &lt;command&gt;</code> work as on a computer. <code>runserver</code> runs without the autoreloader (iOS cannot start the child process it needs), so stop and run again after a change. <code>dbshell</code> is refused, because it starts an external database program.</li>
      <li><code>flask --app hello run</code> runs a Flask app. The reloader and <code>--debug</code> are refused for the same reason.</li>
      <li><code>uvicorn main:app</code> serves a FastAPI or Starlette app on <code>127.0.0.1:8000</code>; <code>--host</code> and <code>--port</code> change that. <code>--reload</code> and <code>--workers</code> start extra processes and are refused.</li>
    </ul>
    <p>When a server starts, Pythilo shows it and offers <span className="ui">Open site</span>. See <Link href="/guide/web-servers/">Web servers and the preview</Link>.</p>

    <h2 id="chips">Framework chips</h2>
    <p>Pythilo looks at the project and puts its framework&apos;s commands one tap away, above the terminal and below the output after a run:</p>
    <Table head={["Project has", "Chips"]} rows={[
      [<code key="c">manage.py</code>, <><strong>Django</strong>: <code>runserver</code>, <code>migrate</code>, <code>makemigrations</code>, <code>createsuperuser</code>, <code>test</code>, <code>check</code>. Commands that need an argument, such as <code>startapp</code>, fill in the line instead of running. After <code>python manage.py</code> lists its commands once, <span className="ui">All N commands</span> opens every one, grouped by app.</>],
      [<><code>Flask(</code> in app, main, hello, wsgi, asgi or server.py</>, <><strong>Flask</strong>: <code>run</code>, <code>routes</code></>],
      [<><code>FastAPI(</code> or <code>Starlette(</code></>, <><strong>Uvicorn</strong>: <code>uvicorn main:app</code></>],
      [<><code>test_*.py</code> or <code>tests/</code></>, <code>pytest -q</code>],
      [<code key="c">package.json</code>, <><strong>NPM</strong>: <code>install</code>, and <code>build</code>, <code>dev</code> or <code>start</code> when the project defines them</>],
    ]} />

    <h2 id="other">pip, pytest, sqlite3, git and npm</h2>
    <ul>
      <li><code>pip</code> installs into the project. See <Link href="/guide/packages/">Packages</Link>.</li>
      <li><code>pytest</code> runs as on a computer, with your arguments.</li>
      <li><code>sqlite3 db.sqlite3</code> opens a database. See <Link href="/guide/sqlite/">SQLite</Link>.</li>
      <li><code>git</code> covers <code>init</code>, <code>status</code>, <code>add</code>, <code>reset</code>/<code>restore</code>, <code>commit -m</code>, <code>log</code>, <code>diff</code>, <code>branch</code>, <code>switch</code>/<code>checkout</code>, <code>merge</code>, <code>rebase</code>, <code>remote</code>, <code>fetch</code>, <code>pull</code>, <code>push</code> and <code>config</code>. Clone from the Projects screen. See <Link href="/guide/git/">Git</Link>.</li>
      <li><code>npm</code> installs from the npm registry and builds with esbuild; <code>npx esbuild</code> works too. See <Link href="/guide/packages/#npm">npm and esbuild</Link>.</li>
    </ul>

    <h2 id="servers-busy">While a server runs</h2>
    <p>A server keeps Python busy. If you type a command while a server you started from the terminal is running, Pythilo stops the server, runs the command and starts the server again; the field says <em>Command (restarts the server)</em>. If some other program is running, the terminal asks you to stop it first.</p>
    <Pager slug="terminal" />
  </>;
}
