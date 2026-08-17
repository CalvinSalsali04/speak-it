# Speak It — marketing site

A static, dependency-free download site for the Speak It iPhone app. Plain HTML,
CSS, and one small JavaScript file. No build step, no framework, no external
requests — it can be dropped on any static host as-is.

```
Website/
  index.html            the live page
  assets/stage.css      design tokens + layout for index.html
  assets/stage.js       the opening, the walk, the capture demo, the reveals

  classic.html          the earliest page, kept intact and unlinked
  assets/styles.css     design tokens + layout for classic.html
  assets/site.js        nav, download dialog, showcase crossfade, hero demo

  assets/img/           screenshots, QR code, favicon
  tools/make_qr.py      regenerates assets/img/qr.svg
```

`classic.html` is the earliest section-by-section landing page. Nothing links to
it; it is kept only so the previous design can be compared or restored (swap the
two filenames). It has its own stylesheet and script and shares only `img/`.

## Run it locally

```bash
python3 -m http.server 4173 --directory Website
```

Then open <http://localhost:4173>. Opening `index.html` straight off the disk
also works, except for the microphone — see below.

## Design

The palette, type and component shapes are taken from the app itself
(`SpeakIt/Components/SpeakItTheme.swift` and the screens in
`Design/Screenshots/`), so the site and the app read as one product:

| Token | Value | App equivalent |
| --- | --- | --- |
| `--bg` | `#F8F8F6` | `speakBackground` |
| `--surface` | `#FFFFFF` | `speakSurface` |
| `--ink` | `#0E0E0E` | `speakInk` |
| `--muted` | `#6B6B6B` | `speakMuted` |
| `--line` | `#D6D6D6` | `speakDivider` |

There is no brand accent colour and no serif. The app is SF and nothing else, so
the site is too — emphasis comes only from weight, scale and whitespace, and
there is no webfont to request or to silently fall back from.

**`index.html` is light only** — it is the app's light appearance, so it declares
`color-scheme: light`, defines one palette, and has no `prefers-color-scheme`
block. (`classic.html` still follows the system setting and carries both.)

### The shape of the page

The page shows rather than tells. Every section is either the app running, the
app pictured, or a fact — there are no essay columns, and nothing asks to be read
before the reader can see what the product does.

1. **The opening.** The headline with the listening indicator in the gap, and a
   day's worth of spoken thoughts scattering out of it. Scrolling draws them back
   in and the App Store button takes the scroll hint's place.
2. **Try it.** The capture screen, running in the page. Talk to it.
3. **The walk.** One phone that changes screen as three short steps scroll past.
4. **Where it starts.** The seven capture surfaces, as cards.
5. **Your words.** Stays on your iPhone · No account · Works offline.
6. **The offer.** Free and Pro, then the download.

"Local-first" is deliberately absent from the copy. It is accurate, but it is
engineer vocabulary; the site says *stays on your iPhone*, which is the same
promise in words a buyer already owns.

### How the opening works

- **The bubbles are speech, not tags.** Each has a tail — a rotated square of the
  same surface carrying only the two borders that fall outside the bubble — and
  every other one is tailed from the opposite side, so the field reads as several
  people talking rather than as one list.
- **They arrive rather than exist.** On the first painted frame the page holds
  still, then fires one bubble every 62ms out of the indicator, each on an
  `outBack` curve that overshoots slightly and turns as it flies. The clock
  starts on the first frame rather than at load, so a page opened in a background
  tab still plays its entrance when somebody finally looks at it.
- **On a phone the ring is sized by the sentences, not by the viewport.** The
  cloud is an ellipse at 60% of the width on a desktop, but a phone is narrower
  than the sentences on it, and at 60% the thoughts passing three and nine
  o'clock hung up to 126px off a 402pt screen — a row of shapes cut in half
  rather than things somebody had said. `cloudBounds()` asks the bubbles
  instead: `readable` is the widest the ring can be with every thought still
  ending on the screen, `clear` the narrowest it can be without one crossing the
  indicator's outer ring, and the ring is drawn between them, capped at the old
  60%. Both are measured from `offsetWidth`, so they follow whatever the tier is
  doing to the type. Every bubble counts toward both, whatever angle it was
  authored at, because the cloud turns all the way round every 36 seconds and
  each one takes its turn at the widest point.
  On the narrowest screens those two bounds cross — no radius keeps a sentence
  whole *and* off the indicator — so the portrait tier lets the long ones wrap
  to a second line at `max-width: 36vw`, which is what buys the room. Three of
  the seven wrap on a 402pt screen; the widest then ends 2px past the edge
  instead of 126. Sideways there is width to spare and they stay on one line.
