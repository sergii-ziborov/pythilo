import { mkdir, readFile, readdir, rename, rm, writeFile } from "node:fs/promises";
import { join } from "node:path";

const marker = ".pythilo-build-id";
const archives = ".pythilo-previous-builds";
/** Archived builds kept for inspection. Each one is a full set of page responses, about 90 MB. */
const keptArchives = 1;

const archivedAt = (name: string) => Number(name.match(/-(\d+)$/)?.[1] ?? 0);

/** Deletes all but the newest archived builds. They are derived pages; the mount would otherwise grow with every release. */
async function pruneArchives(directory: string): Promise<number> {
  let names: string[];
  try { names = await readdir(join(directory, archives)); }
  catch (error) { if ((error as NodeJS.ErrnoException).code === "ENOENT") return 0; throw error; }
  const stale = names.sort((a, b) => archivedAt(b) - archivedAt(a) || b.localeCompare(a)).slice(keptArchives);
  for (const name of stale) await rm(join(directory, archives, name), { recursive: true, force: true });
  return stale.length;
}

/**
 * A mounted Next.js response cache must never serve another build's HTML/RSC.
 * Returns how many entries of the previous build were set aside.
 */
export async function prepareRouteCache(directory: string, build: string): Promise<number> {
  if (!/^[A-Za-z0-9_-]{1,160}$/.test(build)) throw new Error("Invalid site build ID.");
  let entries: string[];
  try { entries = await readdir(directory); }
  catch (error) { if ((error as NodeJS.ErrnoException).code === "ENOENT") return 0; throw error; }

  let previous = "unmarked";
  try { previous = (await readFile(join(directory, marker), "utf8")).trim(); }
  catch (error) { if ((error as NodeJS.ErrnoException).code !== "ENOENT") throw error; }
  if (previous === build) { await pruneArchives(directory); return 0; }

  const old = entries.filter(entry => entry !== marker && entry !== archives);
  if (old.length) {
    const label = /^[A-Za-z0-9_-]{1,160}$/.test(previous) ? previous : "unmarked";
    const backup = join(directory, archives, `${label}-${Date.now()}`);
    await mkdir(backup, { recursive: true });
    for (const entry of old) await rename(join(directory, entry), join(backup, entry));
  }
  await writeFile(join(directory, marker), build + "\n", "utf8");
  await pruneArchives(directory);
  return old.length;
}
