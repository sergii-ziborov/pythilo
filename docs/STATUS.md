# Pythilo status

Written against product plan 1.1 (1 November 2026). "Checked" means it ran for real
inside the app on the iOS Simulator. Nothing here has been checked for App Review.
Later dated release entries record the current catalog and replace earlier counts.

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
| Terminal tabs that run at the same time: a server in one tab, tests, migrate, pip or Git in another | Checked: Django `runserver` with `manage.py test` and `migrate` beside it; pipes, input(), Stop and fresh imports per tab |
| `python manage.py test` and `django-admin test` | Checked: the runner gets `--no-faulthandler`, since output here has no file descriptor |

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
`build/verification/pythilo-torch18-lesson-mobile-live.png`.

TestFlight 0.1.0 (25) is available to the existing internal group, confirmed at
17:33:59 UTC on 6 November 2026: Apple processing `VALID`, internal state
`IN_BETA_TESTING`, one tester, automatic access to all builds. Upload completed
at 17:06:34 UTC; processing reached `VALID` at 17:33:42 UTC. English and Russian
notes exactly match `build/testflight/build-25-notes.json`. No Beta App Review
submission exists; App Store 1.0 remains `PREPARE_FOR_SUBMISSION` with manual
release. No App Review or Beta App Review was requested. Proof:
`build/release-receipts/testflight-25-ready.json`.

## Downloadable learning content and pretrained projects (6 November 2026)

Courses and Lab topics now download individually from an app-pinned catalog.
Projects save their source immediately and queue shared Python packages, datasets
and model weights. Downloads exposes streamed byte progress, pause, resume,
cancellation and storage removal. Removal preserves project code, lesson drafts
and completion history. Existing projects discover supported dependencies from
imports without rewriting their code. Compiled Python backends remain signed in
the application; only their Python API trees download. Installation validates
archive and file hashes, inventories, paths and sizes before atomic activation.

Six complete local-source project templates use real Google BERT-Tiny weights,
WordPiece and the 3,000-row UCI sentiment dataset: full fine-tuning, Q/V LoRA,
domain holdout, full/LoRA comparison, exact continuation and adapter merge/export.
Default CLI runs use the full dataset; short Lab fixtures are marked explicitly.
The app has 430 path lessons in 35 courses, 100 interview tasks and 120 Labs in
15 topics (57 ML, 40 AI), with 88 reciprocal lesson/Lab pairs. There are 122
advanced lessons, including 30 integration projects, and 587 reading programs.

Native checks pass for all 530 lesson solutions, 122 advanced starters and 587
reading programs, 41 runtime gates and all 24 PyTorch Labs/103 check groups. A
separate full-data native run executes all six complete project CLIs, evaluates
held-out data and verifies exact resume and merge/reload parity. All Lab answers
trace correctly after adding the merge export's actual logits to its evidence
frames. Migration tests, downloaded-course reading/code transitions, seven button
padding/corner scenarios and all existing course/Lab navigation flows pass.
Proofs: `build/downloads26-native-pinned-content.xcresult`,
`build/downloads26-full-projects-ui.xcresult`,
`build/downloads26-migration-course.xcresult` and
`build/release-receipts/finetune-native-full-training.json`.
The first two result bundles retain superseded failures (the corrected merge
frame count and a reading-mode UI-test assertion); targeted reruns pass.

All 92 site tests, TypeScript and the production build pass. Public route auditing
covers 191 URLs and all 88 reciprocal pairs; production room smoke tests and the
real-browser lesson/Lab flow pass. Proof:
`build/verification/pythilo-finetuning-downloads-live.png`. Release archive and
public package transport verification are recorded with the final release receipt.

