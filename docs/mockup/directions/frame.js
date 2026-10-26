// Shared by the mockups: draws the recording inside a box at a zoom depth aimed at a point.
// fit: the footage at 1x sits centered with padding; zoom: the view (W/z x H/z) is centered
// on the target and clamped to the footage box, the way the engine is meant to clamp.
const FOOT = { w: 1696, h: 1716 };
function frame(el, z, tx, ty) {
  const W = el.clientWidth, H = el.clientHeight, pad = 0.08 * Math.min(W, H);
  const s = Math.min((W - 2 * pad) / FOOT.w, (H - 2 * pad) / FOOT.h);
  const fw = FOOT.w * s, fh = FOOT.h * s, fx = (W - fw) / 2, fy = (H - fh) / 2;
  const vw = W / z, vh = H / z;
  const clamp = (c, v, lo, len) => v >= len ? lo + len / 2 : Math.min(Math.max(c, lo + v / 2), lo + len - v / 2);
  const cx = clamp(fx + tx * fw, vw, fx, fw), cy = clamp(fy + ty * fh, vh, fy, fh);
  const inner = document.createElement('div');
  inner.className = 'cam';
  inner.style.cssText = `position:absolute;left:0;top:0;width:${W}px;height:${H}px;transform-origin:0 0;transform:translate(${W / 2 - z * cx}px,${H / 2 - z * cy}px) scale(${z})`;
  const img = document.createElement('div');
  img.style.cssText = `position:absolute;left:${fx}px;top:${fy}px;width:${fw}px;height:${fh}px;border-radius:${Math.max(4, fw * 0.03)}px;background:url(${window.FOOTAGE}) center/cover;box-shadow:0 ${fw * .04}px ${fw * .1}px rgba(0,0,0,.28)`;
  inner.appendChild(img);
  el.appendChild(inner);
  return { fx, fy, fw, fh, cx, cy, vw, vh, W, H };
}
const theme = new URLSearchParams(location.search).get('theme') || 'light';
document.documentElement.dataset.theme = theme;
window.FOOTAGE = `../assets/footage-${theme}.png`;
document.querySelectorAll('.ft').forEach(e => e.style.backgroundImage = `url(${window.FOOTAGE})`);
