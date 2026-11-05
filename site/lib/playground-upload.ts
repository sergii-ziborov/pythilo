import { unzipSync } from "fflate";
import { isValidSourcePath, isValidSourceText, PLAYGROUND_LIMITS } from "./playground-document.ts";

export type UploadedFile = { name: string; bytes: Uint8Array };
export type UploadResult = { files: Record<string, string>; skipped: string[] };

const decoder = () => new TextDecoder("utf-8", { fatal: true });

/** Drops one folder that holds everything, as in GitHub's "Download ZIP". */
function withoutSharedRoot(paths: string[]): (path: string) => string {
  const first = paths[0]?.split("/")[0];
  // A Python package at the top stays, so its imports keep working.
  if (!first || paths.some(path => !path.startsWith(first + "/")) || paths.includes(`${first}/__init__.py`)) return path => path;
  return path => path.slice(first.length + 1);
}

/**
 * Text files for the project from picked or dropped files. A .zip is unpacked.
 * Binary, unsupported or oversized files are skipped and named in `skipped`.
 * `folder` puts plain files (not ZIP contents) inside that folder.
 */
export function readUploads(uploads: UploadedFile[], folder = ""): UploadResult {
  const files: Record<string, string> = {}, skipped: string[] = [];
  const take = (path: string, bytes: Uint8Array) => {
    if (/(^|\/)(__MACOSX|\.DS_Store)(\/|$)/.test(path)) return;
    let text: string;
    try { text = decoder().decode(bytes).replace(/^﻿/, ""); } catch { skipped.push(path); return; }
    if (!isValidSourcePath(path) || !isValidSourceText(text) || bytes.length > PLAYGROUND_LIMITS.fileBytes) { skipped.push(path); return; }
    files[path] = text;
  };
  for (const upload of uploads) {
    if (/\.zip$/i.test(upload.name)) {
      let entries: Record<string, Uint8Array>;
      try { entries = unzipSync(upload.bytes, { filter: file => !file.name.endsWith("/") && file.originalSize <= PLAYGROUND_LIMITS.fileBytes * 4 }); }
      catch { skipped.push(upload.name); continue; }
      const strip = withoutSharedRoot(Object.keys(entries).filter(path => !/(^|\/)__MACOSX\//.test(path)));
      for (const [path, bytes] of Object.entries(entries)) if (!/(^|\/)__MACOSX\//.test(path)) take(strip(path), bytes);
    } else take(folder ? `${folder}/${upload.name}` : upload.name, upload.bytes);
  }
  return { files, skipped };
}
