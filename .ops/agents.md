# Agents working on Snip

Snip is a native macOS menu bar app (Swift, AppKit, ScreenCaptureKit) for quick screen recordings:
hotkey, pick a window or drag a box, record, and a small CRF-encoded MP4 lands in ~/Downloads.

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
- `bin/build-app`: builds and signs `build/Snip.app`.

Library first: capture and encode work from `snip-cli` before the UI depends on them.

## Conventions

- Swift 6 toolchain, Swift 5 language mode, macOS 15 minimum.
- Stay in the files your task names. Other agents work in the other modules at the same time.
- Tests (`swift-testing`) only for logic that can break quietly: naming, settings, ffmpeg
  arguments. No tests of how UI looks.
- Recordings and mockup renders are never committed except the PNGs under `docs/mockups/`.
