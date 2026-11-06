"""Train, reload, merge Q/V adapters and check actual held-out inference parity."""
from pathlib import Path
import torch
import pythilo_finetune as ft
from finetune_projects.lora import run_project as train_adapter


def run_project(output, quick=False):
    output = Path(output)
    training = train_adapter(output, quick)
    adapter = ft.load_adapter(output / 'adapter.pt').eval()
    merged = ft.merge_adapter(adapter)
    data = ft.dataset(quick=quick)
    ids, mask, labels = ft.encode(data['test'], training['sequence_length'])
    # No training or threshold/model selection uses these test labels.
    with torch.no_grad():
        original_logits = adapter(ids, mask)
        merged_logits = merged(ids, mask)
    error = (original_logits - merged_logits).abs().max().item()
    if not torch.allclose(original_logits, merged_logits, atol=2e-5, rtol=1e-5):
        raise AssertionError('Merged inference differs from the loaded adapter')
    torch.save(merged.state_dict(), output / 'merged.pt')
    restored = ft.pretrained('full')
    restored.load_state_dict(torch.load(output / 'merged.pt', weights_only=True), strict=True)
    restored.eval()
    with torch.no_grad():
        reload_error = (restored(ids, mask) - merged_logits).abs().max().item()
    report = dict(training=training, quick=quick, merge_max_error=error, reload_max_error=reload_error,
                  merged_metrics=ft.metrics(merged_logits, labels), adapter_bytes=(output / 'adapter.pt').stat().st_size,
                  merged_bytes=(output / 'merged.pt').stat().st_size,
                  has_adapter_modules=any(isinstance(module, ft.LoRALinear) for module in merged.modules()),
                  deployment='The small adapter requires the exact base model; merged.pt contains the complete classifier state.')
    ft.save_json(output / 'merge-report.json', report)
    return report
