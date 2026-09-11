# Decisions

## 2026-09-11 — Speech is framed at both ends, and the second end now has an owner

The everyday held-out set (235 captures, never tuned against) put the worst
routing families in one place: `run-on` 0/8, `rambling-intro` 1/6,
`trailing-goodbye` 2/7, `sequencing` 6/17, `multi-thought` 19/40. Merges
outnumbered splits 23 to 17, and 14 of the 18 title defects were framing
material still sitting in the shown title. The families that read what a
sentence *means*, once it has been cut out correctly, scored in the eighties
and nineties. The problem was the cutting, not the reading.

Two things were missing rather than wrong. Nothing in the app handled a
farewell — a search for one returned no code at all — so every "bye", "thanks"
and "that's it" a person ends a voice note with became the last word of a
title. And nothing treated enumeration as a boundary, although "number one …
number two …" is a speaker saying out loud where one thought ends.
`IntentConsolidation` owns the elaborative frame but stands down by design the
moment two substantive clauses are present, so it collapses rambling with a
single point and never sees a recording with three.

`DiscourseFrame` in `SpeechRepair.swift` owns the closing frame, and the clause
splitter gained the enumeration vocabulary it did not have. Both are decided
structurally rather than by phrase. A sign-off is a discourse move, not an
argument of a verb: "call Dana and tell her thanks" keeps its message because
the farewell is governed by `tell`, and a remainder that cannot end an English
clause blocks the cut so "I'll see you later" is not reduced to "I'll". An
enumerator is a discourse move rather than a post-nominal modifier: "number
two" only opens a clause when an instruction follows it, which is what leaves
"gate number two" and "apartment number three" alone without naming the nouns
they attach to.

`second`, `third`, `finally` and `one more thing` were already in the splitter
and are deliberately untouched. The new vocabulary is a separate alternation so
that widening the gate cannot change what those four do.

This is measured by `Tools/CorpusRunner/devsets/framing.tsv`, written from the
everyday set's per-family *rates* and from none of its sentences.

## 2026-09-08 — Keep monthly and annual with ten free captures

Retain $2.99/month and $14.99/year launch pricing against $29.99 standard annual. No weekly product or additional auto-renewing trial for launch. The ten lifetime captures already let users try the whole app without committing to billing. A seven-day trial remains a future experiment, not something category-level correlations can decide. Paywall sale claims now require the configured USD 14.99 StoreKit price as well as the build flag and date; other currencies show localized pricing without an unverified percentage. Remove the unconditional lifetime-rate promise until price preservation is verified in App Store Connect. See `PRICING_DECISION_2026-09-08.html` for evidence, tradeoffs and launch configuration.

## 2026-08-03 — Target iOS 17+

SwiftData and the selected SwiftUI APIs provide the simplest local-first foundation without compatibility layers.

## 2026-08-03 — Preserve enum values explicitly

Persistent models store enum raw values and expose computed typed properties. Unknown values can fall back safely, and migrations remain visible.

## 2026-08-03 — Repository owns all persistent mutations

Feature views use `@Query` for observed reads, but creation, updates, lifecycle changes, and deletion go through `ThoughtRepository`. This keeps write logic independently testable.

## 2026-08-03 — One item per manual capture in Phase 1

Phase 1 does no organization. Each text capture creates one item linked to one session. The one-to-many relationship is already prepared for future splitting.

## 2026-08-03 — Keep completed items recoverable

Completed items leave Today but remain in Inbox until archived, so accidental completion can be reversed without adding another screen.

## 2026-08-03 — Archive is reversible; delete is confirmed

Archive is the normal removal path. Permanent deletion is available only in the editor and requires explicit confirmation.

## 2026-08-03 — No external dependencies

The first milestone uses only Apple frameworks. This limits setup, privacy exposure, and early architectural uncertainty.

## 2026-08-17 — Referrals are isolated, verified, and launch-gated

The iPhone app still has no third-party package and the user's library remains
fully usable without a Speak It server. The optional referral program is a
separate Node service because a credible “Give a month. Get a month.” promise
needs a durable anti-replay ledger and Apple transaction verification.

The app creates an accountless Keychain UUID and credential, uses the UUID as
StoreKit's `appAccountToken`, and sends only referral identifiers and Apple's
signed transaction JWS. Rewards come back exclusively as Apple offer codes or
server-signed promotional offers; the app never edits an entitlement or an
expiration date itself. One referral can create one reward, one original Apple
transaction cannot be both parties, expired or revoked transactions fail, and
the referrer is capped at 12 rewards per calendar year.

Both public surfaces are configuration-gated. An empty referral API URL leaves
the existing “Share Speak It” row in place, and the website switch remains off
until the production service and Sandbox redemption flow are verified.

## 2026-08-17 — Summer launch pricing ends on October 22, 2026

(Extended from September 22 on 2026-08-23 so the window clears the beta.)

Annual Pro is $14.99 during the launch window and is intended to move to $29.99
at 12:00 a.m. America/Toronto on October 22, 2026 (`04:00:00Z`). That makes
“50% off” a comparison with the genuine standard annual price, not with twelve
monthly payments. Sale copy is build-gated and time-gated, and App Store Connect
must have the matching future price scheduled before the gate is enabled.

## 2026-09-07 — Monthly Pro is $2.99, and annual must stay below twelve months of it

The scheduled annual increase to $29.99 was going to ship against a $1.99
monthly, which makes the annual plan $6.11 a year *more expensive* than paying
monthly — while the paywall pre-selects it and badges it `BEST VALUE`. Under
guideline 3.1.2 that badge is a claim a reviewer can check, and it would have
been false the moment the price change landed.

Monthly moves to $2.99. That restores the ratio the rest of the category uses:
annual is priced at roughly ten months of monthly (Drafts Pro $1.99/$19.99, Bear
$2.99/$29.99, Timery $0.99/$9.99, checked 2026-09-07), so $2.99 against $29.99
is a genuine saving and the badge is true again. It also raises revenue per
monthly subscriber by half at a price that still sits with the most respected
indie note apps rather than above them.

Aggregate benchmark data argues for far more — a $8 median monthly across
Productivity, and roughly six times the realized first-year value per payer in
the high-priced tier. That median is set by products with teams and paid
acquisition, and it is not the shelf Speak It sits on. The evidence and the
reasoning are in `Docs/PRICING_AND_CONVERSION_2026-09-07.md`.

Weekly billing was considered and rejected in the same pass. No comparable
productivity or note app sells one; weekly-dominant apps monetize an install
worse than yearly-dominant apps; and every weekly price that would be worth
charging annualizes above the $29.99 annual plan.

The invariant this creates: **annual must stay below twelve months of monthly.**
Changing either price without the other re-creates the defect.

## 2026-09-07 — The launch price ends the offer, not the subscriber's rate

The paywall said "$14.99 per year until October 22, 2026," which reads as though
the buyer's own price expires on that date. What expires is the offer; App Store
Connect is configured to preserve the rate for subscriptions that began inside
the window. The caption now names which of the two ends.

`speakitapp.ca` still has to agree with the sheet. The page had been printing a
struck-through $3.99 monthly that the app never implemented, and it must not
claim a monthly discount, because `priceColumn(product:isAnnual:alignment:)`
only ever strikes a regular price through for annual. That correction belongs
with the website work in flight and is not part of this change;
`Website/README.md` carries the open item.

## 2026-09-07 — Pro is offered twice before the wall, and never blocks

The free-limit wall was the only place Speak It made its case. It is the worst
one: the person has already been stopped, and the thought they were trying to
save is what they are thinking about. It is also weeks late — roughly half of
all paid conversions across the store happen on the day of install, and a
lifetime allowance of ten captures that never renews puts the wall in week three
or five by construction.

`ProMoment` adds two invitations while the allowance still has room: one after
the first capture that actually spends part of it, and one when three remain.
Each is offered at most once for the life of the install, each is an ordinary
dismissible sheet with "Continue using Speak It free" on it, and neither blocks
anything. Practice captures during the tutorial are complimentary and never
reach the rule, so nobody is asked to pay before Speak It has worked for them.

Three constraints shaped the implementation:

- **Delivery is marked when the sheet appears, not when the moment comes due.**
  A capture made through Siri, Back Tap, or the share extension has no Speak It
  window to put a sheet on. The moment stays pending and is offered at the next
  launch instead of being lost.
- **A quiet screen outranks it.** Onboarding, practice, an open capture, the
  free-limit wall, and a referral invitation all defer it, and it waits rather
  than being dropped.
- **Entitlement state has to be settled first.** A subscriber whose cached
  access flag was cleared reads as free for as long as the StoreKit round trip
  takes. `canPresentProMoment` requires a resolved `.free` level, so the app
  cannot show a paywall to somebody already paying — the same defect the cached
  flag exists to prevent.

The whole timing rule is a pure function, `ProMoment.due(forCaptureCount:alreadyDelivered:)`,
so it is tested without a StoreKit session or the Keychain-backed ledger.

## 2026-08-03 — Voice is the default capture mode

The central waveform opens an immersive voice-first screen. Typing remains one visible action away and receives partial transcription whenever recognition fails.

## 2026-08-03 — External capture stays system-native

Back Tap runs a composed Shortcut containing Dictate Text and Speak It’s Save Thought App Intent. This preserves the user’s current context instead of opening the app solely to display a custom animation.

## 2026-08-03 — One capture implementation across surfaces

In-app text, in-app voice, Siri, and Shortcuts all write through `SwiftDataThoughtRepository` and preserve capture source plus original wording.

## 2026-08-03 — Two destinations plus a capture dock

The permanent Capture tab was replaced with a signature central pulse between Today and Inbox. Capture is an action, not a database destination.

## 2026-08-11 — Lock Screen Today shows counts, not task names, by default

The Today widget now offers the accessory families, so it renders on the Lock Screen, which anyone holding a locked iPhone can read. Task names are therefore hidden there unless the user turns on "Show task names on the Lock Screen" in Account & Settings. The choice is published inside `SharedTodaySnapshot`, so the widget extension has a single source of truth and needs no second cross-process preference. Home Screen families are unaffected and always show names.

## 2026-08-11 — Lock Screen Today opens the app instead of completing in place

Home Screen families keep their interactive completion buttons. The accessory families are glance-and-tap only: they open `speakit://today`. A pocket mistap on a locked phone must not silently finish a task.

## 2026-08-11 — The Today snapshot uses the same protection class as the store

`SharedTodayStore` wrote its snapshot with `completeFileProtectionUnlessOpen`, which permits writes while the device is locked but refuses new reads until unlock. Lock Screen widgets and background timeline reloads both read while locked, so that class produced a false "All clear". The snapshot now uses `completeFileProtectionUntilFirstUserAuthentication`, matching what SwiftData already uses for the primary store, so it is not weaker than the source of truth it summarizes.

## 2026-08-11 — The dock follows the scroll view, not a gesture

Dock visibility used to be inferred from a `DragGesture` layered over the scroll surface with `.simultaneousGesture`. That was wrong twice over. It hid the dock on screens with nothing to scroll, because the finger moved even when the content could not. And because it judged the finger rather than the content, ordinary swipes had to satisfy its axis and distance rules to count — an arcing thumb was written off as a row swipe, and any wobble reset the accumulated travel — so the screen felt like it was ignoring real swipes.

`MemoryDockScrollTracker` and its gesture are gone. `DockScrollPolicy` now reads the scroll view's own position: iOS 18 and later through `onScrollGeometryChange`, and iOS 17 through a geometry anchor on the first row, where a recycled anchor means the list is unambiguously past the top. Content that cannot move reports nothing, so a short screen can never hide the dock no matter how the swipe is thrown; `.scrollBounceBehavior(.basedOnSize)` keeps rubber-banding from faking movement. The dock hides after 56 pt of continuous downward scrolling, returns after 36 pt back up, and is always present within 24 pt of the top, including when momentum carries the list home with no finger on screen.

Nothing now competes with the scroll view for the drag, which is the point: swiping the list is the system's job, not the app's.

## 2026-08-11 — Today rows dropped custom swipe-to-complete

Removing the dock gesture fixed part of the problem, but swipes that began on a row still failed, and rows cover most of the screen. `SwipeActionRow` layered its own `DragGesture` on every Today row. Measured on an iPhone 17 simulator: a 221 pt vertical swipe starting on a row title moved the list zero points, twice in a row, while a 160 pt swipe starting on empty background scrolled with momentum. Swipes starting on ordinary `Button`s — the black card, section headers, the completion circle — always scrolled, so the drag gesture was the only offender. Raising its activation distance from 12 pt to 28 pt let the scroll through, but that only converts a reliable failure into an intermittent one, which is what "sometimes buggy" already meant.

The gesture is gone. The reveal it offered was a shortcut for the completion circle that is already visible on every row, so no action became unreachable, and Memory, Inbox, and the completed log keep their native `List` `.swipeActions`, which arbitrate correctly because UIKit owns them. Restoring the shortcut on Today means a native mechanism — moving those sections into a `List`, or a UIKit pan recognizer that refuses to begin on vertical movement — not another SwiftUI gesture over the scroll view.

## 2026-08-12 — Needs review names the missing input instead of flagging it

Every row in Today's "Needs review" section read the same hedge: "Tap to confirm, split, or change the time". The section could tell a person that something was wrong with three items without telling them what, so clearing it meant opening each one to find out.

Rows now name the gap — "Needs a time", "Needs a person", "Task or note?", "Might be 2 thoughts", "Needs confirmation" — and the editor puts a red `*` beside the one field that answers it, with a banner naming the ask. The asterisk is deliberately not on the row: `*` is form convention for a field you must fill on this screen, and the review row is a link to a different screen. Naming the gap is what makes the section scannable; the asterisk is what makes the editor navigable once you are there.

`speakWarning` is the first chromatic token in an otherwise monochrome palette, and is reserved for exactly this meaning: this item is waiting on input from you. It is muted rather than alert-red so a section holding several rows still reads calm, and clears 4.5:1 on `speakSurface` in both appearances.

Filling the field flips "Needs clarification" off automatically. Supplying the missing input is the entire reason a person opens a flagged item, so leaving them to find the toggle — and leaving the item in Needs review if they did not — would have undone the point of naming the gap. The flip is one-directional and visible in the toggle, and the banner resolves to "Ready to save" so nothing about the form contradicts itself.

`ClarificationRequirement` is derived from the item's fields at read time, not recorded when extraction flags the item. See KNOWN_ISSUES.md — persisting the reason is the better end state and needs a schema version.

## 2026-08-14 — A reminder is whatever the person asked for, phrased any way

"Give me a reminder to message Catherine in one hour" produced a note in Memory › Reference with no date and no notification. The cause was narrow literal matching: typing looked for a sentence starting with `remind me`, and reminder delivery looked for the substring `"remind me"`. The noun form — "give me a reminder", "set a reminder", "I need a reminder", "reminder to…" — matched neither, so the capture fell through to `.note`, which is a Memory type that Today never shows and `ReminderScheduleRequest` never schedules. It was not one bad phrase; it was every phrasing that names the reminder instead of commanding it.

`ReminderPhrasing` in `ThoughtOrganizer.swift` is now the single source of truth for both forms, and the three places that used to carry their own copy — the action-body strip that decides an item's type, the timing parser that decides delivery, and `ReminderCopy` that writes the row title and notification body — all read from it. One definition means a phrasing cannot be understood by one of them and missed by another, which is exactly how the reported bug was shaped.

Behind that sits a structural guarantee, because phrase matching will always have gaps. A time the person committed to now makes an item actionable regardless of its type: `ThoughtOrganizer` promotes a non-actionable type to `.task` when timing resolved a reminder, and `CapturedItem.belongsInToday` / `belongsInMemory` are written as exact complements of each other, so no live item can land in both destinations or in neither. Wording we cannot read costs a good title, never a lost notification.

A reminder resolving into the past ("tonight", said at 11pm) now asks for a time instead of saving one. iOS drops a past-dated notification silently, so the previous behavior was an item that looked scheduled and could never fire.

## 2026-08-14 — Day rollover is derived, never migrated

Today's sections are computed from a live reference clock, not stored in the items. Crossing local midnight therefore re-sorts the screen with no write, no churn, and nothing to undo if the clock was wrong — a scheduled sweep that rewrote `dueDate` at midnight would mutate user data on a timer, and a device asleep at midnight would miss it.

`referenceNow` is refreshed from four signals because none subsumes the others: a 60-second timer while the app is awake, `NSCalendarDayChanged` for the precise local-day boundary, `significantTimeChange` for carrier time and DST, and `scenePhase == .active` so a device that slept across midnight is correct before the first frame. `completedToday` reads the same clock as the sections so the whole screen agrees on which day it is.

Reminder notifications now pin `TimeZone.current` into their `UNCalendarNotificationTrigger` components. Without it iOS re-reads those wall-clock components in whatever zone the device is in at fire time, so travelling would move the notification off the instant the item's own date describes, and Today and the notification would disagree.

## 2026-08-14 — Ten free captures, once

The free allowance no longer renews monthly. `FreePlanAllowance.lifetimeCaptureLimit` is a one-time total: a person tries the whole product, then decides whether it is worth paying for, rather than waiting out a reset. This also resolves a mismatch flagged in `Website/README.md`, where the site already advertised "ten captures to try" while the app shipped a monthly ration.

The migration is non-destructive and one-directional. The `SpeakIt.freePeriodStartedAt` storage key is unchanged and `normalizedUsage` now only clamps, so an install that used its captures under the monthly plan keeps that count instead of being handed ten more, and a clock moved backwards cannot mint a fresh allowance.

