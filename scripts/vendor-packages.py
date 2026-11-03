#!/usr/bin/env python3
"""Fills build/app_packages/<platform> with the bundled Python packages, and
build/esbuild with the esbuild-wasm that npm run build uses in the app."""

import base64
import hashlib
import io
import shutil
import ssl
import subprocess
import sys
import tarfile
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PLATFORMS = {
    "iphoneos": "arm64_iphoneos",
    "iphonesimulator": "arm64_iphonesimulator",
}
IOS_VERSIONS = ["13_0", "14_0", "15_0", "16_0", "17_0", "18_0"]
ESBUILD_VERSION = "0.28.2"
ESBUILD_INTEGRITY = "sha512-GccVwhv3mmOUVQHCQm2Ox/rby8n/EqUwvZxE6Pjfikrq/lWw9g9WX/u9EykWnpot3Ko6j426DgQdea2xWKIAQA=="


def vendor_esbuild():
    """esbuild's WebAssembly build and its browser loader, pinned by hash."""
    target = ROOT / "build" / "esbuild"
    stamp = target / "VERSION"
    if stamp.exists() and stamp.read_text().strip() == ESBUILD_VERSION:
        return
    try:
        import certifi

        context = ssl.create_default_context(cafile=certifi.where())
    except ImportError:
        from pip._vendor import certifi

        context = ssl.create_default_context(cafile=certifi.where())
    url = f"https://registry.npmjs.org/esbuild-wasm/-/esbuild-wasm-{ESBUILD_VERSION}.tgz"
    with urllib.request.urlopen(url, context=context, timeout=120) as response:
        data = response.read()
    if "sha512-" + base64.b64encode(hashlib.sha512(data).digest()).decode() != ESBUILD_INTEGRITY:
        raise SystemExit("esbuild-wasm does not match its pinned hash. Nothing was written.")
    shutil.rmtree(target, ignore_errors=True)
    target.mkdir(parents=True)
    with tarfile.open(fileobj=io.BytesIO(data), mode="r:gz") as archive:
        for member, name in (("package/esbuild.wasm", "esbuild.wasm"), ("package/lib/browser.min.js", "browser.min.js"), ("package/LICENSE.md", "LICENSE.md")):
            (target / name).write_bytes(archive.extractfile(member).read())
    stamp.write_text(ESBUILD_VERSION + "\n")
    print(f"esbuild-wasm {ESBUILD_VERSION}: {(target / 'esbuild.wasm').stat().st_size // 1024} KB")


def prune(target):
    """Drop what a phone never needs: test suites and most translations."""
    for path in list(target.rglob("tests")) + list(target.rglob("__pycache__")):
        if path.is_dir():
            shutil.rmtree(path, ignore_errors=True)
    for locale in target.glob("django/**/locale"):
        for language in locale.iterdir():
            if language.is_dir() and language.name not in ("en", "__init__.py"):
                shutil.rmtree(language, ignore_errors=True)
    for path in target.rglob("*.pyi"):
        if "typeshed" not in path.parts:
            path.unlink()
    for path in (target / "bin").glob("*") if (target / "bin").exists() else []:
        path.unlink()


def main():
    vendor_esbuild()
    lock = ROOT / "runtime" / "requirements.lock"
    source = lock if lock.exists() else ROOT / "runtime" / "requirements.in"
    for platform, suffix in PLATFORMS.items():
        target = ROOT / "build" / "app_packages" / platform
        shutil.rmtree(target, ignore_errors=True)
        command = [
            sys.executable, "-m", "pip", "install", "--quiet", "--disable-pip-version-check",
            "--target", str(target),
            "--only-binary", ":all:",
            "--implementation", "cp", "--python-version", "3.14",
            "--abi", "cp314", "--abi", "abi3", "--abi", "none",
            "--index-url", "https://pypi.org/simple",
            "--extra-index-url", "https://pypi.anaconda.org/beeware/simple",
            # pydantic-core, built here by scripts/build-pydantic-core.sh.
            "--find-links", str(ROOT / "build" / "native" / "wheels"),
            "-r", str(source),
        ]
        for version in IOS_VERSIONS:
            command += ["--platform", f"ios_{version}_{suffix}"]
        subprocess.run(command, check=True)
        prune(target)
        print(f"{platform}: {sum(1 for _ in target.iterdir())} entries")

    if not lock.exists():
        target = ROOT / "build" / "app_packages" / "iphoneos"
        names = sorted(path.name[:-len(".dist-info")] for path in target.glob("*.dist-info"))
        pins = [f"{name.rpartition('-')[0]}=={name.rpartition('-')[2]}" for name in names]
        lock.write_text("# Generated from requirements.in by scripts/vendor-packages.py.\n" + "\n".join(pins) + "\n")
        print(f"Wrote {lock}")


if __name__ == "__main__":
    main()
