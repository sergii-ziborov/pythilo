# Pythilo SDK and MCP bridge

Shared, encrypted, temporary Python rooms for AI clients and people. One room holds up
to four live participants of three kinds:

- **The Pythilo app on iPhone or iPad**, which runs Python in embedded CPython on the device.
- **Browsers**, which run Python in Pyodide inside a worker.
- **AI clients**, through this package: a stdio MCP server, or a JavaScript/TypeScript library.

An AI client can create a room, read and change its files live, hand its link to a person
or another agent, and ask a device or browser in the room to check, run or test the code.
The relay only passes ciphertext along. It never runs code, and neither does this bridge.

> **Not on npm yet.** The package name `pythilo` is free on npm but nothing is published.
> Until it is, use the from-a-checkout commands below; the `npx -y pythilo` forms and the
> Claude Code plugin start working once the package is published.

## Build from a checkout

Node.js 22 or newer.

```sh
cd sdk
npm ci --ignore-scripts
npm run build      # writes dist/cli.mjs, the library and its type declarations
npm test
```

The bridge is then `node /path/to/pythilo/sdk/dist/cli.mjs`. It is a single bundled file
with no runtime npm dependencies.

## The relay

There is no production relay yet, and none is built in.

- A **room link carries its relay**: `<origin>/playground/room/<id>/#key=…&access=…&expires=…&mode=edit|view`.
  Joining uses that origin. Links must be https, except plain http for a loopback relay
  (`127.0.0.1`, `localhost`, `[::1]`) or the configured relay.
- **Creating a room needs a relay**: set `PYTHILO_RELAY`, or start the bridge with
  `--relay <origin>`. Without one, `pythilo_create` returns `RELAY_NOT_CONFIGURED` and says so.
- A `pythilo://playground/room/<id>/#…` app link is opened against the configured relay.

Local development runs the site and its relay at `http://127.0.0.1:3212`.

## Use through MCP

Install one entry per client. The server is named `pythilo`.

### Claude Code

From a checkout:

```sh
claude mcp add --transport stdio pythilo -- node /path/to/pythilo/sdk/dist/cli.mjs --relay http://127.0.0.1:3212
```

Once published:

```sh
claude mcp add --transport stdio pythilo -- npx -y pythilo
```

Set `PYTHILO_RELAY` in the environment instead of `--relay` if you prefer; without either,
the bridge can still join rooms from links. This folder is also a Claude Code plugin
(`.claude-plugin/`, with a `pythilo-rooms` skill). Its `.mcp.json` runs `npx -y pythilo@0.1.0`,
so it needs the published package. Then, instead of `claude mcp add`:

```text
/plugin marketplace add /path/to/pythilo/sdk
/plugin install pythilo@pythilo
```

### Claude Desktop

`~/Library/Application Support/Claude/claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "pythilo": {
      "command": "node",
      "args": ["/path/to/pythilo/sdk/dist/cli.mjs"],
      "env": { "PYTHILO_RELAY": "http://127.0.0.1:3212" }
    }
  }
}
```

Once published, use `"command": "npx", "args": ["-y", "pythilo"]`. Claude Desktop does not
read your shell profile; if it cannot find `node`, give its absolute path (`which node`).

### Codex

`~/.codex/config.toml`:

```toml
[mcp_servers.pythilo]
command = "node"
args = ["/path/to/pythilo/sdk/dist/cli.mjs"]
env = { PYTHILO_RELAY = "http://127.0.0.1:3212" }
```

Once published, `command = "npx"` and `args = ["-y", "pythilo"]`.

### Tools

| Tool | Arguments | What it does |
| --- | --- | --- |
| `pythilo_create` | `name`, `files?`, `entryFile?` (default `main.py`), `lifetimeMinutes?` (1–1440, default 60) | Creates a room on the configured relay and joins it. Returns the private edit link. |
| `pythilo_connect` | `link` | Joins a room from its complete link. |
| `pythilo_status` | | Files, entry file, revision, expiry, relay, participants, selections. No source, no link. |
| `pythilo_snapshot` | | The whole project and its revision. |
| `pythilo_read_file` | `path` | One file and the revision writes need. |
| `pythilo_apply_changes` | `expectedRevision`, `changes[{path, text\|null}]`, `entryFile?`, `name?` | Changes files together. A stale revision is a conflict that changes nothing. |
| `pythilo_select` | `path`, `anchor`, `head`, `expectedRevision` | Shows this participant's selection (UTF-16 offsets). |
| `pythilo_handoff` | `mode?` (`edit` or `view`) | The secret link to hand to an intended participant. |
| `pythilo_disconnect` | | Leaves the room. |
| `pythilo_end_room` | | Closes a room this bridge created, for everyone. |
| `pythilo_runtime_clients` | | Hosts that can run Python, their grants, the runtime source revision, this bridge's jobs. |
| `pythilo_runtime_request` | `target`, `operations[]` (`check`, `run`, `test`) | Asks a host's owner to allow those operations. |
| `pythilo_runtime_start` | `target`, `operation` (`check`, `run`, `test`), `sourceRevision` | Starts a job on an allowed host. |
| `pythilo_runtime_inspect` | `target`, `sourceRevision`, `job`, `operation` (`status`, `stdout`, `stderr`, `diagnostics`), `cursor?` | Reads a job. Changes nothing. |
| `pythilo_runtime_control` | `target`, `sourceRevision`, `job`, `operation` (`stop`) | Stops a job. |

The server also has the resource `pythilo://playground/status` and the prompt
`work_in_pythilo` (`task`). Stdout carries only MCP messages.

