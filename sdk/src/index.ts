import { PlaygroundRoom } from './room.js';
import { configuredRelay } from './relay.js';
import type { Status,CreatedRoom,Snapshot,SourceFile,ApplyResult,Handoff,RuntimeClients,RuntimeRequest,RuntimeResult,StartOperation,InspectOperation } from './types.js';
export type * from './types.js';
export { PLAYGROUND_LIMITS } from './core/playground-document.js';
export { PythiloError } from './errors.js';
/** `relay` is the origin where create() makes rooms; it defaults to PYTHILO_RELAY. Joining uses the relay a link names. */
export type PythiloOptions = { name?: string; relay?: string };
export type CreateOptions = { name: string; files?: Record<string,string>; entryFile?: string; lifetimeMinutes?: number };
export type ApplyOptions = { expectedRevision: string; changes: { path: string; text: string | null }[]; entryFile?: string; name?: string };
/** One live temporary room per instance. Source stays encrypted at the relay.
 * Neither construction, edits nor a handoff run code. Call close() in finally.
 */
export class Pythilo {
  readonly #room: PlaygroundRoom;
  constructor(options: PythiloOptions = {}) { this.#room = new PlaygroundRoom(configuredRelay(options.relay)?.origin, options.name); }
  create(options: CreateOptions):Promise<CreatedRoom> { options=structuredClone(options); return this.#room.exclusive(()=>this.#room.create(options.name,options.files,options.entryFile,options.lifetimeMinutes)) as Promise<CreatedRoom>; }
  connect(link: string):Promise<Status> { return this.#room.exclusive(()=>this.#room.connect(link)); }
  status():Promise<Status> { return this.#room.exclusive(()=>this.#room.status()); }
  snapshot():Promise<Snapshot> { return this.#room.exclusive(()=>this.#room.snapshot()); }
  read(path: string):Promise<SourceFile> { return this.#room.exclusive(()=>this.#room.read(path)); }
  apply(options: ApplyOptions):Promise<ApplyResult> { options=structuredClone(options); return this.#room.exclusive(()=>this.#room.apply(options.expectedRevision,options.changes,options.entryFile,options.name)); }
  select(path: string,anchor: number,head: number,expectedRevision: string) { return this.#room.exclusive(()=>this.#room.select(path,anchor,head,expectedRevision)); }
  /** Explicitly returns a secret link for handoff to an intended participant. */
  share(mode?: 'edit'|'view'):Promise<Handoff> { return this.#room.exclusive(()=>this.#room.share(mode)); }
  runtimeClients():Promise<RuntimeClients> { return this.#room.exclusive(()=>this.#room.runtimeClients()) as Promise<RuntimeClients>; }
  requestRuntime(target:string,operations:StartOperation[]):Promise<RuntimeRequest> { return this.#room.exclusive(()=>this.#room.runtimeRequest(target,operations)) as Promise<RuntimeRequest>; }
  /** Starts check, run or test on a host that granted it. The acknowledgement is not success. */
  start(target:string,operation:StartOperation,sourceRevision:string):Promise<RuntimeResult> { return this.#room.exclusive(()=>this.#room.runtimeCommand(target,operation,sourceRevision)) as Promise<RuntimeResult>; }
  /** Read a job's status or paged output without changing it. */
  inspect(target:string,sourceRevision:string,job:string,operation:InspectOperation,options:{cursor?:number}={}):Promise<RuntimeResult> { options=structuredClone(options); return this.#room.exclusive(()=>this.#room.runtimeCommand(target,operation,sourceRevision,job,options)) as Promise<RuntimeResult>; }
  /** Stop a job this client started. */
  control(target:string,sourceRevision:string,job:string,operation:'stop'='stop'):Promise<RuntimeResult> { return this.#room.exclusive(()=>this.#room.runtimeCommand(target,operation,sourceRevision,job)) as Promise<RuntimeResult>; }
  endRoom() { return this.#room.exclusive(()=>this.#room.endRoom()); }
  disconnect() { return this.#room.exclusive(async()=>this.#room.disconnect()); }
  /** Synchronous cancellation releases network, keys and outstanding operations. */
  close() { this.#room.dispose(); }
}
