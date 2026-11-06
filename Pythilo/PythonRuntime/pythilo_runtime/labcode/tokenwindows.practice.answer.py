def token_windows(tokens,size,overlap):
    if type(size) is not int or type(overlap) is not int or size<1 or not 0<=overlap<size:raise ValueError('invalid window')
    result=[];start=0
    while start<len(tokens):
        result.append((start,list(tokens[start:start+size])))
        if start+size>=len(tokens):break
        start+=size-overlap
    return result
