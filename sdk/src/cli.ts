#!/usr/bin/env node
import { serveStdio } from "@modelcontextprotocol/server/stdio";
import { makeServer } from "./server.js";
import { PlaygroundRoom } from "./room.js";
import { SDK_VERSION } from "./version.js";
import { formatDoctor, runDoctor } from "./doctor.js";
import { configuredRelay } from "./relay.js";

// Each option at most once; a value is taken as given, even when it looks like an option.
function parse(list: string[], valued: string[], flags: string[] = []) {
  const values: Record<string, string> = {}, set = new Set<string>();
  for (let i = 0; i < list.length; i++) {
    const arg = list[i];
    if (flags.includes(arg) && !set.has(arg)) set.add(arg);
    else if (valued.includes(arg) && !(arg in values) && i + 1 < list.length) values[arg] = list[++i];
    else return null;
  }
  return { values, flags: set };
}

const args = process.argv.slice(2);
const usage = () => { process.stderr.write("Pythilo MCP: use --help, --version, doctor [--json] [--relay <origin>], or start with [--name <name>] [--relay <origin>].\n"); process.exitCode = 1; };
if (args.length === 1 && args[0] === "--help") {
  process.stdout.write(`Pythilo SDK + MCP · ${SDK_VERSION}\nShared, encrypted, temporary Python rooms for AI clients and people.\n\nRun without arguments as an MCP stdio server: pythilo [--name <name>] [--relay <origin>].
A room link carries its relay. Creating a room uses https://pythilo.com by default. Set PYTHILO_RELAY or --relay <origin> for another relay; local development uses http://127.0.0.1:3212.
Python runs only on a host in the room, the Pythilo app on iPhone or iPad (CPython) or a browser (Pyodide), after its owner allows it.
Diagnostics: pythilo doctor [--json] [--relay <origin>]. It opens no room, reads no source and changes no setting.
Library: import { Pythilo } from "pythilo";\nNode.js 22 or newer.\n`);
} else if (args.length === 1 && args[0] === "--version") {
  process.stdout.write(SDK_VERSION + "\n");
} else if (args[0] === "doctor") {
  const options = parse(args.slice(1), ["--relay"], ["--json"]);
  if (!options) usage();
  else {
    const report = await runDoctor({ relay: options.values["--relay"] });
    process.stdout.write(options.flags.has("--json") ? JSON.stringify(report, null, 2) + "\n" : formatDoctor(report));
    process.exitCode = report.ok ? 0 : 1;
  }
} else {
  const options = parse(args, ["--name", "--relay"]);
  if (!options) usage();
  else {
    let room: PlaygroundRoom;
    try { room = new PlaygroundRoom(configuredRelay(options.values["--relay"], "--relay")?.origin, options.values["--name"]); }
    catch (error) { process.stderr.write("Pythilo: " + ((error as { code?: string }).code === "RELAY_NOT_CONFIGURED" ? (error as Error).message : "use a printable participant name up to 40 characters.") + "\n"); process.exit(2); }
    const handle = serveStdio(() => makeServer(room), { onerror: () => { process.stderr.write("Pythilo MCP protocol error. No source or private link was logged.\n"); } });
    let closing = false;
    const close = async () => { if (closing) return; closing = true; room.dispose(); await handle.close(); };
    process.stdin.once("end", () => { void close(); });
    process.once("SIGINT", () => { void close(); });
    process.once("SIGTERM", () => { void close(); });
  }
}
