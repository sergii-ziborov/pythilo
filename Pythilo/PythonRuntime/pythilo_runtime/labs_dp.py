"""Dynamic Programming. Calls and table writes are recorded while the user's code runs."""

import collections
import functools
import time
import sys
import types

from . import emit_json
from .labs import describe_failure

MAXIMUM_CALLS = 200_000
MAXIMUM_WRITES = 3000

PROBLEMS = {
    "stairs": {"function": "ways", "args": (10,)},
    "coins": {"function": "min_coins", "args": (18,)},
    "edit": {"function": "edit_distance", "args": ("kitten", "sitting")},
}


class _Stop(Exception):
    pass


def _call(name, args):
    return f"{name}({', '.join(repr(value) for value in args)})"


@functools.cache
def _ways(n):
    return 1 if n < 2 else _ways(n - 1) + _ways(n - 2)


def _min_coins(amount, coins=(1, 3, 4)):
    best = [0] + [None] * amount
    for value in range(1, amount + 1):
        options = [best[value - coin] for coin in coins if coin <= value and best[value - coin] is not None]
        best[value] = min(options) + 1 if options else None
    return best[amount]


def _edit_distance(a, b):
    row = list(range(len(b) + 1))
    for i, left in enumerate(a, 1):
        previous, row[0] = row[0], i
        for j, right in enumerate(b, 1):
            previous, row[j] = row[j], min(row[j] + 1, row[j - 1] + 1, previous + (left != right))
    return row[-1]


REFERENCE = {"stairs": _ways, "coins": _min_coins, "edit": _edit_distance}


class Table:
    """A grid the user fills. Every write is a step of the trace."""

    def __init__(self, rows, columns, fill, writes):
        self.rows = rows
        self.columns = columns
        self._cells = [[fill] * columns for _ in range(rows)]
        self._writes = writes

    def __getitem__(self, row):
        return _Row(self, row)

    def set(self, row, column, value):
        if len(self._writes) >= MAXIMUM_WRITES:
            raise _Stop
        self._cells[row][column] = value
        self._writes.append([row, column, value if isinstance(value, (int, float)) and not isinstance(value, bool) else None])

    def get(self, row, column):
        return self._cells[row][column]


class _Row:
    __slots__ = ("_table", "_row")

    def __init__(self, table, row):
        self._table = table
        self._row = row

    def __getitem__(self, column):
        return self._table.get(self._row, column)

    def __setitem__(self, column, value):
        self._table.set(self._row, column, value)

    def __len__(self):
        return self._table.columns


def _load(source, problem, tables):
    module = types.ModuleType("dp")
    shape = {}

    def table(rows, columns=1, fill=0):
        if shape:
            raise ValueError("Make one table per run.")
        made = Table(rows, columns, fill, tables)
        shape["rows"], shape["columns"] = rows, columns
        return made

    module.__dict__["table"] = table
    exec(compile(source, "dp.py", "exec"), module.__dict__)
    name = PROBLEMS[problem]["function"]
    if not callable(module.__dict__.get(name)):
        raise ValueError(f"Define a function called {name}.")
    return module, name, shape


def _instrument(module, name, calls, depth):
    """Calls go through the module global, so recursion is counted call by call."""
    inner = module.__dict__[name]

    @functools.wraps(inner)
    def counted(*args):
        if len(calls) >= MAXIMUM_CALLS:
            raise _Stop
        calls.append(args)
        depth[0] += 1
        depth[1] = max(depth[1], depth[0])
        try:
            return inner(*args)
        finally:
            depth[0] -= 1

    module.__dict__[name] = counted
    return counted, inner


