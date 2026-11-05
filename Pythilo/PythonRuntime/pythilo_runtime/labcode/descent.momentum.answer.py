def step(x, y, gx, gy, vx, vy, lr, beta):
    # (vx, vy) is the velocity carried over from the last step.
    vx = beta * vx + gx
    vy = beta * vy + gy
    return x - lr * vx, y - lr * vy, vx, vy
