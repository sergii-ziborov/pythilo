import { mkdir, readFile, readdir, rename, writeFile } from "node:fs/promises";
import { join } from "node:path";

const marker = ".pythilo-build-id";
const archives = ".pythilo-previous-builds";

/** A mounted Next.js response cache must never serve another build's HTML/RSC. */
export async function prepareRouteCache(directory: string, build: string): Promise<number> {
  if (!/^[A-Za-z0-9_-]{1,160}$/.test(build)) throw new Error("Invalid site build ID.");
  let entries: string[];
  try { entries = await readdir(directory); }
  catch (error) { if ((error as NodeJS.ErrnoException).code === "ENOENT") return 0; throw error; }

  let previous = "unmarked";
  try { previous = (await readFile(join(directory, marker), "utf8")).trim(); }
  catch (error) { if ((error as NodeJS.ErrnoException).code !== "ENOENT") throw error; }
  if (previous === build) return 0;

  const old = entries.filter(entry => entry !== marker && entry !== archives);
  if (old.length) {
    const label = /^[A-Za-z0-9_-]{1,160}$/.test(previous) ? previous : "unmarked";
    const backup = join(directory, archives, `${label}-${Date.now()}`);
    await mkdir(backup, { recursive: true });
    for (const entry of old) await rename(join(directory, entry), join(backup, entry));
  }
  await writeFile(join(directory, marker), build + "\n", "utf8");
  return old.length;
}
