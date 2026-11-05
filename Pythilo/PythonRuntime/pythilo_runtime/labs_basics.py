"""Basics: binary search, sliding window, stacks and queues, the recursion tree."""

import itertools
import math
import random
from collections import deque

from .labs_engine import (
    LEFT_NAMES, MIDDLE_NAMES, RIGHT_NAMES, CountingList, CountingStr, Stop, array, first_int,
    pointers, register, short, stack, tree, variables, wrap_recursion,
)

# Binary search

SEARCH_ITEMS = [3, 8, 12, 17, 21, 26, 30, 34, 41, 45, 52, 58, 63, 70, 77, 81]


def _search_render(items):
    n = len(items)

    def render(view):
        values = view.locals
        _, lo = first_int(values, LEFT_NAMES)
        _, hi = first_int(values, RIGHT_NAMES)
        _, mid = first_int(values, MIDDLE_NAMES)
        items.take()
        roles = []
        for index in range(n):
            if view.event == "return" and view.value == index:
                roles.append("done")
            elif index == mid:
                roles.append("now")
            elif lo is not None and hi is not None and not (lo <= index <= hi):
                roles.append("dim")
            else:
                roles.append("")
        window = [lo, min(hi, n - 1)] if lo is not None and hi is not None and lo <= hi else None
        plain = items.plain()
        if view.event == "return":
            note = f"returned {view.value!r}" + (f": items[{view.value}] is {plain[view.value]}" if isinstance(view.value, int) and 0 <= view.value < n else "")
        elif lo is not None and hi is not None:
            left = max(0, min(hi, n - 1) - lo + 1)
            note = f"{left} candidate{'s' if left != 1 else ''} left between lo = {lo} and hi = {hi}"
            if mid is not None and 0 <= mid < n:
                note += f"; items[{mid}] = {plain[mid]}"
        else:
            note = ""
        drawn = [array(plain, roles=roles, pointers=pointers(values, n, LEFT_NAMES + MIDDLE_NAMES + RIGHT_NAMES), window=window, title="items")]
        return drawn, note

    return render


def _search_trace(ns, rec):
    function = ns["binary_search"]
    items = CountingList(SEARCH_ITEMS)
    for target in (58, 40):
        rec.context = f"binary_search(items, {target})"
        before = items.reads
        result = rec.watch(lambda: function(items, target), _search_render(items))
        expected = SEARCH_ITEMS.index(target) if target in SEARCH_ITEMS else -1
        if result != expected:
            return f"binary_search(items, {target}) returned {result!r}, expected {expected}."
        rec.add([array(SEARCH_ITEMS, roles=["done" if i == result else "" for i in range(len(SEARCH_ITEMS))], title="items")],
                f"{target}: {'found at index ' + str(result) if result >= 0 else 'not there, returned -1'} after reading {items.reads - before} of {len(SEARCH_ITEMS)} items")
    return ""


def _search_correct(ns):
    function = ns["binary_search"]
    for n in (0, 1, 2, 3, 7, 16, 33):
        items = list(range(0, 2 * n, 2))
        for index, value in enumerate(items):
            got = function(list(items), value)
            if got != index:
                return f"binary_search({short(items, 40)}, {value}) returned {got!r}, expected {index}."
        for value in (-1, 2 * n, 1, 2 * n - 1):
            if value in items:
                continue
            got = function(list(items), value)
            if got != -1:
                return f"binary_search({short(items, 40)}, {value}) returned {got!r}, expected -1: {value} is not in the list."
    return None


def _search_fast(ns):
    function = ns["binary_search"]
    items = CountingList(range(0, 4096, 2))
    worst = 0
    for target in random.Random(3).sample(range(0, 4096, 2), 40):
        before = items.reads
        function(items, target)
        worst = max(worst, items.reads - before)
    budget = 2 * math.ceil(math.log2(len(items))) + 4
    if worst > budget:
        return (f"It finds the right answer, but one search read {worst} of {len(items)} items. "
                f"Halving the range each step needs about {math.ceil(math.log2(len(items)))}.")
    return None


