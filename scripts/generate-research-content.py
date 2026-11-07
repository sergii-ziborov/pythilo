#!/usr/bin/env python3
"""Generate the linked senior CPU research courses from authored contracts/code."""
import ast
import json
import pprint
from pathlib import Path

ROOT=Path(__file__).resolve().parent.parent
RUNTIME=ROOT/'Pythilo/PythonRuntime/pythilo_runtime'
LABS=RUNTIME/'labcode'

def main():
    rows=json.loads((ROOT/'scripts/research-content/labs.json').read_text())
    assert len(rows)==16 and len({r['id'] for r in rows})==16
    catalog_file=LABS/'catalog-expansion.json'
    topic_file=LABS/'lab-topics.json'
    catalog=json.loads(catalog_file.read_text())
    topics=json.loads(topic_file.read_text())
    ids={r['id'] for r in rows}
    catalog=[r for r in catalog if r['id'] not in ids]
    definitions=[('robust-training','Robust training mechanisms','Machine learning'),
                 ('robustness-projects','Robustness & uncertainty projects','Machine learning'),
                 ('alignment-mechanisms','Alignment & sparse inference','Artificial intelligence'),
                 ('alignment-projects','Preference & expert projects','Artificial intelligence')]
    for id,title,section in definitions:
        topic=dict(id=id,title=title,section=section)
        topics['topics']=[t for t in topics['topics'] if t['id']!=id]+[topic]
    courses={False:dict(id='robust-ml-engineering',title='Robust training & uncertainty engineering',kind='path',summary='Own SAM, gradient surgery, Group DRO, heteroscedastic likelihood and fake quantization; train, select, export and audit two complete CPU experiments.',lessons=[]),
             True:dict(id='alignment-engineering',title='Preference optimization & sparse AI engineering',kind='path',summary='Differentiate DPO and grouped policy objectives, route sparse experts, preserve speculative target mass, enforce grammars and train two complete local CPU projects.',lessons=[])}
    specs={}
    for row in rows:
        id=row['id'];source=(LABS/f'{id}.practice.answer.py').read_text()
        tree=ast.parse(source)
        entry=next(n for n in tree.body if isinstance(n,ast.FunctionDef) and n.name==row['entry'])
        lines=source.splitlines(keepends=True)
        starter=''.join(lines[:entry.body[0].lineno-1])+f'    # TODO: implement {row["entry"]} under the declared contract.\n    return None\n'+''.join(lines[entry.end_lineno:])
        if row['project']:
            demo=next(n for n in ast.parse(starter).body if isinstance(n,ast.If) and '__name__' in ast.unparse(n.test))
            starter=''.join(starter.splitlines(keepends=True)[:demo.lineno-1])+"if __name__=='__main__':\n    print('Implement run_experiment, then run the lesson checks.')\n"
        (LABS/f'{id}.practice.starter.py').write_text(starter)
        lesson_id=('project-' if row['project'] else 'research-')+id
        body=('# '+row['title']+'\n\n'+row['concept']+'\n\n## Prepare offline\n\n'
              'Choose Download entire course or Download entire category first. After completion, code and checks run locally on CPU. The independent example needs no account, remote service or API key.\n\n'
              '```python\n'+row['example']+'\n```\n\n## Review the evidence\n\n'+row['review']+'\n')
        lesson=dict(id=lesson_id,title=row['title'],level='Senior',minutes=90 if row['project'] else 50,
                    body=body,task=row['task'],starter=starter,solution=source,checks=row['checks'],
                    hints=['Make tensor ownership, masking and normalization explicit before optimizing.',
                           'Use the independent contracts to audit gradients and failure paths; plausible scalar output is insufficient.',
                           'Keep selection and calibration evidence separate from final test labels.'],
                    explanation=row['review']+' Reference: '+row['sourceURL']+' The executable fixture is a controlled CPU exercise; passing it does not establish production model quality.')
        courses[row['ai']]['lessons'].append(lesson)
        section='Artificial intelligence' if row['ai'] else 'Machine learning'
        topic=('alignment-projects' if row['project'] else 'alignment-mechanisms') if row['ai'] else ('robustness-projects' if row['project'] else 'robust-training')
        catalog.append(dict(id=id,title=row['title'],summary=row['task'],symbol='brain',tint='violet' if row['ai'] else 'blue',section=section,
                            variants=[dict(id='practice',title='Project' if row['project'] else 'Mechanism',prompt=row['task'],file=id+'.py',scales=False)],
                            lessons=[lesson_id],runtime='pytorch',idea=row['concept']))
        topics['assignments'][id]=topic
        specs[id]={k:row[k] for k in ('entry','fixture','checks','project')}
    for ai,number in [(False,37),(True,38)]:
        assert len(courses[ai]['lessons'])==8
        (ROOT/'Pythilo/Resources/Courses'/f'{number}-{courses[ai]["id"]}.json').write_text(json.dumps(courses[ai],ensure_ascii=False,indent=2)+'\n')
    catalog_file.write_text(json.dumps(catalog,ensure_ascii=False,indent=2)+'\n')
    topic_file.write_text(json.dumps(topics,ensure_ascii=False,indent=2)+'\n')
    support='''
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
'''
    (RUNTIME/'labs_research.py').write_text('"""Generated senior CPU Labs; see scripts/research-content/."""\nSPECS = '+pprint.pformat(specs,sort_dicts=False,width=105)+'\n'+support)
    print('Generated 16 linked senior Labs, 16 lessons, 4 complete experiments and 80 independent contracts.')

if __name__=='__main__':main()
