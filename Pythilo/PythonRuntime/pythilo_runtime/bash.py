"""A small bash for the project terminal.

iOS has no processes to start, so this reads a command line the way bash
does (quotes, $VARIABLES, ~, globs, pipes, &&, ||, ;, redirects) and runs each
command as a Python function against the real file system. A pipe passes text
from one command to the next in memory.
"""

import base64
import difflib
import fnmatch
import glob
import gzip
import hashlib
import io
import os
import platform
import re
import shutil
import stat
import sys
import tarfile
import time
import zipfile


class ShellError(Exception):
    pass


# The exit code of the last command, for $?.
last_status = 0


# ---------------------------------------------------------------- reading a line

_OPERATORS = ("&&", "||", "2>&1", "&>", "2>>", "2>", ">>", ">", "<", "|", ";", "&")


class Word:
    """One word of a command line, with the parts that came from quotes marked,
    so that only unquoted * and ? expand to file names."""

    def __init__(self):
        self.parts = []  # (text, quoted) or (None, variable name)
        self.started = False

    def add(self, text, quoted):
        self.started = True
        self.parts.append((text, quoted))

    def add_variable(self, name):
        # Expanded when its command runs, so X=1; echo $X sees the new value.
        self.started = True
        self.parts.append((None, name))

    def resolve(self):
        text = pattern = ""
        globs = False
        for value, quoted in self.parts:
            if value is None:
                value = str(last_status) if quoted == "?" else os.environ.get(quoted, "")
                quoted = True
            text += value
            if quoted:
                pattern += glob.escape(value)
            else:
                pattern += value
                globs = globs or any(c in value for c in "*?[")
        return text, pattern, globs


def tokenize(line):
    """Splits a line into words and operators. Variables and ~ are expanded here,
    because whether they expand depends on the quotes around them."""
    tokens = []
    word = Word()
    index = 0
    length = len(line)

    def finish():
        nonlocal word
        if word.started:
            tokens.append(word)
        word = Word()

    while index < length:
        char = line[index]
        if char in " \t\n":
            finish()
            index += 1
            continue
        if char == "#" and not word.started:
            break
        operator = next((op for op in _OPERATORS if line.startswith(op, index)), None)
        # 2> is only a redirect at the start of a word.
        if operator and operator.startswith("2") and word.started:
            operator = None
        if operator:
            finish()
            tokens.append(operator)
            index += len(operator)
            continue
        if char == "\\":
            if index + 1 < length:
                word.add(line[index + 1], quoted=True)
            index += 2
            continue
        if char == "'":
            end = line.find("'", index + 1)
            if end < 0:
                raise ShellError("a ' quote is not closed")
            word.add(line[index + 1:end], quoted=True)
            index = end + 1
            continue
        if char == '"':
            index += 1
            text = ""
            while True:
                if index >= length:
                    raise ShellError('a " quote is not closed')
                c = line[index]
                if c == '"':
                    index += 1
                    break
                if c == "\\" and index + 1 < length and line[index + 1] in '"\\$`':
                    text += line[index + 1]
                    index += 2
                    continue
                if c == "$":
                    name, index = _variable(line, index)
                    if name is None:
                        text += "$"
                    else:
                        word.add(text, quoted=True)
                        word.add_variable(name)
                        text = ""
                    continue
                text += c
                index += 1
            word.add(text, quoted=True)
            continue
        if char == "$":
            name, index = _variable(line, index)
            if name is None:
                word.add("$", quoted=True)
            else:
                word.add_variable(name)
            continue
        if char == "~" and not word.started and (index + 1 == length or line[index + 1] in "/ \t"):
            word.add(os.environ.get("PYTHILO_PROJECT") or os.path.expanduser("~"), quoted=True)
            index += 1
            continue
        word.add(char, quoted=False)
        index += 1
    finish()
    return tokens


def _variable(line, index):
    """Reads $NAME, ${NAME} or $? at index; returns the name (None for a lone $)
    and the next index."""
    rest = line[index + 1:]
    if rest.startswith("?"):
        return "?", index + 2
    if rest.startswith("{"):
        end = rest.find("}")
        if end < 0:
            raise ShellError("a ${ is not closed")
        return rest[1:end], index + end + 2
    match = re.match(r"[A-Za-z_][A-Za-z0-9_]*", rest)
    if not match:
        return None, index + 1
    return match.group(), index + 1 + match.end()


def expand(word):
    text, pattern, globs = word.resolve()
    if not globs:
        return [text]
    # As in bash, a pattern that matches nothing stays as written.
    return sorted(glob.glob(pattern)) or [text]


class Command:
    def __init__(self):
        self.words = []
        self.stdin = None
        self.stdout = None  # (mode, path)
        self.stderr = None  # (mode, path) or "stdout"


def parse(tokens):
    """Returns [(pipeline, connector)], where a pipeline is a list of Commands and
    the connector (;, && or ||) says whether the next pipeline runs."""
    sequence = []
    pipeline = [Command()]
    position = 0
    while position < len(tokens):
        token = tokens[position]
        current = pipeline[-1]
        if isinstance(token, Word):
            current.words.append(token)
        elif token == "|":
            if not current.words:
                raise ShellError("a | needs a command on each side")
            pipeline.append(Command())
        elif token in ("&&", "||", ";"):
            if not current.words:
                raise ShellError(f"{token} needs a command before it")
            sequence.append((pipeline, token))
            pipeline = [Command()]
        elif token == "&":
            raise ShellError("background jobs (&) are not available: iOS runs one program at a time")
        elif token == "2>&1":
            current.stderr = "stdout"
        else:
            position += 1
            if position >= len(tokens) or not isinstance(tokens[position], Word):
                raise ShellError(f"{token} needs a file name after it")
            target = tokens[position]
            if token == "<":
                current.stdin = target
            elif token in (">", ">>"):
                current.stdout = ("a" if token == ">>" else "w", target)
            elif token in ("2>", "2>>"):
                current.stderr = ("a" if token == "2>>" else "w", target)
            elif token == "&>":
                current.stdout = ("w", target)
                current.stderr = "stdout"
        position += 1
    if pipeline[-1].words:
        sequence.append((pipeline, ";"))
    elif len(pipeline) > 1:
        raise ShellError("a | needs a command on each side")
    return sequence


# ---------------------------------------------------------------- running

def run(line, commands):
    """Runs a whole line; returns the exit code of the last command."""
    global last_status
    sequence = parse(tokenize(line))
    status = 0
    skip = None
    for pipeline, connector in sequence:
        if skip is None:
            status = run_pipeline(pipeline, commands)
            last_status = status
        # && runs the next pipeline only after success, || only after failure.
        if connector == "&&":
            skip = None if status == 0 else "&&"
        elif connector == "||":
            skip = None if status != 0 else "||"
        else:
            skip = None
    return status


def run_pipeline(pipeline, commands):
    text_in = None
    status = 0
    for index, command in enumerate(pipeline):
        last = index == len(pipeline) - 1
        words = [text for word in command.words for text in expand(word)]
        while words and re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*=.*", words[0]):
            name, _, value = words.pop(0).partition("=")
            os.environ[name] = value
        if not words:
            continue
        status, text_in = run_command(words, command, commands, text_in, capture=not last)
    return status


