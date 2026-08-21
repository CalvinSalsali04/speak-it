import fs from "node:fs/promises";
import path from "node:path";
import { createRequire } from "node:module";

const require = createRequire(import.meta.url);
const sharp = require(
  "/Users/calvinwak/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/sharp",
);

const ROOT = path.resolve("Marketing/TikTokSlideshows");
const PHOTO = path.join(ROOT, "source_photos");
const OUTPUT = path.join(ROOT, "output");

const WIDTH = 1080;
const HEIGHT = 1920;
const INK = "#0E0E0E";
const PAPER = "#F8F8F6";
const MUTED = "#6B6B68";
const DIVIDER = "#D8D8D2";
const FONT = "Helvetica Neue, Helvetica, Arial, sans-serif";

const screens = {
  capture: path.resolve("Design/Screenshots/03-Capture.png"),
  today: path.resolve("Website/assets/img/01-Today-v2.png"),
  memory: path.resolve("Website/assets/img/02-Memory-v2.png"),
  icon: path.resolve("SpeakIt/Assets.xcassets/AppIcon.appiconset/SpeakIt-AppIcon-1024.png"),
};

const concepts = [
  {
    id: "01-late-night-thought",
    title: "The thought that arrives at the worst time",
    photos: {
      start: "c1-night-ceiling.png",
      detail: "c1-bedside-dawn.png",
      close: "c1-bedside-dawn.png",
    },
    captionA:
      "I needed a brain dump app that worked before I was awake enough to organize anything. Speak It lets me say the thought first, then separates what belongs in Today from what belongs in Memory. Follow for the iPhone launch.",
    captionB:
      "My productivity problem was not planning. It was capturing a thought before the ‘where should I put this?’ decision erased it. This is the one-tap voice capture flow I built for iPhone.",
    hashtags: "#braindump #productivitytips #iphoneapps #memorytips",
    variants: {
      A: [
        "my best idea this week showed up at 1:43 a.m.",
        "by morning, I could only remember that it was ‘really good’",
        "so now I tap once and say the whole messy thought",
        "no formatting. no choosing a list. no trying to sound organized.",
        "things I need to do show up in Today",
        "ideas and details I want later stay in Memory",
        "for thoughts that refuse to wait until morning.",
      ],
      B: [
        "my brain only remembers important things when my hands are full",
        "if saving it takes more than one step, the thought is gone",
        "this is why I replaced the ‘which app?’ decision with one button",
        "I say the task, idea, or reminder exactly how it arrived",
        "action words and times land in Today",
        "useful notes, people, and ideas stay searchable in Memory",
        "one place to say it before it disappears.",
      ],
    },
    slides: ["cover", "lifestyle", "screen:capture", "quote", "screen:today", "screen:memory", "closing"],
  },
  {
    id: "02-remember-people",
    title: "The tiny personal detail that actually matters",
    photos: {
      start: "c2-coffee-table.png",
      detail: "c2-coffee-hand.png",
      close: "c2-coffee-table.png",
    },
    captionA:
      "A reminder app can tell me to buy coffee. I wanted somewhere to remember how someone actually takes it. Speak It keeps quick people-details in Memory so I can find them later.",
    captionB:
      "This is my answer to ‘where do I save tiny details about people?’ I say them naturally, Speak It preserves the original wording, and Memory makes them searchable later.",
    hashtags: "#memorytips #thoughtful #iphoneapps #productivityapp",
    variants: {
      A: [
        "I forgot the one detail that would’ve made me look thoughtful",
        "Daniel said ‘oat milk, not soy.’ I knew I’d forget.",
        "so I quietly said: ‘Daniel takes oat milk, not soy’",
        "I did not stop the conversation to make a perfect note",
        "later, Memory had: ‘Daniel prefers oat milk’",
        "next coffee run, I remembered—without pretending I have a perfect memory",
        "Speak It helps me remember people, not just tasks.",
      ],
      B: [
        "the smallest things are always what I forget about people",
        "birthdays go in calendars. the little preferences have nowhere to go.",
        "when someone mentions one, I say it into Speak It immediately",
        "it keeps my original words, even after it tidies the result",
        "names, preferences, ideas, and useful facts live together in Memory",
        "I can search the person later instead of scrolling through random notes",
        "remember the detail while it still means something.",
      ],
    },
    slides: ["cover", "lifestyle", "quote", "screen:capture", "screen:memoryDetail", "lifestyle", "closing"],
  },
  {
    id: "03-capture-before-organizing",
    title: "My productivity system was the friction",
    photos: {
      start: "c3-messy-desk.png",
      detail: "c3-messy-desk.png",
      calm: "c3-calm-desk.png",
      close: "c3-calm-desk.png",
    },
    captionA:
      "I did not need another complicated productivity system. I needed a faster front door. Speak It captures the sentence in my own words, then routes action to Today and useful knowledge to Memory.",
    captionB:
      "A voice capture app for the moment before your planner, calendar, and notes system. One tap, say it, find the result in Today or Memory.",
    hashtags: "#productivitysystem #workflow #iphoneapps #productivitytips",
    variants: {
      A: [
        "my productivity system was making me forget more",
        "every thought started with: note, task, event, person, or idea?",
        "by the time I chose, half the sentence was gone",
        "Speak It lets me capture first and decide nothing",
        "if it needs action, I see it in Today",
        "if it is worth keeping, I find it in Memory",
        "the best system is the one I can use mid-thought.",
      ],
      B: [
        "before: 4 apps just to save one thought",
        "note? reminder? calendar? message myself?",
        "after: tap one button and say the entire thing",
        "Speak It handles the first sorting pass after I finish speaking",
        "tasks, reminders, and follow-ups → Today",
        "ideas, people, and useful context → Memory",
        "one capture door instead of four.",
      ],
    },
    slides: ["cover", "lifestyle", "lifestyle:calm", "screen:capture", "screen:today", "screen:memory", "closing"],
  },
  {
    id: "04-chaotic-brain-dump",
    title: "One chaotic thought, several useful results",
    photos: {
      start: "c4-bathroom-rush.png",
      detail: "c4-grocery-hands.png",
      close: "c4-grocery-hands.png",
    },
    captionA:
      "My brain dumps never arrive one neat item at a time. Speak It can take one natural capture, preserve what I said, and separate the actions from the knowledge I may need later.",
    captionB:
      "The voice note is messy because real thoughts are messy. The useful part is what happens after: Today for action, Memory for everything worth finding again.",
    hashtags: "#braindump #busymind #productivitytips #iphoneapp",
    variants: {
      A: [
        "POV: your brain gives you five important thoughts while brushing your teeth",
        "call Mum. buy toothpaste. bins when I get home. Daniel hates soy. new project idea.",
        "typing that list is not happening",
        "I just speak naturally and pause when I’m done",
        "the things with an action became tasks and reminders",
        "the person-detail and idea went to Memory",
        "brain dump in. organized thoughts out.",
      ],
      B: [
        "my brain waited until both hands were busy to remember everything",
        "pharmacy at six. reply to Priya. parking level 3. book dentist. podcast idea.",
        "I said the whole chaotic sentence in one go",
        "no keywords. no commands. no stopping to label each part.",
        "calls, errands, and appointments landed in Today",
        "the parking detail and idea stayed in Memory",
        "say the messy version. keep the useful version.",
      ],
    },
    slides: ["coverByVariant", "lifestyle", "screen:capture", "quote", "screen:today", "screen:memory", "closing"],
  },
  {
    id: "05-no-account",
    title: "A quieter place for my thoughts",
    photos: {
      start: "c5-signup-fatigue.png",
      detail: "c5-signup-fatigue.png",
      close: "c5-park-bench.png",
    },
    captionA:
      "No profile, email, or sign-in is required for Speak It. I wanted the first experience to be capturing a real thought—not filling out another account form.",
    captionB:
      "Speak It is designed to keep your thought library on your iPhone. Optional iCloud Sync uses your private iCloud container. Speech transcription uses Apple’s Speech framework and may use an internet connection depending on the device and language; the privacy page explains the details.",
    hashtags: "#digitalprivacy #iphoneapps #minimalapps #productivityapp",
    variants: {
      A: [
        "I stopped giving apps my email just to save a thought",
        "I wanted to open it, say something, and leave",
        "Speak It does not require an account",
        "I tap, speak, and the original wording is preserved",
        "actions still become easy to see in Today",
        "ideas, people, and facts stay findable in Memory",
        "calm capture. no account.",
      ],
      B: [
        "I wanted a memory app that didn’t treat my thoughts like content",
        "my tasks and half-formed ideas are more personal than they look",
        "Speak It stores the thought library on my iPhone",
        "it organizes a useful result without deleting what I actually said",
        "I keep control: review, edit, complete, archive, or delete",
        "optional iCloud Sync uses my own iCloud when I choose it",
        "my words, still mine.",
      ],
    },
    slides: ["cover", "lifestyle", "welcome", "screen:capture", "screen:today", "screen:memory", "closing"],
  },
];

