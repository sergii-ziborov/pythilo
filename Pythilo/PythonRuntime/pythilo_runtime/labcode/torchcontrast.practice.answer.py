import math
import torch
from torch.nn import functional as F


def symmetric_contrastive(a, b, temperature):
    if a.ndim != 2 or a.shape != b.shape or a.shape[0] < 2 or a.shape[1] < 1:
        raise ValueError('two aligned embedding matrices with at least two pairs required')
    if not math.isfinite(temperature) or temperature <= 0:
        raise ValueError('positive finite temperature required')
    if any(not bool(torch.isfinite(x).all()) or bool((x.norm(dim=-1) == 0).any()) for x in (a, b)):
        raise ValueError('finite nonzero embeddings required')
    scores = F.normalize(a, dim=-1) @ F.normalize(b, dim=-1).T / temperature
    labels = torch.arange(a.shape[0], device=a.device)
    return (F.cross_entropy(scores, labels) + F.cross_entropy(scores.T, labels)) / 2
