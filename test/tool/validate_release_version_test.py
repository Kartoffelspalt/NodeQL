import subprocess
import sys
import unittest
from pathlib import Path

from tool.validate_release_version import validate_release_version


class ValidateReleaseVersionTest(unittest.TestCase):
    def test_accepts_increasing_major_minor_and_patch_versions(self):
        for previous, current in [
            ("0.5.1+2", "0.5.2+3"),
            ("0.5.9+2", "0.6.0+3"),
            ("0.9.9+2", "0.10.0+3"),
            ("0.99.99+2", "1.0.0+3"),
        ]:
            with self.subTest(previous=previous, current=current):
                outputs = validate_release_version(current, previous)
                self.assertEqual(outputs["version-updated"], "true")
                self.assertEqual(outputs["tag"], f"v{current.split('+')[0]}")

    def test_rejects_downgrades_even_with_a_higher_build_number(self):
        for previous, current in [
            ("0.5.1+2", "0.5.0+3"),
            ("0.6.0+2", "0.5.99+3"),
            ("0.10.0+2", "0.9.99+3"),
            ("1.0.0+2", "0.99.99+3"),
            ("1.0.0+2", "1.0.0-rc.1+3"),
        ]:
            with self.subTest(previous=previous, current=current):
                with self.assertRaisesRegex(ValueError, "version downgrades"):
                    validate_release_version(current, previous)

    def test_unchanged_version_skips_release_regardless_of_build_number(self):
        for build in ["1", "2", "3"]:
            with self.subTest(build=build):
                outputs = validate_release_version(f"0.5.1+{build}", "0.5.1+2")
                self.assertEqual(outputs["version-updated"], "false")
                self.assertEqual(outputs["build-number"], build)

    def test_higher_version_still_requires_increasing_sparkle_build_number(self):
        for build in ["1", "2"]:
            with self.subTest(build=build):
                with self.assertRaisesRegex(ValueError, "for Sparkle updates"):
                    validate_release_version(f"0.6.0+{build}", "0.5.1+2")

    def test_checks_version_before_build_number(self):
        with self.assertRaisesRegex(ValueError, "version downgrades"):
            validate_release_version("0.5.0+1", "0.5.1+2")

    def test_uses_semver_prerelease_ordering(self):
        versions = [
            "1.0.0-alpha",
            "1.0.0-alpha.1",
            "1.0.0-alpha.beta",
            "1.0.0-beta",
            "1.0.0-beta.2",
            "1.0.0-beta.11",
            "1.0.0-rc.1",
            "1.0.0",
        ]
        for previous, current in zip(versions, versions[1:]):
            with self.subTest(previous=previous, current=current):
                outputs = validate_release_version(f"{current}+3", f"{previous}+2")
                self.assertEqual(outputs["version-updated"], "true")
                with self.assertRaisesRegex(ValueError, "version downgrades"):
                    validate_release_version(f"{previous}+4", f"{current}+3")

    def test_accepts_first_release_without_previous_version(self):
        self.assertEqual(
            validate_release_version("0.5.1+2"),
            {
                "version": "0.5.1",
                "build-number": "2",
                "tag": "v0.5.1",
                "version-updated": "true",
            },
        )

    def test_rejects_invalid_current_or_previous_versions(self):
        for invalid in [
            "0.5.1",
            "0.5.1+abc",
            "0.5.1.2+3",
            "0.5.1-+3",
            "0.5.1-alpha..1+3",
            "0.5.1-rc.01+3",
            "00.5.1+3",
        ]:
            with self.subTest(version=invalid):
                with self.assertRaisesRegex(ValueError, "Invalid release version"):
                    validate_release_version(invalid)
                with self.assertRaisesRegex(ValueError, "Invalid release version"):
                    validate_release_version("0.6.0+4", invalid)

    def test_cli_emits_only_valid_outputs_and_fails_on_downgrade(self):
        script = (
            Path(__file__).resolve().parents[2] / "tool/validate_release_version.py"
        )
        for current, expected_code in [("0.6.0+3", 0), ("0.5.0+3", 1)]:
            with self.subTest(current=current):
                result = subprocess.run(
                    [
                        sys.executable,
                        str(script),
                        "--current",
                        current,
                        "--previous",
                        "0.5.1+2",
                    ],
                    capture_output=True,
                    text=True,
                    check=False,
                )
                self.assertEqual(result.returncode, expected_code)
                if expected_code == 0:
                    self.assertEqual(
                        result.stdout,
                        "version=0.6.0\nbuild-number=3\ntag=v0.6.0\nversion-updated=true\n",
                    )
                    self.assertEqual(result.stderr, "")
                else:
                    self.assertEqual(result.stdout, "")
                    self.assertIn("::error::Release version", result.stderr)


if __name__ == "__main__":
    unittest.main()