function esc(value) {
  return String(value)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;");
}

function splitLongWord(word, limit) {
  if (word.length <= limit) return [word];
  const chunks = [];
  for (let index = 0; index < word.length; index += limit) {
    chunks.push(word.slice(index, index + limit));
  }
  return chunks;
}

function wrap(text, width, fontSize, maxLines = 8) {
  const averageWidth = fontSize * 0.53;
  const charLimit = Math.max(8, Math.floor(width / averageWidth));
  const words = text
    .split(/\s+/)
    .flatMap((word) => splitLongWord(word, Math.max(10, charLimit - 2)));
  const lines = [];
  let current = "";
  for (const word of words) {
    const next = current ? `${current} ${word}` : word;
    if (next.length > charLimit && current) {
      lines.push(current);
      current = word;
    } else {
      current = next;
    }
  }
  if (current) lines.push(current);
  if (lines.length > maxLines) {
    const kept = lines.slice(0, maxLines);
    kept[maxLines - 1] = `${kept[maxLines - 1].replace(/[. ]+$/, "")}…`;
    return kept;
  }
  return lines;
}

function textBlock({
  text,
  x,
  y,
  width,
  fontSize,
  color = "#FFFFFF",
  weight = 700,
  lineHeight = 1.08,
  maxLines = 8,
  anchor = "start",
  letterSpacing = 0,
}) {
  const lines = wrap(text, width, fontSize, maxLines);
  const tspans = lines
    .map(
      (line, index) =>
        `<tspan x="${x}" dy="${index === 0 ? 0 : Math.round(fontSize * lineHeight)}">${esc(line)}</tspan>`,
    )
    .join("");
  return `<text x="${x}" y="${y}" text-anchor="${anchor}" font-family="${FONT}" font-size="${fontSize}" font-weight="${weight}" letter-spacing="${letterSpacing}" fill="${color}">${tspans}</text>`;
}

