# Speak It — marketing site

A static, dependency-free download site for the Speak It iPhone app. Plain HTML,
CSS, and one small JavaScript file. No build step, no framework, no external
requests — it can be dropped on any static host as-is.

```
Website/
  index.html            the live page
  invite/index.html     validates a referral link and opens the app
  privacy/index.html    public App Store privacy-policy page
  support/index.html    public App Store support page
  assets/stage.css      design tokens + layout for index.html
  assets/stage.js       the opening, the emergence trigger, the demo, the reveals

  assets/img/           screenshots, QR code, favicon
  tools/make_qr.py      regenerates assets/img/qr.svg
```

`classic.html` — the earliest section-by-section landing page — **has been
deleted.** It was unlinked but still a reachable URL if this folder were
deployed whole, and it still carried the old Pro claims and the old "works
offline" line. Its stylesheet and script, `assets/styles.css` and
`assets/site.js`, and `assets/img/03-Capture.png`, are now unreferenced by
anything and can be deleted too; they are left in place only because deleting
them was not asked for.

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
block.

### The shape of the page

The page shows rather than tells. Every section is either the app running, the
app pictured, or a fact — there are no essay columns, and nothing asks to be
read before the reader can see what the product does.

1. **The opening.** The headline with the listening indicator in the gap, and a
   day's worth of spoken thoughts scattering out of it. Scrolling draws them back
   in and the App Store button takes the scroll hint's place.
2. **What happens.** One capture, three thoughts, and the three different things
   they turn into: a place reminder, a timed reminder, and something kept in
   Memory. The phone is drawn in perspective and carries the app's own capture
   screen; each thought lifts out of it and the row it became resolves under it.
3. **Try it.** The capture screen, running in the page. Talk to it.
4. **Two screens.** Today and Memory, at size, one line each.
5. **Where it starts.** The seven capture surfaces, each under a rule.
6. **Your words.** Stays on your iPhone · No account · Works offline.
7. **The offer.** Free and Pro, then the download.

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

**What happens** (`#how`) is the section that has to explain the product before
anybody reads a paragraph, and it is the only place on the page with a device
in perspective.

- **The device is reproduced, not exported.** No Rotato, Spline or Vectary asset
  is embedded. That is a constraint, not a preference: the three sentences
  physically leave this screen and become HTML rows, and a baked PNG or 4K video
  cannot hand one over. Drawn, it also stays sharp at any size, costs no bytes,
  needs no WebGL context on a phone, and follows the app's colours for free.
  `.tilt` is `rotateY(-16deg) rotateX(3deg) rotateZ(1deg)` in a
  `perspective: 1500px` scene. The thickness is flat offset shadows rather than
  a rotated side panel — a real panel needs its own corner radii to meet the
  face's, and the seam where they fail to is what makes a CSS device look like
  a CSS device. What sells it instead is a polished rim (a bright narrow catch
  down the leading edge, a dimmer one on the far edge), three buttons standing
  proud of the visible flank, and the Dynamic Island.
- **The screen's type is sized in `cqw`.** `.tilt` is a container, so everything
  inside is a percentage of the device's own width — one design at every
  breakpoint. Every value is the app's real point size over the 420pt screen it
  is drawn from: `SPEAK IT` is `.caption` at 12pt, so `2.7cqw`; the indicator is
  `ListeningOrb`'s 230pt, so `52cqw`.
- **The results are not cards, because the app has no cards.** A row in Today is
  a title, a category line and a trailing detail sitting straight on the
  background under a hairline — there is no surface, border or radius anywhere
  in `CapturedItemRow.swift`. So each result is a slab of the app's *own*
  background, lifted only by a shadow, carrying the app's section header, the
  app's row, and — under a hairline — the sentence that produced it.
  An earlier version drew a speech bubble with a tail, a connecting thread, a
  white bordered card and an explanatory footnote: five bordered pieces per
  thought, four of which exist nowhere in the product.
- **The original wording is inside the result, not above it.** That is where the
  app keeps it, and it collapses two containers into one. It is also what lets
  the third example earn its place: "Oh, Daniel takes oat milk, not soy" becomes
  a row titled *Daniel prefers oat milk*, so the tidied title and the exact
  words are visible in the same object.
