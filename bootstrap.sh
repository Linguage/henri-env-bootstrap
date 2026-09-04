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
CHECK_ONLY=0
DRY_RUN=0
ALIGNMENT_NEEDED=0
RECONCILE_BLOCKED=0
UNSAFE_INCREMENTAL=0

usage() {
  sed -n '/^# BEGIN_USAGE$/,/^# END_USAGE$/p' "$0" \
    | sed -n '/^# BEGIN_USAGE$/d; /^# END_USAGE$/d; s/^# \{0,1\}//p'
}

# BEGIN_USAGE
# Reconcile henri_env with the repository's requested configuration.
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
#   --check              Audit requested state and health without changing anything
#   --dry-run            Show the reconciliation plan without changing anything
#   --recreate           Remove and rebuild an existing target environment
#   --verify-only        Run health verification without checking requested versions
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
    --check) CHECK_ONLY=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    --verify-only) VERIFY_ONLY=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

if ((CHECK_ONLY + VERIFY_ONLY > 1)); then
  echo "--check and --verify-only are mutually exclusive." >&2
  exit 2
fi
if ((DRY_RUN && VERIFY_ONLY)); then
  echo "--dry-run cannot be combined with --verify-only." >&2
  exit 2
fi
if ((RECREATE && (CHECK_ONLY || VERIFY_ONLY))); then
  echo "--recreate cannot be combined with --check or --verify-only." >&2
  exit 2
fi

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

if CONDA_BIN="$(find_conda)"; then
  :
elif ((CHECK_ONLY || DRY_RUN || VERIFY_ONLY)); then
  echo "Conda is not installed or discoverable." >&2
  if ((DRY_RUN)); then
    echo "  - would install Miniforge before creating the target environment"
    exit 0
  fi
  if ((CHECK_ONLY)); then
    exit 4
  fi
  exit 1
else
  CONDA_BIN="$(install_miniforge)"
fi

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

base_python() {
  local conda_base
  conda_base="$($CONDA_BIN info --base)"
  printf '%s\n' "${conda_base}/bin/python"
}

target_python() {
  "$CONDA_BIN" run -n "$ENV_NAME" python -c 'import sys; print(sys.executable)'
}

