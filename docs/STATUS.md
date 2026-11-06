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
| 308 lessons in 23 courses and 100 interview tasks | All 408 solutions pass inside the app on the simulator (`testEveryBundledLessonSolutionPassesOnTheDevice`). All 465 reading blocks also execute independently (`testEveryReadingExampleRunsIndependentlyOnTheDevice`). |
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

Build 16 completed processing at 19:53:58 UTC and is IN_BETA_TESTING for the
existing internal group (one tester). A subsequent executable-example check found
a quoting error in the JSON-boundary reading example, while its solution and
checks were already passing. The example now uses a single-quoted Python string
around the JSON object. A new Pyodide regression test executes every example in
the four practical courses; all 77 site tests pass, including all 32 new examples.
Build 17 packages this reading-only correction.

The JSON-example correction was deployed at 19:59:41 UTC as image
`sha256:271aa96e03669d5a892ba84ef6d9de3fd4416a1be423bbcbd24b306ed9b80083`,
receipt `pythilo-learning-example-fix-deploy-20261105-v4`. The public lesson serves
the corrected code and the full public smoke test passes. Build 17 was archived,
its corrected course file checked against source, and uploaded successfully; Apple
processing and final TestFlight notes are followed by `scripts/testflight-finish.mjs`
with `build/notes-17.json`. Build 16 remains available in internal beta testing.

## ML, AI and interview expansion (5–6 November 2026)

The app now bundles 52 Labs: Basics 5, Data structures 8, Algorithms 10,
Machine learning 21 and Artificial intelligence 8. Twenty additions cover
preprocessing, classification metrics, thresholds, validation folds, ridge,
gradient checks, Adam, mini-batches, Naive Bayes, PCA, silhouette, stable softmax,
attention, causal masks, nucleus candidates, beam search, BPE, cosine retrieval
and layer normalization. The shared engine renders numeric matrices as grids.
The native catalog shows the total, ML/AI filters, search, an empty-result state
and the installed build number; ML and AI appear first in the unfiltered list.

Interview practice has 100 tasks (35 Easy, 45 Medium, 20 Hard). Existing IDs are
preserved. The 80 additions include standalone reading examples, progressive
hints, explanations, ordinary/boundary checks and input-mutation checks. Two
companion courses add 12 ML and 8 AI lessons, giving 256 path lessons in 19 courses
and 356 total lesson/task records. The browser shares 30 Labs and the same checks.

The Next.js blog adds six practical articles with original SVG covers, tested
Python, primary references and links to the corresponding lessons and labs.
Topics: leakage, precision/recall, attention, vector retrieval, decoding and BPE.

Validation: all 120 lessons/tasks in the expanded course files pass the authoring
verifier; all 356 bundled solutions pass inside the iOS Simulator. Every native
Lab answer traces and passes, and every starter fails with readable feedback.
The UI test opens the 52-lab catalog, selects AI, opens attention, loads the worked
answer and verifies a successful trace. Its retained screenshots are exported to
`build/verification/native-52-labs/`. All 80 site tests pass, including all 80 new
interview examples, all 52 practical course examples, every new blog example and
all 30 browser Lab answer/starter runs. Local production smoke checks pass.

The signed build 18 archive was checked against the final course JSON and Lab
sources byte for byte. App Store draft and TestFlight metadata say 256 lessons,
19 courses, 100 interview tasks and 52 Labs. The Learn and Labs marketing images
were refreshed, using the actual new native catalog; all eight Apple screenshot
assets are COMPLETE. The version remains PREPARE_FOR_SUBMISSION with MANUAL
release. No App Review or Beta App Review submission was made.

The expanded website is live as of 5 November 2026, 22:03:09 UTC (6 November
locally), through Hostwatch receipt `pythilo-intelligence-100-deploy-20261105-v2`.
Serving image: `sha256:846c5b24418bf743615979992e849cf6de6d85bac48703a6ea0b2b13c929a749`.
Public smoke checks passed, and browser verification showed the 100-task catalog,
eight articles and a causal attention replay with the correct final matrix and
all checks passing. App build 18 is being uploaded separately through TestFlight;
review submission remains explicitly prohibited.

