import math
def psi(reference,current,epsilon=1e-6):
    if not reference or len(reference)!=len(current) or not math.isfinite(epsilon) or epsilon<=0 or any(not math.isfinite(x) or x<0 for x in list(reference)+list(current)) or sum(reference)<=0 or sum(current)<=0:raise ValueError('invalid histogram')
    a=[x+epsilon for x in reference];b=[x+epsilon for x in current];sa=sum(a);sb=sum(b)
    return sum((y/sb-x/sa)*math.log((y/sb)/(x/sa)) for x,y in zip(a,b))
