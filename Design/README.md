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
| `readme/` | README icon (rendered from `glassine.icon` with `ictool`) and GIFs: `capture`, `record`, `pin` (recipe below) |
| `demo/` | Older GIF tooling: scripted input driver (backs up the clipboard), MOV → GIF converter, a demo scene. The README GIFs are now recorded by hand (below) |
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

## README GIFs

Record with live input in QuickTime Player (File → New Screen Recording): Glassine leaves its own windows
out of its recordings. Then trim, crop (Retina pixels), speed up and encode with one shared palette:

```bash
ffmpeg -ss 1.5 -to 34 -i Screenshot.mov -vf "crop=2320:1440:380:200,setpts=PTS/2,fps=12,scale=900:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=192:stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=4:diff_mode=rectangle" Design/readme/capture.gif
```

Used for 0.4: `capture` 1.5–34 s ×2, `record` 3–51.6 s ×2.5 (crop `2640:1644:384:320`), `pin` 1–27 s ×1.6
(crop `2388:1644:636:320`). Keep each around 2–3 MB.
`record` blurs the Add Source menu (it lists the running apps) for source seconds 12–17.5: before the crop,
`split[m][b];[b]crop=410:1010:1290:440,boxblur=24:3[bl];[m][bl]overlay=1290:440:enable='between(t,9,14.5)'`
(`t` counts from `-ss`).
