"""Native PyTorch Labs: real tensors, autograd and small CPU training projects."""
from .labs_engine import register
from .labs_extended import render

SPECS = {'torchclip': {'entry': 'clipped_update',
               'fixture': 'result = clipped_update([[1.,2.],[3.]], [[3.,4.],None], .1, 2.)\n',
               'checks': [{'name': 'global norm and clipped update',
                           'code': 'r=clipped_update([[1.],[2.]],[[3.],[4.]],.5,2)\n'
                                   "assert abs(r['norm']-5)<1e-12\n"
                                   "assert abs(r['values'][0][0]-.4)<1e-6 and "
                                   "abs(r['values'][1][0]-1.2)<1e-6\n"},
                          {'name': 'missing gradients and input ownership',
                           'code': 'import copy\n'
                                   'v=[[1.],[2.]]; old=copy.deepcopy(v)\n'
                                   'r=clipped_update(v,[None,[0.]],.1,1)\n'
                                   "assert v==old and r['values']==v and r['norm']==0\n"},
                          {'name': 'small gradients are not amplified',
                           'code': 'r=clipped_update([[1.]],[[.1]],1,3)\n'
                                   "assert abs(r['values'][0][0]-.9)<1e-12\n"},
                          {'name': 'nonfinite gradients and zero cap fail',
                           'code': 'try:\n'
                                   "    clipped_update([[1.]],[[float('nan')]],.1,1)\n"
                                   'except ValueError:\n'
                                   '    pass\n'
                                   'else:\n'
                                   "    assert False, 'Reject the invalid input before changing "
                                   "state.'\n"
                                   'try:\n'
                                   '    clipped_update([[1.]],[[1.]],.1,0)\n'
                                   'except ValueError:\n'
                                   '    pass\n'
                                   'else:\n'
                                   "    assert False, 'Reject the invalid input before changing "
                                   "state.'\n"}],
               'project': False},
 'torchgroups': {'entry': 'adamw_groups',
                 'fixture': 'model = torch.nn.Sequential(torch.nn.Linear(2,2), torch.nn.LayerNorm(2))\n'
                            'result = adamw_groups(model,.1)\n',
                 'checks': [{'name': 'all trainable parameters have one owner',
                             'code': 'm=torch.nn.Sequential(torch.nn.Linear(2,2),torch.nn.LayerNorm(2))\n'
                                     'g=adamw_groups(m,.1)\n'
                                     "a=[p for row in g for p in row['params']]\n"
                                     'assert len(a)==4 and {id(p) for p in a}=={id(p) for p in '
                                     'm.parameters()}\n'
                                     "assert all(p.ndim>=2 for p in g[0]['params']) and all(p.ndim<2 "
                                     "for p in g[1]['params'])\n"},
                            {'name': 'tied weights are deduplicated and frozen weights excluded',
                             'code': 'm=torch.nn.Module();m.a=torch.nn.Linear(2,2);m.b=torch.nn.Linear(2,2);m.b.weight=m.a.weight;m.b.bias.requires_grad_(False)\n'
                                     'g=adamw_groups(m,.2)\n'
                                     "assert sum(len(r['params']) for r in g)==2\n"},
                            {'name': 'actual AdamW applies only declared decay',
                             'code': 'm=torch.nn.Linear(2,1)\n'
                                     'with torch.no_grad():m.weight.fill_(1);m.bias.fill_(1)\n'
                                     'for p in m.parameters():p.grad=torch.zeros_like(p)\n'
                                     'o=torch.optim.AdamW(adamw_groups(m,.2),lr=.1);o.step()\n'
                                     'assert torch.allclose(m.weight,torch.full_like(m.weight,.98)) '
                                     'and m.bias.item()==1\n'},
                            {'name': 'invalid policy rejected',
                             'code': 'try:\n'
                                     '    adamw_groups(torch.nn.Linear(1,1),-1)\n'
                                     'except ValueError:\n'
                                     '    pass\n'
                                     'else:\n'
                                     "    assert False, 'Reject the invalid input before changing "
                                     "state.'\n"
                                     'try:\n'
                                     '    adamw_groups(torch.nn.Identity(),.1)\n'
                                     'except ValueError:\n'
                                     '    pass\n'
                                     'else:\n'
                                     "    assert False, 'Reject the invalid input before changing "
                                     "state.'\n"}],
                 'project': False},
 'torchdistill': {'entry': 'distillation_loss',
                  'fixture': 's=torch.tensor([[1.,-1.]],requires_grad=True)\n'
                             't=torch.tensor([[0.,2.]],requires_grad=True)\n'
                             'result=distillation_loss(s,t,torch.tensor([1]),2.,.7)\n'
                             'result.backward()\n',
                  'checks': [{'name': 'independent categorical KL and mixture',
                              'code': 'import math\n'
                                      's=torch.zeros(1,2,requires_grad=True);t=torch.tensor([[2.,0.]])\n'
                                      'p=(t/2).softmax(-1)\n'
                                      'kl=(p*(p.log()+math.log(2))).sum()\n'
                                      'r=distillation_loss(s,t,torch.tensor([1]),2,.7)\n'
                                      'assert '
                                      'torch.allclose(r,.3*torch.tensor(math.log(2))+.7*4*kl)\n'},
                             {'name': 'only the student receives gradients',
                              'code': 's=torch.zeros(2,2,requires_grad=True);t=torch.ones(2,2,requires_grad=True)\n'
                                      'distillation_loss(s,t,torch.tensor([0,1]),2,.5).backward()\n'
                                      'assert s.grad is not None and torch.isfinite(s.grad).all() and '
                                      't.grad is None\n'},
                             {'name': 'hard-label endpoint and identical distributions',
                              'code': 'from torch.nn import functional as F\n'
                                      's=torch.tensor([[1.,2.],[3.,0.]],requires_grad=True);y=torch.tensor([0,1])\n'
                                      'assert '
                                      'torch.allclose(distillation_loss(s,s.detach(),y,3,0),F.cross_entropy(s,y))\n'
                                      'assert '
                                      'abs(distillation_loss(s,s.detach(),y,3,1).item())<1e-6\n'},
                             {'name': 'zero temperature rejected',
                              'code': 'try:\n'
                                      '    '
                                      'distillation_loss(torch.zeros(1,2),torch.zeros(1,2),torch.tensor([0]),0,.5)\n'
                                      'except ValueError:\n'
                                      '    pass\n'
                                      'else:\n'
                                      "    assert False, 'Reject the invalid input before changing "
                                      "state.'\n"}],
                  'project': False},
 'torchcontrast': {'entry': 'symmetric_contrastive',
                   'fixture': 'a=torch.eye(3,requires_grad=True)\n'
                              'b=torch.eye(3,requires_grad=True)\n'
                              'result=symmetric_contrastive(a,b,.2)\n'
                              'result.backward()\n',
                   'checks': [{'name': 'correct pairs beat mismatched pairs',
                               'code': 'a=torch.eye(3)\n'
                                       'assert '
                                       'symmetric_contrastive(a,a,.2)<symmetric_contrastive(a,a[[1,2,0]],.2)\n'},
                              {'name': 'both encoders receive nonzero gradients',
                               'code': 'a=torch.tensor([[1.,.2],[.3,1.]],requires_grad=True);b=torch.tensor([[.8,.1],[.2,.7]],requires_grad=True)\n'
                                       'symmetric_contrastive(a,b,.5).backward()\n'
                                       'assert a.grad.abs().sum()>0 and b.grad.abs().sum()>0\n'},
                              {'name': 'joint permutation and positive scale invariance',
                               'code': 'a=torch.tensor([[1.,.2],[.3,1.],[1.,1.]]);b=a+.1\n'
                                       'r=symmetric_contrastive(a,b,.3)\n'
                                       'assert '
                                       'torch.allclose(r,symmetric_contrastive(a[[2,0,1]]*3,b[[2,0,1]]*7,.3),atol=1e-6)\n'},
                              {'name': 'zero embeddings rejected',
                               'code': 'try:\n'
                                       '    symmetric_contrastive(torch.zeros(2,2),torch.eye(2),.1)\n'
                                       'except ValueError:\n'
                                       '    pass\n'
                                       'else:\n'
                                       "    assert False, 'Reject the invalid input before changing "
                                       "state.'\n"}],
                   'project': False},
 'torchema': {'entry': 'update_ema',
              'fixture': 'import copy\n'
                         'm=torch.nn.Linear(2,1)\n'
                         'average=copy.deepcopy(m)\n'
                         'with torch.no_grad():m.weight.add_(1)\n'
                         'result=update_ema(average,m,.9)\n',
              'checks': [{'name': 'parameters average without changing the source',
                          'code': 'import copy\n'
                                  'm=torch.nn.Linear(1,1);a=copy.deepcopy(m)\n'
                                  'with torch.no_grad():a.weight.fill_(2);m.weight.fill_(6)\n'
                                  'r=update_ema(a,m,.75)\n'
                                  'assert r is a and a.weight.item()==3 and m.weight.item()==6 and '
                                  "a.weight.grad is None, 'Return and update the independently owned "
                                  "EMA module.'\n"},
                         {'name': 'floating and integer buffers are copied',
                          'code': 'a=torch.nn.BatchNorm1d(2);m=torch.nn.BatchNorm1d(2)\n'
                                  'with '
                                  'torch.no_grad():m.running_mean.fill_(8);m.num_batches_tracked.fill_(7)\n'
                                  'update_ema(a,m,.9)\n'
                                  'assert torch.equal(a.running_mean,m.running_mean) and '
                                  'a.num_batches_tracked.item()==7\n'},
                         {'name': 'tied parameters are averaged exactly once',
                          'code': 'import copy\n'
                                  'm=torch.nn.Module();m.a=torch.nn.Linear(2,2,bias=False);m.b=torch.nn.Linear(2,2,bias=False);m.b.weight=m.a.weight;a=copy.deepcopy(m)\n'
                                  'with torch.no_grad():a.a.weight.fill_(2);m.a.weight.fill_(6)\n'
                                  'update_ema(a,m,.75)\n'
                                  'assert torch.equal(a.a.weight,torch.full_like(a.a.weight,3)) and '
                                  'a.a.weight is a.b.weight\n'},
                         {'name': 'storage cannot alias the live model',
                          'code': 'm=torch.nn.Linear(1,1)\n'
                                  'try:\n'
                                  '    update_ema(m,m,.9)\n'
                                  'except ValueError:\n'
                                  '    pass\n'
                                  'else:\n'
                                  "    assert False, 'Reject the invalid input before changing "
                                  "state.'\n"},
                         {'name': 'shape mismatch rejected before mutation',
                          'code': 'a=torch.nn.Linear(1,1);m=torch.nn.Linear(2,1);old=a.weight.detach().clone()\n'
                                  'try:\n'
                                  '    update_ema(a,m,.9)\n'
                                  'except ValueError:\n'
                                  '    pass\n'
                                  'else:\n'
                                  "    assert False, 'Reject the invalid input before changing "
                                  "state.'\n"
                                  'assert torch.equal(a.weight,old)\n'}],
              'project': False},
 'torchtokens': {'entry': 'accumulated_token_loss',
                 'fixture': 'a=torch.zeros(2,3,requires_grad=True)\n'
                            'b=torch.zeros(1,3,requires_grad=True)\n'
                            'result=accumulated_token_loss([(a,torch.tensor([0,-1])),(b,torch.tensor([2]))])\n'
                            'result.backward()\n',
                 'checks': [{'name': 'one denominator matches concatenated valid targets',
                             'code': 'from torch.nn import functional as F\n'
                                     'a=torch.tensor([[3.,0.],[0.,2.]],requires_grad=True);b=torch.tensor([[1.,0.]],requires_grad=True)\n'
                                     'r=accumulated_token_loss([(a,torch.tensor([0,-1])),(b,torch.tensor([1]))])\n'
                                     'expected=F.cross_entropy(torch.stack([a[0],b[0]]),torch.tensor([0,1]))\n'
                                     'assert torch.allclose(r,expected)\n'},
                            {'name': 'padding receives zero gradient',
                             'code': 'a=torch.zeros(2,2,requires_grad=True);b=torch.zeros(1,2,requires_grad=True)\n'
                                     'accumulated_token_loss([(a,torch.tensor([0,-1])),(b,torch.tensor([1]))]).backward()\n'
                                     'assert torch.equal(a.grad[1],torch.zeros(2)) and '
                                     'torch.allclose(a.grad[0],torch.tensor([-.25,.25])) and '
                                     'torch.allclose(b.grad[0],torch.tensor([.25,-.25]))\n'},
                            {'name': 'all-padding graphs remain differentiable',
                             'code': 'a=torch.ones(2,2,requires_grad=True);b=torch.ones(1,2,requires_grad=True)\n'
                                     'r=accumulated_token_loss([(a,torch.tensor([-1,-1])),(b,torch.tensor([-1]))]);r.backward()\n'
                                     'assert r.item()==0 and torch.equal(a.grad,torch.zeros_like(a)) '
                                     'and torch.equal(b.grad,torch.zeros_like(b))\n'},
                            {'name': 'empty collection rejected',
                             'code': 'try:\n'
                                     '    accumulated_token_loss([])\n'
                                     'except ValueError:\n'
                                     '    pass\n'
                                     'else:\n'
                                     "    assert False, 'Reject the invalid input before changing "
                                     "state.'\n"}],
                 'project': False},
 'torchmlp': {'entry': 'fit_mlp',
              'fixture': "train=[{'id': 't0', 'x': [0.0, 0.0], 'y': 0}, {'id': 't1', 'x': [0.0, 1.0], "
                         "'y': 1}, {'id': 't2', 'x': [1.0, 0.0], 'y': 1}, {'id': 't3', 'x': [1.0, "
                         "1.0], 'y': 0}]\n"
                         "validation=[{'id': 'v0', 'x': [0.05, 0.05], 'y': 0}, {'id': 'v1', 'x': "
                         "[0.05, 0.95], 'y': 1}, {'id': 'v2', 'x': [0.95, 0.05], 'y': 1}, {'id': 'v3', "
                         "'x': [0.95, 0.95], 'y': 0}]\n"
                         "test=[{'id': 'z0', 'x': [0.1, 0.1], 'y': 0}, {'id': 'z1', 'x': [0.1, 0.9], "
                         "'y': 1}]\n"
                         'result=fit_mlp(train,validation,test,4,7)\n',
              'checks': [{'name': 'actual nonlinear learning and checkpoint selection',
                          'code': "train=[{'id': 't0', 'x': [0.0, 0.0], 'y': 0}, {'id': 't1', 'x': "
                                  "[0.0, 1.0], 'y': 1}, {'id': 't2', 'x': [1.0, 0.0], 'y': 1}, {'id': "
                                  "'t3', 'x': [1.0, 1.0], 'y': 0}]\n"
                                  "validation=[{'id': 'v0', 'x': [0.05, 0.05], 'y': 0}, {'id': 'v1', "
                                  "'x': [0.05, 0.95], 'y': 1}, {'id': 'v2', 'x': [0.95, 0.05], 'y': "
                                  "1}, {'id': 'v3', 'x': [0.95, 0.95], 'y': 0}]\n"
                                  "test=[{'id': 'z0', 'x': [0.1, 0.1], 'y': 0}, {'id': 'z1', 'x': "
                                  "[0.1, 0.9], 'y': 1}]\n"
                                  'r=fit_mlp(train,validation,test,80,7)\n'
                                  "assert r['training_loss']<.08 and "
                                  "r['training_loss']<r['initial_loss'] and r['predictions']==[0,1]\n"
                                  "assert r['validation_loss']==min(r['history']) and "
                                  "r['best_step']==r['history'].index(min(r['history']))+1\n"},
                         {'name': 'held-out labels cannot change model selection',
                          'code': "train=[{'id': 't0', 'x': [0.0, 0.0], 'y': 0}, {'id': 't1', 'x': "
                                  "[0.0, 1.0], 'y': 1}, {'id': 't2', 'x': [1.0, 0.0], 'y': 1}, {'id': "
                                  "'t3', 'x': [1.0, 1.0], 'y': 0}]\n"
                                  "validation=[{'id': 'v0', 'x': [0.05, 0.05], 'y': 0}, {'id': 'v1', "
                                  "'x': [0.05, 0.95], 'y': 1}, {'id': 'v2', 'x': [0.95, 0.05], 'y': "
                                  "1}, {'id': 'v3', 'x': [0.95, 0.95], 'y': 0}]\n"
                                  "test=[{'id': 'z0', 'x': [0.1, 0.1], 'y': 0}, {'id': 'z1', 'x': "
                                  "[0.1, 0.9], 'y': 1}]\n"
                                  'import copy\n'
                                  'a=fit_mlp(train,validation,test,12,3);poison=copy.deepcopy(test)\n'
                                  "for row in poison:row['y']=1-row['y']\n"
                                  'b=fit_mlp(train,validation,poison,12,3)\n'
                                  "assert a['artifact']==b['artifact'] and "
                                  "a['predictions']==b['predictions'] and "
                                  "a['best_step']==b['best_step'] and "
                                  "a['test_loss']!=b['test_loss']\n"},
                         {'name': 'serialized artifact independently predicts',
                          'code': "train=[{'id': 't0', 'x': [0.0, 0.0], 'y': 0}, {'id': 't1', 'x': "
                                  "[0.0, 1.0], 'y': 1}, {'id': 't2', 'x': [1.0, 0.0], 'y': 1}, {'id': "
                                  "'t3', 'x': [1.0, 1.0], 'y': 0}]\n"
                                  "validation=[{'id': 'v0', 'x': [0.05, 0.05], 'y': 0}, {'id': 'v1', "
                                  "'x': [0.05, 0.95], 'y': 1}, {'id': 'v2', 'x': [0.95, 0.05], 'y': "
                                  "1}, {'id': 'v3', 'x': [0.95, 0.95], 'y': 0}]\n"
                                  "test=[{'id': 'z0', 'x': [0.1, 0.1], 'y': 0}, {'id': 'z1', 'x': "
                                  "[0.1, 0.9], 'y': 1}]\n"
                                  'import json\n'
                                  "r=fit_mlp(train,validation,test,20,7);a=json.loads(json.dumps(r['artifact']))\n"
                                  "x=(torch.tensor([row['x'] for row in "
                                  "test])-torch.tensor(a['means']))/torch.tensor(a['scales'])\n"
                                  "s={k:torch.tensor(v) for k,v in a['state'].items()}\n"
                                  "h=torch.tanh(torch.nn.functional.linear(x,s['0.weight'],s['0.bias']))\n"
                                  "z=torch.nn.functional.linear(h,s['2.weight'],s['2.bias'])\n"
                                  "assert z.argmax(-1).tolist()==r['predictions'] and "
                                  "a['means']==[.5,.5]\n"},
                         {'name': 'caller randomness is preserved',
                          'code': "train=[{'id': 't0', 'x': [0.0, 0.0], 'y': 0}, {'id': 't1', 'x': "
                                  "[0.0, 1.0], 'y': 1}, {'id': 't2', 'x': [1.0, 0.0], 'y': 1}, {'id': "
                                  "'t3', 'x': [1.0, 1.0], 'y': 0}]\n"
                                  "validation=[{'id': 'v0', 'x': [0.05, 0.05], 'y': 0}, {'id': 'v1', "
                                  "'x': [0.05, 0.95], 'y': 1}, {'id': 'v2', 'x': [0.95, 0.05], 'y': "
                                  "1}, {'id': 'v3', 'x': [0.95, 0.95], 'y': 0}]\n"
                                  "test=[{'id': 'z0', 'x': [0.1, 0.1], 'y': 0}, {'id': 'z1', 'x': "
                                  "[0.1, 0.9], 'y': 1}]\n"
                                  'torch.manual_seed(113);before=torch.get_rng_state().clone()\n'
                                  'a=fit_mlp(train,validation,test,3,5)\n'
                                  'assert torch.equal(before,torch.get_rng_state())\n'
                                  'b=fit_mlp(train,validation,test,3,5)\n'
                                  'assert a==b\n'},
                         {'name': 'partition identity leakage rejected',
                          'code': "train=[{'id': 't0', 'x': [0.0, 0.0], 'y': 0}, {'id': 't1', 'x': "
                                  "[0.0, 1.0], 'y': 1}, {'id': 't2', 'x': [1.0, 0.0], 'y': 1}, {'id': "
                                  "'t3', 'x': [1.0, 1.0], 'y': 0}]\n"
                                  "validation=[{'id': 'v0', 'x': [0.05, 0.05], 'y': 0}, {'id': 'v1', "
                                  "'x': [0.05, 0.95], 'y': 1}, {'id': 'v2', 'x': [0.95, 0.05], 'y': "
                                  "1}, {'id': 'v3', 'x': [0.95, 0.95], 'y': 0}]\n"
                                  "test=[{'id': 'z0', 'x': [0.1, 0.1], 'y': 0}, {'id': 'z1', 'x': "
                                  "[0.1, 0.9], 'y': 1}]\n"
                                  'try:\n'
                                  '    fit_mlp(train,train,test,2,7)\n'
                                  'except ValueError:\n'
                                  '    pass\n'
                                  'else:\n'
                                  "    assert False, 'Reject the invalid input before changing "
                                  "state.'\n"}],
              'project': True},
 'torchresume': {'entry': 'train_segment',
                 'fixture': 'xs=[[0.0, 0.0], [0.0, 1.0], [1.0, 0.0], [1.0, 1.0]]\n'
                            'ys=[0.0, 1.0, 1.0, 2.0]\n'
                            'first=train_segment(xs,ys,2,7)\n'
                            "result=train_segment(xs,ys,2,7,first['checkpoint'])\n",
                 'checks': [{'name': 'resumed trajectory equals uninterrupted training',
                             'code': 'xs=[[0.0, 0.0], [0.0, 1.0], [1.0, 0.0], [1.0, 1.0]]\n'
                                     'ys=[0.0, 1.0, 1.0, 2.0]\n'
                                     "full=train_segment(xs,ys,8,7);a=train_segment(xs,ys,3,7);b=train_segment(xs,ys,5,99,a['checkpoint'])\n"
                                     "assert full['losses']==a['losses']+b['losses'] and "
                                     "full['batches']==a['batches']+b['batches']\n"
                                     "assert b['checkpoint']['step']==8\n"
                                     "assert all(torch.equal(v,b['checkpoint']['model'][k]) for k,v in "
                                     "full['checkpoint']['model'].items())\n"},
                            {'name': 'optimizer moments and RNG continue exactly',
                             'code': 'xs=[[0.0, 0.0], [0.0, 1.0], [1.0, 0.0], [1.0, 1.0]]\n'
                                     'ys=[0.0, 1.0, 1.0, 2.0]\n'
                                     "full=train_segment(xs,ys,5,4);a=train_segment(xs,ys,2,4);b=train_segment(xs,ys,3,4,a['checkpoint'])\n"
                                     "f=full['checkpoint'];r=b['checkpoint']\n"
                                     "assert torch.equal(f['rng'],r['rng'])\n"
                                     "for key,state in f['optimizer']['state'].items():\n"
                                     '    for name,value in state.items():\n'
                                     '        assert '
                                     "torch.equal(value,r['optimizer']['state'][key][name])\n"},
                            {'name': 'resume cannot mutate its supplied checkpoint',
                             'code': 'xs=[[0.0, 0.0], [0.0, 1.0], [1.0, 0.0], [1.0, 1.0]]\n'
                                     'ys=[0.0, 1.0, 1.0, 2.0]\n'
                                     'import copy\n'
                                     "a=train_segment(xs,ys,2,3)['checkpoint'];old=copy.deepcopy(a)\n"
                                     'train_segment(xs,ys,3,3,a)\n'
                                     "assert all(torch.equal(v,a['model'][k]) for k,v in "
                                     "old['model'].items()) and torch.equal(a['rng'],old['rng']) and "
                                     "a['step']==2\n"},
                            {'name': 'zero-step capture and caller RNG ownership',
                             'code': 'xs=[[0.0, 0.0], [0.0, 1.0], [1.0, 0.0], [1.0, 1.0]]\n'
                                     'ys=[0.0, 1.0, 1.0, 2.0]\n'
                                     'torch.manual_seed(91);old=torch.get_rng_state().clone()\n'
                                     'r=train_segment(xs,ys,0,3)\n'
                                     "assert r['checkpoint']['step']==0 and r['losses']==[] and "
                                     "r['batches']==[] and torch.equal(old,torch.get_rng_state())\n"},
                            {'name': 'data identity mismatch rejected',
                             'code': 'xs=[[0.0, 0.0], [0.0, 1.0], [1.0, 0.0], [1.0, 1.0]]\n'
                                     'ys=[0.0, 1.0, 1.0, 2.0]\n'
                                     "c=train_segment(xs,ys,1,3)['checkpoint']\n"
                                     'try:\n'
                                     '    train_segment(xs,[0.,1.,1.,9.],1,3,c)\n'
                                     'except ValueError:\n'
                                     '    pass\n'
                                     'else:\n'
                                     "    assert False, 'Reject the invalid input before changing "
                                     "state.'\n"}],
                 'project': True},
 'torchlora': {'entry': 'fit_low_rank',
               'fixture': 'base=[[0.,0.],[0.,0.]]\n'
                          'xs=[[1.,0.],[0.,1.],[1.,1.],[-1.,1.]]\n'
                          'ys=[[1.,2.],[2.,4.],[3.,6.],[1.,2.]]\n'
                          'result=fit_low_rank(base,xs,ys,1,4,7)\n',
               'checks': [{'name': 'a real rank-one target is learned',
                           'code': 'base=[[0.,0.],[0.,0.]]\n'
                                   'xs=[[1.,0.],[0.,1.],[1.,1.],[-1.,1.]]\n'
                                   'ys=[[1.,2.],[2.,4.],[3.,6.],[1.,2.]]\n'
                                   'r=fit_low_rank(base,xs,ys,1,100,7)\n'
                                   "assert r['loss']<.03 and r['loss']<r['history'][0]/100\n"
                                   "assert any(abs(v)>0 for row in r['b'] for v in row)\n"},
                          {'name': 'merge reproduces adapter inference',
                           'code': 'base=[[0.,0.],[0.,0.]]\n'
                                   'xs=[[1.,0.],[0.,1.],[1.,1.],[-1.,1.]]\n'
                                   'ys=[[1.,2.],[2.,4.],[3.,6.],[1.,2.]]\n'
                                   'r=fit_low_rank(base,xs,ys,1,12,5)\n'
                                   "x=torch.tensor(xs);a=torch.tensor(r['a']);b=torch.tensor(r['b']);w=torch.tensor(r['base'])\n"
                                   'p=x@w.T+(x@a.T)@b.T\n'
                                   "assert torch.allclose(p,torch.tensor(r['predictions']),atol=1e-5)\n"
                                   "assert torch.allclose(torch.tensor(r['merged']),w+b@a)\n"},
                          {'name': 'base and caller randomness remain owned',
                           'code': 'base=[[0.,0.],[0.,0.]]\n'
                                   'xs=[[1.,0.],[0.,1.],[1.,1.],[-1.,1.]]\n'
                                   'ys=[[1.,2.],[2.,4.],[3.,6.],[1.,2.]]\n'
                                   'import copy\n'
                                   'old=copy.deepcopy(base);torch.manual_seed(90);rng=torch.get_rng_state().clone()\n'
                                   'r=fit_low_rank(base,xs,ys,1,3,5)\n'
                                   "assert base==old==r['base'] and "
                                   'torch.equal(rng,torch.get_rng_state())\n'},
                          {'name': 'seeded training is reproducible',
                           'code': 'base=[[0.,0.],[0.,0.]]\n'
                                   'xs=[[1.,0.],[0.,1.],[1.,1.],[-1.,1.]]\n'
                                   'ys=[[1.,2.],[2.,4.],[3.,6.],[1.,2.]]\n'
                                   'assert '
                                   'fit_low_rank(base,xs,ys,1,4,7)==fit_low_rank(base,xs,ys,1,4,7)\n'},
                          {'name': 'impossible rank rejected',
                           'code': 'base=[[0.,0.],[0.,0.]]\n'
                                   'xs=[[1.,0.],[0.,1.],[1.,1.],[-1.,1.]]\n'
                                   'ys=[[1.,2.],[2.,4.],[3.,6.],[1.,2.]]\n'
                                   'try:\n'
                                   '    fit_low_rank(base,xs,ys,3,3,7)\n'
                                   'except ValueError:\n'
                                   '    pass\n'
                                   'else:\n'
                                   "    assert False, 'Reject the invalid input before changing "
                                   "state.'\n"}],
               'project': True},
 'torchsdpa': {'entry': 'masked_attention',
               'fixture': 'q=torch.tensor([[[[1.,0.],[0.,1.]]]],requires_grad=True)\n'
                          'k=torch.tensor([[[[1.,0.],[0.,1.]]]],requires_grad=True)\n'
                          'v=torch.tensor([[[[2.,0.],[0.,4.]]]],requires_grad=True)\n'
                          'allow=torch.tensor([[[[True,False],[False,False]]]])\n'
                          'result=masked_attention(q,k,v,allow)\n'
                          'result[0].sum().backward()\n',
               'checks': [{'name': 'allowed values and exact forbidden probabilities',
                           'code': 'q=torch.tensor([[[[1.,0.],[0.,1.]]]],requires_grad=True)\n'
                                   'k=torch.tensor([[[[1.,0.],[0.,1.]]]],requires_grad=True)\n'
                                   'v=torch.tensor([[[[2.,0.],[0.,4.]]]],requires_grad=True)\n'
                                   'out,w=masked_attention(q,k,v,torch.tensor([[[[True,False],[True,True]]]]))\n'
                                   'assert torch.equal(out[0,0,0],v[0,0,0]) and w[0,0,0,1].item()==0\n'
                                   'assert torch.allclose(w.sum(-1),torch.ones(1,1,2))\n'},
                          {'name': 'fully masked rows have finite zero backward',
                           'code': 'q=torch.tensor([[[[1.,0.],[0.,1.]]]],requires_grad=True)\n'
                                   'k=torch.tensor([[[[1.,0.],[0.,1.]]]],requires_grad=True)\n'
                                   'v=torch.tensor([[[[2.,0.],[0.,4.]]]],requires_grad=True)\n'
                                   'out,w=masked_attention(q,k,v,torch.zeros(1,1,2,2,dtype=torch.bool))\n'
                                   'out.sum().backward()\n'
                                   'assert torch.equal(out,torch.zeros_like(out)) and '
                                   'torch.equal(w,torch.zeros_like(w))\n'
                                   'assert all(torch.isfinite(t.grad).all() and '
                                   'torch.equal(t.grad,torch.zeros_like(t)) for t in (q,k,v))\n'},
                          {'name': 'masked keys cannot affect output or receive gradients',
                           'code': 'q=torch.tensor([[[[1.,0.],[0.,1.]]]],requires_grad=True)\n'
                                   'k=torch.tensor([[[[1.,0.],[0.,1.]]]],requires_grad=True)\n'
                                   'v=torch.tensor([[[[2.,0.],[0.,4.]]]],requires_grad=True)\n'
                                   'allow=torch.tensor([[[[True,False],[True,False]]]])\n'
                                   'out,w=masked_attention(q,k,v,allow);out.sum().backward()\n'
                                   'assert torch.equal(k.grad[:,:,1],torch.zeros_like(k.grad[:,:,1])) '
                                   'and torch.equal(v.grad[:,:,1],torch.zeros_like(v.grad[:,:,1]))\n'},
                          {'name': 'float masks rejected',
                           'code': 'q=torch.tensor([[[[1.,0.],[0.,1.]]]],requires_grad=True)\n'
                                   'k=torch.tensor([[[[1.,0.],[0.,1.]]]],requires_grad=True)\n'
                                   'v=torch.tensor([[[[2.,0.],[0.,4.]]]],requires_grad=True)\n'
                                   'try:\n'
                                   '    masked_attention(q,k,v,torch.ones(1,1,2,2))\n'
                                   'except ValueError:\n'
                                   '    pass\n'
                                   'else:\n'
                                   "    assert False, 'Reject the invalid input before changing "
                                   "state.'\n"}],
               'project': False},
 'torchrope': {'entry': 'rotary_positions',
               'fixture': 'x=torch.arange(8,dtype=torch.float32).reshape(1,1,2,4).requires_grad_()\n'
                          'result=rotary_positions(x,torch.tensor([0,3]))\n'
                          'result.sum().backward()\n',
               'checks': [{'name': 'zero positions and owned output',
                           'code': 'x=torch.randn(1,2,3,4);old=x.clone();r=rotary_positions(x,torch.zeros(3,dtype=torch.long))\n'
                                   'assert torch.equal(r,x) and torch.equal(x,old) and '
                                   'r.data_ptr()!=x.data_ptr()\n'},
                          {'name': 'rotations preserve norms and have real gradients',
                           'code': 'x=torch.randn(1,2,3,4,requires_grad=True);r=rotary_positions(x,torch.tensor([0,1,4]))\n'
                                   'assert torch.allclose(r.norm(dim=-1),x.norm(dim=-1),atol=1e-6)\n'
                                   'r.square().sum().backward();assert '
                                   'torch.allclose(x.grad,2*x,atol=1e-5)\n'},
                          {'name': 'shared offsets preserve query/key dot products',
                           'code': 'q=torch.arange(12,dtype=torch.float32).reshape(1,1,3,4)/10;k=q.flip(-1);p=torch.tensor([1,2,5])\n'
                                   'a=rotary_positions(q,p)@rotary_positions(k,p).transpose(-2,-1)\n'
                                   'b=rotary_positions(q,p+7)@rotary_positions(k,p+7).transpose(-2,-1)\n'
                                   'assert torch.allclose(a,b,atol=1e-5)\n'},
                          {'name': 'odd head width rejected',
                           'code': 'try:\n'
                                   '    rotary_positions(torch.ones(1,1,2,3),torch.tensor([0,1]))\n'
                                   'except ValueError:\n'
                                   '    pass\n'
                                   'else:\n'
                                   "    assert False, 'Reject the invalid input before changing "
                                   "state.'\n"}],
               'project': False},
 'torchkv': {'entry': 'cached_attention',
             'fixture': 'q=torch.arange(12,dtype=torch.float32).reshape(1,1,3,4)/10\n'
                        'k=q.flip(-1);v=q+1\n'
                        'first,cache=cached_attention(q[:,:,:1],k[:,:,:1],v[:,:,:1])\n'
                        'result=cached_attention(q[:,:,1:],k[:,:,1:],v[:,:,1:],cache)\n',
             'checks': [{'name': 'tokenwise inference matches full causal attention',
                         'code': 'q=torch.arange(12,dtype=torch.float32).reshape(1,1,3,4)/10\n'
                                 'k=q.flip(-1);v=q+1\n'
                                 'full,_=cached_attention(q,k,v);cache=None;parts=[]\n'
                                 'for i in range(3):\n'
                                 '    '
                                 'out,cache=cached_attention(q[:,:,i:i+1],k[:,:,i:i+1],v[:,:,i:i+1],cache);parts.append(out)\n'
                                 'assert torch.allclose(full,torch.cat(parts,dim=2),atol=1e-6)\n'},
                        {'name': 'multi-token chunks use the correct causal offset',
                         'code': 'q=torch.arange(12,dtype=torch.float32).reshape(1,1,3,4)/10\n'
                                 'k=q.flip(-1);v=q+1\n'
                                 'full,_=cached_attention(q,k,v);a,c=cached_attention(q[:,:,:1],k[:,:,:1],v[:,:,:1]);b,_=cached_attention(q[:,:,1:],k[:,:,1:],v[:,:,1:],c)\n'
                                 'assert torch.allclose(torch.cat([a,b],dim=2),full,atol=1e-6)\n'},
                        {'name': 'old cache and input chunks cannot alias new storage',
                         'code': 'q=torch.arange(12,dtype=torch.float32).reshape(1,1,3,4)/10\n'
                                 'k=q.flip(-1);v=q+1\n'
                                 "_,c=cached_attention(q[:,:,:1],k[:,:,:1],v[:,:,:1]);old=c['k'].clone();_,n=cached_attention(q[:,:,1:],k[:,:,1:],v[:,:,1:],c)\n"
                                 "n['k'].zero_();assert torch.equal(c['k'],old) and not "
                                 "torch.equal(k,torch.zeros_like(k)) and not n['k'].requires_grad\n"},
                        {'name': 'cache geometry mismatch rejected',
                         'code': 'q=torch.arange(12,dtype=torch.float32).reshape(1,1,3,4)/10\n'
                                 'k=q.flip(-1);v=q+1\n'
                                 'try:\n'
                                 '    '
                                 "cached_attention(q,k,v,{'k':torch.zeros(1,2,1,4),'v':torch.zeros(1,2,1,4)})\n"
                                 'except ValueError:\n'
                                 '    pass\n'
                                 'else:\n'
                                 "    assert False, 'Reject the invalid input before changing "
                                 "state.'\n"}],
             'project': False},
 'torchpacked': {'entry': 'packed_attention',
                 'fixture': 'q=torch.ones(1,1,4,2,requires_grad=True)\n'
                            'k=q.detach().clone().requires_grad_();v=torch.arange(8,dtype=torch.float32).reshape(1,1,4,2).requires_grad_()\n'
                            'result=packed_attention(q,k,v,torch.tensor([[0,0,1,-1]]))\n'
                            'result.sum().backward()\n',
                 'checks': [{'name': 'other documents cannot influence a packed query',
                             'code': 'q=torch.ones(1,1,4,2);k=q.clone();v=torch.arange(8,dtype=torch.float32).reshape(1,1,4,2);s=torch.tensor([[0,0,1,1]])\n'
                                     'a=packed_attention(q,k,v,s);poison=v.clone();poison[:,:,:2]+=10000\n'
                                     'b=packed_attention(q,k,poison,s)\n'
                                     'assert torch.equal(a[:,:,2:],b[:,:,2:])\n'},
                            {'name': 'future tokens are hidden within a document',
                             'code': 'q=torch.ones(1,1,3,2);k=q.clone();v=torch.arange(6,dtype=torch.float32).reshape(1,1,3,2);s=torch.zeros(1,3,dtype=torch.long)\n'
                                     'a=packed_attention(q,k,v,s);v[:,:,2]+=100\n'
                                     'b=packed_attention(q,k,v,s);assert '
                                     'torch.equal(a[:,:,:2],b[:,:,:2])\n'},
                            {'name': 'padding and forbidden gradients are finite zeros',
                             'code': 'q=torch.ones(1,1,3,2,requires_grad=True);k=q.detach().clone().requires_grad_();v=q.detach().clone().requires_grad_()\n'
                                     'r=packed_attention(q,k,v,torch.tensor([[0,1,-1]]));r[:,:,1].sum().backward()\n'
                                     'assert torch.equal(r[:,:,2],torch.zeros_like(r[:,:,2]))\n'
                                     'assert '
                                     'torch.equal(v.grad[:,:,0],torch.zeros_like(v.grad[:,:,0])) and '
                                     'all(torch.isfinite(t.grad).all() for t in (q,k,v))\n'},
                            {'name': 'invalid segment identity rejected',
                             'code': 'try:\n'
                                     '    '
                                     'packed_attention(torch.ones(1,1,1,2),torch.ones(1,1,1,2),torch.ones(1,1,1,2),torch.tensor([[-2]]))\n'
                                     'except ValueError:\n'
                                     '    pass\n'
                                     'else:\n'
                                     "    assert False, 'Reject the invalid input before changing "
                                     "state.'\n"}],
                 'project': False},
 'torchgqa': {'entry': 'grouped_attention',
              'fixture': 'q=torch.ones(1,4,2,2,requires_grad=True)\n'
                         'k=torch.ones(1,2,2,2,requires_grad=True);v=torch.arange(8,dtype=torch.float32).reshape(1,2,2,2).requires_grad_()\n'
                         'result=grouped_attention(q,k,v)\n'
                         'result.sum().backward()\n',
              'checks': [{'name': 'consecutive query groups map to the right KV head',
                          'code': 'q=torch.ones(1,4,1,2);k=torch.ones(1,2,1,2);v=torch.tensor([[[[1.,2.]],[[7.,8.]]]])\n'
                                  'r=grouped_attention(q,k,v)\n'
                                  'assert '
                                  'torch.equal(r[0,:,0],torch.tensor([[1.,2.],[1.,2.],[7.,8.],[7.,8.]]))\n'},
                         {'name': 'shared value gradients sum query contributions',
                          'code': 'q=torch.ones(1,4,1,2,requires_grad=True);k=torch.ones(1,2,1,2,requires_grad=True);v=torch.ones(1,2,1,2,requires_grad=True)\n'
                                  'grouped_attention(q,k,v).sum().backward()\n'
                                  'assert torch.equal(v.grad,torch.full_like(v,2)) and '
                                  'torch.isfinite(q.grad).all()\n'},
                         {'name': 'causal isolation with several heads',
                          'code': 'q=torch.ones(1,4,3,2);k=torch.ones(1,2,3,2);v=torch.arange(12,dtype=torch.float32).reshape(1,2,3,2)\n'
                                  'a=grouped_attention(q,k,v);v[:,:,2]+=100\n'
                                  'b=grouped_attention(q,k,v);assert '
                                  'torch.equal(a[:,:,:2],b[:,:,:2])\n'},
                         {'name': 'nondivisible head counts rejected',
                          'code': 'try:\n'
                                  '    '
                                  'grouped_attention(torch.ones(1,3,2,2),torch.ones(1,2,2,2),torch.ones(1,2,2,2))\n'
                                  'except ValueError:\n'
                                  '    pass\n'
                                  'else:\n'
                                  "    assert False, 'Reject the invalid input before changing "
                                  "state.'\n"}],
              'project': False},
 'torchrms': {'entry': 'rms_normalize',
              'fixture': 'x=torch.tensor([[3.,4.],[0.,0.]],requires_grad=True)\n'
                         'w=torch.ones(2,requires_grad=True)\n'
                         'result=rms_normalize(x,w)\n'
                         'result.sum().backward()\n',
              'checks': [{'name': 'RMS is not mean-centered layer norm',
                          'code': 'x=torch.full((2,3),2.)\n'
                                  'r=rms_normalize(x,torch.ones(3))\n'
                                  'assert torch.allclose(r,torch.ones_like(x),atol=1e-5)\n'},
                         {'name': 'zero inputs and both parameter gradients stay finite',
                          'code': 'x=torch.tensor([[3.,4.],[0.,0.]],requires_grad=True);w=torch.ones(2,requires_grad=True)\n'
                                  'r=rms_normalize(x,w);r.sum().backward()\n'
                                  'assert torch.equal(r[1],torch.zeros(2)) and '
                                  'torch.isfinite(x.grad).all() and w.grad.abs().sum()>0\n'},
                         {'name': 'low precision squares accumulate after promotion',
                          'code': 'x=torch.tensor([[1000.,1000.]],dtype=torch.float16);w=torch.ones(2,dtype=torch.float16)\n'
                                  'r=rms_normalize(x,w)\n'
                                  'assert r.dtype==torch.float16 and '
                                  'torch.allclose(r,torch.ones_like(r),atol=.002)\n'},
                         {'name': 'shape and epsilon mismatches rejected',
                          'code': 'try:\n'
                                  '    rms_normalize(torch.ones(2,3),torch.ones(2))\n'
                                  'except ValueError:\n'
                                  '    pass\n'
                                  'else:\n'
                                  "    assert False, 'Reject the invalid input before changing "
                                  "state.'\n"
                                  'try:\n'
                                  '    rms_normalize(torch.ones(2,3),torch.ones(3),0)\n'
                                  'except ValueError:\n'
                                  '    pass\n'
                                  'else:\n'
                                  "    assert False, 'Reject the invalid input before changing "
                                  "state.'\n"}],
              'project': False},
 'torchblock': {'entry': 'decoder_block',
                'fixture': 'x=torch.arange(12,dtype=torch.float32).reshape(1,3,4)/10\n'
                           "p={'n1':torch.ones(4,requires_grad=True),'n2':torch.ones(4,requires_grad=True)}\n"
                           'for key,shape in '
                           "[('qkv',(12,4)),('out',(4,4)),('ff1',(8,4)),('ff2',(4,8))]:\n"
                           '    '
                           'p[key]=(torch.arange(shape[0]*shape[1],dtype=torch.float32).reshape(shape).sin()*.2).requires_grad_()\n'
                           'result=decoder_block(x,p,2)\n'
                           'result.square().sum().backward()\n',
                'checks': [{'name': 'future tokens cannot change earlier outputs',
                            'code': 'x=torch.arange(12,dtype=torch.float32).reshape(1,3,4)/10\n'
                                    "p={'n1':torch.ones(4,requires_grad=True),'n2':torch.ones(4,requires_grad=True)}\n"
                                    'for key,shape in '
                                    "[('qkv',(12,4)),('out',(4,4)),('ff1',(8,4)),('ff2',(4,8))]:\n"
                                    '    '
                                    'p[key]=(torch.arange(shape[0]*shape[1],dtype=torch.float32).reshape(shape).sin()*.2).requires_grad_()\n'
                                    'a=decoder_block(x,p,2);poison=x.clone();poison[:,2]+=100\n'
                                    'b=decoder_block(poison,p,2)\n'
                                    'assert torch.allclose(a[:,:2],b[:,:2],atol=1e-6)\n'},
                           {'name': 'all parameter families participate in autograd',
                            'code': 'x=torch.arange(12,dtype=torch.float32).reshape(1,3,4)/10\n'
                                    "p={'n1':torch.ones(4,requires_grad=True),'n2':torch.ones(4,requires_grad=True)}\n"
                                    'for key,shape in '
                                    "[('qkv',(12,4)),('out',(4,4)),('ff1',(8,4)),('ff2',(4,8))]:\n"
                                    '    '
                                    'p[key]=(torch.arange(shape[0]*shape[1],dtype=torch.float32).reshape(shape).sin()*.2).requires_grad_()\n'
                                    'r=decoder_block(x,p,2);r.square().sum().backward()\n'
                                    'assert all(v.grad is not None and torch.isfinite(v.grad).all() '
                                    'and v.grad.abs().sum()>0 for v in p.values())\n'},
                           {'name': 'zero branches preserve the input residual',
                            'code': 'x=torch.arange(12,dtype=torch.float32).reshape(1,3,4)/10\n'
                                    "p={'n1':torch.ones(4,requires_grad=True),'n2':torch.ones(4,requires_grad=True)}\n"
                                    'for key,shape in '
                                    "[('qkv',(12,4)),('out',(4,4)),('ff1',(8,4)),('ff2',(4,8))]:\n"
                                    '    '
                                    'p[key]=(torch.arange(shape[0]*shape[1],dtype=torch.float32).reshape(shape).sin()*.2).requires_grad_()\n'
                                    "p['out']=torch.zeros(4,4);p['ff2']=torch.zeros(4,8)\n"
                                    'assert torch.equal(decoder_block(x,p,2),x)\n'},
                           {'name': 'backward cannot cross the causal boundary',
                            'code': 'x=torch.arange(12,dtype=torch.float32).reshape(1,3,4)/10\n'
                                    "p={'n1':torch.ones(4,requires_grad=True),'n2':torch.ones(4,requires_grad=True)}\n"
                                    'for key,shape in '
                                    "[('qkv',(12,4)),('out',(4,4)),('ff1',(8,4)),('ff2',(4,8))]:\n"
                                    '    '
                                    'p[key]=(torch.arange(shape[0]*shape[1],dtype=torch.float32).reshape(shape).sin()*.2).requires_grad_()\n'
                                    'x=x.clone().requires_grad_();decoder_block(x,p,2)[:,0].sum().backward()\n'
                                    'assert torch.equal(x.grad[:,1:],torch.zeros_like(x.grad[:,1:])) '
                                    'and torch.isfinite(x.grad).all()\n'},
                           {'name': 'invalid parameter schema rejected',
                            'code': 'x=torch.arange(12,dtype=torch.float32).reshape(1,3,4)/10\n'
                                    "p={'n1':torch.ones(4,requires_grad=True),'n2':torch.ones(4,requires_grad=True)}\n"
                                    'for key,shape in '
                                    "[('qkv',(12,4)),('out',(4,4)),('ff1',(8,4)),('ff2',(4,8))]:\n"
                                    '    '
                                    'p[key]=(torch.arange(shape[0]*shape[1],dtype=torch.float32).reshape(shape).sin()*.2).requires_grad_()\n'
                                    "p.pop('n2')\n"
                                    'try:\n'
                                    '    decoder_block(x,p,2)\n'
                                    'except ValueError:\n'
                                    '    pass\n'
                                    'else:\n'
                                    "    assert False, 'Reject the invalid input before changing "
                                    "state.'\n"}],
                'project': True},
 'torchtinylm': {'entry': 'train_tiny_lm',
                 'fixture': 'tokens=[[0,1,2,0,1,2],[1,2,0,1,2,0]]\n'
                            'result=train_tiny_lm(tokens,3,4,7)\n',
                 'checks': [{'name': 'real transformer optimization learns the token pattern',
                             'code': 'tokens=[[0,1,2,0,1,2],[1,2,0,1,2,0]]\n'
                                     'r=train_tiny_lm(tokens,3,60,7)\n'
                                     "assert r['loss']<.1 and r['loss']<r['initial_loss']/10 and "
                                     "len(r['history'])==60\n"},
                            {'name': 'exported logits reproduce shifted loss and perplexity',
                             'code': 'tokens=[[0,1,2,0,1,2],[1,2,0,1,2,0]]\n'
                                     'import math,json\n'
                                     "r=train_tiny_lm(tokens,3,6,4);a=json.loads(json.dumps(r['artifact']));z=tiny_lm_logits(a,tokens)\n"
                                     'l=torch.nn.functional.cross_entropy(z[:,:-1].reshape(-1,3),torch.tensor(tokens)[:,1:].reshape(-1))\n'
                                     "assert abs(l.item()-r['loss'])<1e-6 and "
                                     "abs(math.exp(l.item())-r['perplexity'])<1e-6 and not "
                                     'z.requires_grad\n'},
                            {'name': 'saved model cannot read a future token',
                             'code': 'tokens=[[0,1,2,0,1,2],[1,2,0,1,2,0]]\n'
                                     "a=train_tiny_lm(tokens,3,3,7)['artifact']\n"
                                     'x=tiny_lm_logits(a,[[0,1,2,0]]);y=tiny_lm_logits(a,[[0,1,2,1]])\n'
                                     'assert torch.allclose(x[:,:3],y[:,:3],atol=1e-6)\n'},
                            {'name': 'training is seeded and leaves caller RNG intact',
                             'code': 'tokens=[[0,1,2,0,1,2],[1,2,0,1,2,0]]\n'
                                     'torch.manual_seed(17);old=torch.get_rng_state().clone();a=train_tiny_lm(tokens,3,2,5)\n'
                                     'assert torch.equal(old,torch.get_rng_state())\n'
                                     'assert a==train_tiny_lm(tokens,3,2,5)\n'},
                            {'name': 'too-short and invalid token sequences fail',
                             'code': 'try:\n'
                                     '    train_tiny_lm([[0]],3,2,7)\n'
                                     'except ValueError:\n'
                                     '    pass\n'
                                     'else:\n'
                                     "    assert False, 'Reject the invalid input before changing "
                                     "state.'\n"
                                     'try:\n'
                                     '    train_tiny_lm([[0,3]],3,2,7)\n'
                                     'except ValueError:\n'
                                     '    pass\n'
                                     'else:\n'
                                     "    assert False, 'Reject the invalid input before changing "
                                     "state.'\n"}],
                 'project': True},
 'torchseqcls': {'entry': 'train_sequence_classifier',
                 'fixture': "train=[{'id': 't0', 'tokens': [1, 1], 'y': 0}, {'id': 't1', 'tokens': [1, "
                            "2], 'y': 0}, {'id': 't2', 'tokens': [3, 4], 'y': 1}, {'id': 't3', "
                            "'tokens': [4, 3, 4], 'y': 1}, {'id': 'e0', 'tokens': [1], 'y': 0}, {'id': "
                            "'e1', 'tokens': [2], 'y': 0}, {'id': 'e2', 'tokens': [3], 'y': 1}, {'id': "
                            "'e3', 'tokens': [4], 'y': 1}]\n"
                            "validation=[{'id': 'v0', 'tokens': [1], 'y': 0}, {'id': 'v1', 'tokens': "
                            "[4], 'y': 1}]\n"
                            "test=[{'id': 'z0', 'tokens': [2, 1], 'y': 0}, {'id': 'z1', 'tokens': [3], "
                            "'y': 1}]\n"
                            'result=train_sequence_classifier(train,validation,test,5,4,7)\n',
                 'checks': [{'name': 'actual training and validation-selected checkpoint',
                             'code': "train=[{'id': 't0', 'tokens': [1, 1], 'y': 0}, {'id': 't1', "
                                     "'tokens': [1, 2], 'y': 0}, {'id': 't2', 'tokens': [3, 4], 'y': "
                                     "1}, {'id': 't3', 'tokens': [4, 3, 4], 'y': 1}, {'id': 'e0', "
                                     "'tokens': [1], 'y': 0}, {'id': 'e1', 'tokens': [2], 'y': 0}, "
                                     "{'id': 'e2', 'tokens': [3], 'y': 1}, {'id': 'e3', 'tokens': [4], "
                                     "'y': 1}]\n"
                                     "validation=[{'id': 'v0', 'tokens': [1], 'y': 0}, {'id': 'v1', "
                                     "'tokens': [4], 'y': 1}]\n"
                                     "test=[{'id': 'z0', 'tokens': [2, 1], 'y': 0}, {'id': 'z1', "
                                     "'tokens': [3], 'y': 1}]\n"
                                     'r=train_sequence_classifier(train,validation,test,5,40,7)\n'
                                     "assert r['training_loss']<.1 and "
                                     "r['training_loss']<r['initial_loss'] and "
                                     "r['predictions']==[0,1]\n"
                                     "assert r['validation_loss']==min(r['history']) and "
                                     "r['best_step']==r['history'].index(min(r['history']))+1\n"},
                            {'name': 'right padding cannot change exported predictions',
                             'code': "train=[{'id': 't0', 'tokens': [1, 1], 'y': 0}, {'id': 't1', "
                                     "'tokens': [1, 2], 'y': 0}, {'id': 't2', 'tokens': [3, 4], 'y': "
                                     "1}, {'id': 't3', 'tokens': [4, 3, 4], 'y': 1}, {'id': 'e0', "
                                     "'tokens': [1], 'y': 0}, {'id': 'e1', 'tokens': [2], 'y': 0}, "
                                     "{'id': 'e2', 'tokens': [3], 'y': 1}, {'id': 'e3', 'tokens': [4], "
                                     "'y': 1}]\n"
                                     "validation=[{'id': 'v0', 'tokens': [1], 'y': 0}, {'id': 'v1', "
                                     "'tokens': [4], 'y': 1}]\n"
                                     "test=[{'id': 'z0', 'tokens': [2, 1], 'y': 0}, {'id': 'z1', "
                                     "'tokens': [3], 'y': 1}]\n"
                                     "a=train_sequence_classifier(train,validation,test,5,3,4)['artifact']\n"
                                     'x=sequence_logits(a,[[1,2],[3]])\n'
                                     'y=sequence_logits(a,[[1,2,0,0],[3,0,0,0]])\n'
                                     'assert torch.allclose(x,y,atol=1e-5) and not y.requires_grad\n'},
                            {'name': 'held-out labels cannot change the artifact',
                             'code': "train=[{'id': 't0', 'tokens': [1, 1], 'y': 0}, {'id': 't1', "
                                     "'tokens': [1, 2], 'y': 0}, {'id': 't2', 'tokens': [3, 4], 'y': "
                                     "1}, {'id': 't3', 'tokens': [4, 3, 4], 'y': 1}, {'id': 'e0', "
                                     "'tokens': [1], 'y': 0}, {'id': 'e1', 'tokens': [2], 'y': 0}, "
                                     "{'id': 'e2', 'tokens': [3], 'y': 1}, {'id': 'e3', 'tokens': [4], "
                                     "'y': 1}]\n"
                                     "validation=[{'id': 'v0', 'tokens': [1], 'y': 0}, {'id': 'v1', "
                                     "'tokens': [4], 'y': 1}]\n"
                                     "test=[{'id': 'z0', 'tokens': [2, 1], 'y': 0}, {'id': 'z1', "
                                     "'tokens': [3], 'y': 1}]\n"
                                     'import copy\n'
                                     'a=train_sequence_classifier(train,validation,test,5,4,7);poison=copy.deepcopy(test)\n'
                                     "for r in poison:r['y']=1-r['y']\n"
                                     'b=train_sequence_classifier(train,validation,poison,5,4,7)\n'
                                     "assert a['artifact']==b['artifact'] and "
                                     "a['predictions']==b['predictions'] and "
                                     "a['test_loss']!=b['test_loss']\n"},
                            {'name': 'reloaded checkpoint reproduces validation evidence',
                             'code': "train=[{'id': 't0', 'tokens': [1, 1], 'y': 0}, {'id': 't1', "
                                     "'tokens': [1, 2], 'y': 0}, {'id': 't2', 'tokens': [3, 4], 'y': "
                                     "1}, {'id': 't3', 'tokens': [4, 3, 4], 'y': 1}, {'id': 'e0', "
                                     "'tokens': [1], 'y': 0}, {'id': 'e1', 'tokens': [2], 'y': 0}, "
                                     "{'id': 'e2', 'tokens': [3], 'y': 1}, {'id': 'e3', 'tokens': [4], "
                                     "'y': 1}]\n"
                                     "validation=[{'id': 'v0', 'tokens': [1], 'y': 0}, {'id': 'v1', "
                                     "'tokens': [4], 'y': 1}]\n"
                                     "test=[{'id': 'z0', 'tokens': [2, 1], 'y': 0}, {'id': 'z1', "
                                     "'tokens': [3], 'y': 1}]\n"
                                     "r=train_sequence_classifier(train,validation,test,5,5,7);z=sequence_logits(r['artifact'],[row['tokens'] "
                                     'for row in validation])\n'
                                     "l=torch.nn.functional.cross_entropy(z,torch.tensor([row['y'] for "
                                     'row in validation]))\n'
                                     "assert abs(l.item()-r['validation_loss'])<1e-6\n"},
                            {'name': 'all-padding input and identity leakage rejected',
                             'code': "train=[{'id': 't0', 'tokens': [1, 1], 'y': 0}, {'id': 't1', "
                                     "'tokens': [1, 2], 'y': 0}, {'id': 't2', 'tokens': [3, 4], 'y': "
                                     "1}, {'id': 't3', 'tokens': [4, 3, 4], 'y': 1}, {'id': 'e0', "
                                     "'tokens': [1], 'y': 0}, {'id': 'e1', 'tokens': [2], 'y': 0}, "
                                     "{'id': 'e2', 'tokens': [3], 'y': 1}, {'id': 'e3', 'tokens': [4], "
                                     "'y': 1}]\n"
                                     "validation=[{'id': 'v0', 'tokens': [1], 'y': 0}, {'id': 'v1', "
                                     "'tokens': [4], 'y': 1}]\n"
                                     "test=[{'id': 'z0', 'tokens': [2, 1], 'y': 0}, {'id': 'z1', "
                                     "'tokens': [3], 'y': 1}]\n"
                                     'try:\n'
                                     '    train_sequence_classifier(train,train,test,5,2,7)\n'
                                     'except ValueError:\n'
                                     '    pass\n'
                                     'else:\n'
                                     "    assert False, 'Reject the invalid input before changing "
                                     "state.'\n"
                                     'try:\n'
                                     "    sequence_logits({'vocab':5,'state':{}},[[0,0]])\n"
                                     'except ValueError:\n'
                                     '    pass\n'
                                     'else:\n'
                                     "    assert False, 'Reject the invalid input before changing "
                                     "state.'\n"}],
                 'project': True}}


