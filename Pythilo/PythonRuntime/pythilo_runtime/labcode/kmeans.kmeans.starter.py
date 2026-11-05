def assign(points, centers):
    # The number of the nearest center for every point.
    labels = []
    for x, y in points:
        distances = [(x - cx) ** 2 + (y - cy) ** 2 for cx, cy in centers]
        labels.append(distances.index(min(distances)))
    return labels


def update(points, labels, centers):
    # TODO: move each center to the mean of the points assigned to it.
    # A center with no points stays where it is.
    return centers
