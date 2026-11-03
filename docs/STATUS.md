# Pythilo status

Written against product plan 1.1 (1 November 2026). "Checked" means it ran for real
inside the app on the iOS Simulator. Nothing here has been checked for App Review.

## Runtime (plan sections 9 to 11, P0-A and P0-B)

| Item | State |
| --- | --- |
| Embedded CPython 3.14.10 from BeeWare's support package, hash pinned | Checked |
| Print, files, exceptions with source lines, `SystemExit`, `os._exit` refused | Checked |
| `input()` and end of input | Checked |
| Stop: infinite loop, `sleep`, `input`, blocking socket, asyncio, code catching one interrupt | Checked |
| Stop on a compiled call that never returns | Designed to report "cannot be stopped". Not exercised |
| Repeated Run and Stop, large output, leftover threads reported | Checked |
| Switching projects does not leak modules, paths or environment | Checked |
| NumPy across repeated runs | Checked |
| pip into a per-project folder, pure wheels from PyPI | Checked |
| Fork-free terminal: files, Python, pip, pytest, Django, Flask, Uvicorn, Git | Checked, apart from the Git commands listed below |

All projects share one process. Resetting between runs is cleanup, not a security
boundary, and the app says so.

## Web and notebooks (sections 12 and 13)

| Item | State |
| --- | --- |
| Django with SQLite, migrations, real HTTP, Stop, restart on the same port | Checked |
| Flask, and Starlette on Uvicorn, real HTTP and restart | Checked |
| FastAPI with Pydantic validation, async routes, a WebSocket, TestClient | Checked: the template's pytest passes on the device. `pydantic-core` is built here by `scripts/build-pydantic-core.sh`, since nobody publishes an iOS wheel. `/docs` loads Swagger UI from a CDN |
| Notebooks: `.ipynb` round trip, shared namespace, rich output, stale marker | Checked at the model level. Native notebook, not Jupyter |
| Real Jupyter server and kernel | Not done |
| pandas and Matplotlib | Not bundled. No cp314 iOS wheels exist on PyPI or BeeWare's channel (checked 3 November 2026), and building them here was not attempted |

## Tools (sections 14 and 15)

| Item | State |
| --- | --- |
| Debugger: breakpoints, stepping, locals, evaluate, stop while paused | Checked in the runtime. Screen not driven by hand yet |
| Breakpoints in threads, web request handlers and async code | Checked. One thread pauses at a time and the panel names it; the others keep running |
| Debugging notebook cells | Not done |
| Git with libgit2 and a real `.git`: init, stage, commit, log, diff, branches, safe switch, HTTPS clone | Checked |
| Fetch, fast-forward pull, push, Keychain tokens | Written. Not run against a real remote |
| `git merge` (fast-forward, merge commit, conflicts with markers, `--abort`) and `git rebase` | Checked by the package's own tests on macOS, the same libgit2 code. Rebase is all or nothing: at a conflict it is undone |
| SSH, submodules, LFS | Not done, and refused rather than faked |
| Pyflakes problems and Jedi completion on their own thread | Problems checked. Completion not exercised |

## Learning (sections 16 and 17)

| Item | State |
| --- | --- |
| 36 lessons and 20 interview tasks | Every solution passes on the embedded interpreter |
| Learn screens: path, course timeline, lesson read and code modes, check sheet | Checked on the simulator. Drawn on the canvas, iPad lesson included |
| Failed checks say what came back and what was expected | Checked against every lesson's starter code on the Mac |
| Long lines wrap in the lesson editor, the tail indented under its own code | Checked by screenshot |
| Sorting Bench: traces of the user's real code, measurements without the tracer | Checked |
| Graph Explorer (BFS, DFS, Dijkstra), Search & Hashing, Dynamic Programming | Checked: traces come from the user's code through instrumented graph, keys and table. DFS orders are judged as valid depth-first orders, not one fixed answer |

## Rooms, website and MCP (section 18)

Ported from the Crabrix playground with its own namespace (`docs/design/ROOMS.md`).
The relay keeps rooms in memory and only ever sees encrypted text.

| Item | State |
| --- | --- |
| App: share a project as a room, join by link or `pythilo://`, edits both ways, remote cursors, end room | Checked against a local relay, by tests and by hand |
| App as a runtime host: check, run and test for a browser or an AI client, asked each time or allowed for the room, result says where it ran | Checked: a browser and the MCP bridge each ran pytest on the simulator |
| Website: home, lessons that run and check in Pyodide, playground, rooms, Connect AI | Checked in a browser against the local server. 56 lessons' solutions pass the app's own checker in Pyodide; Flask's lesson says it needs the app |
| Browser "Run on" another device in the room | Checked: browser to simulator |
| MCP bridge `pythilo`: 15 tools, revision conflicts, runtime requests | 58 tests, and checked against the live room. Not on npm yet |
| MCP served by the app on the local network | Checked, as before |
| Hosting the relay and website | Not done: no domain or server chosen. `site/DEPLOY.md` is ready for one |
| A browser host only runs while its tab is visible; `asyncio.run` in the browser needs Chrome or Edge | Known limits |

## Screens

Designed on the canvas linked from the README. Checked by screenshot on simulators:
vertical and horizontal iPhone, the Duo cover screen on the real simulator display.

Duo laptop, book and flat, and iPad landscape, were captured at their exact sizes
with debug launch arguments on an iPad simulator, because Device Hub cannot drive
the hinge here. The hinge reader itself has not been exercised. The sideways phone
with the camera on the right, the external keyboard pill with a real keyboard, and
the swipe gestures have not been driven by hand.

## Device and TestFlight

The test suite has not run on a physical iPhone yet: Xcode lost the connection to the
phone each time. Run it with the phone unlocked and on a cable.

TestFlight is uploaded by hand with `scripts/testflight.sh` and
`scripts/testflight-finish.mjs`, built with Xcode 27.2. Every build so far reached beta
testing for the internal group. Two things to settle before an
App Store release:

- `ITSAppUsesNonExemptEncryption` is false, but the app ships OpenSSL with Python and
  libgit2's HTTPS. Check the export compliance answer for this.
- Crashes inside the prebuilt Python and NumPy frameworks will not symbolicate, because
  those frameworks come without dSYMs.

## Machine learning (section 19)

No iOS wheels exist for PyTorch, ExecuTorch, ONNX Runtime, SciPy or scikit-learn on
CPython 3.14. A full PyTorch build was not attempted on this Mac; the reasons and the
Core ML route are in `docs/research/ml-on-ios.md`. The Core ML bridge is not built.

## Not started

- StoreKit purchase and App Review materials (section 4, P6)
