#!/bin/zsh
# Runs the unit tests (Swift Testing) in GlassineTests and prints one line per test.
set -euo pipefail
cd "$(dirname "$0")/.."

xcodegen generate --quiet
xcodebuild test -project Glassine.xcodeproj -scheme Glassine \
  -destination "platform=macOS,arch=arm64" -derivedDataPath build.noindex \
  -allowProvisioningUpdates "$@" 2>&1 \
  | grep -E "^.?(✔|✘|◇)|error:|Expectation failed|TEST (SUCCEEDED|FAILED)"
