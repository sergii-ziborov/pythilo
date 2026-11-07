import math
import torch

def group_dro(losses, groups, log_weights, eta=.1):
    if losses.ndim!=1 or losses.numel()==0 or not losses.is_floating_point() or not torch.isfinite(losses).all():raise ValueError('Expected finite floating per-row losses.')
    if groups.shape!=losses.shape or groups.dtype!=torch.long or log_weights.ndim!=1 or not log_weights.is_floating_point() or len(log_weights)==0 or not torch.isfinite(log_weights).all():raise ValueError('Expected aligned groups and finite adversary state.')
    if not math.isfinite(eta) or eta<=0 or groups.min()<0 or groups.max()>=len(log_weights):raise ValueError('Invalid group ID or learning rate.')
    means=[]
    for group in range(len(log_weights)):
        selected=groups==group
        if not selected.any():raise ValueError('Every declared group must occur in this batch.')
        means.append(losses[selected].mean())
    means=torch.stack(means)
    next_log=(log_weights.detach()+eta*means.detach()).log_softmax(0)
    robust=(next_log.exp().detach()*means).sum()
    return robust,next_log
