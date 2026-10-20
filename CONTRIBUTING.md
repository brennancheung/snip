# Contributing to Snip

Thanks for helping. Snip is a personal tool kept small on purpose: a quick way to record a short
clip of the screen. Bug fixes and polish are welcome. For a new feature, open an issue first, since
it may not fit what Snip is for.

## Setup

Follow [Getting it running](README.md#getting-it-running) in the README: macOS 15 or later, Xcode
16 or the Swift 6 toolchain, and `brew install ffmpeg`. Run `bin/make-signing-cert` once, so
Screen Recording permission survives your rebuilds.

```sh
swift build
swift test
bin/build-app && open build/Snip.app
```

Before you open a pull request, `swift build` and `swift test` should pass; CI runs both on
macOS. If you changed the UI, say how you checked it, and include a screenshot.

## Layout

- `Sources/SnipCore`: models (`CaptureTarget`, `RecordingSettings`, `RecorderState`), the
  `ScreenRecorder` and `RecordingEncoder` protocols, output naming, settings persistence, the
  ffmpeg encoder. Foundation and CoreGraphics only, no AppKit.
- `Sources/SnipCapture`: `SCKRecorder` (ScreenCaptureKit) and microphone capture.
- `Sources/SnipUI`: hotkey, selection overlay, recording pill and border, countdown,
  after-recording panel, menu bar, Settings, and `AppController`, the state machine that ties
  them together.
- `Sources/Snip`: the app's `main.swift`.
- `Sources/snip-cli`: a command-line driver for capture and encode, no UI.
- `Sources/snip-ui-preview`: draws Snip's own UI off-screen at chosen interface sizes and writes
  PNGs, to check how it looks without clicking through the app:
  `swift run snip-ui-preview /tmp/snip-ui 100 200 [recording.mp4]`. The views come from
  `UIPreviews` in SnipUI.
- `bin/build-app` builds and signs `build/Snip.app`; `bin/make-signing-cert` creates the local
  signing certificate it prefers.
- `docs/images`: the README's images. `docs/images/src/README.md` explains how to make them again.

Library first: capture and encode work from `snip-cli` before the UI depends on them.

## Conventions

- Swift 6 toolchain, Swift 5 language mode, macOS 15 minimum.
- Every size Snip's UI sets (fonts, paddings, corner radii, icons, panels) goes through
  `UIScale`, the Interface size setting: a macOS default size times the scale, for example
  `ui.metric(8)` or `ui.font(13, weight: .medium)`. Snip draws its own buttons, segmented
  controls, pop-ups, switches and slider (`BezelButton`, `SettingsControls.swift`) because
  AppKit's bezelled controls keep a fixed height per control size and clip larger text.
- Tests use `swift-testing` and cover logic that can break quietly: output naming, settings,
  ffmpeg arguments. There are no tests of how the UI looks; use `snip-ui-preview` for that.
- Comments say why, not what, in plain sentences.
- Don't commit recordings or renders, except the images under `docs/images`.
