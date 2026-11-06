import math
def bh_adjust(pvalues):
    if any(not math.isfinite(p) or not 0<=p<=1 for p in pvalues):raise ValueError('invalid p value')
    order=sorted(range(len(pvalues)),key=lambda i:pvalues[i]);result=[0.0]*len(order);best=1.0
    for j in range(len(order)-1,-1,-1):
        i=order[j];best=min(best,pvalues[i]*len(order)/(j+1));result[i]=best
    return result
