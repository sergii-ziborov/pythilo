import { deflateSync, Inflate, strFromU8, strToU8 } from "fflate";
import { validatePlaygroundDocument, type PlaygroundDocument } from "./playground-document.ts";

/**
 * Share links carry a whole project in the URL fragment, so no server holds it:
 *
 *   https://pythilo.com/playground/#code=<payload>
 *   pythilo://playground/#code=<payload>
 *
 * payload = base64url, no padding ( DEFLATE raw, RFC 1951 ( UTF-8 ( JSON ) ) )
 * JSON    = {"v":1,"name":"demo","main":"main.py","files":{"main.py":"print(1)\n"}}
 *
 * The format is described for other clients in PLAYGROUND-LINKS.md.
 */
export const SHARE_LINK_VERSION = 1;
export const SHARE_LINK_LIMITS = Object.freeze({
  /** Longest payload (characters after `code=`) a client writes or reads. */
  payloadChars: 100_000,
  /** Above this, some chat apps and mail clients shorten or break a link. */
  comfortableChars: 8_000,
  /** Inflating stops here, so a small link cannot expand into a huge one. */
  inflatedBytes: 1024 * 1024,
});

export type SharePayload = { v: 1; name: string; main: string; files: Record<string, string> };

const sortedFiles = (files: Record<string, string>) => {
  const result: Record<string, string> = {};
  for (const path of Object.keys(files).sort()) result[path] = files[path];
  return result;
};

export function sharePayloadJSON(document: PlaygroundDocument): string {
  const source = validatePlaygroundDocument(document);
  const payload: SharePayload = { v: SHARE_LINK_VERSION, name: source.name, main: source.entryFile, files: sortedFiles(source.files) };
  return JSON.stringify(payload);
}

function toBase64url(bytes: Uint8Array): string {
  let text = "";
  for (let i = 0; i < bytes.length; i += 8192) text += String.fromCharCode(...bytes.subarray(i, i + 8192));
  return btoa(text).replaceAll("+", "-").replaceAll("/", "_").replace(/=+$/, "");
}

function fromBase64(text: string): Uint8Array {
  // Lenient on read: standard alphabet, padding and line breaks from mail clients.
  const clean = text.replace(/\s+/g, "").replace(/=+$/, "").replaceAll("+", "-").replaceAll("/", "_");
  if (!clean || !/^[A-Za-z0-9_-]+$/.test(clean) || clean.length % 4 === 1) throw new Error("This share link is damaged. Copy the entire link.");
  const binary = atob(clean.replaceAll("-", "+").replaceAll("_", "/"));
  return Uint8Array.from(binary, character => character.charCodeAt(0));
}

function inflateLimited(bytes: Uint8Array): Uint8Array {
  const chunks: Uint8Array[] = []; let length = 0, done = false;
  const inflater = new Inflate((chunk, final) => {
    length += chunk.length;
    if (length > SHARE_LINK_LIMITS.inflatedBytes) throw new Error("This share link holds more than a Playground can open.");
    chunks.push(chunk); if (final) done = true;
  });
  try { inflater.push(bytes, true); }
  catch (error) { if (error instanceof Error && /more than a Playground/.test(error.message)) throw error; throw new Error("This share link is damaged. Copy the entire link."); }
  if (!done) throw new Error("This share link is cut short. Copy the entire link.");
  const result = new Uint8Array(length); let offset = 0;
  for (const chunk of chunks) { result.set(chunk, offset); offset += chunk.length; }
  return result;
}

/** The text after `code=`. Throws when the project cannot be shared or is too large for a link. */
export function encodeSharePayload(document: PlaygroundDocument): string {
  const payload = toBase64url(deflateSync(strToU8(sharePayloadJSON(document)), { level: 9 }));
  if (payload.length > SHARE_LINK_LIMITS.payloadChars) throw new Error("This project is too large for a link. Share a live room or download a ZIP instead.");
  return payload;
}

export function decodeSharePayload(payload: string): PlaygroundDocument {
  if (payload.length > SHARE_LINK_LIMITS.payloadChars * 1.1) throw new Error("This share link holds more than a Playground can open.");
  const text = strFromU8(inflateLimited(fromBase64(payload)));
  let value: unknown;
  try { value = JSON.parse(text); } catch { throw new Error("This share link is damaged. Copy the entire link."); }
  if (!value || typeof value !== "object" || Array.isArray(value)) throw new Error("This share link is damaged. Copy the entire link.");
  const data = value as Record<string, unknown>;
  if (typeof data.v !== "number" || data.v > SHARE_LINK_VERSION) throw new Error("This link was made by a newer Pythilo. Update the app or reload the page.");
  if (data.v !== SHARE_LINK_VERSION) throw new Error("This share link is damaged. Copy the entire link.");
  const files = data.files && typeof data.files === "object" && !Array.isArray(data.files) ? data.files as Record<string, unknown> : {};
  const pythonFiles = Object.keys(files).filter(path => path.endsWith(".py")).sort();
  const main = typeof data.main === "string" && data.main in files ? data.main : files["main.py"] !== undefined ? "main.py" : pythonFiles[0];
  if (main === undefined) throw new Error("This share link has no Python entry file.");
  const name = typeof data.name === "string" && data.name.trim() ? data.name.trim().slice(0, 80) : "shared-project";
  return validatePlaygroundDocument({ schemaVersion: 1, name, entryFile: main, files });
}

/** `code=` from a fragment such as `#code=…&other=…`; unknown keys are ignored. */
export function sharePayloadFromHash(hash: string): string | null {
  for (const part of hash.replace(/^#/, "").split("&")) {
    const at = part.indexOf("=");
    if (at > 0 && part.slice(0, at) === "code") return decodeURIComponent(part.slice(at + 1));
  }
  return null;
}

/** A project in a pasted or opened link, or null when the link carries none. Throws for a damaged link. */
export function parseShareLink(url: URL): PlaygroundDocument | null {
  const web = /^https?:$/.test(url.protocol) && /^\/playground\/?$/.test(url.pathname);
  const app = url.protocol === "pythilo:" && (url.host === "playground" || /^\/\/playground\/?$/.test(url.pathname));
  if (!web && !app) return null;
  const payload = sharePayloadFromHash(url.hash);
  return payload === null ? null : decodeSharePayload(payload);
}

export function shareLink(document: PlaygroundDocument, origin: string): string {
  return `${origin.replace(/\/+$/, "")}/playground/#code=${encodeSharePayload(document)}`;
}

/** The same project in the iPhone and iPad app. */
export function appShareLink(document: PlaygroundDocument): string {
  return `pythilo://playground/#code=${encodeSharePayload(document)}`;
}