function progressSvg(current, color = "#FFFFFF") {
  const dots = Array.from({ length: 7 }, (_, index) => {
    const active = index + 1 === current;
    return `<rect x="${378 + index * 48}" y="94" width="${active ? 34 : 20}" height="10" rx="5" fill="${color}" opacity="${active ? 1 : 0.34}"/>`;
  }).join("");
  return svgBuffer(dots);
}

function svgBuffer(body, definitions = "") {
  return Buffer.from(
    `<svg width="${WIDTH}" height="${HEIGHT}" viewBox="0 0 ${WIDTH} ${HEIGHT}" xmlns="http://www.w3.org/2000/svg"><defs>${definitions}</defs>${body}</svg>`,
  );
}

async function photoBuffer(file, options = {}) {
  let image = sharp(path.join(PHOTO, file)).resize(WIDTH, HEIGHT, {
    fit: "cover",
    position: options.position ?? "centre",
  });
  if (options.blur) image = image.blur(options.blur);
  if (options.brightness || options.saturation) {
    image = image.modulate({
      brightness: options.brightness ?? 1,
      saturation: options.saturation ?? 1,
    });
  }
  return image.png().toBuffer();
}

async function roundedImage(buffer, width, height, radius = 44) {
  const mask = Buffer.from(
    `<svg width="${width}" height="${height}" xmlns="http://www.w3.org/2000/svg"><rect width="${width}" height="${height}" rx="${radius}" fill="white"/></svg>`,
  );
  return sharp(buffer)
    .resize(width, height, { fit: "cover" })
    .composite([{ input: mask, blend: "dest-in" }])
    .png()
    .toBuffer();
}

