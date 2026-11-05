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
    assert.equal((await readdir(join(root, ".pythilo-previous-builds"))).length, 2);
    assert.equal((await readFile(join(root, ".pythilo-build-id"), "utf8")).trim(), "build-two");
  } finally { await rm(root, { recursive: true, force: true }); }
});
