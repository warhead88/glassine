# Glassine design files

| File | What |
|---|---|
| `glassine.icon` | **App icon** — Icon Composer document, built into the app via `project.yml` |
| `glassine-g.svg` | The G alone, outlines, transparent 1024×1024 — **layer for Icon Composer** |
| `glassine.icon/Assets/sleeve.svg` | The glassine sleeve over the lower third of the icon (0.4) |
| `glassine-v2.svg` | Current logo: G on the macOS icon grid (824×824 body, 185 pt corners) |
| `glassine-v1.svg/.png` | First version (Apple Chancery, text — not outlines). Kept for history |
| `g-candidates.png` | Font comparison the G was chosen from (variant 6) |
| `fonts/` | Fraunces roman and italic (variable: opsz, wght, SOFT, WONK), SIL Open Font License (`Fraunces-OFL.txt`). Both ship in the app |
| `tools/glyphs.swift` | Renders the comparison sheet and exports the G as outlines |
| `readme/` | README icon (rendered from `glassine.icon` with `ictool`) |
| `demo/` | Tooling for future README GIFs: scripted input driver (backs up the clipboard), MOV → GIF converter, a demo scene. GIFs were removed for now — see ROADMAP |
| `0.4/` | The 0.4 redesign: decisions, tokens (`tokens.json` → the app's theme colors), scenes, backlog |
| `dmg/`, `tools/dmg-background.swift` | DMG window background (1x, 2x, TIFF) in the 0.4 look, used by `scripts/release.sh` |

**The G:** Fraunces Italic, weight 400, optical size 144, softness (SOFT) 100.

**The 0.4 icon** (as in the update window, scene 3): a cream G (`#EDEBE2`) on an ink gradient
(`#2C3343` → `ink` `#1C2230`), its lower part in a glassine sleeve — the paper color at 24%, translucent,
in front of the G. Dark, Clear and Tinted are derived by the system. Render a preview:

```bash
"/Applications/Xcode.app/Contents/Applications/Icon Composer.app/Contents/Executables/ictool" Design/glassine.icon \
  --export-image --output-file Design/readme/icon.png --platform macOS --rendition Default --width 256 --height 256 --scale 2
```

Regenerate the layer (e.g. after changing weight):

```bash
swift Design/tools/glyphs.swift svg Design/fonts/Fraunces-Italic.ttf 400 Design/glassine-g.svg 144 100
```

## Building the app icon in Icon Composer

1. Xcode → Open Developer Tool → **Icon Composer**, File → New.
2. Drag `glassine-g.svg` onto the canvas — it becomes a layer in a group.
3. Select the top-level icon (left sidebar) → **Fill**: the ink gradient above.
4. Select the G layer: fill `#EDEBE2`; play with **Liquid Glass**
   (on/off), **Translucency**, **Shadow** (Neutral/Chromatic), **Specular**.
5. Check the appearance previews at the top: Default, Dark, Clear, Tinted.
6. File → Save (`Design/glassine.icon`), then `scripts/install.sh`.

The build compiles it into `Assets.car` (Liquid Glass, macOS 26+) and `glassine.icns`
(flat, macOS 14–15). Exports from Icon Composer (`Icon Exports/`) are previews only and not committed.
If Finder keeps showing an old icon: `touch /Applications/Glassine.app`.
