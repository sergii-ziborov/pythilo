import math


def mmr_select(query, documents, k, relevance_weight):
    if type(k) is not int or k < 0 or not 0 <= relevance_weight <= 1:
        raise ValueError('nonnegative cutoff and weight in 0..1 required')
    if not query or any(not math.isfinite(x) for x in query):
        raise ValueError('finite nonempty query vector required')
    if any(not isinstance(doc['id'], str) for doc in documents):
        raise ValueError('string document identities required')
    if len({doc['id'] for doc in documents}) != len(documents):
        raise ValueError('unique document identities required')
    if any(len(doc['vector']) != len(query) or any(not math.isfinite(x) for x in doc['vector'])
           for doc in documents):
        raise ValueError('aligned finite vectors required')
    def cosine(a, b):
        denominator = math.sqrt(sum(x*x for x in a) * sum(x*x for x in b))
        return sum(x*y for x, y in zip(a, b)) / denominator if denominator else 0
    remaining = list(documents)
    selected = []
    while remaining and len(selected) < k:
        scores = []
        for doc in remaining:
            similarity = cosine(query, doc['vector'])
            redundancy = max((cosine(doc['vector'], other['vector']) for other in selected), default=0)
            score = relevance_weight * similarity - (1 - relevance_weight) * redundancy
            scores.append((-score, doc['id'], doc))
        chosen = min(scores, key=lambda item: (item[0], item[1]))[2]
        selected.append(chosen)
        remaining.remove(chosen)
    return [doc['id'] for doc in selected]
