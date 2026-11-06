import math
def brier(labels,probabilities):
    if not labels or len(labels)!=len(probabilities) or any(type(y) is not int or y not in (0,1) for y in labels) or any(not math.isfinite(p) or not 0<=p<=1 for p in probabilities):raise ValueError('invalid probabilities')
    squared_errors=[(p-y)**2 for y,p in zip(labels,probabilities)]
    total_error=sum(squared_errors)
    result=total_error/len(labels)
    return result
