"""Search and Hashing. Probes are counted by the keys themselves, whatever the table does."""

import random
import statistics
import time
import types

from . import emit_json
from .labs import describe_failure

WORKLOADS = ("words", "sequential", "random", "colliding")


class Key:
    """Hashes like the value it wraps and counts every comparison the table makes."""

    __slots__ = ("value", "_counter")

    def __init__(self, value, counter):
        self.value = value
        self._counter = counter

    def __hash__(self):
        return hash(self.value)

    def __eq__(self, other):
        self._counter[0] += 1
        return self.value == (other.value if isinstance(other, Key) else other)

    def __repr__(self):
        return repr(self.value)


def _keys(workload, count, buckets):
    generator = random.Random(5)
    if workload == "sequential":
        return list(range(count))
    if workload == "random":
        return generator.sample(range(count * 50), count)
    if workload == "colliding":
        # Integers hash to themselves, so multiples of the bucket count share one bucket
        # under hash(key) % len(buckets).
        return [index * buckets for index in range(count)]
    letters = "abcdefghijklmnopqrstuvwxyz"
    words = set()
    while len(words) < count:
        words.add("".join(generator.choice(letters) for _ in range(generator.randint(3, 8))))
    return sorted(words)


def _load(source):
    module = types.ModuleType("table")
    exec(compile(source, "table.py", "exec"), module.__dict__)
    cls = module.__dict__.get("Table")
    if not isinstance(cls, type):
        raise ValueError("Define a class called Table with put(key, value) and get(key).")
    return cls


def _occupancy(table):
    buckets = getattr(table, "buckets", None)
    if not isinstance(buckets, list):
        return None
    lengths = []
    for bucket in buckets:
        if bucket is None:
            lengths.append(0)
        elif hasattr(bucket, "__len__") and not isinstance(bucket, (str, bytes, tuple)):
            lengths.append(len(bucket))
        else:
            lengths.append(1)
    return lengths


def run(job):
    try:
        _run(job)
    except Exception as error:
        emit_json(
            "lab_hash",
            {
                "id": job["id"], "workload": job.get("workload", "words"), "count": job.get("count", 400),
                "buckets": [], "bucketCount": 0, "longest": 0, "empty": 0, "putProbes": 0,
                "averageProbes": 0, "mostProbes": 0, "tableMs": 0, "dictMs": 0,
                "correct": False, "message": describe_failure(error, "table.py"),
            },
        )


def _run(job):
    cls = _load(job["source"])
    workload = job.get("workload", "words")
    count = job.get("count", 400)
    table = cls()
    initial = _occupancy(table)
    keys = _keys(workload, count, len(initial) if initial else 16)
    counter = [0]
    wrapped = [Key(key, counter) for key in keys]

    started = time.perf_counter()
    for index, key in enumerate(wrapped):
        table.put(key, index)
    put_ms = (time.perf_counter() - started) * 1000
    put_probes = counter[0]

    correct, message = True, ""
    probes = []
    started = time.perf_counter()
    for index, key in enumerate(wrapped):
        before = counter[0]
        try:
            got = table.get(Key(key.value, counter))
        except KeyError:
            got = KeyError
        probes.append(counter[0] - before)
        if got != index and correct:
            correct, message = False, f"get({key.value!r}) gave {'KeyError' if got is KeyError else repr(got)}, expected {index}."
    get_ms = (time.perf_counter() - started) * 1000
    if correct:
        try:
            table.get(Key("not a key", counter))
            correct, message = False, "get() of a missing key should raise KeyError."
        except KeyError:
            pass

    reference = {}
    started = time.perf_counter()
    for index, key in enumerate(keys):
        reference[key] = index
    for key in keys:
        reference[key]
    dict_ms = (time.perf_counter() - started) * 1000

    lengths = _occupancy(table)
    emit_json(
        "lab_hash",
        {
            "id": job["id"],
            "workload": workload,
            "count": count,
            "buckets": lengths[:512] if lengths else [],
            "bucketCount": len(lengths) if lengths else 0,
            "longest": max(lengths) if lengths else 0,
            "empty": lengths.count(0) if lengths else 0,
            "putProbes": put_probes,
            "averageProbes": statistics.fmean(probes) if probes else 0,
            "mostProbes": max(probes) if probes else 0,
            "tableMs": put_ms + get_ms,
            "dictMs": dict_ms,
            "correct": correct,
            "message": message,
        },
    )


def scale(job):
    """How it scales: n puts then n gets on the learner's table and on dict, for one workload."""
    from .labs_engine import scale as run_scale

    workload = job.get("workload", "words")
    try:
        cls = _load(job["source"])
        buckets = len(_occupancy(cls()) or [None] * 16)
    except Exception as error:
        emit_json("lab_scale", {"id": job["id"], "lab": "hash", "variant": workload, "what": "", "x": "keys n", "runs": 0, "series": [],
                                "takeaway": "", "stopped": describe_failure(error, "table.py"), "footnote": ""})
        return

    def mine(n):
        keys = _keys(workload, n, buckets)

        def run():
            table = cls()
            for index, key in enumerate(keys):
                table.put(key, index)
            for key in keys:
                table.get(key)
        return run

    def builtin(n):
        keys = _keys(workload, n, buckets)

        def run():
            table = {}
            for index, key in enumerate(keys):
                table[key] = index
            for key in keys:
                table[key]
        return run

    def check(n):
        keys = _keys(workload, min(n, 200), buckets)
        table = cls()
        for index, key in enumerate(keys):
            table.put(key, index)
        for index, key in enumerate(keys):
            got = table.get(key)
            if got != index:
                return f"get({key!r}) gave {got!r}, expected {index}."
        return None

    footnote = "Colliding keys all land in one bucket, so each get walks a list as long as the table." if workload == "colliding" else ""
    run_scale(job["id"], "hash", workload, f"Puts n {workload} keys into a new table, then gets every one back. dict does the same for comparison.",
              "keys n", job.get("sizes") or [250, 500, 1000, 2000, 4000, 8000, 16000],
              [("your Table", mine), ("dict", builtin)], check=check, footnote=footnote)