def run_command(words, command, commands, text_in, capture):
    name, *args = words
    handler = commands.get(name)
    if handler is None:
        print(f"pythilo: command not found: {name}. Type help to see what is available.", file=sys.stderr)
        return 127, ""
    if name in USAGE and args in (["--help"], ["--version"]):
        # The utilities are small built-ins, not the programs they are named after.
        handler = lambda _: print(f"usage: {USAGE[name]}" if args == ["--help"] else f"{name}: built into Pythilo")
    saved = sys.stdin, sys.stdout, sys.stderr
    opened = []
    captured = io.StringIO() if capture else None
    try:
        if command.stdin is not None:
            handle = open(expand(command.stdin)[0], encoding="utf-8", errors="replace")
            opened.append(handle)
            sys.stdin = handle
        elif text_in is not None:
            sys.stdin = _PipeInput(text_in)
        if command.stdout is not None:
            mode, path = command.stdout
            handle = open(expand(path)[0], mode, encoding="utf-8")
            opened.append(handle)
            sys.stdout = handle
        elif captured is not None:
            sys.stdout = captured
        if command.stderr == "stdout":
            sys.stderr = sys.stdout
        elif command.stderr is not None:
            mode, path = command.stderr
            handle = open(expand(path)[0], mode, encoding="utf-8")
            opened.append(handle)
            sys.stderr = handle
        try:
            code = handler(args)
        except SystemExit as exit:
            code = exit.code if isinstance(exit.code, int) else (0 if exit.code is None else 1)
            if exit.code is not None and not isinstance(exit.code, int):
                print(exit.code, file=sys.stderr)
        except ShellError as error:
            print(f"{name}: {error}", file=sys.stderr)
            code = 1
        except OSError as error:
            where = f"{error.filename}: " if error.filename else ""
            print(f"{name}: {where}{error.strerror or error}", file=sys.stderr)
            code = 1
        except (ValueError, LookupError, re.error, zipfile.BadZipFile, tarfile.TarError) as error:
            print(f"{name}: {error}", file=sys.stderr)
            code = 1
    finally:
        try:
            sys.stdout.flush()
        except Exception:
            pass
        sys.stdin, sys.stdout, sys.stderr = saved
        for handle in opened:
            handle.close()
    return int(code or 0), captured.getvalue() if captured is not None else None


class _PipeInput(io.StringIO):
    piped = True


def piped():
    """True when stdin is a pipe or a file, not the person at the keyboard."""
    return getattr(sys.stdin, "piped", False) or isinstance(sys.stdin, io.TextIOWrapper) and sys.stdin.name != "<stdin>"


# ---------------------------------------------------------------- helpers

def options(args, flags="", valued=""):
    """Splits short options in the usual way: -la is -l -a, -n 5 and -n5 take a
    value. Long options pass through as they are. Returns (set, values, rest)."""
    seen, values, rest = set(), {}, []
    iterator = iter(args)
    done = False
    for arg in iterator:
        if done or arg == "-" or not arg.startswith("-") or len(arg) == 1:
            rest.append(arg)
            continue
        if arg == "--":
            done = True
            continue
        if arg.startswith("--"):
            seen.add(arg)
            continue
        letters = arg[1:]
        position = 0
        while position < len(letters):
            letter = letters[position]
            if letter in valued:
                value = letters[position + 1:] or next(iterator, None)
                if value is None:
                    raise ShellError(f"option -{letter} needs a value")
                values[letter] = value
                break
            if letter not in flags:
                if letter.isdigit() and "n" in valued:
                    values["n"] = letters[position:]
                    break
                raise ShellError(f"option -{letter} is not supported here")
            seen.add(letter)
            position += 1
    return seen, values, rest


def reject_long(seen, allowed=()):
    for flag in seen:
        if flag.startswith("--") and flag not in allowed:
            raise ShellError(f"option {flag} is not supported here")


def read_inputs(paths, what="a file"):
    """Yields (name, text) for each file, or stdin when there are none or for -."""
    if not paths:
        if not piped():
            raise ShellError(f"needs {what}, or text piped into it")
        yield "-", sys.stdin.read()
        return
    for path in paths:
        if path == "-":
            yield "-", sys.stdin.read()
        else:
            with open(path, encoding="utf-8", errors="replace") as handle:
                yield path, handle.read()


def lines_of(text):
    return text.splitlines(keepends=True)


def write_lines(lines):
    for line in lines:
        sys.stdout.write(line if line.endswith("\n") else line + "\n")


def human(size):
    for unit in ("B", "K", "M", "G"):
        if size < 1024 or unit == "G":
            return f"{size:.0f}{unit}" if unit == "B" else f"{size:.1f}{unit}"
        size /= 1024


def project_root():
    return os.path.realpath(os.environ.get("PYTHILO_PROJECT") or os.getcwd())


# ---------------------------------------------------------------- files

def ls(args):
    seen, _, paths = options(args, "alh1RtSrdF")
    reject_long(seen, ("--all",))
    show_all = "a" in seen or "--all" in seen

    def entries(path):
        names = os.listdir(path)
        if not show_all:
            names = [n for n in names if not n.startswith(".")]
        full = [(n, os.path.join(path, n)) for n in names]
        if "t" in seen:
            full.sort(key=lambda item: -os.lstat(item[1]).st_mtime)
        elif "S" in seen:
            full.sort(key=lambda item: -os.lstat(item[1]).st_size)
        else:
            full.sort(key=lambda item: item[0].lower())
        if "r" in seen:
            full.reverse()
        return full

    def show(name, full):
        suffix = "/" if os.path.isdir(full) else ""
        if "l" in seen:
            info = os.lstat(full)
            size = human(info.st_size) if "h" in seen else str(info.st_size)
            stamp = time.strftime("%Y-%m-%d %H:%M", time.localtime(info.st_mtime))
            link = f" -> {os.readlink(full)}" if os.path.islink(full) else ""
            print(f"{stat.filemode(info.st_mode)} {size:>8}  {stamp}  {name}{suffix}{link}")
        else:
            print(f"{name}{suffix}")

    targets = paths or ["."]
    for index, path in enumerate(targets):
        if not os.path.isdir(path) or "d" in seen:
            os.lstat(path)
            show(path, path)
            continue
        if "R" in seen:
            for directory, subdirectories, _ in os.walk(path):
                subdirectories[:] = sorted(d for d in subdirectories if show_all or not d.startswith("."))
                print(f"{directory}:")
                for name, full in entries(directory):
                    show(name, full)
                print()
            continue
        if len(targets) > 1:
            print(f"{'' if index == 0 else chr(10)}{path}:")
        for name, full in entries(path):
            show(name, full)


def cd(args):
    _, _, rest = options(args)
    if len(rest) > 1:
        raise ShellError("takes one directory")
    target = rest[0] if rest else os.environ.get("PYTHILO_PROJECT") or "."
    if target == "-":
        target = os.environ.get("OLDPWD") or "."
    previous = os.getcwd()
    os.chdir(target)
    os.environ["OLDPWD"] = previous
    os.environ["PWD"] = os.getcwd()


def pwd(args):
    options(args, "LP")
    print(os.getcwd())


def cat(args):
    seen, _, paths = options(args, "nbsA")
    number = 0
    for _, text in read_inputs(paths):
        if "n" in seen or "b" in seen:
            for line in lines_of(text):
                if "b" in seen and not line.strip():
                    sys.stdout.write(line)
                    continue
                number += 1
                sys.stdout.write(f"{number:>6}\t{line}")
        else:
            sys.stdout.write(text)


def head(args):
    seen, values, paths = options(args, "qv", "nc")
    count = int(values.get("n", values.get("c", 10)))
    many = len(paths) > 1
    for index, (name, text) in enumerate(read_inputs(paths)):
        if many:
            print(f"{'' if index == 0 else chr(10)}==> {name} <==")
        if "c" in values:
            sys.stdout.write(text[:count])
        else:
            sys.stdout.write("".join(lines_of(text)[:count] if count >= 0 else lines_of(text)[:count]))


