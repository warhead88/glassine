#!/bin/zsh
# Writes Glassine/Resources/Acknowledgements.txt — the licenses of the code Glassine ships with
# (MIT asks for its notice in every copy) — from the resolved Swift packages. Run after updating them.
set -euo pipefail
cd "$(dirname "$0")/.."

CHECKOUTS=build.noindex/SourcePackages/checkouts
[[ -d $CHECKOUTS/Sparkle ]] || xcodebuild -resolvePackageDependencies -project Glassine.xcodeproj -scheme Glassine \
  -derivedDataPath build.noindex -quiet

{
  print "Glassine is free software under the GNU General Public License v3.0."
  print "It includes the following open-source components."
  for name url file in \
    Sparkle https://sparkle-project.org $CHECKOUTS/Sparkle/LICENSE \
    KeyboardShortcuts https://github.com/sindresorhus/KeyboardShortcuts $CHECKOUTS/KeyboardShortcuts/license; do
    print "\n\n$name — $url\n"
    cat $file
  done
} > Glassine/Resources/Acknowledgements.txt
echo "Glassine/Resources/Acknowledgements.txt ($(wc -l < Glassine/Resources/Acknowledgements.txt | tr -d ' ') lines)"
