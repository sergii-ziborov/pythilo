def retrieval_metrics(ranked,relevant,k):
    if type(k) is not int or k<1:raise ValueError('positive k required')
    relevant=set(relevant)
    if not relevant:return {'recall':None,'mrr':None}
    top=list(dict.fromkeys(ranked))[:k]
    return {'recall':len(set(top)&relevant)/len(relevant),'mrr':next((1/i for i,key in enumerate(top,1) if key in relevant),0.0)}
