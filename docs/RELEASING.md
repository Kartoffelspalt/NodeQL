# Releasing NodeQL

NodeQL's first public release target is desktop: Linux x64, macOS, and Windows
x64. Web, Android, and iOS are not release targets yet.

## Required repository setup

1. Rename or transfer the GitHub repository to `Kartoffelspalt/NodeQL`.
2. Enable GitHub Actions with read/write access for release contents.
3. Enable private vulnerability reporting under **Settings > Security**.
4. Enable branch protection for `master` or `main` and require the CI job.
5. Configure GitHub Pages before enabling online language downloads.
6. Configure your Gemini API key as the `GEMINI_API_KEY` Actions secret.
   Optionally set `NODEQL_TRANSLATION_MODEL` (default: `gemini-3.8-flash`)
   and `NODEQL_TRANSLATION_LOCALES`; see the
   [AI translation setup](localization/README.md#ai-translations-during-github-releases).

## Release procedure

1. Update `CHANGELOG.md`.
2. Set `version: X.Y.Z+BUILD` in `pubspec.yaml`. Choose a build number
   higher than those in earlier Sparkle-enabled builds, including local
   builds that use the production update feed.
3. Run the full local verification commands from `CONTRIBUTING.md`.
4. Increase both the release version and build number, then merge the change
   into `master`.

The merged `pubspec.yaml` change starts the `Desktop Release` workflow. It
validates that the version has not already been published, generates and
validates AI language packs, builds and signs all three desktop targets with
those packages included, generates `SHA256SUMS.txt`, and creates the matching Git
tag and GitHub release only after all quality and build jobs succeed.

Language packages are generated once and shared across the desktop build jobs.
Reviewed translations override generated messages; source hashes and Actions
caching avoid translating unchanged strings again. API or translation validation
failures stop the release. The release also contains
`nodeql-translations-X.Y.Z.tar.gz`. After publication, the same catalog is deployed
to GitHub Pages for language downloads. A Pages failure can be retried without
rebuilding or republishing the installers.

The release jobs run when the release version changes on `master`, the build
number increases, and the release tag does not already exist. Sparkle compares
the build numbers to decide whether to offer an update. Keep increasing the
build number across release versions. Linux and Windows builds run only as
part of this release workflow.

## Signing

The workflow always publishes usable desktop installers. Signing is optional:
without the configuration below, it publishes unsigned macOS DMGs, a Windows
setup program and portable ZIP, a Debian package, and a Linux archive. Users
may see the normal macOS Gatekeeper or Windows SmartScreen warning until
signing is enabled.

| Platform | Published artifact when signing is configured | Optional GitHub Actions configuration |
| --- | --- | --- |
| macOS | Notarized `nodeql-macos-X.Y.Z.dmg` for drag-and-drop installation and `nodeql-macos-X.Y.Z-portable.dmg` for launching directly from the image | Secrets: `APPLE_CERTIFICATE_P12_BASE64`, `APPLE_CERTIFICATE_PASSWORD`, `APPLE_NOTARY_KEY_BASE64`; Variables: `APPLE_SIGNING_IDENTITY`, `APPLE_NOTARY_KEY_ID`, `APPLE_NOTARY_ISSUER_ID` |
| Windows x64 | Authenticode-signed `nodeql-windows-x64-X.Y.Z-setup.exe` and `nodeql-windows-x64-X.Y.Z-portable.zip` containing the signed app | `WINDOWS_CERTIFICATE_P12_BASE64`, `WINDOWS_CERTIFICATE_PASSWORD` |
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
UUID in `APPLE_NOTARY_ISSUER_ID`. The workflow submits both macOS images,
staples each notarization ticket, and verifies Gatekeeper assessment.

To run NodeQL without installing it, mount the portable DMG and open
`NodeQL.app` directly. Download a fresh portable image for each update.
Sparkle uses the regular drag-and-drop DMG and needs an app installed on a
writable volume, such as the copy in `/Applications`.

The Windows certificate must be an Authenticode-capable PFX. The workflow signs
the executable and DLLs before packaging the installer and the portable ZIP.
It then signs the Inno Setup installer and verifies its Authenticode status.
For portable use, extract the entire ZIP to a folder and run `nodeql.exe` from
that folder. The ZIP includes the Flutter data and DLLs, plus the application-local
Visual C++ runtime.

Publish the Linux release public key alongside the project documentation. Users
can verify a Linux asset with `gpg --verify <asset>.asc <asset>` after importing
that public key.

## macOS automatic updates

Sparkle verifies the macOS DMG and its update feed using an Ed25519 key pair.
GitHub Actions reads both values from **repository secrets**. The private
signing key stays in the Mac Keychain and the GitHub secret. The public
verification key is embedded in the released app's `Info.plist` so every
installation can verify updates. Anyone with the app can read that public key.
The public release assets contain the DMG and signatures, and the private key
is never included. Apple Developer ID is only needed if you want to notarize
the app with Apple.

### 1. Prepare the Sparkle tools

On your Mac, open a terminal at the NodeQL repository root. Build the app to
resolve the pinned Sparkle version and download its tools. Authenticate the
GitHub CLI with an account that can manage the repository's Actions secrets.

```bash
flutter build macos --release
gh auth status
```

Run `gh auth login --hostname github.com` if you are signed out.

### 2. Generate the signing key pair once

```bash
build/macos/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys --account nodeql >/dev/null
```

Approve the macOS Keychain prompt if shown. Keep a secure backup of the
private key and reuse this pair for future releases.

### 3. Save both values as GitHub Actions secrets

Run the following from the same repository root. It passes the values to
GitHub CLI through standard input, keeps the temporary export outside the
checkout, and removes that export when the command finishes. For a fork,
replace `Kartoffelspalt/NodeQL` with your repository.

```bash
(
  set -euo pipefail
  umask 077
  sparkle_repo=Kartoffelspalt/NodeQL
  sparkle_keys=build/macos/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys
  sparkle_temp="$(mktemp -d "${TMPDIR:-/tmp}/nodeql-sparkle.XXXXXX")"
  trap 'rm -rf "$sparkle_temp"' EXIT

  "$sparkle_keys" --account nodeql -x "$sparkle_temp/private-key" >/dev/null
  gh secret set SPARKLE_PRIVATE_ED_KEY --repo "$sparkle_repo" < "$sparkle_temp/private-key"
  "$sparkle_keys" --account nodeql -p |
    gh secret set SPARKLE_PUBLIC_ED_KEY --repo "$sparkle_repo"
  gh secret list --repo "$sparkle_repo"
)
```

GitHub lists the secret names in **Settings → Secrets and variables →
Actions → Repository secrets**. If you previously created an Actions
variable named `SPARKLE_PUBLIC_ED_KEY`, remove it after setting the secret.

### 4. Publish and verify the first update

1. Merge a change that increases both the release version and build number in
   `pubspec.yaml` into the release branch. The **Desktop Release** workflow
   validates the key pair, builds the app, signs the final DMG and appcast, and
   uploads them together. With both secrets absent, the manual download flow
   remains available. An incomplete or mismatched pair fails the macOS job.
2. Verify that the GitHub release contains the macOS DMG and
   `nodeql-macos-appcast.xml`. Install this first Sparkle-enabled DMG manually
   by copying NodeQL to `/Applications`.
3. After the next release, open the older Sparkle-enabled version and choose
   **NodeQL → Check for Updates…**. Verify that NodeQL installs the update,
   restarts, and reports the new version. Users can disable automatic
   installation from the same menu.

Keep both secrets configured on future releases because the installed app
fetches its feed from the latest GitHub release.

### Build a Sparkle-enabled DMG locally

After creating the key pair in step 2, run this from the repository root.

```bash
bash tool/build_macos_sparkle_dmg.sh
```

The script reads the public verification key from the `nodeql` Keychain
account and creates `build/NodeQL-local-sparkle.dmg`. The DMG contains the
app and a link to `/Applications`. Quit any running NodeQL instance, drag
the app into `/Applications`, and launch that copy to see **Check for
Updates…** and **Automatically Install Updates** in the NodeQL menu.

The local DMG uses the same GitHub update feed as the release build. A
newer signed release with `nodeql-macos-appcast.xml` must be available
before Sparkle can offer an update. The local script uses ad-hoc macOS
code signing and only reads the public key. For a fork, pass its
`OWNER/REPO` as the first argument. If you used a different account name
when generating the key, set `SPARKLE_KEYCHAIN_ACCOUNT`.
