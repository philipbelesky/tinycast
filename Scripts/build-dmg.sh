#!/bin/bash
# Build a signed Tinycast.app into build/Tinycast-<version>.dmg, then drop a copy where the other
# Macs can reach it. Usage: ./Scripts/build-dmg.sh [version]
set -euo pipefail

cd "$(dirname "$0")/.." || exit 1
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
# Signing itself lives in project.yml so `xcodegen generate` carries it (FORK.md divergence 1); this
# names the same identity only so a missing certificate fails here rather than mid-build.
IDENTITY="${TINYCAST_SIGN_IDENTITY:-Apple Development}"
DROP="${TINYCAST_DMG_DROP:-$HOME/Library/Mobile Documents/com~apple~CloudDocs/Resources}"
DERIVED="build/DerivedData"

if ! security find-identity -p codesigning | grep -q "$IDENTITY"; then
    echo "✗ '$IDENTITY' code-signing identity not found — see docs/signing.md." >&2
    exit 1
fi

echo "▸ Building signed Tinycast.app (Release)…"
xcodebuild -project Tinycast.xcodeproj -scheme Tinycast -configuration Release \
    -derivedDataPath "$DERIVED" \
    CODE_SIGN_IDENTITY="$IDENTITY" \
    ${1:+MARKETING_VERSION="$1"} \
    build

APP="$DERIVED/Build/Products/Release/Tinycast.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
DMG="build/Tinycast-${VERSION}.dmg"

echo "▸ Packaging ${DMG}"
STAGE="$(mktemp -d)"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
diskutil image create from "$STAGE" --format UDZO --volumeName "Tinycast" "$DMG" >/dev/null
rm -rf "$STAGE"

echo "✓ $DMG"

# Absent on CI and on a fresh clone, so a missing drop is a skip rather than a failed build.
if [ -d "$DROP" ]; then
    cp "$DMG" "$DROP/"
    echo "✓ copied to $DROP"
else
    echo "· $DROP not present — skipped the copy"
fi
