# Final language reliability report — Candidate47

The ChatGPT/Astra synthetic-language campaign is closed. **Candidate47 is the
frozen deterministic baseline for controlled real-audio/TestFlight validation.**
No confirmed broad P0 family remains in the reviewed evidence. This conclusion
is bounded by the reviewed host evidence; it is not zero-defect certification.
Do not create Candidate48, repeat the 250K, generate a new bank, or restart broad
parser research without new real-user evidence justifying that work.

## Source and preservation

The original campaign worktree is `/private/tmp/speak-it-conditional-intent`,
branch `codex/conditional-intent-safety`, base
`faeab4e90bee4f67d60e33daa248f48b333ca445`. All **68/68** production Swift files
match the frozen Candidate47 manifest and the source hashes in validation 47.
No production bytes have changed since that validated identity. The manifest's
SHA-256 is `f46a0a6ec9f3edf536a0d94c3b482901ec125ff52cc306b214487f4f37a3c42b`.

Closure uses the isolated `/private/tmp/speak-it-candidate47-closeout` worktree
on `codex/candidate47-closeout`, with the same base. The main workspace at
`/Users/calvinwak/Documents/Speak It` is based on
`2932272b8741901fcb3e3f62e4a6998e7dc07689` and differs in 14 frozen Swift files;
it is **not** the Candidate47 baseline. Neither existing dirty worktree was
rewritten. The closure tree was reconciled by copying only hash-verified source
from the saved production worktree onto its original base.

The exact local production commit is `15bde2157036000fa8b070c3ff731fed21b1a5ce`
(`Finalize language reliability after 250K campaign`); the source identity is independently recoverable from
[the per-file manifest](Candidate47/development/candidate47-source.json).
The frozen archive remains in the original evidence directory with SHA-256
`0d1721978e6fe962d0a9beaec91ad9dd526d1c37ab41f728171b4066579a798d`.
Original frozen records are copied unchanged under `Candidate47/`; statements
there that source was uncommitted describe the historical freeze, superseded
only for Git status by the closure record.

## Original 250K baseline

The original full working-source hash was
`846e7a1bb45071ac4c38f2c4e37e104fdaa838e9d3d029b7152a091e6ff43cf7`;
its parser-source hash was
`eecdd86d51f4792a005d689b3cf475f54ac79f726d787483718eae0d9e60c8fa`.
The base commit alone did not identify this source: it included the existing
conditional-intent patch. The earlier older-main diagnostic is excluded.
Full per-file identity is in [baseline/freeze.json](Candidate47/baseline/freeze.json).

All three complete executions used the unchanged bank SHA-256
`eec6aabf7b23920ba0798e549a92613990077387431afdcddfacbbf0cdcb1311`:
250,000 unique IDs, 418 semantic families, 513 structural variants.

| Version | Cases | Measured agreement | Measured disagreement | P0 flags | P1 flags |
|---|---:|---:|---:|---:|---:|
| Original baseline | 250,000 | 82,732 (33.0928%) | 167,268 | 8,813 | 158,455 |
| Candidate16 | 250,000 | 111,929 (44.7716%) | 138,071 | 2,699 | 135,372 |
| Candidate35 | 250,000 | 120,894 (48.3576%) | 129,106 | 2,424 | 126,682 |

These are agreement on measurable evaluator checks, **not accuracy estimates**.
P0/P1 figures are evaluator flags, not confirmed bugs. The baseline analysis
identified 144,560 cases with measurement limitations and 104 questionable
`before after` contracts. Lexical similarity, alignment, absent target ontology,
and unmeasured context limit interpretation. The bank marks 4,957 ambiguous rows
and supplies context for 6,000 rows that the host cannot fully exercise.

## Candidate16

Candidate16 completed the full 250K (`iteration-2`). Agreement increased by
29,197 cases, or 11.6788 percentage points, relative to baseline; disagreement
fell by the same count. P0 flags fell by 6,114. Source-tree hash:
`03f156c0e4c2060fb12828ab4cb99a13b0186db888890ad13c4e55d9cba68396`.

