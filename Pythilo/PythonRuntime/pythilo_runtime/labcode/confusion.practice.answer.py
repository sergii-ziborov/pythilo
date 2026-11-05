def confusion(actual, predicted, classes):
    matrix = [[0] * classes for _ in range(classes)]
    for truth, guess in zip(actual, predicted):
        matrix[truth][guess] += 1
    return matrix
