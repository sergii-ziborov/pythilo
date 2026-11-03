#!/bin/bash
# Builds pydantic-core for iOS devices and the simulator. Nobody publishes cp314 iOS
# wheels of it, and FastAPI needs it. Needs rustup with the aarch64-apple-ios and
# aarch64-apple-ios-sim targets, and Xcode. Writes wheels to build/native/wheels,
# where scripts/vendor-packages.py picks them up.
#
# The extension links Python.framework like BeeWare's own iOS wheels do, so PyO3 is
# told through a config file to add no link flags of its own.
set -euo pipefail

VERSION="${1:-2.50.2}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$ROOT/build/native"
SOURCE="$WORK/pydantic_core-$VERSION"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
export IPHONEOS_DEPLOYMENT_TARGET=18.0
export CARGO_TARGET_DIR="$WORK/target"

mkdir -p "$WORK/wheels" "$WORK/support"
if [[ ! -d "$SOURCE" ]]; then
  python3 -m pip download "pydantic-core==$VERSION" --no-binary :all: --no-deps -d "$WORK" --quiet
  tar -xzf "$WORK/pydantic_core-$VERSION.tar.gz" -C "$WORK"
fi
if [[ ! -d "$WORK/support/Python.xcframework/ios-arm64" ]]; then
  tar -xzf "$ROOT/build/python-support/support.tar.gz" -C "$WORK/support" \
    "Python.xcframework/ios-arm64" "Python.xcframework/ios-arm64_x86_64-simulator"
fi

build() {
  local triple="$1" slice="$2" platform="$3"
  local framework="$WORK/support/Python.xcframework/$slice"
  printf 'implementation=CPython\nversion=3.14\nshared=true\nabi3=false\nlib_name=python3.14\npointer_width=64\nsuppress_build_script_link_lines=true\n' > "$WORK/pyo3-$platform.cfg"
  (
    cd "$SOURCE"
    PYO3_CONFIG_FILE="$WORK/pyo3-$platform.cfg" \
    RUSTFLAGS="-C link-arg=-F$framework -C link-arg=-framework -C link-arg=Python -C link-arg=-Wl,-install_name,@rpath/_pydantic_core.so" \
      cargo build --release --lib --target "$triple" --quiet
  )
  python3 - "$SOURCE" "$CARGO_TARGET_DIR/$triple/release/lib_pydantic_core.dylib" "$platform" "$VERSION" "$WORK/wheels" <<'PYTHON'
import base64, hashlib, pathlib, sys, zipfile

source, library, platform, version, out = sys.argv[1:]
package = pathlib.Path(source) / "python" / "pydantic_core"
tag = f"cp314-cp314-ios_18_0_arm64_{platform}"
info = f"pydantic_core-{version}.dist-info"
files = {}
for path in sorted(package.rglob("*")):
    if path.is_file() and "_pydantic_core" not in path.relative_to(package).parts[:1]:
        files[f"pydantic_core/{path.relative_to(package)}"] = path.read_bytes()
files[f"pydantic_core/_pydantic_core.cpython-314-{platform}.so"] = pathlib.Path(library).read_bytes()
files[f"{info}/METADATA"] = (
    f"Metadata-Version: 2.1\nName: pydantic_core\nVersion: {version}\n"
    "Requires-Python: >=3.10\nRequires-Dist: typing-extensions>=4.16.0\nLicense-Expression: MIT\n"
).encode()
files[f"{info}/WHEEL"] = f"Wheel-Version: 1.0\nGenerator: pythilo\nRoot-Is-Purelib: false\nTag: {tag}\n".encode()
files[f"{info}/licenses/LICENSE"] = (pathlib.Path(source) / "LICENSE").read_bytes()

def digest(data):
    return "sha256=" + base64.urlsafe_b64encode(hashlib.sha256(data).digest()).rstrip(b"=").decode()

record = "".join(f"{name},{digest(data)},{len(data)}\n" for name, data in files.items()) + f"{info}/RECORD,,\n"
wheel = pathlib.Path(out) / f"pydantic_core-{version}-{tag}.whl"
with zipfile.ZipFile(wheel, "w", zipfile.ZIP_DEFLATED) as archive:
    for name, data in files.items():
        archive.writestr(name, data)
    archive.writestr(f"{info}/RECORD", record)
print(wheel)
PYTHON
}

build aarch64-apple-ios ios-arm64 iphoneos
build aarch64-apple-ios-sim ios-arm64_x86_64-simulator iphonesimulator
