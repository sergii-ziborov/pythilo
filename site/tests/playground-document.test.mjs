import { test } from "node:test";
import assert from "node:assert/strict";
import { isValidSourcePath, newPlaygroundDocument, REFUSED_FOLDERS, validatePlaygroundDocument, PLAYGROUND_LIMITS } from "../lib/playground-document.ts";
import { documentFromY, updateYDocument, Y } from "../lib/playground-collab.ts";
import { runtimeSource, runtimeSourceRevision, RUNTIME_SOURCE } from "../lib/playground-runtime-source.ts";
import { RUNTIME_EDIT_PROOF, RUNTIME_PROFILE, RUNTIME_PROTOCOL, runtimeOperations } from "../lib/playground-runtime-protocol.ts";
import { runtimeActions } from "../lib/playground-runtime-authority.ts";
import { PLAYGROUND_ADDITIONAL_DATA } from "../lib/playground-crypto.ts";
import { appLink, parsePlaygroundLink, playgroundLink, CLIENT_CODECS } from "../lib/playground-session.ts";
import { KEEP_DRAFTS_KEY } from "../lib/playground-drafts.ts";
import { HANDOFF_SCHEMA } from "../lib/playground-handoff.ts";

const document = files => ({ schemaVersion: 1, name: "demo", entryFile: "main.py", files: { "main.py": "print(1)\n", ...files } });

test("the Pythilo namespace replaces every Crabrix name", () => {
  assert.equal(PLAYGROUND_ADDITIONAL_DATA, "pythilo-playground-v1");
  assert.equal(RUNTIME_PROTOCOL, "pythilo-runtime-v1");
  assert.equal(RUNTIME_EDIT_PROOF, "pythilo-runtime-edit-proof-v1");
  assert.equal(RUNTIME_SOURCE, "pythilo-runtime-source-v1");
  assert.equal(HANDOFF_SCHEMA, "pythilo-handoff-v1");
  assert.equal(RUNTIME_PROFILE, "python3-v1");
  assert.equal(CLIENT_CODECS, "1");
  assert.match(KEEP_DRAFTS_KEY, /^pythilo\./);
});

test("python3-v1 offers check, run and test, and inspection without Crabrix's debugger", () => {
  assert.deepEqual([...runtimeActions], ["check", "run", "test"]);
  assert.deepEqual([...runtimeOperations].sort(), ["check", "diagnostics", "discover", "grant", "revoke", "run", "status", "stderr", "stdout", "stop", "test"]);
  for (const gone of ["build", "debug", "locals", "step", "continue", "breakpoints"]) assert.equal(runtimeOperations.includes(gone), false, gone);
});

test("text files of a Python project are accepted", () => {
  const accepted = ["main.py", "pkg/__init__.py", "stubs/x.pyi", "notes.txt", "README.md", "docs/index.rst", "data/people.csv", "data/t.tsv", "config.json", "pyproject.toml", "setup.cfg", "tox.ini", "ci.yaml", "ci.yml", "site/index.html", "site/style.css", "site/app.js", "schema.sql", "requirements.txt", "LICENSE", "NOTICE", "README", ".gitignore"];
  for (const path of accepted) assert.equal(isValidSourcePath(path), true, path);
  const value = validatePlaygroundDocument(document(Object.fromEntries(accepted.slice(1, 15).map(path => [path, ""]))));
  assert.equal(Object.keys(value.files).length, 15);
});

test("binary files, other languages, extensionless names below the root and refused folders are not", () => {
  for (const path of ["image.png", "app.ipynb", "lib.so", "main.rs", "Makefile", "docs/README", "pkg/LICENSE", ".env", "db.sqlite3"]) assert.equal(isValidSourcePath(path), false, path);
  assert.deepEqual([...REFUSED_FOLDERS], ["__pycache__", ".venv", "venv", ".git", ".pythilo", "site-packages", "node_modules", ".mypy_cache", ".pytest_cache"]);
  for (const folder of REFUSED_FOLDERS) {
    assert.equal(isValidSourcePath(`${folder}/x.py`), false, folder);
    assert.equal(isValidSourcePath(`pkg/${folder.toUpperCase()}/x.py`), false, folder);
  }
});

test("the entry is a Python file, metadata has no edition, and limits stay as in format v1", () => {
  assert.deepEqual(PLAYGROUND_LIMITS.files, 16);
  assert.equal(newPlaygroundDocument().entryFile, "main.py");
  assert.throws(() => validatePlaygroundDocument({ ...document(), entryFile: "README.md", files: { "README.md": "" } }), /Python entry file/);
  assert.throws(() => validatePlaygroundDocument({ ...document(), entryFile: "missing.py" }), /Python entry file/);
  const value = validatePlaygroundDocument({ ...document(), edition: "2024" });
  assert.equal("edition" in value, false);
  assert.throws(() => validatePlaygroundDocument(document({ "a.py": "x".repeat(65 * 1024) })), /64 KiB/);
  assert.throws(() => validatePlaygroundDocument(document(Object.fromEntries(Array.from({ length: 3 }, (_, i) => [`f${i}.py`, "x".repeat(60 * 1024)])))), /128 KiB/);
  const doc = new Y.Doc(); updateYDocument(doc, document({ "cleaner.py": "" }));
  assert.deepEqual([...doc.getMap("meta").keys()].sort(), ["entryFile", "name", "schemaVersion"]);
  assert.deepEqual({ ...documentFromY(doc).files }, document({ "cleaner.py": "" }).files);
});

test("source origins are GitHub links only", () => {
  assert.equal(validatePlaygroundDocument({ ...document(), origin: { url: "https://github.com/a/b", commit: "c".repeat(40) } }).origin.commit, "c".repeat(40));
  assert.throws(() => validatePlaygroundDocument({ ...document(), origin: { url: "https://play.rust-lang.org/?x" } }), /origin/);
});

test("the runtime revision is the SHA-256 of the sorted document without origin", async () => {
  const value = document({ "b.py": "", "a.py": "" });
  const canonical = JSON.stringify(["pythilo-runtime-source-v1", "demo", "main.py", [["a.py", ""], ["b.py", ""], ["main.py", "print(1)\n"]]]);
  assert.equal(runtimeSource(value).canonical, canonical);
  assert.deepEqual(runtimeSource(value).paths, ["a.py", "b.py", "main.py"]);
  const expected = Buffer.from(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(canonical))).toString("hex");
  assert.equal(await runtimeSourceRevision(value), expected);
  assert.equal(await runtimeSourceRevision({ ...value, origin: { url: "https://github.com/a/b" } }), expected);
});

test("room links keep the key and capability in the fragment; the app link uses pythilo://", () => {
  const link = { id: "r".repeat(24), key: "k".repeat(43), access: "e".repeat(43), expiresAt: 1793671210885, mode: "edit" };
  const url = playgroundLink(link, "http://127.0.0.1:3212");
  assert.equal(url, `http://127.0.0.1:3212/playground/room/${"r".repeat(24)}/#key=${"k".repeat(43)}&access=${"e".repeat(43)}&expires=1793671210885&mode=edit`);
  assert.deepEqual(parsePlaygroundLink(new URL(url)), link);
  assert.equal(appLink(link), url.replace("http://127.0.0.1:3212/", "pythilo://"));
  assert.throws(() => parsePlaygroundLink(new URL("http://127.0.0.1:3212/playground/room/short/")), /invalid room/);
  assert.throws(() => parsePlaygroundLink(new URL(url.split("#")[0])), /incomplete/);
});
