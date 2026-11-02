"""Editor services. They run on their own thread, so they work during a long run."""

import ast
import json
import os
import sys

import _pythilo

_jedi_configured = False


def _emit(kind, payload):
    _pythilo.emit(kind, json.dumps(payload, ensure_ascii=False))


def dispatch(text):
    request = json.loads(text)
    action = request.get("action")
    if action == "check":
        _emit("analysis_problems", {"token": request.get("token"), "path": request["path"], "problems": check(request["source"], request["path"])})
    elif action == "complete":
        _emit("analysis_completions", {"token": request.get("token"), "items": complete(request)})


def check(source, path):
    try:
        tree = ast.parse(source, filename=path)
    except SyntaxError as error:
        return [
            {
                "line": error.lineno or 1,
                "column": (error.offset or 1) - 1,
                "severity": "error",
                "message": error.msg,
                "code": "syntax",
            }
        ]
    except ValueError as error:
        return [{"line": 1, "column": 0, "severity": "error", "message": str(error), "code": "syntax"}]
    try:
        from pyflakes import checker
    except ImportError:
        return []
    problems = []
    for message in sorted(checker.Checker(tree, filename=path).messages, key=lambda item: item.lineno):
        problems.append(
            {
                "line": message.lineno,
                "column": message.col,
                "severity": "warning",
                "message": message.message % message.message_args,
                "code": type(message).__name__,
            }
        )
    return problems


def _configure_jedi(jedi):
    global _jedi_configured
    if _jedi_configured:
        return
    from . import cache_root

    jedi.settings.cache_directory = os.path.join(cache_root, "jedi")
    # Jedi normally inspects another Python process. Here there is only this one.
    jedi.settings.fast_parser = True
    _jedi_configured = True


def complete(request):
    try:
        import jedi
        from jedi.api.environment import InterpreterEnvironment
    except ImportError:
        return []
    _configure_jedi(jedi)
    root = request.get("root")
    try:
        project = jedi.Project(
            root,
            sys_path=[root, os.path.join(root, ".pythilo", "site-packages"), *sys.path],
            added_sys_path=(),
            smart_sys_path=False,
        ) if root else None
        script = jedi.Script(
            request["source"],
            path=request.get("path"),
            project=project,
            environment=InterpreterEnvironment(),
        )
        items = script.complete(request["line"], request["column"])[:60]
    except Exception:
        return []
    return [
        {"label": item.name, "insert": item.complete or "", "kind": item.type}
        for item in items
        if not item.name.startswith("__") or request.get("dunder")
    ]
