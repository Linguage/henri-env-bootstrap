#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_NAME="${HENRI_ENV_NAME:-henri_env}"
PROJECTS_DIR="${HENRI_PROJECTS_DIR:-${HOME}/henri-projects}"
MIRROR="${HENRI_MIRROR:-tuna}"
INSTALL_PROJECTS=1
REGISTER_KERNEL=1
RECREATE=0
VERIFY_ONLY=0

usage() {
  sed -n '/^# BEGIN_USAGE$/,/^# END_USAGE$/p' "$0" \
    | sed -n '/^# BEGIN_USAGE$/d; /^# END_USAGE$/d; s/^# \{0,1\}//p'
}

# BEGIN_USAGE
# Recreate the clean henri_env Conda environment.
#
# Usage:
#   ./bootstrap.sh [options]
#
# Options:
#   --name NAME          Conda environment name (default: henri_env)
#   --projects-dir DIR   Where editable Git projects are cloned
#   --mirror NAME        tuna, bfsu, ustc, nju, or official (default: tuna)
#   --skip-projects      Do not clone/install the two editable projects
#   --no-kernel          Do not register a Jupyter kernel
#   --recreate           Remove an existing target environment first
#   --verify-only        Only verify an existing target environment
#   -h, --help           Show this help
#
# Environment variables:
#   HENRI_ENV_NAME       Alternative environment name
#   HENRI_PROJECTS_DIR   Alternative editable-project root
#   HENRI_MIRROR         Alternative package mirror
# END_USAGE

while (($#)); do
  case "$1" in
    --name)
      [[ $# -ge 2 ]] || { echo "--name requires a value" >&2; exit 2; }
      ENV_NAME="$2"
      shift 2
      ;;
    --projects-dir)
      [[ $# -ge 2 ]] || { echo "--projects-dir requires a value" >&2; exit 2; }
      PROJECTS_DIR="$2"
      shift 2
      ;;
    --mirror)
      [[ $# -ge 2 ]] || { echo "--mirror requires a value" >&2; exit 2; }
      MIRROR="$2"
      shift 2
      ;;
    --skip-projects) INSTALL_PROJECTS=0; shift ;;
    --no-kernel) REGISTER_KERNEL=0; shift ;;
    --recreate) RECREATE=1; shift ;;
    --verify-only) VERIFY_ONLY=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

case "$MIRROR" in
  tuna)
    PIP_INDEX_URL="https://pypi.tuna.tsinghua.edu.cn/simple"
    MINIFORGE_BASE_URL="https://mirrors.tuna.tsinghua.edu.cn/github-release/conda-forge/miniforge/LatestRelease"
    ;;
  bfsu)
    PIP_INDEX_URL="https://mirrors.bfsu.edu.cn/pypi/web/simple"
    MINIFORGE_BASE_URL="https://mirrors.bfsu.edu.cn/github-release/conda-forge/miniforge/LatestRelease"
    ;;
  ustc)
    PIP_INDEX_URL="https://mirrors.ustc.edu.cn/pypi/simple"
    MINIFORGE_BASE_URL="https://mirrors.ustc.edu.cn/github-release/conda-forge/miniforge/LatestRelease"
    ;;
  nju)
    PIP_INDEX_URL="https://mirror.nju.edu.cn/pypi/web/simple"
    MINIFORGE_BASE_URL="https://mirror.nju.edu.cn/github-release/conda-forge/miniforge/LatestRelease"
    ;;
  official)
    PIP_INDEX_URL="https://pypi.org/simple"
    MINIFORGE_BASE_URL="https://github.com/conda-forge/miniforge/releases/latest/download"
    ;;
  *)
    echo "Unsupported mirror '$MIRROR'. Choose tuna, bfsu, ustc, nju, or official." >&2
    exit 2
    ;;
esac

CONDARC_FILE="${ROOT_DIR}/mirrors/${MIRROR}.condarc.yml"

