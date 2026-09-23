# V1 owner handoff

Every V1 validation step that truly needs Calvin's Mac or a physical iPhone, and
nothing else. Anything a session can do with the repository, GitHub, a hosted
CI dispatch, recorded artifacts or static analysis is done there and is not
listed here.

Calvin runs nothing from this file until one of three things is true: further
engineering would be unsafe without a hardware result (every known Mac check is
then batched into one run), every non-hardware V1 task is complete, or a
destructive, privacy or cost decision needs his approval.

**Mac steps are one command.** `./Tools/CI/v1-qualification.sh` qualifies every
row of `Tools/CI/v1-qualification.tsv` in fresh worktrees pinned to exact
commits, and writes one evidence directory and one zip. The manifest and this
file are kept in step: a Mac entry below with status *queued* is a row there.

Status values: **queued** (ready, waiting for the consolidated run),
**pending** (the thing to validate is not built yet), **done** (with the
evidence that closed it).

## Mac

### M1. Compile, test and build the open reliability PRs against a healthy simulator

| | |
|---|---|
| Commits | one manifest row each: baseline `fbb6f90` (main); #116 with #119 `bfc482d`; #117 `c51842c`; #122 alert bell `32453a2`; #123 recovery `216ac33`; #124 edits `3374631`; #125 place `2238b02`; #126 stale save `cae7402` (on #119) |
| Why a Mac | GitHub's hosted macOS simulator has no `NLTagger` lexical-class model: every token tags `OtherWord`. The whole unit suite and every tagger-dependent assertion can only be answered where the model exists. Hosted dispatches can still settle whether the Swift compiles and whether the Release build passes, and those runs are recorded under *Hosted evidence* below. None of these commits has been through a compiler yet. |
| Command | `./Tools/CI/v1-qualification.sh` (runs M1 and M2 together) |
| Expected evidence | `SUMMARY.md`, with PASS on every PR row for compile, Release and the focused class: `CaptureFeedbackTests`, `PersonMentionTests`, `ItemPresentationTests`, `DurabilityTests` and `LocationReminderTests`. #117's `testAnAccountIsHeldWithAnInstitutionAndNotWithAPerson` may skip if the tagger reads its brand as a name; a skip is reported as a skip. The whole suite shows **0 NEW failures against the baseline row**. The corpus gate adds no blocking row beyond the baseline's. Also the `NaturalLanguageEnvironmentTests` readout, and from #117's own list, `grep entity-frame-comparison pr117/focused.log` (six informational lines). |
| Later work depends on it | Yes. No PR here can be proposed for merge without it, and the readout decides how every tagger-dependent failure is read. |
| Release blocker | Yes. The frozen commit must compile and build Release. |
| Status | queued |

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

## Hosted evidence (no owner action)

Runs that retired part of an entry above without Calvin, recorded so the Mac run
is not asked to prove them again.

| Run | Commit | What it established |
|---|---|---|
| (pending) | compile ref for #119 | dispatched 2026-09-23 with `CaptureFeedbackTests`, `NaturalLanguageEnvironmentTests` and the Release build |
| (pending) | compile ref for #117 | dispatched 2026-09-23 with `PersonMentionTests`, `NaturalLanguageEnvironmentTests` and the Release build |
