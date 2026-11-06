import math
def wilson(successes,total,z=1.96):
    if type(successes) is not int or type(total) is not int or not 0<=successes<=total or total<1 or not math.isfinite(z) or z<=0:raise ValueError('invalid sample')
    p=successes/total;den=1+z*z/total
    center=(p+z*z/(2*total))/den
    half=z*math.sqrt(p*(1-p)/total+z*z/(4*total*total))/den
    return max(0.0,center-half),min(1.0,center+half)
