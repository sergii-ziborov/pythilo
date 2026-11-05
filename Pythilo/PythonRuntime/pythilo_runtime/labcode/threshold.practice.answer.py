def choose_threshold(scores, labels, candidates):
    best, best_f1 = None, -1.0
    for threshold in sorted(candidates):
        predictions = [int(score >= threshold) for score in scores]
        tp = sum(a == p == 1 for a, p in zip(labels, predictions))
        fp = sum(a == 0 and p == 1 for a, p in zip(labels, predictions))
        fn = sum(a == 1 and p == 0 for a, p in zip(labels, predictions))
        f1 = 2 * tp / (2 * tp + fp + fn) if 2 * tp + fp + fn else 0.0
        if f1 > best_f1:
            best, best_f1 = threshold, f1
    return best
