# Changelog

Notable changes in each Glassine release. The format follows [Keep a Changelog](https://keepachangelog.com):
sections **Added**, **Changed**, **Fixed**, **Removed** (and **Security** when needed). A release's
section is what the update window shows, so write it for users. Versions follow
[Semantic Versioning](https://semver.org).

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
