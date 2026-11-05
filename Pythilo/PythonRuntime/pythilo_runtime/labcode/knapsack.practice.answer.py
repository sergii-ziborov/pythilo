def pack(items, capacity):
    best = [0] * (capacity + 1)
    for weight, value in items:
        for room in range(capacity, weight - 1, -1):
            best[room] = max(best[room], best[room - weight] + value)
    return best[capacity]
