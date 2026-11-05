def folds(n, k):
    result = []
    start = 0
    for fold in range(k):
        size = n // k + (fold < n % k)
        stop = start + size
        validation = list(range(start, stop))
        training = list(range(start)) + list(range(stop, n))
        result.append((training, validation))
        start = stop
    return result
