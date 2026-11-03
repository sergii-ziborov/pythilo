// The parts of docs/design/ROOMS.md that separate Pythilo from Crabrix and Python from Rust.
import { test } from "node:test";
import assert from "node:assert/strict";
import { webcrypto } from "node:crypto";
import { Client, InMemoryTransport } from "@modelcontextprotocol/client";
import { startRelay } from "./support/relay";
import { PlaygroundRoom, authorizedLink } from "../src/room";
import { makeServer } from "../src/server";
import { PythiloError } from "../src/errors";
import { Y, yDocument } from "../src/core/playground-collab";
import { playgroundLink } from "../src/core/playground-session";
import { newPlaygroundDocument, validatePlaygroundDocument, isValidSourcePath } from "../src/core/playground-document";
import { base64url, decryptPlayground, encryptPlayground, newEncryptionSecret } from "../src/core/playground-crypto";
import { createRuntimeSigner, verifyRuntimeEnvelope, RUNTIME_PROTOCOL } from "../src/core/playground-runtime-protocol";

const failsWith = (code: string) => (error: unknown) => { assert.ok(error instanceof PythiloError, String(error)); assert.equal(error.code, code, error.message); return true; };
const encoder = new TextEncoder();
// What a Crabrix client produces: the same AES-GCM packet under its own additional data.
async function crabrixPacket(secret: string, bytes: Uint8Array) {
  const key = await webcrypto.subtle.importKey("raw", Buffer.from(secret, "base64url"), "AES-GCM", false, ["encrypt"]);
  const iv = webcrypto.getRandomValues(new Uint8Array(12));
  const data = await webcrypto.subtle.encrypt({ name: "AES-GCM", iv, additionalData: encoder.encode("crabrix-playground-v1") }, key, bytes);
  return { iv: base64url(iv), data: base64url(new Uint8Array(data)) };
}
const sha256 = async (bytes: Uint8Array) => Buffer.from(await webcrypto.subtle.digest("SHA-256", bytes)).toString("hex");

test("a Crabrix-encrypted packet does not decrypt, and a Pythilo packet does", async () => {
  const key = newEncryptionSecret(), bytes = encoder.encode("print('hi')\n");
  await assert.rejects(decryptPlayground(key, await crabrixPacket(key, bytes)));
  assert.deepEqual(await decryptPlayground(key, await encryptPlayground(key, bytes)), bytes);
});

test("a Crabrix room or handoff link is refused quickly, and the current room is kept", async () => {
  const { rooms, origin, close } = await startRelay(), mcp = new PlaygroundRoom(origin);
  try {
    const kept = await mcp.create("Kept");
    // A room whose snapshot a Crabrix client wrote, reached through an ordinary link.
    const key = newEncryptionSecret(), seed = yDocument(newPlaygroundDocument());
    const crabrix = rooms.create(await crabrixPacket(key, Y.encodeStateAsUpdate(seed)), 600); seed.destroy();
    const link = playgroundLink({ id: crabrix.id, key, access: crabrix.edit, expiresAt: crabrix.expiresAt, mode: "edit" }, origin);
    const started = Date.now();
    await assert.rejects(() => mcp.exclusive(() => mcp.connect(link)), failsWith("UNREADABLE_ROOM"));
    assert.ok(Date.now() - started < 5000, "refused without waiting for the join timeout");
    assert.equal((await mcp.status()).room, kept.room);
    for (const end = Date.now() + 2000; rooms.rooms.get(crabrix.id)!.listeners.size && Date.now() < end;) await new Promise(resolve => setTimeout(resolve, 20));
    assert.equal(rooms.rooms.get(crabrix.id)!.listeners.size, 0, "the refused room's slot is released");
    for (const handoff of [link.replace(origin, "crabrix://playground"), "crabrix://playground/room/" + crabrix.id + "/#" + link.split("#")[1]]) await assert.rejects(() => mcp.exclusive(() => mcp.connect(handoff)), failsWith("INVALID_LINK"));
    const share = await mcp.share("view");
    assert.equal(share.schema, "pythilo-handoff-v1");
  } finally { mcp.dispose(); await close(); }
});

