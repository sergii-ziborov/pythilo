import type {Metadata} from 'next';
import {notFound} from 'next/navigation';
import Link from 'next/link';
import {SiteHeader,SiteFooter} from '@/components/site-header';
import {LabWorkspace} from '@/components/labs/lab-workspace';
import {allLabs} from '@/lib/browser-labs';
import {PythonCode} from '@/components/python-code';
import {courses} from '@/lib/courses';
import '../labs.css';
export const dynamicParams=false;
export function generateStaticParams(){return allLabs.map(lab=>({lab:lab.id}));}
type Params={params:Promise<{lab:string}>};
export async function generateMetadata({params}:Params):Promise<Metadata>{const {lab:id}=await params;const lab=allLabs.find(lab=>lab.id===id);return lab?{title:`${lab.title} lab`,description:lab.summary}:{};}
export default async function LabPage({params}:Params){
  const {lab:id}=await params;
  const lab=allLabs.find(lab=>lab.id===id);
  if(!lab)notFound();
  const lessons=courses.flatMap(course=>course.lessons.filter(lesson=>lab.lessons?.includes(lesson.id)).map(lesson=>({href:`/learn/${course.id}/${lesson.id}/`,title:lesson.title})));
  return <><SiteHeader current="labs"/>{lab.runtime==='pytorch' ? <main className="lab-workspace lab-native">
    <nav className="lab-breadcrumb" aria-label="Breadcrumb"><Link href="/labs/">← All Labs</Link><span>PYTORCH · APP REQUIRED</span></nav>
    <header className="lab-title"><p className="eyebrow">REAL PYTORCH · CPU TRAINING AND AUTOGRAD</p><h1>{lab.title}</h1><p>{lab.summary}</p></header>
    <section className="labs-app"><h2>Run this Lab in Pythilo</h2><p>This Lab uses the real PyTorch runtime bundled in the iOS app. Open Labs, choose its topic, then load the starter or worked answer and tap Trace. The independent checks execute tensor operations and gradients on the device. No GPU, external model weights or API key is required.</p><p>PyTorch is unavailable in this browser runtime. The code and lessons are readable here; execution and checks run in the app.</p><Link className="pill-button" href="/pricing/#beta">Pythilo TestFlight →</Link></section>
    {lessons.map(lesson=><p key={lesson.href}><Link className="pill-button" href={lesson.href}>Read lesson: {lesson.title} →</Link></p>)}
    <section className="lab-notes"><h2>Your task</h2><p>{lab.variants[0].prompt}</p><h2>Starter</h2><PythonCode code={lab.starter}/><details><summary>Inspect the worked answer</summary><PythonCode code={lab.answer}/></details></section>
  </main> : <LabWorkspace key={lab.id} lab={lab} lessons={lessons}/>}<SiteFooter/></>;
}
