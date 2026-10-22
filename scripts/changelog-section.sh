#!/bin/zsh
# Prints one version's section of CHANGELOG.md (the lines under "## [version]"), for the
# update feed and the GitHub release notes.
set -euo pipefail
cd "$(dirname "$0")/.."
awk -v v="$1" '
  /^## / { if (found) exit; if (index($0, "## [" v "]") == 1) { found = 1; next } }
  found { print }
' CHANGELOG.md | sed -e '/./,$!d' | sed -e :a -e '/^\n*$/{$d;N;ba' -e '}'
