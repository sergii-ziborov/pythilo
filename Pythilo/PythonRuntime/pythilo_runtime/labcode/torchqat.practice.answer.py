import torch

def fake_quant_weight(weight, bits=8, scales=None):
    if weight.ndim!=2 or 0 in weight.shape or not weight.is_floating_point() or not torch.isfinite(weight).all():raise ValueError('Expected finite floating nonempty [out, in] weights.')
    if type(bits)!=int or not 2<=bits<=8:raise ValueError('Use an integer precision from 2 through 8.')
    maximum=2**(bits-1)-1
    if scales is None:
        scale=(weight.detach().abs().amax(1)/maximum).clamp_min(1e-8)
    else:
        if scales.shape!=(len(weight),) or not torch.isfinite(scales).all() or (scales<=0).any():raise ValueError('Expected positive finite per-channel scales.')
        scale=scales.detach().clone()
    scaled=weight/scale[:,None]
    clipped=scaled.clamp(-maximum,maximum)
    straight=clipped+(clipped.round()-clipped).detach()
    return straight*scale[:,None]
