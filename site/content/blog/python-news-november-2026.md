---
title: "Python in November 2026: 3.15 ships, the JIT stalls, and the tools keep getting faster"
description: "Python 3.15 is out with lazy imports and frozendict, 3.14 is on its tenth bugfix, the JIT's future is uncertain, and uv, Ruff, ty and Pyrefly keep changing how Python projects are built. Here is what changed, with sources."
date: 2026-11-04
author: Pythilo
cover: /blog/python-news-november-2026/cover.webp
coverAlt: "Abstract illustration: a yellow ribbon and a blue ribbon twist around each other across a dark navy background, crossed by thin lines of light and surrounded by small translucent tiles of geometric shapes."
tags: Python, Releases, Tooling, Packaging
---

October is when Python ships, and October 2026 was a busy one. Python 3.15.0 came out on 9 October, a year and two days after 3.14.0. The 3.14 line kept getting bugfix releases, and is now on 3.14.10. Python 3.10 reached its end of life. Work on 3.16 started straight away. And in the middle of all that, the proposal meant to secure a future for CPython's experimental JIT compiler was withdrawn.

This post goes through what changed in the language, the interpreter, the packaging world and the tools most people use every day. Every version number and date below comes from an official source, listed at the end. Where something is still undecided, we say so rather than guess.

## Where the release lines stand

Python works on a yearly schedule. A new feature release arrives each October, gets about two years of bugfix releases, then three more years of security fixes. That rhythm makes it easy to describe the state of things in early November 2026:

- **Python 3.15** is the newest feature release. 3.15.0 came out on 9 October 2026, followed quickly by 3.15.1 on 21 October and 3.15.2 on 25 October. Hugo van Kemenade is the release manager, and PEP 790 puts its end of life in October 2031.
- **Python 3.14** is still in bugfix mode. Its latest release is 3.14.10, from the last week of October 2026, and PEP 745 plans 3.14.11 for 1 December 2026.
- **Python 3.11, 3.12 and 3.13** only get security fixes now.
- **Python 3.10** reached end of life on 1 October 2026. Its final release, 3.10.22, came out as source only, alongside 3.11.17, 3.12.15, 3.13.16 and 3.14.8. Python 3.9 went the same way on 31 October 2025.
- **Python 3.16** is under way. PEP 826 names Savannah Ostrowski as release manager. The first alpha came out on 13 October 2026, the first beta (and feature freeze) is planned for 4 May 2027, and the final release for 5 October 2027.

If you still run 3.10, you are now on an unsupported interpreter, and libraries are already moving on. PyTorch 2.15, for example, needs Python 3.11 or newer. Python 3.13 or 3.14 is a sensible target for a new project. Move to 3.15 once the libraries you depend on publish wheels for it.

## Python 3.14, one year on

Python 3.14.0 came out on 7 October 2025. It's worth a look back, because it is the release most people are moving to right now. It's also the interpreter we ship: the Pythilo app embeds CPython 3.14.10, built from BeeWare's iOS support package.

The headline features in the official "What's New in Python 3.14":

- **Deferred evaluation of annotations** (PEP 649 and PEP 749). Annotations are no longer evaluated when a function or class is defined, only when something asks for them. Forward references stop being a problem, and the new `annotationlib` module gives tools a supported way to read them.
- **Template strings** (PEP 750). A `t"..."` literal looks like an f-string but produces a `Template` object from the new `string.templatelib` module, not a string. Libraries can then escape or check the interpolated parts before building the final text, which is exactly what HTML and SQL need.
- **Multiple interpreters in the standard library** (PEP 734). The `concurrent.interpreters` module, together with `InterpreterPoolExecutor`, lets one process run several isolated interpreters, each with its own GIL.
- **Zstandard compression** (PEP 784), in a new `compression.zstd` module.
- **Exceptions without brackets** (PEP 758). `except ValueError, TypeError:` now works when you don't bind the exception with `as`.
- **Warnings for jumps out of a finally block** (PEP 765). A `return`, `break` or `continue` that leaves a `finally` block now raises a `SyntaxWarning`, because such a jump quietly swallows any exception in flight.
- **A safe external debugger interface** (PEP 768). `sys.remote_exec()` lets a debugger attach to a running process without stopping it, and `python -m asyncio ps` and `pstree` use the same groundwork to show what a running program's tasks are doing.
- **Syntax highlighting in the REPL**, and more colour across the standard library's command-line tools.

