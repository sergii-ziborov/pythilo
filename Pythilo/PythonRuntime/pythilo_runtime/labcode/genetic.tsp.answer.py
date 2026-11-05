# A tour is a list of city numbers; it visits each city once and returns home.


def crossover(a, b, rng):
    # Order crossover: keep a slice of a, then the other cities in b's order.
    i, j = sorted(rng.sample(range(len(a) + 1), 2))
    middle = a[i:j]
    rest = [city for city in b if city not in middle]
    return rest[:i] + middle + rest[i:]


def mutate(tour, rate, rng):
    # Sometimes reverse a stretch of the tour, which undoes a crossing.
    tour = list(tour)
    if rng.random() < rate:
        i, j = sorted(rng.sample(range(len(tour) + 1), 2))
        tour[i:j] = reversed(tour[i:j])
    return tour
