"""Data structures: linked lists, search trees, heaps, tries, union-find, an LRU cache."""

import heapq
import random
from collections import OrderedDict

from .labs_engine import CountingList, Stop, array, chain, register, short, stack, tree, variables

# Linked lists


class Node:
    """One link: a value and the next node, or None at the end."""

    def __init__(self, value, next=None):
        self.value = value
        self.next = next

    def __repr__(self):
        return f"Node({self.value!r})"


def _build(values):
    nodes = [Node(value) for value in values]
    for left, right in zip(nodes, nodes[1:]):
        left.next = right
    return nodes


def _to_list(head, limit):
    out, seen = [], set()
    while head is not None:
        if id(head) in seen or len(out) > limit:
            return None
        seen.add(id(head))
        out.append(head.value)
        head = head.next
    return out


POINTER_NODES = ("head", "prev", "previous", "current", "cur", "node", "nxt", "next_node", "after", "slow", "fast", "new_head", "rest")


def _chain_render(nodes):
    ids = {id(node): f"n{index}" for index, node in enumerate(nodes)}

    def render(view):
        values = view.locals
        marks = []
        for name, value in values.items():
            if isinstance(value, Node) and id(value) in ids:
                marks.append((name, ids[id(value)]))
            elif value is None and name in POINTER_NODES:
                marks.append((name, None))
        if view.event == "return" and isinstance(view.value, Node) and id(view.value) in ids:
            marks.append(("returned", ids[id(view.value)]))
        pointed = {node for _, node in marks}
        drawn = [{"id": ids[id(node)], "label": short(node.value, 6),
                  "next": ids.get(id(node.next)) if node.next is not None else None,
                  "role": "now" if ids[id(node)] in pointed else ""} for node in nodes]
        names = ", ".join(f"{name} → {'None' if node is None else nodes[int(node[1:])].value}" for name, node in marks)
        return [chain(drawn, marks, title="nodes, in the order they were made")], names

    return render


def _reverse_trace(ns, rec):
    values = [1, 2, 3, 4, 5]
    nodes = _build(values)
    rec.context = "reverse(head) on 1 → 2 → 3 → 4 → 5"
    result = rec.watch(lambda: ns["reverse"](nodes[0]), _chain_render(nodes))
    got = _to_list(result, len(values) + 2)
    if got is None:
        return "The list loops back on itself after reverse: some node's next points at an earlier node."
    if got != values[::-1]:
        return f"reverse gave {' → '.join(map(str, got)) or 'None'}, expected 5 → 4 → 3 → 2 → 1."
    return ""


def _reverse_correct(ns):
    for size in range(0, 8):
        values = list(range(1, size + 1))
        nodes = _build(values)
        got = _to_list(ns["reverse"](nodes[0] if nodes else None), size + 2)
        if got is None:
            return f"With {size} nodes the reversed list loops back on itself."
        if got != values[::-1]:
            return f"reverse of {values} gave {got}, expected {values[::-1]}."
    return None


def _reverse_scale(ns):
    function = ns["reverse"]

    def mine(n):
        head = _build(range(n))[0]
        return lambda: function(head)

    return {"what": "Reverses a fresh linked list of n nodes.", "x": "nodes n",
            "sizes": [1000 * 2 ** k for k in range(9)], "series": [("your reverse", mine)],
            "check": lambda n: None if _to_list(function(_build(range(5))[0]), 8) == [4, 3, 2, 1, 0] else "reverse gave a wrong list."}