```python
# Python 3.14: a template string keeps its parts separate.
from string.templatelib import Template

name = "<script>"
greeting = t"Hello, {name}!"
assert isinstance(greeting, Template)
print(greeting.strings)                         # ('Hello, ', '!')
print([part.value for part in greeting.interpolations])  # ['<script>']
```

The release also brought platform changes. PEP 779 made the free-threaded build officially supported (more on that below). The Windows and macOS binaries included the experimental JIT compiler. A new tail-calling interpreter became available for builds made with Clang 19 or newer; the documentation measured it at 3 to 5 percent faster on the pyperformance suite (geometric mean). Python 3.14 was also the first release with official Android binaries, and PEP 761 dropped PGP signatures for releases in favour of Sigstore.

One feature didn't last. Python 3.14.0 shipped a new incremental garbage collector. **Python 3.14.5, released on 10 May 2026, went back to the generational collector from 3.13**, after reports of significant memory pressure in production. If you read a 3.14 feature list from late 2025 that lists incremental GC, it no longer applies to current 3.14 releases. Garbage collection was also on the agenda at this year's Language Summit, so expect the topic to return.

![Illustration: four processor chips sit on parallel lanes of light that carry small yellow, blue and green blocks, while above them an open padlock breaks apart into pixels.](/blog/python-news-november-2026/free-threading.webp "Free-threaded Python lets threads run Python code on several cores at once. It has been officially supported since 3.14, but it is still not the default build.")

## Python 3.15: what is new

Python 3.15 is a big release for code you write every day. The headline features from the official release notes:

### Explicit lazy imports

PEP 810 adds a `lazy` soft keyword. `lazy import json` binds the name straight away but only loads the module the first time the name is used. Command-line tools and large applications that import a lot at start-up but only use a little of it on any one run should start faster. You can also turn lazy imports on globally, with `-X lazy_imports` or the `PYTHON_LAZY_IMPORTS` environment variable. Ruff 0.17 already has rules for the new syntax (more on Ruff below).

```python
# Python 3.15
lazy import json
lazy from pathlib import Path

def save(data, where):
    # json and pathlib are loaded here, the first time they are used.
    Path(where).write_text(json.dumps(data))
```

### New built-ins and syntax

- `frozendict` (PEP 814) is now a built-in: an immutable, hashable mapping, so a dictionary can be a set member or a dictionary key.
- `sentinel` (PEP 661) is a built-in way to make unique marker objects like "no value given", replacing the many home-made `_MISSING = object()` patterns.
- **Unpacking in comprehensions** (PEP 798). `[*row for row in rows]` flattens one level, and `**` works the same way in dictionary comprehensions.
- **Unary plus** is now allowed in `match` literal patterns.

### UTF-8 by default

PEP 686 makes UTF-8 the default encoding for file I/O on every platform. This mostly matters on Windows, where `open()` without an `encoding=` argument used to depend on the locale and caused a whole family of "works on my machine" bugs. If you need the old behaviour, `PYTHONUTF8=0` brings it back.

### A new profiling package

PEP 799 adds a `profiling` package. `profiling.tracing` is the familiar deterministic profiler from `cProfile`. `profiling.sampling` is a new statistical profiler, named "Tachyon" in the release notes, that samples a running program at rates up to 1,000,000 Hz. The old pure-Python `profile` module is deprecated and due for removal in 3.17. A sampling profiler adds little overhead to the program it measures, which makes it much easier to profile a real server or a long job.

### Typing, the C API and the build

Typing got three accepted PEPs: PEP 728 (TypedDict with extra items), PEP 747 (`TypeForm`, for annotating values that are themselves types) and PEP 800 (disjoint bases). Smaller standard library additions include `math.integer` (PEP 791), `asyncio.TaskGroup.cancel()` and TOML 1.1.0 support in `tomllib`.

For extension authors, the most important change is PEP 803, which adds `abi3t`: a stable ABI for free-threaded builds. Until now, a C extension had to be built separately for every free-threaded Python version. With `abi3t`, one wheel can serve several of them. PEP 831 turns frame pointers on by default, which gives profilers and debuggers better stack traces.

### Platforms

According to the 3.15.0 release page, the official macOS installers include free-threading support by default, and the Windows 64-bit binaries use the tail-calling interpreter. Android gets embeddable packages for aarch64 and x86_64, and, for the first time, **an official iOS XCframework** is published.