def tail(args):
    seen, values, paths = options(args, "qv", "nc")
    raw = values.get("n", values.get("c", "10"))
    from_start = raw.startswith("+")
    count = int(raw.lstrip("+"))
    many = len(paths) > 1
    for index, (name, text) in enumerate(read_inputs(paths)):
        if many:
            print(f"{'' if index == 0 else chr(10)}==> {name} <==")
        if "c" in values:
            sys.stdout.write(text[count - 1:] if from_start else text[-count:] if count else "")
        else:
            lines = lines_of(text)
            sys.stdout.write("".join(lines[count - 1:] if from_start else lines[-count:] if count else []))


def wc(args):
    seen, _, paths = options(args, "lwcm")
    pick = [flag for flag in "lwc" if flag in seen or (flag == "c" and "m" in seen)] or ["l", "w", "c"]
    totals = {"l": 0, "w": 0, "c": 0}
    count = 0
    for name, text in read_inputs(paths):
        counts = {"l": text.count("\n"), "w": len(text.split()), "c": len(text.encode()) if "m" not in seen else len(text)}
        for key in totals:
            totals[key] += counts[key]
        count += 1
        label = "" if name == "-" else f" {name}"
        print("".join(f"{counts[key]:>8}" for key in pick) + label)
    if count > 1:
        print("".join(f"{totals[key]:>8}" for key in pick) + " total")


def walk_files(start, include_dirs=False, max_depth=None):
    if os.path.isfile(start) or os.path.islink(start):
        yield start
        return
    base_depth = start.rstrip("/").count("/")
    if include_dirs:
        yield start
    for directory, subdirectories, files in os.walk(start):
        subdirectories[:] = sorted(d for d in subdirectories if d not in (".git", ".pythilo", "__pycache__", "node_modules"))
        depth = directory.rstrip("/").count("/") - base_depth + 1
        if max_depth is not None and depth > max_depth:
            subdirectories[:] = []
            continue
        if include_dirs:
            for name in subdirectories:
                yield os.path.join(directory, name)
        for name in sorted(files):
            yield os.path.join(directory, name)


def grep(args):
    seen, values, rest = options(args, "inrRvclLwxEFoHhqs", "e")
    reject_long(seen, ("--color", "--colour"))
    patterns = [values["e"]] if "e" in values else []
    if not patterns:
        if not rest:
            raise ShellError("needs a pattern")
        patterns.append(rest.pop(0))
    recursive = "r" in seen or "R" in seen
    flags = re.IGNORECASE if "i" in seen else 0
    sources = [re.escape(p) if "F" in seen else p for p in patterns]
    if "w" in seen:
        sources = [rf"\b(?:{s})\b" for s in sources]
    if "x" in seen:
        sources = [rf"^(?:{s})$" for s in sources]
    pattern = re.compile("|".join(sources), flags)
    targets = rest or (["."] if recursive else [])
    files = []
    for target in targets:
        if os.path.isdir(target) and not recursive:
            print(f"grep: {target}: is a directory", file=sys.stderr)
            continue
        files.extend(walk_files(target))
    show_names = ("H" in seen or len(files) > 1 or recursive) and "h" not in seen
    found = False

    def search(name, text):
        nonlocal found
        hits = 0
        for number, line in enumerate(text.splitlines(), 1):
            matched = bool(pattern.search(line)) != ("v" in seen)
            if not matched:
                continue
            found = True
            hits += 1
            if "q" in seen or "l" in seen or "L" in seen or "c" in seen:
                continue
            prefix = (f"{name}:" if show_names else "") + (f"{number}:" if "n" in seen else "")
            if "o" in seen and "v" not in seen:
                for match in pattern.finditer(line):
                    print(prefix + match.group())
            else:
                print(prefix + line)
        if "c" in seen:
            print((f"{name}:" if show_names else "") + str(hits))
        if "l" in seen and hits:
            print(name)
        if "L" in seen and not hits:
            print(name)

    if not targets:
        for name, text in read_inputs([], "a file, -r to search this folder"):
            search("(standard input)", text)
    for path in files:
        try:
            with open(path, encoding="utf-8") as handle:
                search(path, handle.read())
        except UnicodeDecodeError:
            continue
        except OSError as error:
            if "s" not in seen:
                print(f"grep: {path}: {error.strerror}", file=sys.stderr)
    return 0 if found else 1


def find(args):
    starts = []
    index = 0
    while index < len(args) and not args[index].startswith("-"):
        starts.append(args[index])
        index += 1
    tests = []
    max_depth = None
    kind = None
    rest = args[index:]
    iterator = iter(rest)
    for arg in iterator:
        if arg in ("-name", "-iname", "-path"):
            value = next(iterator, None)
            if value is None:
                raise ShellError(f"{arg} needs a pattern")
            tests.append((arg, value))
        elif arg == "-type":
            kind = next(iterator, None)
            if kind not in ("f", "d"):
                raise ShellError("-type takes f or d")
        elif arg == "-maxdepth":
            max_depth = int(next(iterator, "0"))
        elif arg == "-print":
            continue
        else:
            raise ShellError(f"option {arg} is not supported here (try -name, -iname, -path, -type, -maxdepth)")
    for start in starts or ["."]:
        for path in walk_files(start, include_dirs=True, max_depth=max_depth):
            if kind == "f" and not os.path.isfile(path):
                continue
            if kind == "d" and not os.path.isdir(path):
                continue
            name = os.path.basename(path.rstrip("/")) or path
            ok = True
            for test, value in tests:
                if test == "-name":
                    ok = ok and fnmatch.fnmatchcase(name, value)
                elif test == "-iname":
                    ok = ok and fnmatch.fnmatch(name.lower(), value.lower())
                else:
                    ok = ok and fnmatch.fnmatchcase(path, value)
            if ok:
                print(path)


def tree(args):
    seen, values, paths = options(args, "ad", "L")
    depth = int(values["L"]) if "L" in values else None
    counts = [0, 0]

    def walk(path, prefix, level):
        if depth is not None and level >= depth:
            return
        names = sorted(os.listdir(path), key=str.lower)
        names = [n for n in names if ("a" in seen or not n.startswith(".")) and n not in ("__pycache__",)]
        if "d" in seen:
            names = [n for n in names if os.path.isdir(os.path.join(path, n))]
        for index, name in enumerate(names):
            full = os.path.join(path, name)
            last = index == len(names) - 1
            print(f"{prefix}{'└── ' if last else '├── '}{name}")
            if os.path.isdir(full) and not os.path.islink(full):
                counts[0] += 1
                walk(full, prefix + ("    " if last else "│   "), level + 1)
            else:
                counts[1] += 1

    for path in paths or ["."]:
        print(path)
        walk(path, "", 0)
    print(f"\n{counts[0]} directories" + ("" if "d" in seen else f", {counts[1]} files"))


def touch(args):
    _, _, paths = options(args, "c")
    if not paths:
        raise ShellError("needs a file")
    for path in paths:
        with open(path, "a", encoding="utf-8"):
            os.utime(path)


def mkdir(args):
    seen, _, paths = options(args, "pv")
    if not paths:
        raise ShellError("needs a directory")
    for path in paths:
        if "p" in seen:
            os.makedirs(path, exist_ok=True)
        else:
            os.mkdir(path)
        if "v" in seen:
            print(f"created {path}")


def _guard(path):
    full = os.path.realpath(path)
    project = project_root()
    if full == project or project.startswith(full + os.sep):
        raise ShellError(f"refusing to remove {path}: it contains the project")


def rm(args):
    seen, _, paths = options(args, "rRfdv")
    reject_long(seen, ("--recursive", "--force"))
    recursive = bool({"r", "R", "--recursive"} & seen)
    force = "f" in seen or "--force" in seen
    if not paths and not force:
        raise ShellError("needs a file")
    status = 0
    for path in paths:
        _guard(path)
        if os.path.isdir(path) and not os.path.islink(path):
            if recursive:
                shutil.rmtree(path)
            elif "d" in seen:
                os.rmdir(path)
            else:
                print(f"rm: {path}: is a directory; use -r", file=sys.stderr)
                status = 1
                continue
        elif os.path.lexists(path):
            os.remove(path)
        elif not force:
            print(f"rm: {path}: no such file", file=sys.stderr)
            status = 1
            continue
        if "v" in seen:
            print(f"removed {path}")
    return status


