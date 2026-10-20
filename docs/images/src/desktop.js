// Draws the staged desktop (wallpaper, menu bar, three windows, Dock) into <div id="desktop">.
// Each page adds Snip's UI on top. Options come from <body data-*>:
//   data-snip="idle | recording"  how Snip's menu bar item looks
//   data-hide="safari editor terminal"  leaves those windows out

// Geometry the pages share, in points on the 1440 × 900 screen, top-left origin.
window.GEO = {
  // 840 × 500 points: the "Safari · 1680 × 1000" label in ui/overlay-hover@200.png.
  safari: { x: 380, y: 92, w: 840, h: 500 },
  // 560 × 300 points: the "1120 × 600" box in ui/overlay-selected@200.png.
  // The board, its sidebar sized so the columns fit with 10 points to spare on each side.
  area: { x: 630, y: 156, w: 560, h: 300 },
  menuBar: 28,
  dock: 82,
};

const ICON = {
  apple: '<svg viewBox="0 0 24 24"><path d="M12.15 6.9c-.95 0-2.42-1.08-3.96-1.04-2.04.03-3.91 1.18-4.96 3.01-2.12 3.68-.55 9.1 1.52 12.09 1.01 1.45 2.2 3.09 3.79 3.04 1.52-.07 2.09-.99 3.93-.99 1.83 0 2.35.99 3.96.95 1.64-.03 2.68-1.48 3.68-2.95 1.15-1.69 1.63-3.32 1.66-3.41-.04-.02-3.18-1.22-3.22-4.86-.03-3.04 2.48-4.49 2.6-4.56-1.43-2.09-3.62-2.32-4.39-2.38-2-.16-3.68 1.09-4.61 1.09zM15.53 3.83c.84-1.01 1.4-2.43 1.25-3.83-1.21.05-2.66.8-3.53 1.82-.78.9-1.46 2.34-1.27 3.71 1.34.1 2.71-.69 3.56-1.7"/></svg>',
  // Snip's status item: the SF Symbols record.circle, and stop.fill in red while recording.
  record: '<svg width="16" height="16" viewBox="0 0 16 16"><circle cx="8" cy="8" r="7" fill="none" stroke="#fff" stroke-width="1.3"/><circle cx="8" cy="8" r="3.9" fill="#fff"/></svg>',
  stop: '<svg width="14" height="14" viewBox="0 0 14 14"><rect x="1" y="1" width="12" height="12" rx="2.6" fill="#ff453a"/></svg>',
  battery: '<svg width="27" height="13" viewBox="0 0 27 13"><rect x="0.75" y="0.75" width="22.5" height="11.5" rx="3.6" fill="none" stroke="#fff" stroke-opacity=".55" stroke-width="1.2"/><rect x="2.6" y="2.6" width="15" height="7.8" rx="2" fill="#fff"/><path d="M24.8 4.4v4.2c.9-.3 1.4-1.1 1.4-2.1s-.5-1.8-1.4-2.1z" fill="#fff" fill-opacity=".55"/></svg>',
  wifi: '<svg width="17" height="13" viewBox="0 0 17 13" fill="#fff"><path d="M8.5 2.3c2.5 0 4.8 1 6.5 2.6.2.2.5.2.7 0l.9-.9c.2-.2.2-.5 0-.7C14.5 1.3 11.6 0 8.5 0S2.5 1.3.4 3.3c-.2.2-.2.5 0 .7l.9.9c.2.2.5.2.7 0 1.7-1.6 4-2.6 6.5-2.6z"/><path d="M8.5 6c1.5 0 2.8.5 3.8 1.4.2.2.5.2.7 0l.9-.9c.2-.2.2-.5 0-.7-1.5-1.3-3.4-2.1-5.4-2.1s-3.9.8-5.4 2.1c-.2.2-.2.5 0 .7l.9.9c.2.2.5.2.7 0 1-.9 2.3-1.4 3.8-1.4z"/><path d="M10.6 9.4c.2-.2.2-.5 0-.7-.6-.5-1.3-.8-2.1-.8s-1.5.3-2.1.8c-.2.2-.2.5 0 .7l1.7 1.7c.2.2.5.2.7 0z"/></svg>',
  search: '<svg width="15" height="15" viewBox="0 0 15 15" fill="none" stroke="#fff" stroke-width="1.7" stroke-linecap="round"><circle cx="6.2" cy="6.2" r="4.6"/><path d="M9.7 9.7l3.8 3.8"/></svg>',
  control: '<svg width="17" height="15" viewBox="0 0 17 15" fill="none" stroke="#fff" stroke-width="1.3"><rect x="1" y="1" width="15" height="5.4" rx="2.7"/><circle cx="12.2" cy="3.7" r="1.6" fill="#fff" stroke="none"/><rect x="1" y="8.6" width="15" height="5.4" rx="2.7"/><circle cx="4.8" cy="11.3" r="1.6" fill="#fff" stroke="none"/></svg>',
  chevL: '<svg width="9" height="15" viewBox="0 0 9 15" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M7.5 1.5l-6 6 6 6"/></svg>',
  chevR: '<svg width="9" height="15" viewBox="0 0 9 15" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" opacity=".45"><path d="M1.5 1.5l6 6-6 6"/></svg>',
  sidebar: '<svg width="19" height="15" viewBox="0 0 19 15" fill="none" stroke="currentColor" stroke-width="1.4"><rect x="1" y="1" width="17" height="13" rx="3"/><path d="M7 1v13"/></svg>',
  share: '<svg width="14" height="17" viewBox="0 0 14 17" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"><path d="M7 1v10M3.5 4.5L7 1l3.5 3.5M4.5 7.5H2.8c-.7 0-1.3.6-1.3 1.3v5.9c0 .7.6 1.3 1.3 1.3h8.4c.7 0 1.3-.6 1.3-1.3V8.8c0-.7-.6-1.3-1.3-1.3H9.5"/></svg>',
  plus: '<svg width="14" height="14" viewBox="0 0 14 14" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round"><path d="M7 1v12M1 7h12"/></svg>',
  tabs: '<svg width="17" height="15" viewBox="0 0 17 15" fill="none" stroke="currentColor" stroke-width="1.4"><rect x="1" y="4" width="11" height="10" rx="2.4"/><path d="M5 1.3h8.2c1.3 0 2.4 1.1 2.4 2.4V10"/></svg>',
  lock: '<svg width="10" height="12" viewBox="0 0 10 12"><rect x="0.5" y="5" width="9" height="6.5" rx="1.6" fill="currentColor"/><path d="M2.6 5V3.6a2.4 2.4 0 014.8 0V5" fill="none" stroke="currentColor" stroke-width="1.3"/></svg>',
};

