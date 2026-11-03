"""npm without Node: the registry, semver and tarballs, in Python.

Packages land in node_modules the way npm lays them out, so a bundler resolves
them the same way. Install scripts never run, because there is no Node to run
them; a package that needs one says so when it is built. `npm run` is handled by
the app, which builds with esbuild in a web view.
"""

import base64
import concurrent.futures
import hashlib
import io
import json
import os
import re
import shutil
import tarfile
import time
import urllib.parse
import urllib.request

REGISTRY = "https://registry.npmjs.org"
USAGE = "npm install [package[@range] ...] [-D] · npm uninstall <package> · npm ls · npm init -y · npm run <script>"


class NpmError(Exception):
    pass


# Semver, as node-semver reads it for the ranges people write in package.json.

_VERSION = re.compile(r"^v?(\d+)\.(\d+)\.(\d+)(?:-([0-9A-Za-z.-]+))?(?:\+[0-9A-Za-z.-]+)?$")
_PARTIAL = re.compile(r"^v?(\d+|[xX*])(?:\.(\d+|[xX*]))?(?:\.(\d+|[xX*]))?(?:-([0-9A-Za-z.-]+))?(?:\+[0-9A-Za-z.-]+)?$")


class Version:
    __slots__ = ("major", "minor", "patch", "pre", "text")

    def __init__(self, text):
        match = _VERSION.match(text.strip())
        if not match:
            raise ValueError(text)
        self.major, self.minor, self.patch = (int(match.group(i)) for i in (1, 2, 3))
        self.pre = tuple(int(part) if part.isdigit() else part for part in match.group(4).split(".")) if match.group(4) else ()
        self.text = text.strip().lstrip("v")

    def key(self):
        # A release sorts after its prereleases; numeric identifiers before names.
        pre = tuple((0, part, "") if isinstance(part, int) else (1, 0, part) for part in self.pre)
        return (self.major, self.minor, self.patch, 0 if self.pre else 1, pre)

    def __lt__(self, other):
        return self.key() < other.key()

    def __eq__(self, other):
        return self.key() == other.key()

    def __hash__(self):
        return hash(self.key())


def _bound(major, minor, patch, pre=()):
    version = Version("0.0.0")
    version.major, version.minor, version.patch, version.pre = major, minor, patch, pre
    return version


def _comparators(token):
    """One token of a range, as (operator, Version) pairs."""
    match = re.match(r"^(\^|~>?|>=|<=|>|<|=)?(.*)$", token)
    operator, rest = match.group(1) or "", match.group(2)
    partial = _PARTIAL.match(rest)
    if not partial:
        raise NpmError(f"cannot read the version range '{token}'")
    parts = [None if part is None or part in "xX*" else int(part) for part in partial.group(1, 2, 3)]
    pre = tuple(int(p) if p.isdigit() else p for p in partial.group(4).split(".")) if partial.group(4) else ()
    major, minor, patch = parts
    if major is None:
        return [] if operator in ("", "=", ">=", "<=", "^", "~", "~>") else [("<", _bound(0, 0, 0, (0,)))]
    if operator == "^":
        low = _bound(major, minor or 0, patch or 0, pre)
        if major > 0 or minor is None:
            high = _bound(major + 1, 0, 0, (0,))
        elif minor > 0 or patch is None:
            high = _bound(0, minor + 1, 0, (0,))
        else:
            high = _bound(0, 0, patch + 1, (0,))
        return [(">=", low), ("<", high)]
    if operator in ("~", "~>"):
        low = _bound(major, minor or 0, patch or 0, pre)
        high = _bound(major + 1, 0, 0, (0,)) if minor is None else _bound(major, minor + 1, 0, (0,))
        return [(">=", low), ("<", high)]
    if minor is None or patch is None:
        # x-ranges: 1, 1.x, 1.2.*
        low = _bound(major, minor or 0, 0)
        high = _bound(major + 1, 0, 0, (0,)) if minor is None else _bound(major, minor + 1, 0, (0,))
        if operator in ("", "="):
            return [(">=", low), ("<", high)]
        if operator == ">":
            return [(">=", high)]
        if operator == ">=":
            return [(">=", low)]
        if operator == "<":
            return [("<", _bound(low.major, low.minor, 0, (0,)))]
        return [("<", high)]
    return [(operator or "=", _bound(major, minor, patch, pre))]


