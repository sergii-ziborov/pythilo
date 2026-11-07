import math
import torch

def group_dro(losses, groups, log_weights, eta=.1):
    if losses.ndim!=1 or losses.numel()==0 or not losses.is_floating_point() or not torch.isfinite(losses).all():raise ValueError('Expected finite floating per-row losses.')
    if groups.shape!=losses.shape or groups.dtype!=torch.long or log_weights.ndim!=1 or not log_weights.is_floating_point() or len(log_weights)==0 or not torch.isfinite(log_weights).all():raise ValueError('Expected aligned groups and finite adversary state.')
    if not math.isfinite(eta) or eta<=0 or groups.min()<0 or groups.max()>=len(log_weights):raise ValueError('Invalid group ID or learning rate.')
    means=[]
    for group in range(len(log_weights)):
        selected=groups==group
        if not selected.any():raise ValueError('Every declared group must occur in this batch.')
        means.append(losses[selected].mean())
    means=torch.stack(means)
    next_log=(log_weights.detach()+eta*means.detach()).log_softmax(0)
    robust=(next_log.exp().detach()*means).sum()
    return robust,next_log

from torch.nn import functional as F
import copy
import hashlib
import io
import json

def data_hash(rows):
    return hashlib.sha256(json.dumps(rows,sort_keys=True,separators=(',',':')).encode()).hexdigest()

def state_hash(state):
    return data_hash({key:value.detach().cpu().tolist() for key,value in state.items()})

def export_payload(payload):
    stream=io.BytesIO()
    torch.save(payload,stream)
    return stream.getvalue()

def read_payload(blob):
    return torch.load(io.BytesIO(blob),map_location='cpu',weights_only=True)

def check_steps(steps):
    if type(steps)!=int or not 1<=steps<=500:raise ValueError('Choose 1..500 actual optimizer steps.')

def override_rows(original,replacement):
    if replacement is None:return original
    if not isinstance(replacement,list) or len(replacement)!=len(original):raise ValueError('Evaluation replacement must preserve row identities.')
    if [r['id'] for r in replacement]!=[r['id'] for r in original]:raise ValueError('Evaluation row identities must remain unchanged.')
    return copy.deepcopy(replacement)


def make_data(seed=7):
    result={}
    for split,offset in [('train',0),('validation',1000),('test',2000)]:
        rng=torch.Generator().manual_seed(seed+offset)
        counts=[96,24,24,96] if split=='train' else [40]*4
        rows=[]
        for group,count in enumerate(counts):
            label=group//2;spurious=group%2
            noise=torch.randn(count,2,generator=rng)
            for i in range(count):
                rows.append({'id':f'{split}-{group}-{i}','x':[(2*label-1)+noise[i,0].item(),2.5*(2*spurious-1)+.3*noise[i,1].item()],'y':label,'group':group})
        result[split]=rows
    return result

def tensors(rows):
    return torch.tensor([r['x'] for r in rows]),torch.tensor([r['y'] for r in rows]),torch.tensor([r['group'] for r in rows])

def classification(model,rows):
    x,y,g=tensors(rows)
    with torch.no_grad():
        logits=model(x)
        losses=F.cross_entropy(logits,y,reduction='none')
        correct=logits.argmax(-1)==y
        groups=[correct[g==i].float().mean().item() for i in range(4)]
    return {'loss':losses.mean().item(),'accuracy':correct.float().mean().item(),'groups':groups,'worst_group':min(groups)}

def train_model(initial,train,validation,steps,method):
    model=copy.deepcopy(initial)
    optimizer=torch.optim.SGD(model.parameters(),lr=.1,weight_decay=.01)
    x,y,groups=tensors(train)
    log_q=torch.zeros(4)
    history=[];best=None;best_score=None
    empirical=torch.stack([(groups==i).float().mean() for i in range(4)]).tolist()
    for step in range(steps):
        optimizer.zero_grad(set_to_none=True)
        row_loss=F.cross_entropy(model(x),y,reduction='none')
        if method=='dro':loss,log_q=group_dro(row_loss,groups,log_q,.1)
        else:loss=row_loss.mean()
        loss.backward()
        optimizer.step()
        score=classification(model,validation)
        key=(-score['worst_group'],score['loss'])
        if best_score is None or key<best_score:
            best_score=key;best=copy.deepcopy(model.state_dict());best_step=step+1
            best_weights=log_q.exp().tolist() if method=='dro' else empirical
        if step%20==0 or step==steps-1:
            history.append({'step':step+1,'loss':loss.item(),'validation_worst':score['worst_group']})
    model.load_state_dict(best)
    return model,best_step,history,best_weights

def run_experiment(seed=7,steps=120,test_override=None):
    check_steps(steps)
    data=make_data(seed)
    data['test']=override_rows(data['test'],test_override)
    rng=torch.get_rng_state()
    try:
        torch.manual_seed(seed)
        initial=torch.nn.Linear(2,2)
    finally:torch.set_rng_state(rng)
    models={};reports={}
    for method in ('erm','dro'):
        model,best_step,history,q=train_model(initial,data['train'],data['validation'],steps,method)
        models[method]=copy.deepcopy(model.state_dict())
        reports[method]={'initial_train':classification(initial,data['train']),'train':classification(model,data['train']),'validation':classification(model,data['validation']),'test':classification(model,data['test']),'best_step':best_step,'history':history,'group_weights':q}
    fit_hash=data_hash({k:data[k] for k in ('train','validation')})
    artifact=export_payload({'kind':'linear-group-dro','states':models,'group_weights':{method:report['group_weights'] for method,report in reports.items()},'selected_steps':{method:report['best_step'] for method,report in reports.items()},'initial':initial.state_dict(),'fit_hash':fit_hash,'seed':seed,'steps':steps})
    restored=read_payload(artifact)
    fresh=torch.nn.Linear(2,2);fresh.load_state_dict(restored['states']['dro'])
    before=reports['dro']['test'];after=classification(fresh,data['test'])
    report={'models':reports,'artifact':artifact,'artifact_bytes':len(artifact),'reload_equal':before==after,'fit_hash':fit_hash,'data_hash':data_hash(data),'ids':{k:[r['id'] for r in rows] for k,rows in data.items()},'steps':steps}
    return report

if __name__=='__main__':
    result=run_experiment()
    with open('group-dro-model.pt','wb') as f:f.write(result['artifact'])
    with open('group-dro-report.json','w') as f:json.dump({k:v for k,v in result.items() if k!='artifact'},f,indent=2)
    print('Saved group-dro-model.pt and group-dro-report.json')