That last one matters to us. iOS and Android are listed as tier 3 platforms in PEP 11, so they're official, but with fewer guarantees than Linux, macOS or Windows. Pythilo builds on BeeWare's support package, the same work that led to iOS support in CPython itself. An official XCframework from python.org makes it easier for every iOS project that embeds Python.

## Free-threading: supported, not default

Free-threaded Python, the build without the global interpreter lock (often written as `3.14t` or `3.15t`), passed an important milestone in June 2025. PEP 779 was accepted on 16 June 2025 and made the free-threaded build officially supported from Python 3.14 on, which it calls "phase II". The PEP set phase II targets: at most 15 percent slower and at most 20 percent more memory than the normal build. The 3.14 documentation estimates the single-threaded cost at roughly 5 to 10 percent.

"Supported" doesn't mean "default". Phase III, where the free-threaded build would become the standard one, has no PEP and no date. Timelines quoted online for it are guesses. What 3.15 brings is the plumbing that makes free-threading practical. The `abi3t` stable ABI means extension authors can publish one free-threaded wheel instead of one per Python version, the macOS installers include the free-threaded build, and the allocator work continues.

The ecosystem is catching up. PyTorch 2.15 ships wheels for both 3.14t and 3.15t, and its compiler can now use thread-based compile workers on free-threaded Python. If you run CPU-bound Python code in threads, now is a good time to test it on `3.14t`. If you write a C extension, the time to look at `abi3t` is now.

## The JIT's uncertain future

The JIT compiler is the part of the story that changed most this year, and not in the direction its supporters hoped.

CPython has carried an experimental "copy-and-patch" JIT since 3.13, and 3.14 included it, switched off by default, in the Windows and macOS binaries. In 3.15 it got measurably faster. The 3.15 "What's New" reports a 7 to 8 percent geometric mean speedup over the standard interpreter on x86-64 Linux, and 11 to 12 percent over the tail-calling interpreter on AArch64 macOS. Individual benchmarks range from about 15 percent slower to more than twice as fast.

On 5 June 2026 the Steering Council stopped new JIT development on the main branch. It asked for an accepted Standards Track PEP within six months describing how the JIT would become a supported feature. Without one, the council said, the JIT code must be removed from the main branch. The JIT's developers answered with **PEP 836, "JIT Go Brrr"**, created on 2 July 2026 by Savannah Ostrowski, Ken Jin and Brandt Bucher. It laid out method-based compilation, free-threading support and a 20 percent speedup target by 3.17.

**PEP 836 is now marked Withdrawn, with a resolution date of 19 October 2026.** The discussion thread says limited time and people were the reason. The six-month deadline runs to early December 2026. Whether the JIT will actually be removed, and when, has not been officially decided; council members have said in public that removal isn't necessarily immediate. For now: if you use Python 3.15, the JIT is there to try. Whether it survives into 3.16 is undecided.

This doesn't mean CPython has stopped getting faster. The tail-calling interpreter is now the default on Windows 64-bit, frame pointers improve profiling, and the Language Summit discussed GC work and an optional Rust component for CPython (no earlier than 3.16, and not required before 3.18 at the earliest). It does mean that "CPython gets a production JIT" is no longer a safe prediction.

## Tools: uv, Ruff, ty, Pyrefly and pip

For many Python developers the biggest changes of the last two years haven't been in the language at all. They've been in the tools around it.

![Illustration seen from above: a laptop and a tablet on a dark desk, linked by thin lines to icons of a lightning bolt, a gear, a shield with a check mark, a parcel and a locked document, with a plant and a cup of coffee at the edges.](/blog/python-news-november-2026/tooling.webp "Package managers, linters and type checkers: the Python toolbox has been rebuilt over the last two years, much of it in Rust.")

### Astral's uv and Ruff, now part of OpenAI

On 19 March 2026 Astral, the company behind uv, Ruff and ty, announced it was joining OpenAI to work with the Codex team. Astral says its tools will stay open source, and so far the release pace hasn't slowed:

