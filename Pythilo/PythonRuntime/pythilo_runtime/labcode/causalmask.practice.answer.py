def causal_weights(scores):
    import math
    matrix = []
    for i, row in enumerate(scores):
        maximum = max(row[:i+1])
        weights = [math.exp(value-maximum) if j <= i else 0.0 for j,value in enumerate(row)]
        total = sum(weights)
        matrix.append([weight/total for weight in weights])
    return matrix
