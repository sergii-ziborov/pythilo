import type { Metadata } from "next";
import Link from "next/link";
import { GuideHeader, Note, Pager, Table, Toc } from "@/components/guide/doc";
import { DeviceShot } from "@/components/site/phone";
import { shots } from "@/lib/shots";

export const metadata: Metadata = { title: "Packages, PyTorch and Core ML", description: "pip per project, the packages bundled with Pythilo (NumPy, PyTorch, Django, FastAPI and more), npm with esbuild, and Core ML from Python." };

export default function Page() {
  return <>
    <GuideHeader slug="packages" />
    <Toc items={[["bundled", "Bundled with the app"], ["pip", "pip"], ["packages-screen", "The Packages screen"], ["pytorch", "PyTorch"], ["coreml", "Core ML and the Neural Engine"], ["npm", "npm and esbuild"]]} />

    <h2 id="bundled">Bundled with the app</h2>
    <p>These ship inside Pythilo, compiled for iOS where they need to be, and work offline in every project:</p>
    <Table head={["Area", "Packages"]} rows={[
      ["Web", "Django, Flask, FastAPI, Pydantic, Starlette, Uvicorn, Werkzeug, Jinja2"],
      ["Science and ML", "NumPy, PyTorch, SymPy, NetworkX"],
      ["HTTP", "Requests, httpx"],
      ["Tools", "pytest, pip, Jedi, pyflakes, Pygments"],
    ]} />
    <p>Their own dependencies come along too. <code>pip list</code> shows every bundled package and its version, and <Link href="/legal/licenses/">Open-source licences</Link> lists them all with their licences.</p>

    <h2 id="pip">pip</h2>
    <p><code>pip install name</code> downloads wheels from PyPI and installs them into the project&apos;s <code>.pythilo/site-packages</code> folder, which comes first on the path when the project runs. Every project has its own, so two projects can use different versions, and nothing is installed for the whole app.</p>
    <ul>
      <li>pip installs <strong>pure-Python</strong> packages. A package that needs compiled code only works if Pythilo bundles it; iOS runs only code signed into the app. When an install fails, nothing is changed and pip&apos;s full message is in the terminal.</li>
      <li><code>pip install -r requirements.txt</code> works the same way.</li>
      <li><code>pip uninstall</code>, <code>pip list</code> (project packages marked <em>project</em>, the rest <em>bundled</em>; <code>-o</code> for outdated ones), <code>pip show</code> (<code>-f</code> lists files), <code>pip freeze</code> and <code>pip check</code> work as usual.</li>
      <li><code>pip download</code> fetches wheels without installing them, and <code>pip index versions name</code> lists the versions on PyPI.</li>
      <li>Options that would install somewhere else, such as <code>--user</code>, <code>--target</code>, <code>--prefix</code> or <code>-e</code>, are refused: packages always go to the project.</li>
    </ul>

    <h2 id="packages-screen">The Packages screen</h2>
    <p>Open <span className="ui">Packages</span> from the file drawer or the <span className="ui">⋯</span> menu. Type a <span className="ui">Package name</span> and tap <span className="ui">Install</span>. <span className="ui">In this project</span> lists what you installed, each with a button to remove it. <span className="ui">Bundled with Pythilo, work offline</span> lists the main bundled packages.</p>

    <h2 id="pytorch">PyTorch</h2>
    <p>PyTorch 2.15 is built for iOS from source by <a href="https://github.com/sergii-ziborov/torch-ios" target="_blank" rel="noreferrer">torch-ios</a>: the full library with autograd and the Python API, running on the CPU with matrix maths through Apple&apos;s Accelerate. Training, <code>torch.func</code>, <code>torch.jit</code>, <code>DataLoader</code>, saving and loading all work. The PyTorch template trains a small network on the device, and the machine learning course uses it throughout.</p>
    <p>There is no MPS (GPU) backend, no <code>torch.compile</code> and no <code>DataLoader</code> workers: keep <code>num_workers=0</code>.</p>
    <figure><DeviceShot shot={shots.torch} /><DeviceShot shot={shots.coreml} /><figcaption>The PyTorch template training on the device, and Core ML timings.</figcaption></figure>

    <h2 id="coreml">Core ML and the Neural Engine</h2>
    <p><code>pythilo.coreml</code> runs Core ML models (<code>.mlpackage</code> or <code>.mlmodel</code>) from Python, with NumPy arrays in and out:</p>
    <pre><code>{`from pythilo import coreml

print(coreml.devices())
model = coreml.load("model.mlpackage", compute="ane")   # cpu, gpu, ane or all
outputs = model.predict({"input": array})

rows = coreml.benchmark()          # the built-in sample model on every compute unit
print(coreml.report(rows))`}</code></pre>
    <p><code>benchmark</code> loads the model on each compute unit, times the first and the median prediction, and checks the results agree with the CPU. The Neural Engine template shows it end to end. The simulator has no Neural Engine, so its numbers only mean something on a real device.</p>

    <h2 id="npm">npm and esbuild</h2>
    <p>There is no Node on iOS, but Pythilo has its own npm for installing and esbuild for building:</p>
    <ul>
      <li><code>npm install</code> (also <code>i</code>, <code>add</code>, <code>ci</code>) resolves versions from the npm registry, checks each package&apos;s integrity hash, writes <code>node_modules</code> and <code>package-lock.json</code>. <code>-D</code> saves a dev dependency. <code>npm uninstall</code>, <code>npm ls</code> and <code>npm init</code> work too.</li>
      <li>Packages install from the registry only (no git or file sources), and their install scripts are not run.</li>
      <li><code>npm run build</code>, <code>npm run dev</code> and <code>npm start</code> work when the script is an esbuild command, such as <code>esbuild src/main.jsx --bundle --outdir=dist</code>. esbuild runs inside the app. With <code>--watch</code>, it rebuilds every time you save a JavaScript, TypeScript, CSS or JSON file.</li>
      <li>Scripts that need Node itself, such as Vite or webpack, say so.</li>
    </ul>
    <p>The <strong>React and FastAPI</strong> template puts it together: <code>npm install</code>, <code>npm run build</code>, then <code>uvicorn main:app</code> serves the built site and its API.</p>
    <Note>Network access is needed only to download: pip from PyPI and npm from the npm registry. Everything bundled works offline.</Note>
    <Pager slug="packages" />
  </>;
}