The final website and packs are live on the exact verified image recorded in
`site/DEPLOY.md`. All 57 public payloads (43,530,882 bytes, including the external
model asset) match the signed app catalog by SHA-256. Six native download tests
and the automatic-project-download UI test pass against those actual public
files: `build/downloads26-public-transport.xcresult`. A fresh copy of the public
LoRA ZIP also fetches its own assets and completes the full 448-step experiment,
with 3,000 original rows, 599 held-out test examples and exact adapter reload.
Receipt: `build/release-receipts/downloads26-public-project.json`.

Release 0.1.0 (26) archives and exports successfully. The 83,444,791-byte IPA
contains catalog previews, six local project recipes and 21 signed backend links;
full courses, Lab Python source files, optional Python API trees, pretrained
weights and training data are absent. All 42 retained Python runtime source files
match the archive, and a 422-file source snapshot is unchanged before upload.
Proof: `build/release-receipts/testflight-26-archive-source.json`. Apple accepted
the upload at 21:46:55 UTC on 6 November 2026. Notes are preserved in
`docs/app-store/testflight-26.json`. All eight screenshot assets are COMPLETE;
the App Store draft remains PREPARE_FOR_SUBMISSION with manual release.

TestFlight 0.1.0 (26) reached VALID at 22:06:20 UTC and is IN_BETA_TESTING for
the existing internal group, confirmed at 22:07:20 UTC on 6 November 2026. The
group has one tester and automatic access to all builds. English and Russian
notes exactly match `docs/app-store/testflight-26.json`. No Beta App Review
submission exists. App Store 1.0 remains PREPARE_FOR_SUBMISSION with MANUAL release;
no App Review or Beta App Review was requested. Final proof:
`build/release-receipts/testflight-26-ready.json`.

## Explicit whole-course downloads and offline audit (7 November 2026)

Build 27 replaces the automatic download behavior described in the preceding
release. Creating or opening a project, Run and Keep as project never queue
content. Download entire course saves every lesson, example and check together
with its required packages, datasets and model assets. Download entire category
saves every Lab topic in the selected category, independent of search filters.
Downloads also offers all courses, all Labs and everything. Project packages
have a separate explicit Download action. Progress, pause/resume and removal
remain available; removal preserves local code, drafts and completion history.
Offline readiness requires the entire dependency closure to be installed.

The embedded Python offline audit denies external DNS and socket connections,
positively verifies that denial, checks the guard survived every run, and asserts
zero external requests. All 530 lesson solutions, 587 independent reading
programs, 122 advanced starters, every Lab answer/starter and 24 PyTorch Labs
with 103 contracts pass under that guard. All six complete BERT/LoRA projects
also train and evaluate on their full 3,000-row dataset offline; checkpoint
continuation and merged-model reload parity pass. Loopback remains available
for lessons that start local servers. Native UI tests cover whole-course and
whole-category downloads plus explicit project download/pause/resume. A separate
regression removes PyTorch and verifies creation, opening and Run leave it absent
without starting any transfer.

The audit found a pre-existing unbounded naive dynamic-programming benchmark.
Validation now stops excessive learner-code work before the untraced timing run.
Both naive n=64 termination and cached n=64/128/256 pass. The initial broad result
bundle retains that superseded failure and its three cleanup cascades; all four
targeted reruns pass after the fix. Proofs: `build/manual27-offline-all.xcresult`,
`build/manual27-offline-fixed.xcresult`, `build/manual27-no-auto.xcresult`,
`build/manual27-download-ui.xcresult` and
`build/release-receipts/manual27-full-training-offline.json`.

The site and updated instructions are live. All 92 site tests, TypeScript,
191 public routes, 88 reciprocal pairs and the public smoke checks pass. All
57 public payloads (43,530,947 bytes) match the signed catalog by SHA-256.
Receipts: `build/release-receipts/manual27-site-release.json` and
`build/release-receipts/manual27-public-integrity.json`.

