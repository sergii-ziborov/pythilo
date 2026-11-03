import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtemp, copyFile, rm, readFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { promisify } from "node:util";
import { execFile, spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import { Client } from "@modelcontextprotocol/client";
import { StdioClientTransport } from "@modelcontextprotocol/client/stdio";
import { startRelay } from "./support/relay";

// No PYTHILO_RELAY leaks in from the developer's shell.
const cleanEnvironment = () => Object.fromEntries(Object.entries(process.env).filter(([name]) => name !== "PYTHILO_RELAY")) as Record<string, string>;
const run = (args: string[], env: Record<string, string> = cleanEnvironment()) => spawnSync(process.execPath, [path.resolve("dist/cli.mjs"), ...args], { encoding: "utf8", timeout: 5000, env });

test("CLI version agrees with the package and the core manifest names this bridge", async () => {
  const packageInfo = JSON.parse(await readFile("package.json", "utf8"));
  const version = run(["--version"]);
  assert.equal(version.status, 0);
  assert.equal(version.stdout.trim(), packageInfo.version);
  const core = JSON.parse(await readFile("docs/protocol-core.json", "utf8"));
  assert.equal(core.sha256["dist/cli.mjs"], createHash("sha256").update(await readFile("dist/cli.mjs")).digest("hex"));
  assert.deepEqual(core.documentFormats, [1]);
  assert.equal(core.runtimeProfile, "python3-v1");
});

test("doctor refuses unknown flags without starting a server, and help names it", () => {
  const help = run(["--help"]);
  assert.match(help.stdout, /pythilo doctor/);
  assert.match(help.stdout, /PYTHILO_RELAY/);
  const invalid = run(["doctor", "--fix"]);
  assert.notEqual(invalid.status, 0);
  assert.equal(invalid.stdout, "");
});

test("one package.json version generates the plugin's install files", async () => {
  const version = JSON.parse(await readFile("package.json", "utf8")).version;
  const read = async (file: string) => JSON.parse(await readFile(file, "utf8"));
  assert.deepEqual((await read(".mcp.json")).mcpServers.pythilo.args, ["-y", `pythilo@${version}`]);
  assert.equal((await read(".claude-plugin/plugin.json")).version, version);
});

test("no relay domain is built into the bundle", async () => {
  const bundle = await readFile("dist/cli.mjs", "utf8");
  assert.ok(!/crabrix\.com/i.test(bundle));
  for (const name of ["crabrix-playground-v1", "crabrix-runtime-v1", "crabrix-runtime-edit-proof-v1", "crabrix-runtime-source-v1", "crabrix-handoff-v1", "X-Crabrix-Codecs", "shared-std-v1"]) assert.ok(!bundle.includes(name), name);
  for (const name of ["pythilo-playground-v1", "pythilo-runtime-v1", "pythilo-runtime-edit-proof-v1", "pythilo-runtime-source-v1", "pythilo-handoff-v1", "X-Pythilo-Codecs", "python3-v1"]) assert.ok(bundle.includes(name), name);
});

test("participant names that look like options still start a real MCP server", async () => {
  for (const name of ["--help", "--version", "Review agent 🐍"]) {
    const transport = new StdioClientTransport({ command: process.execPath, args: [path.resolve("dist/cli.mjs"), "--name", name], stderr: "pipe", env: cleanEnvironment() });
    const client = new Client({ name: "named-participant-regression", version: "1" });
    try {
      await client.connect(transport);
      const result = await client.callTool({ name: "pythilo_status", arguments: {} });
      assert.equal((result.structuredContent as any).connected, false);
    } finally { await client.close(); await transport.close(); }
  }
});

test("invalid mixed CLI flags fail without writing text into the MCP stdout channel", () => {
  for (const args of [["--name"], ["--version", "extra"], ["--name", "Alice", "--help"], ["--help", "--version"], ["--relay"], ["--relay", "http://127.0.0.1:3212", "--relay", "http://127.0.0.1:3213"], ["doctor", "--json", "--json"], ["doctor", "--relay"]]) {
    const result = run(args);
    assert.notEqual(result.status, 0, JSON.stringify(args));
    assert.equal(result.stdout, "");
    assert.match(result.stderr, /Pythilo MCP/);
  }
});

test("an invalid relay stops the server before it speaks MCP and never echoes credentials", () => {
  for (const relay of ["https://user:relay-secret@relay.example", "https://relay.example/api", "ftp://relay.example", "relay.example"]) {
    const fromFlag = run(["--relay", relay]);
    assert.equal(fromFlag.status, 2, relay);
    assert.equal(fromFlag.stdout, "");
    assert.match(fromFlag.stderr, /--relay must be a relay origin/);
    assert.ok(!fromFlag.stderr.includes("relay-secret"));
    const fromEnvironment = run([], { ...cleanEnvironment(), PYTHILO_RELAY: relay });
    assert.equal(fromEnvironment.status, 2, relay);
    assert.match(fromEnvironment.stderr, /PYTHILO_RELAY must be a relay origin/);
  }
});

test("doctor --json --relay checks a live relay's /healthz and room route", async () => {
  const { origin, close } = await startRelay();
  try {
    const { stdout } = await promisify(execFile)(process.execPath, [path.resolve("dist/cli.mjs"), "doctor", "--json", "--relay", origin], { env: cleanEnvironment() });
    const report = JSON.parse(stdout);
    assert.equal(report.ok, true, stdout);
    assert.deepEqual(report.relay, { origin, source: "--relay" });
    assert.equal(report.checks.find((check: any) => check.name === "relay").status, "ok");
    assert.equal(report.checks.find((check: any) => check.name === "release").status, "ok");
  } finally { await close(); }
});

test("official MCP client discovers and invokes the isolated bundled stdio executable", async () => {
  const directory = await mkdtemp(path.join(tmpdir(), "pythilo-mcp-stdio-"));
  const binary = path.join(directory, "bridge.mjs");
  await copyFile(path.resolve("dist/cli.mjs"), binary);
  const transport = new StdioClientTransport({ command: process.execPath, args: [binary], cwd: directory, stderr: "pipe", env: { PATH: process.env.PATH ?? "" } });
  const client = new Client({ name: "pythilo-mcp-qualification", version: "1.0.0" });
  let errors = "";
  transport.stderr?.on("data", bytes => { errors += bytes; });
  try {
    await client.connect(transport);
    assert.match(client.getInstructions() ?? "", /Pyodide/);
    assert.equal(client.getServerVersion()?.name, "pythilo");
    const tools = await client.listTools();
    assert.deepEqual(tools.tools.map(t => t.name).sort(), ["pythilo_snapshot", "pythilo_handoff", "pythilo_connect", "pythilo_create", "pythilo_status", "pythilo_read_file", "pythilo_apply_changes", "pythilo_select", "pythilo_disconnect", "pythilo_end_room", "pythilo_runtime_clients", "pythilo_runtime_request", "pythilo_runtime_start", "pythilo_runtime_inspect", "pythilo_runtime_control"].sort());
    assert.equal(tools.tools.length, 15);
    assert.equal(tools.tools.find(t => t.name === "pythilo_read_file")?.annotations?.readOnlyHint, true);
    assert.equal(tools.tools.find(t => t.name === "pythilo_runtime_clients")?.annotations?.readOnlyHint, true);
    assert.equal(tools.tools.find(t => t.name === "pythilo_apply_changes")?.annotations?.readOnlyHint, false);
    const words = JSON.stringify(tools.tools);
    assert.ok(!/crabrix|\brust\b|cargo|edition|breakpoint|\blocals\b/i.test(words), "no Rust or debugger wording is left");
    const status = await client.callTool({ name: "pythilo_status", arguments: {} });
    assert.equal((status.structuredContent as any).connected, false);
    assert.equal((status.structuredContent as any).relay, "https://pythilo.com");
    const invalid = await client.callTool({ name: "pythilo_connect", arguments: { link: "https://example.com/secret-that-must-not-leak" } });
    assert.equal(invalid.isError, true);
    assert.ok(!JSON.stringify(invalid).includes("secret-that-must-not-leak"));
    const resource = await client.readResource({ uri: "pythilo://playground/status" });
    assert.equal(JSON.parse((resource.contents[0] as any).text).connected, false);
    const prompts = await client.listPrompts(); assert.equal(prompts.prompts[0].name, "work_in_pythilo");
    const prompt = await client.getPrompt({ name: "work_in_pythilo", arguments: { task: "Add a small Python example" } });
    assert.equal(prompt.messages[0].role, "user");
    assert.match((prompt.messages[0].content as any).text, /Pyodide/);
    assert.equal(errors, "");
  } finally { await client.close(); await transport.close(); await rm(directory, { recursive: true, force: true }); }
});
