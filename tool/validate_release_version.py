"""Validate release ordering and emit GitHub Actions step outputs."""

import argparse
import re
import sys
from dataclasses import dataclass


@dataclass(frozen=True)
class ReleaseVersion:
    name: str
    build: str
    precedence: tuple

    @classmethod
    def parse(cls, value: str) -> "ReleaseVersion":
        match = re.fullmatch(
            r"(?P<name>(?P<core>(?:0|[1-9][0-9]*)\."
            r"(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*))"
            r"(?:-(?P<prerelease>[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?)"
            r"\+(?P<build>[0-9]+)",
            value,
        )
        if match is None:
            raise ValueError(
                f"Invalid release version {value!r}; expected SemVer X.Y.Z+BUILD "
                "or X.Y.Z-PRERELEASE+BUILD with a numeric build number."
            )
        prerelease = match["prerelease"]
        identifiers = prerelease.split(".") if prerelease else []
        if any(
            part.isdigit() and len(part) > 1 and part[0] == "0" for part in identifiers
        ):
            raise ValueError(
                f"Invalid release version {value!r}; numeric prerelease "
                "identifiers cannot have leading zeroes."
            )

        # SemVer orders numeric prerelease identifiers before text identifiers,
        # and the stable version after all prereleases with the same core.
        precedence = (
            tuple(int(part) for part in match["core"].split(".")),
            prerelease is None,
            tuple(
                (0, int(part)) if part.isdigit() else (1, part) for part in identifiers
            ),
        )
        return cls(match["name"], match["build"], precedence)


def validate_release_version(current: str, previous: str = "") -> dict[str, str]:
    version = ReleaseVersion.parse(current)
    updated = True
    if previous:
        baseline = ReleaseVersion.parse(previous)
        if version.precedence < baseline.precedence:
            raise ValueError(
                f"Release version {version.name} must be greater than "
                f"{baseline.name}; version downgrades cannot be published."
            )
        updated = version.precedence > baseline.precedence
        if updated and int(version.build) <= int(baseline.build):
            raise ValueError(
                f"Build number {version.build} must be greater than "
                f"{baseline.build} for Sparkle updates, even when the release "
                "version increases."
            )
    return {
        "version": version.name,
        "build-number": version.build,
        "tag": f"v{version.name}",
        "version-updated": str(updated).lower(),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--current", required=True)
    parser.add_argument("--previous", default="")
    args = parser.parse_args()
    try:
        outputs = validate_release_version(args.current, args.previous)
    except ValueError as error:
        print(f"::error::{error}", file=sys.stderr)
        return 1
    for name, value in outputs.items():
        print(f"{name}={value}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
