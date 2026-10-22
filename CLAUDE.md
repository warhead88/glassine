# Glassine

Native macOS utility (screenshots first; later screen recording, editing, pinning).
Bundle ID `com.warhead88.glassine` — never change it. Minimum macOS 14. Swift 6, AppKit + SwiftUI, no Rust.

## Build

The Xcode project is generated from `project.yml` (not committed). Signing comes from
`Config/Signing.xcconfig`: ad hoc, unless the uncommitted `Config/Signing.local.xcconfig` sets a team
(this Mac: the Personal Team, so the Screen Recording permission survives rebuilds). Build and install to /Applications:

```bash
scripts/install.sh            # Debug; pass Release for a release build
```

Builds go to `build.noindex/` so Spotlight doesn't show duplicate copies of the app.

Release DMG (`dist/Glassine-<version>.dmg`, drag to Applications):

```bash
scripts/release.sh            # DEVELOPER_ID=… NOTARY_PROFILE=… to sign for distribution and notarize
```

Without a Developer ID (paid program) the DMG runs on this Mac; elsewhere Gatekeeper asks first.

Versions follow SemVer (`MARKETING_VERSION` in `project.yml`; 0.x until the finished 1.0: minor = features,
patch = fixes); the build number is the commit count, set by `release.sh`. A release:
1. move the `[Unreleased]` notes in `CHANGELOG.md` to `## [x.y.z] - date` (users read them in the update window),
2. bump `MARKETING_VERSION`, run `scripts/release.sh` — DMG plus `dist/appcast.xml`, signed with the update key
   (Sparkle EdDSA, login keychain account `com.warhead88.glassine`; the public half is `SUPublicEDKey`),
3. `scripts/publish.sh` — tag and GitHub release with both files. Installed copies read
   `releases/latest/download/appcast.xml`, so the repo must be public for updates to reach anyone.

Updates (`Glassine/Updates/`) use Sparkle with Glassine's own window. Debug: `--debug-update` (sample window),
`--debug-feed <url> --debug-check-updates` (check a local appcast). A future App Store build leaves this folder out.
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
  Third-party code must be GPLv3-compatible; after adding or updating a package run
  `scripts/acknowledgements.sh` (its notice ships in the app). Contributions: `CONTRIBUTING.md`
  (includes the grant that keeps an App Store build possible).
- Look (0.4 redesign, `Design/0.4/`): colors and type come from `Design/0.4/tokens.json` — run
  `scripts/theme-tokens.py` after editing it (writes `Glassine/Resources/Theme.xcassets` and
  `Glassine/UI/ThemeTokens.swift`; never hand-edit those). In code: `Color.ink`, `NSColor.paper`, …;
  `.textStyle(ThemeTokens.title)` for Fraunces; accent from `Theme` (`.themed()` at each SwiftUI window root,
  `Theme.shared` in AppKit). Red (`rec`) means recording only, never an accent. Fraunces (roman + italic,
  variable) ships from `Design/fonts`; the editor canvas and captures stay neutral, no paper.
- Features go in their own folder under `Glassine/` (`Capture/`, `Settings/`, …).
- Plan and priorities live in `ROADMAP.md`; tick items off there when they ship.
- Manual QA checklist: `TESTING.md` — extend it when a feature ships.
- Logs: `/usr/bin/log stream --predicate 'subsystem == "com.warhead88.glassine"'` (plain `log` is a zsh builtin).
- Debug builds: `open /Applications/Glassine.app --args --debug-preview` (sample previews) or `--debug-pins` (sample pins) or `--debug-editor` (editor with every annotation) or `--debug-welcome` (permission steps even when granted) or `--debug-record-panel [full] [audio]` (recording
  controls for the middle of the screen or all of it, optionally with the audio editor open) or `--debug-record <seconds> [pause|move]` (records with
  the saved options, stops by itself) — checks without the hotkey or synthetic input.
