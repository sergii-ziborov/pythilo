import math
import torch


def grouped_attention(q, k, v):
    if q.ndim != 4 or k.ndim != 4 or k.shape != v.shape or q.shape[0] != k.shape[0] or q.shape[2:] != k.shape[2:] or min(k.shape) < 1:
        raise ValueError('aligned [B,H,T,D] tensors required')
    if q.shape[1] < 1 or q.shape[1] % k.shape[1]:
        raise ValueError('query heads must be a positive multiple of KV heads')
    repetitions = q.shape[1] // k.shape[1]
    keys = k.repeat_interleave(repetitions, dim=1)
    values = v.repeat_interleave(repetitions, dim=1)
    scores = q @ keys.transpose(-2, -1) / math.sqrt(q.shape[-1])
    allow = torch.ones(q.shape[2], q.shape[2], dtype=torch.bool, device=q.device).tril()
    weights = torch.softmax(scores.masked_fill(~allow, float('-inf')), dim=-1)
    return weights @ values
