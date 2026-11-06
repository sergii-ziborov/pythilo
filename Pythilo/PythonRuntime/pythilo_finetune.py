"""BERT-Tiny teaching support. Real pretrained weights, CPU training, no network calls.

Model: google/bert_uncased_L-2_H-128_A-2, Apache-2.0, revision below.
Data: Kotzias et al., Sentiment Labelled Sentences, UCI, CC BY 4.0.
The project scripts own the experiment; this module implements the shared model,
WordPiece tokenizer, leakage-safe dataset preparation and artifact primitives.
"""
import copy
import hashlib
import json
import math
import os
from pathlib import Path
import random
import re
import struct
import unicodedata

import torch
from torch import nn
from torch.nn import functional as F

REVISION = '30b0a37ccaaa32f332884b96992754e246e48c5f'
WEIGHTS_SHA = '7fb69ad9f6866d8983183c930e33828f326470bf6ad8bbb2ad4ed957a92e9414'
VOCAB_SHA = '07eced375cec144d27c900241f3e339478dec958f92fddbc551f295c992038a3'
DATA_SHA = {
    'amazon_cells_labelled.txt': '47003fc0a0d4840b00e96e715b6189bad09e7443a3da41c4cbe12ffc79f86ae3',
    'imdb_labelled.txt': 'aef2e49e3da25714d61175e3a6e68eeef74a20a2f914318dc3be9947ea86512d',
    'yelp_labelled.txt': 'c76468b7b5c6e56a0804d728345c5f84aa2142ddb214420f61cc9cfd4c00d2ea',
}


def sha(path):
    h = hashlib.sha256()
    with Path(path).open('rb') as source:
        for block in iter(lambda: source.read(262144), b''):
            h.update(block)
    return h.hexdigest()


def assets():
    data = Path(os.environ.get('PYTHILO_FINETUNE_DATA', 'assets'))
    weights = Path(os.environ.get('PYTHILO_BERT_WEIGHTS', 'assets/model.safetensors'))
    if not data.is_dir() or not weights.is_file():
        raise FileNotFoundError('Download the Sentiment dataset and BERT weights in Pythilo Downloads. On a desktop run scripts/fetch-finetune-assets.py --project-assets assets.')
    return data, weights


def read_safetensors(path):
    """Bounded F32 safetensors reader: no pickle or downloaded executable code."""
    if sha(path) != WEIGHTS_SHA:
        raise ValueError('Pretrained model checksum mismatch')
    raw = Path(path).read_bytes()
    header_size = struct.unpack('<Q', raw[:8])[0]
    if not 2 <= header_size <= 1024 * 1024 or header_size + 8 > len(raw):
        raise ValueError('Invalid safetensors header')
    header = json.loads(raw[8:8 + header_size])
    start = 8 + header_size
    result = {}
    for key, entry in header.items():
        if key == '__metadata__':
            continue
        lo, hi = entry['data_offsets']
        shape = entry['shape']
        if entry['dtype'] != 'F32' or not all(isinstance(n, int) and n > 0 for n in shape):
            raise ValueError('Expected positive F32 tensors')
        if not 0 <= lo < hi <= len(raw) - start or hi - lo != math.prod(shape) * 4:
            raise ValueError('Invalid tensor bounds')
        result[key] = torch.frombuffer(bytearray(raw[start + lo:start + hi]), dtype=torch.float32).reshape(shape).clone()
    return result