def parse_range(text):
    text = (text or "").strip()
    if text in ("", "*", "x", "X", "latest"):
        return [[]]
    sets = []
    for part in text.split("||"):
        part = re.sub(r"([<>=~^]+)\s+", r"\1", part.strip())
        hyphen = re.match(r"^(\S+)\s+-\s+(\S+)$", part)
        if hyphen:
            low = _comparators(">=" + hyphen.group(1))
            high_parts = _PARTIAL.match(hyphen.group(2))
            if high_parts and None in [None if p is None or p in "xX*" else p for p in high_parts.group(1, 2, 3)]:
                high = _comparators("<=" + hyphen.group(2))
            else:
                high = [("<=", Version(hyphen.group(2)))]
            sets.append(low + high)
            continue
        comparators = []
        for token in part.split():
            comparators += _comparators(token)
        sets.append(comparators)
    return sets


def satisfies(version, ranges):
    for comparators in ranges:
        ok = True
        for operator, bound in comparators:
            if operator == ">=" and not (bound < version or bound == version):
                ok = False
            elif operator == ">" and not bound < version:
                ok = False
            elif operator == "<=" and not (version < bound or version == bound):
                ok = False
            elif operator == "<" and not version < bound:
                ok = False
            elif operator == "=" and not version == bound:
                ok = False
        if not ok:
            continue
        # A prerelease only matches a range that names a prerelease of the same version.
        if version.pre and not any(
            bound.pre and (bound.major, bound.minor, bound.patch) == (version.major, version.minor, version.patch) and bound.pre != (0,)
            for _, bound in comparators
        ):
            continue
        return True
    return False


# The registry.

class Registry:
    def __init__(self):
        self._documents = {}

    def document(self, name):
        if name not in self._documents:
            # A scoped name keeps its @ and escapes its slash: @types%2freact.
            url = f"{REGISTRY}/{urllib.parse.quote(name, safe='@')}"
            request = urllib.request.Request(url, headers={"Accept": "application/vnd.npm.install-v1+json", "User-Agent": "pythilo-npm"})
            try:
                with urllib.request.urlopen(request, timeout=30) as response:
                    self._documents[name] = json.load(response)
            except urllib.error.HTTPError as error:
                raise NpmError(f"{name}: the registry answered {error.code}" + (" (no such package)" if error.code == 404 else "")) from None
            except OSError as error:
                raise NpmError(f"could not reach the npm registry: {error}") from None
        return self._documents[name]

    def resolve(self, name, spec):
        document = self.document(name)
        tags = document.get("dist-tags", {})
        if spec in tags:
            return document["versions"][tags[spec]]
        if re.match(r"^(git|github:|https?:|file:|link:|workspace:|npm:)", spec or ""):
            raise NpmError(f"{name}@{spec}: only registry versions can be installed here")
        ranges = parse_range(spec)
        candidates = []
        for text in document.get("versions", {}):
            try:
                version = Version(text)
            except ValueError:
                continue
            if satisfies(version, ranges):
                candidates.append(version)
        if not candidates:
            raise NpmError(f"no version of {name} matches {spec!r}")
        latest = tags.get("latest")
        if latest and any(c.text == latest for c in candidates):
            # npm prefers the latest tag when it satisfies the range.
            return document["versions"][latest]
        return document["versions"][max(candidates).text]


def _split_spec(text):
    if text.startswith("@"):
        name, _, spec = text[1:].partition("@")
        return "@" + name, spec or "latest"
    name, _, spec = text.partition("@")
    return name, spec or "latest"


def _wanted_platform(manifest):
    # Native binaries for one operating system come as optional packages; none
    # of them is iOS.
    return not (manifest.get("os") or manifest.get("cpu"))


def plan(root_manifest, registry):
    """The node_modules tree: path -> manifest, placed as high as it can go."""
    tree = {}
    queue = []
    for field, optional in (("dependencies", False), ("devDependencies", False), ("optionalDependencies", True)):
        for name, spec in (root_manifest.get(field) or {}).items():
            queue.append(("", name, spec, optional))
    skipped = []
    while queue:
        parent, name, spec, optional = queue.pop(0)
        # Node walks up from the parent, so does the check for an existing copy.
        found = None
        ancestor = parent
        while True:
            path = f"{ancestor}/node_modules/{name}".lstrip("/")
            if path in tree:
                found = path
                break
            if not ancestor:
                break
            ancestor = ancestor.rsplit("/node_modules/", 1)[0] if "/node_modules/" in ancestor else ""
        if found:
            try:
                ranges = parse_range(spec)
            except NpmError:
                ranges = [[]]  # a dist-tag such as "next": the copy already placed stands
            if satisfies(Version(tree[found]["version"]), ranges):
                continue
        try:
            manifest = registry.resolve(name, spec)
        except NpmError:
            if optional:
                skipped.append(name)
                continue
            raise
        if optional and not _wanted_platform(manifest):
            skipped.append(name)
            continue
        top = f"node_modules/{name}"
        path = top if top not in tree else f"{parent}/node_modules/{name}".lstrip("/")
        tree[path] = manifest
        for field, is_optional in (("dependencies", False), ("optionalDependencies", True), ("peerDependencies", False)):
            for dependency, dependency_spec in (manifest.get(field) or {}).items():
                if field == "peerDependencies" and (manifest.get("peerDependenciesMeta") or {}).get(dependency, {}).get("optional"):
                    continue
                queue.append((path, dependency, dependency_spec, is_optional))
    return tree, skipped


