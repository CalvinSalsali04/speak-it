# SpeechLab Phase 2 corpus

Phase 2 is a bounded, review-first corpus of 818 cases. It improves the draft
synthetic corpus's diversity and measurement discipline, but it is **not yet a
frozen or trusted evaluation set**. The corpus has author self-review only. No
case is called gold, and no production-parser result appears in its labels or
independent-review pack.

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

See [CORPUS-QUALITY-REPORT.md](CORPUS-QUALITY-REPORT.md) for the decision,
[REVIEW-PROTOCOL.md](REVIEW-PROTOCOL.md) for adjudication, and
[REPRODUCE.md](REPRODUCE.md) for exact commands.

## Non-negotiable status

The corpus is useful for development and independent review. It is not an
accuracy benchmark yet because:

1. 514 safety-critical cases await two independent positive reviews each.
2. No case has an independent semantic review in this repository snapshot.
3. Twenty-two deliberately lossy or ambiguity-sensitive cases remain draft.
4. Five taxonomy IDs remain uncovered until the contract or available semantic
   shapes can represent them without inventing meaning.

Do not run the production parser before freezing a future independent split.
