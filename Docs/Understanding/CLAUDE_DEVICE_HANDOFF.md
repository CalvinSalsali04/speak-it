# Claude / device handoff

**Candidate47 is the frozen deterministic language baseline.** The synthetic
campaign is complete.

**Device evidence is gathered from the canonical device baseline, not from
Candidate47 itself.** Calvin authorised it on 2026-09-17: Candidate47's Swift
plus exactly two accepted deviations, `SpeechRepair.swift` (behavioural, from
the reconciliation) and `ModelInterpreter.swift` (provenance only, FNV-1a
fingerprinting). [`DEVICE_BASELINE.md`](DEVICE_BASELINE.md) is the record;
this paragraph is a pointer, not a second copy.

```bash
python3 Tools/Reliability250K/verify_device_baseline.py
```

**That command, not a commit, is the authority.** Check out a commit where it
passes, record that commit beside every capture, and treat a failure as "this
is not the baseline" rather than as corruption. At the time of writing, `main`
passes it; the Swift tree was established by `413a68f` and the receipt landed
at `d2fa541`. A sha written here goes stale the moment `main` moves, which is
why the check is named instead.

**`verify_frozen.py` now fails on that baseline, by design.** It answers "is
this Candidate47?", and the answer is no by two accepted decisions, so it exits
1 naming `SpeechRepair.swift` and `ModelInterpreter.swift` and nothing else.
That output is the expected state, not a defect, and "all 68 production Swift
files must match" is no longer the bar for device work. Run it when you want
the distance from frozen Candidate47 stated explicitly; it is still the right
tool for that question.

**Frozen Candidate47 itself** is commit `15bde2157036000fa8b070c3ff731fed21b1a5ce`
([closure receipt](Candidate47/CLOSURE.json)), reachable on this remote **only**
from `codex/candidate47-closeout` — it is not an ancestor of `main`, because the
reconciliation landed as a squash. So identity here rests on the per-file
hashes, never on `git merge-base`. (Earlier versions of this file also named a
`/private/tmp/...` worktree; that path exists only on Calvin's Mac and no
session can follow it.)

**On "original-main is not this baseline", which this file used to end on:**
that was written about the pre-reconciliation `main` and was true then. It
reads today as an instruction to avoid `main`, which is backwards — `main` now
carries the reconciled baseline. Judge any tree with the verifier above.

Do NOT restart broad parser optimization from an old branch. Do NOT overwrite
Candidate47 with older Claude/parser work. Rejected candidates and partial runs
are historical evidence only. No new bank or 250K run is requested. Later parser
work must be justified by a new confirmed general failure from real-user evidence.

The next separately authorized phase should evaluate:

1. Microphone → Apple transcription → Candidate47 understanding.
2. Where available: microphone/transcript → typed Apple Foundation Models
   interpretation → deterministic safety, routing and execution.

**A Foundation Model must never directly execute user actions.** Candidate47's
deterministic safety invariants remain authoritative, including quotation and
message ownership, memory/action scope, cancellation target ownership, and
non-execution of unresolved temporal/location conditions.

For each case retain and compare the actual spoken utterance, ASR transcript,
Candidate47 output, optional FM-assisted interpretation, and actual persisted
items/reminder/location behavior. Record source commit, device/OS, locale,
reference clock/timezone, contacts/places context and enabled interpretation path
so failures can be reproduced. Keep original user wording intact.

Classify each failure as ASR failure, deterministic parser failure,
FM interpretation failure, routing/safety failure, persistence/integration
failure, ambiguity, or unsupported behavior. Do not attribute transcript errors
to the parser or safe unsupported review to accidental execution.

Include corrected long speech, stored cancellation matching, contacts,
notification/geofence delivery and timezone/DST behavior. Carry forward the
known SB100K-023393 pickup-date attachment defect and grouping/contact metadata
limitations. Preserve the [real-user regression families](REAL_USER_REGRESSION_LESSONS.md).

Evidence: cancellation 187/187, conditional 72/72, qualified CorpusRunner and
Release passed; 16 late memory/scope failures and 4 quote indicators resolved.
Candidate35 is the last full 250K; Candidate47 has 15,058 affected cases and 287
closure cases. Read [the final report](FINAL_RELIABILITY_REPORT.md) for exact
qualifications. This handoff does not claim microphone, FM or device validation
has occurred, and does not initiate that work.
