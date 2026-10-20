# How the README images are made

Each image is Snip's real UI placed on a staged macOS desktop, rendered with headless Chromium at
1440 × 900 points and device scale 2.

- `ui/` holds renders of Snip's own views from `snip-ui-preview` at 200% interface size, one
  pixel per point, which is exactly 2x pixels of the default size:
  ```sh
  swift run snip-ui-preview docs/images/src/ui 200
  ```
  Only `overlay-hover`, `overlay-selected`, `pill`, `done-panel` and `settings` are used; delete
  the rest it writes.
- `desktop.css` and `desktop.js` draw the desktop: wallpaper, menu bar, an editor, a browser, a
  terminal and the Dock.
- `snip.js` cuts the bar, labels, pill, panel and Settings out of the renders and places them.
  The overlay's dimming, outlines and handles, which the renders draw over plain grey, are drawn
  again over the desktop with the sizes and colours from `OverlayView` and `RecordingBorder`. The
  pill and the after-recording panel use the dark HUD material, which off-screen renders can't
  draw, so a translucent dark background stands in for it.
- One HTML page per image. `render.cjs` renders them all to `docs/images/*.webp`:
  ```sh
  npm install playwright sharp && npx playwright install chromium   # anywhere, once
  NODE_PATH=/path/to/node_modules node docs/images/src/render.cjs
  ```
  On Linux, install Inter, JetBrains Mono and Noto Sans Symbols 2 as system fonts; they stand in
  for SF Pro and SF Mono.

The box in the hero and recording images is 560 × 300 points and the hovered browser window
840 × 500, the sizes `snip-ui-preview` labels "1120 × 600" and "Safari · 1680 × 1000". If you
render the UI again with different labels, change `GEO` in `desktop.js` to match.
