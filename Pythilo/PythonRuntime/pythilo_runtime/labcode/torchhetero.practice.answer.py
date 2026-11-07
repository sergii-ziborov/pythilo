import math
import torch
from torch.nn import functional as F

def gaussian_nll(mean, raw_variance, target, floor=1e-4):
    values=(mean,raw_variance,target)
    if mean.numel()==0 or any(x.shape!=mean.shape or not x.is_floating_point() or not torch.isfinite(x).all() for x in values):raise ValueError('Expected aligned finite floating nonempty tensors.')
    if not math.isfinite(floor) or floor<=0:raise ValueError('Variance floor must be positive and finite.')
    variance=F.softplus(raw_variance)+floor
    result=.5*(math.log(2*math.pi)+variance.log()+(target-mean).square()/variance)
    return result.mean()
