import math
import torch


@torch.no_grad()
def cached_attention(q, k, v, cache=None):
    if q.ndim != 4 or q.shape != k.shape or k.shape != v.shape or min(q.shape) < 1:
        raise ValueError('aligned nonempty [B,H,T,D] chunks required')
    past = 0
    if cache is not None:
        if set(cache) != {'k', 'v'} or cache['k'].shape != cache['v'].shape or cache['k'].ndim != 4:
            raise ValueError('owned key/value cache required')
        old = cache['k']
        if old.shape[:2] != k.shape[:2] or old.shape[-1] != k.shape[-1] or old.dtype != k.dtype or old.device != k.device:
            raise ValueError('cache and chunk dimensions must agree')
        past = old.shape[2]
        keys = torch.cat((cache['k'], k), dim=2)
        values = torch.cat((cache['v'], v), dim=2)
    else:
        keys, values = k, v
    query_positions = torch.arange(past, past + q.shape[2], device=q.device)
    key_positions = torch.arange(keys.shape[2], device=q.device)
    allow = key_positions[None, :] <= query_positions[:, None]
    scores = q @ keys.transpose(-2, -1) / math.sqrt(q.shape[-1])
    weights = torch.softmax(scores.masked_fill(~allow, float('-inf')), dim=-1)
    return weights @ values, {'k': keys.detach().clone(), 'v': values.detach().clone()}