- **One transform per bubble per frame.** Position, drift, entrance and collapse
  are composed in `paintField()` and written once, so nothing can fight over the
  same property. CSS animates none of it.
- **Closing the field is one number.** `stage.js` writes `--p` for scroll progress
  and derives the collapse, the fade, the hint and the download block from it, so
  the sequence scrubs in both directions with no state to get out of sync.
- **The pinned frame is 138svh**, a little over a third of a screen of scrolling,
  and every part of the sequence finishes as the frame lets go. There is no
  stretch of scroll after the animation where nothing happens — that was the
  complaint the length is tuned against, so shorten the ramps in `paintOpening()`
  along with the height if it is ever changed.
- **The indicator goes to the type, not the other way round.** The headline,
  standfirst and download block are one centred flow stack — they cannot overlap
  each other at any size — and `dockStage()` measures the gap in the headline and
  moves the fixed indicator onto it. Verified collision-free from 320×568 to
  1512×982. An earlier version pinned the standfirst to the foot of the screen
  independently of a viewport-centred headline, and the two met at heights around
  850px.
- **Type carries paper.** No ellipse clears a full-width headline at twelve and
  six o'clock *and* the copy underneath, so bubbles are allowed to pass behind the
  words and every block of type carries a radial disc of background that
  dissolves them as they cross — the same halo the indicator uses.
- **The indicator** is a CSS re-creation of `ListeningOrb.swift` — the same three
  rings at the same 0.84 + 0.13·n spacing, the same 72:230 core, the same
  waveform.

### The interactive parts

**Try it** (`#try`) is the app's capture screen rebuilt in the page: the same
indicator, the same two lines, the same *Type instead* escape hatch. Tapping it
starts `SpeechRecognition`, the transcript appears as it is heard, and on `onend`
the sentence is classified and drawn as a real Today row or a real Memory entry
beside the reason and the exact words.

- **Speech is the browser's, not the app's.** Chrome sends the audio to Google;
  the section says so in as many words rather than implying the page is running
  what the iPhone runs. `https` or `localhost` is required — over `file://` the
  demo falls back to the typed version.
- **Every failure has a way out.** No API, permission denied, no speech heard, or
  a `start()` that never calls back at all (an unanswered prompt, a policy block,
  an iframe) each say what happened and offer the typed version. `onerror`
  explains and `onend` only restores the controls, so the explanation is not
  overwritten a tick later.
- **The classifier is a stand-in.** `classify()`, `titleFor()` and `timeLabel()`
  in `stage.js` are a deliberate cut-down of the on-device version — a handful of
  regexes for dates, task verbs, ideas, reference details and people. If the
  app's own classification changes meaningfully, either update these to match or
  soften the copy; a demo that disagrees with the product is worse than no demo.
- Everything is string matching in the page. Input is only ever written back with
  `textContent`, so nothing said or typed can be parsed as markup, and there is
  no network call to make.

**The walk** (`#how`) follows one capture all the way through: two sentences said
on the way home, then the two different places they end up.

