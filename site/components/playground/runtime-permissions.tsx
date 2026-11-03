"use client";
import { useState } from 'react';
import type { RuntimeHost } from './use-runtime-host';
import { runtimeActions, type RuntimeAction } from '@/lib/playground-runtime-authority';

const labels: Record<RuntimeAction, string> = { check: 'Check', run: 'Run', test: 'Test' };
const until = (time: number) => new Date(time).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });

/** The owner of this browser decides every request to run shared source here. */
export function RuntimePermissions({ runtime, compact = false }: { runtime: RuntimeHost; compact?: boolean }) {
  const [operations, setOperations] = useState<RuntimeAction[]>([...runtimeActions]);
  const status = runtime.status;
  if (!status) return compact ? null : <section className="host-panel"><p>Waiting for the encrypted source and the room connection…</p></section>;
  if (compact && !status.grant && !status.requests.length && !status.jobs.some(job => job.state !== 'finished')) return null;
  return <section className="host-panel" aria-label="Requests to run code in this browser">
    {!compact ? <><h3>Running code here for others</h3><p>Off until you allow it. A controller in the room, such as an AI client, can ask this browser to check, run or test the shared source with Pyodide. Every request asks you; a grant lasts at most ten minutes and a job at most two minutes.</p></> : null}
    {runtime.notice ? <p role="status">{runtime.notice}</p> : null}
    {status.requests.map(request => <div key={request.controller} className="host-request" role="alert">
      <strong>{request.name} asks to run code in this browser</strong>
      <p className="host-key">Controller key <code>{request.controller.slice(0, 16)}…</code></p>
      <div className="chip-row">{request.operations.map(operation => <label key={operation} className="check-row"><input type="checkbox" checked={operations.includes(operation)} onChange={event => setOperations(previous => event.target.checked ? [...previous, operation] : previous.filter(item => item !== operation))} />{labels[operation]}</label>)}</div>
      <div className="dialog-actions">
        <button type="button" className="pill-button primary" disabled={!request.operations.some(operation => operations.includes(operation))} onClick={() => void runtime.allow(request.controller, request.requestID, operations.filter(operation => request.operations.includes(operation)), true)}>Allow once</button>
        <button type="button" className="pill-button" disabled={!request.operations.some(operation => operations.includes(operation))} onClick={() => void runtime.allow(request.controller, request.requestID, operations.filter(operation => request.operations.includes(operation)), false)}>Allow for 10 minutes</button>
      </div>
    </div>)}
    {status.grant ? <div className="host-grant"><span>Allowed: {status.grant.name} · {status.grant.operations.map(operation => labels[operation]).join(', ')} · {status.once === 'used' ? 'its one job has run' : status.once ? 'one job' : `until ${until(status.grant.expires)}`}</span><button type="button" className="pill-button danger" onClick={runtime.revoke}>Revoke</button></div> : !compact ? <p>Running code here for others is off.</p> : null}
    {status.jobs.filter(job => job.state !== 'finished').map(job => <p key={job.id} className="host-job">{labels[job.operation]} for {status.grant?.name ?? 'a controller'}: {job.stage}</p>)}
    {!compact ? <p className="host-key">This browser&apos;s key <code>{status.fingerprint.slice(0, 16)}…</code></p> : null}
  </section>;
}
