"""Dynamic Programming. Calls and table writes are recorded while the user's code runs."""

import collections
import functools
import time
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
        words = "abcdefghijklmnopqrstuvwx"
        return [(words[:size], words[size // 3 : size + size // 3]) for size in range(2, 26, 3)]
    if problem == "coins":
        return [(amount,) for amount in range(5, 160, 15)]
    return [(n,) for n in range(4, 64, 4)]


def measure(job):
    problem = job.get("problem", "stairs")
    rows = []
    stopped = ""
    budget = time.perf_counter() + job.get("budgetSeconds", 4)
    for args in _sizes(problem):
        writes = []
        module, name, _ = _load(job["source"], problem, writes)
        calls, depth = [], [0, 0]
        counted, _ = _instrument(module, name, calls, depth)
        started = time.perf_counter()
        try:
            result = counted(*args)
        except _Stop:
            stopped = f"Stopped at {_call(name, args)}: over {MAXIMUM_CALLS:,} calls."
            break
        except RecursionError:
            stopped = f"Stopped at {_call(name, args)}: recursion went too deep."
            break
        except Exception as error:
            stopped = describe_failure(error, "dp.py")
            break
        elapsed = (time.perf_counter() - started) * 1000
        rows.append({"size": args[0] if len(args) == 1 else len(args[0]), "milliseconds": elapsed, "calls": len(calls), "correct": result == REFERENCE[problem](*args)})
        if time.perf_counter() > budget or elapsed > 1000:
            stopped = "Stopped growing the input: the time budget ran out."
            break
    emit_json("lab_dp_measure", {"id": job["id"], "problem": problem, "rows": rows, "stopped": stopped})
