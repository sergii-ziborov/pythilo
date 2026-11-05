---
title: Attention, one query at a time
description: Calculate attention scores, stable weights and a weighted value vector before adding a causal mask.
date: 2026-11-05
author: Pythilo
cover: /blog/attention-in-small-python/cover.svg
coverAlt: Scores → Weights → Values on a dark grid with a sequence of colored bars.
tags: Python, AI
---

Attention is easier to inspect with two keys than with a full language model. A query compares itself with keys. Those comparisons become weights, and the weights mix the corresponding values. Keys decide relevance; values provide the information to combine.

This example computes a single query's output. It omits learned projections, batches, multiple heads and dropout so each operation remains visible.

## Calculate a complete forward pass

Scaled dot-product attention divides query-key dot products by the square root of the key dimension. Softmax then turns the scores into positive weights summing to one. Subtracting the largest score before exponentiation preserves the resulting probabilities while avoiding overflow from large positive exponents.

```python
import math

query = [1.0]
keys = [[0.0], [1.0]]
values = [[2.0, 0.0], [0.0, 2.0]]
scores = [sum(q*k for q,k in zip(query,key))
          / math.sqrt(len(query)) for key in keys]
maximum = max(scores)
weights = [math.exp(score-maximum) for score in scores]
weights = [weight/sum(weights) for weight in weights]
output = [sum(w*v[j] for w,v in zip(weights,values))
          for j in range(len(values[0]))]
assert abs(sum(weights)-1.0) < 1e-12
assert output[1] > output[0]
```

The output has the value vectors' width, which need not equal the query width. Try replacing both keys with identical vectors: their weights become equal even when the values differ.

## Prevent a token from reading the future

For autoregressive generation, position i may attend to its prefix, including itself. Later positions must be masked before softmax. A large score at a forbidden column must contribute exactly zero probability rather than merely a small weight.

In [Causal Attention Mask](/labs/causalmask/), the first row always becomes `[1, 0, ...]`. Each later row normalizes only its permitted prefix. Watch the matrix fill and verify that every row sums to one.

## Trace the boundaries of the example

A zero query gives equal scores and therefore uniform attention over allowed keys. A single key receives all the mass. Very large finite equal scores should still yield equal probabilities. These are useful checks because they expose normalization and masking mistakes without requiring a trained model.

Run [Scaled Dot-product Attention](/labs/attention/) and continue with the [AI building blocks course](/learn/ai-building-blocks/). PyTorch's [official attention reference](https://docs.pytorch.org/docs/stable/generated/torch.nn.functional.scaled_dot_product_attention.html) describes the tensor operation, masks and production API. This small implementation is a teaching experiment rather than a replacement for optimized tensor kernels.