// Dock icons: simple squircles in the Tahoe style.
const sq = (id, a, b, inner) =>
  `<svg viewBox="0 0 52 52"><defs><linearGradient id="${id}" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="${a}"/><stop offset="1" stop-color="${b}"/></linearGradient></defs><rect x="1" y="1" width="50" height="50" rx="12" fill="url(#${id})"/><rect x="1.25" y="1.25" width="49.5" height="49.5" rx="11.8" fill="none" stroke="#fff" stroke-opacity=".35" stroke-width=".5"/>${inner}</svg>`;
const DOCK = [
  ['finder', true, sq('gf', '#56c2ff', '#1572e8', '<path d="M27 1h12a12 12 0 0112 12v26a12 12 0 01-12 12H25c2-9 1-16-1-22h5c-1-6-1-17-2-28z" fill="#e8f3ff"/><path d="M17 16v5M35 16v5" stroke="#10243f" stroke-width="2.6" stroke-linecap="round"/><path d="M14 33c7 6 17 6 24 0" fill="none" stroke="#10243f" stroke-width="2.2" stroke-linecap="round"/>')],
  ['safari', true, sq('gs', '#ffffff', '#e2e6ee', '<circle cx="26" cy="26" r="19" fill="#1a8cff"/><circle cx="26" cy="26" r="19" fill="none" stroke="#0a63d6" stroke-width="1"/><path d="M33.5 18.5L28 28l-4-4z" fill="#ff3b30"/><path d="M18.5 33.5L24 24l4 4z" fill="#fff"/>')],
  ['messages', false, sq('gm', '#6cf28b', '#16c13c', '<path d="M26 13c-9.4 0-17 6-17 13.5 0 4.3 2.5 8.1 6.4 10.6-.3 2.2-1.4 4.2-3 5.7 3.3-.2 6.1-1.5 8.1-3.3 1.7.4 3.6.6 5.5.6 9.4 0 17-6 17-13.6S35.4 13 26 13z" fill="#fff"/>')],
  ['mail', false, sq('gma', '#5ad0ff', '#1170f0', '<rect x="10" y="16" width="32" height="21" rx="3.5" fill="#fff"/><path d="M11 18l15 11 15-11" fill="none" stroke="#1d7ff0" stroke-width="1.8"/>')],
  ['notes', false, sq('gn', '#ffffff', '#f1f1f1', '<rect x="1" y="1" width="50" height="13" rx="12" fill="#fecf3e"/><rect x="1" y="9" width="50" height="5" fill="#fecf3e"/><path d="M10 24h32M10 31h32M10 38h22" stroke="#cfcfcf" stroke-width="1.4"/>')],
  ['code', true, sq('gc', '#3aa6ff', '#0b5fcf', '<path d="M20 17l-9 9 9 9M32 17l9 9-9 9" fill="none" stroke="#fff" stroke-width="3.2" stroke-linecap="round" stroke-linejoin="round"/>')],
  ['terminal', true, sq('gt', '#3a3a3e', '#141416', '<path d="M12 18l7 6-7 6" fill="none" stroke="#f2f2f2" stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round"/><path d="M23 31h11" stroke="#f2f2f2" stroke-width="2.6" stroke-linecap="round"/>')],
  ['settings', false, sq('gse', '#c9c9ce', '#8e8e94', '<circle cx="26" cy="26" r="13" fill="none" stroke="#4d4d52" stroke-width="5" stroke-dasharray="3.4 3.4"/><circle cx="26" cy="26" r="9.5" fill="#e8e8ec" stroke="#5e5e64" stroke-width="1.5"/><circle cx="26" cy="26" r="3.5" fill="#5e5e64"/>')],
  ['sep'],
  ['downloads', false, sq('gd', '#7cc4ff', '#2f86f2', '<path d="M26 14v18M19 25l7 7 7-7" fill="none" stroke="#fff" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"/><path d="M15 37h22" stroke="#fff" stroke-width="3" stroke-linecap="round"/>')],
  ['trash', false, '<svg viewBox="0 0 52 52"><path d="M12 12h28l-3 34c-.1 1.4-1.3 2.5-2.7 2.5H17.7c-1.4 0-2.6-1.1-2.7-2.5z" fill="rgba(255,255,255,.55)" stroke="rgba(255,255,255,.85)" stroke-width="1"/><ellipse cx="26" cy="12" rx="15" ry="3" fill="rgba(255,255,255,.75)"/><path d="M21 18l1 26M26 18v26M31 18l-1 26" stroke="rgba(120,130,150,.5)" stroke-width="1"/></svg>'],
];

