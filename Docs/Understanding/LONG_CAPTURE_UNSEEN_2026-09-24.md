# Long-capture unseen validation — September 24, 2026

**Release decision: blocked.** The first frozen candidate failed the independent
whole-capture gate. The set is now development evidence. No result after tuning
against it may be used as a V1 release claim.

An independent author wrote 40 previously unseen text captures in
`long_capture_unseen_2026-09-24.jsonl` (four per family; 185 expected outcomes)
without reading the prior gate, probe output, or implementation. The frozen
shipping-rules candidate was run once through the production-source host probe
at its fixed Toronto fixture clock. A separate scorer judged each whole capture
against the author's expectations. The frozen output and verdicts are in
`/private/tmp/speakit-unseen-output.jsonl` and
`/private/tmp/speakit-unseen-scores-independent.jsonl` for this workspace.

| Family | Whole correct | Safe review | Incorrect |
| --- | ---: | ---: | ---: |
| Clear multi-task long speech | 0 | 0 | 4 |
| Natural rambling | 0 | 1 | 3 |
| Coherent single memories | 0 | 0 | 4 |
| Mixed Today + Memory | 0 | 0 | 4 |
| Corrections / withdrawals | 1 | 0 | 3 |
| Shared context | 0 | 0 | 4 |
| Quoted / reported speech | 0 | 0 | 4 |
| Resolved alternatives | 0 | 0 | 4 |
| 10–25 intention capacity | 0 | 4 | 0 |
| Beginning / middle / end retention | 0 | 0 | 4 |
| **Total** | **1** | **5** | **34** |

The four capacity captures safely retained every spoken item in one visible
Needs Review row, but the independent intentions were not individually usable.
Clear multi-task captures produced phantom rows from prefaces, dates, and
closing commentary; some actions merged. U32 silently lost two committed gift
actions after narrative consolidation. Those are release-blocking failures, not
minor ambiguity. Other families showed wrong Today/Memory routes, detached
timing and purpose, reported words read as instructions, and withdrawals
applied to the wrong identity.

## Development work after the failed gate

- Explicitly numbered sequences now use their spoken ordinal boundaries before
  narrative consolidation. U33–U36 currently yield 10, 15, 20, and 25
  independently accessible Today rows, without a count cap. List lead and
  closing words remain in source quotes. The exact capacity family remains
  development evidence until a new unseen set is run.
- Capture-management speech and singular Memory scopes gained source ownership
  instead of automatically becoming rows. The development probe now gives U01
  five Today rows, U03 six Today rows, and U09–U12 one Memory row each. U03
  still places one action in review; these are not whole-capture passes.
- Resolved-choice pronouns can inherit one explicit chosen object. U32 now has
  separate "buy sketchbook" and "wrap sketchbook" Today actions; its remaining
  explanatory fragments still prevent whole-capture correctness. An ambiguous
  chosen object is held for review, while ordinary short pronoun tasks retain
  their established behavior.
- A local "I already called" correction no longer completes an older saved
  task when it retracts a uniquely matched spoken action. A shopping-list
  withdrawal can find its named product without erasing a Memory fact that
  merely mentions the same word. Operation reconstruction retains conjunction
  boundaries, and emphatic product needs such as "we do need eggs" route to
  Today. U17 and U19 remain incorrect as whole captures.
