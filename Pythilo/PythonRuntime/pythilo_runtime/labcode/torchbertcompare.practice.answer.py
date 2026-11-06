"""Same data, initial classifier, batch order, sequence length and optimizer-step budget."""
from pathlib import Path
import pythilo_finetune as ft
from finetune_projects.full import run_project as full_training
from finetune_projects.lora import run_project as lora_training


def run_project(output, quick=False):
    output = Path(output)
    full = full_training(output / 'full', quick)
    lora = lora_training(output / 'lora', quick)
    if full['split_ids'] != lora['split_ids'] or full['steps'] != lora['steps']:
        raise ValueError('Unfair comparison: data or optimizer-step budget differs')
    # Learning rates differ by method and are declared, not selected on the test.
    report = dict(full=full, lora=lora, full_learning_rate=2e-4, lora_learning_rate=1e-3,
                  trainable_ratio=lora['trainable_parameters'] / full['trainable_parameters'],
                  optimizer_ratio=lora['optimizer_state_bytes'] / full['optimizer_state_bytes'],
                  artifact_ratio=lora['artifact_bytes'] / full['artifact_bytes'],
                  same_step_budget=True, quick=quick,
                  interpretation='Parameter and optimizer tensor bytes are measured. They are not a peak-RAM measurement. Test scores are descriptive; neither method is guaranteed to win.')
    ft.save_json(output / 'comparison.json', report)
    return report
