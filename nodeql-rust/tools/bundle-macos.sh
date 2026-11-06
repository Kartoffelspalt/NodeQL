#!/bin/sh
set -eu

if [ "$(uname -s)" != "Darwin" ]; then
    echo 'This bundle helper requires macOS.' >&2
    exit 1
fi

rust_root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
cd "$rust_root"
cargo build --locked --release

bundle="$rust_root/target/release/bundle/NodeQL Rust.app"
mkdir -p "$bundle/Contents/MacOS"
# Replace the file rather than overwriting an executable in a running app.
cp -p target/release/nodeql-rust "$bundle/Contents/MacOS/.nodeql-rust.new"
mv -f "$bundle/Contents/MacOS/.nodeql-rust.new" "$bundle/Contents/MacOS/nodeql-rust"
cat > "$bundle/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>NodeQL Rust</string>
    <key>CFBundleDisplayName</key><string>NodeQL Rust</string>
    <key>CFBundleIdentifier</key><string>digital.codespiresolutions.nodeql.rust</string>
    <key>CFBundleExecutable</key><string>nodeql-rust</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>10.15</string>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

# Ad-hoc signing is sufficient for a local development bundle, not distribution.
codesign --force --sign - "$bundle"
printf 'Local development app: %s\n' "$bundle"
