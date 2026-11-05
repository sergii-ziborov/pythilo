"""The shared engine for the step-by-step labs.

A lab runs the learner's own code under a line tracer. After each line of their file,
the lab looks at the live variables and draws a frame: arrays with pointers, trees,
grids, stacks, linked nodes, points and curves. Frames that look the same as the one
before are dropped, so every step the learner sees changed something.

"How it scales" runs the same code again without the tracer on growing inputs and
reports the median time per size, with a one-line guess at the growth rate.
"""

import math
import random
import statistics
import sys
import time
import traceback
import types

from . import emit_json

MAXIMUM_FRAMES = 600
MAXIMUM_LINES = 400_000
CHECK_LINES = 1_000_000


class Stop(BaseException):
    """Raised from the tracer. BaseException, so `except Exception` in the learner's code cannot swallow it."""

    def __init__(self, reason):
        super().__init__(reason)
        self.reason = reason


class LabError(Exception):
    """A problem with the learner's file the lab can explain in one sentence."""


def failure(error, filename):
    """The error and the line of the learner's file it came from."""
    if isinstance(error, LabError):
        return str(error)
    line = ""
    for frame in reversed(traceback.extract_tb(error.__traceback__)):
        if frame.filename == filename:
            line = f" (line {frame.lineno}: {(frame.line or '').strip()})"
            break
    if isinstance(error, RecursionError):
        return f"RecursionError: the recursion went too deep{line}. Is there a base case it always reaches?"
    text = str(error.args[0]) if isinstance(error, KeyError) and error.args else str(error)
    return f"{type(error).__name__}: {text}{line}"


def short(value, limit=28):
    text = value if isinstance(value, str) else repr(value)
    return text if len(text) <= limit else text[: limit - 1] + "…"


# Panels. Each is a plain dict the app draws; "roles" colour cells:
# now (the thing this step touched), done, seen, bad, dim, focus.


def array(cells, title=None, roles=None, pointers=None, window=None, caption=None, offset=0):
    cells = [c if isinstance(c, str) else short(c, 8) for c in cells]
    return {
        "type": "array", "title": title, "caption": caption, "cells": cells, "offset": offset,
        "roles": roles or [""] * len(cells),
        "pointers": [{"name": name, "index": index} for name, index in (pointers or [])],
        "window": list(window) if window else None,
    }


def tree(nodes, title=None, binary=False, caption=None):
    """nodes: dicts with id, label, parent (id or None), side ("L"/"R" for binary trees), role, note."""
    return {"type": "tree", "title": title, "caption": caption, "binary": binary, "nodes": nodes}


def grid(cells, roles=None, title=None, caption=None):
    rows = [[c if isinstance(c, str) else short(c, 4) for c in row] for row in cells]
    return {"type": "grid", "title": title, "caption": caption, "grid": rows,
            "gridRoles": roles or [[""] * len(row) for row in rows]}


def stack(items, title=None, roles=None, horizontal=False, ends=None, caption=None):
    items = [i if isinstance(i, str) else short(i, 14) for i in items]
    return {"type": "stack", "title": title, "caption": caption, "cells": items,
            "roles": roles or [""] * len(items), "horizontal": horizontal, "ends": ends or []}


def chain(nodes, pointers, title=None, caption=None):
    return {"type": "chain", "title": title, "caption": caption, "nodes": nodes,
            "pointers": [{"name": name, "node": node} for name, node in pointers]}


def scatter(points, centers=None, lines=None, trails=None, title=None, caption=None, bounds=None, field=None, path=None):
    """points/centers: [x, y, group]; lines: [x1, y1, x2, y2]; trails: lists of [x, y];
    field: rows of 0..1 values drawn as a heat map under everything (row 0 at the top);
    bounds: [xmin, xmax, ymin, ymax]; path: [x, y] points joined in order."""
    return {"type": "scatter", "title": title, "caption": caption, "points": points,
            "centers": centers or [], "lines": lines or [], "trails": trails or [],
            "bounds": bounds, "field": field, "path": path or []}


