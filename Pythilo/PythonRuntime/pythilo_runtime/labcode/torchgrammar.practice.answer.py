import torch

def constrained_beam(logits, transitions, start, accepting, eos, width=4):
    if logits.ndim!=2 or min(logits.shape)==0 or not logits.is_floating_point() or not torch.isfinite(logits).all() or type(width)!=int or width<1:raise ValueError('Expected finite nonempty position logits and positive beam width.')
    if type(eos)!=int or not 0<=eos<logits.shape[1] or start not in transitions:raise ValueError('Invalid EOS or start state.')
    for row in transitions.values():
        if not isinstance(row,dict) or any(type(t)!=int or t==eos or not 0<=t<logits.shape[1] or s not in transitions for t,s in row.items()):raise ValueError('Invalid grammar transition.')
    log_probs=logits.detach().double().log_softmax(-1)
    beam=[([],start,0.,False)]
    for position in range(len(logits)):
        candidates=[]
        for tokens,state,score,finished in beam:
            if finished:
                candidates.append((tokens,state,score,True))
                continue
            if state in accepting:candidates.append((tokens+[eos],state,score+log_probs[position,eos].item(),True))
            for token,next_state in transitions[state].items():
                candidates.append((tokens+[token],next_state,score+log_probs[position,token].item(),False))
        beam=sorted(candidates,key=lambda item:(-item[2],item[0]))[:width]
        if not beam:break
        if all(row[3] for row in beam):break
    finished=[row for row in beam if row[3]]
    if not finished:raise ValueError('No accepted EOS-terminated sequence within this beam and time budget.')
    best=sorted(finished,key=lambda item:(-item[2],item[0]))[0]
    return {'tokens':best[0],'score':best[2]}
