#!/bin/zsh
# Records the README GIFs (Design/readme/*.gif) over a neutral demo scene.
# Takes over the mouse and keyboard for about a minute — don't touch them while it runs.
# Needs Glassine installed and running with its default shortcuts, a 1512×982 pt main screen
# (14" MacBook Pro), and Accessibility + Screen Recording for the terminal running it.
# Restores the clipboard and Glassine's settings afterwards.
set -euo pipefail
cd "$(dirname "$0")/../.."

TMP=build.noindex/demo
OUT=Design/readme
REGION=0,33,1512,949          # the screen below the menu bar
D=com.warhead88.glassine
mkdir -p "$TMP" "$OUT"

swiftc -O -o "$TMP/demoscene" Design/demo/DemoScene.swift 2>/dev/null
swiftc -O -o "$TMP/driver" Design/demo/driver.swift 2>/dev/null
swiftc -O -o "$TMP/mov2gif" Design/demo/mov2gif.swift 2>/dev/null

# Glassine window frame "X Y W H" by layer (0 normal, 3 floating previews/pins).
window() {
  swift -e "import AppKit
  let l = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as! [[String: Any]]
  for w in l where (w[kCGWindowOwnerName as String] as? String) == \"Glassine\" && (w[kCGWindowLayer as String] as! Int) == $1 {
    let b = w[kCGWindowBounds as String] as! [String: Double]
    print(Int(b[\"X\"]!), Int(b[\"Y\"]!), Int(b[\"Width\"]!), Int(b[\"Height\"]!)); break }"
}

play() { printf '%s\n' "$@" > "$TMP/step.txt"; "$TMP/driver" "$TMP/step.txt"; }

start_recording() { screencapture -x -k -v -V "$2" -R "$REGION" "$TMP/$1.mov" & REC=$!; sleep 0.7; }
finish_recording() { wait $REC; "$TMP/mov2gif" "$TMP/$1.mov" "$OUT/$1.gif" 12 900; }

# Keep the user's state.
"$TMP/driver" --backup-clipboard "$TMP/clipboard.bak"
defaults export "$D" "$TMP/prefs.plist"
restore() {
  pkill -x Glassine || true; sleep 1
  # import merges, so clear first — otherwise keys added for the recording would stay
  defaults delete "$D" 2>/dev/null || true
  defaults import "$D" "$TMP/prefs.plist"
  open -g /Applications/Glassine.app
  "$TMP/driver" --restore-clipboard "$TMP/clipboard.bak"
  [[ -n "${SCENE:-}" ]] && kill "$SCENE" 2>/dev/null || true
}
trap restore EXIT

defaults write "$D" saveToFile -bool false
defaults write "$D" editorBackground -dict fill gradient gradient -int 0 padding -float 36 cornerRadius -float 14 shadow -bool true
pkill -x Glassine || true; sleep 1; open -g /Applications/Glassine.app; sleep 2
"$TMP/demoscene" & SCENE=$!; sleep 2.5

# 1. Capture an area, the preview appears, hover shows its buttons.
start_recording capture 9
play "wait 0.6" "move 200 360 0.5" "key 21 cmd shift" "wait 0.7" \
     "drag 84 381 1100 898 1.4" "wait 1.6"
read X Y W H <<< "$(window 3)"
play "move $((X + W / 2)) $((Y + H / 2)) 0.9" "wait 2"
finish_recording capture
play "key 53"; pkill -x Glassine; sleep 1; open -g /Applications/Glassine.app; sleep 2

# 2. Copy text from the screen, then read a QR code.
start_recording text 11
play "wait 0.4" "key 17 cmd opt shift" "wait 0.8" "drag 80 210 1066 318 1.1" "wait 2.4" \
     "key 17 cmd opt shift" "wait 0.8" "drag 1170 345 1460 556 1" "wait 2.6"
finish_recording text
sleep 2

# 3. Pin a capture and move it around.
start_recording pin 12
play "wait 0.4" "key 21 cmd shift" "wait 0.7" "drag 1164 82 1465 319 1" "wait 1.4"
read X Y W H <<< "$(window 3)"
play "move $((X + W / 2)) $((Y + H / 2)) 0.7" "wait 0.9" "click $((X + W - 17)) $((Y + 17))" "wait 1.2" \
     "drag 1314 200 760 560 1.6" "wait 0.5" "scroll 760 560 4" "wait 1.6"
finish_recording pin
pkill -x Glassine; sleep 1; open -g /Applications/Glassine.app; sleep 2

# 4. Open the editor from the preview and annotate.
start_recording editor 17
play "wait 0.4" "key 21 cmd shift" "wait 0.7" "drag 84 381 1100 898 1.2" "wait 1.4"
read X Y W H <<< "$(window 3)"
play "click $((X + W / 2)) $((Y + H / 2))" "wait 1.8"
read X Y W H <<< "$(window 0)"
play "key 0" "wait 0.3" \
     "drag $((X + W * 26 / 100)) $((Y + H * 64 / 100)) $((X + W * 43 / 100)) $((Y + H * 46 / 100)) 0.9" "wait 0.4" \
     "key 15" "wait 0.3" \
     "drag $((X + W * 50 / 100)) $((Y + H * 34 / 100)) $((X + W * 74 / 100)) $((Y + H * 56 / 100)) 0.9" "wait 0.4" \
     "key 17" "wait 0.3" "click $((X + W * 18 / 100)) $((Y + H * 30 / 100))" "wait 0.3" \
     "type Look here" "key 36" "wait 0.6" "key 8 cmd" "wait 2"
finish_recording editor
play "key 13 cmd"

ls -la "$OUT"/*.gif
