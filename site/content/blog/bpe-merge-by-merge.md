---
title: Understand BPE one merge at a time
description: Count adjacent pairs, resolve ties, and merge non-overlapping occurrences without losing text.
date: 2026-11-05
author: Pythilo
cover: /blog/bpe-merge-by-merge/cover.svg
coverAlt: Tokens → Pairs → Merges on a dark grid with a sequence of colored bars.
tags: Python, AI
---

A token need not be a word or a single character. Subword tokenization represents text using reusable pieces, allowing a vocabulary to capture common patterns while still composing less familiar words. A tiny pair-merging exercise shows how such pieces can emerge.

The [Byte-pair Merge Step lab](/labs/bpe/) starts with explicit token strings. It teaches one merge operation, with deterministic tie rules, rather than claiming to reproduce a particular production tokenizer.

## Count adjacent occurrences

```python
from collections import Counter

tokens = ['l', 'o', 'l', 'o', 'w']
counts = Counter(zip(tokens, tokens[1:]))
pair = min(counts, key=lambda candidate: (-counts[candidate], candidate))
assert pair == ('l', 'o')
assert counts[pair] == 2
```

The most frequent pair here is `l` followed by `o`. Joining it creates `lo`, so the new sequence is `['lo', 'lo', 'w']`. Counting pairs is different from replacing them: overlapping occurrences may both be counted even though a token cannot participate in two replacements in the same pass.

## Merge left to right

```python
tokens = ['a', 'a', 'a']
pair = ('a', 'a')
merged = []
i = 0
while i < len(tokens):
    if i+1 < len(tokens) and (tokens[i], tokens[i+1]) == pair:
        merged.append(tokens[i]+tokens[i+1])
        i += 2
    else:
        merged.append(tokens[i])
        i += 1
assert merged == ['aa', 'a']
assert ''.join(merged) == ''.join(tokens)
```

The final assertion is a useful invariant: concatenating the token strings preserves the original text. Another check is that each replacement reduces token count by exactly one. Empty input or a single token has no adjacent pair and should produce an unchanged copy.

## Training and encoding are different jobs

A training procedure chooses merges from a corpus and records them. Encoding new text applies the learned vocabulary and merge rules. Relearning merges independently for every incoming sentence would change the representation between inputs.

Two tokenizers can split the same visible word into different numbers of pieces. That difference changes context usage and the mapping from token IDs to model inputs. Inspect the actual token sequence when debugging a context limit.

The teaching lab counts one supplied sequence and resolves equal frequencies lexicographically. Real tokenizers also define normalization, pre-tokenization, byte handling, boundaries and special tokens. Those rules affect both reversibility and token counts, so a model's exact tokenizer is part of its input contract.

The original [subword-units paper by Sennrich, Haddow and Birch](https://arxiv.org/abs/1508.07909) explains the adaptation of byte-pair encoding to machine translation. Trace the toy merge, then work through its companion lesson in [AI building blocks](/learn/ai-building-blocks/). Change the input to include overlapping pairs and verify the text-preservation invariant yourself.
