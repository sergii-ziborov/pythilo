import copy
import hashlib
import json
import math
import torch
from torch import nn
from torch.nn import functional as F


def train_segment(xs, ys, steps, seed, checkpoint=None):
    if not xs or len(xs) != len(ys) or type(steps) is not int or steps < 0:
        raise ValueError('aligned data and nonnegative integer steps required')
    if any(len(row) != 2 or any(not math.isfinite(v) for v in row) for row in xs) or any(not math.isfinite(v) for v in ys):
        raise ValueError('finite two-feature regression data required')
    identity = hashlib.sha256(json.dumps([xs, ys], sort_keys=True, allow_nan=False).encode()).hexdigest()
    if checkpoint is not None and (checkpoint['data'] != identity or type(checkpoint['step']) is not int or checkpoint['step'] < 0):
        raise ValueError('checkpoint belongs to a different data stream')
    with torch.random.fork_rng(devices=[]):
        torch.manual_seed(seed)
        model = nn.Sequential(nn.Linear(2, 4), nn.Tanh(), nn.Dropout(.25), nn.Linear(4, 1))
        optimizer = torch.optim.AdamW(model.parameters(), lr=.02, weight_decay=.01)
        position = 0
        if checkpoint is not None:
            model.load_state_dict(checkpoint['model'])
            optimizer.load_state_dict(copy.deepcopy(checkpoint['optimizer']))
            torch.set_rng_state(checkpoint['rng'].clone())
            position = checkpoint['step']
        x = torch.tensor(xs, dtype=torch.float32)
        y = torch.tensor(ys, dtype=torch.float32)
        model.train()
        losses, batches = [], []
        for step in range(steps):
            indices = torch.randperm(len(xs))[:min(3, len(xs))]
            optimizer.zero_grad(set_to_none=True)
            loss = F.mse_loss(model(x[indices]).squeeze(-1), y[indices])
            loss.backward()
            optimizer.step()
            losses.append(float(loss.detach()))
            batches.append(indices.tolist())
        captured = copy.deepcopy({'model': model.state_dict(), 'optimizer': optimizer.state_dict(),
                                 'rng': torch.get_rng_state(), 'step': position + steps,
                                 'data': identity})
        return {'checkpoint': captured, 'losses': losses, 'batches': batches}
