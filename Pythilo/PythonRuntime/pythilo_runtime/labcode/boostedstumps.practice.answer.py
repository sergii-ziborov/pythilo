import math
def fit_boost(x,y,rounds,rate):
    if not x or len(x)!=len(y) or type(rounds) is not int or rounds<0 or not 0<rate<=1 or any(not math.isfinite(v) for v in list(x)+list(y)):raise ValueError('invalid training data')
    base=sum(y)/len(y);prediction=[base]*len(y);stumps=[];values=sorted(set(x));cuts=[(a+b)/2 for a,b in zip(values,values[1:])] or [float('inf')]
    for _ in range(rounds):
        residual=[a-b for a,b in zip(y,prediction)];choices=[]
        for cut in cuts:
            left=[r for v,r in zip(x,residual) if v<=cut];right=[r for v,r in zip(x,residual) if v>cut]
            a=sum(left)/len(left) if left else 0;b=sum(right)/len(right) if right else 0
            loss=sum((r-(a if v<=cut else b))**2 for v,r in zip(x,residual));choices.append((loss,cut,a,b))
        _,cut,a,b=min(choices);stumps.append((cut,a,b));prediction=[p+rate*(a if v<=cut else b) for v,p in zip(x,prediction)]
    return {'base':base,'rate':rate,'stumps':stumps}
def predict_boost(model,x):
    return [model['base']+model['rate']*sum(a if value<=cut else b for cut,a,b in model['stumps']) for value in x]
