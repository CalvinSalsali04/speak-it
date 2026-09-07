# Known Issues

## Physical-device voice validation

The project builds and launches on an iPhone 13, passes Xcode static analysis, and all 95 repository, extraction, routing, sync, reminder, draft, integration, and reliability tests pass on an iPhone 17 Pro simulator. The capture subset also passed 175 repeated executions, and the previous complete 93-test baseline passes both Address Sanitizer and Thread Sanitizer. Microphone quality, speech accuracy, true Back Tap recognition, interruptions, AirPods, and locked-device behavior still require the physical-iPhone matrix in `CAPTURE_STRESS_TEST_PLAN.md`; iOS does not expose the hardware Back Tap gesture to automated tests.

## The app cannot set what customers are charged

`SpeakIt.storekit` is a local test configuration, and the paywall renders
`product.displayPrice`. Changing the monthly plan to $2.99 in this repository
changes what the simulator and the UI suite show; it does not change what App
Store Connect bills. Until the monthly product is $2.99 there and the annual
schedule is confirmed, the shipped paywall shows whatever App Store Connect
holds — and if that is still $1.99 against a $29.99 annual, the plan the screen
pre-selects and badges `BEST VALUE` is the more expensive one. `E12` in
`Docs/BUILD_14_DEVICE_SMOKE.md` is the device check that catches it, and the
gates are listed in `Docs/APP_STORE_SUBMISSION.md`.

## Pro moments are offered at the next foreground, not in real time

A capture made through Siri, Back Tap, a Shortcut, or the share extension runs
outside this process, so the moment it earns cannot be shown while it happens —
there is no Speak It window to put a sheet on. The moment stays pending and is
offered the next time the app is on screen. In the rare case where SwiftUI
refuses the presentation because a screen below already has a sheet up, the
moment is not spent: the next foreground clears the stale binding and offers it
again.

## Back Tap setup

iOS does not allow Speak It to assign Back Tap automatically or deep-link directly to the Back Tap choice. The user must add the ready-made one-action **Speak It Capture** shortcut and select it under Accessibility → Touch → Back Tap → Double Tap. The shortcut now foregrounds Speak It directly into an auto-starting capture instead of attempting a fragile cold background microphone start. The app opens as close as the public Accessibility API permits and explains the remaining taps; the physical Back Tap gesture still needs end-to-end device testing across supported iOS versions.

## Personal-team iCloud signing

The optional iCloud synchronization entitlement is enabled in Release builds, but Apple does not allow that entitlement on a free personal development team. Device builds signed with the current personal team therefore use the Debug configuration and keep iCloud disabled. A paid Apple Developer team is required to install or distribute the iCloud-enabled configuration.

## Scheduled messages

Apple does not expose its Messages **Send Later** queue to third-party apps. Speak It can recognize a scheduled-message request, alert at the requested time, prepare the message in Apple's composer, and complete the task after a confirmed send. It cannot silently send or place a message into Apple's encrypted Send Later queue.

## Today rows have no swipe-to-complete

Today's sections are a `LazyVStack`, not a `List`, so the swipe action was a custom `DragGesture`. Layered over scrolling content it won the touch outright and vertical swipes that started on a row did not scroll, so it was removed. Completion is unchanged through the circle on each row and through the editor. Memory and the completed log are `List`-based and keep their native swipe actions. Bringing the shortcut back to Today needs a native implementation, not another gesture.

*Partly addressed.* The wrapper the five section call sites route through was
`SwipeActionRow`, whose body was `content.frame(maxWidth: .infinity)` — it took
an action title, an icon, an accessibility label, an enabled flag and a closure
and rendered none of them, so the code read as though Today had a Done action
when nothing was wired to anything. It is now `RowQuickAction` and delivers that
action through a `.contextMenu`, which is the affordance that works inside a
scroll view without competing for the drag, and the one Memory's rows already
offer. A real swipe still needs Today to become a `List`.

## User preferences

Appearance, setup completion, and reminder permissions have UI. The broader modeled `UserPreferences` fields do not yet have a dedicated settings screen.

## Future data migrations — every version is frozen

