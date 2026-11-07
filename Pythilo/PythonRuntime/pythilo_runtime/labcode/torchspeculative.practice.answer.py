import math
import torch

def speculative_token(target, draft, proposal, accept_uniform, residual_uniform):
    if target.ndim!=1 or len(target)<2 or draft.shape!=target.shape:raise ValueError('Expected aligned categorical probability vectors.')
    for probability in (target,draft):
        if not probability.is_floating_point() or not torch.isfinite(probability).all() or (probability<0).any() or abs(probability.double().sum().item()-1)>1e-6:raise ValueError('Probabilities must be finite, nonnegative and normalized.')
    if type(proposal)!=int or not 0<=proposal<len(target) or draft[proposal]<=0:raise ValueError('Proposed token must have positive draft probability.')
    if any(not math.isfinite(u) or not 0<=u<1 for u in (accept_uniform,residual_uniform)):raise ValueError('Uniform draws must belong to [0, 1).')
    acceptance=min(1.,target[proposal].item()/draft[proposal].item())
    if accept_uniform<acceptance:return proposal,True
    residual=(target.detach().double()-draft.detach().double()).clamp_min(0)
    mass=residual.sum()
    if mass<=0:raise ValueError('A rejected proposal must leave positive residual mass.')
    cumulative=(residual/mass).cumsum(0)
    token=int(torch.searchsorted(cumulative,torch.tensor(residual_uniform,dtype=cumulative.dtype),right=True).item())
    return min(token,len(target)-1),False
