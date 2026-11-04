#!/bin/bash
# Builds PyTorch for iOS with https://github.com/sergii-ziborov/torch-ios, at a
# pinned commit, against Pythilo's own CPython and NumPy, and leaves the wheel in
# build/native/wheels, where scripts/vendor-packages.py picks it up.
#
#   scripts/build-torch.sh iphonesimulator|iphoneos [fetch|configure|build|wheel|all]
#
# Run scripts/vendor-packages.py first: NumPy's headers come from the bundled NumPy.
# Each platform takes about an hour and 6 GB while it builds.
set -euo pipefail

commit=72b5432f78d0e4d9204e7bffb70d35d9c0b37714
root=$(cd "$(dirname "$0")/.." && pwd)
tools="$root/build/torch-ios"
platform=${1:?iphonesimulator or iphoneos}

if [[ ! -d "$tools/.git" ]]; then
  git clone --quiet https://github.com/sergii-ziborov/torch-ios "$tools"
fi
if [[ "$(git -C "$tools" rev-parse HEAD)" != "$commit" ]]; then
  git -C "$tools" fetch --quiet origin
  git -C "$tools" checkout --quiet "$commit"
fi

WORK="$root/build/torch" \
DIST="$root/build/native/wheels" \
PYTHON_XCFRAMEWORK="$root/Vendor/Python.xcframework" \
NUMPY_INCLUDE="$root/build/app_packages/$platform/numpy/_core/include" \
  exec "$tools/build.sh" "$@"
