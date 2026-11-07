import math
import torch
from torch.nn import functional as F

def gaussian_nll(mean, raw_variance, target, floor=1e-4):
    values=(mean,raw_variance,target)
    if mean.numel()==0 or any(x.shape!=mean.shape or not x.is_floating_point() or not torch.isfinite(x).all() for x in values):raise ValueError('Expected aligned finite floating nonempty tensors.')
    if not math.isfinite(floor) or floor<=0:raise ValueError('Variance floor must be positive and finite.')
    variance=F.softplus(raw_variance)+floor
    result=.5*(math.log(2*math.pi)+variance.log()+(target-mean).square()/variance)
    return result.mean()

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
    for split,n,offset in [('train',240,0),('validation',96,1000),('calibration',128,2000),('test',192,3000)]:
        rng=torch.Generator().manual_seed(seed+offset)
        x=torch.rand(n,generator=rng)*6-3
        sigma=.15+.35*torch.sigmoid(2*x)
        y=x.sin()+sigma*torch.randn(n,generator=rng)
        result[split]=[{'id':f'{split}-{i}','x':[x[i].item()],'y':y[i].item()} for i in range(n)]
    return result

def tensors(rows):return torch.tensor([r['x'] for r in rows]),torch.tensor([r['y'] for r in rows])

def build_model():return torch.nn.Sequential(torch.nn.Linear(1,16),torch.nn.Tanh(),torch.nn.Linear(16,2))

def predictions(model,rows):
    with torch.no_grad():
        x,y=tensors(rows);out=model(x)
        return out[:,0],(F.softplus(out[:,1])+1e-4).sqrt()

def likelihood(model,rows):
    with torch.no_grad():
        x,y=tensors(rows);out=model(x)
        return gaussian_nll(out[:,0],out[:,1],y).item()

def train_model(model,train,validation,steps):
    optimizer=torch.optim.Adam(model.parameters(),lr=.03)
    x,y=tensors(train);history=[];best=None;best_score=float('inf')
    for step in range(steps):
        optimizer.zero_grad(set_to_none=True)
        out=model(x);loss=gaussian_nll(out[:,0],out[:,1],y)
        loss.backward();optimizer.step()
        valid_loss=likelihood(model,validation)
        if valid_loss<best_score:
            best_score=valid_loss;best=copy.deepcopy(model.state_dict());best_step=step+1
        if step%20==0 or step==steps-1:
            history.append({'step':step+1,'loss':loss.item(),'validation_loss':valid_loss})
    model.load_state_dict(best)
    return best_step,history

def interval_metrics(model,rows,q):
    mean,std=predictions(model,rows);x,y=tensors(rows)
    covered=(y-mean).abs()<=q*std
    groups=[]
    for mask in (x[:,0]<0,x[:,0]>=0):
        groups.append(covered[mask].float().mean().item() if mask.any() else None)
    return {'nll':likelihood(model,rows),'coverage':covered.float().mean().item(),'mean_width':(2*q*std).mean().item(),'group_coverage':groups}

def run_experiment(seed=7,steps=140,alpha=.1,test_override=None,calibration_override=None):
    check_steps(steps)
    if not math.isfinite(alpha) or not 0<alpha<1:raise ValueError('alpha must lie strictly between zero and one.')
    data=make_data(seed)
    data['test']=override_rows(data['test'],test_override)
    data['calibration']=override_rows(data['calibration'],calibration_override)
    rank=math.ceil((len(data['calibration'])+1)*(1-alpha))
    if rank>len(data['calibration']):raise ValueError('This calibration sample is too small for a finite requested quantile.')
    rng=torch.get_rng_state()
    try:torch.manual_seed(seed);model=build_model()
    finally:torch.set_rng_state(rng)
    initial=copy.deepcopy(model.state_dict());initial_nll=likelihood(model,data['train'])
    best_step,history=train_model(model,data['train'],data['validation'],steps)
    mean,std=predictions(model,data['calibration']);_,labels=tensors(data['calibration'])
    scores=(labels-mean).abs()/std
    q=scores.kthvalue(rank).values.item()
    fit_hash=data_hash({k:data[k] for k in ('train','validation')})
    artifact=export_payload({'kind':'heteroscedastic-conformal','state':model.state_dict(),'initial':initial,'q':q,'alpha':alpha,'rank':rank,'fit_hash':fit_hash,'seed':seed})
    fresh=build_model();fresh.load_state_dict(read_payload(artifact)['state'])
    original_mean,original_std=predictions(model,data['test']);loaded_mean,loaded_std=predictions(fresh,data['test'])
    report={'artifact':artifact,'artifact_bytes':len(artifact),'q':q,'rank':rank,'alpha':alpha,'initial_train_nll':initial_nll,'train_nll':likelihood(model,data['train']),'validation_nll':likelihood(model,data['validation']),'test':interval_metrics(model,data['test'],q),'best_step':best_step,'history':history,'fit_hash':fit_hash,'data_hash':data_hash(data),'reload_max_error':max((original_mean-loaded_mean).abs().max().item(),(original_std-loaded_std).abs().max().item()),'ids':{k:[r['id'] for r in rows] for k,rows in data.items()},'steps':steps}
    return report

if __name__=='__main__':
    result=run_experiment()
    with open('uncertainty-model.pt','wb') as f:f.write(result['artifact'])
    with open('uncertainty-report.json','w') as f:json.dump({k:v for k,v in result.items() if k!='artifact'},f,indent=2)
    print('Saved uncertainty-model.pt and uncertainty-report.json')
