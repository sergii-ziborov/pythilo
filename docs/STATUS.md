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
| 236 lessons in 17 courses and 20 interview tasks | Every solution passes on the Mac (`scripts/verify-lessons.py`) and inside the app on the simulator (`testEveryBundledLessonSolutionPassesOnTheDevice`); starters fail their checks |
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
| MCP bridge `pythilo`: 15 tools, revision conflicts, runtime requests | 59 tests; the official archive at `https://pythilo.com/downloads/pythilo-0.1.0.tgz` passes `doctor` against production. Not published to npm |
| MCP served by the app on the local network | Checked, as before |
| Hosting the relay and website | Live at https://pythilo.com on the Helsinki node. Website completion and release checks are recorded in `site/DEPLOY.md` |
| A browser host only runs while its tab is visible; `asyncio.run` in the browser needs Chrome or Edge | Known limits |

Website completion was published on 5 November 2026 through Hostwatch. The live
home, 15-page guide, lesson catalog, playground, Connect AI, pricing, support and
legal pages now match the app's 204 lessons, 20 interview tasks and 22 labs. The
mounted Next.js page cache is versioned on startup so old HTML cannot hide a new
release. All 75 site tests and the public production smoke checks passed, including
encrypted room updates, presence, view-only access and owner close. Browser checks
covered Python execution, lesson checks, live edits, desktop and mobile layouts.
Support, privacy and security aliases use Forward Email with Vercel DNS; the SMTP
server accepts all three recipients. Inbox delivery was not tested with a message.

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

Build **15** (0.1.0) became `VALID` on 5 November 2026 and is `IN_BETA_TESTING` for
the existing internal group. The finish script now respects groups that already
receive all builds automatically. The App Store 1.0 draft remains
`PREPARE_FOR_SUBMISSION` with manual release: text, links, categories, review
contacts, age answers, US$9.99 price and all eight screenshots are saved. Every
screenshot reports `COMPLETE`. No App Review or Beta App Review was requested.

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

## Release model

- Release model confirmed 5 November 2026: a paid app at US$9.99, with regional prices from Apple. No StoreKit unlock is needed. The TestFlight beta stays free; App Review has not been requested. App Store text is in `docs/app-store/en-US.json`, with screenshots alongside it.

## Learning expansion (5 November 2026)

Added 32 lessons in Algorithm patterns, Data in practice, Reliable Python and
Machine learning in practice. Each lesson has prose, a runnable example, a task,
three progressive hints, an explanation and 3–6 deterministic checks. All 32
solutions pass locally, all browser-compatible solutions pass in Pyodide, and all
256 lesson/task solutions pass inside the iOS Simulator.

Added ten labs shared between the website and iOS: Prefix Sums, Monotonic Stack,
Topological Sort, 0/1 Knapsack, Bellman–Ford, Edit Distance Rows, Linear Regression,
Logistic Regression, Nearest Neighbours and Decision Stumps. The native catalog
now has 32 labs. The expansion catalog and starter/answer files are bundled with
the Python runtime; Swift loads the same metadata that prepares the browser labs.

The new `/labs/` section has an editable Python workspace, real line traces,
array/variable/chart panels, play/pause/scrubbing, checks, worked answers and local
saved drafts/completion. No server executes learner code. Browser traces keep up
to 180 distinct frames; checks still run on the full solution. Comprehension
internals are omitted so the supplied worked examples replay to completion.

Validation: 76 site tests passed, including every new lab's starter/answer in
Pyodide and the complete lesson checker. Focused native content tests passed for
all lesson solutions, all lab answers/starters and the exact 32-lab catalog.
The first broader native run timed out in the existing Graph Explorer scaling
test; that test passed on its own (1.96 seconds). The focused content checks
passed with all new content included. The initial timeout is retained in
`build/logs/expansion-native-labs.log`.

The expanded website was deployed through Hostwatch on 5 November 2026 at 19:22
UTC. Serving image: `sha256:57727030bc4db2d93be2290eb4f01617815a3a0c4efb86fa96fbe6572c654803`.
Deployment receipt: `pythilo-learning-expansion-deploy-20261105-v2`. Public smoke
checks passed, including the new course pages and isolated `/labs/` routes. Browser
checks verified lesson example output and a passing solution, lab starter failures,
worked-answer success, replay to the final state, saved completion and 390 px layouts.

A final follow-up at 19:31:52 UTC added the home-page link to browser labs and
included lab drafts/completion in the privacy storage table. Serving image:
`sha256:befd00129498ce5cb430cda0976f2659bb2f8c37f3d209ab8bf67598c80c69f2`;
receipt `pythilo-learning-expansion-final-deploy-20261105-v3`. The expanded public
smoke checks passed again. The signed build 16 archive contains all 18 course
records (256 lessons/tasks) and byte-identical new lab sources. The public sitemap
contains every new lesson and lab URL.

App Store and beta descriptions now say 236 lessons, 17 courses and 32 labs. The
Learn marketing screenshot was refreshed to 236 lessons; all eight Apple assets
report COMPLETE, with the six iPhone screenshots kept in order. The draft remains
PREPARE_FOR_SUBMISSION with MANUAL release. No review was requested.
