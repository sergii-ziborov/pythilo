# Shared rooms: the Pythilo contract

Pythilo rooms are a port of the Crabrix playground (`~/dev/crabrix-poc/site`,
`~/dev/crabrix-sdk`, `~/dev/crabrix-poc/Crabrix/Playground`). The relay, the Yjs
document, the encryption and the signed runtime protocol stay as Crabrix has them.
What changes is the product namespace, the document rules and who runs the code.
Three clients speak this contract: the website (`site/`), the MCP bridge (`sdk/`)
and the iOS app (`Pythilo/Playground/`). Screens are on the design canvas, in the
"Website and shared rooms" row and the RoomShare and RoomActive boards.

## Namespace

Every Crabrix name below is replaced, so a Crabrix client never accepts a Pythilo
room or job, and the other way round.

| Crabrix | Pythilo |
| --- | --- |
| `crabrix-playground-v1` (AES-GCM additional data) | `pythilo-playground-v1` |
| `crabrix-runtime-v1` | `pythilo-runtime-v1` |
| `crabrix-runtime-edit-proof-v1` | `pythilo-runtime-edit-proof-v1` |
| `crabrix-runtime-source-v1` | `pythilo-runtime-source-v1` |
| `crabrix-handoff-v1` | `pythilo-handoff-v1` |
| `X-Crabrix-Codecs` header | `X-Pythilo-Codecs` |
| `crabrix.*` browser storage keys | `pythilo.*` |
| `crabrix://` app links | `pythilo://` |
| MCP tools `crabrix_*` | `pythilo_*` |
| runtime profile `shared-std-v1` | `python3-v1` |

Only codec 1 (format v1) is supported. Format v2 stays out until it is needed.

## Relay origin

There is no production domain yet. Nothing may hard-code one.

- Site: `SITE_ORIGIN` env var, as in Crabrix.
- SDK: a room link carries its origin. Creating a room needs `PYTHILO_RELAY`
  (or `--relay <origin>`); without it `pythilo_create` explains that.
- App: Info.plist key `PythiloRelayOrigin` (empty for now), overridden in Debug by
  the launch argument `-pythiloRelay http://127.0.0.1:3212`. The app accepts room
  links only from that origin.

Local development runs the site at `http://127.0.0.1:3212`.

## Links

`<origin>/playground/room/<24-char id>/#key=<43>&access=<43>&expires=<ms>&mode=edit|view`

The key and the capability stay in the fragment. `pythilo://playground/room/<id>/#...`
opens the same room in the app, against the configured origin.

## Document

Yjs document, as in Crabrix: map `meta` and map `files` (path to text).

- `meta`: `schemaVersion` (1), `name`, `entryFile`, `origin`. No `edition`.
- `entryFile` ends in `.py`; default `main.py`.
- Text files only. Allowed: `.py .pyi .txt .md .rst .csv .tsv .json .toml .cfg .ini
  .yaml .yml .html .css .js .sql`, and the names `requirements.txt`, `LICENSE`,
  `NOTICE`, `README`, `.gitignore`.
- Refused folders: `__pycache__`, `.venv`, `venv`, `.git`, `.pythilo`,
  `site-packages`, `node_modules`, `.mypy_cache`, `.pytest_cache`.
- Limits stay as in Crabrix format v1: 16 files, 64 KiB each, 128 KiB in all.
- Revision: SHA-256 of the document JSON with files sorted, as in Crabrix.

## Running code

The relay never runs code. A device in the room runs it, and says so.

- Hosts: the browser (Pyodide in a worker) and the iPhone or iPad app (embedded
  CPython). Each host advertises itself in presence with its runtime fingerprint,
  for example `Pyodide 0.x · Python 3.13` or `CPython 3.14.10 · iOS`.
- Operations a controller may start: `check` (compile and pyflakes), `run` (the
  entry file), `test` (pytest when the host has it, otherwise unittest discovery).
  Inspection: `status`, `stdout`, `stderr`, `diagnostics`. Control: `stop`.
  Crabrix's `build`, `debug`, `locals`, `step`, `continue` and `breakpoints` are
  left out of `python3-v1`. Job and envelope shapes are otherwise Crabrix's.
- A host's presence entry says what it is: `kind` (`browser` or `ios`), a display
  name ("Ada", "Serhii's iPhone"), the runtime fingerprint and the operations it
  accepts.
- Controllers: the MCP bridge, and the website (the "Run on" choice). A request
  is a signed envelope as in Crabrix, with the edit-capability proof.
- The host asks its owner every time, unless the owner chose otherwise for this
  room. A grant lasts at most 10 minutes; a job runs at most 120 seconds.
- Every result carries: where it ran (host name and kind), runtime fingerprint,
  source revision, start time, duration, status and exit code.
- Git commit and push never travel through a room.

## Limits and expiry

As in Crabrix: lifetime 1 minute to 24 hours (web UI offers 1, 4, 12, 24 h),
4 live participants, rate limits unchanged. Expiry is fixed at creation.