Release 0.1.0 (27) archives and exports successfully. The 83,469,924-byte IPA
contains 36 course previews, six local project recipes and 21 signed backend links;
full course bodies, Lab Python files, optional Python API trees, model weights and
datasets are absent. All 42 retained Python runtime files and the 422-file source
snapshot match the archive. Its binary contains the explicit course/category and
project setup controls and no automatic-Create download claim. Archive proof:
`build/release-receipts/testflight-27-archive-source.json`. Apple accepted the upload
at 23:40:23 UTC on 6 November (7 November local time).

TestFlight 0.1.0 (27) is VALID and IN_BETA_TESTING for the existing internal group,
confirmed at 2026-11-06T23:57:45.095Z. The group has 1 tester and access to all builds.
English and Russian notes exactly match `docs/app-store/testflight-27.json`.
No Beta App Review submission exists. App Store 1.0 remains
PREPARE_FOR_SUBMISSION with MANUAL release. All eight screenshot assets are
COMPLETE, including the new actual course/category Download controls. Saved draft
and beta descriptions, review notes and links match their local source. No App
Review or Beta App Review was requested. Final proofs:
`build/release-receipts/testflight-27-ready.json`,
`build/release-receipts/manual27-screenshots.json` and
`build/release-receipts/manual27-metadata.json`.

## Senior ML and AI research Labs — 7 November 2026

Added 16 CPU PyTorch Labs and two eight-lesson courses: robust ML engineering
and alignment engineering. Four new topic groups cover focal gradients, SAM,
PCGrad, Group DRO, uncertainty, QAT, DPO/GRPO, contrastive learning, sparse MoE,
speculative sampling and grammar search. Four complete experiments train models,
select on validation data, evaluate separate test data and export/reload real
artifacts. Their deterministic local datasets are explicitly synthetic. Existing
six pretrained BERT projects and downloaded UCI data remain available.

The catalog now contains 136 Labs (65 ML, 48 AI), 19 topics and 40 PyTorch Labs;
446 path lessons plus 100 interview tasks; 138 advanced lessons and 34 integration
projects. All 104 lesson/Lab links are reciprocal. Explicit entire-course and
entire-category downloads include every dependency. Create/Open/Run starts no
download. New authoring metadata and generation instructions live in
`scripts/research-content/README.md`.

Native guarded execution passes all 546 solutions, 138 advanced starters,
603 independent reading programs, every Lab answer/starter, all 183 PyTorch
contracts, six complete pretrained projects and the four new full CLI projects
(120/140/100/120 optimizer steps). External DNS and connections are blocked and
the guard checks for attempted access. Full new projects produce real model bytes
and reload into fresh models. Receipts: `research28-native-readings.json`,
`research28-full-training-offline.json` and `research28-pretrained-full-offline.json`
under `build/release-receipts/`. The initial broad bundle contains one obsolete
587-versus-603 count assertion; the corrected 603-program native rerun passes.

Actual public native installation passes: the app downloads all six new content
packs and three shared runtime packs into a fresh store, verifies the complete
selection and checks all 16 lessons against Lab source bytes. Test:
`ContentDownloadTests.testSeniorResearchSelectionsFetchEveryPublishedCourseTopicAndDependency`
in `build/research28-public-native.xcresult`. That bundle also retains two
superseded UI test geometry failures. Final padding-tap, senior DPO/LoRA execution,
lesson navigation and topic/search reruns all pass in
`build/research28-ui-final.xcresult`; whole-course/category/project download UI
tests pass in `build/research28-final-native.xcresult`. Tests now reveal exact
padding coordinates above the floating tab bar before tapping.

The site is live; 92 web tests, TypeScript, 743 generated pages, 226 public routes,
104 link pairs and public smoke checks pass. Desktop/mobile browser search and
navigation pass without overflow or browser errors. All 63 published payloads
(43,593,736 bytes) match the signed catalog SHA-256 inventory. Release and integrity
receipts are `research28-site-release.json`, `research28-public-integrity.json`
and `research28-browser.json` under `build/release-receipts/`.

