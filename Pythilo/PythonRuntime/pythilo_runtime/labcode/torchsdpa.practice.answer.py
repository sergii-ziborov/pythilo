import math
import torch


def masked_attention(q, k, v, allow):
    if q.ndim != 4 or k.ndim != 4 or v.ndim != 4 or k.shape[:3] != v.shape[:3] or q.shape[:2] != k.shape[:2] or q.shape[-1] != k.shape[-1]:
        raise ValueError('aligned batch, head and attention dimensions required')
    b, h, length, width = q.shape
    if not width or not length or k.shape[2] == 0:
        raise ValueError('nonempty queries and keys required')
    if allow.dtype != torch.bool or allow.ndim != 4 or allow.shape[0] != b or allow.shape[1] not in (1, h) or allow.shape[2:] != (length, k.shape[2]):
        raise ValueError('boolean [B,1-or-H,Q,K] participation mask required')
    scores = q @ k.transpose(-2, -1) / math.sqrt(width)
    active = allow.any(dim=-1, keepdim=True)
    scores = scores.masked_fill(~allow, float('-inf'))
    scores = torch.where(active, scores, torch.zeros_like(scores))
    weights = torch.softmax(scores, dim=-1) * allow.to(scores.dtype)
    return weights @ v, weights
