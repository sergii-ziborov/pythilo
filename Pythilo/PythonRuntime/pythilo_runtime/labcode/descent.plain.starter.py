def step(x, y, gx, gy, lr):
    # (gx, gy) is the gradient: the direction in which the loss rises fastest.
    # TODO: which way should the point move to make the loss smaller?
    return x + lr * gx, y + lr * gy
