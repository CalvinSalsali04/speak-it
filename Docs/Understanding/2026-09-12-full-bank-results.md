# All two million cases evaluated

The complete `synthetic-v1` bank has been evaluated with one frozen rules-pipeline binary. An independent checkpoint audit verified **every index from 0 through 1,999,999 exactly once**, with no gaps or overlap. All 19,985 stored blocks passed the database integrity and aggregate checks. The archive's two million records were also checked against the generator and its recorded SHA-256 before execution.

| Measure | Result |
|---|---:|
| Evaluated cases | 2,000,000 / 2,000,000 |
| Semantic consistency | 1,866,834 / 2,000,000 (93.3417%) |
| Semantic disagreements | 133,166 (6.6583%) |
| Normalized title consistency | 2,000,000 / 2,000,000 (100%) |
| Missing coverage | 0 |

These scores compare clean wording with controlled hesitation or lowercase variants. They do **not** measure independent human accuracy: two consistently wrong outputs can pass. Title comparison ignores case and punctuation. The bank contains eight structural templates and four noise styles, not two million independently authored scenarios. No model weights were trained, no paid inference API was used, and Apple Foundation Models refinement was not exercised by this rules-only probe.

## Where disagreements concentrate

| Frame / perturbation | Cases |
|---|---:|
| Memory followed by errand / lowercase | 62,501 |
| Tomorrow call followed by errand / internal hesitation | 45,125 |
| Errand followed by email / lowercase | 6,636 |
| Call followed by errand / lowercase | 4,711 |
| Errand followed by call / lowercase | 4,703 |
| Tomorrow call followed by errand / lowercase | 4,694 |
| Conditional call followed by errand / lowercase | 2,609 |
| Separately dated call and errand / lowercase | 2,187 |

These are eight test buckets, not necessarily eight independent bugs. The existing development triage points first to lowercase two-word name recognition and punctuation left by hesitation immediately after a communication verb. The prior sentence-boundary fix already restored the lost tasks; the remaining Memory disagreement includes person metadata. Future repairs should replay focused before/after cases and guard against false person matches, unintended reminders, and changed negation. A full bank replay is unnecessary for every small experiment.

## Execution and evidence

Four local workers processed bounded blocks, with each completed interval committed to SQLite. The run reused 1,600 previously evaluated cases on the identical binary and executed the remaining 1,998,400. Earlier results on the older binary were preserved separately and were not counted in these totals. The parser was frozen throughout the run; no production changes were made during evaluation.

The runner's tests cover incomplete and duplicate probe outputs, overlapping ranges, and completion only with contiguous coverage. All 18 lab instrument tests passed during setup. Existing app regression results are documented in the preceding sentence-boundary report; those unchanged suites were not rerun just for volume.

Evidence lives in `output/understanding-scale/full-run/`: `summary.json`, `coverage-audit.json`, `checkpoints.sqlite`, `config.json`, the frozen `probe`, and up to three representative failures per bucket. The original pilot state is `reused-pilot-progress.json`. The parent campaign cursor has been migrated to the audited complete state so its older batch command cannot accidentally repeat completed IDs. The machine-readable sibling of this report records the binary and archive hashes.