- **uv** reached 0.13.0 on 9 October 2026. That release made Python 3.15 the default version uv installs and prefers native Windows ARM64 Python. The latest version is 0.13.7, from 3 November 2026. In June 2026 uv added a preview `uv audit` command and an opt-in malware check (`UV_MALWARE_CHECK=1`) that uses OSV data. It can also export the new standard lock file format with `uv export --format pylock.toml`; installing from one is still in preview.
- **Ruff** reached 0.17.0 on 9 October 2026 and is now on 0.17.3 (27 October). The default target version moved to Python 3.11, new rules (TID254 and TID255) cover the new lazy imports, the binaries are now code-signed, and support for the old `ruff-lsp` server is gone.

### Type checkers in Rust: ty and Pyrefly

Two fast type checkers, both written in Rust, arrived this year:

- **ty**, from Astral, went into beta on 16 December 2025. Astral reported it as 10 to 60 times faster than mypy and Pyright. It's still in beta: the latest version is 0.0.97, released on 4 November 2026, and the stable release is still an open milestone.
- **Pyrefly**, from Meta, reached 1.0.0 on 12 May 2026 and is now on 1.4.0 (15 October 2026). Meta says it is the default type checker at Instagram and is used by PyTorch and JAX.

The independent Zuban checker is also still active, at v0.10.2. For most teams the practical point is simple: type checking a large codebase used to take long enough that people ran it in CI only. Now it's fast enough to run on every save.

### pip and the standard lock file

**pip 26.3** came out on 2 November 2026. Over the 26.x series pip added `--uploaded-prior-to` (install only what had been published by a given date), support for inline script metadata from PEP 723, and, in 26.1, dropped Python 3.9 and added experimental installs from a `pylock.toml` file. 26.3 extends that to extras and dependency groups.

That lock file format is **PEP 751**, accepted on 31 March 2025. Before it, every tool had its own lock file format: `poetry.lock`, `uv.lock`, `pdm.lock` and a pile of pinned `requirements.txt` files. Now there is a standard one that installers can share, and support is spreading through pip and uv. `pip lock` itself is still experimental.

## Packaging and supply-chain security

Packaging governance changed this year. **PEP 772** created a Python Packaging Council, and the first election results were announced on 17 September 2026, from 541 ballots. Brett Cannon and Pradyun Gedam have two-year terms, and Donald Stufft, Henry Schreiner and Ralf Gommers have one-year terms. The council gives packaging standards one elected body that makes decisions, instead of the old arrangement of delegates for each PEP.

On the technical side, the wheel variants effort is moving. These PEPs aim to let one package publish builds for different GPUs, CPU instruction sets or BLAS libraries, and have the installer pick the right one. PEP 817 is the informational overview, and PEP 825, which defines the package format, has been provisionally accepted. Anyone who has installed PyTorch or another GPU-heavy package knows why this matters.

PyPI spent much of the year on security:

- In April 2026 it published the report on the LiteLLM and Telnyx supply-chain compromise. The attackers had got in through a mutable reference to a third-party GitHub Action.
- Also in April, PyPI completed its second external security audit, by Trail of Bits.
- In July 2026 it started refusing new files for releases older than 14 days. PyPI's post explains that an old, long-trusted release should not be open to poisoning with extra files if a project's publishing token or workflow is ever compromised. Only 56 of the top 15,000 packages had ever added files to a release that late, so very little breaks. PyPI also says not to rely on this behaviour yet, until the semantics are formally defined.

The practical advice hasn't changed: use Trusted Publishing from CI rather than long-lived API tokens, and pin GitHub Actions by commit hash, not by tag.

## The community

A few other things from the past year:

- **PyCon US 2026** took place in Long Beach, California, from 13 to 19 May 2026.
- The **Python Language Summit 2026** was held on 14 July in Kraków, during EuroPython: the first summit in Europe since 2011. Topics included Rust in CPython, garbage collection after the 3.14.5 revert, free-threading, and an `AGENTS.md` file for AI coding agents that work on CPython.
- In October 2025 the **Python Software Foundation withdrew a $1.5 million US National Science Foundation grant proposal**. The board voted unanimously to withdraw, because the grant's terms included an anti-DEI clause that would have applied to all of the PSF's activities, not only the funded project.

## What this means if you are learning Python

If you're learning Python now, very little of this changes what you should study. Functions, data structures, classes, errors, files and tests are the same in 3.15 as they were in 3.12. What changes is the language around them: template strings, lazy imports and `frozendict` are worth knowing once the basics are solid.