class WordPiece:
    def __init__(self, path):
        if sha(path) != VOCAB_SHA:
            raise ValueError('Tokenizer checksum mismatch')
        self.vocab = {word: i for i, word in enumerate(Path(path).read_text().splitlines())}

    @staticmethod
    def basic(text):
        cleaned = []
        for char in text:
            cp, category = ord(char), unicodedata.category(char)
            if cp in (0, 0xFFFD) or category.startswith('C') and char not in '\t\n\r':
                continue
            chinese = any(lo <= cp <= hi for lo, hi in [(0x4E00, 0x9FFF), (0x3400, 0x4DBF), (0x20000, 0x2A6DF), (0x2A700, 0x2B73F), (0x2B740, 0x2B81F), (0x2B820, 0x2CEAF), (0xF900, 0xFAFF), (0x2F800, 0x2FA1F)])
            cleaned.append(' ' if char.isspace() else f' {char} ' if chinese else char)
        tokens = []
        for word in ''.join(cleaned).split():
            word = ''.join(c for c in unicodedata.normalize('NFD', word.lower()) if unicodedata.category(c) != 'Mn')
            piece = ''
            for char in word:
                cp = ord(char)
                punctuation = 33 <= cp <= 47 or 58 <= cp <= 64 or 91 <= cp <= 96 or 123 <= cp <= 126 or unicodedata.category(char).startswith('P')
                if punctuation:
                    if piece: tokens.append(piece); piece = ''
                    tokens.append(char)
                else:
                    piece += char
            if piece: tokens.append(piece)
        return tokens

    def tokenize(self, text):
        result = []
        words = []
        special = {'[UNK]', '[SEP]', '[PAD]', '[CLS]', '[MASK]'}
        for segment in re.split(r'(\[UNK\]|\[SEP\]|\[PAD\]|\[CLS\]|\[MASK\])', text):
            words.extend([segment] if segment in special else self.basic(segment))
        for word in words:
            if len(word) > 100:
                result.append('[UNK]'); continue
            pieces, start = [], 0
            while start < len(word):
                end = len(word)
                while end > start:
                    piece = ('##' if start else '') + word[start:end]
                    if piece in self.vocab: break
                    end -= 1
                if end == start:
                    pieces = ['[UNK]']; break
                pieces.append(piece); start = end
            result.extend(pieces)
        return result

    def encode(self, text, length=48):
        if not 2 <= length <= 512: raise ValueError('BERT length must be in [2,512]')
        tokens = ['[CLS]'] + self.tokenize(text)[:length - 2] + ['[SEP]']
        ids = [self.vocab.get(token, self.vocab['[UNK]']) for token in tokens]
        return ids + [0] * (length - len(ids)), [1] * len(ids) + [0] * (length - len(ids))


class Embeddings(nn.Module):
    def __init__(self):
        super().__init__()
        self.word_embeddings = nn.Embedding(30522, 128, padding_idx=0)
        self.position_embeddings = nn.Embedding(512, 128)
        self.token_type_embeddings = nn.Embedding(2, 128)
        self.LayerNorm = nn.LayerNorm(128, eps=1e-12)
        self.dropout = nn.Dropout(0.1)

    def forward(self, ids):
        value = self.word_embeddings(ids) + self.position_embeddings(torch.arange(ids.shape[1], device=ids.device))[None] + self.token_type_embeddings(torch.zeros_like(ids))
        return self.dropout(self.LayerNorm(value))


class SelfAttention(nn.Module):
    def __init__(self):
        super().__init__()
        self.query, self.key, self.value = nn.Linear(128, 128), nn.Linear(128, 128), nn.Linear(128, 128)
        self.dropout = nn.Dropout(0.1)

    def forward(self, hidden, mask):
        b, n, _ = hidden.shape
        q, k, v = [layer(hidden).view(b, n, 2, 64).transpose(1, 2) for layer in (self.query, self.key, self.value)]
        score = q @ k.transpose(-2, -1) / 8
        score = score.masked_fill(~mask[:, None, None, :].bool(), torch.finfo(score.dtype).min)
        weights = self.dropout(score.softmax(-1))
        return (weights @ v).transpose(1, 2).reshape(b, n, 128)


class AttentionOutput(nn.Module):
    def __init__(self):
        super().__init__()
        self.dense, self.LayerNorm, self.dropout = nn.Linear(128, 128), nn.LayerNorm(128, eps=1e-12), nn.Dropout(0.1)

    def forward(self, value, residual):
        return self.LayerNorm(residual + self.dropout(self.dense(value)))


