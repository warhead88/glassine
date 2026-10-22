#!/bin/zsh
# Builds a Release and packs dist/Glassine-<version>.dmg: open it, drag Glassine to Applications.
# The DMG background is rendered by Design/tools/dmg-background.swift into Design/dmg/.
#
# Signed with the project's Apple Development certificate it runs on this Mac; on other Macs
# Gatekeeper asks to confirm the first launch. To sign for distribution and notarize, set:
#   DEVELOPER_ID="Developer ID Application: Name (TEAMID)"   (paid Apple Developer Program)
#   NOTARY_PROFILE=<name from `xcrun notarytool store-credentials`>
#
# Also writes dist/appcast.xml, the update feed: this version, its CHANGELOG.md section as the
# notes, and the DMG's signature made with the update key in the login keychain (created once
# with Sparkle's generate_keys). scripts/publish.sh uploads both to a GitHub release.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(sed -n 's/^ *MARKETING_VERSION: *"\(.*\)"/\1/p' project.yml)
# The build number Sparkle compares: one more with every commit.
BUILD=$(git rev-list --count HEAD)
NOTES=$(scripts/changelog-section.sh "$VERSION")
if [[ -z "$NOTES" ]]; then
  echo "CHANGELOG.md has no section for $VERSION — rename [Unreleased] to [$VERSION] - $(date +%F)" >&2
  exit 1
fi

xcodegen generate --quiet
xcodebuild -project Glassine.xcodeproj -scheme Glassine -configuration Release \
  -destination "platform=macOS,arch=arm64" -derivedDataPath build.noindex \
  -allowProvisioningUpdates -quiet build CURRENT_PROJECT_VERSION="$BUILD"

APP=build.noindex/Build/Products/Release/Glassine.app

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

SPARKLE=$(echo build.noindex/SourcePackages/artifacts/*/Sparkle/bin)
SIGNATURE=$("$SPARKLE/sign_update" --account com.warhead88.glassine "$DMG")
DOWNLOAD_BASE=${DOWNLOAD_BASE:-https://github.com/warhead88/glassine/releases/download/v$VERSION}
cat > dist/appcast.xml <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Glassine</title>
    <item>
      <title>Glassine $VERSION</title>
      <pubDate>$(LC_ALL=C date -u "+%a, %d %b %Y %H:%M:%S +0000")</pubDate>
      <sparkle:version>$BUILD</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      <description sparkle:format="plain-text"><![CDATA[
$NOTES
]]></description>
      <enclosure url="$DOWNLOAD_BASE/$(basename "$DMG")" type="application/octet-stream" $SIGNATURE/>
    </item>
  </channel>
</rss>
XML

echo "$DMG ($(du -h "$DMG" | cut -f1)), build $BUILD, dist/appcast.xml"
