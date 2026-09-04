#!/usr/bin/env python3
"""Compare an existing environment with this repository's requested state.

The script deliberately checks only direct requirements.  It does not ask Conda
or pip for newer releases, so an audit never turns into an implicit upgrade.
Exit code 10 means that one or more requested items are missing or drifted.
"""

from __future__ import annotations

import argparse
import importlib.metadata
import json
import os
import re
import subprocess
import sys
from collections import defaultdict
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Iterable


DRIFT_EXIT = 10


@dataclass(frozen=True)
class RequestedSpec:
    name: str
    version: str | None
    raw: str


@dataclass(frozen=True)
class Drift:
    component: str
    spec: str
    installed: tuple[str, ...]
    reason: str


def normalize_name(value: str) -> str:
    """Return the normalized package name used by Conda and Python metadata."""
    return re.sub(r"[-_.]+", "-", value).lower()


def parse_conda_environment(path: Path) -> list[RequestedSpec]:
    """Read the top-level dependency list from the repository environment.yml."""
    requested: list[RequestedSpec] = []
    in_dependencies = False

    for line_number, original in enumerate(
        path.read_text(encoding="utf-8").splitlines(), 1
    ):
        content = original.split("#", 1)[0].rstrip()
        if not content.strip():
            continue
        if content == "dependencies:":
            in_dependencies = True
            continue
        if not in_dependencies:
            continue

        indent = len(content) - len(content.lstrip())
        if indent == 0:
            break
        if indent != 2 or not content.lstrip().startswith("- "):
            continue

        raw = content.lstrip()[2:].strip()
        if raw == "pip:" or raw.startswith("pip:"):
            continue
        match = re.fullmatch(r"([A-Za-z0-9_.-]+)(?:=([^=<>!~\s]+))?", raw)
        if not match:
            raise ValueError(
                f"Unsupported Conda requirement at {path}:{line_number}: {raw!r}"
            )
        requested.append(
            RequestedSpec(
                name=normalize_name(match.group(1)),
                version=match.group(2),
                raw=raw,
            )
        )
    if not requested:
        raise ValueError(f"No dependencies found in {path}")
    return requested


def parse_pip_requirements(path: Path) -> list[RequestedSpec]:
    """Read direct, exact pip requirements without resolving the dependency graph."""
    requested: list[RequestedSpec] = []
    for line_number, original in enumerate(
        path.read_text(encoding="utf-8").splitlines(), 1
    ):
        raw = original.split(" #", 1)[0].strip()
        if not raw or raw.startswith("#"):
            continue
        if raw.startswith(("-r", "--requirement", "-c", "--constraint")):
            raise ValueError(
                f"Nested requirement files are not supported at {path}:{line_number}"
            )
        if "==" in raw:
            package_name, version = raw.split("==", 1)
        else:
            package_name, version = raw, None
        if not re.fullmatch(r"[A-Za-z0-9_.-]+", package_name) or (
            version is not None and not version
        ):
            raise ValueError(
                f"Only package names and exact == pins are supported at "
                f"{path}:{line_number}: {raw!r}"
            )
        requested.append(
            RequestedSpec(
                name=normalize_name(package_name),
                version=version,
                raw=raw,
            )
        )
    if not requested:
        raise ValueError(f"No requirements found in {path}")
    return requested


def load_conda_records(
    *, conda_json: Path | None, conda_bin: str | None, env_name: str | None
) -> list[dict[str, object]]:
    if conda_json is not None:
        return json.loads(conda_json.read_text(encoding="utf-8"))
    if not conda_bin or not env_name:
        raise ValueError(
            "Conda audit requires --conda-json or --conda-bin and --env-name"
        )
    result = subprocess.run(
        [conda_bin, "list", "--json", "--name", env_name],
        check=False,
        capture_output=True,
        text=True,
    )
    if result.returncode:
        raise RuntimeError(result.stderr.strip() or result.stdout.strip())
    return json.loads(result.stdout)


def conda_versions(records: Iterable[dict[str, object]]) -> dict[str, set[str]]:
    versions: defaultdict[str, set[str]] = defaultdict(set)
    for record in records:
        if record.get("channel") == "pypi":
            continue
        name = str(record.get("name") or "")
        version = str(record.get("version") or "")
        if name and version:
            versions[normalize_name(name)].add(version)
    return dict(versions)


def pip_versions() -> dict[str, set[str]]:
    return {name: set(found) for name, found in pip_distribution_versions().items()}


def pip_distribution_versions() -> dict[str, list[str]]:
    versions: defaultdict[str, list[str]] = defaultdict(list)
    for distribution in importlib.metadata.distributions():
        name = distribution.metadata.get("Name") or ""
        if name:
            versions[normalize_name(name)].append(distribution.version)
    return dict(versions)


