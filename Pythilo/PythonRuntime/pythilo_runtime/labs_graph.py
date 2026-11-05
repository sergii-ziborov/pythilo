"""Graph Explorer. The steps come from the user's own search reading the graph."""

import heapq
import math
import random
import statistics
import time
import types
from collections import deque

from . import emit_json
from .labs import describe_failure

MAXIMUM_STEPS = 2000
FUNCTIONS = {"bfs": "bfs", "dfs": "dfs", "dijkstra": "dijkstra"}


class _Stop(Exception):
    pass


class Graph:
    """What the user's code gets. Reading a node's neighbours is the one hook."""

    def __init__(self, nodes, adjacency, weighted, steps=None):
        self.nodes = list(nodes)
        self._adjacency = adjacency
        self.weighted = weighted
        self._steps = steps
        self._expanded = []
        self._seen = set()
        self.expansions = 0
        self.examined = 0

    def neighbors(self, node):
        edges = self._adjacency.get(node) if isinstance(node, int) else None
        if edges is None:
            hint = " Here neighbors() gives (node, weight) pairs." if self.weighted else ""
            raise KeyError(f"{node!r} is not a node of this graph.{hint}")
        self.expansions += 1
        self.examined += len(edges)
        if self._steps is not None:
            if len(self._steps) >= MAXIMUM_STEPS:
                raise _Stop
            self._expanded.append(node)
            self._seen.update(target for target, _ in edges)
            self._steps.append({"node": node, "expanded": list(self._expanded), "seen": sorted(self._seen)})
        if self.weighted:
            return list(edges)
        return [target for target, _ in edges]

    __getitem__ = neighbors

    def __len__(self):
        return len(self.nodes)

    def __iter__(self):
        return iter(self.nodes)


