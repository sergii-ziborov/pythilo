def shortest(n, edges, start):
    distance = [float('inf')] * n
    distance[start] = 0
    for _ in range(n - 1):
        changed = False
        for source, target, weight in edges:
            candidate = distance[source] + weight
            if candidate < distance[target]:
                distance[target] = candidate
                changed = True
        if not changed:
            break
    for source, target, weight in edges:
        if distance[source] + weight < distance[target]:
            return None
    return distance
