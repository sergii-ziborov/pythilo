def fit(xs, ys, steps, rate):
    import math
    w = b = 0.0
    history = []
    for step in range(steps):
        probabilities = [1 / (1 + math.exp(-(w*x+b))) for x in xs]
        residuals = [p-y for p,y in zip(probabilities,ys)]
        dw = sum(r*x for r,x in zip(residuals,xs)) / len(xs)
        db = sum(residuals) / len(xs)
        w, b = w - rate*dw, b - rate*db
        history.append(sum(r*r for r in residuals) / len(xs))
    return w, b
