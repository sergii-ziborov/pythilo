import copy
import math
import torch
from torch import nn
from torch.nn import functional as F


class SequenceClassifier(nn.Module):
    def __init__(self, vocab):
        super().__init__()
        self.token = nn.Embedding(vocab, 8, padding_idx=0)
        self.position = nn.Embedding(32, 8)
        self.qkv = nn.Linear(8, 24)
        self.projection = nn.Linear(8, 8)
        self.norm = nn.LayerNorm(8)
        self.head = nn.Linear(8, 2)

    def forward(self, tokens):
        valid = tokens != 0
        x = self.token(tokens) + self.position(torch.arange(tokens.shape[1], device=tokens.device))
        q, k, v = self.qkv(x).chunk(3, dim=-1)
        scores = q @ k.transpose(-2, -1) / math.sqrt(8)
        weights = torch.softmax(scores.masked_fill(~valid[:, None, :], float('-inf')), dim=-1)
        hidden = self.norm(x + self.projection(weights @ v))
        pooled = (hidden * valid[:, :, None]).sum(dim=1) / valid.sum(dim=1, keepdim=True)
        return self.head(pooled)


def _encode(sequences, vocab):
    if type(vocab) is not int or vocab < 3 or not sequences:
        raise ValueError('a vocabulary and nonempty sequences required')
    if any(not row or len(row) > 32 or any(type(t) is not int or not 0 <= t < vocab for t in row) or not any(row) for row in sequences):
        raise ValueError('in-vocabulary rows need a non-padding token and length at most 32')
    length = max(len(row) for row in sequences)
    return torch.tensor([row + [0] * (length - len(row)) for row in sequences], dtype=torch.long)


def sequence_logits(artifact, sequences):
    encoded = _encode(sequences, artifact['vocab'])
    with torch.random.fork_rng(devices=[]):
        model = SequenceClassifier(artifact['vocab'])
        model.load_state_dict({k: torch.tensor(v, dtype=torch.float32) for k, v in artifact['state'].items()})
        model.eval()
        with torch.no_grad():
            return model(encoded)


def train_sequence_classifier(train, validation, test, vocab, steps, seed):
    if any(not part for part in (train, validation, test)) or type(steps) is not int or steps < 1:
        raise ValueError('nonempty partitions and positive training steps required')
    rows = train + validation + test
    if len({r['id'] for r in rows}) != len(rows) or any(type(r['y']) is not int or r['y'] not in (0, 1) for r in rows):
        raise ValueError('disjoint sample identities and binary labels required')
    encoded = [_encode([r['tokens'] for r in part], vocab) for part in (train, validation, test)]
    labels = [torch.tensor([r['y'] for r in part], dtype=torch.long) for part in (train, validation, test)]
    with torch.random.fork_rng(devices=[]):
        torch.manual_seed(seed)
        model = SequenceClassifier(vocab)
        optimizer = torch.optim.AdamW(model.parameters(), lr=.03, weight_decay=.01)
        initial = float(F.cross_entropy(model(encoded[0]), labels[0]).detach())
        best, history = None, []
        for step in range(1, steps + 1):
            model.train()
            optimizer.zero_grad(set_to_none=True)
            loss = F.cross_entropy(model(encoded[0]), labels[0])
            loss.backward()
            torch.nn.utils.clip_grad_norm_(model.parameters(), 1.0, error_if_nonfinite=True)
            optimizer.step()
            model.eval()
            with torch.no_grad():
                value = float(F.cross_entropy(model(encoded[1]), labels[1]))
            history.append(value)
            if best is None or value < best[0]:
                best = (value, step, copy.deepcopy(model.state_dict()))
        model.load_state_dict(best[2])
        model.eval()
        with torch.no_grad():
            logits = model(encoded[2])
            train_loss = float(F.cross_entropy(model(encoded[0]), labels[0]))
            test_loss = float(F.cross_entropy(logits, labels[2]))
        artifact = {'vocab': vocab, 'state': {k: v.tolist() for k, v in model.state_dict().items()}}
        return {'artifact': artifact, 'initial_loss': initial, 'training_loss': train_loss,
                'test_loss': test_loss, 'validation_loss': best[0], 'best_step': best[1],
                'predictions': logits.argmax(dim=-1).tolist(), 'history': history}
