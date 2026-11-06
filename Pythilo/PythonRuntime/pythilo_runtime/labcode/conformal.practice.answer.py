import math
def conformal_radius(residuals,alpha):
    if not residuals or not 0<alpha<1 or any(not math.isfinite(x) or x<0 for x in residuals):raise ValueError('invalid calibration')
    rank=math.ceil((len(residuals)+1)*(1-alpha))
    return sorted(residuals)[rank-1] if rank<=len(residuals) else float('inf')
