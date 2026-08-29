#!/usr/bin/env bash
set -u

TIMEOUT_SECONDS="${MIRROR_CHECK_TIMEOUT:-10}"

check_url() {
  local label kind url result
  label="$1"
  kind="$2"
  url="$3"

  if result="$(curl --head --location --silent --show-error --fail \
    --max-time "$TIMEOUT_SECONDS" --output /dev/null \
    --write-out '%{http_code} %{time_total}' "$url" 2>/dev/null)"; then
    printf '%-8s %-6s OK   HTTP %s  %ss\n' "$label" "$kind" ${result}
  else
    printf '%-8s %-6s FAIL %s\n' "$label" "$kind" "$url"
  fi
}

check_url TUNA conda https://mirrors.tuna.tsinghua.edu.cn/anaconda/cloud/conda-forge/noarch/repodata.json.zst
check_url TUNA pypi  https://pypi.tuna.tsinghua.edu.cn/simple/pip/
check_url BFSU conda https://mirrors.bfsu.edu.cn/anaconda/cloud/conda-forge/noarch/repodata.json.zst
check_url BFSU pypi  https://mirrors.bfsu.edu.cn/pypi/web/simple/pip/
check_url USTC conda https://mirrors.ustc.edu.cn/anaconda/cloud/conda-forge/noarch/repodata.json.zst
check_url USTC pypi  https://mirrors.ustc.edu.cn/pypi/simple/pip/
check_url NJU conda  https://mirror.nju.edu.cn/anaconda/cloud/conda-forge/noarch/repodata.json.zst
check_url NJU pypi   https://mirror.nju.edu.cn/pypi/web/simple/pip/
