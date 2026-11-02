"""Runs notebook cells against one namespace per open notebook.

The namespace outlives a run, so notebook modules are not purged the way a
script's are: `reset` is what the notebook's Restart button calls.
"""

import ast
import base64
import io
import os
import sys
import traceback
import types

from . import emit_json

_sessions = {}


def _session(path):
    namespace = _sessions.get(path)
    if namespace is None:
        module = types.ModuleType("__main__")
        module.__file__ = path
        namespace = module.__dict__
        namespace["__notebook_count__"] = 0
        _sessions[path] = namespace
    return namespace


def reset(path):
    if path:
        _sessions.pop(path, None)
    else:
        _sessions.clear()


class _CellOutput(io.TextIOBase):
    encoding = "utf-8"

    def __init__(self, job_id, cell, name):
        self._job_id = job_id
        self._cell = cell
        self._name = name

    def writable(self):
        return True

    def write(self, text):
        if text:
            emit_json("cell_output", {"id": self._job_id, "cell": self._cell, "type": "stream", "name": self._name, "text": text})
        return len(text)

    def flush(self):
        pass


def _rich_output(value):
    """The `data` of a Jupyter output, from the same methods Jupyter looks for."""
    data = {"text/plain": _safe_repr(value)}
    for method, mime in (("_repr_html_", "text/html"), ("_repr_markdown_", "text/markdown"), ("_repr_svg_", "image/svg+xml")):
        renderer = getattr(value, method, None)
        if callable(renderer) and not isinstance(value, type):
            try:
                rendered = renderer()
            except Exception:
                continue
            if isinstance(rendered, str):
                data[mime] = rendered
    renderer = getattr(value, "_repr_png_", None)
    if callable(renderer) and not isinstance(value, type):
        try:
            rendered = renderer()
            if isinstance(rendered, bytes):
                data["image/png"] = base64.b64encode(rendered).decode()
        except Exception:
            pass
    return data


def _safe_repr(value):
    try:
        return repr(value)
    except Exception as error:
        return f"<repr failed: {type(error).__name__}>"


def _flush_matplotlib(job_id, cell):
    pyplot = sys.modules.get("matplotlib.pyplot")
    if pyplot is None:
        return
    for number in pyplot.get_fignums():
        buffer = io.BytesIO()
        pyplot.figure(number).savefig(buffer, format="png", bbox_inches="tight")
        emit_json(
            "cell_output",
            {
                "id": job_id,
                "cell": cell,
                "type": "display_data",
                "data": {"image/png": base64.b64encode(buffer.getvalue()).decode(), "text/plain": f"<Figure {number}>"},
            },
        )
    pyplot.close("all")


def run_cell(job):
    job_id = job["id"]
    cell = job["cell"]
    path = job["path"]
    source = job["source"]
    namespace = _session(path)
    namespace["__notebook_count__"] += 1
    count = namespace["__notebook_count__"]
    emit_json("cell_start", {"id": job_id, "cell": cell, "count": count})
    sys.stdout = _CellOutput(job_id, cell, "stdout")
    sys.stderr = _CellOutput(job_id, cell, "stderr")
    os.environ.setdefault("MPLBACKEND", "Agg")
    main = types.ModuleType("__main__")
    main.__dict__.update(namespace)
    sys.modules["__main__"] = main
    sys.path.insert(0, os.path.dirname(path))
    try:
        tree = ast.parse(source, filename=f"cell {count}")
        last = None
        if tree.body and isinstance(tree.body[-1], ast.Expr):
            last = ast.Expression(tree.body.pop().value)
        exec(compile(tree, f"cell {count}", "exec"), namespace)
        value = eval(compile(last, f"cell {count}", "eval"), namespace) if last is not None else None
        _flush_matplotlib(job_id, cell)
        if value is not None:
            namespace["_"] = value
            emit_json("cell_output", {"id": job_id, "cell": cell, "type": "execute_result", "count": count, "data": _rich_output(value)})
    except KeyboardInterrupt:
        emit_json("cell_output", {"id": job_id, "cell": cell, "type": "error", "ename": "KeyboardInterrupt", "evalue": "Stopped", "traceback": []})
        raise
    except BaseException as error:
        tb = error.__traceback__
        while tb is not None and "/pythilo_runtime/" in tb.tb_frame.f_code.co_filename:
            tb = tb.tb_next
        lines = traceback.format_exception(type(error), error, tb)
        emit_json("cell_output", {"id": job_id, "cell": cell, "type": "error", "ename": type(error).__name__, "evalue": str(error), "traceback": lines})
        emit_json("cell_end", {"id": job_id, "cell": cell, "ok": False})
        return
    finally:
        sys.path.pop(0)
    emit_json("cell_end", {"id": job_id, "cell": cell, "ok": True})