The tools are worth picking up early. A modern setup with uv for environments and dependencies, Ruff for linting and formatting, and a type checker running in the editor catches mistakes before they cost you an afternoon. All of these work from the command line on a laptop. On an iPhone or iPad, Pythilo's terminal runs pip and pytest against the embedded CPython 3.14, and the editor shows Pyflakes problems as you type.

We'll move Pythilo to a newer Python once its iOS builds, and the packages we bundle with it, are ready. Until then, 3.14 is a good place to be: it's supported for bugfixes until the next October, and it has most of what makes modern Python pleasant to write.

## Sources

- [Python downloads and release list](https://www.python.org/downloads/), python.org
- [What's New in Python 3.14](https://docs.python.org/3/whatsnew/3.14.html), Python documentation
- [Python 3.14.0 release page](https://www.python.org/downloads/release/python-3140/), python.org
- [PEP 745: Python 3.14 release schedule](https://peps.python.org/pep-0745/)
- [What's New in Python 3.15](https://docs.python.org/3.15/whatsnew/3.15.html), Python documentation
- [Python 3.15.0 release page](https://www.python.org/downloads/release/python-3150/), python.org
- [PEP 790: Python 3.15 release schedule](https://peps.python.org/pep-0790/)
- [PEP 826: Python 3.16 release schedule](https://peps.python.org/pep-0826/)
- [Status of Python versions](https://devguide.python.org/versions/), Python Developer's Guide
- [Python 3.10.22 release page](https://www.python.org/downloads/release/python-31022/), python.org
- [PEP 779: Criteria for supported status for free-threaded Python](https://peps.python.org/pep-0779/)
- [An announcement from the Steering Council regarding the JIT project](https://discuss.python.org/t/an-announcement-from-the-steering-council-regarding-the-jit-project/107638), discuss.python.org
- [PEP 836: JIT Go Brrr](https://peps.python.org/pep-0836/) and [its discussion thread](https://discuss.python.org/t/pep-836-jit-go-brrr-the-path-to-a-supported-jit-compiler-for-cpython/108010/57)
- [PEP 11: CPython platform support](https://peps.python.org/pep-0011/)
- [The Python Language Summit 2026](https://blog.python.org/2026/09/language-summit-2026/), Python Insider
- [uv 0.13.0 release notes](https://github.com/astral-sh/uv/releases/tag/0.13.0), GitHub
- [uv audit](https://astral.sh/blog/uv-audit), Astral blog
- [uv documentation: exporting a lockfile](https://docs.astral.sh/uv/concepts/projects/export/)
- [Ruff 0.17.0 release notes](https://github.com/astral-sh/ruff/releases/tag/0.17.0), GitHub, and [Astral on Python 3.15](https://astral.sh/blog/python-3.15)
- [ty beta announcement](https://astral.sh/blog/ty), Astral blog, and the [ty repository](https://github.com/astral-sh/ty)
- [Astral is joining OpenAI](https://astral.sh/blog/openai), Astral blog
- [Pyrefly 1.0.0 release](https://github.com/facebook/pyrefly/releases/tag/1.0.0), GitHub
- [Zuban releases](https://github.com/zubanls/zuban/releases), GitHub
- [pip release notes](https://pip.pypa.io/en/stable/news/)
- [PEP 751: A file format to record Python dependencies](https://peps.python.org/pep-0751/)
- [PEP 817: Wheel variants](https://peps.python.org/pep-0817/) and [PEP 825](https://peps.python.org/pep-0825/)
- [Announcing the 2026 Python Packaging Council](https://pyfound.blogspot.com/2026/09/announcing-2026-python-packaging.html), PSF blog
- [Incident report: LiteLLM and Telnyx supply-chain attack](https://blog.pypi.org/posts/2026-04-02-incident-report-litellm-telnyx-supply-chain-attack/), PyPI blog
- [PyPI completes second audit](https://blog.pypi.org/posts/2026-04-16-pypi-completes-second-audit/), PyPI blog
- [Releases now reject new files after 14 days](https://blog.pypi.org/posts/2026-07-22-releases-now-reject-new-files-after-14-days/), PyPI blog
- [PyCon US 2026](https://us.pycon.org/2026/)
- [PSF statement on NSF funding](https://pyfound.blogspot.com/2025/10/NSF-funding-statement.html), PSF blog
- Pythilo's own runtime and package versions: the project's README and status notes
