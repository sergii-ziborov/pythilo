import math
import numpy as np


def _fit_base(rows, degree):
    x = np.asarray([[row['x'] ** p for p in range(1, degree + 1)] for row in rows])
    y = np.asarray([row['y'] for row in rows])
    mx, my = x.mean(axis=0), float(y.mean())
    centered = x - mx
    w = np.linalg.solve(centered.T @ centered + .1 * np.eye(degree), centered.T @ (y - my))
    return w, my - float(mx @ w)


def _predict_base(model, row):
    w, b = model
    return b + sum(float(weight) * row['x'] ** (i + 1) for i, weight in enumerate(w))


def stacked_regression(rows, test):
    if len(rows) < 4 or not test:
        raise ValueError('at least four training rows and test features required')
    if len({row['id'] for row in rows + test}) != len(rows + test):
        raise ValueError('disjoint unique sample identities required')
    if any(not math.isfinite(row['x']) for row in rows + test):
        raise ValueError('finite features required')
    if any(not math.isfinite(row['y']) for row in rows):
        raise ValueError('finite targets required')
    folds = sorted(set(row['fold'] for row in rows))
    if len(folds) < 2:
        raise ValueError('at least two folds required')
    oof, audits = {}, []
    for fold in folds:
        train = [row for row in rows if row['fold'] != fold]
        held = [row for row in rows if row['fold'] == fold]
        if len(train) < 2:
            raise ValueError('every base fit needs two rows')
        models = [_fit_base(train, degree) for degree in (1, 2)]
        for row in held:
            oof[row['id']] = [_predict_base(model, row) for model in models]
        audits.append({'fold': fold, 'fit_ids': [row['id'] for row in train],
                       'held_ids': [row['id'] for row in held]})
    z = np.asarray([oof[row['id']] for row in rows])
    y = np.asarray([row['y'] for row in rows])
    means, center = z.mean(axis=0), float(y.mean())
    centered = z - means
    weights = np.linalg.solve(centered.T @ centered + .001 * np.eye(2), centered.T @ (y - center))
    bias = center - float(means @ weights)
    full = [_fit_base(rows, degree) for degree in (1, 2)]
    predictions = [bias + sum(float(w) * _predict_base(model, row)
                   for w, model in zip(weights, full)) for row in test]
    return {'oof': oof, 'folds': audits, 'weights': weights.tolist(),
            'bias': bias, 'predictions': predictions}
