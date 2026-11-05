'use client';
import Link from 'next/link';
import { useEffect, useRef, useState } from 'react';
import { PlainEditor } from '@/components/python/plain-editor';
import { usePythonRuntime } from '@/components/python/use-python-runtime';
import { labFiles, readLabResult, type BrowserLab, type LabPanel, type LabResult } from '@/lib/browser-labs';

function Chart({ panel }: {panel: LabPanel}) {
  const sets = panel.type === 'plot' ? panel.series?.map(series => series.points) ?? [] : [panel.points?.map(([x,y]) => [x,y] as [number,number]) ?? [], ...(panel.lines ?? []).map(([x1,y1,x2,y2]) => [[x1,y1],[x2,y2]] as [number,number][])];
  const all = sets.flat().filter(([x,y]) => Number.isFinite(x) && Number.isFinite(y));
  if (!all.length) return null;
  const xs=all.map(p=>p[0]), ys=all.map(p=>p[1]);
  const xmin=Math.min(...xs), xmax=Math.max(...xs), ymin=Math.min(...ys), ymax=Math.max(...ys);
  const x=(n:number)=>40+(n-xmin)/(xmax-xmin || 1)*560, y=(n:number)=>185-(n-ymin)/(ymax-ymin || 1)*150;
  return <svg viewBox="0 0 640 220" role="img" aria-label={`${panel.title ?? 'Trace chart'}; x ${xmin.toFixed(2)} to ${xmax.toFixed(2)}, y ${ymin.toFixed(2)} to ${ymax.toFixed(2)}`}>
    <path d="M40 20V185H610" fill="none" stroke="currentColor" opacity=".35" />
    <text x="40" y="210">{xmin.toFixed(2)}</text><text x="560" y="210">{xmax.toFixed(2)}</text><text x="4" y="22">{ymax.toFixed(2)}</text>
    {sets.map((points,i)=>panel.type==='scatter' && i===0 ? <g key={i}>{points.map(([a,b],j)=><circle key={j} cx={x(a)} cy={y(b)} r="5" />)}</g> : <polyline key={i} points={points.map(([a,b])=>`${x(a)},${y(b)}`).join(' ')} fill="none" strokeWidth="3" />)}
  </svg>;
}
function Panel({panel}: {panel: LabPanel}) {
  return <section className="lab-panel"><h3>{panel.title ?? 'State'}</h3>
    {panel.type==='array' ? <div className="lab-array">{panel.cells?.map((cell,i)=><div key={i}><small>{i}</small><code>{cell || '∅'}</code></div>)}</div> : panel.type==='vars' ? <dl className="lab-vars">{panel.pairs?.map(([name,value],i)=><div key={i}><dt>{name}</dt><dd><code>{value}</code></dd></div>)}</dl> : <Chart panel={panel} />}
  </section>;
}
export function LabWorkspace({lab}: {lab: BrowserLab}) {
  const python=usePythonRuntime();
  const [code,setCode]=useState(lab.starter),[version,setVersion]=useState(0),[result,setResult]=useState<LabResult|null>(null);
  const [frame,setFrame]=useState(0),[playing,setPlaying]=useState(false),[delay,setDelay]=useState(600),[error,setError]=useState('');
  const codeRef=useRef(code);codeRef.current=code;
  const key=`pythilo:lab:${lab.id}:v1:draft`;
  useEffect(()=>{try { const saved=localStorage.getItem(key); if(saved!==null) {setCode(saved);setVersion(v=>v+1);} } catch {}},[key]);
  useEffect(()=>{
    if (!playing || !result?.frames.length) return;
    const timer=setInterval(()=>setFrame(value=>{if(value>=result.frames.length-1){return value;} return value+1;}),delay);
    return ()=>clearInterval(timer);
  },[playing,result,delay]);
  useEffect(()=>{if(result && frame>=result.frames.length-1) setPlaying(false);},[frame,result]);
  const change=(value:string,replace=false)=>{
    setCode(value);setResult(null);setFrame(0);setPlaying(false);setError('');
    if(replace) setVersion(v=>v+1);
    try {localStorage.setItem(key,value);}catch{}
  };
  const trace=async()=>{
    setPlaying(false);setResult(null);setFrame(0);setError('');
    const tracedCode=code;
    try {
      const run=await python.run('run',labFiles(lab.id,code),'main.py','');
      if(run.status==='stopped') {setError('Stopped. Your code is still saved in this browser.');return;}
      if(run.status!=='succeeded') throw new Error(run.stderr || 'Python could not finish this trace.');
      if(codeRef.current!==tracedCode){setError('Your code changed during the run. Trace again to replay the current version.');return;}
      const report=readLabResult(run.stdout);setResult(report);
      if(report.correct) {try {localStorage.setItem(`pythilo:lab:${lab.id}:v1:passed`,'1');}catch{}}
    } catch(e) {setError(e instanceof Error?e.message:String(e));}
  };
  const current=result?.frames[frame];
  return <main className="lab-workspace">
    <nav className="lab-breadcrumb" aria-label="Breadcrumb"><Link href="/labs/">← All labs</Link><span>{lab.section}</span></nav>
    <header className="lab-title"><p className="eyebrow">WRITE · TRACE · UNDERSTAND</p><h1>{lab.title}</h1><p>{lab.summary}</p></header>
    <div className="lab-columns">
      <section className="lab-code" aria-label="Your Python code"><h2>Your experiment</h2><p>{lab.variants[0].prompt}</p>
        <PlainEditor value={code} onChange={change} label="Lab Python code" version={version} />
        <div className="lab-actions"><button type="button" className="pill-button primary" disabled={python.busy} onClick={()=>void trace()}>{python.busy?'Tracing…':'Trace & check'}</button>
          {python.busy?<button type="button" className="pill-button" onClick={python.stop}>Stop</button>:null}
          <button type="button" className="pill-button" disabled={python.busy} onClick={()=>change(lab.starter,true)}>Reset</button>
          <button type="button" className="pill-button" disabled={python.busy} onClick={()=>change(lab.answer,true)}>Load worked answer</button></div>
        <p className="lab-runtime" role="status">{python.stage || 'Python runs in your browser. Your draft stays on this device.'}</p>
        {error || python.error ? <pre className="lab-error" role="alert">{error || python.error}</pre>:null}
        <details className="lab-notes"><summary>What to look for</summary><p>{lab.idea}</p></details>
      </section>
      <section className="lab-replay" aria-label="Trace replay"><div className="lab-replay-heading"><h2>Watch your code work</h2><span>{result?.frames.length ? `${frame+1} / ${result.frames.length}`:'Ready to experiment'}</span></div>
        {current ? <>
          <div className="lab-player"><button type="button" aria-label="Previous step" disabled={frame===0} onClick={()=>{setPlaying(false);setFrame(v=>v-1);}}>←</button><button type="button" onClick={()=>{if(frame===result!.frames.length-1)setFrame(0);setPlaying(v=>!v);}}>{playing?'Pause':'Play'}</button><button type="button" aria-label="Next step" disabled={frame===result!.frames.length-1} onClick={()=>{setPlaying(false);setFrame(v=>v+1);}}>→</button>
          <label>Speed <select value={delay} onChange={e=>setDelay(Number(e.target.value))}><option value={1000}>Slow</option><option value={600}>Normal</option><option value={150}>Fast</option></select></label></div>
          <input className="lab-scrubber" type="range" aria-label="Trace step" min={0} max={result!.frames.length-1} value={frame} onChange={e=>{setPlaying(false);setFrame(Number(e.target.value));}} />
          <p className="lab-context">{current.context}</p><pre className="lab-line"><span>{current.line ? `Line ${current.line}`:'State'}</span><code>{current.code || current.note}</code></pre>
          <div className="lab-panels">{current.panels.map((panel,i)=><Panel key={`${panel.type}:${panel.title}:${i}`} panel={panel} />)}</div>
        </>:<div className="lab-empty"><span aria-hidden="true">⌘</span><p>Write a solution or load the worked answer, then choose <strong>Trace & check</strong>.</p><p>Step through arrays, variables and training curves produced by your own Python.</p></div>}
        {result?.truncated?<p className="lab-runtime">Replay reached the 180-frame browser limit. Checks still run separately on the full solution.</p>:null}
        {result?<section className="lab-checks" aria-label="Correctness checks"><h3>{result.correct?'All checks passed': 'Check results'}</h3>{result.checks.map((check,i)=><div key={i} data-ok={check.ok}><span>{check.ok?'✓':'×'}</span><div><strong>{check.name}</strong>{check.message?<p>{check.message}</p>:null}</div></div>)}{result.message && !result.checks.length?<p>{result.message}</p>:null}</section>:null}
      </section>
    </div>
  </main>;
}
