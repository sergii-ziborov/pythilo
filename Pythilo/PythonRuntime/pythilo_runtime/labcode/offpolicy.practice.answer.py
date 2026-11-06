import math


def offpolicy_value(events, clip):
    if not events or not math.isfinite(clip) or clip <= 0:
        raise ValueError('events and a positive clipping bound required')
    weights = []
    contributions = []
    for event in events:
        reward, propensity, target = event
        if not all(math.isfinite(x) for x in event):
            raise ValueError('finite logged values required')
        if not 0 < propensity <= 1 or not 0 <= target <= 1:
            raise ValueError('logging support and valid target probabilities required')
        weight = min(target / propensity, clip)
        weights.append(weight)
        contributions.append(weight * reward)
    squared = sum(w * w for w in weights)
    return {'value': sum(contributions) / len(events),
            'ess': sum(weights) ** 2 / squared if squared else 0,
            'mean_weight': sum(weights) / len(events)}
