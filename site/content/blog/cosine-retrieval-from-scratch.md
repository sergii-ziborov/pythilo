---
title: Build a tiny vector retriever
description: Rank vectors by direction, make ties deterministic, and evaluate retrieval before generating answers.
date: 2026-11-05
author: Pythilo
cover: /blog/cosine-retrieval-from-scratch/cover.svg
coverAlt: Query → Rank → Inspect on a dark grid with a sequence of colored bars.
tags: Python, AI
---

A retrieval system chooses which stored material is relevant to a query. You can study the ranking step with hand-written vectors before introducing an embedding model, database or language model. Small vectors make it possible to calculate the expected ranking independently.

Cosine similarity compares directions. A document vector ten times longer than another does not automatically become more relevant. This is useful when magnitude should not determine the ordering, though the right similarity measure ultimately depends on how the embeddings were trained.

## Normalize the comparison

```python
import math

query = [1.0, 0.0]
documents = [[0.0, 1.0], [10.0, 0.0], [1.0, 0.0]]
def cosine(a, b):
    denominator = math.hypot(*a) * math.hypot(*b)
    return sum(x*y for x,y in zip(a,b))/denominator if denominator else 0.0
scores = [cosine(query, document) for document in documents]
ranking = sorted(range(len(scores)), key=lambda i: (-scores[i], i))
assert ranking == [1, 2, 0]
```

The second and third documents tie despite their different lengths. Choosing the smaller original index gives repeatable output. Our lab assigns zero similarity to a zero vector, since its direction is undefined; real systems should make their own zero-vector policy explicit.

## Ranking is only one stage

In a document application, the stored vectors would correspond to chunks with text, source identifiers and boundaries. Keep those identifiers through ranking so a later answer can point back to the material it used. A high similarity score is a ranking signal, not a probability that the document proves a claim.

Before adding generation, build a small evaluation set of queries and relevant document IDs. Examine whether the expected documents appear near the top. Also inspect near misses: a retriever can match vocabulary while missing the requested fact.

## Design a useful experiment

Change the query direction, add a duplicate document and insert a zero vector. Predict the order before running [Cosine Retrieval](/labs/retrieval/). Then reduce k and identify which relevant documents disappear from the selected context. This separates errors caused by ranking from errors caused by a later context budget or answer generator.

The [AI building blocks course](/learn/ai-building-blocks/) includes the same exercise with hints and checks. Scikit-learn's [cosine similarity reference](https://scikit-learn.org/stable/modules/generated/sklearn.metrics.pairwise.cosine_similarity.html) specifies the normalized dot product used here. The vectors in this walkthrough are illustrative coordinates, not learned semantic embeddings, so their meanings come entirely from the example we constructed.
