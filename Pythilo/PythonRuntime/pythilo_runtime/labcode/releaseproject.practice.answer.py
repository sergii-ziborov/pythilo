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


def evaluate_release(baseline, candidate, policy):
    required = {'minimum', 'max_cost', 'p95_latency', 'tolerance', 'repetitions', 'seed'}
    if set(policy) != required:
        raise ValueError('exact release policy required')
    if not baseline or len({r['id'] for r in baseline}) != len(baseline):
        raise ValueError('unique baseline evaluation identities required')
    if len({r['id'] for r in candidate}) != len(candidate):
        raise ValueError('duplicate candidate evaluation identities')
    old = {r['id']: r for r in baseline}
    new = {r['id']: r for r in candidate}
    if old.keys() != new.keys():
        raise ValueError('candidate must cover exactly the paired evaluation inventory')
    if any(not math.isfinite(policy[k]) or policy[k] < 0 for k in ('max_cost', 'p95_latency', 'tolerance')):
        raise ValueError('finite nonnegative policy thresholds required')
    if any(type(n) is not int or n < 1 for n in policy['minimum'].values()):
        raise ValueError('positive category sample requirements required')
    coverage, groups, deltas = {}, [], []
    for key in sorted(old):
        before, after = old[key], new[key]
        if (before['category'], before['group']) != (after['category'], after['group']):
            raise ValueError('paired category and independent group identities must agree')
        for row in (before, after):
            if not math.isfinite(row['quality']) or not 0 <= row['quality'] <= 1:
                raise ValueError('quality must be a finite grade in 0..1')
            if any(not math.isfinite(row[k]) or row[k] < 0 for k in ('cost', 'latency')) or type(row['safe']) is not bool:
                raise ValueError('nonnegative measurements and explicit safety outcomes required')
        category = before['category']
        coverage[category] = coverage.get(category, 0) + 1
        groups.append(before['group'])
        deltas.append(after['quality'] - before['quality'])
    interval = cluster_interval(groups, deltas, policy['repetitions'], policy['seed'])
    latencies = sorted(row['latency'] for row in candidate)
    p95 = latencies[math.ceil(.95 * len(latencies)) - 1]
    mean_cost = sum(row['cost'] for row in candidate) / len(candidate)
    reasons = []
    if coverage.keys() != policy['minimum'].keys() or any(coverage.get(k, 0) < n for k, n in policy['minimum'].items()):
        reasons.append('coverage')
    if any(not row['safe'] for row in candidate):
        reasons.append('safety')
    if interval['low'] < -policy['tolerance']:
        reasons.append('quality')
    if mean_cost > policy['max_cost']:
        reasons.append('cost')
    if p95 > policy['p95_latency']:
        reasons.append('latency')
    return {'promote': not reasons, 'reasons': reasons, 'coverage': coverage,
            'quality': interval, 'mean_cost': mean_cost, 'p95_latency': p95}
