import math
import torch


def rms_normalize(x, weight, eps=1e-6):
    if x.ndim < 1 or x.shape[-1] == 0 or weight.shape != x.shape[-1:]:
        raise ValueError('one learned weight per last-axis feature required')
    if not math.isfinite(eps) or eps <= 0:
        raise ValueError('positive finite epsilon required')
    working = x if x.dtype == torch.float64 else x.float()
    mean_square = working.square().mean(dim=-1, keepdim=True)
    normalized = working * torch.rsqrt(mean_square + eps)
    return normalized.to(x.dtype) * weight
