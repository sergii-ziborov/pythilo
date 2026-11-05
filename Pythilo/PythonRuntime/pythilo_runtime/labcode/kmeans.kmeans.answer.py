def assign(points, centers):
    # The number of the nearest center for every point.
    labels = []
    for x, y in points:
        distances = [(x - cx) ** 2 + (y - cy) ** 2 for cx, cy in centers]
        labels.append(distances.index(min(distances)))
    return labels


def update(points, labels, centers):
    moved = []
    for k, center in enumerate(centers):
        mine = [p for p, label in zip(points, labels) if label == k]
        if mine:
            moved.append((sum(x for x, _ in mine) / len(mine), sum(y for _, y in mine) / len(mine)))
        else:
            moved.append(center)  # no points: stay put
    return moved
