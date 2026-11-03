import type { Awareness } from 'y-protocols/awareness';
import { createRuntimeSigner, verifyRuntimeEnvelope, RUNTIME_PROFILE, startOperations, type RuntimeEnvelope, type RuntimeOperation } from './playground-runtime-protocol.js';
import { publishRuntimePresence, remoteRuntimePresence } from './playground-presence.js';
import { runtimeSourceRevision } from './playground-runtime-source.js';
import { base64url } from './playground-crypto.js';
import { isWellFormedUTF16 } from './playground-document.js';
import type { PlaygroundSession } from './playground-session.js';
import type { PlaygroundDocument } from './playground-document.js';

/** Where code runs, as the host's signed presence says. A name is a label, not attestation; the fingerprint is its key. */
export type RuntimeHost = { kind: 'browser' | 'ios'; name: string; runtime: string; fingerprint: string };
type Client = RuntimeHost & { revision: string; expires: number; profile: string; operations: string[]; ready: boolean; busy: boolean; permissions: string; editConfirmed: boolean; job?: {id:string;requestID:string;operation:string;state:string} };
type Grant = { id: string; expires: number; operations: string[]; host: RuntimeHost };
type Job = { operation: string; revision: string; host: RuntimeHost; startedAt: number; state: string; exitCode: number | null; durationMs: number | null };
const startable = (op: unknown) => (startOperations as readonly string[]).includes(String(op));
const label = (value: unknown, maximum: number): value is string => typeof value === 'string' && value.length > 0 && value.length <= maximum && isWellFormedUTF16(value) && !/[\u0000-\u001f\u007f]/.test(value);
const jobID = /^[A-Za-z0-9_-]{16,64}$/;
export class RuntimeController {
  private signer: Awaited<ReturnType<typeof createRuntimeSigner>>;
  private clients = new Map<string, Client>();
  private grants = new Map<string, Grant>();
  private jobs = new Map<string, Job>();
  private waiting = new Map<string, { target: string; operation: string; revision: string; job: string; resolve: (value: any) => void; reject: (error: Error) => void }>();
  private seen = new Map<number, number>();
  private timer: ReturnType<typeof setInterval>;
  private stopped = false;
  private scanning = false;
  private warnings:string[]=[];
  private heartbeating = false;
  private publishing = Promise.resolve();
  private publishCount = 0;
  private publishedAt = 0;
  private requests = new Map<string,{target:string;revision:string;operations:string[];host:RuntimeHost}>();
  private publish(envelope:RuntimeEnvelope) {
    if(this.publishCount>=16) return Promise.reject(new Error('Runtime transport is busy.'));
    this.publishCount++;
    const next=this.publishing.then(async()=>{await new Promise(resolve=>setTimeout(resolve,Math.max(0,220-(Date.now()-this.publishedAt))));if(this.stopped)throw new Error('Runtime controller disconnected.');publishRuntimePresence(this.awareness,envelope);this.publishedAt=Date.now();});
    this.publishing=next.catch(()=>{});void next.finally(()=>{this.publishCount--;}).catch(()=>{});return next;
  }
  private constructor(private session: PlaygroundSession, private awareness: Awareness, private source: () => PlaygroundDocument, signer: Awaited<ReturnType<typeof createRuntimeSigner>>, private name = "Agent · Pythilo") {
    this.signer = signer; awareness.on('change', this.changed);
    this.timer = setInterval(() => { void this.heartbeat(); void this.scan(); }, 5000);
    session.onRuntimeReset = () => { this.clients.clear(); this.grants.clear(); this.requests.clear(); this.jobs.clear(); for (const pending of this.waiting.values()) pending.reject(new Error('Runtime connection changed.')); this.waiting.clear(); };
    void this.heartbeat(); void this.scan();
  }
  static async create(session: PlaygroundSession, awareness: Awareness, source: () => PlaygroundDocument, name = "Agent · Pythilo") { return new RuntimeController(session, awareness, source, await createRuntimeSigner(), name); }
  private changed = () => { void this.scan(); };
  private warn(warning:string){if(!this.warnings.includes(warning))this.warnings=[...this.warnings,warning].slice(-8);}
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
          if (h[1] === 'capabilities' && p?.role === 'host') {
            // A host says what it is: kind, display name, runtime fingerprint and the operations it accepts.
            if (p.profile !== RUNTIME_PROFILE || !['browser','ios'].includes(p.kind) || !label(p.name,60) || !label(p.runtime,80) || !Array.isArray(p.operations) || !p.operations.length || !p.operations.every(startable) || typeof p.ready !== 'boolean' || typeof p.busy !== 'boolean' || typeof p.editConfirmed !== 'boolean') { this.warn('A host without the python3-v1 profile, its kind, name, runtime fingerprint or operations was not listed.'); continue; }
            if(p.permissions!=='granted')this.grants.delete(frame.sender);
            const job=p.job?.controller===this.signer.fingerprint && typeof p.job.id==='string' && jobID.test(p.job.id) && typeof p.job.requestID==='string' && startable(p.job.operation) && ['working','finished'].includes(p.job.state)?{id:p.job.id,requestID:p.job.requestID,operation:p.job.operation,state:p.job.state}:undefined;
            const owned=job&&this.jobs.get(job.id);if(owned&&owned.state!=='finished')owned.state=job!.state;
            if (this.clients.has(frame.sender) || this.clients.size < 16) this.clients.set(frame.sender,{fingerprint:frame.sender,kind:p.kind,name:p.name,runtime:p.runtime,revision:h[7],expires:h[11],profile:p.profile,operations:[...p.operations],ready:p.ready,busy:p.busy,permissions:p.permissions,editConfirmed:p.editConfirmed,...(job?{job}:{})});
          } else if (h[1] === 'response' && h[4] === this.signer.fingerprint && frame.editAccessProved) {
            const pending=this.waiting.get(h[5]);
            if (!pending || pending.target!==frame.sender || pending.operation!==h[6] || (h[6]!=='grant' && pending.revision!==h[7]) || (pending.job && pending.job!==h[8])) continue;
            const request=this.requests.get(h[5]);
            if (h[6]==='grant' && request && p.ok===true && typeof p.grant==='string' && jobID.test(p.grant) && Number.isSafeInteger(p.expires) && Array.isArray(p.operations) && p.operations.length>0 && p.operations.length<=3 && new Set(p.operations).size===p.operations.length && p.operations.every(startable) && p.expires>Date.now() && p.expires<=Math.min(Date.now()+605000,this.session.link.expiresAt)) this.grants.set(frame.sender,{id:p.grant,expires:p.expires,operations:p.operations,host:request.host});
            this.waiting.delete(h[5]); this.requests.delete(h[5]); pending.resolve({...p,job:h[8]||p.job,sourceRevision:h[7]});
          }
        } catch(error) { this.warn(error instanceof Error?error.message:'Invalid runtime presence'); }
      }
      for (const [key,value] of this.clients) if(value.expires<=Date.now()) this.clients.delete(key);
    } finally { this.scanning=false; }
  }
  private hostOf(client: RuntimeHost): RuntimeHost { return { kind: client.kind, name: client.name, runtime: client.runtime, fingerprint: client.fingerprint }; }
  private jobSummary(id: string, job: Job) {
    return { job: id, operation: job.operation, sourceRevision: job.revision, ranOn: { ...job.host }, startedAt: new Date(job.startedAt).toISOString(), durationMs: job.durationMs, status: job.state, exitCode: job.exitCode };
  }
  status() {
    return {controller:this.signer.fingerprint,profile:RUNTIME_PROFILE,warnings:this.warnings,clients:[...this.clients.values()].filter(c=>c.expires>Date.now()).map(client=>({...client,grant:this.grants.get(client.fingerprint)?.expires!>Date.now()?(({host:_,...grant})=>grant)(this.grants.get(client.fingerprint)!):null})),
      jobs:[...this.jobs].map(([id,job])=>this.jobSummary(id,job)),
      execution:'A host in the room runs code only after its owner allows it there; the relay never runs code. Compare this controller key on that device or browser.'};
  }
  async request(target: string,operations:string[]) {
    await this.session.confirmRuntimeEditAccess();
    const client=this.clients.get(target);
    if(!client||client.expires<=Date.now()) throw new Error('Runtime host is not listed now. Read runtime clients again and choose a listed host.');
    if(!operations.length||new Set(operations).size!==operations.length||operations.some(op=>!client.operations.includes(op))) throw new Error('Runtime host does not offer '+operations.join(', ')+'. It offers '+client.operations.join(', ')+'.');
    const revision=await runtimeSourceRevision(this.source()), requestID=base64url(crypto.getRandomValues(new Uint8Array(18)));
    const envelope=await this.signer.sign({kind:'permission-request',room:this.session.link.id,target,requestID,operation:'grant',revision},{name:this.name,operations},{editCapability:this.session.link.access});
    // The acknowledgement may arrive long after the tool returns, while the
    // owner decides on the host. Keep a bounded pending grant listener.
    if(this.waiting.size>=8) throw new Error('Too many pending runtime requests.');
    const timeout=setTimeout(()=>{this.waiting.delete(requestID);this.requests.delete(requestID);},120_000);
    this.waiting.set(requestID,{target,operation:'grant',revision,job:'',resolve:()=>clearTimeout(timeout),reject:()=>clearTimeout(timeout)});
    this.requests.set(requestID,{target,revision,operations,host:this.hostOf(client)});
    await this.publish(envelope);
    return {pending:true,controller:this.signer.fingerprint,target,host:this.hostOf(client),requestID,instructions:'The host asks its owner on that device or browser, unless the owner chose otherwise for this room. They can compare this controller key there. Poll runtime clients for the grant; no code has run.'};
  }
  async command(target:string,operation:RuntimeOperation,revision:string,job='',arguments_:Record<string,unknown>={}) {
    const grant=this.grants.get(target);
    if(!grant||grant.expires<=Date.now()) throw new Error('No current grant from this host. Request access and let its owner allow it there.');
    if(startable(operation)&&!grant.operations.includes(operation)) throw new Error('No current grant from this host for '+operation+'; its owner allowed '+grant.operations.join(', ')+'. Request access again.');
    const requestID=base64url(crypto.getRandomValues(new Uint8Array(18)));
    const envelope=await this.signer.sign({kind:'command',room:this.session.link.id,target,requestID,operation,revision,job},{grant:grant.id,...arguments_},{editCapability:this.session.link.access});
    const reply=await this.exchange(envelope,target,operation,revision,job);
    return this.result(grant.host,operation,revision,reply);
  }
  // Every result says where it ran, on which runtime and source, when it started, how long it took, its state and exit code.
  private result(host:RuntimeHost,operation:string,revision:string,reply:Record<string,unknown>) {
    const id=typeof reply.job==='string'?reply.job:'';
    let job=this.jobs.get(id);
    if(!job&&startable(operation)&&reply.ok===true&&jobID.test(id)){
      job={operation,revision,host,startedAt:Date.now(),state:'working',exitCode:null,durationMs:null};
      this.jobs.set(id,job); if(this.jobs.size>16) this.jobs.delete(this.jobs.keys().next().value!);
    }
    if(job&&reply.ok===true){
      if(label(reply.state,20)) job.state=reply.state;
      if(reply.exitCode===null||Number.isSafeInteger(reply.exitCode)) job.exitCode=reply.exitCode as number|null;
      if(Number.isSafeInteger(reply.durationMs)&&(reply.durationMs as number)>=0) job.durationMs=reply.durationMs as number;
      // A host's own start time is used when it is close to what this bridge observed.
      if(Number.isSafeInteger(reply.startedAt)&&Math.abs((reply.startedAt as number)-job.startedAt)<=600_000) job.startedAt=reply.startedAt as number;
    }
    const summary=job?this.jobSummary(id,job):{job:id||null,operation,sourceRevision:revision,ranOn:{...host},startedAt:null,durationMs:null,status:reply.ok===false?'refused':'unknown',exitCode:null};
    return {...reply,...summary,at:new Date().toISOString()};
  }
  private async exchange(envelope:RuntimeEnvelope,target:string,operation:string,revision:string,job:string):Promise<any> {
    if(this.waiting.size>=8) throw new Error('Too many pending runtime commands.');
    const requestID=envelope.header[5];
    return new Promise((resolve,reject)=>{
      const timeout=setTimeout(()=>{clearInterval(retry);this.waiting.delete(requestID);reject(new Error('Host acknowledgement timed out. Poll runtime clients and the job before deciding whether to start a new job.'));},10_000);
      const retry=setInterval(()=>{if(!this.stopped) void this.publish(envelope).catch(()=>{})},1500);
      this.waiting.set(requestID,{target,operation,revision,job,resolve:value=>{clearTimeout(timeout);clearInterval(retry);resolve(value);},reject:error=>{clearTimeout(timeout);clearInterval(retry);reject(error);}});
      void this.publish(envelope).catch(error=>{this.waiting.delete(requestID);clearTimeout(timeout);clearInterval(retry);reject(error);});
    });
  }
  close(){this.stopped=true;clearInterval(this.timer);this.awareness.off('change',this.changed);for(const pending of this.waiting.values())pending.reject(new Error('Runtime controller disconnected.'));this.waiting.clear();this.requests.clear();this.grants.clear();this.clients.clear();this.jobs.clear();this.signer.destroy();}
}
