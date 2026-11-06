import math
import torch


def packed_attention(q, k, v, segments):
    if q.ndim != 4 or q.shape != k.shape or k.shape != v.shape or min(q.shape) < 1:
        raise ValueError('aligned nonempty [B,H,T,D] tensors required')
    if segments.shape != (q.shape[0], q.shape[2]) or segments.dtype != torch.long or bool((segments < -1).any()):
        raise ValueError('integer document identities or -1 padding required')
    length = q.shape[2]
    same = segments[:, :, None] == segments[:, None, :]
    valid = (segments[:, :, None] >= 0) & (segments[:, None, :] >= 0)
    causal = torch.ones(length, length, dtype=torch.bool, device=q.device).tril()
    allow = (same & valid & causal)[:, None, :, :]
    active = allow.any(dim=-1, keepdim=True)
    scores = q @ k.transpose(-2, -1) / math.sqrt(q.shape[-1])
    scores = scores.masked_fill(~allow, float('-inf'))
    scores = torch.where(active, scores, torch.zeros_like(scores))
    weights = torch.softmax(scores, dim=-1) * allow.to(scores.dtype)
    return weights @ v
