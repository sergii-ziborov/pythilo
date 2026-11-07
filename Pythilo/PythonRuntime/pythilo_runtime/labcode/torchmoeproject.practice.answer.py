import torch

def sparse_mixture(x, router, experts, capacity):
    if x.ndim!=2 or min(x.shape)==0 or not x.is_floating_point() or not torch.isfinite(x).all() or type(capacity)!=int or capacity<=0:raise ValueError('Expected finite nonempty token matrix and positive integer capacity.')
    count=len(experts)
    if count<2 or not isinstance(router,torch.nn.Linear) or router.in_features!=x.shape[1] or router.out_features!=count:raise ValueError('Router and expert count must match.')
    if any(not isinstance(e,torch.nn.Linear) or e.in_features!=x.shape[1] or e.out_features!=experts[0].out_features for e in experts):raise ValueError('Experts must share input/output dimensions.')
    if any(not torch.isfinite(p).all() for m in [router,*experts] for p in m.parameters()):raise ValueError('Model parameters must be finite.')
    probabilities=router(x).softmax(-1)
    chosen=probabilities.argsort(dim=-1,descending=True,stable=True)[:,:2]
    requested=torch.bincount(chosen.flatten(),minlength=count).to(x.dtype)/(2*len(x))
    auxiliary=count*(probabilities.mean(0)*requested.detach()).sum()
    accepted=torch.zeros_like(probabilities,dtype=torch.bool)
    loads=[]
    for expert in range(count):
        tokens=(chosen==expert).any(-1).nonzero().flatten()[:capacity]
        accepted[tokens,expert]=True
        loads.append(len(tokens))
    retained=probabilities*accepted
    gates=retained/retained.sum(-1,keepdim=True).clamp_min(1e-12)
    zero=(x.sum()+probabilities.sum())*0
    output=x.new_zeros((len(x),experts[0].out_features))+zero
    for expert in range(count):
        tokens=accepted[:,expert].nonzero().flatten()
        if len(tokens):
            contribution=experts[expert](x.index_select(0,tokens))*gates[tokens,expert,None]
            output=output.index_add(0,tokens,contribution)
    dropped=2*len(x)-sum(loads)
    return output,auxiliary,loads,dropped

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


class SparseClassifier(torch.nn.Module):
    def __init__(self):
        super().__init__()
        self.router=torch.nn.Linear(2,4)
        self.experts=torch.nn.ModuleList([torch.nn.Linear(2,2) for _ in range(4)])
    def forward(self,x,capacity=None):
        return sparse_mixture(x,self.router,self.experts,len(x) if capacity is None else capacity)

def make_data(seed=7):
    result={}
    for split,n,offset in [('train',160,0),('validation',80,1000),('test',96,2000)]:
        rng=torch.Generator().manual_seed(seed+offset)
        x=torch.rand(n,2,generator=rng)*4-2
        labels=(x[:,0]*x[:,1]>0).long()
        result[split]=[{'id':f'{split}-{i}','x':row,'y':labels[i].item()} for i,row in enumerate(x.tolist())]
    return result

def tensors(rows):return torch.tensor([r['x'] for r in rows]),torch.tensor([r['y'] for r in rows])

def metrics(model,rows,capacity=None):
    x,y=tensors(rows)
    with torch.no_grad():
        logits,aux,loads,dropped=model(x,capacity)
        return {'loss':F.cross_entropy(logits,y).item(),'accuracy':(logits.argmax(-1)==y).float().mean().item(),'auxiliary':aux.item(),'accepted_loads':loads,'dropped_assignments':dropped}

def train_model(model,train,validation,steps):
    optimizer=torch.optim.Adam(model.parameters(),lr=.04)
    x,y=tensors(train);history=[];best=None;best_score=float('inf')
    for step in range(steps):
        optimizer.zero_grad(set_to_none=True)
        logits,aux,loads,dropped=model(x)
        loss=F.cross_entropy(logits,y)+.03*aux
        loss.backward();optimizer.step()
        valid_loss=metrics(model,validation)['loss']
        if valid_loss<best_score:
            best_score=valid_loss;best=copy.deepcopy(model.state_dict());best_step=step+1
        if step%20==0 or step==steps-1:
            history.append({'step':step+1,'loss':loss.item(),'validation_loss':valid_loss,'accepted_loads':loads})
    model.load_state_dict(best)
    return best_step,history

def run_experiment(seed=7,steps=120,test_override=None):
    check_steps(steps);data=make_data(seed)
    data['test']=override_rows(data['test'],test_override)
    rng=torch.get_rng_state()
    try:torch.manual_seed(seed);model=SparseClassifier()
    finally:torch.set_rng_state(rng)
    initial=copy.deepcopy(model.state_dict());initial_train=metrics(model,data['train'])
    best_step,history=train_model(model,data['train'],data['validation'],steps)
    fit_hash=data_hash({k:data[k] for k in ('train','validation')})
    artifact=export_payload({'kind':'sparse-top2-classifier','state':model.state_dict(),'initial':initial,'fit_hash':fit_hash,'seed':seed,'experts':4,'top_k':2})
    fresh=SparseClassifier();fresh.load_state_dict(read_payload(artifact)['state'])
    x,y=tensors(data['test'])
    with torch.no_grad():reload_error=(fresh(x)[0]-model(x)[0]).abs().max().item()
    stress_capacity=max(1,len(data['test'])//5)
    report={'artifact':artifact,'artifact_bytes':len(artifact),'initial_train':initial_train,'train':metrics(model,data['train']),'validation':metrics(model,data['validation']),'test':metrics(model,data['test']),'capacity_stress':metrics(model,data['test'],stress_capacity),'stress_capacity':stress_capacity,'best_step':best_step,'history':history,'reload_max_error':reload_error,'fit_hash':fit_hash,'data_hash':data_hash(data),'ids':{k:[r['id'] for r in rows] for k,rows in data.items()},'steps':steps}
    return report

if __name__=='__main__':
    result=run_experiment()
    with open('sparse-moe-model.pt','wb') as f:f.write(result['artifact'])
    with open('sparse-moe-report.json','w') as f:json.dump({k:v for k,v in result.items() if k!='artifact'},f,indent=2)
    print('Saved sparse-moe-model.pt and sparse-moe-report.json')
