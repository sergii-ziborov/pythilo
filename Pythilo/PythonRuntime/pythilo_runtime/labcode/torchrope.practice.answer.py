import math
import torch


def rotary_positions(x, positions, base=10000.0):
    if x.ndim != 4 or x.shape[-1] < 2 or x.shape[-1] % 2:
        raise ValueError('a positive even head width required')
    if positions.ndim != 1 or positions.shape[0] != x.shape[-2] or positions.dtype != torch.long or bool((positions < 0).any()):
        raise ValueError('one nonnegative integer position per token required')
    if not math.isfinite(base) or base <= 1:
        raise ValueError('finite frequency base greater than one required')
    width = x.shape[-1]
    frequency = base ** (-torch.arange(0, width, 2, dtype=x.dtype, device=x.device) / width)
    angle = positions.to(dtype=x.dtype, device=x.device)[:, None] * frequency
    cosine, sine = angle.cos(), angle.sin()
    even, odd = x[..., 0::2], x[..., 1::2]
    pairs = torch.stack((even * cosine - odd * sine, even * sine + odd * cosine), dim=-1)
    return pairs.flatten(-2)
