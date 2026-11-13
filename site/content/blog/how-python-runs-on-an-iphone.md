---
title: "How real Python runs on an iPhone"
description: "iOS allows one process, only signed code, no JIT and no background servers. Python's tools assume the opposite. This is how Pythilo runs CPython 3.14, a terminal, pip, Django and PyTorch inside those rules, and where the rules still win."
date: 2026-11-13
author: Pythilo
cover: /blog/how-python-runs-on-an-iphone/cover.jpg
coverAlt: "Abstract illustration: a phone drawn as separate glass layers floating above a glowing chip, with a blue ribbon and a yellow ribbon rising through all the layers on a dark navy background."
tags: Python, iOS, Runtime, Pythilo
---

An iPhone has a faster processor than many laptops, plenty of memory and a full Unix kernel underneath. On paper, nothing stops it from running Python the way a laptop does. In practice, iOS sets four rules for apps, and almost everything in the Python world quietly assumes the opposite of each one:

1. An app is one process. It cannot start another program.
2. Only code that was signed into the app may run as machine code.
3. An app cannot generate machine code while it runs, so there is no JIT.
4. An app that goes to the background is suspended.

Pythilo runs CPython 3.14 inside those rules, with a terminal, pip, pytest, Git, Django and PyTorch. This post explains how each rule is handled, with the real mechanism where there is one, and where the rule still wins. If you write Python but have never looked inside an iOS app, this is also a tour of the assumptions your tools make about the machine under them.

## The interpreter is a library inside the app

On a computer, Python is a program: you type `python` and the shell starts it. On iOS there is no shell to start it from, so the interpreter has to be a library that the app loads into its own process.

That became an officially supported arrangement with PEP 730, which made iOS a supported platform of CPython from Python 3.13. Pythilo embeds CPython 3.14.10, built from BeeWare's iOS support package, with its hash pinned in the build. A small C host inside the app starts the interpreter once, and everything you run afterwards is a job handed to it.

This is real CPython, not a reimplementation and not WebAssembly. You can ask it where it is:

```python
import platform
import sys

print(sys.platform)        # ios
print(platform.system())   # iOS on an iPhone, iPadOS on an iPad
print(sys.version_info[:3])
```

That second line matters more than it looks, and it comes back later in this post.

Because the interpreter lives in the app's process, your program has what the app has: real files in the project's folder, sockets, threads, and the network. It also means all projects share one Python process. Pythilo resets it between runs by clearing modules, paths and environment variables, but that is tidying, not a security boundary, and the app says so.

It is worth comparing with the other way to run Python where you cannot install it, which is the one this website uses. The lessons on pythilo.com run on Pyodide, CPython compiled to WebAssembly, inside your browser's sandbox. That is a fine fit for lessons, but there are no real sockets, so a Django server cannot listen, and no PyTorch. The app exists because some things need the real interpreter on the real operating system.

## One process, so the terminal is built in

Rule one removes more than you would think. No `fork`, no `exec`, no `posix_spawn`. So there is no `subprocess`, no `multiprocessing` and no `os.system`. There is no bash to run, no `git` binary, no `node`.

Yet a terminal is the natural way to drive a Python project. So Pythilo's terminal is a small bash written in Python and built into the app. It reads a command line the way bash does, with quotes, variables, `~`, globs, pipes, `&&`, `||`, `;` and redirects, and then runs each command as a function against the real file system. A pipe passes text from one command to the next in memory.

```sh
grep -rn "TODO" . | sort | uniq -c
ls *.py | xargs wc -l
pytest -q && git commit -m "Tests pass"
```

More than sixty commands are built in, from `ls`, `find` and `sed` to `curl`, `tar` and `sha256sum`. A command or an option that is not built in says so. It is never silently ignored, because a terminal that pretends is worse than one that refuses.

The programs a Python developer expects are handled one by one:

- **python** is the interpreter already running. `python file.py`, `python -m module`, `python -c` and the interactive prompt all work.
- **pip** is the real pip, imported and run inside this process against the project's own package folder.
- **pytest** runs in the same way, with your arguments.
- **git** is libgit2, compiled into the app behind a Swift wrapper. The project has a genuine `.git` folder that any other Git can read.
- **npm** is Pythilo's own: it resolves versions from the npm registry, checks each package's integrity hash and writes `node_modules`. It does not run install scripts, because they would need Node.
- **sqlite3** opens a database with Python's own `sqlite3` module.

