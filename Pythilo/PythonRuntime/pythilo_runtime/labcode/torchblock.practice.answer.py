import math
import torch
from torch.nn import functional as F


def decoder_block(x, parameters, heads):
    if x.ndim != 3 or min(x.shape) < 1 or type(heads) is not int or heads < 1 or x.shape[-1] % heads:
        raise ValueError('nonempty [B,T,D] input and a head count dividing D required')
    batch, length, width = x.shape
    shapes = {'n1': (width,), 'n2': (width,), 'qkv': (3 * width, width),
              'out': (width, width), 'ff1': (2 * width, width), 'ff2': (width, 2 * width)}
    if parameters.keys() != shapes.keys() or any(tuple(parameters[k].shape) != shape for k, shape in shapes.items()):
        raise ValueError('exact decoder parameter schema required')
    normalized = F.layer_norm(x, (width,), parameters['n1'])
    qkv = F.linear(normalized, parameters['qkv'])
    q, k, v = [part.reshape(batch, length, heads, width // heads).transpose(1, 2)
               for part in qkv.chunk(3, dim=-1)]
    scores = q @ k.transpose(-2, -1) / math.sqrt(width // heads)
    causal = torch.ones(length, length, dtype=torch.bool, device=x.device).tril()
    attention = torch.softmax(scores.masked_fill(~causal, float('-inf')), dim=-1) @ v
    joined = attention.transpose(1, 2).reshape(batch, length, width)
    residual = x + F.linear(joined, parameters['out'])
    hidden = F.layer_norm(residual, (width,), parameters['n2'])
    hidden = F.gelu(F.linear(hidden, parameters['ff1']))
    return residual + F.linear(hidden, parameters['ff2'])
