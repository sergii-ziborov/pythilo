"""Algorithms: backtracking (N-Queens), string matching (naive and KMP), flood fill and islands."""

import random
from collections import deque

from .labs_engine import CountingStr, array, grid, register, short, stack, variables

# N-Queens

QUEEN_COUNTS = {1: 1, 2: 0, 3: 0, 4: 2, 5: 10, 6: 4, 7: 40}


def _queens_list(values):
    for name in ("queens", "cols", "columns", "board", "placed", "positions"):
        value = values.get(name)
        if isinstance(value, list) and all(isinstance(c, int) and not isinstance(c, bool) for c in value):
            return value
    return None


def _attacked(queens, n):
    cells = set()
    for row, col in enumerate(queens):
        for other in range(n):
            cells.add((other, col))
            for step in (-1, 1):
                diagonal = col + step * (other - row)
                if 0 <= diagonal < n:
                    cells.add((other, diagonal))
    return cells


def _queens_render(n, state):
    def render(view):
        values = view.locals
        queens = _queens_list(values)
        if queens is None:
            return None
        queens = [c for c in queens[:n]]
        attacked = _attacked(queens, n)
        trying = values.get("col") if view.function != "solve" or "row" in values else None
        try_row = len(queens)
        cells, roles = [], []
        for row in range(n):
            cells.append(["♛" if row < len(queens) and queens[row] == col else "" for col in range(n)])
            line = []
            for col in range(n):
                if row < len(queens) and queens[row] == col:
                    line.append("now" if row == len(queens) - 1 else "done")
                elif row == try_row and col == trying and isinstance(trying, int):
                    line.append("bad" if (row, col) in attacked else "focus")
                elif (row, col) in attacked and row >= len(queens):
                    line.append("dim")
                else:
                    line.append("")
            roles.append(line)
        solutions = values.get("solutions") or values.get("result") or values.get("found")
        count = len(solutions) if isinstance(solutions, list) else state["solutions"]
        state["solutions"] = count
        drawn = [grid(cells, roles, title=f"{n} × {n} board"), variables([("queens placed", len(queens)), ("solutions found", count), ("backtracks", state["backs"])])]
        if len(queens) < state["last"]:
            state["backs"] += 1
            note = f"dead end: take the queen off row {len(queens)} and try the next column"
        elif len(queens) > state["last"]:
            note = f"row {len(queens) - 1}: a queen in column {queens[-1]} is safe so far"
        elif isinstance(trying, int) and try_row < n:
            note = f"row {try_row}, column {trying}: " + ("attacked" if (try_row, trying) in attacked else "free")
        else:
            note = ""
        if len(queens) == n:
            note = "every row has a queen: a solution"
        state["last"] = len(queens)
        return drawn, note

    return render


def _valid_board(board, n):
    if not isinstance(board, (list, tuple)) or len(board) != n:
        return False
    for r1, c1 in enumerate(board):
        for r2 in range(r1 + 1, n):
            c2 = board[r2]
            if c1 == c2 or abs(c1 - c2) == r2 - r1:
                return False
    return True


def _queens_check(got, n):
    if not isinstance(got, list):
        return f"solve({n}) returned {short(got, 40)}, expected a list of boards."
    bad = next((board for board in got if not _valid_board(board, n)), None)
    if bad is not None:
        return f"solve({n}) returned {len(got)} boards, but {list(bad)} has two queens attacking each other. Queens also attack along diagonals."
    if len({tuple(board) for board in got}) != len(got):
        return f"solve({n}) returned the same board twice."
    if len(got) != QUEEN_COUNTS[n]:
        return f"solve({n}) returned {len(got)} boards, expected {QUEEN_COUNTS[n]}."
    return None


def _queens_trace(ns, rec):
    n = 5
    rec.context = f"solve({n})"
    got = rec.watch(lambda: ns["solve"](n), _queens_render(n, {"last": 0, "backs": 0, "solutions": 0}))
    return _queens_check(got, n) or ""


def _queens_correct(ns):
    for n in range(1, 8):
        message = _queens_check(ns["solve"](n), n)
        if message:
            return message
    return None


def _queens_scale(ns):
    function = ns["solve"]
    return {"what": "Finds every solution on an n × n board.", "x": "board size n", "sizes": list(range(4, 11)), "step": "add",
            "series": [("your solve", lambda n: (lambda: function(n)))],
            "check": lambda n: _queens_check(function(6), 6),
            "footnote": "Backtracking cuts most branches early, but the search still grows exponentially with n."}


