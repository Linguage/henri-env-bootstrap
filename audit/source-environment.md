# `henri_env` source audit

Snapshot date: 2026-08-29

## Runtime

- Host: macOS 26.6.1, Apple Silicon (`arm64`)
- Conda: 25.9.1 with the libmamba solver
- Environment prefix: `~/miniconda3/envs/henri_env`
- Python: 3.13.9, native `arm64`
- Conda subdir: `osx-arm64`
- Configured channel: `conda-forge`; the environment also retains 18 packages from `defaults`
- Conda environment variables: none

## Inventory

- 345 records reported by `conda list`
- 245 records currently presented as Conda-managed by `conda list`
- 255 Conda artifacts retained in `conda-meta` and the explicit lock
- 100 PyPI package records
- Requested Conda capabilities: Python, pandas, JupyterLab, Notebook, NumPy,
  IPython kernel, Matplotlib, widgets, SymPy, OSMnx, geopy, Ruff, and mypy
- External commands found on the source Mac: Homebrew `ffmpeg`, system `git`,
  and MacTeX `latex`

## Findings that should not be copied literally

1. `pip check` fails because `zhipuai==2.1.5.20250825` requires
   `PyJWT>=2.8,<2.9`, while the source environment exposes PyJWT 2.11.0.
2. There are 22 normalized package names with duplicate `.dist-info` metadata,
   including AnyIO, attrs, Click, MCP, Pydantic, Requests, Starlette, and Uvicorn.
   In several cases the imported code and metadata report different versions.
3. The editable installs still point at two paths that no longer exist:
   `~/Documents/EmacsNotes/MiaoYan-Notes` and
   `~/Documents/work-studio/zotero-workbench`.
4. Those projects now live elsewhere on the source Mac. `projects.lock` records
   their GitHub repositories and the audited commits without embedding local paths.

The installer therefore recreates the same working toolset in a clean environment,
pins PyJWT 2.8.0 and Starlette 0.49.3 for compatibility, installs `ffmpeg` through
Conda, and recreates the two local packages as editable Git checkouts.

The files under `locks/` are evidence snapshots of the original environment. They
are not the default installation input because doing so would preserve the polluted
mixed Conda/pip state.
