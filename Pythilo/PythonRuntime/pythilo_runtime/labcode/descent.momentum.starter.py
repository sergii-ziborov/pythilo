def step(x, y, gx, gy, vx, vy, lr, beta):
    # (vx, vy) is the velocity carried over from the last step.
    # TODO: plain descent ignores it. Let it build up instead:
    #   v = beta * v + gradient, then move by lr * v.
    return x - lr * gx, y - lr * gy, vx, vy