test("a Crabrix runtime envelope, edit proof or debugger operation is refused", async () => {
  const signer = await createRuntimeSigner(), capability = newEncryptionSecret(), room = "a".repeat(24), now = Date.now();
  const fields = { kind: "command" as const, room, target: "b".repeat(64), requestID: "contract-request-0001", operation: "run" as const, revision: "c".repeat(64) };
  try {
    assert.equal(RUNTIME_PROTOCOL, "pythilo-runtime-v1");
    const good = await signer.sign(fields, { grant: "g".repeat(16) }, { now, editCapability: capability });
    await verifyRuntimeEnvelope(good, { room, editCapability: capability, requireEditProof: true, clock: () => now });
    // A Crabrix header, re-signed by its own key, is still not a Pythilo header.
    const pair = await webcrypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]) as CryptoKeyPair;
    const raw = new Uint8Array(await webcrypto.subtle.exportKey("raw", pair.publicKey)), payload = encoder.encode("{}");
    const header = ["crabrix-runtime-v1", "command", room, await sha256(raw), fields.target, fields.requestID, "run", fields.revision, "", base64url(webcrypto.getRandomValues(new Uint8Array(32))), now, now + 10_000, await sha256(payload)];
    const signature = base64url(new Uint8Array(await webcrypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, pair.privateKey, encoder.encode(JSON.stringify(header)))));
    await assert.rejects(verifyRuntimeEnvelope({ v: 1, key: base64url(raw), header, payload: base64url(payload), signature }, { room, clock: () => now }), /header/);
    // A Pythilo envelope whose edit proof uses the Crabrix label proves nothing.
    const plain = await signer.sign(fields, { grant: "g".repeat(16) }, { now });
    const hmac = await webcrypto.subtle.importKey("raw", encoder.encode(capability), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
    const crabrixProof = base64url(new Uint8Array(await webcrypto.subtle.sign("HMAC", hmac, encoder.encode("crabrix-runtime-edit-proof-v1\n" + JSON.stringify(plain.header) + "\n" + plain.signature))));
    await assert.rejects(verifyRuntimeEnvelope({ ...plain, editProof: crabrixProof }, { room, editCapability: capability, requireEditProof: true, clock: () => now }), /edit access/);
    for (const operation of ["build", "debug", "step", "continue", "locals", "breakpoints"]) await assert.rejects(signer.sign({ ...fields, operation: operation as "run" }, {}, { now }), /header/, operation);
    await signer.sign({ ...fields, operation: "test" }, {}, { now });
  } finally { signer.destroy(); }
});

test("Python document rules: .py entry, allowed files, refused folders", () => {
  const base = { schemaVersion: 1, name: "Rules" };
  assert.throws(() => validatePlaygroundDocument({ ...base, entryFile: "main.rs", files: { "main.rs": "fn main() {}\n" } }), /Unsupported source path/);
  assert.throws(() => validatePlaygroundDocument({ ...base, entryFile: "main.rs", files: { "main.py": "", "main.rs": "" } }), /Unsupported source path/);
  assert.throws(() => validatePlaygroundDocument({ ...base, entryFile: "stubs.pyi", files: { "stubs.pyi": "" } }), /Python source entry/);
  assert.throws(() => validatePlaygroundDocument({ ...base, entryFile: "README", files: { "README": "", "main.py": "" } }), /Python source entry/);
  const crabrix = validatePlaygroundDocument({ ...base, entryFile: "main.py", edition: "2024", files: { "main.py": "" } });
  assert.equal("edition" in crabrix, false, "a Crabrix edition field is not carried");
  assert.equal(newPlaygroundDocument().entryFile, "main.py");
  for (const path of ["main.py", "pkg/__init__.py", "pkg/mod.pyi", "notes.txt", "README.md", "docs/guide.rst", "data/x.csv", "data/x.tsv", "conf.json", "pyproject.toml", "setup.cfg", "tox.ini", "a.yaml", "b.yml", "web/index.html", "web/site.css", "web/app.js", "schema.sql",
    "requirements.txt", "LICENSE", "NOTICE", "README", ".gitignore"]) assert.equal(isValidSourcePath(path), true, path);
  for (const path of ["main.rs", "Cargo.toml.lock", "image.png", "lib.so", "module.pyc", "docs/README", "sub/.gitignore", "sub/LICENSE", "Makefile", "../x.py", "/abs.py", "a\\b.py", "c:x.py",
    "__pycache__/m.py", ".venv/lib.py", "venv/x.py", ".git/config.txt", ".pythilo/state.json", "lib/site-packages/x.py", "node_modules/x.js", ".mypy_cache/x.json", ".pytest_cache/README.md", "pkg/__PYCACHE__/m.py"]) assert.equal(isValidSourcePath(path), false, path);
});

