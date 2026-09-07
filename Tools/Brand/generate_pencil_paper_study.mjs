// Speak It — pencil-on-paper logo study (deterministic, no dependencies).
//
// Run:  node Tools/Brand/generate_pencil_paper_study.mjs [--no-raster]
//
// Separate from generate_brand.swift on purpose: this writes review candidates
// into Design/Brand/Explorations/Pencil-Paper-Study and never touches the
// production masters. Every letter and bar is geometry in this file.
//
// How the pencil works. A stroke is not one outline: graphite is laid down as
// many fine fibres that cross and fray — dense in the middle, sparse at the
// edges, thinner where the tip lands and where it lifts, with short strays where
// the paper tooth caught the lead. Three soft filled cores give the mass that
// survives a 60 px icon; the fibres give the edge; an SVG turbulence mask then
// punches paper tooth through the graphite and a second, slow mask varies the
// pressure. Everything is seeded (xorshift64*, same as the Swift generator), so
// a re-run is bit-identical. Chrome, if installed, rasterises the review board
// and every candidate to PNG; nothing else on a stock Mac renders SVG filters.
import fs from "node:fs";
import path from "node:path";
import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, "../..");
const outDir = path.join(root, "Design/Brand/Explorations/Pencil-Paper-Study");
fs.mkdirSync(outDir, { recursive: true });

// ---------- seeded random + noise ----------
const MASK = (1n << 64n) - 1n;
class Rand {
  constructor(seed) { this.s = ((BigInt(seed) * 0x9E3779B97F4A7C15n) | 1n) & MASK; }
  next() { // uniform in [-1, 1]
    let s = this.s;
    s ^= s >> 12n; s ^= (s << 25n) & MASK; s ^= s >> 27n; this.s = s;
    const v = ((s * 0x2545F4914F6CDD1Dn) & MASK) >> 11n;
    return Number(v) / 2 ** 53 * 2 - 1;
  }
  unit() { return (this.next() + 1) / 2; }
  gauss() { const u = Math.max(this.unit(), 1e-9), v = this.unit(); return Math.sqrt(-2 * Math.log(u)) * Math.cos(2 * Math.PI * v); }
  int(n) { return Math.min(Math.floor(this.unit() * n), n - 1); }
}
class Noise1D {
  constructor(knots, rand) { this.k = Array.from({ length: Math.max(knots, 2) }, () => rand.next()); }
  at(u) {
    const x = Math.min(Math.max(u, 0), 1) * (this.k.length - 1);
    const i = Math.min(Math.floor(x), this.k.length - 2);
    const t = x - i, f = (1 - Math.cos(t * Math.PI)) / 2;
    return this.k[i] * (1 - f) + this.k[i + 1] * f;
  }
}
const smoothstep = (a, b, x) => { const t = Math.min(Math.max((x - a) / (b - a), 0), 1); return t * t * (3 - 2 * t); };
const lerp = (a, b, t) => a + (b - a) * t;

// ---------- geometry ----------
const P = (x, y) => ({ x, y });
function flattenPath(d, segs = 20) {
  // Absolute M/L/C/Q/Z only (that is all the study skeletons use).
  const tok = d.match(/[MLCQZ]|-?\d*\.?\d+(?:e-?\d+)?/gi);
  const polys = []; let cur = null; let i = 0; let cmd = null; let last = P(0, 0);
  const num = () => parseFloat(tok[i++]);
  while (i < tok.length) {
    if (/[MLCQZ]/i.test(tok[i])) { cmd = tok[i++].toUpperCase(); if (cmd === "Z") { cur = null; continue; } }
    if (cmd === "M") { cur = [P(num(), num())]; polys.push(cur); last = cur[0]; cmd = "L"; }
    else if (cmd === "L") { const q = P(num(), num()); cur.push(q); last = q; }
    else if (cmd === "C") {
      const c1 = P(num(), num()), c2 = P(num(), num()), e = P(num(), num()), s = last;
      for (let k = 1; k <= segs; k++) { const t = k / segs, m = 1 - t;
        cur.push(P(m*m*m*s.x + 3*m*m*t*c1.x + 3*m*t*t*c2.x + t*t*t*e.x, m*m*m*s.y + 3*m*m*t*c1.y + 3*m*t*t*c2.y + t*t*t*e.y)); }
      last = e;
    } else if (cmd === "Q") {
      const c = P(num(), num()), e = P(num(), num()), s = last;
      for (let k = 1; k <= segs; k++) { const t = k / segs, m = 1 - t;
        cur.push(P(m*m*s.x + 2*m*t*c.x + t*t*e.x, m*m*s.y + 2*m*t*c.y + t*t*e.y)); }
      last = e;
    }
  }
  return polys;
}
function arc(cx, cy, r, a0, a1, steps = 40) {
  return Array.from({ length: steps + 1 }, (_, i) => { const a = (a0 + (a1 - a0) * i / steps) * Math.PI / 180; return P(cx + r * Math.cos(a), cy + r * Math.sin(a)); });
}
function arcLength(poly) {
  const cum = [0];
  for (let i = 1; i < poly.length; i++) cum.push(cum[i - 1] + Math.hypot(poly[i].x - poly[i - 1].x, poly[i].y - poly[i - 1].y));
  return cum;
}
function pointAt(poly, cum, d) {
  let i = 1; while (i < cum.length - 1 && cum[i] < d) i++;
  const a = poly[i - 1], b = poly[i], seg = Math.max(cum[i] - cum[i - 1], 1e-9);
  const t = Math.min(Math.max((d - cum[i - 1]) / seg, 0), 1);
  return P(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t);
}
const tf = (v) => (Math.round(v * 100) / 100).toString();
const polyD = (pts) => "M" + pts.map((q) => `${tf(q.x)} ${tf(q.y)}`).join(" L");

// ---------- the pencil ----------
// Presets are graphite grades. `width` is the visible line width the hand is
// aiming for (the lead on its side for wide bars, its point for letters).
const GRADES = {
  HB:  { color: "#3A3A3C", tone: 0.88, fibers: 20, spread: 0.26, core: 0.56, grainK: 1.7, grainB: 1.42, fray: 1.0 },
  "2B": { color: "#28282A", tone: 0.96, fibers: 26, spread: 0.28, core: 0.68, grainK: 1.4, grainB: 1.36, fray: 1.0 },
  "6B": { color: "#171719", tone: 1.0, fibers: 32, spread: 0.30, core: 0.80, grainK: 1.1, grainB: 1.30, fray: 1.1 },
  carpenter: { color: "#28282A", tone: 0.96, fibers: 28, spread: 0.5, core: 0.74, grainK: 1.3, grainB: 1.34, fray: 0.6, flat: true },
  chalk: { color: "#EDEAE3", tone: 0.95, fibers: 28, spread: 0.30, core: 0.66, grainK: 1.5, grainB: 1.38, fray: 1.0 },
};