def plot(series, title=None, caption=None):
    return {"type": "plot", "title": title, "caption": caption,
            "series": [{"name": name, "points": points} for name, points in series]}


def variables(pairs, title=None):
    return {"type": "vars", "title": title, "pairs": [[str(k), short(v, 40)] for k, v in pairs]}


class View:
    """What a render function sees after one line of the learner's code."""

    def __init__(self, frame, line, text, event, value):
        self.frame = frame
        self.locals = dict(frame.f_locals)
        self.line = line
        self.text = text
        self.event = event
        self.value = value
        self.function = frame.f_code.co_name

    def stack(self, filename):
        frames = []
        frame = self.frame
        while frame is not None:
            if frame.f_code.co_filename == filename:
                frames.append(frame)
            frame = frame.f_back
        return list(reversed(frames))


class Recorder:
    def __init__(self, source, filename):
        self.filename = filename
        self.source_lines = source.splitlines()
        self.frames = []
        self.lines = 0
        self.truncated = False
        self._last = None
        self.context = ""

    def add(self, panels, note="", line=None):
        if self._last == panels and line is None:
            return
        if len(self.frames) >= MAXIMUM_FRAMES:
            self.truncated = True
            return
        self._last = panels
        text = self.source_lines[line - 1].strip() if line and 0 < line <= len(self.source_lines) else ""
        self.frames.append({"note": note, "line": line, "code": text, "panels": panels, "context": self.context})

    def snapshot(self, panels, note=""):
        """A frame from the lab itself, between calls."""
        if self._last == panels:
            return
        self._last = None
        self.add(panels, note)
        self.frames[-1]["line"] = None

    def watch(self, call, render):
        """Runs call() with a line tracer. render(view) gives (panels, note) or None to skip the line."""
        filename = self.filename
        last_line = {}

        def emit(frame, line, event, value):
            drawn = render(View(frame, line, self.source_lines[line - 1].strip() if 0 < line <= len(self.source_lines) else "", event, value))
            if drawn:
                panels, note = drawn
                if panels == self._last:
                    return
                if len(self.frames) >= MAXIMUM_FRAMES:
                    self.truncated = True
                    return
                self._last = panels
                self.frames.append({"note": note, "line": line, "code": self.source_lines[line - 1].strip() if 0 < line <= len(self.source_lines) else "", "panels": panels, "context": self.context})

        def local(frame, event, arg):
            if event == "line":
                self.lines += 1
                if self.lines > MAXIMUM_LINES:
                    raise Stop(f"Ran over {MAXIMUM_LINES:,} lines without finishing. Is there a loop that never ends?")
                previous = last_line.get(frame)
                last_line[frame] = frame.f_lineno
                if previous:
                    emit(frame, previous, "line", None)
            elif event == "return":
                previous = last_line.pop(frame, None)
                if previous:
                    emit(frame, previous, "return", arg)
            return local

        def outer(frame, event, arg):
            if frame.f_code.co_filename != filename:
                return None
            return local

        sys.settrace(outer)
        try:
            return call()
        finally:
            sys.settrace(None)


def guarded(call, filename, limit=CHECK_LINES):
    """Runs call() and stops it if the learner's code runs too many lines, for checks."""
    count = [0]

    def local(frame, event, arg):
        if event == "line":
            count[0] += 1
            if count[0] > limit:
                raise Stop("ran too long without finishing. Is there a loop that never ends?")
        return local

    def outer(frame, event, arg):
        return local if frame.f_code.co_filename == filename else None

    sys.settrace(outer)
    try:
        return call()
    finally:
        sys.settrace(None)


def load(source, filename, names, inject=None):
    module = types.ModuleType(filename.rsplit(".", 1)[0])
    module.__dict__.update(inject or {})
    exec(compile(source, filename, "exec"), module.__dict__)
    for name, signature in names:
        if name not in module.__dict__:
            raise LabError(f"Define {signature}.")
    return module.__dict__


# Running a lab


LABS = {}


