"""Additional labs shared by iOS and the browser; frames come from learner locals."""
import copy
import math
from collections import deque
from .labs_engine import array, grid, plot, register, scatter, short, variables


def render(view):
    # Comprehension frames repeat the same source line; replay the enclosing statement.
    if view.function.startswith("<"):
        return None
    panels = []
    pairs = []
    for name, value in view.locals.items():
        if name.startswith('_') or callable(value) or hasattr(value, '__spec__'):
            continue
        if isinstance(value, (list, tuple, deque)) and len(value) <= 60:
            if all(isinstance(item, (int, float, str, bool)) for item in value):
                panels.append(array(list(value), title=name))
            elif value and all(isinstance(row, (list, tuple)) and len(row) <= 16 and all(isinstance(v, (int,float)) for v in row) for row in value) and len(value) <= 16:
                panels.append(grid(value, title=name))
            elif name not in ('xs', 'ys'):
                pairs.append((name, short(value, 100)))
        elif isinstance(value, dict) and len(value) <= 24:
            panels.append(variables(list(value.items()), title=name))
        elif isinstance(value, (int, float, str, bool)) or value is None:
            pairs.append((name, value))
    xs, ys = view.locals.get('xs'), view.locals.get('ys')
    w, b = view.locals.get('w'), view.locals.get('b')
    if isinstance(xs, list) and isinstance(ys, list) and xs and len(xs) == len(ys) and all(isinstance(v, (int,float)) for v in xs + ys):
        lines = [[min(xs), w*min(xs)+b, max(xs), w*max(xs)+b]] if isinstance(w,(int,float)) and isinstance(b,(int,float)) and all(math.isfinite(v) for v in (w,b)) else []
        panels.insert(0, scatter([[x,y,0] for x,y in zip(xs,ys)], lines=lines, title='Samples and current score line'))
    history = view.locals.get('history')
    if isinstance(history, list) and history and all(isinstance(v,(int,float)) and math.isfinite(v) for v in history):
        panels.append(plot([('history', list(enumerate(history)))], title='Training diagnostic'))
    if view.event == 'return':
        pairs.append(('returned', short(view.value, 100)))
    if pairs:
        panels.append(variables(pairs[:20], title=view.function))
    return (panels, f'After line {view.line}: {view.text}') if panels else None


def topo_check(got, args):
    graph = args[0]
    if got is None or not isinstance(got, list) or len(got) != len(graph) or set(got) != set(graph):
        return 'Return every node once in a valid order.'
    position = {node:i for i,node in enumerate(got)}
    return None if all(position[a] < position[b] for a,targets in graph.items() for b in targets) else 'A dependent task appears before its prerequisite.'


def near(expected):
    def check(got, _):
        if not isinstance(got, (list,tuple)) or len(got) != len(expected):
            return f'Expected parameters {expected}, got {short(got)}.'
        return None if all(isinstance(a,(int,float)) and math.isfinite(a) and abs(a-b)<1e-8 for a,b in zip(got,expected)) else f'Expected parameters {expected}, got {short(got)}.'
    return check


def trained(got, args):
    if not isinstance(got,(list,tuple)) or len(got)!=2 or not all(isinstance(v,(int,float)) and math.isfinite(v) for v in got):
        return 'Return two finite parameters (w, b).'
    xs,ys=args[:2]
    return None if sum((got[0]*x+got[1]-y)**2 for x,y in zip(xs,ys))/len(xs)<0.02 else 'The fitted line still has mean squared error above 0.02.'


def classified(got, args):
    if not isinstance(got,(list,tuple)) or len(got)!=2 or not all(isinstance(v,(int,float)) and math.isfinite(v) for v in got):
        return 'Return two finite parameters (w, b).'
    return None if all((got[0]*x+got[1]>=0)==bool(y) for x,y in zip(*args[:2])) else 'The learned score boundary does not separate the training labels.'


