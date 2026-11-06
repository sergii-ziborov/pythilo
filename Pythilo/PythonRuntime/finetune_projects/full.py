"""Full pretrained BERT fine-tuning with validation selection and untouched final test."""
from pathlib import Path
import random
import torch
from torch.nn import functional as F
import pythilo_finetune as ft


def run_project(output, quick=False):
    torch.set_num_threads(2)
    output = Path(output); output.mkdir(parents=True, exist_ok=True)
    data = ft.dataset(quick=quick)
    length, batch_size, epochs = (24, 8, 2) if quick else (48, 16, 4)
    train, valid, test = [ft.encode(data[key], length) for key in ('train', 'valid', 'test')]
    model = ft.pretrained('full')
    before = ft.state_hash(model)
    frozen_before = ft.state_hash(model, frozen_only=True)
    optimizer = torch.optim.AdamW([p for p in model.parameters() if p.requires_grad], lr=2e-4, weight_decay=.01)
    rng = random.Random(17)
    torch.manual_seed(317)
    baseline = ft.evaluate(model, valid)
    best, best_state, history, steps = None, None, [], 0
    for epoch in range(epochs):
        order = list(range(len(data['train']))); rng.shuffle(order)
        model.train()
        train_loss = 0.0
        for cursor in range(0, len(order), batch_size):
            ids, mask, labels = ft.minibatch(train, order[cursor:cursor + batch_size])
            optimizer.zero_grad(set_to_none=True)
            loss = F.cross_entropy(model(ids, mask), labels)
            if not torch.isfinite(loss): raise ValueError('Nonfinite training loss')
            loss.backward()
            torch.nn.utils.clip_grad_norm_([p for p in model.parameters() if p.requires_grad], 1.0, error_if_nonfinite=True)
            optimizer.step(); steps += 1
            train_loss += loss.item() * len(labels)
        score = ft.evaluate(model, valid)
        history.append(dict(epoch=epoch + 1, train_loss=train_loss / len(order), **score))
        # The test split is not consulted for model selection.
        key = (score['macro_f1'], -score['loss'])
        if best is None or key > best:
            best, best_state = key, {name: value.detach().clone() for name, value in model.state_dict().items()}
    model.load_state_dict(best_state, strict=True)
    validation = ft.evaluate(model, valid)
    final_test = ft.evaluate(model, test)
    report = ft.provenance(data, model, optimizer)
    report.update(mode='full', sequence_length=length, batch_size=batch_size, epochs=epochs, steps=steps,
                  baseline_validation=baseline, validation=validation, test=final_test, history=history,
                  parameters_before=before, parameters_after=ft.state_hash(model),
                  frozen_before=frozen_before, frozen_after=ft.state_hash(model, frozen_only=True))
    torch.save(model.state_dict(), output / 'model.pt')
    report['artifact_bytes'] = (output / 'model.pt').stat().st_size
    ft.save_json(output / 'report.json', report)
    return report
