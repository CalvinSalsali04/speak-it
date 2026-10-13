# Long-capture V1 release criteria — locked before fresh qualification

Date locked: 2026-09-25. The September 23 long-capture gate and every case
used while changing the implementation are development regressions, never
qualification evidence. Do not change these thresholds after seeing a fresh
set. A code change prompted by a fresh set requires a new independently
authored, unseen set and a new freeze.

## Supported range to qualify

- One continuous spoken capture lasting 1–5 minutes, including ordinary pauses,
  fillers, false starts, and late corrections. This is a **target to validate**,
  not an already proven microphone promise.
- One coherent Memory of up to roughly 700 spoken words remains one usable
  thought when its meaning is one thought. Length alone never splits it.
- A clear list of 10, 15, 20, 25, or 30 independent intentions remains
  individually accessible, with no arbitrary count cap. Mixed Today and Memory
  captures of comparable length are in range.
- The text semantic gate and live microphone gate are separate. Passing typed
  text cannot prove that the recognizer captures five minutes faithfully.

## Whole capture correct

The unit is the entire capture. It scores correct only when every meaningful
intention is present and individually usable where independent, a coherent
single thought stays coherent, no meaning is invented, Today versus Memory is
right, important people/place/time/condition context has the right owner,
corrections and withdrawals modify the right intention, resolved alternatives
are resolved, quote/report content remains attributed, no unsafe operation
executes, and nothing is silently truncated. One wrong row makes the capture
incorrect. A visible Needs Review fallback is **safe incomplete**, not correct,
unless the ground truth itself is genuinely ambiguous and review is the
intended outcome. Raw transcript retention alone never earns correctness.

Score every capture as exactly one of: **correct**, **safe incomplete**, or
**unsafe/silent incomplete**. Also tag every failure by family and defect:
lost meaning, unowned source, over-split, under-split, wrong destination,
wrong context owner, wrong temporal scope, wrong correction/withdrawal target,
wrong quote/report owner, unsafe operation, capacity fallback, and unnecessary
review. Report counts and rates, not only an aggregate.

## Fresh text qualification

An author who has not implemented the candidate writes and seals at least 20
realistic unseen captures in each of these 12 strata: clear long multi-task,
natural rambling, coherent long Memory, mixed Today and Memory, corrections,
withdrawals, quote/report, alternatives resolved later, shared context,
multiple dates/people, capacity (including 25 and 30 intentions), and
beginning/middle/end retention. The set includes punctuation loss, diverse
surface forms, and opposite-direction controls, without copying development
sentences. Expected meaning is sealed before candidate output is inspected.
An independent scorer compares the **shipping production path** to the sealed
expectations. Cases cannot be removed or relabeled after scoring.

Pass thresholds, fixed before evaluation:

- 100% whole-capture correctness in clear long multi-task and clear 25/30
  intention capacity cases. No tail hidden in one fallback row for clear lists.
- At least 95% whole-capture correctness in each other family except natural
  rambling; at least 90% for natural rambling. At least 95% overall.
- At most 5% unnecessary Needs Review overall and at most 10% in natural
  rambling. Genuinely ambiguous source with faithful review is reported
  separately; it cannot conceal clear-speech defects.
- **Zero** silent lost meaningful source, silent capacity truncation, unsafe
  executable quote/report or hypothetical interpretation, destructive wrong
  operation, or unrecoverable uncovered meaningful source in every family.
- Existing short/simple corpus and iOS unit tests, release compilation, and
  relevant persistence/notification checks pass on the exact frozen code.

Any zero-tolerance event blocks V1 regardless of aggregate score. A family
below its threshold blocks V1. These are release thresholds, not an invitation
to tune against the qualification set.

## Live speech and integrated build

On an authorized physical iPhone, exercise the frozen build through
microphone → ASR → interpretation → persistence → review → reminder/operation.
Use at least 30 real captures across the supported duration range, including
clear lists, messy brain dumps, coherent memories, late corrections, different
speakers, proper names, ordinary pauses, and practical background noise.
Retain transcript and recovered audio where applicable; attribute each error
to ASR, interpretation, storage, or UI. Zero silent loss, unrecoverable capture,
unsafe execution, or hidden truncation. At least 95% whole-capture correct on
clear microphone lists and at least 90% overall, with safe review reported
separately. Physical-device behaviors in `CAPTURE_STRESS_TEST_PLAN.md` remain
required where they touch long capture.

The release report must identify the frozen commit, exact test/build logs,
family results, safety events, device results, and limitations. Without both
fresh text qualification and authorized device evidence, status remains
**blocked**, even if development regressions pass.
