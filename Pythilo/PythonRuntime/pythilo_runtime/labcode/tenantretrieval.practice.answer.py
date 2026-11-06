def authorized_topk(docs,tenant,roles,k):
    if k<0:raise ValueError('negative limit')
    allowed=[d for d in docs if d['tenant']==tenant and (not d['roles'] or set(d['roles'])&set(roles))]
    return [d['id'] for d in sorted(allowed,key=lambda d:(-d['score'],d['id']))[:k]]
