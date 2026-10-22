#!/bin/zsh
# Publishes what scripts/release.sh built: tags the version and creates its GitHub release with
# the DMG and appcast.xml. Installed copies find the update through
# releases/latest/download/appcast.xml, so every release must carry its appcast.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(sed -n 's/^ *MARKETING_VERSION: *"\(.*\)"/\1/p' project.yml)
DMG="dist/Glassine-$VERSION.dmg"
[[ -f "$DMG" && -f dist/appcast.xml ]] || { echo "Run scripts/release.sh first" >&2; exit 1; }
grep -q "<sparkle:shortVersionString>$VERSION<" dist/appcast.xml || { echo "dist/appcast.xml is not for $VERSION" >&2; exit 1; }

gh release create "v$VERSION" "$DMG" dist/appcast.xml --title "Glassine $VERSION" \
  --notes "$(scripts/changelog-section.sh "$VERSION")"