function coverOverlay(text, current = 1) {
  const length = text.length;
  const fontSize = length > 72 ? 69 : length > 58 ? 76 : 84;
  const body = [
    `<rect width="1080" height="1920" fill="url(#coverFade)"/>`,
    `<text x="80" y="210" font-family="${FONT}" font-size="25" font-weight="700" letter-spacing="3.5" fill="#FFFFFF" opacity=".78">A REAL THOUGHT</text>`,
    textBlock({ text, x: 80, y: 350, width: 890, fontSize, maxLines: 6, lineHeight: 1.06 }),
    `<g transform="translate(80 1500)"><rect width="188" height="60" rx="30" fill="#FFFFFF" fill-opacity=".16" stroke="#FFFFFF" stroke-opacity=".38"/><text x="94" y="39" text-anchor="middle" font-family="${FONT}" font-size="25" font-weight="700" fill="#FFFFFF">SWIPE →</text></g>`,
  ].join("");
  const defs = `<linearGradient id="coverFade" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#000" stop-opacity=".55"/><stop offset=".58" stop-color="#000" stop-opacity=".25"/><stop offset="1" stop-color="#000" stop-opacity=".72"/></linearGradient>`;
  return [svgBuffer(body, defs), progressSvg(current)];
}

async function renderCover(photo, text, destination) {
  const base = await photoBuffer(photo);
  const [overlay, progress] = coverOverlay(text);
  await sharp(base).composite([{ input: overlay }, { input: progress }]).png().toFile(destination);
}

function paperCardSvg(text, current, options = {}) {
  const dark = options.dark ?? true;
  const y = options.y ?? 235;
  const width = 920;
  const padding = 58;
  const fontSize = text.length > 90 ? 53 : text.length > 64 ? 59 : 66;
  const lines = wrap(text, width - padding * 2, fontSize, 6);
  const cardHeight = Math.max(280, 116 + lines.length * Math.round(fontSize * 1.08));
  const fill = dark ? "#111111" : PAPER;
  const color = dark ? "#FFFFFF" : INK;
  const body = [
    `<rect x="80" y="${y}" width="${width}" height="${cardHeight}" rx="42" fill="${fill}" fill-opacity="${dark ? 0.91 : 0.96}" stroke="${dark ? "#FFFFFF" : DIVIDER}" stroke-opacity=".2"/>`,
    `<text x="${80 + padding}" y="${y + 70}" font-family="${FONT}" font-size="23" font-weight="700" letter-spacing="3" fill="${dark ? "#FFFFFF" : MUTED}" opacity=".72">THE PART I NEEDED TO KEEP</text>`,
    textBlock({
      text,
      x: 80 + padding,
      y: y + 145,
      width: width - padding * 2,
      fontSize,
      color,
      weight: 700,
      maxLines: 6,
      lineHeight: 1.08,
    }),
  ].join("");
  return [svgBuffer(body), progressSvg(current, dark ? "#FFFFFF" : INK)];
}

async function renderLifestyle(photo, text, current, destination, position = "centre") {
  const base = await photoBuffer(photo, { position });
  const shade = svgBuffer(`<rect width="1080" height="1920" fill="url(#shade)"/>`, `<linearGradient id="shade" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#000" stop-opacity=".25"/><stop offset=".68" stop-color="#000" stop-opacity=".08"/><stop offset="1" stop-color="#000" stop-opacity=".38"/></linearGradient>`);
  const [card, progress] = paperCardSvg(text, current);
  await sharp(base)
    .composite([{ input: shade }, { input: card }, { input: progress }])
    .png()
    .toFile(destination);
}

