---
title: "Pythilo 1.0 is on the App Store"
description: "Pythilo 1.0 is out for iPhone and iPad: CPython 3.14 on the device, a terminal with tabs, Django and PyTorch, 478 lessons and 136 Labs, for US$9.99 paid once. Here is what is in it, what is not, and how to start."
date: 2026-11-12
author: Pythilo
cover: /blog/pythilo-1-0-on-the-app-store/cover.jpg
coverAlt: "Abstract illustration: a phone on a dark navy background, with a blue ribbon and a yellow ribbon rising from its screen between glass tiles that show a terminal prompt, brackets, a graph of nodes and a bar chart."
tags: Pythilo, Release, iPhone, iPad
---

Pythilo 1.0 went on sale on the App Store on 12 November 2026, in 175 countries and regions. It runs on iPhone and iPad with iOS 18 or later, and it costs US$9.99, paid once. There is no subscription, no in-app purchase and no account.

Pythilo is three things in one app: a Python IDE, a set of courses, and a collection of Labs that trace your own code while it runs. All three sit on the same foundation, which is a real CPython 3.14 interpreter inside the app. Your code does not go to a server and it does not run in a web view. It runs on the phone in your hand, and it keeps running on a plane.

This post goes through what 1.0 contains, what it leaves out, and how to spend a first afternoon with it. If you only want the link: [Pythilo on the App Store](https://apps.apple.com/app/id6829637526).

## Real Python, on the device

The interpreter is CPython 3.14.10, built from BeeWare's iOS support package and embedded in the app. That one decision shapes everything else, so it is worth saying what it means in practice.

`input()` works, and waits for you to type. Files are real files in a real folder, which you can also see in the Files app. A traceback points at your file and your line. The standard library is all there. A program can open sockets, start threads and run an asyncio loop, because it is an ordinary Python program in an ordinary interpreter.

Here is a first program worth running, because the second line prints something you will not see on a laptop:

```python
import platform
import sys

print(sys.version.split()[0])
print(platform.system())
```

Stop works too, which is harder than it sounds inside an app. It interrupts an endless loop, a `time.sleep`, a waiting `input()`, a blocking socket and asyncio code, and it keeps asking if your code catches the first interrupt.

Once a course, a Lab topic or a package is downloaded, running it needs no network at all. The interpreter and every compiled library are already in the app.

## A workspace, not a scratchpad

Plenty of apps can run twenty lines of Python. Pythilo is built for projects, the kind with folders, tests and a Git history.

- **Projects with many files.** A drawer shows nested folders, with quick search. Every project is an ordinary folder. You can search your projects, sort them, and group them into categories.
- **An editor made for touch.** Syntax colours, completion from Jedi that knows your own modules, and a problems list from pyflakes that flags mistakes as you type.
- **A terminal with tabs.** iOS does not let an app start other programs, so the terminal is a small bash built into Pythilo. It understands quotes, variables, globs, pipes and redirects, and it has the commands you reach for: `ls`, `grep`, `sed`, `find`, `curl`, `tar` and many more, plus `python`, `pip`, `pytest`, `sqlite3`, `git` and `npm`.
- **A debugger.** Tap a line number to set a breakpoint. When the program pauses you get the call stack, each variable with its value and type, and a field to evaluate an expression in the selected frame. Breakpoints also stop inside threads, inside web request handlers and inside async code.
- **Tests.** pytest runs as it does on a computer, with your arguments.
- **Git, for real.** There is a genuine `.git` folder in the project. Commit, branch, diff, merge with conflict markers and `--abort`, rebase, and clone over HTTPS.
- **GitHub in Clone.** Search GitHub by name, owner or language and see stars and forks before you clone. If you save a GitHub account, which is a personal access token kept in the Keychain, your own repositories are listed too, private ones included.
- **Notebooks and SQLite.** Ordinary `.ipynb` files open and save, with cells that share one namespace. A SQLite browser shows the tables in a project's database.

The [guide](/guide/) has a page for each of these, with screenshots. [Getting started](/guide/getting-started/) is the place to begin.

## A web server in your pocket

This is the part people do not expect. Django, Flask, FastAPI with Pydantic, and Starlette on Uvicorn all run on the phone. You start them the way you would on a computer:

```sh
python manage.py runserver
```

Pythilo notices when a program starts listening on a port, whatever the framework. It shows a banner, "Django is running", with the address and an **Open site** button. The site opens in a preview with an address bar, so you can type `/admin/` and go there. If Django reports migrations that are not applied, the banner offers **Migrate & restart**.

The terminal's tabs run at the same time. Keep `runserver` going in the first tab, and in a second one run the tests, apply a migration or make a commit while the site keeps answering:

```sh
python manage.py test
python manage.py makemigrations notes
git commit -am "Add a due date to notes"
```

Up to four programs run at once. If you type a command into a tab that is busy, Pythilo runs it in another tab and says so, so the terminal is never blocked by your own server.

There is a frontend story as well. Node cannot run on iOS, but Pythilo has its own npm, which installs packages from the npm registry and checks each one's integrity, and esbuild, which bundles them inside the app. The React and FastAPI template installs, builds and serves its site on the device.

Two limits are worth knowing now. Autoreloaders need a second process, which iOS does not allow, so after a change you stop the server and run it again. And iOS pauses apps in the background, so a server runs while Pythilo is open. [Web servers and the preview](/guide/web-servers/) has the details.

## Machine learning that trains on the phone

NumPy is here. So is PyTorch 2.15, built for iOS from source by the [torch-ios](https://github.com/sergii-ziborov/torch-ios) project: the full library with autograd, running on the CPU with matrix maths through Apple's Accelerate. The PyTorch template trains a small network on the device and reaches 97% test accuracy. The machine learning courses use the same PyTorch, so their lessons train real networks offline.

For the Neural Engine there is `pythilo.coreml`, which runs a Core ML model from Python on the CPU, the GPU or the Neural Engine, times each one and checks that the results agree.

The largest projects fine-tune a real pretrained BERT model on the UCI sentiment dataset: full fine-tuning, LoRA adapters on the query and value matrices, domain transfer, exact resume from a checkpoint, and evaluation of the merged model. The dataset, tokenizer and weights download once and are shared between the six projects. Training and evaluation then run locally.

The honest limits: PyTorch uses the CPU only. There is no MPS backend and no `torch.compile`. And there is no pandas, Matplotlib or SciPy, because nobody publishes iOS builds of them for Python 3.14 yet.

## 478 lessons, checked by running your code

Learn holds 478 lessons in 38 courses, grouped into five tracks: Python, web and data, machine learning, AI, and algorithms. You can search every lesson by name.

![A path of blue and yellow stepping stones climbing across a dark navy background, beside a small tree of nodes, a row of rising bars and a grid with a traced route.](/blog/pythilo-1-0-on-the-app-store/learning-path.webp "Courses run from the first variable to algorithms, PyTorch and language models.")

The Python track starts from the first variable and goes through two 30-lesson courses, then clean code, testing, the tools around Python, architecture, and concurrency with async. Web and data covers Pydantic 2 in 20 lessons, FastAPI with HTTPX in 14, practical testing and file formats. The machine learning track includes the mathematics of neural networks and 30 lessons of machine learning with PyTorch. The AI track looks at language models from the inside: tokenizers, attention, decoding, retrieval and evaluation.

The newest course is **Algorithms and data structures**: 32 lessons from binary search, two pointers and sliding windows to heaps, tries, union-find, Dijkstra, dynamic programming, N-Queens and KMP. Each lesson links to the Lab that traces the same algorithm. You can read the same lessons [in the browser](/learn/algorithms/).

A lesson is short. You read a part, run its example, and then write code for a task. The task is checked by running your code on the device, and a failed check says what happened instead of just turning red:

> describe(3) returned None, expected 'int: 3'. Is a return missing?

When every check passes, the next lesson is pinned at the bottom of the results, one tap away. On a phone, reading and coding take turns on the whole screen. On an iPad they sit side by side.

For interview practice there are 100 tasks, 35 easy, 45 medium and 20 hard, with a timer, hints that reveal a little at a time, worked solutions and checks for the edge cases people forget.

## 136 Labs that trace your own code

A Lab is a workbench for one idea. You write the algorithm, tap Trace, and watch what your own code did, step by step. Correctness comes first, then measurements of time.

There are 136 Labs in 19 topics. A few examples give the flavour:

- **Sorting Bench** shows every read and write your sort makes, on four kinds of input.
- **Graph Explorer** runs your BFS, DFS or Dijkstra on a grid, a tree or a random graph. A depth-first search is judged as a valid depth-first order, not against one fixed answer.
- **Search & Hashing** lets you build a hash table and watch buckets fill and keys collide.
- **Dynamic Programming** counts how many calls a recursion repeats, and what a cache saves.

Sixty-five Labs are about machine learning and 48 about AI: train-only standardization, threshold selection, gradient checks, Adam, scaled dot-product attention, causal masks, beam search, BPE merging, KV caches, LoRA and more. Forty of them run real PyTorch on the device. Seventy-four of the Labs also run free in your browser, at [pythilo.com/labs](/labs/), with the same tracer and the same checks.

## Download what you use

Pythilo does not download anything behind your back. Creating, opening or running a project never starts a download. You choose **Download entire course**, **Download entire category** or **Download project packages**, and each choice brings everything it needs, so that what you downloaded runs offline.

The Downloads screen shows sizes and progress, and lets you pause, resume, cancel and remove. In Learn and Labs you can touch and hold a course or a topic to download it, remove it or hide it from the list. Removing a download keeps your project code, your lesson drafts and your progress.

Every archive is checked against a catalog pinned inside the signed app before it is installed. Compiled code never arrives by download: the native parts of NumPy, PyTorch and the rest stay inside the signed app, and only their Python files download separately.

## Work with someone else, or with an AI client

A **shared room** puts a project in front of another person's browser by link, with live edits and cursors. Rooms are end-to-end encrypted, so the relay that connects you only sees ciphertext. Code runs where someone asks it to run. If a guest wants to run something on your iPhone, you get a prompt and decide: deny, or run once. See [Rooms](/guide/rooms/).

An **AI client** on your computer, such as Claude, Codex or any other MCP client, can work on one project over your local network. Reading, editing, running, installing packages and committing are separate permissions that you grant one at a time. [Connect AI](/guide/connect-ai/) explains the setup.

## What 1.0 does not do

A list of limits is more useful before you pay than after, so here it is.

- **No pandas, Matplotlib or SciPy.** There are no iOS builds of them for Python 3.14.
- **PyTorch on the CPU only.** No GPU backend and no `torch.compile`.
- **No Node.** npm installs and esbuild builds, but tools that need Node itself, such as Vite or webpack, cannot run.
- **pip installs pure-Python packages.** A package with compiled code works only if Pythilo bundles it, because iOS runs only code that is signed into the app.
- **No subprocesses.** That rules out reloaders, `uvicorn --workers`, multiprocessing and Docker.
- **No Jupyter server.** Notebooks run on Pythilo's own kernel.
- **Servers pause in the background**, along with the app.
- **Git over HTTPS only**, without SSH, submodules or LFS.

The guide keeps this list current on [What runs on iOS](/guide/limits/). The repository's status file goes further and lists, item by item, what is done and how it was checked.

## How it was checked

Before a release, the app's own test suite runs inside the app, against the embedded interpreter, on the iOS Simulator. It runs the worked solution of every one of the 478 lessons and 100 interview tasks, and every Lab's answer and starter, so a lesson cannot ship with a check its own solution fails. The website's tests run the browser versions of the same solutions in Pyodide. Interface tests then drive the real screens on an iPhone and an iPad simulator: terminal tabs with a Django server beside its tests, downloads, search, GitHub and the Labs.

Each build went to TestFlight before it was offered for review. Build 34 is the one on the App Store.

## Price and privacy

Pythilo costs US$9.99 in the United States, and Apple shows the price in your currency before you pay. You pay once. Nothing inside the app is locked and nothing is sold inside it. One purchase covers your iPhone and your iPad. The [Pricing](/pricing/) page answers the usual questions, including refunds, which Apple handles.

There is no Pythilo account, no analytics and no advertising. Your projects stay on your device unless you push them somewhere or share a room. A GitHub account is optional, and its token is sent only to GitHub.

The website stays free: the same lessons run in your browser on Pyodide, next to the playground and the browser Labs. It is a fair way to see how the lessons read before buying the app.

## A first afternoon

If you have just installed Pythilo, this order works well.

1. Create a project from the **Django notes** or **FastAPI** template and tap Run. Open the site in the preview.
2. Tap + above the terminal for a second tab and run the template's tests while the server is still up.
3. Set a breakpoint in a view and start the project with Debug, from the Run button's menu. Open the page in the preview, and the debugger stops inside the request.
4. Open **Learn**, choose a track and download one course. Do the first lesson with its check.
5. Open **Labs**, download a topic, and trace a sort or a graph search you wrote yourself.
6. Commit the project, then open **Clone** and search GitHub for something you would like to read on the train.

If something does not work as it should, [Support](/support/) says how to reach us. Every message is read by the person who wrote the app.