def rmdir(args):
    seen, _, paths = options(args, "p")
    for path in paths:
        _guard(path)
        os.rmdir(path)
        if "p" in seen:
            parent = os.path.dirname(path.rstrip("/"))
            while parent:
                try:
                    os.rmdir(parent)
                except OSError:
                    break
                parent = os.path.dirname(parent)


def _destination(source, target):
    return os.path.join(target, os.path.basename(source.rstrip("/"))) if os.path.isdir(target) else target


def mv(args):
    seen, _, paths = options(args, "fniv")
    if len(paths) < 2:
        raise ShellError("needs a source and a destination")
    *sources, target = paths
    if len(sources) > 1 and not os.path.isdir(target):
        raise ShellError(f"{target} is not a directory")
    for source in sources:
        destination = _destination(source, target)
        if "n" in seen and os.path.exists(destination):
            continue
        shutil.move(source, destination)
        if "v" in seen:
            print(f"{source} -> {destination}")


def cp(args):
    seen, _, paths = options(args, "rRafnpv")
    if len(paths) < 2:
        raise ShellError("needs a source and a destination")
    *sources, target = paths
    if len(sources) > 1 and not os.path.isdir(target):
        raise ShellError(f"{target} is not a directory")
    for source in sources:
        destination = _destination(source, target)
        if "n" in seen and os.path.exists(destination):
            continue
        if os.path.isdir(source):
            if not ({"r", "R", "a"} & seen):
                raise ShellError(f"{source} is a directory; use -r")
            shutil.copytree(source, destination, dirs_exist_ok=True)
        else:
            shutil.copy2(source, destination)
        if "v" in seen:
            print(f"{source} -> {destination}")


def ln(args):
    seen, _, paths = options(args, "sfv")
    if "s" not in seen:
        raise ShellError("only symbolic links (ln -s) are available here")
    if len(paths) != 2:
        raise ShellError("needs a target and a link name")
    target, name = paths
    if os.path.isdir(name):
        name = os.path.join(name, os.path.basename(target))
    if "f" in seen and os.path.lexists(name):
        os.remove(name)
    os.symlink(target, name)


def stat_(args):
    _, _, paths = options(args)
    if not paths:
        raise ShellError("needs a file")
    for path in paths:
        info = os.lstat(path)
        kind = "directory" if stat.S_ISDIR(info.st_mode) else "symbolic link" if stat.S_ISLNK(info.st_mode) else "regular file"
        print(f"  File: {path}")
        print(f"  Size: {info.st_size}\tType: {kind}\tMode: {stat.filemode(info.st_mode)} ({oct(info.st_mode & 0o777)[2:]})")
        for label, value in (("Modify", info.st_mtime), ("Change", info.st_ctime), ("Access", info.st_atime)):
            print(f"{label}: {time.strftime('%Y-%m-%d %H:%M:%S', time.localtime(value))}")


def du(args):
    seen, values, paths = options(args, "shac", "d")
    max_depth = 0 if "s" in seen else int(values["d"]) if "d" in values else None
    total = 0

    def size_of(path):
        if os.path.isfile(path) or os.path.islink(path):
            return os.lstat(path).st_size
        size = 0
        for directory, _, files in os.walk(path):
            for name in files:
                try:
                    size += os.lstat(os.path.join(directory, name)).st_size
                except OSError:
                    pass
        return size

    def show(size, path):
        print(f"{human(size) if 'h' in seen else (size + 1023) // 1024}\t{path}")

    for start in paths or ["."]:
        base = start.rstrip("/").count("/")
        if os.path.isdir(start) and max_depth != 0:
            for directory, subdirectories, files in os.walk(start, topdown=False):
                depth = directory.rstrip("/").count("/") - base
                if max_depth is not None and depth > max_depth:
                    continue
                if "a" in seen:
                    for name in files:
                        full = os.path.join(directory, name)
                        show(os.lstat(full).st_size, full)
                if directory != start:
                    show(size_of(directory), directory)
        size = size_of(start)
        total += size
        show(size, start)
    if "c" in seen:
        show(total, "total")


def file_(args):
    _, _, paths = options(args, "b")
    for path in paths:
        if os.path.isdir(path):
            kind = "directory"
        else:
            with open(path, "rb") as handle:
                start = handle.read(512)
            signatures = {
                b"SQLite format 3\x00": "SQLite 3 database", b"\x89PNG": "PNG image", b"\xff\xd8\xff": "JPEG image",
                b"GIF8": "GIF image", b"PK\x03\x04": "Zip archive", b"\x1f\x8b": "gzip compressed data",
                b"%PDF": "PDF document", b"\x7fELF": "ELF binary", b"\xcf\xfa\xed\xfe": "Mach-O binary",
            }
            kind = next((label for sig, label in signatures.items() if start.startswith(sig)), None)
            if kind is None:
                if not start:
                    kind = "empty"
                elif b"\x00" in start:
                    kind = "data"
                else:
                    first = start.split(b"\n", 1)[0]
                    kind = f"script, {first[2:].decode(errors='replace').strip()}" if first.startswith(b"#!") else "text"
        print(f"{path}: {kind}")


def basename(args):
    _, _, rest = options(args)
    if not rest:
        raise ShellError("needs a path")
    name = os.path.basename(rest[0].rstrip("/")) or "/"
    if len(rest) > 1 and name.endswith(rest[1]) and name != rest[1]:
        name = name[: -len(rest[1])]
    print(name)


def dirname(args):
    for path in args or [""]:
        print(os.path.dirname(path.rstrip("/")) or ".")


def realpath(args):
    for path in args or ["."]:
        print(os.path.realpath(path))


def chmod(args):
    if len(args) < 2:
        raise ShellError("needs a mode and a file")
    mode, *paths = args
    for path in paths:
        current = os.stat(path).st_mode
        if re.fullmatch(r"[0-7]{3,4}", mode):
            os.chmod(path, int(mode, 8))
            continue
        match = re.fullmatch(r"([ugoa]*)([+-=])([rwx]+)", mode)
        if not match:
            raise ShellError(f"mode {mode} is not understood; try 644, 755 or +x")
        who, op, what = match.groups()
        who = who or "a"
        bits = 0
        for person in "ugo":
            if person in who or "a" in who:
                shift = {"u": 6, "g": 3, "o": 0}[person]
                for letter in what:
                    bits |= {"r": 4, "w": 2, "x": 1}[letter] << shift
        new = current | bits if op == "+" else current & ~bits if op == "-" else (current & ~0o777) | bits
        os.chmod(path, new)


# ---------------------------------------------------------------- text

def echo(args):
    newline = True
    interpret = False
    while args and re.fullmatch(r"-[neE]+", args[0]):
        newline = newline and "n" not in args[0]
        interpret = "e" in args[0] or interpret and "E" not in args[0]
        args = args[1:]
    text = " ".join(args)
    if interpret:
        text = text.encode().decode("unicode_escape")
    sys.stdout.write(text + ("\n" if newline else ""))


def printf(args):
    if not args:
        raise ShellError("needs a format")
    template, *values = args
    template = template.encode().decode("unicode_escape")
    specifiers = re.findall(r"%[-+ #0]*\d*(?:\.\d+)?[sdifgexXoc%]", template)
    needed = len([s for s in specifiers if s != "%%"]) or 1
    chunks = [values[i:i + needed] for i in range(0, len(values), needed)] or [[]]

    def convert(spec, value):
        if spec[-1] in "dixXoc":
            return int(value or 0)
        if spec[-1] in "fge":
            return float(value or 0)
        return value

    for chunk in chunks:
        position = 0
        converted = []
        for spec in specifiers:
            if spec == "%%":
                continue
            converted.append(convert(spec, chunk[position] if position < len(chunk) else ""))
            position += 1
        sys.stdout.write(template % tuple(converted))


