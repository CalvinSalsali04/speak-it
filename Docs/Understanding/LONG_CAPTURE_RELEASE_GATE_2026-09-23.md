# Long-capture release gate — September 23, 2026

**Decision: V1 long-capture gate is open. Do not call the app launch-ready for realistic brain dumps.**

This pass used thirteen newly authored, previously unrun long utterances: ten
phenomenon cases in `Tools/PipelineProbe/long-capture-gate-2026-09-23.txt` and
three additional clear multi-task cases in
`Tools/PipelineProbe/clear-long-gate-2026-09-23.txt`. Each line is one whole
capture. The primary judgment is **WHOLE CAPTURE CORRECT**: every independent
meaning, its ownership, polarity, timing, and Today/Memory destination must be
right together. A correct row count alone does not pass.

## Evidence boundary

The host probe compiles the actual production rule sources and calls the
shipping rules path at the fixed `2026-08-03 10:00 America/Toronto` reference.
These are fresh text utterances, not recorded speech from opt-in speakers. This
pass does not exercise ASR, SwiftData persistence, Foundation Models
refinement, reminder scheduling, or physical-device capture. The production
policy sends clear lists to rules and considers model refinement only for
review-worthy captures of at most 1,500 characters; operations also stay on
rules. Therefore these failures are directly relevant to the shipping path,
but this pass alone cannot certify that full path. The failed #118 experiment,
older synthetic banks, and short-capture reliability were not scored as
long-capture evidence.

## Whole-capture results

- **Clear multi-task speech:** all four fresh clear captures now have the
  intended ten to twelve independent Today items, including beginning and end.
  This is a narrow text-path pass, not enough samples to establish a release
  rate.
- **Natural rambling:** fails. “Maybe first” becomes a resolved Memory row;
  buying batteries and replacing the detector battery collapse into one
  shopping row; the plant watering intention remains inside a resolved Memory
  sentence. Meaning is visible in the source quote, but the action is missed.
- **Coherent long single memory:** fails the single-memory shape. The Dr Chen
  explanation becomes four Memory fragments. The reported family obligation
  initially became a resolved Today task; the attribution fix in this pass
  now keeps it in Memory.
- **Mixed Today + Memory:** fails. A garden *idea* becomes an executable Today
  task. “Dad prefers a phone call after dinner” was also split into a Memory
  fragment and an unrelated Today/review call; the deterministic nominal
  compound guard now keeps that preference in one Memory row.
- **Corrections / withdrawals:** fails. The Tuesday-to-Thursday correction
  resolves to Tuesday; withdrawn envelopes remain an active shopping item.
  The final instruction to send Omar a draft was silently consumed by an
  operation boundary before this pass; it now survives. “I already have a
  box” no longer executes as a completion, and “don't cancel it” no longer
  executes as a cancellation.
- **Shared context:** the four leak tasks all retain Friday. The shared
  bathroom-leak purpose becomes a separate Memory row, so ownership is not
  represented on each action. No source words are silently dropped here.
- **Quoted/reported speech:** fails. A quote from Nina is split; its “tell
  everyone” portion becomes a Today row marked Needs Review. The speaker's
  actual venue call remains separate. The quoted instruction must never be
  treated as the user's task.
- **Resolved alternatives:** the chosen bus and Thai restaurant are reflected
  by actionable ticket and booking rows, but discarded alternatives also make
  separate resolved Memory rows. This is recoverable clutter, not a proven
  silent loss.
- **10–25 intention capacity:** a 25-errand capture yields 19 individual Today
  rows plus one explicit Needs Review row containing all six remaining errands.
  There is **no silent capacity truncation** in this case. It does not pass
  whole-capture correctness because six independent intentions are not
  individually actionable; the overflow is reviewable.
- **Beginning/middle/end retention:** all substantive spans remain quoted.
  A later “after lunch” and “before bed” originally created phantom rows;
  the clause fix now attaches each phrase to the first following action.
  Shared timing on the later coordinated actions remains unproven.

## Fixes made during this pass

1. Operation partitioning now recognizes capitalized sentence boundaries, so
   an anchored operation cannot consume a later new instruction.
2. A prohibition on cancellation no longer becomes a cancellation operation;
   simple possession with “already have” no longer becomes a completion.
3. “Explained” is read as attributed speech before a third-party obligation
   can become the user's task.
4. Fronted time/sequence phrases stay with the instruction after their comma.
   A nominal compound and an open preference object are guarded against
   unpunctuated instruction splitting.

These are clause, attribution, and operation-scope changes in the existing
pipeline, not a new semantic-map architecture.

## Verification

- The unsigned integrated Release build compiled after these edits.
- `Tools/CI/corpus-gate.sh` passed: 1,403/1,403 identity-rendering corpus cases,
  zero critical or behavioral failures.
- The focused `SpeechRepairTests` simulator class passed. The new attribution
  assertion is also exercised separately.
- The full `ActionabilityTests` class did not pass on the iOS 26.5 slim
  simulator. Its reported failures are fronted-adjunct, condition, possession,
  and possessive/verb readings that depend on the documented simulator
  NaturalLanguage tagging fault. The host corpus passes those cases. This is
  an infrastructure limit, not a claim that the new parsing work is fully
  simulator-verified. The full unit suite and physical-device QA remain open.

## Required next gate work

