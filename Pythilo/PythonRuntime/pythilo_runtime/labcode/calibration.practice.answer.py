import math
def ece(labels,probs,bins):
    if type(bins) is not int or bins<1 or not labels or len(labels)!=len(probs) or any(type(y) is not int or y not in (0,1) for y in labels) or any(not math.isfinite(p) or not 0<=p<=1 for p in probs):raise ValueError('invalid calibration data')
    groups=[[] for _ in range(bins)]
    for y,p in zip(labels,probs):groups[min(int(p*bins),bins-1)].append((y,p))
    return sum(abs(sum(p for y,p in g)-sum(y for y,p in g))/len(labels) for g in groups if g)
