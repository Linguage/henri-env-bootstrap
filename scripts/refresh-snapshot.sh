#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_NAME="${1:-henri_env}"
TEMP_JSON="$(mktemp)"
trap 'rm -f "$TEMP_JSON"' EXIT

command -v conda >/dev/null 2>&1 || { echo "conda is required" >&2; exit 1; }

conda list --explicit --md5 --name "$ENV_NAME" > \
  "$ROOT_DIR/locks/conda-osx-arm64.explicit"

conda list --json --name "$ENV_NAME" > "$TEMP_JSON"
conda run --name base python -c '
import json
import sys

with open(sys.argv[1], encoding="utf-8") as stream:
    packages = json.load(stream)
for package in sorted(packages, key=lambda item: item["name"].lower()):
    if package["channel"] == "pypi":
        print("{}=={}".format(package["name"], package["version"]))
' "$TEMP_JSON" | sed '/^$/d' > "$ROOT_DIR/locks/pip-observed.txt"

echo "Refreshed lock snapshots from '$ENV_NAME'."
echo "Review duplicates and compatibility before changing the clean installer inputs."
