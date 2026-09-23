# V1 owner handoff

Every V1 validation step that truly needs Calvin's Mac or a physical iPhone, and
nothing else. Anything a session can do with the repository, GitHub, a hosted
CI dispatch, recorded artifacts or static analysis is done there and is not
listed here.

Calvin runs nothing from this file until one of three things is true: further
engineering would be unsafe without a hardware result (every known Mac check is
then batched into one run), every non-hardware V1 task is complete, or a
destructive, privacy or cost decision needs his approval.

**Mac steps are one command, plus one short block by hand.** `./Tools/CI/v1-qualification.sh`
qualifies every row of `Tools/CI/v1-qualification.tsv` in fresh worktrees
pinned to exact commits, and writes one evidence directory and one zip. The
manifest and this file are kept in step: a Mac entry below with status *queued*
is a row there, and the commit list under M1 is the manifest's rows. M3 is the
only Mac step outside the command: two probe scripts and a timing for #136.

**Before the session, check the pins.** `./Tools/CI/v1-qualification.sh
--check-pins` fetches origin and compares every row's commit with the tip of the
branch the manifest names for it (a PR row's head branch). Exit 0 means every
pin is its branch's tip. Exit 1 lists each stale pin and how far behind it is:
stop there and have the manifest and the commit list below repinned, because a
run on a stale pin qualifies a version of the PR nobody is proposing to merge.
The full run makes the same check and marks any stale row in `SUMMARY.md` and
in that row's `identity.txt`, so the evidence says so even if this step is
skipped.

Status values: **queued** (ready, waiting for the consolidated run),
**pending** (the thing to validate is not built yet), **done** (with the
evidence that closed it).

## Mac

### M1. Compile, test and build the open reliability PRs against a healthy simulator

| | |
|---|---|
| Commits | one manifest row each, listed in the commit list below: the baseline (main), one row per open PR from #116 to #144 except #121 (this file's own PR, whose checkout runs the command), and #118's model run (M2). Stacked PRs have their own row at their own head, which contains their base's commits. |
| Why a Mac | GitHub's hosted macOS simulator has no `NLTagger` lexical-class model: every token tags `OtherWord`. The whole unit suite and every tagger-dependent assertion can only be answered where the model exists. Hosted dispatches can still settle whether the Swift compiles and whether the Release build passes, and those runs are recorded under *Hosted evidence* below. They compiled #117, main, #116 with #119's first commit, and two integration merges of earlier heads (wave 1 and wave 2). Of the PR pins below, only #124 `660fcfb` and #127 `f21cb09` went through a compiler, and only as parts of the wave-2 merge. Every other PR head has moved on since, so it has not been through a compiler as far as this file records. |
| Command | `./Tools/CI/v1-qualification.sh --check-pins` first (see above), then `./Tools/CI/v1-qualification.sh` (runs M1 and M2 together). Exit 1 is expected on this Mac: the gate fails on main because of one known row, and a blind simulator fails the NaturalLanguage diagnostics. Exit 4 means at least one comparison was not measured; `SUMMARY.md` says which. |
| Expected evidence | `SUMMARY.md`. **Table:** PASS on every PR row for compile, and for Release on every row that asks for it (`pr120-ci` and `semantic-units` do not). Each row's focused cell (the classes in the commit list) carries passed, failed and skipped from its own result bundle. #117's `testAnAccountIsHeldWithAnInstitutionAndNotWithAPerson` may skip if the tagger reads its brand as a name; the skip shows in that cell's skipped count. **Suite comparison, per row:** "measured" and **NEW: 0**. A row can instead read **INCOMPLETE** (it ran fewer tests than the baseline plus the test methods its own source adds: a crash, a timeout or a partial run) or **NOT MEASURED** (checkout failed, no readable result bundle, the summary could not be read, or its failures carry no `testIdentifierString`). Neither is a verdict: rerun that row with `--only <label>`. `PersonMentionTests.testTransportVerbsCarryPeopleNotParcels` is expected to FAIL on the baseline row too if this simulator is blind: it failed on the hosted, blind simulator on main (runs 35809409958 and 35810907291) as well as at #117's commit, so it is not NEW. **Gate comparison, per row:** NEW blocking rows 0. The baseline section lists the one known blocking row, GATE-1 ("Remind me before the office closes December 24": delivery expected notification, got none). GATE-1 is expected red on every row until the owner answers Q5 (restore a reminder on that day, or retire the decision and the corpus row); on a row it is never NEW. **Tests to read by name** (the summary names failures only, so a skip or a pass is read in the row's `focused.xcresult`): `pr129-snooze`: `TemporalFullPathTests/testASchedulingPassLeavesAFiredSeriesArmedInTheNotificationCenter` is the only test that proves a fired series stays armed after a real scheduling pass. It needs provisional notification authorization, which a fresh simulator grants without a prompt. **If it is reported skipped, the simulator refused authorization and the row is not evidence for that guarantee**, whatever its pass count says. `pr135-regions`: the reconcile now fetches with a `#Predicate` on an optional `Data` column, which nothing else in the app does, and a predicate the store cannot translate fails when it runs, not when it compiles. `LocationReminderTests/testALivePlaceWithNoTriggerKindIsStillPlanned` fails if it does not translate, and the app logs a `fault` ("Place reminder reconcile could not fetch its rows"). A PASS on that test is the evidence; a skip, or that fault in `pr135-regions/focused-console.txt`, is a failure of the row. `pr140-held-shopping`: the UI test `SpeakItUITests/testAHeldShoppingCaptureIsListedInNeedsReviewAndKeepsItsListCard` is the only test that reaches `TodayView.needsReview`. It types the Costco sentence and expects the `today.review.Buy cereal` row with the `Costco` card still present. UI tests are not in CI, so record its result under *Results recorded from the run* below. **Also** the `NaturalLanguageEnvironmentTests` readout, and from #117's own list, `grep entity-frame-comparison pr117/focused-console.txt`: six lines, but only if `testTheTaggerFrameIsNotALeadingQuestion` did not skip (it skips when no control name gets a personal tag, which is what a blind simulator does). That file is the console log pulled out of `pr117/focused.xcresult` with `xcrun xcresulttool get log --type console`, and its first line says how many items came back. **Unverified:** that subcommand is in xcresulttool's manual for Xcode 16 and later, but it has not been run on a real bundle here and its JSON schema is undocumented. If the file says the command failed or found 0 items, the bundle is kept beside it: open it in Xcode and read that test's console output. **Blind spot:** both comparisons are on names, so a test (or corpus row) that already fails on the baseline and fails on a branch for a new reason is not NEW. Read the failure text of the tagger-dependent tests in the region a branch changes, `PersonMentionTests` for #117 above all. |
| Cost | Most of a day of the Mac, unattended: run it overnight. The manifest has 28 rows. Every row runs the corpus gate (about 9 min on the hosted runner in run 35810907291; `CLAUDE.md` says about 90 s on the author's Mac). The 26 that ask for them (baseline and 25 PR rows) also run the whole unit suite (about 9 min, `CLAUDE.md`) and the Release build (about 2.5 min, hosted): about 20 min a row, so about 8 h 40 min, plus the gate and compile of `pr120-ci` and `semantic-units`. On top of that come each row's clean simulator compile (derived data is per row and commit, so nothing is reused), its focused classes, the baseline's NaturalLanguage readout and M2's model run. Schedule about thirteen hours; a faster local gate makes it shorter. Derived data is kept per row and commit under `SPEAKIT_QUALIFICATION_WORK`, so check free disk before starting. `--only <label>` re-runs one row, and always runs the baseline beside it, so a single re-run costs two rows, about 45 min. No CI minutes, no paid inference. |
| Later work depends on it | Yes. No PR here can be proposed for merge without it, and the readout decides how every tagger-dependent failure is read. |
| Release blocker | Yes. The frozen commit must compile and build Release. |
| Status | queued |

#### Commit list (kept in step with the manifest)

| Row | PR | Pin | Branch whose tip it is | Focused | Suite / Release |
|---|---|---|---|---|---|
| `baseline` | main | `fbb6f90` | `main` | - | yes / yes |
| `pr116-with-119` | #116 + #119 | `bfc482d` | `claude/v1-reliability-nyngoe` | `CaptureFeedbackTests` | yes / yes |
| `pr117` | #117 | `c51842c` | `claude/entity-context-avp56j` | `PersonMentionTests` | yes / yes |
| `pr120-ci` | #120 | `630e3e0` | `claude/v1-reliability-nyngoe-ci` | - | no / no |
| `pr122-bell` | #122 | `edb9e2b` | `claude/v1-reliability-nyngoe-bell` | `ItemPresentationTests` | yes / yes |
| `pr123-recovery` | #123 | `ce62a4d` | `claude/v1-reliability-nyngoe-recovery` | `DurabilityTests`, `CaptureRecoveryEscapeTests` | yes / yes |
| `pr124-edits` | #124 | `660fcfb` | `claude/v1-reliability-nyngoe-edits` | `DurabilityTests` | yes / yes |
| `pr125-place` | #125 | `6d09fcd` | `claude/v1-reliability-nyngoe-place` | `LocationReminderTests`, `ItemPresentationTests` | yes / yes |
| `pr126-stale-save` | #126 | `6333167` | `claude/v1-reliability-nyngoe-stale-save` | `CaptureFeedbackTests` | yes / yes |
| `pr127-alarms` | #127 | `f21cb09` | `claude/v1-reliability-nyngoe-alarms` | `DurabilityTests` | yes / yes |
| `pr128-relaunch` | #128 | `e18e148` | `claude/v1-reliability-nyngoe-relaunch` | `DurabilityTests`, `UpgradeDurabilityTests` | yes / yes |
| `pr129-snooze` | #129 | `20827c8` | `claude/v1-reliability-nyngoe-snooze` | `TemporalFullPathTests`, `SwiftDataThoughtRepositoryTests` | yes / yes |
| `pr130-health` | #130 | `37cb1a7` | `claude/v1-reliability-nyngoe-health` | `LexicalTaggingHealthTests`, `SemanticStatePersistenceTests`, `SwiftDataThoughtRepositoryTests` | yes / yes |
| `pr131-broad-ops` | #131 | `b9f044c` | `claude/v1-reliability-nyngoe-broad-ops` | `DurabilityTests` | yes / yes |
| `pr132-retry-snapshot` | #132 | `75e94ca` | `claude/v1-reliability-nyngoe-retry-snapshot` | `SwiftDataThoughtRepositoryTests` | yes / yes |
| `pr133-alarm-repeat` | #133 | `043f009` | `claude/v1-reliability-nyngoe-alarm-repeat` | `TemporalFullPathTests` | yes / yes |
| `pr134-mic2` | #134 | `42a9db3` | `claude/v1-reliability-nyngoe-mic2` | `CaptureFeedbackTests` | yes / yes |
| `pr135-regions` | #135 | `8da8ea8` | `claude/v1-reliability-nyngoe-regions` | `LocationReminderTests` | yes / yes |
| `pr136-place-day` | #136 | `00bcf75` | `claude/v1-reliability-nyngoe-place-day` | `LocationReminderTests`, `SemanticCorpusTests`, `SwiftDataThoughtRepositoryTests` | yes / yes |
| `pr137-weekly-clock` | #137 | `06b5d62` | `claude/v1-reliability-nyngoe-weekly-clock` | `SwiftDataThoughtRepositoryTests` | yes / yes |
| `pr138-held` | #138 | `12dd411` | `claude/v1-reliability-nyngoe-held` | `ItemPresentationTests`, `TemporalFullPathTests`, `LocationReminderTests`, `SwiftDataThoughtRepositoryTests`, `DurabilityTests`, `MorningBriefTests` | yes / yes |
| `pr139-a11y` | #139 | `1419bb6` | `claude/v1-reliability-nyngoe-a11y` | `VoiceOverAnnouncementTests` | yes / yes |
| `pr140-held-shopping` | #140 | `338fb1d` | `claude/v1-reliability-nyngoe-held-shopping` | `ItemPresentationTests`, UI test `SpeakItUITests/testAHeldShoppingCaptureIsListedInNeedsReviewAndKeepsItsListCard` | yes / yes |
| `pr141-merge-undo` | #141 | `71ccfb7` | `claude/v1-reliability-nyngoe-merge-undo` | `SwiftDataThoughtRepositoryTests` | yes / yes |
| `pr142-widget-review` | #142 | `89e68b8` | `claude/v1-reliability-nyngoe-widget-review` | `LocationReminderTests` | yes / yes |
| `pr143-edit-time` | #143 | `d5fe9ea` | `claude/v1-reliability-nyngoe-edit-time` | `SwiftDataThoughtRepositoryTests` | yes / yes |
| `pr144-typed-draft` | #144 | `e87d305` | `claude/v1-reliability-nyngoe-typed-draft` | `DurabilityTests` | yes / yes |
| `semantic-units` | #118 | `d79d9fa` | `claude/semantic-map-xklzll` | - (extra: the units experiment, M2) | no / no |

Stacked rows, whose head contains their base's commits: #125 on #122 (up to
`60c660b`, not #122's two later fixture commits), #126 and #134 on #119, #128
and #132 on #126, #131 on #124, #133 on #127, #135 on #125, #138 on #122, #139
and #144 on #128, #140 on #138 (up to `5fb026c`, not #138's later commits), #118 on #117. `pr116-with-119` composes #116
and #119; #116's own tip (`fix/capture-experience-reliability`) must still be
contained in its pin, which `--check-pins` does not check.

#### Results recorded from the run

| Item | Result |
|---|---|
| `pr140-held-shopping`: UI test `testAHeldShoppingCaptureIsListedInNeedsReviewAndKeepsItsListCard` | not yet run |

### M2. Semantic-unit representation experiment (Foundation Models)

| | |
|---|---|
| Commit | `d79d9fa` on `claude/semantic-map-xklzll` (#118, draft) |
| Why a Mac | The on-device model needs an Apple Intelligence Mac on macOS 26. The hosted runner compiles Swift but cannot run the model. The probe `Tools/SemanticMap/Sources/UnitsExperiment.swift` has never been compiled; an independent read found one error, fixed before this commit. |
| Command | the manifest's `semantic-units` row, which runs `./Tools/SemanticMap/UnitsExperiment/run.sh` in a clean worktree at `d79d9fa` and writes into `semantic-units/units-experiment/` |
| Expected evidence | Every line of `steps.txt` is PASS: clean tree, 9 manifest hashes, inputs regenerate, scorer selftest, precheck, build, model available, generation, score. `availability.txt` shows `available`, with prompt fingerprints ranges `df4c6e25` and labels `71e026b5`. `results.jsonl` has 60 records (30 ranges, 30 labels; RB14C's labels job is skipped as a one-line capture) and holds ids, integers and labels only, no capture text. `precheck.txt` and `score.txt` are present. If the build fails, `build.txt` comes back; a compile fix changes a pinned hash and ships with a MANIFEST update, which is allowed because nothing has been generated. |
| Cost | 59 local generations. No paid inference, no CI minutes. |
| Later work depends on it | The choice between the two candidates (or neither), and any arbitration experiment after it. No other V1 lane depends on it. |
| Release blocker | No by itself. The production change it chooses will be. |
| Status | queued |

### M3. #136 (DEL-11): probe scripts and a timing, by hand

The only Mac step outside the command. Run it in a worktree at the
`pr136-place-day` pin, after the run (it needs `swiftc`, not a simulator).

| | |
|---|---|
| Commit | the `pr136-place-day` pin above; the timing also needs `11c93d7` (#136 before the place-name cap) |
| Command | `git worktree add /tmp/si-136-after <pr136-place-day pin>`, then in it: `./Tools/CorpusRunner/devsets/conditional-intent-score.sh` and `./Tools/CorpusRunner/devsets/cancellation-scope-score.sh`. For the timing (R1, #136 round 2), also `git worktree add /tmp/si-136-before 11c93d7`; write "Remind me when I get home from the long weekend away with the whole family and the dog and our neighbours from the cottage down the road Friday to call Mom" 200 times, one per line, to a file; then in each worktree `./Tools/PipelineProbe/build.sh && time ./Tools/PipelineProbe/build/probe <that file> > /dev/null`. Remove both worktrees afterwards with `git worktree remove`. |
| Expected evidence | `conditional-intent-score.sh`: 72/72. `cancellation-scope-score.sh`: 187/187. The corpus gate is already run by the `pr136-place-day` row: GATE-1 stays its only blocking row. The two timings, before and after, are recorded in `Docs/PERFORMANCE_BENCHMARKING.md` on #136's branch. |
| Cost | A few minutes. |
| Release blocker | Yes for #136: its scores are unmeasured until then. |
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
| D17 | main, pre-existing | Arm an alarm, let it ring, then open Speak It. Every launch and foreground reconcile issues `stop` and `cancel` on every known row's alarm and re-arms only future ones, so by reading a ringing or snoozed alarm is silenced and not put back. Record whether it stops. No release note may say a ringing alarm survives opening the app until this has run. | queued |
| D18 | #144 (R1) | With VoiceOver on, type a few words, then switch to voice and swipe once through the voice screen. Record whether the typed words are read once, or twice (once from the child label and once from the container). | queued |

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