def audit_metadata() -> list[Drift]:
    drift: list[Drift] = []
    for name, versions in sorted(pip_distribution_versions().items()):
        if len(versions) > 1:
            drift.append(
                Drift(
                    "metadata",
                    name,
                    tuple(sorted(versions)),
                    "duplicate distribution metadata",
                )
            )
    return drift


def audit_requested(
    component: str,
    requested: Iterable[RequestedSpec],
    installed: dict[str, set[str]],
    *,
    conda_match: bool,
) -> list[Drift]:
    drift: list[Drift] = []
    for requirement in requested:
        found = installed.get(requirement.name, set())
        if not found:
            drift.append(Drift(component, requirement.raw, (), "missing"))
            continue
        if requirement.version is None:
            continue
        if conda_match:
            matches = {
                version
                for version in found
                if version == requirement.version
                or version.startswith(f"{requirement.version}.")
            }
        else:
            matches = {version for version in found if version == requirement.version}
        if matches != found:
            drift.append(
                Drift(
                    component,
                    requirement.raw,
                    tuple(sorted(found)),
                    "version drift" if len(found) == 1 else "duplicate versions",
                )
            )
    return drift


def jupyter_data_directory() -> Path:
    try:
        from jupyter_core.paths import jupyter_data_dir

        return Path(jupyter_data_dir())
    except ImportError:
        configured = os.environ.get("JUPYTER_DATA_DIR")
        if configured:
            return Path(configured).expanduser()
        if sys.platform == "darwin":
            return Path.home() / "Library" / "Jupyter"
        data_home = Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local/share"))
        return data_home / "jupyter"


def audit_kernel(
    env_name: str,
    *,
    data_dir: Path | None = None,
    executable: Path | None = None,
) -> list[Drift]:
    root = data_dir or jupyter_data_directory()
    expected_executable = (executable or Path(sys.executable)).resolve()
    candidates = {
        root / "kernels" / env_name,
        root / "kernels" / env_name.lower(),
    }
    kernel_file = next(
        (
            item / "kernel.json"
            for item in candidates
            if (item / "kernel.json").is_file()
        ),
        None,
    )
    if kernel_file is None:
        return [Drift("kernel", env_name, (), "missing")]
    try:
        data = json.loads(kernel_file.read_text(encoding="utf-8"))
        argv = data.get("argv") or []
        actual_executable = Path(argv[0]).expanduser().resolve() if argv else None
    except (OSError, ValueError, TypeError) as exc:
        return [Drift("kernel", env_name, (), f"invalid kernel.json: {exc}")]
    if actual_executable != expected_executable:
        rendered = (str(actual_executable),) if actual_executable else ()
        return [Drift("kernel", env_name, rendered, "points to another Python")]
    return []


def render(drift: list[Drift], output_format: str, component: str) -> None:
    if output_format == "specs":
        for item in drift:
            print(item.spec)
        return
    if output_format == "json":
        print(
            json.dumps([asdict(item) for item in drift], ensure_ascii=False, indent=2)
        )
        return
    if not drift:
        print(f"[{component}] requested configuration is aligned")
        return
    for item in drift:
        installed = ", ".join(item.installed) if item.installed else "not installed"
        print(f"[{item.component}] {item.spec}: {item.reason} (current: {installed})")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--component",
        choices=("conda", "pip", "kernel", "metadata"),
        required=True,
    )
    parser.add_argument("--environment", type=Path)
    parser.add_argument("--requirements", type=Path)
    parser.add_argument("--conda-json", type=Path)
    parser.add_argument("--conda-bin")
    parser.add_argument("--env-name")
    parser.add_argument(
        "--format", choices=("report", "specs", "json"), default="report"
    )
    parser.add_argument(
        "--exit-zero",
        action="store_true",
        help="Return success when drift is found; configuration errors still fail.",
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    try:
        if args.component == "conda":
            if args.environment is None:
                raise ValueError("Conda audit requires --environment")
            requested = parse_conda_environment(args.environment)
            records = load_conda_records(
                conda_json=args.conda_json,
                conda_bin=args.conda_bin,
                env_name=args.env_name,
            )
            drift = audit_requested(
                "conda", requested, conda_versions(records), conda_match=True
            )
        elif args.component == "pip":
            if args.requirements is None:
                raise ValueError("pip audit requires --requirements")
            requested = parse_pip_requirements(args.requirements)
            drift = audit_requested("pip", requested, pip_versions(), conda_match=False)
        elif args.component == "kernel":
            if not args.env_name:
                raise ValueError("Kernel audit requires --env-name")
            drift = audit_kernel(args.env_name)
        else:
            drift = audit_metadata()
    except (OSError, ValueError, RuntimeError, json.JSONDecodeError) as exc:
        print(f"Audit failed: {exc}", file=sys.stderr)
        return 2

    render(drift, args.format, args.component)
    return 0 if args.exit_zero or not drift else DRIFT_EXIT


if __name__ == "__main__":
    raise SystemExit(main())