A website-only follow-up at 22:27:50 UTC provides PNG covers for all eight blog
posts and matching Open Graph/Twitter/RSS metadata. Targeted asset tests, the
production build, individual public article/image/feed checks and the full public
smoke test pass. Current serving image:
`sha256:d6d956f87350ad3e21c2d43fa8317ba600685d0a997f4a2cc3960f2e4f7c8252`;
receipt `pythilo-blog-share-covers-deploy-20261105-v4`.

Build 18 completed Apple processing at 22:35:05 UTC and is IN_BETA_TESTING for
the existing internal group (one tester). A follow-up audit of the original
interview reading blocks found standalone snippets that referenced undefined
functions or input names. Twenty-two blocks were repaired, including complete
asyncio examples. All 112 Python blocks across all 100 interview tasks now run
independently in CPython, Pyodide (including promising asyncio calls) and inside
the iOS Simulator. The new native gate is
`testEveryInterviewReadingExampleRunsIndependentlyOnTheDevice`; all 80 website
tests pass with the interview reading test expanded to every task. Existing task
IDs, checks, hints and solutions are preserved. Build 19 packages this content
correction; its signed archive contains byte-identical checked course JSON.

The interview reading correction was deployed at 22:41:02 UTC through
`pythilo-interview-reading-deploy-20261105-v5`, serving image
`sha256:5af988ab8b6b83822e9d6b64cbc2365d0303f6dd6ab4fa700fb8a4020bc2a57c`.
Public smoke checks pass. A production browser check ran Rotate a list's reading
example without a learner solution and returned `[4, 1, 2, 3]`, exit 0. Build 19
uploaded successfully at 22:41:16 UTC; Apple processing is pending. No review
submission was made.

Build 19 (marketing version 0.1.0) completed processing at 23:07:54 UTC on
5 November 2026 (6 November locally) and is IN_BETA_TESTING for the existing
internal group with one tester. Build ID: `895e1e27-f484-456c-a451-ef7d6648d7bf`.
Apple reports upload COMPLETE with no errors or warnings. Final readback confirms
the App Store draft is still PREPARE_FOR_SUBMISSION with MANUAL release, the
256/19/100/52 content counts match, and all eight screenshot assets are COMPLETE.
No App Review or Beta App Review was requested. Public health is 200. Local
verification servers are stopped; the workspace retains only its preexisting
untracked `.cortex-loom/` directory.

## Button hit targets — 6 November 2026

Trace and several other title/action buttons sized their Button from the outside,
leaving padding and background outside the label's tap region. Moved presentation
into the labels and replaced custom plain styles with `AppButtonStyle` across
Labs, Learn, Projects, the workspace and shared rooms (96 style applications).
The shared style gives the entire label a rectangular interaction shape, a minimum
44 × 44 pt target, pressed feedback and a visible disabled state. Sorting Bench
now uses the same action component as the other labs.

