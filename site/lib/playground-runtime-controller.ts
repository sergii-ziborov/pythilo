import type { Awareness } from 'y-protocols/awareness';
import { createRuntimeSigner, verifyRuntimeEnvelope, RUNTIME_PROFILE, type RuntimeEnvelope, type RuntimeOperation } from './playground-runtime-protocol.ts';
import { remoteRuntimePresence } from './playground-presence.ts';
import { runtimeSourceRevision } from './playground-runtime-source.ts';
import { runtimeActions, type RuntimeAction } from './playground-runtime-authority.ts';
import type { RuntimeHostKind } from './playground-runtime-host.ts';
import type { RuntimePresenceChannel } from './playground-runtime-channel.ts';
import { base64url } from './playground-crypto.ts';
import type { PlaygroundSession } from './playground-session.ts';
import type { PlaygroundDocument } from './playground-document.ts';

export type RuntimeClient = { fingerprint: string; revision: string; expires: number; name: string; kind: RuntimeHostKind; runtime: string; profile: string; operations: RuntimeAction[]; ready: boolean; busy: boolean; permissions: string; editConfirmed: boolean; job?: {id:string;requestID:string;operation:string;state:string} };
type Grant = { id: string; expires: number; operations: string[] };
export type RemoteRunResult = { operation: RuntimeAction; job: string; revision: string; state: string; succeeded: boolean; exitCode: number | null; startedAt: number; durationMs: number; ranOn: { name: string; kind: RuntimeHostKind }; runtime: string; stdout: string; stderr: string; diagnostics: unknown[]; truncated: boolean; stopped: boolean };
const isAction = (op: unknown): op is RuntimeAction => runtimeActions.includes(op as RuntimeAction);
const sleep = (ms: number) => new Promise(resolve => setTimeout(resolve, ms));

