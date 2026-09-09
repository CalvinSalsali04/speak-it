# App Store listing — Speak It 1.0

Copy for App Store Connect, grounded in `CLAUDE.md`, `Docs/USER_FLOWS.md`,
`Docs/PRICING_AND_CONVERSION_2026-09-07.md`, the website copy in
`Website/index.html`, and the features under `SpeakIt/Features`. Character
counts are shown against Apple's limits. Nothing here names a price; App Store
Connect is the source of truth for live localized prices, and the description
must not go stale when the annual price changes.

Rules this copy follows: calm and plain, no hype, no emoji, no competitor
names, no "coming soon", no referral promise (the program is externally gated
and off in the app until `SPEAKIT_REFERRAL_API_URL` is injected), and no
claim that the app does not make in `Docs/USER_FLOWS.md`.

## App Name (8 / 30)

```
Speak It
```

## Subtitle (28 / 30)

```
Say it before you forget it.
```

The website's headline. Keep the two in step.

## Promotional Text (156 / 170)

```
Turn spoken thoughts into reminders and searchable memories. One tap, no sorting, and your original words are always kept. Your first ten captures are free.
```

Promotional Text can be changed without a new build. Use it for the launch
allowance line; move seasonal wording here rather than into the description.

## Description (3682 / 4000)

```
Speak It turns spoken thoughts into reminders and searchable memories.
Tap once, say what is on your mind, and pause. Speak It saves it, keeps your exact words, and puts it where you will find it again.

TODAY DOES. MEMORY KNOWS.
Things to do go to Today: what is overdue, what is due today, what is coming up, and what can wait for a quiet moment. Check something off and it leaves the list, with a few seconds to undo.

Things worth finding later go to Memory: pinned items, ideas, people, and reference details like a gate code or who takes oat milk. Search your own words. Ideas can move from New to Promising, Exploring, or Parked as they grow.

YOUR WORDS ARE KEPT
Every capture keeps its original transcript. Speak It may tidy a title or pull out a date, but it never rewrites what you said. If something lands in the wrong place, open it and change the type, date, person, or reminder in a moment.

REMINDERS THAT FIT HOW YOU TALK
"Call the pharmacy at six" becomes a reminder at six. "Every Monday at nine" repeats. "Wake me at seven" sets an alarm on iOS 26 and later. "Take the bins out when I get home" waits until you arrive, once you have set your Home or Work place and allowed location reminders.

PEOPLE AND FOLLOW-UPS
Mention someone and the thought is kept under their name in Memory. Dated follow-ups surface in Today when they become timely. When a follow-up calls for a message, Speak It prepares it and nothing is sent until you approve it. A timed task can be added to your calendar the same way, with Apple's event editor showing you exactly what will be added.

ONE BREATH, SEVERAL THOUGHTS
Say "Buy milk, eggs, and toothpaste" and get three checkable items on one list. Say a task and an idea together and each goes where it belongs, still under one capture.

CAPTURE WITHOUT LOOKING FOR THE APP
Start a capture from the Action Button, Back Tap, a Lock Screen or Home Screen widget, Control Center on iOS 18 and later, Siri, or the share sheet. A Live Activity brings you back to a capture in progress. The Lock Screen widget shows how many things are open, and shows their names only if you choose to.

WORKS OFFLINE. NO ACCOUNT.
There is no Speak It account to create. Your library is stored on your iPhone, and optional iCloud sync uses your own private iCloud container. Search, editing, and checking things off work without a signal. Organizing happens on your iPhone. Live dictation may be processed by Apple's speech service. You can type a thought whenever speaking is not the right choice.

If a capture is interrupted, the draft is kept until you decide what to do with it. Speak It does not clear your words before they are saved.

SIMPLE FROM THE START
Your first ten captures are free, with every feature included. It is a one-time allowance, not a monthly limit. Speak It Pro removes the limit so you can capture as often as you need. Everything you have already saved stays readable and editable whether or not you subscribe.

Speak It Pro is an auto-renewable subscription, offered monthly or annually. Payment is charged to your Apple Account when you confirm the purchase. The subscription renews automatically unless it is cancelled at least 24 hours before the end of the current period, and you can manage or cancel it in your Apple Account settings at any time.

Terms of Use: https://www.apple.com/legal/internet-services/itunes/dev/stdeula/
Privacy Policy: https://speakitapp.ca/privacy

Speak It is made by one person. If you have a question or something is not working, write to support@speakitapp.ca.

Requires iOS 17 or later. Apple Intelligence is not required. Some capture routes depend on your iPhone model and iOS version.
```

Notes:

- The first two lines carry the value statement and are what the store shows
  before "more".
- "Live dictation may be processed by Apple's speech service." is required and
  must stay verbatim; it matches the privacy policy and the website FAQ.
- The Terms of Use (Apple standard EULA) and privacy policy links sit near the
  end because Apple requires both in metadata for auto-renewable subscriptions
  (guideline 3.1.2). The same two links are on the Pro screen in the app.
- The subscription paragraph deliberately carries no price. Prices, the annual
  launch price, and its October 22, 2026 change live in App Store Connect and
  are rendered in the app from `product.displayPrice`.

## Keywords (95 / 100)

```
voice,notes,memo,dictation,reminder,todo,task,memory,capture,thought,brain,dump,transcribe,idea
```

14 terms, comma separated with no spaces. None repeats a word from the
name or subtitle (Apple already indexes those), and none is a trademark.
Candidates held back for a later revision if search data warrants them:
`offline`, `journal`, `recorder`, `private`, `speech`, `handsfree`.

