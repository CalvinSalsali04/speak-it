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

## A company said on its own is typed by Apple's name tagger or not at all

"Call <brand>" — an address verb, a capitalized word, no head noun the scan
will read and no complement after it — has exactly one piece of evidence
available, and it is `NLTagger`'s name type. Three shapes are in the family,
not one: a bare name with nothing beside it; a name reached through a particle
("get back to <brand>"), which the motion rule does not touch; and, since the
head scan began stopping at a possessive, `<brand>'s <head noun>` ("Costco's
return policy", "TD Bank's branch closes at four"), where the head noun is
right there and is no longer read. That last one is the price of not taking a
person off the row in "Return Sam's library book", and it is the right trade,
but it belongs in this family rather than out of it. That vocabulary is closed, misses most brands,
and is **absent entirely on a hosted runner**, where it returns `otherWord`
for every token. Where it says nothing, the word is filed as a person: it goes
on the row under People, it is offered to the message composer, and it widens
what a later cancellation can match (`CaptureTargetMatcher` reads
`personName`).

The 2026-09-22 work narrowed this family rather than closing it. A motion
frame no longer produces a person, the same evidence is now read wherever a
name can arrive, the tagger is no longer asked a leading question, and a
relationship with an institution ("about my overdraft") types its target. None
of those reaches a bare brand said with nothing around it, and **none of them
should be extended to**: a list of company names is the failure this file
already records for occupations — the miss is not a blank field but a
confident wrong answer, and the thirty-first company is always missing.

What would close it is contextual entity evidence from a model, constrained to
a source span and a type, able only to **withhold** a person and never to
create one. That is unbuilt and open with Calvin, and it carries a specific
warning from this project's own probe record: a constrained role enum has
failed here twice. `temporalRole` and `locationRole` were both produced and
both useless, and `confidencePercent` reported 100 on every fabrication, so
the model's own confidence cannot gate it. Entity type is more in-domain than
either — it is standard NER and a property of the world rather than of Speak
It's routing — but the failure mode to expect is the same one, and Speak It
has to stay useful with the model unavailable.

**Not pinned by a test.** A case asserting the defect would either freeze it
(so the eventual fix reads as a regression) or leave the suite red, and
`XCTExpectFailure`/`withKnownIssue` appear nowhere in `SpeakItTests`. The
cheapest retest is one command on a Mac:

```
./Tools/CI/unit-tests.sh SpeakItTests/PersonMentionTests
```

`testTheTaggerFrameIsNotALeadingQuestion` prints what the tagger actually
knows about six companies, under both the old person-only frames and the
neutral ones. It asserts nothing about them, so the test passing says nothing:
the measurement is in the log, one line per company, and it is read with
`grep entity-frame-comparison` over the run output or the `.xcresult`. If the
two readings are identical the frame was never what decided those words, and
only a model can type them.

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

**2026-09-23: the app now notices, and what it still does not handle.**
`LinguisticHealth` runs the one-sentence check described above. On a blind
verdict, `DegradedLanguagePolicy` sends every row of the capture to Needs
review, labelled "Not fully read", and removes any time, series or place that
the row's own words did not state. The reasoning is in `DECISIONS.md`
(2026-09-23). What remains:

- **The rules are unchanged.** U1 to U6 still happen on a blind tagger. A
  row can still be typed as shopping when it is an errand, or as a task when
  it is a fact, or be attached to the wrong person. The only difference is
  that the row now waits in review instead of being presented as settled, and
  that a trigger it borrowed no longer fires. The type and grouping that
  review shows the person are the blind reading's.
- **Whether a real iPhone can go blind is still open.** Only the hosted
  runner's simulator has been observed blind. The probe has never been run
  on a device that lost the model, and neither has the re-probe (a blind
  verdict is checked again on every capture) that covers a model arriving
  mid-process. `--force-linguistic-degradation` on a Debug launch shows the
  degraded rows on a healthy device. The notification half of this change
  (no alert for a fact that inherited a trigger, while an explicit own
  reminder still fires) needs that check on a device.
- **Sharing a trigger costs the row that relied on it.** On a blind tagger,
  "call Mum" in "Remind me tomorrow at 9 to buy milk and call Mum" loses the
  9 o'clock it legitimately shared, and waits in review for a time. That is
  the price of never lending a trigger to a fact. A reworded quote (after a
  repair) keeps only what its own quote states, for the same reason.
- **Paths outside the two engines are not held.** Splitting or merging by
  hand re-reads the parts through `ThoughtOrganizer.organize` without the
  policy, which is the person acting on their own words. The launch pass
  `resolveCombinedPlaceAndTimeHoldouts` re-derives a reminder from a row's
  own `originalTextSegment`. Neither can borrow a prefix, but both read
  blind.
- **Nothing tells the person why, beyond the row.** There is no global
  notice, no Settings or diagnostics row, and nothing in analytics. The
  refinement model's outcome is still collapsed into one `nil`. Those are
  the audit's §3.4 and §3.5 and the product decision above.
- **A held operation reads as a question, not as "Not fully read".** On a
  blind tagger every cancel, complete, reschedule and withdrawal is held. The
  review row is the operation's own words (or the capture's placeholder),
  without the new gap, and the receipt says "Which one?" with every active
  item counted, because that is the existing held-operation path. A held
  withdrawal leaves a review row, so it now spends a free capture where a
  withdrawal on a healthy device does not. An operation resolved inside the
  capture (a scoped withdrawal, a sibling cancellation) is undone by reading
  the transcript again without operations, so its clauses come back as held
  rows the person has to clear by hand.