def register(lab_id, variants):
    LABS[lab_id] = variants


MODULES = {
    "binsearch": "labs_basics", "window": "labs_basics", "stackqueue": "labs_basics", "recursion": "labs_basics",
    "linkedlist": "labs_structures", "bst": "labs_structures", "heap": "labs_structures", "trie": "labs_structures",
    "unionfind": "labs_structures", "lru": "labs_structures",
    "queens": "labs_algorithms", "matching": "labs_algorithms", "flood": "labs_algorithms",
    "descent": "labs_ml", "kmeans": "labs_ml",
}


def spec(lab_id, variant):
    if lab_id not in LABS and lab_id in MODULES:
        import importlib

        importlib.import_module(f"{__package__}.{MODULES[lab_id]}")
    variants = LABS.get(lab_id)
    if not variants:
        raise LabError(f"There is no lab called {lab_id}.")
    return variants.get(variant) or next(iter(variants.values()))


def run(job):
    """Trace the learner's code once, then run the checks. Emits lab_frames."""
    lab_id, variant = job.get("lab", ""), job.get("variant", "")
    payload = {"id": job["id"], "lab": lab_id, "variant": variant, "frames": [], "checks": [],
               "correct": False, "message": "", "truncated": False}
    try:
        lab = spec(lab_id, variant)
        filename = lab["file"]
        recorder = Recorder(job["source"], filename)
        payload["frames"] = recorder.frames
        try:
            namespace = load(job["source"], filename, lab["names"], lab.get("inject", {}).copy())
        except SyntaxError as error:
            raise LabError(f"SyntaxError on line {error.lineno}: {error.msg}") from None
        except LabError:
            raise
        except Exception as error:
            raise LabError(failure(error, filename)) from None
        traced = ""
        try:
            traced = lab["trace"](namespace, recorder) or ""
        except Stop as stop:
            traced = stop.reason
            payload["truncated"] = True
        except Exception as error:
            traced = failure(error, filename)
        checks = []
        if traced:
            checks.append({"name": "the traced run", "ok": False, "message": traced})
        for name, check in lab["checks"]:
            try:
                message = guarded(lambda: check(namespace), filename)
            except Stop as stop:
                message = f"{name}: {stop.reason}"
            except Exception as error:
                message = failure(error, filename)
            checks.append({"name": name, "ok": not message, "message": message or ""})
        payload["checks"] = checks
        payload["truncated"] = payload["truncated"] or recorder.truncated
        payload["correct"] = all(check["ok"] for check in checks)
        payload["message"] = next((check["message"] for check in checks if not check["ok"]), "")
    except LabError as error:
        payload["message"] = str(error)
        payload["checks"] = [{"name": "load", "ok": False, "message": str(error)}]
    except Stop as stop:
        payload["message"] = stop.reason
    emit_json("lab_frames", payload)


# How it scales


def describe_growth(points, step="double"):
    """One plain sentence about how the time grew, from (size, ms) points."""
    usable = [(n, ms) for n, ms in points if ms > 0.002 and n > 0]
    if len(usable) < 3:
        return "Too few sizes finished to see a trend. Try again, or make the code faster first."
    tail = usable[-4:]
    xs = [math.log(n) for n, _ in tail]
    ys = [math.log(ms) for _, ms in tail]
    mean_x, mean_y = statistics.fmean(xs), statistics.fmean(ys)
    spread = sum((x - mean_x) ** 2 for x in xs)
    slope = sum((x - mean_x) * (y - mean_y) for x, y in zip(xs, ys)) / spread if spread else 0
    first, last = usable[0], usable[-1]
    if step == "add" or slope > 3.6:
        steps = max(1, len(usable) - 1)
        per = (last[1] / first[1]) ** (1 / steps)
        gap = (last[0] - first[0]) / steps
        if per > 1.6 and slope > 3.0:
            return (f"Each +{gap:g} on the input multiplied the time by about ×{per:.1f}. "
                    "Growth that multiplies like this looks exponential.")
    ratio = 2 ** slope
    if slope < 0.3:
        shape = "barely changes the time"
        guess = "looks like log n (or constant)"
    elif slope < 0.8:
        shape = f"multiplies the time by about ×{ratio:.1f}"
        guess = "grows slower than n, somewhere above log n"
    elif slope < 1.35:
        shape = f"roughly doubles the time (×{ratio:.1f})"
        guess = "looks like n, or n log n"
    elif slope < 1.75:
        shape = f"multiplies the time by about ×{ratio:.1f}"
        guess = "somewhere between n and n²"
    elif slope < 2.5:
        shape = f"roughly quadruples the time (×{ratio:.1f})"
        guess = "looks like n²"
    elif slope < 3.6:
        shape = f"multiplies the time by about ×{ratio:.1f}"
        guess = "looks like n³"
    else:
        shape = f"multiplies the time by about ×{ratio:.0f}"
        guess = "grows faster than any small power of n"
    return f"Doubling n {shape}: {guess}."


