<p align="center">
  <img src="Design/readme/icon.png" width="128" height="128" alt="Glassine icon">
</p>

<h1 align="center">Glassine</h1>

<p align="center">
  A quiet, native screenshot tool for macOS — capture, record, annotate, pin, and copy text from your screen.<br>
  No Dock icon, no network, no clutter. Just shortcuts.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-14%2B-black?logo=apple" alt="macOS 14+">
  <img src="https://img.shields.io/badge/Apple%20Silicon-native-black" alt="Apple Silicon">
  <img src="https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white" alt="Swift 6">
</p>

---

## Capture

Press <kbd>⇧⌘4</kbd> and the screen freezes, so menus and hover states hold still while you select.
A magnifier shows the pixels, coordinates and color under the pointer. Every capture lands in a small
floating preview — drag it straight into any app, or click it to annotate.

| Shortcut | Action |
|---|---|
| <kbd>⇧⌘4</kbd> | Capture an area — drag to select (<kbd>⇧</kbd> square, <kbd>⌥</kbd> from center, hold <kbd>Space</kbd> to move) |
| <kbd>⇧⌘5</kbd> | Capture a window — click the highlighted one (<kbd>Space</kbd> switches area ↔ window) |
| <kbd>⇧⌘3</kbd> | Capture the whole screen |
| <kbd>⌥⇧⌘T</kbd> | Copy text from the screen (on-device OCR, Russian and English) |
| <kbd>⌥⇧⌘C</kbd> | Pick a color (HEX, RGB or HSL) |
| <kbd>⌥⇧⌘M</kbd> | Measure distances in pixels and points |
| <kbd>⌥⇧⌘P</kbd> | Show / hide pins |
| <kbd>⌥⇧⌘,</kbd> | Settings |

All shortcuts can be changed in Settings. Repeat-last-area and timed capture are there too.

## Record

Press <kbd>⌥⇧⌘R</kbd>, then drag an area, click a window (it's followed even when it moves or is
covered), or press <kbd>↩</kbd> for the whole screen. The controls appear beside it — or, when there's no
room, docked to the screen edge: format (MP4 or GIF), codec, frame rate, bitrate, scale, pointer,
audio tracks, and which side the controls go. Press the red button or <kbd>↩</kbd>;
after a 3-second countdown they turn into a small player with the time, pause, stop and discard.

Video is hardware-encoded as H.264 (plays everywhere), HEVC/H.265 (half the size) or ProRes 422 (for
editing, in a .mov), at 30 or 60 fps. Sound is recorded in tracks you put together: each track mixes
its sources — system audio, a microphone, or single apps — and stays separate in the file, so an
editor can level your voice apart from the app.
GIFs are made from the recording at 10–24 fps, scaled to the width you choose. The result lands in the
same floating preview as screenshots.

## Annotate

Arrows, shapes, text, pen, marker, numbered steps, blur, pixelate and redact — each on a single key.
Shapes switch back to Select when you finish, so you can resize them right away. Add padding, rounded
corners, a shadow and a background; it grows by itself when an arrow points past the edge.

## Pin

Keep a capture floating above every window — as a reference while you design or code. Scroll to zoom,
<kbd>⌥</kbd>-scroll for opacity, or let clicks pass through it.

## Copy text from the screen

Select any text — in an image, a video, a locked PDF — and it's on your clipboard. Recognition runs on
your Mac with Vision.

QR codes don't need a separate mode: every capture is checked for them, and if there are any the
preview offers **Copy QR Link** — or a list to copy or open each one when there are several.

## Install

1. Download `Glassine-<version>.dmg` from [Releases](../../releases).
2. Open it and drag **Glassine** to **Applications**.
3. Launch it and follow the welcome window: allow Screen Recording, and turn off macOS's own screenshot
   shortcuts (System Settings → Keyboard → Keyboard Shortcuts… → Screenshots) so Glassine gets
   <kbd>⇧⌘3</kbd>, <kbd>⇧⌘4</kbd> and <kbd>⇧⌘5</kbd>.

Glassine checks for updates once a day (Settings → General → Updates, or **Check for Updates…**)
and shows what's new before installing.

Current builds aren't notarized yet: on a Mac other than the developer's, macOS asks once before the
first launch — right-click Glassine → **Open**.

To remove Glassine: Settings → General → **Uninstall…** — the app, its settings and caches go to the
Trash; your screenshots stay.

## Privacy

Everything stays on your Mac. The only network request is the update check — it fetches the release feed
from GitHub and sends nothing about you (turn it off in Settings). No analytics. Glassine writes only to
its own folders (named `com.warhead88.glassine`) and the screenshot folder you choose.

## Build from source

Requires Xcode 26 or later and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
scripts/install.sh     # build and install to /Applications (pass Release for a release build)
scripts/test.sh        # unit tests (Swift Testing)
scripts/release.sh     # Release build packed as dist/Glassine-<version>.dmg, plus the update feed
scripts/publish.sh     # GitHub release with both (notes from CHANGELOG.md)
```

The Xcode project is generated from `project.yml`. Code lives in `Glassine/` by feature —
`Capture`, `QuickAccess`, `Editor`, `Pins`, `Smart`, `Settings`; design sources and the icon in `Design/`.
See [ROADMAP.md](ROADMAP.md) for what's next and [TESTING.md](TESTING.md) for the manual checklist.

## License

Glassine is free software under the [GNU General Public License v3.0](LICENSE): read it, build it,
change it and share your changes under the same license. Copyright © 2026 warhead88.

The name **Glassine** and the Glassine icon are not covered by the license. Forks are welcome under
their own name and icon, so nobody mistakes them for the original.

Third-party: [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) (MIT); the Fraunces font
in `Design/fonts`, used to draw the icon (SIL Open Font License).