def _middle_trace(ns, rec):
    for values in ([1, 2, 3, 4, 5, 6, 7], [1, 2, 3, 4, 5, 6]):
        nodes = _build(values)
        rec.context = f"middle(head) on {' → '.join(map(str, values))}"
        result = rec.watch(lambda: ns["middle"](nodes[0]), _chain_render(nodes))
        expected = nodes[len(values) // 2]
        if result is not expected:
            return f"middle of {values} returned {result!r}, expected Node({expected.value}): slow should end halfway when fast reaches the end."
    return ""


def _middle_correct(ns):
    for size in range(1, 12):
        nodes = _build(range(size))
        got = ns["middle"](nodes[0])
        if got is not nodes[size // 2]:
            return f"middle of a {size}-node list returned {got!r}, expected Node({size // 2})."
    return None


def _middle_scale(ns):
    function = ns["middle"]

    def mine(n):
        head = _build(range(n))[0]
        return lambda: function(head)

    return {"what": "Finds the middle of a linked list of n nodes.", "x": "nodes n",
            "sizes": [1000 * 2 ** k for k in range(9)], "series": [("your middle", mine)]}


register("linkedlist", {
    "reverse": {"file": "linked.py", "names": [("reverse", "a function reverse(head)")], "inject": {"Node": Node},
                "trace": _reverse_trace, "checks": [("lists of 0 to 7 nodes", _reverse_correct)], "scale": _reverse_scale},
    "middle": {"file": "linked.py", "names": [("middle", "a function middle(head)")], "inject": {"Node": Node},
               "trace": _middle_trace, "checks": [("lists of 1 to 11 nodes", _middle_correct)], "scale": _middle_scale},
})

# Binary search trees


class TreeNode:
    """A search tree node: smaller values on the left, larger on the right."""

    def __init__(self, value):
        self.value = value
        self.left = None
        self.right = None

    def __repr__(self):
        return f"TreeNode({self.value!r})"


def _insert(root, value):
    if root is None:
        return TreeNode(value)
    node = root
    while True:
        if value < node.value:
            if node.left is None:
                node.left = TreeNode(value)
                return root
            node = node.left
        elif value > node.value:
            if node.right is None:
                node.right = TreeNode(value)
                return root
            node = node.right
        else:
            return root


def _inorder(root, limit=100_000):
    out, todo, node, seen = [], [], root, set()
    while todo or node is not None:
        while node is not None:
            if id(node) in seen or len(seen) > limit:
                raise ValueError("The tree has a loop: a node is its own descendant.")
            seen.add(id(node))
            todo.append(node)
            node = node.left
        node = todo.pop()
        out.append(node.value)
        node = node.right
    return out


def _shape(root):
    if root is None:
        return None
    return (root.value, _shape(root.left), _shape(root.right))


class _Ids:
    def __init__(self):
        self.ids = {}
        self.keep = []

    def __call__(self, node):
        if id(node) not in self.ids:
            self.ids[id(node)] = f"t{len(self.ids)}"
            self.keep.append(node)
        return self.ids[id(node)]


def _tree_nodes(root, ids, roles):
    out, todo, seen = [], [(root, None, None)], set()
    while todo:
        node, parent, side = todo.pop()
        if node is None or id(node) in seen or len(out) > 200:
            continue
        seen.add(id(node))
        node_id = ids(node)
        out.append({"id": node_id, "label": short(node.value, 5), "parent": parent, "side": side, "role": roles.get(id(node), "")})
        todo.append((node.right, node_id, "R"))
        todo.append((node.left, node_id, "L"))
    return out


def _bst_render(holder, ids):
    def render(view):
        values = view.locals
        roles, here = {}, None
        for name, value in values.items():
            if isinstance(value, TreeNode):
                if name in ("parent", "successor", "succ", "smallest", "follower"):
                    roles[id(value)] = "focus"
                else:
                    roles[id(value)] = "now"
                    if name in ("root", "node", "current", "cur"):
                        here = value
        target = values.get("value", values.get("key"))
        note = ""
        if here is not None and isinstance(target, (int, float)):
            sign = "<" if target < here.value else ">" if target > here.value else "="
            way = {"<": ": go left", ">": ": go right", "=": ": found it"}[sign]
            note = f"{target} {sign} {here.value}{way}"
        if view.event == "return":
            note = f"returned {view.value!r}"
        return [tree(_tree_nodes(holder["root"], ids, roles), binary=True, title="tree")], note

    return render


INSERTS = [50, 30, 70, 20, 40, 60, 80, 35, 65]


def _insert_trace(ns, rec):
    ids, holder = _Ids(), {"root": None}
    function = ns["insert"]
    done = []
    for value in INSERTS:
        rec.context = f"insert(root, {value})"
        holder["root"] = rec.watch(lambda: function(holder["root"], value), _bst_render(holder, ids))
        done.append(value)
        try:
            order = _inorder(holder["root"])
        except ValueError as error:
            return str(error)
        if order != sorted(done):
            return (f"After inserting {done}, the in-order walk gives {order}. "
                    "A search tree gives them sorted: smaller values go left, larger go right.")
        rec.add([tree(_tree_nodes(holder["root"], ids, {}), binary=True, title="tree")], f"inserted {value}")
    expected = None
    for value in INSERTS:
        expected = _insert(expected, value)
    if _shape(holder["root"]) != _shape(expected):
        return "The values are in order, but the shape differs from inserting each value at the leaf where a search for it ends."
    return ""


def _insert_correct(ns):
    generator = random.Random(9)
    for _ in range(30):
        values = generator.sample(range(100), generator.randint(1, 25))
        mine, expected = None, None
        for value in values:
            mine = ns["insert"](mine, value)
            expected = _insert(expected, value)
        if _shape(mine) != _shape(expected):
            return f"Inserting {short(values, 50)} built a different tree from the standard one (in-order: {short(_inorder(mine), 40)})."
    return None


def _insert_scale(ns):
    function = ns["insert"]

    def series(order):
        def make(n):
            values = list(range(n))
            if order == "random":
                random.Random(n).shuffle(values)

            def run():
                root = None
                for value in values:
                    root = function(root, value)
            return run
        return make

    return {"what": "Inserts n numbers into an empty tree, once in random order and once already sorted.",
            "x": "values n", "sizes": [250 * 2 ** k for k in range(7)],
            "series": [("random order", series("random")), ("sorted order", series("sorted"))],
            "footnote": "Sorted input makes every insert go right, so the tree is one long chain."}


def _build_tree(values):
    root = None
    for value in values:
        root = _insert(root, value)
    return root


DELETE_TREE = [50, 30, 70, 20, 40, 60, 80, 35, 45, 65]


def _delete_trace(ns, rec):
    ids = _Ids()
    holder = {"root": _build_tree(DELETE_TREE)}
    left = sorted(DELETE_TREE)
    for value in (20, 30, 50):
        rec.context = f"delete(root, {value})"
        rec.add([tree(_tree_nodes(holder["root"], ids, {}), binary=True, title="tree")], f"delete {value}")
        holder["root"] = rec.watch(lambda: ns["delete"](holder["root"], value), _bst_render(holder, ids))
        left.remove(value)
        try:
            order = _inorder(holder["root"])
        except ValueError as error:
            return str(error)
        if order != left:
            return f"After delete(root, {value}) the tree holds {order}, expected {left}."
    rec.add([tree(_tree_nodes(holder["root"], ids, {}), binary=True, title="tree")], "deleted 20, 30 and 50")
    return ""


def _delete_correct(ns):
    generator = random.Random(10)
    for _ in range(40):
        values = generator.sample(range(60), generator.randint(1, 20))
        root = _build_tree(values)
        remaining = sorted(values)
        for value in generator.sample(range(60), 8):
            root = ns["delete"](root, value)
            if value in remaining:
                remaining.remove(value)
            order = _inorder(root)
            if order != remaining:
                return f"Deleting {value} from a tree of {short(sorted(values), 40)} left {short(order, 40)}, expected {short(remaining, 40)}."
    return None


def _delete_scale(ns):
    function = ns["delete"]

    def mine(n):
        values = list(range(n))
        random.Random(n).shuffle(values)
        order = values[:]
        random.Random(n + 1).shuffle(order)

        def run():
            root = _build_tree(values)
            for value in order:
                root = function(root, value)
        return run

    return {"what": "Builds a tree of n numbers in random order, then deletes all of them in another random order.",
            "x": "values n", "sizes": [250 * 2 ** k for k in range(7)], "series": [("your delete", mine)],
            "footnote": "Each run also builds the tree first, which is part of the time."}


register("bst", {
    "insert": {"file": "bst.py", "names": [("insert", "a function insert(root, value)")], "inject": {"TreeNode": TreeNode},
               "trace": _insert_trace, "checks": [("30 random trees", _insert_correct)], "scale": _insert_scale},
    "delete": {"file": "bst.py", "names": [("delete", "a function delete(root, value)")], "inject": {"TreeNode": TreeNode},
               "trace": _delete_trace, "checks": [("320 deletes from 40 trees", _delete_correct)], "scale": _delete_scale},
})

# Heaps


def _heap_problem(heap):
    for index in range(1, len(heap)):
        parent = (index - 1) // 2
        if heap[index] < heap[parent]:
            return f"heap[{index}] = {heap[index]} is smaller than its parent heap[{parent}] = {heap[parent]}"
    return ""


def _heap_render(heap):
    def render(view):
        touched = heap.take()
        roles = {}
        for kind, index in touched:
            roles[index] = "now" if kind == "w" else roles.get(index) or "focus"
        values = heap.plain()
        nodes = [{"id": f"h{i}", "label": short(v, 5), "parent": f"h{(i - 1) // 2}" if i else None,
                  "side": ("L" if i % 2 else "R") if i else None, "role": roles.get(i, "")} for i, v in enumerate(values)]
        writes = sorted({index for kind, index in touched if kind == "w"})
        if len(writes) == 2:
            note = f"swap heap[{writes[0]}] and heap[{writes[1]}]"
        elif writes:
            note = f"write heap[{writes[0]}] = {values[writes[0]] if writes[0] < len(values) else '?'}"
        elif touched:
            reads = sorted({index for _, index in touched if index < len(values)})
            note = "compare " + " and ".join(f"heap[{i}] = {values[i]}" for i in reads[:3])
        else:
            note = f"{len(values)} items"
        if view.event == "return":
            note = f"returned {view.value!r}" if view.value is not None else "done"
        return [tree(nodes, binary=True, title="the heap as a tree"),
                array(values, roles=[roles.get(i, "") for i in range(len(values))], title="the same heap as a list")], note

    return render


PUSHES = [5, 3, 8, 1, 9, 2, 7, 4]


def _push_trace(ns, rec):
    heap = CountingList()
    for value in PUSHES:
        rec.context = f"push(heap, {value})"
        rec.watch(lambda: ns["push"](heap, value), _heap_render(heap))
        problem = _heap_problem(heap.plain())
        if problem:
            return f"After pushing {PUSHES[:PUSHES.index(value) + 1]}, the heap is {heap.plain()}: {problem}. Sift the new item up."
    return ""


def _push_correct(ns):
    generator = random.Random(11)
    for _ in range(40):
        heap, values = [], [generator.randrange(50) for _ in range(generator.randint(1, 30))]
        for value in values:
            ns["push"](heap, value)
            problem = _heap_problem(heap)
            if problem:
                return f"Pushing {short(values, 40)} gave {short(heap, 40)}: {problem}."
        if sorted(heap) != sorted(values):
            return f"Pushing {short(values, 40)} left {short(heap, 40)}: items went missing or appeared."
    return None


def _push_scale(ns):
    function = ns["push"]

    def data(n):
        generator = random.Random(n)
        return [generator.random() for _ in range(n)]

    def mine(n):
        values = data(n)

        def run():
            heap = []
            for value in values:
                function(heap, value)
        return run

    def builtin(n):
        values = data(n)

        def run():
            heap = []
            for value in values:
                heapq.heappush(heap, value)
        return run

    return {"what": "Pushes n random numbers into an empty heap.", "x": "pushes n",
            "sizes": [1000 * 2 ** k for k in range(8)], "series": [("your push", mine), ("heapq.heappush", builtin)]}


def _pop_trace(ns, rec):
    heap = CountingList([1, 3, 2, 4, 9, 8, 7, 5])
    expected = sorted(heap.plain())
    for count in range(4):
        rec.context = "pop(heap)"
        got = rec.watch(lambda: ns["pop"](heap), _heap_render(heap))
        if got != expected[count]:
            return f"pop() number {count + 1} returned {got!r}, expected the smallest, {expected[count]}. Sift the moved item down."
        problem = _heap_problem(heap.plain())
        if problem:
            return f"After pop() the heap is {heap.plain()}: {problem}. Sift the moved item down."
    return ""


def _pop_correct(ns):
    generator = random.Random(12)
    for _ in range(40):
        values = [generator.randrange(50) for _ in range(generator.randint(1, 30))]
        heap = list(values)
        heapq.heapify(heap)
        out = []
        while heap:
            out.append(ns["pop"](heap))
            problem = _heap_problem(heap)
            if problem:
                return f"Popping from a heap of {short(values, 40)} left {short(heap, 40)}: {problem}."
        if out != sorted(values):
            return f"Popping everything gave {short(out, 40)}, expected {short(sorted(values), 40)}."
    return None


def _pop_scale(ns):
    function = ns["pop"]

    def data(n):
        generator = random.Random(n)
        values = [generator.random() for _ in range(n)]
        heapq.heapify(values)
        return values

    def series(pop):
        def make(n):
            base = data(n)

            def run():
                heap = list(base)
                while heap:
                    pop(heap)
            return run
        return make

    return {"what": "Pops every item from a heap of n random numbers (that is heapsort).", "x": "items n",
            "sizes": [1000 * 2 ** k for k in range(8)], "series": [("your pop", series(function)), ("heapq.heappop", series(heapq.heappop))]}


register("heap", {
    "push": {"file": "heap.py", "names": [("push", "a function push(heap, value)")],
             "trace": _push_trace, "checks": [("40 random push sequences", _push_correct)], "scale": _push_scale},
    "pop": {"file": "heap.py", "names": [("pop", "a function pop(heap)")],
            "trace": _pop_trace, "checks": [("pops 40 heaps empty, in order", _pop_correct)], "scale": _pop_scale},
})

# Tries


def _trie_nodes(root, roles):
    out, todo, seen = [], [(root, None, "·")], set()
    while todo and len(out) < 160:
        node, parent, label = todo.pop()
        if not isinstance(node, dict) or id(node) in seen:
            continue
        seen.add(id(node))
        node_id = f"d{id(node)}"
        role = roles.get(id(node)) or ("done" if node.get("$") else "")
        out.append({"id": node_id, "label": label, "parent": parent, "role": role})
        for key in sorted((k for k in node if k != "$"), reverse=True):
            todo.append((node[key], node_id, str(key)))
    return out


def _path_to(root, target):
    todo = [(root, "")]
    while todo:
        node, path = todo.pop()
        if node is target:
            return path
        if isinstance(node, dict):
            todo.extend((child, path + str(key)) for key, child in node.items() if key != "$")
    return None


def _trie_render(trie):
    def render(view):
        values = view.locals
        root = getattr(trie, "root", None)
        if not isinstance(root, dict):
            return None
        roles, here = {}, None
        for name, value in values.items():
            if isinstance(value, dict) and name in ("node", "current", "cur", "child"):
                roles[id(value)] = "now"
                here = value
        drawn = [tree(_trie_nodes(root, roles), title="trie: green marks the end of a word")]
        words = values.get("words") or values.get("out") or values.get("found") or values.get("result")
        if isinstance(words, list):
            drawn.append(stack(list(words), title="found", horizontal=True, roles=["done"] * len(words)))
        path = _path_to(root, here) if here is not None else None
        note = f"at '{path}'" if path else "at the root" if path == "" else ""
        if view.event == "return":
            note = f"returned {short(view.value, 60)}" if view.value is not None else ""
        return drawn, note

    return render


TRIE_WORDS = ["tea", "ten", "to", "tom", "in", "inn"]


def _complete(words, prefix):
    return sorted(w for w in set(words) if w.startswith(prefix))


def _trie_trace(ns, rec):
    trie = ns["Trie"]()
    render = _trie_render(trie)
    for word in TRIE_WORDS:
        rec.context = f"insert({word!r})"
        rec.watch(lambda: trie.insert(word), render)
    for prefix in ("te", "to", "i"):
        rec.context = f"complete({prefix!r})"
        got = rec.watch(lambda: trie.complete(prefix), render)
        if got != _complete(TRIE_WORDS, prefix):
            return f"complete({prefix!r}) returned {short(got, 50)}, expected {_complete(TRIE_WORDS, prefix)}."
    return ""


def _trie_correct(ns):
    generator = random.Random(13)
    words = sorted({"".join(generator.choice("abc") for _ in range(generator.randint(1, 5))) for _ in range(120)})
    trie = ns["Trie"]()
    for word in words:
        trie.insert(word)
    for prefix in [""] + sorted({w[:k] for w in words for k in range(1, 4)}) + ["zz", "abcabc"]:
        got = trie.complete(prefix)
        if sorted(got or []) != _complete(words, prefix) or got != sorted(got or []):
            return f"After inserting {len(words)} words, complete({prefix!r}) returned {short(got, 50)}, expected {short(_complete(words, prefix), 50)} in sorted order."
    return None


def _trie_scale(ns):
    cls = ns["Trie"]

    def mine(n):
        generator = random.Random(n)
        words = ["".join(generator.choice("abcdefghij") for _ in range(8)) for _ in range(n)]
        prefixes = [w[:5] for w in generator.sample(words, min(200, n))]

        def run():
            trie = cls()
            for word in words:
                trie.insert(word)
            for prefix in prefixes:
                trie.complete(prefix)
        return run

    return {"what": "Inserts n random 8-letter words, then completes 200 five-letter prefixes.", "x": "words n",
            "sizes": [500 * 2 ** k for k in range(8)], "series": [("your Trie", mine)]}


register("trie", {
    "complete": {"file": "trie.py", "names": [("Trie", "a class Trie with insert(word) and complete(prefix)")],
                 "trace": _trie_trace, "checks": [("every prefix of 120 words", _trie_correct)], "scale": _trie_scale},
})

# Union-find


def _forest_render(parent):
    def render(view):
        touched = parent.take()
        roles = {}
        for kind, index in touched:
            roles[index] = "now" if kind == "w" else roles.get(index) or "focus"
        values = parent.plain()
        nodes = [{"id": str(i), "label": str(i), "parent": str(p) if p != i and 0 <= p < len(values) else None,
                  "role": roles.get(i, "")} for i, p in enumerate(values)]
        writes = [index for kind, index in touched if kind == "w"]
        if writes:
            note = "; ".join(f"parent[{i}] = {values[i]}" for i in writes[-3:])
        elif touched:
            walk = [index for _, index in touched]
            note = "walk up: " + " → ".join(str(i) for i in walk[-8:])
        else:
            note = ""
        if view.event == "return" and view.function == "find":
            note = f"find returned {view.value!r}, the root"
        return [tree(nodes, title="the sets as trees: each root names its set"),
                array(values, roles=[roles.get(i, "") for i in range(len(values))], title="parent")], note

    return render


UNIONS = [(1, 2), (3, 4), (2, 4), (5, 6), (6, 7), (4, 7), (8, 9), (0, 9)]


class _Reference:
    def __init__(self, n):
        self.parent = list(range(n))

    def find(self, x):
        while self.parent[x] != x:
            self.parent[x] = self.parent[self.parent[x]]
            x = self.parent[x]
        return x

    def union(self, a, b):
        self.parent[self.find(a)] = self.find(b)


def _uf_trace(ns, rec):
    parent = CountingList(range(10))
    render = _forest_render(parent)
    reference = _Reference(10)
    for a, b in UNIONS:
        rec.context = f"union(parent, {a}, {b})"
        rec.watch(lambda: ns["union"](parent, a, b), render)
        reference.union(a, b)
    for x in (1, 0):
        rec.context = f"find(parent, {x})"
        rec.watch(lambda: ns["find"](parent, x), render)
    plain = parent.plain()
    for a in range(10):
        for b in range(10):
            same = ns["find"](list(plain), a) == ns["find"](list(plain), b)
            if same != (reference.find(a) == reference.find(b)):
                return f"After the unions, {a} and {b} {'are' if same else 'are not'} in the same set, but they {'are not' if same else 'are'}."
    return ""


def _uf_correct(ns):
    generator = random.Random(14)
    for _ in range(20):
        n = 30
        parent, reference = list(range(n)), _Reference(n)
        for _ in range(generator.randint(5, 40)):
            a, b = generator.randrange(n), generator.randrange(n)
            ns["union"](parent, a, b)
            reference.union(a, b)
        for _ in range(60):
            a, b = generator.randrange(n), generator.randrange(n)
            mine = ns["find"](parent, a) == ns["find"](parent, b)
            if mine != (reference.find(a) == reference.find(b)):
                return f"After random unions, find says {a} and {b} are {'in the same set' if mine else 'apart'}, but they are {'apart' if mine else 'in the same set'}."
    return None


def _uf_fast(ns):
    n = 2000
    parent = CountingList(range(n))
    for i in range(n - 1):
        ns["union"](parent, i, i + 1)
    parent.reads = 0
    parent.limit = 30 * 1000
    try:
        for x in random.Random(15).sample(range(n), 1000):
            ns["find"](parent, x)
    except Stop:
        pass
    if parent.reads > parent.limit:
        return (f"Right sets, but 1,000 finds read parent over {parent.limit:,} times after unions that build a chain of {n:,}. "
                "As find walks up, point each node at the root (path compression), or hang the smaller tree under the bigger one.")
    return None


def _uf_scale(ns):
    find, union = ns["find"], ns["union"]

    def mine(n):
        targets = [random.Random(n).randrange(n) for _ in range(n)]

        def run():
            parent = list(range(n))
            for i in range(n - 1):
                union(parent, i, i + 1)
            for x in targets:
                find(parent, x)
        return run

    return {"what": "Joins n items into one long chain with n − 1 unions, then runs n finds on random items.", "x": "items n",
            "sizes": [500 * 2 ** k for k in range(8)], "series": [("your find and union", mine)]}


register("unionfind", {
    "sets": {"file": "union_find.py", "names": [("find", "a function find(parent, x)"), ("union", "a function union(parent, a, b)")],
             "trace": _uf_trace, "checks": [("20 random sets of unions", _uf_correct), ("finds stay short", _uf_fast)], "scale": _uf_scale},
})

# LRU cache


class _LRU:
    def __init__(self, capacity):
        self.capacity, self.items = capacity, OrderedDict()

    def get(self, key):
        if key not in self.items:
            return None
        self.items.move_to_end(key)
        return self.items[key]

    def put(self, key, value):
        self.items[key] = value
        self.items.move_to_end(key)
        if len(self.items) > self.capacity:
            self.items.popitem(last=False)


LRU_OPS = [("put", "a", 1), ("put", "b", 2), ("put", "c", 3), ("get", "a"), ("put", "d", 4), ("get", "b"),
           ("get", "c"), ("put", "e", 5), ("get", "a"), ("get", "d")]


def _storage(cache):
    for value in vars(cache).values() if hasattr(cache, "__dict__") else []:
        if isinstance(value, dict):
            return value
    return None


def _call_text(op):
    return f"{op[0]}({', '.join(repr(a) for a in op[1:])})"


def _lru_render(cache, stats):
    def render(view):
        storage = _storage(cache)
        if storage is None:
            return None
        key = view.locals.get("key")
        keys = list(storage.keys())
        drawn = [stack([f"{k}: {short(storage[k], 6)}" for k in keys], title="cache, least recently used first", horizontal=True,
                       roles=["now" if k == key else "" for k in keys], ends=["evict next", "newest"]),
                 variables([("capacity", getattr(cache, "capacity", "?")), ("hits", stats["hits"]), ("misses", stats["misses"])])]
        note = f"returned {view.value!r}" if view.event == "return" and view.function == "get" else ""
        return drawn, note

    return render


def _lru_trace(ns, rec):
    cache, reference = ns["LRUCache"](3), _LRU(3)
    stats = {"hits": 0, "misses": 0}
    render = _lru_render(cache, stats)
    for index, op in enumerate(LRU_OPS, 1):
        rec.context = _call_text(op)
        got = rec.watch(lambda: getattr(cache, op[0])(*op[1:]), render)
        expected = getattr(reference, op[0])(*op[1:])
        if op[0] == "get":
            stats["hits" if got is not None else "misses"] += 1
            if got != expected:
                why = " It should have been evicted as the least recently used key." if expected is None else ""
                return f"Step {index}, {_call_text(op)}: got {got!r}, expected {expected!r}.{why}"
    storage = _storage(cache)
    if storage is not None and list(storage) != list(reference.items):
        return f"At the end the cache holds {list(storage)}, expected {list(reference.items)} (oldest first)."
    return ""


def _lru_correct(ns):
    generator = random.Random(16)
    for capacity in (1, 2, 5):
        cache, reference = ns["LRUCache"](capacity), _LRU(capacity)
        for index in range(1500):
            key = generator.choice("abcdefgh")
            if generator.random() < 0.5:
                got, expected = cache.get(key), reference.get(key)
                if got != expected:
                    return f"With capacity {capacity}, operation {index + 1}: get({key!r}) gave {got!r}, expected {expected!r}."
            else:
                cache.put(key, index)
                reference.put(key, index)
    return None


def _lru_scale(ns):
    cls = ns["LRUCache"]

    def mine(n):
        generator = random.Random(n)
        ops = [(generator.random() < 0.5, generator.randrange(n // 2)) for _ in range(n)]

        def run():
            cache = cls(max(1, n // 10))
            for is_get, key in ops:
                if is_get:
                    cache.get(key)
                else:
                    cache.put(key, key)
        return run

    return {"what": "Runs n random gets and puts on a cache that holds n / 10 keys.", "x": "operations n",
            "sizes": [1000 * 2 ** k for k in range(8)], "series": [("your LRUCache", mine)]}


register("lru", {
    "cache": {"file": "lru.py", "names": [("LRUCache", "a class LRUCache(capacity) with get(key) and put(key, value)")],
              "trace": _lru_trace, "checks": [("4,500 random gets and puts", _lru_correct)], "scale": _lru_scale},
})
