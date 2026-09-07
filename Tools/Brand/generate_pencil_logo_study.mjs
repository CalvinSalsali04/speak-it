// Speak It pencil-logo exploration generator.
//
// This is intentionally separate from generate_brand.swift. It creates review
// candidates only and never overwrites the approved production masters.
// Every letter is a vector path; there are no external fonts in the logos.

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, "../..");
const outDir = path.join(root, "Design/Brand/Explorations/Pencil-Study");
fs.mkdirSync(outDir, { recursive: true });

const ink = "#0A0A0A";

const caps = {
  S: { a: 72, p: ["M60 14 C43 2 15 8 12 31 C10 51 53 48 59 68 C65 89 37 105 11 84"] },
  P: { a: 73, p: ["M12 96 L12 10", "M12 11 C54 4 66 18 64 37 C62 56 44 61 12 56"] },
  E: { a: 70, p: ["M61 10 L12 10 L12 96 L62 96", "M12 52 L54 52"] },
  A: { a: 81, p: ["M8 96 L40 10 L73 96", "M20 66 L61 66"] },
  K: { a: 78, p: ["M12 10 L12 96", "M65 10 L12 58", "M37 36 L69 96"] },
  I: { a: 31, p: ["M15 10 L15 96"] },
  T: { a: 75, p: ["M6 10 L68 10", "M37 10 L37 96"] },
  " ": { a: 46, p: [] },
};

const lower = {
  s: { a: 67, p: ["M57 29 C45 14 17 15 13 34 C10 50 52 45 57 65 C62 85 34 99 11 82"] },
  p: { a: 72, p: ["M12 27 L12 119", "M13 36 C25 15 58 17 61 49 C64 78 34 91 13 69"] },
  e: { a: 72, p: ["M13 57 C15 22 53 17 61 43 C65 58 52 63 14 59 C17 84 44 96 62 76"] },
  a: { a: 72, p: ["M61 27 L61 89", "M60 35 C51 16 18 18 12 50 C7 82 42 99 60 74"] },
  k: { a: 70, p: ["M12 6 L12 91", "M59 26 L12 61", "M34 48 L64 92"] },
  i: { a: 31, p: ["M15 32 L15 91", "M15 13 L15 14"] },
  t: { a: 63, p: ["M27 8 L27 76 C27 90 40 95 53 86", "M8 31 L50 31"] },
  " ": { a: 42, p: [] },
};

