"""Machine learning: gradient descent, a perceptron and a small network, a genetic algorithm,
k-means and Q-learning. The learner writes the key step; the lab runs the loop around it
and draws every round."""

import math
import random

from .labs_engine import LabError, grid, plot, register, scatter, short, stack, variables

# Gradient descent on a 2-D loss surface

BOUNDS = [-5.0, 5.0, -3.5, 3.5]


def _loss(x, y):
    return 0.25 * (x - 2) ** 2 + 2.0 * (y + 1) ** 2


def _gradient(x, y):
    return 0.5 * (x - 2), 4.0 * (y + 1)


def _field(function, bounds, columns=26, rows=18, log=True):
    xmin, xmax, ymin, ymax = bounds
    values = []
    for row in range(rows):
        y = ymax - (row + 0.5) * (ymax - ymin) / rows
        values.append([function(xmin + (column + 0.5) * (xmax - xmin) / columns, y) for column in range(columns)])
    flat = [v for line in values for v in line]
    if log:
        flat_log = [math.log1p(v) for v in flat]
        low, high = min(flat_log), max(flat_log)
        return [[round((math.log1p(v) - low) / (high - low or 1), 2) for v in line] for line in values]
    low, high = min(flat), max(flat)
    return [[round((v - low) / (high - low or 1), 2) for v in line] for line in values]


SURFACE = None


def _surface():
    global SURFACE
    if SURFACE is None:
        SURFACE = _field(_loss, BOUNDS)
    return SURFACE


def _descend(step, momentum, start, lr, steps, beta=0.8, record=None):
    x, y = start
    vx = vy = 0.0
    path = [[x, y]]
    losses = [[0, _loss(x, y)]]
    for index in range(1, steps + 1):
        gx, gy = _gradient(x, y)
        if momentum:
            got = step(x, y, gx, gy, vx, vy, lr, beta)
            if not isinstance(got, (tuple, list)) or len(got) != 4:
                raise LabError(f"step should return (x, y, vx, vy), not {short(got, 30)}.")
            x, y, vx, vy = (float(v) for v in got)
        else:
            got = step(x, y, gx, gy, lr)
            if not isinstance(got, (tuple, list)) or len(got) != 2:
                raise LabError(f"step should return the new (x, y), not {short(got, 30)}.")
            x, y = (float(v) for v in got)
        if not (math.isfinite(x) and math.isfinite(y)) or abs(x) > 1e6 or abs(y) > 1e6:
            return path, losses, f"After {index} steps the point flew off to ({x:.3g}, {y:.3g}). Step against the gradient: x - lr * gx."
        path.append([x, y])
        losses.append([index, _loss(x, y)])
        if record:
            record(index, x, y, gx, gy, path, losses)
    return path, losses, ""


def _descent_trace(momentum):
    def trace(ns, rec):
        step = ns["step"]
        start, lr = (-4.0, 2.5), 0.1

        def record(index, x, y, gx, gy, path, losses):
            visible = [p for p in path if BOUNDS[0] <= p[0] <= BOUNDS[1] and BOUNDS[2] <= p[1] <= BOUNDS[3]]
            rec.add([
                scatter([[2.0, -1.0, 9]], centers=[[x, y, 0]] if BOUNDS[0] <= x <= BOUNDS[1] and BOUNDS[2] <= y <= BOUNDS[3] else [],
                        bounds=BOUNDS, field=_surface(), path=visible,
                        title="loss surface: darker is lower; the cross is the minimum"),
                plot([("loss", [[i, round(v, 4)] for i, v in losses])], title="loss after each step"),
                variables([("step", index), ("x, y", f"{x:.3f}, {y:.3f}"), ("gradient", f"{gx:.3f}, {gy:.3f}"), ("loss", f"{_loss(x, y):.4f}")]),
            ], f"step {index}: the gradient was ({gx:.2f}, {gy:.2f}); now at ({x:.2f}, {y:.2f}), loss {_loss(x, y):.3f}")

        rec.context = f"{'momentum' if momentum else 'gradient descent'}, learning rate {lr}, from (-4, 2.5)"
        rec.add([scatter([[2.0, -1.0, 9]], centers=[[start[0], start[1], 0]], bounds=BOUNDS, field=_surface(), path=[list(start)],
                         title="loss surface: darker is lower; the cross is the minimum"),
                 plot([("loss", [[0, _loss(*start)]])], title="loss after each step"),
                 variables([("step", 0), ("x, y", "-4.000, 2.500"), ("loss", f"{_loss(*start):.4f}")])], "the start")
        path, losses, problem = _descend(step, momentum, start, lr, 40, record=record)
        if problem:
            return problem
        first, last = losses[0][1], losses[-1][1]
        if last > first * 0.2:
            return f"After 40 steps the loss went from {first:.2f} to {last:.2f}. Each step should move against the gradient: x - lr * gx."
        return ""
    return trace