# (check name, arguments, exact expected value or validator)
CASES = {
 'prefix': ('range_sums', [
  ('mixed signs and ranges', ([3,-2,5,4],[(0,4),(1,3),(2,2)]), [10,3,0]),
  ('empty input', ([],[(0,0)]), [0]), ('zero and negative totals', ([-2,2,-1],[(0,2),(1,3)]), [0,1])]),
 'monostack': ('warmer_days', [
  ('several pending days', ([20,18,22,21,23],), [2,1,2,1,0]),
  ('equal is not warmer', ([5,5,6],), [2,1,0]), ('empty and decreasing', ([],), [])]),
 'topological': ('task_order', [
  ('dependency order', ({'ship':[],'build':['ship'],'test':['ship'],'parse':['build','test']},), topo_check),
  ('cycle', ({'a':['b'],'b':['a']},), None), ('empty graph', ({},), [])]),
 'knapsack': ('pack', [
  ('best combination', ([(2,3),(3,4),(4,5)],5), 7),
  ('take each item once', ([(2,3)],4), 3), ('zero capacity', ([(1,9)],0), 0), ('no items', ([],4),0)]),
 'bellmanford': ('shortest', [
  ('negative edge', (5,[(0,1,4),(0,2,5),(1,2,-2),(2,3,3)],0), [0,4,2,5,float('inf')]),
  ('reachable negative cycle', (3,[(0,1,1),(1,2,-3),(2,1,1)],0), None),
  ('unreachable cycle ignored', (3,[(1,2,-3),(2,1,1)],0), [0,float('inf'),float('inf')]),
  ('single node', (1,[],0), [0])]),
 'editrows': ('distance', [
  ('different prefixes', ('kitten','sitting'), 3), ('empty left', ('','abc'),3),
  ('identical', ('banana','banana'),0), ('empty right', ('abc',''),3)]),
 'linearfit': ('fit', [
  ('one step uses mean gradient', ([1,2],[2,4],1,0.1), near((1.0,0.6))),
  ('learn a line', ([-2,-1,0,1,2],[-3,-1,1,3,5],200,0.05), trained),
  ('zero steps', ([1],[3],0,0.1), near((0.0,0.0)))]),
 'logistic': ('fit', [
  ('one step with cross-entropy gradient', ([-1,1],[0,1],1,0.2), near((0.1,0.0))),
  ('learn separated labels', ([-2,-1,1,2],[0,0,1,1],100,0.1), classified),
  ('learn reversed labels', ([-2,-1,1,2],[1,1,0,0],100,0.1), classified)]),
 'neighbors': ('nearest_label', [
  ('nearest label', ([[0,0],[4,4],[5,4]],[0,1,1],[4,3],2),1),
  ('stable equal distances', ([[0],[2]],[2,1],[1],1),2),
  ('vote ties choose smaller label', ([[0],[2]],[2,1],[1],2),1), ('k larger than data', ([[0]],[3],[2],9),3)]),
 'stump': ('best_split', [
  ('pure groups', ([1,2,3,4],[0,0,1,1]),2.5),
  ('tie chooses lower threshold', ([1,2,3],[0,1,0]),1.5),
  ('constant feature', ([2,2],[0,1]),None), ('empty data', ([],[]),None)]),
}


def evaluate(function, case):
    name,args,expected=case
    args=copy.deepcopy(args)
    got=function(*args)
    if callable(expected):
        return expected(got, args)
    return None if got == expected else f'{name}: returned {short(got,90)}, expected {short(expected,90)}.'


for lab_id,(name,cases) in CASES.items():
    def trace(ns,rec,name=name,cases=cases,lab_id=lab_id):
        args=copy.deepcopy(cases[0][1])
        if lab_id in ('linearfit','logistic'):
            args=(*args[:2],15,0.1)
        rec.context=f'{name}{short(args,160)}'
        got=rec.watch(lambda: ns[name](*args),render)
        return ''
    checks=[(case[0],lambda ns,case=case,name=name: evaluate(ns[name],case)) for case in cases]
    register(lab_id,{'practice':{'file':lab_id+'.py','names':[(name,'a function '+name)],'trace':trace,'checks':checks}})
