#!/usr/bin/env bash
# Builds Islet.app from SwiftPM output. Works with the Command Line Tools alone (no Xcode).
#
#   scripts/bundle.sh                 # release build, ad-hoc signed → build/Islet.app
#   CONFIG=debug scripts/bundle.sh    # debug build
#   SIGN_IDENTITY="Developer ID Application: Name (TEAMID)" scripts/bundle.sh   # distributable build
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${CONFIG:-release}"
VERSION="${VERSION:-0.1.0}"
BUILD="${BUILD:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}"
BUNDLE_ID="${BUNDLE_ID:-dev.islet.Islet}"
APP="build/Islet.app"

echo "▸ swift build ($CONFIG)"
swift build -c "$CONFIG" --product Islet
swift build -c "$CONFIG" --product isletctl
BIN="$(swift build -c "$CONFIG" --show-bin-path)"

echo "▸ MediaRemote helper"
mkdir -p build/helpers
clang -dynamiclib -fobjc-arc -O2 -arch arm64e -arch arm64 -arch x86_64 -mmacosx-version-min=14.0 \
    -framework Foundation -o build/helpers/IsletMediaRemote.dylib Helpers/MediaRemoteBridge/IsletMediaRemote.m 2>&1 \
    | { grep -v "^ld: warning" || true; }
cp Helpers/MediaRemoteBridge/islet-mediaremote.pl build/helpers/

echo "▸ assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/Islet" "$BIN/isletctl" "$APP/Contents/MacOS/"
cp build/helpers/IsletMediaRemote.dylib build/helpers/islet-mediaremote.pl "$APP/Contents/Resources/"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"
[ -f docs/API.md ] && cp docs/API.md "$APP/Contents/Resources/API.md"
sed -e "s/__BUNDLE_ID__/$BUNDLE_ID/" -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD/" Resources/Info.plist > "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"
plutil -lint "$APP/Contents/Info.plist" >/dev/null

echo "▸ signing"
if [ -n "${SIGN_IDENTITY:-}" ]; then
    # Distributable: hardened runtime + timestamp, inside-out (never --deep).
    for f in "$APP/Contents/Resources/IsletMediaRemote.dylib" "$APP/Contents/MacOS/isletctl"; do
        codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$f"
    done
    codesign --force --options runtime --timestamp --entitlements Resources/Islet.entitlements --sign "$SIGN_IDENTITY" "$APP"
else
    # Local build: ad-hoc, with an identifier-based requirement so macOS privacy grants
    # (Calendar, Accessibility, Automation) survive rebuilds.
    codesign --force --sign - "$APP/Contents/Resources/IsletMediaRemote.dylib"
    codesign --force --sign - --identifier "$BUNDLE_ID.isletctl" "$APP/Contents/MacOS/isletctl"
    codesign --force --sign - --identifier "$BUNDLE_ID" -r="designated => identifier \"$BUNDLE_ID\"" "$APP"
fi
codesign --verify --strict "$APP"
echo "✓ $APP ($(du -sh "$APP" | cut -f1))"