function pencilStroke(ideal, o) {
  // o: { width, seed, grade, drift, tremor, pressure, landing, lift, hook, taper, toneScale }
  const g = GRADES[o.grade ?? "2B"];
  const width = o.width;
  const drift = o.drift ?? 0.08, tremor = o.tremor ?? 0.02, pressure = o.pressure ?? 0.14;
  const landing = o.landing ?? 0.04, lift = o.lift ?? 0.22, hook = o.hook ?? 0.04, taper = o.taper ?? 1;
  const toneScale = o.toneScale ?? 1;
  const cum = arcLength(ideal), total = cum[cum.length - 1];
  const widths = Math.max(total / width, 0.5);
  const rand = new Rand(o.seed);
  const wander = new Noise1D(2 + Math.floor(widths * 0.6), rand);
  const shake = new Noise1D(3 + Math.floor(widths * 2.2), rand);
  const press = new Noise1D(2 + Math.floor(widths * 1.1), rand);
  const hookSign = rand.next() < 0 ? -1 : 1;
  const reach = smoothstep(0.3, 3.0, widths);
  const S = Math.min(Math.max(Math.round(widths * 9), 14), 110);
  // Hand centreline + normals.
  const centre = [], normals = [];
  for (let k = 0; k <= S; k++) {
    const u = k / S;
    const base = pointAt(ideal, cum, u * total);
    const ah = pointAt(ideal, cum, Math.min(u + 0.01, 1) * total), bh = pointAt(ideal, cum, Math.max(u - 0.01, 0) * total);
    let tx = ah.x - bh.x, ty = ah.y - bh.y; const tl = Math.max(Math.hypot(tx, ty), 1e-9); tx /= tl; ty /= tl;
    const nx = -ty, ny = tx;
    const side = drift * reach * width * wander.at(u) + tremor * reach * width * shake.at(u)
      + hook * reach * hookSign * width * Math.pow(smoothstep(0.85, 1, u), 2);
    centre.push(P(base.x + nx * side, base.y + ny * side));
  }
  for (let k = 0; k <= S; k++) {
    const a = centre[Math.max(k - 1, 0)], b = centre[Math.min(k + 1, S)];
    let tx = b.x - a.x, ty = b.y - a.y; const tl = Math.max(Math.hypot(tx, ty), 1e-9);
    normals.push(P(-ty / tl, tx / tl));
  }
  const pressAt = (u) => (1 + pressure * press.at(u)) * (1 + landing * (1 - smoothstep(0, 0.15, u))) * (1 - lift * smoothstep(0.72, 1, u));
  const pt = (k, off) => P(centre[k].x + normals[k].x * off, centre[k].y + normals[k].y * off);
  const parts = [];
  // Core: the dense middle of the graphite, a soft filled outline with round
  // (but slightly feathered) caps, plus a darker burnished centre.
  const capR = width / 2 * (g.flat ? 0.5 : 1);
  const coreOutline = (frac, feather) => {
    const left = [], right = [];
    for (let k = 0; k <= S; k++) {
      const u = k / S, pw = pressAt(u);
      const endFade = taper * feather * ((1 - smoothstep(0, 0.06, u)) * 0.25 + smoothstep(0.9, 1, u) * 0.35);
      const hw = width / 2 * frac * pw * (1 - endFade);
      left.push(pt(k, hw)); right.push(pt(k, -hw));
    }
    const endHw = Math.hypot(left[S].x - right[S].x, left[S].y - right[S].y) / 2, startHw = Math.hypot(left[0].x - right[0].x, left[0].y - right[0].y) / 2;
    const nE = normals[S], nS = normals[0];
    const aE = Math.atan2(nE.y, nE.x) * 180 / Math.PI, aS = Math.atan2(-nS.y, -nS.x) * 180 / Math.PI;
    const capE = g.flat ? [] : arc(centre[S].x, centre[S].y, endHw * capR / (width / 2), aE, aE - 180, 12).slice(1, -1);
    const capS = g.flat ? [] : arc(centre[0].x, centre[0].y, startHw * capR / (width / 2), aS, aS - 180, 12).slice(1, -1);
    return polyD(left.concat(capE, right.reverse(), capS)) + "Z";
  };
  parts.push(`<path d="${coreOutline(g.flat ? 0.94 : 0.9, 1)}" fill="${g.color}" opacity="${tf(g.tone * g.core * toneScale * 0.5)}"/>`);
  parts.push(`<path d="${coreOutline(g.flat ? 0.78 : 0.68, 1.3)}" fill="${g.color}" opacity="${tf(g.tone * g.core * toneScale * 0.5)}"/>`);
  parts.push(`<path d="${coreOutline(g.flat ? 0.6 : 0.4, 1.8)}" fill="${g.color}" opacity="${tf(g.tone * g.core * toneScale * 0.45)}"/>`);
  // Direction vectors at the ends so fibres can run into the round cap.
  const tEnd = P(centre[S].x - centre[S - 1].x, centre[S].y - centre[S - 1].y), tEl = Math.max(Math.hypot(tEnd.x, tEnd.y), 1e-9);
  const tStart = P(centre[1].x - centre[0].x, centre[1].y - centre[0].y), tSl = Math.max(Math.hypot(tStart.x, tStart.y), 1e-9);
  const unitEnd = P(tEnd.x / tEl, tEnd.y / tEl), unitStart = P(tStart.x / tSl, tStart.y / tSl);
  // Fibres.
  const nF = Math.round(g.fibers * (o.fiberScale ?? 1));
  for (let j = 0; j < nF; j++) {
    const lateral = g.flat ? (rand.unit() - 0.5) * width * 0.96 : Math.max(-0.48, Math.min(0.48, rand.gauss() * g.spread * 0.8)) * width;
    const wob = new Noise1D(3 + Math.floor(widths * 1.4), rand);
    const wobAmp = width * (g.flat ? 0.02 : 0.035) * g.fray;
    const fw = width * (0.045 + 0.11 * rand.unit()) * (g.flat ? 1.2 : 1);
    const edge = Math.min(Math.abs(lateral) / (0.5 * width), 1);
    const op = g.tone * toneScale * (0.14 + 0.34 * rand.unit()) * (1 - 0.7 * edge * edge);
    let s0 = 0.05 * rand.unit() * taper * (rand.unit() < 0.5 ? 1 : 0.2);
    let s1 = 1 - 0.10 * rand.unit() * taper;
    if (edge > 0.72) { s0 = rand.unit() * 0.6; s1 = Math.min(1, s0 + 0.12 + 0.35 * rand.unit()); } // strays where the tooth caught
    // How far this fibre may run into the round cap (a circle's chord), feathered.
    const reachCap = g.flat ? 0 : capR * Math.sqrt(Math.max(0, 1 - edge * edge)) * (0.55 + 0.4 * rand.unit());
    const dragPast = rand.unit() < 0.14 ? width * 0.12 : 0;
    const pts = [];
    if (s0 < 0.02) pts.push(P(centre[0].x - unitStart.x * reachCap * (0.9 - s0 * 20) + normals[0].x * lateral, centre[0].y - unitStart.y * reachCap * (0.9 - s0 * 20) + normals[0].y * lateral));
    for (let k = 0; k <= S; k++) {
      const u = k / S; if (u < s0 || u > s1) continue;
      const pw = pressAt(u);
      pts.push(pt(k, (lateral + wobAmp * wob.at(u)) * pw));
    }
    if (s1 > 0.97) { const e = reachCap * pressAt(1) + dragPast; pts.push(P(centre[S].x + unitEnd.x * e + normals[S].x * lateral * pressAt(1), centre[S].y + unitEnd.y * e + normals[S].y * lateral * pressAt(1))); }
    if (pts.length < 2) continue;
    parts.push(`<path d="${polyD(pts)}" fill="none" stroke="${g.color}" stroke-width="${tf(fw)}" stroke-linecap="${g.flat ? "butt" : "round"}" opacity="${tf(op)}"/>`);
  }
  // Grain hits: a few short dark ticks where the tooth caught the lead.
  const hits = Math.round(widths * 1.5 * (o.hitScale ?? 1));
  for (let h = 0; h < hits; h++) {
    const k = 1 + rand.int(S - 1), lat = (rand.unit() - 0.5) * width * 0.7;
    const a = pt(k, lat), b = pt(Math.min(k + 1, S), lat + width * 0.03 * rand.next());
    parts.push(`<path d="${polyD([a, b])}" fill="none" stroke="${g.color}" stroke-width="${tf(width * 0.05)}" stroke-linecap="round" opacity="${tf(g.tone * toneScale * 0.55)}"/>`);
  }
  return parts.join("");
}

