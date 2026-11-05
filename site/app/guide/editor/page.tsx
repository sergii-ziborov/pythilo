import type { Metadata } from "next";
import Link from "next/link";
import { GuideHeader, Note, Pager, Table, Toc } from "@/components/guide/doc";
import { DeviceShot } from "@/components/site/phone";
import { shots } from "@/lib/shots";

export const metadata: Metadata = { title: "The editor and the key bar", description: "Pythilo's code editor on iPhone and iPad: the key bar above the keyboard, completion, problems, tabs, quick open and keyboard shortcuts." };

export default function Page() {
  return <>
    <GuideHeader slug="editor" />
    <Toc items={[["workspace", "The workspace"], ["key-bar", "The key bar"], ["typing", "Typing and indentation"], ["completion", "Completion"], ["problems", "Problems"], ["tabs", "Tabs and quick open"], ["shortcuts", "Keyboard shortcuts"], ["highlighting", "Highlighted languages"]]} />

    <h2 id="workspace">The workspace</h2>
    <p>Opening a project shows the workspace. On an iPhone held upright, <span className="ui">Back to projects</span> and the files button sit at the top left, <span className="ui">Run</span> at the top right beside the camera, the open files as tabs below them, and the editor runs to the bottom edge. A dock at the bottom switches between five panels: <span className="ui">Code</span>, <span className="ui">Problems</span>, <span className="ui">Output</span>, <span className="ui">Terminal</span> and <span className="ui">Debug</span>. The dock hides while the keyboard is up. Other screen shapes arrange the same pieces differently; see <Link href="/guide/layouts/">Layouts</Link>.</p>
    <p>The <span className="ui">⋯</span> menu beside the tabs holds the project actions: <span className="ui">Packages</span>, <span className="ui">Web preview</span> (while a server runs), <span className="ui">Git</span>, <span className="ui">Share with an AI client or person</span>, <span className="ui">Share as a link</span>, <span className="ui">Debug</span>, <span className="ui">Run tests</span> and <span className="ui">Close</span> for the current file.</p>
    <figure><DeviceShot shot={shots.editor} /><DeviceShot shot={shots.darkEditor} /><figcaption>The editor in light and dark appearance.</figcaption></figure>

    <h2 id="key-bar">The key bar</h2>
    <p>When the on-screen keyboard is up, a bar of keys sits on top of it. It scrolls sideways; the first and last keys stay put.</p>
    <Table head={["Key", "What it does"]} rows={[
      [<strong key="k">{"{ }"} Complete</strong>, "Pinned on the left. Asks for completions at the cursor, offline."],
      [<strong key="k">Tab (→|)</strong>, "Inserts four spaces."],
      [<>Punctuation</>, <><code>:</code> <code>(</code> <code>)</code> <code>[</code> <code>]</code> <code>{"{"}</code> <code>{"}"}</code> <code>=</code> <code>&quot;</code> <code>&apos;</code> <code>#</code> <code>_</code> <code>.</code> <code>,</code></>],
      [<>Words</>, <><code>def</code> <code>self</code> <code>for</code> <code>if</code> <code>return</code> <code>import</code> <code>class</code>, each with the space after it where Python needs one.</>],
      [<>Operators</>, <><code>==</code> <code>!=</code> <code>+</code> <code>-</code> <code>*</code> <code>/</code> <code>%</code> <code>&lt;</code> <code>&gt;</code> <code>@</code> <code>\</code> <code>-&gt;</code> <code>:=</code> <code>**</code></>],
      [<strong key="k">Hide keyboard</strong>, "Pinned on the right, in blue."],
    ]} />
    <p>Each key types exactly what it shows. Brackets and quotes are not paired automatically, so what you see is what is in the file.</p>

    <h2 id="typing">Typing and indentation</h2>
    <p>The editor turns off the things iOS does to prose: autocorrection, automatic capitals, spell checking, and smart quotes and dashes, so <code>&quot;</code> stays a straight quote and <code>--</code> stays two hyphens. Undo and redo are the system&apos;s own (shake, three-finger swipe, or <kbd>⌘Z</kbd>).</p>
    <p>In Python files, Return keeps the current indentation, adds a level after a line that ends in <code>:</code>, <code>(</code>, <code>[</code> or <code>{"{"}</code>, and removes one after <code>return</code>, <code>pass</code>, <code>break</code>, <code>continue</code> or <code>raise</code>. Lines do not wrap in the workspace editor; scroll sideways for long ones. (Lesson editors do wrap, with the rest of the line indented under its start.) The code size is set in <Link href="/guide/settings/">Settings</Link>, from 10 to 24 points.</p>

    <h2 id="completion">Completion</h2>
    <p>Completion comes from Jedi, running on the device. It knows the standard library, the packages Pythilo bundles, the ones you installed into the project, and your own modules. It appears a moment after you type a letter, a digit, <code>_</code> or <code>.</code> in a Python file, as a small list of up to four suggestions marked <strong>ƒ</strong> function, <strong>C</strong> class, <strong>m</strong> module or <strong>v</strong> other. The <span className="ui">Complete</span> key on the key bar asks for it at any time.</p>

    <h2 id="problems">Problems</h2>
    <p>Pythilo checks Python files as you type, about half a second after you stop. Syntax errors are listed as errors; pyflakes findings, such as an unused import or an undefined name, as warnings. The <span className="ui">Problems</span> panel groups them by file with the line number; tap one to jump there. The dock shows how many there are. A run that ends with an exception adds it to the list too, marked <em>last run</em>.</p>

    <h2 id="tabs">Tabs and quick open</h2>
    <p>Every file you open gets a tab; a dot marks unsaved changes. Touch and hold a tab to close it. <span className="ui">Open a file</span> (<kbd>⌘P</kbd>) searches the project by name. Files save themselves one second after you stop typing.</p>

    <h2 id="shortcuts">Keyboard shortcuts</h2>
    <p>With a hardware keyboard, such as an iPad Magic Keyboard:</p>
    <Table head={["Keys", "Action"]} rows={[
      [<kbd key="k">⌘R</kbd>, "Run"], [<kbd key="k">⌘.</kbd>, "Stop"], [<kbd key="k">⌘B</kbd>, "Show or hide the files"], [<kbd key="k">⌘J</kbd>, "Show or hide the bottom panel"], [<kbd key="k">⌘P</kbd>, "Open a file"], [<kbd key="k">⌘S</kbd>, "Save all"],
    ]} />
    <p>On an iPad with a keyboard attached, a small pill at the bottom right of the editor reminds you of them. Its keyboard button brings back the on-screen keys if you need the key bar.</p>

    <h2 id="highlighting">Highlighted languages</h2>
    <p>Syntax colours cover Python (<code>.py</code>, <code>.pyi</code>), TOML, CFG and INI files, JSON and notebooks, Markdown, and HTML including Django and Jinja template tags (<code>{"{{ }}"}</code> and <code>{"{% %}"}</code>). JavaScript and CSS open as plain text.</p>
    <Note>Notebooks (<code>.ipynb</code>) open in their own view rather than the text editor. See <Link href="/guide/notebooks/">Notebooks</Link>.</Note>
    <Pager slug="editor" />
  </>;
}