The batch improved explicit memory framing, non-person entity interpretation,
withdrawal and conditional scope, unfinished requests, exact-value retention,
and safe review of unsupported timing. Remaining flags included 1,244 scoped
cancellation representations, 1,198 reported-user-obligation ambiguities, and
257 other non-actionable candidates requiring review. Ten negative-polarity
failures and four quote indicators remained for successor work. The exact-value
audit found retained literal amounts with alignment issues rather than proven
loss. Persisted cancellation effects remained unmeasured.

Candidate20 was **not promoted**: despite retaining Candidate16 source fixes,
restored actions could lose inherited unresolved temporal context. Its direct
2,044-case comparison showed 72 improvements and 49 new discrepancy candidates.
Do not use passing protected gates alone as evidence of a safe successor.

## Candidate35

Candidate35 completed the later full 250K (`iteration-4`) and remains the last
complete full-bank execution. Agreement increased by 8,965 cases / 3.5860 points
relative to Candidate16 and 38,162 cases / 15.2648 points relative to baseline.
P0 flags fell another 275. Source-tree hash:
`082ab5ac5d3cb260a785d73c51003a6b23dead04fe79bb2025a8526d6a765874`.

Successors through 35 repaired message-owned timing/operations, quotation and
reported actors, restored shared event scope, explicit memory under discourse,
prohibitions with verb-shaped noun objects, calendar inheritance, and selective
cancellation ownership. Its 2,424 P0 flags were adjudicated into 1,198 reported
obligation ambiguities, 1,157 cancellation representations, 52 memory/event
ambiguities, 16 confirmed mixed-memory/scope defects, and one ambiguous implicit
shopping intent. The cancellation cohort showed scoped operations and no broad
operation/timed-alert leak; this does not certify stored-item matching.
The 16 confirmed defects and four quote indicators were resolved on 47.

## Candidate47 validation and safety closure

Candidate47 did **not** run the entire 250K. Its own affected-family comparison
covers 15,058 cases against saved Candidate35 output: 1,355 improvements and 68 newly
flagged rows, all adjudicated. Three cancellation flags retain identical scoped
operations and survivor titles. The direct Candidate45 comparison's three new date flags
are safe review of unresolved event dependencies with execution fields absent.
Earlier successor cohorts were 39,956 on 41, 28,083 on 44 and 3,378 on 45; these
overlap and must not be summed or credited as Candidate47 full-bank coverage.

Protected gates and final closure:

- Cancellation: **187/187**; conditional intent: **72/72**.
- Qualified CorpusRunner: 1,434 cases; zero critical, one behavioral, zero
  metadata, two cosmetic differences. The behavioral qualification holds
  “before the office closes December24” for review because the closing time is
  unknown; no notification is scheduled. Cosmetics concern before-dinner
  punctuation and visible unresolved essay context. The corpus was not edited.
- Release build, semantic contrast controls and saved diff checks passed.
- Final closure: 287 cases (267 residuals + 16 late memory/scope failures + 4 quote
  cases). All 16 failures and all 4 quote indicators resolved; prohibitions 10/10.
  Twenty cases improved. The one newly flagged row-count case, GAP50K-48553,
  retains the full withdrawn-target utterance for review without executable
  date, reminder, geofence or operation.

See [validation 47](Candidate47/development/validation47.json),
[adjudication](Candidate47/development/candidate47-adjudication.json), and
[final resolution](Candidate47/development/final-resolution47.json).
No confirmed broad P0 family remains in reviewed evidence: quoted/reported
operation leaks and message-body timing/operation leaks are addressed;
unresolved event timing is held safely for review; memory/action scope,
cancellation target ownership, date/time correction, location/geofence ownership,
and person/topic/entity handling have been improved at their grammatical scope.

Another full run was not justified after two full successor/baseline comparisons,
affected-family replays and safety closure. Remaining questions are dominated
by qualifications and actual recognition/device integration. This decision
neither claims full Candidate47 coverage nor dismisses the remaining P1 debt.