Before the fix, all four single corner taps on Trace failed to run. After the fix,
all four pass on both iPhone and iPad. Seven new UI regression cases cover Trace,
classic sorting, lab filters/cards/choices/chips, lesson Check, project/sharing
buttons and editor Run. The existing attention answer/trace route also passes on
both devices. Run is checked against real Python stdout on both devices, since
the iPad panel tabs do not expose the phone dock's selected accessibility trait.
Evidence: `build/verification/hit-target-before.xcresult`,
`hit-target-after-iphone.xcresult`, `hit-target-after-ipad.xcresult` and
`editor-run-output.xcresult`. The initial iPad suite had one assertion failure for
that trait; the corrected stdout assertion passes on both devices. The release
archive and export for version 0.1.0, build 20, succeeded. Apple accepted the
TestFlight upload at 06:59:05 UTC on 6 November 2026. Build upload
`b126c843-4ae6-45c4-9776-868cd1b73968` completed processing at 07:25:22 UTC
(09:25 locally) and is VALID / IN_BETA_TESTING for the existing internal group
with one tester. Final readback confirms build 20, its tap-target test notes,
and the App Store 1.0 draft still PREPARE_FOR_SUBMISSION with MANUAL release.
No App Review or Beta App Review was requested. Upload validation has no errors
or warnings; Xcode separately reported missing dSYMs in 92 vendored Python
frameworks. Pythilo's own app dSYM is present. Receipt:
`build/release-receipts/button-targets-build-20.json`. Both dedicated Pythilo
simulators have been shut down.

## Library lessons and executable reading audit — 6 November 2026

Added 52 lessons: Pydantic 2 (20), FastAPI/HTTPX (14), practical testing (10), and
file/data formats (8). The catalog now contains 308 path lessons in 23 courses and
100 interview tasks. The lesson sources and runtime version matrix are documented
in `docs/LESSON-SOURCES.md`. Pydantic validators, RootModel/TypeAdapter, ASGI and
mock HTTP transports, actual pytest fixtures, and format examples run using real
libraries. Each new lesson has three checks and three topic-specific hints.

Native simulator gates executed all 408 worked solutions and all 465 reading
blocks independently, without skips. This caught and repaired eight old reading
examples and a module-registration bug in the checker affecting Pydantic generics.
Two UI tests pass: a reading example opens a correctly titled Output sheet, and
a RootModel solution passes through the actual Check button. The report sheet now
uses its run/check kind as the presentation identity, fixing a stale zero-check
heading on successful Run output.

The website is published; `site/DEPLOY.md` records the final image and receipts.
All 82 site tests and production checks pass, including 362 browser solutions,
417 browser reading examples, all 52 new URLs, and cold-start package discovery.
Native-only reading blocks now explicitly say which package/feature requires the
app. Production browser checks ran Pydantic and FastAPI/HTTPX examples and passed
their exercise checks. The package catalog has a content-derived URL to avoid
stale browser caches after adding libraries.

TestFlight 0.1.0 (22) is available to the existing internal group, confirmed at
09:37:53 UTC on 6 November 2026: Apple processing `VALID`, internal state
`IN_BETA_TESTING`, one tester, automatic access to all builds. English and Russian
build-22 notes are attached. There is no Beta App Review submission; App Store 1.0
remains `PREPARE_FOR_SUBMISSION`, manual release. The archive contains the exact
24 course files and checker verified above. Receipt:
`build/release-receipts/testflight-22-ready.json`. Build 21 was superseded before
its upload completed; build 22 includes the verified report-title fix.

## Advanced curriculum and linked Labs (6 November 2026)

Added 74 advanced lessons in seven courses, including six integration projects:
Python runtime ownership/concurrency, resilient transactional services, statistical
ML evaluation, ML production contracts, permission-aware AI systems, PyTorch
training correctness and composed projects. Current totals are 382 path lessons
in 30 courses plus 100 interview tasks. The public `/learn/senior/` paths explain
review evidence and the additional real production/data/model/GPU experience
required for senior work; passing local exercises does not certify a job level.

Added 20 Labs (12 ML, eight AI): 72 native Labs total, including 33 ML and 16 AI;
50 Labs also run in the browser. Forty lesson/Lab pairs link in both directions.
Both native navigation stacks use value-based paths, including Lab links opened
from a lesson. UI checks exercise links near their leading edge, beyond the text.
Scoped website lesson-editor CSS prevents retained styles from overlaying a Lab
and intercepting its links after client navigation.

