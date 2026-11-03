# App Store materials, draft

Every claim below is something `docs/STATUS.md` marks as checked. Anything it marks as
not done stays out. Price and packaging are not decided (plan section 4: free with one
unlock, or paid up front), so nothing here mentions them.

## Name and subtitle

- Name: Pythilo (working name; not cleared as a trademark)
- Subtitle (30): Python IDE, course and labs

## Promotional text (170)

Real CPython 3.14 on your iPhone and iPad, offline. Write, run, debug and test projects,
learn from runnable lessons, and explore algorithms in labs.

## Description

Pythilo runs Python 3.14 on the device itself. Nothing is sent to a server to run.

Work on real projects
- Multi-file projects with a file drawer, a terminal, Git and an editor made for touch
- Run, stop and rerun, with input(), clear tracebacks and leftover threads reported
- A debugger with breakpoints, stepping and variables, including in threads, web
  request handlers and async code
- pytest, pip for pure-Python packages, and bundled NumPy, Django, Flask, FastAPI and
  Starlette with Uvicorn, serving real HTTP you can open in the preview
- Notebooks that open and save .ipynb files
- Git: commit, branches, diff, merge with conflict markers, rebase, and HTTPS clone
  (fetch, pull and push are written but not yet tried against a real remote, so they
  stay out of the listing until they are)

Learn
- 36 lessons from foundations to typing, tools, the web and data, plus 20 interview
  tasks with timers and hints
- Every check runs your code on the device and says what came back and what was expected

Explore
- Sorting Bench, Graph Explorer, Search & Hashing and Dynamic Programming labs trace your
  own code while it runs and measure it on the device

Work with an AI client
- Share one project with Claude, Codex or another MCP client on your local network.
  Reading, editing, running, installing packages and committing are separate permissions

Layouts for iPhone in both orientations, iPad, and the folding iPhone.

## Keywords (100)

python,ide,code,editor,learn,course,debugger,pytest,jupyter,notebook,django,fastapi,git,offline

## App Review notes

- The app embeds CPython 3.14 and runs the user's own code on the device, as an
  educational and development tool (guideline 2.5.2 allows this for apps whose
  primary purpose is teaching or writing code). Code is never downloaded from us.
- pip installs pure-Python packages from PyPI into the open project, at the user's
  request. Compiled packages only work if the app bundles them.
- Local-network permission: used only when the user shares a project with an AI
  client on their own network (Playground tab).
- No account, no sign-in. To try it: Projects, then New project, choose the CSV
  Cleaner template, open main.py and tap Run; open the Terminal and type pytest.
- Shared rooms with browsers need a hosted relay that is not live; the app says so and
  offers only the local-network connection.

## Privacy answers

- Data collected: none. No analytics, no advertising, no tracking.
- Network use, all started by the user: pip (PyPI), Git remotes, code the user runs,
  the local-network MCP connection.
- Export compliance: still open (`docs/STATUS.md`). The app contains OpenSSL with Python
  and libgit2's HTTPS; `ITSAppUsesNonExemptEncryption` is false today and needs a
  decision before submission.
