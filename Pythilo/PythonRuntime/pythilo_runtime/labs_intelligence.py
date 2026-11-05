"""ML and AI experiments. Reference cases are independent of learner code."""
import copy
import math
from .labs_engine import register, short
from .labs_extended import render

def equivalent(actual, expected):
    if isinstance(expected, (list, tuple)):
        return isinstance(actual, (list, tuple)) and len(actual) == len(expected) and all(equivalent(a,b) for a,b in zip(actual,expected))
    if isinstance(expected, (int,float)) and not isinstance(expected,bool):
        return isinstance(actual, (int,float)) and math.isfinite(actual) and math.isclose(actual, expected, rel_tol=1e-6, abs_tol=1e-7)
    return actual == expected

def evaluate(function, case):
    title, args, expected = case
    got = function(*copy.deepcopy(args))
    return None if equivalent(got,expected) else f'{title}: returned {short(got,100)}, expected {short(expected,100)}.'

CASES = {'standardize': ('normalize',
                 [('reuse training statistics', ([0, 2], [1, 3]), [0, 2]),
                  ('constant column', ([5, 5], [5, 8]), [0, 3]),
                  ('empty validation', ([2], []), [])]),
 'confusion': ('confusion',
               [('off-diagonal errors', ([0, 0, 1, 1], [0, 1, 1, 1], 2), [[1, 1], [0, 2]]),
                ('unseen class', ([2, 0], [1, 0], 3), [[1, 0, 0], [0, 0, 0], [0, 1, 0]]),
                ('no samples', ([], [], 2), [[0, 0], [0, 0]])]),
 'precisionrecall': ('prf',
                     [('different denominators',
                       ([1, 1, 0, 0], [1, 0, 1, 1]),
                       [0.3333333333333333, 0.5, 0.4]),
                      ('no predicted positives', ([1, 0], [0, 0]), [0, 0, 0]),
                      ('perfect', ([0, 1], [0, 1]), [1, 1, 1])]),
 'threshold': ('choose_threshold',
               [('validation choice', ([0.1, 0.4, 0.6, 0.9], [0, 1, 1, 1], [0.3, 0.5, 0.8]), 0.3),
                ('deterministic tie', ([0.8], [1], [0.5, 0.2]), 0.2),
                ('zero positives', ([0.1], [0], [0.5, 0.7]), 0.5)]),
 'crossvalidation': ('folds',
                     [('uneven split', (5, 2), [([3, 4], [0, 1, 2]), ([0, 1, 2], [3, 4])]),
                      ('leave one out', (3, 3), [([1, 2], [0]), ([0, 2], [1]), ([0, 1], [2])]),
                      ('single fold', (2, 1), [([], [0, 1])])]),
 'ridge': ('ridge',
           [('shrink slope', ([0, 2], [1, 5], 2), [1, 2]),
            ('ordinary least squares', ([0, 2], [1, 5], 0), [2, 1]),
            ('constant feature', ([3, 3], [2, 4], 0), [0, 3])]),
 'gradientcheck': ('gradient_error',
                   [('correct derivative', (2, 0.001, 10), 1e-06),
                    ('wrong sign', (1, 0.001, -1), 2.000001),
                    ('zero point', (0, 0.001, -2), 1e-06)]),
 'adam': ('adam_step',
          [('bias-corrected first step',
            (1, 2, 0, 0, 1, 0.1, 0.9, 0.999, 1e-08),
            [0.9000000005, 0.2, 0.004]),
           ('zero gradient', (3, 0, 0, 0, 1, 0.1, 0.9, 0.99, 1e-08), [3, 0, 0]),
           ('no momentum', (0, -2, 0, 0, 1, 0.2, 0, 0, 1), [0.13333333333333333, -2, 4])]),
 'minibatch': ('epoch',
               [('sequential updates', ([1, 2], [2, 4], 0, 0.1, 1), 1.68),
                ('full batch', ([1, 2], [2, 4], 0, 0.1, 2), 1),
                ('short last batch', ([1, 1, 1], [2, 2, 2], 0, 0.1, 2), 0.72),
                ('empty epoch', ([], [], 3, 0.1, 2), 3)]),
 'naivebayes': ('log_scores',
                [('smoothed likelihood',
                  ([['red', 'red'], ['blue']], [0, 1], ['red'], ['red', 'blue']),
                  [-0.9808292530117262, -1.791759469228055]),
                 ('unknown ignored',
                  ([['a'], ['b']], [0, 1], ['?'], ['a', 'b']),
                  [-0.6931471805599453, -0.6931471805599453]),
                 ('repeated query',
                  ([['a'], ['b']], [0, 1], ['a', 'a'], ['a', 'b']),
                  [-1.5040773967762742, -2.8903717578961645])]),
 'pca': ('principal_axis',
         [('diagonal cloud',
           ([[0, 0], [1, 1], [2, 2]], 3),
           [0.7071067811865476, 0.7071067811865476]),
          ('horizontal cloud', ([[-2, 1], [0, 1], [2, 1]], 3), [1, 0]),
          ('orthogonal seed', ([[-1, 1], [1, -1]], 3), [0.7071067811865476, -0.7071067811865476]),
          ('zero variance', ([[3, 4], [3, 4]], 3), [0, 0])]),
 'silhouette': ('silhouette',
                [('separated pairs', ([0, 1, 9, 10], [0, 0, 1, 1]), 0.8885448916408669),
                 ('singletons', ([0, 4], [0, 1]), 0),
                 ('coincident points', ([0, 0, 0, 0], [0, 0, 1, 1]), 0)]),
 'softmax': ('softmax',
             [('large equal logits', ([1000, 1000], 1), [0.5, 0.5]),
              ('temperature changes spread', ([0, 2], 2), [0.2689414213699951, 0.7310585786300049]),
              ('empty and single', ([], 1), [])]),
 'attention': ('attend',
               [('unequal relevance',
                 ([1], [[0], [1]], [[2, 0], [0, 2]]),
                 [0.5378828427399902, 1.4621171572600098]),
                ('uniform query', ([0, 0], [[1, 2], [3, 4]], [[2], [4]]), [3]),
                ('scale and overflow', ([1000, 1000], [[1, 1]], [[7, 8]]), [7, 8])]),
 'causalmask': ('causal_weights',
                [('future hidden', ([[0, 9], [0, 0]],), [[1, 0], [0.5, 0.5]]),
                 ('single token', ([[1000]],), [[1]]),
                 ('large future ignored',
                  ([[0, 10000, 10000], [0, 0, 10000], [0, 0, 0]],),
                  [[1, 0, 0],
                   [0.5, 0.5, 0],
                   [0.3333333333333333, 0.3333333333333333, 0.3333333333333333]])]),
 'nucleus': ('nucleus',
             [('smallest prefix',
               ([0.1, 0.6, 0.3], 0.8),
               [[1, 0.6666666666666666], [2, 0.3333333333333333]]),
              ('tie by index', ([0.5, 0.5], 0.5), [[0, 1]]),
              ('full mass', ([0.2, 0.8, 0], 1), [[1, 0.8], [0, 0.2]])]),
 'beamsearch': ('beam_search',
                [('alternative beats greedy',
                  ({'s': [('a', 0.6), ('b', 0.4)], 'a': [('x', 0.5), ('z', 0.5)], 'b': [('y', 1)]},
                   's',
                   2,
                   2),
                  ['s', 'b', 'y']),
                 ('width one', ({'s': [('b', 0.4), ('a', 0.6)]}, 's', 1, 1), ['s', 'a']),
                 ('zero steps', ({}, 's', 0, 2), ['s'])]),
 'bpe': ('merge_pair',
         [('repeated pair', (['l', 'o', 'l', 'o', 'w'],), [['lo', 'lo', 'w'], ['l', 'o']]),
          ('overlapping occurrences', (['a', 'a', 'a'],), [['aa', 'a'], ['a', 'a']]),
          ('no pair', (['x'],), [['x'], None])]),
 'retrieval': ('rank_vectors',
               [('length invariant', ([1, 0], [[0, 1], [10, 0], [1, 0], [-1, 0]], 3), [1, 2, 0]),
                ('zero query ties', ([0, 0], [[2, 3], [0, 0]], 2), [0, 1]),
                ('no requested results', ([1], [[1]], 0), [])]),
 'layernorm': ('layer_norm',
               [('gain and bias', ([1, 3], [2, 2], [1, 1], 3), [0, 2]),
                ('constant values', ([5, 5], [3, 4], [1, 2], 0.001), [1, 2]),
                ('one feature', ([7], [2], [3], 1e-05), [3])])}

for lab_id,(name,cases) in CASES.items():
    def trace(ns,rec,name=name,cases=cases):
        args = copy.deepcopy(cases[0][1])
        rec.context = f'{name}{short(args,160)}'
        rec.watch(lambda: ns[name](*args), render)
        return ''
    checks = [(case[0],lambda ns,case=case,name=name: evaluate(ns[name],case)) for case in cases]
    register(lab_id, {'practice': {'file':lab_id+'.py', 'names':[(name,'a function '+name)], 'trace':trace, 'checks':checks}})
