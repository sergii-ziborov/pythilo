def best_split(values, labels):
    distinct = sorted(set(values))
    best = None
    best_score = float('inf')
    for a,b in zip(distinct, distinct[1:]):
        threshold = (a+b)/2
        groups = [[label for value,label in zip(values,labels) if value < threshold],
                  [label for value,label in zip(values,labels) if value >= threshold]]
        score = 0.0
        for group in groups:
            counts = {}
            for label in group:
                counts[label] = counts.get(label,0)+1
            score += len(group)/len(labels) * (1-sum((n/len(group))**2 for n in counts.values()))
        if score < best_score:
            best_score, best = score, threshold
    return best
