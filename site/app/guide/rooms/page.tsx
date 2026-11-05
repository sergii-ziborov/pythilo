import type { Metadata } from "next";
import Link from "next/link";
import { GuideHeader, Note, Pager, Table, Toc } from "@/components/guide/doc";
import { DeviceShot } from "@/components/site/phone";
import { shots } from "@/lib/shots";

export const metadata: Metadata = { title: "Playground and shared rooms", description: "Share a Pythilo project as an end-to-end encrypted room, join one by link, edit together, and decide who may run code on your iPhone or iPad." };

export default function Page() {
  return <>
    <GuideHeader slug="rooms" />
    <Toc items={[["playground", "The Playground tab"], ["share", "Share a project"], ["what", "What a room carries"], ["link", "Share as a link"], ["join", "Join with a link"], ["in-room", "In a room"], ["running", "Running code for others"], ["end", "Ending a room"], ["privacy", "Privacy"]]} />

    <h2 id="playground">The Playground tab</h2>
    <p><span className="ui">Playground</span> is where you work on one project with another person or an AI client. Editing and running code are separate permissions. It has <span className="ui">Share a project</span>, <span className="ui">Join with a link</span>, the <Link href="/guide/connect-ai/">AI client over MCP</Link> card, and your active rooms with who is in them and when they end. Inside a project, <span className="ui">⋯</span> › <span className="ui">Share with an AI client or person</span> leads to the same places.</p>
    <figure><DeviceShot shot={shots.share} /><DeviceShot shot={shots.room} /><figcaption>Sharing a project, and a request to run code on this iPhone.</figcaption></figure>

    <h2 id="share">Share a project</h2>
    <p>Choose a project (it needs at least one <code>.py</code> file), then:</p>
    <ul>
      <li><span className="ui">Room closes after</span>: 1 h, 4 h (the default), 12 h or 24 h.</li>
      <li><span className="ui">People with the link can</span>: <span className="ui">Edit</span> or <span className="ui">Only view</span>.</li>
      <li><span className="ui">Others may run code here</span>: see <a href="#running">below</a>.</li>
    </ul>
    <p><span className="ui">Create room and copy link</span> encrypts the files, creates the room and copies its link. <span className="ui">Create room and connect an AI client</span> does the same and shows how to hand the room to an AI client. Send the link only to the people you mean: whoever has it can join with the access it grants.</p>

    <h2 id="what">What a room carries</h2>
    <p>A room carries source and text files: Python, text, Markdown, CSV, JSON, TOML, YAML, HTML, CSS, JavaScript, SQL and similar, plus <code>requirements.txt</code>, <code>README</code>, <code>LICENSE</code> and <code>.gitignore</code>. Up to 16 files, 64 KiB each, 128 KiB in all. The share sheet lists anything <span className="ui">Left out</span> and why:</p>
    <Table head={["Reason", "For example"]} rows={[
      ["Installed packages and environments stay on this device", <><code>.venv</code>, <code>site-packages</code>, <code>node_modules</code></>],
      ["Not a source or text file a room carries", "Images, databases, archives"],
      ["Larger than 64 KiB, or not UTF-8 text", "Big data files, binary files"],
      ["Over the 16-file limit, or over the 128 KiB limit for all files", "The rest of a large project"],
    ]} />
    <p><code>.git</code>, <code>.pythilo</code> and caches are never included.</p>

    <h2 id="link">Share as a link</h2>
    <p>For a quick, one-off share there is no need for a room. <span className="ui">⋯</span> › <span className="ui">Share as a link</span> packs the project&apos;s text files into a single link, compressed into the part after <code>#</code>, so no server keeps a copy. Opened in a browser, it shows the code in the <Link href="/playground/">playground</Link> on pythilo.com, ready to run; opened on a device with Pythilo, or pasted into <span className="ui">Join with a link</span>, it becomes a new project. <code>.env</code> files, <code>.git</code> and <code>.pythilo</code> are left out, and a project too large for a link says so: share a live room instead.</p>

    <h2 id="join">Join with a link</h2>
    <p>Paste a room link (or a shared project link) into <span className="ui">Join with a link</span> and tap <span className="ui">Join room</span>, or open the link on the device and choose Pythilo. Joining makes a new project on this device with the room&apos;s files. Nothing runs until you press Run, or allow someone else to. Links look like <code>https://pythilo.com/playground/room/…/#key=…</code>; everything after <code>#</code> is needed, and it never leaves your device in a request. A room that has ended cannot be joined.</p>

    <h2 id="in-room">In a room</h2>
    <p>Edits go both ways as you type, and you see the others&apos; cursors with their names. The room screen shows its revision and when it closes, <span className="ui">In the room</span> with each person&apos;s access (Owner, Can edit, Can view) and the file they are editing, the permissions, <span className="ui">Recent runs on this iPhone</span>, and <span className="ui">Copy link</span>, <span className="ui">Connect AI</span> and <span className="ui">Open in the editor</span>. Your name in rooms is set in <Link href="/guide/settings/">Settings</Link>. <span className="ui">Git commit and push</span> is always yours alone.</p>

    <h2 id="running">Running code for others</h2>
    <p>Code runs only where someone asks it to: in their own browser, or on a device whose owner allows it. Each result says where it ran, on which Python, and for which revision. For your device you choose:</p>
    <Table head={["Setting", "Meaning"]} rows={[
      [<strong key="s">Ask each time</strong>, "The default. A request shows who wants to run what, with Deny and Run once."],
      [<strong key="s">Allowed in this room</strong>, "Runs start without asking while the room is open."],
      [<strong key="s">Not allowed</strong>, "Code runs only where people press Run."],
    ]} />
    <p>Only people who can edit may ask. You can <span className="ui">Revoke</span> a permission you gave, and permissions end when Pythilo goes to the background. A run for someone else can be stopped like your own.</p>

    <h2 id="end">Ending a room</h2>
    <p>The owner can <span className="ui">End room</span> for everyone; others can <span className="ui">Leave room</span>. Rooms also end on their own when their time is up. Your copy of the files stays on your device either way.</p>

    <h2 id="privacy">Privacy</h2>
    <Note title="End-to-end encrypted">The link carries the key, so the relay at pythilo.com only ever sees encrypted text: not your file names, code, names or cursors. It keeps rooms in memory only, until they close. Details are in the <Link href="/legal/privacy/#rooms">Privacy Policy</Link>, and the rules for rooms in <Link href="/legal/acceptable-use/">Acceptable use</Link>.</Note>
    <Pager slug="rooms" />
  </>;
}
