import math
import torch
from torch.nn import functional as F

def dpo_loss(policy, reference, targets, beta=.1):
    if policy.ndim!=4 or policy.shape[1]!=2 or min(policy.shape)==0 or policy.shape[-1]<2 or reference.shape!=policy.shape or targets.shape!=policy.shape[:-1]:raise ValueError('Expected [batch, pair=2, time, vocabulary] aligned logits and targets.')
    if not policy.is_floating_point() or not reference.is_floating_point() or targets.dtype!=torch.long or not torch.isfinite(policy).all() or not torch.isfinite(reference).all() or not math.isfinite(beta) or beta<=0:raise ValueError('Expected finite floating logits, int64 labels and beta > 0.')
    mask=targets!=-100
    if (mask.sum(-1)==0).any() or ((targets[mask]<0)|(targets[mask]>=policy.shape[-1])).any():raise ValueError('Every response needs valid in-vocabulary targets.')
    safe=targets.masked_fill(~mask,0)
    policy_sum=(policy.log_softmax(-1).gather(-1,safe.unsqueeze(-1)).squeeze(-1)*mask).sum(-1)
    reference_sum=(reference.detach().log_softmax(-1).gather(-1,safe.unsqueeze(-1)).squeeze(-1)*mask).sum(-1)
    margin=(policy_sum[:,0]-policy_sum[:,1])-(reference_sum[:,0]-reference_sum[:,1])
    result=F.softplus(-beta*margin).mean()
    return result
