import assert from "node:assert/strict";
import { createServer } from "node:http";
import test from "node:test";
import { runDoctor } from "../src/doctor.js";

test("doctor uses the canonical health route without following a redirect", async () => {
  const paths: string[] = [];
  const server = createServer((request, response) => {
    paths.push(request.url!);
    if (request.url === "/healthz") {
      response.writeHead(308, { Location: "/healthz/" }).end();
    } else if (request.url === "/healthz/") {
      response.writeHead(200, { "Content-Type": "application/json" }).end('{"ok":true}');
    } else {
      response.writeHead(404, { "Content-Type": "application/json" }).end('{"error":"Room not found"}');
    }
  });
  await new Promise<void>(resolve => server.listen(0, "127.0.0.1", resolve));
  try {
    const address = server.address();
    assert.ok(address && typeof address !== "string");
    const report = await runDoctor({ relay: `http://127.0.0.1:${address.port}`, environment: {}, timeoutMs: 2000 });
    assert.equal(report.checks.find(check => check.name === "relay")?.status, "ok");
    assert.ok(paths.includes("/healthz/"));
    assert.ok(!paths.includes("/healthz"));
  } finally {
    server.closeAllConnections();
    await new Promise<void>((resolve, reject) => server.close(error => error ? reject(error) : resolve()));
  }
});