- **The place row carries `mappin.and.ellipse`,** because the app does. "Home"
  on its own in a trailing slot reads as a category rather than a trigger.
- **The scene sorts by depth, not by source order.** `.scene` carries
  `transform-style: preserve-3d`, so a slab at `--z: 150px` passes in front of
  one at `-40px` because it is nearer.
- **The launch vectors were solved, not guessed.** `--fx`/`--fy` put the flying
  sentence's centre exactly on the phone's transcript line at its first frame;
  they were measured in the page and rounded, and they land within ~13px. Move
  or resize the device and they have to be re-solved, or the sentences stop
  coming out of the screen and start coming out of the air beside it. They are
  in `cqw` — `.emit` is a container — because a single line of text is a few
  pixels tall, so expressing the travel as a percentage of *itself* gave
  `--fy: 828%` and would have broken the moment a sentence wrapped.
- **No `translateZ` on the flying sentence.** `.emit` is transformed but not
  `preserve-3d`, so a `translateZ` on a child of it is silently flattened. The
  depth cue is the scale and the blur, which is also cheaper to composite.
- **The order is the argument.** *I said this → Speak It understood it → this is
  where it went.* The sentence leaves the phone first and alone, still in the
  transcript's voice; the paper forms around it from its own line; the row
  resolves on top; the destination is last. One easing throughout,
  `cubic-bezier(.16, .84, .28, 1)` — a long decelerating curve with no
  overshoot, because the movement has to read as weight settling, never as a
  spring.
- **The sequence is CSS, and it is one class.** Each element carries its own
  animation, paused on its opening frame (`animation-fill-mode: both` is what
  makes a paused animation show one), and `stage.js` adds `.is-live` once, the
  first time the composition is on screen. It never re-runs: a section that
  replays every time it is scrolled past cannot be re-read. One beat is
  `--beat` on `.scene`.
- **The finished state is the authored state.** The layout is written as the
  arrived composition and the animation only supplies the order — so reduced
  motion, a missing `IntersectionObserver`, and a page whose script never loaded
  all show the assembled picture rather than an empty stage.
- **The ground is small and eased.** It used to be a wash across the whole scene
  at very low alpha, which banded, and on its own composited layer the bands
  resolved as a visible grey rectangle in the gap between the slabs. It is now a
  disc around the phone with five stops on an eased ramp. More stops, not more
  blur, is what removes contouring at these alphas.
- **Mobile is a second composition, not the first one shrunk.** A phone-width
  room has no depth to stand three slabs in, so the room becomes a column: the
  device keeps a smaller version of the angle, and the results drop out of the
  bottom of it one after another.
- **The dates are resolved at read time.** "Tomorrow at five" and the Memory
  row's created date are written by `stage.js` in the reader's locale, because a
  launch page showing a reminder for a date eight months ago is the one thing
  that would make the composition read as a mock-up.

**Try it** (`#try`) is the app's capture screen rebuilt in the page: the same
indicator, the same two lines, the same *Type instead* escape hatch. Tapping it
starts `SpeechRecognition`, the transcript appears as it is heard, and on `onend`
the sentence is classified and drawn as a real Today row or a real Memory entry
beside the reason and the exact words.

- **Speech is the browser's, not the app's.** Chrome sends the audio to Google;
  the section says so in as many words. It does **not** claim the iPhone
  transcribes locally: `SpeechTranscriber.swift` sets
  `requiresOnDeviceRecognition = false` and lets iOS choose, so Apple may process
  the audio over the network. The note says "transcription uses Apple's Speech
  framework" and links to the privacy policy, which spells the rest out.
  `https` or `localhost` is required — over `file://` the demo falls back to the
  typed version.
- **Every failure has a way out.** No API, permission denied, no speech heard, or
  a `start()` that never calls back at all (an unanswered prompt, a policy block,
  an iframe) each say what happened and offer the typed version. `onerror`
  explains and `onend` only restores the controls, so the explanation is not
  overwritten a tick later.
