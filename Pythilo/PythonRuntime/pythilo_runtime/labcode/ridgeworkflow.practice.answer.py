import math
import numpy as np


def _ridge_fit(rows, alpha):
    x = np.asarray([row['x'] for row in rows], dtype=float)
    y = np.asarray([row['y'] for row in rows], dtype=float)
    means = x.mean(axis=0)
    scales = x.std(axis=0)
    scales[scales == 0] = 1
    z = (x - means) / scales
    intercept = float(y.mean())
    coefficients = np.linalg.solve(z.T @ z + alpha * np.eye(z.shape[1]),
                                   z.T @ (y - intercept))
    return {'means': means.tolist(), 'scales': scales.tolist(),
            'coefficients': coefficients.tolist(), 'intercept': intercept}


def _ridge_predict(model, rows):
    return [model['intercept'] + sum((x - m) / s * w for x, m, s, w in
            zip(row['x'], model['means'], model['scales'], model['coefficients']))
            for row in rows]


def ridge_workflow(train, validation, test, alphas):
    partitions = [train, validation, test]
    if any(not part for part in partitions) or not alphas:
        raise ValueError('three nonempty partitions and regularization candidates required')
    rows = train + validation + test
    ids = [row['id'] for row in rows]
    if any(not isinstance(key, str) for key in ids) or len(set(ids)) != len(ids):
        raise ValueError('sample identities must be unique across partitions')
    width = len(train[0]['x'])
    if not width or any(len(row['x']) != width for row in rows):
        raise ValueError('feature dimensions must agree')
    if any(not math.isfinite(v) for row in rows for v in row['x'] + [row['y']]):
        raise ValueError('finite numeric observations required')
    if any(not math.isfinite(alpha) or alpha <= 0 for alpha in alphas):
        raise ValueError('positive finite ridge penalties required')
    trials = []
    for alpha in sorted(set(alphas)):
        model = _ridge_fit(train, alpha)
        predictions = _ridge_predict(model, validation)
        mse = sum((p - row['y']) ** 2 for p, row in zip(predictions, validation)) / len(validation)
        trials.append((mse, alpha))
    validation_mse, selected = min(trials)
    artifact = _ridge_fit(train + validation, selected)
    predictions = _ridge_predict(artifact, test)
    test_mse = sum((p - row['y']) ** 2 for p, row in zip(predictions, test)) / len(test)
    result = {'alpha': selected, 'validation_mse': validation_mse,
              'test_mse': test_mse, 'predictions': predictions, 'artifact': artifact,
              'fit_ids': [row['id'] for row in train + validation]}
    return result
