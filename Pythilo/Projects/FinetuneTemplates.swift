import Foundation

extension ProjectTemplate {
    static let finetuning: [ProjectTemplate] = [
        ("full", "Pretrained BERT fine-tuning", "Full encoder training, validation selection and final test"),
        ("lora", "BERT LoRA adapters", "Frozen base, Q/V adapters and portable export"),
        ("domain", "Sentiment domain transfer", "Amazon/Yelp training and held-out IMDb evaluation"),
        ("compare", "Full tuning vs LoRA", "Equal step budgets, optimizer bytes and artifact costs"),
        ("resume", "Resumable transformer training", "AdamW, dropout RNG and a mid-epoch continuation"),
        ("merge", "Merge a trained BERT adapter", "Train, merge, export and verify inference parity"),
    ].compactMap { name, title, summary in
        let python = Bundle.main.bundleURL.appending(path: "app")
        let source = python.appending(path: "finetune_projects")
        var files: [String: String] = [:]
        for module in ["__init__", "full", "lora", "domain", "compare", "resume", "merge"] {
            guard let text = try? String(contentsOf: source.appending(path: "\(module).py"), encoding: .utf8) else { return nil }
            files["finetune_projects/\(module).py"] = text
        }
        guard let helper = try? String(contentsOf: python.appending(path: "pythilo_finetune.py"), encoding: .utf8),
              let manifest = try? String(contentsOf: source.appending(path: "finetune-assets.json"), encoding: .utf8),
              let fetcher = try? String(contentsOf: source.appending(path: "fetch_assets_source.py"), encoding: .utf8) else { return nil }
        files["pythilo_finetune.py"] = helper
        files["runtime/finetune-assets.json"] = manifest
        files["scripts/fetch-finetune-assets.py"] = fetcher
        files["fetch_assets.py"] = "import runpy, sys\nfrom pathlib import Path\nsys.argv = ['fetch_assets.py', '--project-assets', 'assets']\nrunpy.run_path(str(Path(__file__).parent / 'scripts/fetch-finetune-assets.py'), run_name='__main__')\n"
        files["main.py"] = """
        import json
        import sys
        from finetune_projects.\(name) import run_project

        if __name__ == "__main__":
            report = run_project("artifacts/\(name)", quick="--quick" in sys.argv)
            print(json.dumps(report, indent=2))

        """
        files["requirements.txt"] = "torch==2.15.0\nnumpy>=2.0,<3\n"
        files[".gitignore"] = ".pythilo/\n__pycache__/\nassets/\nartifacts/\n*.pt\n"
        files["README.md"] = """
        # \(title)

        \(summary). All project source stays local and is editable.

        In Pythilo, packages, the real UCI sentiment dataset/tokenizer and Google's pretrained
        BERT-Tiny safetensors weights download automatically. Open Downloads for progress,
        pause, resume or removal. Assets are shared between projects. Run main.py after
        downloads finish; training and evaluation then work offline on CPU.

        On a desktop: install requirements.txt, run python fetch_assets.py once, then
        python main.py. python main.py --quick explicitly runs the small contract fixture.
        Outputs go to artifacts/\(name). The complete dataset is the default.

        Model: google/bert_uncased_L-2_H-128_A-2, revision
        30b0a37ccaaa32f332884b96992754e246e48c5f, Apache-2.0.
        Dataset: Kotzias (2015), Sentiment Labelled Sentences, UCI DOI 10.24432/C57604,
        CC BY 4.0. Original files are unchanged; grouping/splitting occurs in memory.
        The downloaded data includes attribution and exact hashes. These small English
        experiments measure model quality; they do not establish production readiness.
        """
        return ProjectTemplate(id: "finetune-\(name)", title: title, summary: summary, systemImage: "brain", files: files)
    }
}
