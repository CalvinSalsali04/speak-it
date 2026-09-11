# Adversarial held-out set — phenomena in combination

120 captures, 12 in each of 10 pairings. **Nothing here has been tuned against,
and nothing here may be tuned against.**

```bash
./Tools/CorpusRunner/adversarial/score.sh          # the numbers
```

## What this set asks that the others do not

The repository already holds two sealed sets, and this is a third axis rather
than more of either.

| set | held out by | what it varies |
|---|---|---|
| `heldout/` (389) | mechanism | one phenomenon per capture — homophone, name-as-noun, negation, ellipsis |
| `everyday/` (255) | content | ordinary life speech; phenomena co-occur only where real speech happens to |
| `adversarial/` (120) | **interaction** | two phenomena deliberately compounded in one capture |

`heldout.tsv` is strictly one family tag per row — all 389 of them. That is a
deliberate design and it makes the set readable: a failure names the phenomenon
that caused it. But it means nothing in the repository asks whether the
pipeline's layers **compose**.

That question is the point of this set. Every pairing here is built from two
ingredients that `heldout/` already measures separately. So when a pairing
scores badly while both its ingredients score well alone, the finding is not
"the parser cannot do negation" — it is "the parser can do negation and can do
multi-task, but not at the same time". That is evidence about architecture,
and it is the kind of evidence Speak It's charter asks for before heuristics
are added.

The reverse reading matters too and is the honest caveat: if an ingredient
scores badly on its own in `heldout/`, a bad score here tells you nothing new.
**Read a pairing against its ingredients, never on its own.**

That instruction was not executable until 2026-09-11. `heldout.tsv` carries
exactly one family tag per row so that a failure names its phenomenon, and its
scorer read that column and dropped it, printing four aggregate numbers. It now
prints a per-family table — rates only, still sealed, still non-verbose — so an
ingredient can actually be looked up.

### And check the lengths before comparing

A pairing and its ingredient have to be comparable **inputs**, not just share a
name. The first reading made that concrete. `runon-x-repair` scored 8/12 on
routing where the everyday `run-on` family scored 0/8, which looks like
combination being *easier* than its ingredient. It is not: that pairing was
written at roughly half the length, over a range that does not overlap its
ingredient's at any point.

**A pairing whose length range is disjoint from its ingredient's cannot be read
against that ingredient.** That is the one hard rule here, and it is mechanical
rather than remembered: `ComparabilityTests` in `../everyday/test_score.py`
fails if a capture is edited into a new unreadable comparison, and fails just
as loudly if a declared one is fixed and the list left stale. Regenerate the
table with

```bash
python3 Tools/CorpusRunner/adversarial/lengths.py
```