class Attention(nn.Module):
    def __init__(self):
        super().__init__()
        self.self, self.output = SelfAttention(), AttentionOutput()

    def forward(self, hidden, mask):
        return self.output(self.self(hidden, mask), hidden)


class Intermediate(nn.Module):
    def __init__(self):
        super().__init__(); self.dense = nn.Linear(128, 512)

    def forward(self, value):
        return F.gelu(self.dense(value), approximate='none')


class LayerOutput(AttentionOutput):
    def __init__(self):
        super().__init__(); self.dense = nn.Linear(512, 128)


class Layer(nn.Module):
    def __init__(self):
        super().__init__()
        self.attention, self.intermediate, self.output = Attention(), Intermediate(), LayerOutput()

    def forward(self, value, mask):
        value = self.attention(value, mask)
        return self.output(self.intermediate(value), value)


class Encoder(nn.Module):
    def __init__(self):
        super().__init__(); self.layer = nn.ModuleList([Layer(), Layer()])

    def forward(self, value, mask):
        for layer in self.layer: value = layer(value, mask)
        return value


class Pooler(nn.Module):
    def __init__(self):
        super().__init__(); self.dense = nn.Linear(128, 128)

    def forward(self, value):
        return self.dense(value[:, 0]).tanh()


class Bert(nn.Module):
    def __init__(self):
        super().__init__()
        self.embeddings, self.encoder, self.pooler = Embeddings(), Encoder(), Pooler()

    def forward(self, ids, mask):
        hidden = self.encoder(self.embeddings(ids), mask)
        return hidden, self.pooler(hidden)


class Classifier(nn.Module):
    def __init__(self):
        super().__init__()
        self.bert, self.dropout, self.classifier = Bert(), nn.Dropout(0.1), nn.Linear(128, 2)

    def forward(self, ids, mask):
        return self.classifier(self.dropout(self.bert(ids, mask)[1]))


class LoRALinear(nn.Module):
    def __init__(self, base, rank=4, alpha=8):
        super().__init__()
        if not 1 <= rank <= 128 or not math.isfinite(alpha) or alpha <= 0: raise ValueError('Invalid LoRA settings')
        self.base, self.scale = base, alpha / rank
        self.A, self.B = nn.Parameter(torch.empty(rank, base.in_features)), nn.Parameter(torch.zeros(base.out_features, rank))
        nn.init.kaiming_uniform_(self.A, a=math.sqrt(5))

    def forward(self, value):
        return self.base(value) + F.linear(F.linear(value, self.A), self.B) * self.scale


def pretrained(mode='full', seed=17, rank=4, alpha=8):
    if mode not in ('full', 'lora'): raise ValueError('Expected full or lora')
    torch.manual_seed(seed)
    _, weights = assets()
    model = Classifier()
    state = {key.removeprefix('bert.'): value for key, value in read_safetensors(weights).items() if key.startswith('bert.')}
    model.bert.load_state_dict(state, strict=True)
    nn.init.normal_(model.classifier.weight, std=0.02); nn.init.zeros_(model.classifier.bias)
    if mode == 'lora':
        for parameter in model.bert.parameters(): parameter.requires_grad_(False)
        for layer in model.bert.encoder.layer:
            for name in ('query', 'value'):
                setattr(layer.attention.self, name, LoRALinear(getattr(layer.attention.self, name), rank, alpha))
    return model