function quoteSvg(text, current) {
  const fontSize = text.length > 82 ? 52 : text.length > 58 ? 59 : 66;
  const body = [
    `<rect width="1080" height="1920" fill="#000000" fill-opacity=".42"/>`,
    `<rect x="72" y="265" width="936" height="1040" rx="54" fill="${PAPER}"/>`,
    `<g transform="translate(130 350)"><circle cx="58" cy="58" r="58" fill="${INK}"/><rect x="29" y="51" width="8" height="20" rx="4" fill="white"/><rect x="45" y="37" width="8" height="48" rx="4" fill="white"/><rect x="61" y="23" width="8" height="76" rx="4" fill="white"/><rect x="77" y="37" width="8" height="48" rx="4" fill="white"/></g>`,
    `<text x="130" y="535" font-family="${FONT}" font-size="23" font-weight="700" letter-spacing="3.4" fill="${MUTED}">SAID OUT LOUD</text>`,
    textBlock({ text, x: 130, y: 650, width: 820, fontSize, color: INK, weight: 700, lineHeight: 1.1, maxLines: 7 }),
    `<line x1="130" y1="1135" x2="950" y2="1135" stroke="${DIVIDER}" stroke-width="2"/>`,
    `<text x="130" y="1205" font-family="${FONT}" font-size="28" font-weight="500" fill="${MUTED}">Speak It keeps the original wording.</text>`,
  ].join("");
  return [svgBuffer(body), progressSvg(current, "#FFFFFF")];
}

async function renderQuote(photo, text, current, destination) {
  const base = await photoBuffer(photo, { blur: 14, brightness: 0.72, saturation: 0.75 });
  const [overlay, progress] = quoteSvg(text, current);
  await sharp(base).composite([{ input: overlay }, { input: progress }]).png().toFile(destination);
}

const cropSpecs = {
  capture: { file: "capture", crop: { left: 0, top: 0, width: 1260, height: 2736 }, width: 690, y: 380 },
  today: { file: "today", crop: { left: 0, top: 0, width: 1320, height: 2460 }, width: 770, y: 430 },
  memory: { file: "memory", crop: { left: 0, top: 0, width: 1320, height: 2520 }, width: 770, y: 420 },
  memoryDetail: { file: "memory", crop: { left: 0, top: 1280, width: 1320, height: 1450 }, width: 860, y: 720 },
};

async function preparedScreen(kind) {
  const spec = cropSpecs[kind];
  const source = screens[spec.file];
  const cropped = await sharp(source).extract(spec.crop).resize({ width: spec.width }).png().toBuffer();
  const metadata = await sharp(cropped).metadata();
  return {
    buffer: await roundedImage(cropped, metadata.width, metadata.height, 48),
    width: metadata.width,
    height: metadata.height,
    y: spec.y,
  };
}

function screenTextSvg(text, current) {
  const fontSize = text.length > 88 ? 43 : text.length > 70 ? 47 : text.length > 54 ? 51 : 57;
  const lines = wrap(text, 830, fontSize, 5);
  const lineStep = Math.round(fontSize * 1.07);
  const cardHeight = Math.max(260, 180 + lines.length * lineStep);
  const textTspans = lines
    .map(
      (line, index) =>
        `<tspan x="122" dy="${index === 0 ? 0 : lineStep}">${esc(line)}</tspan>`,
    )
    .join("");
  const body = [
    `<rect width="1080" height="1920" fill="#000000" fill-opacity=".34"/>`,
    `<rect x="72" y="150" width="936" height="${cardHeight}" rx="42" fill="${PAPER}" fill-opacity=".97"/>`,
    `<text x="122" y="217" font-family="${FONT}" font-size="22" font-weight="700" letter-spacing="3" fill="${MUTED}">WHAT HAPPENS NEXT</text>`,
    `<text x="122" y="295" font-family="${FONT}" font-size="${fontSize}" font-weight="700" fill="${INK}">${textTspans}</text>`,
  ].join("");
  return [svgBuffer(body), progressSvg(current, "#FFFFFF"), 150 + cardHeight];
}

