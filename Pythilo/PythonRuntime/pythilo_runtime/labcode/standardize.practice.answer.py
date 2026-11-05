def normalize(train, values):
    import math
    mean = sum(train) / len(train)
    variance = sum((x - mean) ** 2 for x in train) / len(train)
    scale = math.sqrt(variance) or 1.0
    result = [(x - mean) / scale for x in values]
    return result