def _draw(view, entry):
    if view.function != entry:
        return None
    values = {}
    for name, value in view.locals.items():
        if hasattr(value, 'detach') and hasattr(value, 'numel'):
            tensor = value.detach().cpu()
            if tensor.numel() <= 64:
                if tensor.ndim > 2:
                    tensor = tensor.reshape(-1, tensor.shape[-1])
                values[name] = tensor.tolist()
            else:
                values[name] = 'tensor ' + str(tuple(tensor.shape))
        else:
            values[name] = value
    view.locals = values
    return render(view)


for lab_id, spec in SPECS.items():
    def trace(namespace, recorder, spec=spec):
        recorder.context = spec['entry'] + ' · real PyTorch CPU fixture'
        recorder.watch(lambda: exec(compile(spec['fixture'], '<torch-fixture>', 'exec'), namespace),
                       lambda view: _draw(view, spec['entry']))
        return ''
    def check(namespace, code):
        exec(compile(code, '<torch-check>', 'exec'), dict(namespace))
    checks = [(row['name'], lambda namespace, code=row['code']: check(namespace, code))
              for row in spec['checks']]
    register(lab_id, {'practice': {'file': lab_id+'.py',
             'names': [(spec['entry'], 'a function '+spec['entry'])],
             'trace': trace, 'checks': checks}})
