def rrf(rankings,k=60):
    if k<=0:raise ValueError('positive smoothing required')
    scores={}
    for ranking in rankings:
        unique=list(dict.fromkeys(ranking))
        for rank,key in enumerate(unique,1):scores[key]=scores.get(key,0)+1/(k+rank)
    return sorted(scores,key=lambda key:(-scores[key],key))
