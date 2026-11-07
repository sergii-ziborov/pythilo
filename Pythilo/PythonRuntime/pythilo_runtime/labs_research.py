"""Generated senior CPU Labs; see scripts/research-content/."""
SPECS = {'torchfocal': {'entry': 'focal_loss',
                'fixture': 'x=torch.tensor([[2.,0.],[0.,1.]],requires_grad=True)\n'
                           'result=focal_loss(x,torch.tensor([1,1]))\n'
                           'result.backward()\n',
                'checks': [{'name': 'gamma zero matches the declared weighted reduction',
                            'code': 'from torch.nn import functional as F\n'
                                    'x = torch.tensor([[2.0, 0.0], [1.0, 3.0]], dtype=torch.float64)\n'
                                    'y = torch.tensor([0, 1])\n'
                                    'a = torch.tensor([2.0, 4.0], dtype=x.dtype)\n'
                                    'assert torch.allclose(focal_loss(x, y, 0, a), F.cross_entropy(x, '
                                    "y, weight=a, reduction='sum') / 2), 'Contract failed: gamma zero "
                                    "matches the declared weighted reduction.'\n"},
                           {'name': 'focal factor participates in the gradient',
                            'code': 'x = torch.tensor([[0.3, -0.4]], dtype=torch.float64, '
                                    'requires_grad=True)\n'
                                    'y = torch.tensor([1])\n'
                                    'focal_loss(x, y).backward()\n'
                                    'actual = x.grad[0, 0].item()\n'
                                    'h = 1e-05\n'
                                    'p = x.detach().clone()\n'
                                    'm = p.clone()\n'
                                    'p[0, 0] += h\n'
                                    'm[0, 0] -= h\n'
                                    'assert abs(actual - (focal_loss(p, y) - focal_loss(m, y)).item() / '
                                    "(2 * h)) < 1e-07, 'Contract failed: focal factor participates in "
                                    "the gradient.'\n"},
                           {'name': 'ignored rows and empty valid batch retain finite gradients',
                            'code': 'x = torch.randn(3, 2, requires_grad=True)\n'
                                    'y = torch.tensor([-100, 1, -100])\n'
                                    'assert torch.allclose(focal_loss(x, y), focal_loss(x[1:2], '
                                    "y[1:2])), 'Contract failed: ignored rows and empty valid batch "
                                    "retain finite gradients.'\n"
                                    'z = focal_loss(x, torch.full((3,), -100))\n'
                                    'z.backward()\n'
                                    'assert z.item() == 0 and torch.equal(x.grad, torch.zeros_like(x)), '
                                    "'Contract failed: ignored rows and empty valid batch retain finite "
                                    "gradients.'\n"},
                           {'name': 'large logits and row shifts preserve the result',
                            'code': 'x = torch.tensor([[1000.0, -1000.0], [0.0, 2.0]], '
                                    'requires_grad=True)\n'
                                    'y = torch.tensor([1, 0])\n'
                                    'r = focal_loss(x, y)\n'
                                    'r.backward()\n'
                                    'assert torch.isfinite(r) and torch.isfinite(x.grad).all(), '
                                    "'Contract failed: large logits and row shifts preserve the "
                                    "result.'\n"
                                    'assert torch.allclose(r, focal_loss(x.detach() + 100, y)), '
                                    "'Contract failed: large logits and row shifts preserve the "
                                    "result.'\n"},
                           {'name': 'invalid weights and labels fail',
                            'code': 'try:\n'
                                    '    focal_loss(torch.zeros(1, 2), torch.tensor([2]))\n'
                                    'except ValueError:\n'
                                    '    pass\n'
                                    'else:\n'
                                    "    assert False, 'Reject invalid input before changing state.'\n"
                                    'try:\n'
                                    '    focal_loss(torch.zeros(1, 2), torch.tensor([0]), '
                                    'alpha=torch.tensor([0.0, 1.0]))\n'
                                    'except ValueError:\n'
                                    '    pass\n'
                                    'else:\n'
                                    "    assert False, 'Reject invalid input before changing "
                                    "state.'\n"}],
                'project': False},
 'torchsam': {'entry': 'sam_step',
              'fixture': 'm=torch.nn.Linear(1,1,bias=False)\n'
                         'optimizer=torch.optim.SGD(m.parameters(),lr=.1)\n'
                         'result=sam_step(m,optimizer,lambda:m(torch.ones(2,1)).square().mean(),.1)\n',
              'checks': [{'name': 'analytic quadratic uses the perturbed gradient once',
                          'code': 'm = torch.nn.Linear(1, 1, bias=False)\n'
                                  'with torch.no_grad():\n'
                                  '    m.weight.fill_(2)\n'
                                  'o = torch.optim.SGD(m.parameters(), lr=0.1)\n'
                                  'r = sam_step(m, o, lambda: m.weight.square().sum(), 0.5)\n'
                                  "assert abs(m.weight.item() - 1.5) < 1e-06 and abs(r['norm'] - 4) < "
                                  "1e-06, 'Contract failed: analytic quadratic uses the perturbed "
                                  "gradient once.'\n"},
                         {'name': 'closure runs twice but momentum advances once',
                          'code': 'm = torch.nn.Linear(1, 1, bias=False)\n'
                                  'o = torch.optim.SGD(m.parameters(), lr=0.1, momentum=0.9)\n'
                                  'calls = []\n'
                                  '\n'
                                  'def closure():\n'
                                  '    calls.append(1)\n'
                                  '    return m.weight.square().sum()\n'
                                  'sam_step(m, o, closure, 0.1)\n'
                                  "assert len(calls) == 2 and len(o.state) == 1 and ('momentum_buffer' "
                                  "in o.state[m.weight]), 'Contract failed: closure runs twice but "
                                  "momentum advances once.'\n"},
                         {'name': 'failed second pass restores exact parameters and state',
                          'code': 'm = torch.nn.Linear(2, 1)\n'
                                  'o = torch.optim.Adam(m.parameters())\n'
                                  'saved = [p.detach().clone() for p in m.parameters()]\n'
                                  'calls = []\n'
                                  '\n'
                                  'def closure():\n'
                                  '    calls.append(1)\n'
                                  '    if len(calls) == 2:\n'
                                  "        raise RuntimeError('second pass failure')\n"
                                  '    return m(torch.ones(1, 2)).square().sum()\n'
                                  'try:\n'
                                  '    sam_step(m, o, closure, 0.1)\n'
                                  'except RuntimeError:\n'
                                  '    pass\n'
                                  'else:\n'
                                  "    assert False, 'Contract failed: failed second pass restores "
                                  "exact parameters and state.'\n"
                                  'assert all((torch.equal(p, v) and p.grad is None for p, v in '
                                  "zip(m.parameters(), saved))) and (not o.state), 'Contract failed: "
                                  "failed second pass restores exact parameters and state.'\n"},
                         {'name': 'zero first gradient remains finite',
                          'code': 'm = torch.nn.Linear(1, 1, bias=False)\n'
                                  'with torch.no_grad():\n'
                                  '    m.weight.zero_()\n'
                                  'o = torch.optim.SGD(m.parameters(), lr=0.1)\n'
                                  'r = sam_step(m, o, lambda: m.weight.square().sum(), 0.1)\n'
                                  "assert r['norm'] == 0 and m.weight.item() == 0, 'Contract failed: "
                                  "zero first gradient remains finite.'\n"},
                         {'name': 'bad radius and missing ownership fail',
                          'code': 'try:\n'
                                  '    sam_step(torch.nn.Linear(1, 1), '
                                  'torch.optim.SGD([torch.nn.Parameter(torch.ones(1))], lr=0.1), '
                                  'lambda: torch.ones(1), 0.1)\n'
                                  'except ValueError:\n'
                                  '    pass\n'
                                  'else:\n'
                                  "    assert False, 'Reject invalid input before changing state.'\n"
                                  'try:\n'
                                  '    sam_step(torch.nn.Linear(1, 1), None, None, -1)\n'
                                  'except ValueError:\n'
                                  '    pass\n'
                                  'else:\n'
                                  "    assert False, 'Reject invalid input before changing state.'\n"}],
              'project': False},
 'torchpcgrad': {'entry': 'project_conflicts',
                 'fixture': 'g=torch.tensor([[1.,-1.],[0.,1.],[1.,0.]])\n'
                            'result=project_conflicts(g,3)\n',
                 'checks': [{'name': 'two-task projection matches independent geometry',
                             'code': 'g = torch.tensor([[1.0, -1.0], [0.0, 1.0]], dtype=torch.float64)\n'
                                     'r = project_conflicts(g, 1)\n'
                                     'assert torch.allclose(r, torch.tensor([[1.0, 0.0], [0.5, 0.5]], '
                                     "dtype=g.dtype), atol=1e-12), 'Contract failed: two-task "
                                     "projection matches independent geometry.'\n"},
                            {'name': 'aligned and zero peers do not change gradients',
                             'code': 'g = torch.tensor([[1.0, 2.0], [2.0, 4.0], [0.0, 0.0]])\n'
                                     "assert torch.equal(project_conflicts(g), g), 'Contract failed: "
                                     "aligned and zero peers do not change gradients.'\n"},
                            {'name': 'original matrix and global random state remain owned',
                             'code': 'import random\n'
                                     'random.seed(91)\n'
                                     'state = random.getstate()\n'
                                     'g = torch.tensor([[1.0, -1.0], [0.0, 1.0]], requires_grad=True)\n'
                                     'saved = g.detach().clone()\n'
                                     'r = project_conflicts(g, 9)\n'
                                     'assert torch.equal(g, saved) and (not r.requires_grad) and '
                                     "(random.getstate() == state), 'Contract failed: original matrix "
                                     "and global random state remain owned.'\n"},
                            {'name': 'seed-local ordering is reproducible',
                             'code': 'g = torch.tensor([[1.0, -2.0, 0.0], [-1.0, 0.0, 2.0], [0.0, 2.0, '
                                     '-1.0]])\n'
                                     'assert torch.equal(project_conflicts(g, 7), project_conflicts(g, '
                                     "7)) and torch.isfinite(project_conflicts(g, 1)).all(), 'Contract "
                                     "failed: seed-local ordering is reproducible.'\n"},
                            {'name': 'bad shapes and nonfinite vectors fail',
                             'code': 'try:\n'
                                     '    project_conflicts(torch.ones(3))\n'
                                     'except ValueError:\n'
                                     '    pass\n'
                                     'else:\n'
                                     "    assert False, 'Reject invalid input before changing state.'\n"
                                     'try:\n'
                                     "    project_conflicts(torch.tensor([[float('nan')], [1.0]]))\n"
                                     'except ValueError:\n'
                                     '    pass\n'
                                     'else:\n'
                                     "    assert False, 'Reject invalid input before changing "
                                     "state.'\n"}],
                 'project': False},
 'torchgroupdro': {'entry': 'group_dro',
                   'fixture': 'losses=torch.tensor([1.,1.,3.],requires_grad=True)\n'
                              'result,log_q=group_dro(losses,torch.tensor([0,0,1]),torch.zeros(2),.5)\n'
                              'result.backward()\n',
                   'checks': [{'name': 'adversary uses group means and normalized log state',
                               'code': 'x = torch.tensor([1.0, 1.0, 3.0], dtype=torch.float64, '
                                       'requires_grad=True)\n'
                                       'r, q = group_dro(x, torch.tensor([0, 0, 1]), torch.zeros(2, '
                                       'dtype=x.dtype), 0.5)\n'
                                       'w = torch.tensor([0.5, 1.5], dtype=x.dtype).softmax(0)\n'
                                       'assert torch.allclose(q.exp(), w) and torch.allclose(r, w @ '
                                       "torch.tensor([1.0, 3.0], dtype=x.dtype)), 'Contract failed: "
                                       "adversary uses group means and normalized log state.'\n"},
                              {'name': 'only sample losses receive gradients',
                               'code': 'x = torch.tensor([1.0, 1.0, 3.0], requires_grad=True)\n'
                                       'old = torch.zeros(2, requires_grad=True)\n'
                                       'r, q = group_dro(x, torch.tensor([0, 0, 1]), old, 0.5)\n'
                                       'r.backward()\n'
                                       'assert torch.allclose(x.grad, torch.stack([q.exp()[0] / 2, '
                                       'q.exp()[0] / 2, q.exp()[1]])) and old.grad is None and (not '
                                       "q.requires_grad), 'Contract failed: only sample losses receive "
                                       "gradients.'\n"},
                              {'name': 'duplicating a group row cannot alter its risk',
                               'code': 'a = group_dro(torch.tensor([1.0, 3.0]), torch.tensor([0, 1]), '
                                       'torch.zeros(2), 0.2)\n'
                                       'b = group_dro(torch.tensor([1.0, 1.0, 3.0]), torch.tensor([0, '
                                       '0, 1]), torch.zeros(2), 0.2)\n'
                                       'assert torch.allclose(a[0], b[0]) and torch.allclose(a[1], '
                                       "b[1]), 'Contract failed: duplicating a group row cannot alter "
                                       "its risk.'\n"},
                              {'name': 'large adversary offsets are irrelevant',
                               'code': 'x = torch.tensor([1.0, 2.0])\n'
                                       'g = torch.tensor([0, 1])\n'
                                       'a = group_dro(x, g, torch.tensor([0.0, 2.0]), 0.3)\n'
                                       'b = group_dro(x, g, torch.tensor([1000.0, 1002.0]), 0.3)\n'
                                       'assert torch.allclose(a[0], b[0], atol=1e-05) and '
                                       "torch.allclose(a[1], b[1], atol=1e-05), 'Contract failed: large "
                                       "adversary offsets are irrelevant.'\n"},
                              {'name': 'missing groups and invalid rates fail',
                               'code': 'try:\n'
                                       '    group_dro(torch.ones(2), torch.tensor([0, 0]), '
                                       'torch.zeros(2))\n'
                                       'except ValueError:\n'
                                       '    pass\n'
                                       'else:\n'
                                       "    assert False, 'Reject invalid input before changing "
                                       "state.'\n"
                                       'try:\n'
                                       '    group_dro(torch.ones(2), torch.tensor([0, 1]), '
                                       'torch.zeros(2), 0)\n'
                                       'except ValueError:\n'
                                       '    pass\n'
                                       'else:\n'
                                       "    assert False, 'Reject invalid input before changing "
                                       "state.'\n"}],
                   'project': False},
 'torchhetero': {'entry': 'gaussian_nll',
                 'fixture': 'm=torch.tensor([0.,1.],requires_grad=True)\n'
                            's=torch.tensor([-1.,2.],requires_grad=True)\n'
                            'result=gaussian_nll(m,s,torch.tensor([1.,3.]))\n'
                            'result.backward()\n',
                 'checks': [{'name': 'matches the independent Gaussian density',
                             'code': 'import math\n'
                                     'm = torch.tensor([1.0, 2.0], dtype=torch.float64)\n'
                                     'v = torch.tensor([0.5, 2.0], dtype=m.dtype)\n'
                                     'raw = torch.log(torch.expm1(v - 0.0001))\n'
                                     'y = torch.tensor([2.0, 0.0], dtype=m.dtype)\n'
                                     'expected = (0.5 * (math.log(2 * math.pi) + v.log() + (y - '
                                     'm).square() / v)).mean()\n'
                                     'assert torch.allclose(gaussian_nll(m, raw, y), expected, '
                                     "atol=1e-12), 'Contract failed: matches the independent Gaussian "
                                     "density.'\n"},
                            {'name': 'both outputs receive finite autograd derivatives',
                             'code': 'm = torch.zeros(2, requires_grad=True)\n'
                                     'raw = torch.zeros(2, requires_grad=True)\n'
                                     'gaussian_nll(m, raw, torch.tensor([1.0, 2.0])).backward()\n'
                                     'assert m.grad.abs().sum() > 0 and raw.grad.abs().sum() > 0 and '
                                     "torch.isfinite(raw.grad).all(), 'Contract failed: both outputs "
                                     "receive finite autograd derivatives.'\n"},
                            {'name': 'extreme negative raw variance remains finite',
                             'code': 'm = torch.zeros(1, requires_grad=True)\n'
                                     'raw = torch.tensor([-1000.0], requires_grad=True)\n'
                                     'r = gaussian_nll(m, raw, torch.ones(1))\n'
                                     'r.backward()\n'
                                     'assert torch.isfinite(r) and torch.isfinite(m.grad).all() and '
                                     "torch.isfinite(raw.grad).all(), 'Contract failed: extreme "
                                     "negative raw variance remains finite.'\n"},
                            {'name': 'joint translation does not change likelihood',
                             'code': 'm = torch.tensor([1.0, 2.0])\n'
                                     'y = torch.tensor([0.0, 4.0])\n'
                                     'v = torch.tensor([-0.2, 0.8])\n'
                                     'assert torch.allclose(gaussian_nll(m, v, y), gaussian_nll(m + 20, '
                                     "v, y + 20)), 'Contract failed: joint translation does not change "
                                     "likelihood.'\n"},
                            {'name': 'invalid shape and floor fail',
                             'code': 'try:\n'
                                     '    gaussian_nll(torch.zeros(2), torch.zeros(1), torch.zeros(2))\n'
                                     'except ValueError:\n'
                                     '    pass\n'
                                     'else:\n'
                                     "    assert False, 'Reject invalid input before changing state.'\n"
                                     'try:\n'
                                     '    gaussian_nll(torch.zeros(1), torch.zeros(1), torch.zeros(1), '
                                     '0)\n'
                                     'except ValueError:\n'
                                     '    pass\n'
                                     'else:\n'
                                     "    assert False, 'Reject invalid input before changing "
                                     "state.'\n"}],
                 'project': False},
 'torchqat': {'entry': 'fake_quant_weight',
              'fixture': 'w=torch.tensor([[.1,.8],[-2.,1.]],requires_grad=True)\n'
                         'result=fake_quant_weight(w,4)\n'
                         'result.sum().backward()\n',
              'checks': [{'name': 'per-channel grids match an independent quantizer',
                          'code': 'w = torch.tensor([[0.1, 0.8], [-2.0, 1.0]])\n'
                                  's = w.abs().amax(1) / 7\n'
                                  'expected = (w / s[:, None]).round().clamp(-7, 7) * s[:, None]\n'
                                  "assert torch.allclose(fake_quant_weight(w, 4), expected), 'Contract "
                                  "failed: per-channel grids match an independent quantizer.'\n"},
                         {'name': 'surrogate gradients stop outside explicit clipping limits',
                          'code': 'w = torch.tensor([[-2.0, -0.2, 0.25, 2.0]], requires_grad=True)\n'
                                  's = torch.tensor([0.1], requires_grad=True)\n'
                                  'fake_quant_weight(w, 3, s).sum().backward()\n'
                                  'assert torch.equal(w.grad, torch.tensor([[0.0, 1.0, 1.0, 0.0]])) and '
                                  "s.grad is None, 'Contract failed: surrogate gradients stop outside "
                                  "explicit clipping limits.'\n"},
                         {'name': 'rounding uses ties to even',
                          'code': 'w = torch.tensor([[0.5, 1.5, 2.5, -0.5]])\n'
                                  'assert torch.equal(fake_quant_weight(w, 4, torch.ones(1)), '
                                  "torch.tensor([[0.0, 2.0, 2.0, 0.0]])), 'Contract failed: rounding "
                                  "uses ties to even.'\n"},
                         {'name': 'zero rows and channel rescaling remain finite',
                          'code': 'w = torch.tensor([[0.0, 0.0], [0.2, 0.9]])\n'
                                  'r = fake_quant_weight(w, 4)\n'
                                  'assert torch.isfinite(r).all() and torch.equal(r[0], '
                                  "torch.zeros(2)), 'Contract failed: zero rows and channel rescaling "
                                  "remain finite.'\n"
                                  'assert torch.allclose(fake_quant_weight(w * 5, 4), r * 5, '
                                  "atol=1e-06), 'Contract failed: zero rows and channel rescaling "
                                  "remain finite.'\n"},
                         {'name': 'invalid precision and scale fail',
                          'code': 'try:\n'
                                  '    fake_quant_weight(torch.ones(2, 2), 1)\n'
                                  'except ValueError:\n'
                                  '    pass\n'
                                  'else:\n'
                                  "    assert False, 'Reject invalid input before changing state.'\n"
                                  'try:\n'
                                  '    fake_quant_weight(torch.ones(2, 2), 4, torch.tensor([0.0, '
                                  '1.0]))\n'
                                  'except ValueError:\n'
                                  '    pass\n'
                                  'else:\n'
                                  "    assert False, 'Reject invalid input before changing state.'\n"}],
              'project': False},
 'torchdpo': {'entry': 'dpo_loss',
              'fixture': 'p=torch.zeros(1,2,2,3,requires_grad=True)\n'
                         'r=torch.zeros_like(p,requires_grad=True)\n'
                         'y=torch.tensor([[[1,2],[0,-100]]])\n'
                         'result=dpo_loss(p,r,y,.5)\n'
                         'result.backward()\n',
              'checks': [{'name': 'equal policy and reference yield log two',
                          'code': 'import math\n'
                                  'p = torch.randn(2, 2, 3, 4, dtype=torch.float64)\n'
                                  'y = torch.tensor([[[1, 2, -100], [0, 1, 2]], [[0, 1, 2], [2, -100, '
                                  '-100]]])\n'
                                  'assert abs(dpo_loss(p, p.clone(), y, 0.7).item() - math.log(2)) < '
                                  "1e-12, 'Contract failed: equal policy and reference yield log "
                                  "two.'\n"},
                         {'name': 'independent summed-token margin matches the objective',
                          'code': 'from torch.nn import functional as F\n'
                                  'p = torch.tensor([[[[1.0, 0.0], [0.0, 2.0]], [[0.0, 1.0], [2.0, '
                                  '0.0]]]], dtype=torch.float64)\n'
                                  'r = torch.zeros_like(p)\n'
                                  'y = torch.tensor([[[0, 1], [0, -100]]])\n'
                                  'ps = p.log_softmax(-1)\n'
                                  'rs = r.log_softmax(-1)\n'
                                  'm = ps[0, 0, 0, 0] + ps[0, 0, 1, 1] - ps[0, 1, 0, 0] - (rs[0, 0, 0, '
                                  '0] + rs[0, 0, 1, 1] - rs[0, 1, 0, 0])\n'
                                  'assert torch.allclose(dpo_loss(p, r, y, 0.3), F.softplus(-0.3 * m)), '
                                  "'Contract failed: independent summed-token margin matches the "
                                  "objective.'\n"},
                         {'name': 'reference and masked token positions receive no gradients',
                          'code': 'p = torch.zeros(1, 2, 2, 3, requires_grad=True)\n'
                                  'r = torch.zeros_like(p, requires_grad=True)\n'
                                  'y = torch.tensor([[[1, -100], [2, -100]]])\n'
                                  'dpo_loss(p, r, y, 0.5).backward()\n'
                                  'assert p.grad[:, :, 0].abs().sum() > 0 and p.grad[:, :, '
                                  "1].abs().sum() == 0 and (r.grad is None), 'Contract failed: "
                                  "reference and masked token positions receive no gradients.'\n"},
                         {'name': 'better chosen probability lowers the preference objective',
                          'code': 'p = torch.zeros(1, 2, 1, 2)\n'
                                  'r = p.clone()\n'
                                  'y = torch.tensor([[[0], [1]]])\n'
                                  'a = dpo_loss(p, r, y, 1.0)\n'
                                  'p[0, 0, 0, 0] = 8\n'
                                  'assert dpo_loss(p, r, y, 1.0) < a and torch.isfinite(dpo_loss(p * '
                                  "1000, r, y, 1.0)), 'Contract failed: better chosen probability "
                                  "lowers the preference objective.'\n"},
                         {'name': 'empty responses and invalid beta fail',
                          'code': 'try:\n'
                                  '    dpo_loss(torch.zeros(1, 2, 1, 2), torch.zeros(1, 2, 1, 2), '
                                  'torch.full((1, 2, 1), -100), 1)\n'
                                  'except ValueError:\n'
                                  '    pass\n'
                                  'else:\n'
                                  "    assert False, 'Reject invalid input before changing state.'\n"
                                  'try:\n'
                                  '    dpo_loss(torch.zeros(1, 2, 1, 2), torch.zeros(1, 2, 1, 2), '
                                  'torch.zeros(1, 2, 1, dtype=torch.long), 0)\n'
                                  'except ValueError:\n'
                                  '    pass\n'
                                  'else:\n'
                                  "    assert False, 'Reject invalid input before changing state.'\n"}],
              'project': False},
 'torchgrpo': {'entry': 'group_policy_loss',
               'fixture': 'p=torch.zeros(1,2,2,requires_grad=True)\n'
                          'result=group_policy_loss(p,torch.zeros_like(p),torch.tensor([[0.,2.]]),torch.ones_like(p,dtype=torch.bool))\n'
                          'result.backward()\n',
               'checks': [{'name': 'independent clipped two-response surrogate',
                           'code': 'import math\n'
                                   'p = torch.tensor([[[math.log(1.1)], [math.log(0.9)]]], '
                                   'dtype=torch.float64)\n'
                                   'r = group_policy_loss(p, torch.zeros_like(p), torch.tensor([[2.0, '
                                   '0.0]], dtype=p.dtype), torch.ones_like(p, dtype=torch.bool))\n'
                                   "assert abs(r.item() + 0.1) < 1e-07, 'Contract failed: independent "
                                   "clipped two-response surrogate.'\n"},
                          {'name': 'clipped good and bad responses have zero incentive',
                           'code': 'import math\n'
                                   'p = torch.tensor([[[math.log(2.0)], [math.log(0.5)]]], '
                                   'requires_grad=True)\n'
                                   'r = group_policy_loss(p, torch.zeros_like(p), torch.tensor([[2.0, '
                                   '0.0]]), torch.ones_like(p, dtype=torch.bool))\n'
                                   'r.backward()\n'
                                   "assert torch.equal(p.grad, torch.zeros_like(p)), 'Contract failed: "
                                   "clipped good and bad responses have zero incentive.'\n"},
                          {'name': 'only new valid-token probabilities receive gradients',
                           'code': 'p = torch.zeros(1, 2, 2, requires_grad=True)\n'
                                   'old = torch.zeros_like(p, requires_grad=True)\n'
                                   'rewards = torch.tensor([[0.0, 2.0]], requires_grad=True)\n'
                                   'mask = torch.tensor([[[True, False], [True, False]]])\n'
                                   'group_policy_loss(p, old, rewards, mask).backward()\n'
                                   'assert p.grad[:, :, 0].abs().sum() > 0 and p.grad[:, :, '
                                   '1].abs().sum() == 0 and (old.grad is None) and (rewards.grad is '
                                   "None), 'Contract failed: only new valid-token probabilities receive "
                                   "gradients.'\n"},
                          {'name': 'constant groups produce graph-connected zero',
                           'code': 'p = torch.randn(2, 3, 2, requires_grad=True)\n'
                                   'mask = torch.ones_like(p, dtype=torch.bool)\n'
                                   'r = group_policy_loss(p, p.detach(), torch.ones(2, 3), mask)\n'
                                   'r.backward()\n'
                                   'assert r.item() == 0 and torch.equal(p.grad, torch.zeros_like(p)), '
                                   "'Contract failed: constant groups produce graph-connected zero.'\n"},
                          {'name': 'empty response and invalid clip fail',
                           'code': 'try:\n'
                                   '    group_policy_loss(torch.zeros(1, 2, 1), torch.zeros(1, 2, 1), '
                                   'torch.zeros(1, 2), torch.zeros(1, 2, 1, dtype=torch.bool))\n'
                                   'except ValueError:\n'
                                   '    pass\n'
                                   'else:\n'
                                   "    assert False, 'Reject invalid input before changing state.'\n"
                                   'try:\n'
                                   '    group_policy_loss(torch.zeros(1, 2, 1), torch.zeros(1, 2, 1), '
                                   'torch.zeros(1, 2), torch.ones(1, 2, 1, dtype=torch.bool), 1)\n'
                                   'except ValueError:\n'
                                   '    pass\n'
                                   'else:\n'
                                   "    assert False, 'Reject invalid input before changing state.'\n"}],
               'project': False},
 'torchsupcon': {'entry': 'supervised_contrastive',
                 'fixture': 'x=torch.tensor([[1.,.1],[1.,.2],[.1,1.],[.2,1.]],requires_grad=True)\n'
                            'result=supervised_contrastive(x,torch.tensor([0,0,1,1]),.3)\n'
                            'result.backward()\n',
                 'checks': [{'name': 'independent categorical sum over all positives',
                             'code': 'import math\n'
                                     'x = torch.tensor([[1.0, 0.0], [0.9, 0.1], [0.0, 1.0], [1.0, '
                                     '1.0]], dtype=torch.float64)\n'
                                     'y = torch.tensor([0, 0, 1, 0])\n'
                                     'z = x / x.norm(dim=1, keepdim=True)\n'
                                     'scores = z @ z.T / 0.4\n'
                                     'values = []\n'
                                     'for i in range(4):\n'
                                     '    positive = [j for j in range(4) if j != i and y[j] == y[i]]\n'
                                     '    if positive:\n'
                                     '        den = sum((math.exp(scores[i, j].item()) for j in '
                                     'range(4) if j != i))\n'
                                     '        values.append(sum((math.log(den) - scores[i, j].item() '
                                     'for j in positive)) / len(positive))\n'
                                     'assert abs(supervised_contrastive(x, y, 0.4).item() - sum(values) '
                                     "/ len(values)) < 1e-10, 'Contract failed: independent categorical "
                                     "sum over all positives.'\n"},
                            {'name': 'singleton remains a negative and receives gradients',
                             'code': 'x = torch.tensor([[1.0, 0.2], [0.8, 0.3], [0.1, 1.0]], '
                                     'requires_grad=True)\n'
                                     'r = supervised_contrastive(x, torch.tensor([0, 0, 1]), 0.5)\n'
                                     'r.backward()\n'
                                     'assert torch.isfinite(x.grad).all() and x.grad[2].abs().sum() > '
                                     "0, 'Contract failed: singleton remains a negative and receives "
                                     "gradients.'\n"},
                            {'name': 'joint permutations and positive scaling preserve loss',
                             'code': 'x = torch.tensor([[1.0, 0.2], [0.8, 0.3], [0.1, 1.0], [0.2, '
                                     '0.9]])\n'
                                     'y = torch.tensor([0, 0, 1, 1])\n'
                                     'p = torch.tensor([2, 0, 3, 1])\n'
                                     'assert torch.allclose(supervised_contrastive(x, y, 0.4), '
                                     'supervised_contrastive(x[p] * 3, y[p], 0.4), atol=1e-06), '
                                     "'Contract failed: joint permutations and positive scaling "
                                     "preserve loss.'\n"},
                            {'name': 'aligned clusters beat mixed identities',
                             'code': 'x = torch.tensor([[1.0, 0.01], [1.0, -0.01], [0.01, 1.0], [-0.01, '
                                     '1.0]])\n'
                                     'assert supervised_contrastive(x, torch.tensor([0, 0, 1, 1]), 0.2) '
                                     '< supervised_contrastive(x, torch.tensor([0, 1, 0, 1]), 0.2), '
                                     "'Contract failed: aligned clusters beat mixed identities.'\n"},
                            {'name': 'missing positives and zero vectors fail',
                             'code': 'try:\n'
                                     '    supervised_contrastive(torch.eye(2), torch.tensor([0, 1]))\n'
                                     'except ValueError:\n'
                                     '    pass\n'
                                     'else:\n'
                                     "    assert False, 'Reject invalid input before changing state.'\n"
                                     'try:\n'
                                     '    supervised_contrastive(torch.zeros(2, 2), torch.tensor([0, '
                                     '0]))\n'
                                     'except ValueError:\n'
                                     '    pass\n'
                                     'else:\n'
                                     "    assert False, 'Reject invalid input before changing "
                                     "state.'\n"}],
                 'project': False},
 'torchmoe': {'entry': 'sparse_mixture',
              'fixture': 'router=torch.nn.Linear(2,3)\n'
                         'experts=torch.nn.ModuleList([torch.nn.Linear(2,2) for _ in range(3)])\n'
                         'x=torch.tensor([[1.,0.],[0.,1.],[1.,1.]],requires_grad=True)\n'
                         'output,aux,loads,dropped=sparse_mixture(x,router,experts,2)\n'
                         'result=output.square().mean()+.1*aux\n'
                         'result.backward()\n',
              'checks': [{'name': 'stable ties capacity and zero-output overflow',
                          'code': 'router = torch.nn.Linear(1, 3, bias=False)\n'
                                  'experts = torch.nn.ModuleList([torch.nn.Linear(1, 1, bias=False) for '
                                  '_ in range(3)])\n'
                                  'with torch.no_grad():\n'
                                  '    router.weight.zero_()\n'
                                  '    for i, e in enumerate(experts):\n'
                                  '        e.weight.fill_(i + 1)\n'
                                  'y, a, loads, dropped = sparse_mixture(torch.ones(3, 1), router, '
                                  'experts, 1)\n'
                                  'assert loads == [1, 1, 0] and dropped == 4 and torch.allclose(y, '
                                  'torch.tensor([[1.5], [0.0], [0.0]])) and (abs(a.item() - 1) < '
                                  "1e-06), 'Contract failed: stable ties capacity and zero-output "
                                  "overflow.'\n"},
                         {'name': 'accepted experts and gate probabilities receive gradients',
                          'code': 'torch.manual_seed(3)\n'
                                  'r = torch.nn.Linear(2, 3)\n'
                                  'es = torch.nn.ModuleList([torch.nn.Linear(2, 1) for _ in range(3)])\n'
                                  'x = torch.randn(5, 2, requires_grad=True)\n'
                                  'y, a, loads, d = sparse_mixture(x, r, es, 10)\n'
                                  '(y.square().mean() + 0.1 * a).backward()\n'
                                  'assert r.weight.grad.abs().sum() > 0 and x.grad.abs().sum() > 0, '
                                  "'Contract failed: accepted experts and gate probabilities receive "
                                  "gradients.'\n"
                                  'assert all((e.weight.grad is None or '
                                  'torch.isfinite(e.weight.grad).all() for e in es)) and sum(loads) == '
                                  "10 and (d == 0), 'Contract failed: accepted experts and gate "
                                  "probabilities receive gradients.'\n"},
                         {'name': 'unselected expert is never executed',
                          'code': 'class Forbidden(torch.nn.Linear):\n'
                                  '\n'
                                  '    def forward(self, x):\n'
                                  "        raise AssertionError('Unselected expert executed.')\n"
                                  'r = torch.nn.Linear(1, 3, bias=False)\n'
                                  'with torch.no_grad():\n'
                                  '    r.weight.copy_(torch.tensor([[3.0], [2.0], [-10.0]]))\n'
                                  'es = torch.nn.ModuleList([torch.nn.Linear(1, 1), torch.nn.Linear(1, '
                                  '1), Forbidden(1, 1)])\n'
                                  'y, a, loads, d = sparse_mixture(torch.ones(2, 1), r, es, 3)\n'
                                  "assert loads == [2, 2, 0] and torch.isfinite(y).all(), 'Contract "
                                  "failed: unselected expert is never executed.'\n"},
                         {'name': 'renormalized retained gate owns a partially overflowed token',
                          'code': 'r = torch.nn.Linear(1, 3, bias=False)\n'
                                  'es = torch.nn.ModuleList([torch.nn.Linear(1, 1, bias=False) for _ in '
                                  'range(3)])\n'
                                  'with torch.no_grad():\n'
                                  '    r.weight.copy_(torch.tensor([[2.0], [1.0], [-2.0]]))\n'
                                  '    for i, e in enumerate(es):\n'
                                  '        e.weight.fill_(i + 1)\n'
                                  'y, a, loads, d = sparse_mixture(torch.tensor([[1.0], [-1.0]]), r, '
                                  'es, 1)\n'
                                  'assert loads == [1, 1, 1] and d == 1 and (abs(y[1].item() + 3) < '
                                  "1e-06), 'Contract failed: renormalized retained gate owns a "
                                  "partially overflowed token.'\n"},
                         {'name': 'bad capacity and mismatched expert widths fail',
                          'code': 'try:\n'
                                  '    sparse_mixture(torch.ones(1, 1), torch.nn.Linear(1, 2), '
                                  'torch.nn.ModuleList([torch.nn.Linear(1, 1), torch.nn.Linear(1, 1)]), '
                                  '0)\n'
                                  'except ValueError:\n'
                                  '    pass\n'
                                  'else:\n'
                                  "    assert False, 'Reject invalid input before changing state.'\n"
                                  'try:\n'
                                  '    sparse_mixture(torch.ones(1, 1), torch.nn.Linear(1, 2), '
                                  'torch.nn.ModuleList([torch.nn.Linear(1, 1), torch.nn.Linear(1, 2)]), '
                                  '2)\n'
                                  'except ValueError:\n'
                                  '    pass\n'
                                  'else:\n'
                                  "    assert False, 'Reject invalid input before changing state.'\n"}],
              'project': False},
 'torchspeculative': {'entry': 'speculative_token',
                      'fixture': 'result=speculative_token(torch.tensor([.2,.8]),torch.tensor([.8,.2]),0,.6,.4)\n',
                      'checks': [{'name': 'rejection samples the residual rather than the draft',
                                  'code': 'p = torch.tensor([0.2, 0.8])\n'
                                          'q = torch.tensor([0.8, 0.2])\n'
                                          'assert speculative_token(p, q, 0, 0.6, 0.4) == (1, False), '
                                          "'Contract failed: rejection samples the residual rather than "
                                          "the draft.'\n"
                                          'assert speculative_token(p, q, 0, 0.1, 0.4) == (0, True), '
                                          "'Contract failed: rejection samples the residual rather than "
                                          "the draft.'\n"},
                                 {'name': 'equal distributions always accept valid proposals',
                                  'code': 'p = torch.tensor([0.0, 0.3, 0.7])\n'
                                          'assert speculative_token(p, p, 1, 0.999, 0.1) == (1, True) '
                                          'and speculative_token(p, p, 2, 0.0, 0.9) == (2, True), '
                                          "'Contract failed: equal distributions always accept valid "
                                          "proposals.'\n"},
                                 {'name': 'residual CDF uses declared right-open boundaries',
                                  'code': 'p = torch.tensor([0.0, 0.5, 0.5], dtype=torch.float64)\n'
                                          'q = torch.tensor([1.0, 0.0, 0.0], dtype=p.dtype)\n'
                                          'assert speculative_token(p, q, 0, 0.1, 0.499) == (1, False), '
                                          "'Contract failed: residual CDF uses declared right-open "
                                          "boundaries.'\n"
                                          'assert speculative_token(p, q, 0, 0.1, 0.5) == (2, False), '
                                          "'Contract failed: residual CDF uses declared right-open "
                                          "boundaries.'\n"},
                                 {'name': 'stratified draft and acceptance mass recover target exactly',
                                  'code': 'p = torch.tensor([0.2, 0.8], dtype=torch.float64)\n'
                                          'q = torch.tensor([0.8, 0.2], dtype=p.dtype)\n'
                                          'counts = [0, 0]\n'
                                          'for i in range(100):\n'
                                          '    proposal = 0 if (i + 0.5) / 100 < 0.8 else 1\n'
                                          '    for j in range(100):\n'
                                          '        token, accepted = speculative_token(p, q, proposal, '
                                          '(j + 0.5) / 100, 0.37)\n'
                                          '        counts[token] += 1\n'
                                          "assert counts == [2000, 8000], 'Contract failed: stratified "
                                          "draft and acceptance mass recover target exactly.'\n"},
                                 {'name': 'bad support and uniform values fail',
                                  'code': 'try:\n'
                                          '    speculative_token(torch.tensor([0.2, 0.8]), '
                                          'torch.tensor([0.0, 1.0]), 0, 0.1, 0.1)\n'
                                          'except ValueError:\n'
                                          '    pass\n'
                                          'else:\n'
                                          "    assert False, 'Reject invalid input before changing "
                                          "state.'\n"
                                          'try:\n'
                                          '    speculative_token(torch.tensor([0.2, 0.8]), '
                                          'torch.tensor([0.8, 0.2]), 0, 1.0, 0.1)\n'
                                          'except ValueError:\n'
                                          '    pass\n'
                                          'else:\n'
                                          "    assert False, 'Reject invalid input before changing "
                                          "state.'\n"}],
                      'project': False},
 'torchgrammar': {'entry': 'constrained_beam',
                  'fixture': 'result=constrained_beam(torch.tensor([[2.,1.,-2.],[0.,1.,2.]]),{0:{0:1,1:1},1:{}},0,{1},2,4)\n',
                  'checks': [{'name': 'wide beam matches exhaustive allowed complete sequences',
                              'code': 'import itertools\n'
                                      'x = torch.tensor([[2.0, 1.0, -2.0], [1.0, 2.0, -1.0], [0.0, 0.0, '
                                      '3.0]], dtype=torch.float64)\n'
                                      'tr = {0: {0: 1, 1: 1}, 1: {0: 1, 1: 1}}\n'
                                      'scores = x.log_softmax(-1)\n'
                                      'candidates = []\n'
                                      'for length in (2, 3):\n'
                                      '    for prefix in itertools.product((0, 1), repeat=length - 1):\n'
                                      '        tokens = prefix + (2,)\n'
                                      '        score = sum((scores[i, t].item() for i, t in '
                                      'enumerate(tokens)))\n'
                                      '        candidates.append((tokens, score))\n'
                                      'best = sorted(candidates, key=lambda p: (-p[1], p[0]))[0]\n'
                                      'r = constrained_beam(x, tr, 0, {1}, 2, 20)\n'
                                      "assert tuple(r['tokens']) == best[0] and abs(r['score'] - "
                                      "best[1]) < 1e-12, 'Contract failed: wide beam matches exhaustive "
                                      "allowed complete sequences.'\n"},
                             {'name': 'EOS cannot terminate a nonaccepting prefix',
                              'code': 'x = torch.tensor([[0.0, 0.0, 10.0], [0.0, 0.0, 10.0]])\n'
                                      'r = constrained_beam(x, {0: {0: 1}, 1: {}}, 0, {1}, 2, 4)\n'
                                      "assert r['tokens'] == [0, 2], 'Contract failed: EOS cannot "
                                      "terminate a nonaccepting prefix.'\n"},
                             {'name': 'finished paths retain their score and deterministic ties',
                              'code': 'x = torch.zeros(3, 3)\n'
                                      'r = constrained_beam(x, {0: {0: 1, 1: 1}, 1: {0: 1, 1: 1}}, 0, '
                                      '{1}, 2, 8)\n'
                                      "assert r['tokens'] == [0, 2] and abs(r['score'] - 2 * "
                                      "x.log_softmax(-1)[0, 0].item()) < 1e-06, 'Contract failed: "
                                      "finished paths retain their score and deterministic ties.'\n"},
                             {'name': 'original full-vocabulary likelihood is retained',
                              'code': 'x = torch.tensor([[0.0, 9.0, 0.0], [0.0, 0.0, 9.0]], '
                                      'dtype=torch.float64)\n'
                                      'r = constrained_beam(x, {0: {0: 1}, 1: {}}, 0, {1}, 2, 4)\n'
                                      'expected = x.log_softmax(-1)[0, 0] + x.log_softmax(-1)[1, 2]\n'
                                      "assert abs(r['score'] - expected.item()) < 1e-12 and r['score'] "
                                      "< -8, 'Contract failed: original full-vocabulary likelihood is "
                                      "retained.'\n"},
                             {'name': 'invalid width and impossible termination fail',
                              'code': 'try:\n'
                                      '    constrained_beam(torch.zeros(2, 3), {0: {0: 0}}, 0, set(), '
                                      '2, 4)\n'
                                      'except ValueError:\n'
                                      '    pass\n'
                                      'else:\n'
                                      "    assert False, 'Reject invalid input before changing state.'\n"
                                      'try:\n'
                                      '    constrained_beam(torch.zeros(2, 3), {0: {}}, 0, {0}, 2, 0)\n'
                                      'except ValueError:\n'
                                      '    pass\n'
                                      'else:\n'
                                      "    assert False, 'Reject invalid input before changing "
                                      "state.'\n"}],
                  'project': False},
 'torchrobustproject': {'entry': 'run_experiment',
                        'fixture': 'result=run_experiment(seed=7,steps=8)\n',
                        'checks': [{'name': 'actual optimization changes both models and reports group '
                                            'evidence',
                                    'code': 'r = run_experiment(7, 50)\n'
                                            "a = read_payload(r['artifact'])\n"
                                            "assert all((any((not torch.equal(v, a['initial'][k]) for "
                                            "k, v in s.items())) for s in a['states'].values())), "
                                            "'Contract failed: actual optimization changes both models "
                                            "and reports group evidence.'\n"
                                            "for m in r['models'].values():\n"
                                            "    assert len(m['test']['groups']) == 4 and "
                                            "m['test']['worst_group'] == min(m['test']['groups']) and "
                                            "(len(m['history']) >= 3) and (1 <= m['best_step'] <= 50), "
                                            "'Contract failed: actual optimization changes both models "
                                            "and reports group evidence.'\n"
                                            '\n'
                                            "counts=[sum(r['group']==i for r in "
                                            "make_data(7)['train'])/len(make_data(7)['train']) for i in "
                                            'range(4)]\n'
                                            'assert all(abs(x-y)<1e-7 for x,y in '
                                            "zip(r['models']['erm']['group_weights'],counts)), 'ERM "
                                            "group mass must reflect sample frequency.'\n"
                                            'assert '
                                            "abs(sum(r['models']['dro']['group_weights'])-1)<1e-6, 'DRO "
                                            "checkpoint probabilities must normalize.'\n"
                                            "assert a['group_weights']=={k:v['group_weights'] for k,v "
                                            "in r['models'].items()} and "
                                            "a['selected_steps']=={k:v['best_step'] for k,v in "
                                            "r['models'].items()}, 'Serialized group evidence must "
                                            "belong to the selected checkpoint.'\n"},
                                   {'name': 'test labels cannot select or fit either artifact',
                                    'code': 'data = make_data(9)\n'
                                            "poison = copy.deepcopy(data['test'])\n"
                                            'for row in poison:\n'
                                            "    row['y'] = 1 - row['y']\n"
                                            'a = run_experiment(9, 35)\n'
                                            'b = run_experiment(9, 35, poison)\n'
                                            "pa = read_payload(a['artifact'])\n"
                                            "pb = read_payload(b['artifact'])\n"
                                            "assert a['fit_hash'] == b['fit_hash'] and a['data_hash'] "
                                            "!= b['data_hash'], 'Contract failed: test labels cannot "
                                            "select or fit either artifact.'\n"
                                            "assert all((torch.equal(v, pb['states'][m][k]) for m, s in "
                                            "pa['states'].items() for k, v in s.items())), 'Contract "
                                            'failed: test labels cannot select or fit either '
                                            "artifact.'\n"},
                                   {'name': 'serialized artifact independently reproduces test '
                                            'predictions',
                                    'code': 'r = run_experiment(11, 40)\n'
                                            "saved = read_payload(r['artifact'])\n"
                                            'm = torch.nn.Linear(2, 2)\n'
                                            "m.load_state_dict(saved['states']['dro'])\n"
                                            "metrics = classification(m, make_data(11)['test'])\n"
                                            "assert metrics == r['models']['dro']['test'] and "
                                            "r['reload_equal'] and (r['artifact_bytes'] == "
                                            "len(r['artifact']) > 1000), 'Contract failed: serialized "
                                            "artifact independently reproduces test predictions.'\n"},
                                   {'name': 'all partitions are disjoint and repeatable across a seed',
                                    'code': 'a = run_experiment(3, 25)\n'
                                            'b = run_experiment(3, 25)\n'
                                            "sets = [set(x) for x in a['ids'].values()]\n"
                                            'assert all((not left & right for i, left in '
                                            "enumerate(sets) for right in sets[i + 1:])), 'Contract "
                                            'failed: all partitions are disjoint and repeatable across '
                                            "a seed.'\n"
                                            "assert a['models'] == b['models'] and a['data_hash'] == "
                                            "b['data_hash'], 'Contract failed: all partitions are "
                                            "disjoint and repeatable across a seed.'\n"},
                                   {'name': 'invalid budgets and evaluation identities fail',
                                    'code': 'try:\n'
                                            '    run_experiment(7, 0)\n'
                                            'except ValueError:\n'
                                            '    pass\n'
                                            'else:\n'
                                            "    assert False, 'Reject invalid input before changing "
                                            "state.'\n"
                                            'try:\n'
                                            '    run_experiment(7, 10, [])\n'
                                            'except ValueError:\n'
                                            '    pass\n'
                                            'else:\n'
                                            "    assert False, 'Reject invalid input before changing "
                                            "state.'\n"}],
                        'project': True},
 'torchuncertaintyproject': {'entry': 'run_experiment',
                             'fixture': 'result=run_experiment(seed=7,steps=8)\n',
                             'checks': [{'name': 'actual likelihood training and calibrated held-out '
                                                 'evidence',
                                         'code': 'r = run_experiment(7, 70)\n'
                                                 "assert r['train_nll'] < r['initial_train_nll'] and 0 "
                                                 "<= r['test']['coverage'] <= 1 and "
                                                 "(r['test']['mean_width'] > 0) and "
                                                 "(len(r['test']['group_coverage']) == 2), 'Contract "
                                                 'failed: actual likelihood training and calibrated '
                                                 "held-out evidence.'\n"
                                                 "assert 1 <= r['best_step'] <= 70 and "
                                                 "len(r['history']) >= 4, 'Contract failed: actual "
                                                 'likelihood training and calibrated held-out '
                                                 "evidence.'\n"},
                                        {'name': 'quantile equals the independent corrected calibration '
                                                 'rank',
                                         'code': 'r = run_experiment(8, 35)\n'
                                                 "saved = read_payload(r['artifact'])\n"
                                                 'm = build_model()\n'
                                                 "m.load_state_dict(saved['state'])\n"
                                                 "rows = make_data(8)['calibration']\n"
                                                 'mean, std = predictions(m, rows)\n'
                                                 '_, y = tensors(rows)\n'
                                                 'values = sorted(((y - mean).abs() / std).tolist())\n'
                                                 'rank = math.ceil((len(values) + 1) * 0.9)\n'
                                                 "assert r['rank'] == rank and abs(r['q'] - values[rank "
                                                 "- 1]) < 1e-06, 'Contract failed: quantile equals the "
                                                 "independent corrected calibration rank.'\n"},
                                        {'name': 'test and calibration labels never fit the model',
                                         'code': 'data = make_data(9)\n'
                                                 "test = copy.deepcopy(data['test'])\n"
                                                 "cal = copy.deepcopy(data['calibration'])\n"
                                                 'for row in test:\n'
                                                 "    row['y'] += 30\n"
                                                 'for row in cal:\n'
                                                 "    row['y'] += 10\n"
                                                 'a = run_experiment(9, 30)\n'
                                                 'b = run_experiment(9, 30, 0.1, test, cal)\n'
                                                 "pa = read_payload(a['artifact'])\n"
                                                 "pb = read_payload(b['artifact'])\n"
                                                 "assert a['fit_hash'] == b['fit_hash'] and "
                                                 "all((torch.equal(v, pb['state'][k]) for k, v in "
                                                 "pa['state'].items())) and (b['q'] > a['q']), "
                                                 "'Contract failed: test and calibration labels never "
                                                 "fit the model.'\n"},
                                        {'name': 'fresh reload and all four partitions preserve '
                                                 'ownership',
                                         'code': 'r = run_experiment(3, 30)\n'
                                                 "a = read_payload(r['artifact'])\n"
                                                 'm = build_model()\n'
                                                 "m.load_state_dict(a['state'])\n"
                                                 "assert interval_metrics(m, make_data(3)['test'], "
                                                 "a['q']) == r['test'] and r['reload_max_error'] == 0 "
                                                 "and (r['artifact_bytes'] > 1000), 'Contract failed: "
                                                 'fresh reload and all four partitions preserve '
                                                 "ownership.'\n"
                                                 "sets = [set(ids) for ids in r['ids'].values()]\n"
                                                 'assert len(sets) == 4 and all((not left & right for '
                                                 'i, left in enumerate(sets) for right in sets[i + '
                                                 "1:])), 'Contract failed: fresh reload and all four "
                                                 "partitions preserve ownership.'\n"},
                                        {'name': 'invalid budgets alpha and calibration rank fail',
                                         'code': 'try:\n'
                                                 '    run_experiment(7, 0)\n'
                                                 'except ValueError:\n'
                                                 '    pass\n'
                                                 'else:\n'
                                                 "    assert False, 'Reject invalid input before "
                                                 "changing state.'\n"
                                                 'try:\n'
                                                 '    run_experiment(7, 10, 0)\n'
                                                 'except ValueError:\n'
                                                 '    pass\n'
                                                 'else:\n'
                                                 "    assert False, 'Reject invalid input before "
                                                 "changing state.'\n"
                                                 'try:\n'
                                                 '    run_experiment(7, 10, 0.0001)\n'
                                                 'except ValueError:\n'
                                                 '    pass\n'
                                                 'else:\n'
                                                 "    assert False, 'Reject invalid input before "
                                                 "changing state.'\n"}],
                             'project': True},
 'torchpreferenceproject': {'entry': 'run_experiment',
                            'fixture': 'result=run_experiment(seed=7,steps=8)\n',
                            'checks': [{'name': 'real preference optimization changes adapters and '
                                                'reduces train loss',
                                        'code': 'r = run_experiment(7, 60)\n'
                                                "a = read_payload(r['artifact'])\n"
                                                "assert r['train']['preference_loss'] < "
                                                "r['initial_train']['preference_loss'] and "
                                                "r['trainable_parameters'] < r['total_parameters'], "
                                                "'Contract failed: real preference optimization changes "
                                                "adapters and reduces train loss.'\n"
                                                "assert not torch.equal(a['state']['adapter_b'], "
                                                "a['initial']['adapter_b']) and len(r['history']) >= 3, "
                                                "'Contract failed: real preference optimization changes "
                                                "adapters and reduces train loss.'\n"},
                                       {'name': 'the reference and every base parameter remain frozen',
                                        'code': 'r = run_experiment(8, 30)\n'
                                                "a = read_payload(r['artifact'])\n"
                                                "assert r['frozen_before'] == r['frozen_after'], "
                                                "'Contract failed: the reference and every base "
                                                "parameter remain frozen.'\n"
                                                "for k, v in a['state'].items():\n"
                                                "    if not k.startswith('adapter_'):\n"
                                                "        assert torch.equal(v, a['reference'][k]) and "
                                                "torch.equal(v, a['initial'][k]), 'Contract failed: the "
                                                "reference and every base parameter remain frozen.'\n"},
                                       {'name': 'test preference reversal cannot alter fitted weights',
                                        'code': 'data = make_data(9)\n'
                                                "poison = copy.deepcopy(data['test'])\n"
                                                'for row in poison:\n'
                                                "    row['chosen'], row['rejected'] = (row['rejected'], "
                                                "row['chosen'])\n"
                                                'a = run_experiment(9, 25)\n'
                                                'b = run_experiment(9, 25, poison)\n'
                                                "pa = read_payload(a['artifact'])\n"
                                                "pb = read_payload(b['artifact'])\n"
                                                "assert a['fit_hash'] == b['fit_hash'] and "
                                                "all((torch.equal(v, pb['state'][k]) for k, v in "
                                                "pa['state'].items())) and (a['test']['win_rate'] != "
                                                "b['test']['win_rate']), 'Contract failed: test "
                                                "preference reversal cannot alter fitted weights.'\n"},
                                       {'name': 'a fresh exported model reproduces held-out logits and '
                                                'metrics',
                                        'code': 'r = run_experiment(3, 30)\n'
                                                "a = read_payload(r['artifact'])\n"
                                                'm = PreferencePolicy()\n'
                                                'ref = PreferencePolicy()\n'
                                                "m.load_state_dict(a['state'])\n"
                                                "ref.load_state_dict(a['reference'])\n"
                                                "assert pair_metrics(m, ref, make_data(3)['test']) == "
                                                "r['test'] and r['reload_max_error'] == 0 and "
                                                "(r['artifact_bytes'] > 1000), 'Contract failed: a "
                                                'fresh exported model reproduces held-out logits and '
                                                "metrics.'\n"
                                                "sets = [set(ids) for ids in r['ids'].values()]\n"
                                                'assert all((not left & right for i, left in '
                                                "enumerate(sets) for right in sets[i + 1:])), 'Contract "
                                                'failed: a fresh exported model reproduces held-out '
                                                "logits and metrics.'\n"},
                                       {'name': 'invalid training budget and evaluation identities fail',
                                        'code': 'try:\n'
                                                '    run_experiment(7, 0)\n'
                                                'except ValueError:\n'
                                                '    pass\n'
                                                'else:\n'
                                                "    assert False, 'Reject invalid input before "
                                                "changing state.'\n"
                                                'try:\n'
                                                '    run_experiment(7, 10, [])\n'
                                                'except ValueError:\n'
                                                '    pass\n'
                                                'else:\n'
                                                "    assert False, 'Reject invalid input before "
                                                "changing state.'\n"}],
                            'project': True},
 'torchmoeproject': {'entry': 'run_experiment',
                     'fixture': 'result=run_experiment(seed=7,steps=4)\n',
                     'checks': [{'name': 'actual router and expert training reduce the local objective',
                                 'code': 'r = run_experiment(7, 60)\n'
                                         "a = read_payload(r['artifact'])\n"
                                         "assert r['train']['loss'] < r['initial_train']['loss'] and "
                                         "(not torch.equal(a['state']['router.weight'], "
                                         "a['initial']['router.weight'])), 'Contract failed: actual "
                                         "router and expert training reduce the local objective.'\n"
                                         "assert any((not torch.equal(v, a['initial'][k]) for k, v in "
                                         "a['state'].items() if k.startswith('experts.'))) and "
                                         "len(r['history']) >= 3, 'Contract failed: actual router and "
                                         "expert training reduce the local objective.'\n"},
                                {'name': 'capacity stress conserves every requested assignment',
                                 'code': 'r = run_experiment(8, 25)\n'
                                         "m = r['capacity_stress']\n"
                                         "n = len(r['ids']['test'])\n"
                                         "assert sum(m['accepted_loads']) + m['dropped_assignments'] == "
                                         "2 * n and all((v <= r['stress_capacity'] for v in "
                                         "m['accepted_loads'])) and (m['dropped_assignments'] > 0), "
                                         "'Contract failed: capacity stress conserves every requested "
                                         "assignment.'\n"
                                         "assert r['test']['dropped_assignments'] == 0 and "
                                         "sum(r['test']['accepted_loads']) == 2 * n, 'Contract failed: "
                                         "capacity stress conserves every requested assignment.'\n"},
                                {'name': 'test labels cannot select or fit router or experts',
                                 'code': 'data = make_data(9)\n'
                                         "poison = copy.deepcopy(data['test'])\n"
                                         'for row in poison:\n'
                                         "    row['y'] = 1 - row['y']\n"
                                         'a = run_experiment(9, 20)\n'
                                         'b = run_experiment(9, 20, poison)\n'
                                         "pa = read_payload(a['artifact'])\n"
                                         "pb = read_payload(b['artifact'])\n"
                                         "assert a['fit_hash'] == b['fit_hash'] and all((torch.equal(v, "
                                         "pb['state'][k]) for k, v in pa['state'].items())), 'Contract "
                                         'failed: test labels cannot select or fit router or '
                                         "experts.'\n"},
                                {'name': 'fresh reload and independent partitions reproduce evidence',
                                 'code': 'r = run_experiment(3, 25)\n'
                                         "a = read_payload(r['artifact'])\n"
                                         'm = SparseClassifier()\n'
                                         "m.load_state_dict(a['state'])\n"
                                         "assert metrics(m, make_data(3)['test']) == r['test'] and "
                                         "r['reload_max_error'] == 0 and (r['artifact_bytes'] > 1000), "
                                         "'Contract failed: fresh reload and independent partitions "
                                         "reproduce evidence.'\n"
                                         "sets = [set(ids) for ids in r['ids'].values()]\n"
                                         'assert all((not left & right for i, left in enumerate(sets) '
                                         "for right in sets[i + 1:])), 'Contract failed: fresh reload "
                                         "and independent partitions reproduce evidence.'\n"},
                                {'name': 'invalid budgets and evaluation identities fail',
                                 'code': 'try:\n'
                                         '    run_experiment(7, 0)\n'
                                         'except ValueError:\n'
                                         '    pass\n'
                                         'else:\n'
                                         "    assert False, 'Reject invalid input before changing "
                                         "state.'\n"
                                         'try:\n'
                                         '    run_experiment(7, 10, [])\n'
                                         'except ValueError:\n'
                                         '    pass\n'
                                         'else:\n'
                                         "    assert False, 'Reject invalid input before changing "
                                         "state.'\n"}],
                     'project': True}}

