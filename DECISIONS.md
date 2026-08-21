# Decisions

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

## 2026-08-17 — Summer launch pricing ends on September 22, 2026

Annual Pro is $14.99 during the launch window and is intended to move to $29.99
at 12:00 a.m. America/Toronto on September 22, 2026 (`04:00:00Z`). That makes
“50% off” a comparison with the genuine standard annual price, not with twelve
monthly payments. Sale copy is build-gated and time-gated, and App Store Connect
must have the matching future price scheduled before the gate is enabled.

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
