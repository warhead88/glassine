#!/bin/zsh
# Renders svg/*.svg to png/<name>@2x.png with headless Chrome (fonts load from Google Fonts).
set -e
cd "$(dirname "$0")"
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
mkdir -p png
for f in svg/*.svg; do
  name=$(basename "$f" .svg)
  w=$(sed -n 's/.*<svg[^>]* width="\([0-9.]*\)".*/\1/p' "$f" | head -1)
  h=$(sed -n 's/.*<svg[^>]* height="\([0-9.]*\)".*/\1/p' "$f" | head -1)
  "$CHROME" --headless=new --disable-gpu --hide-scrollbars --default-background-color=00000000 \
    --window-size="$w,$h" --force-device-scale-factor=2 --virtual-time-budget=6000 \
    --screenshot="$PWD/png/$name@2x.png" "file://$PWD/$f" >/dev/null 2>&1
  echo "png/$name@2x.png"
done