Release 0.1.0 (28) archives, exports and uploads successfully. Its 83,492,655-byte
IPA contains 38 course previews, 43 matching runtime files, six local project
recipes and 21 signed backend links; complete lessons, Lab Python files, optional
API trees, datasets and weights remain downloadable. Archive proof:
`build/release-receipts/testflight-28-archive-source.json`.
Apple completed processing with no errors. TestFlight 0.1.0 (28) is VALID and
IN_BETA_TESTING for the existing internal group, verified at
2026-11-07T01:30:51.686Z. The group has one tester and access to all builds. English
and Russian notes exactly match `docs/app-store/testflight-28.json`.
No Beta App Review submission exists. App Store 1.0 remains PREPARE_FOR_SUBMISSION
with MANUAL release; neither App Review nor Beta App Review was requested.
Readiness proof: `build/release-receipts/testflight-28-ready.json`.

All eight screenshot assets are COMPLETE in the correct order. Updated captures
show the 136-Lab catalog with an explicit whole-category Download control and a
real DPO/LoRA training curve, held-out metrics, artifact size and exact reload.
The final two UI capture/navigation tests also pass in
`build/research28-ui-screens.xcresult`. Draft/beta descriptions, review notes and
marketing/support links match the authored metadata. Final receipts:
`build/release-receipts/research28-screenshots.json` and
`build/release-receipts/research28-metadata.json`.

## Gestures and modal windows — 7 November 2026

The file drawer's invisible 22-point edge view intercepted taps on controls near
the edge, including Back and the landscape Output button. Edge drags now run on
the workspace container without a hit-testing overlay. Both directions, outside
taps, the swipe preference and mostly vertical drags are checked. File-list
scrolling can coexist with the close gesture. Landscape controls have full
44-point targets in a wider rail and report their selected state.

Downloads opens as a modal form from all four tabs and the project menu. Done
stays available through Project downloads → All downloads, and the form also
dismisses by swiping down. Its close action updates the owning presentation state
directly: an initial active-transfer regression found that Done could leave the
window open after Pause/Resume. The corrected single-tap close, ongoing download,
reopening and final offline readiness all pass. Offline-library headings remain
visible when all three selections show Available offline.

Download removal, project/file deletion, Lab reset, database row deletion and
ending/leaving a room now use centered confirmations with Cancel. Destructive
project/file actions capture their target before presentation state clears.
Project-link sharing uses a modal with Done, replacing the arbitrary UIKit
popover anchor; tests open and dismiss the system sharing UI without sending.

The iPad sidebar keeps its identity across portrait/landscape changes, and layout
classification uses the window size when the keyboard reduces the visible area.
This fixes the focused New file form disappearing. Creating a file, rotating
with its input focused, returning to portrait, canceling deletion and then deleting
only that test file pass on both devices.

Native simulator verification passes all 16 interaction scenarios on iPhone and
11 on iPad, including edge-back navigation, left/right Lab filters, answers,
editor panels, project creation/cancellation and destructive confirmations.
Final modal changes also pass four targeted cases on each device and the active
transfer case. Three native content tests, seven button-padding tests and both
course/category download tests pass. The initial regression bundle retains the
superseded transfer-close failure; its targeted rerun is green. Earlier iPad Lab
tests required installing their offline fixtures; the catalog preparation gate
downloaded and verified all 63 packs before those reruns. No physical-device run
is claimed. Summary: `build/release-receipts/interaction29-qa.json`.

Proof bundles: `build/interaction29-final-phone.xcresult`,
`build/interaction29-final-pad.xcresult`,
`build/interaction29-owner-phone.xcresult`,
`build/interaction29-owner-pad.xcresult` and
`build/interaction29-owner-transfer.xcresult`. Native captures under
`build/verification/` show the centered Downloads form/removal alert, system
sharing modal and landscape controls. The Python runtime and curriculum are
unchanged; the same 63-pack catalog pins all downloaded content. Guarded tests
confirm that Create/Open/Run starts no download and package removal preserves
project code and lesson drafts.

