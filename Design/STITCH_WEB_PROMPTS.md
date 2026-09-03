# Google Stitch — Speak It download site (Web mode)

Goal: a responsive marketing site that **demonstrates the app** and **drives App Store
downloads** (badge on desktop, QR code for hand-off to phone), in the same visual
language as the iOS app.

Companion screenshots live in `Design/Screenshots/` — attach them in Stitch.

---

## Before you prompt

1. Switch the composer to **Web** (not App).
2. Model: **Thinking with 3.1 Pro** for the first generation of each section. **3 Flash** to iterate.
3. Click the **paperclip / +** and attach `01-Today.png`, `02-Memory.png`, `03-Capture.png`.
   Stitch reads them for style, palette, and product truth.
4. Set the palette explicitly with the **palette icon**: background `#F8F8F6`,
   surface `#FFFFFF`, text `#0E0E0E`, secondary `#6B6B6B`, border `#D6D6D6`.

**Honest limitation:** Stitch will *not* embed your PNGs pixel-perfect in its output. It
generates its own placeholder imagery. So the prompts below tell it to reserve
correctly-proportioned image slots with visible labels; you swap in the real files after
export. Attaching the screenshots still matters — it's what keeps the generated site
monochrome and calm instead of a purple-gradient SaaS template.

---

## STYLE BLOCK (prepend to every section prompt)

```
Design a responsive marketing website for "Speak It", an iPhone app for capturing
thoughts by voice before you forget them. The site's only jobs are to demonstrate the
app and get the visitor to download it from the App Store.

The site must inherit the app's visual language exactly:
- Background #F8F8F6 (warm off-white). Cards/surfaces #FFFFFF. Primary text #0E0E0E.
  Secondary text #6B6B6B. Hairline borders #D6D6D6 at 1px.
- Dark sections invert to: background #090909, surface #161616, text #FFFFFF,
  secondary #A3A3A3, borders #2E2E2E.
- NO brand accent color. No purple, no blue, no gradient. Emphasis comes only from
  type weight, scale, and whitespace. The single permitted accent is a muted brick red
  #B3382E, used at most once on the whole page.
- Typography: a clean geometric/neutral sans (Inter or SF Pro style). Huge, confident
  headlines with tight letter-spacing. Body copy at generous line-height (1.6).
- Corner radius 14px on cards, 999px on buttons and pills. NO drop shadows.
  NO glassmorphism. NO 3D. NO stock photography of people. NO emoji. NO illustrations
  of robots or AI brains.
- Layout: max content width 1120px, centered, with very generous vertical section
  padding (120px desktop / 64px mobile). Let it breathe — whitespace is the brand.
- Fully responsive: 1440 / 1024 / 768 / 375. Nothing may scroll horizontally.

Tone of voice: calm, plain, declarative. Short sentences. Never hype, never exclamation
marks, never "revolutionary" or "AI-powered" or "supercharge".
```

---

## 1. Hero — with QR code and App Store badge

```
[STYLE BLOCK]

Build the hero section.

Left column (55% width on desktop):
- A small uppercase letter-spaced eyebrow in #6B6B6B: "iPHONE · LOCAL-FIRST".
- Headline, very large (72px desktop / 40px mobile), weight 600, max two lines:
  "Say it before you forget it."
- Subhead in #6B6B6B, 20px, max 60 characters per line:
  "Speak naturally. Speak It saves your exact words, organizes them, and brings them
  back when they matter."
- A download row containing, side by side:
  1. A black "Download on the App Store" badge button, 160px wide.
  2. A vertical hairline divider.
  3. A QR code block: a 104x104px black-on-white QR code with a 1px #D6D6D6 border and
     14px radius, and to its right, two stacked lines — "Scan to install" in #0E0E0E
     medium weight, and "Opens the App Store on your iPhone" in 13px #6B6B6B.
  On screens under 768px, HIDE the QR code entirely and show only the App Store badge
  at full width.
- Below that, one 13px #6B6B6B line: "Free to start · 10 captures a month · No account required."

Right column (45%):
- A single realistic iPhone 15 Pro frame, thin dark bezel, no hand holding it, no
  floating angle, no shadow — perfectly upright and centered.
- Inside the frame, a placeholder image slot labeled "SCREENSHOT: 03-Capture.png"
  with a 9:19.5 aspect ratio.

Background #F8F8F6. No hero background image, no gradient mesh, no dot grid.
Header nav above the hero: the wordmark "Speak It" on the left in 18px weight 600, and
on the right three text links — "How it works", "Privacy", "Pricing" — plus a small
pill button "Download". The nav is transparent over the background with a 1px bottom
hairline that appears only after scroll.
```

