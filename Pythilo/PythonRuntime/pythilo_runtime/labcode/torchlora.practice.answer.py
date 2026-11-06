import math
import torch
from torch import nn
from torch.nn import functional as F


def fit_low_rank(base, xs, ys, rank, steps, seed):
    if type(rank) is not int or rank < 1 or type(steps) is not int or steps < 1:
        raise ValueError('positive rank and training steps required')
    frozen = torch.tensor(base, dtype=torch.float32)
    x, y = torch.tensor(xs, dtype=torch.float32), torch.tensor(ys, dtype=torch.float32)
    if frozen.ndim != 2 or x.ndim != 2 or y.ndim != 2 or x.shape[0] != y.shape[0] or x.shape[1] != frozen.shape[1] or y.shape[1] != frozen.shape[0] or min(x.shape) < 1 or rank > min(frozen.shape):
        raise ValueError('aligned nonempty data and feasible adapter rank required')
    if any(not bool(torch.isfinite(t).all()) for t in (frozen, x, y)):
        raise ValueError('finite model and data required')
    with torch.random.fork_rng(devices=[]):
        torch.manual_seed(seed)
        a = nn.Parameter(torch.randn(rank, frozen.shape[1]) * .1)
        b = nn.Parameter(torch.zeros(frozen.shape[0], rank))
        optimizer = torch.optim.Adam([a, b], lr=.05)
        history = []
        for step in range(steps):
            optimizer.zero_grad(set_to_none=True)
            prediction = F.linear(x, frozen) + F.linear(F.linear(x, a), b) / rank
            loss = F.mse_loss(prediction, y)
            loss.backward()
            optimizer.step()
            history.append(float(loss.detach()))
        merged = frozen + b.detach() @ a.detach() / rank
        with torch.no_grad():
            final_loss = float(F.mse_loss(F.linear(x, merged), y))
        return {'base': frozen.tolist(), 'a': a.detach().tolist(), 'b': b.detach().tolist(),
                'merged': merged.tolist(), 'history': history, 'loss': final_loss,
                'predictions': F.linear(x, merged).tolist()}
