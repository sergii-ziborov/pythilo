import math


def multiclass_loss(logits, labels, weights):
    if not logits or len(logits) != len(labels) or len(labels) != len(weights):
        raise ValueError('aligned nonempty batches required')
    width = len(logits[0])
    if width < 2 or any(len(row) != width for row in logits):
        raise ValueError('a rectangular multiclass matrix is required')
    if any(not math.isfinite(x) for row in logits for x in row):
        raise ValueError('finite logits required')
    if any(type(y) is not int or not 0 <= y < width for y in labels):
        raise ValueError('class index outside the matrix')
    if any(not math.isfinite(w) or w < 0 for w in weights) or sum(weights) <= 0:
        raise ValueError('nonnegative weights with positive total required')
    losses = []
    for row, target in zip(logits, labels):
        maximum = max(row)
        normalizer = math.log(sum(math.exp(x - maximum) for x in row))
        losses.append(normalizer + maximum - row[target])
    result = sum(w * loss for w, loss in zip(weights, losses)) / sum(weights)
    return result