An order-dependent `torch.export` failure exposed global `atexit` cleanup that
prematurely ran `weakref.finalize` process hooks and removed live PyTorch operator
registrations. The runner now executes only project-owned exit callbacks between
jobs, preserving bundled-library process callbacks. The native regression checks
LIFO/unregister behavior, process-finalizer lifetime and actual PyTorch export
across three jobs.

Validation: all 482 solutions, all 539 independent reading blocks, 74 rejected
advanced starters, every Lab variant answer/starter and both reciprocal native
navigation routes pass in iOS Simulator. Result bundle:
`build/verification/senior-runtime-fixed-native.xcresult`. All 85 site tests and
the 608-page production build pass. Public route/link audits and smoke checks
pass. Browser proof: `build/verification/pythilo-senior-lab-live.png`; native proof:
`build/verification/pythilo-senior-linked-native.png`.

The Release archive for build 23 matches 31 course JSON files and the current
Lab catalog/code/runtime byte for byte (191 checked files). Source proof:
`build/release-receipts/testflight-23-archive-source.json`.

The seven `ButtonHitTargetTests` also pass after the expansion, including Trace
at all four corners, catalog filter/card padding, classic Trace, editor Run,
lesson Check, project/Playground actions and Lab choices. Result bundle:
`build/verification/senior-button-targets.xcresult`. The AI filter expectation
was updated to the actual 16-Lab catalog; no app code changed in this follow-up.

TestFlight 0.1.0 (23) is available to the existing internal group, confirmed at
12:30:53 UTC on 6 November 2026: Apple processing `VALID`, internal state
`IN_BETA_TESTING`, one tester, automatic access to all builds. English and Russian
notes exactly match `build/testflight/build-23-notes.json`. No Beta App Review
submission exists; App Store 1.0 remains `PREPARE_FOR_SUBMISSION` with manual
release. Proof: `build/release-receipts/testflight-23-ready.json`. Upload completed
at 11:58:56 UTC; Apple finished processing at 12:30:24 UTC. No App Review or Beta
App Review was requested.

## ML/AI systems projects and Labs (6 November 2026)

Added 24 linked lessons and Labs, including 12 composed projects: 12 ML Labs and
12 AI Labs. Totals are 406 path lessons in 32 courses plus 100 interview tasks,
96 native Labs (45 ML, 28 AI), 74 browser Labs and 64 reciprocal lesson/Lab pairs.
The advanced paths now contain 98 lessons, including 18 integration projects.

The ML projects train real NumPy ridge/logistic models, audit nested group
selection, walk-forward evaluation and OOF stacking, restore a validation
checkpoint and track delayed-label cohort rollout state. AI projects implement
authorized BM25, versioned index updates/tombstones, bounded context and exact
evidence spans, approved local tool DAGs, scheduling and paired release evidence.
Saved provider-output fixtures and discrete serving simulations are explicitly
identified. Project traces follow the main orchestration function; helper
computations execute and have independent checks. Local state copies do not claim
durable distributed effects, and a valid quote does not prove claim entailment.

All 506 solutions, 563 independent reading blocks, 98 advanced starters and every
Lab variant answer/starter pass in iOS Simulator. The 20 selected native tests
also cover project Check/Trace through the UI, lesson links in both directions,
catalog counts and seven button padding/corner scenarios. Result bundle:
`build/verification/projects24-native.xcresult`. Proofs:
`build/verification/pythilo-projects24-ridge-native.png` and
`build/verification/pythilo-projects24-linked-native.png`.

All 87 site tests pass, including 452 browser solutions, 507 reading blocks and
all 74 browser Lab answers/starters. A fresh-interpreter regression verifies
NumPy discovery and a complete model-project trace. Learner source now has its
own Python file in the worker request so package discovery can see its imports;
embedding it solely in a JSON string had hidden NumPy on first Lab use. The
scoped Lab lesson-link style wraps long project titles; a real 390px browser
check confirms no horizontal overflow. The public model project runs its example,
passes four lesson checks, traces to 31/31 with four passing Lab checks and links
back to the lesson. Proofs: `build/verification/pythilo-projects24-ridge-live.png`
and `build/verification/pythilo-projects24-ridge-mobile.png`.

