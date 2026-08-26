#!/bin/bash
# Build a signed Tinycast.app into build/Tinycast-<version>.dmg, drop a copy where the other Macs can
# reach it, then install it over /Applications. Usage: ./Scripts/build-dmg.sh [version]
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

# The KVS entitlement needs an Apple-issued profile (FORK.md divergence 10) and a development one names
# the Macs it covers. Anywhere else the app dies at launch as "damaged or incomplete", so say it here.
PROFILE="$APP/Contents/embedded.provisionprofile"
if [ -f "$PROFILE" ]; then
    PLIST="$(mktemp)"
    security cms -D -i "$PROFILE" -o "$PLIST" 2>/dev/null || true
    DEVICES="$(/usr/libexec/PlistBuddy -c 'Print :ProvisionedDevices' "$PLIST" 2>/dev/null |
        sed -n 's/^[[:space:]]*\([0-9A-Fa-f]\{8\}-[0-9A-Fa-f]*\)[[:space:]]*$/    \1/p')"
    rm -f "$PLIST"
    if [ -n "$DEVICES" ]; then
        echo "▸ This build runs on these Macs only — 'Provisioning UDID' in About This Mac ▸ Report:"
        echo "$DEVICES"
        echo "  Another Mac needs registering, then Xcode ▸ Settings ▸ Accounts ▸ Download Profiles."
    fi
fi

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

# This Mac gets the build too, and last, so a refused install never costs the DMG that already shipped.
# `-x` keeps this to the stable channel: Tinycast Dev and Tinycast Beta are other apps and stay running.
INSTALL="/Applications/Tinycast.app"
RELAUNCH=false
if pgrep -qx Tinycast; then
    RELAUNCH=true
    echo "▸ Quitting Tinycast…"
    # A login-item agent is essentially always live, and a replaced bundle under a running process
    # leaves the old build serving hotkeys until something restarts it.
    osascript -e 'tell application "Tinycast" to quit' 2>/dev/null || pkill -x Tinycast || true
    for _ in $(seq 40); do pgrep -qx Tinycast || break; sleep 0.25; done
fi

if pgrep -qx Tinycast; then
    echo "✗ Tinycast would not quit — quit it by hand and re-run. $DMG is already built." >&2
    exit 1
fi

# Staged alongside the target, so a copy that dies partway leaves the installed app untouched.
STAGED="/Applications/.Tinycast.app.new"
rm -rf "$STAGED"
ditto "$APP" "$STAGED"
rm -rf "$INSTALL"
mv "$STAGED" "$INSTALL"
echo "✓ installed to $INSTALL"

if $RELAUNCH; then
    open -a "$INSTALL"
    echo "✓ relaunched"
fi