- Explicit propositional recording and described hypothetical quotations now
  route to Memory before action interpretation. U24 is currently one Memory
  row. An ordinal followed by a noun no longer fabricates a date ("second
  line"), while an ordinal date still works. A unique name in the immediately
  prior recorded fact can ground a direct "email her" follow-up; U25's action
  is now identified as email Rosa rather than held for review. A separate
  anaphoric request to remember a note attaches to its Memory antecedent.
  U25 and U27 still have excess Memory rows. Shared purpose and daypart
  attachment have improved, but U02, U04, and U21–U23 remain incorrect.
- The safety-procedure quotation U28 now has one Memory row and two Today
  actions in the development probe. The repair is structural: quote/source
  directives attach to the unique prior quoted Memory even across intervening
  actions; a "contact sheet" compound stays inside "update" while a real
  "contact Sarah" still opens a task; and a first-person promise to perform
  an action stays on Today. Third-party and discharged promises are controls.
- A recording frame that explicitly introduces a fact after a colon routes to
  Memory, while physical "keep the file" stays actionable. A completed-action
  report is now suppressed as an old-task operation only when the self-correction
  stage actually changed the transcript; an unrelated clock repair does not
  trigger that suppression. A broader local-identity audit is still needed.

After these edits, all four clear multi-task development captures have the
expected **row counts and Today/Memory routes**, as do the 10/15/20/25 capacity
captures. This is not whole-capture correctness: timing, source ownership, and
semantic content still require individual scoring. Natural rambling, mixed
Today + Memory, corrections, shared context, resolved alternatives, and
beginning/middle/end retention still show substantial row and routing failures.
The canonical 1,403-case corpus gate was clean after the edits above. The
September 24 full iOS simulator run had 873 passed, 25 failed, and 1 skipped;
several failures depended on NaturalLanguage's device tagging, while others
involved clause splitting, people, operation identity, and source ownership.
Focused iOS checks subsequently passed for fronted clauses, the "had better"
comparison/action distinction, alarm source ownership, and 25 individually
accessible actions both with and without spoken numbers. These focused checks
do not replace a new full suite run. No new unseen release gate has been run
on this tuned candidate.

All these observations use the rules-only host probe. It does not exercise
SwiftData persistence, optional model adjudication, live speech recognition,
microphone interruptions, or a physical iPhone. The earlier full simulator
unit suite was red; focused tests and the corpus gate do not replace it. The repaired-creation source ledger also
does not yet prove coverage of every raw word consumed by speech repair or
operation partitioning. These are open release conditions.

The next release decision requires freezing a revised production candidate,
an independent new unseen set and scorer, whole-capture correctness by family,
zero silent meaningful loss and unsafe execution, green app-level verification,
and hands-on microphone/device QA. The September 24 set must remain a regression
set and cannot serve as that new gate.

## September 25 development diagnostic (not a release score)

The integrated rules path was rerun on the now-exposed 40 captures after the
raw repair audit. Only **17/40** matched the expected row count and ordered
Today/Memory destinations; this deliberately weaker check does not score
meaning, timing, ownership, or whole-capture correctness. All four clear
multi-task captures, four coherent single memories, and four numbered capacity
captures matched on this limited check. Natural rambling and resolved
alternatives matched 0/4 each; beginning/middle/end retention matched 0/4.
The output contained 13 Needs Review rows across the set. This is useful for
clustering remaining failures, never a fresh launch gate.

The repeated failure shape is promoting source commentary and anaphoric
continuations into independent rows. It appears across rambling, shared
context, correction explanations, rejected alternatives, and end-of-capture
recaps. Several long narratives also split one Memory into separate facts
without a new recording request. The next mechanism should assign those spans
an owner or leave an explicit review hold; adding phrase-specific patches to
this exposed set would not establish general reliability.

Further development on September 24 reproduced two raw-loss/ownership defects
outside the frozen gate: an additive "actually I also need to..." deleted the
preceding action, and a reported instruction about keeping a form "for review"
was absorbed into a later unrelated task. The production-source probe and
focused iOS tests now preserve both meanings. A separate fronted-date control
also stopped a new Tuesday action from moving an earlier Monday action's date;
a same-target date restatement still corrects that target. These are regression
controls, not new independent validation. The current old-gate diagnostic still
has only 18/40 matching expected row counts and routes; whole-capture quality
is lower and has not been rescored for release. The last complete three-shard
iOS run had six failing tests on the second shard, concentrated in transport
name/person ambiguity and rendering invariance; the other two shards passed.
The full raw-source ledger, stable correction identities, directive target sets,
fresh unseen gate, and real microphone/device validation remain open.

Subsequent development (still using this set only as regression context) scopes
each self-correction to a local intention in a compound prefix, with a fronted
bare date carried by its action and an explicit completed-action report allowed
to target one uniquely matching earlier action. Report ownership is read on
the whole sentence before action-shaped coordination is split. New structural
controls distinguish a reported chain from a later direct instruction. Focused
iOS tests for these mechanisms pass, the canonical 1,403-case corpus gate is
clean, and the unsigned release build compiles. None of those checks replaces
raw-source disposition, the red full unit suite, an independently authored
unseen gate, or microphone/device QA. V1 remains blocked.
