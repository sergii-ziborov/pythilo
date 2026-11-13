import type { Metadata } from 'next';
import Link from 'next/link';
import { SiteHeader, SiteFooter } from '@/components/site-header';
import { allLabs, browserLabs, labTopics, labTopicAssignments } from '@/lib/browser-labs';
import { CatalogBrowser } from '@/components/labs/catalog-browser';
import { labCount } from '@/lib/labs';
import './labs.css';
export const metadata:Metadata={title:'Interactive Python labs',description:'Write Python, trace your own algorithms step by step, and check your solution in free browser labs. Arrays, graph algorithms and machine learning.'};
export default function LabsPage(){
  return <><SiteHeader current="labs"/><main className="labs-index"><header><p className="eyebrow">A WORKBENCH FOR YOUR IDEAS</p><h1>Algorithms you can see.</h1><p>Write Python. Run a trace. Follow each change, then test the edges.</p><div className="labs-facts"><span><strong>{browserLabs.length}</strong> browser labs</span><span><strong>{labCount}</strong> labs in the app</span><span>No account · free</span></div></header>
    <section className="labs-how" aria-label="How labs work"><div><b>01 / Write</b><p>Begin with a starter or inspect a worked answer. Your code runs in this browser.</p></div><div><b>02 / Replay</b><p>Play, pause and scrub through real Python state after each line.</p></div><div><b>03 / Check</b><p>Tests cover normal inputs, empty cases, ties and other traps. Progress stays on this device.</p></div></section>
    <CatalogBrowser topics={labTopics} labs={allLabs.map(lab=>({id:lab.id,title:lab.title,summary:lab.summary,section:lab.section,topic:labTopicAssignments[lab.id],topicTitle:labTopics.find(topic=>topic.id===labTopicAssignments[lab.id])!.title,runtime:lab.runtime==='pytorch'?'pytorch':'browser'}))}/>
    <aside className="labs-app"><h2>Train real PyTorch models in Pythilo</h2><p>{allLabs.length-browserLabs.length} PyTorch Labs use the app’s CPU tensor runtime, autograd and optimizers: train a tiny language model, resume dropout and AdamW, or merge a learned low-rank adapter. Their pages link to lessons and show the code. The app also includes sorting, graphs, trees and other foundations. These {browserLabs.length} browser Labs remain runnable here.</p><Link href="/guide/learn/#labs">Explore the full app catalog →</Link></aside>
  </main><SiteFooter/></>;
}
