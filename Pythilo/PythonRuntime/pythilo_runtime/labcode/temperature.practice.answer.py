import math


def fit_temperature(logits, labels, grid):
    if not grid or any(not math.isfinite(t) or t <= 0 for t in grid):
        raise ValueError('positive finite temperature grid required')
    if not logits or len(logits) != len(labels):
        raise ValueError('aligned calibration data required')
    width = len(logits[0])
    if width < 2 or any(len(row) != width for row in logits):
        raise ValueError('rectangular multiclass logits required')
    if any(not math.isfinite(x) for row in logits for x in row):
        raise ValueError('finite logits required')
    if any(type(y) is not int or not 0 <= y < width for y in labels):
        raise ValueError('invalid class identity')
    scores = []
    for temperature in sorted(set(grid)):
        losses = []
        for row, target in zip(logits, labels):
            scaled = [x / temperature for x in row]
            peak = max(scaled)
            losses.append(math.log(sum(math.exp(x - peak) for x in scaled))
                          + peak - scaled[target])
        scores.append((sum(losses) / len(losses), temperature))
    loss, temperature = min(scores)
    return {'temperature': temperature, 'loss': loss}