The example is built out of what is **actually in the screenshots**. "Remind me
to buy milk after work at nine" produces the row `Buy milk after work · Work ·
Shopping · 9:00 AM`, and "Daniel prefers oat milk" produces the Memory entry
`Daniel prefers oat milk · Note` — both of which are really on screen in
`01-Today.png` and `02-Memory.png`. A `.pin` ring is positioned over each one so
the reader can see the sentence become the row, and a second, quieter `.pin--soft`
marks the People card a beat later.

`.pin--soft` is laid on the People card's own border box, measured off the
screenshot's pixels, and its corner radius comes from the app rather than from
the picture: the collection card in `LibraryView.swift` is
`RoundedRectangle(cornerRadius: 20, style: .continuous)`, and the screenshot is
a 420pt-wide device at @3x, so the radius is `20/420` of the screen width at any
size the phone is drawn. `.continuous` is a squircle and `border-radius` is a
circular arc, so they are different curves and cannot be reconciled exactly —
`--squircle` on that rule is the factor that makes the circular arc read like
the corner next to it, and it is the only part of the value that is taste rather
than arithmetic. **If the screenshots are ever replaced, those
percentages have to be re-measured and the example rewritten around whatever the
new screens contain** — an earlier version narrated a pharmacy call that appeared
nowhere on the phone, and the section did not read.

One caveat on the Memory step: the copy says the note is kept under People, and
that is what the app does with something about a person, but the row in the
current screenshot shows only `Note` where a categorised row would show
`People · Note` (compare `Work · Idea` two rows below it). The claim is true of
the product and slightly ahead of this particular screenshot's seed data.
Re-capturing `02-Memory.png` with that row reading `People · Note` would close
the gap.
The title in the row is also what `titleFor()` would produce from that sentence:
strip "Remind me to", strip "at nine", capitalise.

It has no controls at all: `paintWalk()` finds the step nearest the reading line
and lights it, and the phone crossfades to match. It is measured rather than
observed, so it is correct at any scroll position, including the one a deep link
lands on. The reading line is the middle of the viewport when the phone is beside
the text, and the middle of the band under the phone when the phone is above it —
taken off the device's own box rather than written as a fraction, so it is right
at every screen the stacked layout is used on. The steps column carries extra
bottom padding because the phone stays pinned only for as long as that column is
tall — without it the phone slides out from under the top bar while the last step
is still being read. On narrow screens the grid drops to block flow (a grid
item's sticky positioning is confined to its own grid area, so the phone could
otherwise only stick for its own height) and the phone carries a plate of
background so step text dissolves as it passes behind.

## Before this ships

- [ ] **Set the real App Store URL.** It appears once per page: `APP_STORE_URL`
      at the top of `assets/stage.js` (and again in `assets/site.js` if
      `classic.html` is kept). Every download button and printed URL reads from
      it.
- [ ] **Regenerate the QR code to match.** The committed code encodes
      `https://speakit.app`, a placeholder — the app has no public listing yet
      (see `APP_STORE_SUBMISSION.md`). Never ship a QR that resolves to nothing:

      ```bash
      python3 Website/tools/make_qr.py "<the same URL as APP_STORE_URL>" Website/assets/img/qr.svg
      ```

- [ ] **Swap in Apple's official "Download on the App Store" badge.** The current
      button is Speak It's own styling with a generic glyph — deliberately *not*
      an imitation of Apple's badge, since redrawing it violates the badge terms.
      Replace the `.appstore` markup in `index.html` with Apple's supplied asset
      from their marketing guidelines before launch. It appears twice: in the
      hero and in the offer.
- [x] **The free tier the site advertises now matches the app.** Resolved by
      changing the app rather than the copy: `FreePlanAllowance` is a one-time
      `lifetimeCaptureLimit = 10` that never resets, matching the offer
      section's *ten captures to try*. `classic.html` has been updated too.
- [ ] **Confirm launch pricing in App Store Connect.** Configure the live
      products at `$1.99/month` and `$14.99/year`, then confirm the localized
      StoreKit prices match the app and website. Do not publish comparison,
      discount, or time-limited pricing claims unless App Store Connect is
      configured to support the exact offer.
- [ ] **Point "Privacy" at a real page.** The footer link currently jumps to the
      pledge section as a placeholder, and there is no Terms page yet.
- [ ] **Confirm `hello@speakit.app`** is a real, monitored address.
- [ ] Refresh the screenshots in `assets/img/` if the app's UI changes. They are
      copies of `Design/Screenshots/`, not symlinks.

## The QR generator

`tools/make_qr.py` is a self-contained QR encoder (byte mode, error-correction
level M, versions 1–10) using only the standard library, so the site has no
dependency on a QR service or package. It writes an SVG, and optionally a PNG
used for verification:

