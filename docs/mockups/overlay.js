// Small helpers the step pages use to place Snip's overlay pieces.
window.place = (el, r, pad = 0) => Object.assign(el.style, {
  left: r.x - pad + 'px', top: r.y - pad + 'px', width: r.w + 2 * pad + 'px', height: r.h + 2 * pad + 'px',
});

window.CROSSHAIR = '<svg width="23" height="23" viewBox="0 0 23 23"><path d="M11.5 0v23M0 11.5h23" stroke="#fff" stroke-width="3"/><path d="M11.5 .5v22M.5 11.5h22" stroke="#000" stroke-width="1"/></svg>';
window.ARROW = '<svg width="20" height="26" viewBox="0 0 20 26"><path d="M2 1.5v19.2l4.6-4.4 3.1 7.3 3.3-1.4-3.1-7.1h6.4z" fill="#000" stroke="#fff" stroke-width="1.4" stroke-linejoin="round"/></svg>';

window.cursor = (svg, x, y) => {
  const c = document.createElement('div');
  c.className = 'cursor';
  c.innerHTML = svg;
  Object.assign(c.style, { left: x + 'px', top: y + 'px' });
  document.body.appendChild(c);
};

// Eight handles on a selection: corners and edge midpoints.
window.handles = (sel) => {
  for (const [x, y] of [[0, 0], [50, 0], [100, 0], [100, 50], [100, 100], [50, 100], [0, 100], [0, 50]]) {
    const h = document.createElement('i');
    h.className = 'h';
    Object.assign(h.style, { left: x + '%', top: y + '%' });
    sel.appendChild(h);
  }
};

// The dimmed screen with a clear hole over the selection (or the hovered window).
window.dim = (r, radius = 0) => {
  const ns = 'http://www.w3.org/2000/svg';
  const svg = document.createElementNS(ns, 'svg');
  svg.setAttribute('width', 1440);
  svg.setAttribute('height', 900);
  svg.style.cssText = 'position:absolute;left:0;top:0';
  const k = radius;
  const hole = `M${r.x + k},${r.y}h${r.w - 2 * k}a${k},${k} 0 0 1 ${k},${k}v${r.h - 2 * k}a${k},${k} 0 0 1 -${k},${k}h-${r.w - 2 * k}a${k},${k} 0 0 1 -${k},-${k}v-${r.h - 2 * k}a${k},${k} 0 0 1 ${k},-${k}z`;
  svg.innerHTML = `<path fill-rule="evenodd" fill="rgba(0,0,0,.45)" d="M0,0H1440V900H0z${hole}"/>`;
  document.querySelector('.layer').prepend(svg);
};