- **The classifier is a stand-in, and it speaks the app's vocabulary.**
  `classify()`, `titleFor()` and `timeLabel()` in `stage.js` are a deliberate
  cut-down of the on-device version. Every `category · type` pair it can print
  exists in `ItemCategory` and `ItemType` — there is no Health, Travel, Errand or
  Fact in either, and a row printing one describes an app the reader is not about
  to download. It also reads a place instead of a time ("when I get home", "when
  I leave work") and answers with the place, because that is the first thing
  anybody will type in to test it. **If the app's own classification changes
  meaningfully, either update these to match or soften the copy; a demo that
  disagrees with the product is worse than no demo.**
- Everything is string matching in the page. Input is only ever written back with
  `textContent`, so nothing said or typed can be parsed as markup, and there is
  no network call to make.

**Two screens** (`#screens`) is `01-Today-v2.png` and `02-Memory-v2.png` at size, with
one line of copy each and **nothing drawn on top of them**. The frame around
them is built from the same parts as the device in **What happens** — the same
body gradient, the same polished rim, the same buttons on the flank — because
once that one was rebuilt, a plain dark rounded rectangle beside it was the
thing on the page that looked drawn. No Dynamic Island is added here: these are
real device captures and carry their own. The previous version
of this section rang the interesting row with a marker and put a second, quieter
mark on the collection card behind it. Those rings had to be re-measured against
the screenshots' pixels every time a screen changed, and they aged worse than
the screenshots did — a device drawn large enough to read does not need one.
`data-parallax` gives the two devices a few pixels of drift against each other
as the section passes; the travel is deliberately under twenty pixels, above
which it stops reading as depth and starts reading as the page being uneven.

## Before this ships

- [x] **Every link and the QR point at `https://speakitapp.ca`.** That is the
      domain the shipping app already trusts for invite links
      (`ReferralService.swift` validates the host), the domain
      `Docs/APP_STORE_SUBMISSION.md` names for the privacy and support routes, and
      the one the referral service is configured for. It resolves today, which
      is the whole point: a QR that resolves to nothing is worse than one that
      resolves to the page the reader is already on. `APP_STORE_URL` at the top
      of `assets/stage.js` is the single source — every download button and
      every printed URL reads from it.
- [ ] **Swap in the real App Store listing URL the day it exists.** Change
      `APP_STORE_URL`, then regenerate the QR so the two never disagree:

      ```bash
      python3 Website/tools/make_qr.py "<the same URL as APP_STORE_URL>" Website/assets/img/qr.svg
      ```

      The committed QR was regenerated for `https://speakitapp.ca` and verified
      by decoding it with macOS Vision, which is the check to repeat.
- [ ] **Swap in Apple's official "Download on the App Store" badge.** The current
      button is Speak It's own styling with a generic glyph — deliberately *not*
      an imitation of Apple's badge, since redrawing it violates the badge terms.
      Replace the `.appstore` markup in `index.html` with Apple's supplied asset
      from their marketing guidelines before launch. It appears twice: in the
      hero and in the offer.
- [ ] **Confirm the launch discount in App Store Connect — the page is already
      printing it.** `SUMMER_SALE_ENABLED` in `assets/stage.js` is now `true`,
      so the offer shows *50% off at launch* on both plans — `$3.99` struck
      through above `$1.99/month`, `$29.99` struck through above `$14.99/year`,
      the line *Pro is half price while Speak It launches*, and a note giving
      the regular prices. Monthly Pro must actually be `$1.99` (regularly
      `$3.99`) and annual `$14.99` (regularly `$29.99`) in App Store Connect,
      with all localized prices confirmed. **The in-app paywall
      (`SpeakItProView.swift`) currently shows monthly as a flat `$1.99` with no
      regular price** — either give monthly the same scheduled-price treatment
      as annual there, or drop the monthly strike-through here. A page that
      disagrees with the sheet is a refund.
      **No end date is published anywhere**, deliberately — the site states the
      discount, not a deadline, so the offer can be ended or extended without
      the page having lied. Setting the flag back to `false` removes every trace
      of the sale in one edit.
- [x] **The free tier the site advertises matches the app.** Resolved by
      changing the app rather than the copy: `FreePlanAllowance` is a one-time
      `lifetimeCaptureLimit = 10` that never resets, matching the offer
      section's *ten captures, once*.
- [x] **Pro's list is what Pro actually is.** The offer used to sell "Lock
      Screen, Action Button, Back Tap" as Pro features. They are not gated:
      `SpeakItProView.swift` sells exactly one thing, an unlimited capture
      count, and `CaptureAnywhereSetupView` is available to everybody.
- [x] **The offline claim is scoped, and has to stay scoped.** *Works offline*
      is back in the pledge row, but the note under it says what is actually
      true: everything you have captured opens, searches and works with no
      connection, and only the speech-to-text may reach Apple. The app sets
      `requiresOnDeviceRecognition = false` in `SpeechTranscriber.swift` and lets
      iOS choose between its local and network recognisers, so a flat
      no-connection claim would overstate the one part of the app that can leave
      the device. `privacy/index.html` says the same thing at length. If that
      flag ever changes, this line can be widened — not before.
- [x] **`classic.html` is gone.** It was unlinked but `/classic.html` was still a
      URL, and it carried the old Pro claims and an unqualified "works offline"
      line.
      `assets/styles.css`, `assets/site.js` and `assets/img/03-Capture.png` were
      its only consumers and are now unreferenced; delete them when convenient.
- [ ] **Deploy and verify referrals.** Follow `ReferralService/README.md`, pass
      the physical-device Sandbox journey, inject the production API URL in the
      app, and only then change `REFERRALS_ENABLED` to `true`. The checked-in
      `false` value deliberately hides reward language.
- [x] **Privacy and support use real routes.** The footer points to
      `privacy/index.html` and `support/index.html`; deploy them at
      `https://speakitapp.ca/privacy/` and `https://speakitapp.ca/support/`.
- [x] **Support email is `support@speakitapp.ca`.** It replaced
      `hello@speakit.app` (a domain Speak It does not own) in
      `privacy/index.html`, `support/index.html` and the "Email us" link in the
      main page's footer; `invite/index.html`'s App Store fallback now points at
      `speakitapp.ca` too. Confirm the mailbox exists and is monitored before
      the App Store listing goes live — it is also the contact in
      `Docs/APP_STORE_SUBMISSION.md`.
- [x] **`01-Today-v2.png` and `02-Memory-v2.png` are re-captured.** Shot from
      `SampleDataLibrary.Marketing` on an iPhone 17 Pro Max at 1320×2868; the
      recipe is in **The two screenshots** below.

## The two screenshots

`01-Today-v2.png` and `02-Memory-v2.png` are the only place on the page where the real
app is shown at size, so what is on those two screens is a product claim. Both
are 1320×2868 — an iPhone 17 Pro Max at @3x, straight out of `simctl`, no
resampling. `.phone__screen` and `.tilt__screen` carry that ratio as their
`aspect-ratio`, so a re-shoot on a different device means changing it in two
places in `stage.css` and the `width`/`height` attributes in `index.html`.

Keep the status bar and shoot in the **light** appearance to match the page.

**Change the filename when the contents change.** Both files carry a `-v2`
suffix for exactly that reason: they replaced a committed pair under the same
name, and a returning visitor's browser will happily keep serving the old bytes
from cache. A new URL is the only cache invalidation that is not somebody else's
cache policy — bump the suffix on the next re-shoot too.

### Reproducing them

The fixtures are `SampleDataLibrary.Marketing` and they are seeded by a
DEBUG-only launch argument, so the pair can be re-shot without hand-entering ten
captures and without the result drifting between shoots:

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
UDID=$(xcrun simctl list devices available | awk '/iPhone 17 Pro Max/{print $NF}' | tr -d '()')

xcodebuild build -quiet -project SpeakIt.xcodeproj -scheme SpeakIt \
  -configuration Debug -destination "platform=iOS Simulator,id=$UDID" \
  -derivedDataPath /tmp/SpeakItShots CODE_SIGNING_ALLOWED=NO

xcrun simctl boot "$UDID"
xcrun simctl uninstall "$UDID" com.calvinwak.SpeakIt          # the seed runs once
xcrun simctl install "$UDID" /tmp/SpeakItShots/Build/Products/Debug-iphonesimulator/SpeakIt.app
xcrun simctl privacy "$UDID" grant location-always com.calvinwak.SpeakIt
xcrun simctl status_bar "$UDID" override --time "9:41" \
  --batteryState charged --batteryLevel 100 --cellularBars 4 --wifiBars 3
xcrun simctl launch "$UDID" com.calvinwak.SpeakIt --load-marketing-examples \
  -SpeakIt.hasDismissedCaptureAnywhereDiscovery YES \
  -SpeakIt.hasDismissedProDiscovery YES
```

Then tap **Explore first** on the welcome screen and
`xcrun simctl io "$UDID" screenshot` each tab. The uninstall matters: the seed is
guarded by `SpeakIt.hasLoadedMarketingExamples` so it cannot double up, which
also means a reinstall is the only way to re-run it. The location grant matters
too — *"Take the bins out when I get home"* with no permission is a blocked
reminder, and a blocked reminder is a *Needs review* row.

### What the fixtures fix

**`01-Today-v2.png`.** The old one was shot from `SampleDataLibrary.examples`,
which is a rule-engine torture test rather than a product tour. The black
*Capture from anywhere* setup card was the loudest object on the screen and it
is onboarding, not the product at rest; the first row under *Needs review* read
"Don't remind me to buy milk — Task or note?", which put the app failing to
understand a sentence in the hero screenshot; "Buy milk after work" duplicated
it, so the data read as test data; all three times were 5:00 AM / 9:00 AM /
9:00 AM; and no place-triggered row appeared at all, even though location is a
headline feature and the section above it shows one.

What is there now, and why:

- **The setup card is dismissed** by the two `-SpeakIt.hasDismissed…` launch
  arguments, so the screen is the product at rest.
- **No *Needs review* section.** Every fixture is unambiguous, so the screenshot
  shows the app succeeding rather than asking.
- **Four rows across the three tiers**, which is what the caption describes:
  *Now* holds *Call Mum · People · Person follow-up · 5:00 PM*, *Rest of today*
  holds *Pick up the dry cleaning · Shopping · 6:30 PM*, *Coming up* is
  collapsed at 2, and *When you have time* holds the place-triggered
  *Take the bins out when I get home · Personal · Task · Home* — the one row
  that puts a place trigger in the hero shot.
- **Nothing about milk**, no two rows sharing a noun, and no two sharing a time.

**`02-Memory-v2.png`.** What was wrong with the old one: *Pinned* showed **0**, so
the hero screenshot contained an empty collection; both *Recently added* rows
carried a `HIGH` priority pill, which reads as debug data; *Get the laundry* was
a task sitting in Memory, which contradicts the Today/Memory split the entire
page is built on; the *Daniel prefers oat milk* row read `Note` where a
categorised row reads `People · Note`; and *People* read "1 people remembered".

What is there now, and why:

- **Every collection non-zero** — Pinned 2, Ideas 2, People 3, Reference 5. The
  two pinned rows are pinned by the seed through `MemoryPinStore`, because a
  hero screenshot with an empty *Pinned* argues against the feature.
- **Three people**, so the count reads "3 people remembered" and the singular
  grammar bug cannot appear in the shot. (It is still worth fixing in the app.)
- **No `HIGH` pills**, because nothing in the fixtures implies high priority.
- **Nothing actionable in Memory.** Every visible row is a fact, an idea or a
  reference. This is the most important one: the page's whole claim is that the
  two halves do not mix.
- **`Daniel prefers oat milk` reading `People · Note`,** matching the row the
  *What happens* section shows two screens earlier. This is why
  `Marketing.memory` is ordered the way it is — *Recently added* shows the tail
  of that list, so the last two entries are people facts.
- **A search field with placeholder text, not a typed query** — the caption sells
  searching in your own words, and an empty field reads as an invitation.

Both are seeded through the app and captured whole, never composited or
retouched: if an exact state stops being reproducible, ship the closest honest
capture instead.

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

- **The bar's Download opens a sheet, not the offer.** `[data-download]` in
  `index.html` is a native `<dialog>`: a dimmed, blurred layer with the QR on
  the left ("Scan the QR code:"), a hairline, and an "Open App Store" button on
  the right. `showModal()` gives it focus trapping, Escape and page inertness
  for free; `stage.js` only opens it, closes it on a backdrop click or the ×,
  and locks page scroll (`.is-dl-open`) while it is up. Under 700px the QR half
  is hidden — a phone cannot scan itself — and only the button remains. Without
  JS, or on a browser with no `showModal()`, the link keeps its `#get` href.
  The button is a `[data-appstore]` link, so it takes the same URL swap as the
  other two the day the listing goes live.
- Focus is never suppressed.
- The bubbles, the indicator and the devices are decorative and hidden from
  assistive tech. Nothing is available only through an image: in **What
  happens** the three sentences and the three cards are real text in the
  document and are read in order, and only the phone drawn around them is
  hidden. In **Two screens** the caption under each device carries what the
  screenshot shows.
- The demo announces its transcript through `aria-live="polite"`, and the
  microphone button carries a visually hidden label that tracks its state.
- **Everything the script hides is behind `.js`.** `stage.js` adds that class to
  `<html>` on its first line, so the sheet only hides what the page has said it
  can put back. `.reveal` used to sit outside that rule, which meant a page
  whose script 404s, is blocked by a CSP, or throws showed every heading, both
  plans, the pledge row and the download block at `opacity: 0` — a blank page
  with a working scrollbar. It is now `.js .reveal`.
- `prefers-reduced-motion` drops the scatter and the collapse entirely — the
  opening becomes a plain 100svh hero already in its finished state, with the
  indicator present and still and the download block in place rather than
  arriving — and stops the waveform, the breathing, the entrances and the
  reveals. It also turns off smooth anchor scrolling. **What happens** shows the
  assembled composition with no motion at all, which is the state its layout is
  authored in — the phone, the three sentences and the three cards are all
  present, and the section explains the product exactly as well standing still.
  The two devices in **Two screens** stop drifting and sit where they are laid
  out.
- No horizontal scroll from 320px to 1920px; `scrollWidth` measured equal to
  `innerWidth` at 320×568, 375×667, 390×844, 430×932, 768×1024, 844×390,
  956×440, 1024×768, 1280×800, 1440×900 and 1920×1080, each rendered in an
  iframe of that size so `100svh`, `position: fixed` and the media queries
  resolve against a real viewport rather than the window Chrome is willing to
  open.
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
  height, so the opening's eyebrow clears it whatever it comes to — it changes with the pointer, the safe area and the reader's text
  size. There is a static fallback in `:root` for the frames before the first
  measurement, and for a page whose script never runs.
- **Fingers and cursors are asked about separately.** Every hover state is behind
  `@media (hover: hover)`, because a touch browser resolves `:hover` on tap and
  leaves it resolved — unguarded, a tapped card stays lifted after you have
  scrolled on. `@media (pointer: coarse)` brings every target to 44pt, drops the
  tap flash, and puts the demo's input at 16px, under which iOS zooms the page in
  on focus and leaves it zoomed.

**What happens** is the one section whose arrangement changes rather than its
sizes, and it has three of them rather than two.

| Tier | The scene is | Because |
| --- | --- | --- |
| default | a room: device at the left, three slabs cascading down and right across it at three depths | there is width for depth |
| narrow | a column: device on top, the three results dropping out of it | a phone-width room has no depth to stand slabs in |
| on its side | a shallow room, device at 20%, slabs in two non-overlapping columns | there is width again but only ~440pt of height |

The landscape tier is the fussy one. Its slabs do not overlap and its turn is
`-4deg` rather than `-6deg`: on a desktop a slab passing in front of another
reads as depth, but at 844×390 it reads as a sentence with its first three words
hidden behind something else, and the extra turn threw the far corner of the
right-hand slab past the edge of the screen.
