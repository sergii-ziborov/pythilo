import math
import torch
from torch import nn
from torch.nn import functional as F


class TinyDecoder(nn.Module):
    def __init__(self, vocab):
        super().__init__()
        self.token = nn.Embedding(vocab, 8)
        self.position = nn.Embedding(32, 8)
        self.norm1 = nn.LayerNorm(8)
        self.qkv = nn.Linear(8, 24, bias=False)
        self.projection = nn.Linear(8, 8, bias=False)
        self.norm2 = nn.LayerNorm(8)
        self.feedforward = nn.Sequential(nn.Linear(8, 16), nn.GELU(), nn.Linear(16, 8))
        self.final = nn.LayerNorm(8)

    def forward(self, tokens):
        batch, length = tokens.shape
        x = self.token(tokens) + self.position(torch.arange(length, device=tokens.device))
        normalized = self.norm1(x)
        q, k, v = [part.reshape(batch, length, 2, 4).transpose(1, 2)
                   for part in self.qkv(normalized).chunk(3, dim=-1)]
        scores = q @ k.transpose(-2, -1) / math.sqrt(4)
        allow = torch.ones(length, length, dtype=torch.bool, device=tokens.device).tril()
        mixed = torch.softmax(scores.masked_fill(~allow, float('-inf')), dim=-1) @ v
        x = x + self.projection(mixed.transpose(1, 2).reshape(batch, length, 8))
        x = x + self.feedforward(self.norm2(x))
        return F.linear(self.final(x), self.token.weight)


def _tokens(rows, vocab):
    if type(vocab) is not int or vocab < 2 or not rows or not rows[0] or len(rows[0]) > 32:
        raise ValueError('nonempty token rows with length at most 32 required')
    if any(len(row) != len(rows[0]) or any(type(t) is not int or not 0 <= t < vocab for t in row) for row in rows):
        raise ValueError('rectangular in-vocabulary integer tokens required')
    return torch.tensor(rows, dtype=torch.long)


def tiny_lm_logits(artifact, tokens):
    encoded = _tokens(tokens, artifact['vocab'])
    with torch.random.fork_rng(devices=[]):
        model = TinyDecoder(artifact['vocab'])
        model.load_state_dict({k: torch.tensor(v, dtype=torch.float32) for k, v in artifact['state'].items()})
        model.eval()
        with torch.no_grad():
            return model(encoded)


def train_tiny_lm(tokens, vocab, steps, seed):
    encoded = _tokens(tokens, vocab)
    if encoded.shape[1] < 2 or type(steps) is not int or steps < 1:
        raise ValueError('next-token sequences and positive training steps required')
    with torch.random.fork_rng(devices=[]):
        torch.manual_seed(seed)
        model = TinyDecoder(vocab)
        optimizer = torch.optim.AdamW(model.parameters(), lr=.03, weight_decay=.01)
        def objective():
            logits = model(encoded)[:, :-1, :]
            return F.cross_entropy(logits.reshape(-1, vocab), encoded[:, 1:].reshape(-1))
        initial = float(objective().detach())
        history = []
        for step in range(steps):
            model.train()
            optimizer.zero_grad(set_to_none=True)
            loss = objective()
            loss.backward()
            torch.nn.utils.clip_grad_norm_(model.parameters(), 1.0, error_if_nonfinite=True)
            optimizer.step()
            history.append(float(loss.detach()))
        model.eval()
        with torch.no_grad():
            final = float(objective())
        artifact = {'vocab': vocab, 'state': {k: v.tolist() for k, v in model.state_dict().items()}}
        return {'artifact': artifact, 'initial_loss': initial, 'loss': final,
                'perplexity': math.exp(final), 'history': history}