register("queens", {
    "queens": {"file": "queens.py", "names": [("solve", "a function solve(n)")],
               "trace": _queens_trace, "checks": [("boards from 1 × 1 to 7 × 7", _queens_correct)], "scale": _queens_scale},
})

# String matching


def _find_all(text, pattern):
    if not pattern:
        return list(range(len(text) + 1))
    return [i for i in range(len(text) - len(pattern) + 1) if text.startswith(pattern, i)]


MATCH_TEXT = "abababcabababcab"
MATCH_PATTERN = "ababc"


def _matching_render(text, pattern):
    state = {"t": None, "p": None}

    def render(view):
        values = view.locals
        read_text, read_pattern = text.take(), pattern.take()
        if read_text:
            state["t"] = read_text[-1]
        if read_pattern:
            state["p"] = read_pattern[-1]
        if not read_text and view.event != "return":
            if not read_pattern:
                return None
        t, p = state["t"], state["p"]
        shift = t - p if t is not None and p is not None else 0
        shift = max(0, min(shift, len(text) - 1))
        found = values.get("matches") or values.get("found") or values.get("result") or values.get("out") or []
        text_roles = [""] * len(text)
        for start in found if isinstance(found, list) else []:
            for index in range(start, min(len(text), start + len(pattern))):
                text_roles[index] = "seen"
        pattern_roles = [""] * len(pattern)
        same = None
        if t is not None and p is not None and t < len(text) and p < len(pattern):
            same = str.__getitem__(text, t) == str.__getitem__(pattern, p)
            text_roles[t] = "done" if same else "bad"
            pattern_roles[p] = "done" if same else "bad"
        drawn = [array(list(str(text)), roles=text_roles, title="text"),
                 array(list(str(pattern)), roles=pattern_roles, title="pattern", offset=shift)]
        table = values.get("fail") or values.get("lps") or values.get("table") or values.get("prefix")
        if isinstance(table, list) and table and all(isinstance(v, int) for v in table):
            drawn.append(array(table, title="failure table: how much of the pattern still matches after a mismatch"))
        drawn.append(variables([("character comparisons", text.reads), ("matches", list(found) if isinstance(found, list) else found)]))
        if view.event == "return":
            note = f"returned {short(view.value, 40)} after {text.reads} reads of the text"
        elif same is not None:
            note = f"text[{t}] = '{str.__getitem__(text, t)}' {'matches' if same else 'differs from'} pattern[{p}] = '{str.__getitem__(pattern, p)}'"
        else:
            note = ""
        return drawn, note

    return render


def _matching_trace(ns, rec):
    text, pattern = CountingStr(MATCH_TEXT), CountingStr(MATCH_PATTERN)
    rec.context = f"find_all({MATCH_TEXT!r}, {MATCH_PATTERN!r})"
    got = rec.watch(lambda: ns["find_all"](text, pattern), _matching_render(text, pattern))
    expected = _find_all(MATCH_TEXT, MATCH_PATTERN)
    if got != expected:
        return f"find_all({MATCH_TEXT!r}, {MATCH_PATTERN!r}) returned {short(got, 40)}, expected {expected}."
    return ""


def _matching_correct(ns):
    generator = random.Random(17)
    cases = [("aaaa", "aa"), ("abc", "abc"), ("abc", "abcd"), ("", "a"), ("abab", "b"), ("abcab", "ab")]
    for _ in range(60):
        text = "".join(generator.choice("ab") for _ in range(generator.randint(0, 20)))
        pattern = "".join(generator.choice("ab") for _ in range(generator.randint(1, 4)))
        cases.append((text, pattern))
    for text, pattern in cases:
        got = ns["find_all"](text, pattern)
        if got != _find_all(text, pattern):
            return f"find_all({text!r}, {pattern!r}) returned {short(got, 40)}, expected {_find_all(text, pattern)}."
    return None


def _kmp_fast(ns):
    raw_text, raw_pattern = "a" * 2000, "a" * 40 + "b"
    text = CountingStr(raw_text)
    got = ns["find_all"](text, CountingStr(raw_pattern))
    if got != []:
        return f"find_all('a' * 2000, 'a' * 40 + 'b') returned {short(got, 30)}, expected []."
    budget = 2 * len(raw_text) + len(raw_pattern)
    if text.reads > budget:
        return (f"Right answer, but it compared {text.reads:,} characters of a 2,000-character text. "
                f"KMP never steps back in the text: at most {budget:,}. Use the failure table to slide the pattern instead.")
    return None