def _descent_check(ns):
    path, losses, problem = _descend(ns["step"], False, (4.5, -3.0), 0.2, 80)
    if problem:
        return problem
    x, y = path[-1]
    if abs(x - 2) > 0.05 or abs(y + 1) > 0.05:
        return f"From (4.5, -3) with learning rate 0.2, 80 steps ended at ({x:.3f}, {y:.3f}); the minimum is (2, -1)."
    return None


def _momentum_check(ns):
    path, losses, problem = _descend(ns["step"], True, (-4.0, 2.5), 0.1, 60)
    if problem:
        return problem
    x, y = path[-1]
    if abs(x - 2) > 0.05 or abs(y + 1) > 0.05:
        return (f"After 60 steps it is at ({x:.3f}, {y:.3f}), still away from (2, -1). With velocity "
                "v = beta * v + gradient and x = x - lr * v, it builds speed along the long, gentle valley.")
    return None


register("descent", {
    "plain": {"file": "descent.py", "names": [("step", "a function step(x, y, gx, gy, lr)")],
              "trace": _descent_trace(False), "checks": [("reaches the minimum from another start", _descent_check)]},
    "momentum": {"file": "momentum.py", "names": [("step", "a function step(x, y, gx, gy, vx, vy, lr, beta)")],
                 "trace": _descent_trace(True), "checks": [("reaches the minimum in 60 steps", _momentum_check)]},
})

# Perceptron


def _blobs(seed, count=30, gap=1.4):
    generator = random.Random(seed)
    points = []
    for index in range(count):
        label = 1 if index % 2 else -1
        cx, cy = (gap, gap * 0.6) if label == 1 else (-gap, -gap * 0.4)
        points.append(((cx + generator.gauss(0, 0.7), cy + generator.gauss(0, 0.7)), label))
    return points


PERCEPTRON_BOUNDS = [-4.0, 4.0, -3.5, 3.5]


def _boundary(w, b, bounds):
    w1, w2 = w
    xmin, xmax, ymin, ymax = bounds
    if abs(w1) < 1e-12 and abs(w2) < 1e-12:
        return []
    if abs(w2) > abs(w1):
        return [[xmin, -(b + w1 * xmin) / w2, xmax, -(b + w1 * xmax) / w2]]
    return [[-(b + w2 * ymin) / w1, ymin, -(b + w2 * ymax) / w1, ymax]]


def _mistakes(w, b, points):
    return sum(1 for (x1, x2), label in points if label * (w[0] * x1 + w[1] * x2 + b) <= 0)


def _train_perceptron(update, points, epochs, record=None):
    w, b = [0.0, 0.0], 0.0
    history = []
    for epoch in range(1, epochs + 1):
        for index, (x, label) in enumerate(points):
            got = update(list(w), b, x, label, 1.0)
            if not isinstance(got, (tuple, list)) or len(got) != 2:
                raise LabError(f"update should return (w, b), not {short(got, 30)}.")
            new_w, new_b = got
            new_w = [float(v) for v in new_w]
            changed = new_w != w or new_b != b
            w, b = new_w, float(new_b)
            if record and changed:
                record(epoch, index, w, b, history)
        history.append([epoch, _mistakes(w, b, points)])
        if record:
            record(epoch, None, w, b, history)
        if history[-1][1] == 0:
            break
    return w, b, history


