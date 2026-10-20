# Snip mockups

How Snip should look at each step of a recording, drawn as HTML on a macOS 26 desktop and
rendered to PNG at 1440 × 900 points, 2x. The flow they follow is the plan's
(https://volgenic.com/pages/4b992081-efa6-4f6f-82e1-44e68dfafd88).

1. `01-menu.png`: the menu bar menu, with New Recording, Record Last Area, recent recordings, Settings and Quit.
2. `02-window-hover.png`: selecting; the screen dims and the window under the crosshair lights up with its name and pixel size.
3. `03-drag-box.png`: selecting; a drawn area with eight handles and the bar under it: size, Cancel, Record.
4. `04-countdown.png`: the countdown in the middle of the area, the rest still dimmed.
5. `05-recording.png`: recording; a red border outside the area, the pill under it, the menu bar item red with the time.
6. `06-compressing.png`: the pill compressing, with progress.
7. `07-saved.png`: the notification: saved to Downloads, file name and size, Show in Finder.
8. `08-settings.png`: the Settings window.

Sizes are the video's pixels at the default Full Retina setting (a 640 × 360 point area records 1280 × 720).

## Rendering

`desktop.css` and `desktop.js` draw the shared desktop; `overlay.js` places Snip's overlay; each
numbered HTML file is one step. To render them again:

```sh
npm install playwright && npx playwright install chromium   # anywhere, once
NODE_PATH=/path/to/node_modules node docs/mockups/render.cjs
```

On a Mac the pages use SF Pro. Elsewhere set `FONT_DIR` to a folder holding Inter,
JetBrains Mono and Noto Sans Symbols 2, which stand in for it.
