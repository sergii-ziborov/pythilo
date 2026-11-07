#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/fetch-python.sh
python3 scripts/generate-finetune-content.py
python3 scripts/generate-research-content.py
python3 scripts/build-content-packs.py
xcodegen generate
