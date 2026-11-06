#!/usr/bin/env python3
"""Keep six local project recipes, linked lessons and native Lab contracts in sync."""
import json
from pathlib import Path
import pprint

ROOT = Path(__file__).resolve().parent.parent
PYTHON = ROOT / 'Pythilo/PythonRuntime'
LABS = PYTHON / 'pythilo_runtime/labcode'
PROJECTS = [
    ('full', 'torchbertfull', 'Fine-tune pretrained BERT', 'Machine learning',
     'Update the complete pretrained encoder; select a checkpoint on validation macro-F1 and evaluate the test once.',
     'Full fine-tuning updates all 4.39 million classifier parameters. The random classification head is initialized once, while the encoder starts from Google’s published BERT-Tiny weights. AdamW state is substantially larger than the exported model because each trainable parameter receives optimizer moments. This project uses real positive and negative review sentences rather than a synthetic token rule.'),
    ('lora', 'torchbertlora', 'Train query/value LoRA adapters', 'Artificial intelligence',
     'Freeze BERT, insert rank-four Q/V adapters, train the classifier and export the exact base/tokenizer identity.',
     'A small adapter is meaningful only together with its exact base model and tokenizer. Insert LoRA into the query and value projections in both encoder layers, freeze all original encoder weights, and optimize only A, B and the classification head. Zero-initialize B so the adapter initially preserves the pretrained projection. The project proves that frozen parameters remain unchanged and reloads the adapter for numerical comparison.'),
    ('domain', 'torchbertdomain', 'Transfer sentiment across domains', 'Machine learning',
     'Train on Amazon and Yelp, select on their validation partition, then report untouched IMDb performance.',
     'An IID split does not measure domain transfer. Keep every IMDb review group out of training and validation. Normalize duplicate identities across all three sources before assigning a split; a repeated sentence that occurs in IMDb belongs only to the held-out domain. Select the checkpoint using Amazon/Yelp validation rows. Report IMDb results as a domain-shift measurement without tuning against those labels.'),
    ('compare', 'torchbertcompare', 'Compare full tuning and LoRA budgets', 'Machine learning',
     'Compare identical splits and step budgets; measure trainable tensors, AdamW state and export bytes.',
     'A fair comparison records what is held constant and what differs. Both methods start from the same pretrained revision and classification head, see the same row order, use the same sequence length and receive the same number of optimizer steps. The method-specific learning rates are declared in the report. Parameter bytes, AdamW tensor bytes and file sizes answer different questions; none is a measurement of peak resident memory.'),
    ('resume', 'torchbertresume', 'Resume real transformer training exactly', 'Artificial intelligence',
     'Interrupt LoRA mid-epoch, save AdamW and both RNGs, restore a fresh process state and match the uninterrupted trajectory.',
     'Restoring model weights alone is not an exact continuation. AdamW moments and step counters affect the next update; dropout consumes the Torch RNG; the sampler owns a Python RNG, an explicit permutation and a cursor. Save these together at an optimizer-step boundary. Construct a fresh model and optimizer, restore every component, then compare every final tensor and every observed loss against an uninterrupted CPU run.'),
    ('merge', 'torchbertmerge', 'Merge and deploy a trained BERT adapter', 'Artificial intelligence',
     'Train and reload an adapter, merge Q/V deltas, export the complete classifier and check held-out logits after reload.',
     'An adapter artifact is small because it omits the frozen base. A merged classifier contains the complete encoder again. Merge W plus alpha/r times B@A in evaluation mode, remove the LoRA modules, and compare actual inference logits. Export the resulting state and load it into a fresh ordinary classifier. This demonstrates a real deployment transformation; it does not imply quantization, acceleration or a smaller full-model file.'),
]


