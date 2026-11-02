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

This repository has no CI or CD. Builds, tests and releases are run by hand.

## Layout

| Path | What it is |
| --- | --- |
| `Pythilo/Runtime` | The C host and Swift session around CPython |
| `Pythilo/PythonRuntime/pythilo_runtime` | The Python side: runner, shell, debugger, pip, analysis, notebooks, lessons, labs |
| `Pythilo/Projects` | Project folders, the open workspace, Git commands |
| `Pythilo/MCP` | The MCP server the app hosts over Streamable HTTP |
| `Pythilo/UI/Workspace` | The IDE, with one arrangement per screen shape |
| `Pythilo/Resources/Courses` | Lessons and interview tasks |
| `Vendor/PythiloGitCore` | libgit2 and its Swift wrapper |
| `docs/STATUS.md` | What works, what was checked, what is missing |

The screens are designed on the [design canvas](https://claude.ai/artifact/1Nh2dSBeFktQYok5CT3Qeb).
