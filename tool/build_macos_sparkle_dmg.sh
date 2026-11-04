#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

release_repo="${1:-Kartoffelspalt/NodeQL}"
sparkle_account="${SPARKLE_KEYCHAIN_ACCOUNT:-nodeql}"
flutter build macos --release \
  --dart-define="NODEQL_RELEASE_OWNER=${release_repo%%/*}" \
  --dart-define="NODEQL_RELEASE_REPOSITORY=${release_repo#*/}"

generate_keys="build/macos/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys"
if ! public_key="$("$generate_keys" --account "$sparkle_account" -p)" || [[ -z "$public_key" ]]; then
  echo "Sparkle key not found in Keychain for account '$sparkle_account'. See docs/RELEASING.md." >&2
  exit 1
fi

work="$(mktemp -d "${TMPDIR:-/tmp}/nodeql-sparkle-dmg.XXXXXX")"
trap 'rm -rf "$work"' EXIT

dmg_root="$work/image"
app_path="$dmg_root/NodeQL.app"
mkdir "$dmg_root"
ditto build/macos/Build/Products/Release/NodeQL.app "$app_path"
ln -s /Applications "$dmg_root/Applications"

entitlements="$work/entitlements.plist"
codesign -d --entitlements :- "$app_path" > "$entitlements"
if plutil -extract 'com\.apple\.security\.get-task-allow' raw "$entitlements" >/dev/null 2>&1; then
  plutil -remove 'com\.apple\.security\.get-task-allow' "$entitlements"
fi

SPARKLE_PUBLIC_ED_KEY="$public_key" bash tool/configure_macos_sparkle.sh "$app_path" "$release_repo"
codesign --force --sign - --entitlements "$entitlements" "$app_path"
codesign --verify --deep --strict "$app_path"

output="$PWD/build/NodeQL-local-sparkle.dmg"
hdiutil create -volname NodeQL -srcfolder "$dmg_root" -ov -format UDZO "$output"
