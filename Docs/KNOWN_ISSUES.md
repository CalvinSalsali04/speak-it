# Known Issues

## Automatic capture follow-up (unreleased)

Voice now starts on presentation with automatic endpointing and no mode
selector. Timed shopping rows separate products, place grouping, and time
metadata. Named-place lookup remains unsupported: an arrival destination is
retained, with the existing options to use Home/Work or set a time. The app
does not infer a specific Hamilton or silently create a geofence from its name.
Real microphone endpointing and recognition on iPhone 13/16 still require
physical-device QA. The source change does not update the installed Build 22.


## Build 22 list and voice behavior

“Remind me to complete my scientific computation and real time systems
assignment” is one task. It still needs a reminder time; no hour is guessed.
Swipe X Remove completes a list item just like its circle, retaining it in
Settings → Completed. Keep as one thought answers grouping only.
Auto finish waits longer for incomplete phrasing, so it is not an immediate
stop at every brief pause. Real microphone endpointing, interruptions and
model latency on iPhone 13/16 still require hands-on QA. Focused regressions
and UI checks do not establish a new global capture-accuracy percentage.


## Build 21 full-bank trial — device support and accuracy limits

The bundled development bank occupies about 1.42 GB before distribution
compression. Search reads the index and a few selected payloads, rather than
loading the bank into memory. The reviewed 59-record collection is retained
as a small regression fixture; it is not the app's search limit.

Apple's language model is unavailable on iPhone 13. iPhone 16 additionally
requires a supported OS/language and an enabled, downloaded Apple Intelligence
model. Availability does not guarantee every capture uses a generated result:
failed, cancelled, over-budget or invalid generations fall back safely.
The 510,000 synthetic proposals are not 510,000 independently reviewed stories,
and searching more of them does not itself establish improved accuracy.
Physical microphone, interruption, Back Tap, AirPods, lock-screen and model
latency checks on both target phones remain hands-on QA.

The October 11 retrieval candidate adds 1,696 representatives covering the
212 authored example blueprints. Its compact index searches representatives
and reads the selected payloads from the complete bank; it does not search
every one of the 510,000 wordings on each capture. Compact and semantic routing
remain disabled in the bundled configuration pending qualification. Zero
retrieval errors or a relevant-example match does not prove that final Today
and Memory organization is correct. The complete-model preflight has retained
unresolved captures and missed explicit actions; this is still an accuracy
limitation, even when all original words remain recoverable. Mac model timings
and results do not establish behavior on the iPhone 16's iOS 26.6 model.

Mixed captures can still require review when the engine cannot prove separate
owners for their actions, facts, conditions and corrections within its existing
time budget. A bounded local certificate covers complete factual notes and
explicit own actions only when every source occurrence has an independent
owner. Other material uses the normal engine. Retaining all source
words in a review item protects the capture but does not count as successful
organization of each action.

The failed-capture replay also exposed long narratives that the rules fallback
can still combine into an incomplete task. The weekly parser now requires an
actual temporal quantifier, so an unrelated “every resident” cannot create a
weekly schedule. That repair removes the invented series; it does not establish
complete organization of the long narrative, particularly without an available
generative model.

Month-end and end-bounded recurrence forms that the stored recurrence model
cannot represent remain for review without an active series. An explicit
instruction to leave the hour unset is not replaced with a default clock.
After a local withdrawal such as “cancel that thought, I already bought them,”
the retained Memory title can still use “them”; the complete original capture
retains its object context. This is a presentation limitation, not permission
to complete an older saved task.

The October 12 fixes receive failed-check retries and a final integration/app
smoke. They do not establish a new global accuracy score or an iPhone latency
claim; the earlier 330-case baseline and failed runs remain preserved.

