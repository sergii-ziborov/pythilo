import type { Metadata } from "next";
import { GuideHeader, Note, Pager, Toc } from "@/components/guide/doc";
import { DeviceShot } from "@/components/site/phone";
import { shots } from "@/lib/shots";

export const metadata: Metadata = { title: "Notebooks", description: "Open, run and save Jupyter .ipynb notebooks in Pythilo on iPhone and iPad, with code and text cells, NumPy and images." };

export default function Page() {
  return <>
    <GuideHeader slug="notebooks" />
    <Toc items={[["open", "Open and save"], ["cells", "Cells"], ["running", "Running"], ["output", "Output"], ["not", "What it is not"]]} />

    <h2 id="open">Open and save</h2>
    <p>Tap any <code>.ipynb</code> file and it opens as a notebook. Changes are saved back to the same file, in the standard Jupyter format, a second after you stop editing, so the file opens in Jupyter, VS Code or on GitHub as usual. The <strong>Notebook</strong> template starts you off with a small study using NumPy. To add a notebook to a project, choose <span className="ui">Notebook</span> under <span className="ui">Start from</span> when you make a new file.</p>
    <figure><DeviceShot shot={shots.notebook} /><figcaption>A notebook from the Notebook template.</figcaption></figure>

    <h2 id="cells">Cells</h2>
    <p>A notebook has code cells and text (Markdown) cells. <span className="ui">Add code</span> and <span className="ui">Add text</span> at the bottom add one. Text cells show formatted; tap one to edit it. Each cell&apos;s <span className="ui">⋯</span> menu has <span className="ui">Move up</span>, <span className="ui">Move down</span> and <span className="ui">Delete</span>.</p>

    <h2 id="running">Running</h2>
    <ul>
      <li>▶ on a cell runs it. Its number in brackets, <code>[3]</code>, says in which order cells ran.</li>
      <li><span className="ui">Run all</span> runs every code cell from the top, and stops if you stop one.</li>
      <li>All cells share one namespace, so a variable from one cell is there in the next, until <span className="ui">Restart</span>, which clears outputs and starts afresh. <span className="ui">Clear</span> clears outputs only.</li>
      <li>A cell you edit after it ran is marked <em>Edited after it ran</em>, so you know its output is stale.</li>
    </ul>

    <h2 id="output">Output</h2>
    <p>A cell shows what it printed, errors with their traceback, and the value of its last line as <code>Out</code>. Images in PNG form are shown. Objects that offer HTML, Markdown or SVG are saved with those forms in the notebook file, so Jupyter shows them, while Pythilo shows their plain text.</p>

    <h2 id="not">What it is not</h2>
    <Note>Pythilo runs notebooks on its own kernel, inside the app. There is no Jupyter server, no other kernels and no widgets, and the debugger does not step through notebook cells yet. Matplotlib and pandas are not available on iOS for Python 3.14 yet.</Note>
    <Pager slug="notebooks" />
  </>;
}