test("create and apply refuse Rust files, and a stale expectedRevision is a conflict that changes nothing", async () => {
  const { origin, close } = await startRelay(), mcp = new PlaygroundRoom(origin);
  try {
    await assert.rejects(() => mcp.exclusive(() => mcp.create("Rust", { "main.rs": "fn main() {}\n" }, "main.rs")), failsWith("PATH_CONFLICT"));
    await assert.rejects(() => mcp.exclusive(() => mcp.create("Rust entry", { "main.py": "", "lib.py": "" }, "main.rs")), failsWith("INVALID_ARGUMENT"));
    await mcp.create("Python", { "main.py": "print(1)\n" });
    const first = await mcp.read("main.py");
    const changed = await mcp.apply(first.revision, [{ path: "main.py", text: "print(2)\n" }, { path: "test_main.py", text: "def test_ok():\n    assert True\n" }]);
    assert.equal(changed.changed, true);
    await assert.rejects(() => mcp.exclusive(() => mcp.apply(first.revision, [{ path: "main.py", text: "print(3)\n" }])), failsWith("REVISION_CONFLICT"));
    await assert.rejects(() => mcp.exclusive(() => mcp.apply(changed.revision, [{ path: "src/lib.rs", text: "" }])), failsWith("PATH_CONFLICT"));
    await assert.rejects(() => mcp.exclusive(() => mcp.apply(changed.revision, [{ path: "__pycache__/main.py", text: "" }])), failsWith("PATH_CONFLICT"));
    assert.equal((await mcp.read("main.py")).text, "print(2)\n");
    assert.equal((await mcp.status()).revision, changed.revision);
    const server = makeServer(mcp), client = new Client({ name: "contract", version: "1" });
    const [a, b] = InMemoryTransport.createLinkedPair();
    await Promise.all([server.connect(a), client.connect(b)]);
    try {
      const stale = await client.callTool({ name: "pythilo_apply_changes", arguments: { expectedRevision: first.revision, changes: [{ path: "main.py", text: "print(4)\n" }] } });
      assert.equal(stale.isError, true);
      assert.equal((stale.structuredContent as any).error.code, "REVISION_CONFLICT");
      assert.equal((stale.structuredContent as any).error.action, "refresh_and_replan");
    } finally { await client.close(); await server.close(); }
    assert.equal((await mcp.read("main.py")).text, "print(2)\n");
  } finally { mcp.dispose(); await close(); }
});

test("a link names its relay: https anywhere, http only for loopback or the configured relay, pythilo:// against the configured relay", async () => {
  const id = "r".repeat(24), fragment = "#" + new URLSearchParams({ key: "k".repeat(43), access: "a".repeat(43), expires: String(Date.now() + 60_000), mode: "edit" });
  assert.equal(authorizedLink(`https://relay.example/playground/room/${id}/${fragment}`).origin, "https://relay.example");
  assert.equal(authorizedLink(`http://127.0.0.1:3212/playground/room/${id}/${fragment}`).origin, "http://127.0.0.1:3212");
  assert.equal(authorizedLink(`http://localhost:3212/playground/room/${id}/${fragment}`).origin, "http://localhost:3212");
  assert.throws(() => authorizedLink(`http://192.168.1.5:3212/playground/room/${id}/${fragment}`), failsWith("INVALID_LINK"));
  assert.equal(authorizedLink(`http://192.168.1.5:3212/playground/room/${id}/${fragment}`, "http://192.168.1.5:3212").origin, "http://192.168.1.5:3212");
  assert.throws(() => authorizedLink(`pythilo://playground/room/${id}/${fragment}`), /names no relay/);
  assert.equal(authorizedLink(`pythilo://playground/room/${id}/${fragment}`, "http://127.0.0.1:3212").origin, "http://127.0.0.1:3212");
  assert.throws(() => authorizedLink(`pythilo://elsewhere/room/${id}/${fragment}`, "http://127.0.0.1:3212"), failsWith("INVALID_LINK"));
  assert.throws(() => authorizedLink(`https://relay.example/playground/room/${id}/?x=1${fragment}`), failsWith("INVALID_LINK"));
  assert.throws(() => authorizedLink(`https://relay.example/playground/room/${id}/`), /incomplete/);
  const { origin, close } = await startRelay(), owner = new PlaygroundRoom(origin), guest = new PlaygroundRoom(origin);
  try {
    const created = await owner.create("App link");
    const status = await guest.connect(created.link.replace(origin + "/playground", "pythilo://playground"));
    assert.equal(status.room, created.room);
    assert.equal(status.relay, origin);
    assert.equal((await guest.share()).link, created.link, "a handoff carries the https link of the room's relay");
  } finally { owner.dispose(); guest.dispose(); await close(); }
});
