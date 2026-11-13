import type { Metadata } from "next";
import Link from "next/link";
import { guidePages } from "@/lib/guide";

export const metadata: Metadata = { title: "Guide to the Pythilo app", description: "A complete guide to Pythilo for iPhone and iPad: projects, the editor, the terminal, packages, web servers, Git, notebooks, courses, rooms and AI clients." };

export default function GuideIndex() {
  const groups = [...new Set(guidePages.map(page => page.group))];
  return <>
    <header>
      <span className="label">Guide</span>
      <h1>The Pythilo guide</h1>
      <p>Everything the app does, screen by screen, in the words the app uses. If something here does not match what you see, the app is right and this page is out of date: please <Link href="/support/">tell us</Link>.</p>
    </header>
    <p>Pythilo has four tabs at the bottom of the screen: <span className="ui">Projects</span>, <span className="ui">Learn</span>, <span className="ui">Labs</span> and <span className="ui">Playground</span>. A project opens as a full-screen workspace with the editor, the terminal and the other panels. <span className="ui">Settings</span> is the gear on the Projects screen.</p>
    {groups.map(group => <section key={group} aria-labelledby={`g-${group}`}>
      <h2 id={`g-${group}`}>{group}</h2>
      <div className="card-grid two">
        {guidePages.filter(page => page.group === group).map(page => <Link key={page.slug} href={`/guide/${page.slug}/`} className="card"><h3>{page.title}</h3><p>{page.summary}</p></Link>)}
      </div>
    </section>)}
  </>;
}
