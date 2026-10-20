# AGENTS.md

Notes for AI coding assistants working in this repository. People should read
[CONTRIBUTING.md](CONTRIBUTING.md); everything there applies here too.

## What this is

Snip is a native macOS menu bar app (Swift, AppKit, ScreenCaptureKit) for short screen recordings:
a global hotkey, pick a window or drag a box, record, and ffmpeg compresses the result into a
small MP4 in `~/Movies/snip`. Swift Package Manager, no Xcode project.

## Building and testing

- `swift build`, `swift test`, and `bin/build-app` for the app bundle. All three need macOS 15 or
  later: AppKit, ScreenCaptureKit and AVFoundation don't exist on Linux, so the package doesn't
  build there. If you can't build, keep changes small, write them carefully against the macOS 15
  SDK, and say plainly that they are unbuilt.
- `swift test` covers `SnipCore` only. The encode tests run real ffmpeg and are skipped when it
  isn't installed (`brew install ffmpeg`).
- To see UI changes without running the app: `swift run snip-ui-preview /tmp/snip-ui 100 200`
  writes PNGs of the overlay, bar, pill, countdown, after-recording panel and Settings.

## Rules that are easy to miss

- Every UI size goes through `UIScale` (`ui.metric(_:)`, `ui.font(_:weight:)`); never hard-code
  points in SnipUI. Use Snip's own controls (`BezelButton`, `SettingsControls.swift`), not
  AppKit's bezelled ones, which clip at larger interface sizes.
- `SnipCore` stays Foundation and CoreGraphics only.
- Settings are decoded key by key with defaults (`RecordingSettings.init(from:)`), so a new
  field must not break settings saved by an older build. Add a test when you add a field.
- ffmpeg arguments are covered by `FFmpegEncoderTests`; update them with any encoder change.
- Keep the bundle identifier `com.brennancheung.snip`: Screen Recording permission is keyed to it.
- Don't commit recordings, build output or rendered previews.
