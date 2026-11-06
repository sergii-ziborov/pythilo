import math
import random


def cluster_interval(groups, deltas, repetitions, seed):
    if not groups or len(groups) != len(deltas):
        raise ValueError('aligned groups and deltas required')
    if any(not isinstance(g, str) for g in groups):
        raise ValueError('string group identities required')
    if any(not math.isfinite(x) for x in deltas):
        raise ValueError('finite paired differences required')
    if type(repetitions) is not int or repetitions < 2:
        raise ValueError('at least two repetitions required')
    buckets = {}
    for group, delta in zip(groups, deltas):
        buckets.setdefault(group, []).append(delta)
    means = [sum(buckets[g]) / len(buckets[g]) for g in sorted(buckets)]
    if len(means) < 2:
        raise ValueError('at least two independent groups required')
    rng = random.Random(seed)
    samples = []
    for _ in range(repetitions):
        draw = [rng.choice(means) for _ in means]
        samples.append(sum(draw) / len(draw))
    samples.sort()
    def percentile(q):
        position = (len(samples) - 1) * q
        left = math.floor(position)
        right = math.ceil(position)
        return samples[left] + (samples[right] - samples[left]) * (position - left)
    return {'estimate': sum(means) / len(means), 'low': percentile(.025),
            'high': percentile(.975), 'groups': len(means)}
