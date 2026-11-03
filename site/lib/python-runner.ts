// Python half of the browser runtime. The worker installs this as the module
// `_pythilo_web`; tests run the same source in Pyodide under Node.
export const PROJECT_ROOT = "/home/pyodide/project";
export const LESSON_ROOT = "/home/pyodide/lesson";
export const SHIM_ROOT = "/home/pyodide/pythilo-shim";

// The app's checker does `from . import emit_json`. This package provides that
// one name and keeps the payload for the worker, so failure messages match the app.
export const LESSON_SHIM = `import json

events = []


def emit_json(kind, payload):
    events.append((kind, json.loads(json.dumps(payload, ensure_ascii=False))))
`;

export const RUNNER_SOURCE = String.raw`
import ast
import importlib
import importlib.util
import json
import os
import runpy
import shutil
import sys
import traceback

PROJECT = ${JSON.stringify(PROJECT_ROOT)}
LESSON = ${JSON.stringify(LESSON_ROOT)}


def _write_tree(root, files):
    if os.path.isdir(root):
        shutil.rmtree(root)
    os.makedirs(root)
    for path, text in files.items():
        full = os.path.join(root, path)
        os.makedirs(os.path.dirname(full), exist_ok=True)
        with open(full, "w", encoding="utf-8", newline="") as handle:
            handle.write(text)
    # Modules imported from an earlier version of the project must load again.
    for name, module in list(sys.modules.items()):
        file = getattr(module, "__file__", None) or ""
        if file.startswith(root + "/"):
            del sys.modules[name]
    importlib.invalidate_caches()


def _relative(text):
    return text.replace(PROJECT + "/", "").replace(LESSON + "/", "")


def _user_frame(error, root):
    tb = error.__traceback__
    while tb is not None and not tb.tb_frame.f_code.co_filename.startswith(root + "/"):
        tb = tb.tb_next
    return tb


def _report(error, root):
    tb = _user_frame(error, root)
    text = "".join(traceback.format_exception(type(error), error, tb))
    sys.stderr.write(_relative(text))
    line, file = None, None
    if isinstance(error, SyntaxError) and error.filename:
        file, line = error.filename, error.lineno
    else:
        last = None
        while tb is not None:
            if tb.tb_frame.f_code.co_filename.startswith(root + "/"):
                last = tb
            tb = tb.tb_next
        if last is not None:
            file, line = last.tb_frame.f_code.co_filename, last.tb_lineno
    message = traceback.format_exception_only(type(error), error)[-1].strip()
    return [{"level": "error", "file": _relative(file or ""), "line": line, "message": _relative(message)}] if file else [{"level": "error", "message": _relative(message)}]


def _exit_code(code):
    if code is None:
        return 0
    if isinstance(code, int):
        return code
    sys.stderr.write(str(code) + "\n")
    return 1


def _enter(root, argv0):
    os.chdir(root)
    sys.path.insert(0, root)
    sys.argv = [argv0]


def _leave(root):
    sys.stdout.flush()
    sys.stderr.flush()
    while root in sys.path:
        sys.path.remove(root)
    os.chdir("/home/pyodide")


def run(files_json, entry, root=PROJECT):
    _write_tree(root, json.loads(files_json))
    _enter(root, entry)
    result = {"exitCode": 0, "stopped": False, "diagnostics": []}
    try:
        runpy.run_path(os.path.join(root, entry), run_name="__main__")
    except SystemExit as error:
        result["exitCode"] = _exit_code(error.code)
    except KeyboardInterrupt:
        sys.stderr.write("Stopped.\n")
        result.update(exitCode=130, stopped=True)
    except BaseException as error:
        result.update(exitCode=1, diagnostics=_report(error, root))
    finally:
        _leave(root)
    return json.dumps(result)


def check(files_json, use_pyflakes):
    files = json.loads(files_json)
    diagnostics = []
    for path, text in sorted(files.items()):
        if not path.endswith((".py", ".pyi")):
            continue
        try:
            tree = compile(text, path, "exec", flags=ast.PyCF_ONLY_AST, dont_inherit=True)
            compile(tree, path, "exec", dont_inherit=True)
        except SyntaxError as error:
            diagnostics.append({"level": "error", "file": path, "line": error.lineno, "column": error.offset, "message": f"{type(error).__name__}: {error.msg}"})
            continue
        if use_pyflakes:
            from pyflakes import checker as flakes

            for message in sorted(flakes.Checker(tree, filename=path).messages, key=lambda item: item.lineno):
                diagnostics.append({"level": "warning", "file": path, "line": message.lineno, "column": getattr(message, "col", 0) + 1, "message": message.message % message.message_args})
    return json.dumps({"diagnostics": diagnostics, "exitCode": 1 if any(item["level"] == "error" for item in diagnostics) else 0})


def test(files_json, framework):
    _write_tree(PROJECT, json.loads(files_json))
    _enter(PROJECT, "pytest" if framework == "pytest" else "unittest")
    result = {"exitCode": 0, "stopped": False, "diagnostics": [], "framework": framework}
    try:
        if framework == "pytest":
            import pytest

            # The output panel is narrow; pytest sizes its separators from COLUMNS.
            os.environ["COLUMNS"] = "60"
            result["exitCode"] = int(pytest.main(["-q", "-p", "no:cacheprovider", "--color=no", PROJECT]))
        else:
            import unittest

            suite = unittest.defaultTestLoader.discover(PROJECT, pattern="test*.py", top_level_dir=PROJECT)
            outcome = unittest.TextTestRunner(stream=sys.stdout, verbosity=2).run(suite)
            result["exitCode"] = 5 if outcome.testsRun == 0 else 0 if outcome.wasSuccessful() else 1
    except SystemExit as error:
        result["exitCode"] = _exit_code(error.code)
    except KeyboardInterrupt:
        sys.stderr.write("Stopped.\n")
        result.update(exitCode=130, stopped=True)
    except BaseException as error:
        result.update(exitCode=1, diagnostics=_report(error, PROJECT))
    finally:
        _leave(PROJECT)
    return json.dumps(result)


def lesson_check(code, checks_json):
    import pythilo_runtime
    from pythilo_runtime import lessons

    _write_tree(LESSON, {"solution.py": code})
    os.chdir(LESSON)
    pythilo_runtime.events.clear()
    result = {"stopped": False, "results": [], "error": None}
    try:
        lessons.check({"id": "web", "path": os.path.join(LESSON, "solution.py"), "checks": json.loads(checks_json)})
        for kind, payload in pythilo_runtime.events:
            if kind == "lesson_result":
                result.update(results=payload["results"], error=payload["error"])
    except KeyboardInterrupt:
        sys.stderr.write("Stopped.\n")
        result["stopped"] = True
    finally:
        _leave(LESSON)
    return json.dumps(result)


def imports(files_json):
    """Top-level imports this browser cannot satisfy, project modules excluded."""
    files = json.loads(files_json)
    local = {path.split("/")[0].removesuffix(".py") for path in files}
    names = set()
    for path, text in files.items():
        if not path.endswith(".py"):
            continue
        try:
            tree = ast.parse(text)
        except SyntaxError:
            continue
        for node in ast.walk(tree):
            if isinstance(node, ast.Import):
                names.update(alias.name.split(".")[0] for alias in node.names)
            elif isinstance(node, ast.ImportFrom) and node.level == 0 and node.module:
                names.add(node.module.split(".")[0])
    return json.dumps(sorted(name for name in names if name not in local and name not in sys.builtin_module_names and importlib.util.find_spec(name) is None))
`;
