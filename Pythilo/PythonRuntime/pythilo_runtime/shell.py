"""The project terminal.

iOS has no processes to start, so each command is implemented here against the
real file system and the real interpreter. A command or flag that is not
implemented says so; nothing is ignored silently.
"""

import fnmatch
import os
import re
import shlex
import shutil
import sys
import time

from . import runner


class ShellError(Exception):
    pass


HELP = """Pythilo terminal. Commands run in this app, on this device.

Files     ls cd pwd cat head tail wc grep find touch mkdir rm rmdir mv cp echo
Python    python [file | -m module | -c code]   with no arguments opens a REPL
Packages  pip install|uninstall|list|show|freeze  (pure Python, plus what Pythilo bundles)
Tests     pytest [args]
Web       python manage.py <command>   django-admin <command>
          flask --app <module> run   uvicorn <module:app>
Git       git status|add|commit|log|diff|branch|switch|clone|fetch|pull|push|remote|init
Other     env which clear help

There is no Unix shell underneath: pipes, background jobs and other programs
are not available. `>` and `>>` redirect a built-in command's output to a file.
"""


PYTHON_HELP = """usage: python [file.py | -m module | -c code] [args]
  python              interactive Python
  python file.py      run a file (manage.py too)
  python -m module    run a module: pip, pytest, http.server, json.tool...
  python -c code      run a line of code
  python --version    the Python version (-V)
Other options are not available: there is one interpreter, inside the app.
"""


def run_line(line, root):
    try:
        words = shlex.split(line, posix=True)
    except ValueError as error:
        print(f"Could not read that command: {error}", file=sys.stderr)
        return {"status": "failed", "code": 2}
    if not words:
        return None
    for token in ("|", "&&", "||", ";", "&"):
        if token in words:
            print(f"pythilo: '{token}' is not supported. Run one command at a time.", file=sys.stderr)
            return {"status": "failed", "code": 2}
    while words and re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*=.*", words[0]):
        name, _, value = words.pop(0).partition("=")
        os.environ[name] = value
    if not words:
        return None
    words, redirect = _split_redirect(words)
    command, *args = words
    handler = _COMMANDS.get(command)
    if handler is None:
        print(f"pythilo: command not found: {command}. Type help to see what is available.", file=sys.stderr)
        return {"status": "failed", "code": 127}
    try:
        if redirect:
            mode, target = redirect
            with open(target, mode, encoding="utf-8") as handle:
                previous = sys.stdout
                sys.stdout = handle
                try:
                    code = handler(args)
                finally:
                    sys.stdout = previous
        else:
            code = handler(args)
    except ShellError as error:
        print(f"{command}: {error}", file=sys.stderr)
        return {"status": "failed", "code": 1}
    except OSError as error:
        print(f"{command}: {error.filename or ''}: {error.strerror or error}", file=sys.stderr)
        return {"status": "failed", "code": 1}
    code = code or 0
    return {"status": "finished" if code == 0 else "failed", "code": code}


def _split_redirect(words):
    for index, word in enumerate(words):
        if word in (">", ">>"):
            if index + 2 != len(words):
                raise_message = "A redirect takes exactly one file and must come last."
                print(f"pythilo: {raise_message}", file=sys.stderr)
                return ["true"], None
            return words[:index], ("w" if word == ">" else "a", words[index + 1])
    return words, None


def _reject_flags(args, allowed=()):
    for arg in args:
        if arg.startswith("-") and arg != "-" and arg not in allowed:
            raise ShellError(f"option {arg} is not supported here")


def _ls(args):
    show_all = long_format = False
    paths = []
    for arg in args:
        if arg.startswith("-") and len(arg) > 1:
            for flag in arg[1:]:
                if flag == "a":
                    show_all = True
                elif flag == "l":
                    long_format = True
                else:
                    raise ShellError(f"option -{flag} is not supported here")
        else:
            paths.append(arg)
    for index, path in enumerate(paths or ["."]):
        if len(paths) > 1:
            print(f"{'' if index == 0 else chr(10)}{path}:")
        if not os.path.isdir(path):
            os.stat(path)
            print(path)
            continue
        names = sorted(os.listdir(path), key=str.lower)
        if not show_all:
            names = [name for name in names if not name.startswith(".")]
        for name in names:
            full = os.path.join(path, name)
            suffix = "/" if os.path.isdir(full) else ""
            if long_format:
                info = os.stat(full)
                stamp = time.strftime("%Y-%m-%d %H:%M", time.localtime(info.st_mtime))
                print(f"{info.st_size:>10}  {stamp}  {name}{suffix}")
            else:
                print(f"{name}{suffix}")


