def pack_context(chunks,window,fixed,output):
    if any(type(x) is not int or x<0 for x in [window,fixed,output]) or fixed+output>window:raise ValueError('invalid budget')
    remaining=window-fixed-output;used=0;chosen=[];seen=set()
    for key,count in chunks:
        if type(count) is not int or count<0:raise ValueError('invalid token count')
        if key not in seen and used+count<=remaining:chosen.append(key);seen.add(key);used+=count
    return chosen,used
