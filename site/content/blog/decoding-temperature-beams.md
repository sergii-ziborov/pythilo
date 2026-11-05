---
title: Temperature, top-p and beam search
description: Separate probability shaping, candidate filtering and sequence search with deterministic examples.
date: 2026-11-05
author: Pythilo
cover: /blog/decoding-temperature-beams/cover.svg
coverAlt: Shape · Filter · Search on a dark grid with a sequence of colored bars.
tags: Python, AI
---

Several generation controls operate at different stages. Temperature reshapes token probabilities. Top-p filters a probability distribution to a candidate set. Beam search keeps multiple sequence prefixes. Understanding those roles makes experiments easier to interpret than changing every setting at once.

The Pythilo labs use supplied numbers and a tiny transition graph. They do not call a language model, so every result can be checked with arithmetic.

## Temperature changes concentration

Divide logits by a positive temperature before softmax. Lower temperatures concentrate mass on higher-scoring options; equal logits remain tied. Temperature does not supply new evidence or make an answer factually reliable.

```python
import math

def probabilities(logits, temperature):
    maximum = max(logits)
    weights = [math.exp((x-maximum)/temperature) for x in logits]
    return [weight/sum(weights) for weight in weights]

cold = probabilities([0.0, 2.0], 0.5)
warm = probabilities([0.0, 2.0], 2.0)
assert cold[1] > warm[1]
assert abs(sum(warm)-1.0) < 1e-12
```

[Stable Softmax & Temperature](/labs/softmax/) also checks large logits. Once you have a distribution, [Nucleus Sampling Candidates](/labs/nucleus/) retains the smallest descending prefix whose cumulative mass reaches p, then renormalizes it. The lab returns the candidates without making a random draw, so the filtering is easy to replay.

## The best next token can lose the sequence

Suppose the first choice has probability 0.6, followed by a best continuation of 0.5. Another first choice has probability 0.4 and a continuation of 1.0. Greedy selection takes the first branch, although its complete path has lower probability.

```python
import math

greedy_score = math.log(0.6) + math.log(0.5)
alternative_score = math.log(0.4) + math.log(1.0)
assert alternative_score > greedy_score
```

[Beam Search](/labs/beamsearch/) retains a limited number of prefixes and compares their cumulative log scores after each expansion. A width of one reproduces the greedy choice in this example. Wider search can preserve the alternative, but bounded search can still prune a globally better path.

## Keep the objective visible

Our beam exercise compares equal-length paths and deliberately omits stop tokens and length penalties. Those choices matter in full generation systems: summing negative log probabilities across different lengths introduces additional behavior to account for.

Use one controlled change per run, record the distribution or path that changed, and distinguish deterministic candidate selection from random sampling. Hugging Face's [generation strategies guide](https://huggingface.co/docs/transformers/main/en/generation_strategies) explains the corresponding model-generation options. Continue with the [AI building blocks course](/learn/ai-building-blocks/) for implementation exercises.
