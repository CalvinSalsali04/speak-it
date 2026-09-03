# Google Stitch prompt pack — Speak It

Copy-paste briefs for generating Speak It UI in Google Stitch (stitch.withgoogle.com).

## How to drive Stitch

- Use **App** mode, not Web. Stitch's App mode targets a phone frame; Web mode will give you a marketing layout.
- Model choice: use **Thinking with 3.1 Pro** for the first generation of each screen (it respects long, structured constraints far better). Switch to **3 Flash** for cheap iteration once the layout is right.
- **One screen per prompt.** Stitch degrades when asked for a whole app at once. Generate Today, then Memory, then Capture, each as its own turn.
- Follow-up messages in the same chat *edit the existing design*. Say "change only the X" or it may re-roll the whole screen.
- The **palette icon** (next to the model picker) sets theme colors deterministically. Set the hexes there instead of trusting the prompt to hold them.
- To restyle a screen you already built, use **Redesign** mode and attach a simulator screenshot rather than describing it.
- Stitch does not know SwiftUI. Export is HTML/CSS — treat output as a *visual reference*, not code to port. See "After Stitch" at the bottom.

---

## STYLE BLOCK (prepend to every screen prompt)

```
Design an iOS 17+ iPhone app screen. App name: Speak It. It is a calm, voice-first,
local-first thought-capture app. The visual language is restrained and monochrome —
closer to a well-set book page than to a productivity dashboard.

STRICT STYLE RULES:
- Light mode: background #F8F8F6 (warm off-white), card/surface #FFFFFF,
  primary text #0E0E0E, secondary text #6B6B6B, hairline dividers #D6D6D6.
- Dark mode: background #090909, surface #161616, primary text #FFFFFF,
  secondary text #A3A3A3, dividers #2E2E2E.
- There is NO brand accent color. Emphasis comes from weight, size, and whitespace only.
- Exactly one chromatic exception exists: a muted brick red (#B3382E light, #E6786B dark)
  used ONLY to mark "this item needs your input." Never for buttons, links, or decoration.
- Typography: SF Pro / system rounded-neutral. Screen title = large title, semibold.
  Section header = headline. Row title = body, medium weight. Metadata = footnote, secondary color.
- Generous vertical rhythm. Cards use ~14pt corner radius, no drop shadows, no gradients,
  no glassmorphism, no colored illustrations, no emoji.
- Icons: SF Symbols style, thin/regular weight, monochrome, small.
- Every tappable control is at least 44x44pt.
- Respect iOS safe areas and show a status bar.

DO NOT ADD: a settings gear cluster, avatars, charts, progress rings, streak counters,
badges, gamification, colored category chips, or a tab bar with more than two destinations.
```

---

## 1. Today

> Purpose: "What can I act on?" Only actions live here.

```
[STYLE BLOCK]

Screen: "Today" — the action list.

Layout top to bottom:
1. Large title area: a time-aware greeting ("Good afternoon") in large-title semibold,
   with today's date beneath it in footnote secondary color ("Tuesday, 12 August").
2. A small toolbar row, right-aligned, with two thin monochrome icon buttons only:
   a hand-tap icon (capture-anywhere setup) and a person-circle icon (account & settings).
3. A stack of grouped sections. Each section has:
   - a headline-weight title,
   - directly beneath it, a footnote-size secondary line stating the literal membership
     rule for that section,
   - then its rows.
   Sections, in order, with their exact rule text:
   - "Now" / "Overdue and next scheduled"
   - "Rest of today" / "Scheduled before the day ends"
   - "Coming up" / collapsed by default, showing a count and a chevron
   - "When you have time" / "Ready to do · no date set"
4. One section, "Needs review", may appear above the others with its title and a single
   row marked in the muted brick red — this is the only color on screen.

Row anatomy (white surface card, full width minus 16pt margins):
- Leading: a 24pt circular hairline outline checkbox, empty.
- Center: the thought title in body/medium, wrapping to at most two lines.
- Below the title: footnote secondary metadata line, e.g. "2:30 PM" or "Overdue · yesterday".
- Trailing: a very light chevron.

At the bottom, floating above the content: a custom dock — a pill-shaped bar containing
two text destinations, "Today" (selected, primary ink) and "Memory" (secondary), with a
single prominent circular capture button centered between them containing a simple
monochrome waveform glyph. The dock floats with a soft hairline border, not a shadow.

Show 6-7 realistic rows. Sample content, use verbatim:
"Email Dr. Chen about the reschedule", "Pick up the prescription before 6",
"Send Maya the apartment listing", "Renew the parking permit",
"Ask Sam what he thought of the draft", "Book the dentist".
Empty sections are hidden entirely — do not render placeholder text for them.
```

**Follow-ups worth running:**
- `Show the same screen in dark mode using the dark hexes. Change nothing else.`
- `Show the empty state: keep the greeting and dock, replace all sections with a single centered block — a thin waveform icon, the line "Nothing to act on yet", and the secondary line "Capture a thought and anything time-based will appear here."`
- `Show "Coming up" expanded, with three rows dated tomorrow through Friday.`

