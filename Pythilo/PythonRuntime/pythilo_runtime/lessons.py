"""Checks a lesson's solution: run the file, then run each check in its namespace."""

import contextlib
import io
import os
import sys
import traceback
import types

from . import emit_json


def _describe(error):
    if isinstance(error, AssertionError) and str(error):
        return str(error)
    frames = traceback.extract_tb(error.__traceback__)
    for frame in reversed(frames):
        if frame.filename in ("<check>", "solution.py") or frame.filename.endswith("/solution.py"):
            return f"{type(error).__name__}: {error} (line {frame.lineno}: {frame.line or ''})".strip()
    return f"{type(error).__name__}: {error}"


def check(job):
    path = job["path"]
    checks = job.get("checks") or []
    module = types.ModuleType("solution_under_test")
    module.__file__ = path
    namespace = module.__dict__
    captured = io.StringIO()
    load_error = None
    sys.path.insert(0, os.path.dirname(path))
    try:
        with open(path, encoding="utf-8") as handle:
            source = handle.read()
        with contextlib.redirect_stdout(captured):
            exec(compile(source, path, "exec"), namespace)
    except KeyboardInterrupt:
        raise
    except BaseException as error:
        load_error = _describe(error)
    sys.stdout.write(captured.getvalue())
    namespace["_stdout"] = captured.getvalue()
    results = []
    for item in checks:
        name = item.get("name", "check")
        if load_error:
            results.append({"name": name, "ok": False, "message": load_error})
            continue
        try:
            with contextlib.redirect_stdout(io.StringIO()):
                exec(compile(item["code"], "<check>", "exec"), namespace)
            results.append({"name": name, "ok": True, "message": ""})
        except KeyboardInterrupt:
            raise
        except BaseException as error:
            results.append({"name": name, "ok": False, "message": _describe(error)})
    emit_json("lesson_result", {"id": job["id"], "results": results, "error": load_error})
