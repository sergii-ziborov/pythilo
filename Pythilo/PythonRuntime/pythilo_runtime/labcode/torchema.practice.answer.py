import math
import torch


def update_ema(average, model, decay):
    if not math.isfinite(decay) or not 0 <= decay <= 1:
        raise ValueError('EMA decay in 0..1 required')
    old, new = average.state_dict(), model.state_dict()
    if old.keys() != new.keys() or any(old[k].shape != new[k].shape or old[k].dtype != new[k].dtype for k in old):
        raise ValueError('matching model state required')
    live_storage = {value.data_ptr() for value in new.values() if value.numel()}
    if any(value.numel() and value.data_ptr() in live_storage for value in old.values()):
        raise ValueError('the average must own separate tensor storage')
    parameter_names = {name for name, _ in model.named_parameters(remove_duplicate=False)}
    aliases = {}
    for name, value in old.items():
        if not value.numel():
            continue
        identity = value.data_ptr()
        signature = (new[name].data_ptr(), tuple(value.shape), tuple(value.stride()), name in parameter_names)
        if identity in aliases and aliases[identity] != signature:
            raise ValueError('shared shadow storage needs matching live aliases')
        aliases[identity] = signature
    updated = set()
    with torch.no_grad():
        for name in old:
            identity = old[name].data_ptr() if old[name].numel() else name
            if identity in updated:
                continue
            updated.add(identity)
            if name in parameter_names and old[name].is_floating_point():
                old[name].mul_(decay).add_(new[name], alpha=1 - decay)
            else:
                old[name].copy_(new[name])
    return average