## Remaining limitations

- P1 grouping/date attachment: SB100K-023393 still separates a movie-theatre
  trip and travel-adapter pickup; the pickup lacks its separately copied date.
  Destination/contact metadata and trip-purpose grouping remain imperfect.
- Reported obligations, implicit shopping and memory/event meanings can be
  ambiguous. Entity ontology and contact matching are not fully measured.
- Host rules measurement excludes Foundation Models, SwiftData persistence,
  stored target matching, notification delivery and physical geofence resolution.
  The fixed frame is 2026-08-03 10:00 America/Toronto; actual timezone/DST behavior
  and device integration still need validation.
- Simulator NaturalLanguage returned OtherWord for all tokens during earlier
  work. Host tagging passed health checks; no production workaround was made.
- No real microphone/ASR or TestFlight/device validation is included. Text noise
  rows are not recordings. Supplied context is not end-to-end host coverage.
- The bank is synthetic and contains ambiguities/quality issues. Saved blind
  model review is a biased sample, not an independent whole-bank accuracy test.

## Diff review and closeout checks

A. Production: eight changed files relative to `faeab4e`: ShoppingGroups,
Actionability, ClauseStructure, LocationIntentParser, PersonMention, SpeechRepair,
ThoughtExtractor and ThoughtOrganizer. Review covered shared speech-act/scope
ownership, calendar repair, cancellation association, neutral entity evidence,
and safe-review suppression. No production changes were made during closure;
no bank phrases or brand-specific exception list was introduced.

B. Tests: existing ActionabilityTests (36 added regression methods) and
ThoughtCompletionTests (one added method); existing conditional-intent devset,
extractor and scorer. These are preserved tests, not newly claimed executions.
The protected187/72 bank slices remain unchanged in ignored evidence, identified
by their copied manifest.

C. Tooling/docs: exact evaluator/report source, read-only identity verifier,
small frozen records, scope documentation, this report and device handoff.
Large evidence and the external bank remain ignored. Rejected/partial artifacts
remain historical and were not copied over production. The archived sources
for baseline/16/35 were checked member-by-member against their manifests;
full bank/raw-output hashes and all final frozen artifact hashes matched.

D. Excluded: all original-main dirty files (including branding/UI, tests,
parser/tool/doc work); original campaign pre-existing corpus inventory edits
in Docs/LANGUAGE_BASELINE.md and Tools/CorpusRunner/test_observation.py.
Their bytes and dirty states were preserved, not silently committed.

Closure ran `git diff --check` and the read-only identity verifier. Source
identity matches validation 47 exactly, so no expensive build, test suite or 250K
execution was repeated. The exact evaluator hash remains
`669bf4d04c67bca624162d1fed7c7e04c5e82b70ecdfe72091b77f367a33e93a`;
report hash `51fc8c1db2a6958a2a4310fe2649e1e8c541ef3e3a558a9f733edcd0a5c5c63f`;
shared evaluator dependency hash
`a22b99a9b791954138a0cb692e0c574f8e9718078f2ba29b9601ade33501b2c4`.

## Retrieval and next phase

Use [CLAUDE_DEVICE_HANDOFF.md](CLAUDE_DEVICE_HANDOFF.md) and
[permanent regression lessons](REAL_USER_REGRESSION_LESSONS.md).
Run `python3 Tools/Reliability250K/verify_frozen.py` in the closure worktree or a
checkout of its source commit. Add `--evidence-root` pointing to the original
`output/reliability-250k` to verify preserved large evidence without execution.
A future machine needs a separate byte-preserving copy of that ignored directory
for raw comparisons; Git deliberately does not contain the external bank.

No push, merge, remote branch change, PR creation, audio test, or Foundation
Models work is part of this closure. A later authorized publication would use
`git push -u origin codex/candidate47-closeout` from this branch, after review of
its original base against current integration work. Do not blindly apply it to
an older parser branch or overwrite newer unrelated integration work.
