def nearest_label(points, labels, query, k):
    distances = [sum((a-b)**2 for a,b in zip(point,query)) for point in points]
    order = sorted(range(len(points)), key=lambda i: distances[i])
    counts = {}
    for i in order[:k]:
        counts[labels[i]] = counts.get(labels[i],0) + 1
    return min(counts, key=lambda label: (-counts[label],label))
