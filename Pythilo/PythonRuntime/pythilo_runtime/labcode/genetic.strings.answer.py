LETTERS = "ABCDEFGHIJKLMNOPQRSTUVWXYZ "


def fitness(candidate, target):
    # One point for each letter in the right place.
    return sum(1 for a, b in zip(candidate, target) if a == b)


def crossover(a, b, rng):
    # A child takes the start of one parent and the rest of the other.
    cut = rng.randrange(len(a))
    return a[:cut] + b[cut:]


def mutate(candidate, rate, rng):
    # Each letter has a small chance to change at random.
    return "".join(rng.choice(LETTERS) if rng.random() < rate else ch for ch in candidate)