// An excerpt of Sources/SnipCore/FFmpegEncoder.swift.
const SWIFT = `/// Re-encodes the intermediate recording with x264 at the chosen CRF, which makes screen
/// recordings several times smaller than the hardware encode.
public struct FFmpegEncoder: RecordingEncoder {
    public let ffmpegURL: URL?

    public static func arguments(
        intermediate: URL,
        output: URL,
        settings: RecordingSettings,
        audioStreams: Int = 0
    ) -> [String] {
        ["-hide_banner", "-y", "-i", intermediate.path]
        + [
            "-c:v", "libx264",
            "-crf", String(settings.crf),
            "-preset", settings.preset,
            "-pix_fmt", "yuv420p",
            // x264 with yuv420p needs even dimensions.
            "-vf", "scale=trunc(iw/2)*2:trunc(ih/2)*2",
            "-fps_mode", "cfr",
            "-r", String(settings.fps),
            "-movflags", "+faststart",
        ]
        + audioArguments(streams: audioStreams)
        + ["-progress", "pipe:1", "-nostats", output.path]
    }
}`;

const KEYWORDS = new Set('import final class struct public static private let var func guard case else return in self Task await try weak set'.split(' '));

function highlight(line) {
  const esc = (s) => s.replace(/&/g, '&amp;').replace(/</g, '&lt;');
  const comment = line.indexOf('//');
  const code = comment >= 0 ? line.slice(0, comment) : line;
  const html = esc(code).replace(/"[^"]*"|@?[A-Za-z_][A-Za-z0-9_]*|\d+/g, (w, i, s) => {
    if (w.startsWith('"')) return `<span class="s">${w}</span>`;
    if (/^\d/.test(w)) return `<span class="n">${w}</span>`;
    if (w.startsWith('@') || KEYWORDS.has(w)) return `<span class="k">${w}</span>`;
    if (/^[A-Z]/.test(w)) return `<span class="ty">${w}</span>`;
    if (s[i + w.length] === '(' ) return `<span class="f">${w}</span>`;
    return w;
  });
  return comment >= 0 ? html + `<span class="c">${esc(line.slice(comment))}</span>` : html;
}

