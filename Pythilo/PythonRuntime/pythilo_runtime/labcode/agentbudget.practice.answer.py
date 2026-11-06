def admitted_steps(costs,max_steps,max_tokens):
    costs=list(costs)
    if any(type(x) is not int or x<0 for x in costs+[max_steps,max_tokens]):raise ValueError('invalid agent budget')
    count=used=0
    for cost in costs:
        if count>=max_steps or used+cost>max_tokens:break
        count+=1;used+=cost
    return count,used
