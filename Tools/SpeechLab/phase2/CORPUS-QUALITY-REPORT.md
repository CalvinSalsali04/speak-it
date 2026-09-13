# Phase 2 corpus-quality report

## Decision

The 818-case corpus is a substantially healthier **adjudication candidate**,
but it is not ready to freeze and must not scale to 10,000. Twelve of fourteen
automated gates pass. The two failed gates are decisive: there is no independent
semantic review, and none of the 514 safety-critical cases has the required two
independent approvals.

No production parser was invoked, no parser output was used as truth, and no
sealed failure content was read.

## Corpus and lineage

- Historical input: 260 blueprint IDs.
- Historical bookkeeping removed: 133 value-agnostic product-behavior families.
- Public pilot additions: four genuinely new semantic shapes.
- Final semantic-family count: 137.
- Cases: 818, each with a distinct semantic blueprint and structured lineage.
- Build mix: 266 core, 190 single-phenomenon, 250 pairs, 56 triads, 14 four-way
  compositions, and 42 public-derived cases.
- Average phenomena per case: 1.117.
- Multi-phenomenon cases: 320 (39.1%).
- Covered taxonomy IDs: 78 of 83; uncovered IDs are `conditional-intent`,
  `conjunction-ambiguity`, `self-correction-quantity`, `shared-object`, and
  `unresolved-alternative`.
- Distinct observed phenomenon pairs: 410.

Composition is ordered semantic/context → structure → repair → discourse → ASR.
The engine rejects incompatible semantics, reversed ordering, unclear
cancellation context, unresolved pronouns under an act policy, destructive ASR
on safety-critical meaning, and punctuation noise that would erase correction
boundaries. A realization check verifies that high-risk labels are actually
visible in the utterance/context. Lossy/high-risk transforms are isolated rather
than repeatedly compounded.

## Provenance and label confidence

| Provenance | Cases |
|---|---:|
| Repository-authored | 776 |
| PRESTO | 12 |
| MASSIVE | 10 |
| SLURP text | 10 |
| Taskmaster | 10 |

| Label state | Cases |
|---|---:|
| Machine-reviewed | 796 |
| Draft | 22 |
| Independently reviewed | 0 |
| Human reviewed | 0 |
| Trusted | 0 |

The 22 draft cases are deliberately lossy or ambiguity-sensitive. No item is
called gold.

## Naturalness and semantic preservation

| Naturalness | Count |
|---:|---:|
| 1 | 0 |
| 2 | 0 |
| 3 | 227 |
| 4 | 546 |
| 5 | 45 |

Author self-review places 72.2% at 4 or 5 and 0% at 1 or 2. The corresponding
machine-assessed broken-language rate is 0%. A small rule-based language lint
suite reports zero known malformed patterns, but neither measure is independent;
both must be replaced or confirmed during adjudication.

Meaning preservation is `appears_preserved` for 796 cases and `uncertain` for
22, a 97.3% author self-review preservation rate. This clears the numerical 95%
direction but not the evidentiary requirement for an audited preservation rate.

## Duplicate and template health

- Exact unique texts: 818/818.
- Normalized duplicate groups: 0.
- Jaccard ≥ 0.80 lexical pairs: 1 pair affecting 2 records (0.24%).
- Structural templates: 816.
- Structural near-duplicate groups: 2, affecting 4 records.
- Largest structural template: 2 records (0.24%).
- Largest semantic-family share: 1.71% (maximum 14 cases; median 6).
- Renderings copying all expected facts verbatim: 6 (0.73%), down from 96.9%.

The very high structural-template count comes from the declared function-word
skeleton metric. It should be complemented by embeddings or a linguist-reviewed
template clustering pass before a future freeze; it is not proof of 816 wholly
independent syntactic structures.

## Entity and value diversity

- People: 50 unique; most frequent appears 22 times.
- Locations: 34 unique; most frequent appears 15 times.
- Date expressions: 39 unique; most frequent appears 35 times.
- Times: 27 unique; most frequent appears 25 times.
- Recurrences: 6 unique; most frequent appears 9 times.

The phrase plans cover school, work, shopping, errands, relationships, travel,
appointments, chores, food, finances, ideas, memories, people facts, plans, and
follow-ups. Product/business variety is carried in action facts and locations,
but is not yet a first-class entity field and therefore needs a future dedicated
metric.

## Safety and splits

There are 514 safety-critical cases. Zero are trusted and all 514 await two
independent positive reviews. Primary proposed roles are 489 safety, 176
development, 111 synthetic stress, and 42 public-derived. Regression and
independent-evaluation splits remain empty. The split manifest is not frozen.

## Saturation

| Cases | Coverage units | New units | Marginal units/case | Families | Phenomena | Pairs | Structural templates |
|---:|---:|---:|---:|---:|---:|---:|---:|
| 100 | 205 | 205 | 2.050 | 100 | 0 | 0 | 100 |
| 200 | 338 | 133 | 1.330 | 133 | 0 | 0 | 200 |
| 400 | 615 | 277 | 1.385 | 133 | 78 | 0 | 399 |
| 600 | 959 | 344 | 1.720 | 133 | 78 | 144 | 599 |
| 800 | 1,426 | 467 | 2.335 | 134 | 78 | 410 | 799 |
| 818 | 1,446 | 20 | 1.111 | 137 | 78 | 410 | 816 |

The curve does not flatten by 600 because pair selection begins later in the
ordered corpus; it is a composition-plan diagnostic, not evidence that 10,000
examples will add value. The final 18 public records add four semantic families
but no new phenomenon pairs. A future analysis should randomize or stratify
ordering and measure adjudicated coverage, not just authored coverage.

## Remaining gaps

1. Independent review is completely absent.
2. Safety review workload is large: 1,028 distinct positive review decisions are
   required if every current safety case is retained.
3. Five taxonomy concepts cannot yet be represented honestly by the available
   contracts/shapes; they remain measured gaps rather than fabricated coverage.
4. Naturalness and preservation numbers are author self-assessments.
5. Timezone and DST have only one case each.
6. Cross-turn resolution and contact ambiguity remain thin.
7. No audio/ASR evaluation method or audio license decision exists.
8. Product and business names are not structured entities in the contract.
9. The public pilot is English-only and still awaiting independent mapping
   review.

## Freeze and scale recommendation

Do not freeze this snapshot. Send the blind review pack to independent reviewers,
resolve disputes, remove or rewrite low-naturalness cases, then rerun the gates.
Do not evaluate the independent split with the production parser until labels
are frozen.

Do not scale to 10,000. The corpus is correctly bounded at 818 until independent
evidence—not generator confidence—shows that the measuring instrument is
trustworthy.
