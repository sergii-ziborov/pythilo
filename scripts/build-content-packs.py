#!/usr/bin/env python3
"""Reproducible, content-addressed downloads; the signed app pins every byte.

Only Python APIs and data leave the app. Native extensions are still embedded
and signed by embed-python.sh. Generic .fwork markers reference those backends.
"""
import hashlib
import json
import re
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUTPUT = ROOT / "site/public/content-packs"
CATALOG = ROOT / "build/ContentCatalog"
RUNTIME = ROOT / "Pythilo/PythonRuntime/pythilo_runtime"
GROUPS = {
    "numpy": ["numpy"],
    "math": ["sympy", "mpmath", "networkx", "isympy.py"],
    "torch": ["torch", "functorch", "torchgen", "filelock", "fsspec"],
    "web": ["django", "flask", "fastapi", "starlette", "uvicorn", "httpx", "httpcore", "h11",
            "pydantic", "pydantic_core", "anyio", "asgiref", "sqlparse", "werkzeug", "blinker",
            "itsdangerous", "click", "annotated_doc", "annotated_types", "typing_inspection",
            "opentelemetry"],
}


def digest(data):
    return hashlib.sha256(data).hexdigest()


def group(name):
    for key, roots in GROUPS.items():
        if name in roots or any(name.startswith(root.removesuffix('.py') + '-') and name.endswith('.dist-info') for root in roots):
            return key


def python_files(platform, key):
    base = ROOT / 'build/app_packages' / platform
    if not base.exists():
        raise SystemExit(f"Missing {base}; run scripts/vendor-packages.py first.")
    result = {}
    for root in sorted(base.iterdir()):
        if group(root.name) != key:
            continue
        for path in sorted(root.rglob('*')) if root.is_dir() else [root]:
            if not path.is_file() or path.is_symlink():
                continue
            relative = path.relative_to(base).as_posix()
            if '__pycache__' in path.parts or path.suffix in ('.pyc', '.a', '.dylib'):
                continue
            if path.name in ('RECORD', 'WHEEL', 'direct_url.json', 'INSTALLER'):
                continue
            # C++ SDK headers are not needed for Python execution on iOS.
            if relative.startswith(('torch/include/', 'torch/share/')):
                continue
            if path.suffix == '.so':
                module = relative.split('.', 1)[0].replace('/', '.')
                target = relative.rsplit('/', 1)
                filename = path.name.split('.', 1)[0] + '.fwork'
                relative = '/'.join(target[:-1] + [filename])
                data = f'Frameworks/{module}.framework/{module}\n'.encode()
            else:
                data = path.read_bytes()
            result['app_packages/' + relative] = data
    if not result:
        raise SystemExit(f'Empty runtime pack: {key}')
    return result


def archive(pack_id, title, kind, files, dependencies=()):
    import io
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, 'w', zipfile.ZIP_DEFLATED, compresslevel=9) as output:
        for name, data in sorted(files.items()):
            entry = zipfile.ZipInfo(name, (2026, 1, 1, 0, 0, 0))
            entry.compress_type = zipfile.ZIP_DEFLATED
            entry.external_attr = 0o100644 << 16
            output.writestr(entry, data)
    payload = buffer.getvalue()
    sha = digest(payload)
    filename = f'{pack_id}-{sha[:16]}.zip'
    path = OUTPUT / filename
    if not path.exists():
        path.write_bytes(payload)
    return dict(id=pack_id, title=title, kind=kind, url=f'https://pythilo.com/content-packs/{filename}',
                bytes=len(payload), sha256=sha, dependencies=list(dependencies),
                files=[dict(path=name, bytes=len(data), sha256=digest(data)) for name, data in sorted(files.items())])


