import math
import torch

def group_policy_loss(logp, old_logp, rewards, mask, clip=.2):
    if logp.ndim!=3 or min(logp.shape)==0 or logp.shape[1]<2 or old_logp.shape!=logp.shape or mask.shape!=logp.shape or rewards.shape!=logp.shape[:2]:raise ValueError('Expected aligned [prompts, completions>=2, tokens] tensors.')
    if mask.dtype!=torch.bool or not logp.is_floating_point() or not math.isfinite(clip) or not 0<clip<1 or any(not x.is_floating_point() or not torch.isfinite(x).all() for x in (logp,old_logp,rewards)):raise ValueError('Expected finite floating policy scores/rewards, boolean masks and 0<clip<1.')
    if (mask.sum(-1)==0).any() or ((logp-old_logp).detach().abs()>20).any():raise ValueError('Each response needs tokens and bounded finite log ratios.')
    centered=rewards.detach()-rewards.detach().mean(-1,keepdim=True)
    advantage=centered/(rewards.detach().std(-1,correction=0,keepdim=True)+1e-8)
    ratio=(logp-old_logp.detach()).exp()
    raw=ratio*advantage.unsqueeze(-1)
    bounded=ratio.clamp(1-clip,1+clip)*advantage.unsqueeze(-1)
    token=torch.minimum(raw,bounded)
    response=(token*mask).sum(-1)/mask.sum(-1)
    return -response.mean()