The separately installed Build 20 preview owns its own scheduled notifications.
Build 21 can import its shared library and drafts, but cannot cancel another
app's notifications through its own notification center. After confirming the
import, disable notifications for the old preview or remove that app if it has
pending reminders. Keep the original installation until its captures are
verified in the normal app. Apple's notification center is scoped to the
[app or its extension](https://developer.apple.com/documentation/usernotifications/unusernotificationcenter).


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
>
> *2026-09-15.* The animacy entry was sized as well as read, and it is **an
> accepted decision, not open work** — see the table in it. What the sizing
> turned up applies to the whole document: its corpus figure was wrong, and
> disagreed with the same figure in the source it describes — 1,069 here, 1,022
> there, 1,404 in fact. **A number typed into prose recomputes nowhere and says
> nothing when it goes wrong.**
>
> The line-number citations were checked at the same time and are in better
> shape than that. Of the sixteen `File.swift:N` citations here, none points
> anywhere wrong, and one is off by a line: `ThoughtRepository.swift:206`, in
> the cancellation entry, lands on the last line of the docstring for
> `consumesFreeCapture`, declared on 207. They are the same kind of claim as
> the figure and they drift the same silent way — the two `Actionability.swift`
> citations in the animacy entry were correct until the commit that wrote this
> paragraph grew a docstring above them, and nothing said so.

## A considered thought and a committed one look the same once stored

`SemanticGap` names one reason per structural question the pipeline asks, and
none of them is "the speaker was only considering this". "I might repaint the
hallway tomorrow" and "I'm repainting the hallway tomorrow" differ by a modal
and by whether anything is owed, and a row written from the first can record
`needsClarification` but not *why*. The four gaps that come closest —
`incompleteThought`, `reportedSpeech`, `unsupportedCondition`, `ambiguousActor` —
are each about something else, and using one of them would be a marker standing
in for a judgement it does not make.

Found while building the interpretation prototype, which does have a field for
it (`SegmentDisposition.hypothetical`) and has to drop it on the way into the
stored model. Adding a case is allowed — the raw values are persisted, so a case
may be added and none may ever be renamed — but it is a schema decision that
wants evidence first: nothing here establishes how often people dictate a
thought they have not committed to. See `Docs/FOUNDATION_MODELS_ARCHITECTURE.md`.


## A thought that stops and then keeps going is read as finished

**Measured 2026-09-11, run 34644656689, and traced to source. Six named
captures below; the rate is `abandoned-midthought` 3 of 9 in
`devsets/unfinished.tsv`.**

When somebody opens a thought, loses it, and says so out loud — *"Tomorrow I
need to, um, wait, I forgot"* — Speak It files a confident Today task and dates
it Tuesday. Not a flagged fragment the person can finish: `state=resolved`, a
date attached. Four of the six captures in this shape become tasks, one of them
dated, and the speaker never said what the task was.

**Root cause.** `ThoughtCompletion.unfinished` in `ClauseStructure.swift` reads
`tokens.last`, its lexical class, the token before it, and — for `to` — how
many infinitive markers the clause holds. That is its entire reach. It can only
recognise a thought that **stops** at the moment it breaks off. The three
captures in this family that pass are exactly the three whose filler strips
back to a clause ending on `to`.

So the words a speaker uses to say the thought is gone (*I forgot*, *I lost
it*, *hold on*, *what was it*, a trailing *I mean*) are evidence about what came
before them, and nothing in the pipeline reads them that way. `SpeechRepair`
carries a closed class for *"the speaker took it back"* and has no counterpart
for *"the speaker lost it"* — different destinations, `Abandoned` against
`Incomplete`, and only one is modelled. The representation for the second
(`SemanticGap.incompleteThought`) already exists; what is missing is anything
that reaches it from here.

**Why it is named rather than fixed.** Across 102,420 readable sentences the
shape occurs six times and all six are rows written for this set. The same set
contains its own trap — `I think I forgot` is a finished sentence — so a rule
keyed on the phrase would put the first hole in a `0/96` fallout record to
recover captures nobody outside this repository has said. A structural version
(an infinitive or modal frame followed by a finite clause that cannot fill it)
would reach four of the six and is worth building **against real captures**,
which is where this is blocked. See `Docs/LANGUAGE_BASELINE.md`, 20:38.

## A choice can be recorded as open, never as resolved

**Verified from source 2026-09-11; the per-row consequence is a prediction, not
a measurement, and is marked as such below.**

Speak It can represent *"the speaker named alternatives and did not choose"*. It
has no representation for *"named alternatives and then chose."* Thinking aloud
and landing on an answer is therefore read as thinking aloud and never landing.

`TemporalCommitment.Unsettled` in `ClauseStructure.swift` is a closed enum of
four reasons a stated time is not settled, and `competingDays` fires on
`<day> or <day>` anywhere in the clause. It is terminal: nothing downstream
looks for a resolution stated afterwards. The assumption is written into the
comment above it — *"'or Wednesday' names two days precisely because the
speaker has not picked"* — which is true of "Tuesday or Wednesday" standing
alone and false the moment a person carries on talking. `ThoughtOrganizer`
then drops the date and keeps the words.

So of a development capture reading *"maybe cook the salmon Wednesday or
Thursday, I think Thursday, cook the salmon on Thursday"*, the pattern matches
`Wednesday or Thursday` and the clause carrying it loses its date, although the
speaker resolved the choice twice in the following six words. Its clean twin,
"cook the salmon on Thursday", does not match and keeps everything. **Predicted,
not observed:** `unsettled` is consulted per row after clause splitting, so
which row loses the date depends on where the cut falls, and no run has
confirmed the final rows. The prediction is recorded here so the next
measurement can falsify it.

The clause-level counterpart is the same shape. `SelfCorrectionResolver`
repairs by **slot replacement** — a later value overwrites an earlier one in
the same slot — so it can fix "Tuesday, no, Wednesday" and cannot express
"drive or take the bus, actually no, take the bus", where the alternatives are
whole clauses and there is no slot to swap. Resolution is representable for a
value inside a slot and not representable for a choice between clauses.

**Why this is named rather than patched.** A resolution test bolted onto
`unsettled` would cover the temporal case and miss the clause case, which is
most of the family: the shape needs somewhere to put a *choice set with an
optional resolution*, carried from clause analysis through to the organized
thought, so that a later mention of one alternative — or a resolution marker
like "actually no", "I think", "better" — selects it and everything downstream
reads the winner. That is a representation change, not a rule.

It is not being built yet, and the reason is evidential rather than technical.
The readable material for this family is five rows in
`Tools/CorpusRunner/devsets/rambling.tsv`, all written by one author, and four
of them phrase the resolution as a restatement of the canonical sentence rather
than as a person actually resolving a choice. Rewritten rows are being written
by a second author. Building a representation against five self-authored rows
would measure our idea of how people deliberate, which is the failure this
whole set exists to escape.

Development-set standing: `decision` scores **1 of 6** on thought count, the
worst family in any readable set.

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

**Re-verified 2026-09-16**, and the date is kept beside the first rather than
replacing it, because what matters is that two readings five days apart agree
about a runner image that can change under us.
[Run 35126863033](https://github.com/CalvinSalsali04/speak-it/actions/runs/35126863033)
returned the same readout on `main`: `11 passed, 4 failed`, every token
`OtherWord`, `NLEmbedding` green in the same process. Read a *pass* here as the
surprising result; a failure is only the status quo holding.

**What the second reading added: the failures are the smaller half.** A rule
that reads the tagger's silence as fact does not only return the wrong answer —
it returns the *same* answer for every input, and for
`ThoughtCompletion.unfinished` that answer is nil. So on this image every
assertion expecting nil passes without exercising the rule it names. In
`ThoughtCompletionTests` the two failing assertions were the only ones in the
class carrying information about the tagger-dependent rules; three more passed
as tautologies, as did one written that same day to test something else
entirely.

That is the distinction worth keeping, because a summary table hides it.
`NaturalLanguageEnvironmentTests` fails **deliberately** — it is the diagnostic,
and its failure is the information it exists to deliver. A rule test that fails
for the diagnostic's reason fails **accidentally**, and reports "this rule is
broken" when what happened is "I could not ask". `LexicalTagging.skipIfBlind`,
beside the probe in `RenderingInvarianceTests.swift`, separates them: the
dependent assertions abstain into the Skipped column and the diagnostic still
fails loudly. The diagnostic must never abstain — a suite that skips its way to
green is the same defect as a step that runs no tests, one level up — and a
test pins that it does not.

This has a deadline. `ci.yml` defaults the test selection to the whole of
`SpeakItTests` and runs the `iOS app` job only on dispatch or once
`vars.IOS_RUNNER` names a self-hosted Mac. So the unit suite cannot come back
green on a hosted runner today, and on the day anyone sets `IOS_RUNNER` — which
that file describes as the intended direction — every pull request goes red on
its first run for reasons unrelated to it.

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

*The launch screen follows the phone, not the app (2026-09-18).* `UILaunchScreen` is drawn by the system before any app code runs, so it uses the device's appearance. Someone who has chosen Dark in Speak It while the iPhone is in Light still sees a light launch screen for the moment before the first frame. There is no API that lets an app's own choice reach it; a dark launch storyboard would only move the flash to the opposite pairing.

*Appearance is applied by hand, not by `preferredColorScheme` (2026-09-10).* SwiftUI keeps the last non-nil value `preferredColorScheme` was given and re-asserts it whenever the traits change, so after the app had been in Light (the first-install default) choosing System left a light window that ignored the iPhone's own switch until relaunch; clearing the window, controller and view overrides did not help because SwiftUI wrote Light back on the next trait change. `SpeakItAppearanceSync` and `SpeakItSceneDelegate.sceneWillEnterForeground` now write `overrideUserInterfaceStyle` onto the window themselves and nothing passes a scheme to SwiftUI. Since 2026-09-18 the write is made under a snapshot of the outgoing appearance, which is then faded off the top, because the assignment alone reaches SwiftUI, `UINavigationBar` and `UISegmentedControl` on three different clocks (see `Docs/DECISIONS.md`). XCUITest cannot read the effective scheme, so the check is the gated probe `testSystemAppearanceHandsControlBackToIOS` (set `TEST_RUNNER_SPEAKIT_APPEARANCE_PROBE_DIR`, flip `xcrun simctl ui <udid> appearance` while it holds, and compare `simctl io screenshot` brightness; modes `system`, `control`, `explicit`).

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
stoplist at `Actionability.swift:779` — does neither.

*Corrected 2026-09-11:* the previous wording said "deliberately does neither",
which reads as though querying an embedding would be a departure for this
codebase. It would not. `Actionability.swift:947` already loads
`NLEmbedding.wordEmbedding(for: .english)` in this same file, and
`PersonMentionResolver.readsAsOccupation` already decides the adjacent
role-versus-person question that way, measured over 30 trade nouns and 36
personal names at 28 of 30 blocked with 0 of 36 names lost. So the cost of
reading animacy here is a query against a vocabulary that is already loaded,
not a new dependency. What is deliberate is the *priority*, not the technique —
see the paragraph below.

It is the safer wrong: the words are kept and nothing is scheduled, where the
opposite error puts a job the person never accepted on the list they work from.
If a real capture hits it, the fix is a new corpus family, not a widening of the
rule.

*Sized 2026-09-15.* The claim under that decision — that nothing of the shape is
attested — holds, and both figures it was written with were wrong. This entry
said 1,069 cases and the rule's own docstring said 1,022, for a gating corpus
then holding **1,404**. Neither number recomputed anywhere, which is the same defect
[#82](https://github.com/CalvinSalsali04/speak-it/pull/82) fixed for the
baseline's population section.

Screening every readable utterance for the subject slot the rule reads:

| population | of the shape | inanimate subject in an utterance position |
| --- | --- | --- |
| gating corpus, `corpusCase` utterance slot | 6 | 0 |
| the seven development sets | 4 | 0 |
| everything readable | 89 distinct, on 2026-09-15 | 0 |

The row counts are deliberately not in that table. Between opening this change
and merging it the readable population went from 10,139 rows to 11,106, twice,
because other work landed on `main` — which is the argument of this entry
happening to the entry itself. What is checked is the first row's subjects; the
third row's 89 is dated for the same reason the denominators are gone, since
nothing recomputes it either. The qualifier in the last column is load bearing:
outside an utterance position the readable population is full of inanimate
subjects, and they are the assertion messages described below.

The gating corpus's six are *Mike* twice, *My brother*, *Priya*, *Dana*, and a
bare *No* — the last being the screen reaching wider than the rule, off "No need
to book the table", a row the corpus labels `count: 0, operation: [.cancel]`.
The development sets add *Mike* three more times and *my brother*, in
`routed.tsv` and `unfinished.tsv`.

The 89 in the third row look alarming and are not. Six of them sit in the
`corpusCase` utterance slot — the same six above. **Two more are development-set
rows with human subjects** — "Mike needs to sign it" in `unfinished.tsv` and "my
brother has to renew his passport" in `routed.tsv`; the other two development-set
hits are strings that also sit in the gating slot, so they are inside the six
rather than beside them. **Every one of the rest is an XCTest assertion
message**: "A reschedule must never complete or remove the item", "The reminder
must land on a Friday". The readable-material census reads Swift by harvesting
literals, which is right for a leak check and counts reviewer prose as speech
here; position is what separates them, so the check added with this entry reads
the slot instead. Every inanimate subject in the readable population is one of
those assertion messages.

So the item is an accepted decision rather than an open defect, and it stays one
until a capture of the shape exists. What changed is that the sentence carrying
it now fails when it stops being true: `WhoTheCorpusSaysOwesSomething` in
`Tools/CorpusRunner/test_parser_vocabulary.py` pins those subjects, recomputes
them from the slot on every CI run, and fails when a new one appears. Animacy
still cannot be decided mechanically here, so the check does not try — it hands
a new subject to a person, which is the smallest thing that makes an
unrecomputable claim fail out loud.

## Removal requests: one defect closed, one decision open

*The old heading here — "delete and remove are not operation verbs" — was
wrong.* `delete`, `remove`, `clear`, `kill` and `drop` have been in the
cancellation patterns all along. The two cases filed under it failed for two
**different** reasons, and only one of them was a defect.

**Closed in the working tree (2026-09-11): word order.** The rule required the
container noun — reminder, task, item, note, alarm, entry — to be the *last
token of the sentence*. So "delete the call Dave reminder" was recognised and
"delete the reminder to call Dave" was not: the same request, post-modified
instead of pre-modified. That is positional and it is a defect.
`CaptureOperationDetector.removalOfStoredRow` now reads the **head** of the
object noun phrase and admits the two shapes an English noun phrase has:

- head-initial through a complement — "the reminder *to* call Dave", "the note
  *about* the picnic". Only a complement counts, so "remove the note *from* the
  fridge" is still a sticky note on a fridge.
- head-final when no prepositional phrase stands in front of the head — "the
  call Dave reminder", "the grocery list note". That test is what keeps "drop
  the kids *off at* the appointment" an errand.

The container vocabulary did not move, beyond admitting the plurals of the
nouns already there — which `CaptureTargetMatcher.stopWords` had always
treated as the same word. The **verb** list did not move either:
`removalVerb` is exactly `delete|remove|clear|kill|drop|get rid of`, the two
patterns it replaces. A leading "please" is newly tolerated, which is a
politeness marker rather than reach and is called out here because it is the
only other thing the change admits. `StoredRowRemovalTests` pins the shapes on
both sides.

`erase` is the verb a reader expects to find in that list and it is
deliberately absent, for the same reason `appointment` is absent from the
nouns: admitting it would make "erase the gym reminder" destroy a stored row
where today it is an ordinary capture. `ThoughtExtractor` does read `erase`,
in a rule that carves words out of a sentence rather than one that deletes a
row, so its presence there is not a precedent. Adding it is the same kind of
decision as the one below.

**Open, and a product decision rather than a defect: reach.** "Remove the
dentist appointment" is still not recognised, and no amount of noun-phrase
reading changes that: `appointment` has never been a container noun. Behind it
is a real inconsistency between two tiers of destructive verb:

| tier | target | what keeps it safe |
|---|---|---|
| `cancel` | unrestricted | `cancelsAnArrangement` — an arrangement noun or a deadline frame says the sentence is an errand |
| `delete`, `remove`, `clear`, `kill`, `drop` | must name a container noun | the container noun itself |

So "cancel the dentist appointment" acts on stored data and "remove the dentist
appointment" does not. Making the second tier read the first tier's evidence
would close the gap, and it would also widen what can destroy a person's rows.
That is Calvin's call, not the implementation's. `DO03` in
`Tools/CorpusRunner/devsets/routed.tsv` stays expected-to-fail until it is
made; `DO02` no longer is.

**What has been run.** The change was written in a Linux container with no
Swift toolchain, so every Swift number comes from a macOS runner. The corpus
gate is green on the change (1,404 cases, no blocking regression), and the
capture-operation classes were run on a simulator — 49 passed, 0 failed, before
review added three more tests. The whole unit suite and the release compile
check have **not** been run. See `Docs/DECISIONS.md`, 2026-09-11.

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

- A numbered enumerator in front of a **fact** was not read as a boundary, and
  that half is now closed. "Call the dentist number two the garage code is
  4821" arrived as one row, because the gate asked what came *behind* the
  number and required an instruction there — which is also what kept "gate
  number two" and "apartment number three" whole. The gate now asks what stands
  in *front* of the number instead: it declines only where a preposition or a
  copula sits within three words to the left, so "from gate number two", "under
  plant pot number two" and "my locker is number three" are still one row while
  a bare `number two` before a fact is a boundary. The copula half of that
  guard declines only where no instruction follows, so "the meeting is tomorrow
  number two call the dentist" still cuts — it did before the change, and
  review caught the first version taking that boundary away in a shape no
  corpus row had. Measured on `macos-26`
  ([run 34960158656](https://github.com/CalvinSalsali04/speak-it/actions/runs/34960158656),
  gate re-confirmed on
  [run 34976825027](https://github.com/CalvinSalsali04/speak-it/actions/runs/34976825027)):
  the everyday title-defect list no longer carries `preamble 'number two'
  kept`, and everyday clean titles moved 245/255 → 246/255. **The family around
  it did not move** — `run-on` is still 0/8 on routing and 0/8 on count — so
  this closes one narrow gap and is not evidence about the larger half above.
  One accepted cost ships with it: "Drop the parcel at the post office number
  two the garage code is 4821" is still one row, because a preposition three
  words to the left is exactly the shape of "at gate number two" and telling
  the two apart needs to know whether the phrase has closed. That is a parse
  this layer does not have; the case is pinned as a corpus row carrying that
  reason rather than left to be rediscovered.
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

## Obligation vocabulary lives in five places and they still disagree

Five separate lists state "this is an obligation". The four that claim a form
*is* one agree on five of the thirty-seven forms between them; the splitter is
a sixth kind of list and is counted separately below.

| list | file | what it gates |
|---|---|---|
| `ClauseJuxtaposition.clauseInternalLead` | `SpeechRepair.swift:1517` | whether the sentence gets cut here |
| `ActionabilityReader.obligationLead` | `Actionability.swift:137` | Today versus Memory |
| `ActionabilityReader.thirdPersonObligation` | `Actionability.swift:737` | whether the obligation is the speaker's own |
| `ObligationFrame.link` | `ThoughtOrganizer.swift:226` | what the row title reads |
| `ThoughtExtractor.isFragment` | `ThoughtExtractor.swift:1872` | whether a severed piece is glued back on |

`clauseInternalLead` is not really an obligation list — it is a "cannot end a
clause" set holding conjunctions, copulas, pronouns and motion verbs as well —
so counting it as a claimant would make every conjunction an obligation. It is
in the table because it is what severs the others.

Every *count* in this section is recomputed from the source by
`Tools/CorpusRunner/test_parser_vocabulary.py`; the ones that were here before
(four lists, 7 of 32, 22%) were hand-typed. The line numbers in the table are
not checked and will go stale again — two of the four already had.

The position at risk is mechanical: `ClauseJuxtaposition` decides a cut from
the single token standing in front of the candidate verb, so what has to be
protected is each frame's **last** word — `to` in "have to call", `better` in
"had better call", the whole word in "hafta call". Twenty-three of the
thirty-seven forms end in `to`, which `clauseInternalLead` has held since it
was written. Of the rest, four were missing from both of the first two lists —
`hafta`, `oughta`, `needa`, `better` — and were cut in half: "I hafta drop the
car off on Thursday" filed a Memory note titled **"I hafta"** beside the
errand. Those four are now closed and pinned by nine `.dictation` corpus cases.

An earlier draft of this section said multi-word frames were "protected for
free, because every one of them ends in `to`". That was two different claims
and only the second is a rule. Four multi-word frames did not end in `to`:
`had better`, `i/we better` and `'d better`, which are protected by a second
mechanism described below, and `got\s+ta`, which was protected by nothing. It
was a second spelling of `gotta` in `obligationLead` alone — in no other
vocabulary, no test, and none of the seven development sets — and it could not
have worked where it matched, because clause splitting runs first and does not
hold `ta`, so "I got ta call Dave" was severed into a Memory row titled **"I
got ta"** and an errand. Build 21 restored that router-only spelling without
its boundary protection. Build 22 removes the dead router alternative again,
preserving the documented policy: `gotta` remains supported, and bare `ta`
never enters `clauseInternalLead`. A trial exact-pair guard was rejected after
an end-to-end check still failed to route the spelling as an action; it is not
part of the shipped source.

**The structural problem is not closed.** The lists are still five lists.
`thirdPersonObligation` is the smallest on purpose and declines `gotta` and
`want to`, which is right — "Mike gotta call Sarah" is not English and "Mike
wants to call Sarah" is a preference rather than an errand the person owes — so
the disagreement is not simply one of them being short. Converging them is
still staged and still waits for its own measurement pass: three of the five
gate `count` or `route`, which are CRITICAL and BEHAVIORAL severity.

**What is closed is the half that needs no judgement.** The defect that
actually bit was positional, not a matter of which vocabulary is right: an
obligation frame whose last word `clauseInternalLead` does not hold gets cut
off from what it governs. That position is mechanical, which makes it
checkable. The suite asserts that the last word of every form any obligation
list claims is held by the splitter, with one declared exception — `better`,
which is also an ordinary comparative and so cannot live in a set that sees one
token. `SpeechRepair` reads the word *in front of* `better` instead
(`deonticBetterSubject`, `SpeechRepair.swift:1511`), at the same guard and to
the same effect, and that set is now read and checked too: it must still hold
every subject the four `better` frames carry. A form added to one list without
a decision about the others now fails on Linux, on the pull request that adds
it, rather than in somebody's Memory tab.

Graded by mutation, control green either side: the splitter losing `hafta`, a
new single-token form entering the route list, the splitter gaining the
declared exception, the title list losing an entry, `deonticBetterSubject`
losing a subject, and a reader returning an empty set instead of refusing were
all caught. Restoring `got\s+ta` to `obligationLead` is caught too, and is the
mutation that separates this check from the one it replaced: the old filter
dropped every form containing a space, so it passed that mutation. Two
size-preserving swaps — which the pinned counts cannot see — were caught by the
invariant alone, which is what establishes it is doing work the census is
not.

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
  firing. **Completing a task from the Today widget now answers the brief that
  preceded it (2026-09-21)**, so reading it on the Lock Screen and acting from
  the widget no longer counts against it. Reading it and doing nothing at all
  still counts as unanswered, and five such mornings in a row switch the brief
  off; it can be turned back on in Account & Settings. Any other way of acting
  on a brief without opening the app — there is none today — would need the
  same treatment.
- **The brief names one task only where the person allowed task names on a
  locked phone** (Account & Settings; the same switch the Today widget and the
  Live Activity read). With it off the brief is counts-only, exactly as it
  shipped. The name shown is chosen as the item least likely to reach the
  person any other way; it is not necessarily the next one chronologically.
- The named brief's content is fixed when scheduled, like the counts, so the
  same staleness applies: a brief planned for a later morning can name a task
  completed through the share extension, Siri or a Shortcut since the app was
  last opened.
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

## September 10 — information requests that still take a date

Fixed on this date: impossible calendar dates rolling into real ones, dotted and
decimal numbers read as clocks, and contracted or pronoun-subject questions
being scheduled. See `Docs/DECISIONS.md` for that work. What still ships:

- **"Let me know", "tell me" and "read out" frames take a date from their
  complement.** "Please let me know the alarm kept for Tuesday's meeting" is
  filed with a due date of Tuesday, which is when the meeting is, not when to
  be told. These cannot be closed with a guard, because the same frames carry
  real deadlines — "let me know tomorrow" is a reminder — so the fix needs the
  date attached to the request verb or to its complement. Three of the 280
  public question captures are affected. "Let me know about any alarms set
  today" additionally splits into two rows, the second titled "Set today".
- **A bare noun phrase naming a day is still scheduled.** "Time and date of
  today" has no question shape to detect and lands on Today.
- **A stated year is discarded.** Speak It's date grammar reads a month and a
  day and resolves them to the next occurrence, so "February 29, 2022" is filed
  as the next real February 29, in 2028. No date is invented — the day and month
  are the speaker's — but the year shown is not the year they said. The corpus
  comparator checks month, day, hour and minute and never the year, so it cannot
  catch a wrong-year defect either. Reading stated years is a feature, not a
  guard, and has not been designed.
- **Arithmetic read as a clock.** "Tell me the answer for two plus two" resolves
  *two* to 2 AM. Calculator queries are outside what Speak It captures, and the
  narrower fix would be an operator vocabulary.
- **A question buried in a run-on keeps a recurrence.** "I've got dollars for
  the month how much can I spend every day" reads "every day" as a series,
  because the interrogative sits in the second half of an unpunctuated run-on
  and the tests above are anchored to the start of the clause.

Six of the 280 public question captures still take a date, down from eleven.

## September 23 — V1 long-capture release block

The former fresh long-capture gate is now development/regression evidence. Its
clear 25-intention list reaches 25 separate Today rows after removing the
extraction-stage cap, and the corpus gate remains clean. This does not clear
the long-capture release gate. The development ramble now separates its
explicit actions but holds an implicit plant need in Needs Review. A coherent
reported Memory and a counted shared purpose now keep their intended grouping.
Resolved choices now attach to a unique adjacent committed action when the
speaker explicitly selects an option; unresolved or ambiguous choices retain
their own rows. The later anaphoric request to save a reported detail stays
with its adjacent Memory. The rambling plant need remains a visible ambiguity
in Needs Review and still fails whole-capture correctness.
Repaired creation words now carry ordered occurrence identities through row
shaping, including shared context and shopping expansion; any unowned
meaningful occurrence gets a visible review hold. Optional model refinement
is restricted to one unresolved row with its full raw quote. This does not yet
audit raw words removed by speech repair or all words partitioned into
operations. The zero-silent-loss release invariant therefore remains
unproven. A new unseen, independently
authored text gate and real microphone validation of the frozen production
build are still required.
See `Docs/Understanding/LONG_CAPTURE_RELEASE_GATE_2026-09-23.md` for the
family-by-family development evidence and its boundaries.

The latest complete iOS simulator unit run passed 888 tests, failed 15, and
skipped 1. Focused fixes since that run have reduced several failing families,
but the complete suite has not yet been rerun. In particular, a repeated
cancellation currently produces a visible Needs Review row when its target
is gone; the app has no durable operation receipt that would prove the prior
cancellation already handled that same intention. This is safer than silently
dropping an unmatched command but is not the final identity behavior. Other
remaining failures include person/parcel ambiguity in transport verbs and
some rendering-invariance cases on iOS. Launch readiness is not established.

The September 24 simulator rerun reached 906 passed, 7 failed, 1 skipped before
the additive-correction safety fix. Remaining failures were a repeated
cancellation's visible review receipt, two rendering-invariance tests, two
people/transport name tests, a transport people-versus-parcel test, and the
aggregate corpus family test. A newly reproduced "buy milk, actually I also
need to call Mom" loss is fixed in the rules path, with focused iOS and corpus
checks passing. Raw-source coverage across every kind of repair and operation
partition remains unproved; the current candidate is still blocked from release.

The complete three-shard simulator run after the temporal fix passed its first
and third shards, while the second shard had 294 passed, 6 failed, and 1 skipped.
The six failures were the aggregate corpus gate, two people/transport corpus
families, one direct transport-person test, and two rendering-invariance tests.
The run was before the later reported-speech and pronoun-correction fixes; their
focused iOS tests passed. The old long-capture development set still has only
18/40 captures with matching row counts and Today/Memory routes, which is not a
whole-capture score. V1 remains blocked.

A fresh rules-path probe after the correction-scope change exposed the same
ownership problem in reported coordination: “Maya said call Ben and then email
Jo” created a Memory row for the first reported action and an executable Today
row for the second. The clause splitter now reads report ownership on the full
sentence before dividing coordinated actions; this development example stays
one Memory note, while a direct action in a following sentence still creates
its own Today row. Report ownership across more complex speaker switches still
needs independent long-capture validation. No new release gate has been run.

Operation partitioning now carries transient occurrence IDs for operation
words, uniquely withdrawn local targets, and surviving creation clauses. The
production extractor now fails closed if a meaningful post-repair word has no
owner: the entire original capture remains visible in Needs Review and no
operation executes. The IDs still start after speech repair. This closes the
operation-partition gap, but does not establish zero silent raw-source loss
through speech repair. V1 remains blocked on that invariant.

The occurrence-aware raw-to-repaired diagnostic finds unaligned source words
in 134 of the 1,403 existing corpus captures on the current candidate. That
includes ordinary fillers and licensed corrections, so
it is not a defect count. The current production path does not yet record an
explicit disposition for every such raw span. The original transcript remains
durable, but durability alone does not prove that omitted meaning is presented
for review. Long-capture release remains blocked until this is proven.

The focused repair tests, corpus gate, and unsigned release build pass on this
candidate. Two full iOS unit runs on September 24 were interrupted after long
waits. The second result bundle records 442 passing tests, two failing
rendering-invariance tests, and one failing person/transport test; its corpus
test was canceled during interruption. These substantive failures were already
present in prior full-suite evidence and remain open. A clean full-suite pass
is required before a freeze.

The origin-span repair closes the known “to morrow” raw-quote omission in a
multi-intention capture. The latest diagnostic has 124 of 1,403 corpus captures
with unaligned raw words; fillers and explicit corrections remain in that set.
No production raw-source disposition audit has yet classified all 124, so this
is still a long-capture release blocker.

A separate read-only audit of the 150 multi-item corpus captures without
operations finds eight with raw words absent from all item raw quotes after
excluding conjunctions. Inspection shows filler or discourse wording in each
of those eight, including one “while I'm thinking about it” transition. This
is useful development evidence, not proof for unseen long captures: the audit
still uses word counts and has no production rule that assigns exact raw
occurrences to discourse, replacement, operation, or a visible review row.

The local correction boundary now handles a replacement action followed by an
independent action and preserves the full original correction wording on its
row. Opposite controls cover a different object and a possessive pronoun.
This closes that observed identity failure, but the production path still has
no general receipt for every withdrawn or replaced raw span. The long-capture
release decision remains blocked pending that invariant and an independent
unseen validation set.

The iOS rendering-invariance suite now passes for the established corpus after
the fronted-time and coordinated-companion boundary fixes. This removes two
known punctuation-dependent critical failures from development evidence. It
does not clear the long-capture gate: production still needs an exact raw-source
disposition audit, a clean full unit run, a frozen candidate evaluated on a
new independent unseen set, and real microphone/device validation. Short
controls and the existing corpus are regression evidence only.

Independent review found that the first raw audit could falsely certify a
deleted action if its words remained in a full-source quote, and could leave an
action active beside a review hold. The revised audit quarantines the entire
capture on unclassified raw loss and narrows repair licences to typed,
recomputed transformations. That revision is still under regression testing;
the earlier passing corpus and release build apply to the previous candidate,
not this one. The “pick up Alex and Sam” people/product ambiguity remains a
known iOS corpus failure. The fresh unseen long-capture gate has not run on a
frozen revised candidate. V1 remains blocked.

The September 25 development rerun of the exposed 40-capture set matches only
18 captures on the weaker ordered row-count/Today-Memory check. That is not a
whole-capture score. Natural rambling, shared context, reported speech,
corrections, alternatives, and end retention still show extra rows or wrong
ownership. The general mechanism under investigation is assigning a clause's
owner and temporal role before promoting it to a row and converting its dates.
The current 1,403-case corpus gate and unsigned release compile pass; the
full iOS unit suite is being rerun. V1 remains blocked, and no new independent
unseen gate has been run on a frozen candidate.

The newly locked long-capture operating target is 1–5 minutes and up to 30
independent intentions, but the live microphone path has not qualified that
range. `SpeechTranscriber` currently auto-finalizes a transcript whose last
token looks complete after about 1.9 seconds of silence. A realistic thinking
pause can therefore end a brain dump before the user is done, even if typed
semantic tests pass. The app retains recovery audio and source drafts, but
that does not make one continuous long capture usable. This endpoint tradeoff
needs device measurement and a short-capture latency control before V1 can
claim natural long-speech support.

September 27 update: the in-app voice screen now defaults to continuous capture,
so this timer is reached only after an explicit Auto finish choice. The code
path change still needs a real-device microphone and backend qualification;
the 1–5-minute operating target is not yet established. The separate
background Shortcut capture still has its own automatic endpoint policy.

The September 25 full sharded iOS unit run completed with two failures from
one bare transport/person-versus-product case (`Pick up Alex and Sam`):
`SemanticCorpusTests.testTransportedPeople` and its family gate. The other
shards passed. That run preceded the latest bounded source-owner change;
focused iOS owner/action tests, the 1,403-case corpus gate, and the unsigned
release compile pass afterward. A full integrated iOS rerun remains required.
The exposed 40-capture development set now matches 19/40 on the weak ordered
row-count/Today-Memory check, up from 18/40; this is not whole-capture
correctness or independent release evidence. Retrospective shared context,
cross-intention deadlines, and Memory elaboration after intervening actions
still create resolved extra rows or wrong ownership. V1 remains blocked.

A bounded return link now retains a uniquely owned later Memory detail across
an intervening task. This improves the atlas and Porto development examples,
but neither is fully whole-capture correct: the atlas's background remains a
separate resolved Memory, and the Porto negative capture directive remains a
separate row rather than being absorbed into the original Memory. The link
also uses a display ellipsis for disjoint
source fragments; `CaptureSession.originalTranscription` is still the exact
full source. Shared context and temporal group ownership remain unresolved.
No fresh independent qualification set has been scored on this candidate.

Before the counted-deadline edge, the exposed 40-capture development set was
19/40 on the **weak** ordered
row-count and Today/Memory check after the September 26 ownership changes.
That check omits meaning, dates, correction targets, and safety, so it cannot
support a release claim. Natural rambling and beginning/middle/end retention
still have zero weak matches in their four exposed cases each. The next work
must resolve typed group context and temporal ownership rather than tune
another phrase in that set.

After the typed counted-deadline edge, that same weak development check is
20/40: shared context rises from 1/4 to 2/4 because the grant application
steps now receive their common date without losing the independent PDF fact.
This is still below the release threshold and still omits full meaning and
safety scoring. The school-fair event group, allergy explanation, natural
rambling, and beginning/middle/end ownership remain unresolved.

The September 26 full sharded unit run did not yield a valid suite verdict:
one shard exposed a repeated-fact merge regression, and another `xcodebuild`
process crashed while importing simulator diagnostics. The repeated-fact
failure has since been fixed and its isolated iOS test passes; the complete
consolidation suite also passes. A clean full run on the final code remains
required. The previously observed bare pickup people/product corpus ambiguity
also remains unresolved and cannot be counted as a pass.

A serial full-suite retry on September 26 also failed to produce a verdict:
after roughly fourteen minutes, Xcode reported a crashed test worker and
remained blocked while trying to restart it. The process was interrupted;
its incomplete `.xcresult` could not be read. This is an infrastructure
failure, not evidence that all iOS tests pass. Focused iOS owner tests, the
isolated repeated-fact regression, the 1,403-case host corpus, and the
unsigned release compile did complete on the current code.

The typed group-context changes raise the exposed 40-capture development set
to 22/40 on the **weak** ordered row-count and Today/Memory check. This is
not whole-capture correctness and is not independent qualification. The
school-fair event and allergy explanation now attach their source to distinct
owners; an opposite reported-speech control stays separate. The counted
deadline, event, and explanation edges passed focused iOS tests and the
1,403-case host corpus; the unsigned Release build also compiles on the
combined correction and context changes. Natural rambling, corrections,
reported speech, resolved alternatives, and beginning/middle/end retention
still have substantial whole-capture failures. V1 remains blocked.

The fronted-time completed-action correction works when the report ends at
"already called". A coordinated follow-up clause can identify another
person, so the exposed longer plumber capture stays in visible review until
that report's object can be assigned safely. It is still incorrect as a whole
capture. Focused iOS correction tests pass after the conservative guard;
the full iOS
suite, fresh independent long-capture qualification, and physical-device
microphone validation remain unverified.

The September 26 combined-candidate three-shard iOS run is also incomplete.
Shards 0 and 2 ended without assertion lines; the available shard-0 result
bundle reports 321 passed, zero failed, zero skipped. Shard 1, which includes
the semantic corpus, had no test-worker process or log output after nearly
nine minutes and was stopped. An isolated `SemanticCorpusTests` retry on the
same simulator entered Xcode's test-session cleanup stall and emitted
`DVTAssertions` warnings when interrupted. These are not passing suite
results. The bare `Pick up Alex and Sam` iOS ambiguity remains a known
behavioral failure; full simulator regression evidence is still required.

Quoted-source ownership now prevents a later request to retain scene words
from attaching to the intervening task. A directly cited quote can serve as
evidence for one later retained staging note, with quoted imperatives excluded
from speaker-directive checks. The exposed rehearsal capture has two rows in
the production-rule probe, and opposite controls pass in focused iOS tests.
The exposed 40-capture development diagnostic is now 23/40 on the weak ordered
row-count/Today-Memory check. Reported interview and family-saying captures
still produce extra Memory rows; no fresh qualification set has been scored.
V1 remains blocked.

The quote-content attribution and coordinated retention changes bring the
exposed development diagnostic to 24/40 on the same weak ordered row-count
and Today/Memory measure. U26 and U27 now have their expected two-row shape;
U25 still has a separate reported-context Memory. The focused iOS
consolidation suite passes on these changes. Whole-capture correctness,
the full iOS suite, fresh independent text qualification, and live microphone
validation remain open; V1 remains blocked.

Selective ownership of an explicitly disclaimed reported command and the
propositional “what I also want to keep is that …” routing rule bring the
exposed development diagnostic to 25/40 on ordered row count and
Today/Memory destination alone. U25 now has one Memory with its quoted source
and one Monday email task. Opposite reporter, additive-memory, explicit-quote,
and physical-keep controls pass focused iOS tests; the 1,403-case corpus gate
and unsigned release compile pass. This does not establish whole-capture
correctness. Natural rambling is still 0/4 and beginning/middle/end retention
is still 0/4 even on the weak diagnostic. Corrections and alternatives also
remain poor. The full iOS suite, new independent long-capture set, and live
microphone/device qualification remain open; V1 remains blocked.

The uncertain-completion guard now scopes review to the ambiguous reported
prefix when a later sentence has an explicit independent intention. In the
exposed plumber capture, photographing the leak and clearing the cabinet are
accessible Today rows; the call/visit correction remains a separate Needs
Review row and creates no completion operation. This is safe incomplete, not a
whole-capture fix. A dependent pronoun in the later sentence also stays in
review. The remaining correction-identity and capture-commentary failures
still block V1.

An early section-frame rule now routes the content of explicit spoken labels
and self-narration before row creation. The opposite quoted-command control
remains visible in Needs Review; a direct command after the same label stays
actionable. This does not solve the larger natural-rambling and
beginning/middle/end ownership failures: scene-setting narration, rejected
possibilities, local withdrawal versus saved-item operations, and deictic
recaps can still produce wrong rows or owners. The September long-capture set
is development evidence only. A frozen candidate, full iOS suite, independent
fresh text qualification, and physical microphone validation are still
required before release.

Indefinite negated actions now remain in the capture instead of becoming
saved-item cancellations. The exposed park-path ramble no longer yields a
cancel operation, while a direct “don't call Maya” still does. That ramble
continues to misroute recording commentary as Today and does not meet the
whole-capture gate. This is a safety improvement, not release qualification.

The pre-row capture-commentary role now attaches a uniquely referenced recap
to its source owner or leaves an ambiguous reference in visible Needs Review.
The exposed park-path capture no longer creates a Today row from “I am
repeating it,” and its outing denial creates no cancel operation. The exposed
cinema capture retains the final-step recap on the charger task. A conditional
about possibly finding the paper statement no longer turns that fact into a
task. These are scoped regression improvements only: both long families still
have unrelated incorrect rows, and no fresh whole-capture qualification has
been run. V1 remains blocked.

The conditional factual-matrix correction now applies across ordinary and
framed captures through the shared actionability reader. It preserves the
opposite committed-action controls, but does not yet resolve all compound
conditional or reported speech ownership in long captures. The existing
long-capture release blockers and fresh qualification requirements remain.

Trailing task conditions now remain on a usable Today row when no event
notification was requested; a request to notify on that event and a fronted
condition whose concise title omits it remain in Needs Review. Bare “this
week” and “next week” tasks now retain a visible calendar span without a due
instant or alert. This improves the exposed clear-list development cases but
does not qualify them as whole-capture correct: event-relative timing, other
ownership errors, independent unseen text scoring, the full iOS suite, and
physical microphone validation are still outstanding. V1 remains blocked.

The clause-boundary reader now keeps ordinal modifiers inside an unfinished
noun phrase and separates coordinated direct actions even when the lexical
tagger mislabels an action verb. The exposed plumber footer is one source unit,
and the exposed train preparation is two actions. An explicit obsolete/current
time-fact replacement keeps the old train time only as source evidence on the
current ticket Memory, and later correction instructions attach to that
Memory. The train departure now owns visible source context on the separate
“leave for the station” action without inventing a leave-time alarm. The
uncertain completed-call report remains a visible review hold. Both captures
still require whole-capture evaluation, and independent unseen validation
remains a release blocker.

The iOS simulator did not provide personal-name tags for ordinary bare pickup
objects. An offline Census first-name corroboration now covers common names
inside transport frames and keeps a shared pickup as one Today task. It is not
comprehensive for unfamiliar names or name/product homonyms. Opposite product
and short-trip controls pass in the focused simulator test; the full iOS suite
and fresh long-capture qualification remain required. V1 remains blocked.

A reported or third-party choice no longer suppresses its own Memory row
merely because a later user action repeats the selected noun. An explicitly
resolved first-person choice now binds its proposal and selection to one
uniquely matched action before row creation, and an action spoken inside an
owned decision clause is retained as an action. Its complete raw source quote
remains visible. Explicit nonselection now stays out of Today, and options
paired by “between” stay in one deliberation span. Alternative commentary
that explicitly names a rejected or considered option now attaches to one
lexically identified selected action; without a unique owner it remains in
Needs Review. A dated trip goal now scopes clock-only actions explicitly at
its destination when the context is contiguous, while unrelated actions keep
their own dates. Other recap and output commentary still require general role
and identity work; the exposed
long-capture alternatives family is not whole-capture correct. V1 remains
blocked.

Explicit reference-only clarification can now attach to one uniquely named
Memory without creating an alarm or an extra review row. Ambiguous possessive
references across two plausible place antecedents still keep their factual
source in separate Memory rows; they are not yet one proven retrieval identity.
Natural rambling can still produce extra resolved narration rows or split one
coherent idea. These are whole-capture correctness failures even when every
word remains in the capture and no unsafe action executes. V1 remains blocked.

Explicit Long capture retains protected audio and requires verified whole-file
recovery after a recognizer stops early, including retry from Today and launch
recovery. Its current 45-second recovery pieces require an unambiguous spoken
overlap to join. A natural pause spanning a five-second overlap can therefore
leave an intact recording in visible failed-draft review even when both pieces
transcribed correctly. This is safe but may exceed the locked unnecessary-review
limit; measure it on real 1–5 minute iPhone recordings before release. The
simulator and rules corpus cannot establish microphone completeness or seam
usability. V1 remains blocked.

The latest exposed development-only whole-capture review is 32 correct,
1 safe incomplete, and 7 incorrect out of 40; natural rambling remains
0/4 correct. Narration, tentative plans, and elaboration can still create
extra or fragmented Memory rows even when the original transcript is safe.
The first independently authored 240-case candidate was rejected in an
editorial audit because its repeated templates and inconsistent expected
answers would overstate qualification. Neither that set nor the exposed 40
is V1 release evidence. A varied sealed set and live iPhone qualification
remain required; V1 remains blocked.

The separately authored and independently audited 240-case fresh long-capture
qualification on September 27 failed decisively: 3 whole captures correct,
2 safe incomplete, and 235 unsafe or silently incomplete. Clear long
multi-task, natural rambling, coherent long Memory, corrections, withdrawals,
quote/report, multiple dates/people, and 10–30 intention capacity each scored
0/20 correct. One clear 30-job list produced only four unreviewed rows; quoted
commands became Today actions in several captures. The original transcript
survived, but missing or misrouted intentions were not reliably visible for
review. See `Understanding/LONG_CAPTURE_FRESH_QUALIFICATION_2026-09-27.md`.
That set is now development/regression evidence because source changes began
after its failure. A different unseen set and authorized live microphone
qualification are required for a new release decision. V1 remains blocked.

The post-gate development candidate now gives independently numbered action
slots visible identities and carries an explicit task-list commitment through
platform-dependent verb tagging. Saved-row revisions have a typed identity but
remain one visible Needs Review capture; they do not yet update the existing
row in place. Unnumbered long speech, temporal and quote ownership, and mixed
corrections still fail the whole-capture bar. These development regressions
cannot replace a different unseen qualification set. V1 remains blocked.

## September 28 current development status

The preceding post-gate note describes an earlier candidate. The saved
dentist date amendment now updates the identified existing item and has
repository identity, provenance and duplicate-capture coverage. An ambiguous
saved cancellation now preserves both targets until the user chooses; the
choice and surviving independent shopping task passed a simulator UI test.
These are development checks with notification delivery disabled, not a
physical-device delivery claim.

Long speech still fails the product contract. On a frozen pre-S001/S010
revision, all 1,770 exposed development inputs executed in ten bounded
repository batches, but a conservative scorer found 453 missing explicit
clocks and 19 absent required saved mutations among 1,756 nonalias cases.
That scorer does not measure wrong grouping, invented rows, conditional
meaning, unnecessary review or whole-capture correctness. Later bounded
repairs recovered the 19:00 photo reminder and independent shopping in one
S001 rendering and the 08:00 parsley reminder in three S010 renderings.
The lightly punctuated versions of both remain incomplete, and the pilot
still contains many false extra rows from explanatory speech. The S001/S010
source was rerun across all 1,770 inputs: the conservative missing-clock
count fell to 381, absent required saved mutations stayed at 19, and no new
hard-failure ID appeared. This is still a failure lower bound, not a
whole-capture pass rate. The S049 30-row Today capture passed a simulator
first/middle/final-item management test. The September 27
240-case fresh qualification failed and is now exposed development data;
there is no passing independent replacement.

The normal in-app recording path is Continuous with explicit Finish in code,
but no physical microphone continuity, long-duration fidelity, interruption
handling, or real notification delivery has been observed on this candidate.
The 120 supplied recording cases are specifications; 88 require physical
microphone execution and 32 specify fault or recovery injection. V1 remains
blocked on semantic failures and unexecuted qualification.

A September 28 bounded saved-cancellation repair now applies the named
community-key cancellation in all six S063 request renderings while preserving
the library distractor and new capture source. The single-target path now
saves a performed V5 receipt with the deletion and retains the saved target's
original source session; a file-backed store reopen and retry test passed.
The positive-action opposite control still keeps `also buy eggs` separate.
The bounded S064 saved box-quantity and S065 notification-only amendments
pass their six exposed request renderings, opposite controls and file-backed
repeat/relaunch tests. On the S065 source the full 1,770 exposed inputs ran,
with 381 missing required explicit clocks and one missing saved mutation among
1,756 nonalias cases under the deterministic lower-bound checker. That one
mutation was S062 with punctuation loss. S065's exact target notification
removal passed with a simulated delivery sink; real iPhone delivery remains
unverified.
The S062 completion now passes all six exposed request renderings without an
invented extra row, plus the opposite control and file-backed retry. The
separately confirmed broad-cancel path now saves all deletions with a receipt
in one transaction and preserves each original CaptureSession; stale target
and reopen/retry tests passed. Broad completion is still a legacy path without
that atomicity evidence. The S062-plus-broad full unit check passed 1,108
tests with zero failures and three skips; unsigned Release compiled. Its
complete 1,770-case exposed run retained every original and reduced absent
required saved mutations from one to zero among 1,756 nonalias cases. It
still missed 381 required explicit clocks under the lower-bound checker.
The exact 25-case pilot was rerun on this receipt and boundary source with
zero canonical persisted-output changes from the earlier S063 candidate.
It still has 17 wrong persisted whole-capture interpretations on the current
pilot rerun. A later bounded S011 clock repair recovered the 15:00 wheel
collection reminder in four of its five main renderings and six related
compositions without changing any of the 25 pilot outputs. S011's lightly
punctuated rendering and explanatory-speech ownership still fail; its two
correct clocks do not make the whole capture correct. The S011 source has not
had a complete 1,770-case or independent qualification rerun. Release remains
blocked.

### 2026-09-29 — Paired reminder ownership and qualification remain open

The S011 punctuation-loss capture still loses its second 15:00 clock on the
accepted source and the punctuated variants still create separate explanatory
rows. A paired-annotation challenger fixed the isolated punctuation-loss
case but regressed C026/C041 composition dates and invented rows; it was
rejected, with traces and diff preserved in the Understanding handoff. The
new whole-capture S011 regression test is intentionally red. S001's exact
pilot now persists three audited intentions and preserves its original after
bounded source-role repair, but its photo title does not surface the new-photo
qualifier without opening the source. It is provisionally tested, not release
qualified. The current source passed the 1,403-case corpus gate; final-source
full unit, UI, Release, 1,770-case, independent 240-case and physical
microphone gates are still outstanding. A stopped 650-case intermediate trace
does not count as a completed 1,770-case run.

### 2026-09-29 — Clarification scope is only partially repaired

S069 now saves the form and folder without extra instruction rows in the
punctuated pilot and keeps the unresolved hour unarmed; S079 saves one bins
task with its place intent. Across the affected 14 renderings and controls,
S069 lowercase and punctuation-loss still merge or misclassify the folder,
and spoken fillers invent shopping rows. A subsequent bounded boundary fixed
S079 punctuation-loss so the bins reminder remains actionable. S079 opposite
still adds an unnecessary review row. These are unresolved product failures, not successful
clarification. The current source has only focused and short-corpus checks;
the mandatory final full validation and physical microphone checks have not
been executed on it. Actual Home/permission monitoring remains unverified.
Exact traces and hashes are in the Understanding handoff.

### 2026-09-29 — Elapsed recurrence explanations remain incomplete in some renderings

The S072 punctuated pilot now saves one 24-hour duration recurrence and no
extra calendar recurrence. Four main renderings and the concise form keep the
correct first instant through the Toronto clock change. The spoken-filler
rendering still invents shopping and note rows.
Synthetic repository traces do not prove notification delivery or long-term
recurrence scheduling. This source remains below the locked release gate.

## Isolated candidate: keyboard frame diagnostic (2026-10-04)

The October 2 readiness failure remains preserved. A later normal, bounded
LLDB diagnostic reproduced two warnings in `SwiftUI.InputAccessoryBar.body`
and keyboard accessory sizing during typed capture. The isolated candidate
removes CaptureView's redundant keyboard toolbar and keeps its existing
44-point inline Done action. On the same simulator/runtime, the repeated
native typed-capture journey passed with no warning and no hits at the
installed warning breakpoint. This closes the bounded simulator reproduction;
physical keyboard/runtime behavior is still unverified. The original evidence
and readiness requirements remain in
[the readiness record](PRODUCT_READINESS_2026-10-01.md).

## Runtime worked-example candidate remains unqualified (2026-10-04)

The isolated candidate enables `SPEAKIT_RUNTIME_CANDIDATE` in both Debug and
Release and bundles exactly 59 independently input-first reviewed records
(352,256-byte index). These are AI reviews, not human approval or proof that
all generated references are correct. The complete 510,000-row source library
and 1,371,029,504-byte full index remain available outside the app bundle.
Storage selection is measured on this Mac; supported-phone memory, latency,
battery and thermal qualification remain open. Real-data Release use remains
disabled outside this candidate.

Current source and actual saved snapshots govern every fact and effect. The
local source interpreter is available on iOS 17+, while generative Foundation
Models requires the available iOS 26.4 API/model/locale. Equivalent complex
interpretation across supported devices is unproven. Missing assets, model
unavailability and validation failures retain the capture for visible review;
this is safe incompleteness, not complete-capture success. A source-only
certificate validates bounded discourse and identity lineage independently
of parser confidence; it is reported separately from example benefit.

A real approved-example quantity repair has passed through the actual
repository, idempotent retry and file-backed relaunch, with three current
allocations and no copied reference facts. Source-bound withdrawal and complete
atomic saved-revision paths have focused native coverage. The formerly invalid
saved-state developer exporter is corrected and retains pending revision,
complete timing and independent-source metadata. Host proposals do not prove
database or reminder effects. Native saved-target tests remain the authority
for identity/version, untouched fields and retry; the dark largest-text UI
journey additionally checks target traversal, stale exclusion, chosen fields,
source and separate persisted deadline/alert receipt values.

The retained 12-capture diagnostic was OFF 4 correct / 8 safe incomplete /
0 unsafe and ON 6 / 6 / 0. Its two incremental gains came from approved quantity
and quoted-refusal operators. The same Source11 candidate's broader 48-capture
comparison is independently graded: OFF 17 correct / 31 safe incomplete /
0 unsafe, ON 19 / 29 / 0, with 30/28 unnecessary-review outcomes. Selected
references, actual model projections and the two compiled uses are accounted
separately; source-only gains are not retrieval benefit. This is exposed
host development evidence and falls below the locked release criteria.

Unpromoted first-outline-example and staged-anchor challengers have not
qualified the feature. The latter accepted a task whose November 18 date
remained in the title but disappeared from dueDate and TemporalIntent. The
exact host failure, contrasting simulator behavior and subsequent nested
recipient repair are preserved; passing focused tests does not erase that
failure or establish a new runtime result. No fresh release set has been
commissioned. Existing difficult 240-case failures remain separate development
evidence, not qualified by an easy bank denominator.

Remaining family-role, coupled meaning, condition/list and complete-capture
failures, unnecessary review, StoreKit setup failures and required final
integration, account and physical checks still block release. No global family
graph, guessed contact or missing location, automatic communication, schema
reset, cloud processing or paid inference is introduced. The consolidated
readiness and hardware requirements remain in
[the product readiness record](PRODUCT_READINESS_2026-10-01.md).


Isolated runtime candidate limitation (unshipped Source101): an explicit later instruction to combine previously independent Memory intentions has no complete source-bound reconciliation proof yet. Preserve the complete capture for review; do not automatically merge from vague pronouns, quoted or conditional instructions. This remains release work, with a diagnostic asserting visible retained source rather than automatic completion.

### Isolated next nominal draft: pending qualification

The draft present-owned plural task reader and quote-return segmentation have not been compiled or tested. Predicate coordination, conditional/report scope, unavailable lexical assets, exact source ownership and saved-operation boundaries require the new regression matrix plus existing checks before promotion. Multi-action completion is deliberately unsupported: a plural status is retained for review rather than closing one or several tasks. The new grammar is bounded; arbitrary modifiers, relative clauses, past/modal copulas and unknown continuations do not receive declaration authority. No release-readiness or accuracy improvement is claimed from source inspection.


The frozen v20 focused run failed six checks, including an existing long paired-reminder regression. Those results remain failed evidence. A separate repaired draft addresses the reproduced ownership, reminder-wrapper, clock-context and recipient-boundary causes; it has not yet passed native or complete-engine qualification. Row quote spans may omit an outside terminal sentence delimiter under the established word-provenance contract; the immutable CaptureSession retains the exact original transcript, and the new tests check it explicitly. The compact and semantic routing defaults remain OFF.

- October 12 retention follow-up: v22 focused checks had four failures (454 pass/3 skip). A late discourse-filing merge was found after correct retention/action segmentation; the next draft adds the shared positive retention guard and corrects two tracking-contract tests. These changes have no new qualification yet. Failed runs are preserved; compact and semantic retrieval remain disabled by default.


2026-10-12 final normal-default capture qualification: frozen23 focused run completed with 458 passed, 1 failed, and 3 skipped (462 total). The sole failure was a newly added repository test expecting its retained originalTextSegment to lose the original terminal period. The repository correctly preserved the entire prefix including that period, consistent with the adjacent immutable-transcript tests. Frozen24 changes only that exact expected value to prefix; all persistence, revision, provenance, separate saved-call, and routing assertions remain intact. Application source is byte-identical to frozen23. Full native suite, Release compile, native harness build and large normal-default model comparison remain pending. Compact and semantic routing defaults remain off.


2026-10-12 check evidence before the saved-field safety repair: frozen23 corpus replay exited0 with 1,434 cases, 1,428 clean, zero blocking and six cosmetic title differences. The earlier v13 run reported four cosmetic differences. The six current differences include titles retaining a fronted condition/adjunct with an explicit comma rather than silently flattening it; this observation does not independently identify the exact change set from v13. Frozen24 unsigned Release and host compilation passed; full native suite was still running when the additional field-tail and quoted-antecedent problems were reproduced. These receipts do not qualify the next changed application source. Normal full-bank lookup receives no compact/hybrid speed promotion; the new candidate will measure its own complete-engine text latency, with real iPhone voice-to-result latency still requiring device QA.


2026-10-12 frozen24 full-suite result: 2,038 passed, eight failed, 35 skipped and one expected failure (2,082 total). Five failures are the separately tracked inherited StoreKit `notEntitled` setup limitation. Three new failing tests exposed two mechanisms: one exact-source expectation omitted a preserved terminal period, and two unchanged saved/reopen diagnostic tests crashed in the same recipient-repair range helper on the same original transcript. The expectation now includes the original period. The repair licence now requires the entire correction cue to fit its selected sentence before constructing the suffix range. Cross-sentence cues decline this narrow licence; original transcript and broader correction handling remain intact. Two additional regression methods cover the exact crash and 24 sentence-boundary/stacked-marker/whitespace controls. These changes and the saved-field scope/antecedent repair require their own native qualification; prior passes do not qualify frozen25.