- **A capture read before the first probe can still pass as healthy.** The
  first usable verdict now empties `SentenceContextCache`, so no later capture
  reuses a reading taken before the model answered. The capture whose rules
  ran before that first probe (a Back Tap or App Intent cold launch, before
  prewarm) has already been read, and it is not re-read.
- **Test harnesses never apply it by default.** The unit-test host and any
  `--ui-testing` launch read the tagger as usable (`LinguisticHealth.hostDefault`),
  so the existing suites still measure the rules as before on a blind
  simulator. Only tests that bind `LinguisticHealth.$override` see the
  policy.

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

## Removing an item: what stops at once and what still waits

*2026-09-23, DEL-22.* Every path that removes an item now calls
`ReminderScheduler.cancel(itemID:)` for each removed id right after the save,
and relaunch cancels any AlarmKit alarm no row asks for. See `DECISIONS.md` of
the same date. Three things are left, and none is verified on a device.

- **A notification built from a capture still waits for the queued pass.**
  `cancel(itemID:)` removes `SpeakIt.reminder.<item id>` and the item's alarm.
  But a request made from a stored item carries its session, and
  `notificationGroups` files it under `SpeakIt.session.<session id>.<session
  id>-<fire time>`, shared with any sibling due at the same second. That
  identifier is not removed synchronously, because removing it would silence
  the siblings until the queued pass re-adds them. So a deleted item's
  *notification*, unlike its alarm, can still arrive if the app is killed
  before the queued pass runs and not reopened before the fire time. Relaunch
  and foreground reconciliation (`replacesAllSpeakItReminders`) remove it on
  the next open. The seeded identifiers in `CaptureOperationTests` and
  `DurabilityTests` are the per-item form, so no test covers the grouped one.
- **The kill window before the synchronous cancel.** A kill after `delete`'s
  save and before its cancel leaves the alarm armed until the next launch or
  foreground, where #127's orphan sweep cancels it. Without #127 it would ring.
- **The recorder sees teardown only.** Arming goes to `AlarmManager` and
  `UNUserNotificationCenter` directly, not through `ReminderDeliverySink`, so a
  test cannot see a pass re-arm something. The post-drain assertions show the
  item stays disarmed and nothing else was torn down, not that nothing was
  armed.

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

## Some recurring alarms still ring once per app run

*2026-09-23, DEL-13; see `DECISIONS.md`.* On iOS 26 a recurring item delivered
as an AlarmKit alarm repeats by itself only when AlarmKit's relative schedule
can express its rule: daily, or weekly on named days ("every weekday at 6:30",
"every Monday", "every week"). Every other rule is still armed as a one-shot
`.fixed` alarm, rings once, and gets its next occurrence only when Speak It is
opened again and the foreground pass re-arms it. **If the person is woken by
it and does not open the app, the next occurrence does not ring.** The rules
this applies to:

