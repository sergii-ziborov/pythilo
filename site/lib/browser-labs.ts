import snapshot from '../content/labs.json' with { type: 'json' };

export type BrowserLab = {
  id: string; title: string; summary: string; section: string; idea: string;
  variants: { id: string; title: string; prompt: string; file: string; scales: boolean }[];
  starter: string; answer: string;
  lessons?: string[];
  runtime?: 'pytorch';
};
export const allLabs = snapshot.labs as BrowserLab[];
export const browserLabs = allLabs.filter(lab => lab.runtime !== 'pytorch');
export const labTopics = snapshot.topics;
export const labTopicAssignments: Record<string, string> = snapshot.assignments;
export const labSources: Record<string,string> = snapshot.sources;
export type LabPanel = { type: string; title?: string; grid?: string[][]; cells?: string[]; pairs?: [string,string][]; series?: { name: string; points: [number,number][] }[]; points?: [number,number,number][]; lines?: [number,number,number,number][] };
export type LabFrame = { note: string; line: number | null; code: string; context: string; panels: LabPanel[] };
export type LabResult = { correct: boolean; message: string; truncated: boolean; checks: {name: string; ok: boolean; message: string}[]; frames: LabFrame[] };
const RESULT = '__PYTHILO_LAB_RESULT__';

/** The same tracing engine as iOS, isolated in the page's Python worker. */
export function labFiles(id: string, source: string): Record<string,string> {
  return {
    ...Object.fromEntries(Object.entries(labSources).map(([name,text]) => [`pythilo_labs_web/${name}`,text])),
    // Package discovery scans actual Python files before execution. Keeping
    // learner code only inside a JSON string hides its NumPy imports.
    '_pythilo_lab_solution.py': source,
    'pythilo_labs_web/__init__.py': 'events = []\ndef emit_json(kind, payload):\n    events.append((kind, payload))\n',
    'main.py': `import json\nfrom pathlib import Path\nfrom pythilo_labs_web import events, labs_engine\nlabs_engine.MAXIMUM_FRAMES = 180\njob = ${JSON.stringify({id:'web',lab:id,variant:'practice'})}\njob['source'] = Path('_pythilo_lab_solution.py').read_text()\nlabs_engine.run(job)\nprint(${JSON.stringify(RESULT)} + json.dumps(events[-1][1], ensure_ascii=False))\n`,
  };
}
export function readLabResult(stdout: string): LabResult {
  const index = stdout.lastIndexOf(RESULT);
  if (index < 0) throw new Error('The trace did not finish. Check Python output and try again.');
  return JSON.parse(stdout.slice(index + RESULT.length).trim()) as LabResult;
}
