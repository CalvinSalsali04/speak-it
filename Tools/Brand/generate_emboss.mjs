// Speak It — embossed mark masters (review candidates; does not touch production files).
//
// Run:  node Tools/Brand/generate_emboss.mjs
//
// Writes to Design/Brand/Emboss/: the five-bar mark as clean capsules, raised
// out of light paper (the neumorphic emboss Calvin referenced), a dark twin,
// and flat black-on-white / white-on-black masters for the app, favicon and
// print. SVG for everything; Chrome rasterises 4K PNGs and 1024 icons.
import fs from "node:fs";
import path from "node:path";
import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, "../..");
const out = path.join(root, "Design/Brand/Emboss");
fs.mkdirSync(out, { recursive: true });

// The mark: 1 : 2.1 : 3.03 : 2.1 : 1, bar width 368, pitch 600 (units of a 2184-tall mark).
const BAR = 368, PITCH = 600, HEIGHTS = [720, 1512, 2184, 1512, 720];
const MARK_W = PITCH * 4 + BAR, MARK_H = 2184;
const f = (v) => (Math.round(v * 100) / 100).toString();

function capsules(scale, ox, oy) {
  return HEIGHTS.map((h, i) => {
    const x = ox + i * PITCH * scale, w = BAR * scale, hh = h * scale, y = oy + (MARK_H * scale - hh) / 2;
    return `<rect x="${f(x)}" y="${f(y)}" width="${f(w)}" height="${f(hh)}" rx="${f(w / 2)}"/>`;
  }).join("");
}

function emboss({ id, size, width, height, dark, markFraction = 0.26, strength = 1, contrast = false }) {
  const W = width ?? size, H = height ?? size;
  // contrast: black bars on light paper / white bars on black paper (the flat logo, raised).
  const s = H * markFraction / MARK_H;               // mark height = markFraction × canvas height
  const ox = (W - MARK_W * s) / 2, oy = (H - MARK_H * s) / 2;
  const bw = BAR * s;                                  // bar width in px: everything scales from it
  const paper = dark ? "#1C1C1E" : "#ECECEC";
  const face0 = contrast ? (dark ? "#FFFFFF" : "#26262A") : dark ? "#2A2A2C" : "#FAFAFA";
  const face1 = contrast ? (dark ? "#E9E9E9" : "#0A0A0A") : dark ? "#202022" : "#EFEFEF";
  const rimA = contrast ? (dark ? 0.9 : 0.28) : dark ? 0.16 : 0.9;
  const innerA = contrast ? (dark ? 0.12 : 0.55) : dark ? 0.5 : 0.10;
  const shadowC = dark ? "#000000" : "#000000", shadowA = (dark ? 0.55 : 0.16) * strength;
  const lightC = "#FFFFFF", lightA = (dark ? 0.10 : 0.95) * strength;
  const d = bw * 0.28, blur = bw * 0.30;               // offset and softness of the two lights
  return `<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" width="${W}" height="${H}" viewBox="0 0 ${W} ${H}" role="img" aria-label="Speak It embossed mark">
  <defs>
    <linearGradient id="face" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="${face0}"/><stop offset="1" stop-color="${face1}"/></linearGradient>
    <radialGradient id="paperLight" cx="0.5" cy="0.45" r="0.75"><stop offset="0" stop-color="#FFFFFF" stop-opacity="${dark ? 0.04 : 0.55}"/><stop offset="1" stop-color="#FFFFFF" stop-opacity="0"/></radialGradient>
    <filter id="grain" x="0" y="0" width="100%" height="100%"><feTurbulence type="fractalNoise" baseFrequency="${f(0.9 * 1024 / H)}" numOctaves="2" seed="3"/><feColorMatrix type="matrix" values="0 0 0 0 0.5  0 0 0 0 0.5  0 0 0 0 0.5  0 0 0 ${dark ? 0.05 : 0.045} 0"/></filter>
    <filter id="relief" x="-50%" y="-50%" width="200%" height="200%" color-interpolation-filters="sRGB">
      <feGaussianBlur in="SourceAlpha" stdDeviation="${f(blur)}" result="soft"/>
      <feOffset in="soft" dx="${f(d)}" dy="${f(d * 1.15)}" result="shadowO"/>
      <feFlood flood-color="${shadowC}" flood-opacity="${f(shadowA)}"/><feComposite in2="shadowO" operator="in" result="shadow"/>
      <feOffset in="soft" dx="${f(-d * 0.8)}" dy="${f(-d * 0.9)}" result="lightO"/>
      <feFlood flood-color="${lightC}" flood-opacity="${f(lightA)}"/><feComposite in2="lightO" operator="in" result="light"/>
      <feGaussianBlur in="SourceAlpha" stdDeviation="${f(bw * 0.10)}" result="tight"/>
      <feOffset in="tight" dx="${f(bw * 0.05)}" dy="${f(bw * 0.08)}" result="tightO"/>
      <feComposite in="tightO" in2="SourceAlpha" operator="out" result="contactMask"/>
      <feFlood flood-color="${shadowC}" flood-opacity="${f(shadowA * 0.9)}"/><feComposite in2="contactMask" operator="in" result="contact"/>
      <feOffset in="SourceAlpha" dx="${f(-bw * 0.06)}" dy="${f(-bw * 0.10)}" result="innerO"/>
      <feGaussianBlur in="innerO" stdDeviation="${f(bw * 0.10)}" result="innerB"/>
      <feComposite in="SourceAlpha" in2="innerB" operator="out" result="innerMask"/>
      <feFlood flood-color="${shadowC}" flood-opacity="${f(innerA * strength)}"/><feComposite in2="innerMask" operator="in" result="innerShade"/>
      <feOffset in="SourceAlpha" dx="${f(bw * 0.04)}" dy="${f(bw * 0.07)}" result="rimO"/>
      <feGaussianBlur in="rimO" stdDeviation="${f(bw * 0.06)}" result="rimB"/>
      <feComposite in="SourceAlpha" in2="rimB" operator="out" result="rimMask"/>
      <feFlood flood-color="#FFFFFF" flood-opacity="${f(rimA)}"/><feComposite in2="rimMask" operator="in" result="rim"/>
      <feMerge><feMergeNode in="shadow"/><feMergeNode in="light"/><feMergeNode in="contact"/><feMergeNode in="SourceGraphic"/><feMergeNode in="innerShade"/><feMergeNode in="rim"/></feMerge>
    </filter>
  </defs>
  <rect width="${W}" height="${H}" fill="${paper}"/>
  <rect width="${W}" height="${H}" fill="url(#paperLight)"/>
  <rect width="${W}" height="${H}" filter="url(#grain)"/>
  <g fill="url(#face)" filter="url(#relief)">${capsules(s, ox, oy)}</g>
</svg>
`;
}