- an `interval` above 1: "every other Tuesday", "every 2 days", "every 3 weeks";
- monthly and yearly rules, including ordinal weekdays ("the first Monday
  every month");
- elapsed-time rules ("every 3 hours");
- completion-anchored rules, whose next date does not exist until the
  occurrence is completed.

AlarmKit's `Alarm.Schedule.Relative.Recurrence` has only `.never` and
`.weekly([Locale.Weekday])`, so none of these has a repeating form to move to;
the alternative is arming several future occurrences as separate alarms, which
needs alarm IDs that are not the item ID and is not built.

Even an expressible series starts as a one-shot in three cases, and repeats
from its next re-arm: its first occurrence is later than the next weekday match
(created today for next week, or completed before it rang, which moves the
next occurrence past the match that is still to come today); it rings a
minute from now or sooner, where a relative alarm that missed its moment while
registering would ring at the next match rather than not at all; and the
repeating hour and minute are read from the occurrence's fire date, so an
occurrence daylight saving moved out of a skipped hour ("every day at 2:30 AM"
on the spring-forward night) repeats at the moved time until the next
foreground re-arms it at 2:30. The same reading truncates seconds: a fire date
with seconds becomes a weekly match at its minute, so that series rings up to
59 seconds early on every occurrence, not once. A relative alarm also follows the device's time
zone, so travelling moves it with the clock, which is the documented default
for recurring reminders below.

The row does not travel with it. `reminderDate` is an absolute instant that
nothing re-reads in the new zone until the app runs, while the relative alarm
needs no app run, so after a flight from Toronto to London "every weekday at
6:30" rings at 6:30 London time, five hours before the 11:30 the row still
claims. The app running does not settle it at once: the foreground pass re-arms
the alarm from the row, so it repeats at 11:30 until that occurrence passes and
the series advances, and a series that names any weekday then advances at
11:30 rather than 6:30, because the weekly branch of `RecurrenceRule.nextDate`
reads the clock of the previous occurrence and ignores the stated one. That is
a recurrence bug that predates repeating alarms and moves notifications too
(DEL-21, fixed separately in #137). The same series can also answer differently from one occurrence to the
next: an occurrence that fell back to a `.fixed` alarm does not travel, and the
repeating notification path pins `components.timeZone = TimeZone.current`, so a
repeating notification for the same rule does not travel either. No behaviour
change is planned here; an alarm following the device's zone is what an alarm
clock does.

Not verified on an iPhone: that a relative weekly alarm rings twice without the
app being opened in between, that stopping it leaves it `.scheduled` for the
next occurrence (so the orphan sweep keeps protecting it), that
`cancel(id:)` removes the whole series, and that `.weekly` with all seven
`Locale.Weekday` values behaves as a daily alarm, which is how a daily series
is armed and which Apple's documentation neither promises nor rules out. A
snoozed occurrence of a repeating alarm (PR #129) is not reconciled with the
series yet; see the follow-up in `DECISIONS.md`.

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

## A snooze keeps its series armed, except for alarms

Since 2026-09-23 a snooze moves one occurrence and leaves the series at its
own time. A snoozed notification occurrence arms both the one-shot at the
snooze and the series' own repeating trigger. A series whose alert has
fired, snoozed or not, keeps its repeating trigger through every scheduling
pass (DEL-12, closed the same day; see `DECISIONS.md`). What that does not
cover:

- **Alarms.** AlarmKit delivery is a `.fixed` one-shot for every occurrence.
  A recurring alarm, snoozed or not, rings once and then waits for the app to
  run and roll the row forward. The DEL-12 fix does not reach alarms either.
  Speak It's alarm alert has no snooze, so this gap is not caused by
  snoozing. It is the existing state of recurring alarms. Closing it means
  scheduling AlarmKit's own repeating schedule.
- **Only daily and single-weekday series repeat natively.** Every weekday,
  every other week, the first Monday of the month, and elapsed-time series
  have no repeating trigger to keep armed. They still depend on the app
  running to generate the next occurrence, as they did before.
- **Series snoozed before this build are not repaired.** That drift was
  written into `reminderDate` with no record of what it replaced. The person
  has to fix the time once in the editor.

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
- **The Today widget can lag a permission change until Speak It runs.** The
  widget snapshot now holds a place reminder in review exactly when Today does
  (2026-09-23), but it is rebuilt only by the app: on a save, on foreground,
  and on an authorization change while the app is running. Revoke location
  access in Settings and look at the widget before opening Speak It, and it
  can still count the reminder and show its complete button, because the file
  was written under the old access. "Complete my next item" is not affected:
  it rebuilds the snapshot against the live authorization before choosing.
  Tapping a stale row on the widget is dropped when the app next drains the
  queue, if Today holds that row for review, so the tap looks done on the
  widget and the row comes back in Needs review.
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
got ta"** and an errand. It has been removed rather than rescued: adding `ta`
to `clauseInternalLead` would suppress a real boundary ("email the TA send the
form") to protect a spelling with no observed instance.

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

## Merge and Undo: what the 2026-09-23 survivor rule leaves

A merge or undo that mixes done and open rows now keeps an open row (see
`Docs/DECISIONS.md`, 2026-09-23). What it does not do:

- **A merged-away done row is not remembered as done.** "Buy milk" ticked
  and then merged with an open "call Mom" comes back as one open row. That
  is the chosen side of the trade, not a defect, but it is visible.
- **The review sheet does not show which rows are done or archived**, so the
  person cannot see beforehand that a merge will reopen something.
- **Undo over a capture whose rows are all closed** keeps a completed row.
  Completed rows never ask for review, so the footer's "one reviewable item"
  is not true in that one shape.
- **Place regions are not re-planned by Merge or Undo** (REV-10). A region
  left behind by a merged-away row is stopped the first time it is crossed
  and dropped at the next foreground reconcile; until then it holds one of
  the region slots. Open PR #135 adds the reconcile to `merge`, not to
  `undoOrganization`.
- **Merge still discards hand edits** on the rows it joins (REV-8), except
  what stays on the surviving row: its pin, idea stage and hand-set place.
  The survivor may be a later row, so a pin on an earlier, closed row is
  lost.
- **The receipt refresh after a review-sheet change is unverified on a
  device.** It replaces the stale rows the capture screen held (LIF-11), but
  no UI test drives Merge or Undo from the receipt, and the crash it removes
  was never reproduced in a simulator.
