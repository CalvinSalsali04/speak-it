# SpeechLab Phase 2 corpus

Phase 2 is a bounded, review-first corpus of 818 cases. It improves the draft
synthetic corpus's diversity and measurement discipline, but it is **not yet a
frozen evaluation set**. The authored snapshot remains in `data/cases.jsonl`;
the independent-review result is kept separately under `adjudication/`. No case
is called gold, and no production-parser result appears in its labels or
independent-review artifacts.

## Contents

- `data/semantic-families.jsonl`: the 260 historical IDs collapsed into 133
  value-agnostic product-behavior families, plus four public-pilot shapes.
- `data/blueprints.jsonl`: explicit semantic contracts for all 818 cases.
- `data/renderings.jsonl`: SpeechLab-compatible renderings.
- `data/cases.jsonl`: review state, provenance, structured lineage, quality
  assessment, safety requirements, and proposed split role.
- `review/independent-review-pack.jsonl`: blind semantic-review input. It does
  not expose parser output, pass/fail state, or requested parser changes.
- `public/source-records.jsonl`: the bounded 42-record text-only public pilot.
- `artifacts/quality-report.json`: complete machine-measured health report.
- `artifacts/saturation.json`: coverage at 100, 200, 400, 600, 800, and 818.
- `artifacts/split-manifest.json`: explicitly records that freezing is blocked.
- `adjudication/`: 1,332 schema-valid independent external-AI reviews, the
  adjudicated 818-case snapshot, assignment provenance, and complete metrics.

See [ADJUDICATION-REPORT.md](ADJUDICATION-REPORT.md) for the current decision,
[CORPUS-QUALITY-REPORT.md](CORPUS-QUALITY-REPORT.md) for the pre-review baseline,
[REVIEW-PROTOCOL.md](REVIEW-PROTOCOL.md) for adjudication, and
[REPRODUCE.md](REPRODUCE.md) for exact commands.

The subsequent repair work is under `repair/`. See
[`repair/REPAIR-REPORT.md`](repair/REPAIR-REPORT.md) for the 695-case strict
trust-closure result, [`repair/SCORING.md`](repair/SCORING.md) for role-specific
scoring, and [`repair/CONTRACT-GAPS.md`](repair/CONTRACT-GAPS.md) for the five
concepts deliberately left uncovered.

## Non-negotiable status

The corpus is useful for development and targeted remediation. It is not an
accuracy benchmark yet because:

1. 50 cases remain disputed, including 29 safety-critical cases without two
   independent positive reviews.
2. Independent review found an 11.49% conservative broken-language rate and a
   93.89% meaning-preservation rate; both miss their gates.
3. Five taxonomy IDs remain uncovered until the contract or available semantic
   shapes can represent them without inventing meaning.

Do not run the production parser against a future independent split before its
semantics are frozen.

The repair artifacts do not change that freeze decision. They establish a
high-trust 695-case scoreable subset, but the exact existing gate suite is 12 of
14 because the corpus is now below 800 and fewer than 300 weakly composed
multi-phenomenon cases remain. The subset is therefore versioned and hashed but
not frozen or sealed.
