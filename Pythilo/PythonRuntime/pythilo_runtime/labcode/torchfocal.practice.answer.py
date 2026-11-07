import math
import torch
from torch.nn import functional as F

def focal_loss(logits, targets, gamma=2., alpha=None, ignore=-100):
    if logits.ndim!=2 or logits.shape[0]==0 or logits.shape[1]<2 or not logits.is_floating_point() or not torch.isfinite(logits).all():
        raise ValueError('Expected finite nonempty [batch, classes] floating logits.')
    if targets.shape!=logits.shape[:1] or targets.dtype!=torch.long or not math.isfinite(gamma) or gamma<0:
        raise ValueError('Expected aligned int64 targets and finite gamma >= 0.')
    valid=targets!=ignore
    if ((targets[valid]<0)|(targets[valid]>=logits.shape[1])).any():
        raise ValueError('Target outside the vocabulary.')
    if alpha is not None and (alpha.shape!=(logits.shape[1],) or not torch.isfinite(alpha).all() or (alpha<=0).any()):
        raise ValueError('Class weights must be finite positive [classes].')
    if not valid.any():return logits.sum()*0
    selected=logits[valid].log_softmax(-1).gather(1,targets[valid,None]).squeeze(1)
    weight=1 if alpha is None else alpha[targets[valid]]
    loss=-weight*(1-selected.exp()).pow(gamma)*selected
    return loss.mean()
