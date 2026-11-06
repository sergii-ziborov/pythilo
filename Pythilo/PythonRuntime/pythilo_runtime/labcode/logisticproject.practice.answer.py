import math
import numpy as np


def train_logistic(train, validation, test, learning_rate, steps, l2):
    if any(not part for part in (train, validation, test)):
        raise ValueError('nonempty train, validation and test partitions required')
    all_rows = train + validation + test
    if len({row['id'] for row in all_rows}) != len(all_rows):
        raise ValueError('sample identities must be disjoint')
    width = len(train[0]['x'])
    if not width or any(len(row['x']) != width for row in all_rows):
        raise ValueError('consistent feature dimensions required')
    if any(not math.isfinite(x) for row in all_rows for x in row['x']):
        raise ValueError('finite features required')
    if any(type(row['y']) is not int or row['y'] not in (0, 1) for row in all_rows):
        raise ValueError('binary integer labels required')
    if not math.isfinite(learning_rate) or learning_rate <= 0 or type(steps) is not int or steps < 1:
        raise ValueError('positive learning rate and integer step budget required')
    if not math.isfinite(l2) or l2 < 0:
        raise ValueError('nonnegative finite penalty required')
    x = np.asarray([row['x'] for row in train], dtype=float)
    y = np.asarray([row['y'] for row in train], dtype=float)
    means, scales = x.mean(axis=0), x.std(axis=0)
    scales[scales == 0] = 1
    x = (x - means) / scales
    vx = (np.asarray([row['x'] for row in validation]) - means) / scales
    vy = np.asarray([row['y'] for row in validation])
    w, b = np.zeros(width), 0.0
    best, history = None, []
    for step in range(1, steps + 1):
        logits = x @ w + b
        probabilities = np.exp(-np.logaddexp(0, -logits))
        error = probabilities - y
        w = w - learning_rate * (x.T @ error / len(y) + l2 * w)
        b = b - learning_rate * float(error.mean())
        score = vx @ w + b
        loss = float(np.mean(np.logaddexp(0, score) - vy * score))
        history.append(loss)
        if best is None or loss < best[0]:
            best = (loss, step, w.copy(), b)
    validation_loss, best_step, w, b = best
    tx = (np.asarray([row['x'] for row in test]) - means) / scales
    ty = np.asarray([row['y'] for row in test])
    logits = tx @ w + b
    test_loss = float(np.mean(np.logaddexp(0, logits) - ty * logits))
    return {'weights': w.tolist(), 'bias': b, 'means': means.tolist(),
            'scales': scales.tolist(), 'best_step': best_step, 'history': history,
            'validation_loss': validation_loss, 'test_loss': test_loss,
            'predictions': (logits >= 0).astype(int).tolist()}