find_conda() {
  if command -v conda >/dev/null 2>&1; then
    command -v conda
    return
  fi

  local candidate
  for candidate in \
    "${HOME}/miniforge3/bin/conda" \
    "${HOME}/miniconda3/bin/conda" \
    "/opt/homebrew/Caskroom/miniforge/base/bin/conda"; do
    if [[ -x "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return
    fi
  done
  return 1
}

install_miniforge() {
  local system machine platform arch url temp_dir installer prefix
  system="$(uname -s)"
  machine="$(uname -m)"

  case "$system" in
    Darwin) platform="MacOSX" ;;
    Linux) platform="Linux" ;;
    *) echo "Unsupported operating system: $system" >&2; exit 1 ;;
  esac

  case "$machine" in
    arm64) arch="arm64" ;;
    aarch64) arch="aarch64" ;;
    x86_64) arch="x86_64" ;;
    *) echo "Unsupported CPU architecture: $machine" >&2; exit 1 ;;
  esac

  if [[ "$platform" == "MacOSX" && "$arch" == "aarch64" ]]; then
    arch="arm64"
  elif [[ "$platform" == "Linux" && "$arch" == "arm64" ]]; then
    arch="aarch64"
  fi

  command -v curl >/dev/null 2>&1 || {
    echo "curl is required to install Miniforge." >&2
    exit 1
  }

  prefix="${HOME}/miniforge3"
  if [[ -e "$prefix" ]]; then
    echo "Cannot install Miniforge: $prefix already exists but conda was not found." >&2
    exit 1
  fi

  url="${MINIFORGE_BASE_URL}/Miniforge3-${platform}-${arch}.sh"
  temp_dir="$(mktemp -d)"
  installer="${temp_dir}/miniforge.sh"
  trap 'rm -rf "$temp_dir"' RETURN

  echo "Conda was not found; installing Miniforge in $prefix" >&2
  curl --fail --location --silent --show-error "$url" --output "$installer"
  bash "$installer" -b -p "$prefix" >&2
  printf '%s\n' "${prefix}/bin/conda"
}

CONDA_BIN="$(find_conda || install_miniforge)"

environment_exists() {
  "$CONDA_BIN" env list | awk -v target="$ENV_NAME" '$1 == target { found = 1 } END { exit !found }'
}

run_verify() {
  "$CONDA_BIN" run -n "$ENV_NAME" python "$ROOT_DIR/scripts/verify.py"
}

if ((VERIFY_ONLY)); then
  environment_exists || { echo "Conda environment '$ENV_NAME' does not exist." >&2; exit 1; }
  run_verify
  exit 0
fi

if environment_exists; then
  if ((RECREATE)); then
    echo "Removing existing Conda environment '$ENV_NAME'"
    "$CONDA_BIN" env remove --yes --name "$ENV_NAME"
  else
    echo "Conda environment '$ENV_NAME' already exists." >&2
    echo "Use --recreate to replace it, or --name to install a separate copy." >&2
    exit 3
  fi
fi

echo "Creating Conda environment '$ENV_NAME'"
echo "Using package mirror: $MIRROR"
CONDARC="$CONDARC_FILE" "$CONDA_BIN" env create \
  --yes --name "$ENV_NAME" --file "$ROOT_DIR/environment.yml"

echo "Installing pinned direct pip packages"
"$CONDA_BIN" run -n "$ENV_NAME" python -m pip install \
  --disable-pip-version-check \
  --index-url "$PIP_INDEX_URL" \
  --requirement "$ROOT_DIR/requirements-pip.txt"

if ((INSTALL_PROJECTS)); then
  command -v git >/dev/null 2>&1 || { echo "git is required for editable projects." >&2; exit 1; }
  mkdir -p "$PROJECTS_DIR"

  while IFS='|' read -r project_name repository commit directory; do
    [[ -n "$project_name" && "${project_name:0:1}" != "#" ]] || continue
    destination="${PROJECTS_DIR}/${directory}"

    if [[ ! -e "$destination" ]]; then
      echo "Cloning $project_name"
      git clone "$repository" "$destination"
      git -C "$destination" checkout --detach "$commit"
    elif [[ ! -d "$destination/.git" ]]; then
      echo "Expected a Git checkout at $destination; refusing to overwrite it." >&2
      exit 1
    else
      current_commit="$(git -C "$destination" rev-parse HEAD)"
      if [[ "$current_commit" != "$commit" ]]; then
        echo "Using existing $project_name checkout at $current_commit (lock: $commit)"
      fi
    fi

    "$CONDA_BIN" run -n "$ENV_NAME" python -m pip install \
      --disable-pip-version-check --no-deps --editable "$destination"
  done < "$ROOT_DIR/projects.lock"
fi

if ((REGISTER_KERNEL)); then
  echo "Registering Jupyter kernel '$ENV_NAME'"
  "$CONDA_BIN" run -n "$ENV_NAME" python -m ipykernel install \
    --user --name "$ENV_NAME" --display-name "Python ($ENV_NAME)"
fi

run_verify

conda_base="$($CONDA_BIN info --base)"
echo
echo "Installation complete. Activate it with:"
echo "  source \"${conda_base}/etc/profile.d/conda.sh\""
echo "  conda activate ${ENV_NAME}"
