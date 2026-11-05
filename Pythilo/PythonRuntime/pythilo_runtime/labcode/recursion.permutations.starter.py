def permutations(items):
    if not items:
        return []  # TODO: how many ways are there to order nothing?
    result = []
    for i, first in enumerate(items):
        rest = items[:i] + items[i + 1:]
        for tail in permutations(rest):
            result.append([first] + tail)
    return result
