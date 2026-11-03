"""Checks a lesson's solution: run the file, then run each check in its namespace."""

import ast
import contextlib
import io
import linecache
import os
import sys
import traceback
import types

from . import emit_json

# Checks are written as `assert got == want, got`, and the bare value after the
# comma is what Python would report: "None" tells a learner nothing. Each such
# assert is rewritten to keep both sides and say what came back and what was
# expected. An assert whose message is written out in words keeps its words, on
# a line above the explanation when there is one.

_HELPER = "__pythilo_check__"
_OPS = {
    ast.Eq: "==", ast.NotEq: "!=", ast.Lt: "<", ast.LtE: "<=", ast.Gt: ">", ast.GtE: ">=",
    ast.Is: "is", ast.IsNot: "is not", ast.In: "in", ast.NotIn: "not in",
}


def _show(value, limit=160):
    text = repr(value)
    return text if len(text) <= limit else text[: limit - 3] + "..."


def _compare_message(left_src, left, op, right_src, right, is_call):
    if op == "in" and right_src == "_stdout":
        printed = right.rstrip("\n")
        if not printed:
            return f"Expected the output to include {_show(left)}, but nothing was printed."
        return f"Expected the output to include {_show(left)}. It printed {_show(printed[-160:])}."
    if op in ("==", "is"):
        subject = f"{left_src} returned" if is_call else f"{left_src} is"
        message = f"{subject} {_show(left)}, expected {_show(right)}."
        if is_call and left is None:
            message += " Is a return missing?"
        return message
    if op == "!=":
        return f"{left_src} and {right_src} are both {_show(left)}. They should differ."
    if op == "is not":
        if right is None:
            return f"{left_src} is None."
        return f"{left_src} is the same object as {right_src}."
    if op == "in":
        return f"{_show(left)} is not in {right_src}, which is {_show(right)}."
    if op == "not in":
        return f"{_show(left)} should not be in {right_src}."
    return f"{left_src} is {_show(left)}, expected {op} {_show(right)}."


class _Helper:
    @staticmethod
    def compare(left_src, left, op, right_src, right, is_call, detail, words=None):
        message = _compare_message(left_src, left, op, right_src, right, is_call)
        if detail is not None:
            message += f" Details: {_show(detail())}"
        raise AssertionError(f"{words}\n{message}" if words else message)

    @staticmethod
    def truth(test_src, detail):
        message = f"{test_src} is false."
        if detail is not None:
            message += f" Got {_show(detail())}."
        raise AssertionError(message)


class _Explain(ast.NodeTransformer):
    def visit_Assert(self, node):
        test = node.test
        compares = isinstance(test, ast.Compare) and len(test.ops) == 1 and type(test.ops[0]) in _OPS
        words = node.msg.value if isinstance(node.msg, ast.Constant) and isinstance(node.msg.value, str) else None
        if words is not None and not compares:
            return node
        helper = ast.Name(_HELPER, ast.Load())

        def detail(shown):
            # The author's message only adds something when it is not the value
            # the explanation already shows. It runs only on failure, as in assert.
            if node.msg is None or words is not None or ast.unparse(node.msg) in shown:
                return ast.Constant(None)
            no_arguments = ast.arguments(posonlyargs=[], args=[], kwonlyargs=[], kw_defaults=[], defaults=[])
            return ast.Lambda(no_arguments, node.msg)

        if compares:
            left_src = ast.unparse(test.left)
            right_src = ast.unparse(test.comparators[0])
            names = ("_pythilo_left", "_pythilo_right")
            statements = [
                ast.Assign([ast.Name(names[0], ast.Store())], test.left),
                ast.Assign([ast.Name(names[1], ast.Store())], test.comparators[0]),
                ast.If(
                    ast.UnaryOp(ast.Not(), ast.Compare(ast.Name(names[0], ast.Load()), test.ops, [ast.Name(names[1], ast.Load())])),
                    [ast.Expr(ast.Call(ast.Attribute(helper, "compare", ast.Load()), [
                        ast.Constant(left_src), ast.Name(names[0], ast.Load()),
                        ast.Constant(_OPS[type(test.ops[0])]),
                        ast.Constant(right_src), ast.Name(names[1], ast.Load()),
                        ast.Constant(isinstance(test.left, ast.Call)),
                        detail({left_src, right_src, f"repr({left_src})", f"repr({right_src})"}),
                        ast.Constant(words),
                    ], []))],
                    [],
                ),
            ]
        else:
            statements = [ast.If(
                ast.UnaryOp(ast.Not(), test),
                [ast.Expr(ast.Call(ast.Attribute(helper, "truth", ast.Load()), [
                    ast.Constant(ast.unparse(test)), detail(set()),
                ], []))],
                [],
            )]
        for statement in statements:
            ast.copy_location(statement, node)
            ast.fix_missing_locations(statement)
        return statements


def _compile_check(code):
    # Registered so a traceback through the check shows the check's own line.
    linecache.cache["<check>"] = (len(code), None, code.splitlines(True), "<check>")
    tree = _Explain().visit(ast.parse(code, "<check>"))
    return compile(ast.fix_missing_locations(tree), "<check>", "exec")


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
    namespace[_HELPER] = _Helper
    results = []
    for item in checks:
        name = item.get("name", "check")
        if load_error:
            results.append({"name": name, "ok": False, "message": load_error})
            continue
        try:
            code = _compile_check(item["code"])
            with contextlib.redirect_stdout(io.StringIO()):
                exec(code, namespace)
            results.append({"name": name, "ok": True, "message": ""})
        except KeyboardInterrupt:
            raise
        except BaseException as error:
            results.append({"name": name, "ok": False, "message": _describe(error)})
    linecache.cache.pop("<check>", None)
    emit_json("lesson_result", {"id": job["id"], "results": results, "error": load_error})
