def asof_values(events,queries):
    result=[]
    for entity,now in queries:
        eligible=[e for e in events if e[0]==entity and e[1]<=now and e[2]<=now]
        result.append(max(eligible,key=lambda e:(e[1],e[2]))[3] if eligible else None)
    return result
