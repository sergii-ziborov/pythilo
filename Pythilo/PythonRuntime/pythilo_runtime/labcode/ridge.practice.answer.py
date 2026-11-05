def ridge(xs, ys, penalty):
    mx, my = sum(xs) / len(xs), sum(ys) / len(ys)
    numerator = sum((x-mx)*(y-my) for x,y in zip(xs,ys))
    denominator = sum((x-mx)**2 for x in xs) + penalty
    w = numerator / denominator if denominator else 0.0
    b = my - w * mx
    return w, b