const variants = [
  {
    id: "01", name: "Soft Pencil Caps", family: "LETTERING FIRST",
    note: "Closest to today; slimmer graphite-like caps and more breathing room.",
    word: "SPEAK IT", form: "caps", wordStroke: 10.5, tracking: 22,
    wordScaleX: 0.86, wordScaleY: 0.90, markStroke: 15, passes: 1,
  },
  {
    id: "02", name: "Lowercase Ease", family: "LETTERING FIRST",
    note: "Rounded custom lowercase; the clearest HEYTEA-like behavioral shift.",
    word: "speak it", form: "lower", wordStroke: 10.5, tracking: 15,
    wordScaleX: 0.92, wordScaleY: 0.90, markStroke: 15, passes: 1,
    letterDy: [0, -2, 1, -1, 2, 0, 1], letterRot: [-1.0, 0.4, -0.4, 0.7, -0.6, 0.5, -0.5],
  },
  {
    id: "03", name: "Airy Lowercase", family: "LETTERING FIRST",
    note: "Quiet lowercase with extra air; calm, premium, and less app-generic.",
    word: "speak it", form: "lower", wordStroke: 9.2, tracking: 24,
    wordScaleX: 0.86, wordScaleY: 0.86, markStroke: 14, passes: 1,
    letterDy: [1, -1, 1, 0, 2, -1, 0],
  },
  {
    id: "04", name: "Loose Note Caps", family: "LETTERING FIRST",
    note: "Uppercase remains, but each letter has a subtly different stance.",
    word: "SPEAK IT", form: "caps", wordStroke: 10, tracking: 18,
    wordScaleX: 0.82, wordScaleY: 0.84, markStroke: 15, passes: 1,
    letterDy: [1, -3, 2, -1, 3, 0, -2], letterRot: [-1.2, 0.8, -0.5, 0.6, -0.8, 0.5, 0.8],
  },
  {
    id: "05", name: "Graphite Double-Pass", family: "TOOL & PRESSURE",
    note: "A controlled second trace makes the hand visible without paper texture.",
    word: "speak it", form: "lower", wordStroke: 9.4, tracking: 17,
    wordScaleX: 0.91, wordScaleY: 0.90, markStroke: 14, passes: 2,
    letterDy: [0, -1, 1, -1, 1, 0, 1], ghostOpacity: 0.20,
  },
  {
    id: "06", name: "Felt-Tip Pressure", family: "TOOL & PRESSURE",
    note: "Bolder landing and softer lift; strongest continuity with the existing bars.",
    word: "SPEAK IT", form: "caps", wordStroke: 14.5, tracking: 17,
    wordScaleX: 0.78, wordScaleY: 0.88, markStroke: 18, passes: 1,
  },
  {
    id: "07", name: "Dry Lead", family: "TOOL & PRESSURE",
    note: "Fine primary skeleton plus faint broken graphite; texture stays secondary.",
    word: "speak it", form: "lower", wordStroke: 8.5, tracking: 18,
    wordScaleX: 0.93, wordScaleY: 0.91, markStroke: 13, passes: 3,
    ghostOpacity: 0.11, dry: true, letterDy: [0, -1, 2, 0, 1, -1, 0],
  },
  {
    id: "08", name: "Carpenter Pencil", family: "TOOL & PRESSURE",
    note: "Flatter terminals and a wider nib feel more deliberate and editorial.",
    word: "SPEAK IT", form: "caps", wordStroke: 12.5, tracking: 20,
    wordScaleX: 0.80, wordScaleY: 0.84, markStroke: 16, passes: 1, linecap: "square",
  },
  {
    id: "09", name: "Inward Breath", family: "VOICE RHYTHM",
    note: "The same five heights bow inward, making the capture action feel focused.",
    word: "speak it", form: "lower", wordStroke: 10.5, tracking: 15,
    wordScaleX: 0.92, wordScaleY: 0.90, markStroke: 15, passes: 1,
    markLean: [5, 3, 0, -3, -5], markCurve: [3, 4, 1, -4, -3],
  },
  {
    id: "10", name: "Forward Capture", family: "VOICE RHYTHM",
    note: "A slight shared forward lean suggests a thought moving into the app.",
    word: "speak it", form: "lower", wordStroke: 10, tracking: 16,
    wordScaleX: 0.92, wordScaleY: 0.90, markStroke: 15, passes: 1,
    markLean: [5, 7, 8, 7, 5], markCurve: [2, 3, 4, 3, 2],
    letterRot: [-0.6, 0.4, 0.2, -0.4, 0.5, 0.2, -0.3],
  },
  {
    id: "11", name: "Landing & Lift", family: "VOICE RHYTHM",
    note: "Uneven landings and a lifted final t turn recording into a human gesture.",
    word: "speak it", form: "lower", wordStroke: 10.5, tracking: 16,
    wordScaleX: 0.91, wordScaleY: 0.90, markStroke: 15, passes: 1,
    barDy: [3, -2, 1, 2, -4], markLean: [-1, 2, 4, 5, 7], signature: true,
  },
  {
    id: "12", name: "Quiet Signature", family: "VOICE RHYTHM",
    note: "Best all-rounder: human mixed case, original bars, and one restrained exit flick.",
    word: "Speak It", form: "mixed", wordStroke: 10.7, tracking: 14,
    wordScaleX: 0.90, wordScaleY: 0.91, markStroke: 15, passes: 2,
    ghostOpacity: 0.12, letterDy: [0, -1, 1, 0, 2, -1, 0], signature: true,
  },
];

function esc(s) {
  return s.replaceAll("&", "&amp;").replaceAll("<", "&lt;").replaceAll(">", "&gt;");
}