def sort(args):
    seen, values, paths = options(args, "rnufbV", "kto")
    text = "".join(t for _, t in read_inputs(paths))
    lines = text.splitlines()
    separator = values.get("t")

    def key(line):
        value = line
        if "k" in values:
            field = int(values["k"].split(",")[0].split(".")[0]) - 1
            parts = line.split(separator) if separator else line.split()
            value = parts[field] if field < len(parts) else ""
        if "b" in seen:
            value = value.lstrip()
        if "f" in seen:
            value = value.lower()
        if "n" in seen:
            match = re.match(r"\s*-?\d+(?:\.\d+)?", value)
            return (0, float(match.group()) if match else 0.0, value)
        if "V" in seen:
            return (0, 0.0, [int(p) if p.isdigit() else p for p in re.split(r"(\d+)", value)])
        return (0, 0.0, value)

    lines.sort(key=key, reverse="r" in seen)
    if "u" in seen:
        unique = []
        for line in lines:
            if not unique or key(unique[-1]) != key(line):
                unique.append(line)
        lines = unique
    output = "".join(line + "\n" for line in lines)
    if "o" in values:
        with open(values["o"], "w", encoding="utf-8") as handle:
            handle.write(output)
    else:
        sys.stdout.write(output)


def uniq(args):
    seen, _, paths = options(args, "cdui")
    text = "".join(t for _, t in read_inputs(paths[:1]))
    groups = []
    for line in text.splitlines():
        compare = line.lower() if "i" in seen else line
        if groups and groups[-1][0] == compare:
            groups[-1][2] += 1
        else:
            groups.append([compare, line, 1])
    for _, line, count in groups:
        if "d" in seen and count < 2 or "u" in seen and count > 1:
            continue
        print(f"{count:>7} {line}" if "c" in seen else line)


def _ranges(spec):
    picks = []
    for part in spec.split(","):
        if "-" in part:
            start, _, end = part.partition("-")
            picks.append((int(start or 1), int(end) if end else None))
        else:
            picks.append((int(part), int(part)))
    return picks


def cut(args):
    seen, values, paths = options(args, "s", "dfc")
    if "f" not in values and "c" not in values:
        raise ShellError("needs -f fields or -c characters")
    delimiter = values.get("d", "\t")
    for _, text in read_inputs(paths):
        for line in text.splitlines():
            if "c" in values:
                picked = "".join(line[s - 1:e] for s, e in _ranges(values["c"]))
                print(picked)
                continue
            if delimiter not in line:
                if "s" not in seen:
                    print(line)
                continue
            parts = line.split(delimiter)
            chosen = []
            for start, end in _ranges(values["f"]):
                chosen.extend(parts[start - 1:end])
            print(delimiter.join(chosen))


def _charset(spec):
    classes = {"[:lower:]": "abcdefghijklmnopqrstuvwxyz", "[:upper:]": "ABCDEFGHIJKLMNOPQRSTUVWXYZ",
               "[:digit:]": "0123456789", "[:space:]": " \t\n\r\f\v", "[:alpha:]": "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ",
               "[:alnum:]": "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789", "[:punct:]": "!\"#$%&'()*+,-./:;<=>?@[\\]^_`{|}~"}
    for name, chars in classes.items():
        spec = spec.replace(name, chars)
    spec = spec.encode().decode("unicode_escape")
    out = ""
    index = 0
    while index < len(spec):
        if index + 2 < len(spec) and spec[index + 1] == "-":
            out += "".join(chr(c) for c in range(ord(spec[index]), ord(spec[index + 2]) + 1))
            index += 3
        else:
            out += spec[index]
            index += 1
    return out


def tr(args):
    seen, _, sets = options(args, "dsc")
    if not piped():
        raise ShellError("reads text piped into it, for example: echo hi | tr a-z A-Z")
    text = sys.stdin.read()
    if "d" in seen:
        if not sets:
            raise ShellError("-d needs a set")
        remove = set(_charset(sets[0]))
        text = "".join(c for c in text if (c in remove) == ("c" in seen))
        sys.stdout.write(text)
        return
    if len(sets) < 2 and "s" not in seen:
        raise ShellError("needs two sets, for example tr a-z A-Z")
    if len(sets) >= 2:
        source, target = _charset(sets[0]), _charset(sets[1])
        target = target + target[-1:] * (len(source) - len(target)) if target else ""
        text = text.translate(str.maketrans(source, target[: len(source)]))
    if "s" in seen:
        squeeze = set(_charset(sets[-1]))
        text = re.sub("|".join(f"{re.escape(c)}{re.escape(c)}+" for c in squeeze) or "(?!)", lambda m: m.group()[0], text)
    sys.stdout.write(text)


def _sed_program(script):
    """Parses the common sed commands: s/a/b/flags, d, p, q, and an address of a
    line number, a range, $ or /regex/ before them."""
    commands = []
    for part in [p.strip() for p in re.split(r";\s*(?=(?:\d|\$|/|s|d|p|q|$))", script) if p.strip()]:
        address = None
        match = re.match(r"^(\d+|\$|/(?:[^/\\]|\\.)*/)(?:,(\d+|\$|/(?:[^/\\]|\\.)*/))?", part)
        if match:
            address = (match.group(1), match.group(2))
            part = part[match.end():].strip()
        negate = part.startswith("!")
        part = part.lstrip("!").strip()
        if part.startswith("s") and len(part) > 1:
            delimiter = part[1]
            pieces = re.split(rf"(?<!\\){re.escape(delimiter)}", part[2:])
            if len(pieces) < 3:
                raise ShellError(f"s command is not finished: {part}")
            pattern, replacement, flags = pieces[0], pieces[1], pieces[2]
            replacement = re.sub(r"\\(\d)", r"\\g<\1>", replacement).replace("&", r"\g<0>")
            commands.append((address, negate, "s", re.compile(pattern, re.IGNORECASE if "I" in flags or "i" in flags else 0), replacement, flags))
        elif part in ("d", "p", "q", "="):
            commands.append((address, negate, part, None, None, ""))
        else:
            raise ShellError(f"sed command {part!r} is not supported here (s, d, p, q and = are)")
    return commands


def sed(args):
    in_place = False
    quiet = False
    scripts = []
    paths = []
    extended = False
    iterator = iter(args)
    for arg in iterator:
        if arg == "-n":
            quiet = True
        elif arg in ("-i", "--in-place") or arg.startswith("-i"):
            in_place = True
        elif arg == "-e":
            scripts.append(next(iterator, ""))
        elif arg in ("-E", "-r"):
            extended = True
        elif arg.startswith("-") and arg != "-":
            raise ShellError(f"option {arg} is not supported here")
        elif not scripts:
            scripts.append(arg)
        else:
            paths.append(arg)
    del extended  # Python's re is already extended syntax.
    if not scripts:
        raise ShellError("needs a script, for example sed 's/old/new/g' file")
    program = _sed_program(";".join(scripts))

    def matches(spec, number, line, last):
        if spec == "$":
            return last
        if spec.isdigit():
            return number == int(spec)
        return bool(re.search(spec[1:-1], line))

    def run_text(text):
        out = []
        lines = text.splitlines()
        active = {}
        for number, line in enumerate(lines, 1):
            last = number == len(lines)
            deleted = False
            for index, (address, negate, kind, pattern, replacement, flags) in enumerate(program):
                selected = True
                if address:
                    start, end = address
                    if end is None:
                        selected = matches(start, number, line, last)
                    elif active.get(index):
                        selected = True
                        if matches(end, number, line, last) or (end.isdigit() and number >= int(end)):
                            active[index] = False
                    else:
                        selected = matches(start, number, line, last)
                        if selected and not (end.isdigit() and number >= int(end)):
                            active[index] = True
                if selected == negate:
                    continue
                if kind == "s":
                    count = 0 if "g" in flags else 1
                    new, made = pattern.subn(replacement, line, count=count)
                    line = new
                    if made and "p" in flags:
                        out.append(line)
                elif kind == "d":
                    deleted = True
                    break
                elif kind == "p":
                    out.append(line)
                elif kind == "=":
                    out.append(str(number))
                elif kind == "q":
                    if not quiet:
                        out.append(line)
                    return out
            if not deleted and not quiet:
                out.append(line)
        return out

    if in_place:
        if not paths:
            raise ShellError("-i needs a file")
        for path in paths:
            with open(path, encoding="utf-8") as handle:
                text = handle.read()
            result = "\n".join(run_text(text))
            with open(path, "w", encoding="utf-8") as handle:
                handle.write(result + ("\n" if text.endswith("\n") or result else ""))
        return
    for _, text in read_inputs(paths):
        write_lines(run_text(text))