function flat({ size, ink, paper, markFraction, tight }) {
  // tight: the SVG is the mark's own bounds (for embedding); else a square canvas.
  if (tight) {
    return `<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" width="${MARK_W}" height="${MARK_H}" viewBox="0 0 ${MARK_W} ${MARK_H}" role="img" aria-label="Speak It mark">
  ${paper ? `<rect width="${MARK_W}" height="${MARK_H}" fill="${paper}"/>` : ""}
  <g fill="${ink}">${capsules(1, 0, 0)}</g>
</svg>
`;
  }
  const s = size * markFraction / MARK_H, ox = (size - MARK_W * s) / 2, oy = (size - MARK_H * s) / 2;
  return `<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" width="${size}" height="${size}" viewBox="0 0 ${size} ${size}" role="img" aria-label="Speak It mark">
  <rect width="${size}" height="${size}" fill="${paper}"/>
  <g fill="${ink}">${capsules(s, ox, oy)}</g>
</svg>
`;
}

const files = [
  ["SpeakIt-Emboss-Light-4K.svg", emboss({ id: "light", size: 4096, dark: false }), 4096],
  ["SpeakIt-Emboss-Light-Strong-4K.svg", emboss({ id: "strong", size: 4096, dark: false, strength: 1.5 }), 4096],
  ["SpeakIt-Emboss-Dark-4K.svg", emboss({ id: "dark", size: 4096, dark: true }), 4096],
  ["SpeakIt-Emboss-Black-on-White-4K.svg", emboss({ id: "bow", size: 4096, dark: false, contrast: true }), 4096],
  ["SpeakIt-Emboss-White-on-Black-4K.svg", emboss({ id: "wob", size: 4096, dark: true, contrast: true }), 4096],
  ["SpeakIt-Emboss-Black-on-White-8K.svg", emboss({ id: "bow8", size: 8192, dark: false, contrast: true }), 8192],
  ["SpeakIt-Emboss-White-on-Black-8K.svg", emboss({ id: "wob8", size: 8192, dark: true, contrast: true }), 8192],
  ["SpeakIt-Emboss-Black-on-White-Icon-1024.svg", emboss({ id: "bowIcon", size: 1024, dark: false, contrast: true, markFraction: 0.56 }), 1024],
  ["SpeakIt-Emboss-White-on-Black-Icon-1024.svg", emboss({ id: "wobIcon", size: 1024, dark: true, contrast: true, markFraction: 0.56 }), 1024],
  ["SpeakIt-Emboss-Light-Icon-1024.svg", emboss({ id: "icon", size: 1024, dark: false, markFraction: 0.56, strength: 1.4 }), 1024],
  ["SpeakIt-Emboss-Dark-Icon-1024.svg", emboss({ id: "iconDark", size: 1024, dark: true, markFraction: 0.56 }), 1024],
  ["SpeakIt-Flat-Black-on-White-4K.svg", flat({ size: 4096, ink: "#0A0A0A", paper: "#FFFFFF", markFraction: 0.5 }), 4096],
  ["SpeakIt-Flat-White-on-Black-4K.svg", flat({ size: 4096, ink: "#FFFFFF", paper: "#0A0A0A", markFraction: 0.5 }), 4096],
  ["SpeakIt-Flat-Icon-White-on-Black-1024.svg", flat({ size: 1024, ink: "#FFFFFF", paper: "#0A0A0A", markFraction: 0.56 }), 1024],
  ["SpeakIt-Flat-Icon-Black-on-White-1024.svg", flat({ size: 1024, ink: "#0A0A0A", paper: "#FFFFFF", markFraction: 0.56 }), 1024],
  ["SpeakIt-Mark-Black.svg", flat({ ink: "#0A0A0A", tight: true }), 0],
  ["SpeakIt-Mark-White.svg", flat({ ink: "#FFFFFF", tight: true }), 0],
];
for (const [name, svg] of files) fs.writeFileSync(path.join(out, name), svg);