// Colour-in a closed region with a pencil zigzag (the way a hand shades a bar).
function scribbleFill(axis, halfWidth, o) {
  // axis: polyline down the middle of the bar; the zigzag crosses it.
  const cum = arcLength(axis), total = cum[cum.length - 1];
  const rand = new Rand(o.seed * 7 + 1);
  const step = o.step ?? halfWidth * 0.2;
  const pts = []; let d = halfWidth * 0.5; let side = 1;
  while (d < total - halfWidth * 0.3) {
    const q = pointAt(axis, cum, d);
    const ah = pointAt(axis, cum, Math.min(d + 1, total)), bh = pointAt(axis, cum, Math.max(d - 1, 0));
    let tx = ah.x - bh.x, ty = ah.y - bh.y; const tl = Math.max(Math.hypot(tx, ty), 1e-9);
    const nx = -ty / tl, ny = tx / tl;
    const reach = halfWidth * (0.80 + 0.2 * rand.unit());
    pts.push(P(q.x + nx * reach * side, q.y + ny * reach * side));
    side = -side; d += step * (0.8 + 0.4 * rand.unit());
  }
  return pencilStroke(pts, { ...o, width: o.width, drift: 0.02, tremor: 0.02, lift: 0.05, landing: 0.02, hook: 0, taper: 0.3 });
}

// A clean capsule around an ideal centreline (for stipple and emboss modes).
function capsulePath(ideal, hw) {
  const cum = arcLength(ideal), L = cum[cum.length - 1];
  const a = ideal[0], z = ideal[ideal.length - 1];
  const left = [], right = [];
  for (let k = 0; k <= 32; k++) {
    const u = k / 32, q = pointAt(ideal, cum, u * L);
    const ah = pointAt(ideal, cum, Math.min(u + 0.02, 1) * L), bh = pointAt(ideal, cum, Math.max(u - 0.02, 0) * L);
    let tx = ah.x - bh.x, ty = ah.y - bh.y; const tl = Math.max(Math.hypot(tx, ty), 1e-9);
    const nx = -ty / tl, ny = tx / tl;
    left.push(P(q.x + nx * hw, q.y + ny * hw)); right.push(P(q.x - nx * hw, q.y - ny * hw));
  }
  const nE = P(left[32].x - z.x, left[32].y - z.y), aE = Math.atan2(nE.y, nE.x) * 180 / Math.PI;
  const nS = P(right[0].x - a.x, right[0].y - a.y), aS = Math.atan2(nS.y, nS.x) * 180 / Math.PI;
  return polyD(left.concat(arc(z.x, z.y, hw, aE, aE - 180, 14).slice(1, -1), right.reverse(), arc(a.x, a.y, hw, aS, aS - 180, 14).slice(1, -1))) + "Z";
}

// Pencil stipple: the bar built from dots on a loose hand lattice, denser in
// the middle, thinning to nothing at the edge and the caps.
function stipple(ideal, hw, o) {
  const cum = arcLength(ideal), L = cum[cum.length - 1];
  const rand = new Rand(o.seed * 13 + 5);
  const s = hw * 2 * (o.pitch ?? 0.105);
  const parts = [];
  for (let d = -hw * 0.9; d <= L + hw * 0.9; d += s) {
    const row = Math.round(d / s);
    for (let l = -hw; l <= hw; l += s) {
      const lat = l + (row % 2 ? s / 2 : 0);
      const q = pointAt(ideal, cum, Math.min(Math.max(d, 0), L));
      const ah = pointAt(ideal, cum, Math.min(Math.max(d, 0) / L + 0.02, 1) * L), bh = pointAt(ideal, cum, Math.max(Math.max(d, 0) / L - 0.02, 0) * L);
      let tx = ah.x - bh.x, ty = ah.y - bh.y; const tl = Math.max(Math.hypot(tx, ty), 1e-9); tx /= tl; ty /= tl;
      const over = d < 0 ? -d : d > L ? d - L : 0;               // distance past the end, into the cap
      const inside = Math.hypot(lat, over) / hw;                  // 1 at the capsule edge
      if (inside > 1) continue;
      const edge = Math.pow(inside, 3);
      if (rand.unit() < edge * (o.dropout ?? 0.7)) continue;
      const jx = (rand.next()) * s * 0.16, jy = (rand.next()) * s * 0.16;
      const cx = q.x + tx * (d - Math.min(Math.max(d, 0), L)) - ty * lat + jx, cy = q.y + ty * (d - Math.min(Math.max(d, 0), L)) + tx * lat + jy;
      const r = s * (0.27 + 0.14 * rand.unit()) * (1 - 0.4 * edge);
      const op = (o.tone ?? 0.95) * (0.6 + 0.4 * rand.unit()) * (1 - 0.35 * edge);
      parts.push(`<circle cx="${tf(cx)}" cy="${tf(cy)}" r="${tf(r)}" fill="${o.color}" opacity="${tf(op)}"/>`);
    }
  }
  return parts.join("");
}

