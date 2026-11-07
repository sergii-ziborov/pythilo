import math
import torch
from torch.nn import functional as F

def dpo_loss(policy, reference, targets, beta=.1):
    if policy.ndim!=4 or policy.shape[1]!=2 or min(policy.shape)==0 or policy.shape[-1]<2 or reference.shape!=policy.shape or targets.shape!=policy.shape[:-1]:raise ValueError('Expected [batch, pair=2, time, vocabulary] aligned logits and targets.')
    if not policy.is_floating_point() or not reference.is_floating_point() or targets.dtype!=torch.long or not torch.isfinite(policy).all() or not torch.isfinite(reference).all() or not math.isfinite(beta) or beta<=0:raise ValueError('Expected finite floating logits, int64 labels and beta > 0.')
    mask=targets!=-100
    if (mask.sum(-1)==0).any() or ((targets[mask]<0)|(targets[mask]>=policy.shape[-1])).any():raise ValueError('Every response needs valid in-vocabulary targets.')
    safe=targets.masked_fill(~mask,0)
    policy_sum=(policy.log_softmax(-1).gather(-1,safe.unsqueeze(-1)).squeeze(-1)*mask).sum(-1)
    reference_sum=(reference.detach().log_softmax(-1).gather(-1,safe.unsqueeze(-1)).squeeze(-1)*mask).sum(-1)
    margin=(policy_sum[:,0]-policy_sum[:,1])-(reference_sum[:,0]-reference_sum[:,1])
    result=F.softplus(-beta*margin).mean()
    return result

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


class PreferencePolicy(torch.nn.Module):
    def __init__(self):
        super().__init__()
        self.embedding=torch.nn.Embedding(3,4)
        self.base=torch.nn.Linear(6,3)
        self.adapter_a=torch.nn.Parameter(torch.randn(2,6)*.05)
        self.adapter_b=torch.nn.Parameter(torch.zeros(3,2))
    def forward(self,features,responses):
        previous=torch.zeros_like(responses)
        previous[:,:,1:]=responses[:,:,:-1]
        context=features[:,None,None,:].expand(-1,2,responses.shape[2],-1)
        hidden=torch.cat([context,self.embedding(previous)],-1)
        return self.base(hidden)+F.linear(F.linear(hidden,self.adapter_a),self.adapter_b)

def make_data(seed=7):
    result={}
    for split,n,offset in [('train',96,0),('validation',48,1000),('test',64,2000)]:
        rng=torch.Generator().manual_seed(seed+offset)
        features=torch.randn(n,2,generator=rng)
        rows=[]
        for i,x in enumerate(features.tolist()):
            token=1 if sum(x)>=0 else 2
            rows.append({'id':f'{split}-prompt-{i}','x':x,'chosen':[token,token],'rejected':[3-token,3-token]})
        result[split]=rows
    return result

def tensors(rows):
    return torch.tensor([r['x'] for r in rows]),torch.tensor([[r['chosen'],r['rejected']] for r in rows])

def pair_metrics(model,reference,rows):
    x,y=tensors(rows)
    with torch.no_grad():
        p=model(x,y);ref=reference(x,y)
        logps=p.log_softmax(-1).gather(-1,y.unsqueeze(-1)).squeeze(-1).sum(-1)
        probability=ref.softmax(-1)
        kl=(probability*(ref.log_softmax(-1)-p.log_softmax(-1))).sum(-1).mean().item()
        return {'preference_loss':dpo_loss(p,ref,y,.5).item(),'win_rate':(logps[:,0]>logps[:,1]).float().mean().item(),'reference_to_policy_kl':kl}

def train_policy(model,reference,train,validation,steps):
    x,y=tensors(train)
    with torch.no_grad():ref=reference(x,y)
    optimizer=torch.optim.Adam([model.adapter_a,model.adapter_b],lr=.04)
    history=[];best=None;best_score=float('inf')
    for step in range(steps):
        optimizer.zero_grad(set_to_none=True)
        loss=dpo_loss(model(x,y),ref,y,.5)
        loss.backward();optimizer.step()
        score=pair_metrics(model,reference,validation)['preference_loss']
        if score<best_score:
            best_score=score;best=copy.deepcopy(model.state_dict());best_step=step+1
        if step%20==0 or step==steps-1:
            history.append({'step':step+1,'loss':loss.item(),'validation_loss':score})
    model.load_state_dict(best)
    return best_step,history

def run_experiment(seed=7,steps=100,test_override=None):
    check_steps(steps);data=make_data(seed)
    data['test']=override_rows(data['test'],test_override)
    rng=torch.get_rng_state()
    try:torch.manual_seed(seed);reference=PreferencePolicy()
    finally:torch.set_rng_state(rng)
    reference.adapter_a.requires_grad_(False);reference.adapter_b.requires_grad_(False)
    base_optimizer=torch.optim.Adam([*reference.embedding.parameters(),*reference.base.parameters()],lr=.03)
    x,y=tensors(data['train'])
    for warmup in range(20):
        base_optimizer.zero_grad(set_to_none=True)
        logits=reference(x,y)[:,0]
        loss=F.cross_entropy(logits.reshape(-1,3),y[:,0].reshape(-1))
        loss.backward();base_optimizer.step()
    for p in reference.parameters():
        p.requires_grad_(False)
        p.grad=None
    model=copy.deepcopy(reference)
    model.adapter_a.requires_grad_(True);model.adapter_b.requires_grad_(True)
    frozen_before=state_hash({k:v for k,v in model.state_dict().items() if not k.startswith('adapter_')})
    initial=copy.deepcopy(model.state_dict());baseline=pair_metrics(model,reference,data['train'])
    best_step,history=train_policy(model,reference,data['train'],data['validation'],steps)
    frozen_after=state_hash({k:v for k,v in model.state_dict().items() if not k.startswith('adapter_')})
    fit_hash=data_hash({k:data[k] for k in ('train','validation')})
    artifact=export_payload({'kind':'local-preference-lora','state':model.state_dict(),'reference':reference.state_dict(),'initial':initial,'seed':seed,'fit_hash':fit_hash})
    fresh=PreferencePolicy();fresh.load_state_dict(read_payload(artifact)['state'])
    test_x,test_y=tensors(data['test'])
    with torch.no_grad():reload_error=(fresh(test_x,test_y)-model(test_x,test_y)).abs().max().item()
    report={'artifact':artifact,'artifact_bytes':len(artifact),'initial_train':baseline,'train':pair_metrics(model,reference,data['train']),'validation':pair_metrics(model,reference,data['validation']),'test':pair_metrics(model,reference,data['test']),'best_step':best_step,'history':history,'frozen_before':frozen_before,'frozen_after':frozen_after,'trainable_parameters':sum(p.numel() for p in model.parameters() if p.requires_grad),'total_parameters':sum(p.numel() for p in model.parameters()),'reload_max_error':reload_error,'fit_hash':fit_hash,'data_hash':data_hash(data),'ids':{k:[r['id'] for r in rows] for k,rows in data.items()},'steps':steps,'base_provenance':'locally initialized and supervised-trained on synthetic training rows; not pretrained language-model weights'}
    return report

if __name__=='__main__':
    result=run_experiment()
    with open('preference-lora.pt','wb') as f:f.write(result['artifact'])
    with open('preference-report.json','w') as f:json.dump({k:v for k,v in result.items() if k!='artifact'},f,indent=2)
    print('Saved preference-lora.pt and preference-report.json')
