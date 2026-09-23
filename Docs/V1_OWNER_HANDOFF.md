# V1 owner handoff

Every V1 validation step that truly needs Calvin's Mac or a physical iPhone, and
nothing else. Anything a session can do with the repository, GitHub, a hosted
CI dispatch, recorded artifacts or static analysis is done there and is not
listed here.

Calvin runs nothing from this file until one of three things is true: further
engineering would be unsafe without a hardware result (every known Mac check is
then batched into one run), every non-hardware V1 task is complete, or a
destructive, privacy or cost decision needs his approval.

**Mac steps are one command, then one typed session.** `./Tools/CI/v1-qualification.sh`
qualifies every row of `Tools/CI/v1-qualification.tsv` in fresh worktrees
pinned to exact commits, and writes one evidence directory and one zip. The
manifest and this file are kept in step: a Mac entry below with status *queued*
is a row there, and the commit list under M1 is the manifest's rows. There are
three rows: `baseline` (main), `rc` (the V1 candidate, carrying every check the
per-PR rows used to run) and `semantic-units` (M2). M3 is the only Mac step
outside the command: captures typed into the Simulator with Apple Intelligence
on, using a list the command writes. Nothing else on the Mac is run by hand.

**Before the session, check the pins.** `./Tools/CI/v1-qualification.sh
--check-pins` fetches origin and compares every row's commit with the tip of the
branch the manifest names for it (for `rc`, the candidate branch). Exit 0 means
every pin is its branch's tip. Exit 1 lists each stale pin and how far behind it
is: stop there and have the manifest and the commit list below repinned, because
a run on a stale pin qualifies a version nobody is proposing to ship. The `rc`
pin goes stale whenever anything is merged into the candidate after it was set;
repinning it is one line in the manifest. The full run makes the same check and
marks any stale row in `SUMMARY.md` and in that row's `identity.txt`, so the
evidence says so even if this step is skipped.

Status values: **queued** (ready, waiting for the consolidated run),
**pending** (the thing to validate is not built yet), **done** (with the
evidence that closed it).

**Gates.** A step marked **Gates:** names a claim that no release note,
CHANGELOG line or App Store text may make until that step has run and said yes.

## Mac

### M1. Compile, test and build the V1 candidate against a healthy simulator