// ---------- Speak It geometry ----------
// The mark: five bars, 1 : 2.1 : 3.03 : 2.1 : 1, same hands as generate_brand.swift.
const HANDS = [
  { lean: -0.10, bow: 0.05, stretch: 0.97, lift: 0.06, seed: 11, down: true },
  { lean: 0.08, bow: -0.09, stretch: 1.02, lift: -0.05, seed: 23, down: false },
  { lean: -0.05, bow: 0.07, stretch: 1.00, lift: 0.02, seed: 37, down: true },
  { lean: 0.10, bow: 0.08, stretch: 0.985, lift: 0.07, seed: 41, down: false },
  { lean: -0.09, bow: -0.05, stretch: 1.03, lift: -0.04, seed: 59, down: true },
];
function bars(height, barScale = 1) {
  const unit = height / 2184;
  return { barWidth: 368 * unit * barScale, pitch: 600 * unit, heights: [720, 1512, 2184, 1512, 720].map((h) => h * unit), fullWidth: 600 * unit * 4 + 368 * unit };
}
function barIdeals(b, originX, centerY, downOnly = false) {
  return b.heights.map((h, i) => {
    const hand = HANDS[i];
    const cx = originX + i * b.pitch + 368 * (b.pitch / 600) / 2;
    const length = Math.max(h * hand.stretch - b.barWidth, b.barWidth * 0.2);
    const y0 = centerY - length / 2 + hand.lift * b.barWidth;
    const ideal = Array.from({ length: 25 }, (_, k) => { const u = k / 24; return P(cx + hand.lean * b.barWidth * (u - 0.5) + hand.bow * b.barWidth * Math.sin(Math.PI * u), y0 + length * u); });
    return { ideal: (hand.down || downOnly) ? ideal : ideal.reverse(), seed: hand.seed, cx, y0, length };
  });
}

// Lettering skeletons. Caps: the production geometric alphabet (cap height 100).
const T = 8, CAP = 100;
const CAPS = (() => {
  const g = {};
  { const r = (CAP - 2 * T) / 4, cx = T + r; g.S = { s: [arc(cx, T + r, r, -28, -270).concat(arc(cx, CAP - T - r, r, -90, 152).slice(1))], a: cx + r + T }; }
  { const bowlR = 22, bowlX = 38; g.P = { s: [[P(T, T), P(T, CAP - T)], [P(T, T), P(bowlX, T)].concat(arc(bowlX, T + bowlR, bowlR, -90, 90).slice(1), [P(T, T + 2 * bowlR)])], a: bowlX + bowlR + T }; }
  { const w = 60; g.E = { s: [[P(w - T, T), P(T, T), P(T, CAP - T), P(w - T, CAP - T)], [P(T, 50), P(w - T - 6, 50)]], a: w }; }
  { const w = 84, apex = P(w / 2, T), l = P(T, CAP - T), r = P(w - T, CAP - T), barY = 68, f = (barY - T) / (CAP - 2 * T);
    g.A = { s: [[l, apex, r], [P(l.x + (apex.x - l.x) * (1 - f), barY), P(r.x + (apex.x - r.x) * (1 - f), barY)]], a: w }; }
  { const w = 74, armTop = P(w - T - 2, T), armRoot = P(T, 56), f = 0.42, joint = P(armRoot.x + (armTop.x - armRoot.x) * f, armRoot.y + (armTop.y - armRoot.y) * f);
    g.K = { s: [[P(T, T), P(T, CAP - T)], [armRoot, armTop], [joint, P(w - T, CAP - T)]], a: w }; }
  g.I = { s: [[P(T, T), P(T, CAP - T)]], a: 16 };
  { const w = 68; g.T = { s: [[P(T, T), P(w - T, T)], [P(w / 2, T), P(w / 2, CAP - T)]], a: w }; }
  g[" "] = { s: [], a: 58 - 30 };
  return g;
})();
// Lowercase: the study's relaxed rounded skeleton (x-height ~60, baseline 91, in a 120 box).
const LOWER_RAW = {
  s: { a: 67, p: ["M57 29 C45 14 17 15 13 34 C10 50 52 45 57 65 C62 85 34 99 11 82"] },
  p: { a: 72, p: ["M12 27 L12 119", "M13 36 C25 15 58 17 61 49 C64 78 34 91 13 69"] },
  e: { a: 72, p: ["M13 57 C15 22 53 17 61 43 C65 58 52 63 14 59 C17 84 44 96 62 76"] },
  a: { a: 72, p: ["M61 27 L61 89", "M60 35 C51 16 18 18 12 50 C7 82 42 99 60 74"] },
  k: { a: 70, p: ["M12 6 L12 91", "M59 26 L12 61", "M34 48 L64 92"] },
  i: { a: 31, p: ["M15 32 L15 91", "M15 13 L15 15"] },
  t: { a: 63, p: ["M27 8 L27 76 C27 90 40 95 53 86", "M8 31 L50 31"] },
  tSig: { a: 63, p: ["M27 8 L27 75 C27 90 42 95 61 80", "M8 31 L52 31"] },
  " ": { a: 42, p: [] },
};
const NOTE_RAW = {
  s: { a: 64, p: ["M58 40 C54 28 24 26 18 40 C13 54 54 52 57 70 C60 88 30 98 10 82"] },
  p: { a: 70, p: ["M18 30 C14 38 13 70 12 118", "M14 44 C26 26 60 30 60 55 C60 80 28 88 14 68"] },
  e: { a: 70, p: ["M14 60 L56 58 C60 36 24 28 14 54 C8 82 42 98 62 76"] },
  a: { a: 72, p: ["M58 42 C50 28 16 30 12 56 C8 84 46 94 58 70", "M59 34 L58 82 C58 91 66 93 71 86"] },
  k: { a: 68, p: ["M16 8 C14 30 13 60 13 91", "M56 34 C42 46 30 56 14 62 C32 62 50 74 62 92"] },
  i: { a: 30, p: ["M16 34 L14 91", "M17 15 L18 18"] },
  t: { a: 60, p: ["M28 12 L27 78 C27 90 40 94 54 84", "M10 35 L50 32"] },
  tSig: { a: 60, p: ["M28 12 L27 76 C27 90 44 95 62 80", "M10 35 L52 31"] },
  S: { a: 74, p: ["M62 16 C50 2 16 6 12 30 C8 52 54 48 60 68 C66 90 34 106 8 84"] },
  I: { a: 30, p: ["M17 10 C15 40 15 70 14 96"] },
  " ": { a: 40, p: [] },
};
const CAPS_RAW = { // the study's slightly looser caps, same 120 box (cap 10..96)
  S: { a: 72, p: ["M60 14 C43 2 15 8 12 31 C10 51 53 48 59 68 C65 89 37 105 11 84"] },
  I: { a: 31, p: ["M15 10 L15 96"] },
};
const LOWER = Object.fromEntries(Object.entries(LOWER_RAW).map(([k, v]) => [k, { s: v.p.flatMap((d) => flattenPath(d)), a: v.a }]));
const NOTE = Object.fromEntries(Object.entries(NOTE_RAW).map(([k, v]) => [k, { s: v.p.flatMap((d) => flattenPath(d)), a: v.a }]));
const LOOSECAPS = Object.fromEntries(Object.entries(CAPS_RAW).map(([k, v]) => [k, { s: v.p.flatMap((d) => flattenPath(d)), a: v.a }]));

