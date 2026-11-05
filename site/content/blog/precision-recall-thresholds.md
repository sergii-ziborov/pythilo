---
title: Accuracy is only the first question
description: Read a confusion matrix, calculate precision and recall, and choose a threshold on validation data.
date: 2026-11-05
author: Pythilo
cover: /blog/precision-recall-thresholds/cover.png
coverAlt: Count The Errors on a dark grid with a sequence of colored bars.
tags: Python, Machine learning
---

Imagine a dataset with ninety negative examples and ten positive ones. A classifier that always predicts negative achieves ninety percent accuracy and finds none of the positives. Before trusting an impressive percentage, inspect the mistakes it combines.

A confusion matrix separates actual classes from predicted classes. In Pythilo's lab, rows are actual labels and columns are predictions. State that convention explicitly: swapping the axes changes which cells represent false positives and false negatives.

## Begin with counts

For a binary classifier, a true positive is a positive example predicted positive. A false positive is a negative example predicted positive. A false negative is a missed positive.

```python
actual = [1, 1, 0, 0]
predicted = [1, 0, 1, 1]
tp = sum(a == p == 1 for a,p in zip(actual, predicted))
fp = sum(a == 0 and p == 1 for a,p in zip(actual, predicted))
fn = sum(a == 1 and p == 0 for a,p in zip(actual, predicted))
precision = tp / (tp+fp)
recall = tp / (tp+fn)
f1 = 2*tp / (2*tp+fp+fn)
assert (tp, fp, fn) == (1, 2, 1)
assert abs(f1 - 0.4) < 1e-12
```

Precision asks how many predicted positives were correct. Recall asks how many actual positives were recovered. Their denominators answer different questions. Our teaching exercises return zero for undefined ratios; a reporting system should also make the missing denominator visible.

## A score needs a decision rule

A probability-like score does not determine a class until you choose a threshold. Lowering that threshold can recover missed positives while admitting additional false positives. The useful operating point depends on the consequences of those errors.

In [Threshold Sweep](/labs/threshold/), evaluate several candidates against validation labels and select the best F1, with a documented tie rule. Keep the final test outside that selection. F1 is one possible objective; it does not incorporate every application's costs and it ignores true negatives.

## Inspect more than one summary

Compare the confusion matrix, class counts and your chosen metric together. If the data contains multiple groups, an aggregate score can also hide where mistakes concentrate. Small validation sets may produce unstable threshold choices, so avoid treating one winning decimal as a universal setting.

Trace the [Confusion Matrix](/labs/confusion/) and [Precision, Recall & F1](/labs/precisionrecall/) labs, then change one prediction and anticipate which counts move. The scikit-learn [model evaluation guide](https://scikit-learn.org/stable/modules/model_evaluation.html) documents these metrics and their conventions in detail.
