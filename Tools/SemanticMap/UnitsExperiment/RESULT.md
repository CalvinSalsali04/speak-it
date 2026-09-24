# Semantic-unit experiment: result

**Outcome C: neither candidate is good enough.** Production semantics stay
exactly as they are, and the semantic map stays diagnostic-only for V1. No
hybrid is proposed.

This is development evidence on 30 existing captures, not launch accuracy.

## The run

- One run on an Apple Intelligence Mac at the pinned commit `09a9eed`, with
  no edits and no retries. It used en_CA, greedy sampling and a 4096-token
  context. Evidence: `evidence/20260923-200122/`.
- All 21 steps passed:
  - the clean tree and all 11 MANIFEST hashes;
  - regenerated inputs, both selftests and the precheck;
  - the Swift build;
  - model availability;
  - 60 records written, then scored and decided.
- The live prompt fingerprints match the pinned ones: ranges `df4c6e25`,
  labels `71e026b5`.
- Gold is `d8d4a436…6d345c`, and `results.jsonl` is `4c070543…c2bbd`.
- The run is valid. The only skip is labels on RB14C, a one-line capture
  skipped as `tooShortToSplit`, which is allowed. There were no generation
  errors.
- `score.txt` and `decision.txt` were recomputed from `results.jsonl` in a
  second environment. The body of `score.txt` below its hash header and all of
  `decision.txt` came out byte for byte identical.

## Whole-capture exactness

| arm | exact, view `any` | exact, view `own` | multi-unit exact (`any`, 14) |
|---|---|---|---|
| Candidate 1, ranges | 12/30 | 9/30 | 0/14 |
| Candidate 2, labels | 16/30 | 12/30 | 0/14 |
| constant "one unit" | 16/30 | 12/30 | 0/14 |
| constant "every line starts" | 5/30 | 5/30 | 4/14 |

## The gates each candidate failed

**Candidate 1 (ranges)** failed three gates:
- Material gain: 12 − 16 in view `any`, and 9 − 12 in view `own`.
- Multi-unit recovery: 0 of 14.
- Broken single units: 4, which are RB17R, RB31C, RB31R and RB41R.

It passed the rest: silent cuts were 2 (RB21R, CAP14), there were no
guarded-family cuts, and it beat every-line.

**Candidate 2 (labels)** failed two gates:
- Material gain: 0 in both views.
- Multi-unit recovery: 0 of 14.

It passed every safety gate, and representability was 30/30.

## Mechanisms, from the raw outputs

- **Labels is the constant.** All 29 answered captures came back as
  `starts, continues, continues, …`. So labels equals the one-unit answer on
  every capture, and its boundary recall is 0 of 59.
- **Ranges almost always opens with the whole capture.** 28 of 30 answers
  begin with the range from the first atom to the last:
  - 17 stop there, which is one unit.
  - 6 add the last atom again as a one-atom unit, which overlaps and is
    malformed: RB17R, RB29C, RB30C, RB31C, RB31R, RB41R.
  - 5 add further ranges after the whole range, which overlap it and are
    malformed: RB28C, RB28R, RB29R, RB30R, CAP25. CAP25's extra ranges are a
    stride-one count loop.

  The two answers that do not open with the whole capture are these:
  - RB21R: 4 units against gold's 2, including a one-atom unit.
  - CAP14: 2 units against gold's 14, one of which is a single atom.

  Boundary recall is 1 of 60.
- **No answer from either arm dropped source.** Neither arm has a string field,
  so neither can author wording, dates, people or operations.
- The overlapping answers are scored malformed under the pinned rule. Removing
  the leading whole range and scoring what remains would be tuning against
  candidate output, so it was not done.

## Latency and tokens

| arm | latency p50 | latency p90 | latency max | response tokens p50 / max |
|---|---|---|---|---|
| ranges | 1,067 ms | 2,697 ms | 6,802 ms | 19 / 304 |
| labels | 2,161 ms | 3,782 ms | 7,175 ms | 76 / 319 |

## Capacity

- CAP25 (25 gold units):
  - ranges is malformed. It opens with the whole range, followed by a count
    loop, and it hit the schema maximum of 20.
  - labels is under-split. It answered one unit.
- Neither arm truncated silently.

## What this means

- Given this segmentation job alone, the on-device model does not recover
  semantic units on this set. In either representation it defaults to "the
  whole capture is one thought".
- Every gate that failed is a recovery gate. No safety gate failed except
  ranges breaking four single units.
- `DECISION_PLAN.md` §4 applies:
  - Production is unchanged.
  - No production semantic change is expected before the V1 freeze.
  - The semantic map stays diagnostic-only.
  - No third contract is proposed.
