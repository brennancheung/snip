# Agents working on Snip

Snip is a native macOS menu bar app (Swift, AppKit, ScreenCaptureKit) for quick screen recordings:
hotkey, pick a window or drag a box, record, and a small CRF-encoded MP4 lands in ~/Movies/snip.

## Containers can't build it

The containers are Linux. AppKit, ScreenCaptureKit and AVFoundation don't exist there, so
`swift build` won't work in a container. Write the code carefully against the macOS 15 SDK and
say in your pull request that it is unbuilt. The first mate builds every pull request on the
owner's Mac (`swift build`, `swift test`, `bin/build-app`) and sends compiler errors back to you.

## Layout

- `Sources/SnipCore`: models (`CaptureTarget`, `RecordingSettings`, `RecorderState`), the
  `ScreenRecorder` and `RecordingEncoder` protocols, output naming, settings persistence, the
  ffmpeg encoder. Foundation and CoreGraphics only.
- `Sources/SnipCapture`: `SCKRecorder`, the ScreenCaptureKit recorder.
- `Sources/SnipUI`: hotkey, selection overlay, recording HUD, menu bar, settings window,
  `AppController` (the state machine).
- `Sources/Snip`: the app's `main.swift`. `Sources/snip-cli`: a command-line driver for capture
  and encode, no UI.
- `Sources/snip-ui-preview`: draws Snip's own UI (selection bar, overlay, pill, countdown, Settings)
  off-screen at interface sizes and writes PNGs: `swift run snip-ui-preview /tmp/snip-ui 100 200`.
  The views come from `UIPreviews` in SnipUI.
- `bin/build-app`: builds and signs `build/Snip.app`.

Library first: capture and encode work from `snip-cli` before the UI depends on them.

## Conventions

- Swift 6 toolchain, Swift 5 language mode, macOS 15 minimum.
- Stay in the files your task names. Other agents work in the other modules at the same time.
- Every size Snip's UI sets (fonts, paddings, radii, icons, panels) goes through `UIScale`, the
  Interface size setting: a macOS default size times the scale. Snip draws its own buttons,
  segments, popups, switches and slider (`BezelButton`, SettingsControls.swift) because AppKit's
  bezelled controls keep a fixed height per control size and clip larger text.
- Tests (`swift-testing`) only for logic that can break quietly: naming, settings, ffmpeg
  arguments. No tests of how UI looks.
- Recordings and mockup renders are never committed except the PNGs under `docs/mockups/`.
