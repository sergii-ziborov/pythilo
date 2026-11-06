import torch
from torch.nn import functional as F


def accumulated_token_loss(batches, pad=-1):
    if not batches:
        raise ValueError('at least one logits/target microbatch required')
    total, count = None, 0
    for logits, targets in batches:
        if logits.ndim != 2 or logits.shape[0] == 0 or logits.shape[1] < 2 or targets.shape != logits.shape[:1] or targets.dtype != torch.long:
            raise ValueError('nonempty logits and aligned integer targets required')
        valid = targets != pad
        n = int(valid.sum())
        if n:
            part = F.cross_entropy(logits[valid], targets[valid], reduction='sum')
        else:
            part = logits.sum() * 0
        total = part if total is None else total + part
        count += n
    return total / count if count else total