function editor() {
  const lines = SWIFT.split('\n').map((l, i) => `<span class="ln">${i + 1}</span>${highlight(l)}`).join('\n');
  return `
  <div class="win dark inactive editor" style="left:36px;top:52px;width:900px;height:600px">
    <div class="titlebar"><div class="lights"><i></i><i></i><i></i></div>
      <div class="tabs"><div class="tab on">FFmpegEncoder.swift</div><div class="tab">RecordingSettings.swift</div><div class="tab">AppController.swift</div></div>
    </div>
    <div class="body">
      <div class="tree">
        <div class="h">SNIP</div>
        <div class="d">▾ Sources</div>
        <div class="d" style="padding-left:20px">▸ Snip</div>
        <div class="d" style="padding-left:20px">▸ SnipCapture</div>
        <div class="d" style="padding-left:20px">▾ SnipCore</div>
        <div style="padding-left:36px">CaptureTarget.swift</div>
        <div class="cur-file" style="padding-left:36px">FFmpegEncoder.swift</div>
        <div style="padding-left:36px">OutputNaming.swift</div>
        <div style="padding-left:36px">RecentRecordings.swift</div>
        <div style="padding-left:36px">RecordingSettings.swift</div>
        <div style="padding-left:36px">SettingsStore.swift</div>
        <div class="d" style="padding-left:20px">▸ SnipUI</div>
        <div class="d" style="padding-left:20px">▸ snip-cli</div>
        <div class="d" style="padding-left:20px">▸ snip-ui-preview</div>
        <div class="d">▸ Tests</div>
        <div class="d">▸ docs</div>
        <div>Package.swift</div>
        <div>README.md</div>
      </div>
      <div class="code">${lines}</div>
    </div>
  </div>`;
}

function terminal() {
  return `
  <div class="win dark inactive terminal" style="left:832px;top:614px;width:568px;height:206px">
    <div class="titlebar"><div class="lights"><i></i><i></i><i></i></div><div class="title">snip — zsh — 80×24</div></div>
<pre><span class="b">~/code/snip</span> <span class="g">main</span> <span class="p">❯</span> swift build
Build complete! (6.12s)
<span class="b">~/code/snip</span> <span class="g">main</span> <span class="p">❯</span> bin/build-app
Build complete! (24.87s)
Signing with "Snip Local Signing"
/Users/me/code/snip/build/Snip.app
<span class="b">~/code/snip</span> <span class="g">main</span> <span class="p">❯</span> open build/Snip.app
<span class="b">~/code/snip</span> <span class="g">main</span> <span class="p">❯</span> <span class="cur">_</span></pre>
  </div>`;
}

function card(id, title, tag, tagColor, tagBg, avatar, extra = '') {
  return `<div class="card ${extra}"><div class="id">${id}</div><div class="t">${title}</div>
    <div class="meta"><span class="tag" style="color:${tagColor};background:${tagBg}">${tag}</span><i style="background:${avatar}"></i></div></div>`;
}