def _matching_scale(ns):
    function = ns["find_all"]

    def mine(n):
        text, pattern = "a" * n, "a" * (n // 8) + "b"
        return lambda: function(text, pattern)

    return {"what": "Searches a text of n letter a's for a pattern of n / 8 a's followed by a b, the worst case for restarting.",
            "x": "text length n", "sizes": [500 * 2 ** k for k in range(8)], "series": [("your find_all", mine)],
            "check": lambda n: None if function("aaab", "ab") == [2] else "find_all gave a wrong answer."}


register("matching", {
    "naive": {"file": "match.py", "names": [("find_all", "a function find_all(text, pattern)")],
              "trace": _matching_trace, "checks": [("66 texts and patterns", _matching_correct)], "scale": _matching_scale},
    "kmp": {"file": "match.py", "names": [("find_all", "a function find_all(text, pattern)")],
            "trace": _matching_trace, "checks": [("66 texts and patterns", _matching_correct), ("never steps back in the text", _kmp_fast)],
            "scale": _matching_scale},
})

# Flood fill and islands

FILL_MAP = [
    "#.....#.....",
    "#.###.#.###.",
    "#.#...#...#.",
    "#.#.#####.#.",
    "....#...#...",
    "##..#.#.#.##",
    "#...#.#...#.",
    "#.###.#####.",
    "#...........",
]

ISLAND_MAP = [
    "LL..L....L",
    "L...LL..LL",
    "..L......L",
    ".LLL..L...",
    ".L.L..LL..",
    ".......L.L",
    "LL.L......",
]


def _cell(values):
    for row_name, col_name in (("r", "c"), ("row", "col"), ("y", "x"), ("i", "j")):
        row, col = values.get(row_name), values.get(col_name)
        if isinstance(row, int) and isinstance(col, int) and not isinstance(row, bool):
            return row, col
    return None


def _pending(values):
    for name in ("queue", "stack", "todo", "frontier", "q"):
        value = values.get(name)
        if isinstance(value, (list, deque)):
            return [item for item in value if isinstance(item, tuple) and len(item) == 2]
    return []


def _grid_render(board, kind):
    def render(view):
        values = view.locals
        now = _cell(values)
        waiting = set(_pending(values))
        seen = values.get("seen") or values.get("visited")
        seen = seen if isinstance(seen, set) else set()
        cells, roles = [], []
        for r, row in enumerate(board):
            line_cells, line_roles = [], []
            for c, value in enumerate(row):
                line_cells.append("" if value in (".", "#") else value)
                if (r, c) == now:
                    role = "now"
                elif (r, c) in waiting:
                    role = "focus"
                elif value == "#":
                    role = "wall"
                elif value == "L":
                    role = "seen" if (r, c) in seen else "land"
                elif value in ("o", "~") or (kind == "fill" and value not in (".", "#")):
                    role = "done"
                else:
                    role = "dim" if (r, c) in seen else ""
                line_roles.append(role)
            cells.append(line_cells)
            roles.append(line_roles)
        drawn = [grid(cells, roles, title="grid")]
        extra = [("waiting", len(waiting))] if waiting or kind == "fill" else []
        if kind == "islands":
            count = values.get("count", values.get("islands"))
            extra.append(("islands", count if isinstance(count, int) else "?"))
        drawn.append(variables(extra))
        note = ""
        if now is not None and 0 <= now[0] < len(board) and 0 <= now[1] < len(board[0]):
            note = f"at row {now[0]}, column {now[1]}: '{board[now[0]][now[1]]}'"
        if view.event == "return" and view.function in ("count_islands",):
            note = f"returned {view.value!r}"
        return drawn, note

    return render


def _reference_fill(board, row, col):
    if board[row][col] != ".":
        return
    todo = [(row, col)]
    board[row][col] = "o"
    while todo:
        r, c = todo.pop()
        for nr, nc in ((r + 1, c), (r - 1, c), (r, c + 1), (r, c - 1)):
            if 0 <= nr < len(board) and 0 <= nc < len(board[0]) and board[nr][nc] == ".":
                board[nr][nc] = "o"
                todo.append((nr, nc))


def _fill_compare(got, expected, start):
    for r, (mine, theirs) in enumerate(zip(got, expected)):
        for c, (a, b) in enumerate(zip(mine, theirs)):
            if a != b:
                if b == "o":
                    return f"Cell (row {r}, column {c}) can be reached from {start} but was not filled."
                return f"Cell (row {r}, column {c}) was set to {a!r}, but it should stay {b!r}."
    return None


def _fill_trace(ns, rec):
    board = [list(row) for row in FILL_MAP]
    expected = [list(row) for row in FILL_MAP]
    _reference_fill(expected, 4, 5)
    rec.context = "fill(grid, 4, 5)"
    rec.watch(lambda: ns["fill"](board, 4, 5), _grid_render(board, "fill"))
    return _fill_compare(board, expected, "(4, 5)") or ""


def _random_map(generator, rows, cols, wall=0.3):
    return [["#" if generator.random() < wall else "." for _ in range(cols)] for _ in range(rows)]


def _fill_correct(ns):
    generator = random.Random(18)
    for _ in range(30):
        rows, cols = generator.randint(1, 9), generator.randint(1, 9)
        board = _random_map(generator, rows, cols)
        r, c = generator.randrange(rows), generator.randrange(cols)
        expected = [row[:] for row in board]
        _reference_fill(expected, r, c)
        ns["fill"](board, r, c)
        message = _fill_compare(board, expected, f"({r}, {c})")
        if message:
            return message
    return None


def _fill_scale(ns):
    function = ns["fill"]

    def mine(cells):
        side = int(cells ** 0.5)
        return lambda: function([["."] * side for _ in range(side)], side // 2, side // 2)

    return {"what": "Fills a square grid of n open cells from its centre.", "x": "cells n",
            "sizes": [256 * 4 ** k for k in range(5)], "series": [("your fill", mine)],
            "footnote": "A recursive fill on a big open grid can run out of stack. An explicit stack or queue cannot."}


def _islands(board):
    seen, count = set(), 0
    for r, row in enumerate(board):
        for c, value in enumerate(row):
            if value == "L" and (r, c) not in seen:
                count += 1
                todo = [(r, c)]
                seen.add((r, c))
                while todo:
                    y, x = todo.pop()
                    for ny, nx in ((y + 1, x), (y - 1, x), (y, x + 1), (y, x - 1)):
                        if 0 <= ny < len(board) and 0 <= nx < len(row) and board[ny][nx] == "L" and (ny, nx) not in seen:
                            seen.add((ny, nx))
                            todo.append((ny, nx))
    return count


def _islands_trace(ns, rec):
    board = [list(row) for row in ISLAND_MAP]
    rec.context = "count_islands(grid)"
    got = rec.watch(lambda: ns["count_islands"](board), _grid_render(board, "islands"))
    expected = _islands([list(row) for row in ISLAND_MAP])
    if got != expected:
        return f"count_islands(grid) returned {got!r}, expected {expected}. Land cells touching up, down, left or right are one island."
    return ""


def _islands_correct(ns):
    generator = random.Random(19)
    for _ in range(40):
        rows, cols = generator.randint(1, 9), generator.randint(1, 9)
        board = [["L" if generator.random() < 0.5 else "." for _ in range(cols)] for _ in range(rows)]
        expected = _islands([row[:] for row in board])
        got = ns["count_islands"]([row[:] for row in board])
        if got != expected:
            picture = " / ".join("".join(row) for row in board)
            return f"count_islands({picture}) returned {got!r}, expected {expected}."
    return None


def _islands_scale(ns):
    function = ns["count_islands"]

    def mine(cells):
        side = int(cells ** 0.5)
        generator = random.Random(cells)
        base = [["L" if generator.random() < 0.45 else "." for _ in range(side)] for _ in range(side)]
        return lambda: function([row[:] for row in base])

    return {"what": "Counts the islands on a square map of n cells, about half of them land.", "x": "cells n",
            "sizes": [256 * 4 ** k for k in range(5)], "series": [("your count_islands", mine)]}


register("flood", {
    "fill": {"file": "flood.py", "names": [("fill", "a function fill(grid, row, col)")],
             "trace": _fill_trace, "checks": [("30 random maps", _fill_correct)], "scale": _fill_scale},
    "islands": {"file": "islands.py", "names": [("count_islands", "a function count_islands(grid)")],
                "trace": _islands_trace, "checks": [("40 random maps", _islands_correct)], "scale": _islands_scale},
})
