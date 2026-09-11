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
