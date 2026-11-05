def step(x, y, gx, gy, lr):
    # (gx, gy) is the gradient: the direction in which the loss rises fastest.
    # Step the other way, by a little: the learning rate.
    return x - lr * gx, y - lr * gy
