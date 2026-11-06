def temporal_split(times,start,end,gap):
    if start>end or gap<0:raise ValueError('invalid window')
    return ([i for i,t in enumerate(times) if t<start-gap],[i for i,t in enumerate(times) if start<=t<=end])
