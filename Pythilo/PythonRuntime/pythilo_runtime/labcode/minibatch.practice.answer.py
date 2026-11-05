def epoch(xs, ys, w, lr, batch_size):
    history = [w]
    for start in range(0, len(xs), batch_size):
        bx, by = xs[start:start+batch_size], ys[start:start+batch_size]
        gradient = 2 * sum((w*x-y)*x for x,y in zip(bx,by)) / len(bx)
        w -= lr * gradient
        history.append(w)
    return w