The store is at schema version 4. `SpeakItSchemaV1` through `SpeakItSchemaV4` in
`SchemaV1.swift` are all frozen snapshots: each nests its own `@Model` copies of
`CaptureSession`, `CapturedItem`, and `UserPreferences`, so `CaptureSession.self`
inside those enums resolves to the historical shape. They must never be edited —
they are what later versions migrate *from*, so changing one rewrites history and
can make an existing device's store unreachable.

Versions 1, 2 and 3 each had to be frozen after the fact, and version 2's freeze
was a repair to a launch abort that had already reached a build. Version 4 was
frozen the moment it was created, which is the order that works.

**The live shape lives in `SpeakItSchemaCurrent`**, an alias — today pointing at
`SpeakItSchemaV4Live` — which is the schema `PersistenceController` opens and the
only declaration allowed to move. The two roles, "the shape the app addresses"
and "a version some phone is arriving as", are deliberately separate
declarations.

`SchemaFreezeTests` holds both contracts. Version 3 is anchored to
`SpeakItTests/Fixtures/SpeakItVersionThree.store` — a real SQLite store written
by the last build that shipped an unfrozen version 3 — and to the Core Data
entity version hashes that build stamped into it. Version 4 is anchored to the
hashes it declared when it was introduced. Two assertions matter:

- each frozen snapshot still stamps its own hashes, which fails if anyone edits
  a numbered schema;
- the live models still stamp version 4's hashes, which fails the moment a
  persisted model gains, loses or retypes a property.

**The second one is not a test to update.** When it fails, the fix is to add
`SpeakItSchemaV5` with its own frozen model copies, add a stage from version 4 to
it, and repoint `SpeakItSchemaCurrent` at a live twin of version 5. Editing the
recorded hashes instead would silently redefine a version that people's phones
already hold.

### Rows that predate version 4 carry no verdict

Version 4 persists `SemanticState` and `SemanticGap`. There is deliberately no
backfill: what a build that never recorded a verdict would have concluded is not
recoverable from the fields it left behind, and reconstructing one is exactly the
guess version 4 exists to replace. Pre-version-4 rows read back as
`semanticState == nil` with `hasRecordedSemanticState == false`, and
`clarificationRequirement` falls back to the derivation they already had. They are
never labelled `resolved`, which would claim every unreviewed row from before the
upgrade had been understood.

## UI validation

*Automated suite state, 2026-09-04.* Two UI tests had drifted from the app
and failed on stock and slim simulators alike. The first practice mission now
completes only when the capture names a person, so the onboarding test types
"Tomorrow at 9, ask Maya about the proposal" instead of "Buy toothpaste"; and
the seeded-Today tests wait on the app's own launch-finished signal
(`debug.launchWorkFinished`) instead of racing the fixture load, which costs
about nine seconds wherever the on-device model runs. Both fixes came from the
`wip/ui-test-fixture-order` and `wip/ui-tests-wait-for-launch-work` branches.
One more: the untimed "Pack gym clothes" row is the last thing on Today, under
two discovery cards, and a lazy stack builds it before it is on screen — so it
*existed* while not being hittable, and the touch-target assertion failed on
it. That test now scrolls until the row is hittable. It looked like a
wall-clock dependence at first (passed at 02:35, failed at 03:38); it was not.

Standard-size Today and Memory layouts now have clean-state simulator visual coverage. A dark-mode walk of Welcome, Today, Account & Settings and the Capture Anywhere method list on an iPhone 17 Pro simulator (2026-09-03) found and fixed two dark-only defects — an on switch with an invisible knob, and the selected method row's icon halo — and confirmed the new wordmark and icon in both appearances. VoiceOver, the largest accessibility Dynamic Type sizes, rotation policy, and a complete dark-mode pass still require hands-on device QA. The implementation uses semantic system controls and colours, but automated unit tests cannot replace that pass.

## Clarification reasons are inferred, not recorded

`CapturedItem.needsClarification` is a single `Bool`, so the reason extraction had at capture time is discarded. `ThoughtOrganizer` knows when it wanted a reminder and could not parse a time, `ThoughtExtractor` knows when it kept a capture whole because splitting it looked unsafe, and the on-device model path knows when it was simply unconfident — all three collapse into one flag.

