"use client";
import { useEffect, useRef, useState } from 'react';
import { RuntimeHostCore, type RuntimeEffect, type RuntimeHostContext, type RuntimeJobUpdate } from '@/lib/playground-runtime-host';
import { createRuntimeSigner } from '@/lib/playground-runtime-protocol';
import { remoteRuntimePresence } from '@/lib/playground-presence';
import { runtimeSource, runtimeSourceRevision } from '@/lib/playground-runtime-source';
import type { PlaygroundSession } from '@/lib/playground-session';
import type { PlaygroundDocument } from '@/lib/playground-document';
import type { RuntimePresenceChannel } from '@/lib/playground-runtime-channel';
import type { RuntimeAction } from '@/lib/playground-runtime-authority';
import { BROWSER_RUNTIME, type RunResult } from '@/lib/python-runtime';
import type { Awareness } from 'y-protocols/awareness';
import type { PythonRuntime } from '@/components/python/use-python-runtime';

export type HostStatus = ReturnType<RuntimeHostCore['drain']> & { fingerprint: string };

/** This browser as a runtime host: a controller in the room may ask it to run shared source, and its owner decides. */
export function useRuntimeHost(session: PlaygroundSession | null, awareness: Awareness, channel: RuntimePresenceChannel | null, source: () => PlaygroundDocument, python: PythonRuntime, name: string) {
  const latest = useRef({ source, python, name }); latest.current = { source, python, name };
  const [notice, setNotice] = useState('');
  const [status, setStatus] = useState<HostStatus>();
  const actions = useRef<{ allow: (controller: string, requestID: string, operations: RuntimeAction[], once: boolean) => Promise<void>; revoke: () => void } | undefined>(undefined);
  useEffect(() => {
    if (!session || !channel) return;
    let stopped = false, core: RuntimeHostCore, signer: Awaited<ReturnType<typeof createRuntimeSigner>>, queue = Promise.resolve(), connection = 0;
    let active: string | undefined, activeRevision = '', lastLocal: RunResult | null = null, seen = new Map<number, number>(), lastVisible = document.visibilityState === 'visible';
    const releaseReset = session.onRuntimeReset(() => reset());
    const stop = () => { if (active) latest.current.python.stopOwned(active); };
    async function context(): Promise<RuntimeHostContext> {
      const s = latest.current.source(), p = latest.current.python, { paths } = runtimeSource(s);
      return { room: session!.link.id, target: signer.fingerprint, scope: session!.peer + ':' + connection, revision: await runtimeSourceRevision(s), editCapability: session!.link.access, expires: session!.link.expiresAt,
        foreground: document.visibilityState === 'visible', connected: session!.connected && !session!.stopped, editConfirmed: session!.runtimeEditConfirmed, ready: p.ready, busy: p.busy,
        name: latest.current.name, kind: 'browser', runtime: BROWSER_RUNTIME, paths };
    }
    async function flush() {
      const reply = core.drain(); if (stopped) return;
      setStatus({ ...reply, fingerprint: signer.fingerprint });
      for (const effect of reply.effects.filter(e => e.type !== 'start')) apply(effect);
      try {
        for (const p of reply.publications) {
          const envelope = await signer.sign(p.fields, JSON.parse(p.payloadJSON), { ...(p.proof ? { editCapability: session!.link.access } : {}) });
          if (!stopped) await channel!.publish(envelope);
        }
      } catch (error) { for (const effect of reply.effects.filter(e => e.type === 'start')) core.update(effect.job, { state: 'finished', succeeded: false, stage: 'Start acknowledgement could not be published; no code executed' }); throw error; }
      for (const effect of reply.effects.filter(e => e.type === 'start')) apply(effect);
    }
    function enqueue(work: () => Promise<void>) { queue = queue.then(async () => { if (!stopped && core) await work(); }).catch(error => { if (!stopped) setNotice(error instanceof Error ? error.message : 'Python in this browser is unavailable'); }); return queue; }
    function update(id: string, value: RuntimeJobUpdate) {
      void enqueue(async () => {
        core.tick(await context()); core.update(id, value);
        await flush();
      });
    }
    function apply(effect: RuntimeEffect) {
      const p = latest.current.python;
      if (effect.type === 'start') {
        active = effect.job; activeRevision = effect.revision;
        const document = latest.current.source();
        // Its result already reaches the room through update(); it is not also shared as a local run.
        p.run(effect.operation as RuntimeAction, document.files, document.entryFile, effect.revision, { id: effect.job, update: value => { if (value.state === 'finished' && active === effect.job) active = undefined; update(effect.job, value); } })
          .then(result => { lastLocal = result; }, () => { /* Reported through update(). */ });
      } else if (effect.type === 'stop') { if (active === effect.job) p.stopOwned(effect.job); else update(effect.job, { state: 'finished', succeeded: false, stage: 'Unstarted job stopped' }); }
    }
    const changed = () => { void enqueue(async () => {
      const ctx = await context(); if (active && activeRevision !== ctx.revision) stop(); core.tick(ctx);
      const result = latest.current.python.result;
      // A run started by this browser's owner is shown to the room as shared output.
      if (result && result !== lastLocal) { lastLocal = result; if (result.ranOn.here && result.revision === ctx.revision && !active) core.reportLocal(ctx.revision, { stdout: result.stdout, stderr: result.stderr, succeeded: result.status === 'succeeded', exitCode: result.exitCode, durationMs: result.durationMs, operation: result.operation, startedAt: result.startedAt, truncated: result.truncated }); }
      const peers = remoteRuntimePresence(awareness); const live = new Set(peers.map(p => p.clientID)); for (const id of seen.keys()) if (!live.has(id)) seen.delete(id);
      for (const frame of peers) if (seen.get(frame.clientID) !== frame.clock) { seen.set(frame.clientID, frame.clock); try { await core.frame(JSON.parse(frame.envelope)); } catch {} }
      await flush();
    }); };
    const visibility = () => { if (document.visibilityState !== 'visible') { stop(); if (core) core.revoke(); } lastVisible = document.visibilityState === 'visible'; changed(); };
    function reset() { stop(); connection++; seen.clear(); void enqueue(async () => { core.revoke(); core = new RuntimeHostCore(await context()); await flush(); }); }
    void (async () => {
      while (!stopped && !session.receivedState) { await new Promise(resolve => setTimeout(resolve, 50)); } if (stopped) return;
      signer = await createRuntimeSigner(); if (stopped) { signer.destroy(); return; } core = new RuntimeHostCore(await context());
      actions.current = {
        allow: async (controller, requestID, operations, allowOnce) => {
          // The owner's explicit choice is what loads Python here; a request alone never does.
          if (!latest.current.python.ready) void latest.current.python.load().then(changed, () => {});
          await enqueue(async () => { core.tick(await context()); core.allow(controller, requestID, operations, undefined, allowOnce); await flush(); });
        },
        revoke: () => { stop(); void enqueue(async () => { core.revoke(); await flush(); }); },
      };
      awareness.on('change', changed); awareness.doc.on('afterTransaction', changed); document.addEventListener('visibilitychange', visibility); changed();
    })().catch(error => { if (!stopped) setNotice(error instanceof Error ? error.message : 'Python in this browser is unavailable'); });
    const timer = setInterval(() => { void enqueue(async () => { if (session.connected && lastVisible && session.link.mode === 'edit' && !session.runtimeEditConfirmed && remoteRuntimePresence(awareness).some(frame => frame.envelope.includes('permission-request'))) try { await session.confirmRuntimeEditAccess(); } catch {}; const ctx = await context(); if (active && activeRevision !== ctx.revision) stop(); core.tick(ctx); await flush(); }); changed(); }, 1000);
    return () => { stopped = true; stop(); clearInterval(timer); releaseReset(); awareness.off('change', changed); awareness.doc.off('afterTransaction', changed); document.removeEventListener('visibilitychange', visibility); signer?.destroy(); actions.current = undefined; };
  }, [session, awareness, channel]);
  return { status, notice, allow: (controller: string, requestID: string, operations: RuntimeAction[], once: boolean) => actions.current?.allow(controller, requestID, operations, once), revoke: () => actions.current?.revoke() };
}
export type RuntimeHost = ReturnType<typeof useRuntimeHost>;