---

## 2. Memory

> Purpose: "What useful knowledge did I save?" Never actions.

```
[STYLE BLOCK]

Screen: "Memory" — a searchable knowledge list.

Layout:
1. Large title "Memory" with a footnote secondary subtitle "Find · Recognize · Reuse".
2. A full-width search field, surface-colored with a hairline border and a small
   magnifier icon, placeholder "Search people, ideas, or facts".
3. A single-line horizontally scrollable row of filter pills directly under the search:
   "All" (selected — filled with primary ink, inverse text), then "Pinned", "Ideas",
   "People", "Reference", "Archive" (unselected — hairline outline, secondary text).
   The row must never wrap to two lines; it scrolls.
4. Grouped sections with headline titles, in order: "Pinned", "Ideas", "People",
   "Notes & context". Each section header has a small trailing count in secondary color.

Row anatomy:
- Leading: a small thin monochrome SF-Symbol-style icon indicating type
  (lightbulb for idea, person for people, doc.text for reference).
- Center: title in body/medium, plus a footnote secondary second line that is a short
  excerpt of the user's original words in the user's own phrasing.
- Trailing: a small pin glyph on pinned rows only; otherwise nothing.

Show one row swiped partially left revealing a single monochrome "Archive" action in a
dark neutral swipe panel — not red, not colored.

Sample content, use verbatim:
Pinned: "Wifi password is on the fridge magnet"
Ideas: "App that reads recipes aloud hands-free", "Teach a short workshop on note-taking"
People: "Maya — allergic to shellfish, birthday March 9", "Sam — new job at the clinic"
Notes & context: "Landlord prefers texts after 5", "Car needs 5W-30, not 5W-20"

Same floating bottom dock as Today, but "Memory" is the selected destination.
```

**Follow-ups:**
- `Show the search-results state: query "maya", results header "Results for "maya"", two matching rows, and no filter pills change.`
- `Show the Archive filter selected with an empty state: "Nothing archived", secondary line "Archived items stay safe without cluttering Memory."`
- `Show a compact row density variant — same content, tighter vertical padding, single-line titles.`

---

## 3. Capture — listening (the signature screen)

```
[STYLE BLOCK]

Screen: full-screen voice capture. No dock, no tab bar, no navigation chrome.
This screen should feel like the room went quiet.

Layout, vertically centered on a plain #F8F8F6 background:
1. Top-left: a single thin "×" close button. Top-center: the word "SPEAK IT" in
   tiny uppercase letter-spaced footnote, secondary color. Nothing else.
2. The centerpiece: a large soft circular "memory pulse", roughly 220pt across —
   a monochrome concentric form made of 3-4 nested rings that fade outward from a
   solid dark center, like a slow breath. It is soft-edged and grayscale, NOT a
   colorful glowing orb, NOT a Siri gradient, NOT a rainbow blob.
3. Beneath the pulse, ~40pt down: the status line "Listening" in headline weight.
4. Beneath that: live transcription text, body size, primary ink, left-aligned within
   generous horizontal margins, showing a partially-formed sentence with the last few
   words in a lighter secondary tone to imply they are still being recognized:
   "Remind me to email Dr. Chen about moving the appointment to" — with "to" faded.
5. Near the bottom: a single low-emphasis text button "Type instead" in secondary color,
   with a small keyboard glyph. Nothing else competes with it.

The entire pulse is the primary control — do not draw a separate record button.
```

**Follow-ups:**
- `Show the idle state before listening: pulse smaller and calmer, status line "Tap to speak", supporting line "Just speak. I'll save after a natural pause.", no transcription text.`
- `Show the saved state: the pulse has contracted into a small solid circle containing a thin checkmark, with the word "Remembered" beneath it. Remove the transcription and the "Type instead" button.`
- `Show the permission-denied state: replace the pulse with a thin microphone-slash icon, headline "Microphone access is off", secondary line "Allow microphone and speech recognition, or type instead.", then two stacked buttons — a filled dark "Open Settings" and an outline "Type instead".`
- `Show the dark mode version of the listening state.`

---

## 4. Capture — typing

```
[STYLE BLOCK]

Screen: full-screen text capture, the alternative to voice.

- Top-left thin "×" close button. Top-right a text button "Speak instead" with a small
  waveform glyph, secondary color.
- The body is one large focused text editor filling the screen: body-size text,
  generous margins, placeholder "Something you don't want to forget…" in secondary color,
  with a visible text cursor.
- Above the keyboard, a single full-width filled button in primary ink with inverse text:
  "Save thought", 50pt tall, 14pt radius.
- Show the iOS keyboard raised.
- Small footnote line above the button, secondary color: "Write naturally. You can
  organize it later."
```

---

## 5. Item editor

