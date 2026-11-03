"""Algorithm labs. Traces come from really running the user's code."""

import random
import statistics
import time
import traceback
import types

from . import emit_json

MAXIMUM_STEPS = 4000


class _Stop(Exception):
    pass


def describe_failure(error, filename):
    """The error and the line of the user's file it came from, for a lab's result card."""
    line = ""
    for frame in reversed(traceback.extract_tb(error.__traceback__)):
        if frame.filename == filename:
            line = f" (line {frame.lineno}: {frame.line or ''})"
            break
    text = str(error.args[0]) if isinstance(error, KeyError) and error.args else str(error)
    return f"{type(error).__name__}: {text}{line}"


class TracedList(list):
    """Records every read and write the user's sort does to this list."""

    def __init__(self, values, steps):
        super().__init__(values)
        self._steps = steps
        self._active = []

    def _record(self, kind, *indexes):
        if len(self._steps) >= MAXIMUM_STEPS:
            raise _Stop
        self._steps.append({"kind": kind, "i": list(indexes), "values": list(self)})

    def __getitem__(self, index):
        value = super().__getitem__(index)
        if isinstance(index, int):
            self._record("read", index if index >= 0 else len(self) + index)
        return value

    def __setitem__(self, index, value):
        super().__setitem__(index, value)
        if isinstance(index, int):
            self._record("write", index if index >= 0 else len(self) + index)

    def sort(self, *args, **kwargs):
        raise TypeError("Write the sort yourself here. list.sort() has no steps to trace.")


def _load(source):
    module = types.ModuleType("bench")
    exec(compile(source, "sort.py", "exec"), module.__dict__)
    function = module.__dict__.get("my_sort")
    if not callable(function):
        raise ValueError("Define a function called my_sort(items) that sorts the list in place.")
    return function


def _inputs(kind, size):
    generator = random.Random(1234)
    values = list(range(size))
    if kind == "random":
        generator.shuffle(values)
    elif kind == "reversed":
        values.reverse()
    elif kind == "duplicates":
        values = [generator.randrange(max(1, size // 10)) for _ in range(size)]
    return values


def trace_sort(job):
    function = _load(job["source"])
    generator = random.Random(job.get("seed", 7))
    values = list(range(5, 5 + job.get("size", 14) * 7, 7))
    generator.shuffle(values)
    steps = [{"kind": "start", "i": [], "values": list(values)}]
    traced = TracedList(values, steps)
    truncated = False
    try:
        function(traced)
    except _Stop:
        truncated = True
    final = list.__iter__(traced)
    final = list(final)
    emit_json(
        "lab_trace",
        {
            "id": job["id"],
            "steps": steps,
            "correct": final == sorted(values),
            "truncated": truncated,
        },
    )


def measure_sort(job):
    function = _load(job["source"])
    size = job.get("size", 2000)
    rows = []
    for name, sorter in (("your sort", function), ("sorted()", None)):
        row = {"name": name, "cells": {}}
        for kind in ("random", "sorted", "reversed", "duplicates"):
            samples = []
            correct = True
            for _ in range(job.get("runs", 5)):
                values = _inputs(kind, size)
                expected = sorted(values)
                started = time.perf_counter()
                if sorter is None:
                    values = sorted(values)
                else:
                    sorter(values)
                samples.append((time.perf_counter() - started) * 1000)
                correct = correct and values == expected
            row["cells"][kind] = {
                "median": statistics.median(samples),
                "spread": max(samples) - min(samples),
                "correct": correct,
            }
        rows.append(row)
    emit_json("lab_measure", {"id": job["id"], "size": size, "rows": rows})
