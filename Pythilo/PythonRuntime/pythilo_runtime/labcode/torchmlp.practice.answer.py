import copy
import math
import torch
from torch import nn
from torch.nn import functional as F


def fit_mlp(train, validation, test, steps, seed):
    if any(not part for part in (train, validation, test)) or type(steps) is not int or steps < 1:
        raise ValueError('three nonempty partitions and a positive step budget required')
    rows = train + validation + test
    if len({row['id'] for row in rows}) != len(rows):
        raise ValueError('unique disjoint sample identities required')
    if any(len(row['x']) != 2 or any(not math.isfinite(x) for x in row['x']) or type(row['y']) is not int or row['y'] not in (0, 1) for row in rows):
        raise ValueError('finite two-feature binary observations required')
    with torch.random.fork_rng(devices=[]):
        torch.manual_seed(seed)
        x = torch.tensor([r['x'] for r in train], dtype=torch.float32)
        y = torch.tensor([r['y'] for r in train], dtype=torch.long)
        means = x.mean(dim=0)
        scales = x.std(dim=0, correction=0)
        scales = torch.where(scales == 0, torch.ones_like(scales), scales)
        x = (x - means) / scales
        vx = (torch.tensor([r['x'] for r in validation]) - means) / scales
        vy = torch.tensor([r['y'] for r in validation], dtype=torch.long)
        model = nn.Sequential(nn.Linear(2, 8), nn.Tanh(), nn.Linear(8, 2))
        optimizer = torch.optim.Adam(model.parameters(), lr=.04)
        initial = float(F.cross_entropy(model(x), y).detach())
        best, history = None, []
        for step in range(1, steps + 1):
            model.train()
            optimizer.zero_grad(set_to_none=True)
            loss = F.cross_entropy(model(x), y)
            loss.backward()
            optimizer.step()
            model.eval()
            with torch.no_grad():
                value = float(F.cross_entropy(model(vx), vy))
            history.append(value)
            if best is None or value < best[0]:
                best = (value, step, copy.deepcopy(model.state_dict()))
        model.load_state_dict(best[2])
        model.eval()
        with torch.no_grad():
            tx = (torch.tensor([r['x'] for r in test]) - means) / scales
            ty = torch.tensor([r['y'] for r in test], dtype=torch.long)
            logits = model(tx)
            test_loss = float(F.cross_entropy(logits, ty))
            training_loss = float(F.cross_entropy(model(x), y))
        artifact = {'state': {k: v.tolist() for k, v in model.state_dict().items()},
                    'means': means.tolist(), 'scales': scales.tolist()}
        return {'artifact': artifact, 'predictions': logits.argmax(dim=-1).tolist(),
                'initial_loss': initial, 'training_loss': training_loss,
                'validation_loss': best[0], 'best_step': best[1],
                'test_loss': test_loss, 'history': history}
