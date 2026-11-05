def rank_vectors(query, documents, k):
    import math
    qnorm = math.sqrt(sum(x*x for x in query))
    scores = []
    for index, vector in enumerate(documents):
        norm = math.sqrt(sum(x*x for x in vector))
        score = sum(a*b for a,b in zip(query,vector))/(qnorm*norm) if qnorm*norm else 0.0
        scores.append((index, score))
    scores.sort(key=lambda item: (-item[1], item[0]))
    return [index for index,score in scores[:k]]