async function renderScreen(photo, kind, text, current, destination) {
  const base = await photoBuffer(photo, { blur: 20, brightness: 0.58, saturation: 0.68 });
  const prepared = await preparedScreen(kind);
  const [copy, progress, copyBottom] = screenTextSvg(text, current);
  const panelY = Math.max(prepared.y, copyBottom + 24);
  const availableHeight = 1810 - panelY;
  let panel = prepared.buffer;
  let panelWidth = prepared.width;
  let panelHeight = prepared.height;
  if (panelHeight > availableHeight) {
    panel = await sharp(panel).resize({ height: availableHeight }).png().toBuffer();
    const metadata = await sharp(panel).metadata();
    panelWidth = metadata.width;
    panelHeight = metadata.height;
  }
  const panelX = Math.round((WIDTH - panelWidth) / 2);
  const shadow = svgBuffer(
    `<rect x="${panelX - 12}" y="${panelY - 8}" width="${panelWidth + 24}" height="${panelHeight + 28}" rx="60" fill="#000" fill-opacity=".45" filter="url(#blur)"/>`,
    `<filter id="blur"><feGaussianBlur stdDeviation="20"/></filter>`,
  );
  await sharp(base)
    .composite([
      { input: shadow },
      { input: panel, left: panelX, top: panelY },
      { input: copy },
      { input: progress },
    ])
    .png()
    .toFile(destination);
}

function welcomeSvg(text, current) {
  const fontSize = text.length > 56 ? 56 : 64;
  const body = [
    `<rect width="1080" height="1920" fill="#000" fill-opacity=".38"/>`,
    `<rect x="72" y="220" width="936" height="1250" rx="60" fill="${PAPER}"/>`,
    `<text x="130" y="315" font-family="${FONT}" font-size="24" font-weight="700" letter-spacing="3.3" fill="${MUTED}">NO ACCOUNT</text>`,
    `<g transform="translate(385 405)"><circle cx="155" cy="155" r="155" fill="${INK}"/><rect x="92" y="145" width="14" height="34" rx="7" fill="white"/><rect x="121" y="115" width="14" height="94" rx="7" fill="white"/><rect x="150" y="80" width="14" height="164" rx="7" fill="white"/><rect x="179" y="115" width="14" height="94" rx="7" fill="white"/><rect x="208" y="145" width="14" height="34" rx="7" fill="white"/></g>`,
    `<text x="540" y="865" text-anchor="middle" font-family="${FONT}" font-size="38" font-weight="650" letter-spacing="-.5" fill="${INK}">Speak It</text>`,
    textBlock({ text, x: 130, y: 1015, width: 820, fontSize, color: INK, weight: 700, lineHeight: 1.08, maxLines: 4 }),
    `<line x1="130" y1="1300" x2="950" y2="1300" stroke="${DIVIDER}" stroke-width="2"/>`,
    `<text x="130" y="1370" font-family="${FONT}" font-size="29" font-weight="500" fill="${MUTED}">Open it. Say it. Keep moving.</text>`,
  ].join("");
  return [svgBuffer(body), progressSvg(current, "#FFFFFF")];
}

async function renderWelcome(photo, text, current, destination) {
  const base = await photoBuffer(photo, { blur: 17, brightness: 0.68, saturation: 0.7 });
  const [overlay, progress] = welcomeSvg(text, current);
  await sharp(base).composite([{ input: overlay }, { input: progress }]).png().toFile(destination);
}