def _verify(data, dist):
    integrity = dist.get("integrity", "")
    for item in integrity.split():
        algorithm, _, digest = item.partition("-")
        if algorithm in ("sha512", "sha384", "sha256"):
            if base64.b64encode(hashlib.new(algorithm, data).digest()).decode() != digest:
                raise NpmError(f"{dist.get('tarball')}: the download does not match its integrity hash")
            return
    if dist.get("shasum") and hashlib.sha1(data).hexdigest() != dist["shasum"]:
        raise NpmError(f"{dist.get('tarball')}: the download does not match its checksum")


def _extract(data, target):
    """A package tarball's first folder becomes the package folder. Links and
    paths that climb out are refused."""
    if os.path.isdir(target):
        shutil.rmtree(target)
    os.makedirs(target)
    real = os.path.realpath(target)
    with tarfile.open(fileobj=io.BytesIO(data), mode="r:gz") as archive:
        for member in archive.getmembers():
            if not (member.isfile() or member.isdir()):
                continue
            parts = member.name.split("/", 1)
            if len(parts) < 2 or not parts[1]:
                continue
            destination = os.path.realpath(os.path.join(target, parts[1]))
            if not destination.startswith(real + os.sep):
                continue
            if member.isdir():
                os.makedirs(destination, exist_ok=True)
                continue
            os.makedirs(os.path.dirname(destination), exist_ok=True)
            source = archive.extractfile(member)
            with open(destination, "wb") as handle:
                shutil.copyfileobj(source, handle)
            os.chmod(destination, 0o755 if member.mode & 0o111 else 0o644)


def _download(manifest):
    dist = manifest["dist"]
    request = urllib.request.Request(dist["tarball"], headers={"User-Agent": "pythilo-npm"})
    with urllib.request.urlopen(request, timeout=120) as response:
        data = response.read()
    _verify(data, dist)
    return data


def _read_json(path):
    with open(path, encoding="utf-8") as handle:
        return json.load(handle)


def _write_json(path, value):
    with open(path, "w", encoding="utf-8") as handle:
        json.dump(value, handle, indent=2, ensure_ascii=False)
        handle.write("\n")


def _installed(root):
    """Installed package folders, as lock paths: node_modules/a, node_modules/@s/b,
    node_modules/a/node_modules/c."""
    found = {}
    for dirpath, dirnames, filenames in os.walk(os.path.join(root, "node_modules")):
        dirnames[:] = [d for d in dirnames if d != ".bin"]
        parts = os.path.relpath(dirpath, root).split(os.sep)
        is_package = len(parts) >= 2 and (parts[-2] == "node_modules" or (len(parts) >= 3 and parts[-3] == "node_modules" and parts[-2].startswith("@")))
        if is_package and "package.json" in filenames and not parts[-1].startswith("@"):
            try:
                found["/".join(parts)] = _read_json(os.path.join(dirpath, "package.json")).get("version")
            except (OSError, ValueError):
                pass
    return found


