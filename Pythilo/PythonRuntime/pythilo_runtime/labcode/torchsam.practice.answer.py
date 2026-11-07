import math
import torch

def sam_step(model, optimizer, closure, rho=.05):
    if not math.isfinite(rho) or rho<0:raise ValueError('rho must be finite and nonnegative.')
    params=[p for p in model.parameters() if p.requires_grad]
    owners=[p for g in optimizer.param_groups for p in g['params']]
    if not params or len(owners)!=len(params) or {id(p) for p in owners}!={id(p) for p in params}:
        raise ValueError('Each trainable parameter must have exactly one optimizer owner.')
    original=[p.detach().clone() for p in params]
    optimizer.zero_grad(set_to_none=True)
    try:
        first=closure()
        if first.numel()!=1 or not torch.isfinite(first):raise ValueError('Loss must be finite and scalar.')
        first.backward()
        gradients=[p.grad for p in params if p.grad is not None]
        if not gradients or any(not torch.isfinite(g).all() for g in gradients):raise ValueError('Finite gradients required.')
        norm=torch.stack([g.detach().double().norm() for g in gradients]).norm().item()
        with torch.no_grad():
            for p in params:
                if p.grad is not None:p.add_(p.grad,alpha=rho/(norm+1e-12))
        optimizer.zero_grad(set_to_none=True)
        second=closure()
        if second.numel()!=1 or not torch.isfinite(second):raise ValueError('Second loss must be finite.')
        second.backward()
        if any(p.grad is not None and not torch.isfinite(p.grad).all() for p in params):raise ValueError('Second gradients must be finite.')
    except BaseException:
        with torch.no_grad():
            for p,v in zip(params,original):p.copy_(v)
        optimizer.zero_grad(set_to_none=True)
        raise
    with torch.no_grad():
        for p,v in zip(params,original):p.copy_(v)
    optimizer.step()
    return {'loss':first.detach().item(),'perturbed_loss':second.detach().item(),'norm':norm}
