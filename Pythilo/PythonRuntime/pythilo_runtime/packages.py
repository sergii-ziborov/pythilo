"""pip, run in this process against the project's own package folder."""

import json
import os
import sys
import time


def _bundled_native_packages():
    """Top-level packages Pythilo ships with compiled code, pinned by this build."""
    root = None
    for entry in sys.path:
        if entry.endswith("/app_packages"):
            root = entry
            break
    if root is None:
        return {}
    pinned = {}
    for name in os.listdir(root):
        if not name.endswith(".dist-info"):
            continue
        stem = name[: -len(".dist-info")]
        distribution, _, version = stem.rpartition("-")
        pinned[distribution.lower().replace("_", "-")] = version
    return pinned


def pip(args, site):
    if not args or args[0] in ("-h", "--help", "help"):
        print("pip install <package>...   pip uninstall <package>...   pip list   pip show <package>   pip freeze")
        print(f"Packages for this project live in {site}.")
        print("Pure-Python wheels install from PyPI. Compiled packages only work if Pythilo bundles them.")
        return 0
    command, *rest = args
    if command in ("-V", "-v", "--version"):
        import pip

        print(f"pip {pip.__version__} (Python {sys.version.split()[0]}), installing into {site}")
        return 0
    os.makedirs(site, exist_ok=True)
    if command == "install":
        return _install(rest, site)
    if command == "uninstall":
        return _uninstall(rest, site)
    if command in ("list", "freeze", "show"):
        return _inspect(command, rest, site)
    print(f"pip {command} is not available in Pythilo.", file=sys.stderr)
    return 2


def _call_pip(arguments):
    from pip._internal.cli.main import main
    from pip._internal.commands import install

    # pip install guards against importing what it just installed with an audit
    # hook, and an audit hook can never be removed. Here pip shares the one
    # interpreter with everything the user runs later, so the hook would flag
    # (and from pip 26.3 refuse) every later import. Marking it as already
    # installed keeps pip from adding it.
    install._IMPORT_AUDIT_HOOK_INSTALLED = True
    return main(["--no-input", "--disable-pip-version-check", "--no-color", *arguments])


def _install(args, site):
    requested = list(args)
    for flag in ("--user", "-e", "--editable", "--target", "-t", "--prefix", "--root"):
        if flag in requested:
            print(f"pip install {flag} is not available: packages always go to {site}.", file=sys.stderr)
            return 2
    # A source package would need a build process, and a compiled wheel could
    # not be signed into the app afterwards, so only wheels are allowed.
    pinned = _bundled_native_packages()
    code = _call_pip(
        [
            "install",
            "--target",
            site,
            "--upgrade",
            "--only-binary",
            ":all:",
            "--progress-bar",
            "off",
            *requested,
        ]
    )
    if code == 0:
        _write_manifest(site, pinned)
    else:
        print(
            "Install failed and nothing was changed. If a package needs compiled code or a source build, "
            "it cannot be installed on iOS unless Pythilo bundles it.",
            file=sys.stderr,
        )
    return code


def _uninstall(args, site):
    import shutil

    from importlib import metadata

    names = [arg for arg in args if not arg.startswith("-")]
    if not names:
        print("pip uninstall needs a package.", file=sys.stderr)
        return 2
    code = 0
    distributions = {
        (dist.metadata["Name"] or "").lower().replace("_", "-"): dist
        for dist in metadata.distributions(path=[site])
    }
    for name in names:
        dist = distributions.get(name.lower().replace("_", "-"))
        if dist is None:
            print(f"{name} is not installed in this project.", file=sys.stderr)
            code = 1
            continue
        for file in dist.files or []:
            path = os.path.join(site, str(file))
            if os.path.isfile(path):
                os.remove(path)
        info = str(dist._path)
        if os.path.isdir(info):
            shutil.rmtree(info)
        for directory, subdirectories, files in os.walk(site, topdown=False):
            if directory != site and not files and not subdirectories:
                os.rmdir(directory)
        print(f"Removed {name}")
    _write_manifest(site, _bundled_native_packages())
    return code


def _inspect(command, args, site):
    from importlib import metadata

    project = sorted(
        (dist for dist in metadata.distributions(path=[site])),
        key=lambda dist: (dist.metadata["Name"] or "").lower(),
    )
    if command == "freeze":
        for dist in project:
            print(f"{dist.metadata['Name']}=={dist.version}")
        return 0
    if command == "list":
        for dist in project:
            print(f"{dist.metadata['Name']:<30} {dist.version}  project")
        for name, version in sorted(_bundled_native_packages().items()):
            print(f"{name:<30} {version}  bundled")
        return 0
    code = 0
    for name in args:
        try:
            dist = metadata.distribution(name)
        except metadata.PackageNotFoundError:
            print(f"{name} is not installed.", file=sys.stderr)
            code = 1
            continue
        print(f"Name: {dist.metadata['Name']}\nVersion: {dist.version}")
        print(f"Summary: {dist.metadata['Summary']}\nLocation: {dist.locate_file('')}")
    return code


def _write_manifest(site, pinned):
    from importlib import metadata

    manifest = {
        "python": sys.version.split()[0],
        "platform": sys.platform,
        "written": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "packages": {
            dist.metadata["Name"]: dist.version for dist in metadata.distributions(path=[site])
        },
        "bundled": pinned,
    }
    with open(os.path.join(os.path.dirname(site), "environment.json"), "w", encoding="utf-8") as handle:
        json.dump(manifest, handle, indent=2, sort_keys=True)
        handle.write("\n")
