# Glassine

Native macOS utility (screenshots first; later screen recording, editing, pinning).
Bundle ID `com.warhead88.glassine` — never change it. Minimum macOS 14. Swift 6, AppKit + SwiftUI, no Rust.

## Build

The Xcode project is generated from `project.yml` (not committed). Build and install to /Applications:

```bash
scripts/install.sh            # Debug; pass Release for a release build
```

Builds go to `build.noindex/` so Spotlight doesn't show duplicate copies of the app.

Release DMG (`dist/Glassine-<version>.dmg`, drag to Applications):

```bash
scripts/release.sh            # DEVELOPER_ID=… NOTARY_PROFILE=… to sign for distribution and notarize
```

Without a Developer ID (paid program) the DMG runs on this Mac; elsewhere Gatekeeper asks first.
The DMG window (arrow, caption) is laid out by `scripts/dmg-settings.py` (dmgbuild, private venv in
`build.noindex`) over `Design/dmg/background.tiff`, rendered by `Design/tools/dmg-background.swift`.

Screen Recording permission: request only through `ScreenAccess.request()` — the system prompt the
first time, the settings pane after. Never both.

Unit tests (Swift Testing, `Tests/`), run before every commit that touches logic:

```bash
scripts/test.sh
```

Keep testable logic as pure functions (`Glassine/Core/Geometry.swift`) and call them from the views;
the test host starts the app bare (no delegate), so tests never touch hotkeys, windows or user files.

## Conventions

- Agent app (`LSUIElement`): no Dock icon. Menu bar icon is optional and off by default.
  Relaunching the app opens Settings; first launch (or missing permission) opens the Welcome window.
- Clean uninstall (Settings → General → Uninstall…, `Core/Uninstaller.swift`, moves to Trash; dry run:
  `--debug-uninstall-plan` logs the plan): write only to paths listed in `Glassine/Core/AppPaths.swift`
  (Application Support / Caches / Logs / Preferences, all named by bundle ID).
  No privileged helpers, LaunchDaemons or .pkg installers. Login item only via `SMAppService.mainApp`.
  Saved screenshots are user content and are never deleted by the app.
- Not sandboxed (Developer ID distribution).
- License GPLv3 (`LICENSE`); the name Glassine and the icon are not covered (README → License).
  Third-party code must be GPLv3-compatible.
- Features go in their own folder under `Glassine/` (`Capture/`, `Settings/`, …).
- Plan and priorities live in `ROADMAP.md`; tick items off there when they ship.
- Manual QA checklist: `TESTING.md` — extend it when a feature ships.
- Logs: `/usr/bin/log stream --predicate 'subsystem == "com.warhead88.glassine"'` (plain `log` is a zsh builtin).
- Debug builds: `open /Applications/Glassine.app --args --debug-preview` (sample previews) or `--debug-pins` (sample pins) or `--debug-editor` (editor with every annotation) or `--debug-welcome` (permission steps even when granted) — checks without the hotkey or synthetic input.
