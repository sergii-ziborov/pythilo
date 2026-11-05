LETTERS = "ABCDEFGHIJKLMNOPQRSTUVWXYZ "


def fitness(candidate, target):
    # TODO: score how close candidate is to target. Higher is better.
    return 0


def crossover(a, b, rng):
    # A child takes the start of one parent and the rest of the other.
    cut = rng.randrange(len(a))
    return a[:cut] + b[cut:]


def mutate(candidate, rate, rng):
    # Each letter has a small chance to change at random.
    return "".join(rng.choice(LETTERS) if rng.random() < rate else ch for ch in candidate)
