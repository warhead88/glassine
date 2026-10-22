#!/bin/zsh
# Builds a Release and packs dist/Glassine-<version>.dmg: open it, drag Glassine to Applications.
# The DMG background is rendered by Design/tools/dmg-background.swift into Design/dmg/.
#
# Signed with the project's Apple Development certificate it runs on this Mac; on other Macs
# Gatekeeper asks to confirm the first launch. To sign for distribution and notarize, set:
#   DEVELOPER_ID="Developer ID Application: Name (TEAMID)"   (paid Apple Developer Program)
#   NOTARY_PROFILE=<name from `xcrun notarytool store-credentials`>
set -euo pipefail
cd "$(dirname "$0")/.."

xcodegen generate --quiet
xcodebuild -project Glassine.xcodeproj -scheme Glassine -configuration Release \
  -destination "platform=macOS,arch=arm64" -derivedDataPath build.noindex \
  -allowProvisioningUpdates -quiet build

APP=build.noindex/Build/Products/Release/Glassine.app
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")

if [[ -n "${DEVELOPER_ID:-}" ]]; then
  codesign --force --options runtime --timestamp \
    --entitlements Glassine/Resources/Glassine.entitlements --sign "$DEVELOPER_ID" "$APP"
fi
codesign --verify --strict "$APP"

# The DMG opens as a plain Finder window: Glassine, an arrow, Applications — drag to install.
# dmgbuild writes the window layout into the image itself (no Finder scripting, same result
# every time); it lives in a private venv inside build.noindex.
VENV=build.noindex/.venv
if [[ ! -x "$VENV/bin/dmgbuild" ]]; then
  python3 -m venv "$VENV"
  "$VENV/bin/pip" install --quiet --disable-pip-version-check dmgbuild
fi

mkdir -p dist
DMG="dist/Glassine-$VERSION.dmg"
rm -f "$DMG"
"$VENV/bin/dmgbuild" -s scripts/dmg-settings.py -D app="$APP" -D background=Design/dmg/background.tiff \
  "Glassine $VERSION" "$DMG" > /dev/null

if [[ -n "${DEVELOPER_ID:-}" ]]; then
  codesign --timestamp --sign "$DEVELOPER_ID" "$DMG"
fi
if [[ -n "${NOTARY_PROFILE:-}" ]]; then
  xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG"
fi

echo "$DMG ($(du -h "$DMG" | cut -f1))"