def time_call(call, minimum_runs=3, target_ms=40, maximum_runs=25):
    """The median of several runs. Fast calls run more times so the clock can see them."""
    samples = []
    total = 0.0
    while len(samples) < maximum_runs and (len(samples) < minimum_runs or total < target_ms):
        prepared = call()
        started = time.perf_counter()
        prepared()
        elapsed = (time.perf_counter() - started) * 1000
        samples.append(elapsed)
        total += elapsed
        if elapsed > 300:
            break
    return statistics.median(samples), len(samples)


def scale(job_id, lab_id, variant, what, x_label, sizes, series, check=None, step="double",
          budget=6.0, size_limit_ms=900, footnote=""):
    """series: [(name, prepare(n) -> callable)]; the first is the learner's.

    check(n) gives an error message for the learner's code at size n, or None.
    """
    deadline = time.perf_counter() + budget
    rows = [{"name": name, "points": [], "runs": 0, "ok": True, "message": ""} for name, _ in series]
    stopped = ""
    for n in sizes:
        if time.perf_counter() > deadline:
            stopped = f"Stopped before n = {n:,}: the time budget for this run ran out."
            break
        if check is not None:
            message = check(n)
            if message:
                rows[0]["ok"], rows[0]["message"] = False, message
                stopped = f"Stopped at n = {n:,}: {message}"
                break
        slow = False
        for row, (_, prepare) in zip(rows, series):
            if not row["ok"] or row.get("done"):
                continue
            try:
                median, runs = time_call(lambda: prepare(n))
            except RecursionError:
                row["ok"], row["message"] = False, f"RecursionError at n = {n:,}: the recursion went too deep."
                stopped = row["message"]
                continue
            except Exception as error:
                row["ok"], row["message"] = False, f"{type(error).__name__} at n = {n:,}: {error}"
                stopped = row["message"]
                continue
            row["points"].append([n, median])
            row["runs"] = max(row["runs"], runs)
            if median > size_limit_ms:
                if row is rows[0]:
                    slow = True
                else:
                    row["done"] = True
        if slow:
            stopped = f"Stopped growing after n = {n:,}: one run took over {size_limit_ms / 1000:.1f} s."
            break
        if not rows[0]["ok"]:
            break
    for row in rows:
        row.pop("done", None)
    takeaway = describe_growth([tuple(p) for p in rows[0]["points"]], step) if rows[0]["ok"] or len(rows[0]["points"]) >= 3 else ""
    runs = max((row["runs"] for row in rows), default=0)
    emit_json(
        "lab_scale",
        {
            "id": job_id, "lab": lab_id, "variant": variant, "what": what, "x": x_label,
            "runs": runs, "series": rows, "takeaway": takeaway, "stopped": stopped, "footnote": footnote,
        },
    )