def _build(topology, size, seed, weighted):
    generator = random.Random(seed)
    edges = set()

    def connect(a, b):
        if a != b:
            edges.add((min(a, b), max(a, b)))

    positions = {}
    if topology == "grid":
        columns = max(2, round(math.sqrt(size)))
        rows = max(2, math.ceil(size / columns))
        size = rows * columns
        for node in range(size):
            row, column = divmod(node, columns)
            positions[node] = ((column + 0.5) / columns, (row + 0.5) / rows)
            if column + 1 < columns:
                connect(node, node + 1)
            if row + 1 < rows:
                connect(node, node + columns)
    else:
        for node in range(1, size):
            connect(node, generator.randrange(node))
        extra = {"tree": 0, "sparse": size, "dense": size * (size - 1) // 4}.get(topology, size)
        while len(edges) < (size - 1) + extra and len(edges) < size * (size - 1) // 2:
            connect(generator.randrange(size), generator.randrange(size))
        for node in range(size):
            angle = 2 * math.pi * node / size - math.pi / 2
            positions[node] = (0.5 + 0.44 * math.cos(angle), 0.5 + 0.44 * math.sin(angle))
    adjacency = {node: [] for node in range(size)}
    weights = {}
    for a, b in sorted(edges):
        weight = generator.randint(1, 9) if weighted else 1
        weights[(a, b)] = weight
        adjacency[a].append((b, weight))
        adjacency[b].append((a, weight))
    for node in adjacency:
        adjacency[node].sort()
    return list(range(size)), adjacency, weights, positions


def _reference(algorithm, adjacency, start):
    if algorithm == "dijkstra":
        distance = {start: 0}
        queue = [(0, start)]
        while queue:
            cost, node = heapq.heappop(queue)
            if cost > distance[node]:
                continue
            for target, weight in adjacency[node]:
                if cost + weight < distance.get(target, math.inf):
                    distance[target] = cost + weight
                    heapq.heappush(queue, (cost + weight, target))
        return distance
    hops = {start: 0}
    queue = deque([start])
    while queue:
        node = queue.popleft()
        for target, _ in adjacency[node]:
            if target not in hops:
                hops[target] = hops[node] + 1
                queue.append(target)
    return hops


def _valid_dfs(order, adjacency, start):
    """Whether order is the visiting order of some depth-first search from start."""
    reachable = _reference("bfs", adjacency, start)
    if not isinstance(order, (list, tuple)) or not order or order[0] != start:
        return False, f"The order should be a list that starts at {start}."
    if len(order) != len(set(order)):
        return False, "A node appears twice in the order."
    if set(order) != set(reachable):
        missing = sorted(set(reachable) - set(order))
        return False, f"Not every reachable node was visited, for example {missing[:3]}."
    neighbours = {node: {target for target, _ in edges} for node, edges in adjacency.items()}
    visited = {start}
    path = [start]
    for node in order[1:]:
        while path and node not in neighbours[path[-1]]:
            if not neighbours[path[-1]] <= visited:
                return False, f"Left {path[-1]} while it still had unvisited neighbours, so {node} came too early."
            path.pop()
        if not path:
            return False, f"{node} is not next to anything still on the search path."
        visited.add(node)
        path.append(node)
    return True, ""


def _judge(algorithm, result, adjacency, start):
    if algorithm == "dfs":
        return _valid_dfs(result, adjacency, start)
    expected = _reference(algorithm, adjacency, start)
    if not isinstance(result, dict):
        return False, f"Return a dict of node to {'distance' if algorithm == 'dijkstra' else 'hops'}, not {type(result).__name__}."
    for node, value in expected.items():
        if result.get(node) != value:
            return False, f"Node {node}: got {result.get(node)!r}, expected {value}."
    extra = sorted(set(result) - set(expected))
    if extra:
        return False, f"Node {extra[0]} cannot be reached from {start}, so it should not be in the result."
    return True, ""


def _load(source, algorithm):
    module = types.ModuleType("explorer")
    module.__dict__.update({"deque": deque, "heapq": heapq})
    exec(compile(source, "graph.py", "exec"), module.__dict__)
    name = FUNCTIONS[algorithm]
    function = module.__dict__.get(name)
    if not callable(function):
        raise ValueError(f"Define a function called {name}(graph, start).")
    return function


def trace(job):
    algorithm = job.get("algorithm", "bfs")
    function = _load(job["source"], algorithm)
    weighted = algorithm == "dijkstra"
    nodes, adjacency, weights, positions = _build(job.get("topology", "grid"), job.get("size", 16), job.get("seed", 7), weighted)
    start = 0
    steps = []
    graph = Graph(nodes, adjacency, weighted, steps)
    truncated = False
    result = None
    failure = ""
    try:
        result = function(graph, start)
    except _Stop:
        truncated = True
    except Exception as error:
        failure = describe_failure(error, "graph.py")
    if failure:
        correct, message = False, failure
    elif truncated:
        correct, message = False, "Stopped recording before the search finished."
    else:
        correct, message = _judge(algorithm, result, adjacency, start)
    emit_json(
        "lab_graph_trace",
        {
            "id": job["id"],
            "algorithm": algorithm,
            "nodes": [{"id": node, "x": positions[node][0], "y": positions[node][1]} for node in nodes],
            "edges": [[a, b, weight] for (a, b), weight in sorted(weights.items())],
            "start": start,
            "steps": steps,
            "labels": {str(node): int(value) for node, value in result.items()} if isinstance(result, dict) and correct else {},
            "correct": correct,
            "message": message,
            "truncated": truncated,
        },
    )


def scale(job):
    """How it scales: the learner's search from node 0 on growing graphs of one shape."""
    from .labs_engine import scale as run_scale

    algorithm = job.get("algorithm", "bfs")
    topology = job.get("topology", "sparse")
    weighted = algorithm == "dijkstra"
    try:
        function = _load(job["source"], algorithm)
    except Exception as error:
        emit_json("lab_scale", {"id": job["id"], "lab": "graph", "variant": algorithm, "what": "", "x": "nodes n", "runs": 0,
                                "series": [], "takeaway": "", "stopped": describe_failure(error, "graph.py"), "footnote": ""})
        return
    built = {}
    counts = {}

    def graph(n):
        if n not in built:
            built.clear()
            built[n] = _build(topology, n, 11, weighted)
        return built[n]

    def check(n):
        nodes, adjacency, weights, _ = graph(n)
        counted = Graph(nodes, adjacency, weighted)
        try:
            result = function(counted, 0)
        except Exception as error:
            return describe_failure(error, "graph.py")
        correct, message = _judge(algorithm, result, adjacency, 0)
        counts["last"] = (len(nodes), len(weights), counted.expansions, counted.examined)
        return None if correct else message

    def mine(n):
        nodes, adjacency, _, _ = graph(n)
        return lambda: function(Graph(nodes, adjacency, weighted), 0)

    sizes = job.get("sizes") or ([25, 50, 100, 200, 400] if topology == "dense" else [200, 400, 800, 1600, 3200, 6400, 12800])
    shape = {"grid": "square grids", "tree": "random trees", "sparse": "sparse random graphs", "dense": "dense random graphs"}.get(topology, topology)
    footnote = "Dense graphs have about n² / 4 edges, so the edges, not the nodes, set the pace." if topology == "dense" else ""
    run_scale(job["id"], "graph", algorithm, f"Runs your {algorithm} from node 0 on {shape} of n nodes.", "nodes n", sizes,
              [(f"your {algorithm}", mine)], check=check, footnote=footnote)
