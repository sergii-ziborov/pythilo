import type { Metadata } from 'next';
import Link from 'next/link';
import { SiteHeader, SiteFooter } from '@/components/site-header';
import { browserLabs } from '@/lib/browser-labs';
import { LabProgress } from '@/components/labs/lab-progress';
import { labCount } from '@/lib/labs';
import './labs.css';
export const metadata:Metadata={title:'Interactive Python labs',description:'Write Python, trace your own algorithms step by step, and check your solution in free browser labs. Arrays, graph algorithms and machine learning.'};
export default function LabsPage(){
  return <><SiteHeader current="labs"/><main className="labs-index"><header><p className="eyebrow">A WORKBENCH FOR YOUR IDEAS</p><h1>Algorithms you can see.</h1><p>Write Python. Run a trace. Follow each change, then test the edges.</p><div className="labs-facts"><span><strong>{browserLabs.length}</strong> browser labs</span><span><strong>{labCount}</strong> labs in the TestFlight app</span><span>No account · free</span></div></header>
    <section className="labs-how" aria-label="How labs work"><div><b>01 / Write</b><p>Begin with a starter or inspect a worked answer. Your code runs in this browser.</p></div><div><b>02 / Replay</b><p>Play, pause and scrub through real Python state after each line.</p></div><div><b>03 / Check</b><p>Tests cover normal inputs, empty cases, ties and other traps. Progress stays on this device.</p></div></section>
    {[...new Set(browserLabs.map(lab=>lab.section))].map(section=><section className="labs-group" key={section}><h2>{section}</h2><div className="labs-cards">{browserLabs.filter(lab=>lab.section===section).map(lab=><Link href={`/labs/${lab.id}/`} key={lab.id}><span className="lab-card-kind">PYTHON · RUNS HERE <LabProgress id={lab.id}/></span><h3>{lab.title}</h3><p>{lab.summary}</p><span className="lab-card-link">Open lab <span aria-hidden="true">↗</span></span></Link>)}</div></section>)}
    <aside className="labs-app"><h2>Keep exploring in Pythilo</h2><p>The app includes sorting, graphs, trees, heaps, tries, backtracking, neural networks and more. These 30 browser labs share the app’s tracing engine and are included in the TestFlight app.</p><Link href="/guide/learn/#labs">Explore the full lab catalog →</Link></aside>
  </main><SiteFooter/></>;
}