`ClarificationRequirement` re-derives the likely reason from the item's own fields so Needs review can name the gap. It is right for the common cases and covered by unit tests, but it is a good guess rather than ground truth. Two limits follow. "Might be 2 thoughts" is inferred from a capture still holding its whole transcript with a clause connector in it, so a whole capture kept for a safety reason can read as a split candidate. And a low-confidence flag with no identifiable gap falls back to "Needs confirmation" even when extraction had a more specific doubt.

*Resolved for readings the interpreter judged.* Schema version 4 stores `SemanticState` and its `SemanticGap` on `CapturedItem`, and `clarificationRequirement` reports the recorded gap in preference to the derivation. The derivation still runs for rows with no recorded verdict — every row written before version 4 — and for the reasons that are not readings of a sentence at all: a held destructive request, a place trigger waiting on the device, a combined place-and-time request. Those are states of the device or the item and still outrank a recorded gap.

**This now reaches the store.** `OrganizedThought.state` carries a `SemanticState` — `resolved`, `underspecified`, `contested`, `unsupported` — with a named `SemanticGap` saying what could not be determined (`ambiguousActor`, `ambiguousTemporalScope`, `reportedSpeech`, and so on). Schema version 4 persists it as two raw strings and `CapturedItem.semanticState` reads it back.

What remains open is coverage, not plumbing: `TemporalCommitment` is still the only producer of a non-resolved state, so `ambiguousTemporalScope` is the only gap any capture currently records. The other six are storable, round-trip, and have review copy, and will start appearing as more of the pipeline reports what it could not settle. Until then most flagged rows still reach review through the old derivation.

## Temporal intent is stored; two kinds of trigger are still missing

Schema version 2 records what a person said about time (`TemporalIntent`) beside the instant it resolved to, so `dateOnly`, `exactDateTime`, `relativeDuration`, `calendarRecurrence`, and `durationRecurrence` are now distinct all the way into storage. Named time zones are stored as identifiers. What is still not modelled:

- **Location triggers.** *Superseded.* "Remind me to buy milk when I get home" is now modelled: `ReminderTrigger` has `time` and `location` cases, `LocationIntent` records the place reference, and `LocationReminderMonitor` handles permission and region monitoring. `UnsupportedTrigger.location` survives only on rows captured before that landed. What remains unfinished is the *product* around it — see "Location reminders — architecture complete, feature not" below.
- **Compound triggers.** "When I get home after 6" carries both a place and a time constraint. Both are now parsed and stored, and neither is acted on: the request is held in Needs review rather than reduced to one half. Enforcing the combination — a place trigger gated by a time window — is still unbuilt.
- **Floating versus fixed recurrence across travel.** `TimeZoneBehavior` distinguishes `fixed` from `deviceLocal` and is stored, but nothing yet lets a person *choose* which one a recurring reminder uses. "Every day at 9 AM", carried from Toronto to Hong Kong, currently follows the device. That is the better default; it is not yet a decision the person can make.
- **Locale-driven numeric dates.** "4/5" is flagged as ambiguous and sent to Needs review; "13/5" and "5/13" resolve without asking, because 13 cannot be a month and the order is therefore forced. The ambiguous case does not yet offer the two candidate dates as a choice, which is what the clarification UI should eventually present.