def dataset(domain_holdout=False, quick=False):
    folder, _ = assets()
    grouped = {}
    total = 0
    for filename, expected in DATA_SHA.items():
        if sha(folder / filename) != expected: raise ValueError('Dataset checksum mismatch: ' + filename)
        domain = filename.split('_')[0]
        # splitlines() also splits embedded U+0085/NEL inside two IMDb sentences.
        for line_number, line in enumerate((folder / filename).read_text(encoding='utf-8-sig').split('\n'), 1):
            line = line.rstrip('\r')
            if not line.strip(): continue
            text, label = line.rsplit('\t', 1)
            if label not in ('0', '1'): raise ValueError('Invalid sentiment label')
            normalized = ' '.join(unicodedata.normalize('NFC', text).casefold().split())
            key = hashlib.sha256(normalized.encode()).hexdigest()
            row = dict(id=f'{domain}:{line_number}', group=key, text=text, label=int(label), domain=domain)
            grouped.setdefault(key, []).append(row); total += 1
    if total != 3000: raise ValueError('Expected the original 3000-row dataset')
    buckets, test, conflicts = {}, [], 0
    for key, copies in sorted(grouped.items()):
        if len({row['label'] for row in copies}) != 1:
            conflicts += len(copies); continue
        row = copies[0]
        if domain_holdout and any(copy['domain'] == 'imdb' for copy in copies):
            row = next(copy for copy in copies if copy['domain'] == 'imdb'); test.append(row)
        else:
            buckets.setdefault((row['label'], row['domain']), []).append(row)
    train, valid = [], []
    for key, rows in sorted(buckets.items()):
        rows.sort(key=lambda row: hashlib.sha256(('split-17:' + row['group']).encode()).hexdigest())
        n = len(rows)
        a, b = (int(n * .8), n) if domain_holdout else (int(n * .6), int(n * .8))
        train += rows[:a]; valid += rows[a:b]; test += rows[b:]
    # Stable, label-mixed small slices are used only by contract checks, never silently in a full project.
    rng = random.Random(17)
    for rows in (train, valid, test): rng.shuffle(rows)
    if quick: train, valid, test = train[:16], valid[:8], test[:8]
    groups = [set(row['group'] for row in rows) for rows in (train, valid, test)]
    assert not (groups[0] & groups[1] or groups[0] & groups[2] or groups[1] & groups[2])
    return dict(train=train, valid=valid, test=test, original_rows=total, conflicts=conflicts,
                unique_rows=sum(len(rows) for rows in (train, valid, test)), quick=quick)


def encode(rows, length=48):
    tokenizer = WordPiece(assets()[0] / 'vocab.txt')
    encoded = [tokenizer.encode(row['text'], length) for row in rows]
    return (torch.tensor([pair[0] for pair in encoded], dtype=torch.long),
            torch.tensor([pair[1] for pair in encoded], dtype=torch.long),
            torch.tensor([row['label'] for row in rows], dtype=torch.long))


def minibatch(data, indices):
    index = torch.tensor(indices, dtype=torch.long)
    return tuple(value[index] for value in data)


def metrics(logits, labels):
    with torch.no_grad():
        prediction = logits.argmax(-1)
        f1 = []
        for label in (0, 1):
            tp = ((prediction == label) & (labels == label)).sum().item()
            fp = ((prediction == label) & (labels != label)).sum().item()
            fn = ((prediction != label) & (labels == label)).sum().item()
            f1.append(2 * tp / max(1, 2 * tp + fp + fn))
        return dict(loss=F.cross_entropy(logits, labels).item(), accuracy=(prediction == labels).float().mean().item(), macro_f1=sum(f1) / 2, examples=len(labels))


def evaluate(model, data, batch_size=32):
    model.eval()
    with torch.no_grad():
        logits = torch.cat([model(data[0][i:i + batch_size], data[1][i:i + batch_size]) for i in range(0, len(data[0]), batch_size)])
    return metrics(logits, data[2])


def state_hash(model, frozen_only=False):
    h = hashlib.sha256()
    for name, parameter in model.named_parameters():
        if frozen_only and parameter.requires_grad: continue
        h.update(name.encode()); h.update(parameter.detach().contiguous().view(torch.uint8).numpy().tobytes())
    return h.hexdigest()


def optimizer_bytes(optimizer):
    return sum(value.numel() * value.element_size() for state in optimizer.state.values() for value in state.values() if isinstance(value, torch.Tensor))


