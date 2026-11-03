export type PlaygroundDocument = { schemaVersion:1; name:string; entryFile:string; files:Record<string,string>; origin?:{url:string;commit?:string} };
export type Change = {path:string;text:string|null};
export type RemoteSelection = {clientID:number;name:string;color:string;file:string;anchor:number;head:number};
export type Status = {connected:boolean;connection:string;execution:string;relay?:string|null;room?:string;mode?:'edit'|'view';expiresAt?:string;remainingSeconds?:number;canEndRoom?:boolean;revision?:string;stateGenerationChecks?:boolean;lastOperation?:{outcome:'applied'|'not_applied'|'superseded';files:string[]};outcomeUnknown?:boolean;sequence?:number;name?:string;entryFile?:string;files?:{path:string;bytes:number}[];participants?:{name:string}[];selections?:RemoteSelection[];conditionalEdits?:boolean};
export type CreatedRoom = Status & {link:string;linkType:string;instructions:string;canEndRoom:true;expiresAt:string;revision:string};
export type SourceFile = {path:string;text:string;revision:string;contentTrust:string};
export type Snapshot = {document:PlaygroundDocument;revision:string;contentTrust:string};
export type ApplyResult = {changed:boolean;revision:string;acknowledgedSequence?:number;files?:string[];entryFile?:string;note?:string};
export type Handoff = {schema:string;linkType:string;link:string;expiresAt:string;revision:string;mode:'edit'|'view';execution:string;warning:string};
/** python3-v1: check, run and test start a job; status, stdout, stderr and diagnostics read it; stop ends it. */
export type StartOperation = 'check'|'run'|'test';
export type InspectOperation = 'status'|'stdout'|'stderr'|'diagnostics';
export type RuntimeOperation = 'discover'|'grant'|StartOperation|'stop'|InspectOperation|'revoke';
/** Where code runs, from the host's signed presence. `fingerprint` is the host's key; `runtime` names its Python. */
export type RuntimeHost = {kind:'browser'|'ios';name:string;runtime:string;fingerprint:string};
export type RuntimeJob = {job:string|null;operation:string;sourceRevision:string;ranOn:RuntimeHost;startedAt:string|null;durationMs:number|null;status:string;exitCode:number|null};
export type RuntimeClients = {controller:string;profile:'python3-v1';warnings:string[];source:{revision:string;paths:string[]};clients:(RuntimeHost&{revision:string;expires:number;profile:string;operations:StartOperation[];ready:boolean;busy:boolean;permissions:string;editConfirmed:boolean;grant?:{id:string;expires:number;operations:StartOperation[]}|null;job?:{id:string;requestID:string;operation:string;state:string}})[];jobs:RuntimeJob[];execution:string};
export type RuntimeRequest = {pending:true;controller:string;target:string;host:RuntimeHost;requestID:string;instructions:string};
/** The host's own reply fields (ok, state, text, next, items, reason …) plus where and how the job ran. */
export type RuntimeResult = RuntimeJob & {ok?:boolean;at:string} & Record<string,unknown>;