The final website image and receipts are recorded in `site/DEPLOY.md`. Production
audits pass for 133 URLs, isolation headers and all 64 reciprocal link pairs.
The Release archive for TestFlight 0.1.0 (24) matches 242 current source files,
including 33 course JSON files and the new project engine. Archive proof:
`build/release-receipts/testflight-24-archive-source.json`. Apple accepted upload
at 15:51:24 UTC and processing reached `VALID` at 16:18:06 UTC. Internal TestFlight
0.1.0 (24) is available to the existing group: `IN_BETA_TESTING`, one tester,
automatic access to all builds, confirmed at 16:18:24 UTC. English and Russian
notes exactly match `build/testflight/build-24-notes.json`. No Beta App Review
submission exists; App Store 1.0 remains `PREPARE_FOR_SUBMISSION` with manual
release. No App Review or Beta App Review was requested. Proof:
`build/release-receipts/testflight-24-ready.json`.

## PyTorch projects and topic navigation (6 November 2026)

Added 18 real PyTorch CPU Labs and linked lessons, including six projects:
validation-selected nonlinear classification, exact AdamW/sampling/dropout
continuation, frozen-base low-rank adapter training/merge, a causal pre-norm
decoder block, a trainable tiny tied-embedding language model and a padding-safe
sequence classifier. Focused tasks cover clipping, optimizer ownership,
distillation, contrastive learning, EMA including tied weights, token accumulation,
attention masks, rotary positions, KV chunks, packed documents, GQA and RMSNorm.
All fixtures use small local models; no pretrained download or GPU is claimed.

The app now has 114 Labs (54 ML, 37 AI) in 13 expandable topics, with concept
search. One shared topic index owns every Lab. The site provides section/runtime
filters, search, expandable groups and 18 App required PyTorch pages alongside
74 runnable browser Labs. The 82 lesson/Lab pairs link in both directions.
Totals: 424 path lessons in 34 courses, 100 interview tasks, 116 advanced lessons
including 24 integration projects, and 581 standalone reading programs.

All 524 solutions, 116 advanced starters, 581 reading programs and all Lab
answers/starters pass the native gates. The 22-test suite also covers seven
button-padding scenarios, six lesson/navigation flows and three catalog/project
UI flows. Result: `build/verification/torch18-native-stable.xcresult`. A final
18-Lab native parity gate passes all 79 PyTorch check groups after the tied-EMA
fix and compares answers/check names with their lesson contracts:
`build/verification/torch18-contract-final.xcresult`. Current bundled engine,
answer and topic bytes match canonical files.

All 90 site tests, TypeScript and the 696-page production build pass. After the
final content update, seven catalog/path tests pass. Real-browser checks cover
topic expand/collapse, search, combined filters, empty results, App required
execution controls and reciprocal links. A long Practice in Lab button was found
to widen lessons to 552px; scoped wrapping fixes it. Lesson, Lab and expanded
catalog pages now remain 390px wide at a 390px viewport. Local route/header/link
audit passes 179 URLs and all 82 pairs.

Release 0.1.0 (25) archives and exports successfully. All 304 checked runtime and
course files, including 35 course JSON files, match the archive byte for byte.
Proof: `build/release-receipts/testflight-25-archive-source.json`. The site is live
on the exact verified image at 17:04:02 UTC; receipts are in
`build/release-receipts/torch18-site-release.json`. Public audit passes 179 URLs,
isolation headers and all 82 pairs; smoke and real-browser checks pass. Public
proofs: `build/verification/pythilo-torch18-catalog-live.png` and
`build/verification/pythilo-torch18-lesson-mobile-live.png`. TestFlight upload and
processing are being checked separately; no App Review or Beta App Review was
requested.
