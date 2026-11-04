"""The project terminal.

iOS has no processes to start, so each command is implemented here against the
real file system and the real interpreter. A command or flag that is not
implemented says so; nothing is ignored silently.
"""

import os
import re
import sys
import time

from . import bash, runner


ShellError = bash.ShellError


HELP = """Pythilo terminal. Commands run in this app, on this device.

Files     ls cd pwd cat less head tail tree find stat du file touch mkdir rm rmdir mv cp ln chmod
          basename dirname realpath zip unzip tar gzip gunzip
Text      echo printf grep sed awk sort uniq cut tr wc diff tee seq rev nl xargs base64 sha256sum md5sum
Python    python [options] [file | -m module | -c code]   with no arguments opens a REPL
Packages  pip install|uninstall|list|show|freeze|check|download|index|inspect  (pure Python + bundled)
Tests     pytest [args]
Data      sqlite3 [file] [SQL]   (tap a .sqlite3 or .db file to browse it)
Web       python manage.py <command>   django-admin <command>
          flask --app <module> run   uvicorn <module:app>   curl url   wget url
Git       git status|add|commit|log|diff|branch|switch|clone|fetch|pull|push|remote|init
Other     env printenv export unset date sleep time whoami uname which clear help

Pipes and lists work: ls | grep py, pytest && git commit -m ok, a || b, a ; b.
Redirects: > file, >> file, < file, 2> file, 2>&1, &> file. $NAME, ~ and *.py expand.
Each command is built into the app (iOS starts no other programs), so background
jobs (&) and programs outside this list are not available. COMMAND --help shows
a command's options.
"""


PYTHON_HELP = """usage: python [options] [file.py | -m module | -c code | -] [args]
  python              interactive Python
  python file.py      run a file (manage.py and folders with __main__.py too)
  python -m module    run a module: pip, pytest, http.server, json.tool, timeit...
  python -c code      run code given as text
  python -            run code piped in: cat script.py | python -
options:
  -i   open the interactive prompt after the program, with its variables
  -q   no banner in the interactive prompt
  -W   warning filter, for example -W error or -W ignore::DeprecationWarning
  -X   set an -X option (sys._xoptions)
  -B   do not write .pyc files
  -u -E -s -I   accepted; they make no difference here
  -V   version (-VV for the full build string)
There is one interpreter, inside the app: python and python3 are the same.
"""


def run_line(line, root):
    if root:
        os.environ.setdefault("PYTHILO_PROJECT", root)
    try:
        code = bash.run(line, _COMMANDS)
    except bash.ShellError as error:
        print(f"pythilo: {error}", file=sys.stderr)
        return {"status": "failed", "code": 2}
    return {"status": "finished" if code == 0 else "failed", "code": code}


def _which(args):
    code = 0
    for name in args:
        if name.startswith("-"):
            continue
        if name in _COMMANDS:
            print(f"{name}: built into Pythilo")
        else:
            print(f"{name} not found", file=sys.stderr)
            code = 1
    return code


def _sqlite3(args):
    from . import sqlite_cli

    return sqlite_cli.main(args)


def _help(args):
    sys.stdout.write(HELP)


def _python(args):
    import warnings

    # -W, -X and -B last for this program only, as they would in a new process;
    # here the interpreter is shared with every later command.
    saved_options = dict(sys._xoptions), sys.dont_write_bytecode
    with warnings.catch_warnings():
        try:
            return _python_program(args)
        finally:
            sys._xoptions.clear()
            sys._xoptions.update(saved_options[0])
            sys.dont_write_bytecode = saved_options[1]


def _python_program(args):
    import runpy
    import warnings

    interactive_after = quiet = False
    index = 0
    # Options come before the program, as in CPython; the rest belongs to it.
    while index < len(args) and args[index].startswith("-") and args[index] not in ("-", "-c", "-m"):
        option = args[index]
        index += 1
        if option in ("-V", "--version"):
            print(f"Python {sys.version.split()[0]}")
            return 0
        if option == "-VV":
            print(f"Python {sys.version}")
            return 0
        if option in ("-h", "-?", "--help"):
            print(PYTHON_HELP, end="")
            return 0
        if option == "-i":
            interactive_after = True
        elif option == "-q":
            quiet = True
        elif option == "-B":
            sys.dont_write_bytecode = True
        elif option in ("-u", "-E", "-s", "-I", "-P", "-b", "-bb", "-d", "-R", "-x"):
            continue  # output is unbuffered and the environment is the app's already
        elif option in ("-O", "-OO"):
            print("python: -O is fixed when Python starts; asserts stay on here", file=sys.stderr)
        elif option.startswith("-W"):
            spec = option[2:] or (args[index] if index < len(args) else "")
            if not option[2:]:
                index += 1
            action, _, rest = spec.partition(":")
            actions = {"ignore", "default", "error", "always", "module", "once", "i", "d", "e", "a", "m", "o"}
            if action not in actions:
                raise ShellError(f"-W {spec}: the action must be ignore, default, error, always, module or once")
            full = {"i": "ignore", "d": "default", "e": "error", "a": "always", "m": "module", "o": "once"}.get(action, action)
            category = rest.split(":")[1] if rest.count(":") >= 1 else ""
            warnings.simplefilter(full, getattr(__import__("builtins"), category, Warning) if category else Warning)
        elif option.startswith("-X"):
            name = option[2:] or (args[index] if index < len(args) else "")
            if not option[2:]:
                index += 1
            sys._xoptions[name.partition("=")[0]] = name.partition("=")[2] or True
        else:
            raise ShellError(f"option {option} is not supported here. python --help lists what works")
    args = args[index:]
    if not args:
        if bash.piped():
            source = sys.stdin.read()
            sys.argv[:] = ["-"]
            module = runner.main_module_for("<stdin>")
            exec(compile(source, "<stdin>", "exec"), module.__dict__)
            return 0
        repl(quiet=quiet)
        return 0
    if args[0] == "-m":
        if len(args) < 2:
            raise ShellError("-m needs a module")
        code = _run_module(args[1], args[2:])
    elif args[0] == "-c":
        if len(args) < 2:
            raise ShellError("-c needs code")
        sys.argv[:] = ["-c", *args[2:]]
        sys.path.insert(0, "")
        module = runner.main_module_for("<string>")
        exec(compile(args[1], "<string>", "exec"), module.__dict__)
        code = 0
    elif args[0] == "-":
        sys.argv[:] = ["-", *args[1:]]
        module = runner.main_module_for("<stdin>")
        exec(compile(sys.stdin.read() if bash.piped() else "", "<stdin>", "exec"), module.__dict__)
        code = 0
    else:
        path, rest = args[0], args[1:]
        if os.path.basename(path) == "manage.py":
            rest = _adapt_manage_py(rest)
        if os.path.isdir(path) or path.endswith(".zip"):
            sys.path.insert(0, path)
            sys.argv[:] = [path, *rest]
            runpy.run_path(path, run_name="__main__")
        else:
            runner.run_script(path, rest)
        code = 0
    if interactive_after:
        repl(quiet=True, namespace=sys.modules["__main__"].__dict__)
    return code


