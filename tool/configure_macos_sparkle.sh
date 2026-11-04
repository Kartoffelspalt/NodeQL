#!/bin/bash
set -euo pipefail

app_path="${1:?Provide the path to NodeQL.app}"
release_repo="${2:?Provide the release repository as OWNER/REPO}"
public_key="${SPARKLE_PUBLIC_ED_KEY:-}"

if [[ ! "$public_key" =~ ^[A-Za-z0-9+/]{43}=$ ]]; then
  echo "Sparkle needs a valid Ed25519 public key." >&2
  exit 1
fi
if [[ ! "$release_repo" =~ ^[A-Za-z0-9-]+/[A-Za-z0-9_.-]+$ ]]; then
  echo "Provide a GitHub release repository as OWNER/REPO." >&2
  exit 1
fi
test -d "$app_path/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices/Installer.xpc"

info_plist="$app_path/Contents/Info.plist"
plutil -replace SUPublicEDKey -string "$public_key" "$info_plist"
plutil -replace SUFeedURL -string "https://github.com/$release_repo/releases/latest/download/nodeql-macos-appcast.xml" "$info_plist"
plutil -replace SUEnableInstallerLauncherService -bool YES "$info_plist"
plutil -replace SUVerifyUpdateBeforeExtraction -bool YES "$info_plist"
plutil -replace SURequireSignedFeed -bool YES "$info_plist"
plutil -replace SUEnableAutomaticChecks -bool YES "$info_plist"
plutil -replace SUAutomaticallyUpdate -bool YES "$info_plist"