async function renderClosing(photo, text, current, destination) {
  const base = await photoBuffer(photo);
  const icon = await roundedImage(await sharp(screens.icon).resize(180, 180).png().toBuffer(), 180, 180, 42);
  const fontSize = text.length > 56 ? 58 : 67;
  const overlay = svgBuffer(
    [
      `<rect width="1080" height="1920" fill="url(#closeFade)"/>`,
      `<text x="290" y="1168" font-family="${FONT}" font-size="55" font-weight="700" fill="#FFFFFF">Speak It</text>`,
      `<text x="290" y="1214" font-family="${FONT}" font-size="24" font-weight="650" letter-spacing="2.5" fill="#FFFFFF" opacity=".72">FOR IPHONE</text>`,
      textBlock({ text, x: 80, y: 1320, width: 900, fontSize, color: "#FFFFFF", weight: 700, lineHeight: 1.08, maxLines: 4 }),
      `<rect x="80" y="1540" width="520" height="86" rx="43" fill="#FFFFFF"/>`,
      `<text x="340" y="1596" text-anchor="middle" font-family="${FONT}" font-size="28" font-weight="700" fill="${INK}">FOLLOW FOR THE LAUNCH</text>`,
    ].join(""),
    `<linearGradient id="closeFade" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#000" stop-opacity=".1"/><stop offset=".5" stop-color="#000" stop-opacity=".32"/><stop offset="1" stop-color="#000" stop-opacity=".88"/></linearGradient>`,
  );
  await sharp(base)
    .composite([
      { input: overlay },
      { input: icon, left: 80, top: 1060 },
      { input: progressSvg(current) },
    ])
    .png()
    .toFile(destination);
}

function resolvePhoto(concept, variant, type, slideIndex) {
  if (type === "coverByVariant") {
    return variant === "A" ? concept.photos.start : concept.photos.detail;
  }
  if (type === "lifestyle:calm") return concept.photos.calm;
  if (type === "cover") return concept.photos.start;
  if (type === "closing") return concept.photos.close;
  if (type === "quote") return concept.photos.detail;
  if (type.startsWith("screen:")) return slideIndex % 2 === 0 ? concept.photos.start : concept.photos.detail;
  return concept.photos.detail;
}

async function renderSlide(concept, variant, slideIndex, destination) {
  const type = concept.slides[slideIndex];
  const text = concept.variants[variant][slideIndex];
  const current = slideIndex + 1;
  const photo = resolvePhoto(concept, variant, type, slideIndex);

  if (type === "cover" || type === "coverByVariant") {
    await renderCover(photo, text, destination);
  } else if (type === "lifestyle" || type === "lifestyle:calm") {
    await renderLifestyle(photo, text, current, destination);
  } else if (type === "quote") {
    await renderQuote(photo, text, current, destination);
  } else if (type === "welcome") {
    await renderWelcome(photo, text, current, destination);
  } else if (type === "closing") {
    await renderClosing(photo, text, current, destination);
  } else if (type.startsWith("screen:")) {
    await renderScreen(photo, type.split(":")[1], text, current, destination);
  } else {
    throw new Error(`Unknown slide type: ${type}`);
  }
}

async function ensureEmptyOutput() {
  await fs.mkdir(OUTPUT, { recursive: true });
  const entries = await fs.readdir(OUTPUT, { withFileTypes: true });
  for (const entry of entries) {
    if (!entry.isDirectory() || !/^\d{2}-/.test(entry.name)) continue;
    const folder = path.join(OUTPUT, entry.name);
    const children = await fs.readdir(folder, { withFileTypes: true });
    for (const child of children) {
      if (!child.isDirectory() || !/^[AB]$/.test(child.name)) continue;
      const variantFolder = path.join(folder, child.name);
      for (const file of await fs.readdir(variantFolder)) {
        if (/^slide-\d{2}\.png$/.test(file) || file === "caption.txt") {
          await fs.unlink(path.join(variantFolder, file));
        }
      }
    }
  }
}

