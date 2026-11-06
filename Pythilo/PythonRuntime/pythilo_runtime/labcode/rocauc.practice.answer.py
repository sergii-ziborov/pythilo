import math
def roc_auc(labels,scores):
    if not labels or len(labels)!=len(scores) or any(type(y) is not int or y not in (0,1) for y in labels) or any(not math.isfinite(s) for s in scores):raise ValueError('invalid ranking')
    pos=[s for y,s in zip(labels,scores) if y];neg=[s for y,s in zip(labels,scores) if not y]
    if not pos or not neg:raise ValueError('both classes required')
    return sum((p>n)+.5*(p==n) for p in pos for n in neg)/(len(pos)*len(neg))