import math
from .labs_engine import register, plot
from .labs_torch import _draw as tensor_draw

def _draw(view,spec):
    if not spec['project']:
        return tensor_draw(view,spec['entry'])
    if view.function in ('train_model','train_policy'):
        if not view.text.startswith('history.append('):return None
    elif view.function!=spec['entry']:return None
    keep=('step','steps','seed','best_step','loss','valid_loss','best_score','frozen_before','frozen_after','fit_hash','reload_error','history','q','rank','alpha','stress_capacity')
    original=view.locals
    view.locals={k:v for k,v in original.items() if k in keep and k!='history'}
    report=original.get('report')
    if isinstance(report,dict):
        evidence={k:report[k] for k in ('artifact_bytes','best_step','reload_max_error','reload_equal','q','rank','alpha','trainable_parameters','total_parameters','initial_train_nll','train_nll','validation_nll') if k in report}
        for split in ('train','validation','test'):
            metrics=report.get(split,{})
            if isinstance(metrics,dict):
                for key,value in metrics.items():
                    if isinstance(value,(int,float)) and key!='auxiliary':evidence[split+' '+key]=value
                    if isinstance(value,list) and split=='test':view.locals['held-out '+key]=value
        for method,model in report.get('models',{}).items():
            for key in ('accuracy','worst_group'):
                if key in model.get('test',{}):evidence[method+' test '+key]=model['test'][key]
        view.locals['evaluation']=dict(list(evidence.items())[:24])
        if view.event=='return':view.value=view.locals['evaluation']
    drawn=tensor_draw(view,view.function)
    history=original.get('history')
    if drawn and isinstance(history,list):
        points=[(r['step'],r['loss']) for r in history if isinstance(r,dict) and all(isinstance(r.get(k),(int,float)) and math.isfinite(r[k]) for k in ('step','loss'))]
        if points:drawn[0].insert(0,plot([('training loss',points)],title='Actual optimizer steps'))
    return drawn

for lab_id,spec in SPECS.items():
    def trace(namespace,recorder,spec=spec):
        recorder.context=spec['entry']+' · real offline PyTorch CPU experiment'
        recorder.watch(lambda:exec(compile(spec['fixture'],'<research-fixture>','exec'),namespace),lambda view:_draw(view,spec))
        return ''
    def check(namespace,code):
        exec(compile(code,'<research-check>','exec'),dict(namespace))
    checks=[(row['name'],lambda namespace,code=row['code']:check(namespace,code)) for row in spec['checks']]
    register(lab_id,{'practice':{'file':lab_id+'.py','names':[(spec['entry'],'a function '+spec['entry'])],'trace':trace,'checks':checks}})
