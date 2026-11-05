def silhouette(points, labels):
    scores = []
    for i, point in enumerate(points):
        own = [abs(point-q) for j,q in enumerate(points) if j != i and labels[j] == labels[i]]
        if not own:
            scores.append(0.0)
            continue
        a = sum(own) / len(own)
        other = []
        for label in sorted(set(labels) - {labels[i]}):
            distances = [abs(point-q) for j,q in enumerate(points) if labels[j] == label]
            other.append(sum(distances) / len(distances))
        b = min(other)
        scores.append((b-a)/max(a,b) if max(a,b) else 0.0)
    return sum(scores) / len(scores)