def checks(name):
    setup = ("import tempfile, math, json\nfrom pathlib import Path\nimport torch\nimport pythilo_finetune as ft\n"
             "_work = tempfile.TemporaryDirectory()\n_out = Path(_work.name)\n_report = run_project(_out, quick=True)\n")
    training = "_training = _report['training']\n" if name == 'merge' else "_training = _report['full']\n" if name == 'compare' else "_training = _report\n"
    common = [
        ('real pretrained training and finite held-out evidence', setup + training +
         "assert _training['weights_sha256'] == ft.WEIGHTS_SHA and _training['original_rows'] == 3000\n"
         "assert _training['steps'] >= 4 and math.isfinite(_training['test']['loss'])\n"
         "assert _training['test']['examples'] == 8 and 0 <= _training['test']['macro_f1'] <= 1\n"),
        ('text groups cannot cross train/validation/test', setup + training +
         "_groups = [set(_training['split_groups'][k]) for k in ('train','valid','test')]\n"
         "assert not (_groups[0]&_groups[1] or _groups[0]&_groups[2] or _groups[1]&_groups[2])\n"
         "assert all(_groups)\n"),
    ]
    if name == 'full':
        specific = [
            ('exported encoder changes through actual backward updates', "_state = torch.load(_out/'model.pt', weights_only=True)\n_base = ft.pretrained()\nassert not torch.equal(_state['bert.encoder.layer.0.attention.self.query.weight'], _base.state_dict()['bert.encoder.layer.0.attention.self.query.weight'])\nassert _report['parameters_before'] != _report['parameters_after']\n"),
            ('reloaded best checkpoint reproduces validation score', "_m=ft.pretrained();_m.load_state_dict(torch.load(_out/'model.pt',weights_only=True))\n_v=ft.encode(ft.dataset(quick=True)['valid'],24)\nassert abs(ft.evaluate(_m,_v)['loss']-_report['validation']['loss'])<1e-6\nassert _report['validation']['macro_f1'] == max(row['macro_f1'] for row in _report['history'])\n"),
        ]
    elif name in ('lora', 'domain'):
        specific = [
            ('base stays frozen and exported B receives a real update', "assert _report['frozen_before']==_report['frozen_after']\nassert _report['parameters_before']!=_report['parameters_after']\n_s=torch.load(_out/'adapter.pt',weights_only=True)\nassert any(k.endswith('.B') and bool(v.ne(0).any()) for k,v in _s.items())\nassert not any('.base.' in k for k in _s)\n"),
            ('exact adapter identity and offline reload', "_m=ft.load_adapter(_out/'adapter.pt');assert _report['adapter_reload_max_error']==0\nassert _report['trainable_parameters'] < _report['total_parameters']/100\n" + ("assert all(x.startswith('imdb:') for x in _report['split_ids']['test'])\nassert not any(x.startswith('imdb:') for k in ('train','valid') for x in _report['split_ids'][k])\n" if name == 'domain' else "_manifest=json.loads((_out/'adapter.pt.json').read_text());_manifest['revision']='wrong';(_out/'adapter.pt.json').write_text(json.dumps(_manifest))\ntry: ft.load_adapter(_out/'adapter.pt')\nexcept ValueError: pass\nelse: raise AssertionError('Wrong-base adapter was accepted')\n")),
        ]
    elif name == 'compare':
        specific = [
            ('identical partitions and real optimizer-state savings', "assert _report['full']['split_ids']==_report['lora']['split_ids']\nassert _report['full']['steps']==_report['lora']['steps']\nassert 0 < _report['optimizer_ratio'] < .01 and 0 < _report['trainable_ratio'] < .01\n"),
            ('independent artifacts retain their distinct deployment costs', "assert (_out/'full/model.pt').stat().st_size == _report['full']['artifact_bytes']\nassert (_out/'lora/adapter.pt').stat().st_size == _report['lora']['artifact_bytes']\nassert 0 < _report['artifact_ratio'] < .01\n"),
        ]
    elif name == 'resume':
        specific = [
            ('mid-epoch checkpoint has every required continuation component', "_s=torch.load(_out/'resume.pt',weights_only=True)\nassert {'optimizer','torch_rng','sampler_rng','order','cursor','epoch'} <= _s.keys()\nassert _s['optimizer']['state'] and _s['cursor'] > 0\nassert _s['revision']==ft.REVISION\n"),
            ('fresh restoration matches all tensors and every loss', "assert _report['max_parameter_difference']==0 and _report['identical_losses'] is True\nassert 0 < _report['checkpoint_step'] < _report['steps']\nassert (_out/'adapter.pt').is_file()\n"),
        ]
    else:
        specific = [
            ('merged export contains ordinary projections with inference parity', "_s=torch.load(_out/'merged.pt',weights_only=True)\nassert not any(k.endswith(('.A','.B')) or '.base.' in k for k in _s)\n_m=ft.pretrained();_m.load_state_dict(_s,strict=True)\nassert _report['merge_max_error']<2e-5 and _report['reload_max_error']==0\nassert _report['has_adapter_modules'] is False\n"),
            ('full-model and adapter sizes are measured from actual files', "assert (_out/'merged.pt').stat().st_size==_report['merged_bytes']\nassert (_out/'adapter.pt').stat().st_size==_report['adapter_bytes']\nassert _report['merged_bytes'] > 100*_report['adapter_bytes']\n"),
        ]
    return [{'name': title, 'code': code} for title, code in common + [(title, setup + code) for title, code in specific]]


