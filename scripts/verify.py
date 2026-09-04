#!/usr/bin/env python3
"""Verify that a recreated henri_env is coherent and usable."""

from __future__ import annotations

import importlib
import importlib.metadata
import platform
import re
import shutil
import subprocess
import sys
from collections import defaultdict


REQUIRED_IMPORTS = {
    "anthropic": "Anthropic SDK",
    "fastapi": "FastAPI",
    "geopandas": "GeoPandas",
    "jupyterlab": "JupyterLab",
    "manim": "Manim",
    "matplotlib": "Matplotlib",
    "mypy": "mypy",
    "nltk": "NLTK",
    "notebook": "Jupyter Notebook",
    "numpy": "NumPy",
    "openai": "OpenAI SDK",
    "openpyxl": "openpyxl",
    "osmnx": "OSMnx",
    "pandas": "pandas",
    "pdfplumber": "pdfplumber",
    "ruff": "Ruff",
    "seaborn": "seaborn",
    "streamlit": "Streamlit",
    "sympy": "SymPy",
    "zhipuai": "ZhipuAI SDK",
}


def normalize_name(value: str) -> str:
    """Normalize distribution names according to the PyPA name rules."""
    return re.sub(r"[-_.]+", "-", value).lower()


def duplicate_distributions() -> dict[str, list[str]]:
    versions: defaultdict[str, list[str]] = defaultdict(list)
    for distribution in importlib.metadata.distributions():
        raw_name = distribution.metadata.get("Name") or ""
        name = normalize_name(raw_name)
        versions[name].append(distribution.version)
    return {name: found for name, found in versions.items() if len(found) > 1}


def main() -> int:
    print(
        f"Python {platform.python_version()} ({platform.system()} {platform.machine()})"
    )
    failures: list[str] = []

    for module_name, label in REQUIRED_IMPORTS.items():
        try:
            importlib.import_module(module_name)
        except Exception as exc:  # noqa: BLE001 - verification must report every import failure
            failures.append(f"{label}: {exc}")

    duplicates = duplicate_distributions()
    if duplicates:
        rendered = ", ".join(
            f"{name}={sorted(set(versions))}"
            for name, versions in sorted(duplicates.items())
        )
        failures.append(f"duplicate distribution metadata: {rendered}")

    pip_check = subprocess.run(
        [sys.executable, "-m", "pip", "check"],
        check=False,
        capture_output=True,
        text=True,
    )
    if pip_check.returncode:
        failures.append(
            f"pip check: {pip_check.stdout.strip() or pip_check.stderr.strip()}"
        )

    if shutil.which("ffmpeg") is None:
        failures.append("ffmpeg is not available")

    if failures:
        print("Verification failed:", file=sys.stderr)
        for failure in failures:
            print(f"- {failure}", file=sys.stderr)
        return 1

    print(
        "Verification passed: imports, metadata, pip dependencies, and ffmpeg are healthy."
    )
    if shutil.which("latex") is None:
        print(
            "Optional: install a TeX distribution for Manim scenes that render LaTeX."
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
