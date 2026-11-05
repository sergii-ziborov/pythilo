def adam_step(w, gradient, m, v, t, lr, beta1, beta2, epsilon):
    import math
    m = beta1 * m + (1 - beta1) * gradient
    v = beta2 * v + (1 - beta2) * gradient * gradient
    m_hat = m / (1 - beta1 ** t)
    v_hat = v / (1 - beta2 ** t)
    w -= lr * m_hat / (math.sqrt(v_hat) + epsilon)
    return w, m, v