function layoutWord(text, style, tracking, jitter) {
  // Returns strokes (polylines) in letter space plus width. style: 'caps' | 'lower' | 'mixed'
  const out = []; let x = 0; let idx = 0;
  const chars = [...text];
  for (let c = 0; c < chars.length; c++) {
    const ch = chars[c];
    let glyph;
    if (style === "caps") glyph = CAPS[ch.toUpperCase()];
    else if (style === "lower") glyph = LOWER[ch.toLowerCase()];
    else if (style === "note") glyph = NOTE[ch] ?? NOTE[ch.toLowerCase()];
    else if (style === "notelower") glyph = NOTE[ch.toLowerCase()];
    else glyph = ch === " " ? LOWER[" "] : (ch === ch.toUpperCase() ? LOOSECAPS[ch] : LOWER[ch]);
    if (!glyph) throw new Error(`no glyph ${ch} in ${style}`);
    if (jitter?.signature && ch.toLowerCase() === "t" && c === chars.length - 1 && style !== "caps") glyph = style.startsWith("note") ? NOTE.tSig : LOWER.tSig;
    if (ch === " ") { x += glyph.a + tracking * 0.3; continue; }
    const dy = jitter?.dy?.[idx] ?? 0, rot = (jitter?.rot?.[idx] ?? 0) * Math.PI / 180;
    const cx = 36, cy = style === "caps" ? 50 : 54;
    for (const s of glyph.s) out.push(s.map((q) => { const rx = q.x - cx, ry = q.y - cy; return P(x + cx + rx * Math.cos(rot) - ry * Math.sin(rot), cy + dy + rx * Math.sin(rot) + ry * Math.cos(rot)); }));
    x += glyph.a + tracking; idx++;
  }
  return { strokes: out, width: x - tracking };
}

// ---------- compositions ----------
function grainFilter(id, g, freq = 1.0) {
  // `freq` is tooth per user unit; the pressure cloud is 20× slower. Scale both with the drawing.
  const cloud = tf(freq * 0.05);
  return `<filter id="${id}" x="-5%" y="-5%" width="110%" height="110%" color-interpolation-filters="sRGB">` +
    `<feTurbulence type="fractalNoise" baseFrequency="${freq}" numOctaves="2" seed="7" result="fine"/>` +
    `<feColorMatrix in="fine" type="matrix" values="0 0 0 0 0  0 0 0 0 0  0 0 0 0 0  0 0 0 ${tf(-g.grainK)} ${tf(g.grainB)}" result="tooth"/>` +
    `<feTurbulence type="fractalNoise" baseFrequency="${cloud}" numOctaves="1" seed="11" result="cloud"/>` +
    `<feColorMatrix in="cloud" type="matrix" values="0 0 0 0 0  0 0 0 0 0  0 0 0 0 0  0 0 0 -0.55 1.18" result="pressure"/>` +
    `<feComposite in="SourceGraphic" in2="tooth" operator="in" result="g1"/>` +
    `<feComposite in="g1" in2="pressure" operator="in"/></filter>`;
}
function debossFilter(id, depth = 5) {
  return `<filter id="${id}" x="-20%" y="-20%" width="140%" height="140%" color-interpolation-filters="sRGB">` +
    `<feFlood flood-color="#4A4640" flood-opacity="0.34" result="dark"/>` +
    `<feOffset in="SourceAlpha" dx="${depth}" dy="${depth * 1.2}" result="o1"/><feGaussianBlur in="o1" stdDeviation="${depth * 1.1}" result="b1"/>` +
    `<feComposite in="SourceAlpha" in2="b1" operator="out" result="m1"/><feComposite in="dark" in2="m1" operator="in" result="innerShadow"/>` +
    `<feFlood flood-color="#FFFFFF" flood-opacity="0.95" result="light"/>` +
    `<feOffset in="SourceAlpha" dx="${-depth}" dy="${-depth * 1.2}" result="o2"/><feGaussianBlur in="o2" stdDeviation="${depth * 1.1}" result="b2"/>` +
    `<feComposite in="SourceAlpha" in2="b2" operator="out" result="m2"/><feComposite in="light" in2="m2" operator="in" result="innerLight"/>` +
    `<feGaussianBlur in="SourceAlpha" stdDeviation="${depth * 0.6}" result="soft"/><feOffset in="soft" dx="${-depth * 0.5}" dy="${-depth * 0.6}" result="softO"/>` +
    `<feComposite in="softO" in2="SourceAlpha" operator="out" result="rimMask"/><feFlood flood-color="#FFFFFF" flood-opacity="0.9" result="rimLight"/><feComposite in="rimLight" in2="rimMask" operator="in" result="rim"/>` +
    `<feMerge><feMergeNode in="rim"/><feMergeNode in="SourceGraphic"/><feMergeNode in="innerShadow"/><feMergeNode in="innerLight"/></feMerge></filter>`;
}
function ruledPaper(size, pitch = 64, color = "#B9C6D6") {
  let out = "";
  for (let y = pitch * 1.5; y < size; y += pitch) out += `<line x1="0" y1="${y}" x2="${size}" y2="${y}" stroke="${color}" stroke-width="1.6" opacity="0.7"/>`;
  return out;
}
function paperDefs(id) {
  return `<filter id="${id}" x="0" y="0" width="100%" height="100%"><feTurbulence type="fractalNoise" baseFrequency="0.9" numOctaves="2" seed="3"/><feColorMatrix type="matrix" values="0 0 0 0 0.25  0 0 0 0 0.22  0 0 0 0 0.18  0 0 0 0.06 0"/></filter>`;
}