def _adapt_manage_py(args):
    """Django's autoreloader starts a child process, which iOS does not allow."""
    if args and args[0] == "runserver" and "--noreload" not in args:
        print("Pythilo: running without the autoreloader. Stop and run again after a change.")
        return ["runserver", "--noreload", *args[1:]]
    if args and args[0] == "dbshell":
        raise ShellError("dbshell starts an external database program, which iOS does not allow")
    return args


def _run_module(name, args):
    import runpy

    if name == "pip":
        return _pip(args)
    if name == "pytest":
        return _pytest(args)
    if name == "venv":
        raise ShellError("each project already has its own package folder, .pythilo/site-packages")
    sys.argv[:] = [name, *args]
    sys.path.insert(0, os.getcwd())
    runpy.run_module(name, run_name="__main__", alter_sys=True)
    return 0


def _project_site():
    project = os.environ.get("PYTHILO_PROJECT") or os.getcwd()
    return os.path.join(project, ".pythilo", "site-packages")


def _pip(args):
    from . import packages

    return packages.pip(args, _project_site())


def _npm(args):
    from . import npm

    return npm.main(args, os.getcwd())


def _pytest(args):
    import pytest

    sys.path.insert(0, os.getcwd())
    # stdout and stderr are not file descriptors here, which rules out the
    # faulthandler plugin and fd capture. The cache plugin would also write a
    # folder into a project the user exports.
    return int(pytest.main(["-p", "no:cacheprovider", "-p", "no:faulthandler", "--capture=sys", "--color=no", *args]))


def _django_admin(args):
    from django.core.management import execute_from_command_line

    sys.path.insert(0, os.getcwd())
    execute_from_command_line(["django-admin", *_adapt_manage_py(args)])
    return 0


def _uvicorn(args):
    import uvicorn

    if args in (["--version"], ["-v"]):
        print(f"uvicorn {uvicorn.__version__}")
        return 0
    if args in (["--help"], ["-h"]):
        print("usage: uvicorn module:app [--host 127.0.0.1] [--port 8000]")
        return 0

    target = None
    options = {"host": "127.0.0.1", "port": 8000}
    iterator = iter(args)
    for arg in iterator:
        if arg == "--port":
            options["port"] = int(next(iterator))
        elif arg == "--host":
            options["host"] = next(iterator)
        elif arg in ("--reload", "--workers"):
            raise ShellError(f"{arg} starts extra processes, which iOS does not allow")
        elif arg.startswith("-"):
            raise ShellError(f"option {arg} is not supported here")
        else:
            target = arg
    if target is None:
        raise ShellError("needs an app, for example main:app")
    sys.path.insert(0, os.getcwd())
    uvicorn.run(target, loop="asyncio", http="h11", ws="none", lifespan="auto", **options)
    return 0


def _flask(args):
    from flask.cli import main

    sys.path.insert(0, os.getcwd())
    if "--reload" in args or "--debug" in args:
        raise ShellError("the reloader starts a child process, which iOS does not allow")
    sys.argv[:] = ["flask", *args]
    if "run" in args:
        sys.argv.extend(["--no-reload", "--without-threads"])
    main()
    return 0


def repl(quiet=False, namespace=None):
    import code

    banner = "" if quiet else f"Python {sys.version.split()[0]} on {sys.platform}. Stop ends the session."
    if namespace is None:
        namespace = runner.main_module_for("<stdin>").__dict__
    sys.path.insert(0, "")
    code.InteractiveConsole(namespace).interact(banner=banner, exitmsg="")


_COMMANDS = bash.build({
    "env": bash.printenv,
    "which": _which,
    "type": _which,
    "command": _which,
    "help": _help,
    "man": _help,
    "python": _python,
    "python3": _python,
    "pip": _pip,
    "pip3": _pip,
    "pytest": _pytest,
    "npm": _npm,
    "django-admin": _django_admin,
    "uvicorn": _uvicorn,
    "flask": _flask,
    "sqlite3": _sqlite3,
})