function markPaths(v) {
  const heights = [56, 118, 170, 118, 56]; // preserves 1 : 2.1 : 3.03 : 2.1 : 1
  const xs = [80, 108, 136, 164, 192];
  const lean = v.markLean ?? [0, 0, 0, 0, 0];
  const curve = v.markCurve ?? [1.5, -2, 2, -1.5, 1];
  const dy = v.barDy ?? [0, 0, 0, 0, 0];
  return heights.map((h, i) => {
    const y1 = 150 - h / 2 + dy[i] / 2;
    const y2 = 150 + h / 2 + dy[i] / 2;
    const x1 = xs[i] - lean[i] / 2;
    const x2 = xs[i] + lean[i] / 2;
    const cx = xs[i] + curve[i];
    return `M${x1.toFixed(1)} ${y1.toFixed(1)} Q${cx.toFixed(1)} 150 ${x2.toFixed(1)} ${y2.toFixed(1)}`;
  });
}

function drawPass(paths, stroke, width, linecap, opacity = 1, transform = "", dash = "") {
  const dashAttr = dash ? ` stroke-dasharray="${dash}"` : "";
  return `<g fill="none" stroke="${stroke}" stroke-width="${width}" stroke-linecap="${linecap}" stroke-linejoin="round" opacity="${opacity}" transform="${transform}"${dashAttr}>${paths.map((d) => `<path d="${d}"/>`).join("")}</g>`;
}

function drawMark(v) {
  const paths = markPaths(v);
  const cap = v.linecap ?? "round";
  let out = "";
  if (v.passes >= 2) out += drawPass(paths, ink, Math.max(v.markStroke * 0.62, 5), cap, v.ghostOpacity ?? 0.15, "translate(1.2 -0.8)");
  if (v.passes >= 3) out += drawPass(paths, ink, Math.max(v.markStroke * 0.38, 4), cap, v.ghostOpacity ?? 0.10, "translate(-1.5 1.1)", v.dry ? "9 7" : "");
  out += drawPass(paths, ink, v.markStroke, cap, 0.96);
  return out;
}

function wordPaths(v) {
  const all = [];
  let x = 0;
  let visibleIndex = 0;
  for (const ch of v.word) {
    const alphabet = v.form === "caps" ? caps : v.form === "lower" ? lower : (ch === ch.toUpperCase() && ch !== " " ? caps : lower);
    const glyph = alphabet[ch];
    if (!glyph) throw new Error(`Missing ${v.form} glyph: ${ch}`);
    if (ch === " ") {
      x += glyph.a + v.tracking * 0.3;
      continue;
    }
    const dy = v.letterDy?.[visibleIndex] ?? 0;
    const rot = v.letterRot?.[visibleIndex] ?? 0;
    let paths = glyph.p;
    if (v.signature && ch.toLowerCase() === "t" && visibleIndex === v.word.replaceAll(" ", "").length - 1) {
      paths = v.form !== "caps"
        ? ["M27 8 L27 75 C27 90 42 95 61 80", "M8 31 L52 31"]
        : ["M6 10 L70 10", "M37 10 L37 87 Q43 98 57 88"];
    }
    all.push({ paths, transform: `translate(${x.toFixed(2)} ${dy}) rotate(${rot} 36 54)` });
    x += glyph.a + v.tracking;
    visibleIndex += 1;
  }
  return all;
}

function drawWord(v) {
  const cap = v.linecap ?? "round";
  const glyphs = wordPaths(v);
  const sx = v.wordScaleX ?? 1;
  const sy = v.wordScaleY ?? 1;
  const originY = v.form === "caps" ? 105 : 96;
  const pass = (width, opacity, transform = "", dash = "") => {
    const dashAttr = dash ? ` stroke-dasharray="${dash}"` : "";
    return `<g transform="translate(250 ${originY}) scale(${sx} ${sy}) ${transform}" fill="none" stroke="${ink}" stroke-width="${width}" stroke-linecap="${cap}" stroke-linejoin="round" opacity="${opacity}"${dashAttr}>${glyphs.map((g) => `<g transform="${g.transform}">${g.paths.map((d) => `<path d="${d}"/>`).join("")}</g>`).join("")}</g>`;
  };
  let out = "";
  if (v.passes >= 2) out += pass(Math.max(v.wordStroke * 0.60, 4), v.ghostOpacity ?? 0.15, "translate(1.1 -0.8)");
  if (v.passes >= 3) out += pass(Math.max(v.wordStroke * 0.38, 3), v.ghostOpacity ?? 0.10, "translate(-1.4 1.0)", v.dry ? "8 6" : "");
  out += pass(v.wordStroke, 0.96);
  return out;
}