def awk(args):
    """The part of awk most people type: printing fields, with an optional
    /pattern/ or condition, -F for the separator and NR/NF."""
    separator = None
    program = None
    paths = []
    iterator = iter(args)
    for arg in iterator:
        if arg == "-F":
            separator = next(iterator, " ")
        elif arg.startswith("-F"):
            separator = arg[2:]
        elif program is None:
            program = arg
        else:
            paths.append(arg)
    if program is None:
        raise ShellError("needs a program, for example awk '{print $1}'")
    match = re.fullmatch(r"\s*(?:/((?:[^/\\]|\\.)*)/|(NR\s*[<>=!]=?\s*\d+|NF\s*[<>=!]=?\s*\d+|\$\d+\s*[<>=!]=?\s*\S+))?\s*(?:\{\s*(.*?)\s*\})?\s*", program, re.S)
    if not match:
        raise ShellError("only programs like '{print $1, $3}', '/re/ {print}' or 'NR>1 {print $2}' are supported here")
    regex, condition, action = match.groups()
    action = action if action is not None else "print"
    if separator is not None:
        separator = separator.encode().decode("unicode_escape")
    number = 0
    for _, text in read_inputs(paths):
        for line in text.splitlines():
            number += 1
            fields = line.split(separator) if separator not in (None, " ") else line.split()
            values = {"NR": number, "NF": len(fields)}

            def field(token):
                token = token.strip()
                if token.startswith("$"):
                    index = int(values.get(token[1:], token[1:]) if token[1:] in values else token[1:])
                    return line if index == 0 else fields[index - 1] if index <= len(fields) else ""
                if token in values:
                    return str(values[token])
                if token.startswith('"') and token.endswith('"'):
                    return token[1:-1].encode().decode("unicode_escape")
                raise ShellError(f"{token} is not supported in awk here")

            if regex is not None and not re.search(regex, line):
                continue
            if condition:
                left, op, right = re.match(r"(\S+?)\s*([<>=!]=?)\s*(\S+)", condition).groups()
                left_value = field(left) if left.startswith("$") else values[left]
                right_value = right.strip('"')
                try:
                    left_value, right_value = float(left_value), float(right_value)
                except (TypeError, ValueError):
                    left_value = str(left_value)
                op = "==" if op == "=" else op
                if not {"<": left_value < right_value, ">": left_value > right_value, "<=": left_value <= right_value,
                        ">=": left_value >= right_value, "==": left_value == right_value, "!=": left_value != right_value}[op]:
                    continue
            for statement in [s.strip() for s in action.split(";") if s.strip()]:
                if statement == "print":
                    print(line)
                elif statement.startswith("print"):
                    items = re.findall(r'"(?:[^"\\]|\\.)*"|\$\w+|\bNR\b|\bNF\b|,', statement[5:])
                    parts, current = [], ""
                    for item in items:
                        if item == ",":
                            parts.append(current)
                            current = ""
                        else:
                            current += field(item)
                    parts.append(current)
                    print(" ".join(parts))
                else:
                    raise ShellError(f"awk statement {statement!r} is not supported here (print is)")


def diff(args):
    seen, values, paths = options(args, "uqr", "U")
    if len(paths) != 2:
        raise ShellError("needs two files")
    first, second = paths
    if os.path.isdir(first) and os.path.isdir(second):
        status = 0
        names = sorted(set(os.listdir(first)) | set(os.listdir(second)))
        for name in names:
            a, b = os.path.join(first, name), os.path.join(second, name)
            if not os.path.exists(a):
                print(f"Only in {second}: {name}")
                status = 1
            elif not os.path.exists(b):
                print(f"Only in {first}: {name}")
                status = 1
            elif os.path.isfile(a) and os.path.isfile(b):
                status = max(status, diff([*(["-u"] if "u" in seen else []), *(["-q"] if "q" in seen else []), a, b]) or 0)
        return status
    with open(first, encoding="utf-8", errors="replace") as handle:
        a = handle.read().splitlines(keepends=True)
    with open(second, encoding="utf-8", errors="replace") as handle:
        b = handle.read().splitlines(keepends=True)
    if a == b:
        return 0
    if "q" in seen:
        print(f"Files {first} and {second} differ")
        return 1
    if "u" in seen or "U" in values:
        for line in difflib.unified_diff(a, b, first, second, n=int(values.get("U", 3))):
            sys.stdout.write(line if line.endswith("\n") else line + "\n")
        return 1

    def span(start, end):
        return f"{start + 1}" if end - start == 1 else f"{start + 1},{end}" if end > start else f"{start}"

    for tag, i1, i2, j1, j2 in difflib.SequenceMatcher(None, a, b).get_opcodes():
        if tag == "equal":
            continue
        letter = {"replace": "c", "delete": "d", "insert": "a"}[tag]
        print(f"{span(i1, i2)}{letter}{span(j1, j2)}")
        for line in a[i1:i2]:
            sys.stdout.write("< " + (line if line.endswith("\n") else line + "\n"))
        if tag == "replace":
            print("---")
        for line in b[j1:j2]:
            sys.stdout.write("> " + (line if line.endswith("\n") else line + "\n"))
    return 1


def tee(args):
    seen, _, paths = options(args, "a")
    text = sys.stdin.read() if piped() else ""
    for path in paths:
        with open(path, "a" if "a" in seen else "w", encoding="utf-8") as handle:
            handle.write(text)
    sys.stdout.write(text)


def seq(args):
    seen, values, numbers = options(args, "w", "s")
    if not numbers:
        raise ShellError("needs a number")
    parts = [float(n) if "." in n else int(n) for n in numbers]
    first, step, last = (1, 1, parts[0]) if len(parts) == 1 else (parts[0], 1, parts[1]) if len(parts) == 2 else parts[:3]
    if step == 0:
        raise ShellError("the step cannot be 0")
    values_out = []
    value = first
    while (step > 0 and value <= last) or (step < 0 and value >= last):
        values_out.append(str(value))
        value += step
        if len(values_out) > 1_000_000:
            raise ShellError("stopped at a million numbers")
    if "w" in seen:
        width = max(len(v) for v in values_out) if values_out else 0
        values_out = [v.zfill(width) for v in values_out]
    sys.stdout.write(values.get("s", "\n").join(values_out) + ("\n" if values_out else ""))


def rev(args):
    for _, text in read_inputs(args):
        for line in text.splitlines():
            print(line[::-1])


def nl(args):
    _, _, paths = options(args)
    number = 0
    for _, text in read_inputs(paths):
        for line in text.splitlines():
            if line.strip():
                number += 1
                print(f"{number:>6}\t{line}")
            else:
                print()