def _perceptron_trace(ns, rec):
    points = _blobs(22, 30, 1.0)

    def record(epoch, index, w, b, history):
        dots = [[x[0], x[1], 0 if label == 1 else 1] for x, label in points]
        centers = [[points[index][0][0], points[index][0][1], 0 if points[index][1] == 1 else 1]] if index is not None else []
        field = _field(lambda px, py: 1.0 if w[0] * px + w[1] * py + b > 0 else 0.0, PERCEPTRON_BOUNDS, 24, 20, log=False) if any(w) or b else None
        rec.add([
            scatter(dots, centers=centers, lines=_boundary(w, b, PERCEPTRON_BOUNDS), bounds=PERCEPTRON_BOUNDS, field=field,
                    title="the line is where w · x + b = 0"),
            plot([("mistakes", history)], title="mistakes after each pass over the data"),
            variables([("pass", epoch), ("w", f"{w[0]:.2f}, {w[1]:.2f}"), ("b", f"{b:.2f}"), ("mistakes now", _mistakes(w, b, points))]),
        ], f"pass {epoch}: point {index} was on the wrong side, so the line moved" if index is not None else f"end of pass {epoch}: {_mistakes(w, b, points)} mistakes")

    rec.context = "update(w, b, x, y, lr) on 30 points, up to 20 passes"
    w, b, history = _train_perceptron(ns["update"], points, 20, record)
    if history[-1][1]:
        return f"After {len(history)} passes it still gets {history[-1][1]} of {len(points)} points wrong. When y * (w · x + b) <= 0, add lr * y * x to w and lr * y to b."
    return ""


def _perceptron_check(ns):
    for seed in (31, 32, 33):
        points = _blobs(seed, 40, 1.8)
        w, b, history = _train_perceptron(ns["update"], points, 50)
        if history[-1][1]:
            return f"On another separable set it still made {history[-1][1]} mistakes after 50 passes."
    w, b = ns["update"]([1.0, 1.0], 0.5, (1.0, 1.0), 1, 1.0)
    if list(map(float, w)) != [1.0, 1.0] or float(b) != 0.5:
        return "update changed w and b for a point that was already on the right side. Only learn from mistakes."
    return None


def _perceptron_scale(ns):
    update = ns["update"]

    def mine(n):
        points = _blobs(n, n, 3.0)
        return lambda: _train_perceptron(update, points, 5)

    return {"what": "Trains for 5 passes over n points from two well-separated clouds.", "x": "points n",
            "sizes": [250 * 2 ** k for k in range(7)], "series": [("your update", mine)]}

# A small network learning XOR