function drawMark(v, originX, centerY, height) {
  const b = bars(height, v.barScale ?? 1);
  const ideals = barIdeals(b, originX, centerY, v.downOnly);
  const seedBase = v.seed ?? 0;
  let out = "";
  const strokeOpts = (i) => ({ width: b.barWidth, seed: ideals[i].seed + seedBase, grade: v.grade, fiberScale: v.fiberScale, ...(v.stroke ?? {}) });
  if (v.mark === "wave") {
    // Five beats in one gesture: the pencil barely lifts between bars, so a
    // faint travelling line joins the end of each bar to the start of the next.
    ideals.forEach((bar, i) => {
      out += pencilStroke(bar.ideal, { ...strokeOpts(i) });
      if (i < 4) {
        const from = bar.ideal[bar.ideal.length - 1], to = ideals[i + 1].ideal[0];
        const mid = P((from.x + to.x) / 2 + (i % 2 ? -1 : 1) * b.barWidth * 0.15, (from.y + to.y) / 2);
        out += pencilStroke([from, mid, to], { ...strokeOpts(i), seed: 500 + i, width: b.barWidth * 0.16, fiberScale: 0.4, hitScale: 0, toneScale: 0.35, lift: 0.4, landing: 0, drift: 0.1 });
      }
    });
    return { svg: out, width: b.fullWidth };
  }
  ideals.forEach((bar, i) => {
    if (v.mark === "stipple") {
      const g = GRADES[v.grade ?? "2B"];
      out += stipple(bar.ideal, b.barWidth / 2, { seed: ideals[i].seed + seedBase, color: g.color, tone: g.tone, pitch: v.stipplePitch, dropout: v.dropout });
    } else if (v.mark === "emboss") {
      out += `<path d="${capsulePath(bar.ideal, b.barWidth / 2)}" fill="${v.embossFill ?? "#E9E7E1"}"/>`;
    } else if (v.mark === "scribble") {
      out += scribbleFill(bar.ideal, b.barWidth / 2 * 0.9, { ...strokeOpts(i), width: b.barWidth * 0.42, fiberScale: 0.4, hitScale: 0.2, toneScale: 0.85 });
      if (v.outlineToo) out += pencilStroke(bar.ideal, { ...strokeOpts(i), width: b.barWidth * 0.18, fiberScale: 0.5 });
    } else if (v.mark === "outline") {
      // Trace the capsule contour like a sketch, one loop, thin lead.
      const r = b.barWidth / 2, a = bar.ideal[0], z = bar.ideal[bar.ideal.length - 1];
      const dirx = z.x - a.x, diry = z.y - a.y, L = Math.hypot(dirx, diry), tx = dirx / L, ty = diry / L, nx = -ty, ny = tx;
      const loop = [];
      for (let k = 0; k <= 24; k++) { const u = k / 24; const q = pointAt(bar.ideal, arcLength(bar.ideal), u * L); loop.push(P(q.x + nx * r, q.y + ny * r)); }
      loop.push(...arc(z.x, z.y, r, Math.atan2(ny, nx) * 180 / Math.PI, Math.atan2(ny, nx) * 180 / Math.PI + 180, 12).slice(1));
      for (let k = 24; k >= 0; k--) { const u = k / 24; const q = pointAt(bar.ideal, arcLength(bar.ideal), u * L); loop.push(P(q.x - nx * r, q.y - ny * r)); }
      loop.push(...arc(a.x, a.y, r, Math.atan2(-ny, -nx) * 180 / Math.PI, Math.atan2(-ny, -nx) * 180 / Math.PI + 180, 12).slice(1));
      loop.push(P(loop[0].x + nx * 0.5, loop[0].y + ny * 0.5 + b.barWidth * 0.15));
      out += pencilStroke(loop, { ...strokeOpts(i), width: b.barWidth * 0.2, drift: 0.03, tremor: 0.02, lift: 0.15 });
    } else {
      const passes = v.passes ?? 1;
      for (let pss = 0; pss < passes; pss++) {
        const off = pss === 0 ? 0 : (pss % 2 ? 1 : -1) * b.barWidth * 0.14 * pss;
        const ideal = bar.ideal.map((q) => P(q.x + off, q.y + (pss ? b.barWidth * 0.05 * pss : 0)));
        out += pencilStroke(ideal, { ...strokeOpts(i), seed: ideals[i].seed + seedBase + pss * 101, toneScale: pss ? 0.55 : 1 });
      }
    }
  });
  return { svg: out, width: b.fullWidth };
}

function drawWord(v, x0, baselineY, capH) {
  const style = v.word ?? "caps";
  const tracking = v.tracking ?? (style === "caps" ? 30 : 15);
  const { strokes, width } = layoutWord(v.text ?? (style === "caps" ? "SPEAK IT" : (style === "lower" || style === "notelower") ? "speak it" : "Speak It"), style, tracking, v.jitter);
  const scale = capH / (style === "caps" ? 100 : 86); // lowercase cap-ish height (k ascender 6..91)
  const originY = style === "caps" ? 100 : 91; // baseline in glyph space
  const tx = (q) => P(x0 + q.x * scale, baselineY + (q.y - originY) * scale);
  let out = ""; let k = 0;
  for (const s of strokes) {
    const passes = v.wordPasses ?? v.passes ?? 1;
    for (let pss = 0; pss < passes; pss++) {
      const off = pss ? (pss % 2 ? 1 : -1) * v.leadWidth * 0.25 * pss : 0;
      out += pencilStroke(s.map((q) => { const r = tx(q); return P(r.x + off, r.y + off * 0.6); }), {
        width: v.leadWidth * scale / (capH / 100) * (v.wordWeight ?? 1), seed: 1000 + k * 13 + (v.seed ?? 0) + pss * 77, grade: v.grade, fiberScale: v.fiberScale,
        drift: 0.05, tremor: 0.025, pressure: 0.16, lift: 0.18, landing: 0.05, hook: 0.03, toneScale: pss ? 0.5 : 1, ...(v.wordStroke ?? {}),
      });
    }
    k++;
  }
  return { svg: out, width: width * scale };
}

