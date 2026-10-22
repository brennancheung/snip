// Puts Snip's UI on the staged desktop. The pieces come from snip-ui-preview's renders in ui/
// (Snip's own views drawn at 200% interface size, one pixel per point, so they are 2x pixels of
// the default size); the overlay's dimming, outlines and handles are drawn here from the same
// numbers Snip uses (OverlayView, RecordingBorder).

const px = (v) => v + 'px';

window.loadUI = (name) => new Promise((resolve, reject) => {
  const img = new Image();
  img.onload = () => resolve(img);
  img.onerror = () => reject(new Error('missing ui/' + name + '@200.png'));
  img.src = 'ui/' + name + '@200.png';
});

function pixels(img) {
  const c = document.createElement('canvas');
  c.width = img.naturalWidth;
  c.height = img.naturalHeight;
  const g = c.getContext('2d');
  g.drawImage(img, 0, 0);
  return g.getImageData(0, 0, c.width, c.height);
}

function toImage(data) {
  const c = document.createElement('canvas');
  c.width = data.width;
  c.height = data.height;
  c.getContext('2d').putImageData(data, 0, 0);
  const img = new Image();
  img.src = c.toDataURL('image/png');
  // Two render pixels per CSS point.
  img.style.width = px(data.width / 2);
  img.style.height = px(data.height / 2);
  return img;
}

function crop(data, r) {
  const out = new ImageData(r.w, r.h);
  for (let y = 0; y < r.h; y++) {
    const from = ((r.y + y) * data.width + r.x) * 4;
    out.data.set(data.data.subarray(from, from + r.w * 4), y * r.w * 4);
  }
  return out;
}

// The smallest rect in `area` (render pixels) whose pixels differ from the grey `bg`.
function bounds(data, area, bg) {
  let x0 = Infinity, y0 = Infinity, x1 = -1, y1 = -1;
  for (let y = area.y; y < area.y + area.h; y++) {
    for (let x = area.x; x < area.x + area.w; x++) {
      const i = (y * data.width + x) * 4;
      const d = Math.max(Math.abs(data.data[i] - bg), Math.abs(data.data[i + 1] - bg), Math.abs(data.data[i + 2] - bg));
      if (d > 2) { x0 = Math.min(x0, x); y0 = Math.min(y0, y); x1 = Math.max(x1, x); y1 = Math.max(y1, y); }
    }
  }
  return { x: x0, y: y0, w: x1 - x0 + 1, h: y1 - y0 + 1 };
}

// An overlay label (white text on black at 75% over the grey `bg`) as its text alone, white with
// alpha, so it can sit on a .snip-label over any background. `inset` keeps the rounded edge out.
function labelText(data, r, bg, inset) {
  const base = 0.25 * bg;
  const out = new ImageData(r.w, r.h);
  for (let y = 0; y < r.h; y++) {
    for (let x = 0; x < r.w; x++) {
      const i = ((r.y + y) * data.width + r.x + x) * 4, o = (y * r.w + x) * 4;
      const inside = x >= inset && y >= inset && x < r.w - inset && y < r.h - inset;
      const t = inside ? Math.min(1, Math.max(0, (data.data[i] - base) / (255 - base))) : 0;
      out.data.set([255, 255, 255, Math.round(t * 255)], o);
    }
  }
  return out;
}

// GIMP's colour to alpha: the least opaque colour that gives each pixel over the background, so a
// view rendered on grey can sit on the HUD stand-in. `background(x, y)` (render pixels) is the RGB
// it was drawn on, or null to make the pixel clear.
function colourToAlpha(data, background) {
  const out = new ImageData(new Uint8ClampedArray(data.data), data.width, data.height);
  const d = out.data;
  for (let y = 0; y < data.height; y++) {
    for (let x = 0; x < data.width; x++) {
      const i = (y * data.width + x) * 4;
      const bg = background(x, y);
      if (!bg) { d[i + 3] = 0; continue; }
      let a = 0;
      for (let c = 0; c < 3; c++) {
        const v = d[i + c], b = bg[c];
        a = Math.max(a, v > b ? (v - b) / (255 - b) : v < b ? (b - v) / b : 0);
      }
      for (let c = 0; c < 3; c++) d[i + c] = a > 0 ? Math.round((d[i + c] - bg[c]) / a + bg[c]) : 0;
      d[i + 3] = Math.round(a * 255);
    }
  }
  return out;
}