def _cd(args):
    _reject_flags(args)
    if len(args) > 1:
        raise ShellError("takes one directory")
    os.chdir(args[0] if args else os.environ.get("PYTHILO_PROJECT") or ".")


def _pwd(args):
    _reject_flags(args)
    print(os.getcwd())


def _cat(args):
    _reject_flags(args)
    if not args:
        raise ShellError("needs a file")
    for path in args:
        with open(path, encoding="utf-8", errors="replace") as handle:
            sys.stdout.write(handle.read())


def _count_option(args, default):
    count = default
    paths = []
    iterator = iter(args)
    for arg in iterator:
        if arg == "-n":
            count = int(next(iterator, default))
        elif re.fullmatch(r"-\d+", arg):
            count = int(arg[1:])
        elif arg.startswith("-"):
            raise ShellError(f"option {arg} is not supported here")
        else:
            paths.append(arg)
    if not paths:
        raise ShellError("needs a file")
    return count, paths


def _head(args):
    count, paths = _count_option(args, 10)
    for path in paths:
        with open(path, encoding="utf-8", errors="replace") as handle:
            for index, line in enumerate(handle):
                if index >= count:
                    break
                sys.stdout.write(line)


def _tail(args):
    count, paths = _count_option(args, 10)
    for path in paths:
        with open(path, encoding="utf-8", errors="replace") as handle:
            for line in handle.readlines()[-count:]:
                sys.stdout.write(line)


def _wc(args):
    _reject_flags(args)
    if not args:
        raise ShellError("needs a file")
    for path in args:
        with open(path, "rb") as handle:
            data = handle.read()
        print(f"{data.count(b'\n'):>7} {len(data.split()):>7} {len(data):>7} {path}")


def _walk_files(start):
    if os.path.isfile(start):
        yield start
        return
    for directory, subdirectories, files in os.walk(start):
        subdirectories[:] = [name for name in subdirectories if name not in (".git", ".pythilo", "__pycache__")]
        for name in sorted(files):
            yield os.path.join(directory, name)


def _grep(args):
    insensitive = recursive = numbers = False
    positional = []
    for arg in args:
        if arg.startswith("-") and len(arg) > 1:
            for flag in arg[1:]:
                if flag == "i":
                    insensitive = True
                elif flag == "r":
                    recursive = True
                elif flag == "n":
                    numbers = True
                else:
                    raise ShellError(f"option -{flag} is not supported here")
        else:
            positional.append(arg)
    if not positional:
        raise ShellError("needs a pattern")
    pattern = re.compile(positional[0], re.IGNORECASE if insensitive else 0)
    targets = positional[1:] or (["."] if recursive else [])
    if not targets:
        raise ShellError("needs a file, or -r to search this folder")
    found = False
    for target in targets:
        if os.path.isdir(target) and not recursive:
            print(f"grep: {target}: is a directory", file=sys.stderr)
            continue
        for path in _walk_files(target):
            try:
                with open(path, encoding="utf-8") as handle:
                    for number, line in enumerate(handle, 1):
                        if pattern.search(line):
                            found = True
                            label = f"{path}:" + (f"{number}:" if numbers else "")
                            sys.stdout.write(label + line if line.endswith("\n") else label + line + "\n")
            except UnicodeDecodeError:
                continue
    return 0 if found else 1


def _find(args):
    start = "."
    pattern = None
    iterator = iter(args)
    for arg in iterator:
        if arg == "-name":
            pattern = next(iterator, None)
            if pattern is None:
                raise ShellError("-name needs a pattern")
        elif arg.startswith("-"):
            raise ShellError(f"option {arg} is not supported here")
        else:
            start = arg
    for path in _walk_files(start):
        if pattern is None or fnmatch.fnmatch(os.path.basename(path), pattern):
            print(path)


def _touch(args):
    _reject_flags(args)
    if not args:
        raise ShellError("needs a file")
    for path in args:
        with open(path, "a", encoding="utf-8"):
            os.utime(path)


def _mkdir(args):
    _reject_flags(args, ("-p",))
    parents = "-p" in args
    paths = [arg for arg in args if arg != "-p"]
    if not paths:
        raise ShellError("needs a directory")
    for path in paths:
        if parents:
            os.makedirs(path, exist_ok=True)
        else:
            os.mkdir(path)


