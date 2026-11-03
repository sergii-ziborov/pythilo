// A minimal host, as the app or a browser runs one, and the MCP tools driving it end to end.
import { test } from "node:test";
import assert from "node:assert/strict";
import { Client, InMemoryTransport } from "@modelcontextprotocol/client";
import { startRelay } from "./support/relay";
import { PlaygroundRoom, authorizedLink } from "../src/room";
import { makeServer } from "../src/server";
import { Y, documentFromY } from "../src/core/playground-collab";
import { createPresence, publishRuntimePresence, remoteRuntimePresence } from "../src/core/playground-presence";
import { PlaygroundSession, type PlaygroundLink } from "../src/core/playground-session";
import { base64url } from "../src/core/playground-crypto";
import { createRuntimeSigner, verifyRuntimeEnvelope, type RuntimeEnvelope, type RuntimeFields, type VerifiedRuntimeFrame } from "../src/core/playground-runtime-protocol";
import { runtimeSourceRevision } from "../src/core/playground-runtime-source";

const sleep = (ms: number) => new Promise(resolve => setTimeout(resolve, ms));
async function until<T>(read: () => Promise<T>, check: (value: T) => boolean, label: string): Promise<T> {
  const end = Date.now() + 15_000;
  for (;;) { const value = await read(); if (check(value)) return value; if (Date.now() >= end) throw new Error("Timed out: " + label); await sleep(100); }
}
const id = () => base64url(crypto.getRandomValues(new Uint8Array(18)));

// Allows every request, as an owner who chose "allow for this room" would.
async function host(link: PlaygroundLink, origin: string, advertised: Record<string, unknown>, startedAt: number) {
  const doc = new Y.Doc(), awareness = createPresence(doc, String(advertised.name ?? "Host"));
  const session = new PlaygroundSession(doc, link, () => {}, () => {}, awareness, origin);
  void session.start();
  while (!session.receivedState) await sleep(20);
  await session.confirmRuntimeEditAccess();
  const signer = await createRuntimeSigner(), replies = new Map<string, RuntimeEnvelope>(), handled = new Set<string>(), jobs = new Map<string, string>();
  let grant: string | undefined, quietUntil = 0, closed = false;
  const sign = (fields: RuntimeFields, payload: unknown) => signer.sign(fields, payload, { editCapability: link.access });
  const capabilities = async () => {
    if (closed || Date.now() < quietUntil) return;
    publishRuntimePresence(awareness, await sign({ kind: "capabilities", room: link.id, target: "", requestID: id(), operation: "discover", revision: await runtimeSourceRevision(documentFromY(doc)) },
      { role: "host", ready: true, busy: false, permissions: grant ? "granted" : "off", editConfirmed: true, ...advertised }));
  };
  const reply = async (frame: VerifiedRuntimeFrame, payload: unknown, job = "") => {
    const envelope = await sign({ kind: "response", room: link.id, target: frame.sender, requestID: frame.header[5], operation: frame.header[6], revision: frame.header[7], job }, payload);
    replies.set(frame.sender + ":" + frame.header[5], envelope); quietUntil = Date.now() + 1500; publishRuntimePresence(awareness, envelope);
  };
  const scan = async () => {
    for (const item of remoteRuntimePresence(awareness)) {
      let frame: VerifiedRuntimeFrame;
      try { frame = await verifyRuntimeEnvelope(JSON.parse(item.envelope), { room: link.id, editCapability: link.access }); } catch { continue; }
      const h = frame.header, key = frame.sender + ":" + h[5];
      if (closed || h[4] !== signer.fingerprint || !frame.editAccessProved) continue;
      // A retransmission gets the same reply again, never a second job.
      if (replies.has(key)) { quietUntil = Date.now() + 1500; publishRuntimePresence(awareness, replies.get(key)!); continue; }
      if (handled.has(key)) continue;
      handled.add(key);
      const p = frame.payload as Record<string, any>;
      if (h[1] === "permission-request") { grant = id(); await reply(frame, { ok: true, grant, operations: p.operations, expires: Date.now() + 600_000, profile: "python3-v1" }); }
      else if (h[1] === "command" && p.grant !== grant) await reply(frame, { ok: false, reason: "No grant." });
      else if (["check", "run", "test"].includes(h[6])) { const job = id(); jobs.set(job, h[6]); await reply(frame, { ok: true, job, state: "working", profile: "python3-v1" }, job); }
      else if (!jobs.has(h[8])) await reply(frame, { ok: false, reason: "This owned job is unavailable." }, h[8]);
      else if (h[6] === "status") await reply(frame, { ok: true, state: "finished", stage: "Finished", succeeded: true, exitCode: 0, durationMs: 42, startedAt, truncated: false }, h[8]);
      else if (h[6] === "stdout") await reply(frame, { ok: true, text: "Hello, Pythilo!\n", next: null, truncated: false }, h[8]);
      else if (h[6] === "stop") await reply(frame, { ok: true, state: "finished" }, h[8]);
    }
  };
  awareness.on("update", () => { void scan(); });
  const timer = setInterval(() => { void capabilities(); }, 1000);
  await capabilities();
  return { fingerprint: signer.fingerprint, close() { closed = true; clearInterval(timer); session.stop(); signer.destroy(); awareness.destroy(); doc.destroy(); } };
}

