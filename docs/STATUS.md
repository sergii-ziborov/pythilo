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
| FastAPI | Not bundled. Needs an iOS build of `pydantic-core`, which nobody publishes |
| Notebooks: `.ipynb` round trip, shared namespace, rich output, stale marker | Checked at the model level. Native notebook, not Jupyter |
| Real Jupyter server and kernel | Not done |
| pandas and Matplotlib | Not bundled. No cp314 iOS wheels were found |

## Tools (sections 14 and 15)

| Item | State |
| --- | --- |
| Debugger: breakpoints, stepping, locals, evaluate, stop while paused | Checked in the runtime. Screen not driven by hand yet |
| Debugging threads, async code, web handlers and notebook cells | Not done |
| Git with libgit2 and a real `.git`: init, stage, commit, log, diff, branches, safe switch, HTTPS clone | Checked |
| Fetch, fast-forward pull, push, Keychain tokens | Written. Not run against a real remote |
| Merge, rebase, SSH, submodules, LFS | Not done, and refused rather than faked |
| Pyflakes problems and Jedi completion on their own thread | Problems checked. Completion not exercised |

## Learning (sections 16 and 17)

| Item | State |
| --- | --- |
| 36 lessons and 20 interview tasks | Every solution passes on the embedded interpreter |
| Sorting Bench: traces of the user's real code, measurements without the tracer | Checked |
| Graph, hashing and dynamic programming labs | Not done |

## MCP (section 18)

The plan's route was a relay and a room, as in `crabrix-sdk`. A relay needs hosting
and a domain, so the first version serves MCP from the app itself, over Streamable
HTTP on the local network, with a bearer token that ends when sharing stops. Read,
edit, run, packages, commit and push are separate grants, and writes check revisions.

Checked with a real HTTP client inside the tests: bearer token, handshake, tools,
stale-revision conflict, path escapes, approval and denial, push off by default.

Not done: rooms with other people, the website and browser playground, anything
reaching the app from outside the local network.

## Screens

Designed on the canvas linked from the README. Checked by screenshot on simulators:
vertical and horizontal iPhone, the Duo cover screen on the real simulator display.

Duo laptop, book and flat, and iPad landscape, were captured at their exact sizes
with debug launch arguments on an iPad simulator, because Device Hub cannot drive
the hinge here. The hinge reader itself has not been exercised. The sideways phone
with the camera on the right, the external keyboard pill with a real keyboard, and
the swipe gestures have not been driven by hand.

## Not started

- PyTorch and the Neural Engine (section 19, P0-F, P0-G)
- Website, Pyodide playground (section 18, P4)
- StoreKit purchase and App Review materials (section 4, P6)