Some features of familiar tools turn out to be a second process in disguise, and those are refused with a reason. Django's autoreloader starts a child process to watch your files, so `runserver` runs with `--noreload` added for you. Flask's reloader, `uvicorn --reload` and `uvicorn --workers` are refused. `manage.py dbshell` would start an external database program. PyTorch's `DataLoader` workers are processes too, so `num_workers` stays at 0.

## Four programs, one interpreter

A web framework wants two things at once: the server running, and a prompt for `migrate`, tests and Git. On a computer those are separate processes. Here they have to be threads in one interpreter.

The C host has four lanes. Lane 0 is Python's main thread, and three more lanes each run their own jobs on their own thread. A terminal tab's command runs on the main thread when it is free and on another lane otherwise, which is why up to four programs run at once and why typing into a busy tab runs the command in another tab.

![Four parallel lines of light, two blue and two yellow, running side by side inside one rounded channel and starting from a single glowing point.](/blog/how-python-runs-on-an-iphone/lanes.webp "Four lanes share one interpreter. Each has its own input, output and Stop.")

Threads in one interpreter share everything, and most of the work was in deciding what must not be shared:

- **Output.** There is one `sys.stdout`. Each write carries its lane, so every tab shows only its own program.
- **Pipes and redirects.** A shell redirect is kept per lane instead of replacing `sys.stdout`. Otherwise one tab's `| grep` would catch another tab's server log.
- **Input.** Each lane has its own stdin pipe, so `input()` in one tab waits for that tab.
- **Signal and exit handlers.** unittest can install its own SIGINT handler for a test run. On a lane, that handler is kept for that lane only.
- **Modules.** A ledger notes which lane imported each module. When a job ends while another still runs, it forgets only its own modules. That is how `pytest` in tab two reads your edited files again while the server in tab one keeps the modules it loaded. The last job to end resets the interpreter.

Here is what that looks like from the outside, with the server in the first tab:

```sh
python manage.py runserver
```

and in a second tab, while the site keeps answering:

```sh
python manage.py test
curl http://127.0.0.1:8000/
```

The interpreter is the standard build with a global interpreter lock, so the lanes take turns running Python code. For a development server that mostly waits on sockets, beside a test run, that is exactly enough. It is not a way to use four cores for arithmetic.

One consequence carries over from the missing reloader: a running server keeps the modules it imported, such as your Django models, until you stop and start it.

## Stop, when you cannot kill the process

On a computer, Ctrl-C sends SIGINT, and if the program ignores it you kill the process. Inside an app, killing the process means closing the app. So Stop has to work from the inside, and it has to be honest when it cannot.

For the main thread, the host delivers a real SIGINT to it. Python turns that into `KeyboardInterrupt`, and it wakes a blocked `sleep`, a socket or a read, just as it does in a desktop terminal. For the other lanes, the interrupt is raised inside that lane's thread, which also wakes a `sleep` or an `input()`. A blocking socket read on a lane ends only when it returns.

Code can catch one `KeyboardInterrupt`, so Stop repeats. If Python still has not stopped after several tries, Pythilo stops pretending and says "This run cannot be stopped from here". That happens in one situation: compiled code that never returns to the interpreter. Your files are already saved, so closing the app from the app switcher loses nothing.

Threads that your program leaves running stay until the app closes. Python has no way to end a thread from outside, so the Output panel names them instead of hiding them.

## Only signed code runs

Rule two decides what pip can do. An iPhone will only execute machine code that Apple's signature covers, and that signature is made when the app is built. A file that arrives later can be read as data, and Python source is data, but a compiled extension module that arrives later cannot be loaded.

So pip works, inside a clear line. It installs pure-Python wheels from PyPI into the project's `.pythilo/site-packages` folder, which comes first on the path when the project runs. Pythilo calls pip with `--only-binary :all:`, so it never tries to compile anything. A package that needs compiled code fails with pip's own message, and nothing is changed.

Compiled packages have to ship inside the app. iOS also insists that each piece of loadable code is a framework, so the build wraps every extension module as its own framework. For Pythilo that means:

