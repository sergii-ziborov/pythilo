import numpy as np


def train_step(net, X, y, lr):
    W1, b1, W2, b2 = net["W1"], net["b1"], net["W2"], net["b2"]
    # Forward: 2 inputs -> tanh hidden layer -> one sigmoid output.
    h = np.tanh(X @ W1 + b1)
    p = 1 / (1 + np.exp(-(h @ W2 + b2)))
    loss = -np.mean(y * np.log(p + 1e-9) + (1 - y) * np.log(1 - p + 1e-9))
    # Backward: the gradient of the loss for every weight.
    dz2 = (p - y) / len(X)
    dW2 = h.T @ dz2
    db2 = dz2.sum(axis=0)
    dz1 = (dz2 @ W2.T) * (1 - h ** 2)
    dW1 = X.T @ dz1
    db1 = dz1.sum(axis=0)
    # Update in place, against the gradient.
    W1 -= lr * dW1
    b1 -= lr * db1
    W2 -= lr * dW2
    b2 -= lr * db2
    return loss