The first remaining mechanism is a source-coverage invariant over the
untouched transcript, accepted operations, and persisted/reviewable rows. It
must surface uncovered meaningful spans for review instead of allowing a
confident but incomplete reading. Next are stable correction/withdrawal
identity, quoted-speech ownership, narrative consolidation, and shared-context
ownership. Address those with regression cases from these captures, then run fresh unseen
spoken captures through the full signed production build on device. Review the
saved `CaptureSession` and every linked row, Needs Review disposition, and
notification. The release condition is zero silent dropped meaningful source,
zero silent capacity truncation, zero unsafe executable interpretation, and a
recoverable/reviewable place for every uncovered meaning. Rare messy ambiguity
that lands safely in Needs Review should be reported separately from silently
wrong Today or Memory rows.

## Development follow-up after the gate became regression evidence

The September 23 captures above are now **development cases**. Changes made
against them cannot turn this document into an unseen release pass. The current
rules path splits the exposed 25-errand list into 25 individually accessible
Today rows and no longer applies an extraction-stage row cap. A named local
withdrawal removes only its uniquely identified intention. Quoted commands
remain inside reported/relayed speech; an unclosed quote goes to Needs Review.
Fronted daypart timing is inherited by the coordinated actions in its sentence.
A uniquely named later postponement can revise one existing intention; chained
postponements apply in spoken order. An unmatched revision stays in Needs Review.

These are bounded mechanisms, not a frozen production candidate. Follow-up
work separates buying batteries from replacing the detector battery, keeps the
coherent Dr Chen account in one Memory, and attaches the leak purpose to its
four independent actions. The rambling plant need is now visibly contested in
Needs Review. The development captures still fail whole-capture correctness:
resolved alternatives create extra Memory rows, and the messy plant need still
needs human adjudication. An adjacent anaphoric request to save a reported fact
now remains with that Memory, while a file-saving action and a separated
reference do not merge. These results are visible in the shipping rules-path
probe; whole-capture persistence and device speech have not been validated for
these examples.

The new segment coverage check protects word-bearing gaps in the **repaired
creation text**. It does not prove coverage of the untouched transcript across
repairs, operations, or later row shaping, and a fully quoted row can still
contain two intentions. The immutable `CaptureSession` preserves the original
transcript, but that alone does not meet the release standard for independently
actionable meaning. V1 remains blocked. The candidate must be frozen before an
independent author creates a fresh validation set; real microphone validation
on a signed device follows a passing fresh text gate.

## September 24 integrated verification (development evidence)

The focused anaphoric recording and full quoted-suggestion regressions pass on
the iOS 26.5 simulator. The host corpus gate is 1,403/1,403 clean, and the
unsigned integrated Release build compiles. The complete simulator unit run is
**not green**: 814 passed, 39 failed, and one was skipped. Many failures are in
the previously observed simulator NaturalLanguage-dependent action and clause
families; failures also include an unfinished-thought durability assertion,
intent consolidation assertions, and a default-reminder-time assertion. These
must not be dismissed wholesale as infrastructure without isolation. Focused
long-capture tests and the host corpus passing do not make the candidate frozen.

The unfinished-thought failure reproduced alone: “Buy milk and tomorrow I want
to” persisted only one row on the simulator. A deterministic trailing-frame
boundary now separates the completed errand from the incomplete self-commitment;
the focused persistence test passes. The opposite controls retain an ordinary
shopping list and protect a quoted unfinished frame. The full suite result
above predates this repair; it is not represented as a passing integrated run.

Independent semantic review found that an anaphoric save request could use the
first of two identical raw antecedents and falsely span unrelated words. The
raw quote now combines only unique adjacent spans; ambiguous repetition keeps
the known exact antecedent quote, while the visible source and immutable
session retain the save request. The review also found that a coherent Memory
could swallow a changed speaker or independent fact. Consolidation now
requires a reported episode, one consistent reporting pronoun, and a closing
request to remember that account. Focused positive and opposite controls pass.

A proposed final-row word-count audit was rejected: it created 73 blocking
corpus failures, and repeated shared context could mask a missing same-word
source occurrence. It was removed. The remaining release blocker is precise:
post-repair `sourceQuote` strings do not carry stable ordered source-span IDs
through correction, withdrawal, shared-context duplication, shopping shaping,
and persistence. The current segment-gap check is useful but cannot prove
untouched-source coverage. V1 cannot meet the zero-silent-loss claim from this
representation alone; an ordered span ledger and a fresh gate are needed before
a launch decision.

## September 24 development update — still not a release result

The ordered occurrence ledger now follows each repaired creation word through
the deterministic row pipeline. It holds any unowned meaningful occurrence in
Needs Review after shaping. Shopping products map to exact ordered source
spans; a changed or ambiguous mapping keeps the complete parent row. A dated
trip folded into a named shopping list must attach to a product row with the
same date; multiple trips with indistinguishable ownership remain separate.
Repeated action wording and a short simple capture have opposite-direction
tests. Independent review identified and closed a bypass in optional model
refinement: it is now limited to one unresolved rules row, and its single
quote must match the complete raw quote. Multi-row captures stay on the
deterministic path.

The exposed resolved-choice case now makes three actionable rows. The
discarded options remain visible in the chosen action's source quote, while
an unresolved, unmatched, or ambiguous option retains its own row. The
25-errand case remains 25 independently accessible rows. The corpus gate is
1,403/1,403 clean and the unsigned Release build compiles. Focused simulator
tests for coverage, choice persistence, dated shopping ownership, and model
exposure pass. The complete simulator unit suite is being rerun; earlier
39 failures cannot yet be dismissed as infrastructure.

The ledger currently audits repaired creation text. Raw words removed by
speech repair and words partitioned into operations still need an explicit
ownership audit. The current gate remains development evidence. No new
independently authored unseen set or real microphone run has been scored, so
the V1 long-capture release gate remains open.
