// Renders each page here to docs/images/<page>.webp: 1440 × 900 points at device scale 2, or the
// rect in <meta name="clip" content="x,y,w,h"> (points). Needs playwright and its Chromium, and
// sharp for the WebP (a third of the size of a PNG at no visible cost):
//
//   npm install playwright sharp && npx playwright install chromium
//   NODE_PATH=/path/to/node_modules node docs/images/src/render.cjs [page ...]
//
// On a Mac the desktop uses SF Pro and SF Mono. Elsewhere install Inter, JetBrains Mono and
// Noto Sans Symbols 2 as system fonts (in ~/.fonts on Linux); the CSS falls back to them.

const { chromium } = require('playwright');
const sharp = require('sharp');
const fs = require('fs');
const http = require('http');
const path = require('path');

const dir = __dirname;
const outDir = path.join(dir, '..');
const only = process.argv.slice(2);
const pages = fs.readdirSync(dir).filter((f) => f.endsWith('.html')).sort()
  .filter((f) => only.length === 0 || only.includes(f.replace(/\.html$/, '')));

// Served over http rather than file:// so the pages can read the renders' pixels.
function serve() {
  const types = { '.html': 'text/html', '.css': 'text/css', '.js': 'text/javascript', '.png': 'image/png' };
  const server = http.createServer((req, res) => {
    const url = new URL(req.url, 'http://localhost');
    const file = path.join(dir, decodeURIComponent(url.pathname));
    if (!file.startsWith(dir)) { res.writeHead(403).end(); return; }
    fs.readFile(file, (err, body) => {
      if (err) { res.writeHead(404).end(); return; }
      res.writeHead(200, { 'Content-Type': types[path.extname(file)] || 'application/octet-stream' }).end(body);
    });
  });
  return new Promise((resolve) => server.listen(0, '127.0.0.1', () => resolve(server)));
}

(async () => {
  const server = await serve();
  const base = `http://127.0.0.1:${server.address().port}/`;
  const browser = await chromium.launch();
  for (const file of pages) {
    const html = fs.readFileSync(path.join(dir, file), 'utf8');
    const page = await browser.newPage({ viewport: { width: 1440, height: 900 }, deviceScaleFactor: 2 });
    page.on('pageerror', (e) => { console.error(file, e); process.exitCode = 1; });
    page.on('requestfailed', (r) => console.error(file, 'failed:', r.url(), r.failure()?.errorText));
    await page.goto(base + file);
    await page.evaluate(() => Promise.all([document.fonts.ready, window.ready]));
    await page.waitForTimeout(150);
    const c = html.match(/<meta name="clip" content="(\d+),(\d+),(\d+),(\d+)">/);
    const clip = c ? { x: +c[1], y: +c[2], width: +c[3], height: +c[4] } : undefined;
    const shot = await page.screenshot({ clip });
    const out = path.join(outDir, file.replace(/\.html$/, '.webp'));
    await sharp(shot).webp({ quality: 90, effort: 6 }).toFile(out);
    console.log(path.relative(process.cwd(), out), Math.round(fs.statSync(out).size / 1024) + ' KB');
    await page.close();
  }
  await browser.close();
  server.close();
})().catch((e) => { console.error(e); process.exit(1); });
