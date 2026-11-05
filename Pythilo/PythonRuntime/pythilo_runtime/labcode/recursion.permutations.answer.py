def permutations(items):
    if not items:
        return [[]]  # one way to order nothing: the empty ordering
    result = []
    for i, first in enumerate(items):
        rest = items[:i] + items[i + 1:]
        for tail in permutations(rest):
            result.append([first] + tail)
    return result
