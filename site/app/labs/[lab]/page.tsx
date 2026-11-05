import type {Metadata} from 'next';
import {notFound} from 'next/navigation';
import {SiteHeader,SiteFooter} from '@/components/site-header';
import {LabWorkspace} from '@/components/labs/lab-workspace';
import {browserLabs} from '@/lib/browser-labs';
import '../labs.css';
export const dynamicParams=false;
export function generateStaticParams(){return browserLabs.map(lab=>({lab:lab.id}));}
type Params={params:Promise<{lab:string}>};
export async function generateMetadata({params}:Params):Promise<Metadata>{const {lab:id}=await params;const lab=browserLabs.find(lab=>lab.id===id);return lab?{title:`${lab.title} lab`,description:lab.summary}:{};}
export default async function LabPage({params}:Params){const {lab:id}=await params;const lab=browserLabs.find(lab=>lab.id===id);if(!lab)notFound();return <><SiteHeader current="labs"/><LabWorkspace key={lab.id} lab={lab}/><SiteFooter/></>;}