const GREY = [51, 51, 51];

function add(el, style, parent = document.querySelector('.layer')) {
  Object.assign(el.style, style);
  parent.appendChild(el);
  return el;
}

function div(cls) {
  const el = document.createElement('div');
  el.className = cls;
  return el;
}

// Black at 35% everywhere but `r`.
window.dimAround = (r) => {
  const W = 1440, H = 900;
  for (const [x, y, w, h] of [[0, 0, W, r.y], [0, r.y + r.h, W, H - r.y - r.h], [0, r.y, r.x, r.h], [r.x + r.w, r.y, W - r.x - r.w, r.h]]) {
    add(div('dim'), { left: px(x), top: px(y), width: px(w), height: px(h) });
  }
};

window.outline = (r, style) => add(div('outline ' + style), { left: px(r.x), top: px(r.y), width: px(r.w), height: px(r.h) });

window.handles = (r) => {
  for (const [fx, fy] of [[0, 0], [0.5, 0], [1, 0], [1, 0.5], [1, 1], [0.5, 1], [0, 1], [0, 0.5]]) {
    add(div('handle'), { left: px(r.x + fx * r.w), top: px(r.y + fy * r.h) });
  }
};

window.recordingBorder = (r) => add(div('rec-border'), { left: px(r.x), top: px(r.y), width: px(r.w), height: px(r.h) });

// The hint and a hovered window's label, from overlay-hover. Returns their sizes in points.
window.hoverPieces = async () => {
  const data = pixels(await loadUI('overlay-hover'));
  const hintBox = bounds(data, { x: 0, y: 40, w: data.width, h: 160 }, 91);
  const labelBox = bounds(data, { x: 404, y: 264, w: 600, h: 80 }, 140);
  const piece = (box, bg) => {
    const tag = div('snip-label');
    tag.style.width = px(box.w / 2);
    tag.style.height = px(box.h / 2);
    tag.appendChild(toImage(labelText(data, box, bg, 4)));
    return tag;
  };
  return { hint: piece(hintBox, 91), label: piece(labelBox, 140) };
};

// The Record/Cancel bar under a box, from overlay-selected: near-opaque, so cut out as it is.
window.selectionBar = async () => {
  const data = pixels(await loadUI('overlay-selected'));
  const box = bounds(data, { x: 0, y: 870, w: data.width, h: 100 }, 91);
  const bar = div('cut');
  Object.assign(bar.style, { width: px(box.w / 2), height: px(box.h / 2), borderRadius: '8px' });
  bar.appendChild(toImage(crop(data, box)));
  return bar;
};

// The recording pill: its content on the HUD stand-in, corners half its height.
window.pill = async () => {
  const data = pixels(await loadUI('pill'));
  const el = div('hud');
  Object.assign(el.style, { width: px(data.width / 2), height: px(data.height / 2), borderRadius: px(data.height / 4) });
  el.appendChild(toImage(colourToAlpha(data, () => GREY)));
  return el;
};