test("an AI client asks an iPhone host to run Python, and every result says where and how it ran", async () => {
  const { origin, close } = await startRelay(), room = new PlaygroundRoom(origin), server = makeServer(room), client = new Client({ name: "runtime", version: "1" });
  const [a, b] = InMemoryTransport.createLinkedPair();
  await Promise.all([server.connect(a), client.connect(b)]);
  const tool = async (name: string, args: Record<string, unknown> = {}) => {
    const result = await client.callTool({ name, arguments: args });
    if (result.isError) throw Object.assign(new Error((result.content as any)[0].text), { structured: result.structuredContent });
    return result.structuredContent as any;
  };
  const hosts: { close(): void }[] = [];
  try {
    const created = await tool("pythilo_create", { name: "Run me", files: { "main.py": 'print("Hello, Pythilo!")\n' } });
    const { link } = authorizedLink(created.link);
    const startedAt = Date.now();
    const phone = await host(link, origin, { kind: "ios", name: "Serhii's iPhone", runtime: "CPython 3.14.10 · iOS", profile: "python3-v1", operations: ["check", "run"] }, startedAt);
    hosts.push(phone);
    // A Crabrix host in the same room: another profile, no kind or runtime fingerprint.
    hosts.push(await host(link, origin, { name: "Crabrix tab", profile: "shared-std-v1", operations: ["check", "build", "run"] }, startedAt));
    const listed = await until(() => tool("pythilo_runtime_clients"), value => value.clients.some((c: any) => c.fingerprint === phone.fingerprint) && value.warnings.length > 0, "the host is listed");
    assert.equal(listed.clients.length, 1, "only the python3-v1 host is listed");
    const entry = listed.clients[0];
    assert.deepEqual({ kind: entry.kind, name: entry.name, runtime: entry.runtime, profile: entry.profile, operations: entry.operations, grant: entry.grant }, { kind: "ios", name: "Serhii's iPhone", runtime: "CPython 3.14.10 · iOS", profile: "python3-v1", operations: ["check", "run"], grant: null });
    assert.equal(listed.profile, "python3-v1");
    assert.match(listed.warnings.join(" "), /python3-v1/);
    const sourceRevision = listed.source.revision;
    assert.deepEqual(listed.source.paths, ["main.py"]);

    await assert.rejects(() => tool("pythilo_runtime_request", { target: phone.fingerprint, operations: ["test"] }), (error: any) => error.structured.error.code === "RUNTIME_UNAVAILABLE" && /does not offer test/.test(error.message));
    await assert.rejects(() => tool("pythilo_runtime_start", { target: phone.fingerprint, operation: "run", sourceRevision }), (error: any) => error.structured.error.code === "RUNTIME_GRANT_REQUIRED");
    const requested = await tool("pythilo_runtime_request", { target: phone.fingerprint, operations: ["check", "run"] });
    assert.equal(requested.pending, true);
    assert.deepEqual(requested.host, { kind: "ios", name: "Serhii's iPhone", runtime: "CPython 3.14.10 · iOS", fingerprint: phone.fingerprint });
    const granted = await until(() => tool("pythilo_runtime_clients"), value => value.clients.some((c: any) => c.grant), "the grant arrives");
    assert.deepEqual(granted.clients[0].grant.operations, ["check", "run"]);

    const started = await tool("pythilo_runtime_start", { target: phone.fingerprint, operation: "run", sourceRevision });
    const ranOn = { kind: "ios", name: "Serhii's iPhone", runtime: "CPython 3.14.10 · iOS", fingerprint: phone.fingerprint };
    assert.equal(started.ok, true);
    assert.match(started.job, /^[A-Za-z0-9_-]{16,64}$/);
    assert.deepEqual(started.ranOn, ranOn);
    assert.equal(started.operation, "run");
    assert.equal(started.sourceRevision, sourceRevision);
    assert.equal(started.status, "working");
    assert.equal(started.exitCode, null);
    assert.ok(Date.parse(started.startedAt) >= startedAt);
    const job = started.job;

    const status = await tool("pythilo_runtime_inspect", { target: phone.fingerprint, sourceRevision, job, operation: "status" });
    assert.deepEqual(status.ranOn, ranOn);
    assert.equal(status.sourceRevision, sourceRevision);
    assert.equal(status.status, "finished");
    assert.equal(status.exitCode, 0);
    assert.equal(status.durationMs, 42);
    assert.equal(status.startedAt, new Date(startedAt).toISOString(), "the host's own start time");
    assert.ok(Date.parse(status.at) >= startedAt);
    const stdout = await tool("pythilo_runtime_inspect", { target: phone.fingerprint, sourceRevision, job, operation: "stdout" });
    assert.equal(stdout.text, "Hello, Pythilo!\n");
    assert.deepEqual([stdout.status, stdout.exitCode, stdout.durationMs, stdout.ranOn.name], ["finished", 0, 42, "Serhii's iPhone"]);
    const stopped = await tool("pythilo_runtime_control", { target: phone.fingerprint, sourceRevision, job, operation: "stop" });
    assert.equal(stopped.status, "finished");
    const after = await tool("pythilo_runtime_clients");
    assert.deepEqual(after.jobs.map((item: any) => [item.job, item.operation, item.status, item.exitCode, item.ranOn.kind]), [[job, "run", "finished", 0, "ios"]]);
    await assert.rejects(() => tool("pythilo_runtime_start", { target: phone.fingerprint, operation: "test", sourceRevision }), (error: any) => error.structured.error.code === "RUNTIME_GRANT_REQUIRED" && /allowed check, run/.test(error.message));
  } finally {
    for (const item of hosts) item.close();
    await client.close(); await server.close(); room.dispose(); await close();
  }
});
