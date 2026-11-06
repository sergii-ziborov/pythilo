import math


def _fit(rows):
    mx = sum(row['x'] for row in rows) / len(rows)
    my = sum(row['y'] for row in rows) / len(rows)
    slope = sum((row['x'] - mx) * (row['y'] - my) for row in rows)
    slope /= sum((row['x'] - mx) ** 2 for row in rows) + .1
    return slope, my - slope * mx


def walkforward_forecast(rows, cutoffs, horizon, gap):
    if not cutoffs or not math.isfinite(horizon) or horizon <= 0 or gap < 0 or not math.isfinite(gap):
        raise ValueError('cutoffs, positive horizon and nonnegative gap required')
    if any(not math.isfinite(t) for t in cutoffs):
        raise ValueError('finite cutoffs required')
    if len(set(cutoffs)) != len(cutoffs) or cutoffs != sorted(cutoffs):
        raise ValueError('strictly increasing cutoffs required')
    if len({row['id'] for row in rows}) != len(rows):
        raise ValueError('unique sample identities required')
    if any(not math.isfinite(row[key]) for row in rows for key in ('t', 'available', 'x', 'y')):
        raise ValueError('finite rows required')
    if any(row['available'] < row['t'] for row in rows):
        raise ValueError('label availability cannot precede its event')
    windows = []
    for cutoff in cutoffs:
        train = [row for row in rows if row['t'] <= cutoff - gap and row['available'] <= cutoff]
        held = [row for row in rows if cutoff < row['t'] <= cutoff + horizon]
        if len(train) < 2 or not held:
            windows.append({'cutoff': cutoff, 'status': 'insufficient'})
            continue
        slope, intercept = _fit(train)
        predictions = [slope * row['x'] + intercept for row in held]
        mse = sum((p - row['y']) ** 2 for p, row in zip(predictions, held)) / len(held)
        windows.append({'cutoff': cutoff, 'status': 'evaluated',
                        'train_ids': [row['id'] for row in train],
                        'held_ids': [row['id'] for row in held],
                        'predictions': predictions, 'mse': mse})
    return windows