function safari() {
  const g = GEO.safari;
  const A = 'linear-gradient(135deg,#ffb86b,#ff6b8b)', B = 'linear-gradient(135deg,#7cd7ff,#4b7bff)', C = 'linear-gradient(135deg,#9df0a8,#2fbf71)', D = 'linear-gradient(135deg,#d7b4ff,#8b5cf6)';
  const bug = ['#c2410c', '#ffedd5'], feat = ['#4338ca', '#e0e7ff'], design = ['#be185d', '#fce7f3'], infra = ['#047857', '#d1fae5'];
  return `
  <div class="win safari" style="left:${g.x}px;top:${g.y}px;width:${g.w}px;height:${g.h}px">
    <div class="toolbar">
      <div class="lights"><i></i><i></i><i></i></div>
      <div class="tb" style="margin-left:10px">${ICON.sidebar}${ICON.chevL}${ICON.chevR}</div>
      <div class="address">${ICON.lock}<span>app.fieldnote.io</span></div>
      <div class="tb">${ICON.share}${ICON.plus}${ICON.tabs}</div>
    </div>
    <div class="page">
      <div class="fn-nav">
        <div class="fn-brand"><b></b>Fieldnote</div>
        <div class="link"><i></i>Inbox</div>
        <div class="link"><i></i>My issues</div>
        <div class="section">Projects</div>
        <div class="link on"><i class="dot" style="background:#5b5bf0"></i>Q4 Launch</div>
        <div class="link"><i class="dot" style="background:#2fbf71"></i>Onboarding</div>
        <div class="link"><i class="dot" style="background:#ff9f0a"></i>Billing v2</div>
        <div class="link"><i class="dot" style="background:#ff375f"></i>Mobile</div>
        <div class="section">Views</div>
        <div class="link"><i></i>Roadmap</div>
        <div class="link"><i></i>Cycles</div>
      </div>
      <div class="fn-main">
        <div class="fn-head"><h1>Q4 Launch<span>Board</span></h1>
          <div class="actions"><div class="avatars"><i style="background:${A}"></i><i style="background:${B}"></i><i style="background:${C}"></i></div><div class="fn-btn">New issue</div></div>
        </div>
        <div class="cols">
          <div class="col"><h2><i style="border:2px solid #a0a0b0"></i>Todo <em>4</em></h2>
            ${card('FN-218', 'Empty state for the new search page', 'Design', ...design, A)}
            ${card('FN-224', 'Retry failed webhook deliveries', 'Infra', ...infra, B)}
            ${card('FN-231', 'Keyboard shortcut for quick add', 'Feature', ...feat, C)}
            ${card('FN-236', 'Avatar upload crops the wrong way', 'Bug', ...bug, D)}
          </div>
          <div class="col"><h2><i style="background:#ffb340"></i>In progress <em>3</em></h2>
            ${card('FN-201', 'Drag cards between columns', 'Feature', ...feat, B, 'lift')}
            ${card('FN-209', 'Dates show in UTC on the timeline', 'Bug', ...bug, A)}
            ${card('FN-213', 'Faster board load for large projects', 'Infra', ...infra, D)}
          </div>
          <div class="col"><h2><i style="background:#2fbf71"></i>Done <em>12</em></h2>
            ${card('FN-188', 'Invite teammates by link', 'Feature', ...feat, C)}
            ${card('FN-192', 'Dark mode for the editor', 'Design', ...design, A)}
            ${card('FN-197', 'Export a project to CSV', 'Feature', ...feat, B)}
          </div>
        </div>
      </div>
    </div>
  </div>`;
}

function menubar(snip) {
  const snipItem = `<div class="item" id="snip-item">${snip === 'recording' ? ICON.stop : ICON.record}</div>`;
  return `
  <div class="menubar">
    <div class="left">
      <div class="item apple">${ICON.apple}</div>
      <div class="item app">Safari</div>
      ${['File', 'Edit', 'View', 'History', 'Bookmarks', 'Window', 'Help'].map((m) => `<div class="item">${m}</div>`).join('')}
    </div>
    <div class="right">
      ${snipItem}
      <div class="item">${ICON.battery}</div>
      <div class="item">${ICON.wifi}</div>
      <div class="item">${ICON.search}</div>
      <div class="item">${ICON.control}</div>
      <div class="item clock num">Mon Oct 19&nbsp;&nbsp;2:03 PM</div>
    </div>
  </div>`;
}

function dock() {
  return `<div class="dock">${DOCK.map(([name, running, svg]) =>
    name === 'sep' ? '<div class="sep"></div>' : `<div class="ic ${running ? 'run' : ''}">${svg}</div>`).join('')}</div>`;
}

(function draw() {
  const d = document.body.dataset;
  const hide = (d.hide || '').split(' ');
  const windows = { editor, terminal, safari };
  document.getElementById('desktop').innerHTML = '<div class="wallpaper"></div>'
    + Object.keys(windows).filter((w) => !hide.includes(w)).map((w) => windows[w]()).join('')
    + dock() + menubar(d.snip || 'idle');
})();
