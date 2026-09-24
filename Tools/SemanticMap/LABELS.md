# Fresh evaluation slice: label schema and authoring protocol

This is the Phase 5 slice `score.py whole` reads. It measures whether Speak It
understands speech its developers did not write, so **who writes it, and when,
matters more than what is in it.**

## Who and when

1. The slice is written **after** the semantic-map architecture is frozen. The
   freeze is a commit, named in `Docs/SEMANTIC_MAP_ARCHITECTURE.md`; nothing
   under `Tools/SemanticMap/Sources/` or the prompts changes after it without
   the slice being declared spent.
2. Its author is **not** the thread that built the architecture, and has not
   read `Arbiter.swift`, the job prompts, the development sets or Astra's
   long-blurb findings while writing. The coordinator assigns the author.
3. The author writes captures the way a person talks to a phone: from real
   situations they can picture, not from the phenomenon list below. The
   categories are for *balance after writing*, not templates to fill. No
   capture may be a rewrite of a development-set row, a document example or a
   sentence in this repository (`leak-check.py` and a character-overlap scan
   are run before the file is committed, as for `rambling.tsv`).
4. Labels are written from the capture alone, before anyone runs any arm on
   it. A label is never edited after a score has been seen; a label found to be
   wrong is recorded in the file's header with the date and the reason, and the
   capture is scored both ways.
5. The file is committed under `Tools/SemanticMap/fresh/` with its SHA-256 in
   the commit message. It is **sealed**: only `score.py whole` without `--ids`
   is run on it by default, and nobody reads per-capture results while the
   architecture can still change.

## Size and balance

Ten categories, scored separately, never averaged into one number:

| code | category | what makes a capture belong |
| --- | --- | --- |
| A | short simple captures | one or two intentions, under about 12 words |
| B | clear multi-task long captures | three or more separate intentions, said plainly |
| C | natural rambling long captures | the same, with restarts, filler, asides, trailing off |
| D | coherent long single thoughts | one idea or memory, long, that must stay one row |
| E | mixed task + memory captures | at least one Today intention and one Memory one |
| F | corrections / withdrawals | something said, then changed or taken back |
| G | quoted / reported speech | somebody else's words, or a message's contents |
| H | entity-context ambiguity | names that may be people, organizations, places, topics or roles |
| I | conditions and location scope | "if", "when I get to", "unless", and what they govern |
| J | beginning / middle / end retention | long captures whose first, middle and last intentions all have to survive |

About 20 captures per category is enough to see a family fail and small
enough that a person can label it carefully in a sitting. Every capture also
carries a free `family` tag naming the phenomenon in the author's own words, so
a failure names what caused it.

## Schema

One JSON object per line (`fresh/slice.jsonl`):

```json
{
  "id": "FS-C-007",
  "category": "C",
  "family": "rambling-errands",
  "utterance": "the capture exactly as it would reach the parser",
  "ambiguous": false,
  "thoughts": [
    {
      "words": "the words of this intention as spoken",
      "destination": "Today",
      "timed": true,
      "located": false,
      "person": null,
      "review_ok": false
    }
  ],
  "operations": [{"kind": "cancel"}],
  "must_not_execute": [{"words": "the words that must never schedule", "why": "quoted"}],
  "ignorable": ["words a row may carry without counting as invented, such as a sign-off"]
}
```

- `thoughts` lists every **user-visible row** a careful reader expects, in
  spoken order. Its length is the expected row count; a coherent long memory
  is one thought.
- `words` is taken verbatim from the utterance. Scoring matches a row to a
  thought when the row carries at least 60% of the thought's content words.
- `destination` is `Today` or `Memory`.
- `timed` is true when the row should carry a due date or a reminder;
  `located` when it should carry a place trigger. These are the temporal and
  shared-scope measures.
- `person` is present only when the label takes a position: a name, or
  `null` for "this row must not have a person" (the entity measure, category
  H's main question). Omit it when either answer is acceptable.
- `review_ok` is true when a Needs Review flag on this row is the right
  answer. A flag on a row without it counts as unnecessary review.
- `operations` lists the operations the capture should produce (`cancel`,
  `complete`, `reschedule`, `retract`), usually none.
- `must_not_execute` lists spans that must never produce a reminder, date,
  place trigger or recurrence, with `why` one of `quoted`, `reported`,
  `condition`, `correction`, `withdrawal`, `negated`. Any executing row
  carrying one is an **unsafe executable**, the P0 measure.
- `ambiguous` marks a capture a careful human could not pin down: the only
  correct answer is to keep it and act on nothing.

## What the scorer reports

`score.py whole fresh/slice.jsonl --report ARM.report [--runs runs.jsonl]`,
once per arm (`rules`, `production`, `map`, and each `--policy` ablation):

- **WHOLE CAPTURE CORRECT** per category, per family and per length bucket.
- Beside it, captures failing each measure: lost intention, invented
  intention, split, merge, correction target, shared scope, quote ownership,
  entity type, temporal attachment, routing, unsafe executable, unnecessary
  review.
- With `--runs`: map invocation, accepted contribution (output changed) and
  fallback (rules reading kept), and production's invocation and acceptance.
- Latency by length bucket comes from `score.py trace` on the same run.

There is deliberately no overall row. A category is read on its own
denominator, and a change that helps B and hurts G is two findings.
