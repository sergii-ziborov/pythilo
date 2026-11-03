// Bundled, fixed CRDT implementation for JavaScriptCore. User source is data;
// it is never evaluated as JavaScript. Encryption and transport stay native.
import * as Y from "yjs";
import { documentFromY, updateYDocument } from "../lib/playground-collab.ts";
import { createPresence, localPresence, receivePresence, remoteSelections, publishRuntimePresence, remoteRuntimePresence } from "../lib/playground-presence.ts";
import { validatePlaygroundDocument } from "../lib/playground-document.ts";
import { runtimeSource } from "../lib/playground-runtime-source.ts";
export { callRuntime } from "./playground-runtime-policy.ts";
export { callHost } from "./playground-runtime-host.ts";
const doc = new Y.Doc(), awareness = createPresence(doc);
const remote = {}, pending: Uint8Array[] = [];
let presenceDirty = true;
doc.on("update", (bytes: Uint8Array, origin: unknown) => { if (origin !== remote) pending.push(bytes); });
awareness.on("update", (_: unknown, origin: unknown) => { if (origin !== remote) presenceDirty = true; });

// Snapshots and updates cross the bridge as standard base64: a byte array of a 256 KiB
// snapshot would not fit the 2,000,000 character message. The prelude's atob is
// limited to small values, so these run here.
const alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
const lookup = new Map(Array.from(alphabet, (character, index) => [character.charCodeAt(0), index]));
export function decodeBase64(text: unknown, maximumBytes: number): Uint8Array {
  if (typeof text !== "string" || text.length % 4 !== 0 || text.length / 4 * 3 > maximumBytes + 2 || !/^[A-Za-z0-9+/]*={0,2}$/.test(text)) throw new Error("Invalid native collaboration bytes.");
  const padding = text.endsWith("==") ? 2 : text.endsWith("=") ? 1 : 0, bytes = new Uint8Array(text.length / 4 * 3 - padding);
  for (let i = 0, o = 0; i < text.length; i += 4) {
    const value = [0, 1, 2, 3].reduce((n, k) => n << 6 | (text[i + k] === "=" ? 0 : lookup.get(text.charCodeAt(i + k))!), 0);
    for (const shift of [16, 8, 0]) if (o < bytes.length) bytes[o++] = value >> shift & 255;
  }
  if (bytes.length > maximumBytes) throw new Error("Oversized native collaboration bytes.");
  return bytes;
}
export function encodeBase64(bytes: Uint8Array): string {
  const parts: string[] = [];
  for (let start = 0; start < bytes.length; start += 6144) {
    let chunk = "";
    for (let i = start; i < Math.min(bytes.length, start + 6144); i += 3) {
      const value = bytes[i] << 16 | (i + 1 < bytes.length ? bytes[i + 1] << 8 : 0) | (i + 2 < bytes.length ? bytes[i + 2] : 0);
      chunk += alphabet[value >> 18 & 63] + alphabet[value >> 12 & 63] + (i + 1 < bytes.length ? alphabet[value >> 6 & 63] : "=") + (i + 2 < bytes.length ? alphabet[value & 63] : "=");
    }
    parts.push(chunk);
  }
  return parts.join("");
}
const bytesOf = (value: unknown, maximum: number) => Array.isArray(value) ? Uint8Array.from(value as number[]) : decodeBase64(value, maximum);

export function call(requestJSON: string): string {
  try {
    const request = JSON.parse(requestJSON);
    switch (request.type) {
      case "initialize": updateYDocument(doc, validatePlaygroundDocument(request.document)); break;
      case "document": break;
      case "runtime-presence": publishRuntimePresence(awareness, request.envelope ?? null); break;
      case "runtime-source": {
        const source = runtimeSource(documentFromY(doc));
        return JSON.stringify({ runtimeSource: source.canonical, runtimePaths: source.paths });
      }
      case "replace": updateYDocument(doc, validatePlaygroundDocument(request.document)); break;
      case "file": { const value = documentFromY(doc); value.files[request.path] = request.text; updateYDocument(doc, validatePlaygroundDocument(value)); break; }
      case "snapshot": break;
      case "merge": return JSON.stringify({ merged: encodeBase64(Y.mergeUpdates(request.updates.map((value: unknown) => bytesOf(value, 196_608)))) });
      case "state": {
        if (request.codec !== undefined && request.codec !== 1) throw new Error("This Playground uses a newer format. Update Pythilo to open it.");
        const candidate = new Y.Doc();
        try {
          Y.applyUpdate(candidate, bytesOf(request.snapshot, 256 * 1024));
          for (const bytes of request.events) Y.applyUpdate(candidate, bytesOf(bytes, 196_608));
          documentFromY(candidate);
          const delta = Y.encodeStateAsUpdate(doc, Y.encodeStateVector(candidate));
          if (delta.length > 2) pending.push(delta);
          Y.applyUpdate(doc, Y.encodeStateAsUpdate(candidate), remote);
        } finally { candidate.destroy(); }
        break;
      }
      case "update": {
        const bytes = bytesOf(request.bytes, 196_608);
        const candidate = new Y.Doc();
        try { Y.applyUpdate(candidate, Y.encodeStateAsUpdate(doc)); Y.applyUpdate(candidate, bytes); documentFromY(candidate); Y.applyUpdate(doc, bytes, remote); }
        finally { candidate.destroy(); }
        break;
      }
      case "selection": {
        const text = doc.getMap<Y.Text>("files").get(request.file);
        if (text) awareness.setLocalStateField("cursor", {
          anchor: Y.createRelativePositionFromTypeIndex(text, Math.max(0, Math.min(text.length, request.anchor))),
          head: Y.createRelativePositionFromTypeIndex(text, Math.max(0, Math.min(text.length, request.head))),
        });
        break;
      }
      case "identity": {
        // The app's own display name, so other participants see who is here.
        const name = typeof request.name === "string" ? request.name.trim() : "";
        if (!name || name.length > 40 || /[\u0000-\u001f\u007f]/.test(name)) throw new Error("Choose a display name of up to 40 characters.");
        const state = awareness.getLocalState();
        awareness.setLocalStateField("user", { ...(state?.user ?? {}), name });
        break;
      }
      case "presence": receivePresence(awareness, Uint8Array.from(request.bytes), remote); break;
      case "tick": (globalThis as unknown as { __tick: () => void }).__tick(); break;
      default: throw new Error("Unsupported collaboration operation.");
    }
    const result: Record<string, unknown> = { clientID: doc.clientID, selections: remoteSelections(doc, awareness), participants: awareness.getStates().size };
    result.runtimeFrames = remoteRuntimePresence(awareness);
    result.localSelection = remoteSelections(doc, awareness, true).find(value => value.clientID === doc.clientID);
    if (doc.getMap("files").size) result.document = documentFromY(doc);
    if (request.type === "snapshot") result.snapshot = encodeBase64(Y.encodeStateAsUpdate(doc));
    if (presenceDirty || request.type === "tick") { result.presence = Array.from(localPresence(awareness)); presenceDirty = false; }
    // Last, so a failure while reading the project above cannot drop outgoing edits.
    const updates = pending.splice(0);
    if (updates.length) result.update = encodeBase64(Y.mergeUpdates(updates));
    return JSON.stringify(result);
  } catch (error) { return JSON.stringify({ error: error instanceof Error ? error.message : String(error) }); }
}
