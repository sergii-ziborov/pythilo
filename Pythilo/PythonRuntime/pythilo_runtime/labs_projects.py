"""Linked ML/AI systems projects. Checks are independent contracts, not answer lookups."""
import copy
from .labs_engine import register
from .labs_extended import render

SPECS = {'multiclassloss': {'entry': 'multiclass_loss',
                    'args': [[[1000, 999], [1, 3]], [0, 1], [1, 2]],
                    'project': False,
                    'checks': [{'name': 'large logits stay finite',
                                'code': 'assert '
                                        'abs(multiclass_loss([[1000,999]],[0],[1])-0.3132616875182066)<1e-10, '
                                        "'Use a stable log normalizer.'\n"},
                               {'name': 'weight denominator',
                                'code': 'import math\n'
                                        'assert '
                                        'abs(multiclass_loss([[0,0],[0,0]],[0,1],[1,9])-math.log(2))<1e-12, '
                                        "'Normalize by total weight.'\n"},
                               {'name': 'shift and zero weight invariance',
                                'code': 'a=multiclass_loss([[3,1],[1,4]],[0,1],[2,0])\n'
                                        'b=multiclass_loss([[103,101]],[0],[2])\n'
                                        "assert abs(a-b)<1e-12, 'Row shifts and zero-weight rows must "
                                        "preserve the metric.'\n"},
                               {'name': 'bad label and zero denominator',
                                'code': 'try:\n'
                                        '    multiclass_loss([[0,0]],[True],[1])\n'
                                        'except ValueError:\n'
                                        '    pass\n'
                                        'else:\n'
                                        "    assert False, 'Reject invalid input before producing a "
                                        "result.'\n"
                                        'try:\n'
                                        '    multiclass_loss([[0,0]],[0],[0])\n'
                                        'except ValueError:\n'
                                        '    pass\n'
                                        'else:\n'
                                        "    assert False, 'Reject invalid input before producing a "
                                        "result.'\n"}]},
 'ndcg': {'entry': 'ndcg',
          'args': [['b', 'a', 'b'], {'a': 3, 'b': 1}, 2],
          'project': False,
          'checks': [{'name': 'ideal and reversed rankings',
                      'code': "assert ndcg(['a','b'],{'a':3,'b':1},2)==1, 'The ideal ranking must score "
                              "one.'\n"
                              "assert abs(ndcg(['b','a'],{'a':3,'b':1},2)-0.7098097413968655)<1e-10, "
                              "'Discount graded gains by position.'\n"},
                     {'name': 'duplicates do not steal positions',
                      'code': "assert ndcg(['a','a','b'],{'a':3,'b':1},2)==1, 'Deduplicate before applying "
                              "the cutoff.'\n"},
                     {'name': 'unknown and undefined relevance',
                      'code': "assert ndcg(['unknown'],{'a':3},1)==0, 'Unjudged IDs have zero gain in this "
                              "contract.'\n"
                              "assert ndcg(['a'],{'a':0},2) is None, 'No relevance makes normalized gain "
                              "undefined.'\n"},
                     {'name': 'invalid grade rejected',
                      'code': 'try:\n'
                              "    ndcg(['a'],{'a':True},1)\n"
                              'except ValueError:\n'
                              '    pass\n'
                              'else:\n'
                              "    assert False, 'Reject invalid input before producing a result.'\n"}]},
 'clusterbootstrap': {'entry': 'cluster_interval',
                      'args': [['a', 'a', 'b'], [1, 3, 0], 4, 7],
                      'project': False,
                      'checks': [{'name': 'equal group weighting',
                                  'code': "r=cluster_interval(['a','a','b'],[1,3,0],50,7)\n"
                                          "assert r['estimate']==1 and r['groups']==2 and "
                                          "0<=r['low']<=r['high']<=2, 'Weight independent groups "
                                          "equally.'\n"},
                                 {'name': 'constant paired improvement',
                                  'code': "r=cluster_interval(['a','b','c'],[.2,.2,.2],20,1)\n"
                                          "assert abs(r['low']-.2)<1e-12 and abs(r['high']-.2)<1e-12, "
                                          "'Constant group effects have a degenerate bootstrap interval.'\n"},
                                 {'name': 'seeded permutation invariance',
                                  'code': "a=cluster_interval(['a','b','a'],[1,5,3],60,3)\n"
                                          "b=cluster_interval(['a','a','b'],[3,1,5],60,3)\n"
                                          "assert a==b, 'Row order must not change sorted group "
                                          "resampling.'\n"},
                                 {'name': 'one independent unit is rejected',
                                  'code': 'try:\n'
                                          "    cluster_interval(['a','a'],[1,2],20,1)\n"
                                          'except ValueError:\n'
                                          '    pass\n'
                                          'else:\n'
                                          "    assert False, 'Reject invalid input before producing a "
                                          "result.'\n"}]},
 'offpolicy': {'entry': 'offpolicy_value',
               'args': [[[1, 0.5, 1], [0, 0.25, 1]], 3],
               'project': False,
               'checks': [{'name': 'IPS differs from self normalization',
                           'code': 'r=offpolicy_value([[1,.5,1],[0,.25,1]],10)\n'
                                   "assert r['value']==1 and r['mean_weight']==3 and "
                                   "abs(r['ess']-1.8)<1e-12, 'Use the declared IPS denominator and "
                                   "squared-weight ESS.'\n"},
                          {'name': 'clipping is explicit',
                           'code': 'r=offpolicy_value([[2,.01,1]],3)\n'
                                   "assert r['value']==6 and r['mean_weight']==3 and r['ess']==1, 'Clip "
                                   "before aggregation.'\n"},
                          {'name': 'zero target weight',
                           'code': 'r=offpolicy_value([[9,.5,0]],2)\n'
                                   "assert r=={'value':0,'mean_weight':0,'ess':0}, 'Handle a target with no "
                                   "observed-action mass.'\n"},
                          {'name': 'unsupported logging action rejected',
                           'code': 'try:\n'
                                   '    offpolicy_value([[1,0,1]],2)\n'
                                   'except ValueError:\n'
                                   '    pass\n'
                                   'else:\n'
                                   "    assert False, 'Reject invalid input before producing a result.'\n"}]},
 'temperature': {'entry': 'fit_temperature',
                 'args': [[[4, 0], [4, 0]], [0, 1], [1, 2, 4]],
                 'project': False,
                 'checks': [{'name': 'overconfident errors soften',
                             'code': 'r=fit_temperature([[4,0],[4,0]],[0,1],[1,2,4])\n'
                                     "assert r['temperature']==4 and abs(r['loss']-.8132616875182228)<1e-10, "
                                     "'Select on held-out log loss.'\n"},
                            {'name': 'confident correct scores sharpen',
                             'code': "assert fit_temperature([[4,0],[0,4]],[0,1],[1,2,4])['temperature']==1, "
                                     "'Correct logits can favor the smallest candidate.'\n"},
                            {'name': 'ties and shift invariance',
                             'code': 'a=fit_temperature([[0,0]],[0],[2,1,2])\n'
                                     'b=fit_temperature([[1000,1000]],[0],[1,2])\n'
                                     "assert a['temperature']==1 and abs(a['loss']-b['loss'])<1e-10, 'Use "
                                     "deterministic ties and stable row shifts.'\n"},
                            {'name': 'zero temperature rejected',
                             'code': 'try:\n'
                                     '    fit_temperature([[0,0]],[0],[0])\n'
                                     'except ValueError:\n'
                                     '    pass\n'
                                     'else:\n'
                                     "    assert False, 'Reject invalid input before producing a "
                                     "result.'\n"}]},
 'isotonic': {'entry': 'isotonic_fit',
              'args': [[0, 1, 2], [1, 1, 0], [1, 1, 1]],
              'project': False,
              'checks': [{'name': 'weighted violations merge',
                          'code': "assert isotonic_fit([0,1],[1,0],[1,3])==[[0,1,.25]], 'Pool positive and "
                                  "total weights, not unweighted block means.'\n"},
                         {'name': 'ties are one score group',
                          'code': "assert isotonic_fit([1,1,2],[1,0,1],[1,1,1])==[[1,1,.5],[2,2,1]], 'Tied "
                                  "scores share a fitted probability.'\n"},
                         {'name': 'backward cascading merges',
                          'code': "assert isotonic_fit([0,1,2],[1,1,0],[1,1,1])==[[0,2,2/3]], 'Continue "
                                  "merging after the first violation.'\n"},
                         {'name': 'nonpositive observation weight rejected',
                          'code': 'try:\n'
                                  '    isotonic_fit([0],[1],[0])\n'
                                  'except ValueError:\n'
                                  '    pass\n'
                                  'else:\n'
                                  "    assert False, 'Reject invalid input before producing a result.'\n"}]},
 'ridgeworkflow': {'entry': 'ridge_workflow',
                   'args': [[{'id': 't0', 'x': [0, 7], 'y': 1},
                             {'id': 't1', 'x': [1, 7], 'y': 3},
                             {'id': 't2', 'x': [2, 7], 'y': 5}],
                            [{'id': 'v', 'x': [3, 7], 'y': 7}],
                            [{'id': 'z', 'x': [4, 7], 'y': 9}],
                            [0.1, 10]],
                   'project': True,
                   'checks': [{'name': 'learned signal and constant feature',
                               'code': "train=[{'id': 't0', 'x': [0, 7], 'y': 1}, {'id': 't1', 'x': [1, 7], "
                                       "'y': 3}, {'id': 't2', 'x': [2, 7], 'y': 5}]\n"
                                       "validation=[{'id': 'v', 'x': [3, 7], 'y': 7}]\n"
                                       "test=[{'id': 'z', 'x': [4, 7], 'y': 9}]\n"
                                       'r=ridge_workflow(train,validation,test,[10,.1])\n'
                                       "assert r['alpha']==.1 and r['test_mse']<.02, 'Train and select an "
                                       "actual ridge model.'\n"
                                       "assert r['artifact']['means']==[1.5,7] and "
                                       "r['artifact']['scales'][1]==1, 'Refit preprocessing on "
                                       "train+validation only.'\n"},
                              {'name': 'test labels cannot select or fit',
                               'code': "train=[{'id': 't0', 'x': [0, 7], 'y': 1}, {'id': 't1', 'x': [1, 7], "
                                       "'y': 3}, {'id': 't2', 'x': [2, 7], 'y': 5}]\n"
                                       "validation=[{'id': 'v', 'x': [3, 7], 'y': 7}]\n"
                                       "test=[{'id': 'z', 'x': [4, 7], 'y': 9}]\n"
                                       'import copy\n'
                                       'a=ridge_workflow(train,validation,test,[.1,10])\n'
                                       "poison=copy.deepcopy(test);poison[0]['y']=10000\n"
                                       'b=ridge_workflow(train,validation,poison,[.1,10])\n'
                                       "assert a['artifact']==b['artifact'] and a['alpha']==b['alpha'] and "
                                       "a['predictions']==b['predictions'], 'Test targets must not influence "
                                       "the artifact.'\n"
                                       "assert a['test_mse']!=b['test_mse'], 'Test targets still determine "
                                       "the reported held-out error.'\n"},
                              {'name': 'artifact independently reproduces predictions',
                               'code': "train=[{'id': 't0', 'x': [0, 7], 'y': 1}, {'id': 't1', 'x': [1, 7], "
                                       "'y': 3}, {'id': 't2', 'x': [2, 7], 'y': 5}]\n"
                                       "validation=[{'id': 'v', 'x': [3, 7], 'y': 7}]\n"
                                       "test=[{'id': 'z', 'x': [4, 7], 'y': 9}]\n"
                                       'import json\n'
                                       'r=ridge_workflow(train,validation,test,[.1])\n'
                                       "m=json.loads(json.dumps(r['artifact']))\n"
                                       "p=m['intercept']+sum((x-a)/s*w for x,a,s,w in "
                                       "zip(test[0]['x'],m['means'],m['scales'],m['coefficients']))\n"
                                       "assert abs(p-r['predictions'][0])<1e-12 and "
                                       "r['fit_ids']==['t0','t1','t2','v'], 'Export all fitted "
                                       "transformation state.'\n"},
                              {'name': 'partition identity leakage rejected',
                               'code': "train=[{'id': 't0', 'x': [0, 7], 'y': 1}, {'id': 't1', 'x': [1, 7], "
                                       "'y': 3}, {'id': 't2', 'x': [2, 7], 'y': 5}]\n"
                                       "validation=[{'id': 'v', 'x': [3, 7], 'y': 7}]\n"
                                       "test=[{'id': 'z', 'x': [4, 7], 'y': 9}]\n"
                                       'try:\n'
                                       '    ridge_workflow(train,train,test,[.1])\n'
                                       'except ValueError:\n'
                                       '    pass\n'
                                       'else:\n'
                                       "    assert False, 'Reject invalid input before producing a "
                                       "result.'\n"}]},
 'nestedridge': {'entry': 'nested_group_ridge',
                 'args': [[{'id': '0', 'group': 'a', 'x': -2, 'y': -3},
                           {'id': '2', 'group': 'b', 'x': 0, 'y': 1},
                           {'id': '4', 'group': 'c', 'x': 2, 'y': 5}],
                          [0.1]],
                 'project': True,
                 'checks': [{'name': 'honest outer predictions cover the population',
                             'code': "rows=[{'id': '0', 'group': 'a', 'x': -2, 'y': -3}, {'id': '1', "
                                     "'group': 'a', 'x': -1, 'y': -1}, {'id': '2', 'group': 'b', 'x': 0, "
                                     "'y': 1}, {'id': '3', 'group': 'b', 'x': 1, 'y': 3}, {'id': '4', "
                                     "'group': 'c', 'x': 2, 'y': 5}, {'id': '5', 'group': 'c', 'x': 3, 'y': "
                                     '7}]\n'
                                     'r=nested_group_ridge(rows,[.01,.1])\n'
                                     "assert set(r['oof'])=={row['id'] for row in rows} and r['mse']<.01, "
                                     "'Train real outer models and predict every sample once.'\n"},
                            {'name': 'outer labels cannot tune their own model',
                             'code': "rows=[{'id': '0', 'group': 'a', 'x': -2, 'y': -3}, {'id': '1', "
                                     "'group': 'a', 'x': -1, 'y': -1}, {'id': '2', 'group': 'b', 'x': 0, "
                                     "'y': 1}, {'id': '3', 'group': 'b', 'x': 1, 'y': 3}, {'id': '4', "
                                     "'group': 'c', 'x': 2, 'y': 5}, {'id': '5', 'group': 'c', 'x': 3, 'y': "
                                     '7}]\n'
                                     'import copy\n'
                                     'a=nested_group_ridge(rows,[.01,10])\n'
                                     'poison=copy.deepcopy(rows)\n'
                                     'for row in poison:\n'
                                     "    if row['group']=='a': row['y']+=1000\n"
                                     'b=nested_group_ridge(poison,[.01,10])\n'
                                     "assert all(a['oof'][row['id']]==b['oof'][row['id']] for row in rows if "
                                     "row['group']=='a'), 'The outer group must never enter its own tuning "
                                     "loop.'\n"
                                     "assert a['folds'][0]['alpha']==b['folds'][0]['alpha'], 'Outer labels "
                                     "cannot choose the inner winner.'\n"},
                            {'name': 'auditable fit and held identities',
                             'code': "rows=[{'id': '0', 'group': 'a', 'x': -2, 'y': -3}, {'id': '1', "
                                     "'group': 'a', 'x': -1, 'y': -1}, {'id': '2', 'group': 'b', 'x': 0, "
                                     "'y': 1}, {'id': '3', 'group': 'b', 'x': 1, 'y': 3}, {'id': '4', "
                                     "'group': 'c', 'x': 2, 'y': 5}, {'id': '5', 'group': 'c', 'x': 3, 'y': "
                                     '7}]\n'
                                     'r=nested_group_ridge(rows,[.1])\n'
                                     "for fold in r['folds']:\n"
                                     "    assert not set(fold['fit_ids'])&set(fold['held_ids']), 'An outer "
                                     "fit contains held-out identities.'\n"
                                     "    assert len(fold['fit_ids'])==4 and len(fold['held_ids'])==2, "
                                     "'Preserve complete groups.'\n"},
                            {'name': 'two groups are insufficient for nested selection',
                             'code': "rows=[{'id': '0', 'group': 'a', 'x': -2, 'y': -3}, {'id': '1', "
                                     "'group': 'a', 'x': -1, 'y': -1}, {'id': '2', 'group': 'b', 'x': 0, "
                                     "'y': 1}, {'id': '3', 'group': 'b', 'x': 1, 'y': 3}, {'id': '4', "
                                     "'group': 'c', 'x': 2, 'y': 5}, {'id': '5', 'group': 'c', 'x': 3, 'y': "
                                     '7}]\n'
                                     'try:\n'
                                     '    nested_group_ridge(rows[:4],[.1])\n'
                                     'except ValueError:\n'
                                     '    pass\n'
                                     'else:\n'
                                     "    assert False, 'Reject invalid input before producing a "
                                     "result.'\n"}]},
 'walkforward': {'entry': 'walkforward_forecast',
                 'args': [[{'id': '0', 't': 0, 'available': 0, 'x': 0, 'y': 1},
                           {'id': '1', 't': 1, 'available': 1, 'x': 1, 'y': 3},
                           {'id': '2', 't': 2, 'available': 5, 'x': 2, 'y': 5},
                           {'id': '3', 't': 3, 'available': 3, 'x': 3, 'y': 7},
                           {'id': '4', 't': 4, 'available': 4, 'x': 4, 'y': 9}],
                          [2],
                          2,
                          0],
                 'project': True,
                 'checks': [{'name': 'late labels excluded from fitting',
                             'code': "rows=[{'id': '0', 't': 0, 'available': 0, 'x': 0, 'y': 1}, {'id': '1', "
                                     "'t': 1, 'available': 1, 'x': 1, 'y': 3}, {'id': '2', 't': 2, "
                                     "'available': 5, 'x': 2, 'y': 5}, {'id': '3', 't': 3, 'available': 3, "
                                     "'x': 3, 'y': 7}, {'id': '4', 't': 4, 'available': 4, 'x': 4, 'y': 9}]\n"
                                     'r=walkforward_forecast(rows,[2],2,0)[0]\n'
                                     "assert r['train_ids']==['0','1'] and r['held_ids']==['3','4'], 'Filter "
                                     "on label availability as well as event time.'\n"
                                     "assert abs(r['predictions'][0]-37/6)<1e-10, 'Fit the declared centered "
                                     "ridge model.'\n"},
                            {'name': 'future labels cannot change a past forecast',
                             'code': "rows=[{'id': '0', 't': 0, 'available': 0, 'x': 0, 'y': 1}, {'id': '1', "
                                     "'t': 1, 'available': 1, 'x': 1, 'y': 3}, {'id': '2', 't': 2, "
                                     "'available': 5, 'x': 2, 'y': 5}, {'id': '3', 't': 3, 'available': 3, "
                                     "'x': 3, 'y': 7}, {'id': '4', 't': 4, 'available': 4, 'x': 4, 'y': 9}]\n"
                                     'import copy\n'
                                     'a=walkforward_forecast(rows,[2],2,0)[0]\n'
                                     'poison=copy.deepcopy(rows)\n'
                                     'for row in poison:\n'
                                     "    if row['t']>=2: row['y']+=1000\n"
                                     'b=walkforward_forecast(poison,[2],2,0)[0]\n'
                                     "assert a['predictions']==b['predictions'] and a['mse']!=b['mse'], "
                                     "'Future truth must affect evaluation only.'\n"},
                            {'name': 'gap and insufficient history',
                             'code': "rows=[{'id': '0', 't': 0, 'available': 0, 'x': 0, 'y': 1}, {'id': '1', "
                                     "'t': 1, 'available': 1, 'x': 1, 'y': 3}, {'id': '2', 't': 2, "
                                     "'available': 5, 'x': 2, 'y': 5}, {'id': '3', 't': 3, 'available': 3, "
                                     "'x': 3, 'y': 7}, {'id': '4', 't': 4, 'available': 4, 'x': 4, 'y': 9}]\n"
                                     'r=walkforward_forecast(rows,[0,3],1,1)\n'
                                     "assert r[0]=={'cutoff':0,'status':'insufficient'}, 'Report "
                                     "insufficient history explicitly.'\n"
                                     "assert r[1]['train_ids']==['0','1'], 'The purge gap must precede model "
                                     "fitting.'\n"},
                            {'name': 'unsorted cutoffs rejected',
                             'code': "rows=[{'id': '0', 't': 0, 'available': 0, 'x': 0, 'y': 1}, {'id': '1', "
                                     "'t': 1, 'available': 1, 'x': 1, 'y': 3}, {'id': '2', 't': 2, "
                                     "'available': 5, 'x': 2, 'y': 5}, {'id': '3', 't': 3, 'available': 3, "
                                     "'x': 3, 'y': 7}, {'id': '4', 't': 4, 'available': 4, 'x': 4, 'y': 9}]\n"
                                     'try:\n'
                                     '    walkforward_forecast(rows,[3,2],1,0)\n'
                                     'except ValueError:\n'
                                     '    pass\n'
                                     'else:\n'
                                     "    assert False, 'Reject invalid input before producing a "
                                     "result.'\n"}]},
 'stackingproject': {'entry': 'stacked_regression',
                     'args': [[{'id': '0', 'fold': 'a', 'x': -2, 'y': 4},
                               {'id': '1', 'fold': 'a', 'x': -1, 'y': 1},
                               {'id': '2', 'fold': 'b', 'x': 0, 'y': 0},
                               {'id': '3', 'fold': 'b', 'x': 1, 'y': 1},
                               {'id': '4', 'fold': 'c', 'x': 2, 'y': 4},
                               {'id': '5', 'fold': 'c', 'x': 3, 'y': 9}],
                              [{'id': 'new', 'x': 4}]],
                     'project': True,
                     'checks': [{'name': 'OOF matrix and test features',
                                 'code': "rows=[{'id': '0', 'fold': 'a', 'x': -2, 'y': 4}, {'id': '1', "
                                         "'fold': 'a', 'x': -1, 'y': 1}, {'id': '2', 'fold': 'b', 'x': 0, "
                                         "'y': 0}, {'id': '3', 'fold': 'b', 'x': 1, 'y': 1}, {'id': '4', "
                                         "'fold': 'c', 'x': 2, 'y': 4}, {'id': '5', 'fold': 'c', 'x': 3, "
                                         "'y': 9}]\n"
                                         'test=[{"id":"new","x":4}]\n'
                                         'r=stacked_regression(rows,test)\n'
                                         "assert len(r['oof'])==6 and all(len(v)==2 for v in "
                                         "r['oof'].values()), 'Every row needs two out-of-fold base "
                                         "features.'\n"
                                         "assert len(r['predictions'])==1 and len(r['weights'])==2, 'Train "
                                         "and apply a real meta-model without test targets.'\n"},
                                {'name': 'held fold labels cannot affect its OOF features',
                                 'code': "rows=[{'id': '0', 'fold': 'a', 'x': -2, 'y': 4}, {'id': '1', "
                                         "'fold': 'a', 'x': -1, 'y': 1}, {'id': '2', 'fold': 'b', 'x': 0, "
                                         "'y': 0}, {'id': '3', 'fold': 'b', 'x': 1, 'y': 1}, {'id': '4', "
                                         "'fold': 'c', 'x': 2, 'y': 4}, {'id': '5', 'fold': 'c', 'x': 3, "
                                         "'y': 9}]\n"
                                         'test=[{"id":"new","x":4}]\n'
                                         'import copy\n'
                                         'a=stacked_regression(rows,test)\n'
                                         'poison=copy.deepcopy(rows)\n'
                                         'for row in poison:\n'
                                         "    if row['fold']=='a': row['y']+=1000\n"
                                         'b=stacked_regression(poison,test)\n'
                                         "assert a['oof']['0']==b['oof']['0'] and "
                                         "a['oof']['1']==b['oof']['1'], 'OOF features must exclude the "
                                         "entire held fold.'\n"},
                                {'name': 'constant targets are reproduced',
                                 'code': "rows=[{'id': '0', 'fold': 'a', 'x': -2, 'y': 4}, {'id': '1', "
                                         "'fold': 'a', 'x': -1, 'y': 1}, {'id': '2', 'fold': 'b', 'x': 0, "
                                         "'y': 0}, {'id': '3', 'fold': 'b', 'x': 1, 'y': 1}, {'id': '4', "
                                         "'fold': 'c', 'x': 2, 'y': 4}, {'id': '5', 'fold': 'c', 'x': 3, "
                                         "'y': 9}]\n"
                                         'test=[{"id":"new","x":4}]\n'
                                         'import copy\n'
                                         'constant=copy.deepcopy(rows)\n'
                                         "for row in constant: row['y']=5\n"
                                         'r=stacked_regression(constant,test)\n'
                                         "assert abs(r['predictions'][0]-5)<1e-10 and all(abs(w)<1e-10 for w "
                                         "in r['weights']), 'Keep unpenalized intercepts in base and meta "
                                         "fits.'\n"
                                         "for fold in r['folds']: assert not "
                                         "set(fold['fit_ids'])&set(fold['held_ids']), 'Fold identity leakage "
                                         "detected.'\n"},
                                {'name': 'overlapping test identity rejected',
                                 'code': "rows=[{'id': '0', 'fold': 'a', 'x': -2, 'y': 4}, {'id': '1', "
                                         "'fold': 'a', 'x': -1, 'y': 1}, {'id': '2', 'fold': 'b', 'x': 0, "
                                         "'y': 0}, {'id': '3', 'fold': 'b', 'x': 1, 'y': 1}, {'id': '4', "
                                         "'fold': 'c', 'x': 2, 'y': 4}, {'id': '5', 'fold': 'c', 'x': 3, "
                                         "'y': 9}]\n"
                                         'test=[{"id":"new","x":4}]\n'
                                         'try:\n'
                                         "    stacked_regression(rows,[{'id':'0','x':8}])\n"
                                         'except ValueError:\n'
                                         '    pass\n'
                                         'else:\n'
                                         "    assert False, 'Reject invalid input before producing a "
                                         "result.'\n"}]},
 'logisticproject': {'entry': 'train_logistic',
                     'args': [[{'id': '0', 'x': [-2, 7], 'y': 0},
                               {'id': '1', 'x': [-1, 7], 'y': 0},
                               {'id': '2', 'x': [1, 7], 'y': 1},
                               {'id': '3', 'x': [2, 7], 'y': 1}],
                              [{'id': 'v0', 'x': [-1.5, 7], 'y': 0}, {'id': 'v1', 'x': [1.5, 7], 'y': 1}],
                              [{'id': 'e0', 'x': [-3, 7], 'y': 0}, {'id': 'e1', 'x': [3, 7], 'y': 1}],
                              0.5,
                              2,
                              0.01],
                     'project': True,
                     'checks': [{'name': 'actual model learns the boundary',
                                 'code': "train=[{'id': '0', 'x': [-2, 7], 'y': 0}, {'id': '1', 'x': [-1, "
                                         "7], 'y': 0}, {'id': '2', 'x': [1, 7], 'y': 1}, {'id': '3', 'x': "
                                         "[2, 7], 'y': 1}]\n"
                                         "validation=[{'id': 'v0', 'x': [-1.5, 7], 'y': 0}, {'id': 'v1', "
                                         "'x': [1.5, 7], 'y': 1}]\n"
                                         "test=[{'id': 'e0', 'x': [-3, 7], 'y': 0}, {'id': 'e1', 'x': [3, "
                                         "7], 'y': 1}]\n"
                                         'r=train_logistic(train,validation,test,.5,20,.01)\n'
                                         "assert r['predictions']==[0,1] and r['test_loss']<.2, 'Train a "
                                         "classifier rather than returning fixture labels.'\n"
                                         "assert r['means']==[0,7] and r['scales'][1]==1 and "
                                         "r['weights'][1]==0, 'Keep constant columns well-defined.'\n"},
                                {'name': 'earliest validation checkpoint is restored',
                                 'code': "train=[{'id': '0', 'x': [-2, 7], 'y': 0}, {'id': '1', 'x': [-1, "
                                         "7], 'y': 0}, {'id': '2', 'x': [1, 7], 'y': 1}, {'id': '3', 'x': "
                                         "[2, 7], 'y': 1}]\n"
                                         "validation=[{'id': 'v0', 'x': [-1.5, 7], 'y': 0}, {'id': 'v1', "
                                         "'x': [1.5, 7], 'y': 1}]\n"
                                         "test=[{'id': 'e0', 'x': [-3, 7], 'y': 0}, {'id': 'e1', 'x': [3, "
                                         "7], 'y': 1}]\n"
                                         'import copy\n'
                                         'bad=copy.deepcopy(validation)\n'
                                         "for row in bad: row['y']=1-row['y']\n"
                                         'a=train_logistic(train,bad,test,.5,10,.01)\n'
                                         'b=train_logistic(train,bad,test,.5,1,.01)\n'
                                         "assert a['best_step']==1 and a['weights']==b['weights'] and "
                                         "a['bias']==b['bias'], 'Restore copied weights from the strict "
                                         "validation minimum.'\n"},
                                {'name': 'test labels cannot change trained parameters',
                                 'code': "train=[{'id': '0', 'x': [-2, 7], 'y': 0}, {'id': '1', 'x': [-1, "
                                         "7], 'y': 0}, {'id': '2', 'x': [1, 7], 'y': 1}, {'id': '3', 'x': "
                                         "[2, 7], 'y': 1}]\n"
                                         "validation=[{'id': 'v0', 'x': [-1.5, 7], 'y': 0}, {'id': 'v1', "
                                         "'x': [1.5, 7], 'y': 1}]\n"
                                         "test=[{'id': 'e0', 'x': [-3, 7], 'y': 0}, {'id': 'e1', 'x': [3, "
                                         "7], 'y': 1}]\n"
                                         'import copy\n'
                                         'a=train_logistic(train,validation,test,.5,8,.01)\n'
                                         'poison=copy.deepcopy(test)\n'
                                         "for row in poison: row['y']=1-row['y']\n"
                                         'b=train_logistic(train,validation,poison,.5,8,.01)\n'
                                         "assert a['weights']==b['weights'] and "
                                         "a['best_step']==b['best_step'] and a['test_loss']!=b['test_loss'], "
                                         "'Test truth belongs only to final evaluation.'\n"},
                                {'name': 'invalid optimizer budget rejected',
                                 'code': "train=[{'id': '0', 'x': [-2, 7], 'y': 0}, {'id': '1', 'x': [-1, "
                                         "7], 'y': 0}, {'id': '2', 'x': [1, 7], 'y': 1}, {'id': '3', 'x': "
                                         "[2, 7], 'y': 1}]\n"
                                         "validation=[{'id': 'v0', 'x': [-1.5, 7], 'y': 0}, {'id': 'v1', "
                                         "'x': [1.5, 7], 'y': 1}]\n"
                                         "test=[{'id': 'e0', 'x': [-3, 7], 'y': 0}, {'id': 'e1', 'x': [3, "
                                         "7], 'y': 1}]\n"
                                         'try:\n'
                                         '    train_logistic(train,validation,test,.5,0,.01)\n'
                                         'except ValueError:\n'
                                         '    pass\n'
                                         'else:\n'
                                         "    assert False, 'Reject invalid input before producing a "
                                         "result.'\n"}]},
 'rolloutmonitor': {'entry': 'monitor_rollout',
                    'args': [{},
                             0,
                             [{'id': 'a', 'cohort': 'small', 'baseline': 0.1, 'candidate': 0.9},
                              {'id': 'b', 'cohort': 'large', 'baseline': 0.1, 'candidate': 0.9}],
                             [{'id': 'a', 'y': 0, 'available': 1}, {'id': 'b', 'y': 0, 'available': 1}],
                             2,
                             1,
                             0.05],
                    'project': True,
                    'checks': [{'name': 'two bad windows trigger a latched rollback',
                                'code': "predictions=[{'id': 'a', 'cohort': 'small', 'baseline': 0.1, "
                                        "'candidate': 0.9}, {'id': 'b', 'cohort': 'large', 'baseline': 0.1, "
                                        "'candidate': 0.9}]\n"
                                        "outcomes=[{'id': 'a', 'y': 0, 'available': 1}, {'id': 'b', 'y': 0, "
                                        "'available': 1}]\n"
                                        'a=monitor_rollout({},0,predictions,outcomes,2,1,.05)\n'
                                        'b=monitor_rollout(a,1,predictions,outcomes,2,1,.05)\n'
                                        "assert a['status']=='hold' and b['status']=='rollback' and "
                                        "b['bad_windows']==2, 'Rollback requires two consecutive "
                                        "sufficiently observed bad windows.'\n"
                                        "good=[{**r,'candidate':.1} for r in predictions]\n"
                                        'c=monitor_rollout(b,2,good,outcomes,2,1,.05)\n'
                                        "assert c['status']=='rollback', 'Rollback is latched, not silently "
                                        "reversed.'\n"},
                               {'name': 'missing cohort labels cannot promote',
                                'code': "predictions=[{'id': 'a', 'cohort': 'small', 'baseline': 0.1, "
                                        "'candidate': 0.9}, {'id': 'b', 'cohort': 'large', 'baseline': 0.1, "
                                        "'candidate': 0.9}]\n"
                                        "outcomes=[{'id': 'a', 'y': 0, 'available': 1}, {'id': 'b', 'y': 0, "
                                        "'available': 1}]\n"
                                        'r=monitor_rollout({},0,predictions,outcomes[:1],2,1,.05)\n'
                                        "assert r['status']=='hold' and "
                                        "r['coverage']=={'large':0,'small':1}, 'Do not hide an unobserved "
                                        "cohort.'\n"
                                        'late=monitor_rollout({},0,predictions,outcomes,0,1,.05)\n'
                                        "assert late['deltas']=={} and late['status']=='hold', 'Future "
                                        "labels are unavailable evidence.'\n"},
                               {'name': 'identical replay is immutable',
                                'code': "predictions=[{'id': 'a', 'cohort': 'small', 'baseline': 0.1, "
                                        "'candidate': 0.9}, {'id': 'b', 'cohort': 'large', 'baseline': 0.1, "
                                        "'candidate': 0.9}]\n"
                                        "outcomes=[{'id': 'a', 'y': 0, 'available': 1}, {'id': 'b', 'y': 0, "
                                        "'available': 1}]\n"
                                        'import copy\n'
                                        's=monitor_rollout({},0,predictions,outcomes,2,1,.05)\n'
                                        'old=copy.deepcopy(s)\n'
                                        'r=monitor_rollout(s,0,predictions,outcomes,2,1,.05)\n'
                                        "r['coverage']['small']=99\n"
                                        "assert s==old, 'Replay must not return mutable aliases into stored "
                                        "state.'\n"},
                               {'name': 'changed window replay rejected',
                                'code': "predictions=[{'id': 'a', 'cohort': 'small', 'baseline': 0.1, "
                                        "'candidate': 0.9}, {'id': 'b', 'cohort': 'large', 'baseline': 0.1, "
                                        "'candidate': 0.9}]\n"
                                        "outcomes=[{'id': 'a', 'y': 0, 'available': 1}, {'id': 'b', 'y': 0, "
                                        "'available': 1}]\n"
                                        's=monitor_rollout({},0,predictions,outcomes,2,1,.05)\n'
                                        'try:\n'
                                        '    monitor_rollout(s,0,predictions,outcomes,3,1,.05)\n'
                                        'except ValueError:\n'
                                        '    pass\n'
                                        'else:\n'
                                        "    assert False, 'Reject invalid input before producing a "
                                        "result.'\n"}]},
 'mmr': {'entry': 'mmr_select',
         'args': [[1, 0],
                  [{'id': 'a', 'vector': [1, 0]},
                   {'id': 'b', 'vector': [1, 0]},
                   {'id': 'c', 'vector': [0, 1]}],
                  2,
                  0.3],
         'project': False,
         'checks': [{'name': 'diversity displaces a duplicate vector',
                     'code': "docs=[{'id': 'a', 'vector': [1, 0]}, {'id': 'b', 'vector': [1, 0]}, {'id': "
                             "'c', 'vector': [0, 1]}]\n"
                             "assert mmr_select([1,0],docs,2,.3)==['a','c'], 'Penalize redundancy against "
                             "the selected evidence.'\n"},
                    {'name': 'pure relevance and deterministic ties',
                     'code': "docs=[{'id': 'a', 'vector': [1, 0]}, {'id': 'b', 'vector': [1, 0]}, {'id': "
                             "'c', 'vector': [0, 1]}]\n"
                             "assert mmr_select([1,0],list(reversed(docs)),3,1)==['a','b','c'], 'Break equal "
                             "scores by identity, not input order.'\n"},
                    {'name': 'zero vectors and zero cutoff',
                     'code': "assert mmr_select([0,0],[{'id':'z','vector':[0,0]}],1,.5)==['z'], 'Define "
                             "zero-norm cosine.'\n"
                             "assert mmr_select([1],[],0,.5)==[], 'An empty candidate set is valid.'\n"},
                    {'name': 'dimension mismatch rejected',
                     'code': 'try:\n'
                             "    mmr_select([1,0],[{'id':'a','vector':[1]}],1,.5)\n"
                             'except ValueError:\n'
                             '    pass\n'
                             'else:\n'
                             "    assert False, 'Reject invalid input before producing a result.'\n"}]},
 'stopdecoder': {'entry': 'stream_decode',
                 'args': [[[1, 7], [8, 9]], [[7, 8]], 10],
                 'project': False,
                 'checks': [{'name': 'split stop sequence',
                             'code': 'assert '
                                     "stream_decode([[1,7],[8,9]],[[7,8]],10)=={'tokens':[1],'reason':'stop','consumed':3}, "
                                     "'Transport chunks must not break stop matching.'\n"},
                            {'name': 'longest completed stop wins',
                             'code': 'assert '
                                     "stream_decode([[1,7,8]],[[8],[7,8]],3)=={'tokens':[1],'reason':'stop','consumed':3}, "
                                     "'Complete stops take precedence and use the longest suffix.'\n"},
                            {'name': 'budget and EOF semantics',
                             'code': 'assert '
                                     "stream_decode([[1,7],[8]],[[7,8]],2)=={'tokens':[1,7],'reason':'budget','consumed':2}, "
                                     "'A hard budget can expose an incomplete stop prefix.'\n"
                                     'assert '
                                     "stream_decode([[],[2]],[],5)=={'tokens':[2],'reason':'eof','consumed':1}, "
                                     "'Empty chunks do not end the stream.'\n"},
                            {'name': 'invalid empty stop rejected',
                             'code': 'try:\n'
                                     '    stream_decode([[1]],[[]],2)\n'
                                     'except ValueError:\n'
                                     '    pass\n'
                                     'else:\n'
                                     "    assert False, 'Reject invalid input before producing a "
                                     "result.'\n"}]},
 'kvplanner': {'entry': 'plan_kv',
               'args': [[{'id': 'a', 'prompt': 2, 'output': 2},
                         {'id': 'b', 'prompt': 3, 'output': 2},
                         {'id': 'c', 'prompt': 0, 'output': 1}],
                        2,
                        1,
                        4,
                        2,
                        192],
               'project': False,
               'checks': [{'name': 'GQA dimensions and ragged requests',
                           'code': "r=plan_kv([{'id': 'a', 'prompt': 2, 'output': 2}, {'id': 'b', 'prompt': "
                                   "3, 'output': 2}, {'id': 'c', 'prompt': 0, 'output': 1}],2,1,4,2,192)\n"
                                   'assert '
                                   "r=={'admitted':['a','c'],'rejected':['b'],'reserved_bytes':160,'bytes_per_token':32}, "
                                   "'Account for KV heads and remaining byte capacity.'\n"},
                          {'name': 'exact capacity boundary',
                           'code': 'assert '
                                   "plan_kv([{'id':'a','prompt':1,'output':1}],1,1,1,2,8)['admitted']==['a'], "
                                   "'An exact fit is admissible.'\n"},
                          {'name': 'zero capacity is explicit',
                           'code': "r=plan_kv([{'id':'a','prompt':1,'output':0}],1,1,1,2,0)\n"
                                   "assert r['admitted']==[] and r['reserved_bytes']==0, 'No memory means no "
                                   "positive-size admission.'\n"},
                          {'name': 'boolean dimensions rejected',
                           'code': 'try:\n'
                                   '    plan_kv([],True,1,1,2,0)\n'
                                   'except ValueError:\n'
                                   '    pass\n'
                                   'else:\n'
                                   "    assert False, 'Reject invalid input before producing a result.'\n"}]},
 'strictschema': {'entry': 'validate_output',
                  'args': [{'count': True, 'extra': 1, 'tags': ['long', 9]},
                           {'type': 'object',
                            'properties': {'count': {'type': 'integer'},
                                           'tags': {'type': 'array',
                                                    'items': {'type': 'string', 'maxLength': 3},
                                                    'maxItems': 2}},
                            'required': ['count'],
                            'additionalProperties': False}],
                  'project': False,
                  'checks': [{'name': 'nested paths and closed properties',
                              'code': "schema={'type': 'object', 'properties': {'count': {'type': "
                                      "'integer'}, 'tags': {'type': 'array', 'items': {'type': 'string', "
                                      "'maxLength': 3}, 'maxItems': 2}}, 'required': ['count'], "
                                      "'additionalProperties': False}\n"
                                      "r=validate_output({'count':True,'extra':1,'tags':['long',9]},schema)\n"
                                      'assert '
                                      "r==['$.count:type','$.extra:extra','$.tags[0]:length','$.tags[1]:type'], "
                                      "'Report strict nested errors in deterministic order.'\n"},
                             {'name': 'valid and missing required output',
                              'code': "schema={'type': 'object', 'properties': {'count': {'type': "
                                      "'integer'}, 'tags': {'type': 'array', 'items': {'type': 'string', "
                                      "'maxLength': 3}, 'maxItems': 2}}, 'required': ['count'], "
                                      "'additionalProperties': False}\n"
                                      "assert validate_output({'count':2,'tags':['ok']},schema)==[], 'Valid "
                                      "output must pass.'\n"
                                      "assert validate_output({},schema)==['$.count:missing'], 'Required "
                                      "properties cannot be omitted.'\n"},
                             {'name': 'finite numbers and exact enum types',
                              'code': "assert validate_output(float('nan'),{'type':'number'})==['$:type'], "
                                      "'Reject nonfinite numbers.'\n"
                                      'assert '
                                      "validate_output(True,{'type':'boolean','enum':[1]})==['$:enum'], "
                                      "'Boolean true is not integer one in an enum.'\n"},
                             {'name': 'unsupported schema fails closed',
                              'code': 'try:\n'
                                      "    validate_output('x',{'type':'string','pattern':'x'})\n"
                                      'except ValueError:\n'
                                      '    pass\n'
                                      'else:\n'
                                      "    assert False, 'Reject invalid input before producing a "
                                      "result.'\n"}]},
 'evalmatrix': {'entry': 'evaluation_matrix',
                'args': [[{'id': 'q1', 'category': 'retrieval'},
                          {'id': 'q2', 'category': 'retrieval'},
                          {'id': 'q3', 'category': 'authority'}],
                         [{'id': 'q3', 'passed': False},
                          {'id': 'q1', 'passed': True},
                          {'id': 'q2', 'passed': True}]],
                'project': False,
                'checks': [{'name': 'inventory controls categories and denominators',
                            'code': "r=evaluation_matrix([{'id': 'q1', 'category': 'retrieval'}, {'id': "
                                    "'q2', 'category': 'retrieval'}, {'id': 'q3', 'category': "
                                    "'authority'}],[{'id': 'q3', 'passed': False}, {'id': 'q1', 'passed': "
                                    "True}, {'id': 'q2', 'passed': True}])\n"
                                    "assert r['retrieval']=={'total':2,'passed':2,'rate':1,'failed':[]}, "
                                    "'Count every expected retrieval case.'\n"
                                    "assert r['authority']['failed']==['q3'] and r['authority']['rate']==0, "
                                    "'Preserve the failing authority case.'\n"},
                           {'name': 'result order is immaterial',
                            'code': "assert evaluation_matrix([{'id': 'q1', 'category': 'retrieval'}, {'id': "
                                    "'q2', 'category': 'retrieval'}, {'id': 'q3', 'category': "
                                    "'authority'}],[{'id': 'q3', 'passed': False}, {'id': 'q1', 'passed': "
                                    "True}, {'id': 'q2', 'passed': True}])==evaluation_matrix([{'id': 'q1', "
                                    "'category': 'retrieval'}, {'id': 'q2', 'category': 'retrieval'}, {'id': "
                                    "'q3', 'category': 'authority'}],list(reversed([{'id': 'q3', 'passed': "
                                    "False}, {'id': 'q1', 'passed': True}, {'id': 'q2', 'passed': True}]))), "
                                    "'Join results by stable case identity.'\n"},
                           {'name': 'missing hard case rejected',
                            'code': "expected=[{'id': 'q1', 'category': 'retrieval'}, {'id': 'q2', "
                                    "'category': 'retrieval'}, {'id': 'q3', 'category': 'authority'}]\n"
                                    'try:\n'
                                    "    evaluation_matrix(expected,[{'id':'q1','passed':True}])\n"
                                    'except ValueError:\n'
                                    '    pass\n'
                                    'else:\n'
                                    "    assert False, 'Reject invalid input before producing a result.'\n"},
                           {'name': 'duplicate and coerced outcomes rejected',
                            'code': "expected=[{'id': 'q1', 'category': 'retrieval'}, {'id': 'q2', "
                                    "'category': 'retrieval'}, {'id': 'q3', 'category': 'authority'}]\n"
                                    'try:\n'
                                    "    evaluation_matrix(expected,[{'id':'q1','passed':True}]*3)\n"
                                    'except ValueError:\n'
                                    '    pass\n'
                                    'else:\n'
                                    "    assert False, 'Reject invalid input before producing a result.'\n"
                                    'try:\n'
                                    '    '
                                    "evaluation_matrix([{'id':'x','category':'a'}],[{'id':'x','passed':1}])\n"
                                    'except ValueError:\n'
                                    '    pass\n'
                                    'else:\n'
                                    "    assert False, 'Reject invalid input before producing a "
                                    "result.'\n"}]},
 'provenance': {'entry': 'verify_provenance',
                'args': [[{'text': 'A statement',
                           'citations': [{'source': 's', 'start': 0, 'end': 6, 'quote': 'Python'}]}],
                         [{'id': 's',
                           'tenant': 'a',
                           'version': 'v1',
                           'text': 'Python has types.',
                           'sha256': '4e3dcb7b0cd4ca68f19f6927a0b3602a92e23021921be20d2e825f103a830ed3'}],
                         'a',
                         'v1'],
                'project': False,
                'checks': [{'name': 'valid versioned span',
                            'code': "assert verify_provenance([{'text': 'A statement', 'citations': "
                                    "[{'source': 's', 'start': 0, 'end': 6, 'quote': 'Python'}]}],[{'id': "
                                    "'s', 'tenant': 'a', 'version': 'v1', 'text': 'Python has types.', "
                                    "'sha256': "
                                    "'4e3dcb7b0cd4ca68f19f6927a0b3602a92e23021921be20d2e825f103a830ed3'}],'a','v1')==[{'ok':True,'errors':[]}], "
                                    "'Verify all provenance layers.'\n"},
                           {'name': 'scope and changed content denied',
                            'code': "s={'id': 's', 'tenant': 'a', 'version': 'v1', 'text': 'Python has "
                                    "types.', 'sha256': "
                                    "'4e3dcb7b0cd4ca68f19f6927a0b3602a92e23021921be20d2e825f103a830ed3'};c={'text': "
                                    "'A statement', 'citations': [{'source': 's', 'start': 0, 'end': 6, "
                                    "'quote': 'Python'}]}\n"
                                    "assert verify_provenance([c],[s],'b','v1')[0]['errors']==['s:scope'], "
                                    "'Cross-tenant provenance is invalid.'\n"
                                    "s['text']='Changed'\n"
                                    "assert verify_provenance([c],[s],'a','v1')[0]['errors']==['s:digest'], "
                                    "'A stale digest cannot authenticate changed text.'\n"},
                           {'name': 'missing and invented quoted spans',
                            'code': "s={'id': 's', 'tenant': 'a', 'version': 'v1', 'text': 'Python has "
                                    "types.', 'sha256': "
                                    "'4e3dcb7b0cd4ca68f19f6927a0b3602a92e23021921be20d2e825f103a830ed3'};c={'text': "
                                    "'A statement', 'citations': [{'source': 's', 'start': 0, 'end': 6, "
                                    "'quote': 'Python'}]}\n"
                                    "c['citations'][0]['quote']='invented'\n"
                                    "assert verify_provenance([c],[s],'a','v1')[0]['errors']==['s:quote'], "
                                    "'The quoted bytes must correspond to the declared code-point span.'\n"
                                    'assert '
                                    "verify_provenance([{'text':'x','citations':[]}],[s],'a','v1')[0]['errors']==['missing'], "
                                    "'Uncited claims need an explicit missing result.'\n"},
                           {'name': 'duplicate source identity rejected',
                            'code': "s={'id': 's', 'tenant': 'a', 'version': 'v1', 'text': 'Python has "
                                    "types.', 'sha256': "
                                    "'4e3dcb7b0cd4ca68f19f6927a0b3602a92e23021921be20d2e825f103a830ed3'}\n"
                                    'try:\n'
                                    "    verify_provenance([],[s,s],'a','v1')\n"
                                    'except ValueError:\n'
                                    '    pass\n'
                                    'else:\n'
                                    "    assert False, 'Reject invalid input before producing a "
                                    "result.'\n"}]},
 'bm25project': {'entry': 'secure_bm25',
                 'args': [[{'id': 'a', 'tenant': 'a', 'roles': [], 'text': 'python python'},
                           {'id': 'b', 'tenant': 'a', 'roles': ['reader'], 'text': 'python tools'},
                           {'id': 'hidden',
                            'tenant': 'b',
                            'roles': [],
                            'text': 'python python python python python python python python python python '
                                    'python python python python python python python python python python '
                                    'python python python python python python python python python python '
                                    'python python python python python python python python python python '
                                    'python python python python python python python python python '
                                    'python '}],
                          'a',
                          ['reader'],
                          'python',
                          2],
                 'project': True,
                 'checks': [{'name': 'actual BM25 formula',
                             'code': 'import math\n'
                                     "d=[{'id':'x','tenant':'a','roles':[],'text':'python tools'}]\n"
                                     "r=secure_bm25(d,'a',[],'python',2)\n"
                                     "assert r[0]['id']=='x' and abs(r[0]['score']-math.log(4/3))<1e-12, "
                                     "'Use the declared BM25 formula, not token overlap counts.'\n"},
                            {'name': 'permissions precede corpus statistics',
                             'code': "docs=[{'id': 'a', 'tenant': 'a', 'roles': [], 'text': 'python "
                                     "python'}, {'id': 'b', 'tenant': 'a', 'roles': ['reader'], 'text': "
                                     "'python tools'}, {'id': 'hidden', 'tenant': 'b', 'roles': [], 'text': "
                                     "'python python python python python python python python python python "
                                     'python python python python python python python python python python '
                                     'python python python python python python python python python python '
                                     'python python python python python python python python python python '
                                     'python python python python python python python python python python '
                                     "'}]\n"
                                     "a=secure_bm25(docs,'a',['reader'],'python',2)\n"
                                     "b=secure_bm25(docs[:2],'a',['reader'],'python',2)\n"
                                     "assert a==b and [r['id'] for r in a]==['a','b'], 'Hidden documents "
                                     "must not alter visible scores.'\n"
                                     "assert [r['id'] for r in secure_bm25(docs,'a',[],'python',3)]==['a'], "
                                     "'Role-restricted evidence must be excluded.'\n"},
                            {'name': 'query ties and no matches',
                             'code': "d=[{'id':key,'tenant':'a','roles':[],'text':'same'} for key in "
                                     "['z','a']]\n"
                                     "assert [r['id'] for r in secure_bm25(d,'a',[],'SAME "
                                     "same',3)]==['a','z'], 'Deduplicate query terms and stabilize ties.'\n"
                                     "assert secure_bm25(d,'a',[],'absent',3)==[], 'No lexical match "
                                     "produces no evidence.'\n"},
                            {'name': 'duplicate tenant identity rejected',
                             'code': "docs=[{'id': 'a', 'tenant': 'a', 'roles': [], 'text': 'python "
                                     "python'}, {'id': 'b', 'tenant': 'a', 'roles': ['reader'], 'text': "
                                     "'python tools'}, {'id': 'hidden', 'tenant': 'b', 'roles': [], 'text': "
                                     "'python python python python python python python python python python "
                                     'python python python python python python python python python python '
                                     'python python python python python python python python python python '
                                     'python python python python python python python python python python '
                                     'python python python python python python python python python python '
                                     "'}]\n"
                                     'try:\n'
                                     "    secure_bm25(docs+[docs[0]],'a',[],'python',1)\n"
                                     'except ValueError:\n'
                                     '    pass\n'
                                     'else:\n'
                                     "    assert False, 'Reject invalid input before producing a "
                                     "result.'\n"}]},
 'indexproject': {'entry': 'update_index',
                  'args': [{'tenant': 'a', 'version': 0, 'documents': {}, 'seen': {}},
                           [{'tenant': 'a',
                             'event': 'e1',
                             'id': 'd',
                             'revision': 1,
                             'op': 'upsert',
                             'text': 'python',
                             'roles': ['reader']},
                            {'tenant': 'a', 'event': 'e2', 'id': 'd', 'revision': 2, 'op': 'delete'}],
                           0],
                  'project': True,
                  'checks': [{'name': 'batch update and exact replay',
                              'code': "state={'tenant': 'a', 'version': 0, 'documents': {}, 'seen': {}}\n"
                                      "up={'tenant': 'a', 'event': 'e1', 'id': 'd', 'revision': 1, 'op': "
                                      "'upsert', 'text': 'python', 'roles': ['reader']}\n"
                                      "delete={'tenant': 'a', 'event': 'e2', 'id': 'd', 'revision': 2, 'op': "
                                      "'delete'}\n"
                                      'a=update_index(state,[up],0)\n'
                                      'b=update_index(a,[up],1)\n'
                                      "assert a==b and a['version']==1 and "
                                      "a['documents']['d']['text']=='python', 'Replay an identical event "
                                      "without another version increment.'\n"
                                      "assert state['documents']=={}, 'Never mutate the input snapshot.'\n"},
                             {'name': 'deletion prevents stale resurrection',
                              'code': "state={'tenant': 'a', 'version': 0, 'documents': {}, 'seen': {}}\n"
                                      "up={'tenant': 'a', 'event': 'e1', 'id': 'd', 'revision': 1, 'op': "
                                      "'upsert', 'text': 'python', 'roles': ['reader']}\n"
                                      "delete={'tenant': 'a', 'event': 'e2', 'id': 'd', 'revision': 2, 'op': "
                                      "'delete'}\n"
                                      'a=update_index(state,[up,delete],0)\n'
                                      "assert a['version']==1 and "
                                      "a['documents']['d']=={'revision':2,'deleted':True,'text':'','roles':[]}, "
                                      "'Retain a tombstone without retrievable text.'\n"
                                      "stale={**up,'event':'stale','revision':1}\n"
                                      'try:\n'
                                      '    update_index(a,[stale],1)\n'
                                      'except ValueError:\n'
                                      '    pass\n'
                                      'else:\n'
                                      "    assert False, 'Reject invalid input before producing a "
                                      "result.'\n"},
                             {'name': 'conflict rolls back a whole batch',
                              'code': "state={'tenant': 'a', 'version': 0, 'documents': {}, 'seen': {}}\n"
                                      "up={'tenant': 'a', 'event': 'e1', 'id': 'd', 'revision': 1, 'op': "
                                      "'upsert', 'text': 'python', 'roles': ['reader']}\n"
                                      "delete={'tenant': 'a', 'event': 'e2', 'id': 'd', 'revision': 2, 'op': "
                                      "'delete'}\n"
                                      'import copy\n'
                                      'before=copy.deepcopy(state)\n'
                                      "bad={**up,'event':'bad','tenant':'b'}\n"
                                      'try:\n'
                                      '    update_index(state,[up,bad],0)\n'
                                      'except ValueError:\n'
                                      '    pass\n'
                                      'else:\n'
                                      "    assert False, 'Reject invalid input before producing a result.'\n"
                                      "assert state==before, 'A failed batch must preserve every byte of the "
                                      "prior state.'\n"
                                      'a=update_index(state,[up],0)\n'
                                      "changed={**up,'text':'different'}\n"
                                      'try:\n'
                                      '    update_index(a,[changed],1)\n'
                                      'except ValueError:\n'
                                      '    pass\n'
                                      'else:\n'
                                      "    assert False, 'Reject invalid input before producing a "
                                      "result.'\n"},
                             {'name': 'new ACL revision and CAS',
                              'code': "state={'tenant': 'a', 'version': 0, 'documents': {}, 'seen': {}}\n"
                                      "up={'tenant': 'a', 'event': 'e1', 'id': 'd', 'revision': 1, 'op': "
                                      "'upsert', 'text': 'python', 'roles': ['reader']}\n"
                                      "delete={'tenant': 'a', 'event': 'e2', 'id': 'd', 'revision': 2, 'op': "
                                      "'delete'}\n"
                                      'a=update_index(state,[up],0)\n'
                                      "new={**up,'event':'e3','revision':3,'roles':['admin','admin']}\n"
                                      'b=update_index(a,[new],1)\n'
                                      "assert b['documents']['d']['roles']==['admin'], 'Publish the new ACL "
                                      "with the content revision.'\n"
                                      'try:\n'
                                      '    update_index(b,[],1)\n'
                                      'except ValueError:\n'
                                      '    pass\n'
                                      'else:\n'
                                      "    assert False, 'Reject invalid input before producing a "
                                      "result.'\n"}]},
 'ragproject': {'entry': 'rag_response',
                'args': [[{'id': 'a', 'tenant': 'a', 'roles': [], 'text': 'python python'},
                          {'id': 'b', 'tenant': 'a', 'roles': ['reader'], 'text': 'python tools'},
                          {'id': 'hidden',
                           'tenant': 'b',
                           'roles': [],
                           'text': 'python python python python python python python python python python '
                                   'python python python python python python python python python python '
                                   'python python python python python python python python python python '
                                   'python python python python python python python python python python '
                                   'python python python python python python python python python python '}],
                         {'tenant': 'a', 'roles': ['reader'], 'query': 'python', 'k': 2, 'word_budget': 4},
                         {'claims': [{'text': 'Python evidence.',
                                      'source': 'a',
                                      'start': 0,
                                      'end': 6,
                                      'quote': 'python'}]}],
                'project': True,
                'checks': [{'name': 'retrieval packing and literal evidence',
                            'code': "docs=[{'id': 'a', 'tenant': 'a', 'roles': [], 'text': 'python python'}, "
                                    "{'id': 'b', 'tenant': 'a', 'roles': ['reader'], 'text': 'python "
                                    "tools'}, {'id': 'hidden', 'tenant': 'b', 'roles': [], 'text': 'python "
                                    'python python python python python python python python python python '
                                    'python python python python python python python python python python '
                                    'python python python python python python python python python python '
                                    'python python python python python python python python python python '
                                    "python python python python python python python python python '}]\n"
                                    "request={'tenant': 'a', 'roles': ['reader'], 'query': 'python', 'k': 2, "
                                    "'word_budget': 4}\n"
                                    "output={'claims': [{'text': 'Python evidence.', 'source': 'a', 'start': "
                                    "0, 'end': 6, 'quote': 'python'}]}\n"
                                    'r=rag_response(docs,request,output)\n'
                                    "assert r=={'context_ids':['a','b'],'words':4,'claims':['Python "
                                    "evidence.'],'answer':'Python evidence.','abstained':False}, 'Compose "
                                    "ranking, packing and response validation.'\n"},
                           {'name': 'hidden or unadmitted sources denied',
                            'code': "docs=[{'id': 'a', 'tenant': 'a', 'roles': [], 'text': 'python python'}, "
                                    "{'id': 'b', 'tenant': 'a', 'roles': ['reader'], 'text': 'python "
                                    "tools'}, {'id': 'hidden', 'tenant': 'b', 'roles': [], 'text': 'python "
                                    'python python python python python python python python python python '
                                    'python python python python python python python python python python '
                                    'python python python python python python python python python python '
                                    'python python python python python python python python python python '
                                    "python python python python python python python python python '}]\n"
                                    "request={'tenant': 'a', 'roles': ['reader'], 'query': 'python', 'k': 2, "
                                    "'word_budget': 4}\n"
                                    "output={'claims': [{'text': 'Python evidence.', 'source': 'a', 'start': "
                                    "0, 'end': 6, 'quote': 'python'}]}\n"
                                    'import copy\n'
                                    "hidden=copy.deepcopy(output);hidden['claims'][0]['source']='hidden'\n"
                                    'try:\n'
                                    '    rag_response(docs,request,hidden)\n'
                                    'except PermissionError:\n'
                                    '    pass\n'
                                    'else:\n'
                                    "    assert False, 'Reject invalid input before producing a result.'\n"
                                    "small={**request,'word_budget':1}\n"
                                    'try:\n'
                                    '    rag_response(docs,small,output)\n'
                                    'except PermissionError:\n'
                                    '    pass\n'
                                    'else:\n'
                                    "    assert False, 'Reject invalid input before producing a result.'\n"},
                           {'name': 'quote forgery and closed schema rejected',
                            'code': "docs=[{'id': 'a', 'tenant': 'a', 'roles': [], 'text': 'python python'}, "
                                    "{'id': 'b', 'tenant': 'a', 'roles': ['reader'], 'text': 'python "
                                    "tools'}, {'id': 'hidden', 'tenant': 'b', 'roles': [], 'text': 'python "
                                    'python python python python python python python python python python '
                                    'python python python python python python python python python python '
                                    'python python python python python python python python python python '
                                    'python python python python python python python python python python '
                                    "python python python python python python python python python '}]\n"
                                    "request={'tenant': 'a', 'roles': ['reader'], 'query': 'python', 'k': 2, "
                                    "'word_budget': 4}\n"
                                    "output={'claims': [{'text': 'Python evidence.', 'source': 'a', 'start': "
                                    "0, 'end': 6, 'quote': 'python'}]}\n"
                                    'import copy\n'
                                    "forged=copy.deepcopy(output);forged['claims'][0]['quote']='invented'\n"
                                    'try:\n'
                                    '    rag_response(docs,request,forged)\n'
                                    'except ValueError:\n'
                                    '    pass\n'
                                    'else:\n'
                                    "    assert False, 'Reject invalid input before producing a result.'\n"
                                    "extra={**output,'tool':'write'}\n"
                                    'try:\n'
                                    '    rag_response(docs,request,extra)\n'
                                    'except ValueError:\n'
                                    '    pass\n'
                                    'else:\n'
                                    "    assert False, 'Reject invalid input before producing a result.'\n"},
                           {'name': 'empty-context abstention runs without a model',
                            'code': "docs=[{'id': 'a', 'tenant': 'a', 'roles': [], 'text': 'python python'}, "
                                    "{'id': 'b', 'tenant': 'a', 'roles': ['reader'], 'text': 'python "
                                    "tools'}, {'id': 'hidden', 'tenant': 'b', 'roles': [], 'text': 'python "
                                    'python python python python python python python python python python '
                                    'python python python python python python python python python python '
                                    'python python python python python python python python python python '
                                    'python python python python python python python python python python '
                                    "python python python python python python python python python '}]\n"
                                    "request={'tenant': 'a', 'roles': ['reader'], 'query': 'python', 'k': 2, "
                                    "'word_budget': 4}\n"
                                    "output={'claims': [{'text': 'Python evidence.', 'source': 'a', 'start': "
                                    "0, 'end': 6, 'quote': 'python'}]}\n"
                                    "r=rag_response(docs,{**request,'word_budget':0},{'claims':[]})\n"
                                    "assert r['abstained'] is True and r['context_ids']==[] and "
                                    "r['words']==0 and r['answer']=='', 'Abstention must not invent evidence "
                                    "or invoke an unavailable provider.'\n"}]},
 'planproject': {'entry': 'execute_plan',
                 'args': [{'records': {'a': {'x': 1}, 'b': {'x': 99}}, 'receipts': {}},
                          [{'id': 'write', 'tool': 'set', 'args': {'key': 'x', 'value': 5}, 'deps': []},
                           {'id': 'read', 'tool': 'read', 'args': {'key': 'x'}, 'deps': ['write']}],
                          'a',
                          ['records:read', 'records:write'],
                          ['1c1f01da3891873e263172fd2eccb076b3b22265bfbb2d8f57f57a4e5d3558fc'],
                          2],
                 'project': True,
                 'checks': [{'name': 'dependency order and tenant isolation',
                             'code': "state={'records': {'a': {'x': 1}, 'b': {'x': 99}}, 'receipts': {}}\n"
                                     "plan=[{'id': 'write', 'tool': 'set', 'args': {'key': 'x', 'value': 5}, "
                                     "'deps': []}, {'id': 'read', 'tool': 'read', 'args': {'key': 'x'}, "
                                     "'deps': ['write']}]\n"
                                     "approved=['1c1f01da3891873e263172fd2eccb076b3b22265bfbb2d8f57f57a4e5d3558fc']\n"
                                     "r=execute_plan(state,plan,'a',['records:read','records:write'],approved,2)\n"
                                     "assert r['order']==['write','read'] and "
                                     "r['outputs']=={'write':5,'read':5} and r['executed']==2, 'Execute the "
                                     "validated dependency order.'\n"
                                     "assert r['state']['records']['b']['x']==99 and "
                                     "state['records']['a']['x']==1, 'Isolate tenant state and preserve the "
                                     "prior snapshot.'\n"},
                            {'name': 'receipt replay spends no new execution budget',
                             'code': "state={'records': {'a': {'x': 1}, 'b': {'x': 99}}, 'receipts': {}}\n"
                                     "plan=[{'id': 'write', 'tool': 'set', 'args': {'key': 'x', 'value': 5}, "
                                     "'deps': []}, {'id': 'read', 'tool': 'read', 'args': {'key': 'x'}, "
                                     "'deps': ['write']}]\n"
                                     "approved=['1c1f01da3891873e263172fd2eccb076b3b22265bfbb2d8f57f57a4e5d3558fc']\n"
                                     "a=execute_plan(state,plan,'a',['records:read','records:write'],approved,2)\n"
                                     "b=execute_plan(a['state'],plan,'a',['records:read','records:write'],approved,0)\n"
                                     "assert b['executed']==0 and b['outputs']==a['outputs'] and "
                                     "b['state']==a['state'], 'Reuse matching receipts without repeating "
                                     "effects.'\n"},
                            {'name': 'approval and cached access require current authority',
                             'code': "state={'records': {'a': {'x': 1}, 'b': {'x': 99}}, 'receipts': {}}\n"
                                     "plan=[{'id': 'write', 'tool': 'set', 'args': {'key': 'x', 'value': 5}, "
                                     "'deps': []}, {'id': 'read', 'tool': 'read', 'args': {'key': 'x'}, "
                                     "'deps': ['write']}]\n"
                                     "approved=['1c1f01da3891873e263172fd2eccb076b3b22265bfbb2d8f57f57a4e5d3558fc']\n"
                                     'try:\n'
                                     '    '
                                     "execute_plan(state,plan,'a',['records:read','records:write'],[],2)\n"
                                     'except PermissionError:\n'
                                     '    pass\n'
                                     'else:\n'
                                     "    assert False, 'Reject invalid input before producing a result.'\n"
                                     "a=execute_plan(state,plan,'a',['records:read','records:write'],approved,2)\n"
                                     'try:\n'
                                     "    execute_plan(a['state'],plan,'a',[],approved,0)\n"
                                     'except PermissionError:\n'
                                     '    pass\n'
                                     'else:\n'
                                     "    assert False, 'Reject invalid input before producing a result.'\n"},
                            {'name': 'budget and cycles abort before publication',
                             'code': "state={'records': {'a': {'x': 1}, 'b': {'x': 99}}, 'receipts': {}}\n"
                                     "plan=[{'id': 'write', 'tool': 'set', 'args': {'key': 'x', 'value': 5}, "
                                     "'deps': []}, {'id': 'read', 'tool': 'read', 'args': {'key': 'x'}, "
                                     "'deps': ['write']}]\n"
                                     "approved=['1c1f01da3891873e263172fd2eccb076b3b22265bfbb2d8f57f57a4e5d3558fc']\n"
                                     'import copy\n'
                                     'before=copy.deepcopy(state)\n'
                                     'try:\n'
                                     '    '
                                     "execute_plan(state,plan,'a',['records:read','records:write'],approved,1)\n"
                                     'except ValueError:\n'
                                     '    pass\n'
                                     'else:\n'
                                     "    assert False, 'Reject invalid input before producing a result.'\n"
                                     "assert state==before, 'A budget failure must leave the source state "
                                     "unchanged.'\n"
                                     "cycle=[{'id':'a','tool':'read','args':{'key':'x'},'deps':['b']},{'id':'b','tool':'read','args':{'key':'x'},'deps':['a']}]\n"
                                     'try:\n'
                                     "    execute_plan(state,cycle,'a',['records:read'],[],2)\n"
                                     'except ValueError:\n'
                                     '    pass\n'
                                     'else:\n'
                                     "    assert False, 'Reject invalid input before producing a result.'\n"},
                            {'name': 'changed replay conflicts even with new approval',
                             'code': "state={'records': {'a': {'x': 1}, 'b': {'x': 99}}, 'receipts': {}}\n"
                                     "plan=[{'id': 'write', 'tool': 'set', 'args': {'key': 'x', 'value': 5}, "
                                     "'deps': []}, {'id': 'read', 'tool': 'read', 'args': {'key': 'x'}, "
                                     "'deps': ['write']}]\n"
                                     "approved=['1c1f01da3891873e263172fd2eccb076b3b22265bfbb2d8f57f57a4e5d3558fc']\n"
                                     'import copy,hashlib,json\n'
                                     "a=execute_plan(state,plan,'a',['records:read','records:write'],approved,2)\n"
                                     "changed=copy.deepcopy(plan);changed[0]['args']['value']=8\n"
                                     "grant=hashlib.sha256(json.dumps({'tenant':'a',**changed[0]},sort_keys=True,separators=(',',':'),allow_nan=False).encode()).hexdigest()\n"
                                     'try:\n'
                                     '    '
                                     "execute_plan(a['state'],changed,'a',['records:read','records:write'],[grant],2)\n"
                                     'except ValueError:\n'
                                     '    pass\n'
                                     'else:\n'
                                     "    assert False, 'Reject invalid input before producing a "
                                     "result.'\n"}]},
 'batchproject': {'entry': 'batch_schedule',
                  'args': [[{'id': 'a', 'arrival': 0, 'deadline': 5, 'prompt': 2, 'output': 2},
                            {'id': 'b', 'arrival': 0, 'deadline': 5, 'prompt': 1, 'output': 1}],
                           2,
                           6],
                  'project': True,
                  'checks': [{'name': 'ragged continuous batching',
                              'code': "r=batch_schedule([{'id': 'a', 'arrival': 0, 'deadline': 5, 'prompt': "
                                      "2, 'output': 2}, {'id': 'b', 'arrival': 0, 'deadline': 5, 'prompt': "
                                      "1, 'output': 1}],2,6)\n"
                                      "assert r['completed']=={'b':1,'a':2} and r['cancelled']==[] and "
                                      "r['rejected']==[], 'Short requests finish while a longer request "
                                      "continues.'\n"
                                      "assert r['events'][0]['reserved']==6 and "
                                      "r['events'][1]['reserved']==4, 'Release a completed request "
                                      "reservation before the next round.'\n"},
                             {'name': 'waiting deadlines and oversize requests',
                              'code': "rows=[{'id':'a','arrival':0,'deadline':5,'prompt':2,'output':2},{'id':'wait','arrival':0,'deadline':1,'prompt':1,'output':1},{'id':'huge','arrival':0,'deadline':9,'prompt':10,'output':1}]\n"
                                      'r=batch_schedule(rows,2,4)\n'
                                      "assert r['completed']=={'a':2} and r['cancelled']==['wait'] and "
                                      "r['rejected']==['huge'], 'Distinguish queued expiry from permanent "
                                      "oversize rejection.'\n"},
                             {'name': 'idle jump and exact deadline completion',
                              'code': "r=batch_schedule([{'id':'x','arrival':10,'deadline':11,'prompt':0,'output':1}],1,1)\n"
                                      "assert r['completed']=={'x':11} and len(r['events'])==1 and "
                                      "r['events'][0]['tick']==10, 'Skip idle time and permit completion "
                                      "exactly at the deadline.'\n"},
                             {'name': 'invalid output budget rejected',
                              'code': 'try:\n'
                                      '    '
                                      "batch_schedule([{'id':'x','arrival':0,'deadline':2,'prompt':1,'output':0}],1,4)\n"
                                      'except ValueError:\n'
                                      '    pass\n'
                                      'else:\n'
                                      "    assert False, 'Reject invalid input before producing a "
                                      "result.'\n"}]},
 'releaseproject': {'entry': 'evaluate_release',
                    'args': [[{'id': 'a',
                               'category': 'retrieval',
                               'group': 'u1',
                               'quality': 0.5,
                               'safe': True,
                               'cost': 1.0,
                               'latency': 2.0},
                              {'id': 'b',
                               'category': 'authority',
                               'group': 'u1',
                               'quality': 0.5,
                               'safe': True,
                               'cost': 1.0,
                               'latency': 2.0},
                              {'id': 'c',
                               'category': 'retrieval',
                               'group': 'u2',
                               'quality': 0.5,
                               'safe': True,
                               'cost': 1.0,
                               'latency': 2.0},
                              {'id': 'd',
                               'category': 'authority',
                               'group': 'u2',
                               'quality': 0.5,
                               'safe': True,
                               'cost': 1.0,
                               'latency': 2.0}],
                             [{'id': 'a',
                               'category': 'retrieval',
                               'group': 'u1',
                               'quality': 0.6,
                               'safe': True,
                               'cost': 1.0,
                               'latency': 2.0},
                              {'id': 'b',
                               'category': 'authority',
                               'group': 'u1',
                               'quality': 0.6,
                               'safe': True,
                               'cost': 1.0,
                               'latency': 2.0},
                              {'id': 'c',
                               'category': 'retrieval',
                               'group': 'u2',
                               'quality': 0.6,
                               'safe': True,
                               'cost': 1.0,
                               'latency': 2.0},
                              {'id': 'd',
                               'category': 'authority',
                               'group': 'u2',
                               'quality': 0.6,
                               'safe': True,
                               'cost': 1.0,
                               'latency': 2.0}],
                             {'minimum': {'retrieval': 2, 'authority': 2},
                              'max_cost': 2.0,
                              'p95_latency': 3.0,
                              'tolerance': 0.02,
                              'repetitions': 4,
                              'seed': 3}],
                    'project': True,
                    'checks': [{'name': 'paired improvement can pass all declared gates',
                                'code': "baseline=[{'id': 'a', 'category': 'retrieval', 'group': 'u1', "
                                        "'quality': 0.5, 'safe': True, 'cost': 1.0, 'latency': 2.0}, {'id': "
                                        "'b', 'category': 'authority', 'group': 'u1', 'quality': 0.5, "
                                        "'safe': True, 'cost': 1.0, 'latency': 2.0}, {'id': 'c', 'category': "
                                        "'retrieval', 'group': 'u2', 'quality': 0.5, 'safe': True, 'cost': "
                                        "1.0, 'latency': 2.0}, {'id': 'd', 'category': 'authority', 'group': "
                                        "'u2', 'quality': 0.5, 'safe': True, 'cost': 1.0, 'latency': 2.0}]\n"
                                        "candidate=[{'id': 'a', 'category': 'retrieval', 'group': 'u1', "
                                        "'quality': 0.6, 'safe': True, 'cost': 1.0, 'latency': 2.0}, {'id': "
                                        "'b', 'category': 'authority', 'group': 'u1', 'quality': 0.6, "
                                        "'safe': True, 'cost': 1.0, 'latency': 2.0}, {'id': 'c', 'category': "
                                        "'retrieval', 'group': 'u2', 'quality': 0.6, 'safe': True, 'cost': "
                                        "1.0, 'latency': 2.0}, {'id': 'd', 'category': 'authority', 'group': "
                                        "'u2', 'quality': 0.6, 'safe': True, 'cost': 1.0, 'latency': 2.0}]\n"
                                        "policy={'minimum': {'retrieval': 2, 'authority': 2}, 'max_cost': "
                                        "2.0, 'p95_latency': 3.0, 'tolerance': 0.02, 'repetitions': 30, "
                                        "'seed': 3}\n"
                                        'r=evaluate_release(baseline,candidate,policy)\n'
                                        "assert r['promote'] is True and r['reasons']==[] and "
                                        "abs(r['quality']['estimate']-.1)<1e-12, 'Combine paired coverage, "
                                        "uncertainty and hard constraints.'\n"
                                        "assert r['coverage']=={'authority':2,'retrieval':2} and "
                                        "r['p95_latency']==2, 'Keep category and tail-latency evidence.'\n"},
                               {'name': 'hard failures cannot hide behind average quality',
                                'code': "baseline=[{'id': 'a', 'category': 'retrieval', 'group': 'u1', "
                                        "'quality': 0.5, 'safe': True, 'cost': 1.0, 'latency': 2.0}, {'id': "
                                        "'b', 'category': 'authority', 'group': 'u1', 'quality': 0.5, "
                                        "'safe': True, 'cost': 1.0, 'latency': 2.0}, {'id': 'c', 'category': "
                                        "'retrieval', 'group': 'u2', 'quality': 0.5, 'safe': True, 'cost': "
                                        "1.0, 'latency': 2.0}, {'id': 'd', 'category': 'authority', 'group': "
                                        "'u2', 'quality': 0.5, 'safe': True, 'cost': 1.0, 'latency': 2.0}]\n"
                                        "candidate=[{'id': 'a', 'category': 'retrieval', 'group': 'u1', "
                                        "'quality': 0.6, 'safe': True, 'cost': 1.0, 'latency': 2.0}, {'id': "
                                        "'b', 'category': 'authority', 'group': 'u1', 'quality': 0.6, "
                                        "'safe': True, 'cost': 1.0, 'latency': 2.0}, {'id': 'c', 'category': "
                                        "'retrieval', 'group': 'u2', 'quality': 0.6, 'safe': True, 'cost': "
                                        "1.0, 'latency': 2.0}, {'id': 'd', 'category': 'authority', 'group': "
                                        "'u2', 'quality': 0.6, 'safe': True, 'cost': 1.0, 'latency': 2.0}]\n"
                                        "policy={'minimum': {'retrieval': 2, 'authority': 2}, 'max_cost': "
                                        "2.0, 'p95_latency': 3.0, 'tolerance': 0.02, 'repetitions': 30, "
                                        "'seed': 3}\n"
                                        'import copy\n'
                                        'bad=copy.deepcopy(candidate);bad[0].update(safe=False,cost=20,latency=10)\n'
                                        'r=evaluate_release(baseline,bad,policy)\n'
                                        "assert r['promote'] is False and "
                                        "r['reasons']==['safety','cost','latency'], 'Report every "
                                        "independent hard failure.'\n"},
                               {'name': 'quality regression and insufficient category coverage',
                                'code': "baseline=[{'id': 'a', 'category': 'retrieval', 'group': 'u1', "
                                        "'quality': 0.5, 'safe': True, 'cost': 1.0, 'latency': 2.0}, {'id': "
                                        "'b', 'category': 'authority', 'group': 'u1', 'quality': 0.5, "
                                        "'safe': True, 'cost': 1.0, 'latency': 2.0}, {'id': 'c', 'category': "
                                        "'retrieval', 'group': 'u2', 'quality': 0.5, 'safe': True, 'cost': "
                                        "1.0, 'latency': 2.0}, {'id': 'd', 'category': 'authority', 'group': "
                                        "'u2', 'quality': 0.5, 'safe': True, 'cost': 1.0, 'latency': 2.0}]\n"
                                        "candidate=[{'id': 'a', 'category': 'retrieval', 'group': 'u1', "
                                        "'quality': 0.6, 'safe': True, 'cost': 1.0, 'latency': 2.0}, {'id': "
                                        "'b', 'category': 'authority', 'group': 'u1', 'quality': 0.6, "
                                        "'safe': True, 'cost': 1.0, 'latency': 2.0}, {'id': 'c', 'category': "
                                        "'retrieval', 'group': 'u2', 'quality': 0.6, 'safe': True, 'cost': "
                                        "1.0, 'latency': 2.0}, {'id': 'd', 'category': 'authority', 'group': "
                                        "'u2', 'quality': 0.6, 'safe': True, 'cost': 1.0, 'latency': 2.0}]\n"
                                        "policy={'minimum': {'retrieval': 2, 'authority': 2}, 'max_cost': "
                                        "2.0, 'p95_latency': 3.0, 'tolerance': 0.02, 'repetitions': 30, "
                                        "'seed': 3}\n"
                                        'import copy\n'
                                        "bad=[{**row,'quality':.3} for row in candidate]\n"
                                        "p=copy.deepcopy(policy);p['minimum']['authority']=3\n"
                                        'r=evaluate_release(baseline,bad,p)\n'
                                        "assert r['reasons']==['coverage','quality'], 'Missing category "
                                        "support and negative group effects are separate failures.'\n"},
                               {'name': 'missing paired case is not a better score',
                                'code': "baseline=[{'id': 'a', 'category': 'retrieval', 'group': 'u1', "
                                        "'quality': 0.5, 'safe': True, 'cost': 1.0, 'latency': 2.0}, {'id': "
                                        "'b', 'category': 'authority', 'group': 'u1', 'quality': 0.5, "
                                        "'safe': True, 'cost': 1.0, 'latency': 2.0}, {'id': 'c', 'category': "
                                        "'retrieval', 'group': 'u2', 'quality': 0.5, 'safe': True, 'cost': "
                                        "1.0, 'latency': 2.0}, {'id': 'd', 'category': 'authority', 'group': "
                                        "'u2', 'quality': 0.5, 'safe': True, 'cost': 1.0, 'latency': 2.0}]\n"
                                        "candidate=[{'id': 'a', 'category': 'retrieval', 'group': 'u1', "
                                        "'quality': 0.6, 'safe': True, 'cost': 1.0, 'latency': 2.0}, {'id': "
                                        "'b', 'category': 'authority', 'group': 'u1', 'quality': 0.6, "
                                        "'safe': True, 'cost': 1.0, 'latency': 2.0}, {'id': 'c', 'category': "
                                        "'retrieval', 'group': 'u2', 'quality': 0.6, 'safe': True, 'cost': "
                                        "1.0, 'latency': 2.0}, {'id': 'd', 'category': 'authority', 'group': "
                                        "'u2', 'quality': 0.6, 'safe': True, 'cost': 1.0, 'latency': 2.0}]\n"
                                        "policy={'minimum': {'retrieval': 2, 'authority': 2}, 'max_cost': "
                                        "2.0, 'p95_latency': 3.0, 'tolerance': 0.02, 'repetitions': 30, "
                                        "'seed': 3}\n"
                                        'try:\n'
                                        '    evaluate_release(baseline,candidate[:-1],policy)\n'
                                        'except ValueError:\n'
                                        '    pass\n'
                                        'else:\n'
                                        "    assert False, 'Reject invalid input before producing a "
                                        "result.'\n"},
                               {'name': 'paired identity and outcome type are enforced',
                                'code': "baseline=[{'id': 'a', 'category': 'retrieval', 'group': 'u1', "
                                        "'quality': 0.5, 'safe': True, 'cost': 1.0, 'latency': 2.0}, {'id': "
                                        "'b', 'category': 'authority', 'group': 'u1', 'quality': 0.5, "
                                        "'safe': True, 'cost': 1.0, 'latency': 2.0}, {'id': 'c', 'category': "
                                        "'retrieval', 'group': 'u2', 'quality': 0.5, 'safe': True, 'cost': "
                                        "1.0, 'latency': 2.0}, {'id': 'd', 'category': 'authority', 'group': "
                                        "'u2', 'quality': 0.5, 'safe': True, 'cost': 1.0, 'latency': 2.0}]\n"
                                        "candidate=[{'id': 'a', 'category': 'retrieval', 'group': 'u1', "
                                        "'quality': 0.6, 'safe': True, 'cost': 1.0, 'latency': 2.0}, {'id': "
                                        "'b', 'category': 'authority', 'group': 'u1', 'quality': 0.6, "
                                        "'safe': True, 'cost': 1.0, 'latency': 2.0}, {'id': 'c', 'category': "
                                        "'retrieval', 'group': 'u2', 'quality': 0.6, 'safe': True, 'cost': "
                                        "1.0, 'latency': 2.0}, {'id': 'd', 'category': 'authority', 'group': "
                                        "'u2', 'quality': 0.6, 'safe': True, 'cost': 1.0, 'latency': 2.0}]\n"
                                        "policy={'minimum': {'retrieval': 2, 'authority': 2}, 'max_cost': "
                                        "2.0, 'p95_latency': 3.0, 'tolerance': 0.02, 'repetitions': 30, "
                                        "'seed': 3}\n"
                                        'import copy\n'
                                        "bad=copy.deepcopy(candidate);bad[0]['group']='another-user'\n"
                                        'try:\n'
                                        '    evaluate_release(baseline,bad,policy)\n'
                                        'except ValueError:\n'
                                        '    pass\n'
                                        'else:\n'
                                        "    assert False, 'Reject invalid input before producing a "
                                        "result.'\n"
                                        "bad=copy.deepcopy(candidate);bad[0]['safe']=1\n"
                                        'try:\n'
                                        '    evaluate_release(baseline,bad,policy)\n'
                                        'except ValueError:\n'
                                        '    pass\n'
                                        'else:\n'
                                        "    assert False, 'Reject invalid input before producing a "
                                        "result.'\n"}]}}


def _check(namespace, code):
    exec(compile(code, '<project-check>', 'exec'), dict(namespace))


def _draw(view, entry, project):
    if project and view.function != entry:
        return None
    view.locals = {key: value.tolist() if hasattr(value, 'tolist') else value
                   for key, value in view.locals.items()}
    return render(view)


for lab_id, spec in SPECS.items():
    def trace(namespace, recorder, spec=spec):
        recorder.context = spec['entry'] + (' · orchestration' if spec['project'] else ' · learner code')
        recorder.watch(lambda: namespace[spec['entry']](*copy.deepcopy(spec['args'])),
                       lambda view: _draw(view, spec['entry'], spec['project']))
        return ''
    checks = [(row['name'], lambda namespace, code=row['code']: _check(namespace, code))
              for row in spec['checks']]
    register(lab_id, {'practice': {'file': lab_id+'.py',
             'names': [(spec['entry'], 'a function '+spec['entry'])],
             'trace': trace, 'checks': checks}})