function lockup(v) {
  // Canvas grows to fit: 80-unit margins, mark at left, word at right.
  const g = GRADES[v.grade ?? "2B"];
  const markH = v.markH ?? 218.4, markX = 80, centerY = 150;
  const mark = drawMark(v, markX, centerY, markH);
  const capH = v.capH ?? 92;
  const word = drawWord(v, markX + mark.width + (v.gap ?? 56), centerY + capH / 2 - (v.word === "caps" ? 0 : 3), capH);
  const W = Math.ceil(markX + mark.width + (v.gap ?? 56) + word.width + 80);
  const paper = v.paper ?? "#FFFFFF";
  const fid = `grain-${v.id}`;
  return `<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${W} 300" role="img" aria-labelledby="t d">
  <title id="t">Speak It pencil study ${v.id}: ${v.name}</title>
  <desc id="d">${v.note} Review candidate only.</desc>
  <defs>${grainFilter(fid, g, v.grainFreq ?? 1.0)}</defs>
  <rect width="${W}" height="300" fill="${paper}"/>
  ${v.mark === "stipple" ? mark.svg + `<g filter="url(#${fid})">${word.svg}</g>` : `<g filter="url(#${fid})">${mark.svg}${word.svg}</g>`}
</svg>
`;
}

function icon(v) {
  const g = GRADES[v.grade ?? "2B"];
  const size = 1024, markH = size * (v.iconScale ?? 0.56);
  const b = bars(markH, v.barScale ?? 1);
  const mark = drawMark(v, (size - b.fullWidth) / 2, size / 2, markH);
  const fid = `grain-${v.id}`;
  const paperFill = v.paper ?? "#F4F1EA";
  const textured = v.mark !== "stipple" && v.mark !== "emboss";
  const defs = textured ? grainFilter(fid, g, (v.grainFreq ?? 1.0) * 218.4 / markH) : v.mark === "emboss" ? debossFilter(fid, v.depth ?? 5) : "";
  const wrapped = textured || v.mark === "emboss" ? `<g filter="url(#${fid})">${mark.svg}</g>` : mark.svg;
  return `<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" role="img" aria-labelledby="t d">
  <title id="t">Speak It pencil icon ${v.id}: ${v.name}</title>
  <desc id="d">${v.note} Review candidate only.</desc>
  <defs>${defs}${paperDefs("paper-" + v.id)}</defs>
  <rect width="1024" height="1024" fill="${paperFill}"/>
  ${v.paperTexture === false ? "" : `<rect width="1024" height="1024" filter="url(#paper-${v.id})"/>`}
  ${v.ruled ? ruledPaper(1024, v.ruled, v.ruleColor) : ""}
  ${wrapped}
</svg>
`;
}

// ---------- the study ----------
const LOCKUPS = [
  { id: "L01", name: "HB, current caps", grade: "HB", word: "caps", leadWidth: 14, note: "Today's logo, drawn in HB pencil. Fine, grey, most paper tooth." },
  { id: "L02", name: "2B, current caps", grade: "2B", word: "caps", leadWidth: 14, note: "Same logo, 2B: darker and softer, the classic sketching grade." },
  { id: "L03", name: "6B, current caps", grade: "6B", word: "caps", leadWidth: 15, note: "Soft, black, heavy graphite. Least tooth, most weight." },
  { id: "L04", name: "2B, lowercase", grade: "2B", word: "lower", leadWidth: 13, jitter: { dy: [0, -2, 1, -1, 2, 0, 1], rot: [-1, 0.4, -0.4, 0.7, -0.6, 0.5, -0.5] }, note: "Relaxed lowercase written in 2B; letters sit on the line like a note." },
  { id: "L05", name: "2B, Speak It signature", grade: "2B", word: "mixed", leadWidth: 13, jitter: { dy: [0, -1, 1, 0, 2, -1, 0], signature: true }, note: "Mixed case with the lifted final t. The one gesture that is ours." },
  { id: "L06", name: "Sketch, double pass", grade: "2B", word: "lower", leadWidth: 11, passes: 2, jitter: { dy: [0, -1, 1, -1, 1, 0, 1] }, note: "Every stroke traced twice, loosely, like a designer's first sketch." },
  { id: "L07", name: "Scribble-filled bars", grade: "2B", word: "lower", mark: "scribble", outlineToo: false, leadWidth: 13, jitter: { dy: [0, -2, 1, -1, 2, 0, 1] }, note: "Bars coloured in with a pencil zigzag; reads solid at 60 px, hand-shaded at 1024." },
  { id: "L08", name: "One gesture, pencil barely lifts", grade: "2B", word: "lower", mark: "wave", leadWidth: 13, jitter: { dy: [0, -2, 1, -1, 2, 0, 1] }, note: "Five bars in one movement; a faint travelling line shows the pencil never quite left the paper." },
  { id: "L09", name: "Same-hand downstrokes", grade: "2B", word: "lower", downOnly: true, leadWidth: 13, jitter: { dy: [0, -2, 1, -1, 2, 0, 1] }, note: "All five bars pulled downward: heavy landing at the top, feathered lift below. One consistent gesture." },
  { id: "L10", name: "Carpenter pencil", grade: "carpenter", word: "caps", leadWidth: 14, note: "Flat wide lead: square ends, even fill, editorial." },
  { id: "L11", name: "2B, slim bars", grade: "2B", word: "lower", barScale: 0.62, leadWidth: 13, jitter: { dy: [0, -2, 1, -1, 2, 0, 1] }, note: "Bars at 62% weight so they read as pencil lines, not marker." },
  { id: "L13", name: "Note hand, lowercase", grade: "2B", word: "notelower", leadWidth: 13, jitter: { dy: [0, -1, 1, -1, 2, 0, 1], rot: [-2, 1, -1, 1.5, -1, 1, -1.5] }, note: "Letters written the way a hand writes fast: one-stroke e and a, entry hooks, exit flicks." },
  { id: "L14", name: "Note hand, Speak It", grade: "2B", word: "note", leadWidth: 13, jitter: { dy: [0, -1, 1, 0, 2, -1, 0], rot: [-1.5, 0.8, -0.6, 1, -0.8, 0.6, -1], signature: true }, note: "Note hand with capitals and the lifted final t." },
  { id: "L16", name: "Stipple mark, note hand", grade: "2B", word: "note", mark: "stipple", leadWidth: 13, jitter: { dy: [0, -1, 1, 0, 2, -1, 0], rot: [-1.5, 0.8, -0.6, 1, -0.8, 0.6, -1], signature: true }, note: "Dotted bars beside a pencil-written name." },
  { id: "L15", name: "Note hand, 6B, slim bars, cream", grade: "6B", word: "note", barScale: 0.7, paper: "#F4F1EA", leadWidth: 14, jitter: { dy: [0, -1, 1, 0, 2, -1, 0], rot: [-1.5, 0.8, -0.6, 1, -0.8, 0.6, -1], signature: true }, note: "The whole thing as one pencil drawing: soft lead, slimmer bars, warm paper." },
  { id: "L12", name: "6B on cream paper", grade: "6B", word: "mixed", paper: "#F4F1EA", leadWidth: 14, jitter: { dy: [0, -1, 1, 0, 2, -1, 0], signature: true }, note: "Soft black on warm paper, the tone of the icon." },
];
const ICONS = [
  { id: "I07", name: "Stipple, white on black", grade: "chalk", mark: "stipple", paper: "#000000", paperTexture: false, note: "Bars built from pencil dots on a loose lattice; density fades to the edge." },
  { id: "I08", name: "Stipple, graphite on cream", grade: "2B", mark: "stipple", note: "Same dots in 2B on warm paper." },
  { id: "I09", name: "Debossed into ruled paper", mark: "emboss", paper: "#F7F6F2", paperTexture: false, ruled: 68, embossFill: "#ECEAE4", depth: 6, note: "The mark pressed into notebook paper; no ink at all." },
  { id: "I10", name: "Debossed, plain paper", mark: "emboss", paper: "#F4F1EA", paperTexture: true, embossFill: "#ECE9E1", depth: 6, note: "Blind emboss on warm paper." },
  { id: "I01", name: "2B on cream", grade: "2B", note: "Graphite bars on warm paper." },
  { id: "I02", name: "6B on cream", grade: "6B", note: "Darker graphite; strongest at 60 px." },
  { id: "I03", name: "Scribble fill on cream", grade: "2B", mark: "scribble", note: "Shaded-in bars." },
  { id: "I04", name: "White pencil on dark", grade: "chalk", paper: "#141416", paperTexture: false, note: "Inverts today's dark icon; white crayon on black card." },
  { id: "I05", name: "HB on white", grade: "HB", paper: "#FFFFFF", paperTexture: false, note: "Lightest, most sketch-like." },
  { id: "I06", name: "One gesture on cream", grade: "2B", mark: "wave", note: "Faint travelling lines between beats." },
];