```bash
python3 tools/make_qr.py "https://example.com" out.svg out.png
```

The output was verified by decoding the generated PNG with macOS Vision
(`VNDetectBarcodesRequest`) across versions 2 through 9, covering both
single-block and multi-block interleaving.

## Accessibility and behaviour notes

- Focus is never suppressed.
- The bubbles, the indicator and the phone are decorative and hidden from
  assistive tech. The three walk steps carry the information the phone
  illustrates, so nothing is available only through the images, and the dots are
  an indicator rather than a set of controls.
- The demo announces its transcript through `aria-live="polite"`, and the
  microphone button carries a visually hidden label that tracks its state.
- `prefers-reduced-motion` drops the scatter and the collapse entirely — the
  opening becomes a plain 100svh hero already in its finished state, with the
  indicator present and still and the download block in place rather than
  arriving — and stops the waveform, the breathing, the entrances and the
  reveals. It also turns off smooth anchor scrolling. The phone still changes
  screen; it just does not fade between them.
- No horizontal scroll from 320px to 1920px; verified at 320, 375, 390, 768, 900,
  1024, 1280, 1440 and 1920.
- Bubbles that swing past the edge of the opening are clipped by the pinned
  frame, never by the page.

## Sizes

The sheet is organised as four tiers, and which one applies is decided by the
shape of the screen rather than by its width alone — a phone lying on its side is
between 667 and 956pt wide, so width by itself cannot tell one from a laptop.

| Tier | Asks for | Is |
| --- | --- | --- |
| default | — | desktop, and the tall end of everything |
| in between | 620–900 wide **and** 600+ tall | a tablet upright, a narrow desktop window |
| narrow | ≤900 wide | a phone upright |
| on its side | ≤560 tall | every iPhone turned sideways, and short desktop windows |

The last tier is written last so it wins over the width tiers for the widths they
overlap on. `max-height: 560px` catches every landscape iPhone — the tallest is
440pt on its side — and no phone standing up, whose shortest screen is the
667pt SE.

Verified against every iPhone that runs iOS 17, in both orientations, by
rendering the page in an iframe sized to the device so that `position: fixed`
and `100svh` resolve against a real viewport of that size. In each: no
horizontal overflow with the demo's result card and typed form both open, the
indicator centred on the gap in the headline to within half a pixel, and
daylight between the bar, the eyebrow, the headline and the foot of the frame.

Three things the page does for a phone specifically:

- **The safe area is one variable.** `--gutter` is the larger of the design's own
  gutter and the left/right safe-area inset, and every horizontal padding on the
  page goes through it, so `viewport-fit=cover` paints the background edge to
  edge without putting a word under the island or a rounded corner. The bar adds
  the top inset and the footer the bottom one, which matter when the page is
  installed to the Home Screen rather than opened in a tab.
- **`--bar` is measured, not written down.** `stage.js` publishes the bar's real
  height, so the eyebrow and the sticky phone in the walk clear it whatever it
  comes to — it changes with the pointer, the safe area and the reader's text
  size. There is a static fallback in `:root` for the frames before the first
  measurement, and for a page whose script never runs.
- **Fingers and cursors are asked about separately.** Every hover state is behind
  `@media (hover: hover)`, because a touch browser resolves `:hover` on tap and
  leaves it resolved — unguarded, a tapped card stays lifted after you have
  scrolled on. `@media (pointer: coarse)` brings every target to 44pt, drops the
  tap flash, and puts the demo's input at 16px, under which iOS zooms the page in
  on focus and leaves it zoomed.

The walk is the one section whose arrangement changes rather than its sizes.
Upright the phone sticks below the bar and the steps pass underneath it; on its
side there is no height for that, so it goes back to the desktop's two columns
with a smaller device. `paintWalk()` reads which arrangement is in force from the
grid's own `display` and measures the reading line to match: the middle of the
screen when the phone is beside the text, the middle of the band under the phone
when it is above it. That is why a step now arrives with its text already in
clear space instead of still climbing into it from below the fold.
