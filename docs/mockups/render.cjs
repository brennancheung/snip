// Renders each mockup page to a PNG beside it, at device scale 2.
//
//   node docs/mockups/render.cjs            (needs the playwright package and its Chromium)
//
// A page sets its own viewport with <meta name="mockup-size" content="W×H">; the default is the
// 1440 × 900 desktop. <meta name="mockup-closeup" content="x,y,w,h"> also writes NN-name-closeup.png,
// that rectangle (in points) cropped from the same frame, for viewers that draw images small.
// FONT_DIR, if set, points at Inter, JetBrains Mono and Noto Sans Symbols 2, stand-ins for
// SF Pro and SF Mono on machines that don't have them (Linux containers).

const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');

const dir = __dirname;
const pages = fs.readdirSync(dir).filter((f) => /^\d\d-.*\.html$/.test(f)).sort();

function fontFaces(fontDir) {
  if (!fontDir) return '';
  const find = (name) => {
    const hit = require('child_process').execSync(`find ${JSON.stringify(fontDir)} -name ${JSON.stringify(name)}`).toString().split('\n')[0];
    return hit ? 'file://' + hit : null;
  };
  const faces = [
    ['Inter', 'Inter-Regular.otf', 400], ['Inter', 'Inter-Medium.otf', 500],
    ['Inter', 'Inter-SemiBold.otf', 600], ['Inter', 'Inter-Bold.otf', 700],
    ['JetBrains Mono', 'JetBrainsMono-Regular.ttf', 400], ['JetBrains Mono', 'JetBrainsMono-Medium.ttf', 500],
    ['Noto Sans Symbols 2', 'NotoSansSymbols2-Regular.ttf', 400], ['Noto Sans Symbols', 'NotoSansSymbols-Regular.ttf', 400],
  ];
  return faces.map(([family, file, weight]) => {
    const url = find(file);
    return url ? `@font-face{font-family:"${family}";src:url("${url}");font-weight:${weight === 400 ? '100 449' : weight === 500 ? '450 549' : weight === 600 ? '550 649' : '650 900'};}` : '';
  }).join('\n');
}

(async () => {
  const css = fontFaces(process.env.FONT_DIR);
  const browser = await chromium.launch();
  for (const file of pages) {
    const html = fs.readFileSync(path.join(dir, file), 'utf8');
    const m = html.match(/<meta name="mockup-size" content="(\d+)×(\d+)">/);
    const [width, height] = m ? [+m[1], +m[2]] : [1440, 900];
    const page = await browser.newPage({ viewport: { width, height }, deviceScaleFactor: 2 });
    await page.goto('file://' + path.join(dir, file));
    if (css) await page.addStyleTag({ content: css });
    await page.evaluate(() => document.fonts.ready);
    await page.waitForTimeout(150);
    const out = path.join(dir, file.replace(/\.html$/, '.png'));
    await page.screenshot({ path: out });
    console.log(path.relative(process.cwd(), out));
    const c = html.match(/<meta name="mockup-closeup" content="(\d+),(\d+),(\d+),(\d+)">/);
    if (c) {
      const [x, y, w, h] = c.slice(1).map(Number);
      const closeup = out.replace(/\.png$/, '-closeup.png');
      await page.screenshot({ path: closeup, clip: { x, y, width: w, height: h } });
      console.log(path.relative(process.cwd(), closeup));
    }
    await page.close();
  }
  await browser.close();
})().catch((e) => { console.error(e); process.exit(1); });
