import { test } from "node:test";
import assert from "node:assert/strict";
import { unzipSync, strFromU8 } from "fflate";
import { PlaygroundRooms } from "../lib/playground-rooms.ts";
import { newPlaygroundDocument } from "../lib/playground-document.ts";
import { buildFileTree, flattenTree, fileIconKind, matchingPaths, planFileOperation, isDestructiveInSharedRoom } from "../lib/playground-file-ops.ts";
import { documentRevision, exportArchive, readView } from "../lib/playground-project.ts";
import { yDocument } from "../lib/playground-collab.ts";
import { aiHandoffText, maskedLink, setupCommand, HANDOFF_SCHEMA } from "../lib/playground-handoff.ts";

const packet = byte => ({ iv: Buffer.alloc(12, byte).toString("base64url"), data: Buffer.alloc(32, byte).toString("base64url") });
const project = () => ({ schemaVersion: 1, name: "demo", entryFile: "main.py", files: { "main.py": "from cleaner import clean\n", "cleaner.py": "def clean(rows):\n    return rows\n" } });

test("a stale generation is refused after a snapshot even though the sequence did not move", () => {
  const relay = new PlaygroundRooms(() => 1_000_000), created = relay.create(packet(1), 60), peer = "a".repeat(24);
  relay.subscribe(created.id, created.edit, peer, () => {});
  const before = relay.state(created.id, created.edit);
  assert.equal(before.protocol.stateGeneration, 1);
  const compacted = relay.compact(created.id, created.edit, before.sequence, packet(2));
  const after = relay.state(created.id, created.edit);
  assert.equal(after.sequence, before.sequence);
  assert.notEqual(after.generation, before.generation);
  assert.equal(compacted.generation, after.generation);
  assert.throws(() => relay.append(created.id, created.edit, peer, "b".repeat(24), packet(3), before.sequence, before.generation), error => error.status === 409);
  assert.equal(relay.state(created.id, created.edit).sequence, before.sequence, "nothing was written");
  const applied = relay.append(created.id, created.edit, peer, "c".repeat(24), packet(3), after.sequence, after.generation);
  assert.equal(applied.generation, after.generation + 1);
  assert.equal(relay.append(created.id, created.edit, peer, "c".repeat(24), packet(3), after.sequence, after.generation).sequence, applied.sequence, "a lost response can still be retried");
});

test("the tree lists folders first in a stable order", () => {
  const tree = buildFileTree(["main.py", "pkg/b.py", "pkg/a/c.py", "README", "pkg/a.py"]);
  assert.deepEqual(tree.map(node => node.name), ["pkg", "main.py", "README"]);
  assert.deepEqual(tree[0].children.map(node => node.name), ["a", "a.py", "b.py"]);
  assert.deepEqual(flattenTree(tree, new Set(["pkg", "pkg/a"])).map(item => [item.node.path, item.depth]).slice(0, 3), [["pkg", 0], ["pkg/a", 1], ["pkg/a/c.py", 2]]);
  assert.deepEqual(matchingPaths(["pkg/Parser.py", "main.py"], "parser"), ["pkg/Parser.py"]);
});

test("file badges follow Python project conventions", () => {
  assert.deepEqual(["a.py", "pkg/__init__.py", "test_a.py", "a_test.py", "requirements.txt", "people.csv", "data.json", "pyproject.toml", "setup.cfg", "README.md", "README", "index.html", "style.css", "schema.sql", ".gitignore", "notes.txt"].map(fileIconKind),
    ["python", "package", "test", "test", "requirements", "csv", "json", "toml", "toml", "markdown", "markdown", "html", "css", "database", "git", "text"]);
});

test("moving a folder updates the entry atomically and one collision moves nothing", () => {
  const source = { ...project(), entryFile: "app/main.py", files: { "app/main.py": "print(1)\n", "app/a.py": "", "lib/a.py": "" } };
  const plan = planFileOperation(source, { kind: "rename-folder", from: "app", to: "src" });
  assert.equal(plan.document.entryFile, "src/main.py");
  assert.equal(plan.moved["app/a.py"], "src/a.py");
  assert.equal(plan.movesPythonSource, true);
  assert.throws(() => planFileOperation(source, { kind: "rename-folder", from: "app", to: "lib" }), /already exists/);
  assert.throws(() => planFileOperation(source, { kind: "rename-folder", from: "app", to: "app/inner" }), /inside itself/);
  assert.equal(source.entryFile, "app/main.py");
});

