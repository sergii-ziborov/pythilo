import torch

def sparse_mixture(x, router, experts, capacity):
    if x.ndim!=2 or min(x.shape)==0 or not x.is_floating_point() or not torch.isfinite(x).all() or type(capacity)!=int or capacity<=0:raise ValueError('Expected finite nonempty token matrix and positive integer capacity.')
    count=len(experts)
    if count<2 or not isinstance(router,torch.nn.Linear) or router.in_features!=x.shape[1] or router.out_features!=count:raise ValueError('Router and expert count must match.')
    if any(not isinstance(e,torch.nn.Linear) or e.in_features!=x.shape[1] or e.out_features!=experts[0].out_features for e in experts):raise ValueError('Experts must share input/output dimensions.')
    if any(not torch.isfinite(p).all() for m in [router,*experts] for p in m.parameters()):raise ValueError('Model parameters must be finite.')
    probabilities=router(x).softmax(-1)
    chosen=probabilities.argsort(dim=-1,descending=True,stable=True)[:,:2]
    requested=torch.bincount(chosen.flatten(),minlength=count).to(x.dtype)/(2*len(x))
    auxiliary=count*(probabilities.mean(0)*requested.detach()).sum()
    accepted=torch.zeros_like(probabilities,dtype=torch.bool)
    loads=[]
    for expert in range(count):
        tokens=(chosen==expert).any(-1).nonzero().flatten()[:capacity]
        accepted[tokens,expert]=True
        loads.append(len(tokens))
    retained=probabilities*accepted
    gates=retained/retained.sum(-1,keepdim=True).clamp_min(1e-12)
    zero=(x.sum()+probabilities.sum())*0
    output=x.new_zeros((len(x),experts[0].out_features))+zero
    for expert in range(count):
        tokens=accepted[:,expert].nonzero().flatten()
        if len(tokens):
            contribution=experts[expert](x.index_select(0,tokens))*gates[tokens,expert,None]
            output=output.index_add(0,tokens,contribution)
    dropped=2*len(x)-sum(loads)
    return output,auxiliary,loads,dropped
