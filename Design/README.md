# Glassine design files

| File | What |
|---|---|
| `glassine.icon` | **App icon** — Icon Composer document, built into the app via `project.yml` |
| `glassine-g.svg` | The G alone, outlines, transparent 1024×1024 — **layer for Icon Composer** |
| `glassine-v2.svg` | Current logo: G on the macOS icon grid (824×824 body, 185 pt corners) |
| `glassine-v1.svg/.png` | First version (Apple Chancery, text — not outlines). Kept for history |
| `g-candidates.png` | Font comparison the G was chosen from (variant 6) |
| `fonts/` | Fraunces Italic, SIL Open Font License (see `Fraunces-Italic-OFL.txt`) |
| `tools/glyphs.swift` | Renders the comparison sheet and exports the G as outlines |
| `readme/` | README icon (rendered from `glassine.icon` with `ictool`) |
| `demo/` | Tooling for future README GIFs: scripted input driver (backs up the clipboard), MOV → GIF converter, a demo scene. GIFs were removed for now — see ROADMAP |
| `dmg/`, `tools/dmg-background.swift` | DMG window background (1x/2x) used by `scripts/release.sh` |

**The G:** Fraunces Italic, weight 400, optical size 144, softness (SOFT) 100. Color `#cccccc` on `#1a1a1a`.

Regenerate the layer (e.g. after changing weight):

```bash
swift Design/tools/glyphs.swift svg Design/fonts/Fraunces-Italic.ttf 400 Design/glassine-g.svg 144 100
```

## Building the app icon in Icon Composer

1. Xcode → Open Developer Tool → **Icon Composer**, File → New.
2. Drag `glassine-g.svg` onto the canvas — it becomes a layer in a group.
3. Select the top-level icon (left sidebar) → **Fill**: solid `#1a1a1a`
   (or try a subtle gradient / a lighter translucent fill — fitting for "glassine").
4. Select the G layer: keep fill `#cccccc` or set it there; play with **Liquid Glass**
   (on/off), **Translucency**, **Shadow** (Neutral/Chromatic), **Specular**.
5. Check the appearance previews at the top: Default, Dark, Clear, Tinted.
6. File → Save (`Design/glassine.icon`), then `scripts/install.sh`.

The build compiles it into `Assets.car` (Liquid Glass, macOS 26+) and `glassine.icns`
(flat, macOS 14–15). Exports from Icon Composer (`Icon Exports/`) are previews only and not committed.
If Finder keeps showing an old icon: `touch /Applications/Glassine.app`.
