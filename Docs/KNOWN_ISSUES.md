# Known Issues

> **On trusting this document.** Several sessions have been ranking work from
> it, so how far it has been checked matters. On 2026-09-11 the "Ownership does
> not read animacy" entry was read against the source and its diagnosis
> corrected in place: an embedding is already loaded in that file, so the
> technique it calls a departure is established here. The "Delete and remove"
> entry was also found to misstate its root cause — the miss is the shape of
> the object noun phrase, not a missing verb — and is being rewritten alongside
> the code change that fixes it rather than here. **No other entry has been
> audited**, and at least one is believed to describe something already fixed.
> Treat an unmarked entry as a claim to verify before ranking work from it, not
> as a finding.

## "Don't buy milk" and "remind me not to buy milk" are opposite captures

**Measured 2026-09-11**, from the corpus and the source, not inferred from a
behaviour report.

Speak It already knows what a prohibition is. The `prohibitions` family is 17
cases of the gating corpus and passes. `Remind me not to buy milk` becomes a
Today task titled **Don't buy milk**; so does `Remind me to not buy milk`, and
the same for the plants, the tickets and Dave
(`SemanticCorpusDataI.swift:812-824`). `Please don't pay the invoice yet` is
kept as a Memory note, with the corpus saying why: *"A bare negative imperative
statement is preserved, not inverted"* (`:841`).

Say it the way people usually say it — `Don't buy milk`, `Don't fix the sink` —
and it is read instead as a **cancel operation** aimed at an existing reminder,
extracting no items at all (`SemanticCorpusDataA.swift:148`,
`SemanticCorpusDataD.swift:394`). So the corpus holds bare prohibitives that
behave in two opposite ways, and what separates them is not documented anywhere
and is not the speaker's intent. When no reminder matches, and for a capture
that is nothing but the prohibitive, the extraction carries no items, so the
"unmatched cancellation can itself be an errand" fallback is skipped at all
three of its sites — each guarded on `!extraction.items.isEmpty`
(`SwiftDataThoughtRepository.swift:92`, `:963`, `:1100`) — and
`discardCaptureItems` runs.

The person is told *"Couldn't find that — Nothing to cancel matching 'buy
milk'"* (`CaptureOperationCopy.swift:34`) and the capture does not spend one of
their ten free ones (`ThoughtRepository.swift:206`). The original transcript is
still on the `CaptureSession`. So nothing is destroyed and nothing is silent —
but Today and Memory are both empty, and which of the two outcomes the speaker
gets turns on a boundary nobody has written down.

