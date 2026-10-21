# Glassine

Native macOS utility (screenshots first; later screen recording, editing, pinning).
Bundle ID `com.warhead88.glassine` — never change it. Minimum macOS 14. Swift 6, AppKit + SwiftUI, no Rust.

## Build

The Xcode project is generated from `project.yml` (not committed). Build and install to /Applications:

```bash
scripts/install.sh            # Debug; pass Release for a release build
```

Builds go to `build.noindex/` so Spotlight doesn't show duplicate copies of the app.

## Conventions

- Agent app (`LSUIElement`): no Dock icon. Menu bar icon is optional and off by default.
  Relaunching the app opens Settings; first launch (or missing permission) opens the Welcome window.
- Clean uninstall: write only to paths listed in `Glassine/Core/AppPaths.swift`
  (Application Support / Caches / Logs / Preferences, all named by bundle ID).
  No privileged helpers, LaunchDaemons or .pkg installers. Login item only via `SMAppService.mainApp`.
  Saved screenshots are user content and are never deleted by the app.
- Not sandboxed (Developer ID distribution).
- Features go in their own folder under `Glassine/` (`Capture/`, `Settings/`, …).
- Plan and priorities live in `ROADMAP.md`; tick items off there when they ship.
- Manual QA checklist: `TESTING.md` — extend it when a feature ships.
- Logs: `/usr/bin/log stream --predicate 'subsystem == "com.warhead88.glassine"'` (plain `log` is a zsh builtin).
- Debug builds: `open /Applications/Glassine.app --args --debug-preview` shows sample previews without the hotkey.