def run_scale(job):
    lab_id, variant = job.get("lab", ""), job.get("variant", "")
    try:
        lab = spec(lab_id, variant)
        filename = lab["file"]
        try:
            namespace = load(job["source"], filename, lab["names"], lab.get("inject", {}).copy())
        except SyntaxError as error:
            raise LabError(f"SyntaxError on line {error.lineno}: {error.msg}") from None
        except LabError:
            raise
        except Exception as error:
            raise LabError(failure(error, filename)) from None
        plan = lab["scale"](namespace)
        sizes = job.get("sizes") or plan["sizes"]
        scale(job["id"], lab_id, variant, plan["what"], plan.get("x", "n"), sizes, plan["series"],
              check=plan.get("check"), step=plan.get("step", "double"), budget=job.get("budget", plan.get("budget", 6.0)),
              footnote=plan.get("footnote", ""))
    except LabError as error:
        emit_json("lab_scale", {"id": job["id"], "lab": lab_id, "variant": variant, "what": "", "x": "n", "runs": 0,
                                "series": [], "takeaway": "", "stopped": str(error), "footnote": ""})


def rng(seed=7):
    return random.Random(seed)


# Instrumented values the learner's code receives


class CountingList(list):
    """A list that counts reads and remembers which indexes the last steps touched."""

    def __init__(self, values=()):
        super().__init__(values)
        self.reads = 0
        self.writes = 0
        self.touched = []
        self.limit = None

    def _over(self):
        if self.limit is not None and self.reads > self.limit:
            raise Stop("read budget")

    def _index(self, index):
        return index if index >= 0 else len(self) + index

    def __getitem__(self, index):
        value = super().__getitem__(index)
        if isinstance(index, int):
            self.reads += 1
            self.touched.append(("r", self._index(index)))
            if len(self.touched) > 512:
                del self.touched[:256]
        else:
            self.reads += len(value)
        self._over()
        return value

    def __setitem__(self, index, value):
        super().__setitem__(index, value)
        if isinstance(index, int):
            self.writes += 1
            self.touched.append(("w", self._index(index)))

    def __iter__(self):
        for index in range(len(self)):
            self.reads += 1
            self.touched.append(("r", index))
            yield list.__getitem__(self, index)

    def take(self):
        touched, self.touched = self.touched, []
        return touched

    def plain(self):
        return list(list.__iter__(self))


class CountingStr(str):
    """A string that counts how many characters were read and remembers the last ones."""

    def __new__(cls, value):
        made = super().__new__(cls, value)
        made.reads = 0
        made.touched = []
        return made

    def __getitem__(self, index):
        value = str.__getitem__(self, index)
        if isinstance(index, int):
            self.reads += 1
            self.touched.append(index if index >= 0 else len(self) + index)
            if len(self.touched) > 512:
                del self.touched[:256]
        else:
            self.reads += len(value)
        return value

    def __iter__(self):
        for index in range(len(self)):
            self.reads += 1
            self.touched.append(index)
            yield str.__getitem__(self, index)

    def take(self):
        touched, self.touched = self.touched, []
        return touched


LEFT_NAMES = ("lo", "low", "left", "l", "start", "begin")
RIGHT_NAMES = ("hi", "high", "right", "r", "end", "stop")
MIDDLE_NAMES = ("mid", "middle", "m")
INDEX_NAMES = ("i", "j", "k", "index", "idx", "pos")


def first_int(values, names):
    for name in names:
        value = values.get(name)
        if isinstance(value, int) and not isinstance(value, bool):
            return name, value
    return None, None


def pointers(values, length, names):
    found = []
    for name in names:
        value = values.get(name)
        if isinstance(value, int) and not isinstance(value, bool) and -1 <= value <= length:
            found.append((name, value))
    return found


def wrap_recursion(namespace, name, on_call, on_return, limit=150):
    """Routes recursive calls through the module global so each one is seen."""
    inner = namespace[name]
    count = [0]

    def counted(*args):
        count[0] += 1
        if count[0] > limit:
            raise Stop(f"Made over {limit} calls on a small input. Does every call get closer to the base case?")
        token = on_call(args)
        result = inner(*args)
        on_return(token, result)
        return result

    namespace[name] = counted
    return counted, lambda: namespace.__setitem__(name, inner)
