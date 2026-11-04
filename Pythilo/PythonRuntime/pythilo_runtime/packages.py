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
    if not args or args[0] in ("-h", "--help") or args == ["help"]:
        print(HELP.format(site=site), end="")
        return 0
    command, *rest = args
    if command == "help":
        command, rest = rest[0], ["--help"]
    if command in ("-V", "-v", "--version"):
        import pip

        print(f"pip {pip.__version__} (Python {sys.version.split()[0]}), installing into {site}")
        return 0
    os.makedirs(site, exist_ok=True)
    if command == "install":
        return _install(rest, site)
    if command == "uninstall":
        return _uninstall(rest, site)
    if command in ("list", "freeze") and not rest:
        return _inspect(command, rest, site)
    if command in ("list", "freeze"):
        # pip's own list and freeze, for --outdated, --format=json and the rest,
        # pointed at this project's folder.
        return _call_pip([command, "--path", site, *rest])
    if command == "show":
        return _show(rest)
    if command in ("check", "index", "inspect", "hash", "debug", "config", "cache"):
        return _call_pip([command, *rest])
    if command in ("download", "wheel"):
        return _call_pip([command, "--only-binary", ":all:", "--progress-bar", "off", *rest])
    if command == "search":
        print("pip search no longer works anywhere: PyPI turned it off. Use pip index versions <package>, "
              "or search pypi.org.", file=sys.stderr)
        return 2
    print(f"pip {command} is not a pip command. pip help lists them.", file=sys.stderr)
    return 2


HELP = """usage: pip <command> [options]
  install PACKAGE... | -r requirements.txt   install wheels into this project (-U, --pre, --no-deps, -i URL work)
  uninstall [-y] PACKAGE... | -r FILE         remove packages from this project
  list [-o | --outdated] [--format=json]     installed packages (project and bundled)
  freeze                                     project packages as requirements
  show [-f] PACKAGE...                       details, dependencies and files
  check                                      look for broken dependencies
  download PACKAGE [-d folder]               fetch wheels without installing
  index versions PACKAGE                     versions available on PyPI
  inspect | hash | config | cache | debug    as in pip
  pip help COMMAND or pip COMMAND --help     all options of a command
Packages for this project live in {site}.
Pure-Python wheels install from PyPI. Compiled packages work only if Pythilo bundles them
(numpy, torch, pydantic and others: pip list shows them as bundled).
"""


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

    names = []
    iterator = iter(args)
    for arg in iterator:
        if arg in ("-r", "--requirement"):
            with open(next(iterator, ""), encoding="utf-8") as handle:
                names.extend(_requirement_name(line) for line in handle if _requirement_name(line))
        elif not arg.startswith("-"):
            names.append(_requirement_name(arg))
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


def _requirement_name(line):
    import re

    line = line.split("#", 1)[0].strip()
    if not line or line.startswith("-"):
        return ""
    return re.split(r"[\s\[<>=!~;@]", line, maxsplit=1)[0]


def _show(args):
    from importlib import metadata

    files = "-f" in args or "--files" in args
    names = [arg for arg in args if not arg.startswith("-")]
    if not names:
        print("pip show needs a package.", file=sys.stderr)
        return 1
    every = list(metadata.distributions())
    code = 0
    for index, name in enumerate(names):
        try:
            dist = metadata.distribution(name)
        except metadata.PackageNotFoundError:
            print(f"WARNING: Package(s) not found: {name}", file=sys.stderr)
            code = 1
            continue
        if index:
            print("---")
        key = (dist.metadata["Name"] or "").lower().replace("_", "-")
        requires = sorted({_requirement_name(r) for r in dist.requires or [] if "extra ==" not in r})
        required_by = sorted(
            other.metadata["Name"] for other in every
            if any(_requirement_name(r).lower().replace("_", "-") == key and "extra ==" not in r for r in other.requires or [])
        )
        meta = dist.metadata
        home = meta.get("Home-page") or next((u.split(",", 1)[1].strip() for u in meta.get_all("Project-URL") or [] if "," in u), "")
        print(f"Name: {meta['Name']}\nVersion: {dist.version}\nSummary: {meta.get('Summary') or ''}\nHome-page: {home}")
        author = meta.get("Author") or meta.get("Author-email") or ""
        license_text = meta.get("License-Expression") or meta.get("License") or ""
        print(f"Author: {author}\nLicense: {license_text}")
        print(f"Location: {dist.locate_file('')}\nRequires: {', '.join(requires)}\nRequired-by: {', '.join(required_by)}")
        if files:
            print("Files:")
            for file in dist.files or []:
                print(f"  {file}")
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
