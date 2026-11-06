import math
import torch


def clipped_update(values, gradients, lr, cap):
    if len(values) != len(gradients) or not values:
        raise ValueError('aligned parameter and gradient groups required')
    if not math.isfinite(lr) or lr < 0 or not math.isfinite(cap) or cap <= 0:
        raise ValueError('nonnegative learning rate and positive norm cap required')
    if any(not row or any(not math.isfinite(v) for v in row) for row in values):
        raise ValueError('nonempty finite parameter groups required')
    for value, gradient in zip(values, gradients):
        if gradient is not None and (len(value) != len(gradient) or any(not math.isfinite(g) for g in gradient)):
            raise ValueError('finite shape-aligned gradients required')
    parameters = [torch.nn.Parameter(torch.tensor(row, dtype=torch.float64)) for row in values]
    for parameter, gradient in zip(parameters, gradients):
        if gradient is not None:
            parameter.grad = torch.tensor(gradient, dtype=torch.float64)
    norm = torch.nn.utils.clip_grad_norm_(parameters, cap, error_if_nonfinite=True)
    with torch.no_grad():
        for parameter in parameters:
            if parameter.grad is not None:
                parameter.add_(parameter.grad, alpha=-lr)
    return {'values': [p.detach().tolist() for p in parameters], 'norm': float(norm)}
