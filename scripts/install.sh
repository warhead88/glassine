#!/bin/zsh
# Builds Glassine and installs it to /Applications, replacing a running copy.
# Builds go to build.noindex so Spotlight doesn't list duplicate apps.
set -euo pipefail
cd "$(dirname "$0")/.."

xcodegen generate --quiet
xcodebuild -project Glassine.xcodeproj -scheme Glassine -configuration "${1:-Debug}" \
  -destination "platform=macOS,arch=arm64" -derivedDataPath build.noindex -allowProvisioningUpdates -quiet build

pkill -x Glassine || true
rm -rf /Applications/Glassine.app
cp -R "build.noindex/Build/Products/${1:-Debug}/Glassine.app" /Applications/
open /Applications/Glassine.app