preflight_metadata_safety() {
  local python_bin output package_name
  local -a duplicates=()
  python_bin="$(target_python)"
  output="$("$python_bin" "$ROOT_DIR/scripts/audit_environment.py" \
    --component metadata \
    --format specs \
    --exit-zero)"
  while IFS= read -r package_name; do
    [[ -n "$package_name" ]] && duplicates[${#duplicates[@]}]="$package_name"
  done <<< "$output"

  if ((${#duplicates[@]} == 0)); then
    echo "Python distribution metadata has no duplicate records."
    return
  fi

  ALIGNMENT_NEEDED=1
  UNSAFE_INCREMENTAL=1
  echo "Incremental reconciliation is unsafe: duplicate Python metadata was found." >&2
  printf '  - %s\n' "${duplicates[@]}" >&2
  if ((!CHECK_ONLY && !DRY_RUN)); then
    echo "No environment changes were made. Run --check for details or use --recreate explicitly." >&2
    exit 3
  fi
}

reconcile_conda_packages() {
  local output spec
  local -a changes=()
  output="$("$(base_python)" "$ROOT_DIR/scripts/audit_environment.py" \
    --component conda \
    --environment "$ROOT_DIR/environment.yml" \
    --conda-bin "$CONDA_BIN" \
    --env-name "$ENV_NAME" \
    --format specs \
    --exit-zero)"
  while IFS= read -r spec; do
    [[ -n "$spec" ]] && changes[${#changes[@]}]="$spec"
  done <<< "$output"

  if ((${#changes[@]} == 0)); then
    echo "Conda direct packages already match environment.yml."
    return
  fi

  ALIGNMENT_NEEDED=1
  echo "Conda packages requiring reconciliation:"
  printf '  - %s\n' "${changes[@]}"
  if ((CHECK_ONLY || DRY_RUN)); then
    return
  fi

  CONDARC="$CONDARC_FILE" "$CONDA_BIN" install \
    --yes --name "$ENV_NAME" "${changes[@]}"
}

reconcile_pip_packages() {
  local python_bin output spec
  local -a changes=()
  python_bin="$(target_python)"
  output="$("$python_bin" "$ROOT_DIR/scripts/audit_environment.py" \
    --component pip \
    --requirements "$ROOT_DIR/requirements-pip.txt" \
    --format specs \
    --exit-zero)"
  while IFS= read -r spec; do
    [[ -n "$spec" ]] && changes[${#changes[@]}]="$spec"
  done <<< "$output"

  if ((${#changes[@]} == 0)); then
    echo "Direct pip packages already match requirements-pip.txt."
    return
  fi

  ALIGNMENT_NEEDED=1
  echo "pip packages requiring reconciliation:"
  printf '  - %s\n' "${changes[@]}"
  if ((CHECK_ONLY || DRY_RUN)); then
    return
  fi

  "$python_bin" -m pip install \
    --disable-pip-version-check \
    --index-url "$PIP_INDEX_URL" \
    "${changes[@]}"
}

editable_project_location() {
  local python_bin="$1"
  local project_name="$2"
  PIP_DISABLE_PIP_VERSION_CHECK=1 PIP_NO_CACHE_DIR=1 \
    "$python_bin" -m pip show "$project_name" 2>/dev/null \
    | sed -n 's/^Editable project location: //p'
}

reconcile_projects() {
  local python_bin project_name repository commit directory destination
  local current_commit editable_location needs_install
  ((INSTALL_PROJECTS)) || return 0
  command -v git >/dev/null 2>&1 || { echo "git is required for editable projects." >&2; return 1; }
  python_bin="$(target_python)"

  if [[ ! -d "$PROJECTS_DIR" ]]; then
    ALIGNMENT_NEEDED=1
    echo "Editable-project root is missing: $PROJECTS_DIR"
    if ((CHECK_ONLY || DRY_RUN)); then
      echo "  - would create it when applying the plan"
    else
      mkdir -p "$PROJECTS_DIR"
    fi
  fi

  while IFS='|' read -r project_name repository commit directory; do
    [[ -n "$project_name" && "${project_name:0:1}" != "#" ]] || continue
    destination="${PROJECTS_DIR}/${directory}"
    needs_install=0

    if [[ ! -e "$destination" ]]; then
      ALIGNMENT_NEEDED=1
      needs_install=1
      echo "$project_name checkout is missing: $destination"
      if ((CHECK_ONLY || DRY_RUN)); then
        echo "  - would clone $repository at $commit"
      else
        git clone "$repository" "$destination"
        git -C "$destination" checkout --detach "$commit"
      fi
    elif [[ ! -d "$destination/.git" ]]; then
      echo "Expected a Git checkout at $destination; refusing to overwrite it." >&2
      RECONCILE_BLOCKED=1
      continue
    else
      current_commit="$(git -C "$destination" rev-parse HEAD)"
      if [[ "$current_commit" != "$commit" ]]; then
        ALIGNMENT_NEEDED=1
        if [[ -n "$(git -C "$destination" status --porcelain)" ]]; then
          echo "$project_name checkout has local changes and differs from its lock." >&2
          echo "  current: $current_commit" >&2
          echo "  lock:    $commit" >&2
          RECONCILE_BLOCKED=1
        elif ((CHECK_ONLY || DRY_RUN)); then
          echo "$project_name would move from $current_commit to $commit"
        else
          if ! git -C "$destination" cat-file -e "${commit}^{commit}" 2>/dev/null; then
            git -C "$destination" fetch --prune origin
          fi
          git -C "$destination" checkout --detach "$commit"
        fi
      fi
    fi

    editable_location="$(editable_project_location "$python_bin" "$project_name")"
    if [[ "${editable_location%/}" != "${destination%/}" ]]; then
      ALIGNMENT_NEEDED=1
      needs_install=1
      echo "$project_name editable install requires reconciliation."
      if [[ -n "$editable_location" ]]; then
        echo "  current: $editable_location"
      else
        echo "  current: not installed"
      fi
      echo "  target:  $destination"
    fi

    if ((needs_install && !CHECK_ONLY && !DRY_RUN && !RECONCILE_BLOCKED)); then
      "$python_bin" -m pip install \
        --disable-pip-version-check --no-deps --editable "$destination"
    fi
  done < "$ROOT_DIR/projects.lock"
}

reconcile_kernel() {
  local python_bin output
  ((REGISTER_KERNEL)) || return 0
  python_bin="$(target_python)"
  output="$("$python_bin" "$ROOT_DIR/scripts/audit_environment.py" \
    --component kernel \
    --env-name "$ENV_NAME" \
    --format specs \
    --exit-zero)"
  if [[ -z "$output" ]]; then
    echo "Jupyter kernel '$ENV_NAME' already points to the target environment."
    return
  fi

  ALIGNMENT_NEEDED=1
  echo "Jupyter kernel '$ENV_NAME' is missing or points to another Python."
  if ((CHECK_ONLY || DRY_RUN)); then
    echo "  - would register the target environment kernel"
    return
  fi
  "$python_bin" -m ipykernel install \
    --user --name "$ENV_NAME" --display-name "Python ($ENV_NAME)"
}

environment_present=0
if environment_exists; then
  environment_present=1
fi

if ((RECREATE && environment_present)); then
  ALIGNMENT_NEEDED=1
  if ((DRY_RUN)); then
    echo "Would remove and recreate Conda environment '$ENV_NAME'."
    exit 0
  fi
  echo "Removing existing Conda environment '$ENV_NAME'"
  "$CONDA_BIN" env remove --yes --name "$ENV_NAME"
  environment_present=0
fi

if ((!environment_present)); then
  ALIGNMENT_NEEDED=1
  if ((CHECK_ONLY || DRY_RUN)); then
    echo "Conda environment '$ENV_NAME' is missing."
    echo "  - would create it from environment.yml"
    if ((CHECK_ONLY)); then
      exit 4
    fi
    exit 0
  fi
  echo "Creating Conda environment '$ENV_NAME'"
  echo "Using package mirror: $MIRROR"
  CONDARC="$CONDARC_FILE" "$CONDA_BIN" env create \
    --yes --name "$ENV_NAME" --file "$ROOT_DIR/environment.yml"
fi

preflight_metadata_safety
reconcile_conda_packages
reconcile_pip_packages
reconcile_projects
reconcile_kernel

if ((RECONCILE_BLOCKED && !CHECK_ONLY && !DRY_RUN)); then
  echo "Reconciliation stopped because a managed project needs manual attention." >&2
  exit 1
fi

if ((CHECK_ONLY || DRY_RUN)); then
  health_status=0
  run_verify || health_status=$?
  if ((CHECK_ONLY && (ALIGNMENT_NEEDED || health_status != 0))); then
    echo "Check found configuration drift or health problems." >&2
    exit 4
  fi
  if ((DRY_RUN)); then
    echo "Dry run complete; no environment changes were made."
  else
    echo "Requested configuration and environment health are aligned."
  fi
  exit 0
fi

if ! run_verify; then
  echo "Incremental reconciliation could not restore full environment health." >&2
  echo "Review the verification output; duplicate stale metadata may require --recreate." >&2
  exit 1
fi

conda_base="$($CONDA_BIN info --base)"
echo
echo "Environment reconciliation complete. Activate it with:"
echo "  source \"${conda_base}/etc/profile.d/conda.sh\""
echo "  conda activate ${ENV_NAME}"
