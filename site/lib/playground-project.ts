import * as Y from "yjs";
import { strToU8, zipSync } from "fflate";
import { documentFromY } from "./playground-collab.ts";
import type { PlaygroundDocument } from "./playground-document.ts";

export type ProjectFileView = { key: string; path: string; text: string };
export type ProjectView = { document: PlaygroundDocument; files: ProjectFileView[]; entryKey: string };

/** Throws while the document is invalid or still empty. */
export function readView(doc: Y.Doc): ProjectView {
  const document = documentFromY(doc);
  return { document, files: Object.entries(document.files).map(([path, text]) => ({ key: path, path, text })), entryKey: document.entryFile };
}

/** The editor's text for a file, or null when that file is not in the project. */
export function fileText(doc: Y.Doc, view: ProjectView, key: string): Y.Text | null {
  if (!view.files.some(file => file.key === key)) return null;
  const text = doc.getMap<Y.Text>("files").get(key); return text instanceof Y.Text ? text : null;
}

export function exportArchive(document: PlaygroundDocument): Uint8Array {
  const files: Record<string, Uint8Array> = {};
  for (const [path, text] of Object.entries(document.files)) files[path] = strToU8(text);
  return zipSync(files);
}

/** Name, entry, origin and every file, for "the source changed after this result". */
export function documentRevision(document: PlaygroundDocument): string {
  const files = Object.keys(document.files).sort().map(path => [path, document.files[path]]);
  return JSON.stringify([document.name, document.entryFile, document.origin ?? null, files]);
}