def _search_scale(ns):
    function = ns["binary_search"]
    cache = {}

    def data(n):
        if n not in cache:
            cache.clear()
            generator = random.Random(n)
            cache[n] = (list(range(0, 2 * n, 2)), [generator.randrange(2 * n) for _ in range(300)])
        return cache[n]

    def check(n):
        items, targets = data(n)
        for target in targets[:20]:
            expected = target // 2 if target % 2 == 0 else -1
            if function(items, target) != expected:
                return f"binary_search gave a wrong answer for {target}."
        return None

    def mine(n):
        items, targets = data(n)
        return lambda: [function(items, t) for t in targets]

    return {
        "what": "Runs 300 searches for random numbers in a sorted list of n numbers.",
        "x": "list length n",
        "sizes": [1000 * 2 ** k for k in range(10)],
        "series": [("your binary_search", mine)],
        "check": check,
    }


register("binsearch", {
    "search": {
        "file": "search.py",
        "names": [("binary_search", "a function binary_search(items, target)")],
        "trace": _search_trace,
        "checks": [("finds every item, and -1 for missing ones", _search_correct), ("reads about log n items", _search_fast)],
        "scale": _search_scale,
    },
})

# Sliding window

WINDOW_TEXT = "abracadabra"


def _window_render(text):
    n = len(text)

    def render(view):
        values = view.locals
        _, left = first_int(values, LEFT_NAMES)
        _, right = first_int(values, RIGHT_NAMES + ("i", "j"))
        text.take()
        roles = [""] * n
        window = None
        if left is not None and right is not None and 0 <= left <= right < n:
            window = [left, right]
            for index in range(left, right + 1):
                roles[index] = "seen"
        if right is not None and 0 <= right < n:
            roles[right] = "now"
        best = values.get("best")
        drawn = [array(list(str(text)), roles=roles, pointers=pointers(values, n, LEFT_NAMES + RIGHT_NAMES + ("i", "j")), window=window, title="text")]
        extra = [(name, values[name]) for name in ("best", "seen", "last", "window") if name in values]
        if extra:
            drawn.append(variables(extra))
        if view.event == "return":
            note = f"returned {view.value!r}"
        elif window:
            note = f"window '{text[left:right + 1]}' has {right - left + 1} different character{'s' if right > left else ''}" + (f"; best so far {best}" if best is not None else "")
            text.take()
        else:
            note = ""
        return drawn, note

    return render


def _window_reference(text):
    last, best, left = {}, 0, 0
    for right, ch in enumerate(text):
        if ch in last and last[ch] >= left:
            left = last[ch] + 1
        last[ch] = right
        best = max(best, right - left + 1)
    return best


def _window_trace(ns, rec):
    function = ns["longest_unique"]
    text = CountingStr(WINDOW_TEXT)
    rec.context = f"longest_unique({WINDOW_TEXT!r})"
    result = rec.watch(lambda: function(text), _window_render(text))
    expected = _window_reference(WINDOW_TEXT)
    if result != expected:
        return f"longest_unique({WINDOW_TEXT!r}) returned {result!r}, expected {expected}."
    rec.add([array(list(WINDOW_TEXT), title="text", caption=f"{text.reads} character reads for {len(WINDOW_TEXT)} characters")],
            f"returned {result}: the longest stretch with no repeated character")
    return ""


def _window_correct(ns):
    function = ns["longest_unique"]
    generator = random.Random(4)
    cases = ["", "a", "aaaa", "abcdef", "abba", "pwwkew", "dvdf"] + [
        "".join(generator.choice("abcde") for _ in range(generator.randint(1, 14))) for _ in range(40)
    ]
    for case in cases:
        got = function(case)
        if got != _window_reference(case):
            return f"longest_unique({case!r}) returned {got!r}, expected {_window_reference(case)}."
    return None


def _window_fast(ns):
    function = ns["longest_unique"]
    generator = random.Random(5)
    raw = "".join(chr(0x4E00 + generator.randrange(1500)) for _ in range(3000))
    text = CountingStr(raw)
    got = function(text)
    if got != _window_reference(raw):
        return f"On a 3,000-character text it returned {got}, expected {_window_reference(raw)}."
    if text.reads > 4 * len(raw) + 10:
        return (f"Right answer, but it read {text.reads:,} characters of a {len(raw):,}-character text. "
                "Keep one window: move right one step at a time and only ever move left forward.")
    return None


