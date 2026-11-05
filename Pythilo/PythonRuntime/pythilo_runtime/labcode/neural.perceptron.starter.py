def update(w, b, x, y, lr):
    # w: two weights, b: the bias, x: a point (x1, x2), y: its label, +1 or -1.
    score = w[0] * x[0] + w[1] * x[1] + b
    if y * score <= 0:  # the point is on the wrong side of the line
        pass  # TODO: nudge the line: w += lr * y * x, b += lr * y
    return w, b
