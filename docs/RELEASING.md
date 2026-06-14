# Releasing NodeQL

NodeQL's first public release target is desktop: Linux x64, macOS, and Windows
x64. Web, Android, and iOS are not release targets yet.

## Required repository setup

1. Rename or transfer the GitHub repository to `Kartoffelspalt/NodeQL`.
2. Enable GitHub Actions with read/write access for release contents.
3. Enable private vulnerability reporting under **Settings > Security**.
4. Enable branch protection for `master` or `main` and require the CI job.
5. Configure GitHub Pages before enabling online language downloads.

## Release procedure

1. Update `CHANGELOG.md`.
2. Set `version: X.Y.Z+BUILD` in `pubspec.yaml`.
3. Run the full local verification commands from `CONTRIBUTING.md`.
4. Commit and merge the release changes.
5. Create and push the matching tag:

```bash
git tag vX.Y.Z
git push origin vX.Y.Z
```

The `Desktop Release` workflow builds all three desktop targets, packages
them, generates `SHA256SUMS.txt`, and creates the GitHub release only after all
quality and build jobs succeed.

## Signing

The current workflow produces unsigned public binaries. Before describing the
release as trusted or generally available, configure:

- Apple Developer ID signing and notarization for macOS.
- Authenticode signing for Windows.

Unsigned archives are suitable for an explicitly labeled preview release, but
operating systems may show security warnings.
