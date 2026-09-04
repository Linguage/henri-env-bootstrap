#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

bash -n bootstrap.sh scripts/check-mirrors.sh scripts/refresh-snapshot.sh \
  scripts/smoke-test.sh
python3 -m py_compile scripts/audit_environment.py scripts/verify.py \
  tests/test_audit_environment.py
python3 -m unittest -v
./bootstrap.sh --help >/dev/null

echo "Smoke tests passed; no Conda environment was created or modified."
