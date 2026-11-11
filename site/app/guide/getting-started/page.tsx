import type { Metadata } from "next";
import Link from "next/link";
import { GuideHeader, Note, Pager, Table, Toc } from "@/components/guide/doc";
import { DeviceShot } from "@/components/site/phone";
import { shots } from "@/lib/shots";

export const metadata: Metadata = { title: "Projects and files", description: "Create, clone and import Pythilo projects, search GitHub, organize projects into categories, choose a template, and manage files and folders on iPhone and iPad." };

export default function Page() {
  return <>
    <GuideHeader slug="getting-started" />
    <Toc items={[["projects", "The Projects screen"], ["organize", "Search and categories"], ["templates", "Templates"], ["clone", "Clone a repository"], ["import", "Import a folder"], ["files-app", "Where projects live"], ["drawer", "The file drawer"], ["file-actions", "File and folder actions"], ["new-item", "New file or folder"]]} />

    <h2 id="projects">The Projects screen</h2>
    <p>Pythilo opens on <span className="ui">Projects</span>. At the top are three tiles: <span className="ui">New</span>, <span className="ui">Clone</span> and <span className="ui">Import</span>. Below them, <span className="ui">Recent</span> lists your projects, newest first, each with its kind (Python, Django, Web or Notebook) and when it was last edited. Before you have any, a card explains that a project is an ordinary folder that also shows up in the Files app.</p>
    <p>Touch and hold a project for <span className="ui">Rename</span>, <span className="ui">Category</span>, <span className="ui">Share folder</span> and <span className="ui">Delete</span>. Delete removes the folder from the device, so commit and push first if you may want it back.</p>
    <figure><DeviceShot shot={shots.projects} /><DeviceShot shot={shots.files} /><figcaption>The Projects screen, and the file drawer of a Django project.</figcaption></figure>

    <h2 id="organize">Search and categories</h2>
    <p>Pull the list down for <span className="ui">Search projects</span>, which matches a project&apos;s name, kind or category. The sort button beside the chips orders the list by <span className="ui">Recently edited</span>, <span className="ui">Name</span> or <span className="ui">Kind</span>.</p>
    <p>To group projects, touch and hold one and choose <span className="ui">Category</span>, then <span className="ui">New category…</span> or an existing one. Chips above the list filter it to one category, or to <span className="ui">No category</span>; with <span className="ui">All</span> selected the list is grouped by category. Touch and hold a chip to rename or remove the category; its projects stay. Categories are kept on the device, never inside the project folder, so they never end up in a repository.</p>

    <h2 id="templates">Templates</h2>
    <p><span className="ui">New</span> asks for a name (it suggests <code>my-project</code>) and what to start from. If the name is taken, Pythilo adds <code>-2</code>, <code>-3</code> and so on. Every template includes a <code>.gitignore</code> that leaves out <code>.pythilo/</code>, <code>__pycache__/</code> and <code>*.sqlite3</code>.</p>
    <Table head={["Template", "What you get"]} rows={[
      [<strong key="t">Empty</strong>, <>One <code>main.py</code>, ready to run.</>],
      [<strong key="t">CSV cleaner</strong>, <>A module, a script, tests and a CSV file: <code>main.py</code>, <code>cleaner.py</code>, <code>test_cleaner.py</code>, <code>people.csv</code>.</>],
      [<strong key="t">Django notes</strong>, <>A Django site with a <code>notes</code> app, a model, a migration, a template and SQLite.</>],
      [<strong key="t">Flask app</strong>, <>A small JSON API in <code>hello.py</code>. Run it with <code>flask --app hello run</code>.</>],
      [<strong key="t">FastAPI</strong>, <>Validated models, async routes, a WebSocket and tests.</>],
      [<strong key="t">React and FastAPI</strong>, <>A React front end built with npm and esbuild, served by a FastAPI API on the same device.</>],
      [<strong key="t">ASGI API</strong>, <>Starlette on Uvicorn. Run it with <code>uvicorn main:app</code>.</>],
      [<strong key="t">Notebook</strong>, <>A <code>study.ipynb</code> with cells and NumPy.</>],
      [<strong key="t">PyTorch</strong>, <>A small network that trains on the device&apos;s CPU.</>],
      [<strong key="t">Neural Engine</strong>, <>Core ML models from Python with <code>pythilo.coreml</code>.</>],
    ]} />

    <h2 id="clone">Clone a repository</h2>
    <p><span className="ui">Clone</span> has three tabs. <span className="ui">Search</span> looks on GitHub as you type and shows each repository&apos;s owner, description, stars, forks, language and last update; sort by <span className="ui">Most stars</span>, <span className="ui">Recently updated</span> or <span className="ui">Best match</span>, and GitHub filters such as <code>language:python stars:&gt;500</code> work too. Tap a repository to clone it. <span className="ui">My repos</span> lists every repository of the GitHub account saved in <Link href="/guide/settings/">Settings</Link>, private ones included, with a filter.</p>
    <figure><DeviceShot shot={shots.github} /><figcaption>Searching GitHub from Clone.</figcaption></figure>
    <p><span className="ui">Address</span> takes an <span className="ui">HTTPS address</span>, such as <code>https://github.com/you/repo.git</code>. For a private repository, fill in <span className="ui">Username</span> and <span className="ui">Access token</span> under <span className="ui">Private repository</span>; leave them empty for a public one. The token is stored in the iOS Keychain, on this device only, and is never written into the project. SSH addresses are not supported: use the HTTPS address. See <Link href="/guide/git/">Git</Link> for everything after the clone.</p>

    <h2 id="import">Import a folder</h2>
    <p><span className="ui">Import</span> opens the system file picker. Choose a folder (from Files, iCloud Drive or another provider) and Pythilo copies it into your projects. Import takes folders, not zip archives.</p>

    <h2 id="files-app">Where projects live</h2>
    <p>Each project is a folder in Pythilo&apos;s Documents, under <code>Projects</code>. Because the app shares its Documents folder, you can see and edit projects in the Files app and from a Mac with Finder. Standard iCloud or computer backups of the device include them.</p>
    <p>Inside a project, Pythilo keeps its own things in a hidden <code>.pythilo</code> folder; installed packages go to <code>.pythilo/site-packages</code>, so each project has its own. The file tree hides <code>.git</code>, <code>.pythilo</code>, <code>__pycache__</code> and <code>.DS_Store</code>.</p>

    <h2 id="drawer">The file drawer</h2>
    <p>On an iPhone, the project&apos;s files live in a drawer. Open it with the folder button at the top, by swiping in from the edge of the screen, or with <kbd>⌘B</kbd> on a keyboard. Close it by swiping back or tapping outside it. You can choose which edge it lives on, and turn the swipe off, in <Link href="/guide/settings/">Settings</Link>. On an iPad, and on wider screens, the files sit in a column beside the editor instead.</p>
    <p>The drawer shows the project&apos;s name and either the current Git branch with the number of changes, or <span className="ui">No Git repository</span>. It has buttons for <span className="ui">New file</span> and <span className="ui">New folder</span>, a <span className="ui">Find a file</span> search, and at the bottom <span className="ui">Packages</span>, <span className="ui">Git</span>, <span className="ui">Room</span>, <span className="ui">Site</span> (while a server runs) and <span className="ui">Share</span>.</p>
    <p>Files changed since the last commit carry a Git badge: <strong>A</strong> added, <strong>M</strong> modified, <strong>D</strong> deleted, <strong>?</strong> untracked and <strong>!</strong> in conflict. A folder shows the badge of what is inside it.</p>

    <h2 id="file-actions">File and folder actions</h2>
    <p>Touch and hold a file or folder for:</p>
    <ul>
      <li><span className="ui">New file or folder here</span> (on a folder) or <span className="ui">New file beside it</span> (on a file)</li>
      <li><span className="ui">Rename</span> and <span className="ui">Duplicate</span></li>
      <li><span className="ui">Move to folder…</span>: type the new path inside the project. Missing folders are created.</li>
      <li><span className="ui">Copy path</span> and <span className="ui">Share</span></li>
      <li><span className="ui">Delete</span>, which removes it from the device. Commit first if you may want it back.</li>
    </ul>
    <p>Each folder also has a <span className="ui">+</span> button for a new item inside it. Files that are not text, such as images, do not open in the editor; Pythilo offers <span className="ui">Share file</span> instead.</p>

    <h2 id="new-item">New file or folder</h2>
    <p>The <span className="ui">New in …</span> sheet switches between <span className="ui">File</span> and <span className="ui">Folder</span>. The path may contain slashes, so <code>app/models/user.py</code> makes the folders and the file in one go; a preview marks each part as existing, a new folder or a new file. For files, <span className="ui">Start from</span> offers:</p>
    <Table head={["Start from", "Makes"]} rows={[
      ["Empty", "An empty file with the name you typed."],
      ["Module", <>A <code>.py</code> file.</>],
      ["Package", <>A folder with <code>__init__.py</code> inside.</>],
      ["Test", <>A <code>.py</code> test file for pytest.</>],
      ["Notebook", <>An <code>.ipynb</code> notebook.</>],
    ]} />
    <p>A row of keys above the keyboard types <code>/</code>, <code>.py</code>, <code>_</code>, <code>-</code> and <code>.</code> for you.</p>
    <Note title="Saving">Pythilo saves a file one second after you stop typing, and saves everything when you run, go back to Projects or press <kbd>⌘S</kbd>. A dot on a tab means it has changes not yet written.</Note>
    <Pager slug="getting-started" />
  </>;
}