| pairing | median words | ingredient | in | n | median | range | comparable? |
|---|---|---|---|---|---|---|---|
| `brand-x-multi` | 8 (7–9) | `brand-verb` | `heldout/` | 15 | 6 | 4–8 | 1.3× longer |
|  |  | `multi-task` | `heldout/` | 12 | 11.5 | 6–15 | 0.7× shorter |
| `cond-x-negation` | 10 (7–11) | `conditional` | `heldout/` | 8 | 8 | 6–9 | 1.2× longer |
|  |  | `negation` | `heldout/` | 12 | 4.5 | 3–9 | 2.2× longer |
|  |  | `negation` | `everyday/` | 51 | 9 | 5–16 | 1.1× longer |
| `ellipsis-x-date` | 6 (4–10) | `ellipsis` | `heldout/` | 12 | 3 | 2–6 | 2.0× longer |
|  |  | `multi-date` | `heldout/` | 12 | 8.5 | 6–11 | 0.7× shorter |
| `idiom-x-op` | 4 (3–7) | `idiom` | `heldout/` | 12 | 6 | 2–10 | 0.7× shorter |
|  |  | `operation` | `heldout/` | 12 | 5.5 | 3–12 | 0.7× shorter |
|  |  | `operation` | `everyday/` | 10 | 9.5 | 7–12 | 0.4× shorter |
| `negation-x-multi` | 11 (7–14) | `multi-task` | `heldout/` | 12 | 11.5 | 6–15 | 1.0× |
|  |  | `negation` | `heldout/` | 12 | 4.5 | 3–9 | 2.4× longer |
|  |  | `negation` | `everyday/` | 51 | 9 | 5–16 | 1.2× longer |
| `nottime-x-date` | 8.5 (7–13) | `date` | `everyday/` | 38 | 10 | 6–17 | 0.8× shorter |
|  |  | `not-a-time` | `heldout/` | 16 | 5 | 3–7 | 1.7× longer |
| `repair-x-name` | 9 (7–11) | `name-as-noun` | `heldout/` | 24 | 5.5 | 4–9 | 1.6× longer |
|  |  | `self-correction` | `heldout/` | 12 | 8 | 5–12 | 1.1× longer |
|  |  | `self-correction` | `everyday/` | 39 | 9 | 8–22 | 1.0× |
| `reported-x-op` | 8.5 (5–11) | `negation` | `heldout/` | 12 | 4.5 | 3–9 | 1.9× longer |
|  |  | `negation` | `everyday/` | 51 | 9 | 5–16 | 0.9× shorter |
|  |  | `operation` | `heldout/` | 12 | 5.5 | 3–12 | 1.5× longer |
|  |  | `operation` | `everyday/` | 10 | 9.5 | 7–12 | 0.9× shorter |
|  |  | `reported-speech` | `heldout/` | 12 | 8 | 5–11 | 1.1× longer |
| `role-x-people` | 8 (7–10) | `multi-person` | `heldout/` | 12 | 7.5 | 5–11 | 1.1× longer |
|  |  | `occupation-vs-person` | `heldout/` | 13 | 6 | 3–9 | 1.3× longer |
| `runon-x-repair` | 13 (10–16) | `run-on` | `heldout/` | 10 | 22.5 | 19–37 | **no — ranges disjoint** |
|  |  | `run-on` | `everyday/` | 8 | 22 | 18–33 | **no — ranges disjoint** |
|  |  | `self-correction` | `heldout/` | 12 | 8 | 5–12 | 1.6× longer |
|  |  | `self-correction` | `everyday/` | 39 | 9 | 8–22 | 1.4× longer |

**One of the 21 comparisons is unmakeable**: `runon-x-repair` against
`run-on`, and in both sets that measure that family. Every other pairing can be
read against every ingredient it carries, so the ordering across pairings — the
finding this set exists to produce — survives intact with that one row set
aside. It is a defect in the set rather than in the parser, and the fix is to
rewrite those twelve captures at their ingredient's length.

Overlapping ranges are **not** a clean bill of health. They only fail to prove
two sets incomparable, which is why the last column prints the ratio of the
medians instead of a pass or a fail: a number that blocked a merge here would
be a number people learn to write around. Read the ratio, and state the
direction of the bias when quoting the row. Two patterns are worth naming.

- **Where both sources carry a family they usually disagree, and `everyday/` is
  the comparable one.** `heldout/` is written as short single-mechanism
  sentences — its `negation` family has a median of 4.5 words against
  everyday's 9 — so the three negation-carrying pairings sit at 1.9–2.4× the
  held-out row and 0.9–1.2× the everyday one. Read them against `everyday/`.
- **`idiom-x-op` is the shortest pairing in the set**, a median of 4 words and
  0.4× the everyday `operation` family. Nothing there is disjoint, but of the
  rows that can be read it is the one where a weak score is most likely to be
  about length.

All of it is counted from the labels — the utterance's word count and the
number of rows a label expects — so nothing was unsealed to establish it.
Thought count is *not* the confounded axis for `runon-x-repair`, and goes the
other way: the everyday captures expect fewer rows at the median, 2.5 against
3.0.

`ellipsis-x-date` passes against both its ingredients — 2.0× the held-out
`ellipsis` family and 0.7× `multi-date`, overlapping both — so its 0/10 routing
is not a length artefact and is the reading to take seriously.

## The pairings

