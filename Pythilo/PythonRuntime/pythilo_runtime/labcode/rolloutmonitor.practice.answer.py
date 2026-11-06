import copy
import hashlib
import json
import math


def monitor_rollout(state, window, predictions, outcomes, asof, min_pairs, tolerance):
    if type(window) is not int or window < 0 or type(min_pairs) is not int or min_pairs < 1:
        raise ValueError('valid window and minimum paired sample count required')
    if not math.isfinite(asof) or not math.isfinite(tolerance) or tolerance < 0:
        raise ValueError('finite cutoff and nonnegative tolerance required')
    payload = [window, predictions, outcomes, asof, min_pairs, tolerance]
    digest = hashlib.sha256(json.dumps(payload, sort_keys=True, allow_nan=False).encode()).hexdigest()
    previous = state.get('window', -1)
    if window == previous:
        if digest != state.get('digest'):
            raise ValueError('conflicting replay of a monitoring window')
        return copy.deepcopy(state)
    if window < previous:
        raise ValueError('monitoring windows must move forward')
    ids = [row['id'] for row in predictions]
    if len(ids) != len(set(ids)) or len({row['id'] for row in outcomes}) != len(outcomes):
        raise ValueError('unique prediction and outcome identities required')
    if any(not math.isfinite(row[key]) or not 0 <= row[key] <= 1
           for row in predictions for key in ('baseline', 'candidate')):
        raise ValueError('valid probability predictions required')
    if any(type(row['y']) is not int or row['y'] not in (0, 1)
           or not math.isfinite(row['available']) for row in outcomes):
        raise ValueError('binary outcomes and finite availability times required')
    known = {row['id']: row for row in outcomes if row['available'] <= asof}
    cohorts = {}
    for row in predictions:
        if row['id'] not in known:
            continue
        y = known[row['id']]['y']
        delta = (row['candidate'] - y) ** 2 - (row['baseline'] - y) ** 2
        cohorts.setdefault(row['cohort'], []).append(delta)
    expected = sorted(set(row['cohort'] for row in predictions))
    coverage = {cohort: len(cohorts.get(cohort, [])) for cohort in expected}
    deltas = {cohort: sum(values) / len(values) for cohort, values in cohorts.items()}
    enough = bool(expected) and all(coverage[cohort] >= min_pairs for cohort in expected)
    bad = enough and any(delta > tolerance for delta in deltas.values())
    bad_windows = state.get('bad_windows', 0) + 1 if bad else 0
    status = 'rollback' if state.get('status') == 'rollback' or bad_windows >= 2 else 'hold'
    if status != 'rollback' and enough and not bad:
        status = 'continue'
    return {'window': window, 'digest': digest, 'bad_windows': bad_windows,
            'status': status, 'coverage': coverage, 'deltas': deltas}