Release 0.1.0 (29) archives and exports successfully. Its 83,527,184-byte IPA
contains 38 course previews, 43 matching runtime files, six local project recipes
and 21 signed native backend links. Full lesson bodies, Lab source, optional APIs,
datasets and weights remain downloadable. Catalog hash remains
`b29787e5e05d7aa54a965695c7c59fb5b920b121174c5bce53321d12ef0bc191`.
Archive/source proof: `build/release-receipts/testflight-29-archive-source.json`.
Apple processing completed. At 2026-11-07 09:14:42 UTC, build 29 is `VALID`
and `IN_BETA_TESTING`, available to the existing internal group (one tester,
all-build access). Both en-US and ru release notes exactly match
`docs/app-store/testflight-29.json`. No Beta App Review submission exists;
App Store 1.0 remains `PREPARE_FOR_SUBMISSION` with manual release. Final proof:
`build/release-receipts/testflight-29-ready.json`.

## Editor and terminal keyboards — 7 November 2026

The reported editor strip is reproduced with the software keyboard open: the
Tab key grew to 1,254.7 points, placing the colon beyond the screen. The keyboard
strip now uses bounded key widths, 44-point targets and explicit scroll layout,
with a fixed Hide keyboard button. Tab, punctuation and scrolled symbols insert
into the actual editor. English and Ukrainian layouts, hiding/reopening and
portrait/landscape are verified. The initial three regression cases all fail on
the previous implementation; screenshots and the accessibility hierarchy are in
`build/verification/keyboard30-baseline/`.

The terminal now owns a separate native accessory with shell punctuation,
cursor left/right, previous/next command, Ctrl-C and a fixed Hide terminal
keyboard button. Its prompt inserts at the cursor and disables smart quotes and
dashes. Executing a Python command, recalling history and stopping a running
command pass through the real runtime. Its command chips remain available.
Prompt text/history/controller belong to the workspace, so layout replacement
cannot discard an unfinished command. The focused editor selection or terminal
responder is restored after a layout change; intentional dismissal and panel
changes do not reopen the keyboard.

The file drawer no longer disables edge swipes while a keyboard is visible.
Opening it dismisses the active responder, including the terminal. Both chosen
edges, outside taps, vertical scrolling, landscape controls and the Back
button's padding pass. Landscape and laptop Hide actions dismiss the active
workspace keyboard rather than only the editor.

Final simulator suites pass 10/10 cases on iPhone and 4/4 on iPad, with no skips
or failures. They include three editor/terminal round trips, portrait/landscape
with focused input, actual symbol insertion and command execution. Earlier
partial runs exposed the rotation issue and incorrect keyboard-test selection;
they are superseded by the complete final bundles. Low disk space interrupted
installation/result writing during another run; generated local artifacts and
dedicated simulator caches were cleared before the final successful run.
No physical-device test is claimed. Proof:
`build/release-receipts/keyboard30-qa.json`,
`build/keyboard30-final-phone.xcresult` and
`build/keyboard30-final-pad.xcresult`. Current native captures are under
`build/verification/keyboard30-final-{phone,pad}/`.

Release 0.1.0 (30) archives and exports successfully. All 460 recorded source
hashes still match the build's inputs. Its 83,556,070-byte IPA retains the same
63-pack catalog, 38 previews, 43 runtime files, 21 signed backend links and six local recipes.
Full courses, Lab Python source, optional APIs, datasets and model weights remain
downloadable. Runtime/curriculum and website content are unchanged. Archive
proof: `build/release-receipts/testflight-30-archive-source.json`.
Apple processing completed: build 30 became `VALID` at 2026-11-07 10:25:05 UTC.
Final verification at 10:41:56 UTC confirms `IN_BETA_TESTING`, the existing
internal group with one tester and all-build access, and exact en-US/ru notes.
No Beta App Review submission exists. App Store 1.0 remains
`PREPARE_FOR_SUBMISSION` with manual release; neither review was requested.
Readiness proof: `build/release-receipts/testflight-30-ready.json`.

