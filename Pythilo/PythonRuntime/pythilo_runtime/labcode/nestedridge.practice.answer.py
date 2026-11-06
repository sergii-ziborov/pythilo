import math


def _fit(rows, alpha):
    mx = sum(row['x'] for row in rows) / len(rows)
    my = sum(row['y'] for row in rows) / len(rows)
    numerator = sum((row['x'] - mx) * (row['y'] - my) for row in rows)
    denominator = sum((row['x'] - mx) ** 2 for row in rows) + alpha
    slope = numerator / denominator
    return slope, my - slope * mx


def nested_group_ridge(rows, alphas):
    if not rows or not alphas:
        raise ValueError('rows and penalty candidates required')
    ids = [row['id'] for row in rows]
    if any(not isinstance(row['id'], str) or not isinstance(row['group'], str) for row in rows):
        raise ValueError('string sample and group identities required')
    if len(ids) != len(set(ids)):
        raise ValueError('sample identities must be unique')
    groups = sorted(set(row['group'] for row in rows))
    if len(groups) < 3:
        raise ValueError('at least three independent groups required')
    if any(not math.isfinite(row[key]) for row in rows for key in ('x', 'y')):
        raise ValueError('finite observations required')
    if any(not math.isfinite(alpha) or alpha <= 0 for alpha in alphas):
        raise ValueError('positive penalties required')
    oof, audits = {}, []
    for outer in groups:
        remaining = [row for row in rows if row['group'] != outer]
        trials = []
        for alpha in sorted(set(alphas)):
            errors = []
            for inner in groups:
                if inner == outer:
                    continue
                fit = [row for row in remaining if row['group'] != inner]
                held = [row for row in remaining if row['group'] == inner]
                slope, intercept = _fit(fit, alpha)
                errors.append(sum((slope * row['x'] + intercept - row['y']) ** 2
                                  for row in held) / len(held))
            trials.append((sum(errors) / len(errors), alpha))
        _, selected = min(trials)
        slope, intercept = _fit(remaining, selected)
        held = [row for row in rows if row['group'] == outer]
        for row in held:
            oof[row['id']] = slope * row['x'] + intercept
        audits.append({'group': outer, 'alpha': selected,
                       'fit_ids': [row['id'] for row in remaining],
                       'held_ids': [row['id'] for row in held]})
    mse = sum((oof[row['id']] - row['y']) ** 2 for row in rows) / len(rows)
    return {'oof': oof, 'mse': mse, 'folds': audits}
