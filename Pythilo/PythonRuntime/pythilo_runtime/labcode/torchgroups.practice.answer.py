import math
import torch


def adamw_groups(model, decay):
    if not math.isfinite(decay) or decay < 0:
        raise ValueError('nonnegative finite decay required')
    decayed, exempt, seen = [], [], set()
    for name, parameter in model.named_parameters():
        if not parameter.requires_grad or id(parameter) in seen:
            continue
        seen.add(id(parameter))
        if parameter.ndim >= 2:
            decayed.append(parameter)
        else:
            exempt.append(parameter)
    if not seen:
        raise ValueError('at least one trainable parameter required')
    return [{'params': decayed, 'weight_decay': decay},
            {'params': exempt, 'weight_decay': 0.0}]
