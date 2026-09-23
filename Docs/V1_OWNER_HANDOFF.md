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
| Commits | `7656ef9` (#116 with #119 on top), `c51842c` (#117), baseline `fbb6f90` (main) |
| Why a Mac | GitHub's hosted macOS simulator has no `NLTagger` lexical-class model: every token tags `OtherWord`. The whole unit suite and every tagger-dependent assertion can only be answered where the model exists. Hosted dispatches can still settle whether the Swift compiles and whether the Release build passes, and those runs are recorded under *Hosted evidence* below. |
| Command | `./Tools/CI/v1-qualification.sh` |
| Expected evidence | `SUMMARY.md`: compile PASS and Release PASS on both PR rows; focused `CaptureFeedbackTests` and `PersonMentionTests` PASS (#117's `testAnAccountIsHeldWithAnInstitutionAndNotWithAPerson` may skip if the tagger reads its brand as a name, and a skip is reported as a skip); whole-suite **NEW failures against the baseline row: 0**; the corpus gate adds no blocking row beyond the baseline's; the `NaturalLanguageEnvironmentTests` readout. From #117's own list: paste `grep entity-frame-comparison pr117/focused.log`. |
| Later work depends on it | Yes. #116, #119 and #117 cannot be proposed for merge without it, and the readout decides how every tagger-dependent failure is read. |
| Release blocker | Yes. The frozen commit must compile and build Release. |
| Status | queued |

### M2. Semantic-unit representation experiment (Foundation Models)

| | |
|---|---|
| Commit | not yet built: the semantic-map lane (#118) is designing two grounded candidates, and a separate thread is writing the development gold blind |
| Why a Mac | The on-device model is reachable only on Calvin's Mac (`en_CA`); CI reports `deviceNotEligible`. Recorded outputs are replayed off the Mac with `--replay`, so the Mac is needed for generation only. |
| Command | added to the manifest's `extra` column when the experiment exists |
| Expected evidence | one `runs.jsonl` per candidate over the frozen capture list, scored off-Mac on whole semantic-unit recovery |
| Later work depends on it | The production semantic change does. No other V1 lane does. |
| Release blocker | No by itself. The production change it chooses will be. |
| Status | pending |

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
