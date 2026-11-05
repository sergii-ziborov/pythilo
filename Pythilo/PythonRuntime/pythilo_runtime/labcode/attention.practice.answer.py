def attend(query, keys, values):
    import math
    scores = [sum(q*k for q,k in zip(query,key)) / math.sqrt(len(query)) for key in keys]
    maximum = max(scores)
    weights = [math.exp(score-maximum) for score in scores]
    total = sum(weights)
    weights = [weight/total for weight in weights]
    output = [sum(weight*value[j] for weight,value in zip(weights,values)) for j in range(len(values[0]))]
    return output