test("file operations share the Python document rules", () => {
  assert.throws(() => planFileOperation(project(), { kind: "create", path: "../x.py" }), /Unsupported/);
  assert.throws(() => planFileOperation(project(), { kind: "create", path: "__pycache__/x.py" }), /Unsupported/);
  assert.throws(() => planFileOperation(project(), { kind: "create", path: "MAIN.py" }), /already exists/);
  assert.throws(() => planFileOperation(project(), { kind: "create", path: "main.py/x.py" }));
  // Deleting the main file without a choice makes the first remaining Python file the main file.
  assert.equal(planFileOperation(project(), { kind: "delete-file", path: "main.py" }).document.entryFile, "cleaner.py");
  assert.throws(() => planFileOperation({ ...project(), files: { "main.py": "", "notes.md": "" } }, { kind: "delete-file", path: "main.py" }), /one Python file/);
  assert.equal(planFileOperation(project(), { kind: "delete-file", path: "main.py", entryFile: "cleaner.py" }).document.entryFile, "cleaner.py");
  assert.equal(planFileOperation(project(), { kind: "duplicate", from: "cleaner.py", to: "cleaner_copy.py" }).document.files["cleaner_copy.py"], project().files["cleaner.py"]);
  assert.equal(isDestructiveInSharedRoom({ kind: "create", path: "a.py" }), false);
  for (const operation of [{ kind: "rename", from: "a", to: "b" }, { kind: "rename-folder", from: "a", to: "b" }, { kind: "delete-file", path: "a" }, { kind: "delete-folder", path: "a" }]) assert.equal(isDestructiveInSharedRoom(operation), true);
});

test("a revision covers the name, entry, origin and every file; export keeps exact text", () => {
  const base = newPlaygroundDocument(), revision = documentRevision(base);
  assert.equal(documentRevision({ ...base, files: { ...base.files } }), revision);
  for (const changed of [{ ...base, name: "other" }, { ...base, files: { "main.py": "x" } }]) assert.notEqual(documentRevision(changed), revision);
  const doc = yDocument(project()), view = readView(doc);
  assert.equal(view.entryKey, "main.py");
  const files = unzipSync(exportArchive(view.document));
  assert.deepEqual(Object.keys(files).sort(), ["cleaner.py", "main.py"]);
  assert.equal(strFromU8(files["cleaner.py"]), project().files["cleaner.py"]);
});

test("the AI handoff uses its own schema and the setup names the pythilo server", () => {
  const link = "http://127.0.0.1:3212/playground/room/" + "r".repeat(24) + "/#key=" + "k".repeat(43) + "&access=" + "e".repeat(43) + "&expires=1&mode=edit";
  const text = aiHandoffText(link, "edit", Date.UTC(2026, 10, 3));
  assert.equal(HANDOFF_SCHEMA, "pythilo-handoff-v1");
  assert.match(text, /^Join my Pythilo room with pythilo_connect:\n/);
  const handoff = JSON.parse(text.slice(text.indexOf("{")));
  assert.deepEqual([handoff.schema, handoff.link, handoff.mode, handoff.expiresAt], ["pythilo-handoff-v1", link, "edit", "2026-11-03T00:00:00.000Z"]);
  assert.doesNotMatch(text, /crabrix/i);
  assert.equal(setupCommand("claude-code"), "claude mcp add --transport stdio pythilo -- npx -y --package=https://pythilo.com/downloads/pythilo-0.1.0.tgz pythilo");
  assert.equal(setupCommand("claude-code", "/src/pythilo/"), "claude mcp add --transport stdio pythilo -- node /src/pythilo/sdk/dist/cli.mjs");
  assert.equal(setupCommand("codex"), "codex mcp add pythilo -- npx -y --package=https://pythilo.com/downloads/pythilo-0.1.0.tgz pythilo");
  assert.deepEqual(JSON.parse(setupCommand("claude-desktop")), { mcpServers: { pythilo: { command: "npx", args: ["-y", "--package=https://pythilo.com/downloads/pythilo-0.1.0.tgz", "pythilo"] } } });
  const masked = maskedLink(link);
  assert.doesNotMatch(masked, /k{43}|e{43}/);
  assert.match(masked, /#key=\[KEY\]&access=\[ACCESS\]&expires=1&mode=edit$/);
});