def xargs(args, commands=None):
    seen, values, rest = options(args, "rt", "nI")
    if not rest:
        rest = ["echo"]
    items = sys.stdin.read().split() if piped() else []
    if not items and "r" in seen:
        return 0
    status = 0
    if "I" in values:
        groups = [[rest_word.replace(values["I"], item) for rest_word in rest] for item in items]
    else:
        size = int(values["n"]) if "n" in values else len(items) or 1
        groups = [rest + items[i:i + size] for i in range(0, max(len(items), 1), size)]
    for words in groups:
        if "t" in seen:
            print(" ".join(words), file=sys.stderr)
        handler = (commands or {}).get(words[0])
        if handler is None:
            raise ShellError(f"command not found: {words[0]}")
        saved = sys.stdin
        sys.stdin = _PipeInput("")
        try:
            status = max(status, int(handler(words[1:]) or 0))
        finally:
            sys.stdin = saved
    return status


def base64_(args):
    seen, _, paths = options(args, "dD", "w")
    if paths and paths[0] != "-":
        with open(paths[0], "rb") as handle:
            data = handle.read()
    elif piped():
        data = sys.stdin.read().encode()
    else:
        raise ShellError("needs a file, or text piped into it")
    if "d" in seen or "D" in seen or "--decode" in seen:
        decoded = base64.b64decode(b"".join(data.split()))
        sys.stdout.write(decoded.decode("utf-8", errors="replace"))
    else:
        print(base64.b64encode(data).decode())


def _hasher(name):
    def run_hash(args):
        _, _, paths = options(args)
        if not paths:
            if not piped():
                raise ShellError("needs a file, or text piped into it")
            print(f"{hashlib.new(name, sys.stdin.read().encode()).hexdigest()}  -")
            return
        for path in paths:
            with open(path, "rb") as handle:
                print(f"{hashlib.new(name, handle.read()).hexdigest()}  {path}")
    return run_hash


# ---------------------------------------------------------------- archives

def zip_(args):
    seen, _, paths = options(args, "rqj")
    if len(paths) < 2:
        raise ShellError("needs an archive name and files, for example zip -r site.zip site")
    archive, *sources = paths
    if not archive.endswith(".zip"):
        archive += ".zip"
    with zipfile.ZipFile(archive, "w", zipfile.ZIP_DEFLATED) as bundle:
        for source in sources:
            files = walk_files(source) if os.path.isdir(source) and "r" in seen else [source]
            if os.path.isdir(source) and "r" not in seen:
                raise ShellError(f"{source} is a directory; use -r")
            for path in files:
                name = os.path.basename(path) if "j" in seen else path
                bundle.write(path, name)
                if "q" not in seen:
                    print(f"  adding: {name}")


def unzip(args):
    seen, values, paths = options(args, "loq", "d")
    if not paths:
        raise ShellError("needs an archive")
    with zipfile.ZipFile(paths[0]) as bundle:
        if "l" in seen:
            for info in bundle.infolist():
                print(f"{info.file_size:>10}  {info.filename}")
            return
        target = values.get("d", ".")
        root = os.path.realpath(target)
        for info in bundle.infolist():
            destination = os.path.realpath(os.path.join(target, info.filename))
            if not destination.startswith(root + os.sep) and destination != root:
                raise ShellError(f"{info.filename} would be written outside {target}")
            if os.path.exists(destination) and "o" not in seen and not info.is_dir():
                print(f"skipping {info.filename}: it exists (use -o to overwrite)", file=sys.stderr)
                continue
            bundle.extract(info, target)
            if "q" not in seen:
                print(f"  inflating: {info.filename}")


def tar(args):
    if args and not args[0].startswith("-") and re.fullmatch(r"[cxtzjvfC]+", args[0]):
        args = ["-" + args[0], *args[1:]]
    seen, values, paths = options(args, "cxtzjv", "fC")
    if "f" not in values:
        raise ShellError("needs -f archive")
    archive = values["f"]
    compression = "gz" if "z" in seen else "bz2" if "j" in seen else ""
    if "c" in seen:
        with tarfile.open(archive, "w:" + compression) as bundle:
            for path in paths:
                bundle.add(path)
                if "v" in seen:
                    print(path)
    elif "x" in seen or "t" in seen:
        with tarfile.open(archive, "r:*") as bundle:
            if "t" in seen:
                for member in bundle.getmembers():
                    print(member.name)
                return
            bundle.extractall(values.get("C", "."), filter="data")
            if "v" in seen:
                for member in bundle.getmembers():
                    print(member.name)
    else:
        raise ShellError("needs -c, -x or -t")


def gzip_(args):
    seen, _, paths = options(args, "dkc")
    for path in paths:
        if "d" in seen:
            if not path.endswith(".gz"):
                raise ShellError(f"{path}: unknown suffix")
            with gzip.open(path, "rb") as source, open(path[:-3], "wb") as target:
                shutil.copyfileobj(source, target)
        else:
            with open(path, "rb") as source, gzip.open(path + ".gz", "wb") as target:
                shutil.copyfileobj(source, target)
        if "k" not in seen:
            os.remove(path)


def gunzip(args):
    return gzip_(["-d", *args])


# ---------------------------------------------------------------- system

def date(args):
    utc = "-u" in args
    args = [a for a in args if a != "-u"]
    moment = time.gmtime() if utc else time.localtime()
    if args and args[0].startswith("+"):
        print(time.strftime(args[0][1:], moment))
    elif args == ["-I"] or args == ["--iso-8601"]:
        print(time.strftime("%Y-%m-%d", moment))
    elif args:
        raise ShellError(f"option {args[0]} is not supported here (+FORMAT, -u and -I are)")
    else:
        print(time.strftime("%a %b %d %H:%M:%S %Z %Y", moment))


def sleep(args):
    if not args:
        raise ShellError("needs a number of seconds")
    total = 0.0
    for arg in args:
        match = re.fullmatch(r"(\d+(?:\.\d+)?)([smh]?)", arg)
        if not match:
            raise ShellError(f"{arg} is not a duration")
        total += float(match.group(1)) * {"": 1, "s": 1, "m": 60, "h": 3600}[match.group(2)]
    time.sleep(total)


def export(args):
    if not args or args == ["-p"]:
        for name in sorted(os.environ):
            print(f"declare -x {name}={os.environ[name]!r}")
        return
    for arg in args:
        if "=" in arg:
            name, _, value = arg.partition("=")
            os.environ[name] = value


def unset(args):
    for name in args:
        os.environ.pop(name, None)


def printenv(args):
    if args:
        missing = 0
        for name in args:
            if name in os.environ:
                print(os.environ[name])
            else:
                missing = 1
        return missing
    for name in sorted(os.environ):
        print(f"{name}={os.environ[name]}")


def whoami(args):
    print("mobile")


def hostname(args):
    print(platform.node() or "localhost")


def uname(args):
    seen, _, _ = options(args, "asnrmvpio")
    system = platform.system() or "Darwin"
    if "a" in seen:
        print(f"{system} {platform.node()} {platform.release()} {platform.version()} {platform.machine()}")
    elif "m" in seen:
        print(platform.machine())
    elif "r" in seen:
        print(platform.release())
    elif "n" in seen:
        print(platform.node())
    else:
        print(system)


def true(args):
    return 0


def false(args):
    return 1


def yes(args):
    raise ShellError("would print forever; try seq or a loop in Python instead")