## 2026-08-14 — Classification tracks the person's live settings

Everything that decides *what day it is now* — Today's buckets, "completed today", relative date labels, the organizer's default calendar — reads `Calendar.autoupdatingCurrent`. A plain `Calendar.current` is a snapshot taken when it was read, so a process that stayed alive through a flight, a manual time-zone change, or a calendar-preference change would keep classifying against the old settings.

The one deliberate exception is resolving a notification trigger. `ReminderScheduler` pins a concrete `TimeZone.current` into the trigger's components at scheduling time, precisely so the fire instant cannot drift afterwards. An autoupdating zone there would reintroduce the drift the pinning exists to prevent. The rule is: autoupdating for reading the present, concrete for fixing a moment in the future.

## 2026-08-14 — Wording that names no single instant asks instead of guessing

Two cases used to resolve silently into a time nobody said.

A spring-forward gap: "tomorrow at 2:30 AM" on a day whose 2:30 AM does not exist. `Calendar.date(bySettingHour:…)` slides past the gap, so the person would have been shown 3:00 AM and a notification would have fired at a time they never chose. The resolved instant is now checked against the wall clock that was asked for, and a mismatch goes to Needs review.

A bare past hour: "remind me at 8", said at 9:30 PM. Both 8 AM and 8 PM have gone, so scheduling tomorrow at 8 AM guesses at the half of the day *and* the day. That also goes to Needs review. An explicit meridiem is different — "8 PM" names one time of day, so rolling to the next 8 PM is not a guess and still resolves silently.

Fall-back ambiguity, where 1:30 AM happens twice, resolves to the first occurrence. That is now stated in code as `repeatedTimePolicy: .first` rather than inherited from a Foundation default that could change.

## 2026-08-14 — Foreground reconciles rather than trusting the last write

SwiftData and `UNUserNotificationCenter` are two stores that can disagree: a scheduling call that failed, a crash between saving and scheduling, notifications revoked in Settings, or a request orphaned by an edit. Rather than tracking which of those happened, every foreground rebuilds the pending set from the saved items and re-reads notification authorization. One cheap pass repairs all of them, and the app never has to be right the first time to end up right.

## 2026-08-14 — Schema V2: a time expression is stored as what it meant

`dueDate: Date?` was carrying at least five different meanings at once. "Tomorrow", "tomorrow at 3", "in one hour", "every day at 9", and "every 24 hours" all collapsed into one instant, and every feature downstream had to guess which one it had been. The guesses were wrong in ways that showed: "buy milk tomorrow" resolved to 9 AM and read as overdue at 9:01 the next morning, for a task that was never due at a time at all.

`TemporalIntent` now records the kind (`dateOnly`, `exactDateTime`, `relativeDuration`, `calendarRecurrence`, `durationRecurrence`), the components the person actually supplied, and the time-zone identifier and behavior. The resolved instants stay in `dueDate` and `reminderDate` — they remain what Today sorts by and what notifications fire at — so the intent is added meaning rather than a replacement. Interpretation now happens before resolution, and both are kept.

The single rule the type exists to enforce: **never add temporal precision the person did not express.** A day stays a day. A date-only reminder still needs a moment to alert at, and that moment is derived for the notification without ever being written back into the intent, so the item still knows no hour was given.

Two kinds of recurrence are now genuinely different. "Every day at 9 AM" finds the next local 9 AM; "every 24 hours" adds exactly 86,400 seconds. They agree on ordinary days and diverge in opposite directions across the two daylight-saving transitions, which is tested in both directions.

The intent is stored encoded in one attribute rather than as a dozen columns, because nothing queries its interior — the resolved dates cover every predicate the app makes — and a blob lets the shape evolve without another schema version. `temporalKindRawValue` is denormalized beside it because every Today row reads it.

## 2026-08-14 — Version 1 is frozen in `SchemaV1.swift`

Migration needs a real predecessor. When every version points at the live model classes, bumping the version silently redefines history too and the plan ends up comparing a schema against itself. `SpeakItSchemaV1` is therefore a frozen snapshot of the three models exactly as they were stored, never instantiated by the app and never to be edited — changing a field there would rewrite the past and could make an existing device's store unreachable.

The stage itself is lightweight, because version 2 only adds optional attributes: no row is rewritten and no existing value is read. What those columns *mean* for older rows is filled in afterwards by `backfillTemporalIntents()`, deliberately outside the migration, because that pass is idempotent and resumable and a migration stage is neither.

The backfill reconstructs intent by reparsing `originalTextSegment` against the item's own `createdAt` — possible only because Speak It never discards what a person actually said, which is the clearest payoff yet from that rule. It trusts the reparse only when the recovered day matches the day already stored; a mismatch means the date was edited by hand after capture, and the stored row wins. Resolved dates are never rewritten, so no existing reminder moves because the app learned to describe it better.

Verified against a real version-1 store on the simulator: 17 items and 15 sessions before, the same 17 and 15 after, with both new columns present and every row's intent recovered.

## 2026-08-14 — Unsupported is not ambiguous

"When I get home" is understood perfectly. Speak It knows exactly what was asked for and simply cannot schedule that kind of trigger yet. Storing that as ambiguity would have produced the wrong sentence in front of the person — "what did you mean?" instead of "place reminders aren't supported yet" — so `UnsupportedTrigger` is recorded on the intent and `ClarificationRequirement.unsupportedLocationTrigger` reads from it. A genuinely ambiguous date ("4/5") keeps the questioning phrasing, because there the question is real.

The same principle sharpened the numeric-date rule. "13/5" and "5/13" are not ambiguous at all — 13 cannot be a month, so the order is forced whatever the locale prefers. Flagging them would have been asking a question with only one answer. Only two numbers that could each be a month are genuinely undecidable.

## 2026-08-14 — A recurring series repeats at the clock it was asked for

Adding a calendar day across a spring-forward silently moves the time: "every day at 2:30 AM" resolves to 3:30 on the transition day. The worse half of that bug is what happens next — the following occurrence is computed from the drifted instant, so the series adopts 3:30 permanently after one transition. A single ambiguous day rewrites the reminder forever.

`RecurrenceRule.nextDate` now takes the intended wall clock from the item's `TemporalIntent` and re-snaps every occurrence onto it, which makes the two ambiguous cases explicit policy rather than emergent behavior:

- **A time that does not exist** (2:30 AM on a spring-forward day) fires at the first moment that does, 3:00 AM, and returns to 2:30 the next day. Not skipped, not an hour late, not permanent.
- **A time that happens twice** (1:30 AM on a fall-back day) fires once, at the first occurrence — a 24-hour gap rather than 25.

Both are tested, and so is the drift itself: one test deliberately omits the intended clock and asserts the series lands on 3:00 forever, so the parameter cannot quietly become decorative.

## 2026-08-14 — Provenance and truth are different fields

An item now carries three things: the original wording, the temporal intent, and the resolved dates. When someone opens the date picker and chooses August 20 at 4 PM, they have said something more precise than any sentence could, and the sentence must stop being authoritative — otherwise "Call Catherine tomorrow" stays `dateOnly` and the row hides the 4 PM they explicitly set.

Editing therefore rebuilds the intent from the edit and marks it `isUserEdited`. The original wording is never touched; it stays in `originalTextSegment` and in the capture session as provenance. The backfill only ever visits rows with no intent at all, so no later reparse can revert a correction.

## 2026-08-14 — A calendar date survives travel because it is stored as a date

`dateOnly` items are bucketed by their recorded `CalendarDay`, not by the instant in `dueDate`. Toronto's midnight on August 15 is the afternoon of August 14 in Los Angeles, so reading the instant would have moved the item a day backwards for someone flying west — the exact failure the `CalendarDay` type exists to prevent. "August 15" means August 15 wherever the person is standing, and that is now tested in four zones and in both directions of travel.

## 2026-08-14 — Every occurrence of a series carries the series' intent

Full-path QA found that `preferredWallClock` was correct everywhere it was passed, and simply never arrived. Completing a recurring item generates the next occurrence, and that generated `CapturedItem` was built without a `temporalIntent`. The first completion still worked, because the *original* item was there to read the intended clock from. From the second occurrence onward there was nothing to read, `nextDate` fell back to deriving each occurrence from the previous resolved instant, and one daylight-saving nudge became the series' new time forever — "every day at 2:30 AM" silently becoming "every day at 3:00 AM".

Every isolated test passed throughout, because they all handed `preferredWallClock` in directly. The failure lived in the wiring, not in the resolver, and only a test that drove the real repository across a real transition could see it. `SwiftDataThoughtRepository.carriedIntent(from:toOccurrenceOn:)` now copies the intent onto each generated occurrence, advancing only `day` — and advancing it in the intent's *own* calendar, so a series pinned to a named zone keeps counting that zone's days rather than the travelling device's.

The lesson generalizes past this bug: a value object can be provably correct and still never be delivered. Correctness of a temporal system is a property of the path, not of the resolver.

## 2026-08-14 — Temporal invariants, asserted rather than intended

Three rules are now treated as architectural invariants with tests that fail loudly rather than as comments that decay:

- **Resolving an intent never modifies the intent.** `TemporalResolver.resolve` and `nextOccurrence` are pure reads, asserted over every `TemporalKind` and both reminder settings. The 9 AM date-only alert hour is the standing temptation here: it is a property of the *notification* and is derived at resolution time, never written back.
- **The next occurrence of a calendar recurrence is computed from the intended wall clock, never from the previous resolved instant.** This is what the preceding decision restored end to end.
- **Speak It never adds temporal precision the person did not express.** "Tomorrow" is not midnight and not 9 AM; "every day at 9" is not "every 24 hours"; "9 AM London time" is not 9 AM wherever the device happens to be.

The fixed-versus-device-local distinction stays automatic and unsurfaced. A bare "9 AM" is `deviceLocal` and follows the person; a named zone is `fixed` and travels with the request. There is no settings toggle, because no one has asked for one and the defaults are right.

## 2026-08-14 — A place is a second trigger, not a second kind of time

Location reminders are built as a sibling of the temporal system, not an
extension of it. `ReminderTrigger` is `.time(TemporalIntent)` or
`.location(LocationIntent)`, and the two share almost nothing: different
resolution, different permission, different failure modes, different
reconciliation. Adding `.location` as another `TemporalKind` would have grown a
branch in every temporal code path that could not mean anything — there is no
wall clock for "when I get home", no daylight-saving policy, and no next
occurrence to compute from a previous instant.

What the two *do* share is the shape of the pipeline, and that shape is the part
worth copying:

```text
TemporalIntent → resolved Date   → UNNotificationRequest
LocationIntent → resolved region → CLCircularRegion
```

## 2026-08-14 — Meaning, resolution, and permission are three separate things

`PlaceReference` records what the person meant — `.home`, `.work`,
`.currentLocation`, `.named("costco")` — and never collapses to coordinates.
`ResolvedPlace` records how that currently resolves, and is disposable. Someone
who moves house has not edited any of their reminders: `.home` still means home,
`SavedPlaceStore` returns a new coordinate, and the next reconcile follows them.
Freezing "home" into a latitude at capture time would have thrown away the one
piece of information needed to do that.

Permission is the third thing, and it is **never persisted**. A reminder that was
authorized yesterday and denied today still means "remind me when I get home".
Writing the authorization beside the intent would freeze a fact about the device
into a fact about the request, and something would then have to decide which was
stale. `LocationAuthorization` is queried at reconcile time and passed in.

Losing permission therefore never deletes or disables a reminder. It changes only
what the app can currently do about it, and the reminder reports
`LocationReminderBlocker.permissionRevoked` until access returns.

## 2026-08-14 — Location failures are distinguished, not pooled

`LocationReminderBlocker` has twelve cases and a test asserting that no two of
them produce the same sentence. "When I get home" with no Home configured says
*Set your Home location*, never *What did you mean?* — the same principle that
made "unsupported" distinct from "ambiguous" in the first place, applied to a
feature that now exists. A place reminder that is understood and configured is
not a review item at all; the only location case that genuinely belongs in review
is a sentence whose place could not be read.

## 2026-08-14 — "Here" is a snapshot; Home is a pointer

The two look alike and behave oppositely, so the difference is worth stating.
`.home` is a *pointer*: it means "wherever home is now", and moving house
re-resolves every reminder that mentions it without editing any of them.
`.currentLocation` is a *snapshot*: the coordinate is the meaning. "Remind me
when I leave here", said at McMaster and carried to Toronto, must still mean
McMaster. Re-resolving it would silently rewrite the request into "wherever I
happen to be", which is not a reminder at all.

So it is resolved exactly once, just after the capture is durable, and never
again. Three consequences follow deliberately:

- **Capture never waits on it.** The fix is fire-and-forget. A location read can
  take seconds or never arrive, and capture durability outranks it. An
  unresolved "here" reports `locationUnavailable` — honest and recoverable —
  rather than a wrong coordinate.
- **A cached fix is preferred to a fresh one.** Counter-intuitive, but a fix iOS
  already holds is *closer in time to the moment the words were said*. Requesting
  a new one can take long enough for the person to walk out of the region.
- **Naming is opt-in, never automatic.** Reverse-geocoding would send the exact
  coordinate to Apple for a purely cosmetic label — the one location call the
  person never asked for, on the one path that is otherwise entirely on-device:
  speak a thought, freeze a coordinate, monitor a region, no network at all.
  "when you leave here" is already legible, so the label is not worth
  transmitting a position for. The editor offers **Name this place** instead,
  which makes the lookup the person's to initiate. Home/Work address search is
  different and stays automatic, because there the person typed the query.

- **A cached fix must be a *suitable* cached fix.** A `CLLocation` exists almost
  always; one 27 minutes old and accurate to ±1.4km is not where the person is
  standing, and accepting it because it was non-nil would pin the region onto
  the wrong neighbourhood. `CurrentLocationProvider.isSuitable` requires an age
  within 120s and accuracy within 100m, rejects CoreLocation's negative
  "invalid" accuracy, and rejects a fix dated in the future whose real age is
  unknowable. The same floor screens freshly delivered fixes — "just arrived" is
  not evidence of "good enough", since a first indoor fix can be kilometres
  wide. The accuracy bound is tied to `ResolvedPlace.defaultRadius` by test, so
  a looser fix can never place the pin outside the region it marks.

## 2026-08-14 — Permission escalates with the action, not with the screen

Core Location has two levels and Speak It needs both, at different moments.
Setting Home from your current position, and freezing "here", are single
foreground reads — `CurrentLocationProvider` asks for When In Use and stops
there. Arming a persistent arrive/leave reminder is the only thing that needs
the app woken while closed, and that is the one place the Always prompt is
raised, with copy that says why before iOS asks.

Opening Places therefore never triggers the strongest prompt. The escalation is
tied to the capability being used, not to a screen being visited.

One platform constraint shapes the UI: **iOS shows the Always upgrade prompt once
per install.** Every later `requestAlwaysAuthorization()` returns silently, so a
button wired straight to it becomes a control that visibly does nothing.
`LocationReminderMonitor.authorizationStep` records that the ask has been spent
and switches the affordance to "Open Settings". That flag records what the *app
asked*, not what the system granted — it is not a cached permission, and
`LocationAuthorization` is still queried fresh every time.

## 2026-08-14 — What the Privacy screen may claim about location

The screen says location stays on the device, is never sent to analytics, and is
not in iCloud Sync. Each was checked against the implementation rather than
assumed: `AnalyticsService`'s vocabulary contains no location term, and
`ICloudItemSnapshot` has no location field, so a place reminder is not synced.

It also says, because it is true, that address search and place naming ask Apple
Maps. `MKLocalSearch` and `CLGeocoder` are network calls; the query or the
coordinate goes to Apple. Claiming "nothing leaves your iPhone" without that
sentence would have been false. Note that naming a captured "here" sends a
coordinate to Apple automatically — the one location call the person does not
explicitly initiate, which is precisely why it is disclosed.

`PrivacyInfo.xcprivacy` is unchanged and correct: `NSPrivacyCollectedDataTypes`
describes what the *developer* collects, and Speak It collects no location.

## 2026-08-14 — The fix for a blocked place reminder lives beside the reminder

`Settings → Capture & reminders → Places` sets Home and Work, but it is not the
only way in. A reminder blocked on `missingHome` offers **Set Home location**
inside the editor it is already open in, pushes the same picker, and re-resolves
on return via `SavedPlaceStore.didChangeNotification`. Permission blockers get
the same treatment: the one that can be granted in-app has a button, and the one
that cannot says "Open Settings" rather than pretending otherwise.

Making the settings screen the only route would have meant leaving the thought,
finding a setting, and coming back to it — for a gap the app had just named on
screen. The blocker enum already distinguishes twelve reasons; this makes each
one's answer reachable from where the person actually is.

Note the asymmetry that stays: setting Home changes a *resolution*, so it is
global and every reminder follows it. Nothing about the reminder is edited.

## 2026-08-14 — Location usage strings must live in the real Info.plist

The project sets `GENERATE_INFOPLIST_FILE = NO` and points at a checked-in
`SpeakIt/Info.plist`. Under that setting Xcode ignores every `INFOPLIST_KEY_*`
build setting, so the two `INFOPLIST_KEY_NSLocation*` values in `project.pbxproj`
never reached the built app. Without `NSLocationWhenInUseUsageDescription` iOS
does not show the permission prompt at all, which meant no place reminder could
ever have been authorized on a device.

