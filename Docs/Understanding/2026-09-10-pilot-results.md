# Public-data pilot: results

Implemented a reproducible local lab using 300 English MASSIVE requests, 24 authored blurb contracts, and controlled hesitation/capitalization variants. The pilot is explicitly pinned to `public.jsonl` and `authored.jsonl`; other dataset imports do not belong to these numbers.

| Measure | Before | After |
|---|---:|---:|
| Development: semantic consistency | 719/757 (95.0%) | 744/757 (98.3%) |
| Development: title consistency | 708/757 (93.5%) | 739/757 (97.6%) |
| Authored contracts, including variants | 66/72 | 72/72 |
| Reserved public sources: semantic consistency | 171/179 (95.5%) | 173/179 (96.6%) |
| Reserved public sources: title consistency | 171/179 (95.5%) | 173/179 (96.6%) |

Development comprises 240 public sources plus 24 authored sources, yielding 1,021 distinct captures. The reserved cohort contains 60 public sources and 179 variant comparisons; these are correlated variations, not 179 independent people. No evaluation text or individual evaluation failure was used to develop these fixes. Reserved scores are filtered to the same three intent families because another dataset was added alongside the pilot during execution.

The existing 1,381-case corpus remains entirely clean. Focused Swift tests passed; the lab's 10 Python instrument tests passed. The older independent 389-capture benchmark remains at 233/320 correct routes, 255/310 correct counts, seven of 69 ambiguous captures acted on, and zero missing outputs. Those scores have not improved in this change.

## Product fixes

- A hesitation before a command complement no longer leaves a comma that disables a reminder: “set alarm, um, for one hour from now” retains the same trigger as fluent speech.
- An explicit numbered introduction is recognized after its fillers are removed, so “Um, Today we…” and “Today we, um, have…” behave like the fluent blurb.
- Spoken contractions and negators keep their complements attached: “I wanna, um, get up…” stays one intention; “Do not, um, call Maya” retains its cancellation target. The probe only detects cancellation; persistence handles whether there is a matching item.

There were no newly failing development checks: 25 semantic inconsistencies and 31 title inconsistencies were resolved. Thirteen semantic and 18 title inconsistencies remain; some overlap.

## What the data does and does not establish

This is an implemented evaluation-and-repair loop, not trained model weights. Public source labels remain separate from Speak It correctness contracts. A phrase can produce the same wrong answer consistently. For example, a fluent alarm can still have an awkward display title even when its trigger survives every tested variation.

The authored negation contracts were checked against the existing product contract before scoring: a refusal detects cancellation, rather than creating a new Memory item directly. These are assistant-reviewed expectations, not a claim of human annotation.

Next development priorities are remaining hesitation boundaries around reminder lead times, command particles, and person lists. Separately, adjudicate representative public requests into full Speak It contracts—including expected times—so the lab can test correctness beyond the authored examples. Use a fresh evaluation cohort for a larger tuning cycle. PRESTO and real permissioned recordings remain future inputs; they were not imported or used for these scores.

## Reproduce

See `Tools/UnderstandingLab/README.md`. Commands pin this cohort even when other record sets are added. The machine-readable sibling report records dataset and probe hashes. No paid inference, external model training, or user-capture upload was started.