// Shipped files (the logo since 2026-09-04): the app icon and the site's social card.
const shipped = [
  [path.join(root, "SpeakIt/Assets.xcassets/AppIcon.appiconset/SpeakIt-AppIcon-1024.png"), emboss({ id: "app", size: 1024, dark: false, contrast: true, markFraction: 0.56 }), 1024, 1024],
  [path.join(root, "Website/assets/img/og.png"), emboss({ id: "og", width: 1200, height: 630, dark: false, contrast: true, markFraction: 0.5 }), 1200, 630],
];
const chrome = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";
if (fs.existsSync(chrome) && !process.argv.includes("--no-raster")) {
  const tmp = path.join(out, ".raster.html");
  for (const [name, , size] of files) {
    if (!size) continue;
    fs.writeFileSync(tmp, `<!doctype html><body style="margin:0"><img src="${name}" width="${size}" height="${size}" style="display:block"></body>`);
    execFileSync(chrome, ["--headless=new", "--disable-gpu", "--hide-scrollbars", `--screenshot=${path.join(out, name.replace(".svg", ".png"))}`, `--window-size=${size},${size}`, `file://${tmp}`], { stdio: "ignore" });
  }
  for (const [png, svg, w, h] of shipped) {
    fs.writeFileSync(tmp, `<!doctype html><body style="margin:0"><img src="data:image/svg+xml;base64,${Buffer.from(svg).toString("base64")}" width="${w}" height="${h}" style="display:block"></body>`);
    execFileSync(chrome, ["--headless=new", "--disable-gpu", "--hide-scrollbars", `--screenshot=${png}`, `--window-size=${w},${h}`, `file://${tmp}`], { stdio: "ignore" });
  }
  fs.unlinkSync(tmp);
}
console.log(`wrote ${files.length} SVGs (+ PNGs) to ${out}`);
