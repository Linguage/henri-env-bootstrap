import json
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from scripts.audit_environment import (
    RequestedSpec,
    audit_kernel,
    audit_metadata,
    audit_requested,
    conda_versions,
    normalize_name,
    parse_conda_environment,
    parse_pip_requirements,
)
from scripts.verify import duplicate_distributions


class AuditEnvironmentTests(unittest.TestCase):
    def test_parses_repository_style_inputs(self):
        with tempfile.TemporaryDirectory() as value:
            root = Path(value)
            environment = root / "environment.yml"
            requirements = root / "requirements.txt"
            environment.write_text(
                "name: demo\nchannels:\n  - conda-forge\ndependencies:\n"
                "  - python=3.13\n  - pip\n  - ffmpeg\n",
                encoding="utf-8",
            )
            requirements.write_text(
                "# direct packages\nOpenAI==1.2.3\npython-slugify==8.0.4\n",
                encoding="utf-8",
            )

            conda = parse_conda_environment(environment)
            pip = parse_pip_requirements(requirements)

            self.assertEqual(
                [item.raw for item in conda], ["python=3.13", "pip", "ffmpeg"]
            )
            self.assertEqual([item.name for item in pip], ["openai", "python-slugify"])

    def test_conda_audit_ignores_pypi_records_and_accepts_minor_pin(self):
        records = [
            {"name": "python", "version": "3.13.9", "channel": "conda-forge"},
            {"name": "ruff", "version": "0.15.5", "channel": "pypi"},
        ]
        requested = [
            RequestedSpec("python", "3.13", "python=3.13"),
            RequestedSpec("ruff", "0.15.5", "ruff=0.15.5"),
        ]

        drift = audit_requested(
            "conda", requested, conda_versions(records), conda_match=True
        )

        self.assertEqual([item.spec for item in drift], ["ruff=0.15.5"])

    def test_pip_audit_reports_only_missing_or_drifted_direct_requirements(self):
        requested = [
            RequestedSpec("openai", "1.2.3", "openai==1.2.3"),
            RequestedSpec("pyjwt", "2.8.0", "PyJWT==2.8.0"),
            RequestedSpec("seaborn", "0.13.2", "seaborn==0.13.2"),
        ]
        installed = {
            "openai": {"1.2.3"},
            "pyjwt": {"2.8.0", "2.11.0"},
        }

        drift = audit_requested("pip", requested, installed, conda_match=False)

        self.assertEqual(
            [(item.spec, item.reason) for item in drift],
            [
                ("PyJWT==2.8.0", "duplicate versions"),
                ("seaborn==0.13.2", "missing"),
            ],
        )

    def test_kernel_audit_checks_the_python_executable(self):
        with tempfile.TemporaryDirectory() as value:
            data_dir = Path(value)
            kernel_dir = data_dir / "kernels" / "demo"
            kernel_dir.mkdir(parents=True)
            expected = data_dir / "env" / "bin" / "python"
            other = data_dir / "old" / "bin" / "python"
            kernel_file = kernel_dir / "kernel.json"
            kernel_file.write_text(
                json.dumps(
                    {
                        "argv": [
                            str(other),
                            "-m",
                            "ipykernel_launcher",
                            "-f",
                            "{connection_file}",
                        ]
                    }
                ),
                encoding="utf-8",
            )

            drift = audit_kernel("demo", data_dir=data_dir, executable=expected)
            self.assertEqual(drift[0].reason, "points to another Python")

            kernel_file.write_text(
                json.dumps(
                    {
                        "argv": [
                            str(expected),
                            "-m",
                            "ipykernel_launcher",
                            "-f",
                            "{connection_file}",
                        ]
                    }
                ),
                encoding="utf-8",
            )
            self.assertEqual(
                audit_kernel("demo", data_dir=data_dir, executable=expected), []
            )

    def test_normalizes_pep503_names(self):
        self.assertEqual(normalize_name("python_slugify"), "python-slugify")

    def test_metadata_audit_detects_duplicate_records_even_at_same_version(self):
        first = mock.Mock(version="1.0")
        first.metadata.get.return_value = "Example_Package"
        second = mock.Mock(version="1.0")
        second.metadata.get.return_value = "example-package"
        with mock.patch(
            "scripts.audit_environment.importlib.metadata.distributions",
            return_value=[first, second],
        ):
            drift = audit_metadata()

        self.assertEqual(len(drift), 1)
        self.assertEqual(drift[0].spec, "example-package")
        self.assertEqual(drift[0].installed, ("1.0", "1.0"))

    def test_verifier_uses_canonical_distribution_names(self):
        first = mock.Mock(version="1.0")
        first.metadata.get.return_value = "Example.Package"
        second = mock.Mock(version="2.0")
        second.metadata.get.return_value = "example_package"
        with mock.patch(
            "scripts.verify.importlib.metadata.distributions",
            return_value=[first, second],
        ):
            duplicates = duplicate_distributions()

        self.assertEqual(duplicates, {"example-package": ["1.0", "2.0"]})


if __name__ == "__main__":
    unittest.main()