| | |
|---|---|
| Commits | The three manifest rows in the commit list below. `rc` is the candidate branch `claude/v1-reliability-nyngoe-rc`, which contains the head of every V1 PR merged into it: #116, #117, #119 to #148 and #150 to #153 (#150 arrived with #152). #118 is M2. It replaces the per-PR rows this file used to list; where each of their checks went is under the commit list. |
| Why a Mac | GitHub's hosted macOS simulator has no `NLTagger` lexical-class model: every token tags `OtherWord`. The whole unit suite and every tagger-dependent assertion can only be answered where the model exists. Hosted dispatches can still settle whether the Swift compiles and whether the Release build passes, and those runs are recorded under *Hosted evidence* below. They compiled earlier heads and integration merges; none of them is the `rc` pin, so as far as this file records the pinned candidate has not been through a compiler. |
| Command | `./Tools/CI/v1-qualification.sh --check-pins` first (see above), then `./Tools/CI/v1-qualification.sh` (runs M1 and M2 together). Exit 1 is expected on this Mac: the gate fails on main because of one known row, and a blind simulator fails the NaturalLanguage diagnostics. Exit 4 means at least one comparison was not measured; `SUMMARY.md` says which. |
| Expected evidence | `SUMMARY.md`. **Table:** PASS for compile and Release on `baseline` and `rc` (`semantic-units` asks for neither Release nor the suite). The `rc` focused cell carries passed, failed and skipped from its own result bundle. #117's `PersonMentionTests/testAnAccountIsHeldWithAnInstitutionAndNotWithAPerson` may skip if the tagger reads its brand as a name; the skip shows in that cell's skipped count. **Suite comparison (`rc` against `baseline`):** "measured" and **NEW: 0**. It can instead read **INCOMPLETE** (it ran fewer tests than the baseline plus the test methods the candidate adds: a crash, a timeout or a partial run) or **NOT MEASURED** (checkout failed, no readable result bundle, the summary could not be read, or its failures carry no `testIdentifierString`). Neither is a verdict: rerun with `--only rc`. `PersonMentionTests.testTransportVerbsCarryPeopleNotParcels` is expected to FAIL on the baseline row too if this simulator is blind: it failed on the hosted, blind simulator on main (runs 35809409958 and 35810907291) as well as at #117's commit, so it is not NEW. **Gate comparison:** NEW blocking rows 0. The baseline section lists the one known blocking row, GATE-1 ("Remind me before the office closes December 24": delivery expected notification, got none). GATE-1 is expected red on both rows until the owner answers Q5 (restore a reminder on that day, or retire the decision and the corpus row); it is never NEW. **Tests to read by name** in `rc/focused.xcresult` (the summary names failures only, so a skip or a pass is read in the bundle): `TemporalFullPathTests/testASchedulingPassLeavesAFiredSeriesArmedInTheNotificationCenter` is the only test that proves a fired series stays armed after a real scheduling pass (#129). It needs provisional notification authorization, which a fresh simulator grants without a prompt. **If it is reported skipped, the simulator refused authorization and the run is not evidence for that guarantee**, whatever the pass count says. In the same class, F1's `testASnoozedRepeatingAlarmKeepsItsSeriesArmedUnderTheItemID`, `testASnoozedRepeatingAlarmRingsOnceAtTheSnoozeUnderItsOwnID` and `testARepeatingAlarmThatHasRungIsStillArmedForItsNextRing` skip only when the run happens within a minute of their ring: a skip there is not a pass, and `--only rc` settles it. `LocationReminderTests/testALivePlaceWithNoTriggerKindIsStillPlanned` (#135): the reconcile fetches with a `#Predicate` on an optional `Data` column, which nothing else in the app does, and a predicate the store cannot translate fails when it runs, not when it compiles. The test fails if it does not translate, and the app logs a `fault` ("Place reminder reconcile could not fetch its rows"). A PASS is the evidence; a skip, or that fault in `rc/focused-console.txt`, is a failure. The UI test `SpeakItUITests/testAHeldShoppingCaptureIsListedInNeedsReviewAndKeepsItsListCard` (#140) is the only test that reaches `TodayView.needsReview`. It types the Costco sentence and expects the `today.review.Buy cereal` row with the `Costco` card still present. UI tests are not in CI, so its result is recorded under *Results recorded from the run* below. **Also** the `NaturalLanguageEnvironmentTests` readout, and `grep entity-frame-comparison rc/focused-console.txt`: six lines, but only if `PersonMentionTests/testTheTaggerFrameIsNotALeadingQuestion` did not skip (it skips when no control name gets a personal tag, which is what a blind simulator does). That file is the console log pulled out of `rc/focused.xcresult` with `xcrun xcresulttool get log --type console`, and its first line says how many items came back. **Unverified:** that subcommand is in xcresulttool's manual for Xcode 16 and later, but it has not been run on a real bundle here and its JSON schema is undocumented. If the file says the command failed or found 0 items, the bundle is kept beside it: open it in Xcode and read that test's console output. **Probes** (the `rc` extra cell; `rc/probes/steps.txt` has one line per step, and nothing in it is read by hand): `build` PASS. `dec24` PASS means the probe gave exactly one answer for each of the 19 sentences of the December 24 family (a short answer file is a FAIL); `dec24.tsv` records route, review flag, due date, reminder, delivery, title and state for each, for Q5. The audit expects the first block to be held for review with no date and no delivery, and it expects "before the weekend" and "before the autumn" to be held too without having confirmed it; this step confirms or refutes that. `151-held` 13/13, run at the `rc` pin: each piece of advice in somebody else's words is one row, held, gap `reportedSpeech`, no due date and no reminder. `151-unchanged` 12/12: #151 changes only these sentences, measured at its merge. Each control reads the same at #151's merge into the candidate (`5f2c2d3`) as at that merge's first parent (`a9f7517`); both commits are fixed in the script, so what lands on the candidate later cannot be charged to #151, and what the candidate itself does with reported speech is `151-held`, run at the `rc` pin. The step FAILs before comparing anything if either commit is missing, if `5f2c2d3`'s first parent is not `a9f7517`, or if `5f2c2d3` is not in the `rc` pin's history. `candidate-controls` 12/12: the same twelve controls through the probe built at the `rc` pin read exactly as they did at #151's merge, so nothing merged since has started holding (or otherwise changed) an ordinary sentence; a single differing control is a FAIL. `136-conditional` 72/72 and `136-cancellation` 187/187 (#136's DEL-11 scorers; the sets and scorers are unchanged since #136's head, so a lower figure is a later merge moving a row, named in that step's file, and a finding for a session, not a rerun). `136-timing` records three figures for 200 copies of one long unpunctuated capture: before #136's place-name cap (`11c93d7`), the cap alone (`26e69c0`) and the candidate; a session copies them into `Docs/PERFORMANCE_BENCHMARKING.md`. `d19-picks` writes `d19-picks.tsv`, the list M3 types. A FAIL on any probe step makes the extra cell FAIL; `steps.txt` says which. **Gates:** no release note may say that advice reported from somebody else is held for review until `151-held`, `151-unchanged` and `candidate-controls` all pass. **Blind spot:** both comparisons are on names, so a test (or corpus row) that already fails on the baseline and fails on the candidate for a new reason is not NEW. Read the failure text of the tagger-dependent tests, `PersonMentionTests` above all. |
| Cost | Unattended, about two and a half hours: run it overnight. `baseline` and `rc` each run the corpus gate (about 9 min on the hosted runner in run 35810907291; `CLAUDE.md` says about 90 s on the author's Mac), the whole unit suite (about 9 min, `CLAUDE.md`) and the Release build (about 2.5 min, hosted), each after a clean simulator compile (derived data is per row and commit, so nothing is reused). On top of that: the baseline's NaturalLanguage readout; `rc`'s focused tests (one UI test among them) and its probes (up to five probe builds, each a few minutes, and the timing); and `semantic-units`' compile, gate and M2's model run. Derived data is kept per row and commit under `SPEAKIT_QUALIFICATION_WORK`, so check free disk before starting. `--only rc` re-runs the candidate, and always runs the baseline beside it: about an hour and a half. No CI minutes, no paid inference. |
| Later work depends on it | Yes. The candidate cannot be proposed for release without it, and the readout decides how every tagger-dependent failure is read. M3 types the list it writes. |
| Release blocker | Yes. The frozen commit must compile and build Release. |
| Status | queued |

#### Commit list (kept in step with the manifest)

The manifest's `rc` line is the one place the candidate's pin is set; this
table restates it.

| Row | What | Pin | Branch whose tip it is | Focused | Suite / Release | Extra |
|---|---|---|---|---|---|---|
| `baseline` | main, before any V1 change: what `rc` is compared with | `fbb6f90` | `main` | - | yes / yes | - |
| `rc` | the V1 candidate: #116, #117, #119 to #148, #150 to #153 | `5f2c2d3` | `claude/v1-reliability-nyngoe-rc` | `PersonMentionTests`, `TemporalFullPathTests`, `LocationReminderTests/testALivePlaceWithNoTriggerKindIsStillPlanned`, UI test `SpeakItUITests/testAHeldShoppingCaptureIsListedInNeedsReviewAndKeepsItsListCard` | yes / yes | `Tools/CI/v1-probes.sh` |
| `semantic-units` | #118 | `09a9eed` | `claude/semantic-map-xklzll` | - | no / no | the units experiment (M2) |

`baseline` stays a separate commit because it is the comparison: the candidate
compared with itself would call nothing NEW. `semantic-units` belongs to the
semantic-map lane, which sets its pin.

**Reproducing the evidence.** A run is reproducible from the pair (the `rc`
pin, the #121 checkout that ran the command). `Tools/CI/v1-probes.sh` and its
inputs live only in #121's checkout, not in the frozen candidate tree, by
design: the probe script's questions come from #121, and the tools it
questions come from the pinned tree.

**Where the per-PR rows went.** Every PR branch the old list named, #118's aside, has its head
inside the `rc` pin (checked with `git merge-base --is-ancestor` for each), so
each row's suite, Release build and gate now run once, at the candidate, against
the same baseline. #146 to #148 and #150 to #153, which never had rows, are covered the same way.

| Former row or step | Its check now |
|---|---|
| `pr116-with-119` to `pr145-alarm-cancel`: the whole suite, Release and the gate at each PR head | `rc`'s whole suite, Release and gate, compared with `baseline` |
| `pr117`: `PersonMentionTests` and its console readout | `rc` focused, `rc/focused-console.txt` |
| `pr129-snooze`: the pass-level test in `TemporalFullPathTests` | `rc` focused (the whole class, which also holds F1's tests) |
| `pr135-regions`: the `#Predicate` test | `rc` focused, by name |
| `pr140-held-shopping`: the UI test | `rc` focused, by name |
| `pr120-ci`: compile and gate through #120's own `Tools/CI` scripts | `rc`'s compile and gate, through the candidate's `Tools/CI`, which carry #120 |
| every other focused class (`CaptureFeedbackTests`, `ItemPresentationTests`, `DurabilityTests`, `CaptureRecoveryEscapeTests`, `UpgradeDurabilityTests`, `SwiftDataThoughtRepositoryTests`, `LexicalTaggingHealthTests`, `SemanticStatePersistenceTests`, `SemanticCorpusTests`, `MorningBriefTests`, `VoiceOverAnnouncementTests`, `CaptureOperationTests`) | `rc`'s whole suite, at the same commit. The suite names its failures; it does not list skips, and none of these classes had a skip the old list read by name |
| the old M3: #136's two scorers and its R1 timing, by hand | `rc`'s probes (`136-conditional`, `136-cancellation`, `136-timing`) |

#### Results recorded from the run

| Item | Result |
|---|---|
| `rc`: UI test `testAHeldShoppingCaptureIsListedInNeedsReviewAndKeepsItsListCard` | not yet run |

### M2. Semantic-unit representation experiment (Foundation Models)

| | |
|---|---|
| Commit | `09a9eed` on `claude/semantic-map-xklzll` (#118, draft) |
| Why a Mac | The on-device model needs an Apple Intelligence Mac on macOS 26. The hosted runner compiles Swift but cannot run the model. The probe `Tools/SemanticMap/Sources/UnitsExperiment.swift` has never been compiled; an independent read found one error, fixed before this commit. |
| Command | the manifest's `semantic-units` row, which runs `./Tools/SemanticMap/UnitsExperiment/run.sh` in a clean worktree at `09a9eed` and writes into `semantic-units/units-experiment/` |
| Expected evidence | Every line of `steps.txt` is PASS: clean tree, 11 manifest hashes, inputs regenerate, scorer selftest, precheck, build, model available, generation, score, decision. `availability.txt` shows `available`, with prompt fingerprints ranges `df4c6e25` and labels `71e026b5`. `results.jsonl` has 60 records (30 ranges, 30 labels; RB14C's labels job is skipped as a one-line capture) and holds ids, integers and labels only, no capture text. `precheck.txt`, `score.txt` and `decision.txt` are present; `decision.txt` ends with the outcome (A ranges, B labels, C neither) from the decision rule pinned before any generation (`DECISION_PLAN.md`, `decide.py`). The last line may read `OUTCOME A (no clear winner)` when A is reached without a clear margin. If it reads RUN INVALID and names a generation error, that is not a failed experiment and nothing more is needed from you: the remedy is pre-registered in `DECISION_PLAN.md` (the semantic-map thread checks the error name against Apple's documentation, re-decides on the same `results.jsonl` if it is model behaviour, and regenerates only for a genuine infrastructure failure). If the build fails, `build.txt` comes back; a compile fix changes a pinned hash and ships with a MANIFEST update, which is allowed because nothing has been generated. |
| Cost | 59 local generations. No paid inference, no CI minutes. |
| Later work depends on it | The choice between the two candidates (or neither), and any arbitration experiment after it. No other V1 lane depends on it. |
| Release blocker | No by itself. The production change it chooses will be. |
| Status | queued |

### M3. #146's two-second budget and #151's model path, typed into the Simulator (D19)

The only Mac step outside the command, and the only one that needs Apple
Intelligence: the Simulator must reach the on-device model. Run it after the
command, on the candidate at the `rc` pin, because it types the list the
command wrote. (The #146 audit calls this D19; it is a Mac step, not an iPhone
one.)

| | |
|---|---|
| Commit | the `rc` pin (it contains #146 and #151) |
| Set up | `git worktree add /tmp/si-rc <rc pin>`, open `SpeakIt.xcodeproj` from it in Xcode, and run the app in an iPhone Simulator. Apple Intelligence on for the Mac; the Simulator's region and language `en_CA`. In Instruments, record with the os_signpost / Logging template on the Simulator (all processes, so a relaunch stays in the same recording), and add the Foundation Models instrument if this Xcode has one. If a relaunch ends the recording anyway, save it and start a new one; number the files in order. Every capture is **typed** (paste each line's text from the list into Type), which follows the same save path as speech without speech's variance. Afterwards, `git worktree remove /tmp/si-rc`. |
| Inputs | `rc/probes/d19-picks.tsv` from the run's evidence: up to 30 captures the rules would send to the model (no operation, at most 1,500 characters, at least one row held for review), the eight the audit names first where they still qualify (`d19-named.txt` says which do not), then five **controls** the rules keep for themselves. Its `rules reading` column is what the rules alone save. Then one more capture: "Sarah said I should call Mike tomorrow at 3". |
| Pacing | (a) the list in order, at least 15 s between one receipt and the next capture; (b) cold: quit the app, relaunch it and type the next capture, then type five more at least 2 minutes apart; (c) busy: two multi-row picks back to back, the second saved within 1 s of the first receipt. |
| Record | Only what the trace cannot hold. **By hand**, one line per capture in a text file: its `n` from the list, which pacing block it belonged to (list, cold after a relaunch, or the busy pair), and anything that went wrong (a retyped or skipped capture). A screenshot of the capture screen about 1 s into the save, and one of the receipt, each named by `n`. The saved rows: how many, Today or Memory, and whether each is in Needs review. **Not by hand:** save the Instruments recording (File > Save, a `.trace` document) and put it with the screenshots and the text file beside the run's zip. A session reads the timings off it with `xcrun xctrace export`: the `SemanticParsing` and `RawCapturePersistence` durations from the os_signpost interval table (subsystem `com.calvinwak.SpeakIt`, category `CapturePipeline`, one interval of each per capture, matched to `n` by order, after first accounting for the retyped and skipped captures the by-hand file names, since one retyped capture shifts every later interval by one); `RefinementClaimTakenOver` from the os_signpost event table, same subsystem and category; and each Foundation Models `respond` start, end and token count from that instrument's own table, if it was recorded. The table names `xctrace` gives these have not been checked here; the session lists them with `xctrace export --toc` first. |
| What the result means | A capture was *invoked* when its `SemanticParsing` is at least the controls' plus 300 ms. **Any `SemanticParsing` above about 2.15 s means #146 does not bound the wait.** Every invoked capture that took 2 s or more must have saved exactly its rules reading, with at least one row in Needs review. In (c) the second capture must save its rules reading. `RefinementClaimTakenOver` should never appear. `RawCapturePersistence` must end before `SemanticParsing` begins, the screenshots must show the saving copy, and no receipt may mention a model. If every eligible capture's `SemanticParsing` looks like a control's, the Simulator never reached the model: say so, and the iPhone's D5 becomes the only answer. For the last capture: the saved row must still be held for review with no date. If it comes back as a confident task due tomorrow at 3, refinement undoes #151 on the model path. A session reads all of this against the audit (expired and invoked, warm against cold, whether abandoned calls stop near 2 s) and asks the semantic-map thread to run the same inputs unbudgeted for the discarded-answer count. |
| Cost | About an hour of typing and waiting, most of it the pacing. No paid inference. |
| Gates | No release note or CHANGELOG line may say #146 bounds the save's wait at two seconds until this has run with no interval above about 2.15 s. No release note may say reported advice stays held on Apple Intelligence devices until the last capture has come back held. |
| Release blocker | Yes for the two claims above, and for the keep-or-defer decision on refinement. |
| Status | queued |

## Merge order and conflicts (for whoever merges)

Known interactions between the open PRs, one line each. Neither side of a line
is to be picked blindly.

- **#128 after #126.** #128 is stacked on #126 and carries the wave-2 merge resolutions: `CaptureDraftStore.leaveRecoveredWordsForToday` clears the handoff when the words it leaves differ, and `CaptureView.save` records the handoff only after `presentation.beginSave()` has claimed the save slot. Keep both.
- **#125 after #122.** #125 is stacked on #122 (at `60c660b`); rebase it onto #122's final head before landing.
- **#122 × #129:** both edit the same `ReminderScheduleRequest.init` hunk. Check by hand: keep `delivery = scheduledDelivery` (#122's one delivery rule) and add #129's `seriesFireDate`, the `repeatingComponents` built from it, and `seriesContinuation`.
- **#123 × #126,** in `CaptureView.recoverActiveAudio`: #126's `CaptureRecoveryHandoff` `continueByTyping` closure must re-read the draft's words after the pass and pass them as #123's `keptWords:`. Drop #123's own `markFailed` in the `catch`, because `finish` already records the failure.
- **#129 × #133:** `ReminderScheduleRequest.alarmRepetition` must derive from `seriesReminderDate` (#129), not from the snoozed `fireDate`. Check it by hand in the merge, and add a test.
- **#135 × #138:** in `reminderState`, keep the order blocker → combined → hold → `.place`.
- **#135 × #141:** in the `merge` hunk, keep #141's `target` and `removed` lines, then #135's `hadPlaceReminder`.
- **#139 × #134,** in `SpeechTranscriber.start`: #134's comment must read "nothing between the wait's own ownership check and here suspends", and the stale guard must release only this run's microphone claim.
- **#136 × #138:** move `awaitsPlaceOrTimeChoice` into `ItemPresentation.mayArmTime`, and assert that `scheduledDelivery` is `.none` for such a row.
- **#143 × #135:** rewrite `testALivePlaceWithNoTriggerKindIsStillPlanned`, whose precondition relied on DEL-20 (the reorganize taking the time away). Build it around a live place whose column reads `time`.
- **#143 × #138:** resolved on #138 (`d615c84`, `b7a48db`). `mayArmPlace` reads only the location mark, and only the editor's `.update` sets it, so #143's kept time mark cannot arm a re-read place. Both graders say they compose in either order; land them together.
- **#145 after #127.** #145 cancels a removed row's alarm synchronously and relies on #127's orphan sweep to heal a kill before that cancel. Both edit `DurabilityTests`' `RecordingDelivery`: keep #145's lock and #127's `scheduledAlarmIDs` hook.
- **#144 × #139:** the no-audio branch of `endAttemptWithoutWords` should keep the typed words. After both merge the census pin should read 4209 (base `e18e148` at 4156, #139 +25, #144 +28 at `b298587`, no shared literals as graded at `95a1f6f`), which `baseline_figures.py --write` should reproduce, not be typed in.
- **Every PR** moves the census pin in `Tools/CorpusRunner/test_observation.py` and the figures in `Docs/LANGUAGE_BASELINE.md`. Recount after each merge (`python3 baseline_figures.py --write` in `Tools/CorpusRunner`), never pick a side.

## Physical iPhone

Collected here as the lanes that need them are closed. The final session is one
structured checklist, not a series of requests.

| | Item | Why a device | Depends on | Release blocker | Status |
|---|---|---|---|---|---|
| D1 | Capture stress plan (`Docs/CAPTURE_STRESS_TEST_PLAN.md`), including cancel then re-record, background, lock and relaunch mid-save | microphone, audio session, app lifecycle | lifecycle lane fixes | yes | pending |
| D2 | Notification, AlarmKit and geofence delivery for the cases the delivery-integrity audit lists | only the OS delivers | delivery lane fixes | yes | pending |
| D3 | Whether a real iPhone can reach the blind-`NLTagger` state (missing assets, offline, unsupported locale) | the simulator result says nothing about a device | runtime-health lane | yes | pending |
| D4 | Long recordings on the legacy recognizer and on SpeechAnalyzer: does either stop early without saying so | recognizer limits are device and network behaviour | capacity lane | yes | pending |
| D5 | Foundation Models route and fallback on Apple Intelligence hardware, and ordinary capture on hardware without it | model availability | semantic lane | yes | pending |
| D6 | VoiceOver and accessibility text sizes on capture, receipt, review, Today, Memory, editor | physical assistive-technology behaviour | review UX lane | yes | pending |

### Device checks queued 2026-09-23

Each is run on a build that contains the PR named. They join the D-rows above
in the one device session.

| | PR | Check | Status |
|---|---|---|---|
| D7 | #127 (`f21cb09`) | One alarm scheduled by this build is listed by `AlarmManager.alarms` as `.scheduled` (the whole orphan sweep rests on it), and `cancel(id:)` on an orphan leaves every other alarm untouched. | queued |
| D8 | #123 | After a failed recovery pass, the capture screen is seeded with the kept words. | queued |
| D9 | #126 | A sheet-triggered `onDisappear` during a save (F3), and the Lock Screen `today` link mid-save. | queued |
| D10 | #134 (LIF-7, N-6) | On a cold analyzer: the orb, then Type instead, then Speak instead, then the orb, then speak for 10 s. Repeat on iOS 17 to 25 (legacy recognizer), then in the tutorial. | queued |
| D11 | #135 (DEL-7, DEL-16) | The 18-region cap; a region iOS refuses; capture "when I get home", lock the phone, arrive. | queued |
| D12 | #129 (DEL-10) | Snooze a recurring place reminder from its notification; a Siri recurring capture; the Allow button on the permission card when a series alert has already fired. | queued |
| D13 | #133 (DEL-13) | `.weekly` with all seven weekdays behaves as daily; a repeating alarm survives in AlarmKit's store after it fires. | queued |
| D14 | #139 (A11Y D-3) | A VoiceOver announcement during recording does not appear in the transcript. | queued |
| D15 | #139 (A11Y F3) | With VoiceOver on, log the type and value of `UIAccessibility.announcementStringValueUserInfoKey` in one `announcementDidFinishNotification` (for example the "Listening" cue). A `String` or an `NSAttributedString` equal to the posted text is fine: both are read. Anything else means every wait runs its whole allowance. | queued |
| D16 | #145 + #127 (DEL-22) | Arm an alarm, delete its row, and kill the app before the next foreground; the alarm must not ring. Then relaunch with an orphan armed and confirm #127's sweep cancels it. | queued |
| D17 | main, pre-existing; DEL-23 fix (#153) on the candidate | In this order, because (a) needs a build the rest of the session replaces. (a) First, on a build of main (`fbb6f90`, without the fix): arm an alarm, let it ring, open Speak It, and record whether it stops. That says whether `stop` reaches an alerting alarm at all. Then install the candidate over it. (b) On the candidate: arm an alarm, let it ring, then open Speak It. Repeat while a snoozed repeating alarm rings under its snooze ID, and while a repeating alarm rings; then open the app while an alarm is snoozed and not ringing. Before the DEL-23 fix, every launch and foreground reconcile issued `stop` and `cancel` on every known row's alarm, so by reading a ringing or snoozed alarm was silenced. Since the fix, that pass leaves alone a row whose alarm rang in the last 30 minutes (`ReminderScheduler.alertingWindow`, a guess). Record whether each alarm keeps ringing, or stays snoozed and rings at its snooze time: none may go silent unless you stopped it. (c) Record how long an unattended alarm alerts, to check the window. **What (a) decides:** if `stop` reaches it, DEL-23 is real on a device, and #153's known `.fixed` gap has a candidate fix (arm the advanced occurrence under the row's snooze ID while that slot is free), held until then because it doubles those rows against the alarm limit. If `stop` never reaches a ringing alarm, DEL-23 never happened on a device, #153's window only costs the gaps `KNOWN_ISSUES.md` lists, and keeping it is revisited. **Gates:** no release note may say a ringing alarm survives opening the app until this has run. | queued |
| D18 | #144 (R1) | With VoiceOver on, type a few words, then switch to voice and swipe once through the voice screen. Record whether the typed words are read once, or twice (once from the child label and once from the container). | queued |
| D19 | #146 | A Mac step, not an iPhone one: see M3. | queued |
| D20 | GATE-1 (Q5), the candidate | Type "Remind me before the office closes December 24" as a capture. Record whether the saved row is in Needs review. Note the Scheduled count in Reminder settings before and after the save: it must not change. Record whether AlarmKit lists any alarm for the row (see *Reading what is armed* below): it must list none. A pending request or an alarm means a held row is armed. **Gates:** the interim December 24 answer (the row is held and nothing is armed) may not be described as shipped behaviour until this has run. | queued |
| D21 | F1 on the candidate (`83ce9c5`; rehearsal 2, G7) | Create a weekly alarm, let it ring, and snooze it. AlarmKit must then list both as scheduled: a `.fixed` alarm under the snooze ID, and the weekly `.relative` series under the item's ID. The snooze rings once; the series rings at its next weekly time. Then, with the same setup, stop the snooze and cancel it through the app's snooze path: the weekly series must stay armed. Record both. Extends D13, which checks a repeating alarm with no snooze. **Gates:** no release note may say snoozing a repeating alarm keeps its series until this has run. #153's follow-up in D17 rests on the same answer (two alarms from one app side by side). | queued |
| D22 | #148 diagnostics follow-up | On one iPhone, ten voice captures with VoiceOver off, then ten with it on. For each, record `capture_ready_ms`: from the `CaptureActivated` signpost to `MicrophoneReady` (Instruments, os_signpost, subsystem `com.calvinwak.SpeakIt`, category `CapturePipeline`). With VoiceOver on, the "Listening" cue is spoken before the engine starts, so expect the cue's length plus the queue drain on top. Report both sets. **Decides** whether `capture_ready_ms` is bucketed or dropped so it stops marking VoiceOver installs (`KNOWN_ISSUES.md`, "`capture_ready_ms` can still carry VoiceOver use"). **Gates:** no privacy answer or release note may say performance timings carry no trace of VoiceOver use until this is measured and decided. | queued |

**Reading what is armed.** Reminder settings (from Settings, or from Today) shows a Scheduled count: Speak It's pending reminder notifications, the morning brief excluded. No screen in the app lists AlarmKit's alarms; D7, D20 and D21 read `AlarmManager.shared.alarms` with the build run from Xcode, in the debugger console (`po try AlarmManager.shared.alarms`). That command has not been tried here.

## Hosted evidence (no owner action)

Runs that retired part of an entry above without Calvin, recorded so the Mac run
is not asked to prove them again.

| Run | Commit | What it established |
|---|---|---|
| [35807374279](https://github.com/CalvinSalsali04/speak-it/actions/runs/35807374279) | `11507dc` on `claude/v1-reliability-nyngoe-compile-117`: #117 `c51842c` plus #120's CI commit | Corpus gate FAIL: 1434 cases, 1 blocking, the same row as main. Swift compiled: PASS. Release: PASS. `PersonMentionTests` + `NaturalLanguageEnvironmentTests`: 28 passed, 4 failed, 1 skipped. Three failures are `NaturalLanguageEnvironmentTests`, every token tagged `OtherWord`: a blind tagger. The fourth is `PersonMentionTests.testTransportVerbsCarryPeopleNotParcels`, three assertions ("Pick up Alex", "Drop off Sam", "Get Sam") getting nil where a name was expected. It predates #117 and, by reading, depends on `NLTagger`'s `isPersonalName`; runs 35809409958 and 35810907291 below confirm it fails on main too. UI tests: not run. |
| [35807372132](https://github.com/CalvinSalsali04/speak-it/actions/runs/35807372132) | `c463e62` on `claude/v1-reliability-nyngoe-compile-119`: #116 plus #119's first commit `7656ef9` plus the CI commit. **Not** #119's head `bfc482d` | Corpus gate FAIL, the same row. Swift compiled: PASS. `CaptureFeedbackTests` + `NaturalLanguageEnvironmentTests`: 23 passed, 3 failed, 0 skipped; all three failures are the blind-tagger diagnostics, so all 21 `CaptureFeedbackTests` passed. Release: PASS. UI tests: not run. Says nothing about `bfc482d`, which the M1 row pins. |
| [35809409958](https://github.com/CalvinSalsali04/speak-it/actions/runs/35809409958) | `617c9c1`: main with the CI commit (the hosted baseline) | Swift compiled: PASS. Five classes: 137 of 138 passed; the only failure is `PersonMentionTests/testTransportVerbsCarryPeopleNotParcels`, the same as on #117. Corpus gate: 1 blocking row (GATE-1). Release: NOT RUN, because the unit step failed (#120's F5). |
| [35809407582](https://github.com/CalvinSalsali04/speak-it/actions/runs/35809407582) | `66ea18e` (wave 1): #122 `32453a2` + #123 `216ac33` + #124 `3374631` + #125 `2238b02` + #126 `cae7402` + the CI commit | Swift compiled: PASS. Release: PASS. `CaptureFeedbackTests` + `ItemPresentationTests` + `DurabilityTests` + `LocationReminderTests`: 153 of 153 passed. Every head since then carries grade fixes that were **not** compiled here. |
| [35810907291](https://github.com/CalvinSalsali04/speak-it/actions/runs/35810907291) | `780e4db`: main with #120's CI fixes | Swift compiled: PASS (the five products named). `ItemPresentationTests` + `PersonMentionTests`: FAIL, 36 passed, 1 failed, 0 skipped (`testTransportVerbsCarryPeopleNotParcels`). Release: PASS. Gate: FAIL (GATE-1). Proves #120's counts path on a real Xcode 26.6 result bundle, and main's Release build. |
| [35811417279](https://github.com/CalvinSalsali04/speak-it/actions/runs/35811417279) | `3ff04ce` (wave 2): ten branches merged onto main (stale-save `366af54`, bell `e8500b2`, place `d914891`, recovery `3ba6d74`, edits `660fcfb`, alarms `f21cb09`, relaunch `4bdcacc`, snooze `3b10701`, health `2488d4b`, ci `780e4db`) | Swift compiled: PASS (the five products). Release: PASS. Nine classes (CaptureFeedback, ItemPresentation, Durability, LocationReminder, TemporalFullPath, SwiftDataThoughtRepository, RenderingInvariance, SemanticStatePersistence, CaptureOperation): 569 passed, 5 failed, 2 skipped. Failures: `RenderingInvarianceTests` comma-free and unpunctuated renderings; `SwiftDataThoughtRepositoryTests` `testOrganizerUnderstandsIntervalAndCompletionAnchoredRecurrence` and `testScheduledMessageBecomesAPersonFollowUpWithAnApprovalReminder` (nil where a value was expected); `TemporalFullPathTests/testSnoozedWeeklyOccurrenceArmsTheOneShotAndTheSeries`, off by exactly four hours on the UTC runner (#129's later `c7b5a4b` reads those values in the machine's zone). Gate: FAIL, GATE-1 only. Its Swift resolutions for #123 × #126, #126 × #128 and #122 × #129 are the ones under *Merge order and conflicts*. |
| [35858682400](https://github.com/CalvinSalsali04/speak-it/actions/runs/35858682400) | `f02851c`: #136 (DEL-11) round 2 `00bcf75` with the CI dispatch branch | Swift compiled: PASS. Eleven classes: 585 passed, 39 failed, 7 skipped. 35 failures pre-existing (blind simulator tagger); 4 new in `SwiftDataThoughtRepositoryTests`, caused by the place-and-time hold dropping a held shopping row's store list. Fixed in `018c3f5`. Gate: FAIL, GATE-1 only. |
| [35893003362](https://github.com/CalvinSalsali04/speak-it/actions/runs/35893003362) | `71e3d14`: #136 `018c3f5` with the CI dispatch branch | Swift compiled: PASS. SwiftDataThoughtRepository, LocationReminder, InterpretationBridge: 394 passed, 2 failed (both pre-existing, same messages as on main). The four tests above and the new `testOnlyThePlaceAndTimeHoldKeepsAReviewRowOnTheStoreList` pass. Gate: FAIL, GATE-1 only; language figures unchanged apart from the Location family (45 to 50 cases, 0 failing). |
