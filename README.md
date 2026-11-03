# Pythilo

A Python IDE, course and lab for iPhone and iPad. CPython runs on the device, with
no cloud runtime. `Pythilo` is a working name.

## Build

Needs Xcode 27, xcodegen and Python 3.14 on the Mac.

```sh
scripts/generate-project.sh
python3 scripts/vendor-packages.py
open Pythilo.xcodeproj
```

Tests run inside the app, against the embedded interpreter:

```sh
xcodebuild -project Pythilo.xcodeproj -scheme Pythilo -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

`python3 scripts/verify-lessons.py` checks the course files on the Mac.

This repository has no CI or CD. Builds, tests and releases are run by hand. For
TestFlight, `scripts/testflight.sh` archives and uploads, then
`scripts/testflight-finish.mjs` waits for Apple and adds the notes and the internal group.

`pydantic-core` has no iOS wheel anywhere, so `scripts/build-pydantic-core.sh` builds it
with Rust (`rustup target add aarch64-apple-ios aarch64-apple-ios-sim`) before
`scripts/vendor-packages.py` runs.

## Website, relay and MCP bridge

`site/` is the website, the room relay and the browser playground (Next.js, Pyodide).
`sdk/` is the `pythilo` MCP bridge an AI client runs. Neither is deployed or published
yet, and nothing in them names a production domain. Locally:

```sh
cd site && pnpm install && pnpm build && SITE_ORIGIN=http://127.0.0.1:3212 pnpm start
cd sdk && npm install && npm run build && npm test
```

The app joins a local relay in Debug builds with the launch argument
`-pythiloRelay http://127.0.0.1:3212`. `docs/design/ROOMS.md` is the contract the three
clients share; `site/DEPLOY.md` covers hosting.

## Layout

| Path | What it is |
| --- | --- |
| `Pythilo/Runtime` | The C host and Swift session around CPython |
| `Pythilo/PythonRuntime/pythilo_runtime` | The Python side: runner, shell, debugger, pip, analysis, notebooks, lessons, labs |
| `Pythilo/Projects` | Project folders, the open workspace, Git commands |
| `Pythilo/MCP` | The MCP server the app hosts over Streamable HTTP on the local network |
| `Pythilo/Playground` | Shared rooms: relay session, encryption, Yjs codec, the device as a runtime host |
| `site/` | Website, relay and browser playground |
| `sdk/` | The `pythilo` MCP bridge for AI clients |
| `Pythilo/UI/Workspace` | The IDE, with one arrangement per screen shape |
| `Pythilo/Resources/Courses` | Lessons and interview tasks |
| `Vendor/PythiloGitCore` | libgit2 and its Swift wrapper |
| `docs/STATUS.md` | What works, what was checked, what is missing |

The screens are designed on the [design canvas](https://claude.ai/artifact/1Nh2dSBeFktQYok5CT3Qeb).