## Terminal tabs, Learn and Labs redesign, release 1.0 — 11 November 2026

`python manage.py test` failed in the terminal with `python: fileno`: Django's test
runner hands `faulthandler` `sys.stderr.fileno()`, and Pythilo's output is a stream into
the app. The terminal now adds `--no-faulthandler` to `test`, as it already adds
`--noreload` to `runserver`. The Django template gained three tests (list, create,
blank note). `manage.py test` and `django-admin test --settings …` both report
`Ran 3 tests … OK`.

The terminal has tabs. Each tab keeps its own folder, history, prompt and output, and
shows whether it is idle, running or serving. Commands run at the same time: the C host
gained three job lanes beside Python's main thread, each with its own stdin pipe and
Stop. A tab's command runs on the main thread when it is free and on a lane otherwise.
Typing into a busy tab runs the command in another tab instead of stopping the server.
All lanes share one interpreter, so the runtime now keeps per-lane output (stdout@N),
input, shell redirects and pipes (`streams.redirect`, so one tab's `| grep` never catches
another tab's server log), exit handlers, leftover-thread reports and signal handlers
(a lane's `signal.signal`, as unittest's `installHandler` does, is kept for that lane).
A ledger notes which lane imported each module; while another lane still runs, a job
that ends forgets only its own modules, so edited project files and pytest tests are
read again while the server keeps the modules it loaded. The last job to end resets
the interpreter as before, under one lock. Lane threads stop `sleep` and `input()` at
once; a blocking native call or socket read ends only when it returns, and the lane
says so after the same escalation as the main thread.

On the iPhone the running server shows as a one-line strip under the tabs, so the tabs
stay reachable; the iPad keeps the floating banner. stderr is no longer red throughout:
progress lines from Django, unittest and logging use the normal ink, and lines that
report an error stay red. A migrate in any tab clears the "unapplied migrations" warning.

Learn groups the 37 courses into five tracks with filter chips, shows overall progress,
moves Interview practice up, and searches every lesson and course by name. Labs has a
compact header with three facts, icon filters, topic cards with an icon, a preview of
their Labs and an offline badge, and compact download controls; a finished download is
a status, not a greyed-out button. After a lesson's checks pass, the results show
"Lesson complete" at the top and a pinned **Next** (or **Course complete**) at the bottom
at every sheet height; the lesson bar keeps **Next lesson** after the sheet closes.
Settings has an About section and page: version and build, contents, website, guide,
Labs in the browser, blog, source, support, email, bug reports, rating, sharing,
privacy policy, terms, acceptable use and licences. Every linked page answered 200.

Verification on the iOS Simulator (iPhone 17 Pro and iPad, iOS 26.5, Xcode 27.2):
all 43 RuntimeGateTests and the template, web-template and two terminal-tab gates pass
(`build/redesign31-gates.xcresult`, `build/redesign31-gates2.xcresult`). One gate first
failed because the new tab test left a daemon thread running into the next test; the
test now stops it, and the rerun passes. The iPhone UI suites ran 46 cases: 44 passed
at once; two failed on project files changed by earlier keyboard tests (a typed `:` in
`manage.py` and `main.py`) and on Django 6.1's "Starting WSGI development server" text.
`-freshTemplate YES` now recreates such a project, and both pass on rerun
(`build/redesign31-ui-phone.xcresult`, `build/redesign31-ui-rerun.xcresult`,
`build/redesign31-ui-rerun2.xcresult`). No physical-device run is claimed.

The iPad run found a real defect that predates this release: PyTorch did not import
on an iPad. torch for iOS skips its desktop-only `libtorch_global_deps` and shared-memory
manager when `platform.system()` is "iOS", and CPython reports "iPadOS" there, so torch
tried to `dlopen` a library that is not shipped. The downloaded torch pack is pinned, so
the runtime answers "iOS" to code in the `torch` package on an iPad only; every other
caller still sees "iPadOS". The iPad UI run had 21 cases: 17 passed at once; the two
PyTorch Labs failed on that defect, and two search steps failed because iPadOS keeps a
`.searchable` field behind a toolbar button (the tests now open it). All four pass on
rerun (`build/redesign31-ui-pad.xcresult`, `build/redesign31-ui-pad-rerun.xcresult`,
`build/redesign31-ui-pad-torch.xcresult`). The torch fix belongs in torch-ios as a
`sys.platform == "ios"` check for its next pack.

Store screenshots 02, 03 and 04 are new captures of terminal tabs with Django tests
beside the server, Learn and Labs, in the same frames as before; the other five are
unchanged. The App Store description now says 19 topics (it said 15) and mentions tabs.
The version is 1.0, matching the App Store draft.

Release 1.0 (31) archives from `fdcbcb2` with Xcode 27.2 / SDK 27.2 and exports an
83,994,102-byte IPA signed by Apple Distribution; it contains the lanes runtime, the
iPadOS torch fix and the Django test adaptation. Apple processing completed: build 31 is
`VALID` and `IN_BETA_TESTING` for the internal group (one tester), and the en-US and ru
notes match `docs/app-store/testflight-31.json`. App Store 1.0 now selects build 31 and
was submitted for App Review at 2026-11-11T02:45:07Z: version and submission are
`WAITING_FOR_REVIEW`, release **MANUAL**. Availability is all 175 territories plus new
ones, price US$9.99, App Privacy "Data Not Collected" and content rights "uses
third-party content", as for Crabrix. Description, keywords, promotional text, URLs and
reviewer notes match their readback; all eight screenshots are `COMPLETE` and match the
repository by checksum. No physical-device run is claimed. Receipt:
`docs/app-store/release-1.0-build31.json`.

## Labs download controls, build 32 and site guide — 11 November 2026

On narrower iPhones a Labs topic card put its description, the Download button and
"N of M ready" in one row, so the button and the status were drawn over each other.
The description now has its own line, and `CompactSelectionControl` moves its status
under the button when the two do not fit side by side (`ViewThatFits`). The section
header already stacked. `LabsCardLayoutTests` compares the frames before, during and
after a partial download; it passes on an iPhone SE (3rd generation, 375 pt) from a
fresh install, on the iPhone 17 Pro and on the iPad, where PyTorch is already present
and the topic pack finishes at once. On iPhone 17 Pro the Labs, Downloads, hit-target
and release-31 suites pass (18 cases); on iPad the Labs and Downloads suites pass
(8 cases). The course download test now taps the lesson's Code tab only on a phone.
Screenshots: `build/labs-fix32-shots/`.

Release 1.0 (32) archives from `e174ca1` with Xcode 27.2 / SDK 27.2 and exports an
84,002,124-byte IPA signed by Apple Distribution. Apple processing completed: build 32
is `VALID` and `IN_BETA_TESTING` for the internal group, with the en-US and ru notes
of `docs/app-store/testflight-32.json`. Build 31's review submission was still
waiting, so it was withdrawn, version 1.0 now selects build 32, and a new submission
(`9cf6f749-794b-4dcd-8389-8706d329a97e`) is `WAITING_FOR_REVIEW` since
2026-11-11T06:43:09Z, release **MANUAL**. Metadata, all eight screenshots, 175
territories, price, privacy and content rights read back unchanged. No physical-device
run is claimed. Receipt: `docs/app-store/release-1.0-build32.json`.

The website guide for terminal tabs, Settings › About and servers in tabs is live on
pythilo.com (see `site/DEPLOY.md`).
