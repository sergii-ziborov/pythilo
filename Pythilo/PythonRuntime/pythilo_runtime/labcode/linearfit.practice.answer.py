def fit(xs, ys, steps, rate):
    w = b = 0.0
    history = []
    for step in range(steps):
        errors = [w*x + b - y for x,y in zip(xs,ys)]
        dw = 2 * sum(error*x for error,x in zip(errors,xs)) / len(xs)
        db = 2 * sum(errors) / len(xs)
        w, b = w - rate*dw, b - rate*db
        loss = sum((w*x+b-y)**2 for x,y in zip(xs,ys)) / len(xs)
        history.append(loss)
    return w, b
