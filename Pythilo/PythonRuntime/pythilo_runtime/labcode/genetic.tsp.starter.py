# A tour is a list of city numbers; it visits each city once and returns home.


def crossover(a, b, rng):
    # TODO: cutting and joining like this repeats some cities and drops others.
    cut = rng.randrange(1, len(a))
    return a[:cut] + b[cut:]


def mutate(tour, rate, rng):
    # Sometimes swap two cities.
    tour = list(tour)
    if rng.random() < rate:
        i, j = rng.randrange(len(tour)), rng.randrange(len(tour))
        tour[i], tour[j] = tour[j], tour[i]
    return tour
