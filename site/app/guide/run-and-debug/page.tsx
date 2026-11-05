import type { Metadata } from "next";
import Link from "next/link";
import { GuideHeader, Note, Pager, Toc } from "@/components/guide/doc";

export const metadata: Metadata = { title: "Run, stop and debug", description: "Run Python files on iPhone and iPad with Pythilo, answer input(), stop runaway code, run tests and use the debugger with breakpoints and stepping." };

export default function Page() {
  return <>
    <GuideHeader slug="run-and-debug" />
    <Toc items={[["run", "Run"], ["input", "input()"], ["stop", "Stop"], ["status", "Status and results"], ["tests", "Run tests"], ["debugger", "The debugger"], ["threads", "Threads, servers and async"]]} />

    <h2 id="run">Run</h2>
    <p><span className="ui">Run</span> (<kbd>⌘R</kbd>) saves every file, clears the <span className="ui">Output</span> panel, switches to it, and runs the Python file you have open. If the open file is not a Python file, it runs the project&apos;s entry point: the first of <code>main.py</code>, <code>manage.py</code>, <code>hello.py</code> and <code>app.py</code> that exists. Touch and hold Run for <span className="ui">Debug</span> and <span className="ui">Run tests</span>.</p>
    <p>Code runs in CPython 3.14, embedded in the app, on this device. It has the full standard library, real files in your project folder, and the network, like any program. Tracebacks point at your file and line.</p>

    <h2 id="input">input()</h2>
    <p>When your program calls <code>input()</code>, the Output panel shows a field labelled <code>input()</code>. Type a line and press Return or the send arrow. <span className="ui">EOF</span> sends end of input, which makes <code>input()</code> raise <code>EOFError</code>, as Ctrl-D does on a computer. In the terminal, the line you type goes to the program instead.</p>

    <h2 id="stop">Stop</h2>
    <p>While code runs, Run turns into <span className="ui">Stop</span> (<kbd>⌘.</kbd>). Stop interrupts endless loops, <code>time.sleep</code>, a waiting <code>input()</code>, blocking sockets and asyncio, and keeps asking if your code catches the first interrupt. If Python still has not stopped after several tries, Pythilo says <em>This run cannot be stopped from here</em>. That happens only inside compiled code that never returns. Your files are already saved, so closing Pythilo from the app switcher and opening it again loses nothing.</p>

    <h2 id="status">Status and results</h2>
    <p>The top of the Output panel shows what Python is doing (<em>Starting Python</em>, <em>Running</em>, <em>Waiting for input</em>, <em>Paused</em>, <em>Stopping</em>), that it runs on this device, and a timer. When the run ends it says <em>Finished in … s</em>, <em>Stopped after … s</em> or <em>Exited with code N</em>. If your program left threads running, Pythilo names them: Python keeps them until the app closes.</p>
    <p>Very fast, very long output is trimmed to what the screen can keep (about 400 KB), with a note saying how much was skipped.</p>

    <h2 id="tests">Run tests</h2>
    <p><span className="ui">Run tests</span>, from the Run button&apos;s menu or the <span className="ui">⋯</span> menu, runs <code>pytest -q</code> in the project&apos;s terminal. When the project has a <code>test_*.py</code> file or a <code>tests</code> folder, a <code>pytest -q</code> chip also appears above the terminal.</p>

    <h2 id="debugger">The debugger</h2>
    <p>Tap a line number in a Python file to set a breakpoint; tap it again to clear it. Then choose <span className="ui">Debug</span> from the Run button&apos;s menu, or <span className="ui">Debug</span> and the file name in the <span className="ui">Debug</span> panel. Without a breakpoint, the debugger stops on the first line.</p>
    <p>When it pauses, the Debug panel opens with:</p>
    <ul>
      <li><span className="ui">Continue</span>, <span className="ui">Step over</span>, <span className="ui">Step in</span> and <span className="ui">Step out</span></li>
      <li><strong>Call stack</strong>: tap a frame to look at its variables</li>
      <li><strong>Variables</strong>: each local with its value and type</li>
      <li><strong>Eval</strong>: type an expression and see its value in the selected frame</li>
    </ul>
    <p>Stop works while paused, too.</p>

    <h2 id="threads">Threads, servers and async</h2>
    <p>Breakpoints also stop inside threads, inside web request handlers while a Django, Flask or FastAPI server runs, and inside async code. One thread pauses at a time and the panel names it; the others keep running. Debugging notebook cells is not supported yet.</p>
    <Note title="One Python for everything">All projects share one Python process. Pythilo cleans up between runs (modules, paths and environment), but that is tidying, not a security boundary. Only run code you trust. See <Link href="/guide/limits/">What runs on iOS</Link>.</Note>
    <Pager slug="run-and-debug" />
  </>;
}