- **NumPy**, compiled for iOS.
- **PyTorch 2.15**, built from source by the [torch-ios](https://github.com/sergii-ziborov/torch-ios) project, with matrix maths through Apple's Accelerate.
- **pydantic-core**, the Rust heart of Pydantic, which FastAPI needs. Nobody publishes an iOS build of it, so the project compiles it from source with Rust's iOS targets.

This is also the honest reason for the most common question, "where is pandas?". Nobody publishes iOS builds of pandas, Matplotlib or SciPy for Python 3.14 yet.

Downloads follow the same line. The app can download a course, a Lab topic or the Python files of a package, and each archive is checked against a catalog pinned inside the signed app before it is installed. The compiled half of a package never comes by download. It is already in the app, signed.

### The iPad that was not iOS

Here is a bug that only this platform can produce. PyTorch's iOS build skips a few desktop-only libraries when `platform.system()` returns `"iOS"`. On an iPad, CPython reports `"iPadOS"`. So on an iPad, torch took the desktop path, tried to load a library that is not shipped, and failed to import. The same build imported perfectly on an iPhone.

The fix in Pythilo is narrow: on an iPad, code inside the `torch` package is told `"iOS"`, and every other caller still sees `"iPadOS"`. The proper fix belongs in the library, as a check of `sys.platform == "ios"`, which is the same on both devices. If you write a library that might one day run on Apple's mobile platforms, that is the comparison to use.

## No JIT, and where the speed comes from

Rule three says an app cannot create executable memory. CPython has an experimental just-in-time compiler in recent versions. It cannot be used on iOS, so Pythilo runs the ordinary interpreter. For teaching, scripting and web work, that is the same Python speed you get from a default install anywhere else.

The heavy work is not done by the interpreter anyway. NumPy and PyTorch spend their time in compiled code, and on iOS that code calls Accelerate, Apple's tuned linear algebra. That is how the PyTorch template trains a small network on the device, on the CPU. The GPU is a different matter: PyTorch's Metal backend is not available here, and `torch.compile` would have to build and load new machine code at run time, which rules two and three forbid. To reach the Neural Engine, Pythilo exposes Core ML to Python as `pythilo.coreml`, where the operating system runs the model.

There is one place on iOS where generated machine code is allowed: the system's web engine. esbuild, which bundles JavaScript for the React template, runs there, as WebAssembly in a hidden web view.

## Servers, sockets and the preview

A Django development server is just a program that listens on a socket, and sockets work. The interesting question is how the app knows a server started, so that it can offer **Open site**. It does not read the output looking for "Starting development server". Django's `runserver`, Flask's werkzeug and Uvicorn's asyncio loop all end in the same call, `socket.listen()`, so the runtime wraps that one function and tells the app the host, the port and the lane. Any program that listens gets the banner, including one you wrote yourself with `http.server`.

Output has its own surprise. On a computer, stdout is file descriptor 1. Here it is a Python object wired to a terminal tab, with no file descriptor behind it. Almost nothing notices, but Django's test runner turns on `faulthandler`, which wants a real descriptor to write to. The terminal adds `--no-faulthandler` to `manage.py test` for that reason.

Then rule four. iOS suspends an app soon after it leaves the screen, and a suspended process does not answer requests. A server runs while Pythilo is open, and it is reachable only from the device itself. To put a project in front of someone else, there are shared rooms, which do not depend on your server at all.

## What the rules still forbid

Engineering can go around a rule only so far. These stay out of reach for any app:

- Docker, database servers, and anything else that is a separate program.
- Node itself, and so Vite, webpack and the tools built on them.
- Installing a compiled package that the app does not bundle.
- Interrupting compiled code that never returns.
- Keeping a server alive in the background.

The guide lists what works and what does not on [What runs on iOS](/guide/limits/), and the pages on the [terminal](/guide/terminal/), [packages](/guide/packages/), [running and debugging](/guide/run-and-debug/) and [web servers](/guide/web-servers/) describe each part as you use it.

## Why go to this trouble

Because the result is a Python that is yours. It needs no setup, it works on a train, and nothing you write leaves the device unless you push it or share it. A lesson's check, a failing test, a Django view and a training loop all run on the same interpreter, a few centimetres from your thumb.

The rules cost something, and this post has tried to say exactly what. Within them, a phone turns out to be a very capable Python computer. [Pythilo is on the App Store](https://apps.apple.com/app/id6829637526), and [the lessons](/learn/) are free to try in your browser first.