function logoGroup(v) {
  return `<g>${drawMark(v)}${drawWord(v)}</g>`;
}

function standaloneSVG(v) {
  return `<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1000 300" role="img" aria-labelledby="title desc">
  <title id="title">Speak It pencil logo study ${v.id}: ${esc(v.name)}</title>
  <desc id="desc">${esc(v.note)} Review candidate only, not an approved production logo.</desc>
  ${logoGroup(v)}
</svg>
`;
}

function boardSVG() {
  const cols = 3;
  const cardW = 660;
  const cardH = 500;
  const gap = 30;
  const margin = 60;
  const top = 245;
  const width = margin * 2 + cols * cardW + (cols - 1) * gap;
  const rows = Math.ceil(variants.length / cols);
  const height = top + rows * cardH + (rows - 1) * gap + 120;
  const cards = variants.map((v, i) => {
    const col = i % cols;
    const row = Math.floor(i / cols);
    const x = margin + col * (cardW + gap);
    const y = top + row * (cardH + gap);
    const family = row === 0 ? v.family : (variants[i - cols]?.family !== v.family ? v.family : "");
    return `<g transform="translate(${x} ${y})">
      <rect width="${cardW}" height="${cardH}" rx="28" fill="#FFFFFF" stroke="#D9D9D9" stroke-width="2"/>
      <text x="32" y="46" font-family="Helvetica, Arial, sans-serif" font-size="16" font-weight="700" letter-spacing="2" fill="#777777">${esc(family || v.family)}</text>
      <text x="32" y="88" font-family="Helvetica, Arial, sans-serif" font-size="28" font-weight="700" fill="${ink}">${v.id}  ${esc(v.name)}</text>
      <g transform="translate(20 104) scale(0.62)">${logoGroup(v)}</g>
      <line x1="32" y1="340" x2="628" y2="340" stroke="#E8E8E8"/>
      <text x="32" y="380" font-family="Helvetica, Arial, sans-serif" font-size="18" fill="#4C4C4C">${esc(v.note)}</text>
      <g transform="translate(520 390) scale(0.46)">${drawMark(v)}</g>
      <text x="32" y="460" font-family="Helvetica, Arial, sans-serif" font-size="14" fill="#888888">same 5-bar count + 1 : 2.1 : 3.03 : 2.1 : 1 rhythm</text>
    </g>`;
  }).join("\n");
  return `<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${width} ${height}" role="img" aria-labelledby="title desc">
  <title id="title">Speak It pencil-drawn logo contender study</title>
  <desc id="desc">Twelve controlled vector explorations that preserve the existing five-bar identity while varying lettering, tool behavior, and voice rhythm.</desc>
  <rect width="${width}" height="${height}" fill="#F4F3F0"/>
  <text x="${margin}" y="82" font-family="Helvetica, Arial, sans-serif" font-size="50" font-weight="700" fill="${ink}">Speak It — pencil-drawn contender study</text>
  <text x="${margin}" y="126" font-family="Helvetica, Arial, sans-serif" font-size="22" fill="#555555">Twelve editable vector directions. The symbol memory cue is preserved; only authorship, pressure, lettering, and rhythm move.</text>
  <text x="${margin}" y="170" font-family="Helvetica, Arial, sans-serif" font-size="18" fill="#777777">Review board · 4 September 2026 · concepts, not approved production masters</text>
  ${cards}
</svg>
`;
}

for (const v of variants) {
  const file = `SpeakIt-Pencil-${v.id}-${v.name.toLowerCase().replaceAll(/[^a-z0-9]+/g, "-").replaceAll(/^-|-$/g, "")}.svg`;
  fs.writeFileSync(path.join(outDir, file), standaloneSVG(v));
}
fs.writeFileSync(path.join(outDir, "SpeakIt-Pencil-Contender-Board.svg"), boardSVG());
fs.writeFileSync(path.join(outDir, "contenders.json"), JSON.stringify(variants, null, 2) + "\n");
console.log(`Wrote ${variants.length} logo candidates and one review board to ${outDir}`);
