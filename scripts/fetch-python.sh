#!/bin/bash
# Downloads the pinned CPython support package and checks its hash.
set -euo pipefail
cd "$(dirname "$0")/.."
source runtime/python-support.lock

if [ -d Vendor/Python.xcframework ]; then
  echo "Vendor/Python.xcframework already present"
  exit 0
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
curl -fsSL -o "$work/support.tar.gz" \
  "https://github.com/beeware/Python-Apple-support/releases/download/$PYTHON_SUPPORT_TAG/$PYTHON_SUPPORT_ASSET"
echo "$PYTHON_SUPPORT_SHA256  $work/support.tar.gz" | shasum -a 256 -c -
tar xzf "$work/support.tar.gz" -C "$work"
mkdir -p Vendor
mv "$work/Python.xcframework" Vendor/Python.xcframework
cat "$work/VERSIONS"