```
[STYLE BLOCK]

Screen: an item detail/edit sheet presented over Today.

- Navigation bar: "Cancel" on the left, "Save" on the right in medium weight, no title.
- First block: a large editable title field containing "Email Dr. Chen about the
  reschedule", styled as title text, not as a boxed input.
- Then an inset grouped list of editable fields, each a row with a secondary-color label
  on the left and the value on the right with a small chevron:
  Type = Task, Category = Health, Priority = Normal, Person = Dr. Chen.
- Then a "Due date" row with an iOS toggle, switched on, revealing a date+time value
  "Today, 2:30 PM".
- Then a visually distinct read-only block with a hairline border and NO fill, headed
  "Original capture" in a tiny uppercase letter-spaced label. Inside, in body text and
  slightly italic-feeling, the user's untouched words:
  "Um, remind me to email Doctor Chen about moving the appointment, the reschedule thing,
  to sometime this afternoon." Beneath it, a footnote metadata line:
  "Captured 9:12 AM · Voice".
  This block must read as an archival record — clearly not editable.
- At the bottom, three separated full-width text actions stacked with dividers:
  "Mark complete", "Archive", and "Delete permanently" (the last one in the muted
  brick red #B3382E — the only color on screen).
```

---

## 6. Onboarding / first launch

```
[STYLE BLOCK]

Screen: first-launch welcome. Centered, extremely sparse, no illustration art.

- Top third: the app name "Speak It" in large title semibold, and beneath it the promise
  line in body secondary: "Speak naturally. Speak It saves, organizes, and resurfaces
  what matters."
- Middle: three small horizontally arranged beats, each a thin monochrome glyph above a
  one-word label — a waveform above "Speak", a small dot-grid above "Organized",
  a soft ring above "Remembered". Connect them with a thin hairline, not arrows.
- Lower third: one full-width filled primary-ink button with inverse text,
  "Capture a thought".
- Beneath it, a footnote secondary line: "No account required."
- Nothing else. No page dots, no "Skip", no login options.
```

---

## 7. Pro paywall

```
[STYLE BLOCK]

Screen: the Speak It Pro upgrade sheet. It must feel like a quiet statement of fact,
not a sales page. No urgency, no countdown, no crossed-out prices, no confetti.

- A grabber bar at the top indicating a sheet.
- Title: "Speak It Pro" in large title semibold. Subtitle in body secondary:
  "Unlimited captures. Everything stays on your iPhone."
- A short list of four rows, each a thin monochrome checkmark plus body text:
  "Unlimited captures every month", "Capture from the Lock Screen and Action Button",
  "Everything stays local to your device", "Support a one-person app".
- Two selectable plan cards side by side, hairline outline, 14pt radius:
  left = "Monthly · $1.99", right = "Annual" marked selected with a 2pt primary-ink
  border and a small "Best value" footnote label. No colored badge.
- One full-width filled primary-ink button, inverse text: "Continue".
- Beneath it, a centered footnote secondary row of three plain text links separated by
  interpuncts: "Restore" · "Terms" · "Privacy".
```

---

## Refinement phrases that work on Stitch

Stitch tends to drift toward generic SaaS styling. These pull it back:

| Problem | Prompt |
| --- | --- |
| Adds color | `Remove all color. The palette is only #F8F8F6, #FFFFFF, #0E0E0E, #6B6B6B, #D6D6D6.` |
| Adds shadows/gradients | `Remove every drop shadow and gradient. Use hairline 1px borders in #D6D6D6 instead.` |
| Cramped | `Increase vertical spacing between sections by 50%. Do not change any content.` |
| Generic tab bar | `Replace the standard tab bar with a floating pill dock containing only "Today" and "Memory" and one central circular capture button.` |
| Wrong pulse | `The center element must be soft concentric grayscale rings, not a glowing colored orb and not a Siri-style gradient.` |
| Clutter | `Delete every element that is not required to answer "what can I act on right now".` |
| Lost the copy | `Keep the exact wording I supplied. Do not rewrite labels.` |

## After Stitch

Stitch exports HTML/CSS and a Figma handoff — neither maps to this codebase. The
useful outputs are the visual composition and spacing decisions. When translating back:

- Colors already exist as `Color.speakBackground` / `speakSurface` / `speakInk` /
  `speakMuted` / `speakDivider` / `speakWarning` in `SpeakIt/Components/SpeakItTheme.swift`.
  Never hardcode a hex in a view.
- Type roles already exist as `SpeakItTypography.screenTitle` / `eyebrow` /
  `sectionTitle` / `sectionDetail` / `itemTitle` / `metadata`.
- Any custom control needs `.buttonStyle(.speakIt)` for the 44pt minimum and pressed state.
- Stitch mockups are fixed-size and will not show you Dynamic Type, wrapping, dark mode,
  or Reduce Motion failures. Those still need a simulator pass before a design is accepted.

## Open discrepancy

`Docs/SCREEN_SPECIFICATIONS.md` line 50 describes "one violet accent"; the shipped theme is
monochrome with `speakAccent = speakInk`. These prompts follow the code. If violet is the
intended direction, update the theme and this pack together rather than letting Stitch
invent an accent.
