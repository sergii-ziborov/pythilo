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
| A started server shows "Django is running" with Open site; the preview's path is editable | Checked: the runtime reports the socket a program listens on, for Django, Flask's werkzeug and Uvicorn alike |
| The framework's commands as chips in the terminal; Django's full list once `manage.py` prints it | Checked |
| `npm install` from the npm registry: semver, hoisting, integrity, package-lock.json; no install scripts | Checked: React and Express on the Mac, React on the simulator |
| `npm run build` / `dev` / `npx esbuild`: esbuild-wasm in a hidden web view; `dev` rebuilds on save | Checked: the React and FastAPI template installs, builds and serves on the simulator. Scripts that need Node (vite, webpack) say so |
| Packages has its own button beside Run | Checked by screenshot |

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
| Pyflakes problems and Jedi completion on their own thread | Checked, completion included: the project's own modules and the standard library |

## Learning (sections 16 and 17)

| Item | State |
| --- | --- |
| 204 lessons in 13 courses and 20 interview tasks | Every solution passes on the Mac (`scripts/verify-lessons.py`) and inside the app on the simulator (`testEveryBundledLessonSolutionPassesOnTheDevice`); starters fail their checks |
| PyTorch on the device | torch-ios conformance suite matches a Mac on 203 groups of operations in the simulator (`testPyTorchMatchesTheReferenceBuild`); not yet run on a physical iPhone |
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
| Website: home, lessons that run and check in Pyodide, playground, rooms, Connect AI | Checked in a browser against the local server. Every lesson the browser can run passes the app's own checker in Pyodide; lessons that need torch, Flask, threads or packages Pyodide lacks say they need the app |
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

PyTorch 2.15 is bundled, built from source by
[torch-ios](https://github.com/sergii-ziborov/torch-ios) (`scripts/build-torch.sh`): the
full library with autograd and the Python bindings, on the CPU, matrix maths through
Accelerate. Checked on the simulator by `RuntimeGateTests` (training, NumPy, linalg,
fft, conv, `torch.func`, `torch.jit`, DataLoader, save and load, and the PyTorch
template reaching 95 % on its spirals); not yet run on a physical iPhone. No MPS, no
`torch.compile`, no DataLoader workers. ExecuTorch, ONNX Runtime, SciPy and
scikit-learn still have no iOS wheels for CPython 3.14.

`pythilo.coreml` runs Core ML models from Python on the CPU, the GPU or the Neural
Engine, with timings and an agreement check against the CPU, and a sample model
(`scripts/make-sample-model.py`). Checked on the simulator, which has no Neural Engine,
so the Neural Engine numbers still need a physical device.

## Not started

- StoreKit purchase (section 4, P6): waits for the choice between a free download with one unlock and a paid app. A first App Store listing is drafted in `docs/app-store/listing.md`, holding only checked claims