def curl(args):
    import urllib.error
    import urllib.request

    seen, values, rest = options(args, "sSLfIOkivg", "oXdHAu")
    headers = {}
    iterator = iter(args)
    for arg in iterator:
        if arg == "-H":
            header = next(iterator, "")
            name, _, value = header.partition(":")
            headers[name.strip()] = value.strip()
    if not rest:
        raise ShellError("needs a URL")
    url = rest[0]
    if "://" not in url:
        url = "http://" + url
    data = values.get("d")
    method = values.get("X") or ("HEAD" if "I" in seen else "POST" if data is not None else "GET")
    if "A" in values:
        headers["User-Agent"] = values["A"]
    headers.setdefault("User-Agent", "pythilo-curl/1")
    if data is not None and "Content-Type" not in headers:
        headers["Content-Type"] = "application/x-www-form-urlencoded"
    request = urllib.request.Request(url, data=data.encode() if data is not None else None, method=method, headers=headers)
    try:
        response = urllib.request.urlopen(request, timeout=30)
    except urllib.error.HTTPError as error:
        response = error
        if "f" in seen:
            if "s" not in seen or "S" in seen:
                print(f"curl: ({error.code}) {error.reason}", file=sys.stderr)
            return 22
    except urllib.error.URLError as error:
        print(f"curl: could not reach {url}: {error.reason}", file=sys.stderr)
        return 6
    head_text = f"HTTP/1.1 {response.status} {response.reason}\n" + "".join(f"{k}: {v}\n" for k, v in response.headers.items())
    if "I" in seen:
        sys.stdout.write(head_text)
        return 0
    body = response.read()
    if "i" in seen:
        sys.stdout.write(head_text + "\n")
    target = values.get("o") or (os.path.basename(url.split("?")[0].rstrip("/")) or "index.html" if "O" in seen else None)
    if target:
        with open(target, "wb") as handle:
            handle.write(body)
        if "s" not in seen:
            print(f"saved {len(body)} bytes to {target}", file=sys.stderr)
    else:
        sys.stdout.write(body.decode("utf-8", errors="replace"))


def wget(args):
    seen, values, rest = options(args, "qc", "O")
    if not rest:
        raise ShellError("needs a URL")
    target = values.get("O") or os.path.basename(rest[0].split("?")[0].rstrip("/")) or "index.html"
    return curl(["-sSLf", "-o", target, rest[0]] if target != "-" else ["-sSLf", rest[0]])


def time_(args, commands=None):
    if not args:
        raise ShellError("needs a command")
    handler = (commands or {}).get(args[0])
    if handler is None:
        raise ShellError(f"command not found: {args[0]}")
    started = time.perf_counter()
    cpu = time.process_time()
    try:
        return handler(args[1:])
    finally:
        print(f"\nreal\t{time.perf_counter() - started:.3f}s\ncpu\t{time.process_time() - cpu:.3f}s", file=sys.stderr)


USAGE = {
    "ls": "ls [-alh1RtSrd] [path...]", "cd": "cd [folder | - | ~]", "pwd": "pwd",
    "cat": "cat [-nb] [file...]   (reads a pipe without files)", "head": "head [-n N | -c N] [file...]",
    "tail": "tail [-n N | -n +N | -c N] [file...]", "wc": "wc [-lwc] [file...]",
    "grep": "grep [-inrvclLwxEFoHhq] [-e pattern] pattern [path...]", "egrep": "egrep pattern [path...]", "fgrep": "fgrep text [path...]",
    "find": "find [path...] [-name P] [-iname P] [-path P] [-type f|d] [-maxdepth N]", "tree": "tree [-a] [-d] [-L depth] [path]",
    "touch": "touch file...", "mkdir": "mkdir [-pv] folder...", "rm": "rm [-rfdv] path...", "rmdir": "rmdir [-p] folder...",
    "mv": "mv [-nv] source... target", "cp": "cp [-rnv] source... target", "ln": "ln -s [-f] target name",
    "stat": "stat file...", "du": "du [-shac] [-d depth] [path...]", "file": "file path...",
    "basename": "basename path [suffix]", "dirname": "dirname path", "realpath": "realpath path...", "readlink": "readlink path...",
    "chmod": "chmod 644|755|+x|u-w file...", "echo": "echo [-n] [-e] text...", "printf": "printf format [values...]",
    "sort": "sort [-rnufbV] [-k N] [-t sep] [-o file] [file...]", "uniq": "uniq [-cdui] [file]",
    "cut": "cut -f list [-d sep] | -c list [file...]", "tr": "tr [-dsc] set1 [set2]   (reads a pipe)",
    "sed": "sed [-n] [-i] [-e] 's/re/new/g' | '/re/d' | 'Np' | '1,5d' [file...]",
    "awk": "awk [-F sep] '[/re/ | NR>1 | $3>10] {print $1, $2}' [file...]",
    "diff": "diff [-u] [-q] [-r] a b", "tee": "tee [-a] file...", "seq": "seq [-w] [-s sep] [first [step]] last",
    "rev": "rev [file...]", "nl": "nl [file...]", "base64": "base64 [-d] [file]",
    "md5sum": "md5sum [file...]", "sha1sum": "sha1sum [file...]", "sha256sum": "sha256sum [file...]", "shasum": "shasum [file...]",
    "less": "less file   (prints the whole file)", "more": "more file   (prints the whole file)",
    "zip": "zip [-rqj] archive.zip path...", "unzip": "unzip [-l] [-o] [-q] [-d folder] archive.zip",
    "tar": "tar -c|-x|-t [-z|-j] [-v] -f archive [-C folder] [path...]", "gzip": "gzip [-dk] file...", "gunzip": "gunzip [-k] file.gz...",
    "date": "date [-u] [+FORMAT | -I]", "sleep": "sleep seconds[s|m|h]", "export": "export NAME=value...", "unset": "unset NAME...",
    "printenv": "printenv [NAME...]", "env": "env", "whoami": "whoami", "hostname": "hostname", "uname": "uname [-a | -m | -r | -n]",
    "true": "true", "false": "false", "curl": "curl [-sSLfIi] [-o file | -O] [-X method] [-H header] [-d data] url",
    "wget": "wget [-q] [-O file] url", "xargs": "xargs [-n N] [-I {}] [-r] [-t] command [args]", "time": "time command [args]",
    "which": "which command...", "type": "type command...", "help": "help", "man": "man   (same as help)",
}


def build(extra):
    """The command table: these utilities plus the ones passed in (python, pip...)."""
    table = {
        "ls": ls, "cd": cd, "pwd": pwd, "cat": cat, "head": head, "tail": tail, "wc": wc, "grep": grep,
        "egrep": lambda args: grep(["-E", *args]), "fgrep": lambda args: grep(["-F", *args]),
        "find": find, "tree": tree, "touch": touch, "mkdir": mkdir, "rm": rm, "rmdir": rmdir, "mv": mv, "cp": cp,
        "ln": ln, "stat": stat_, "du": du, "file": file_, "basename": basename, "dirname": dirname,
        "realpath": realpath, "readlink": realpath, "chmod": chmod,
        "echo": echo, "printf": printf, "sort": sort, "uniq": uniq, "cut": cut, "tr": tr, "sed": sed, "awk": awk,
        "diff": diff, "tee": tee, "seq": seq, "rev": rev, "nl": nl, "base64": base64_,
        "md5sum": _hasher("md5"), "sha1sum": _hasher("sha1"), "sha256sum": _hasher("sha256"),
        "shasum": _hasher("sha1"), "less": cat, "more": cat,
        "zip": zip_, "unzip": unzip, "tar": tar, "gzip": gzip_, "gunzip": gunzip,
        "date": date, "sleep": sleep, "export": export, "unset": unset, "printenv": printenv, "whoami": whoami,
        "hostname": hostname, "uname": uname, "true": true, "false": false, ":": true, "yes": yes,
        "curl": curl, "wget": wget,
    }
    table.update(extra)
    table["xargs"] = lambda args: xargs(args, table)
    table["time"] = lambda args: time_(args, table)
    return table