// The after-recording panel: its content on the HUD stand-in. Its video shows the sample clip's
// first frame; that is cleared, but for the close button over it, and `video` (an element showing
// the recording) goes underneath.
window.donePanel = async (video) => {
  const data = pixels(await loadUI('done-panel'));
  const v = data.data;
  const at = (x, y) => { const i = (y * data.width + x) * 4; return [v[i], v[i + 1], v[i + 2]]; };
  // The video is the frame's blue: rows and columns that are mostly blue, so a stray blue pixel
  // elsewhere (the file chip's icon) doesn't count.
  const rows = new Array(data.height).fill(0), cols = new Array(data.width).fill(0);
  for (let y = 0; y < data.height; y++) for (let x = 0; x < data.width; x++) {
    const [r, , b] = at(x, y);
    if (b - r > 20) { rows[y]++; cols[x]++; }
  }
  const first = (counts, min) => counts.findIndex((n) => n >= min);
  const last = (counts, min) => counts.length - 1 - [...counts].reverse().findIndex((n) => n >= min);
  const x0 = first(cols, data.height / 4), x1 = last(cols, data.height / 4);
  const y0 = first(rows, data.width / 4), y1 = last(rows, data.width / 4);
  const frameColour = at(x1 - 4, y1 - 4);
  // The video's corners are rounded, 6 points (12 render pixels).
  const inVideo = (x, y) => {
    if (x < x0 || x > x1 || y < y0 || y > y1) return false;
    const r = 12, cx = Math.min(Math.max(x, x0 + r), x1 - r), cy = Math.min(Math.max(y, y0 + r), y1 - r);
    return (x - cx) ** 2 + (y - cy) ** 2 <= r * r;
  };
  // The close button sits in the video's top-right corner.
  const closeButton = (x, y) => x > x1 - 64 && y < y0 + 64;
  const el = div('hud');
  Object.assign(el.style, { width: px(data.width / 2), height: px(data.height / 2), borderRadius: '12px' });
  const slot = { x: x0 / 2, y: y0 / 2, w: (x1 - x0 + 1) / 2, h: (y1 - y0 + 1) / 2 };
  const holder = div('cut');
  Object.assign(holder.style, { left: px(slot.x), top: px(slot.y), width: px(slot.w), height: px(slot.h), borderRadius: '6px', background: '#000' });
  video(holder, slot);
  el.appendChild(holder);
  const img = toImage(colourToAlpha(data, (x, y) => !inVideo(x, y) ? GREY : closeButton(x, y) ? frameColour : null));
  img.style.position = 'absolute';
  img.style.left = img.style.top = '0';
  el.appendChild(img);
  return el;
};

// The desktop itself, scaled so `area` covers `slot` (points), as a recording of it would show.
window.recordingOf = (area) => (holder, slot) => {
  const scale = Math.max(slot.w / area.w, slot.h / area.h);
  const frame = document.createElement('iframe');
  frame.src = location.pathname + '?frame';
  Object.assign(frame.style, {
    position: 'absolute', border: '0', width: '1440px', height: '900px', transformOrigin: '0 0',
    transform: `translate(${slot.w / 2 - (area.x + area.w / 2) * scale}px, ${slot.h / 2 - (area.y + area.h / 2) * scale}px) scale(${scale})`,
  });
  holder.appendChild(frame);
  window.frameLoaded = new Promise((resolve) => { frame.onload = resolve; });
};

// The Settings window: Snip's content under a dark title bar.
window.settingsWindow = async () => {
  const img = await loadUI('settings');
  const win = div('sheet');
  win.innerHTML = '<div class="titlebar"><div class="lights"><i></i><i></i><i></i></div><div class="title">Snip Settings</div></div>';
  img.style.width = px(img.naturalWidth / 2);
  img.style.height = px(img.naturalHeight / 2);
  win.appendChild(img);
  win.style.width = px(img.naturalWidth / 2);
  return win;
};

window.place = (el, x, y) => add(el, { left: px(x), top: px(y) });

// Centred under `r` with Snip's 10 pt gap.
window.under = (el, r) => {
  const w = parseFloat(el.style.width);
  return add(el, { left: px(r.x + r.w / 2 - w / 2), top: px(r.y + r.h + 10) });
};

window.CROSSHAIR = '<svg width="23" height="23" viewBox="0 0 23 23"><path d="M11.5 0v23M0 11.5h23" stroke="#fff" stroke-width="3"/><path d="M11.5 .5v22M.5 11.5h22" stroke="#000" stroke-width="1"/></svg>';
window.ARROW = '<svg width="20" height="26" viewBox="0 0 20 26"><path d="M2 1.5v19.2l4.6-4.4 3.1 7.3 3.3-1.4-3.1-7.1h6.4z" fill="#000" stroke="#fff" stroke-width="1.4" stroke-linejoin="round"/></svg>';

window.cursor = (svg, x, y) => {
  const c = div('cursor');
  c.innerHTML = svg;
  Object.assign(c.style, { left: px(x), top: px(y) });
  document.body.appendChild(c);
};

// Each page calls this with its drawing; render.cjs waits for window.ready. A page loaded with
// ?frame is the bare desktop, for a recording of it shown inside another page.
window.compose = (draw) => {
  window.ready = (async () => {
    if (location.search === '?frame') return;
    await draw();
    await Promise.all([...document.images].map((i) => i.decode()));
    await window.frameLoaded;
  })();
};
