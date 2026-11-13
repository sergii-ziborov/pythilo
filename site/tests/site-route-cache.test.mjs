import assert from "node:assert/strict";
import { mkdtemp, mkdir, readFile, readdir, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import { prepareRouteCache } from "../lib/site-route-cache.ts";

test("a release quarantines old HTML, same-build restarts keep current pages, and the next release rotates them", async () => {
  const root = await mkdtemp(join(tmpdir(), "pythilo-route-cache-"));
  try {
    await mkdir(join(root, "APP_PAGE"));
    await writeFile(join(root, "APP_PAGE", "index.html"), "old website");
    assert.equal(await prepareRouteCache(root, "build-one"), 1);
    await assert.rejects(readFile(join(root, "APP_PAGE", "index.html")), { code: "ENOENT" });
    const [backup] = await readdir(join(root, ".pythilo-previous-builds"));
    assert.equal(await readFile(join(root, ".pythilo-previous-builds", backup, "APP_PAGE", "index.html"), "utf8"), "old website");
    await mkdir(join(root, "APP_PAGE"));
    await writeFile(join(root, "APP_PAGE", "index.html"), "current website");
    assert.equal(await prepareRouteCache(root, "build-one"), 0);
    assert.equal(await readFile(join(root, "APP_PAGE", "index.html"), "utf8"), "current website");
    assert.equal(await prepareRouteCache(root, "build-two"), 1);
    await assert.rejects(readFile(join(root, "APP_PAGE", "index.html")), { code: "ENOENT" });
    assert.equal((await readFile(join(root, ".pythilo-build-id"), "utf8")).trim(), "build-two");
    // Only the newest archived build is kept, so the mount stops growing with every release.
    const [kept, ...others] = await readdir(join(root, ".pythilo-previous-builds"));
    assert.deepEqual(others, []);
    assert.match(kept, /^build-one-\d+$/);
    assert.equal(await readFile(join(root, ".pythilo-previous-builds", kept, "APP_PAGE", "index.html"), "utf8"), "current website");
  } finally { await rm(root, { recursive: true, force: true }); }
});

test("a restart of the same build clears archives left by earlier releases", async () => {
  const root = await mkdtemp(join(tmpdir(), "pythilo-route-cache-"));
  try {
    for (const name of ["unmarked-1000", "build-a-2000", "build-b-3000", "stray"]) {
      await mkdir(join(root, ".pythilo-previous-builds", name, "APP_PAGE"), { recursive: true });
      await writeFile(join(root, ".pythilo-previous-builds", name, "APP_PAGE", "index.html"), name);
    }
    await writeFile(join(root, ".pythilo-build-id"), "build-c\n");
    await mkdir(join(root, "APP_PAGE"));
    await writeFile(join(root, "APP_PAGE", "index.html"), "current website");
    assert.equal(await prepareRouteCache(root, "build-c"), 0);
    assert.deepEqual(await readdir(join(root, ".pythilo-previous-builds")), ["build-b-3000"]);
    assert.equal(await readFile(join(root, "APP_PAGE", "index.html"), "utf8"), "current website");
  } finally { await rm(root, { recursive: true, force: true }); }
});
