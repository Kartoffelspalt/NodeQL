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
4. Increase both the release version and build number, then merge the change
   into `master`.

The merged `pubspec.yaml` change starts the `Desktop Release` workflow. It
validates that the version has not already been published, builds and signs all
three desktop targets, generates `SHA256SUMS.txt`, and creates the matching Git
tag and GitHub release only after all quality and build jobs succeed.

The release jobs run only when both parts of `pubspec.yaml`'s version change on
`master` and the release tag does not already exist. Linux and Windows builds
run only as part of this release workflow.

## Signing

The workflow always publishes usable desktop installers. Signing is optional:
without the configuration below, it publishes an unsigned DMG, Windows setup
program, Debian package, and Linux archive. Users may see the normal macOS
Gatekeeper or Windows SmartScreen warning until signing is enabled.

| Platform | Published artifact when signing is configured | Optional GitHub Actions configuration |
| --- | --- | --- |
| macOS | Notarized `nodeql-macos-X.Y.Z.dmg` with `NodeQL.app` and an `Applications` link for drag-and-drop installation | Secrets: `APPLE_CERTIFICATE_P12_BASE64`, `APPLE_CERTIFICATE_PASSWORD`, `APPLE_NOTARY_KEY_BASE64`; Variables: `APPLE_SIGNING_IDENTITY`, `APPLE_NOTARY_KEY_ID`, `APPLE_NOTARY_ISSUER_ID` |
| Windows x64 | Authenticode-signed `nodeql-windows-x64-X.Y.Z-setup.exe` | `WINDOWS_CERTIFICATE_P12_BASE64`, `WINDOWS_CERTIFICATE_PASSWORD` |
| Linux x64 | `nodeql_X.Y.Z_amd64.deb` and tarball, each with a detached GPG `.asc` signature | Secrets: `LINUX_GPG_PRIVATE_KEY`, `LINUX_GPG_PASSPHRASE`; Variable: `LINUX_GPG_KEY_ID` |

All certificate and private-key secrets are base64-encoded file contents, not
file paths. Use a **Developer ID Application** certificate for
`APPLE_CERTIFICATE_P12_BASE64`; `APPLE_SIGNING_IDENTITY` is its complete
identity, for example `Developer ID Application: Example GmbH (TEAMID)`.

The public values `APPLE_SIGNING_IDENTITY`, `APPLE_NOTARY_KEY_ID`,
`APPLE_NOTARY_ISSUER_ID`, and `LINUX_GPG_KEY_ID` are GitHub **Actions
variables**. All remaining values in the table are GitHub **Actions secrets**.
The repository initializes each of these variables as `__SET_ME__`; replace
that placeholder before enabling its corresponding signing method. The workflow
then detects the complete configuration automatically; missing or placeholder
values simply skip signing and never block an unsigned release.

On macOS, produce clipboard-ready values with `base64 -i certificate.p12 |
pbcopy` and `base64 -i AuthKey_KEYID.p8 | pbcopy`. On Windows PowerShell, use
`[Convert]::ToBase64String([IO.File]::ReadAllBytes('certificate.pfx'))`. Export
the Linux private key first (for example, `gpg --armor --export-secret-keys
KEY_ID > nodeql-release-key.asc`) and then base64-encode that file. Store every
value as an **Actions secret** under **Settings → Secrets and variables →
Actions**; never commit certificate, PFX, P12, P8, or private-key files.

For notarization, create an App Store Connect API key with access to the Apple
Developer account. Store the base64-encoded `.p8` contents in
`APPLE_NOTARY_KEY_BASE64`, its key ID in `APPLE_NOTARY_KEY_ID`, and the issuer
UUID in `APPLE_NOTARY_ISSUER_ID`. The workflow submits the final DMG, waits for
Apple's result, staples the ticket, and verifies Gatekeeper assessment.

The Windows certificate must be an Authenticode-capable PFX. The workflow signs
the installed executable and DLLs, creates an Inno Setup installer with an
application shortcut/uninstaller, signs that installer, and verifies its
Authenticode status.

Publish the Linux release public key alongside the project documentation. Users
can verify a Linux asset with `gpg --verify <asset>.asc <asset>` after importing
that public key.
