import math
import torch
from torch.nn import functional as F

def supervised_contrastive(embeddings, labels, temperature=.1):
    if embeddings.ndim!=2 or len(embeddings)<2 or embeddings.shape[1]==0 or labels.shape!=(len(embeddings),) or labels.dtype!=torch.long:raise ValueError('Expected [N>=2,D] embeddings and aligned int64 labels.')
    if not embeddings.is_floating_point() or not torch.isfinite(embeddings).all() or (embeddings.norm(dim=1)==0).any() or not math.isfinite(temperature) or temperature<=0:raise ValueError('Embeddings must be finite and nonzero; temperature must be positive.')
    diagonal=torch.eye(len(embeddings),dtype=torch.bool,device=embeddings.device)
    positive=(labels[:,None]==labels[None,:])&~diagonal
    counts=positive.sum(-1)
    valid=counts>0
    if not valid.any():raise ValueError('At least one non-self positive pair is required.')
    z=F.normalize(embeddings,dim=-1)
    scores=(z@z.T/temperature).masked_fill(diagonal,float('-inf'))
    log_prob=scores-torch.logsumexp(scores,-1,keepdim=True)
    selected=torch.where(positive,log_prob,torch.zeros_like(log_prob))
    per_anchor=-selected.sum(-1)/counts.clamp_min(1)
    return per_anchor[valid].mean()