const files = [];
for (const v of LOCKUPS) { const f = `SpeakIt-Pencil-${v.id}.svg`; fs.writeFileSync(path.join(outDir, f), lockup(v)); files.push({ ...v, file: f, kind: "lockup" }); }
for (const v of ICONS) { const f = `SpeakIt-Pencil-${v.id}.svg`; fs.writeFileSync(path.join(outDir, f), icon(v)); files.push({ ...v, file: f, kind: "icon" }); }

// Review board (HTML; Chrome rasterises it).
const esc = (s) => s.replaceAll("&", "&amp;").replaceAll("<", "&lt;");
const cards = files.map((v) => v.kind === "lockup"
  ? `<section class="card"><h3>${v.id} ${esc(v.name)}</h3><p>${esc(v.note)}</p><img class="big" src="${v.file}" width="880"><div class="row"><img src="${v.file}" width="300"><img src="${v.file}" width="160"><img src="${v.file}" width="90"></div></section>`
  : `<section class="card icon"><h3>${v.id} ${esc(v.name)}</h3><p>${esc(v.note)}</p><div class="row"><img src="${v.file}" width="256" class="ic"><img src="${v.file}" width="120" class="ic"><img src="${v.file}" width="60" class="ic"><img src="${v.file}" width="29" class="ic"></div></section>`).join("\n");
fs.writeFileSync(path.join(outDir, "board.html"), `<!doctype html><meta charset="utf-8"><title>Speak It pencil study</title>
<style>body{margin:0;padding:40px;background:#e9e6df;font:15px/1.4 -apple-system,Helvetica,sans-serif;color:#222}h1{font-size:30px;margin:0 0 6px}h2{margin:40px 0 12px;font-size:20px}.grid{display:grid;grid-template-columns:1fr 1fr;gap:24px}.card{background:#fff;border-radius:16px;padding:18px 20px 16px;box-shadow:0 1px 2px rgba(0,0,0,.06)}.card h3{margin:0 0 4px;font-size:17px}.card p{margin:0 0 10px;color:#666;font-size:13px}.big{display:block;width:100%;height:auto;border:1px solid #eee;border-radius:8px}.row{display:flex;align-items:center;gap:22px;margin-top:12px}.row img{border:1px solid #eee}.ic{border-radius:22%;}.icon .row{align-items:flex-end}</style>
<h1>Speak It — pencil on paper study</h1><p>Deterministic graphite fibres + paper tooth. Each lockup shown at 880, 300, 160 and 90 px; icons at 256, 120, 60, 29 px.</p>
<h2>Lockups</h2><div class="grid">${cards.split("\n").filter((c) => !c.includes("class=\"card icon\"")).join("\n")}</div>
<h2>Icons</h2><div class="grid">${cards.split("\n").filter((c) => c.includes("class=\"card icon\"")).join("\n")}</div>`);
fs.writeFileSync(path.join(outDir, "candidates.json"), JSON.stringify(files, null, 2) + "\n");
const total = fs.readdirSync(outDir).filter((f) => f.endsWith(".svg")).reduce((a, f) => a + fs.statSync(path.join(outDir, f)).size, 0);
console.log(`wrote ${files.length} svgs (${(total / 1024).toFixed(0)} KB) + board.html to ${outDir}`);

// ---------- raster (Chrome) ----------
const chrome = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";
if (!process.argv.includes("--no-raster") && fs.existsSync(chrome)) {
  const shot = (html, png, w, h) => execFileSync(chrome, ["--headless=new", "--disable-gpu", "--hide-scrollbars", `--screenshot=${png}`, `--window-size=${w},${h}`, `file://${html}`], { stdio: "ignore" });
  const boardH = 120 + Math.ceil(LOCKUPS.length / 2) * 480 + Math.ceil(ICONS.length / 2) * 300 + 200;
  shot(path.join(outDir, "board.html"), path.join(outDir, "SpeakIt-Pencil-Paper-Board.png"), 1900, boardH);
  const tmp = path.join(outDir, ".raster.html");
  for (const v of files) {
    const w = v.kind === "lockup" ? 1900 : 1024;
    fs.writeFileSync(tmp, `<!doctype html><body style="margin:0;background:#fff"><img src="${v.file}" width="${w}" style="display:block"></body>`);
    const svg = fs.readFileSync(path.join(outDir, v.file), "utf8");
    const vb = /viewBox="0 0 (\d+) (\d+)"/.exec(svg);
    shot(tmp, path.join(outDir, v.file.replace(".svg", ".png")), w, Math.round(w * vb[2] / vb[1]));
  }
  fs.unlinkSync(tmp);
  console.log(`rasterised the board and ${files.length} candidates with Chrome`);
} else if (!process.argv.includes("--no-raster")) {
  console.log("Chrome not found; skipped PNG rasterisation (open board.html in a browser instead)");
}