**Follow-ups:**
- `The QR code is decorative-looking. Make it a real high-contrast square QR pattern, pure #0E0E0E on #FFFFFF, sharp edges, no rounded dots, no logo in the center.`
- `Reduce the headline to 64px and increase the space between the subhead and the download row to 40px.`

---

## 2. "How it works" — the three beats

```
[STYLE BLOCK]

Build a three-step section that mirrors the app's own model.

- Centered section heading, 40px weight 600: "Three seconds from thought to saved."
- Beneath it, one #6B6B6B line: "You talk. Speak It does the filing."
- Three equal columns, separated by 1px #D6D6D6 vertical hairlines on desktop
  (stacked with horizontal hairlines under 768px). Each column contains:
  - A large thin monochrome line icon, 40px, stroke 1.5px.
  - A step number in 13px #6B6B6B, letter-spaced: "01" / "02" / "03".
  - A title in 22px weight 600.
  - Two lines of #6B6B6B body copy.

  Column 1 — waveform icon — "Speak" —
  "Tap once and say the thought out loud. Your exact words are saved first, before
  anything is interpreted."
  Column 2 — concentric-rings icon — "Organized" —
  "Speak It separates distinct thoughts and sorts each one into Today or Memory,
  with a due date if you mentioned one."
  Column 3 — soft-ring icon — "Remembered" —
  "Actions surface in Today. Ideas, people, and facts wait in Memory until you search
  for them."

No cards, no boxes, no numbered circles with fills. Just type, hairlines, and space.
```

---

## 3. Product demonstration — the part that shows the app

This is the section the visitor came for. Two options; try A first.

**A. Scroll-synced phone (recommended)**

```
[STYLE BLOCK]

Build a "See it work" section, full-bleed on the dark palette
(#090909 background, #FFFFFF text).

Layout: a two-column sticky scroll section, 200vh tall on desktop.
- The RIGHT column holds a single upright iPhone frame that stays sticky and vertically
  centered while the left column scrolls past it.
- The LEFT column contains three stacked text blocks, each 100vh, vertically centered,
  each with a 28px weight 600 title and two lines of #A3A3A3 body copy:

  Block 1 — "Capture without deciding" —
  "No folders, no tags, no forms. Say it and it is safe. The original recording's exact
  wording is never overwritten."
  Block 2 — "Today is only what you can act on" —
  "Overdue, scheduled, and ready-when-you-have-time — each section states its own rule
  so nothing hides."
  Block 3 — "Memory is what you'll want later" —
  "Ideas, people, and reference facts, searchable by the words you actually said."

- As each block becomes active, the phone screen crossfades to the matching screenshot.
  Reserve three labeled image slots at 9:19.5:
  "SCREENSHOT: 03-Capture.png", "SCREENSHOT: 01-Today.png", "SCREENSHOT: 02-Memory.png".
- Show a thin 2px vertical progress indicator in #2E2E2E on the far left of the text
  column, with the active segment in #FFFFFF.

Under 768px: drop the sticky behavior entirely. Stack each text block directly above
its own phone screenshot.
```

**B. Fallback if the sticky version comes out broken**

```
Replace the sticky scroll section with three alternating full-width rows: text left /
phone right, then phone left / text right, then text left / phone right. Same copy,
same image slots, same dark palette. Keep 120px of vertical padding between rows.
```

**Follow-up worth running either way:**
- `Add a small looping demo above the phone: a text line that types out "remind me to call the pharmacy before six" character by character, then collapses into a single Today row card reading "Call the pharmacy" with the metadata "Health · 6:00 PM". Monochrome only, 1px borders, no colored highlight.`

---

## 4. Privacy / local-first

```
[STYLE BLOCK]

Build a privacy section back on the light palette. This is the trust argument, so it
must look like a statement of fact, not a badge wall.

- Left: a heading, 40px weight 600: "It stays on your iPhone."
- Right: a #6B6B6B paragraph, 18px:
  "Speak It is local-first. Your recordings, transcripts, and notes are stored on your
  device. There is no account to create, and your words are never sent to analytics."
- Below, a single row of four short claims separated by 1px #D6D6D6 vertical hairlines,
  each a thin line icon above 15px text:
  "No account required" · "Stored on device" · "No content in analytics" · "Works offline"

Do not use shield icons, lock badges, checkmark seals, or green colors.
```

---

## 5. Pricing

