import { test } from "node:test";
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { createHash, createHmac, createPublicKey, randomBytes, timingSafeEqual, verify } from "node:crypto";
import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import vm from "node:vm";
import { createRuntimeSigner } from "../lib/playground-runtime-protocol.ts";
import { runtimeSourceRevision } from "../lib/playground-runtime-source.ts";
import { base64url, newEncryptionSecret } from "../lib/playground-crypto.ts";
import { yDocument } from "../lib/playground-collab.ts";
import * as Y from "yjs";

// The services the Swift side provides to JavaScriptCore, implemented with Node.
function nativeCrypto(json) {
  const request = JSON.parse(json), bytes = value => Buffer.from(value);
  if (request.op === "digest") return JSON.stringify({ bytes: [...createHash("sha256").update(bytes(request.data)).digest()] });
  if (request.op === "hmac") { const expected = createHmac("sha256", bytes(request.key)).update(bytes(request.data)).digest(); return JSON.stringify({ valid: expected.length === request.signature.length && timingSafeEqual(expected, bytes(request.signature)) }); }
  if (request.op === "ecdsa") {
    const raw = bytes(request.key), key = createPublicKey({ key: { kty: "EC", crv: "P-256", x: raw.subarray(1, 33).toString("base64url"), y: raw.subarray(33).toString("base64url") }, format: "jwk" });
    return JSON.stringify({ valid: verify("sha256", bytes(request.data), { key, dsaEncoding: "ieee-p1363" }, bytes(request.signature)) });
  }
  return JSON.stringify({ error: "unsupported" });
}

const directory = mkdtempSync(join(tmpdir(), "pythilo-codec-")), file = join(directory, "PlaygroundCodec.js");
execFileSync(process.execPath, [new URL("../scripts/build-playground-bridge.mjs", import.meta.url).pathname, file], { stdio: "ignore" });
const source = readFileSync(file, "utf8");
rmSync(directory, { recursive: true, force: true });
const context = vm.createContext({ __pythiloRandom: count => [...new Uint32Array(randomBytes(count * 4).buffer)], __pythiloRuntimeCrypto: nativeCrypto, __pythiloSourceOrigin: value => value, Date });
vm.runInContext(source, context);
const codec = context.PythiloPlaygroundCodec;
const call = request => JSON.parse(codec.call(JSON.stringify(request)));
const callback = (method, request) => new Promise(resolve => codec[method](JSON.stringify(request), reply => resolve(JSON.parse(reply))));
const document = { schemaVersion: 1, name: "csv-cleaner", entryFile: "main.py", files: { "main.py": "from cleaner import clean_rows\n", "cleaner.py": "def clean_rows(rows):\n    return rows\n", "people.csv": "name,age\nAda,36\n" } };

test("the bundle exposes the Crabrix-shaped API under the Pythilo name only", () => {
  assert.deepEqual(Object.keys(codec).sort(), ["call", "callHost", "callRuntime", "decodeBase64", "encodeBase64"]);
  assert.doesNotMatch(source, /crabrix/i);
  for (const name of ["pythilo-playground-v1", "pythilo-runtime-v1", "pythilo-runtime-edit-proof-v1", "pythilo-runtime-source-v1", "__pythiloRandom", "__pythiloRuntimeCrypto", "__pythiloSourceOrigin"]) assert.ok(source.includes(name), name);
});

test("documents follow the Python rules and merge with the website's Yjs updates", async () => {
  const initial = call({ type: "initialize", document });
  assert.deepEqual(initial.document, document);
  assert.ok(initial.update && initial.presence);
  assert.match(call({ type: "replace", document: { ...document, entryFile: "main.rs", files: { "main.rs": "" } } }).error, /Unsupported source path/);
  assert.match(call({ type: "replace", document: { ...document, files: { ...document.files, "__pycache__/x.py": "" } } }).error, /Unsupported source path/);
  assert.match(call({ type: "state", codec: 2, snapshot: "", events: [] }).error, /newer format/);
  // A snapshot made by the website joins as format 1.
  const web = yDocument({ ...document, name: "from-web" }), snapshot = Buffer.from(Y.encodeStateAsUpdate(web)).toString("base64");
  const joined = call({ type: "state", snapshot, events: [] });
  assert.equal(joined.error, undefined);
  const identity = JSON.parse(codec.call(JSON.stringify({ type: "runtime-source" })));
  assert.equal(createHash("sha256").update(identity.runtimeSource).digest("hex"), await runtimeSourceRevision(joined.document));
  assert.deepEqual(identity.runtimePaths, Object.keys(joined.document.files).sort());
  assert.ok(call({ type: "identity", name: "Serhii's iPhone" }).presence.length > 0);
});

test("callRuntime and callHost authenticate a signed request in JavaScriptCore's environment", async () => {
  const room = "R".repeat(24), edit = newEncryptionSecret(), controller = await createRuntimeSigner(), target = "a".repeat(64);
  call({ type: "initialize", document });
  const revision = await runtimeSourceRevision(document);
  const local = { room, target, scope: "app:1", revision, editCapability: edit, expires: Date.now() + 600_000, foreground: true, connected: true, editConfirmed: true, ready: true, busy: false, name: "Serhii's iPhone", kind: "ios", runtime: "CPython 3.14.10 · iOS", paths: ["cleaner.py", "main.py", "people.csv"] };
  const initialized = await callback("callHost", { action: "initialize", context: local });
  assert.equal(initialized.error, undefined);
  const capabilities = initialized.publications.find(item => item.fields.kind === "capabilities");
  assert.equal(JSON.parse(capabilities.payloadJSON).profile, "python3-v1");
  const requestID = base64url(crypto.getRandomValues(new Uint8Array(18)));
  const envelope = await controller.sign({ kind: "permission-request", room, target, requestID, operation: "grant", revision }, { name: "Claude · MCP", operations: ["run"] }, { editCapability: edit });
  const pending = await callback("callHost", { action: "frame", context: local, envelope: JSON.stringify(envelope) });
  assert.deepEqual(pending.requests.map(item => item.name), ["Claude · MCP"]);
  const allowed = await callback("callHost", { action: "allow", context: local, controller: controller.fingerprint, requestID, operations: ["run"], once: true });
  assert.equal(allowed.once, "unused");
  assert.equal(JSON.parse(allowed.publications[0].payloadJSON).ok, true);
  const forged = { ...envelope, editProof: base64url(new Uint8Array(32)) };
  assert.equal((await callback("callHost", { action: "frame", context: local, envelope: JSON.stringify(forged) })).error, "Local runtime host refused this operation.");
  const policy = await callback("callRuntime", { action: "initialize", context: { ...local, jobs: [] } });
  assert.equal(policy.error, undefined);
});