def save_json(path, value):
    path = Path(path); path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + '.tmp')
    temporary.write_text(json.dumps(value, indent=2, sort_keys=True, allow_nan=False) + '\n')
    temporary.replace(path)


def save_checkpoint(path, model, optimizer, epoch, cursor, order, rng):
    path = Path(path); path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix('.tmp')
    torch.save(dict(model=model.state_dict(), optimizer=optimizer.state_dict(), epoch=epoch, cursor=cursor,
                    order=order, sampler_rng=rng.getstate(), torch_rng=torch.get_rng_state(), revision=REVISION), temporary)
    temporary.replace(path)


def load_checkpoint(path, model, optimizer, rng):
    state = torch.load(path, weights_only=True, map_location='cpu')
    if state['revision'] != REVISION: raise ValueError('Checkpoint base revision differs')
    model.load_state_dict(state['model'], strict=True); optimizer.load_state_dict(state['optimizer'])
    rng.setstate(state['sampler_rng']); torch.set_rng_state(state['torch_rng'])
    return state


def export_adapter(model, path):
    trainable = {name for name, parameter in model.named_parameters() if parameter.requires_grad}
    state = {name: value.detach().clone() for name, value in model.state_dict().items() if name in trainable}
    torch.save(state, path)
    manifest = dict(model='google/bert_uncased_L-2_H-128_A-2', revision=REVISION, weights_sha256=WEIGHTS_SHA,
                    vocab_sha256=VOCAB_SHA, rank=4, alpha=8, targets=['query', 'value'],
                    head='classifier', format='Pythilo BERT adapter v1')
    save_json(str(path) + '.json', manifest)
    return manifest


def load_adapter(path, seed=17):
    manifest = json.loads(Path(str(path) + '.json').read_text())
    expected = (REVISION, WEIGHTS_SHA, VOCAB_SHA, 4, 8, ['query', 'value'], 'classifier', 'Pythilo BERT adapter v1')
    actual = tuple(manifest.get(key) for key in ('revision', 'weights_sha256', 'vocab_sha256', 'rank', 'alpha', 'targets', 'head', 'format'))
    if actual != expected: raise ValueError('Adapter identity or configuration differs')
    model = pretrained('lora', seed)
    state = torch.load(path, weights_only=True, map_location='cpu')
    trainable = {name for name, parameter in model.named_parameters() if parameter.requires_grad}
    if set(state) != trainable: raise ValueError('Adapter has missing or unexpected tensors')
    result = model.load_state_dict(state, strict=False)
    if result.unexpected_keys: raise ValueError('Unexpected adapter tensors')
    return model


def merge_adapter(model):
    merged = copy.deepcopy(model)
    for layer in merged.bert.encoder.layer:
        for name in ('query', 'value'):
            adapter = getattr(layer.attention.self, name)
            if not isinstance(adapter, LoRALinear): raise ValueError('Expected query/value LoRA')
            linear = copy.deepcopy(adapter.base)
            with torch.no_grad(): linear.weight.add_(adapter.B @ adapter.A * adapter.scale)
            setattr(layer.attention.self, name, linear)
    return merged.eval()


def provenance(data, model, optimizer):
    return dict(model_revision=REVISION, weights_sha256=WEIGHTS_SHA, vocab_sha256=VOCAB_SHA,
                dataset='UCI Sentiment Labelled Sentences / DOI 10.24432/C57604', data_sha256=DATA_SHA,
                split_ids={key: [row['id'] for row in data[key]] for key in ('train', 'valid', 'test')},
                split_groups={key: [row['group'] for row in data[key]] for key in ('train', 'valid', 'test')},
                original_rows=data['original_rows'], conflicting_rows_removed=data['conflicts'], quick=data['quick'],
                trainable_parameters=sum(p.numel() for p in model.parameters() if p.requires_grad),
                total_parameters=sum(p.numel() for p in model.parameters()), optimizer_state_bytes=optimizer_bytes(optimizer),
                device='cpu', torch_version=str(torch.__version__))