def install(root, add=(), dev=False):
    started = time.monotonic()
    manifest_path = os.path.join(root, "package.json")
    if not os.path.exists(manifest_path):
        raise NpmError("there is no package.json here. npm init -y makes one.")
    manifest = _read_json(manifest_path)
    registry = Registry()
    if add:
        field = "devDependencies" if dev else "dependencies"
        for text in add:
            name, spec = _split_spec(text)
            resolved = registry.resolve(name, spec)
            manifest.setdefault(field, {})[name] = spec if spec not in ("latest", "") and not spec[0].isdigit() else f"^{resolved['version']}"
        _write_json(manifest_path, manifest)

    lock_path = os.path.join(root, "package-lock.json")
    tree = None
    if not add and os.path.exists(lock_path):
        tree = _from_lock(_read_json(lock_path), manifest)
    skipped = []
    if tree is None:
        print("Resolving from registry.npmjs.org…", flush=True)
        tree, skipped = plan(manifest, registry)

    installed = _installed(root)
    wanted = {path: entry for path, entry in tree.items() if installed.get(path) != entry["version"]}
    with concurrent.futures.ThreadPoolExecutor(max_workers=6) as pool:
        downloads = {path: pool.submit(_download, entry) for path, entry in wanted.items()}
        for path, future in downloads.items():
            _extract(future.result(), os.path.join(root, path))
    removed = 0
    for path in sorted(installed, key=len, reverse=True):
        if path not in tree and os.path.isdir(os.path.join(root, path)):
            shutil.rmtree(os.path.join(root, path), ignore_errors=True)
            removed += 1

    _write_json(lock_path, _to_lock(manifest, tree))
    scripts = sorted(entry["name"] for entry in tree.values() if entry.get("hasInstallScript"))
    for path in sorted(p for p in tree if p.count("node_modules/") == 1):
        print(f"{tree[path]['name']} {tree[path]['version']}")
    if skipped:
        print(f"Skipped {len(skipped)} optional package{'s' if len(skipped) != 1 else ''} made for other platforms.")
    if scripts:
        print(f"Install scripts not run, as there is no Node here: {', '.join(scripts)}")
    seconds = time.monotonic() - started
    summary = f"added {len(wanted)} package{'s' if len(wanted) != 1 else ''}"
    if removed:
        summary += f", removed {removed}"
    print(f"{summary}, {len(tree)} in node_modules, in {seconds:.1f} s. Integrity checked.")
    return 0


def _to_lock(manifest, tree):
    packages = {"": {key: manifest[key] for key in ("name", "version", "dependencies", "devDependencies") if key in manifest}}
    for path, entry in sorted(tree.items()):
        packages[path] = {
            "version": entry["version"],
            "resolved": entry["dist"]["tarball"],
            "integrity": entry["dist"].get("integrity"),
        }
    return {"name": manifest.get("name", ""), "version": manifest.get("version", "0.0.0"), "lockfileVersion": 3, "requires": True, "packages": packages}


def _from_lock(lock, manifest):
    """The locked tree, when it still matches package.json's dependencies."""
    packages = lock.get("packages") or {}
    root = packages.get("") or {}
    for field in ("dependencies", "devDependencies"):
        if (root.get(field) or {}) != (manifest.get(field) or {}):
            return None
    tree = {}
    for path, entry in packages.items():
        if not path or "resolved" not in entry:
            continue
        name = path.rsplit("node_modules/", 1)[1]
        tree[path] = {"name": name, "version": entry["version"], "dist": {"tarball": entry["resolved"], "integrity": entry.get("integrity", "")}}
    return tree


def uninstall(root, names):
    manifest_path = os.path.join(root, "package.json")
    manifest = _read_json(manifest_path)
    for name in names:
        for field in ("dependencies", "devDependencies", "optionalDependencies"):
            (manifest.get(field) or {}).pop(name, None)
    _write_json(manifest_path, manifest)
    lock_path = os.path.join(root, "package-lock.json")
    if os.path.exists(lock_path):
        os.remove(lock_path)
    return install(root)


def main(args, root):
    command, rest = (args[0], args[1:]) if args else ("help", [])
    try:
        if command in ("install", "i", "add", "ci"):
            names = [a for a in rest if not a.startswith("-")]
            return install(root, names, dev=any(a in ("-D", "--save-dev") for a in rest))
        if command in ("uninstall", "remove", "rm", "un"):
            return uninstall(root, [a for a in rest if not a.startswith("-")])
        if command in ("ls", "list"):
            for path, version in sorted(_installed(root).items()):
                if path.count("node_modules") == 1:
                    print(f"{path.split('node_modules/', 1)[1]}@{version}")
            return 0
        if command == "init":
            path = os.path.join(root, "package.json")
            if os.path.exists(path):
                raise NpmError("package.json already exists")
            _write_json(path, {"name": os.path.basename(os.path.abspath(root)).lower().replace(" ", "-"), "version": "1.0.0", "private": True, "scripts": {}, "dependencies": {}})
            print("Wrote package.json")
            return 0
        if command in ("-v", "--version", "version"):
            print("pythilo npm 1 (registry installs; builds with esbuild in the app)")
            return 0
        if command == "run":
            print("npm run is handled by the app's terminal, which builds with esbuild.")
            return 1
        print(USAGE)
        return 0 if command == "help" else 1
    except NpmError as error:
        print(f"npm: {error}", file=__import__("sys").stderr)
        return 1
