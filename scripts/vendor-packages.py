#!/usr/bin/env python3
"""Fills build/app_packages/<platform> with the bundled Python packages."""

import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PLATFORMS = {
    "iphoneos": "arm64_iphoneos",
    "iphonesimulator": "arm64_iphonesimulator",
}
IOS_VERSIONS = ["13_0", "14_0", "15_0", "16_0", "17_0", "18_0"]


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
