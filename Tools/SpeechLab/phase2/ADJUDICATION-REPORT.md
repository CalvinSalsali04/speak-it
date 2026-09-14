# Phase 2 independent-adjudication report

## Decision

The independent review round is complete, but the corpus is **not ready to
freeze** and scaling to 10,000 is **not justified**. Ten of fourteen quality
gates pass. The completed review found 50 disputed cases, a 93.89% audited
meaning-preservation rate, and an 11.49% conservative broken-language rate.

No production parser was invoked or exposed to reviewers. No sealed failure
was read. Reviewers did not inspect one another's decisions, and author
self-review was not counted as independent evidence. Nothing is called gold.

## Review method and provenance

Three isolated external-AI reviewer sessions used the existing blind review
pack and the naturalness and review rubrics. They saw utterance, relevant
context, proposed semantic contract, taxonomy labels, and neutral review
questions. They did not see parser output, generator source, sealed failures,
or another reviewer's output.

| Reviewer identity | Source | Assigned and completed |
|---|---|---:|
| `codex-blind-reviewer-a-20260914` | external AI | 442 |
| `codex-blind-reviewer-b-20260914` | external AI | 445 |
| `codex-blind-reviewer-c-20260914` | external AI | 445 |

All 1,332 required review records compiled against the review schema. Every
ordinary case received one independent review. Every safety-critical case
received two reviews from distinct identities. These are external-AI reviews,
not human reviews.

## Outcomes

| Outcome | Cases |
|---|---:|
| Independently reviewed | 818 |
| Completed required review count | 818 |
| Trusted | 768 |
| Disputed | 50 |
| Rejected | 0 |
| Removed | 0 |
| Final corpus size | 818 |

The 50 disputes remain in the adjudicated artifact with `trusted=false`.
Disagreement was not converted into consensus or rejection. Of the trusted
cases, 485 are safety-critical and 283 are ordinary.

### Safety review completion

| Completed independent reviews | Safety cases |
|---:|---:|
| 0 | 0 |
| 1 | 0 |
| 2 | 514 |

Completion alone is not approval. The positive-review distribution is 14
safety cases with zero positive reviews, 15 with one positive review, and 485
with two positive reviews. The remaining 29 safety cases therefore block the
safety trust gate.

## Naturalness after independent review

The case-level score is the lower median of independent ratings. This is
conservative for the two-review safety cases and avoids averaging away a low
rating.

| Score | Cases |
|---:|---:|
| 1 | 2 |
| 2 | 92 |
| 3 | 334 |
| 4 | 361 |
| 5 | 29 |

Only 390 cases (47.68%) score 4 or 5, so the majority-4-or-5 gate fails. The 94
cases scored 1 or 2 produce an audited broken-or-implausible rate of 11.49%,
above the 5% limit. Across all 1,332 individual assessments, the distribution
is 2 score-1, 105 score-2, 475 score-3, 663 score-4, and 87 score-5 ratings.

## Meaning and label changes

Required independent reviews marked meaning preserved for 768 of 818 cases,
an audited rate of 93.89%. The proposed contract was independently affirmed for
the same 768 cases; 43 received at least one `no` contract judgment and seven
received an `uncertain` judgment.

Adjudication changed a semantic assessment on 489 cases: 462 case-level
naturalness scores changed and 56 meaning-preservation states changed (some
cases changed both). Meaning-preservation transitions were:

| Before | After | Cases |
|---|---|---:|
| appears preserved | appears preserved | 759 |
| appears preserved | meaning changed | 29 |
| appears preserved | uncertain | 8 |
| uncertain | appears preserved | 9 |
| uncertain | meaning changed | 10 |
| uncertain | uncertain | 3 |

All 818 confidence states changed because independent evidence replaced the
author snapshot: 759 machine-reviewed and nine draft cases became independently
reviewed; 37 machine-reviewed and 13 draft cases became disputed. Reviewer
verdicts differed on 17 cases, and naturalness ratings differed on 255 cases.
The complete per-case changes and uncollapsed reviews are retained in
`adjudication/report.json` and `adjudication/cases-adjudicated.jsonl`.

## Quality gate

Ten of fourteen gates pass. The four failures are:

1. independent naturalness is not majority score 4 or 5;
2. audited broken-language rate is not below 5%;
3. audited meaning preservation is not at least 95%;
4. not every safety case has two independent positive reviews.

Independent-review completion itself passes. Duplicate, structural-template,
fact-copy, language-lint, provenance, interaction-coverage, and saturation
checks continue to pass. The split remains unfrozen, and parser evaluation must
not be joined to these labels yet.

## Deliberately uncovered concepts

The five concepts remain measured gaps. No weak examples were added after the
review round:

- `conditional-intent` needs a contract field for a condition and its scope;
- `conjunction-ambiguity` needs an explicit representation of alternative
  conjunction parses;
- `self-correction-quantity` needs a structured quantity field;
- `shared-object` needs a shared object/reference field rather than hiding the
  object in free text;
- `unresolved-alternative` needs an explicit unresolved-alternative contract
  shape and adjudication policy.

Adding surface phrases without those semantics would create nominal 83/83
coverage while weakening label truth. Contract support and a new blind review
round should precede coverage credit.

## Recommendation

Do not freeze and do not scale. First remediate or remove the 50 disputed cases
and the independently identified low-naturalness cases, review those revisions
blindly, and rerun all fourteen gates. Parser optimization and sealed-failure
inspection remain out of scope during that work.
