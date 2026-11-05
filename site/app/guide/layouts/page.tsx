import type { Metadata } from "next";
import { GuideHeader, Note, Pager, Table } from "@/components/guide/doc";
import { DeviceShot } from "@/components/site/phone";
import { shots } from "@/lib/shots";

export const metadata: Metadata = { title: "iPhone, iPad and foldable layouts", description: "How Pythilo's workspace arranges itself on an iPhone held either way, an iPad with or without a keyboard, and a folding iPhone in each pose." };

export default function Page() {
  return <>
    <GuideHeader slug="layouts" />
    <p>Pythilo picks the arrangement from the size and shape of the window and, on a folding iPhone, from the hinge, never from the device&apos;s name. So Split View, Stage Manager and rotating the device all get the layout that fits.</p>

    <h2 id="iphone">iPhone</h2>
    <Table head={["Held", "Arrangement"]} rows={[
      [<strong key="l">Upright</strong>, <>Back and Files at the top left (they swap sides if the file drawer is on the right), Run at the top right beside the camera, tabs and <span className="ui">⋯</span> below, and the editor to the bottom edge. A dock of five panels at the bottom hides while you type. Other panels fill the screen.</>],
      [<strong key="l">Sideways</strong>, <>A slim rail on the camera side holds Back, Files and the panels, arranged around the camera. Run floats at the bottom right. While code runs, Output opens beside the editor, so you see both. With the keyboard up, the rail offers <span className="ui">Hide keyboard</span> and Run.</>],
    ]} />

    <h2 id="ipad">iPad</h2>
    <figure><DeviceShot shot={shots.ipadDjango} /><figcaption>An iPad with a keyboard: project column, editor, the terminal panel and the shortcut pill.</figcaption></figure>
    <ul>
      <li>A <strong>project column</strong> on the left with the files, search, and Packages, Git and Share. <kbd>⌘B</kbd> folds it into a slim rail.</li>
      <li>Tabs with the full path of the current file, <span className="ui">⋯</span> and Run on top; the editor in the middle.</li>
      <li>A <strong>bottom panel</strong> with Problems, Output, Terminal and Debug as tabs, the preview globe, and a button to hide it (<kbd>⌘J</kbd>). It is taller in portrait.</li>
      <li>In <strong>landscape</strong>, a live preview column opens on the right while a server runs.</li>
      <li>With a <strong>hardware keyboard</strong>, a pill shows the shortcuts. Lessons put reading and code side by side.</li>
    </ul>

    <h2 id="foldable">Folding iPhone</h2>
    <Table head={["Pose", "Arrangement"]} rows={[
      [<strong key="l">Folded (cover screen)</strong>, "A narrow rail with Back, Files and the panels, and a header with tabs and Run. With the keyboard up, one compact row and the editor."],
      [<strong key="l">Book (hinge upright)</strong>, "Left page: the project column, the panels and the active panel (the terminal at first). Right page: tabs, Run and the editor."],
      [<strong key="l">Laptop (hinge flat)</strong>, "Top half: header and editor, like a laptop screen. Bottom half: the panels and the active one (Output at first), with Hide keyboard while typing."],
      [<strong key="l">Open flat</strong>, "A project column, the editor, and a panel along the bottom that hides while you type."],
    ]} />
    <Note>The folding layouts follow the hinge as the device reports it. If the hinge is half open, Pythilo splits the screen at its middle.</Note>
    <Pager slug="layouts" />
  </>;
}
