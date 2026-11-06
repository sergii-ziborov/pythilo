#!/usr/bin/env python3
"""Small, complete source archives. Large training resources are fetched separately."""
import json
from pathlib import Path
import zipfile

ROOT = Path(__file__).resolve().parent.parent
PYTHON = ROOT / 'Pythilo/PythonRuntime'
OUTPUT = ROOT / 'site/public/projects'


def main():
    OUTPUT.mkdir(parents=True, exist_ok=True)
    for name in ['full', 'lora', 'domain', 'compare', 'resume', 'merge']:
        files = {'pythilo_finetune.py': (PYTHON / 'pythilo_finetune.py').read_bytes(),
                 'runtime/finetune-assets.json': (ROOT / 'runtime/finetune-assets.json').read_bytes(),
                 'scripts/fetch-finetune-assets.py': (ROOT / 'scripts/fetch-finetune-assets.py').read_bytes(),
                 'LICENSE': (ROOT / 'LICENSE').read_bytes(),
                 'requirements.txt': b'torch==2.15.0\nnumpy>=2.0,<3\n'}
        for path in sorted((PYTHON / 'finetune_projects').glob('*.py')):
            if path.name != 'fetch_assets_source.py': files['finetune_projects/' + path.name] = path.read_bytes()
        files['main.py'] = (f'import json, sys\nfrom finetune_projects.{name} import run_project\n\nif __name__ == "__main__":\n    print(json.dumps(run_project("artifacts/{name}", quick="--quick" in sys.argv), indent=2))\n').encode()
        files['fetch_assets.py'] = b"import runpy, sys\nfrom pathlib import Path\nsys.argv = ['fetch_assets.py', '--project-assets', 'assets']\nrunpy.run_path(str(Path(__file__).parent / 'scripts/fetch-finetune-assets.py'), run_name='__main__')\n"
        files['README.md'] = (f'# BERT {name} project\n\nInstall requirements.txt, run `python fetch_assets.py` once, then `python main.py`. '
                              'The default uses the complete real dataset. `python main.py --quick` explicitly uses a small contract fixture. '
                              'All code is included; the 17.7 MB pretrained weights and UCI data download separately and are verified by hash. '
                              'After setup all training and evaluation runs offline on CPU. Outputs are in artifacts/.\n\n'
                              'Google BERT-Tiny: Apache-2.0, exact revision and hashes in runtime/finetune-assets.json. '
                              'Kotzias (2015), UCI Sentiment Labelled Sentences, DOI 10.24432/C57604, CC BY 4.0. '
                              'The downloaded data retains attribution and verbatim source files. Pythilo normalizes and deduplicates in memory.\n').encode()
        with zipfile.ZipFile(OUTPUT / f'bert-{name}.zip', 'w', zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
            for path, data in sorted(files.items()):
                entry = zipfile.ZipInfo(f'bert-{name}/{path}', (2026, 1, 1, 0, 0, 0)); entry.compress_type = zipfile.ZIP_DEFLATED; entry.external_attr = 0o100644 << 16
                archive.writestr(entry, data)
    print('6 complete project source ZIPs; model weights and datasets excluded.')


if __name__ == '__main__':
    main()
