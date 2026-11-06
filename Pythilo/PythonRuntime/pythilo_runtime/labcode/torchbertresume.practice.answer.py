"""Exact CPU resume with AdamW moments, dropout RNG, sampler RNG, order and cursor."""
from pathlib import Path
import random
import torch
from torch.nn import functional as F
import pythilo_finetune as ft


def run_project(output, quick=False):
    torch.set_num_threads(2)
    output = Path(output); output.mkdir(parents=True, exist_ok=True)
    data = ft.dataset(quick=quick)
    length, batch_size, epochs = (24, 8, 2) if quick else (48, 16, 2)
    train, valid, test = [ft.encode(data[key], length) for key in ('train', 'valid', 'test')]
    total_steps = epochs * ((len(data['train']) + batch_size - 1) // batch_size)

    def initialize():
        model = ft.pretrained('lora')
        optimizer = torch.optim.AdamW([p for p in model.parameters() if p.requires_grad], lr=.001)
        rng = random.Random(17)
        torch.manual_seed(317)
        return model, optimizer, rng

    def advance(model, optimizer, rng, state, steps):
        epoch, cursor, order = state
        losses = []
        model.train()
        for _ in range(steps):
            if cursor >= len(order):
                epoch += 1; cursor = 0
                order = list(range(len(data['train']))); rng.shuffle(order)
            ids, mask, labels = ft.minibatch(train, order[cursor:cursor + batch_size])
            optimizer.zero_grad(set_to_none=True)
            loss = F.cross_entropy(model(ids, mask), labels)
            if not torch.isfinite(loss): raise ValueError('Nonfinite loss')
            loss.backward()
            torch.nn.utils.clip_grad_norm_([p for p in model.parameters() if p.requires_grad], 1., error_if_nonfinite=True)
            optimizer.step(); cursor += len(labels); losses.append(loss.item())
        return (epoch, cursor, order), losses

    continuous, optimizer, rng = initialize()
    _, expected_losses = advance(continuous, optimizer, rng, (0, 0, []), total_steps)
    interrupted, interrupted_optimizer, interrupted_rng = initialize()
    split = max(1, total_steps // 2 - 1)  # Deliberately not restricted to an epoch boundary.
    state, first_losses = advance(interrupted, interrupted_optimizer, interrupted_rng, (0, 0, []), split)
    ft.save_checkpoint(output / 'resume.pt', interrupted, interrupted_optimizer, *state, interrupted_rng)
    # Construct a fresh model and optimizer to simulate process loss.
    resumed, resumed_optimizer, resumed_rng = initialize()
    checkpoint = ft.load_checkpoint(output / 'resume.pt', resumed, resumed_optimizer, resumed_rng)
    position = (checkpoint['epoch'], checkpoint['cursor'], checkpoint['order'])
    _, remaining_losses = advance(resumed, resumed_optimizer, resumed_rng, position, total_steps - split)
    difference = max((a - b).abs().max().item() for a, b in zip(continuous.state_dict().values(), resumed.state_dict().values()))
    if difference != 0 or expected_losses != first_losses + remaining_losses:
        raise AssertionError('Resume did not reproduce the uninterrupted CPU trajectory')
    report = ft.provenance(data, resumed, resumed_optimizer)
    report.update(max_parameter_difference=difference, identical_losses=True, steps=total_steps,
                  checkpoint_step=split, sequence_length=length, validation=ft.evaluate(resumed, valid), test=ft.evaluate(resumed, test))
    ft.export_adapter(resumed, output / 'adapter.pt')
    ft.save_json(output / 'report.json', report)
    return report
