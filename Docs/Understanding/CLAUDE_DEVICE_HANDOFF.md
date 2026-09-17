# Claude / device handoff

**Candidate47 is the frozen deterministic language baseline.** The synthetic
campaign is complete. Start from production commit `15bde2157036000fa8b070c3ff731fed21b1a5ce`
([closure receipt](Candidate47/CLOSURE.json)), or its documentation-only
successor on `codex/candidate47-closeout` in
`/private/tmp/speak-it-candidate47-closeout`. Run
`python3 Tools/Reliability250K/verify_frozen.py` before beginning a comparison.
All 68 production Swift files must match. Original-main is not this baseline.

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
