import math


def isotonic_fit(scores, labels, weights):
    if not scores or not len(scores) == len(labels) == len(weights):
        raise ValueError('aligned nonempty observations required')
    if any(not math.isfinite(s) for s in scores):
        raise ValueError('finite scores required')
    if any(type(y) is not int or y not in (0, 1) for y in labels):
        raise ValueError('binary labels required')
    if any(not math.isfinite(w) or w <= 0 for w in weights):
        raise ValueError('positive weights required')
    tied = {}
    for score, label, weight in zip(scores, labels, weights):
        total, positive = tied.get(score, (0, 0))
        tied[score] = (total + weight, positive + label * weight)
    blocks = []
    for score in sorted(tied):
        weight, positive = tied[score]
        blocks.append([score, score, weight, positive])
        while len(blocks) > 1 and blocks[-2][3] / blocks[-2][2] > blocks[-1][3] / blocks[-1][2]:
            right = blocks.pop()
            left = blocks.pop()
            blocks.append([left[0], right[1], left[2] + right[2], left[3] + right[3]])
    result = [[low, high, positive / weight] for low, high, weight, positive in blocks]
    return result
