---
title: A validation score you can trust
description: Fit preprocessing on training data, reuse it on validation, and keep the final test separate.
date: 2026-11-05
author: Pythilo
cover: /blog/validation-without-leakage/cover.svg
coverAlt: Train → Validate on a dark grid with a sequence of colored bars.
tags: Python, Machine learning
---

A model can look convincing while benefiting from information it would never have at prediction time. Leakage often enters before the model itself: a mean, vocabulary or feature-selection rule is learned from the entire dataset and quietly carries validation information into training.

This walkthrough uses one feature and four numbers. Keeping the example small makes the information flow visible. The goal is to decide which observations are allowed to influence each statistic.

## Fit once, transform twice

Suppose the training values are zero and two. Their mean is one and their population standard deviation is one. A future value of three therefore becomes two after standardization. Adding that future value to the fitting data would change the coordinate system before the model had earned access to it.

```python
import math

train = [0.0, 2.0]
validation = [1.0, 3.0]
mean = sum(train) / len(train)
variance = sum((x-mean)**2 for x in train) / len(train)
scale = math.sqrt(variance) or 1.0
transformed = [(x-mean)/scale for x in validation]
assert transformed == [0.0, 2.0]
```

Using one for a constant feature's scale avoids division by zero. It does not give that feature new information. Record this convention so training and prediction use the same rule.

## Folds have their own fitted state

Cross-validation repeats the split-fit-evaluate process. Each fold gets its own preprocessing statistics, learned exclusively from that fold's training portion. Preparing one standardized dataset before splitting defeats that separation.

Our [Cross-validation Folds lab](/labs/crossvalidation/) focuses on the bookkeeping first. Check that each index appears in validation exactly once, and that a fold's training and validation indices never overlap. A practical implementation then fits its scaler and model inside the fold loop.

## Keep the final test final

Validation helps choose a model, threshold or hyperparameter. Repeatedly selecting the best validation result also adapts your decisions to that set. Hold a final test aside until the procedure is settled. For time-dependent data, preserve the prediction timeline rather than assuming a random split represents deployment.

Write down the split rule, the fitted transforms and the selection metric alongside the result. Those details make a score reproducible and explain what it actually measures.

Continue in [Train-only Standardization](/labs/standardize/) or the [ML evaluation course](/learn/ml-evaluation/). For a library implementation, scikit-learn explains [preprocessing consistency, leakage and pipelines](https://scikit-learn.org/stable/common_pitfalls.html). The arithmetic above is deliberately explicit so you can trace where every statistic comes from.