def dependencies(source):
    result = []
    if re.search(r'\b(torch|pythilo_finetune)\b', source):
        result.append('runtime-torch')
    elif re.search(r'\bnumpy\b', source):
        result.append('runtime-numpy')
    if re.search(r'\b(sympy|mpmath|networkx)\b', source):
        result.append('runtime-math')
    if re.search(r'\b(pydantic|fastapi|httpx|django|flask|uvicorn|starlette)\b', source, re.I):
        result.append('runtime-web')
    if 'pythilo_finetune' in source:
        result.extend(['assets-finetune-data', 'assets-bert-weights'])
    return result


def main():
    OUTPUT.mkdir(parents=True, exist_ok=True)
    CATALOG.mkdir(parents=True, exist_ok=True)
    packs = []
    for key, title in [('numpy', 'NumPy'), ('math', 'Symbolic math & graphs'), ('torch', 'PyTorch'), ('web', 'Web & validation')]:
        files = python_files('iphoneos', key)
        simulator = python_files('iphonesimulator', key)
        # NumPy records the cross-compiler and temporary build directory here.
        # It is descriptive only; the distributed API reports the release/device build.
        simulator['app_packages/numpy/__config__.py'] = files.get('app_packages/numpy/__config__.py', b'')
        if key != 'numpy':
            simulator.pop('app_packages/numpy/__config__.py', None)
        if files != simulator:
            different = sorted(set(files) ^ set(simulator) | {p for p in files.keys() & simulator.keys() if files[p] != simulator[p]})
            raise SystemExit(f'Python API differs between device and simulator: {different[:12]}')
        packs.append(archive('runtime-' + key, title, 'runtime', files,
                             ['runtime-numpy', 'runtime-math'] if key == 'torch' else []))
    asset_catalog = ROOT / 'runtime/finetune-assets.json'
    if asset_catalog.exists():
        assets = json.loads(asset_catalog.read_text())
        files = {path.name: path.read_bytes() for path in (ROOT / 'build/finetune-data').iterdir() if path.is_file()}
        packs.append(archive('assets-finetune-data', 'Sentiment dataset & BERT tokenizer', 'asset', files))
        packs.append(assets['weights'])
    courses = []
    for path in sorted((ROOT / 'Pythilo/Resources/Courses').glob('*.json'), key=lambda p: int(p.name.split('-')[0])):
        course = json.loads(path.read_text())
        packs.append(archive('course-' + course['id'], course['title'], 'course', {'course.json': path.read_bytes()}, dependencies(path.read_text())))
        for lesson in course['lessons']:
            for key in ['body', 'task', 'starter', 'solution', 'explanation']:
                lesson[key] = ''
            lesson['checks'], lesson['hints'] = [], []
        courses.append(course)
    index = json.loads((RUNTIME / 'labcode/lab-topics.json').read_text())
    for topic in index['topics']:
        labs = [lab for lab, group_id in index['assignments'].items() if group_id == topic['id']]
        files = {f'labcode/{p.name}': p.read_bytes() for lab in labs for p in (RUNTIME / 'labcode').glob(lab + '.*.py')}
        # The four original visualizers have Swift-defined starters; still downloadable as a topic.
        files['topic.json'] = json.dumps(dict(topic=topic, labs=labs), ensure_ascii=False, indent=2).encode()
        packs.append(archive('labs-' + topic['id'], topic['title'], 'labs', files,
                             dependencies('\n'.join(data.decode() for data in files.values()))))
    ids = {pack['id'] for pack in packs}
    for pack in packs:
        assert set(pack['dependencies']) <= ids, (pack['id'], pack['dependencies'])
    (CATALOG / 'catalog.json').write_text(json.dumps(dict(schema=1, packs=packs, courses=courses), ensure_ascii=False, separators=(',', ':')) + '\n')
    (CATALOG / 'runtime-roots.json').write_text(json.dumps(GROUPS))
    print(f'{len(courses)} course previews, {len(packs)} pinned packs, {sum(p["bytes"] for p in packs):,} download bytes')


if __name__ == '__main__':
    main()
