# Development sets

Where rules are worked out. **Not a gate, and not held out.**

```bash
./Tools/CorpusRunner/devsets/score.sh coordination [--verbose]
./Tools/CorpusRunner/devsets/route-score.sh routed [--verbose]
./Tools/CorpusRunner/devsets/route-score.sh framing [--verbose]
./Tools/CorpusRunner/devsets/unfinished-score.sh [--verbose]
./Tools/CorpusRunner/devsets/abandonment-score.sh [--verbose]
```

These exist so that `../heldout/` never has to be opened during development.
The held-out set answers one question — did this generalise past the examples
it was designed against — and it can only answer it once per change, and only
if nobody looked. Iterating needs somewhere else to iterate.

| set | unit | scored by | what it measures |
|---|---|---|---|
| `coordination.tsv` | `probe --clauses` | `score.py` | where clause boundaries fall |
| `routed.tsv` | full rules path | `../heldout/score.py` | destination, and unsafe action on an ambiguous capture |
| `framing.tsv` | full rules path | `../heldout/score.py` | whether the frame around speech is read as frame: sign-offs, enumeration |
| `unfinished.tsv` | full rules path | `unfinished-score.py` | whether a thought was finished at all |
| `abandonment.tsv` | full rules path | `abandonment-score.py` | whether "never mind" was this speaker taking this thought back |

`framing.tsv` was written from the everyday set's per-family *rates* — `run-on`
0/8, `rambling-intro` 1/6, `trailing-goodbye` 2/7, `sequencing` 6/17 — and from
no capture in it. A rate says which family to look at; a sentence would have
ended the set's usefulness.

`routed.tsv` and `framing.tsv` are deliberately scored by the **held-out
scorer**, on the same five columns, so the number being developed against is the
same number being reported at the end. Only the data differs.

## Reading the coordination set

The unit is `splitClauses` rather than the finished rows, because the shopping
grouper splits one product list into several rows and would otherwise drown the
signal. `over` and `under` are counted apart: an over-split invents a row, an
under-split buries a thought inside another one, and they are not the same
defect.

## The labels are not sacred

Several expectations in `routed.tsv` were wrong on the first pass — the gating
corpus already settles that "Dentist next Monday" is a dated event and that
"Remind me tomorrow" schedules at the default hour, and the labels said
otherwise. They were corrected against the corpus, which is the product
contract; the app was not changed to match a label. When a case here disagrees
with a gating corpus case, the corpus wins and the label is the bug.

Two rows are expected to fail and are kept anyway: `DO02` and `DO03` ask for
"delete the reminder to call Dave" and "remove the dentist appointment" to be
recognised as operations. They are not, and they fail closed to a Memory row
that nothing acts on. Widening the destructive vocabulary to close them would
trade a safe gap for an unsafe one.

## Why abandonment is its own file

`unfinished.tsv` asks whether a sentence stopped. `abandonment.tsv` asks
whether the person then said so. They are different questions with different
failure modes, and folding the second into the first would have moved the
denominators the unfinished floor is quoted against — 34/57 recall, 0/96
fallout, 2 unsafe — which is exactly the number a release is checked on.

Its fallout column is the one to read. Every row under `ordinary-content` is a
sentence that contains a withdrawal word and is not a withdrawal: "I need to
forget it", "remind me to scratch that off the list". The first version of the
rule that fixed the release blocker destroyed all of them, because it asked
whether the words in front of the marker looked unfinished — and they always
do, once you take the marker off the end. Those rows exist so that never
happens quietly.
