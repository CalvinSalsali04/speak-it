# Development sets

Where rules are worked out. **Not a gate, and not held out.**

```bash
./Tools/CorpusRunner/devsets/score.sh coordination [--verbose]
./Tools/CorpusRunner/devsets/route-score.sh routed [--verbose]
```

These exist so that `../heldout/` never has to be opened during development.
The held-out set answers one question — did this generalise past the examples
it was designed against — and it can only answer it once per change, and only
if nobody looked. Iterating needs somewhere else to iterate.

| set | unit | scored by | what it measures |
|---|---|---|---|
| `coordination.tsv` | `probe --clauses` | `score.py` | where clause boundaries fall |
| `routed.tsv` | full rules path | `../heldout/score.py` | destination, and unsafe action on an ambiguous capture |

`routed.tsv` is deliberately scored by the **held-out scorer**, on the same five
columns, so the number being developed against is the same number being reported
at the end. Only the data differs.

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
