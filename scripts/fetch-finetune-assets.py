#!/usr/bin/env python3
"""Fetch pinned public training assets; verify before writing. No downloaded app code."""
import argparse
import hashlib
import io
import json
from pathlib import Path
import ssl
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parent.parent


def fetch(url, expected):
    try:
        import certifi
    except ImportError:
        from pip._vendor import certifi
    context = ssl.create_default_context(cafile=certifi.where())
    with urllib.request.urlopen(url, timeout=120, context=context) as response:
        payload = response.read(expected['bytes'] + 1)
    if len(payload) != expected['bytes'] or hashlib.sha256(payload).hexdigest() != expected['sha256']:
        raise ValueError('Asset checksum/size mismatch: ' + url.split('?')[0])
    return payload


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--project-assets', type=Path)
    args = parser.parse_args()
    spec = json.loads((ROOT / 'runtime/finetune-assets.json').read_text())
    data = args.project_assets or ROOT / 'build/finetune-data'
    model = args.project_assets or ROOT / 'build/finetune-model'
    data.mkdir(parents=True, exist_ok=True); model.mkdir(parents=True, exist_ok=True)
    license_file = data / 'MODEL-LICENSE.txt'
    license_spec = spec['modelLicenseFile']
    if not license_file.exists() or hashlib.sha256(license_file.read_bytes()).hexdigest() != license_spec['sha256']:
        license_file.write_bytes(fetch(license_spec['url'], license_spec))
    for name, expected in spec['files'].items():
        path = data / name
        if not path.exists() or hashlib.sha256(path.read_bytes()).hexdigest() != expected['sha256']:
            path.write_bytes(fetch(f'https://huggingface.co/{spec["model"]}/resolve/{spec["revision"]}/{name}', expected))
    source = fetch(spec['dataset']['url'], spec['dataset'])
    with zipfile.ZipFile(io.BytesIO(source)) as archive:
        for name in archive.namelist():
            filename = Path(name).name
            if filename in ['amazon_cells_labelled.txt', 'imdb_labelled.txt', 'yelp_labelled.txt', 'readme.txt']:
                (data / filename).write_bytes(archive.read(name))
    weights = model / 'model.safetensors'
    expected = spec['weights']
    if not weights.exists() or hashlib.sha256(weights.read_bytes()).hexdigest() != expected['sha256']:
        weights.write_bytes(fetch(expected['url'], expected))
    attribution = (spec['dataset']['citation'] + '\n\nDataset: CC BY 4.0 — https://creativecommons.org/licenses/by/4.0/\n'
                   'Original data retained verbatim. Pythilo normalizes and deduplicates in memory before splitting.\n\n'
                   f'Model and vocabulary: {spec["model"]}, revision {spec["revision"]}, Apache-2.0.\n'
                   'https://huggingface.co/google/bert_uncased_L-2_H-128_A-2\n'
                   'Apache License: https://www.apache.org/licenses/LICENSE-2.0\n')
    (data / 'ATTRIBUTION.txt').write_text(attribution)
    (data / 'provenance.json').write_text(json.dumps(spec, indent=2) + '\n')
    print('Verified 3,000 source rows, tokenizer and 17.7 MB pretrained weights.')


if __name__ == '__main__':
    main()
