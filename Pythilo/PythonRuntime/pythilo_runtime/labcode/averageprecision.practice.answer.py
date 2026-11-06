import math
def average_precision(labels,scores):
    if not labels or len(labels)!=len(scores) or any(type(y) is not int or y not in (0,1) for y in labels) or any(not math.isfinite(s) for s in scores):raise ValueError('invalid data')
    total=sum(labels)
    if total==0:return 0.0
    groups={}
    for y,s in zip(labels,scores):groups.setdefault(s,[]).append(y)
    tp=seen=0;ap=0.0
    for score in sorted(groups,reverse=True):
        ys=groups[score];added=sum(ys);tp+=added;seen+=len(ys);ap+=added/total*tp/seen
    return ap