def _window_scale(ns):
    function = ns["longest_unique"]

    def mine(n):
        text = "".join(chr(0x4E00 + i) for i in range(n))
        return lambda: function(text)

    def check(n):
        text = "".join(chr(0x4E00 + i) for i in range(min(n, 300)))
        got = function(text)
        return None if got == len(text) else f"longest_unique gave {got} for {len(text)} different characters."

    return {
        "what": "Runs on a text of n characters that are all different, the worst case for restarting at every position.",
        "x": "text length n",
        "sizes": [250 * 2 ** k for k in range(9)],
        "series": [("your longest_unique", mine)],
        "check": check,
    }


register("window", {
    "unique": {
        "file": "window.py",
        "names": [("longest_unique", "a function longest_unique(text)")],
        "trace": _window_trace,
        "checks": [("right length on 47 texts", _window_correct), ("reads each character a few times at most", _window_fast)],
        "scale": _window_scale,
    },
})

# Stacks and queues

PAIRS = {")": "(", "]": "[", "}": "{"}


def _balanced(text):
    seen = []
    for ch in text:
        if ch in "([{":
            seen.append(ch)
        elif ch in ")]}":
            if not seen or seen.pop() != PAIRS[ch]:
                return False
    return not seen


def _find_list(values, names):
    for name in names:
        value = values.get(name)
        if isinstance(value, (list, deque)):
            return name, value
    for name, value in values.items():
        if isinstance(value, (list, deque)) and not isinstance(value, (CountingList, CountingStr)):
            return name, value
    return None, None


def _brackets_render(text):
    n = len(text)

    def render(view):
        values = view.locals
        touched = text.take()
        _, at = first_int(values, ("i", "index", "pos", "j"))
        if touched:
            at = touched[-1]
        name, items = _find_list(values, ("stack", "opened", "open_brackets", "seen"))
        cells = list(str(text))
        roles = ["dim" if at is not None and index < at else "" for index in range(n)]
        if at is not None and 0 <= at < n:
            roles[at] = "now"
        drawn = [array(cells, roles=roles, title="text")]
        items = list(items) if items is not None else []
        drawn.append(stack(items, title=name or "stack", roles=["now" if i == len(items) - 1 else "" for i in range(len(items))], ends=["bottom", "top"]))
        if view.event == "return":
            note = f"returned {view.value!r}"
        elif at is not None and 0 <= at < n:
            note = f"read '{text[at]}'; the stack holds {len(items)}"
            text.take()
        else:
            note = ""
        return drawn, note

    return render


def _brackets_trace(ns, rec):
    function = ns["balanced"]
    for case in ("{[()()]}", "([)]"):
        rec.context = f"balanced({case!r})"
        text = CountingStr(case)
        result = rec.watch(lambda: function(text), _brackets_render(text))
        if result != _balanced(case):
            return f"balanced({case!r}) returned {result!r}, expected {_balanced(case)}." + BRACKET_HINTS.get(case, "")
        rec.add([array(list(case), roles=["done" if result else "bad"] * len(case), title="text")],
                f"balanced({case!r}) is {result}")
    return ""


BRACKET_HINTS = {
    "(]": " A count of open brackets cannot tell ( from [: remember which ones are open.",
    "([)]": " The last bracket opened has to be the first one closed.",
    "))((": " A closing bracket with nothing open is already wrong.",
}


def _brackets_correct(ns):
    function = ns["balanced"]
    cases = ["", "()", "[]{}()", "([]{})", "{[()()]}", "a(b[c]d)e", "(]", "([)]", "((", "))((", "}{", "(()", "())", "[(])", "{[}]"]
    for case in cases:
        got = function(case)
        if got != _balanced(case):
            return f"balanced({case!r}) returned {got!r}, expected {_balanced(case)}." + BRACKET_HINTS.get(case, "")
    return None


