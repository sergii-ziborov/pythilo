import type { Metadata } from "next";
import Link from "next/link";
import { GuideHeader, Note, Pager, Table } from "@/components/guide/doc";

export const metadata: Metadata = { title: "Settings", description: "Every setting in Pythilo for iPhone and iPad: file drawer, status bar, code size, appearance, Git identity, GitHub account and tokens, room name and Python version." };

export default function Page() {
  return <>
    <GuideHeader slug="settings" />
    <p>Open <span className="ui">Settings</span> with the gear at the top of the Projects screen. Settings are kept on this device.</p>

    <h2 id="workspace">Workspace</h2>
    <Table head={["Setting", "What it does", "Default"]} rows={[
      [<span key="s" className="ui">File drawer side</span>, "Which edge of the iPhone screen the file drawer slides from, and where the files button sits.", "Left"],
      [<span key="s" className="ui">Swipe from the edge opens it</span>, "Turn off if the swipe gets in the way of your own gestures.", "On"],
      [<span key="s" className="ui">Hide status bar in the editor</span>, "Gives the editor the top of the screen, beside the camera.", "On"],
      [<span key="s" className="ui">Code size</span>, "The editor's font size, 10 to 24 points.", "14 pt"],
      [<span key="s" className="ui">Appearance</span>, "Automatic follows the system; or always Light or Dark.", "Automatic"],
    ]} />

    <h2 id="git">Git</h2>
    <Table head={["Setting", "What it does"]} rows={[
      [<span key="s" className="ui">Name</span>, <>The author name on your commits. Also set by <code>git config user.name</code>.</>],
      [<span key="s" className="ui">Email</span>, <>The author email on your commits. Also set by <code>git config user.email</code>.</>],
      [<span key="s" className="ui">GitHub account</span>, <>Save a GitHub personal access token once. Clone then shows your repositories, private ones included, and pull and push to github.com use it. See <Link href="/guide/git/#tokens">Git</Link>.</>],
      [<span key="s" className="ui">HTTPS tokens</span>, <>How many host tokens are stored in the Keychain. Add or replace one from the <Link href="/guide/git/#tokens">Git screen</Link>.</>],
    ]} />

    <h2 id="rooms">Shared rooms</h2>
    <Table head={["Setting", "What it does"]} rows={[
      [<span key="s" className="ui">Your name</span>, "Shown beside your cursor in rooms. Without it, Pythilo uses the first word of your Git name, or the device's name."],
      [<span key="s" className="ui">Relay</span>, "The relay this build uses for rooms (pythilo.com). Read only."],
    ]} />

    <h2 id="python">Python</h2>
    <Table head={["Item", "What it shows"]} rows={[
      [<span key="s" className="ui">Version</span>, "The exact CPython version inside the app."],
      [<span key="s" className="ui">What runs here</span>, <>What runs on the device, what iOS does not allow, and what is worth knowing. The same as <Link href="/guide/limits/">What runs on iOS</Link>.</>],
      [<span key="s" className="ui">Licenses</span>, <>The runtime&apos;s licences and every bundled Python package. See also <Link href="/legal/licenses/">Open-source licences</Link>.</>],
      [<span key="s" className="ui">About Pythilo</span>, <>The version and build, what is in the app, and links to this website, the guide, the blog, the source, support and the legal pages. The <span className="ui">About</span> section also has <span className="ui">Rate Pythilo</span>, <span className="ui">Share Pythilo</span> and <span className="ui">Report a bug</span>.</>],
    ]} />
    <Note>Lesson progress, lab code and these settings live in the app&apos;s own storage on the device. Deleting Pythilo deletes them, together with your projects, unless the device is backed up.</Note>
    <Pager slug="settings" />
  </>;
}
