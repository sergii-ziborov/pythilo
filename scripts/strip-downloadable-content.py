#!/usr/bin/env python3
"""Run only on an assembled app, after every native extension has been signed."""
import importlib.util
import hashlib
import json
import shutil
import sys
import zipfile
from pathlib import Path

spec = importlib.util.spec_from_file_location('packs', Path(__file__).with_name('build-content-packs.py'))
packs = importlib.util.module_from_spec(spec)
spec.loader.exec_module(packs)
app = Path(sys.argv[1])
catalog = json.loads((packs.CATALOG / 'catalog.json').read_text())
verified_markers = 0
for pack in catalog['packs']:
    markers = [entry for entry in pack['files'] if entry['path'].endswith('.fwork')]
    if pack['kind'] != 'runtime' or not markers:
        continue
    archive_path = packs.OUTPUT / pack['url'].rsplit('/', 1)[1]
    if hashlib.sha256(archive_path.read_bytes()).hexdigest() != pack['sha256']:
        raise SystemExit('Pinned runtime archive changed: ' + pack['id'])
    with zipfile.ZipFile(archive_path) as archive:
        for entry in markers:
            marker = archive.read(entry['path']).decode().strip()
            binary = (app / marker).resolve()
            if not marker.startswith('Frameworks/') or not binary.is_relative_to((app / 'Frameworks').resolve()) or not binary.is_file():
                raise SystemExit('Downloaded Python API has no embedded native backend: ' + marker)
            verified_markers += 1
print(f'Validated {verified_markers} downloaded API links against embedded native frameworks.')
for path in (app / 'app_packages').iterdir():
    if packs.group(path.name):
        shutil.rmtree(path) if path.is_dir() else path.unlink()
for path in (app / 'app/pythilo_runtime/labcode').glob('*.py'):
    path.unlink()
print('Removed downloadable Python APIs and Lab code; signed frameworks retained.')
