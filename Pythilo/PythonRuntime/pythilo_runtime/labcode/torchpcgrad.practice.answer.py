import random
import torch

def project_conflicts(gradients, seed=0):
    if gradients.ndim!=2 or gradients.shape[0]<2 or gradients.shape[1]==0 or not gradients.is_floating_point() or not torch.isfinite(gradients).all():
        raise ValueError('Expected finite floating [tasks>=2, parameters>0] gradients.')
    original=gradients.detach().clone()
    projected=original.clone()
    rng=random.Random(seed)
    for task in range(len(original)):
        order=[j for j in range(len(original)) if j!=task]
        rng.shuffle(order)
        for peer in order:
            norm=original[peer].square().sum()
            conflict=torch.dot(projected[task],original[peer])
            if norm>0 and conflict<0:
                projected[task]=projected[task]-conflict/norm*original[peer]
    return projected