**This is deliberate, not an oversight.** `testCancelWithNoMatchInventsNothing`
asserts it: after an unmatched cancellation, "no fake reminder, and no Memory
item standing in for the request". That test's case is `Cancel the dentist
reminder`, which names an item and is a command aimed at the app's own database.
`Don't buy milk` names an action. The app does not currently separate those two,
and the development set says it should: `routed.tsv` wants `delete the reminder
to call Dave` and `remove the dentist appointment` to be operations (both are
read as Memory today) and `don't call the plumber`, `don't fix the sink`,
`don't text Dave`, `don't reply to Dave` to be Today. The `prohibitive` family
scores **1 of 5** on destination, the worst in that set
([run 34601150638](https://github.com/CalvinSalsali04/speak-it/actions/runs/34601150638)).

**Why this is worth ranking above what looks worse.** It is the one remaining
family that is common everywhere rather than only in the set written for it. A
prohibitive opens 20 of the 1,393 gating cases, 5 of 116 in `routed`, and by
prevalence count alone — no rows read — 10 of 255 everyday captures, 7 of 389
held-out and 7 of 120 adversarial.

**What is not established:** what a person actually wants when they say it.
Both readings are defensible and the choice is a product decision, not an
engineering one. Also unestablished is whether `routed.tsv`'s expectation is
right or is mis-specified for an instrument that cannot see the repository:
`Tools/PipelineProbe` runs without a store, so every cancellation is unmatched
there by construction, and "got nothing" in that report is the extraction's
answer rather than what the person would see.

Finally, one note in the gating corpus overstates the current behaviour.
`SemanticCorpusDataD.swift:396` says a prohibitive "is preserved as a note when
nothing matches" — true only when the capture produced another item as well,
which is the case the guard above is written for. Nothing tests the claim as
written, because the gate scores the extraction and this happens in the
repository.

## Every routing rule rests on one framework answer, and it can be absent

**Verified 2026-09-11**, against the framework rather than inferred from a
behaviour. `SpeakItTests/NaturalLanguageEnvironmentTests` in
`RenderingInvarianceTests.swift` asks `NLTagger` and `NLEmbedding` directly.

On a GitHub-hosted `macos-26` runner's simulator, `NLTagger` returns
`OtherWord` for **every token of every sentence** while
`NLEmbedding.wordEmbedding(for: .english)` loads normally in the same process
([run 34597902006](https://github.com/CalvinSalsali04/speak-it/actions/runs/34597902006)).
The lexical-class model is simply not there.

Almost every routing rule is a structural query over that one answer.
`Actionability.withoutFrontedAdjunct` cuts "on the 15th" off "pay the rent"
only because the tagger calls "pay" a verb; "I had better luck last time" is
knowledge rather than an errand only because "luck" is a noun;
`ClauseJuxtaposition` refuses a cut in front of an adjunct only because the
head is verbless. With the tagger silent the app does not crash and does not
report an error — **every capture quietly reads as though it contained no
verbs**, errands stop being errands, and boundaries move.

What is confirmed: the unit suite cannot be trusted on that runner image for
any tagger-dependent assertion, and the author's Mac is the reference
environment. `Tools/CorpusRunner` is unaffected because it runs on the host.

What is **not** established: whether a real iPhone can reach the same state.
That needs a device check. What this entry records is the failure mode if one
ever does — silent degradation rather than an error — which is the part worth
knowing before anyone designs a fallback.

**And the app has no way to notice.** Nothing in the pipeline asks whether the
tagger answered at all. Every rule asks its own narrow question — is this token
a verb, is this head verbless — and an absent model answers each of them
plausibly and wrongly, so no rule sees anything unusual and there is no place
where the answers are compared against a case whose answer is known. The check
that would catch it is one sentence: tag a fixed string once and see whether any
token comes back as anything but `OtherWord`. `NaturalLanguageEnvironmentTests`
already does exactly that through `SentenceContext` — the diagnostic exists and
nothing in the app runs it.

That is worth separating from what the app should then *do*, which is a product
decision and not an engineering one: carry on and route worse, tell the person
something is wrong, or fall back to a purely lexical reading. None of the three
is obviously right, and the detection is worth nothing until one is chosen. The
detection is also untested against a device that has actually lost the model,
because no such device has been observed — only the runner image.

## Physical-device voice validation

The project builds and launches on an iPhone 13, passes Xcode static analysis, and all 95 repository, extraction, routing, sync, reminder, draft, integration, and reliability tests pass on an iPhone 17 Pro simulator. The capture subset also passed 175 repeated executions, and the previous complete 93-test baseline passes both Address Sanitizer and Thread Sanitizer. Microphone quality, speech accuracy, true Back Tap recognition, interruptions, AirPods, and locked-device behavior still require the physical-iPhone matrix in `CAPTURE_STRESS_TEST_PLAN.md`; iOS does not expose the hardware Back Tap gesture to automated tests.

## The app cannot set what customers are charged

September 8 pricing follow-up: launch percentage claims now require the actual USD 14.99 product price, enabled flag and sale window. Other currencies show localized prices without an unverified discount. The future standard price and preservation of existing subscriber prices still need App Store Connect verification; the paywall no longer promises an indefinite rate.

`SpeakIt.storekit` is a local test configuration; the app renders StoreKit's
localized price. The September 9 App Store Connect review recorded USD 2.99
monthly and USD 14.99 annual, with other storefronts preserved. The future
annual increase remains unconfigured. See
[the recorded pricing status](APP_STORE_PRICING_STATUS_2026-09-09.md).
The paywall now selects and badges annual only when its actual price and
currency demonstrate savings against twelve monthly payments. Sandbox purchase,
renewal, restore, and physical-device price checks remain outstanding.

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

*Appearance is applied by hand, not by `preferredColorScheme` (2026-09-10).* SwiftUI keeps the last non-nil value `preferredColorScheme` was given and re-asserts it whenever the traits change, so after the app had been in Light (the first-install default) choosing System left a light window that ignored the iPhone's own switch until relaunch; clearing the window, controller and view overrides did not help because SwiftUI wrote Light back on the next trait change. `SpeakItAppearanceSync` and `SpeakItSceneDelegate.sceneWillEnterForeground` now write `overrideUserInterfaceStyle` onto the window tree themselves and nothing passes a scheme to SwiftUI. XCUITest cannot read the effective scheme, so the check is the gated probe `testSystemAppearanceHandsControlBackToIOS` (set `TEST_RUNNER_SPEAKIT_APPEARANCE_PROBE_DIR`, flip `xcrun simctl ui <udid> appearance` while it holds, and compare `simctl io screenshot` brightness; modes `system`, `control`, `explicit`).

*Simulator-level defaults shadow `--ui-testing-reset` (2026-09-09).* A value seeded with `xcrun simctl spawn <udid> defaults write com.calvinwak.SpeakIt …` lands in the simulator-user plist outside the app container, and the reset flag only removes `UserDefaults.standard` keys inside it. The 2026-09-03 dark-mode walk left `SpeakIt.appearance = dark` on the stock iPhone 17 Pro simulator, which made `testFirstInstallAppearanceDefaultsToLight` fail deterministically until the key was deleted with `simctl spawn … defaults delete`. Delete seeded keys after hand QA, or use a dedicated simulator; `Tools/Screenshots/capture.sh` cleans up its own.

*Share-sheet captures are retried on every foreground (2026-09-09).* Launch recovery now stops re-reading a capture after two lost launches (`CaptureRecoveryAttemptLedger`), for unorganized sessions and interrupted drafts. The share inbox in `RootView` still retries every file on every foreground with no attempt count, so a shared snippet whose words trap the pipeline would still crash each foreground until the file is removed. The rules trap that motivated the guard is fixed; the inbox guard is the remaining gap.

Standard-size Today and Memory layouts now have clean-state simulator visual coverage. A dark-mode walk of Welcome, Today, Account & Settings and the Capture Anywhere method list on an iPhone 17 Pro simulator (2026-09-03) found and fixed two dark-only defects — an on switch with an invisible knob, and the selected method row's icon halo — and confirmed the new wordmark and icon in both appearances. VoiceOver, the largest accessibility Dynamic Type sizes, rotation policy, and a complete dark-mode pass still require hands-on device QA. The implementation uses semantic system controls and colours, but automated unit tests cannot replace that pass.

## `accessibilityHidden` removes nothing on iOS 26.5

Measured on 2026-08-31 against the accessibility tree XCUITest reads, on the iOS 26.5 simulator: `.accessibilityHidden(true)` takes elements out of nothing. Not a container of rows, not a lone `Text`. `.accessibilityElement(children: .ignore)` and zero opacity do not remove them either. The modifier is reaching the view — an `.accessibilityLabel` added to the same chain in the same build changed the element's label while the element stayed in the tree — it simply has no effect on membership.

Today's collapsed disclosure sections were fixed by not building their rows while closed (`TodayDisclosureContent` in `SpeakIt/Features/Today/TodayView.swift`), which is the only mechanism observed to work. `testTodayDisclosureOpensAndClosesWithoutLeakingHiddenRows` in `SpeakItUITests/SpeakItUITests.swift` asserts a hidden row's button and title both leave the tree on collapse and return on expand.

The consequence elsewhere has not been measured. Every remaining `.accessibilityHidden(true)` in the app hides a decorative image — `CapturedItemRow`, `ShoppingListView`, `PlaceSetupView`, `ItemEditorView`, `RootView` — and on this OS none of them is likely to be doing what it says. XCUITest and VoiceOver read the same tree but are not the same client, so whether these images are actually *spoken* needs the hands-on VoiceOver pass, not another automated run. Nothing hidden this way carries an action, so the risk is verbosity rather than a wrong tap.

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
  cue, so those sentences are events now. "We fly out on 5 Sept" is an
  event in either date order now (re-probed 2026-09-07). "Grab lunch with Sam at noon" is
  now an event: get/grab meal and coffee plans with a confidently identified
  companion take precedence over acquisition classification. Weak person guesses
  (including uncapitalized names without relationship evidence) remain on the
  existing path; food accompaniments must not become appointments.
  "On the 1st renew the car insurance" is one dated task now
  (2026-09-07, corpus family 55): a fronted prepositional phrase with no verb
  and no subject in it is context for the action in both the clause splitter
  and the actionability reader, so "after dinner call Mom", "by Friday send
  the invoice" and "at the store buy milk" no longer leave a phantom row
  behind. The same reading holds on the right of an "and" ("book the dentist and
  before dinner call Mom" splits at the "and", and the date stays with the
  errand it fronts) and for the deictic days ("tomorrow morning email the
  landlord" is one dated task). "After I finish the essay call Dave" and
  "as soon as I land text Mom" are one Today row each now, held in Needs
  review with the condition named, as "When I get paid, remind me to
  transfer money" already was (corpus family 56); the condition is
  understood and still not enforced, which is the compound-trigger
  limitation below. "We're at five" is a Memory note now (2026-09-08): a pronoun straight before "at" is a person stating where they are, and "we're meeting at five" keeps its event. And "the first
  appointment is at 9" no longer means the 1st of next month; as of
  2026-09-08 a bare 8–11 beside a meeting, appointment, dentist, doctor,
  interview or checkup is the morning and rolls to tomorrow when it has
  passed (domains C4 d, closed), while "call Sam at 9" still means the next
  9 and "meeting at 7" the next 7.
- **The date-only alert hour is a setting now.** *Resolved 2026-09-08.* `TemporalResolver.dateOnlyAlertHour` reads the **Default reminder time** under Settings → Capture & reminders (`ReminderDefaults`, shared app-group defaults, 9:00 until changed). It is the moment "remind me tomorrow" alerts at; "tomorrow morning" and "first thing" stay on `TemporalResolver.morningHour`, which is 9 AM and not a preference. The distinction the constant enforced still holds: *"buy milk tomorrow"* schedules nothing at all, while *"remind me to buy milk tomorrow"* alerts at the default time, and neither writes a time into the intent. A reminder already scheduled keeps the moment it was given; the setting applies to captures organized from then on.

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

## Capitalization still decides some metadata

Lowercasing the whole gating corpus costs 0 blocking failures as of 2026-09-08
(`corpus-run --rendering lowercased`; 16 metadata and 2 cosmetic
disagreements remain as of 2026-09-09, seven of them the transported-people
cases below, whose person the flattened rendering cannot name; a flattened
"jean-luc", "wish grandma happy birthday" and "call catherine, actually alex"
now resolve the same person as their cased forms; and the people sweep's P2
cluster, "call Mom tomorrow and my sister Friday" never splitting, is closed
the same day, P1 having been closed in both casings already). It was 9 before the Phase 2 coordination work removed
the two clause-splitting gates that read `NLTagger.personalName` and a bare
capital letter, and 1 until the shopping list rule below. What was left:

- **The shopping grouper.** *Resolved 2026-09-08.* "Get Coke and Sprite" was two
  shopping rows and "get coke and sprite" one shopping row and a Memory note.
  The cause was not product recognition but the one-word-closes-a-list rule in
  the coordination gate, which wanted two items behind the verb; with one, the
  lone word fell to the tagger, which calls a lowercased "sprite" a verb. A
  one-item list now closes the same way, and the lone word is asked whether it
  is an errand on its own ("buy milk and run" keeps its two rows).
- **An unfamiliar head verb read as a proper noun.** *Resolved 2026-09-08.*
  "Descale kettle" reached Memory because "descale" is outside the embedding's
  vocabulary and the tagger takes an unfamiliar capitalized word for a name.
  A productive prefix on a stem the vocabulary knows now reads as a verb, and
  the padded fragment is tagged lowercased as well as written. "Reseal deck"
  still declines ("seal" is read as a noun); the fix is measured, not a list.
- **Transported people read the tagger's name tag.** "Pick up Alex from
  school" is a task about Alex, but only because `NLTagger` calls the
  capitalized "Alex" a personal name there; "pick up alex" is a shopping row,
  and "Pick up Alex" on its own is one too, because the tagger calls that
  "Alex" a place. Kinship words ("pick up mom") do not depend on it. See
  `DECISIONS.md`, 2026-09-08.
- **Name casing in titles and person fields.** *Resolved 2026-09-07.* "let
  priya know…" resolved the person as "Priya Know" because the lowercase path
  let the frame's own anchor join the name; the anchor now closes the name.
  "remind me not to text dave tonight" titled the row "Don't text dave"; the
  title now writes a resolved person the way the resolver displays it
  (`ThoughtTitleFormatter.restoringNameCasing`), whole words only, without
  flattening a name the speaker cased themselves. No lexicon is consulted.

The lowercased rendering is reported and does not gate, for the reason
`RenderingInvarianceTests` gives: a recognizer that lowercases a name has
already destroyed information the app cannot recover. The number is tracked so
the cost stays visible.

## Ownership does not read animacy

`ActionabilityReader.obligationBelongsToAnotherPerson` files "Mike should call
Sarah" in Memory, correctly, and would file "the car has to go in Tuesday" there
too, incorrectly. Separating an animate subject from an inanimate one needs
either a lexicon or an embedding query, and the rule — a regex over a pronoun
stoplist at `Actionability.swift:752` — does neither.

*Corrected 2026-09-11:* the previous wording said "deliberately does neither",
which reads as though querying an embedding would be a departure for this
codebase. It would not. `Actionability.swift:920` already loads
`NLEmbedding.wordEmbedding(for: .english)` in this same file, and
`PersonMentionResolver.readsAsOccupation` already decides the adjacent
role-versus-person question that way, measured over 30 trade nouns and 36
personal names at 28 of 30 blocked with 0 of 36 names lost. So the cost of
reading animacy here is a query against a vocabulary that is already loaded,
not a new dependency. What is deliberate is the *priority*, not the technique —
see the paragraph below.

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

## A verb with no object is not read as an unfinished thought

**Measured 2026-09-11**, run 34617253884 on `macos-26`, from
`Tools/CorpusRunner/devsets/unfinished.tsv`.

`ThoughtCompletion` reads the tail of a sentence structurally: a word whose job
is to introduce something, left with nothing behind it. "Tomorrow I want to"
ends on the infinitive marker and is caught — `dangling-infinitive` scores
**18/20**. "Tomorrow I want" ends on the verb itself, and nothing reaches it —
`incomplete-complement` scores **1/10**.

**What a person sees.** "Tomorrow I want" becomes a Today task, titled with
those three words, dated tomorrow. Half a sentence arrives looking like a
decision the person made. That is the severity of this entry rather than a
second entry: `unfinished.tsv` reports it as `UNSAFE 2` — a fragment given a
date — and both captures behind that figure are ones this gap missed.
`ThoughtOrganizer` drops every commitment the moment the thought is recognised
as unfinished, so **the unsafe count reaches 0 when this gap closes**, with no
separate guard to build. One defect, one entry, and it retires in one piece.

**Four of the nine misses are not this gap and must not be swept in with it.**
Each is a decline recorded in `ClauseStructure.swift` with the measurement
behind it: a stranded preposition ("Meet Mike at" and "remind me an hour
before" are the same shape and the second is finished), a particle behind a
verb (the guard that keeps "follow up" and "check in" whole), and a bare
one-word imperative (`NLTagger` classifies a lone "Add" differently on macOS
and on iOS). Those stay declined.

**Why it is documented rather than fixed.** The five that remain — "I want",
"I need", "I have to get", "I should buy", "Tomorrow I want" — need the app to
know that "buy" takes an object and "ate" does not. That is a vocabulary list,
and `ClauseStructure` is built on the principle that word lists do not survive
contact with speech; the three classes tried and removed there cost four
blocking corpus failures between them. The safe direction is also not obvious:
`unfinished` fallout is **0/96** today, and "I need" said as a complete
utterance is exactly the shape a widened detector starts eating.

## Run-on speech with no marker in it is still one row

`DiscourseFrame` and the enumeration vocabulary in `splitClauses` read the
frame a speaker *states*: a farewell at the end, "number two" in the middle,
"first of all" at the front. Everyday held-out measurement after that change:
every farewell is out of every title (`trailing-goodbye` 0/7 → 7/7 clean),
and `sequencing` gained a capture on both routing and count.

What did not move is the larger half. `run-on` is 0/8 on routing and 0/8 on
count, and `multi-thought` is 19/40 and 22/40, unchanged. A person who says
three things in one breath with no marker between them still gets one row.
Under-segmentation outnumbers over-segmentation 23 to 16 on that set.

Two narrower gaps sit inside the same area:

- A numbered enumerator in front of a **fact** is not read as a boundary.
  "Number two the garage code is 4821" keeps the marker, because the gate
  requires an instruction behind the number — which is what keeps "gate number
  two" and "apartment number three" from being cut. One capture in the everyday
  set still carries `number two` in its title for this reason.
- A long capture whose title is the whole capture — 8 of them — was never
  summarised at all. That is a different stage from framing.

The words are never lost either way: nothing lost held at 210/224 across the
change, and the verbatim transcript is untouched by design.

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

*Addressed for clear action complements.* "I had better drop the car off on
Thursday" now reads "Drop the car off on Thursday". The reducer checks both
the verb and its complement instead of widening `link`: a determiner, pronoun,
particle, or confidently named object corroborates the action. Negation,
historical time cues, weak noun/verb readings, and manually edited titles keep
their wording. Tests include "better luck", "better service", "better call
quality", and "better pay last year".

*Clear past comparisons now route to Memory.* "I had better luck last time",
"I had better service at that hotel", and "We had better seats at the concert"
no longer become tasks. A noun phrase without a verb after "I/we had better"
is past possession, not advice. Explicit reminder requests still take priority,
and a second actionable clause keeps its task and date. Ambiguous readings such
as "better call quality" or "better pay last year", whose nouns are tagged as
verbs, remain outside this conservative routing fix.

Historical diagnosis:

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
- The September 9 full UI run passed 24 tests, including its accessibility-text/dark-appearance flow. Its one stale pricing assertion was corrected and passed on rerun. Physical VoiceOver and animation quality still need hands-on review.
- The website needs a verified App Store listing URL in its metadata before download buttons can be enabled. Until then, its primary action opens the working browser demo.

## Morning brief limits

- The brief is planned by the app on foreground and background. A capture
  made through the share extension, Siri, or a Shortcut does not re-plan it
  until Speak It is next opened; the counts for a morning before that can be
  short by those captures. Reminders are unaffected.
- **Shopping-list counts resolved (2026-09-08).** The brief counts each dated
  shopping list once, using the same earliest open entry as its Today card.
  Completed and archived entries are excluded; undated lists are not counted.
- A brief tap now selects Today, including on cold launch, without starting a
  capture. Direct taps reset the unanswered count regardless of age.
- For ordinary app opens, "answered" is inferred: the app was opened within twelve hours of a brief
  firing. Reading the brief on the Lock Screen and not opening the app counts
  as unanswered, so five such mornings in a row switch the brief off; it can
  be turned back on in Account & Settings.
- The brief is never announced in the app. It is found only as a switch in
  Account & Settings under Capture & reminders, so uptake depends on people
  opening that card.
- Notification delivery, Scheduled Summary placement, and Focus behaviour for
  the passive brief need hands-on iPhone QA; the simulator proves the request
  content, not the presentation.

## September 8 pricing verification

Release compile, focused ItemPresentationTests and the corpus gate pass. The full unit run returned 295 passed and seven process-kill/bootstrap failures. The paywall UI test failed twice; the first result points to its initial Speak It Pro navigation-bar wait (before price assertions). UI and live Sandbox purchase verification remain incomplete.

## September 9 continuation verification

The full UI run's only failure required the deliberately removed promise that
a launch subscriber's renewal price would stay fixed forever. The corrected
assertion checks the current terms and passes. Test-only provisional permission
also enabled all six previously skipped notification-center tests: the temporal
suite passed 25 with one expected denied-permission skip. Actual Focus, delivery,
lock-screen and device behavior remain separate checks.

The 116-case routing development set still flags three ambiguous captures as
acted on. It also contains expectations that conflict with later contract
decisions for reported instructions and prohibitions. Its destination score is
not an independent release verdict. The unseen set remains 72.8% on destination
and 7/69 acted-on ambiguous captures; the date-topic fix did not improve that
aggregate.
