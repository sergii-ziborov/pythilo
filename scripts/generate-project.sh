#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/fetch-python.sh
xcodegen generate