def _brackets_scale(ns):
    function = ns["balanced"]

    def mine(n):
        text = "([{" * (n // 6) + "}])" * (n // 6)
        return lambda: function(text)

    return {
        "what": "Checks a text of n nested brackets, all of them balanced.",
        "x": "text length n",
        "sizes": [1000 * 2 ** k for k in range(9)],
        "series": [("your balanced", mine)],
        "check": lambda n: None if function("([{" * 5 + "}])" * 5) is True else "balanced said a balanced text was not.",
    }


def _potato(names, k):
    queue = deque(names)
    out = []
    while queue:
        queue.rotate(-k)
        out.append(queue.popleft())
    return out


POTATO = ["Ada", "Bo", "Cy", "Di", "Ed", "Flo", "Gus"]


def _potato_render(view):
    values = view.locals
    name, items = _find_list(values, ("queue", "circle", "line", "players", "q"))
    out = values.get("out") or values.get("order") or values.get("result")
    items = list(items) if items is not None else []
    drawn = [stack(items, title=f"{name or 'queue'}: front on the left", horizontal=True,
                   roles=["now" if i == 0 else "" for i in range(len(items))], ends=["front", "back"])]
    if isinstance(out, list):
        drawn.append(stack(list(out), title="out, in order", horizontal=True, roles=["bad"] * len(out)))
    if view.event == "return":
        note = f"returned {short(view.value, 60)}"
    elif items:
        note = f"{items[0]} holds the potato; {len(items)} still playing"
    else:
        note = ""
    return drawn, note


def _potato_trace(ns, rec):
    function = ns["hot_potato"]
    rec.context = f"hot_potato({POTATO!r}, 3)"
    result = rec.watch(lambda: function(list(POTATO), 3), _potato_render)
    expected = _potato(POTATO, 3)
    if result != expected:
        return f"hot_potato(names, 3) returned {short(result, 70)}, expected {expected}."
    return ""


def _potato_correct(ns):
    function = ns["hot_potato"]
    for count in range(1, 9):
        for k in range(0, 5):
            names = [f"p{i}" for i in range(count)]
            got = function(list(names), k)
            if got != _potato(names, k):
                return f"hot_potato({names}, {k}) returned {short(got, 60)}, expected {_potato(names, k)}."
    return None


def _potato_scale(ns):
    function = ns["hot_potato"]

    def mine(n):
        names = list(range(n))
        return lambda: function(names, 3)

    return {
        "what": "Plays hot potato with n players, passing 3 times each round, until everyone is out.",
        "x": "players n",
        "sizes": [500 * 2 ** k for k in range(9)],
        "series": [("your hot_potato", mine)],
        "check": lambda n: None if function(list(range(9)), 3) == _potato(list(range(9)), 3) else "hot_potato gave a wrong order.",
    }


register("stackqueue", {
    "brackets": {
        "file": "brackets.py",
        "names": [("balanced", "a function balanced(text)")],
        "trace": _brackets_trace,
        "checks": [("15 texts, balanced and not", _brackets_correct)],
        "scale": _brackets_scale,
    },
    "queue": {
        "file": "potato.py",
        "names": [("hot_potato", "a function hot_potato(names, k)")],
        "inject": {"deque": deque},
        "trace": _potato_trace,
        "checks": [("every circle from 1 to 8 players", _potato_correct)],
        "scale": _potato_scale,
    },
})

# The recursion tree


def _call_tree(rec, ns, name, label, result_label, args):
    nodes, active = [], []

    def draw(note):
        drawn_nodes = []
        for node in nodes:
            role = "now" if active and node["id"] == active[-1] else "focus" if node["id"] in active else "done" if node.get("note") is not None else ""
            drawn_nodes.append({**node, "role": role})
        calls = [next(n["label"] for n in nodes if n["id"] == i) for i in active]
        rec.add([tree(drawn_nodes, title="calls"),
                 stack(calls, title="call stack", roles=["now" if i == len(calls) - 1 else "focus" for i in range(len(calls))], ends=["first call", "running now"])],
                note)

    def on_call(call_args):
        node = {"id": f"c{len(nodes)}", "label": label(*call_args), "parent": active[-1] if active else None, "note": None}
        nodes.append(node)
        active.append(node["id"])
        draw(f"call {node['label']}, {len(active)} deep")
        return node

    def on_return(node, value):
        node["note"] = result_label(value)
        draw(f"{node['label']} returns {node['note']}")
        active.pop()

    counted, restore = wrap_recursion(ns, name, on_call, on_return)
    try:
        return counted(*args), len(nodes)
    finally:
        restore()


def _perm_label(items):
    return f"perm({short(list(items), 20)})"


def _perm_result(value):
    if isinstance(value, list):
        return f"{len(value)} list{'s' if len(value) != 1 else ''}"
    return short(value, 12)


def _perms_trace(ns, rec):
    rec.context = "permutations([1, 2, 3])"
    result, calls = _call_tree(rec, ns, "permutations", _perm_label, _perm_result, ([1, 2, 3],))
    expected = [list(p) for p in itertools.permutations([1, 2, 3])]
    if not isinstance(result, list) or sorted(map(list, result)) != sorted(expected):
        return f"permutations([1, 2, 3]) returned {short(result, 60)}, expected the 6 orderings like [1, 2, 3], [1, 3, 2]."
    return ""


def _perms_correct(ns):
    function = ns["permutations"]
    for size in range(0, 6):
        items = list("abcdef"[:size])
        got = function(list(items))
        expected = sorted(list(p) for p in itertools.permutations(items))
        if not isinstance(got, list) or sorted(map(list, got)) != expected:
            hint = " The empty list has exactly one ordering: [[]]." if size == 0 or (isinstance(got, list) and not got) else ""
            return f"permutations({items}) returned {short(got, 50)}, expected {len(expected)} orderings.{hint}"
    return None


def _perms_scale(ns):
    function = ns["permutations"]
    return {
        "what": "Builds every ordering of n items.",
        "x": "items n",
        "sizes": list(range(3, 10)),
        "step": "add",
        "series": [("your permutations", lambda n: (lambda: function(list(range(n)))))],
        "check": lambda n: None if len(function(list(range(4)))) == 24 else "permutations gave the wrong number of orderings.",
        "footnote": "n items have n! orderings, so even a perfect answer grows this fast.",
    }


def _sort_label(items):
    return short(list(items), 22)


def _sort_trace(ns, rec):
    values = [38, 27, 43, 3, 9, 82, 10, 5]
    rec.context = f"merge_sort({values})"
    result, _ = _call_tree(rec, ns, "merge_sort", _sort_label, lambda v: short(v, 22), (list(values),))
    if result != sorted(values):
        return f"merge_sort({values}) returned {short(result, 60)}, expected {sorted(values)}."
    return ""


def _sort_correct(ns):
    function = ns["merge_sort"]
    generator = random.Random(8)
    for size in list(range(0, 12)) + [50, 101]:
        items = [generator.randrange(20) for _ in range(size)]
        got = function(list(items))
        if got != sorted(items):
            return f"merge_sort({short(items, 40)}) returned {short(got, 40)}, expected {short(sorted(items), 40)}."
    return None


def _sort_scale(ns):
    function = ns["merge_sort"]

    def data(n):
        generator = random.Random(n)
        return [generator.random() for _ in range(n)]

    def mine(n):
        items = data(n)
        return lambda: function(list(items))

    def builtin(n):
        items = data(n)
        return lambda: sorted(items)

    return {
        "what": "Sorts a list of n random numbers.",
        "x": "list length n",
        "sizes": [1000 * 2 ** k for k in range(8)],
        "series": [("your merge_sort", mine), ("sorted()", builtin)],
        "check": lambda n: None if function(data(50)) == sorted(data(50)) else "merge_sort gave a wrong order.",
    }


register("recursion", {
    "permutations": {
        "file": "permutations.py",
        "names": [("permutations", "a function permutations(items)")],
        "trace": _perms_trace,
        "checks": [("every ordering for 0 to 5 items", _perms_correct)],
        "scale": _perms_scale,
    },
    "mergesort": {
        "file": "merge_sort.py",
        "names": [("merge_sort", "a function merge_sort(items)")],
        "trace": _sort_trace,
        "checks": [("sorts 14 lists", _sort_correct)],
        "scale": _sort_scale,
    },
})