/** Asks a device in the room to run shared source. It never runs code itself. */
export class RuntimeController {
  private signer: Awaited<ReturnType<typeof createRuntimeSigner>>;
  private clients = new Map<string, RuntimeClient>();
  private grants = new Map<string, Grant>();
  private waiting = new Map<string, { target: string; operation: string; revision: string; job: string; resolve: (value: any) => void; reject: (error: Error) => void }>();
  private seen = new Map<number, number>();
  private timer: ReturnType<typeof setInterval>;
  private stopped = false;
  private scanning = false;
  private warnings:string[]=[];
  private heartbeating = false;
  private requests = new Map<string,{target:string;revision:string;operations:string[]}>();
  private releaseReset: () => void;
  private session: PlaygroundSession;
  private awareness: Awareness;
  private source: () => PlaygroundDocument;
  private channel: RuntimePresenceChannel;
  private name: string;
  private constructor(session: PlaygroundSession, awareness: Awareness, source: () => PlaygroundDocument, signer: Awaited<ReturnType<typeof createRuntimeSigner>>, channel: RuntimePresenceChannel, name: string) {
    this.session = session; this.awareness = awareness; this.source = source; this.channel = channel; this.name = name;
    this.signer = signer; awareness.on('change', this.changed);
    this.timer = setInterval(() => { void this.heartbeat(); void this.scan(); }, 5000);
    this.releaseReset = session.onRuntimeReset(() => { this.clients.clear(); this.grants.clear(); this.requests.clear(); for (const pending of this.waiting.values()) pending.reject(new Error('Runtime connection changed.')); this.waiting.clear(); });
    void this.heartbeat(); void this.scan();
  }
  static async create(session: PlaygroundSession, awareness: Awareness, source: () => PlaygroundDocument, channel: RuntimePresenceChannel, name: string) { return new RuntimeController(session, awareness, source, await createRuntimeSigner(), channel, name); }
  get fingerprint() { return this.signer.fingerprint; }
  private changed = () => { void this.scan(); };
  private publish(envelope: RuntimeEnvelope) { return this.channel.publish(envelope); }
  private async heartbeat() {
    if(this.heartbeating)return;this.heartbeating=true;
    try {
      if (this.stopped || !this.session.connected || !this.session.runtimeEditConfirmed) return;
      const envelope = await this.signer.sign({ kind:'capabilities',room:this.session.link.id,target:'',requestID:base64url(crypto.getRandomValues(new Uint8Array(18))),operation:'discover' }, { role:'controller',name:this.name }, { editCapability:this.session.link.access });
      if (!this.stopped) await this.publish(envelope);
      for(const [requestID,request] of this.requests){
        const packet=await this.signer.sign({kind:'permission-request',room:this.session.link.id,target:request.target,requestID,operation:'grant',revision:request.revision},{name:this.name,operations:request.operations},{editCapability:this.session.link.access});
        await this.publish(packet);
      }
    } catch { /* View access and reconnecting never imply execution permission. */ }
    finally {this.heartbeating=false;}
  }
  private async scan() {
    if (this.scanning || this.stopped) return; this.scanning = true;
    try {
      const peers=remoteRuntimePresence(this.awareness), live=new Set(peers.map(p=>p.clientID));for(const id of this.seen.keys())if(!live.has(id))this.seen.delete(id);
      for (const item of peers) {
        if (this.seen.get(item.clientID) === item.clock) continue; this.seen.set(item.clientID,item.clock);
        try {
          const frame = await verifyRuntimeEnvelope(JSON.parse(item.envelope),{room:this.session.link.id,editCapability:this.session.link.access});
          if (this.stopped) return;
          const p = frame.payload as any, h=frame.header;
          if (h[1] === 'capabilities' && p?.role === 'host' && typeof p.name === 'string' && p.name.length <= 60 && ['browser','ios'].includes(p.kind) && typeof p.runtime === 'string' && p.runtime.length <= 60 && p.profile === RUNTIME_PROFILE && Array.isArray(p.operations) && p.operations.every(isAction) && typeof p.ready === 'boolean' && typeof p.busy === 'boolean' && typeof p.editConfirmed === 'boolean') {
            if(p.permissions!=='granted')this.grants.delete(frame.sender);
            if (this.clients.has(frame.sender) || this.clients.size < 16) this.clients.set(frame.sender,{fingerprint:frame.sender,revision:h[7],expires:h[11],name:p.name,kind:p.kind,runtime:p.runtime,profile:p.profile,operations:p.operations,ready:p.ready,busy:p.busy,permissions:p.permissions,editConfirmed:p.editConfirmed,...(p.job?.controller===this.signer.fingerprint && typeof p.job.id==='string' && /^[A-Za-z0-9_-]{16,64}$/.test(p.job.id) && typeof p.job.requestID==='string' && isAction(p.job.operation) && ['working','finished'].includes(p.job.state)?{job:{id:p.job.id,requestID:p.job.requestID,operation:p.job.operation,state:p.job.state}}:{})});
          } else if (h[1] === 'response' && h[4] === this.signer.fingerprint && frame.editAccessProved) {
            const pending=this.waiting.get(h[5]);
            if (!pending || pending.target!==frame.sender || pending.operation!==h[6] || (h[6]!=='grant' && pending.revision!==h[7]) || (pending.job && pending.job!==h[8])) continue;
            if (h[6]==='grant' && p.ok===true && typeof p.grant==='string' && /^[A-Za-z0-9_-]{16,64}$/.test(p.grant) && Number.isSafeInteger(p.expires) && Array.isArray(p.operations) && p.operations.length>0 && p.operations.length<=3 && new Set(p.operations).size===p.operations.length && p.operations.every(isAction) && p.expires>Date.now() && p.expires<=Math.min(Date.now()+605000,this.session.link.expiresAt)) this.grants.set(frame.sender,{id:p.grant,expires:p.expires,operations:p.operations});
            this.waiting.delete(h[5]); this.requests.delete(h[5]); pending.resolve({...p,job:h[8]||p.job,sourceRevision:h[7]});
          }
        } catch(error) { const warning=error instanceof Error?error.message:'Invalid runtime presence';if(!this.warnings.includes(warning))this.warnings=[...this.warnings,warning].slice(-8); }
      }
      for (const [key,value] of this.clients) if(value.expires<=Date.now()) this.clients.delete(key);
    } finally { this.scanning=false; }
  }
  status() {
    return {controller:this.signer.fingerprint,warnings:this.warnings,clients:[...this.clients.values()].filter(c=>c.expires>Date.now()).map(client=>({...client,grant:this.grants.get(client.fingerprint)?.expires!>Date.now()?this.grants.get(client.fingerprint)!:null})),pending:[...this.requests.values()].map(request=>request.target)};
  }
  async request(target: string,operations:RuntimeAction[]) {
    await this.session.confirmRuntimeEditAccess();
    const revision=await runtimeSourceRevision(this.source()), requestID=base64url(crypto.getRandomValues(new Uint8Array(18)));
    const envelope=await this.signer.sign({kind:'permission-request',room:this.session.link.id,target,requestID,operation:'grant',revision},{name:this.name,operations},{editCapability:this.session.link.access});
    // The acknowledgement may arrive long after this returns, while the human
    // on the target chooses. Keep a bounded pending grant listener.
    if(this.waiting.size>=8) throw new Error('Too many pending runtime requests.');
    for (const [id, value] of this.requests) if (value.target === target) { this.requests.delete(id); this.waiting.get(id)?.reject(new Error('Replaced by a new request.')); this.waiting.delete(id); }
    const timeout=setTimeout(()=>{this.waiting.delete(requestID);this.requests.delete(requestID);},120_000);
    this.waiting.set(requestID,{target,operation:'grant',revision,job:'',resolve:()=>clearTimeout(timeout),reject:()=>clearTimeout(timeout)});
    this.requests.set(requestID,{target,revision,operations});
    await this.publish(envelope);
    return {pending:true,controller:this.signer.fingerprint,target,requestID};
  }
  async command(target:string,operation:RuntimeOperation,revision:string,job='',arguments_:Record<string,unknown>={}) {
    const grant=this.grants.get(target);
    if(!grant||grant.expires<=Date.now()) throw new Error('No current grant from this device. Ask it again and let its owner allow it.');
    const requestID=base64url(crypto.getRandomValues(new Uint8Array(18)));
    const envelope=await this.signer.sign({kind:'command',room:this.session.link.id,target,requestID,operation,revision,job},{grant:grant.id,...arguments_},{editCapability:this.session.link.access});
    return this.exchange(envelope,target,operation,revision,job);
  }
  private async exchange(envelope:RuntimeEnvelope,target:string,operation:string,revision:string,job:string):Promise<any> {
    if(this.waiting.size>=8) throw new Error('Too many pending runtime commands.');
    const requestID=envelope.header[5];
    return new Promise((resolve,reject)=>{
      const timeout=setTimeout(()=>{clearInterval(retry);this.waiting.delete(requestID);reject(new Error('The device did not answer. It may be busy, locked or offline.'));},10_000);
      const retry=setInterval(()=>{if(!this.stopped) void this.publish(envelope).catch(()=>{})},1500);
      this.waiting.set(requestID,{target,operation,revision,job,resolve:value=>{clearTimeout(timeout);clearInterval(retry);resolve(value);},reject:error=>{clearTimeout(timeout);clearInterval(retry);reject(error);}});
      void this.publish(envelope).catch(error=>{this.waiting.delete(requestID);clearTimeout(timeout);clearInterval(retry);reject(error);});
    });
  }
  /** Starts one operation on a host that granted it, then reads its result pages. */
  async follow(target: string, operation: RuntimeAction, onStage: (stage: string, job: string) => void = () => {}): Promise<RemoteRunResult> {
    const revision = await runtimeSourceRevision(this.source());
    const started = await this.command(target, operation, revision);
    if (started.ok !== true || typeof started.job !== 'string') throw new Error(typeof started.reason === 'string' ? started.reason : 'The device refused this request.');
    const job: string = started.job, deadline = Date.now() + 135_000;
    let status: any;
    onStage('Started', job);
    while (true) {
      await sleep(700);
      if (this.stopped) throw new Error('Runtime controller disconnected.');
      status = await this.command(target, 'status', revision, job);
      if (status.ok !== true) throw new Error(typeof status.reason === 'string' ? status.reason : 'The device stopped answering about this job.');
      if (status.state === 'finished') break;
      if (typeof status.stage === 'string') onStage(status.stage, job);
      if (Date.now() > deadline) throw new Error('The device did not finish within its two-minute limit.');
    }
    let truncated = status.truncated === true;
    const text = async (stream: 'stdout' | 'stderr') => {
      let out = '', cursor: number | null = 0, pages = 0;
      while (cursor !== null && pages++ < 24) {
        const page = await this.command(target, stream, revision, job, { cursor });
        if (page.ok !== true || typeof page.text !== 'string') break;
        out += page.text; cursor = Number.isSafeInteger(page.next) ? page.next : null;
      }
      if (cursor !== null) truncated = true;
      return out;
    };
    const stdout = await text('stdout'), stderr = await text('stderr');
    const diagnostics: unknown[] = [];
    for (let cursor: number | null = 0, pages = 0; cursor !== null && pages < 8; pages++) {
      const page = await this.command(target, 'diagnostics', revision, job, { cursor });
      if (page.ok !== true || !Array.isArray(page.items)) break;
      diagnostics.push(...page.items); cursor = Number.isSafeInteger(page.next) ? page.next : null;
    }
    const client = this.clients.get(target);
    return { operation, job, revision, state: status.state, succeeded: status.succeeded === true, exitCode: Number.isSafeInteger(status.exitCode) ? status.exitCode : null,
      startedAt: Number.isSafeInteger(status.startedAt) ? status.startedAt : Number(started.startedAt) || Date.now(), durationMs: Number.isSafeInteger(status.durationMs) ? status.durationMs : 0,
      ranOn: { name: typeof status.ranOn?.name === 'string' ? status.ranOn.name : client?.name ?? 'Another device', kind: status.ranOn?.kind === 'ios' ? 'ios' : status.ranOn?.kind === 'browser' ? 'browser' : client?.kind ?? 'browser' },
      runtime: typeof status.runtime === 'string' ? status.runtime : client?.runtime ?? '', stdout, stderr, diagnostics, truncated, stopped: /stop/i.test(String(status.stage ?? '')) && status.succeeded !== true };
  }
  close(){this.stopped=true;clearInterval(this.timer);this.releaseReset();this.awareness.off('change',this.changed);for(const pending of this.waiting.values())pending.reject(new Error('Runtime controller disconnected.'));this.waiting.clear();this.requests.clear();this.grants.clear();this.clients.clear();this.signer.destroy();}
}