def main():
    (PYTHON / 'finetune_projects/finetune-assets.json').write_bytes((ROOT / 'runtime/finetune-assets.json').read_bytes())
    (PYTHON / 'finetune_projects/fetch_assets_source.py').write_bytes((ROOT / 'scripts/fetch-finetune-assets.py').read_bytes())
    course = dict(id='finetuning-projects', title='Pretrained transformers & LoRA projects', kind='path',
                  summary='Six complete CPU projects: real BERT-Tiny weights, review datasets, training, validation, exact resume and deployment artifacts.', lessons=[])
    catalog_file = LABS / 'catalog-expansion.json'
    catalog = json.loads(catalog_file.read_text())
    ids = {item[1] for item in PROJECTS}
    catalog = [lab for lab in catalog if lab['id'] not in ids]
    topic_file = LABS / 'lab-topics.json'
    topics = json.loads(topic_file.read_text())
    for key, title, section in [('finetuning-training', 'Pretrained model training', 'Machine learning'), ('finetuning-adapters', 'LoRA & model deployment', 'Artificial intelligence')]:
        if not any(row['id'] == key for row in topics['topics']): topics['topics'].append(dict(id=key, title=title, section=section))
    specs = {}
    for name, lab_id, title, section, task, introduction in PROJECTS:
        source = (PYTHON / 'finetune_projects' / (name + '.py')).read_text()
        starter = 'from pathlib import Path\nimport torch\nimport pythilo_finetune as ft\n\n\ndef run_project(output, quick=False):\n    raise NotImplementedError("Implement the training, evidence and artifact contract in the task")\n'
        lesson_id = 'project-' + lab_id
        topic = 'finetuning-training' if section == 'Machine learning' else 'finetuning-adapters'
        body = (f'# Project: {title}\n\n{introduction}\n\n'
                '## Download dependencies, keep the source\n\n'
                'In Pythilo, choose this project in New project. Its code is saved locally immediately. Open Project downloads and explicitly tap Download project packages to save PyTorch, the shared UCI dataset/tokenizer and the 17.7 MB pretrained safetensors asset. Nothing downloads when you create, open or run a project. Once that complete download finishes, training and evaluation run entirely offline on the CPU. Progress, pause and resume are in Downloads. Native Python backends remain in the signed app. Each project shares the same downloaded assets.\n\n'
                'On a desktop, use the complete source archive linked from this lesson, install torch==2.15.0 and numpy, then run fetch_assets.py once. Run python main.py for the complete dataset; --quick is an explicitly smaller contract-check run. Pythilo’s Run button uses the complete project by default.\n\n'
                '## Inspect the actual source data\n\n'
                'The original dataset contains 3,000 review sentences from Amazon, Yelp and IMDb. The loader checks source hashes, normalizes text identities, removes conflicting labels, deduplicates groups and creates deterministic partitions. It splits only on newline because two IMDb sentences contain embedded NEL characters. Tokenization uses Google’s fixed WordPiece vocabulary; no vocabulary is fitted on the test set.\n\n'
                '```python\nimport pythilo_finetune as ft\nsplits = ft.dataset()\nprint({key: len(splits[key]) for key in ("train", "valid", "test")})\nprint(splits["original_rows"])\n```\n\n'
                '## Build the experiment\n\n' + task + '\n\n'
                'Read the complete reference implementation below. The shared pythilo_finetune.py implements BERT, WordPiece, safe asset loading, metrics and artifact primitives; the project owns its data choices, optimizer loop and evidence. Full and LoRA recipes expose zero_grad, cross_entropy, backward, gradient clipping, optimizer.step and validation selection directly.\n\n'
                '## Evaluate and review\n\n'
                'Compare validation and held-out loss, accuracy and macro-F1. The report records row and normalized-text identities, all asset hashes, the pretrained revision, real optimizer-state bytes and artifact sizes. Model quality is measured, not assumed; the short quick fixture can perform poorly. Four epochs on this small English dataset do not establish production readiness. Review subgroup errors, multiple seeds, data rights, calibration, serving latency and representative out-of-domain tests before deployment.\n\n'
                '## Sources and reuse\n\n'
                'Model: [Google BERT miniature](https://huggingface.co/google/bert_uncased_L-2_H-128_A-2), revision 30b0a37ccaaa32f332884b96992754e246e48c5f, Apache-2.0. '
                'Dataset: [Kotzias (2015), Sentiment Labelled Sentences](https://archive.ics.uci.edu/dataset/331/sentiment+labelled+sentences), DOI 10.24432/C57604, CC BY 4.0. Original files are retained verbatim; normalization, grouping and splitting happen in memory. Attribution and the source manifest accompany the downloaded data.\n')
        lesson_checks = checks(name)
        lesson = dict(id=lesson_id, title='Project: ' + title, level='Senior', minutes=90, body=body,
                      task=task + ' Implement run_project(output, quick=False). Follow the reference report/artifact schema; the checks run quick=True with actual pretrained weights and real data. The full dataset is the default.',
                      starter=starter, solution=source, checks=lesson_checks,
                      hints=['Keep training, validation selection and final evaluation separate.', 'Record exact identities and verify artifacts by reloading into a fresh model.', 'The download catalog pins all assets. Do not replace a missing asset with random weights or invented reviews.'],
                      explanation='The complete project runs real CPU training and exports evidence. Quick checks exercise its contracts with a small real-data slice; they do not establish model quality. A model or adapter is usable only with its recorded tokenizer, base identity and architecture.')
        course['lessons'].append(lesson)
        catalog.append(dict(id=lab_id, title='Project: ' + title, summary=task, symbol='brain', tint='violet', section=section,
                            variants=[dict(id='practice', title='Project', prompt=lesson['task'], file=name+'.py', scales=False)],
                            lessons=[lesson_id], runtime='pytorch', idea=introduction))
        topics['assignments'][lab_id] = topic
        (LABS / f'{lab_id}.practice.starter.py').write_text(starter)
        (LABS / f'{lab_id}.practice.answer.py').write_text(source)
        specs[lab_id] = dict(entry='run_project', checks=lesson_checks)
    (ROOT / 'Pythilo/Resources/Courses/36-finetuning-projects.json').write_text(json.dumps(course, ensure_ascii=False, indent=2) + '\n')
    catalog_file.write_text(json.dumps(catalog, ensure_ascii=False, indent=2) + '\n')
    topic_file.write_text(json.dumps(topics, ensure_ascii=False, indent=2) + '\n')
    support = '''
from .labs_engine import register
from .labs_engine import plot
from .labs_extended import render
import tempfile

def _draw(view):
    if view.function not in ('run_project', 'advance'): return None
    # Keep the trace focused on the learner's loop, not 3,000 raw rows or model internals.
    original = view.locals
    keep = ('epoch','cursor','steps','train_loss','score','baseline','best','difference','error','reload_error','total_steps','split')
    view.locals = {key: value for key, value in original.items() if key in keep}
    loss = original.get('loss')
    if hasattr(loss, 'numel') and loss.numel() == 1: view.locals['batch_loss'] = loss.detach().item()
    for name in ('original_logits', 'merged_logits'):
        value = original.get(name)
        if hasattr(value, 'numel') and value.numel() <= 64: view.locals[name] = value.detach().tolist()
    report = original.get('report')
    if isinstance(report, dict) and 'merge_max_error' in report:
        view.locals['export evidence'] = {key: report[key] for key in ('merge_max_error','reload_max_error','adapter_bytes','merged_bytes','has_adapter_modules')}
    for method in ('full','lora'):
        evidence = original.get(method)
        if isinstance(evidence, dict):
            view.locals[method] = {key: evidence[key] for key in ('trainable_parameters','optimizer_state_bytes','artifact_bytes','steps','test') if key in evidence}
    losses = original.get('losses')
    if isinstance(losses, list): view.locals['history'] = losses
    drawn = render(view)
    history = original.get('history')
    if isinstance(history, list) and history and all(isinstance(row, dict) and 'train_loss' in row for row in history):
        panel = plot([('training loss', [[row['epoch'],row['train_loss']] for row in history]),
                      ('validation loss', [[row['epoch'],row['loss']] for row in history])], title='Real BERT training and validation')
        return ((drawn[0] if drawn else []) + [panel], f'After line {view.line}: {view.text}')
    return drawn

for lab_id, spec in SPECS.items():
    def trace(namespace, recorder):
        with tempfile.TemporaryDirectory() as output:
            recorder.context = 'real pretrained BERT · explicit quick data slice'
            recorder.watch(lambda: namespace['run_project'](output, quick=True), _draw)
            return ''
    def check(namespace, code):
        exec(compile(code, '<finetune-check>', 'exec'), dict(namespace))
    register(lab_id, {'practice': {'file': lab_id+'.py', 'names': [('run_project','a function run_project(output, quick=False)')],
        'trace': trace, 'checks': [(row['name'], lambda namespace, code=row['code']: check(namespace, code)) for row in spec['checks']]}})
'''
    (PYTHON / 'pythilo_runtime/labs_finetune.py').write_text('"""Native pretrained-transformer project contracts. Generated by scripts/generate-finetune-content.py."""\nSPECS = ' + pprint.pformat(specs, width=110, sort_dicts=False) + '\n' + support)
    print('6 complete local-source projects, 6 linked lessons and 6 native Labs.')


if __name__ == '__main__':
    main()