- **What the international clock work left open** (2026-09-04, see
  `DECISIONS.md`). "Six terty" for "six thirty" is a recogniser error and is
  not chased; it resolves to 18:00, half an hour early. A copular sentence
  whose subject is not a scheduled noun still loses a correctly parsed date —
  "my flight is on 22 September" and "the inspection is Tuesday week" land in
  Memory with no date, exactly as their North American controls ("my flight is
  on September 22") did — closed the same day by teaching the router's day
  cue the day-first order and asking the spoken-clock grammar beside its clock
  cue, so those sentences are events now. "We fly out on 5 Sept" still lands
  in Memory in either date order, because "fly out" is neither a scheduled
  noun nor a listed verb (routing R6/R8). "Grab lunch with Sam at noon" is
  still a shopping row (routing R7: "grab" plus a noun the tagger reads as a
  noun). "On the 1st renew the car insurance" keeps its date on the fronted
  day row but the clause splitter still makes the renewal a second, undated
  row, and "we're at five" still reads a bare "at five" as 17:00. And "the first
  appointment is at 9" no longer means the 1st of next month, but a bare 9
  that has already passed still rolls to 21:00 (domains C4 d).
- **The date-only alert hour is a constant, not a setting.** `TemporalResolver.dateOnlyAlertHour` is 9 AM, and it is the stated policy for "remind me tomorrow" — a day with no time still needs a moment to alert at. It should become a "Default reminder time" preference. Note the distinction it already enforces: *"buy milk tomorrow"* schedules nothing at all, while *"remind me to buy milk tomorrow"* alerts at the default hour, and neither writes a time into the intent.

## The free capture ledger is per-device, not per-person

`FreeCaptureLedger` writes the lifetime count to the Keychain, which survives deleting and reinstalling Speak It, and the higher of Keychain and `UserDefaults` always wins so the count cannot move backwards. That closes the ordinary reinstall path.

It does not make the allowance follow a person across devices, and it does not survive a full device erase or a restore onto new hardware without Keychain restore. Genuinely per-person accounting would need a server or an iCloud-backed identifier, which the local-first model does not currently have. This is a deliberate ceiling rather than a bug: the current design is the strongest guarantee available without accounts.

## Location reminders — architecture complete, feature not

The distinction matters, because the two are easy to confuse from the test
suite alone. What is finished:

| Layer | State |
| --- | --- |
| Parsing / semantic representation | Done |
| Persistence | Done |
| Trigger architecture | Done |
| Permission-state architecture | Done |
| Reconciliation architecture | Done |
| Home / Work semantic recognition | Done |
| Home / Work user configuration | Done |
| "Here" coordinate capture | Done |
| Named-place resolution | **Not started** |
| Combined time + place enforcement | **Held for review, not enforced** |
| Real-device geofence execution | **Unverified** — see `LOCATION_DEVICE_QA.md` |

Home and Work can now be configured, so `"when I get home"` and `"when I leave
work"` are the first place reminders with a complete path from sentence to
monitored region. They remain unverified on hardware.

The specifics:

- **There is no Home/Work settings UI.** *Resolved.* `Settings → Capture &
  reminders → Places` sets both, by map, address search, or current location,
  and the same picker is reachable directly from a blocked reminder in Needs
  review so nobody has to leave the thought to fix it. `.home` and `.work` stay
  semantic pointers: changing one re-resolves every reminder that mentions it.
- **Named places are not geocoded.** "When I get to Costco" parses to
  `.named("costco")` and correctly reports `ambiguousPlace`, but nothing searches
  for it yet. Resolving it needs `MKLocalSearch`, a disambiguation UI for the
  several plausible Costcos, and a decision about the network round trip in a
  local-first app. Until then these reminders are stored, explained, and inert.
- **"Here" is a frozen snapshot.** *Resolved.* `.currentLocation` resolves once,
  just after the thought is persisted, and never again — said at McMaster and
  carried to Toronto it still means McMaster. Deliberately fire-and-forget:
  capture never waits on a location fix, and an unresolved "here" reports
  `locationUnavailable` rather than saving a wrong place. It is also refused when
  the only available fix is too old or too imprecise to mean "here" — a suitable
  fix, not merely a present one. Naming the spot is opt-in (**Name this place**
  in the editor) rather than automatic, so speaking a "here" thought never sends
  a coordinate off the device; the reminder fires on the coordinate alone.
- **Combined place and time is represented, held, and not enforced.** "When I get
  home tonight" stores both intents and fires on *neither*. It is surfaced in
  Needs review as *"Place and time conditions aren't supported together yet —
  choose one"*, and setting a time in the editor commits to the clock half.

  This replaced an earlier design that kept both halves live independently. That
  version scheduled the 8pm notification *and* monitored the region, so the
  person would have been told at 8pm whether or not they were home, and told
  again when they walked in. It was latent only because no Home can be
  configured yet; shipping Home/Work configuration would have activated it.
  Preferring the place instead was also wrong — it fires on a 2pm arrival that
  "tonight" explicitly ruled out. Neither half alone is what was asked for, so
  the request waits rather than being silently halved.
- **Region monitoring is unverified on hardware.** Everything below CoreLocation
  is tested on the simulator, but geofence entry/exit, background wake, and
  Always-permission behaviour need a physical device.

## Capitalization still decides two things

Lowercasing the whole gating corpus costs 4 blocking failures against 0 for
every other rendering (`corpus-run --rendering lowercased`). It was 9 before the
Phase 2 coordination work removed the two clause-splitting gates that read
`NLTagger.personalName` and a bare capital letter. What is left:

- **The shopping grouper.** "Get Coke and Sprite" produces two shopping rows and
  "get coke and sprite" produces one shopping row and a Memory note, because
  product recognition reads the capital. This is genuinely lexical — "sprite" is
  a brand — so it does not have the structural fix the clause splitter had.
- **Name casing in titles and person fields.** "let priya know…" resolves the
  person as "Priya Know", and "remind me not to text dave tonight" titles the
  row "Don't text dave". Both are name-boundary and display-casing problems
  rather than routing ones.

The lowercased rendering is reported and does not gate, for the reason
`RenderingInvarianceTests` gives: a recognizer that lowercases a name has
already destroyed information the app cannot recover. The number is tracked so
the cost stays visible.

## Ownership does not read animacy

`ActionabilityReader.obligationBelongsToAnotherPerson` files "Mike should call
Sarah" in Memory, correctly, and would file "the car has to go in Tuesday" there
too, incorrectly. Separating an animate subject from an inanimate one needs
either a lexicon or an embedding query, and the rule deliberately does neither.

It is the safer wrong: the words are kept and nothing is scheduled, where the
opposite error puts a job the person never accepted on the list they work from.
No utterance of that shape appears in the 1,069-case corpus, so the cost is
currently hypothetical and the benefit is measured. If a real capture hits it,
the fix is a new corpus family, not a widening of the rule.

## Delete and remove are not operation verbs

"Cancel my plumber reminder" is recognised as an operation. "Delete the reminder
to call Dave" and "remove the dentist appointment" are not — they fall through
to a Memory row flagged for review, and nothing is destroyed.

This is a gap and it fails closed, which is why it is documented rather than
fixed. Modifying or deleting stored user data needs substantially stronger
evidence than creating content does, and widening the destructive vocabulary to
make the family consistent would trade a safe gap for an unsafe one. Both cases
are in `Tools/CorpusRunner/devsets/routed.tsv`, expected to fail, so the gap
stays measured.

## Intent consolidation reads English discourse markers only

`IntentConsolidator` decides that a capture is narrative from a closed list of
English phrases ("anyway", "the main thing is", "I've been meaning to"). A
capture in another language, or one that rambles without any of these markers,
falls through to clause splitting as before. The failure mode is the old one —
over-splitting — not a new one, and the raw transcript is preserved either way.

## Obligation vocabulary lives in four places and they still disagree

Four separate lists state "this is an obligation", and they agree on only 7 of
the 32 forms between them (22%):

| list | file | what it gates |
|---|---|---|
| `ClauseJuxtaposition.clauseInternalLead` | `SpeechRepair.swift:1289` | whether the sentence gets cut here |
| `ActionabilityReader.obligationLead` | `Actionability.swift:109` | Today versus Memory |
| `ObligationFrame.link` | `ThoughtOrganizer.swift` | what the row title reads |
| `ThoughtExtractor.isFragment` | `ThoughtExtractor.swift:1538` | whether a severed piece is glued back on |

Every *multi-word* frame is protected for free, because it ends in `to` and
`"to"` is the first entry in `clauseInternalLead`. Only single-token forms are
exposed, and the four that were missing from both of the first two lists —
`hafta`, `oughta`, `needa`, `better` — were cut in half: "I hafta drop the car
off on Thursday" filed a Memory note titled **"I hafta"** beside the errand.
Those four are now closed and pinned by nine `.dictation` corpus cases.

The structural problem is not closed. The four lists are still four lists, and
the next form somebody says will find whichever one is short. The fix is to
derive them from one shared definition. It is deliberately staged: three of the
four gate `count` or `route`, which are CRITICAL and BEHAVIORAL severity, so
unifying them needs its own measurement pass and its own release.

**Measured, and the reason a partial fix is not enough:** widening `isFragment`
alone — gluing the fragment back on without teaching `obligationLead` to read
the result — was measured over a 233-capture stress set as **-37 rows, and all
37 merges moved a Today task to a Memory note**, 19 of them dropping a resolved
due date and one destroying an errand outright. The gating corpus showed
**exactly zero change** for that same edit, so the corpus can neither detect the
defect nor certify the fix. Any future work here has to be measured on captures
authored for it.

## "I had better" keeps its frame in the row title

`ObligationFrame.link` admits `better` but not `had better`, so "I had better
drop the car off on Thursday" routes and dates correctly but still reads with
its frame attached. `'d better` works, because the clitic is part of the subject.

Admitting `had\s+better` would be one alternative, and it is left out on
purpose: nothing in the title layer knows whether a verb follows, so "I had
better luck last time" would be retitled **"Luck last time"**. A comparative
reading is more common than the past-tense deontic idiom in speech, and the
title layer refuses rather than guesses.

## Resolved in working tree: stacked errands behind a hedge

The shared action-body reader now peels the same guarded obligation frames as
the title layer. The reproduced three-errand capture produces three actionable
rows; a regression test preserves that result. Historical diagnosis follows.

### Original failure

`IntentConsolidation` destroys content on a run-on carrying three errands and a
discourse hedge:

    "I keep meaning to book the dentist and I have to call the bank about the
     fee and honestly I should just cancel the gym membership"
      -> one row, "Call the bank about the fee"

Both other errands are lost. This is **not** an obligation-vocabulary defect:
the spelled-out `have to` form and the contracted `oughta` form produce
byte-identical output, before and after the contraction work above. The clause
splitter segments it correctly into three; `consolidate` then collapses it.
Origin is `IntentConsolidation.swift` around the `isSubstantive` /
`elaborativeMarker` path.

## Resolved in working tree: preparatory and modal fragments

Preparatory “sit down and” stays with its action, and modal adverbs such as
“rarely” stay within their clause. Both examples below now produce one row and
have regression coverage. This does not imply every possible fragment is solved.

### Original failure

Independent of the frame reducer, `ThoughtExtractor` sometimes cuts a clause
where there is no clause boundary, and every title is downstream of that.
`I think I need to sit down and finally do my taxes this weekend` produces two
rows, and the first one is `Sit down`. `I should rarely call Dana about the
refund` produces `I should rarely` beside `Call Dana about the refund`.

The reducer improved both — the first row used to read
`I think I need to sit down and`, and the second used to read `Rarely` — but a
title cannot repair a split that should not have happened. The origin is clause
segmentation and `isFragment` in `ThoughtExtractor`, upstream of the formatter.

## Remaining validation after the September product fixes

- FoundationModels cancellation is cooperative. Measure generation latency and fallback behavior on an Apple Intelligence device before claiming a strict two-second completion bound.
- Portable iCloud semantics have local serialization/merge coverage. Live two-device delivery, permissions and notification behavior still require device QA.
- Whole-library search and full-file cloud snapshots remain in use. The projection and ranking changes do not establish performance at 50,000 items.
- Native dock glass and editor focus compile, but Dynamic Type, VoiceOver and animation quality need hands-on review; no Xcode UI suite was run in this work.
- The website needs a verified App Store listing URL in its metadata before download buttons can be enabled. Until then, its primary action opens the working browser demo.

## Morning brief limits

- The brief is planned by the app on foreground and background. A capture
  made through the share extension, Siri, or a Shortcut does not re-plan it
  until Speak It is next opened; the counts for a morning before that can be
  short by those captures. Reminders are unaffected.
- Shopping lists appear on Today as cards, not rows, and are not counted in
  the brief. "2 due today" can therefore be one fewer than the Now section
  shows when a list is due.
- "Answered" is inferred: the app was opened within twelve hours of a brief
  firing. Reading the brief on the Lock Screen and not opening the app counts
  as unanswered, so five such mornings in a row switch the brief off; it can
  be turned back on in Account & Settings.
- The brief is never announced in the app. It is found only as a switch in
  Account & Settings under Capture & reminders, so uptake depends on people
  opening that card.
- Notification delivery, Scheduled Summary placement, and Focus behaviour for
  the passive brief need hands-on iPhone QA; the simulator proves the request
  content, not the presentation.
