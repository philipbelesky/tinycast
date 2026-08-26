#!/bin/bash
# Build a signed Tinycast.app into build/Tinycast-<version>.dmg, drop a copy where the other Macs can
# reach it, then install it over /Applications. Usage: ./Scripts/build-dmg.sh [version]
set -euo pipefail

cd "$(dirname "$0")/.." || exit 1
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
DROP="${TINYCAST_DMG_DROP:-$HOME/Library/Mobile Documents/com~apple~CloudDocs/Resources}"
DERIVED="build/DerivedData"
# Read rather than repeat: the team owns the Developer ID identity and must not drift from project.yml.
TEAM="$(awk '/DEVELOPMENT_TEAM:/ { print $2; exit }' project.yml)"

if [ -z "$TEAM" ]; then
    echo "✗ No DEVELOPMENT_TEAM in project.yml — the export has no team to sign for." >&2
    exit 1
fi

# Automatic signing only ever picks a *development* identity during a build, so naming Developer ID
# as a build setting just conflicts with it. Developer ID is a distribution method: the archive signs
# for development and the export re-signs, exactly as Xcode's Distribute App does.
echo "▸ Archiving Tinycast.app (Release)…"
ARCHIVE="build/Tinycast.xcarchive"
rm -rf "$ARCHIVE"
xcodebuild -project Tinycast.xcodeproj -scheme Tinycast -configuration Release \
    -derivedDataPath "$DERIVED" \
    -archivePath "$ARCHIVE" \
    -allowProvisioningUpdates \
    ${1:+MARKETING_VERSION="$1"} \
    archive

echo "▸ Exporting with Developer ID…"
EXPORT="build/export"
rm -rf "$EXPORT"
OPTDIR="$(mktemp -d)"
cat > "$OPTDIR/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key><string>developer-id</string>
    <key>teamID</key><string>$TEAM</string>
    <key>signingStyle</key><string>automatic</string>
    <key>destination</key><string>export</string>
</dict>
</plist>
PLIST
xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath "$EXPORT" \
    -exportOptionsPlist "$OPTDIR/ExportOptions.plist" -allowProvisioningUpdates
rm -rf "$OPTDIR"

APP="$EXPORT/Tinycast.app"
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