Nothing in Swift could fail this way, so `testTheBuiltAppDeclaresItsLocationUsage`
asserts the keys against `Bundle.main` — the built product — rather than the
source. Any future permission Speak It adds should be checked the same way.

## 2026-08-14 — A place and a time together are held, not halved

"Remind me to take out the garbage when I get home tonight" constrains both a
place and a time, and Speak It can enforce exactly one of them. The original
design kept both halves live and let each fire on its own, which was verified to
schedule the 8pm notification *and* monitor the region — the reminder would
arrive at 8pm regardless of location, and again on arrival. Preferring the place
was the alternative, and it is wrong in the other direction: it fires on a 2pm
arrival that "tonight" ruled out. Preferring the time discards the place the
person named.

There is no correct half. So the combination is stored in full, excluded from
both schedulers, and surfaced as `ClarificationRequirement.combinedTimeAndPlace`
— *"Place and time conditions aren't supported together yet — choose one"* —
with a time set in the editor counting as committing to the clock half. The day
is still kept on the intent, so real narrowing can be added later without the
sentence being re-captured.

This is the location half of the rule the temporal side already follows: never
pretend to support semantics that are not being enforced. It is also a
prerequisite for Home/Work configuration rather than a follow-up to it — the
double-fire was latent only because no Home can currently be set, and shipping
that UI would have activated it.

## 2026-08-14 — Version 2 had to be frozen before version 3 could exist

`SpeakItSchemaV2` was originally declared in terms of the live model classes.
That was invisible while version 2 was newest — the live shape and the version 2
shape were the same object. Adding an attribute to the live `CapturedItem` for
version 3 silently redefined version 2 to include it too, both versions in the
migration plan described the same schema, and opening any existing store aborted
inside CoreData on launch.

Version 2 now carries its own frozen snapshot, exactly as version 1 does. The
rule the V1 file already stated turns out to apply to every version and not just
the first: a schema version can only describe the past if it owns a copy of it.

## 2026-08-14 — A crossing is consumed, not merely reacted to

A place reminder had no record that it had ever fired. Stopping the region at
delivery time looked sufficient and was not, because the region is not the
record — it is rebuilt from the saved reminder on every foreground, and the saved
reminder said nothing. "Next time I get to the gym" therefore fired again on the
next visit, and would have failed device QA §3.5 while passing every test.

`LocationIntent.firedAt` is now written only after UserNotifications accepts the
delivery. Recording it before checking notification authorization retired a
one-shot that the person never received when notifications were off. Duplicate
callbacks during that await are closed by a short-lived main-actor in-flight
claim; after the await, the item is re-read and must still be active, incomplete,
present, and on the same trigger revision. If it changed while scheduling, the
just-added notification is withdrawn. A repeating reminder has no final firing
to record, so it uses the same marker with a five-minute cooldown that also
absorbs GPS boundary bounce.

This is the location counterpart of the temporal system's occurrence bookkeeping,
and it needed **no schema version**: `LocationIntent` is stored as a JSON blob in
`locationIntentData`, decodes tolerantly, and a row written before the field
existed reads back as "never fired" — which is the correct answer for it. The
V3-freeze rule in `SchemaV1.swift` is untouched and still stands: nothing here
adds a persisted property to a `@Model`.

Reconciliation excludes a spent one-shot rather than the resolver doing so. The
task is still outstanding, still in Today, still showing what it was waiting for;
only the region goes away. Retiring it in the resolver would have quietly
reclassified a live task as non-actionable, which is a much larger change than
"stop watching this place".

## 2026-08-14 — A region iOS refused is not a region being watched

`startMonitoring(for:)` cannot fail in place. It returns, and the refusal — no
network reachability, a radius above the device ceiling, a limit hit — arrives
later on `monitoringDidFailFor`. The reconciliation that registered the region
has by then already reported it as monitored, so the person is looking at a
reminder iOS is not watching. `monitoringFailed` is the twelfth blocker for
exactly that gap, and radii are clamped to
`maximumRegionMonitoringDistance` so one cause is removed rather than reported.

Failures are remembered for the run of the app and cleared on foreground and on
authorization change — never on the reconcile the failure itself triggers, which
would spin failure into retry into failure. A refused region is also excluded
*before* the 18-region budget is counted: letting it hold a slot would block a
reminder that could have been watched in favour of one that demonstrably cannot.

Deduplicating reminders that share a place was considered and rejected. It would
need a region identifier naming a coordinate rather than a reminder, and the
event would then have to be fanned back out to several items at delivery — from a
cold launch, before SwiftData has been read. Prioritising the budget and
reporting the overflow is honest at every size and needs no mapping to survive a
relaunch.

## 2026-08-14 — Reconciling must not re-arm a region iOS is already watching

Re-registering an identical region counts as a fresh registration, and a fresh
registration made while inside the region produces no entry event — that is
CoreLocation's documented behaviour, and it happens to be exactly what "remind me
when I get home" means: the *next* time. Since reconciliation runs on every
foreground, blindly re-registering would have reset the arrival for any reminder
about the place the person was standing in, every time they opened the app.

Regions are therefore compared by geometry before being replaced. Their
identifier carries the item, direction, trigger revision, and a compact resolved
geometry fingerprint. The revision rejects a callback that finishes after an
editor change; the fingerprint does the same for a Home/Work pointer that moved
without changing the stored wording. Legacy identifiers and stored intents both
read as revision zero, so the upgrade does not orphan an in-flight reminder.

## 2026-08-16 — Semantic near-neighbours are executable contracts

Semantic correctness is independent of temporal and location reliability. The
regression set therefore pairs phrases whose vocabulary is almost identical but
whose intent is not: “Catherine called me at 3” stays a fact while “Call Catherine
at 3” is an action; a negated reminder never schedules; a spoken correction keeps
only the final hour; a birthday fact stays in Memory while “wish Catherine happy
birthday” is a person follow-up; and “Finish Friday, remind me Wednesday” stores
Friday as the deadline and Wednesday as the notification.

Two implementation rules fell out of those contrasts. Conversational action
wrappers such as “remember to” are removed before type inference so the real verb
can establish a person follow-up. Separately, an action deadline and an earlier
reminder are parsed from their own clauses; they are never two candidates for a
single date. Date-only precision remains intact: the Friday deadline is stored as
a day, while the notification derives its standing 9 AM delivery without writing
that invented hour back into the intent.

## 2026-08-17 — First-run learning follows the first saved thought

The app now opens in Light appearance when no preference exists. This is a
default, not a migration: a stored System or Dark selection continues to win.
Onboarding still begins with capture, then uses the real saved receipt to show
where the thought went. Only after that success does one short screen explain
the product boundary — Today is for action; Memory is for knowledge — and offer
capture-anywhere setup as an optional next step.

Capture dismissal follows the durability rule. X closes an empty surface at
once, presents Save & Close / Discard / Keep Editing once words exist, and closes
an already-processed capture without risking the item. The header is laid out
against the keyboard-reduced window rather than the editor's ideal height, so X
cannot be translated offscreen while typing.

## 2026-08-17 — Only an obvious accidental duplicate is suppressed

In-app voice and text captures reuse an existing result only when the same
source repeats the same normalized wording within 15 seconds. External capture
keeps its stricter five-second retransmission window. Normalization ignores
case, accents, whitespace, and punctuation for matching while the original
transcript remains untouched. A reused capture returns explicit result metadata
so every entry point can say **Already captured** and avoid consuming the
lifetime allowance. Anything outside the narrow window is saved independently;
possible intentional repetition is never silently merged.

Shared reminder wording is propagated to every split clause only when the
command itself carries the shared time. This lets “Remind me tomorrow at 9 to
buy milk and call Mum” schedule both actions, while “Remind me to call Mum
tomorrow, buy milk, and remember Catherine likes sushi” becomes a reminder, an
unscheduled task, and a Memory fact instead of three vague reminders.

## 2026-08-17 — First value must be durable, perceivable, and replayable

Opening the first capture is not onboarding success. The completion flag is now
written only after the repository returns a saved result; cancelling an empty or
permission-blocked attempt returns to Welcome. The first **Remembered** receipt
does not disappear on a timer, and VoiceOver turns every single-item receipt
into an explicit confirmation. This keeps the evidence of trust onscreen long
enough to understand or inspect it, while still making a relaunch from that
receipt land in the product instead of restarting onboarding.

Capture-anywhere setup is useful expansion, not part of the first-value path. It
is offered as a dismissible Today card only after two successful capture
sessions. Account & Settings now owns a permanent **Learn Speak It** guide so a
person can revisit routing, examples, reminders, places, external capture,
privacy, and recovery without replaying onboarding. Empty states use concrete
phrases to teach by doing, without implying that those are the only supported
commands.

## 2026-08-18 — Actionability is read separately from item type

`ItemType` was answering two different questions: *what kind of thing is this?*
and *does the person still have to act on it?* Deriving the second from the
first meant the weaker answer could veto the stronger one. "Get shampoo
tomorrow" resolved `dateOnly(Aug 4)` correctly, the type rules did not
recognise the verb "get", `note` is not actionable, and a correct date was
discarded on the way out — the item lost its day and landed in Memory. Seven
release-blocking misroutes shared that one mechanism.

`Actionability` is now a deterministic intermediate reading — `actionable`,
`outstanding`, `event`, `knowledge`, `ambiguous` — derived from wording alone
and independent of the type taxonomy. It is the authority on which surface an
item belongs to; the type is corrected to agree with it. Two invariants govern
it, and both are tested rather than assumed:

- Temporal information may corroborate actionability but can never create it.
  "Catherine called me at five" names a clock and is still a memory.
- A sentence that is actionable never loses an already-resolved `TemporalIntent`
  because the secondary type guess was uncertain.

The correction is deliberately one-way. `ambiguous` means the reader had no
opinion, and no opinion never demotes a type that was read from the wording;
nor does it overrule a type the person named themselves, which is why "Idea for
tomorrow's team meeting" is still an idea and not a Wednesday commitment.

Every rule is written as an intent family with a historical counterexample
family beside it — `I forgot to call Catherine` is outstanding, `I called
Catherine` is not, and `I didn't call Catherine because she cancelled` is
closed rather than owed, which is why the rule cannot be a search for the
string "didn't call".

## 2026-08-18 — Temporal, recurrence and location contracts are stated, not inferred

Five temporal phrasings had no defensible answer, so each now has one written
down rather than emerging from whichever branch ran first:

- **"tomorrow at this time"** is the same wall clock tomorrow, taken from the
  capture instant. Not the capture plus 24 hours — those differ by an hour twice
  a year, and the person meant the clock face.
- **"on the 15th"** is the next 15th that has not happened, date-only. The
  ordinal suffix is required, so "at 15" stays a clock and "15 eggs" stays a
  quantity.
- **"end of month"** is the last day the month actually has, rolling to next
  month once it passes.
- **"first thing"** is the app's one morning hour, deliberately the same 9 AM a
  date-only reminder alerts at. Three private definitions of morning would be
  three ways to be wrong; when this becomes configurable it becomes configurable
  once.
- **"next week"** stays Needs review. A week is seven days and none of them is
  more defensible than the others, so picking Monday would look on the row
  exactly like something the person had chosen.

**"Next Friday" is Friday of the following calendar week**, and plain "Friday"
is the nearest upcoming one. Speakers genuinely disagree about this, so the
contract is deterministic and the resolved date is shown on the receipt, which
makes a wrong reading one tap from right. Alternative readings are no longer
treated as defects.

Recurrence is now parsed as recurrence *before* anything resolves an instant.
"Every day at nine" previously reached the one-off resolver first, which
correctly answered "the next nine is 9 PM tonight" — a correct answer to a
question nobody asked — and then built a daily series on top of it. A series
owns its own clock, and its first occurrence is computed from the rule. Monthly
series gained `OrdinalWeekday` so "first Monday every month" is 12 occurrences a
year rather than 52 or a drifting day number; it decodes as absent on rules
written before it, exactly like `intervalSeconds`.

Location is read as grammar rather than as a list of place names. A place name
ends where the action begins ("when I get to the store **buy** batteries"),
using the same verb vocabulary `Actionability` owns so the two cannot drift.
"Remind me at X to Y" asks what X is before deciding: a clock reading wins, so
"remind me at five to call Mom" stays a time and "remind me at the pharmacy to
pick up the prescription" becomes a place. Compound place-and-time triggers
still go to Needs review; they are not being built for v1.

## 2026-08-19 — One person resolver, and a missing target is a question

"Who is this about?" was answered twice, by two rules that could not see each
other: `ThoughtOrganizer.inferredPerson` read the object of a communication verb
for Today, and `PersonNameInference.memoryName` read the subject of a fact for
Memory. A sentence that was both a memory and about somebody — "Catherine
called me at five" — fell between them and reached Memory's People collection
under no name at all. The corpus scored `person` as metadata, so all nine of
these sat green while the user-visible consequence was that a person they had
told Speak It about could not be found again.