def trace(job):
    problem = job.get("problem", "stairs")
    writes = []
    module, name, shape = _load(job["source"], problem, writes)
    calls, depth = [], [0, 0]
    counted, inner = _instrument(module, name, calls, depth)
    args = tuple(job.get("args") or PROBLEMS[problem]["args"])
    expected = REFERENCE[problem](*args)
    truncated = False
    failure = ""
    result = None
    started = time.perf_counter()
    try:
        result = counted(*args)
    except _Stop:
        truncated = True
    except Exception as error:
        failure = describe_failure(error, "dp.py")
    elapsed = (time.perf_counter() - started) * 1000
    tally = collections.Counter(calls)
    cache = getattr(inner, "cache_info", None)
    info = cache() if callable(cache) else None
    if failure:
        correct, message = False, failure
    elif truncated:
        correct, message = False, "Stopped recording: the run made too many calls or writes."
    elif result != expected:
        correct, message = False, f"{_call(name, args)} returned {result!r}, expected {expected!r}."
    else:
        correct, message = True, ""
    emit_json(
        "lab_dp_trace",
        {
            "id": job["id"],
            "problem": problem,
            "call": _call(name, args),
            "result": repr(result),
            "expected": repr(expected),
            "correct": correct,
            "message": message,
            "truncated": truncated,
            "milliseconds": elapsed,
            "calls": len(calls),
            "distinct": len(tally),
            "deepest": depth[1],
            "repeated": [{"args": _call(name, key), "count": count} for key, count in tally.most_common(6) if count > 1],
            "cacheHits": info.hits if info else None,
            "cacheMisses": info.misses if info else None,
            "rows": shape.get("rows", 0),
            "columns": shape.get("columns", 0),
            "writes": writes,
        },
    )


def _sizes(problem):
    if problem == "edit":
        words = "abcdefghijklmnopqrstuvwxyz" * 20
        return [(words[:size], words[size // 3 : size + size // 3]) for size in (4, 8, 16, 32, 64, 128, 256)]
    if problem == "coins":
        return [(amount,) for amount in (8, 12, 16, 20, 24, 32, 64, 128, 256, 512)]
    return [(n,) for n in (8, 12, 16, 20, 24, 28, 32, 64, 128, 256, 512)]


class _NoWrites(list):
    """Timing runs keep no trace of table writes."""

    def append(self, item):
        pass


def scale(job):
    """How it scales: the learner's function on growing inputs, a fresh copy of their file each run."""
    from .labs_engine import scale as run_scale

    problem = job.get("problem", "stairs")
    try:
        _load(job["source"], problem, [])
    except Exception as error:
        emit_json("lab_scale", {"id": job["id"], "lab": "dp", "variant": problem, "what": "", "x": "n", "runs": 0, "series": [],
                                "takeaway": "", "stopped": describe_failure(error, "dp.py"), "footnote": ""})
        return
    by_size = {(args[0] if len(args) == 1 else len(args[0])): args for args in _sizes(problem)}

    def fresh(n):
        # A new module each time, so a cache from the last run cannot answer for free.
        module, name, _ = _load(job["source"], problem, _NoWrites())
        function = module.__dict__[name]
        args = by_size[n]
        return lambda: function(*args)

    def check(n):
        module, name, _ = _load(job["source"], problem, _NoWrites())
        function = module.__dict__[name]
        args = by_size[n]
        # Validate before timing. A fast device can reach n=32 cheaply and then
        # jump into an exponential n=64 call; a budget checked between sizes
        # cannot stop that individual call. Keep this guard out of measurements.
        previous = sys.gettrace()
        deadline = time.perf_counter() + 0.5
        steps = 0

        def bounded(frame, event, arg):
            nonlocal steps
            if event == "line" and frame.f_code.co_filename == "dp.py":
                steps += 1
                if steps > 250_000 or time.perf_counter() > deadline:
                    raise _Stop
            return bounded

        try:
            sys.settrace(bounded)
            try:
                result = function(*args)
            finally:
                sys.settrace(previous)
        except _Stop:
            return "The validation work limit was reached. Use a faster algorithm or a smaller input."
        except RecursionError:
            return f"{_call(name, args)} recursed too deep."
        except Exception as error:
            return describe_failure(error, "dp.py")
        expected = REFERENCE[problem](*args)
        return None if result == expected else f"{_call(name, args)} returned {result!r}, expected {expected!r}."

    what = {
        "stairs": "Calls ways(n) for growing n, with a fresh copy of your file each run so no cache carries over.",
        "coins": "Calls min_coins(amount) for growing amounts, with a fresh copy of your file each run.",
        "edit": "Calls edit_distance on two words of length n, with a fresh copy of your file each run.",
    }[problem]
    sizes = sorted(by_size) if not job.get("sizes") else [n for n in sorted(by_size) if n in job["sizes"]]
    run_scale(job["id"], "dp", problem, what, "length n" if problem == "edit" else "n", sizes,
              [("your " + PROBLEMS[problem]["function"], fresh)], check=check)