def _rm(args):
    recursive = force = False
    paths = []
    for arg in args:
        if arg.startswith("-") and len(arg) > 1:
            for flag in arg[1:]:
                if flag == "r":
                    recursive = True
                elif flag == "f":
                    force = True
                else:
                    raise ShellError(f"option -{flag} is not supported here")
        else:
            paths.append(arg)
    if not paths and not force:
        raise ShellError("needs a file")
    project = os.path.realpath(os.environ.get("PYTHILO_PROJECT") or os.getcwd())
    for path in paths:
        full = os.path.realpath(path)
        if full == project or project.startswith(full + os.sep):
            raise ShellError(f"refusing to remove {path}: it contains the project")
        if os.path.isdir(path) and not os.path.islink(path):
            if not recursive:
                raise ShellError(f"{path} is a directory; use -r")
            shutil.rmtree(path)
        elif os.path.lexists(path):
            os.remove(path)
        elif not force:
            raise ShellError(f"{path}: no such file")


def _rmdir(args):
    _reject_flags(args)
    for path in args:
        os.rmdir(path)


def _destination(source, target):
    return os.path.join(target, os.path.basename(source.rstrip("/"))) if os.path.isdir(target) else target


def _mv(args):
    _reject_flags(args)
    if len(args) < 2:
        raise ShellError("needs a source and a destination")
    *sources, target = args
    if len(sources) > 1 and not os.path.isdir(target):
        raise ShellError(f"{target} is not a directory")
    for source in sources:
        shutil.move(source, _destination(source, target))


def _cp(args):
    _reject_flags(args, ("-r",))
    recursive = "-r" in args
    paths = [arg for arg in args if arg != "-r"]
    if len(paths) < 2:
        raise ShellError("needs a source and a destination")
    *sources, target = paths
    if len(sources) > 1 and not os.path.isdir(target):
        raise ShellError(f"{target} is not a directory")
    for source in sources:
        destination = _destination(source, target)
        if os.path.isdir(source):
            if not recursive:
                raise ShellError(f"{source} is a directory; use -r")
            shutil.copytree(source, destination)
        else:
            shutil.copy2(source, destination)


def _echo(args):
    print(" ".join(args))


def _env(args):
    _reject_flags(args)
    for name in sorted(os.environ):
        if name.startswith("PYTHILO_") or name in ("HOME", "PATH", "TMPDIR", "PWD", "LANG", "SSL_CERT_FILE"):
            print(f"{name}={os.environ[name]}")


def _which(args):
    _reject_flags(args)
    code = 0
    for name in args:
        if name in _COMMANDS:
            print(f"{name}: built into Pythilo")
        else:
            print(f"{name} not found", file=sys.stderr)
            code = 1
    return code


def _help(args):
    sys.stdout.write(HELP)


def _python(args):
    import runpy

    if not args:
        repl()
        return 0
    if args[0] in ("-V", "-VV", "--version"):
        print(f"Python {sys.version.split()[0]}")
        return 0
    if args[0] in ("-h", "-?", "--help"):
        print(PYTHON_HELP, end="")
        return 0
    if args[0] == "-m":
        if len(args) < 2:
            raise ShellError("-m needs a module")
        return _run_module(args[1], args[2:])
    if args[0] == "-c":
        if len(args) < 2:
            raise ShellError("-c needs code")
        sys.argv[:] = ["-c", *args[2:]]
        sys.path.insert(0, "")
        module = runner.main_module_for("<string>")
        exec(compile(args[1], "<string>", "exec"), module.__dict__)
        return 0
    if args[0].startswith("-"):
        raise ShellError(f"option {args[0]} is not supported here. python --help lists what works")
    path, rest = args[0], args[1:]
    if os.path.basename(path) == "manage.py":
        rest = _adapt_manage_py(rest)
    if os.path.isdir(path):
        sys.path.insert(0, path)
        sys.argv[:] = [path, *rest]
        runpy.run_path(path, run_name="__main__")
        return 0
    runner.run_script(path, rest)
    return 0


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


def _true(args):
    return 0


def repl():
    import code

    banner = f"Python {sys.version.split()[0]} on {sys.platform}. Stop ends the session."
    namespace = runner.main_module_for("<stdin>").__dict__
    sys.path.insert(0, "")
    code.InteractiveConsole(namespace).interact(banner=banner, exitmsg="")


_COMMANDS = {
    "ls": _ls,
    "cd": _cd,
    "pwd": _pwd,
    "cat": _cat,
    "head": _head,
    "tail": _tail,
    "wc": _wc,
    "grep": _grep,
    "find": _find,
    "touch": _touch,
    "mkdir": _mkdir,
    "rm": _rm,
    "rmdir": _rmdir,
    "mv": _mv,
    "cp": _cp,
    "echo": _echo,
    "env": _env,
    "which": _which,
    "help": _help,
    "python": _python,
    "python3": _python,
    "pip": _pip,
    "pip3": _pip,
    "pytest": _pytest,
    "npm": _npm,
    "django-admin": _django_admin,
    "uvicorn": _uvicorn,
    "flask": _flask,
    "true": _true,
}
