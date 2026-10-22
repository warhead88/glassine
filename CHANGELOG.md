# Changelog

Notable changes in each Glassine release. The format follows [Keep a Changelog](https://keepachangelog.com):
sections **Added**, **Changed**, **Fixed**, **Removed** (and **Security** when needed). A release's
section is what the update window shows, so write it for users. Versions follow
[Semantic Versioning](https://semver.org).

## [Unreleased]

### Added
- Accent color in Settings → General → Appearance: Ink, Sage, Stamp, Ochre or your macOS accent

## [0.3.1] - 2026-10-22

### Fixed
- An app's audio track stayed silent when the app's window wasn't on screen (minimized, hidden or on another Space). If an app really isn't running, Glassine now says so instead of recording silence

## [0.3.0] - 2026-10-22

### Added
- The recorded area can be moved and resized after you pick it. While recording, drag its border to move it and a corner to zoom in or out; the video keeps its size
- Countdown before recording in Settings → Capture: off, 3, 5 or 10 seconds

## [0.2.0] - 2026-10-22

### Added
- Screen recording (⌥⇧⌘R): an area, a window or the whole screen, as MP4 or GIF. The controls beside it — or docked to the screen edge — set codec (H.264, HEVC or ProRes), frame rate, bitrate, scale, the pointer and audio tracks; while recording they pause, stop or discard
- Audio tracks: put system audio, microphones and single apps into tracks of their own, so voice and app sound stay apart in the file
- Updates: Check for Updates… in Settings, a daily check in the background, and a window that shows what's new
- QR codes are found in every capture: the preview offers Copy QR Link, or a list when there are several
- Area capture can go without the frame, and the frame's bottom corners can be square like the screen's

### Changed
- Glassine is free software under GPLv3
- Copy Text from Screen reads text only — QR codes moved to the preview

### Fixed
- The start sound plays every time, even when area capture is reopened right away

## [0.1.0] - 2026-10-22

First release: area, window and screen capture with a Quick Access preview, the editor, pins, text
recognition, color picker and ruler.