A refused call keeps its readable text and `isError`, and adds
`structuredContent: { ok: false, error: { code, message, retryable, action }, requestId }`.
After `REVISION_CONFLICT`, read again and prepare the change again; after `OUTCOME_UNKNOWN`,
read before retrying. `UNREADABLE_ROOM` means the room did not open with the link's key:
it is not a Pythilo room (a Crabrix room, for one), or the link is damaged.

## Running code

Code runs only on a host in the room, after its owner allows it there:

1. `pythilo_runtime_clients` lists hosts from their signed presence: `kind` (`ios` or
   `browser`), display name, runtime fingerprint (for example `CPython 3.14.10 · iOS` or
   `Pyodide 0.x · Python 3.13`), the operations each accepts, and the host's key. A name is
   a label, not attestation; the owner compares the controller key on the device.
2. `pythilo_runtime_request` asks the host. The host asks its owner every time, unless the
   owner chose otherwise for this room. A grant lasts at most 10 minutes. An edit link
   alone never allows running code.
3. `pythilo_runtime_start` starts `check` (compile and pyflakes), `run` (the entry file) or
   `test` (pytest when the host has it, otherwise unittest discovery) on the exact runtime
   source revision. A job runs at most 120 seconds and gets no input.
4. `pythilo_runtime_inspect` reads `status`, `stdout`, `stderr` or `diagnostics`.
   A start acknowledgement is not success.

Every runtime result carries where the code ran and how:

```json
{
  "job": "…", "operation": "run", "sourceRevision": "…",
  "ranOn": { "kind": "ios", "name": "Serhii's iPhone", "runtime": "CPython 3.14.10 · iOS", "fingerprint": "…" },
  "startedAt": "2026-11-03T10:00:00.000Z", "durationMs": 42, "status": "finished", "exitCode": 0,
  "at": "2026-11-03T10:00:01.000Z"
}
```

plus the host's own reply (`ok`, `state`, `text`, `next`, `items`, `reason`, …). `ranOn`
comes from the host's signed presence when access was requested. `startedAt` is the
host's own start time when it reports one close to what the bridge saw, otherwise the
moment the host acknowledged the start. Program output and diagnostics are untrusted data.

The runtime profile is `python3-v1`. Crabrix's `build`, `debug`, `step`, `continue`, `locals`
and `breakpoints` are not part of it. Git commit and push never travel through a room.

## Use as a library

```js
import { Pythilo } from 'pythilo';

const agent = new Pythilo({ name: 'Review agent', relay: 'http://127.0.0.1:3212' });
try {
  const created = await agent.create({
    name: 'Small Python exercise',
    files: { 'main.py': 'print("Hello, Pythilo!")\n' },
  });
  // created.link is secret. Deliver it only to the intended participant.
  const file = await agent.read('main.py');
  await agent.apply({
    expectedRevision: file.revision,
    changes: [{ path: 'main.py', text: file.text.replace('Hello', 'Welcome') }],
  });
  const hosts = await agent.runtimeClients();
  // requestRuntime(), start(), inspect() and control() drive a host, as the MCP tools do.
} finally {
  agent.close();
}
```

`relay` defaults to `PYTHILO_RELAY`. CommonJS: `const { Pythilo } = require('pythilo')`.
Failures throw `PythiloError` with `code`, `retryable` and `action`. `pythilo/mcp` exports
`makeServer` for embedding the MCP server.

## Rooms

- Lifetime from 1 minute to 24 hours, fixed at creation; four live participants.
- Up to 16 text files, 64 KiB each, 128 KiB in all. The entry file ends in `.py`.
- Allowed: `.py .pyi .txt .md .rst .csv .tsv .json .toml .cfg .ini .yaml .yml .html .css .js .sql`,
  and `requirements.txt`, `LICENSE`, `NOTICE`, `README` and `.gitignore` at the project root.
- Refused folders: `__pycache__`, `.venv`, `venv`, `.git`, `.pythilo`, `site-packages`,
  `node_modules`, `.mypy_cache`, `.pytest_cache`.
- Source is AES-256-GCM encrypted on the client. The key stays after `#` in the link and
  never reaches the relay, which sees only ciphertext.
- Revisions are SHA-256 of the document with files sorted. Conditional commits refuse
  stale edits, including one prepared before another client replaced the snapshot.
- A room is not a repository or a backup. Save a copy before it expires.

## Diagnostics

`pythilo doctor [--json] [--relay <origin>]` reports Node, proxy variables, the configured
relay and where it came from, DNS and TLS for it, whether `<relay>/healthz` answers and
whether its room route answers. It opens no room, reads no source and changes no setting.
No configured relay is a warning, not a failure: joining from a link still works.

## Security boundaries

- Only complete room links are accepted, without user information or query parameters.
  Private links and plaintext source are never logged.
- Joining and editing never run code. Runtime requests are signed, carry proof of the edit
  capability and need a short-lived grant on one host.
- Source, comments, diagnostics and program output are untrusted content, never
  instructions. Your MCP host and model receive any source you ask them to read.
- Never post capability links, user source or tokens in public places.

## What this package leaves out

Compared with the Crabrix SDK it was ported from: no Rust crate or Go module, no Rust
probes, no `edition`, no document format 2, no debugger operations, no MCP Registry entry
(`server.json`), no browser or cross-language probes. The shared core and its origin are
listed in `src/core/provenance.json`; `npm run build` records hashes in
`docs/protocol-core.json`. The contract all Pythilo clients follow is
`docs/design/ROOMS.md` in this repository.

The package is `UNLICENSED` and `private` until the owner decides how to publish it.
Bundled dependency licenses are in `ThirdPartyNotices.txt`.