`PersonMention` is now the single answer, read by both surfaces. It carries the
label, the source range it came from, a confidence and a role, and it resolves
three families: the object of a verb aimed at a human ("Call Catherine", "Send
Catherine that thing", "I met Alex yesterday"), the actor of something done to
the speaker ("Catherine called me at five"), and the subject of a human fact
("Alex likes golf", "Alex's brother is visiting").

**Evidence, not capitalization.** A capitalized word is not a person: "Finish
the Alex report", "Read about Ada Lovelace", "Buy milk at Walmart", "Apple
announced something" and "Meet the deadline Friday" all name nobody, and the
phrase has to be functioning as a human participant before it becomes one. The
same guard is what stops a name absorbing the words beside it — *Alex Friday*,
*Catherine Tomorrow*, *Mom Five*, and *Wait Sam*, which was a person invented
out of a self-correction and then used to address a message.

**A missing target and a non-named target are different states.** "Call the
dentist tomorrow" describes who to reach and needs no help. "Call them tomorrow"
is a follow-up with nobody on the other end, and filing it as a healthy task
hands the person a reminder later that cannot tell them who to call — so it goes
to Needs review as `.person`, which already knew how to ask.

Two supporting repairs made this reachable. A self-correction run is matched as
a run — people stack "no wait", "sorry no" — because matching only its last word
left the earlier ones in the repaired sentence. And Memory's People grouping
moved out of the view body into `MemoryPeopleIndex`, so a test can prove the
consequence the corpus was blind to: capture the sentence, then look under
People for the human it named.

## 2026-08-19 — An operation claims its clause, not the whole utterance

The semantic corpus was expanded from 182 to 402 cases, and the largest cluster
of failures had one cause: `CaptureOperationDetector` read the entire transcript
at once. That is correct for "Don't buy milk" and destructive for any capture
that manages one thing and states another — "Don't remind me about the dentist
anymore, but remind me to call Mom at six" produced **no items at all**, and a
cancel target consisting of the whole sentence.

Losing a thought the person just spoke is the failure this app cannot have, so
`partition(_:)` now reads clause by clause and returns the operations alongside
the text that is still creating something.

The split is deliberately allowed to be wrong. When no clause reads as an
operation the **original text** is returned rather than the rejoined pieces, so
an over-eager boundary can only fail to find something — it can never damage an
ordinary capture.

One older decision is preserved inside it. A bare "and" after a denial is
genuinely ambiguous: "don't buy milk and call support" can negate one conjunct
or both, and English does not say which. That ambiguity is owned on purpose by
`hasMixedPolarity`, which holds the whole utterance for review, so a
negation-led capture splits only on a comma or a contrastive "but".

## 2026-08-19 — Three temporal contracts settled by the expanded corpus

Each was genuinely two-sided, and each had to become one thing.

**A named weekday that is today means the next one.** "The deadline is Monday",
said on a Monday morning, resolved to that same day — showing a week-away
deadline as due within hours. Somebody who meant today would have said today.

**An alarm's bare hour is the morning.** Everywhere else a bare hour resolves to
its next occurrence, which is the right general rule and reliably wrong here:
"wake me at 6:30", said at 10 AM, resolved to 6:30 that evening. The window is
4–11 rather than 1–11, because "set an alarm for the meeting at 3" names a 3 PM
meeting and nobody sets a 3 AM alarm.

**A person's birthday is knowledge, not an appointment.** A dated commitment
stated with a copula — "the party is Saturday" — now belongs on Today, which is
what stopped those sentences from losing their date entirely. Birthdays and
anniversaries are explicitly excluded from that rule: an annual fact about
somebody is filed under that person in Memory, which is where people look for it
and what the repository tests already pinned.

## 2026-08-19 — Exceptions to a repeat are asked about, never dropped

"Every Friday at five, remind me to submit the report, except this Friday" built
a correct weekly series and discarded the exclusion in silence. That is the
worst available outcome: the reminder then fires on precisely the day the person
excluded, and nothing on screen ever admitted a word had been ignored.

Speak It has no way to store an exclusion, so a repeating request carrying one
goes to Needs review. This is the same rule the temporal side already follows —
never pretend to support semantics that are not being enforced.

## 2026-08-21 — A date says when something is true, not that there is something to do

Reported from TestFlight: "I want to remember that Priya's birthday is on
December fourth" arrived on Today, under *When you have time*. The rules meant
to prevent exactly this were already written — birthdays are deliberately
excluded from the scheduled nouns, and `Actionability` opens by declaring that
time never promotes history — and three separate mechanisms defeated them.

The wording rule was anchored to the first word. `isRecordedFact` tested
`^remember`, so the moment somebody framed it the way people speak, the sentence
fell out of the fact family and into the obligation family — because *want to*
is an obligation lead. A filing instruction was read as a commitment.

The taxonomy rule then discarded the person. `category` became `.people` only
for a `note`, so once the sentence was promoted to a task, Priya was resolved,
stored, and never used to place the item. It reached neither People nor
Reference.

The model layer was undoing the other two anyway. `isTimeCommitted` counted any
`dueDate` or `reminderDate`, so a fact that resolved a date was pulled onto
Today no matter how carefully it had been read. This is the mechanism that
mattered most, because it made the classifier's care irrelevant.

The contract is now stated in one line and enforced at both layers:

> **A date tells Speak It when something is true. It does not by itself mean the
> person has something to do.**

- A dated fact about a person Speak It can name → Memory, filed under them.
- A dated fact naming nobody → Memory, under Reference.
- Explicit reminder or action wording → Today, whatever it is about. "Remind me
  on December 4 that it's Priya's birthday" is a reminder, and still about Priya.

`isTimeCommitted` now means *a moment the person asked to be interrupted at* —
`reminderDate` alone. Nothing is lost by narrowing it: every type that can carry
a deadline is already actionable. The one path that relied on the old rule was a
note scheduled by hand in the editor, and that is now promoted to a task at the
point of editing, where an explicitly typed date is an explicit intention rather
than an inferred one.

Two smaller faults surfaced on the way and are fixed with it. A past report
about somebody — "Alex moved to Toronto in September" — had no rule of its own,
so the only signal left in the sentence was a month and it became an
appointment; there is now a past-report family, and it yields to a scheduled
noun so "the meeting was moved to Thursday" keeps its Thursday. And a month
followed by a spoken ordinal ("December fourth") resolved no date at all, only
the digit form did, which is why the original report landed with no date rather
than with the wrong one.

## 2026-08-21 — Clause count is not item count

The second TestFlight report: a rambling paragraph that meant one thing became
three rows, one of them a fabricated event. "I was thinking earlier today" has
no verb and no intention in it, and it acquired a date and arrived on Today as
an appointment nobody had made.

The splitter breaks on commas and conjunctions, which is correct for list speech
and wrong for narrative speech, where the same connectives join a person to
their own train of thought. Nothing upstream of it was asking whether the
clauses were separate intentions or one intention being talked towards.

`IntentConsolidator` now runs after speech repair and before splitting. It is
deliberately **a veto and never a splitter**: it can only collapse to one item,
it fires only when the wording is positively narrative, and when unsure it does
nothing and lets the existing splitter run untouched. Two conditions must both
hold — at most one clause that could stand alone as something to do or keep, and
an elaborative signal that is not itself the intention. That asymmetry is what
keeps "Call Mom tomorrow and Alex Friday" at two items: its second clause is not
substantive alone, but nothing about the sentence is elaborative either, so this
stage has no opinion.

The bias is chosen, not incidental. **Over-splitting costs more than
under-splitting.** The original transcript survives on the `CaptureSession`
either way, so a merged item leaves the person one row to read, while a split
one leaves them junk to delete — and, as observed, junk that can carry a date.

When it collapses, the row title becomes the head intention with its framing
stripped ("call the dentist tomorrow"), the quote stays the entire capture, and
the text handed to the organizer excludes trailing explanations — a reason can
carry a date of its own, and "call the dentist because my appointment is
Thursday" is a call with no day.

## 2026-08-21 — A stated closure is a fact; the subject decides which

The boundary case left open by the dated-fact work, now settled rather than
left to whichever rule ran first. "The office closes December 24" resolved a
date and reached Today, because a calendar cue with no recognised verb around
it fell through to the calendar-commitment rule and became an appointment.

The rule is the birthday rule, applied without an exception for one grammatical
shape:

> A statement that merely describes when something is true stays knowledge. A
> date does not create an obligation.

- "The office closes December 24" → Memory / Reference
- "Remember the office closes December 24" → Memory / Reference
- "Remind me before the office closes December 24" → Today
- "I need to go to the office before it closes December 24" → Today

Implemented as a narrow descriptive-verb family — a thing opening, closing,
expiring, renewing or resuming — which is a property of the thing rather than
an appointment. "Starts", "ends" and "begins" are deliberately excluded, since
they are as often about something a person attends: "the movie starts at 8" is a
plan.

The corpus immediately produced the counterexample that completes the rule:
**"Application closes Friday"** is the identical grammar and the opposite
intent. An office closing is a fact about the office; an application closing is
the last moment somebody can act. So the subject decides here exactly as it
already does for the copular case, and `deadlineNoun` is the counterpart to
`scheduledNoun` — application, registration, submission, ballot, entry, RSVP.
Either kind of subject outranks the descriptive reading whatever the verb.

## 2026-08-21 — A failed recovery always has a way out

TestFlight found the dead end: a protected recording whose recovery returned
"No speech detected" stayed listed under "Ready to recover", the only offered
action was the retry that had just failed, and the Today card "One capture needs
attention" could never be resolved. Retry was also the only thing the row could
do, so the person had no way to say "these words are gone, let it go".

Three rules now hold together:

- **A failed attempt never costs the recording.** Retry can be attempted as
  often as the person likes, and nothing is deleted on failure.
- **Deletion always works.** `CaptureDraftStore.deleteRecording(id:)` does not
  depend on the recognizer, the repository, or the audio file still existing,
  and it records a tombstone so a checkpoint written before the deletion cannot
  bring the recording back on the next launch.
- **The interface stops promising what it cannot deliver.** Once the recognizer
  has specifically found no words, the row reads "Couldn't recover" and the
  section reads "Needs attention" rather than "Ready to recover", and the launch
  auto-recovery pass stops re-running that recording every activation.

Failure wording is keyed on `CaptureRecoveryFailureKind`, not on the
recognizer's own string. "Something went wrong" and "The operation could not be
completed" tell a person nothing about whether to retry, retype, or delete.

## 2026-08-21 — Trigger, actionability, and person attribution are independent

Three TestFlight captures exposed one repeated design error: one semantic axis
was being allowed to answer a different question.

- "When I go home remind me to take out the garbage" names a place trigger. It
  never owes the temporal parser a clock. A configured Home arms an arrival
  reminder; an unconfigured Home asks the person to set Home.
- "Let me create a feature in the future…" is proposal language. The verb
  *create* names the content of the idea, not a commitment to execute it.
- "Sarah doesn't like sushi" is still a fact about Sarah. Negation changes the
  fact's polarity, not its owner and not its destination.

The product contract is therefore dimensional:

- **Actionability** decides Today versus Memory.
- **Item type** describes what was captured: task, idea, note, event, and so on.
- **Person attribution** answers who a thought is about, independently of
  whether the item is a `personFollowUp`.
- **Trigger** answers what event should interrupt the person: a clock or a
  location boundary.

`People` already exists as a general Memory category; it is not an alias for
`Person follow-up`. A person fact is a Note with a person and appears in People.
A follow-up is an actionable type and appears in Today. Positive and negative
preferences, allergies, and biographical facts follow the same person path.

The audit also found the same axis leak inside time parsing. Duration grammar
correctly reads the article in "in a minute" as one, but clock grammar reused
that vocabulary and read "idea for a quieter basket" as "for one". Clock hours
now have a narrower vocabulary that cannot consume articles in ordinary prose.

## 2026-08-21 — Semantic evidence is grammatical, not substring-based

A 37-case collision audit found that individually reasonable rules were still
allowed to claim text on lexical coincidence:

- `ideal` and `ideation` became Ideas because they contain `idea`;
- `homework`, `workout`, and `network` became Work because they contain `work`;
- `for two-factor` became two o'clock;
- `get paid`, `reach a decision`, and `are ready` became named places;
- a bare `no` was treated as self-correction and deleted everything before it;
- `When I get home, remind me…` split the condition and action into two items.

The repair is a set of boundaries rather than a larger phrase list. Taxonomy
uses whole-word phrase matching; explicit Idea/Shopping/Event type wins where
that type owns the category, while a person follow-up may still be Work or
School. Bare clocks require actionable or reminder context. Arrival verbs
require a saved-place word or spatial connector. `no` is a correction marker
only after punctuation/dash or alongside a positive repair cue. A fronted
conditional fragment is inherited by the action after it, while a complete
conditional action remains its own item.

Unsupported non-spatial conditions are neither locations nor missing times.
They remain one actionable item in Needs review, retain
`UnsupportedTrigger.condition` in the existing temporal-intent blob, and say
**Trigger not supported**. No SwiftData schema change is required.

The corpus route oracle now follows the production invariant: Today means an
actionable type **or an explicit reminder**, not merely an actionable type.
This closes a test blind spot where a reminder could be lost or invented while
the type label made the expected route appear to pass. The corpus is now 439
cases with 0 critical and 0 behavioral disagreements; the full suite reports
451 passed, 5 skipped, and the unsigned Release build compiles cleanly.

## Reschedule is a capture operation (2026-08-23)

"Move my dentist reminder to Friday", "push the gym back an hour", and
"postpone the dentist" are requests against items the person already has —
the third verb alongside cancel and complete, and the last piece of assistant
parity the operation model was missing. `CaptureOperation` gains
`.reschedule`; the request carries the spoken destination as words
(`newTimingText`), because resolving them needs the store: "back an hour" is
measured from the item's scheduled moment, never from the clock.

Application goes through the same `update(_:with:)` path the editor uses, so
notifications, recurrence, and location metadata move with the time. The
matcher, the one-confident-match rule, and the never-guess fallbacks are all
inherited unchanged. Three deliberate boundaries:

- A destination must *look like a time* before the sentence reads as an
  operation — "move the couch to the garage" stays an errand.
- A pronoun target ("move it to Monday") never claims the store: inside a
  capture it usually corrects something said in the same breath, and the
  existing correction machinery owns it.
- A move with no destination ("postpone the dentist") is held with the item
  attached rather than guessed.

A reschedule is non-destructive and spends no free capture.

## 2026-08-24 — First-run learning happens inside the real product

A passive feature tour makes the person translate screenshots and promises into
an interface they have not yet learned. First run is therefore a resumable
practice journey through production screens. One action example lands in its
exact Today row and Maya profile; one idea example lands in its exact Ideas row
and opens the real stage picker. Teaching stays attached to the object through
a spotlight and explanation immediately below it, so the next action is visible
where it will be used later.

Practice data is a distinct capture source, not sample content disguised as a
real memory. It uses the normal organizer and repository, but cannot consume the
lifetime allowance, schedule an interruption, enter an iCloud snapshot, or
leave a deletion tombstone. Finishing or ending the tutorial deletes tutorial
sessions and their recurrence, notification, alarm, location, pin, idea-stage,
shopping, and pending-operation metadata. Cleanup is scoped and idempotent; it
never deletes a real capture. A new person therefore begins the real product
with no example rows and all ten free captures.

Permissions are not bundled into an inaccurate wall of switches. **Make Speak
It ready** puts every capability in one place, explains its value, reports live
state, and invokes the real system-owned request or app setup. Microphone and
speech, notifications, Home, location reminders, alarms, and Capture Anywhere
remain individually optional. A denied permission routes to Settings, and the
person can always finish for now. This center remains available from Account &
Settings after onboarding.

The tutorial persists its phase and exact item identifiers. Relaunch resumes
the live step; missing tutorial content restarts only that practice mission.
This supersedes the passive first-capture explanation described in the
2026-08-17 onboarding decisions while preserving their durability rule: a
capture is successful only after the repository has safely saved it.

## 2026-08-24 — Tutorial guidance names one visible target and stays optional

A tutorial highlight is part of the layout, not decoration outside it. Its
outline stays inset within the real row so a list or scroll container cannot
clip the sides. When the tutorial opens an editing surface, it names and
highlights a concrete next target—the title field or a suggested idea stage—
while preserving a visible no-change path.

Practice language demonstrates ordinary speech rather than a command syntax.
The idea example therefore uses “I had an idea…” and the title formatter accepts
that conversational frame without producing a blank title. Every practice
capture offers **End tutorial**, and optional system setup offers **Done for
now**. Capture Anywhere shows one chosen method and its instructions first;
alternative methods expand only on request and collapse after selection.

## 2026-08-24 — Understanding must not depend on how the recognizer punctuated it

`SpeechTranscriber` runs two recognizers: the iOS 26 `SpeechAnalyzer` when its
model is installed, and `SFSpeechRecognizer` otherwise — on iOS 17-25, while the
analyzer model downloads, and whenever the analyzer fails to start. They do not
punctuate identically, and neither punctuates a fast talker reliably.

Nearly every rule in `SpeechRepair.swift`, and every clause boundary in
`ThoughtExtractor.swift`, was originally written against a comma. That made the
app's behaviour a function of *which engine answered*, which is not something a
person can see, control, or report a bug about. It also made one defect arrive
over and over wearing a different sentence: a repair would be added for one
phrasing, and the next recording would render without the comma and fail again.

The rule from here is that **meaning survives the rendering**. Two things
enforce it:

- `ClauseJuxtaposition` finds where one instruction ends and the next begins
  when nothing announces the boundary, so a run-on breath splits the way a
  punctuated sentence does. It is deliberately narrow — a verb that can open an
  instruction, preceded by a word that cannot be continuing one, with a real
  clause already behind it — and it refuses a boundary inside an open place
  trigger, in front of a conjunction, or after an article.
- `RenderingInvarianceTests` replays the entire semantic corpus through the
  renderings a recognizer actually produces (commas dropped, all punctuation
  dropped, all lowercase) and asserts the same contract holds. The release gate
  is the corpus gate: zero CRITICAL and zero BEHAVIORAL.

A correction is the one place where punctuation still carries weight, and only
in one direction. A repair may replace a slot it can see — "meeting at three
sorry four" is unambiguous — but it may not *discard* the words in front of it
without either a pause or a restated verb. Without that rule, "tell Sam sorry I
missed his call" became "tell I missed his call".

The lowercase axis is reported rather than gated. A recognizer that lowercases
a name has destroyed information the app cannot recover, and person-boundary
detection legitimately reads capitalization as evidence. The cost stays visible
in the suite's summary instead of being silently accepted.

## The refinement model is bounded by the rules, not trusted over them

`ThoughtExtractionEngine.extract` hands the capture to Apple's on-device model
(`IntelligentThoughtExtractor`) whenever `shouldRefine` says so, and returns
what the model produced. `shouldRefine` returns true for **every** capture the
rules split into more than one row, plus anything flagged for review, plus any
transcript containing a comma, "and", "also", "then", "actually", "not" or
"said" — 31% of the corpus, and far more of real speech, which is longer and
messier than a corpus sentence.

The corpus does not test that path. `CorpusEvaluator` calls `extractWithRules`,
and so does `RenderingInvarianceTests`. The suite is green on the simulator
because Apple Intelligence is unavailable there and the model call falls back to
rules, so the gap was invisible: on a device with Apple Intelligence the
multi-row captures this project worked hardest on were exactly the ones the
rules no longer decided.

That is the punctuation problem one level up — behaviour depending on invisible
state — and the same answer applies. `RefinementGuard.preservesEverything`
requires that every row the rules found still corresponds to some row in the
refinement, matched on the words that distinguish it from its siblings. The
model may re-segment, merge, split, retitle, recategorize, and spot a person the
rules missed. It may not make something disappear. Failing the check keeps the
rules reading, so the worst case is the behaviour every other device gets.

`RefinementGuardTests` replays the corpus through that seam: for every multi-row
capture, deleting any one row must be rejected, and the rules' own output must
always pass — the second half matters because a guard that was accidentally too
strict would silently switch the model off everywhere and no test would notice.
The guard is compiled outside `canImport(FoundationModels)` on purpose, so it is
testable on machines where the model never runs.

This bounds the damage. It does not make the model's reading *correct*, and
nothing here measures that. Doing so needs a device with Apple Intelligence
enabled: replay the corpus through the async path and count cases fixed against
cases broken. Until that measurement exists, the model's quality contribution is
unknown in both directions.

### Why not a cloud model on Wi-Fi

Rejected. Availability would become a function of network state, so the same
sentence would categorize differently depending on where the person was
standing — the exact class of defect `RenderingInvarianceTests` exists to
prevent, except observable by the user and unreportable as a bug. It also puts
user-authored text off-device, which changes the privacy nutrition label, the
policy, and the local-first premise; and per-capture inference against a
$1.99/month subscription makes the heaviest users the least profitable. Apple's
on-device model costs nothing per capture, needs no backend, and is keyed to the
device rather than the network.

### Which Foundation Models variant the refinement uses

`SystemLanguageModel.default`, not `SystemLanguageModel(useCase: .contentTagging)`.

The tagging adapter was the original choice and it was the wrong tool, by
Apple's own description of it. The content-tagging model "isn't a typical
language model that responds to a query from a person" — it evaluates and groups
its input, and if you ask it questions it produces tags about asking questions.
Apple's guidance names two conditions for preferring `general`, and this call
meets both: the content is not an action, object, emotion or topic, and the
constraints are more complicated than the tagging model's maximum-count support.
What `IntelligentThoughtExtractor` asks for is instructed extraction returning a
seven-field `@Generable` struct — exact source quotes, inherited context spans, a
natural-language title, a person, a confidence — which is not tagging in any
sense the adapter was built for.

The `respond` call also passes `GenerationOptions(sampling: .greedy)`. The rules
path is deterministic by construction, and a refinement sampling randomly on top
of it meant one capture could organize two ways on two days with nothing to
explain the difference. Greedy sampling does not make the model correct; it
makes it repeatable, which is the precondition for a disagreement being
reportable as a bug rather than as a mood.

**Neither change is measured.** Both are documented-correct and both compile,
but the refinement path needs an A17 Pro or later device with Apple Intelligence
enabled to run at all, and no such device was available. The change is one line
each and trivially revertible. The measurement that would settle it is the one
already described above: replay the corpus through the async path and count
cases fixed against cases broken.

## 2026-08-26 — Version 3 is frozen against a real store, not against the source

Version 3 was the last version still declared in terms of the live model
classes, which meant "version 3" was whatever `CapturedItem` happened to be at
the moment the plan was read. Version 1 and version 2 had each been frozen only
after the version above them existed, and version 2's freeze was a repair to a
launch abort that had already reached the build. This one is deliberately done
before there is anything to migrate to: the first version 4 attribute would have
silently redefined version 3, made two entries in the migration plan describe the
same schema, and stopped every existing store from opening.

The two roles were the actual defect, so they are now two declarations. Every
numbered version is history and owns a copy of it. `SpeakItSchemaCurrent` — a
one-line alias, today at `SpeakItSchemaV3Live` — is the live shape the app
addresses, and is the only one allowed to move. `PersistenceController.schema`
uses that, never a snapshot, because a container built from frozen classes would
hold entities the repository has no way to fetch. When version 4 arrives it
takes over that alias and version 3 stays exactly where it is.

Freezing is worthless unless the frozen copy is provably the same schema the
unfrozen one was, and re-reading the source proves nothing. So the anchor is
external: `SpeakItTests/Fixtures/SpeakItVersionThree.store` is a real SQLite
store written by the last build that shipped an unfrozen version 3, and
`SchemaFreezeTests` pins the Core Data entity version hashes that build stamped
into it —

```
CaptureSession   nilPIQj+q/80eRq7ELBuQBdnQiZ2/hkGMV4TQ6QxEHI=
CapturedItem     mNIAGWB3h/BSblsq6iWJCD9bm4LmhOglGBbynuVnH9I=
UserPreferences  Qb7pwhuu/qNfNofKI1l6tIrP9gHAUz/lNSt/TcOXpC8=
```

— and checks that the frozen snapshot still stamps them, that the live models
still stamp them, and that the fixture opens under the frozen snapshot with **no
migration plan at all**, which it can only do if the two are the same schema.

Injecting one property into the live `CapturedItem` was used to confirm the
freeze does something. The frozen-snapshot assertion and the no-plan fixture open
both kept passing — version 3 no longer follows the live models — while the live
assertion failed with the instruction to add version 4, and every store open
failed loudly in the test suite. That is the same abort that used to be
discoverable only on a phone that had already taken the update.

Nothing about interpretation changed: the corpus is byte-identical across all
four renderings, and no file the rules path compiles was touched.

## 2026-08-26 — The interpreter's verdict is stored, not re-guessed

The pipeline has always decided how settled a reading is. `OrganizedThought`
carries a `SemanticState` — `resolved`, `underspecified`, `contested`,
`unsupported` — with a named `SemanticGap` when it is not resolved, and that
value was computed for every capture and then dropped between the organizer and
the row. So every screen that needed to explain *why* something was unclear
reconstructed a reason from the item's other fields, after the fact, in code
that never saw the sentence.

The reconstruction was wrong in a way a person notices. "Let me know if the
meeting is Tuesday or Wednesday" names two days and settles on neither, so
`TemporalCommitment` returns `.underspecified(.ambiguousTemporalScope)`, the
date is dropped and the type is set to `.unclear` — and `.unclear` was the only
trace of any of that left on the row. Needs review therefore asked "Task or
note?", a question about something the person had been perfectly clear about,
while the thing they actually left open went unmentioned.

Schema version 4 adds two optional columns, `semanticStateRawValue` and
`semanticGapRawValue`. Two raw strings rather than one blob because there is
exactly one state and at most one gap per reading, and neither needs to be
queried; the enum carries an associated value and cannot be `RawRepresentable`,
so `SemanticState.Kind` names the state and `init?(kind:gap:)` puts the two
halves back together. A kind that requires a reason and arrives without one is
**not** repaired into `resolved` — it reads back as unknown, which is the only
direction this type is allowed to fail in.

`CapturedItem.clarificationRequirement` now reports the recorded gap in
preference to the derivation, and the derivation stays for everything the gap
does not answer. Two classes of reason deliberately still outrank it: a held
destructive request, and what the device is waiting for on a place trigger.
Neither is a reading of a sentence — they are facts about the item and the
phone — and answering them with what the wording left open would send the person
to the wrong screen. Five review reasons were added for gaps no existing case
carried; the two that were already carried (`unsupportedCondition`,
`uncertainClauseBoundary`) reuse the cases that already said the right thing
rather than being duplicated.

**No backfill, on purpose.** Version 2 could reconstruct temporal intent because
the resolved dates it was recovering were already on every row. Nothing
equivalent is true here: what a build that never recorded a verdict would have
concluded is not in the fields it left behind, and inferring it is precisely the
guess this version exists to replace. Pre-version-4 rows keep `nil` and keep the
old derivation, and `hasRecordedSemanticState` makes that observable. Writing
`resolved` across them was the one unrecoverable option available and would have
claimed that every unreviewed row from before the upgrade had been understood.

The state is a record of a decision, not an input to one. Nothing about
destination, actionability, scheduling or typing reads it, which is why the
corpus is byte-identical across all four renderings and the held-out numbers did
not move. Wiring `permitsAction` into scheduling would be a semantic change and
belongs to whatever pass decides to make it.

Generated recurrence occurrences carry the verdict of the row they came from
rather than being left empty. They are the same reading, not a new one, and
empty means "nothing was ever recorded" — which would be false.

## 2026-08-29 — The tutorial counts itself, in one number, everywhere

Each tutorial surface used to name its own position or none at all: "PRACTICE 1
OF 2" on a capture screen, an unnumbered teaching card on the real Today and
Memory screens, an unnumbered setup screen at the end. Nothing told the person
how much was left, and on Today and Memory nothing said a tutorial was running —
a card asking to "Change this thought" read as the app making a demand.

`TutorialStep` is now the single eight-item list every surface counts against,
and one `TutorialStepHeader` renders the badge, the count, and the bar wherever
teaching happens: both practice captures, the four spotlight steps, Capture
Anywhere, and readiness. The finished screen shows the same bar full.

While a step happens inside the real app, `TutorialBanner` is a layout row above
the destination stack, not an overlay or a safe-area inset. Today and Memory
hide their navigation bars, and both of those approaches let scroll content
start underneath the banner: the screen header stayed half-covered and a pushed
Memory screen lost its Back button behind it.

Each spotlight button also states what it will actually do. All of them open
something real — an editor, a person, a stage picker — so "Opens this thought.
Save or close it and the tutorial continues." is the sentence that distinguishes
the tutorial offering a next step from the app issuing an instruction. The
sheets those buttons open cover the banner, so they carry the step count
themselves.

## 2026-08-30 — The Action Button trip is shortened, because it cannot be skipped

Assigning Speak It to the Action Button for someone is not possible, and neither
is linking straight to the pane where they would do it. iOS ships exactly three
public Settings URLs — `openSettingsURLString`, `openNotificationSettingsURLString`
(15.4), and `openDefaultApplicationsSettingsURLString` (18.3) — and the
`AccessibilitySettings.Feature` list the Back Tap step already uses has six
cases, none of them the Action Button. `App-Prefs:root=` reaches the pane but is
private API. So the trip stays manual, and the only thing left to improve is how
much of it a person has to carry in their head after leaving the app.

Three things carry it. `openSettingsURLString` removes the app switch: it lands
on Speak It's own page when the app has one, and on the Settings root when it
does not, and Action Button is a top-level row visible without scrolling either
way — so step one's copy names the destination first and treats the Speak It
page as the detour it sometimes is. A one-line strip above the steps says the
whole trip once — Action Button › Shortcut › Speak It Capture — with
non-breaking spaces inside each name, so at accessibility text sizes it wraps at
the separators instead of through "Speak It Capture". And the picker frame shows
the search field with "speak" already typed, because `BeginListeningIntent` is
an App Shortcut sharing that list with every personal shortcut the person owns.

Controls is left in the help disclosure rather than the card. It is a second
route of equal length on iOS 18+, and offering two equal paths to someone who
has not done this before costs more than it saves. The existing test card is
still what closes the loop: nothing here can read the assignment back, so a real
outside-the-app capture remains the only proof it worked.

## 2026-08-31 — A title drops the framing, not the words

Nobody says the task first. They say "I've got to", "we need to", "make sure I",
"I keep meaning to", and the thing to do follows. The row title used to keep all
of it, because `ThoughtTitleFormatter` was a list of six literal prefixes —
"I need to", "I have to", "I should", and three imperative wrappers — while
`ActionabilityReader.obligationLead` already held eighteen. Routing knew "I've
got to pick up the dry cleaning" was an obligation; the title did not, so the
row read back the person's own throat-clearing.

`ObligationFrame` replaces the list with the paradigm. A frame is
`subject hedge* link+`, anchored at the start and contiguous, and that shape is
the safety argument rather than a style preference: `^(i|we) … need to` cannot
match "I told Alex to get the wrench" or "I need a wrench to fix the gate",
because the noun phrase is physically in the way. No tagger has to decide it, so
nothing about the reduction depends on how the recognizer capitalised the
sentence. Measured over 1,216 utterances the reduction changed 78 titles, changed
no row's count, type, route or date, and introduced no word the speaker had not
said.

Three properties are asserted rather than intended, in `ObligationFrameTests`,
because a corpus `title` disagreement grades `.cosmetic` and only ever reports.
The reduction is **deletion-only** — its output is a contiguous subsequence of
its input, so a title can never contain an invented word. It is **idempotent**,
because launch maintenance re-feeds the formatter its own output. And it is
**invariant** to lowercasing, comma loss and full stops, which is why the gap
between a frame and its complement accepts a comma: "I gotta, you know, finish
the essay" and "I gotta you know finish the essay" are one sentence dictated by
two engines.

### Safety by omission, and why the vocabulary is deliberately incomplete

`had to`, `was supposed to`, `meant to`, `needed to`, `refused to`, `managed to`,
bare `got to`, `like to` and every negated auxiliary are absent from the link set
on purpose. A form that is not listed can never sit inside the span that gets
deleted, so a past, habitual or released obligation survives into the title
untouched — "I had to cancel the appointment" is not retitled "Cancel the
appointment". Adding a past, negated or noun-taking form to that set is the way
this breaks, and the control block of `ObligationFrameTests` exists to catch
exactly that edit.

The complement boundary refuses four things outright, and refusing is the
failure mode of the whole design: a stranded infinitival `to`, a negator, a
coordinator, and a pseudo-cleft pivot. The negator case was already live damage —
"I should not sign the lease until Dana looks at it" shipped as **"Not sign the
lease until Dana looks at it"**, and "I need to not forget the passport" as
**"Not forget the passport"**. Four such inversions, plus rows titled "Rarely",
"And I will" and "But I probably won't", are fixed by refusing rather than by a
new rule.

### The person's own wording outranks the reducer

`displayTitle` has no `isUserEdited` flag the way `temporalIntent` and
`locationIntent` do, and giving it one is a versioned schema migration that does
not belong in a presentation change. So `update(_:with:)` passes
`reduceFrames: false` — somebody who types "We need to talk to the landlord" gets
what they typed — and `HandEditedTitleStore` records the ids whose framing would
not survive an automatic pass, so launch maintenance skips them. A title whose
framing the formatter agrees with is not recorded, because freezing the title of
anybody who only changed a due date would be worse than the problem.

### Launch maintenance runs once per formatter version, not once per launch

`polishPersistedDisplayTitles()` re-polished every row in the store on the main
actor at every launch, and re-entered on its own output. It is now stamped with a
formatter version, so an existing backlog is brought up to the current contract
exactly once — cheaper than before, not more expensive — and a bad reduction
becomes a bug that can be fixed rather than damage already written. It also
requires a **fixpoint** before writing: `polished` is written for a transcript,
and `ReminderCopy` inside it will read an already-stored title as one more spoken
sentence, turning "Set an alarm for 6 AM" into "Alarm". A title is only moved to
somewhere the current formatter would also have put it first time.

### What was deliberately not built

Not a tagger. `NLTagger` labels "I", "we", "she" and "they" identically as
Pronoun, so it cannot say whose obligation a sentence states; the surface form is
the only evidence, and two pronouns is a paradigm rather than a vocabulary. A
tagger would also add a capitalisation dependency to a function that is currently
invariant by construction.

Not the on-device model. `IntelligentThoughtExtractor` already produces a
`suggestedTitle`, but Apple Intelligence needs an A17 Pro or newer chip, and
`shouldRefine` only consults it when a capture is ambiguous to *split*. Most of
the defects above would never have reached it on any hardware.

Not the comma rewrite — "Go to friend, do this" for "I need to go to friend to
do this". It deletes a word to read worse than the infinitive it replaces, and
that sentence already reduced correctly before this change.

Not a reduction of Memory rows. The obligation layers are unreachable for a
non-actionable type, which is what keeps "My blood type is O negative" a
statement instead of an order.

## 2026-08-31 — The Lock Screen rectangular slot lists three tasks, not two

The accessory rectangular slot was rendering the header plus two task names
because two was assumed to be what it fits. It was measured instead, on a
device-sized simulator Lock Screen: the slot renders four lines cleanly and
clips a fifth at both the top and the bottom. The header is one of the four, so
three names is the honest maximum, and `LockScreenTodayVisibility
.rectangularTitleLimit` now carries that number where a test can pin it.

Lock Screen accessory widgets do not scale with Dynamic Type — the layout is
byte-identical at the largest accessibility content size — so the fourth line
does not need a smaller-count fallback.

In the same pass, the header count stopped repeating itself. With names hidden
the body already reads "12 open", so a "12" in the header said the same number
twice; the header count now appears only when names occupy the body and the
total would otherwise be lost.

A task name longer than roughly twenty characters still truncates with an
ellipsis at this width. That is left alone deliberately: the alternative is
shrinking the text, and a Lock Screen glance is worth more legible than
complete.

## 2026-09-01 — The Lock Screen slot is a list with a next item, not three names

Three names stacked in the rectangular slot rendered as a paragraph: same size,
same weight, same colour, nothing for the eye to catch. It was present rather
than useful.

Each row now carries a marker, and the rows are no longer equals. The first —
which is genuinely the soonest due, because `todayItemOrder` sorts by date
ascending and the snapshot preserves that order — is set semibold with a
brighter marker and shows its clock time on the trailing edge. The rest are
lighter and unadorned: *this is next, and these are also today*.

The time is on the first row only, and that is a measured decision rather than a
timid one. A trailing time costs about a third of the 146 pt row; spending it on
every line truncated every name to roughly ten characters — "Pick up th…" — which
is a schedule nobody can read. Confining it to the row being acted on returns the
other two to about twenty-one characters.

Two supporting rules:

- A whole hour drops its `:00`, but only where an AM/PM marker survives to
  anchor the number. On a 24-hour clock a bare "17" is not a time, so those keep
  their minutes. This is worth roughly two characters of task name.
- A time is shown only for a task due on the day the widget is drawing. The slot
  has no room to say *which* day, and a bare "5:00 PM" against tomorrow would be
  a lie.

VoiceOver still speaks every row's time, not just the first. It has no width
budget to spend, so there is nothing to buy by withholding it.

One bug fell out of writing the test, and it was the interesting part. The first
draft formatted the row time with `dueDate.formatted(.dateTime...)`, which
silently reaches for `TimeZone.autoupdatingCurrent` — the *device* zone —
while `isDate(_:inSameDayAs:)` was answering "is this today?" in the zone of the
calendar it was handed. On a Mac in Hong Kong running a Toronto fixture the two
disagreed by thirteen hours, and 5 PM rendered as 4 AM. The formatter is now
built with `Date.FormatStyle(locale:calendar:timeZone:)`, pinned to
`calendar.timeZone`, so the zone that decides the day is the zone that prints
the clock. In production both resolve to the device, so this was invisible until
a test supplied a calendar of its own — which is exactly the failure mode that
makes `TemporalFullPathTests` fail on a Mac outside North America.

## 2026-09-01 — A contraction is the same obligation, so it is cut the same way

"I hafta drop the car off at the shop on Thursday" produced **two** rows: a
Memory note titled "I hafta", and the errand. "I have to drop the car off at the
shop on Thursday" produced one, correctly routed and dated. The two sentences
mean the same thing, and the app disagreed with itself about how many thoughts
were in them.

The cause is a coincidence rather than a rule. Every multi-word obligation frame
ends in `to`, and `"to"` is the first entry in
`ClauseJuxtaposition.clauseInternalLead` — the set of words after which a verb
continues the clause instead of opening a new one. So every frame in the language
is protected from clause splitting *for free*, except the single-token spoken
contractions. That set named `gotta`, `wanna` and `gonna`, and did not name
`hafta`, `oughta`, `needa` or `better`. Exactly those four were cut.

Both halves of the repair are needed, and shipping either alone is worse than
shipping neither:

- `clauseInternalLead` gains the four, so the cut never happens;
- `ActionabilityReader.obligationLead` gains them too, so the uncut sentence is
  *read* as an obligation and reaches Today.

Measured on a 233-capture stress set, gluing the fragment back on **without** the
second half — the obvious fix, widening `ThoughtExtractor.isFragment` — is a net
regression: 37 rows merge and **all 37 move a Today task to a Memory note**, 19
lose a resolved due date, and one errand is destroyed outright. `isFragment` is
the net, not the cause, and it is left alone.

### Why `better` is admitted only with its subject

`obligationLead` is tested **unanchored** (`ActionabilityReader.isOutstanding`),
so a bare `better` would read "the weather is better tomorrow" as an errand.
Only `i better`, `we better`, `'d better` and `had better` are admitted.
`hafta`, `oughta` and `needa` are listed bare because they carry no other meaning
in English. The gating corpus contains three sentences with a comparative
`better` — "The book was better than the film" among them — and they are now
pinned as controls beside the six positives.

### What the corpus could not see

The same edit measured **zero change across all 1,036 gating-corpus utterances**:
byte-identical output, no merge, no wrong merge. The corpus contained no instance
of any of the four forms, so it could neither detect the defect nor certify the
fix. Nine `.dictation` cases now close that hole, and `count` is CRITICAL
severity, so an invented row fails a release rather than being reported.

The general lesson is the one already recorded for the corpus elsewhere: it is a
regression net, not a coverage measure. A defect it cannot see is not a defect
that is absent.

## 2026-09-04 — The logo is the mark raised out of paper

A day of logo exploration (pencil-drawn lettering and bars, stippled bars,
debossed paper; see `Design/Brand/Research/pencil-on-paper.md` and
`Design/Brand/Explorations/`) ended with Calvin choosing the plainest of the
paper directions: the five bars as clean capsules, black, raised out of light
paper with a soft shadow, and its twin in white on black.

- **The mark is unchanged in geometry** — 1 : 2.1 : 3.03, the same pitch and
  weight — and is now a clean capsule everywhere. The hand-inked edges from
  the 3 September refresh are retired behind `Bars.inkedByHand` in
  `generate_brand.swift`; they were an authorship cue the emboss makes
  redundant, and the capsule survives 60 pt better.
- **The emboss is a treatment, not a second logo.** `generate_emboss.mjs`
  writes it: the app icon (black on light paper, 1024, opaque), the website's
  social card, and 4K/8K masters in both polarities for the site, listing and
  print. Everything that must be one colour or tiny — the in-app wordmark PDF,
  the topbar glyph, the favicon — is the flat capsule.
- **The icon flips to light.** It had been white bars on near-black; it is now
  black bars on light paper, matching the chosen master. The favicon follows
  (black bars on a white tile with a hairline edge so it keeps its shape on a
  light tab strip).
- **Two generators, one geometry.** The Swift generator owns the wordmark,
  lockups, mark SVG, favicon and topbar fragment; the Node generator owns the
  relief and the files that need SVG filters. Both hard-code the same bar
  constants (368 / 600 / 720-1512-2184); change them in both or the icon and
  the wordmark drift.

## 2026-09-03 — The name is drawn, not typeset

Speak It's wordmark used to be a `Text("Speak It")` in the caption style, and
the app icon was the five-bar mark in black on white. Both are replaced by a
single drawn brand system in `Tools/Brand/generate_brand.swift`.

- **The mark stays.** The five rounded voice bars are the symbol people already
  know from the dock button, the Lock Screen control and the website, and their
  proportions (1 : 2.1 : 3.03, fully rounded) are unchanged.
- **The lettering is new.** `SPEAK IT` is a monoline, geometric, all-caps
  wordmark with open tracking and rounded terminals. The cue is the HEYTEA
  wordmark: one stroke weight for every letter, letters that are plain shapes
  rather than typeface details, and enough air between them that the name reads
  as a mark and not as a line of text. Every glyph is geometry in the generator,
  so there is no font to license, embed or subset.
- **The icon inverts.** White bars on near-black (`#0A0A0A`), which is what the
  favicon and the dock capture button already were; the white icon had been the
  odd one out. The shipped icon carries no lettering, because iOS renders it at
  60 pt where a wordmark becomes texture; `Design/Brand/SpeakIt-AppIcon-v2-Alt-
  Wordmark-1024.png` is the lettered alternative if the listing ever wants it.
- **In-app, the wordmark is a template PDF** (`Wordmark.imageset`) sized by a
  `@ScaledMetric` on the caption style, so it tints with `speakMuted` and grows
  with Dynamic Type exactly as the text did. `SpeakItWordmark` keeps its
  accessibility label and header trait, so VoiceOver still says "Speak It".

Re-run the generator after changing any letter; it rewrites the app icon, the
brand masters, the asset-catalog PDF and the website favicon together so they
cannot drift.

## 2026-09-03 — Render cost is paid once per fact, not once per row

A performance pass over what an iPhone 13 feels, with the rule that nothing
here may change a schema or an answer — only how often the answer is computed.

- **Intent decoding shares one `JSONDecoder`.** `CapturedItem.temporalIntent`
  and `locationIntent` sit inside the predicates Today and Memory run over every
  row on every render, and each read built a fresh decoder. One shared static
  instance; the decoded value is unchanged.
- **A person's name is memoized per item.** `MemoryPersonNameResolver.name`
  runs the whole mention parser, and Memory's home asked for it for every row
  several times per render. It is now cached by item ID and invalidated by the
  three fields it derives from, mirroring `ItemPresentation`'s delivery cache.
- **Lookups by ID use a predicate.** `findItem(withID:)` and
  `performReminderAction` fetched the whole table to find one row; every
  notification action and editor save paid for it.
- **Regexes go through `speakItCached`.** Three call sites compiled their
  pattern on every call; one of them ran twice per row in a person's detail.
- **The editor reads the cached delivery.** `inferredReminderDelivery` re-ran
  the whole pipeline in `body`. It now asks `ItemPresentation` — the same
  reading the row glyph and the scheduler use — so the editor also stopped
  explaining an alert that a different parse would fire.
- **The word embedding loads at launch, off the main actor**, instead of inside
  the first Memory render.
- **Today's minute timer is built once**, not once per `body`; created inside
  `body` it re-subscribed on every render and the tick restarted with it.

Not done, on purpose: `TodayView` still recomputes its section chain several
times per pass and its reminder signature still joins a string. Both are real
but touch layout code and need a visual pass; see `PERFORMANCE_BENCHMARKING.md`.

## 2026-09-03 — Small readiness fixes found by walking the app

- The paywall's two adjacent links were "Privacy" and "Policy". They are now
  "How data is used" (the in-app explainer) and "Privacy Policy" (the page).
- "Sync now" reported "Library is up to date"; the product calls it Memory.
- The setup screen's selected method row is `speakInverseSurface`, which is
  white in dark mode, and its icon halo and RECOMMENDED pill were
  `Color.white.opacity(0.12)` — invisible there. They use `speakInverseInk` now.
- "Finish later", the way out of the microphone test, sat at 3.1:1 on black.
  It and the timing caption are lifted to clear 4.5:1.
- The Share extension's labels follow Dynamic Type, its close button meets
  44 pt, and its error copy no longer promises audio import.
- The generic repository alert no longer shows a SwiftData error code. A
  system-shaped message is replaced with what happened and that nothing saved
  was lost; messages the app wrote itself pass through.
- The 9 pt badges (priority, TRY THIS, RECOMMENDED) scale with Dynamic Type.
- The free-limit headline interpolates `FreePlanAllowance.lifetimeCaptureLimit`
  instead of hard-coding ten, and the paywall uses one phrase, "Pro is being
  prepared", for the products-not-loaded state.

Checked and left alone: "Add to Calendar" presents `EKEventEditViewController`,
which on iOS 17 and later needs no calendar permission or usage string, so the
absence of `NSCalendars…UsageDescription` is correct; the paywall's privacy URL
has no trailing slash because the site is deployed with `trailingSlash: false`.

### The on-switch has its own tint

Every switch inherited the app-wide `.tint(.speakInk)`, and `speakInk` is white
in dark mode — so an on switch was a white track under iOS's white knob, a blank
pill with no visible state. `Color.speakToggleTint` is the ink in light mode and
a mid grey in dark mode, applied to the nine toggles directly. The global tint
stays, because links, progress bars and buttons want the ink.

## 2026-09-04 — International clock and calendar forms

Re-probing the register lane of the pipeline sweep found its four largest
open clusters still reproducing, and every one was a *confident wrong answer*
rather than a missing one: "the meeting is on 15 August at 11" kept the 11 and
resolved the day to **today**; "the train leaves at 06:20 tomorrow" resolved to
18:20; "remind me at half five tomorrow to call mum" rang at the 09:00
date-only default; "call the bank at ten pass six" resolved to 22:00 because
the bare-clock fallback took the *offset* as the hour; and "remind me at half
five to take the bins out" became an arrival trigger for a place called
*half five*, which no map can find, so the reminder was silently dead.

Each is now read by a rule shaped the way `Docs/PIPELINE_SWEEP_FINDINGS.md`
asks for — structure, not vocabulary:

- **Day before month.** A number, a month, and then a function word, a
  clock, or nothing. An open-class word after the month makes it a quantity
  ("order 12 December calendars"), and "may" followed by what a modal takes
  stays a modal. Measured 17 of 17 positives, 0 of 10 negatives moved.
- **A leading zero is a 24-hour clock**, and unambiguously morning. The
  bare-hour default no longer flips 01:00–07:59 to the afternoon when the hour
  was zero-padded. "6:20" without the zero keeps its evening default.
- **Waking frames** — "be up at 6", "get up at 6", "wake up at 6" — commit an
  hour to the morning the way "set an alarm for 6" already did.
- **"Half five"**, behind a time preposition, is 5:30. "Half a dozen", "half
  an hour" and "half the team" are not clocks because they have no preposition.
- **The 24-hour clock said aloud** — "seventeen thirty", "eighteen hundred",
  "zero nine hundred", "nine hundred hours" — carries its half of the day
  with it and can never be rolled to the evening.
- **The clock face by ear.** "Ten pass six", "ten passed six", "ten too six",
  "ten two six" are the canonical face with the connective written by sound.
  Accepted only behind a time preposition, because "two" and "pass" are
  ordinary words: "the code is ten two six" is not a clock.
- **A clock is not a place — closed by the grammar, not by a second list.**
  `LocationIntentParser` decides whether "remind me at …" names a place with a
  whitelist of a dozen clock shapes, and every form outside it became a place.
  The first draft of this change added an oracle asking the temporal grammar
  about the object of the preposition; the mutation gate reported that
  deleting it cost nothing, because `TemporalIntentParser` reads the time
  first and discards a searchable place whenever a time resolved. So the
  oracle came out, and register C1 closes as a consequence of the clock rules
  above: "half five", "seventeen thirty", "sharp 5" and "sixish" are times the
  grammar now reads, and a time wins.
- **"Sunday week"** and **"a week on Sunday"** are the Sunday after the coming
  one. **"Last Tuesday"** is the Tuesday that has gone, and dates nothing;
  "the last Tuesday of the month" is a different phrase and is left alone.
- **"The first draft" counts drafts.** An ordinal naming a day stands alone or
  is followed by a function word; an ordinal followed by an open-class word is
  counting that word. The closed classes tested — prepositions, conjunctions,
  determiners, pronouns, auxiliaries, the clock and daypart words — are
  complete by definition, which is what makes this grammar rather than a list.

Two behaviours changed deliberately. "Set an alarm for half six" and "wake me
at half seven" used to decline safely with no time; the alarm rule now commits
them to 06:30 and 07:30, as it does for "set an alarm for 6:30". And "remind me
at breakfast", "at teatime" and "at supper" join lunch as conventional anchors
(08:00, 17:00, 18:00) instead of becoming place names.

The router had copies of the same knowledge and they fell behind. `Actionability`
decides whether a copular sentence is a commitment with its own day cue and
clock cue lists, and both knew only the North American forms: "my flight is on
22 September" was a fact about flights while "my flight is on September 22" was
an event, and "lunch with Aoife at half one" resolved to 13:30 and was then
filed as a fact, which throws the resolved time away. The day cue now reads the
day-first order, and the clock cue asks the spoken-clock grammar beside its own
list — as a union, so it can only add a commitment. Not the whole clock grammar:
a bare digit behind "for" is a quantity as often as an hour ("options for one
person", "reasons for two-factor authentication"), and the first draft that
asked the whole grammar broke exactly those. Also closed in passing: "get up",
"get going", "get some rest" were shopping rows, because "get" plus a
non-determiner reads as a grocery list; particles and quantifiers are closed
classes and are now excluded, while "get shampoo" stays a list.

Review pass (the same day). Eight independent reviewers read the diff; what
changed as a result: the object of "get" is read by the sentence tagger rather
than a particle list — a verb, or a predicative adjective with no noun behind
it, acquires nothing ("get moving", "get ready for the party") while "get
organic shampoo" stays a list and the product vocabulary may rescue a
mis-tagged noun; the router's day cue asks the resolver's month-and-day
readers instead of keeping a fifth month list, so "22 Sept" and "Sept 22" agree
with the spelled-out forms; the router's gate takes only the spoken-clock
grammar, because the first version that also took the bare-digit clock cue
read "reasons for two-factor authentication" as a commitment; an ordinal
followed by a verb keeps its date, by the tagger, since no verb list is
complete; a year may follow a date; dictation's curly apostrophe counts as a
function word; "be up / get up" commit to the morning only before "at", "by"
or "before", so "I'm up for dinner at 7" is the evening; "we're at five
hundred" is a level, not 05:00. And `simulator-id.sh` only ever considered
devices named "iPhone…", so its advertised pool preference could never fire —
fixed and verified.

Declined: "six terty" for "six thirty" is an accent-driven misrecognition, not a
rendering; the rules do not chase recogniser errors (see
`rules-not-transcription` in `PIPELINE_SWEEP_FINDINGS.md`). It still resolves
to 18:00, thirty minutes early, and is recorded in `KNOWN_ISSUES.md`.

Evidence: corpus families 52-54 (`SpeakItTests/SemanticCorpusDataR.swift`, 121
cases) at 0 blocking; the 1,082 pre-existing cases byte-identical before and
after; eight new mutation-gate rows, each rule protected; held-out set
unchanged at 229/320 destination, 251/310 count, 8 of 69 ambiguous captures
acted on. Every positive was measured against a negative set first
(`Tools/PipelineProbe`), and no negative moved.

## 2026-09-04 — Slim simulators for test runs

A stock iOS 26.5 simulator boots 202 processes and holds 3.74 GB. Four of them
were booted on this 16 GB Mac at the start of the day, with swap at 19.3 of
20 GB, and every parallel session was reaching for the same one — which is the
collision `concurrent-worktrees-share-simulator` describes.

[SimSlim](https://github.com/MobAI-App/simslim) (MIT) writes persistent
`launchctl disable` overrides into one simulator's launchd database. No `sudo`,
nothing on the Mac changes, `simslim off` restores stock. Measured here:
64 processes and 0.86 GB with the checked-in profile.

The profile was found by bisection, not taken on trust. With every category
off, 13 unit tests failed — every one backed by `NLTagger` or `NLEmbedding`,
while the same corpus passed on the host. Re-enabling categories one at a time
isolated `other`; keeping the single daemon `com.apple.mobileassetd` from it
brought the suite to 721 of 721. NaturalLanguage loads its tagger and embedding
assets through MobileAsset. The UI suite then failed its paywall test on the
same profile: with StoreKit's daemons off the scheme's StoreKit configuration
served no products and the paywall fell back to its developer preview card. So
`Tools/CI/simslim-profile.json` is "everything off, keep `com.apple.mobileassetd`
and the seven daemons SimSlim's `storekit` feature names", and those two
findings are the reason the profile is checked in.

How it is wired, and what it is not:

- `Tools/CI/simulator-pool.sh N` keeps named `SpeakIt-Slim-N` devices, slimmed
  and booted. `simulator-id.sh` prefers them, so a session that wants its own
  device sets `SPEAKIT_SIMULATOR_ID` to one and stops colliding with everyone
  else. `SPEAKIT_SHARDS=N` builds once and runs the unit suite's classes across
  the pool, packed by test count.
- `slim-simulator.sh` refuses to reconfigure a simulator that is not in the
  pool unless told to, because slimming turns off widgets, Live Activities,
  Siri and the App Store on that device — fine for a test device, a surprise on
  one somebody uses by hand. Widget and purchase QA stay on stock devices.
- It is opt-in everywhere. Without SimSlim installed every script behaves as
  before. The CI job adds one step that prepares a pool device when SimSlim is
  on the runner and says so when it is not.
- Xcode's own `-parallel-testing-enabled` clones the destination through
  CoreSimulator, and a CoreSimulator clone comes up stock — measured: a
  `simctl clone` of a slim device booted with 0 of 170 overrides — so it would
  spend the memory the profile saved. It stays off in the scheme for that
  reason and one more: interrupted runs leak clones into
  `~/Library/Developer/XCTestDevices`, and 131 of them (427 GB by `du`; APFS
  cloning means the true figure is lower but not small) were found there on
  2026-09-04, dated 4–17 August. They are not deleted by anything in this
  change; that is a decision for the person whose disk it is.

## 2026-09-07 — Product correctness before decorative redesign

Preserve the existing Today/Memory hierarchy. Mixed operations must not consume unrelated creations, and portable sync data must distinguish omission by an old writer from explicit clearing. Refinement may improve uncertain segmentation but must preserve actions and deterministic behavioral meaning.

Apply Apple's design principles through useful feedback, readable type and accessible materials: native SwiftUI glass only on the floating capture dock, with opaque fallbacks for increased contrast/reduced transparency. Move missing-person and missing-time controls to the start of the editor.

Keep the marketing site static. Reviewed the public Apple design skill and liquid-gooey's React/SVG approach; adding React solely for decorative morphing would add complexity without improving the capture or demo workflow. Use CSS, visible actions and a readable mobile composition. No package was installed. The site remains on its existing hosting workflow; this task does not deploy it.

## 2026-09-07 — The site says how Speak It understands you, and says it without a number

`ThoughtExtractionEngine` has two paths and the landing page named neither. A
visitor could read the whole site and not learn that every capture is understood
on their phone, that the rules are what do the work, or that Apple Intelligence
is a second reading of the ambiguous ones rather than the product. That is the
strongest thing Speak It can say about itself next to a cloud note-taker, and it
was missing.

`#intelligence` states it. Every claim in it is one the code makes good on:
`RefinementPolicy.shouldRefine` only consults the model for a capture the rules
already flagged for review; a capture carrying an operation returns before the
model is reached at all, so a cancellation can never be turned into a task;
`isGrounded` requires every returned quote to appear in the transcript;
`RefinementGuard.preservesEverything` rejects a reading that loses part of the
capture and keeps the rules reading instead; sampling is `.greedy`, so one
capture gives one answer; and `ThoughtOrganizer` — not the model — sets dates and
reminders on both paths.

**No latency figure appears on the page.** `Docs/KNOWN_ISSUES.md` records that
FoundationModels cancellation is cooperative and that the two-second race has
never been measured on an Apple Intelligence device, and no such device has been
available to this repository. The page therefore says a capture does not wait on
the model and stops there. The number is the one thing here that would be a
marketing claim rather than a reading of the source, and it stays off the page
until somebody measures it on hardware.

The compatibility block names iOS 26, an Apple Intelligence iPhone, the setting
and the language, and then says Apple's own list is the one that counts — so a
device list moving does not turn the page into a false statement. It also says,
in as many words, that nothing is missing without it, because the alternative
reading of this section is that Speak It is degraded on most iPhones, and it is
not.

## 2026-09-07 — The thoughts turn around the message again, and a rule keeps them off it

The conversion rewrite replaced the ring of spoken thoughts with a two-column
hero and a static four-bubble field. It converted better on paper and read as a
slide: the one picture that showed what the product is for — a day's worth of
unsorted things somebody said, circling the sentence that says what to do with
them — was gone.

The ring is back, re-implemented on `conversion.js` rather than revived from
`stage.js`. It keeps the conversion hero's copy, its call to action and its
trust line; what returns is the picture, not the 138svh pinned scroll, the
scroll-driven collapse or the fixed indicator `dockStage()` had to measure a gap
for. The indicator now sits in the flow between the two headline lines, so the
type places it instead of script placing script.

**The rule that made it work is `clear()`, not the ellipse.** Four rounds of
geometry — a wider ring, a flatter ring, a ring measured against the copy's
height, a `100vw` ring the shell then clipped — each fixed one width and broke
another, because the copy fills the middle of the hero and any closed ring
centred on it crosses it somewhere. So no ring is asked to avoid the words:
a capsule fades out as its own edge reaches the box the words ink and fades back
in on the far side. That single rule makes every width work, including the one
that has no geometric answer at all — a phone, where the type takes the screen
and the thoughts surface above and below it instead of going round.

The keep-out box is measured with a `Range` over each block of the copy
(`inkedBox()`), not taken from the copy container. The container is the full
measure at every width; the message is centred and much narrower than that on a
desktop, and protecting the container would have pushed the ring off the page to
protect whitespace.

Liquid glass is used where there is something moving behind it: the capsules
carry a blur, a saturate and a specular edge drawn as a masked border gradient.
Over flat paper the edge and the shadow are what read as glass, which is why
`prefers-reduced-transparency` and `prefers-contrast: more` drop to solid paper
without the ring losing its shape. Reduced motion settles the ring in place
rather than emptying the hero — the thoughts are the picture; the turning is
not.

## 2026-09-07 — The site sets its own name in its own typeface

The drawn monoline wordmark beside the five-bar mark was the only lettering on
the site not set in the page's typeface, and next to system type at every other
size it read as a logo with a caption rather than as one object. `index.html`
now sets *Speak It* in the page font at the page's own weight and tracking.

The mark itself is unchanged and still drawn. This is a site decision and not a
brand one: `Design/Brand` and `Tools/Brand/generate_brand.swift` still own the
monoline lettering for the app icon and the other brand surfaces, and nothing
about those was touched.

## 2026-09-07 — A fronted adjunct is read by its structure, in both layers

"On the 1st renew the car insurance" produced an event titled "On the 1st" and
an undated task, and the same shape took "after dinner call Mom", "by Friday
send the invoice" and "at the store buy milk" apart. Two layers were involved.
The clause splitter (`ClauseJuxtaposition.pieces`) cut in front of any
instruction verb whose head had two words and did not end on a lead word, so a
fronted prepositional phrase read as a clause. Closing that cut on its own made
things worse: the actionability reader only knew how to look past a fronted
*weekday* or *tomorrow*, so the whole sentence then went to Memory as a note
with its date discarded.

Both layers now ask the same structural question, through
`SentenceContext` tagging of the whole sentence rather than a list of
phrases: a span that opens on a preposition and holds no verb, no subject
pronoun and no conjunction is context for the verb after it. The splitter
declines to cut there (`isFrontedAdjunct`), and the reader removes the span
before its imperative tests (`withoutFrontedAdjunct`). Two guards carry the
cost of the tagger's habits. "Dinner call" and "morning call" tag as compound
nouns, so when no verb is found the reader inserts a comma at each place the
adjunct could end and asks the tagger again — the same trick
`hasDeterminerlessImperative` uses — accepting the cut when the padded word
tags as a verb or is one the reader already trusts at the head of a body. And
a copula or auxiliary is never the verb an adjunct fronts, which is what keeps
"Before and after photos are in the folder" a note.

The same reading is applied on the right of a conjunction. The coordination
splitter only proposed an "and" boundary when an instruction verb followed
immediately, so "book the dentist **and before dinner** call Mom" was cut at
"call" instead, and the first row carried the second errand's date.
`frontedLeadPattern` lets a short adjunct — a deictic day or a preposition
phrase of at most four words — stand between the conjunction and the verb, and
the pieces then reach the two readers above. Three details of the tagger
shaped the order of the reader's rules: a lowercased name behind the verb tags
*as* the verb ("tomorrow at 9 call sarah"), so the reader's own action-verb
list is consulted at each candidate cut before the tagger's first verb is
trusted; a demonstrative behind the preposition ("after that") is the
preposition's object, not a subject; and the deictic days ("tomorrow morning",
"this weekend") front an adjunct with no preposition at all, so they open one
too.

Corpus family 55 pins the shapes and the guards. Lists were deliberately not
extended: the weekday list in `actionBody` stays as it is, and every other
fronted phrase is read by shape.

A fronted *condition* is the neighbouring case and got the neighbouring
treatment (family 56). "When I finish the essay call Dave" was a Memory note
with the call lost, because the body opened on the subordinator and nothing
looked past it; the app already knew how to hold a condition it cannot enforce
in Needs review, it just never saw the errand. `withoutFrontedCondition` reads
a subordinator, a subject and at least one more word, and cuts where a trusted
action verb or a padded bare-stem verb begins; a pronoun there ("when I was
young **I** loved the beach") means a statement, and nothing is cut. "After I",
"before I", "until I" and "while I" join the condition vocabulary in the
splitter, the comma-lead reader and the organizer's unsupported-condition
test, with "before I forget" excluded by name because it is how people start
an errand, not a condition on one. Enforcing the condition is still unbuilt;
this only stops the errand from disappearing.

## 2026-09-08 — The default reminder time is a preference; morning is not

"Remind me tomorrow" names a day and no moment, and the moment it alerted at
was a constant, 9 AM. It is now **Default reminder time** under Settings →
Capture & reminders, kept in the shared app-group defaults by
`ReminderDefaults` the way `SavedPlaceStore` keeps Home and Work: a settings
row is not worth a schema migration, and the share extension organizes
captures too, so it must read the same value. The preference is the
notification's, never the intent's — a date-only item still records that no
time was expressed.

What it deliberately does *not* move: "tomorrow morning", "first thing", and
the hour a repeating clock falls back to. Those read
`TemporalResolver.morningHour`, which stays 9 AM, because they are facts about
English rather than about the person; an evening default would otherwise turn
"tomorrow morning" into the evening. A bare recurring day ("every Monday
remind me…") follows the preference, since it is a bare day.

The setting applies to captures organized after it changes. Reminders already
scheduled keep their moment; re-organizing them would rewrite what the person
was told they had.

## 2026-09-08 — The habit loop is seven dots and one silent note

Speak It gets the two things that make Duolingo work and none of the rest
(`Docs/GAMIFICATION_PROPOSAL.md`). A first cut shipped more than this and was
trimmed the same day after an honest look at the screen: the first action on
Today had been pushed 40% of the way down the phone, a summary line repeated
what the dots said, an offer card made Today a fourth place the app asks for
something, "opened Today" filling a dot contradicted the rule that the row
rewards outcomes rather than opens, and a "weeks kept up" number reintroduced
a loss. What remains:

- **Seven dots on Today's eyebrow line**, beside the date, today's ringed.
  A dot fills when a capture was saved or a task was completed that day, and
  for nothing else. The row costs the first action no height, hides until
  the second active day ever, carries no number, and cannot be lost.
- **All clear for today**, one line in the place of the Now section when the
  day is clear but the app is not empty. It says nothing else; a first version
  mentioned the brief here with a "Yes" link, which read as the app asking a
  favour and used a control the app has nowhere else, so it was removed.
- **The morning brief**, the only habit notification. "2 due today · 1
  overdue" at a time the person picks, default 8:00, planned three mornings
  ahead from the store on every foreground and background. A morning with
  nothing due sends nothing, and there is no other message: the nudge that
  asked "anything on your mind?" was cut because it was the one notification
  that was not a fact about the day. The switch and its time live in Account
  & Settings under Capture & reminders, directly beneath **Default reminder
  time**, because that is the preference it resembles. Today never asks.

Everything is derived from `CaptureSession.createdAt` and
`CapturedItem.completedAt`; the brief's settings live in the app-group
defaults (`HabitDefaults`) beside `ReminderDefaults`, because a settings row
is not worth a schema migration. The `UserPreferences` briefing fields stay
unused.

### Why a brief is not a reminder, in code

A reminder is something the person asked for; a brief is something the app
thinks would help. The line is drawn where both a person and the code can see
it: `SpeakIt.habit.` identifiers on the `speak-it-habit` thread, the
`.passive` interruption level so it never sounds, never wakes the screen,
lands in Scheduled Summary when that is on, and never breaks a Focus; no
category actions; counts only, never the person's words. The reminder
reconciler sweeps only `SpeakIt.reminder.` and `SpeakIt.session.`, so the two
sets cannot clear each other, and the Reminder check count excludes briefs.

### Why it turns itself off

iOS gives no callback for a background delivery, so a brief is "answered" when
Speak It is opened within twelve hours of it firing — a tap does that, and so
does simply coming back that morning, which is the brief's whole purpose. Five
unanswered in a row and the brief disables itself. This is a product choice to limit unwanted notifications; no verified
Duolingo experiment establishes the effectiveness of this five-brief cutoff.

### What was deliberately not built

No daily streak, no freeze, no streak-at-risk notification, no XP, leagues,
hearts, mascot, badge shelf, or sounds. A daily-capture goal on a ten-capture
free plan is a trap, and a daily obligation is unnecessary for a capture tool. The earlier
secondary-source claim about a 2020 CHI study was not verified and is withdrawn. Seven dots that cannot
break need nothing to soften them.

## 2026-09-08 — Transport verbs may name a person, with corroboration

"Pick up Alex from school" was a shopping row: the acquisition reading sees a
verb and an object, and nothing said the object was a person, because "pick
up" is not a speech verb and the resolver only read those. The resolver now
has a transport frame — pick up, drop off, collect, fetch, and "get … from /
at" — and the organizer turns a shopping reading into a task when the acquired
object is the person the resolver found.

The frame is the one place in `PersonMention.swift` that consults
`NLTagger`'s personal-name tag. Everywhere else that tag is refused on
principle, because it fires on capitals and a clause boundary must not depend
on the recognizer's casing. Here the alternative was worse: the parcel is the
common object of these verbs and brands are capitalized ("Pick up Tylenol"),
so a capital alone would file medicine under People. Kinship words or the
tagger's reading are required, the tag corroborates a frame rather than
deciding anything on its own, and a lowercased "pick up alex" stays a
shopping row — the same cost the resolver already accepts for a name the
recognizer has flattened.

## 2026-09-08 — A correction may repair the object of a fact

`SelfCorrectionResolver`'s object repair only ran when the prefix carried an
instruction verb, so "Remember Alex likes golf, actually tennis" fell through
to the punctuated discard and kept only "tennis" — the person and the fact
gone. The repair now also accepts a prefix whose shape is a verb with a short
noun phrase behind it, read from the tagging of the prefix, or one the person
resolver reads as a fact about somebody (the tagger calls "prefers" a noun in
"Alex prefers tea"). "The deploy actually went fine" still refuses: no verb,
no object, nothing to swap.

Two smaller findings from the same sentence. The bare-object test and the
trigger repair matched a spoken hour at the *start* of a word — "tennis"
opened with "ten" and was refused as a clock — so both alternations now end
on a word boundary. And a preposition in front of the replaced object is
scaffolding, kept unless the replacement brought its own: "allergic to
peanuts, actually tree nuts" keeps its "to".

## 2026-09-08 — The arguable corpus cases are decided

Nine cases had sat in the corpus marked "arguable, recorded, not gated" since
the expansion review. They were decided one at a time, on what a person who
spoke the sentence would want to find, and each is gated now.

- **"Pay the invoice within 30 days" is due on the last day of the window,
  date-only.** A window is a deadline the way "by Friday" is. "In 30 days"
  stays a point and keeps its clock (`deadlineWindow`). "In the next 3 days"
  reads the same way.
- **"Every second Tuesday" is every other Tuesday.** That is the reading in
  the English spoken here, and the monthly one needs "of the month", which
  `ordinalWeekday` already claims first. "Every second week" follows.
- **"Standup moved from 9 to 9:30" is an event at the new time.** Three
  things were wrong. "9 to 9:30" was read as nine minutes to nine, so the
  spoken clock face now refuses a face behind "from" and a target that
  carries its own minutes. The strip that removed the old time removed the
  "to" with it, leaving nothing any clock rule reads. And "Standup" was a
  person: "moved" is a life-event verb, so the resolver now declines a subject
  whose "moved" leads to a clock. The cue is one pattern,
  `ActionabilityReader.rescheduleCue`, read by the event rule, the resolver,
  and the organizer, so the three cannot disagree; an address ("moved to 5
  Main Street") is excluded by the street word behind the number. "Dinner
  moved to 7" became an event as a consequence. A plain span, "meeting from 2
  to 3", now starts at 2; spans are still not modelled beyond that. The
  unpunctuated rendering, "moved from 9 to 930", is repaired to "9:30" by
  `ClockDigitRepair` behind the same two frames — a rescheduling verb, or a
  "from <clock>" — because a bare "to 930" is as often a quantity and could
  not join the cue list; the phone-number, address and unit guards apply.
- **"Remember Catherine's husband is called David" files under Catherine.**
  She is the person the speaker knows and will look under. The actor rule had
  read "is called" as a phone call; a contact verb behind a copula is a naming
  or a passive, and the possessive owner rule takes over.
- **"Give Mom's recipe to Catherine" is a task with Catherine.** Two parts.
  The errand reached Memory because a possessive name was not accepted as
  the object's determiner in the imperative shape; it is now, with pronoun
  contractions ("he's") kept out by name. And the recipient of a transfer verb
  ("give", "send", "return", "bring", "hand", "lend", "pass", "forward",
  "deliver", "mail", "ship") is read through its "to" ahead of the direct
  object, while a possessive owner is ranked after everybody the sentence
  addresses — which is what `possessiveOwner`'s comment already promised.
  "Take" and "get" are left out: they reach a place more often than a person.
- **"Remember Catherine said I need to call Alex Friday" names Alex.** When
  reported speech carries an obligation of its own, the resolver reads the
  obligation first, on the same string so every range stays valid, and falls
  back to the framing only when the obligation names nobody ("Priya said I
  should call the landlord" stays with Priya).
- **"Pick up the prescription at the pharmacy and gas at the station" is two
  errands.** The conjunct repeats the left clause's place frame with a new
  object in front, which is gapping; `sharesVerb` already handled a trailing
  day or clock as context and now handles a determiner-led place the same
  way, and the split rule admits the parallel frame. Each errand can be
  ticked off on its own.
- **"Descale kettle" is a task.** "Descale" is outside the embedding's
  vocabulary, so the proper-name guard declined it. A productive prefix (de-,
  re-, un-, dis-, pre-, mis-, over-) on a stem the vocabulary knows, of at
  least four letters, is an English verb — and the padded fragment is tagged
  lowercased as well, because the tagger takes an unfamiliar capital for a
  proper noun ("Descale the kettle" tags Noun, "descale the kettle" tags
  Verb). Known words keep the reading that was measured. "Devon", "Regina",
  "Preston", "Rebecca" all still read as names.
- **"Don't forget to call Mom" is a `personFollowUp`.** The expectation was
  older than the type; "Call Mom" in the people family already reads that
  way, and the lead does not change what the call is.

The ten cosmetic disagreements were stale lowercase title expectations and a
shopping split that expected the verb dropped where every other split keeps
it; the expectations were corrected to the sentence-case rows the app shows.

## 2026-09-08 — Three things found while deciding the corpus cases

- **A verb behind a copula is its complement.** "Tuesday is book club" was
  cut by the juxtaposition splitter into "Tuesday is" and a task called "Book
  club", because "book" opens an instruction and nothing asked what stood in
  front of it. The copulas join `clauseInternalLead`: a clause cannot start
  right after "is". "The weather is better book the campsite" still splits,
  because "better" is what sits in front of that verb and it has its own rule.
- **Appointments keep business hours.** A bare hour means its next
  occurrence, which is right for "call Sam at 9" and was giving "dentist at
  8" an 8 PM cleaning. The `dayless` reader already committed breakfast,
  standup and the office to the morning for 6–11; meetings, appointments and
  the clinic words now commit 8–11 the same way, read after the evening list
  so "dinner meeting at 8" keeps its dinner. 7 is left to the general rule: a
  7 PM meeting is ordinary and a 7 AM one is not. This closes domains C4 d.
- **Today's ordering is total.** `chronologicalBefore` and `prioritizedBefore`
  ended on a comparison that two rows can tie, and `sorted` is not stable, so
  two undated rows of equal priority could swap places from one render to the
  next. Both now end on the older capture first, then the identifier.

## 2026-09-09 — Development-set misses, read one at a time

`Tools/CorpusRunner/devsets/` is the set that may be read while rules change.
Its routing and coordination misses were taken one by one. Six were labels
that disagree with a corpus decision and stay as they are: "Mike said to book
the room" is an errand the corpus already routes to Today; "call the dentist
and the plumber" is two recipients by the coordination-context family; the
bare "don't call the plumber" family is a cancel operation first and a
preserved Memory note when nothing matches, which "Please don't pay the
invoice yet" pins; "decant the wine" is a vocabulary gap the tagger cannot
close; and the two fragments given a date ("Tuesday and the dentist") are
left as they are. The rest were rules:

- **A clock with its meridiem is a calendar cue.** "Standup 9am" and
  "dentist 2pm" were Memory notes because the bare-hour cue needs an "at" —
  a bare "9" is as often a quantity — and nothing read "9am" without one.
  `ActionabilityReader.meridiemClockCue`.
- **Arrivals are history.** "The parcel arrived Friday" was next Friday's
  event; "arrived", "landed", "came in", "showed up", "turned up" and "got
  delivered" join `pastReportVerb`. "The guests arrive Friday" stays an event.
- **Two dated noun phrases are two events.** "Gym at 6 and dinner at 8" was
  one event at 6. Neither side has a verb, so neither passed the
  subject-predicate test; `isDatedNounPhrase` reads a verbless phrase ending
  on its own "at <clock>" with an object in front, and two of them across an
  "and" split. A day on the last one ("…dinner at 8 tomorrow") is inherited
  by the first, which would otherwise be today's. "Meeting at 2 and at 4" has
  one object and stays one row.
- **The operation detector read its own verb list.** `Docs/KNOWN_ISSUES.md`
  recorded the four errand vocabularies as unified; `CaptureOperationDetector`
  still held a private list of 31, which is why "don't call the plumber"
  cancelled and "don't fix the sink" did not. It reads `actionVerb` now.
- **Three flattened-transcript defects.** A hyphenated name is cased per part
  ("Jean-Luc"), and the title formatter no longer mistakes its own sentence
  case for the speaker's. A lowercase word the tagger reads as an adjective is
  not joined onto a name, and a kinship word takes no surname, so "wish
  grandma happy birthday" and "wish priya happy birthday" name Grandma and
  Priya. And a correction whose replacement carries no capital is put where
  the person stood and the resolver is asked whether it reads as one there,
  so "call catherine tomorrow, actually alex" is a call to Alex; "actually
  text her" and "actually tonight" still fall through to the older repairs.

Development sets after: coordination 115/121 (was 114), routed destination
74/84 (was 72), routed count 77/79.

## 2026-09-09 — A batch of forty everyday captures, read one at a time

Forty sentences were authored the way a person dictates on the way out the
door and run through the probe. Thirty-two read correctly. The eight that did
not:

- **"Book a table for four at 7 on Friday" was 4 PM.** The bare-clock rule
  takes the first of "at|by|before|around|after|for", and "for four" came
  first. A "for" number followed by a clock or a head-count word is a count.
- **"Physio Wednesday 10:15" was day-only.** A bare hour needs its "at"
  because a bare "9" is as often a quantity; a number with a colon is not,
  and now reads as a clock with no preposition. "The score was 3:1" does not:
  the minutes must be two digits. The unpunctuated rendering, "Wednesday
  1015", is repaired to "10:15" by `ClockDigitRepair` when a day word stands
  on either side of the digits, under the same phone-number, address and
  unit guards; "the invoice is 1500 Friday" is left alone.
- **"Idea for the app: let people share lists" was two rows.** The
  juxtaposition splitter cut at "share"; a capture that opens by naming
  itself an idea or a note is not cut, and neither is the verb behind a
  causative "let X".
- **"Note to self: the garage code is 4821" was titled ": The garage code".**
  The lead strip consumed a comma but not the colon dictation writes.
- **"Cancel the gym membership before the end of the month" was an operation
  on a stored row.** Read as a cancellation it would have deleted a "gym"
  reminder and left nothing to do. `CaptureOperationDetector.cancelsAnArrangement`
  names the arrangements a person cancels in the world (membership,
  subscription, plan, policy, account, service, contract, insurance, trial,
  lease, card) and the deadline frame ("by Friday") that says the same, and
  both the detector and the extractor's safety hold read it, so the request
  becomes an ordinary Today task. "Cancel the dentist appointment" and
  "cancel the dentist reminder" keep their operations.
- **"The parking pass expires Friday" was a Memory note.** "Expires" is in
  `descriptiveVerb`, correctly, for "the store closes Sunday"; an expiry on a
  named day or date is the last moment to act and joins "the offer ends
  Friday" on Today. A month alone stays knowledge.
- **"Movie night Friday" was an event at 8 PM.** "Night" in a compound names
  the kind of evening. `DaypartHint` refuses a "night" with a noun straight
  in front of it, and the organizer's separate copy of the daypart reader is
  gone; both paths read `DaypartHint` now, so "Friday night" and "tomorrow
  night" are still evenings and "movie night" is a day.
- **"Cancel …" errands were held as "unclear".** The extractor's destructive
  safety hold kept every "cancel" back for review; it now exempts the same
  arrangements the detector does.

Two readings were left as they are: "my sister's flight lands at 6:45
tomorrow" resolves to the evening, which a bare 6:45 cannot settle, and
"laundry" alone stays a note rather than guessing an errand from one noun.

## 2026-09-09 — Three domain batches, and the people sweep's P2 cluster

Three read-only agents each authored forty-five captures in one domain
(work and school; family, home and health; money, travel and social), ran
the probe, and reported only what a careful user would call wrong: 42 items,
87 read correctly. Each was taken one at a time; about a third were
debatable and left ("my sister's flight lands at 6:45 tomorrow" is the
evening; a stray Memory note for "I never use it" keeps the words). The
rest were rules, grouped by mechanism:

- **People.** Departments ("recruiting", "legal", "accounts", "finance",
  "marketing", "sales", "engineering", "ops", "facilities" …) join the
  never-a-name list beside "hr" and "payroll". A possessive behind a
  determiner is a common noun ("the dog's grooming"), kinship excepted. A
  pronoun contraction never joins a name ("Sarah I'd"). "Recommended" and
  "suggested" are person predicates. A thing moved to a day is a plan, not
  somebody who relocated, through a shared `rescheduleDayCue` read by the
  resolver, the past-report rule and the calendar-commitment rule alike.
- **P2, the last open people cluster.** "Call Mom tomorrow and my sister
  Friday" never split because the guard that keeps "Alex and his brother are
  coming" whole reads any subjectless left as a bare noun, and an imperative
  has no subject either. "His", "her", "their" point back at the left and
  keep the guard; "my", "our", "your" point at the speaker and open a second
  person when the left is an errand. "Meet" joins the shared-verb list so the
  second row reads "Meet Marcus at noon".
- **Boundaries.** The juxtaposition splitter no longer cuts behind a
  possessive ("Maya's swim lesson"), an amount ("the $89 charge") or a day
  behind a determiner ("the Friday sign off"), nor inside a capture that
  names itself an idea within its first three words, nor after a causative
  "let X". Two companions of one "with" are not a boundary ("with Tom and
  Alice, it's $1200 total"), with or without the comma. A trailing condition
  is context for verb sharing ("a travel adapter before we leave").
- **Errands and events.** An imperative that mentions an appointment is an
  errand unless the verb is one of attending. "I told Sarah I'd …" is a
  promise the person keeps. A month with no day is knowledge. "Midterm",
  "finals" and "quiz" are scheduled nouns. "Call about the warranty" is a
  task, not a follow-up with nobody. The reschedule reader accepts spoken
  minutes ("nine fifteen") and stays off relayed messages ("tell Nina the
  brunch is moved to 11"). "Transfer", "deposit", "prep", "cc", "loop in",
  "unload", "scrub" and a few more join the errand vocabulary; "review",
  "draft" and "edit" were tried and removed, being nouns as often ("the
  second draft is due Wednesday" split in two).
- **Lists.** "Costco run tonight: milk, eggs, coffee" is a shopping list,
  by the colon or by a tail that names only products, so the unpunctuated
  rendering agrees; the groceries lead accepts a day before its colon.
  "Some" in front of a product is a quantity, not the determiner that
  refuses "the newspaper".
- **Unfinished thoughts.** A demonstrative behind a preposition completes
  the phrase ("used to work at Shopify before this", "think about this"),
  and a distributive closes one ("$400 each").

Development sets and the held-out set are unchanged by the batch. The
four-item comma list with "some" and a two-word store ("buy chicken, rice,
broccoli and some yogurt at the grocery store") still reads as one row; the
two-item form splits, and the case is narrow enough to leave.

## 2026-09-09 — Second agent round: a freelancer, errands, and row titles

Three more read-only agents: forty-five captures from a freelancer or small
business (invoices, clients, suppliers), forty-five about fitness, hobbies,
the car and errands, and fifty with heavy conversational framing judged on
their row titles alone. Forty-one items were flagged; those taken were rules
again, and a few were noticed to be systemic:

- **Continuations.** A verb-opener whose object is a pronoun that ends the
  clause points back ("invoice 1042 is overdue chase it"); one with more
  behind it is a new instruction ("call her Friday", "move it to Monday"),
  and the connector splitter applies the same test to "and get it back by
  Friday". The word behind a verb is that verb's object, read from the
  tagging of the whole clause, since the tagger cannot read "Marcus prefers"
  on its own; and a two-word head that is somebody and their predicate is
  not cut, the resolver deciding who is somebody. The particle behind a
  second name belongs to the shared verb ("invite Tom and Rachel over").
  Verb sharing looks past an obligation frame ("I need to buy X and Y") and
  treats a purpose ("for client calls") as context.
- **People.** A name followed by a department or a company suffix is an
  organisation ("Northwind accounting"). Addresses ("unit 4") join the
  never-a-name list. An infinitive "to" leads to a verb, not a recipient
  ("supposed to rain"); the flattened person repair requires the person to
  be what the prefix ends on, so "remember alex likes golf, actually tennis"
  stays the object repair's.
- **Knowledge.** "I keep forgetting" with a fact behind it keeps the fact
  and with "to" behind it is an errand; the obligation pattern now requires
  the "to". A repeat makes a note a task only when the sentence is not
  knowledge, so "the nursery closes at 6 on weekdays" is a note with no
  series. "About" is rewritten to "around" only beside a clock, because the
  rewrite reached the quote.
- **Errands.** "Let's <verb>" is the errand, and the frame leaves the title.
  "End of quarter" and "end of year" resolve like "end of month". "We need
  eggs milk and olive oil" is a shopping list by its tail. A fronted
  condition may close on a pronoun or a particle ("while I'm out there grab
  stamps"). "Chase" and "invoice" are errand verbs. "Dont forget to", with
  the apostrophe a recognizer dropped, is read like "don't forget to" — the
  one lead list that spelled it with a fixed apostrophe now carries both.
- **Titles.** Trailing hedges ("or whatever", "I think", "if I can", "or
  something") leave the title and stay in the quote; a possessive name is
  cased ("Max's medication"); every named person is cased, including a
  lowercase name coordinated with a cased one ("Tom and rachel"), the
  resolver deciding what is a name.

Left as they are: "the plant nursery … every weekday" keeps that rewrite in
its title (the repair that makes the recurrence readable), "reschedule my
chem lab to Thursday, actually make that Friday" is an operation whose
correction the repository resolves, and "Milo's teeth cleaning" cannot know
that Milo is a dog.

## 2026-09-09 — Morning brief taps route to Today

The notification delegate previously handled only reminder action buttons. A
brief tap therefore reopened whichever tab was last selected, including Memory.
The shared router now queues a separate Today request, consumed on initial
appearance or while running. It does not create a capture, require Pro, or
dismiss an unsaved composer. A direct tap clears the unanswered count even
after twelve hours; dismissing a notification does not count as an answer.

Apple documents the default notification action as opening the app from the
notification interface, delivered through the existing delegate callback:
[UNNotificationDefaultActionIdentifier](https://developer.apple.com/documentation/usernotifications/unnotificationdefaultactionidentifier).
Background delivery is handled by the system, so passive delivery and reopening
remain separate observations: [local notification scheduling](https://developer.apple.com/documentation/usernotifications/scheduling-a-notification-locally-from-your-app).
The passive brief still needs physical-device delivery QA.

## 2026-09-09 — Distinguish date topics from schedules, and verify skipped paths

A determiner plus a day modifying a placeholder ("that Thursday thing", "the
whole Friday thing", "this Monday stuff") is now underspecified temporal scope.
The complete noun phrase is required: explicit actions and prepositions, such
as "handle that Thursday thing tomorrow" and "the thing on Tuesday", retain
their dates. The original words survive; no date, recurrence, or reminder is
invented. Two actionability tests cover the family and its counterexamples.

The full UI run exposed an obsolete paywall assertion demanding a permanent
renewal-price promise. The product intentionally removed that unverified
promise; the test now checks the exact current offer terms and rejects the
permanent-price claim. Its focused rerun passes.

Fresh simulator notification tests now request provisional authorization only
in their test helper. Apple's [permission guidance](https://developer.apple.com/documentation/usernotifications/asking-permission-to-use-notifications)
supports this without a system prompt. Existing denial is respected. Six
previously skipped notification-center integration tests now execute and pass;
the denied-permission test remains a separate environmental case, already
covered by the earlier unauthorized run. This does not verify physical delivery.

The shared scorer now labels development and held-out input separately, prints
the actual label count and missing probe count, and counts empty ambiguous
captures in content loss. Two synthetic scorer tests run in the corpus gate.
The development ambiguity count improved from 4/32 acted on to 3/32; the
untouched held-out run stayed 233/320 destinations, 255/310 thought counts,
7/69 ambiguous captures acted on, and zero captures lost. No broader accuracy
improvement is claimed, and no held-out failures were read.

## 2026-09-11 — Measure language in CI, because the parser only runs on macOS

The engine depends on Apple's `NaturalLanguage`, and `NLEmbedding` is
load-bearing: it decides whether an unknown word is an ordinary noun or a
person's name. So the parser cannot run on Linux or in a container, and
stubbing the framework would produce numbers that do not match the shipping
app. Until now the only language check CI ran was the corpus gate, and the
development-set and held-out numbers came solely from a hand-run on one Mac.
Anyone else changing language rules was working blind, and three sessions doing
so at once is how unverified claims enter the record.

`Tools/CI/language-metrics.sh` now produces every language number this project
quotes in one run: the gating corpus, all four development sets, and the
held-out set. The `language` job in `ci.yml` runs it with no simulator, no unit
suite and no release build, which costs roughly five macOS minutes against the
allowance's two hundred — about thirty measurements a month where the iOS job
affords one or two. Dispatching with `language_only` skips the iOS job so the
question "did this parser change help" never costs a unit-suite run.

Two deliberate choices in it:

The scorers report and do not gate. Only the corpus gate's blocking count sets
the exit status. Destination accuracy moves either way for defensible reasons,
and a number that blocks a merge is a number people eventually learn to game.

The script refuses `--verbose` rather than forwarding it. Scoring the held-out
set is safe; reading its failures during development is what destroys it, per
`Tools/CorpusRunner/heldout/README.md`. Refusing the flag means running the
metrics can never be the thing that unseals the set, and reviewing those
failures at release stays a deliberate act with its own command.

No accuracy claim is attached to this change. It alters no parsing behaviour;
it only makes the existing measurements reachable by more than one machine.
The script was verified for argument handling, `shellcheck` and `actionlint` on
Linux; its macOS path is unrun here by construction and needs a Mac or a
dispatch.
