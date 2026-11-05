import type { Metadata } from "next";
import Link from "next/link";
import { GuideHeader, Note, Pager } from "@/components/guide/doc";

export const metadata: Metadata = { title: "What runs on iOS", description: "What Pythilo runs on iPhone and iPad, what iOS does not allow, and what to know about running code safely." };

export default function Page() {
  return <>
    <GuideHeader slug="limits" />
    <h2 id="runs">Runs on this device</h2>
    <ul>
      <li>CPython 3.14, with its standard library</li>
      <li>Your projects, tests and the debugger</li>
      <li>Local web servers: Django, Flask, FastAPI, and Starlette on Uvicorn</li>
      <li>Notebooks, with cells that share one namespace</li>
      <li>Pure-Python packages from PyPI, per project</li>
      <li>NumPy and PyTorch, bundled and compiled for iOS; Core ML through <code>pythilo.coreml</code></li>
      <li>npm installs from the registry, and esbuild builds</li>
    </ul>

    <h2 id="not-possible">Not possible on iOS</h2>
    <ul>
      <li>Starting other programs, subprocesses or multiprocessing. That is why reloaders, <code>uvicorn --workers</code> and <code>manage.py dbshell</code> are refused, and why there is no Node.</li>
      <li>Installing compiled packages that Pythilo does not bundle.</li>
      <li>Docker and database servers.</li>
    </ul>

    <h2 id="not-yet">Not there yet</h2>
    <ul>
      <li>pandas, Matplotlib and SciPy: nobody publishes iOS builds of them for Python 3.14 yet.</li>
      <li>PyTorch on the GPU (MPS) and <code>torch.compile</code>.</li>
      <li>A Jupyter server, other kernels, and debugging notebook cells.</li>
      <li>Git over SSH, submodules and LFS.</li>
    </ul>

    <h2 id="worth-knowing">Worth knowing</h2>
    <Note warn title="Only run code you trust">
      <p>All projects share one Python process. Pythilo resets it between runs, but that is cleanup and not a security boundary. Code you run can read and change files in Pythilo&apos;s storage and use the network, as any program can.</p>
    </Note>
    <ul>
      <li>A compiled call that never returns cannot be stopped from inside the app. Your files are already saved, so closing the app loses nothing.</li>
      <li>Servers stop when iOS suspends the app in the background.</li>
      <li>Threads a program leaves running stay until Pythilo closes; the Output panel names them.</li>
    </ul>
    <p>Found something that should work and does not? <Link href="/support/">Tell us</Link>.</p>
    <Pager slug="limits" />
  </>;
}