## What's New (1.0)

```
Speak It 1.0.

Tap once, say what is on your mind, and pause. Tasks and reminders go to Today; ideas, people, and details go to Memory. Your original words are always kept.

Capture from the Action Button, Back Tap, widgets, Control Center, Siri, or the share sheet. Reminders at a time, on a repeat, or when you arrive somewhere. No account, works offline, and your first ten captures are free.
```

## URLs and legal

| Field | Value |
| --- | --- |
| Support URL | https://speakitapp.ca/support |
| Marketing URL | https://speakitapp.ca |
| Privacy Policy URL | https://speakitapp.ca/privacy |
| Copyright | © 2026 Calvin Salsali |

Every field uses the bare host, which is what the app links from the Pro
screen (`SpeakItProView.privacyPolicy`) and what `Website/index.html` uses for
its own absolute URLs. `Website/support/index.html` and
`Website/privacy/index.html` must be deployed and resolve over HTTPS before
submission; if `www.speakitapp.ca` is ever advertised it must redirect here.

## Categories

| Slot | Category | Reason |
| --- | --- | --- |
| Primary | Productivity | Matches `public.app-category.productivity` in `SpeakIt/Info.plist`; the app's job is tasks, reminders, and things to find later. |
| Secondary | Utilities | Speak It behaves like a single-purpose tool: one tap, immediate value, no workspace. Utilities is also where the trial and retention benchmarks in `Docs/PRICING_AND_CONVERSION_2026-09-07.md` are most favourable, so it is the right second shelf if the primary is ever reconsidered. |

## Subscriptions

Subscription group display name (12 / 30): `Speak It Pro`
(already present in App Store Connect for English (Canada); add the same
name to every localization).

| Product ID | Display name | Description |
| --- | --- | --- |
| `com.calvinwak.SpeakIt.pro.monthly` | Speak It Pro Monthly (20 / 30) | Unlimited captures, billed monthly. (35 / 45) |
| `com.calvinwak.SpeakIt.pro.annual` | Speak It Pro Annual (19 / 30) | Unlimited captures, billed yearly. (34 / 45) |

Both plans unlock the same thing — capture without a lifetime limit — and sit
at the same service level. Nothing already saved is ever locked, and no other
feature is gated. Monthly is never discounted; only the annual plan carries a
launch price, and annual must stay below twelve months of monthly so the plan
the paywall pre-selects and badges `BEST VALUE` is the cheaper one. Do not
describe a plan as "50% off" anywhere in metadata unless that schedule is
visible in App Store Connect (`Docs/APP_STORE_PRICING_STATUS_2026-09-09.md`
records that it is not yet configured).

Each subscription also needs a review screenshot of the in-app Pro screen
with both plans visible; capture it on the 6.9" simulator with the StoreKit
configuration attached so the plan cards render.

## In-app purchase promotional image

Apple shows this image on the App Store product page and in search when a
subscription is promoted, and crops it to its own rounded shape.

| Attribute | Value |
| --- | --- |
| Size | 1024 × 1024 px, square |
| Format | PNG (JPEG accepted), sRGB, no transparency, no rounded corners — Apple applies the mask |
| Content | The five-bar Speak It mark from `Design/Brand/Emboss/` on the paper ground, centred, occupying roughly 60% of the width |
| Safe area | Keep the mark inside the central 80% so nothing is lost to the mask or the store's own overlay |
| Text | None. No price, no "free", no "Pro" lettering, no badge — the store renders the plan name and price beside the image |
| Variants | One image serves both plans; give each plan the same file so the promoted cards match |
| File name | `Design/Brand/AppStore/pro-promotional-1024.png` |

The image must not repeat the app icon exactly; using the mark on paper rather
than the icon's framed composition keeps it distinct while staying on brand.

## Screenshot captions

Six 6.9" screenshots in this order, one caption each, under 40 characters.
The caption is the line set above the device frame; the screen underneath
must be an actual screen from the app.

| # | Screen | Caption | Chars |
| --- | --- | --- | --- |
| 1 | Capture | Say it. One tap, no sorting. | 28 |
| 2 | Today | Today shows what needs doing. | 29 |
| 3 | Memory | Memory keeps your words, searchable. | 36 |
| 4 | People and follow-ups | People and follow-ups, together. | 32 |
| 5 | Reminders | Reminders at a time or a place. | 31 |
| 6 | Pro | Ten captures free. Pro is unlimited. | 36 |

Screen notes:

1. Capture — the listening pulse with live text partway through "Call the
   pharmacy at six".
2. Today — Overdue, Today, and Coming up sections with a mix of tasks and a
   scheduled reminder.
3. Memory — the Pinned, Ideas, People, and Reference destinations with a search
   result showing the person's original words.
4. People and follow-ups — a person's profile in Memory with Remembered details
   and a Follow-ups section.
5. Reminders — the item editor on a place reminder ("when I get home") or a
   repeating reminder, showing the date, repeat, and place controls.
6. Pro — the Speak It Pro screen with both plans, annual pre-selected. Take it
   after the App Store Connect prices are final so the rendered prices are
   true.

## Age rating

Answer "None" to every content question. Speak It has no user-generated
content shared with others, no web browsing, no gambling, no contests, and no
unrestricted web access. Result: 4+.

## Review notes

The current review notes are section 1 of `Docs/APP_STORE_REVIEW_PACKAGE.md`
and are not duplicated here. The older draft in `Docs/APP_STORE_SUBMISSION.md`
§6 describes the paywall incorrectly and is superseded.