def _xor_data():
    generator = random.Random(5)
    rows, labels = [], []
    for index in range(40):
        a, b = index % 2, (index // 2) % 2
        rows.append([a * 2 - 1 + generator.gauss(0, 0.18), b * 2 - 1 + generator.gauss(0, 0.18)])
        labels.append([float(a ^ b)])
    return rows, labels


def _xor_net(np, hidden=4, seed=3):
    generator = np.random.default_rng(seed)
    return {"W1": generator.normal(0, 1.0, (2, hidden)), "b1": np.zeros(hidden),
            "W2": generator.normal(0, 1.0, (hidden, 1)), "b2": np.zeros(1)}


def _predict(np, net, X):
    h = np.tanh(X @ net["W1"] + net["b1"])
    return 1 / (1 + np.exp(-(h @ net["W2"] + net["b2"])))


XOR_BOUNDS = [-1.8, 1.8, -1.8, 1.8]


def _numpy():
    try:
        import numpy as np
    except ImportError:
        raise LabError("This lab needs numpy, which is not available here.") from None
    return np


def _xor_trace(ns, rec):
    np = _numpy()
    rows, labels = _xor_data()
    X, y = np.array(rows), np.array(labels)
    net = _xor_net(np)
    losses = []
    xmin, xmax, ymin, ymax = XOR_BOUNDS
    columns, height = 20, 20
    grid_points = np.array([[xmin + (c + 0.5) * (xmax - xmin) / columns, ymax - (r + 0.5) * (ymax - ymin) / height]
                            for r in range(height) for c in range(columns)])
    rec.context = "train_step(net, X, y, lr=0.5), 600 steps on 40 noisy XOR points"
    for index in range(1, 601):
        loss = ns["train_step"](net, X, y, 0.5)
        try:
            loss = float(loss)
        except (TypeError, ValueError):
            raise LabError(f"train_step should return the loss as a number, not {short(loss, 30)}.") from None
        if index % 5 == 0 or index < 10:
            losses.append([index, round(loss, 4)])
        if not math.isfinite(loss):
            return f"The loss became {loss} at step {index}. Check the update: subtract lr times the gradient."
        if index in (1, 2, 3, 5, 8) or index % 15 == 0:
            p = _predict(np, net, X)[:, 0]
            accuracy = float(np.mean((p > 0.5) == (y[:, 0] > 0.5)))
            field = _predict(np, net, grid_points)[:, 0].reshape(height, columns)
            rec.add([
                scatter([[float(a), float(b), int(label[0])] for (a, b), label in zip(rows, labels)], bounds=XOR_BOUNDS,
                        field=[[round(float(v), 2) for v in line] for line in field],
                        title="what the network predicts: dark is 1, light is 0"),
                plot([("loss", losses[:])], title="loss (cross-entropy)"),
                variables([("step", index), ("loss", f"{loss:.4f}"), ("accuracy", f"{accuracy:.0%}"),
                           ("W2", ", ".join(f"{float(v):.2f}" for v in np.ravel(net["W2"])))]),
            ], f"step {index}: loss {loss:.3f}, {accuracy:.0%} of points right")
    first, last = losses[0][1], loss
    if last > 0.2:
        return (f"The loss went from {first:.3f} to {last:.3f} in 600 steps. "
                "The gradients are computed; now move every weight against its gradient: W1 -= lr * dW1, and so on.")
    return ""


def _xor_check(ns):
    np = _numpy()
    rows, labels = _xor_data()
    X, y = np.array(rows), np.array(labels)
    net = _xor_net(np, hidden=6, seed=11)
    for _ in range(800):
        ns["train_step"](net, X, y, 0.5)
    accuracy = float(np.mean((_predict(np, net, X)[:, 0] > 0.5) == (y[:, 0] > 0.5)))
    if accuracy < 1.0:
        return f"With 6 hidden units and another start, 800 steps reached only {accuracy:.0%} accuracy."
    return None


def _xor_scale(ns):
    np = _numpy()
    step = ns["train_step"]

    def mine(n):
        generator = np.random.default_rng(n)
        X = generator.uniform(-1, 1, (n, 2))
        y = ((X[:, :1] > 0) ^ (X[:, 1:] > 0)).astype(float)
        net = _xor_net(np)
        return lambda: [step(net, X, y, 0.5) for _ in range(20)]

    return {"what": "Runs 20 training steps on n random points (numpy does the math on whole arrays).", "x": "points n",
            "sizes": [500 * 2 ** k for k in range(9)], "series": [("your train_step", mine)]}


register("neural", {
    "perceptron": {"file": "perceptron.py", "names": [("update", "a function update(w, b, x, y, lr)")],
                   "trace": _perceptron_trace, "checks": [("learns three more data sets", _perceptron_check)], "scale": _perceptron_scale},
    "xor": {"file": "network.py", "names": [("train_step", "a function train_step(net, X, y, lr)")],
            "trace": _xor_trace, "checks": [("learns XOR from another start", _xor_check)], "scale": _xor_scale},
})

# Genetic algorithm

TARGET = "HELLO PYTHILO"
LETTERS = "ABCDEFGHIJKLMNOPQRSTUVWXYZ "


def _evolve_strings(ns, seed, generations, size=80, record=None):
    fitness, crossover, mutate = ns["fitness"], ns["crossover"], ns["mutate"]
    generator = random.Random(seed)
    population = ["".join(generator.choice(LETTERS) for _ in TARGET) for _ in range(size)]
    history = []
    for generation in range(generations + 1):
        scored = sorted(population, key=lambda c: fitness(c, TARGET), reverse=True)
        right = [sum(a == b for a, b in zip(c, TARGET)) for c in scored]
        history.append([generation, max(right), round(sum(right) / len(right), 2)])
        if record:
            record(generation, scored, history)
        if scored[0] == TARGET:
            return generation, scored[0], history
        if generation == generations:
            break
        children = scored[:2]
        while len(children) < size:
            parents = [scored[min(generator.sample(range(size), 3))] for _ in range(2)]
            child = crossover(parents[0], parents[1], generator)
            child = mutate(child, 1 / len(TARGET), generator)
            if not isinstance(child, str) or len(child) != len(TARGET):
                raise LabError(f"crossover and mutate should give a string of {len(TARGET)} letters, got {short(child, 30)}.")
            children.append(child)
        population = children
    return None, scored[0], history


def _strings_trace(ns, rec):
    def record(generation, scored, history):
        if generation > 40 and generation % 10:
            return
        top = scored[:8]
        cells = [list(c) for c in top]
        roles = [["done" if ch == TARGET[i] else "" for i, ch in enumerate(c)] for c in top]
        rec.add([
            grid(cells, roles, title=f"generation {generation}: the 8 fittest of 80, green letters are right"),
            plot([("best", [[g, b] for g, b, _ in history]), ("average", [[g, a] for g, _, a in history])],
                 title=f"letters right out of {len(TARGET)}"),
        ], f"generation {generation}: best '{top[0]}' has {history[-1][1]} of {len(TARGET)} letters right")

    rec.context = f"evolving '{TARGET}': 80 strings, keep the best 2, tournament of 3"
    solved, best, history = _evolve_strings(ns, 1, 300, record=record)
    if solved is None:
        return (f"After 300 generations the best is '{best}', with {history[-1][1]} of {len(TARGET)} letters right. "
                "Selection needs a fitness that rewards each letter in the right place.")
    return ""


def _strings_check(ns):
    fitness = ns["fitness"]
    worse, better = "HELLO PYTHIXX", "HELLO PYTHILX"
    if not fitness(better, TARGET) > fitness(worse, TARGET):
        return f"fitness('{better}') should be higher than fitness('{worse}'): it has one more letter right."
    generator = random.Random(4)
    a, b = "AAAAAAAAAAAAA", "BBBBBBBBBBBBB"
    child = ns["crossover"](a, b, generator)
    if not isinstance(child, str) or len(child) != len(a) or set(child) - {"A", "B"}:
        return f"crossover('{a}', '{b}') gave {short(child, 30)}: each letter should come from one parent, same length."
    if ns["mutate"](TARGET, 0.0, generator) != TARGET:
        return "mutate with rate 0 changed the string."
    solved = [_evolve_strings(ns, seed, 400)[0] for seed in (2, 3)]
    if None in solved:
        return "With two other random starts, evolution did not reach the target in 400 generations."
    return None


TSP_CITIES = [(0.12, 0.2), (0.3, 0.82), (0.5, 0.12), (0.85, 0.3), (0.68, 0.62), (0.2, 0.5), (0.9, 0.82),
              (0.45, 0.45), (0.62, 0.9), (0.08, 0.86), (0.35, 0.22), (0.78, 0.08)]


def _tour_length(tour, cities):
    return sum(math.dist(cities[tour[i]], cities[tour[(i + 1) % len(tour)]]) for i in range(len(tour)))


def _tour_problem(tour, count):
    if not isinstance(tour, list) or sorted(tour) != list(range(count)):
        twice = sorted({c for c in tour if tour.count(c) > 1}) if isinstance(tour, list) else []
        missing = sorted(set(range(count)) - set(tour)) if isinstance(tour, list) else []
        detail = f": city {twice[0]} twice and no city {missing[0]}" if twice and missing else ""
        return f"A child tour {short(tour, 40)} does not visit every city exactly once{detail}. Try order crossover: copy a slice of one parent, fill the rest in the other parent's order."
    return None


def _evolve_tours(ns, cities, seed, generations, size=60, record=None):
    crossover, mutate = ns["crossover"], ns["mutate"]
    generator = random.Random(seed)
    count = len(cities)
    population = []
    for _ in range(size):
        tour = list(range(count))
        generator.shuffle(tour)
        population.append(tour)
    history = []
    for generation in range(generations + 1):
        scored = sorted(population, key=lambda t: _tour_length(t, cities))
        history.append([generation, round(_tour_length(scored[0], cities), 3)])
        size = len(scored)
        if record:
            record(generation, scored, history)
        if generation == generations:
            break
        children = [list(t) for t in scored[:2]]
        while len(children) < size:
            a, b = (scored[min(generator.sample(range(size), 3))] for _ in range(2))
            child = mutate(crossover(list(a), list(b), generator), 0.2, generator)
            problem = _tour_problem(child, count)
            if problem:
                raise LabError(problem)
            children.append(child)
        population = children
    return scored[0], history


def _tsp_trace(ns, rec):
    def record(generation, scored, history):
        if generation > 60 and generation % 4:
            return
        best = scored[0]
        rec.add([
            scatter([[x, y, 0] for x, y in TSP_CITIES], path=[list(TSP_CITIES[c]) for c in best + best[:1]], bounds=[0, 1, 0, 1],
                    title=f"generation {generation}: the shortest tour of 60"),
            plot([("best length", [[g, length] for g, length in history])], title="length of the best tour"),
        ], f"generation {generation}: best tour {history[-1][1]:.3f} long")

    rec.context = "12 cities, 60 tours, keep the best 2, tournament of 3, 150 generations"
    best, history = _evolve_tours(ns, TSP_CITIES, 1, 150, record=record)
    if history[-1][1] > history[0][1] * 0.75:
        return f"After 150 generations the best tour is {history[-1][1]:.3f} long, barely shorter than the first ({history[0][1]:.3f})."
    return ""


def _optimal(cities):
    import itertools

    best = math.inf
    for order in itertools.permutations(range(1, len(cities))):
        best = min(best, _tour_length([0, *order], cities))
    return best


def _tsp_check(ns):
    generator = random.Random(8)
    for count in (3, 5, 9):
        for _ in range(5):
            a, b = list(range(count)), list(range(count))
            generator.shuffle(a)
            generator.shuffle(b)
            problem = _tour_problem(ns["crossover"](list(a), list(b), generator), count) or _tour_problem(ns["mutate"](list(a), 1.0, generator), count)
            if problem:
                return problem
    cities = [(generator.random(), generator.random()) for _ in range(8)]
    best, _ = _evolve_tours(ns, cities, 3, 120)
    optimal = _optimal(cities)
    if _tour_length(best, cities) > optimal * 1.1:
        return f"On 8 other cities it found a tour of {_tour_length(best, cities):.3f}; the shortest is {optimal:.3f}."
    return None


register("genetic", {
    "strings": {"file": "evolve.py", "names": [("fitness", "a function fitness(candidate, target)"),
                                               ("crossover", "a function crossover(a, b, rng)"), ("mutate", "a function mutate(candidate, rate, rng)")],
                "trace": _strings_trace, "checks": [("fitness, crossover and mutate, and two more runs", _strings_check)]},
    "tsp": {"file": "tours.py", "names": [("crossover", "a function crossover(a, b, rng)"), ("mutate", "a function mutate(tour, rate, rng)")],
            "trace": _tsp_trace, "checks": [("valid tours, near the shortest on 8 cities", _tsp_check)]},
})

# k-means


def _clouds(seed, count=60):
    generator = random.Random(seed)
    middles = [(-2.0, 1.5), (2.2, 1.8), (0.3, -2.0)]
    return [(middles[i % 3][0] + generator.gauss(0, 0.75), middles[i % 3][1] + generator.gauss(0, 0.75)) for i in range(count)]


def _assign(points, centers):
    return [min(range(len(centers)), key=lambda k: (p[0] - centers[k][0]) ** 2 + (p[1] - centers[k][1]) ** 2) for p in points]


def _update(points, labels, centers):
    out = []
    for k, center in enumerate(centers):
        members = [p for p, label in zip(points, labels) if label == k]
        out.append((sum(p[0] for p in members) / len(members), sum(p[1] for p in members) / len(members)) if members else tuple(center))
    return out


def _inertia(points, labels, centers):
    return sum((p[0] - centers[k][0]) ** 2 + (p[1] - centers[k][1]) ** 2 for p, k in zip(points, labels))


KMEANS_BOUNDS = [-4.5, 4.5, -4.0, 4.0]
KMEANS_START = [(-3.5, -3.0), (-3.0, -2.2), (-2.4, -3.4)]


def _run_kmeans(ns, points, centers, rounds, record=None):
    centers = [tuple(c) for c in centers]
    history, trails = [], [[list(c)] for c in centers]
    labels = None
    for round_number in range(1, rounds + 1):
        new_labels = ns["assign"](points, centers)
        if not isinstance(new_labels, list) or len(new_labels) != len(points):
            raise LabError(f"assign should return one cluster number per point, got {short(new_labels, 30)}.")
        if record:
            record(round_number, "assign", new_labels, centers, trails, history)
        new_centers = [tuple(float(v) for v in c) for c in ns["update"](points, new_labels, centers)]
        if len(new_centers) != len(centers):
            raise LabError(f"update should return {len(centers)} centers, got {len(new_centers)}.")
        for trail, center in zip(trails, new_centers):
            trail.append(list(center))
        history.append([round_number, round(_inertia(points, new_labels, new_centers), 3)])
        if record:
            record(round_number, "update", new_labels, new_centers, trails, history)
        if new_labels == labels and new_centers == centers:
            break
        labels, centers = new_labels, new_centers
    return labels, centers, history


def _kmeans_trace(ns, rec):
    points = _clouds(41)

    def record(round_number, phase, labels, centers, trails, history):
        rec.add([
            scatter([[x, y, k] for (x, y), k in zip(points, labels)], centers=[[x, y, k] for k, (x, y) in enumerate(centers)],
                    trails=trails, bounds=KMEANS_BOUNDS, title="points take the colour of their nearest center"),
            plot([("spread", history)], title="spread: total squared distance to the centers"),
            variables([("round", round_number), ("step", "assign each point" if phase == "assign" else "move each center to its points' mean")]),
        ], f"round {round_number}: " + ("each point joins its nearest center" if phase == "assign" else "each center moves to the mean of its points"))

    rec.context = "k-means with k = 3 on 60 points, from three centers bunched in a corner"
    labels, centers, history = _run_kmeans(ns, points, KMEANS_START, 12, record)
    expected_labels, expected_centers, _ = _run_kmeans({"assign": _assign, "update": _update}, points, KMEANS_START, 12)
    if [tuple(c) for c in centers] == [tuple(c) for c in KMEANS_START]:
        return "After 12 rounds the centers never moved. update should move each center to the mean of the points assigned to it."
    if any(math.dist(a, b) > 1e-6 for a, b in zip(centers, expected_centers)):
        return f"The centers ended at {', '.join(f'({x:.2f}, {y:.2f})' for x, y in centers)}, expected {', '.join(f'({x:.2f}, {y:.2f})' for x, y in expected_centers)}."
    return ""


def _kmeans_check(ns):
    generator = random.Random(42)
    for _ in range(5):
        points = [(generator.uniform(-3, 3), generator.uniform(-3, 3)) for _ in range(50)]
        start = generator.sample(points, 4)
        labels = ns["assign"](points, start)
        if labels != _assign(points, start):
            index = next(i for i, (a, b) in enumerate(zip(labels, _assign(points, start))) if a != b)
            return f"assign put point {index} with center {labels[index]}, but center {_assign(points, start)[index]} is nearer."
        _, centers, _ = _run_kmeans(ns, points, start, 20)
        _, expected, _ = _run_kmeans({"assign": _assign, "update": _update}, points, start, 20)
        if any(math.dist(a, b) > 1e-6 for a, b in zip(centers, expected)):
            return "On another data set the centers did not end where k-means puts them."
    return None


def _kmeans_scale(ns):
    def mine(n):
        generator = random.Random(n)
        points = [(generator.uniform(-3, 3), generator.uniform(-3, 3)) for _ in range(n)]
        start = points[:5]
        return lambda: _run_kmeans(ns, points, start, 5)

    return {"what": "Runs 5 rounds of k-means with k = 5 on n random points.", "x": "points n",
            "sizes": [250 * 2 ** k for k in range(8)], "series": [("your assign and update", mine)]}


register("kmeans", {
    "kmeans": {"file": "kmeans.py", "names": [("assign", "a function assign(points, centers)"), ("update", "a function update(points, labels, centers)")],
               "trace": _kmeans_trace, "checks": [("matches k-means on 5 more data sets", _kmeans_check)], "scale": _kmeans_scale},
})

# Q-learning

WORLD = [
    "S...#....",
    ".##.#.##.",
    ".#.....#.",
    ".#.###.#.",
    "...#...#G",
]
MOVES = [(-1, 0, "↑"), (1, 0, "↓"), (0, -1, "←"), (0, 1, "→")]


def _cells(char):
    return [(r, c) for r, row in enumerate(WORLD) for c, value in enumerate(row) if value == char]


def _move(state, action):
    r, c = state
    dr, dc, _ = MOVES[action]
    nr, nc = r + dr, c + dc
    if not (0 <= nr < len(WORLD) and 0 <= nc < len(WORLD[0])) or WORLD[nr][nc] == "#":
        return state, -1.0
    if WORLD[nr][nc] == "G":
        return (nr, nc), 10.0
    return (nr, nc), -0.1


def _greedy_path(Q, start, goal, limit=60):
    state, path = start, [start]
    while state != goal and len(path) < limit:
        values = Q[state]
        state, _ = _move(state, max(range(4), key=lambda a: values[a]))
        path.append(state)
    return path


def _shortest(start, goal):
    from collections import deque

    seen, queue = {start: 0}, deque([start])
    while queue:
        state = queue.popleft()
        for action in range(4):
            nxt, _ = _move(state, action)
            if nxt not in seen:
                seen[nxt] = seen[state] + 1
                queue.append(nxt)
    return seen[goal]


def _q_learn(ns, episodes, seed, record=None):
    update = ns["update"]
    generator = random.Random(seed)
    start, goal = _cells("S")[0], _cells("G")[0]
    Q = {(r, c): [0.0] * 4 for r in range(len(WORLD)) for c in range(len(WORLD[0]))}
    lengths = []
    for episode in range(1, episodes + 1):
        state, steps, visited = start, 0, [start]
        epsilon = max(0.05, 1.0 - episode / (episodes * 0.6))
        while state != goal and steps < 200:
            action = generator.randrange(4) if generator.random() < epsilon else max(range(4), key=lambda a: (Q[state][a], -a))
            nxt, reward = _move(state, action)
            got = update(Q, state, action, reward, nxt, 0.5, 0.95)
            if got is not None:
                raise LabError("update should change Q[state][action] in place and return nothing.")
            state, steps = nxt, steps + 1
            visited.append(state)
        lengths.append([episode, steps])
        if record:
            record(episode, Q, visited, lengths)
    return Q, lengths


def _q_trace(ns, rec):
    start, goal = _cells("S")[0], _cells("G")[0]

    def record(episode, Q, visited, lengths):
        if episode > 40 and episode % 5:
            return
        best = max(max(values) for values in Q.values()) or 1
        low = min(max(values) for values in Q.values())
        cells, roles, heat = [], [], []
        walked = set(visited)
        for r, row in enumerate(WORLD):
            line_cells, line_roles, line_heat = [], [], []
            for c, value in enumerate(row):
                values = Q[(r, c)]
                if value == "#":
                    line_cells.append("")
                    line_roles.append("wall")
                elif value == "G":
                    line_cells.append("★")
                    line_roles.append("done")
                else:
                    line_cells.append(MOVES[max(range(4), key=lambda a: (values[a], -a))][2] if any(values) else "·")
                    line_roles.append("focus" if (r, c) in walked else "")
                line_heat.append(round((max(values) - low) / ((best - low) or 1), 2))
            cells.append(line_cells)
            roles.append(line_roles)
            heat.append(line_heat)
        rec.add([
            grid(cells, roles, heat=heat, title=f"episode {episode}: arrows are the best move so far; outlined cells were walked"),
            plot([("steps to the goal", lengths[:])], title="steps per episode"),
            variables([("episode", episode), ("steps this episode", lengths[-1][1]), ("shortest possible", _shortest(start, goal))]),
        ], f"episode {episode}: reached the goal in {lengths[-1][1]} steps" if lengths[-1][1] < 200 else f"episode {episode}: gave up after 200 steps")

    rec.context = "Q-learning: alpha 0.5, gamma 0.95, 150 episodes, exploring less as it learns"
    Q, lengths = _q_learn(ns, 150, 1, record)
    path = _greedy_path(Q, start, goal)
    if path[-1] != goal:
        return ("After 150 episodes, following the best arrows from S does not reach the goal. "
                "The update should pull Q[state][action] toward reward + gamma * max(Q[next_state]).")
    if len(path) - 1 > _shortest(start, goal) + 2:
        return f"The learned route takes {len(path) - 1} steps; the shortest takes {_shortest(start, goal)}."
    return ""


def _q_check(ns):
    Q = {(0, 0): [0.0, 0.0, 0.0, 0.0], (0, 1): [1.0, 2.0, 0.0, 0.5]}
    ns["update"](Q, (0, 0), 3, -0.1, (0, 1), 0.5, 0.9)
    expected = 0.5 * (-0.1 + 0.9 * 2.0)
    if abs(Q[(0, 0)][3] - expected) > 1e-9:
        return (f"From Q = 0, reward -0.1, alpha 0.5, gamma 0.9 and a next state whose best value is 2.0, "
                f"Q[state][action] became {Q[(0, 0)][3]!r}, expected {expected:.3f}.")
    start, goal = _cells("S")[0], _cells("G")[0]
    Q, _ = _q_learn(ns, 200, 7)
    if _greedy_path(Q, start, goal)[-1] != goal:
        return "With another random seed, the learned arrows do not lead to the goal."
    return None


register("qlearning", {
    "grid": {"file": "qlearning.py", "names": [("update", "a function update(Q, state, action, reward, next_state, alpha, gamma)")],
             "trace": _q_trace, "checks": [("one update by hand, and another run", _q_check)]},
})
