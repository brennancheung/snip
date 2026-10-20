# Snip

A small native macOS screen recorder for quick snippets, in place of OBS.

1. Press **⇧⌘6** (or click the menu bar icon, **New Recording**).
2. Hover a window and click it, or drag a box anywhere. Adjust the box by its handles if you like.
3. Press **Return** (or click **Record**). A 3-second countdown, then it records.
4. Press **⇧⌘6** again, or **Stop** on the floating pill.
5. Snip compresses the recording with x264 at a constant rate factor (CRF 23 by default) and puts
   `Snip 2026-10-19 at 14.03.22.mp4` in ~/Downloads, copied to the clipboard, ready to paste.

## How it works

ScreenCaptureKit records the chosen window or region to a high-quality intermediate `.mov` in a
temporary folder (hardware encoded, so recording costs almost no CPU). On stop, ffmpeg re-encodes
it with libx264 at the chosen CRF, `yuv420p` and `+faststart`, which makes screen recordings
several times smaller than the hardware encode. Microphone and system audio, when turned on in
Settings or the menu, become one AAC track (mixed when both are on). Without ffmpeg (`brew install ffmpeg`) the
intermediate is kept as the result.

## Build

```sh
swift build          # libraries, the app and snip-cli
swift test
bin/build-app        # build/Snip.app, signed
```

The first run asks for Screen Recording permission (System Settings › Privacy & Security), and
turning the microphone on the first time asks for Microphone permission.
