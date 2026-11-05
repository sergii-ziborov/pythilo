def log_scores(documents, labels, query, vocabulary):
    import math
    scores = []
    for label in (0, 1):
        chosen = [doc for doc,y in zip(documents,labels) if y == label]
        counts = dict.fromkeys(vocabulary, 1)
        for doc in chosen:
            for token in doc:
                if token in counts:
                    counts[token] += 1
        total = sum(counts.values())
        score = math.log(len(chosen) / len(documents))
        for token in query:
            if token in counts:
                score += math.log(counts[token] / total)
        scores.append(score)
    return scores