```
[STYLE BLOCK]

Build a compact pricing section. Two cards, centered, max 800px combined width.

- Section heading 40px weight 600, centered: "Start free."
- Subhead #6B6B6B centered: "Ten captures a month, at no cost, forever."

Card 1 — "Free" — 1px #D6D6D6 border, #FFFFFF surface, 14px radius, 32px padding:
  price "$0", then three 15px lines each with a thin checkmark:
  "10 captures a month", "Today and Memory in full", "Everything stored on device".
  Button: outline style, "Download".

Card 2 — "Pro" — same size, but 2px #0E0E0E border to mark it as preferred:
  price "$1.99" with "/ month" in 15px #6B6B6B beside it, then a 13px #6B6B6B line
  "or annual billing". Three lines:
  "Unlimited captures", "Lock Screen, Action Button, and Back Tap", "Support a
  one-person app".
  Button: filled #0E0E0E with #FFFFFF text, "Get Speak It Pro".

Under the cards, one centered 13px #6B6B6B line:
  "Prices shown in USD. Purchases are handled by the App Store."

No "MOST POPULAR" ribbon, no colored badge, no strikethrough pricing, no countdown.
```

---

## 6. Closing download block + footer

```
[STYLE BLOCK]

Build the final call to action on the dark palette (#090909).

- Centered headline, 48px weight 600, #FFFFFF: "The next thought you have is worth keeping."
- Centered #A3A3A3 line: "Free on the App Store. No account required."
- Centered download row: the black-on-white App Store badge, and beside it the same
  QR code block as the hero but inverted for dark — white QR on #FFFFFF tile with a
  #2E2E2E border, label "Scan to install" in #FFFFFF.
- Below, a footer separated by a 1px #2E2E2E hairline, three columns:
  left the "Speak It" wordmark and a 13px #A3A3A3 line "Made by one person.";
  center links "Privacy Policy", "Terms", "Support";
  right a "hello@speakit.app" mail link.
- Footer bottom line, 13px #A3A3A3: "© 2026 Speak It. iPhone and App Store are
  trademarks of Apple Inc."
```

---

## Refinement phrases that work on Stitch (Web mode)

| Problem | Prompt |
| --- | --- |
| Purple/blue creeps in | `Remove every color. The entire page uses only #F8F8F6, #FFFFFF, #0E0E0E, #6B6B6B, #D6D6D6 and their dark equivalents.` |
| Gradient hero | `Delete the gradient background. Use flat #F8F8F6.` |
| Shadows everywhere | `Remove every box-shadow. Separate surfaces with 1px #D6D6D6 borders only.` |
| Too dense | `Double the vertical padding on every section. Do not change any copy.` |
| Marketing voice returns | `Rewrite all copy to be plain and declarative. No exclamation marks, no "revolutionize", no "AI-powered", no "seamless".` |
| Phone mockups tilted | `Make every iPhone frame perfectly upright, front-facing, centered, with no shadow, no reflection, no rotation, and no hand.` |
| QR looks fake | `Render the QR code as a real high-contrast square module pattern, pure black on white, no rounded modules, no center logo.` |
| Lost mobile layout | `Show the 375px breakpoint. Stack all columns, hide the QR code, and make both buttons full width.` |

---

## After export — checklist

Stitch gives you HTML/CSS. Before this ships:

- [ ] Replace every `SCREENSHOT:` placeholder with the real PNG from `Design/Screenshots/`.
- [ ] Generate a real QR code pointing at the live App Store URL (the app has no
      public listing yet — see `Docs/APP_STORE_SUBMISSION.md`; use a placeholder until the
      App Store ID exists, and do not ship a QR that resolves to nothing).
- [ ] Use Apple's official "Download on the App Store" badge asset from Apple's
      marketing guidelines. Do not ship a Stitch-drawn imitation — it violates the
      badge terms.
- [ ] Add real `alt` text to every screenshot ("The Today screen showing three scheduled
      tasks"), not "screenshot".
- [ ] Verify the pricing block against App Store Connect before publishing. `$1.99` is
      the intended monthly price; App Store Connect is the source of truth for live
      localized prices.
- [ ] Check contrast: `#6B6B6B` on `#F8F8F6` is about 5.1:1 — fine for body text, but do
      not let Stitch lighten it to `#999` for "elegance".
- [ ] Confirm no horizontal scroll at 375px.

## Screenshot inventory

| File | Screen | Best used for |
| --- | --- | --- |
| `01-Today.png` | Today, populated — Needs review, Now, Coming up, floating dock | Demo section, hero alt |
| `02-Memory.png` | Memory — search, 2×2 Pinned/Ideas/People/Reference grid, Recently added | Demo section |
| `03-Capture.png` | Capture idle — concentric pulse, "Tap to speak" | **Hero.** The strongest single image. |
| `04-ItemEditor.png` | Edit Thought sheet — fields, timing, reminders | Optional "you stay in control" row |
| `05-Today-Dark.png` | Today in dark mode | The dark demo section |
