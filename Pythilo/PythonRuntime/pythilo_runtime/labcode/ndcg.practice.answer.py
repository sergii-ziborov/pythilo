import math


def ndcg(ranking, grades, k):
    if type(k) is not int or k <= 0:
        raise ValueError('positive integer cutoff required')
    if any(type(g) is not int or not 0 <= g <= 10 for g in grades.values()):
        raise ValueError('integer relevance grades in 0..10 required')
    unique = list(dict.fromkeys(ranking))[:k]
    gains = [2 ** grades.get(key, 0) - 1 for key in unique]
    ideal = sorted((2 ** g - 1 for g in grades.values()), reverse=True)[:k]
    dcg = sum(gain / math.log2(i + 2) for i, gain in enumerate(gains))
    best = sum(gain / math.log2(i + 2) for i, gain in enumerate(ideal))
    result = dcg / best if best else None
    return result