| pair | ingredients | the interaction being tested |
|---|---|---|
| `repair-x-name` | self-correction, name-as-noun | the discarded half is a person whose name is also a common noun |
| `negation-x-multi` | negation, multi-task | one clause negated, another actionable, in one breath |
| `reported-x-op` | reported-speech, operation | someone else's instruction to cancel — relayed, not authored |
| `runon-x-repair` | run-on, self-correction | three thoughts, no markers, a repair inside one of them |
| `cond-x-negation` | conditional, negation | a negated condition over a negated action |
| `role-x-people` | occupation-vs-person, multi-person | a role and a named person in the same capture |
| `brand-x-multi` | brand-verb, multi-task | a brand used as a verb alongside a second action |
| `ellipsis-x-date` | ellipsis, multi-date | two dated items with the verb left out of both |
| `idiom-x-op` | idiom, operation | cancel-shaped verbs used idiomatically, and vice versa |
| `nottime-x-date` | not-a-time, date | a phrase that looks temporal beside a real date |

A pairing's name gives its two ingredients, but the `families` column is what
the per-family table actually reports, and a capture may carry a third tag the
name does not mention: `AS06` and `AS12` in `reported-x-op` exclude a value with
"not" and are tagged `negation` as well. Read ingredients from the column, not
from the name — the comparability table above does.

Each pairing carries 12 captures, so a rate here is readable to roughly ±10%.
That is coarse, and it is deliberate: this set exists to say *which pairings
break*, not to put a precise number on any one of them. Treat a single pairing's
rate as a direction, and the ordering across pairings as the finding.

`idiom-x-op` and `ellipsis-x-date` each include captures expected to be
**Ambiguous** — "scrap the whole idea" has no referent to act on, "Priya Tuesday
Aurelio Thursday" has no recoverable verb. Acting confidently on those is harm
rather than inaccuracy, and the scorer counts it separately, as it does for the
everyday set.

## How it is scored

By `../everyday/score.py`, unchanged, on the same eight columns and the same
measures: routing, thought count, over- and under-segmentation, lost
information, invented information, title hygiene, and confident action on an
unpinnable capture kept separate as harm. The `pair` column takes the place of
everyday's `domain`, so the per-group table reports per pairing while the
per-family table still reports per ingredient. Both axes come out of one run.

Sharing the scorer is the point: a second implementation would be a second set
of bugs, and the everyday scorer has had three real defects found in it already.
The only change this set required was that the report's banner stops being
hardcoded, so a quoted report can be attributed to the set that produced it.

## Sealing

Same contract as `everyday/`, and mechanically enforced rather than promised:

- The scorer is **non-verbose by default**. `--failures` exists for release
  review and ends the set's usefulness the moment it steers a fix.
- `everyday/leak-check.py` checks this file against the gating corpus, every
  development set, the older held-out set, **and the everyday set** — a capture
  shared with another sealed set is not contamination, but it is one
  measurement counted twice. It runs inside the corpus gate.
- A test derives the sealed registry from each file's own shape, so a held-out
  set added later cannot be the one nobody leak-checks.

**Do not read the failures to decide what to fix.** Reproduce the pairing in
`Tools/CorpusRunner/devsets/` and work there.

## Provenance, stated plainly

These captures were written from speech phenomena and from the pairing design
above, not from reading the parser, and none was chosen because it was known to
fail. But honesty about what this set is worth requires saying that its author
had read the failure-family findings for this project. That does not make it
tuned — nothing here has ever been scored and then edited — and the protection
that matters is the standing one: its failures are not read, and the set is
never used to steer a fix.

The frame of reference is Monday 2026-08-03 10:00 America/Toronto. Every
asserted ordinal falls inside August, which has 31 days.

## Family denominators

| date | family | from | to | why |
|---|---|---|---|---|
| 2026-09-11 | `negation` | 24 | 26 | AS06 and AS12 exclude a value with `not` and carried no tag |

No capture and no `reject` span changed, so every headline measure is
untouched; only the `negation` row of the per-family table moves. Since this
set has never been scored, the change costs nothing — the first reading will
be taken at 26.

## Baseline

| date | commit | routing | count | loss | invention | title | unsafe / ambiguous |
|---|---|---|---|---|---|---|---|
| — | — | — | — | — | — | — | — |

**Empty on purpose.** The engine needs Apple's `NaturalLanguage` and cannot run
in the Linux container this set was written in, so no number goes in this table
until `score.sh` has run on a Mac. What has been verified here is the
instrument, not the pipeline: 69 scorer tests, the leak check against every
tuned corpus and the sibling sealed set, and a full-scale render of the report
against a stand-in probe. Filling this table from anything else would be
inventing a result.
