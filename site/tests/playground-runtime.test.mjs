import { test } from "node:test";
import assert from "node:assert/strict";
import { createRuntimeSigner, verifyRuntimeEnvelope } from "../lib/playground-runtime-protocol.ts";
import { RuntimeHostCore } from "../lib/playground-runtime-host.ts";
import { runtimeSourceRevision } from "../lib/playground-runtime-source.ts";
import { base64url, newEncryptionSecret } from "../lib/playground-crypto.ts";

const room = "R".repeat(24), document = { schemaVersion: 1, name: "demo", entryFile: "main.py", files: { "main.py": "print('hi')\n" } };
const id = () => base64url(crypto.getRandomValues(new Uint8Array(18)));
const payload = publication => JSON.parse(publication.payloadJSON);

async function setup() {
  const edit = newEncryptionSecret(), host = await createRuntimeSigner(), controller = await createRuntimeSigner(), revision = await runtimeSourceRevision(document);
  const context = { room, target: host.fingerprint, scope: "peer:0", revision, editCapability: edit, expires: Date.now() + 3_600_000, foreground: true, connected: true, editConfirmed: true, ready: true, busy: false, name: "Serhii's iPhone", kind: "ios", runtime: "CPython 3.14.10 · iOS", paths: ["main.py"] };
  const core = new RuntimeHostCore(context);
  const send = async (fields, body) => core.frame(JSON.parse(JSON.stringify(await controller.sign({ room, target: host.fingerprint, requestID: id(), revision, ...fields }, body, { editCapability: edit }))));
  return { edit, host, controller, revision, context, core, send };
}

test("a host advertises kind, name, runtime fingerprint and the python3-v1 operations", async () => {
  const { core, context } = await setup();
  core.tick(context);
  const [capabilities] = core.drain().publications;
  assert.equal(capabilities.fields.kind, "capabilities");
  const advertised = payload(capabilities);
  assert.deepEqual([advertised.role, advertised.kind, advertised.name, advertised.runtime, advertised.profile, advertised.operations, advertised.permissions, advertised.jobLimitSeconds],
    ["host", "ios", "Serhii's iPhone", "CPython 3.14.10 · iOS", "python3-v1", ["check", "run", "test"], "off", 120]);
});

test("nothing runs without the owner's grant; a granted run reports where, on what and for which source", async () => {
  const { core, context, controller, send, revision } = await setup();
  core.tick(context); core.drain();
  await send({ kind: "command", operation: "run" }, { grant: "g".repeat(32) });
  assert.match(payload(core.drain().publications[0]).reason, /No matching explicit local grant/);
  const request = id();
  await core.frame(JSON.parse(JSON.stringify(await controller.sign({ kind: "permission-request", room, target: context.target, requestID: request, operation: "grant", revision }, { name: "Claude · MCP", operations: ["check", "run", "test"] }, { editCapability: context.editCapability }))));
  const pending = core.drain();
  assert.deepEqual(pending.requests.map(item => [item.name, item.requestID]), [["Claude · MCP", request]]);
  assert.deepEqual(pending.effects, []);
  core.allow(controller.fingerprint, request, ["run", "test"]);
  const granted = payload(core.drain().publications[0]);
  assert.deepEqual([granted.ok, granted.operations, granted.profile], [true, ["run", "test"], "python3-v1"]);
  await send({ kind: "command", operation: "check" }, { grant: granted.grant });
  assert.match(payload(core.drain().publications[0]).reason, /not granted/);
  await send({ kind: "command", operation: "run" }, { grant: granted.grant });
  const started = core.drain(), reply = payload(started.publications[0]);
  assert.deepEqual(started.effects.map(effect => [effect.type, effect.operation]), [["start", "run"]]);
  assert.deepEqual([reply.ok, reply.ranOn, reply.runtime], [true, { name: "Serhii's iPhone", kind: "ios" }, "CPython 3.14.10 · iOS"]);
  core.update(reply.job, { state: "finished", succeeded: true, exitCode: 0, stdout: "hi\n", stderr: "", durationMs: 42 });
  await send({ kind: "command", operation: "status", job: reply.job }, { grant: granted.grant });
  const status = payload(core.drain().publications[0]);
  assert.deepEqual([status.state, status.succeeded, status.exitCode, status.durationMs, status.revision, status.ranOn.kind, status.runtime], ["finished", true, 0, 42, revision, "ios", "CPython 3.14.10 · iOS"]);
  assert.ok(Number.isSafeInteger(status.startedAt));
  await send({ kind: "command", operation: "stdout", job: reply.job }, { grant: granted.grant, cursor: 0 });
  assert.deepEqual(payload(core.drain().publications[0]), { ok: true, text: "hi\n", next: null, truncated: false });
});

test("allow once admits one job and still lets the controller read its result", async () => {
  const { core, context, controller, send, revision } = await setup();
  core.tick(context); core.drain();
  const request = id();
  await core.frame(JSON.parse(JSON.stringify(await controller.sign({ kind: "permission-request", room, target: context.target, requestID: request, operation: "grant", revision }, { name: "Ada · website", operations: ["run"] }, { editCapability: context.editCapability }))));
  core.drain();
  core.allow(controller.fingerprint, request, ["run"], undefined, true);
  const granted = payload(core.drain().publications[0]);
  assert.ok(granted.expires - Date.now() <= 180_000, "a one-job grant is short");
  await send({ kind: "command", operation: "run" }, { grant: granted.grant });
  const job = payload(core.drain().publications[0]).job;
  core.update(job, { state: "finished", succeeded: false, exitCode: 1, stderr: "Traceback\n", durationMs: 5 });
  assert.equal(core.drain().once, "used");
  await send({ kind: "command", operation: "stderr", job }, { grant: granted.grant, cursor: 0 });
  assert.equal(payload(core.drain().publications[0]).text, "Traceback\n");
  await send({ kind: "command", operation: "run" }, { grant: granted.grant });
  assert.match(payload(core.drain().publications[0]).reason, /one job/);
});

test("Crabrix envelopes and Crabrix-only operations are refused", async () => {
  const signer = await createRuntimeSigner(), edit = newEncryptionSecret();
  const envelope = await signer.sign({ kind: "capabilities", room, target: "", requestID: id(), operation: "discover" }, { role: "controller", name: "x" }, { editCapability: edit });
  await verifyRuntimeEnvelope(envelope, { room, editCapability: edit });
  const crabrix = { ...envelope, header: ["crabrix-runtime-v1", ...envelope.header.slice(1)] };
  await assert.rejects(verifyRuntimeEnvelope(crabrix, { room, editCapability: edit }), /Invalid runtime header/);
  await assert.rejects(signer.sign({ kind: "command", room, target: "a".repeat(64), requestID: id(), operation: "debug" }, {}), /Invalid runtime header/);
});