async function createContactSheet(folder, label) {
  const thumbWidth = 252;
  const thumbHeight = 448;
  const gap = 14;
  const headerHeight = 104;
  const canvasHeight = headerHeight + thumbHeight * 2 + gap * 3;
  const composites = [];
  for (let index = 0; index < 7; index += 1) {
    const thumb = await sharp(path.join(folder, `slide-${String(index + 1).padStart(2, "0")}.png`))
      .resize(thumbWidth, thumbHeight, { fit: "cover" })
      .png()
      .toBuffer();
    const column = index < 4 ? index : index - 4;
    const row = index < 4 ? 0 : 1;
    composites.push({
      input: thumb,
      left: gap + column * (thumbWidth + gap),
      top: headerHeight + gap + row * (thumbHeight + gap),
    });
  }
  const header = Buffer.from(
    `<svg width="1080" height="${canvasHeight}" xmlns="http://www.w3.org/2000/svg"><rect width="1080" height="${canvasHeight}" fill="#E9E9E5"/><text x="28" y="62" font-family="${FONT}" font-size="34" font-weight="700" fill="${INK}">${esc(label)}</text><text x="1050" y="61" text-anchor="end" font-family="${FONT}" font-size="22" font-weight="600" fill="${MUTED}">7 SLIDES · 1080 × 1920</text></svg>`,
  );
  await sharp({ create: { width: 1080, height: canvasHeight, channels: 4, background: "#E9E9E5" } })
    .composite([{ input: header }, ...composites])
    .png()
    .toFile(path.join(folder, "contact-sheet.png"));
}

async function createMasterPreview() {
  const previewWidth = 520;
  const previewHeight = 490;
  const gap = 20;
  const headerHeight = 110;
  const canvasHeight = headerHeight + previewHeight * 5 + gap * 6;
  const composites = [];
  let index = 0;
  for (const concept of concepts) {
    for (const variant of ["A", "B"]) {
      const contact = path.join(OUTPUT, concept.id, variant, "contact-sheet.png");
      const preview = await sharp(contact)
        .resize(previewWidth, previewHeight, { fit: "cover", position: "top" })
        .png()
        .toBuffer();
      composites.push({
        input: preview,
        left: index % 2 === 0 ? gap : previewWidth + gap * 2,
        top: headerHeight + gap + Math.floor(index / 2) * (previewHeight + gap),
      });
      index += 1;
    }
  }
  const header = Buffer.from(
    `<svg width="1080" height="${canvasHeight}" xmlns="http://www.w3.org/2000/svg"><rect width="1080" height="${canvasHeight}" fill="#E9E9E5"/><text x="28" y="62" font-family="${FONT}" font-size="38" font-weight="700" fill="${INK}">Speak It · TikTok UGC Slideshows</text><text x="1052" y="62" text-anchor="end" font-family="${FONT}" font-size="22" font-weight="600" fill="${MUTED}">10 SETS · 70 SLIDES</text></svg>`,
  );
  await sharp({ create: { width: 1080, height: canvasHeight, channels: 4, background: "#E9E9E5" } })
    .composite([{ input: header }, ...composites])
    .png()
    .toFile(path.join(OUTPUT, "preview-all.png"));
}

async function main() {
  await ensureEmptyOutput();
  const index = [];
  for (const concept of concepts) {
    for (const variant of ["A", "B"]) {
      const folder = path.join(OUTPUT, concept.id, variant);
      await fs.mkdir(folder, { recursive: true });
      for (let slideIndex = 0; slideIndex < 7; slideIndex += 1) {
        const destination = path.join(folder, `slide-${String(slideIndex + 1).padStart(2, "0")}.png`);
        await renderSlide(concept, variant, slideIndex, destination);
      }
      await createContactSheet(folder, `${concept.id} · VARIATION ${variant}`);
      const caption = `${variant === "A" ? concept.captionA : concept.captionB}\n\n${concept.hashtags}\n`;
      await fs.writeFile(path.join(folder, "caption.txt"), caption, "utf8");
      index.push({
        concept: concept.id,
        title: concept.title,
        variant,
        folder: path.relative(ROOT, folder),
        hook: concept.variants[variant][0],
      });
    }
  }
  await createMasterPreview();
  await fs.writeFile(path.join(OUTPUT, "index.json"), `${JSON.stringify(index, null, 2)}\n`, "utf8");
  console.log(`Rendered ${index.length * 7} slides across ${index.length} slideshow folders.`);
}

await main();
