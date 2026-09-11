# Language baseline

The numbers a language change is judged against. Every figure here came from
one run of `Tools/CI/language-metrics.sh` on a real Mac. Nothing in this file
is an estimate, and nothing in it was produced in a container where the parser
cannot run.

**The newest section is the current baseline.** Older sections stay as written;
they are the record of what was true when they were measured, not a claim about
today.

## 2026-09-11 10:12 — after the discourse-framing change

First measured language change since the baseline. Commit `412a1a8` on
`claude/hearth-thread-tod920`,
[run #51](https://github.com/CalvinSalsali04/speak-it/actions/runs/34587781290),
`macos-26`. Compared against the 09:56 section below, which is the only
difference: no other change landed between them.

### What moved, and what did not

| instrument | measure | before | after |
|---|---|---|---|
| gating corpus | cases / failing | 1381 / 0 | 1393 / **0** |
| everyday | routing | 152/220 (69.1%) | 153/220 (69.5%) |
| everyday | count | 172/212 (81.1%) | 173/212 (81.6%) |
| everyday | nothing lost | 210/224 (93.8%) | 210/224 (93.8%) |
| everyday | nothing invented | 5/19 (26.3%) | 12/19 (63.2%) — **not a real gain, see below** |
| everyday | clean titles | 217/235 (92.3%) | **225/235 (95.7%)** |
| everyday | over-split | 17 | 16 |
| everyday | under-split | 23 | 23 |
| everyday | ambiguous acted on | 0 | 0 |
| held-out (389) | destination | 233/320 (72.8%) | 233/320 (72.8%) |
| held-out (389) | thought count | 255/310 (82.3%) | 255/310 (82.3%) |
| held-out (389) | acted on anyway | 7 | 7 |
| coordination | boundaries | 115/121 (95.0%) | 115/121 (95.0%) |
| routed | destination | 74/84 (88.1%) | 74/84 (88.1%) |
| routed | acted on anyway | 3 | 3 |
| unfinished | recall / fallout | 34/57 / 0/96 | 34/57 / 0/96 |
| abandonment | recall / fallout | 24/24 / 0/24 | 24/24 / 0/24 |
| **framing** (new) | destination | — | 41/45 (91.1%) |
| **framing** (new) | thought count | — | 43/44 (97.7%) |
| **framing** (new) | acted on anyway | — | 0 |

**Nothing regressed.** Not one everyday family lost ground on any of its three
measures, no development set moved down, and the gating corpus stayed at zero
failures across all four severities while growing by the 12 new cases.

### Title hygiene, by defect

| defect | before | after |
|---|---|---|
| farewell kept | 7 | **0** |
| preamble `number one` kept | 2 | **0** |
| preamble `number two` kept | 2 | 1 |
| preamble `number three` kept | 1 | **0** |
| preamble `what happened was` kept | 1 | 1 |
| title is the whole capture | 8 | 8 |

### The families the change was aimed at

| family | n | routing | count | title |
|---|---|---|---|---|
| trailing-goodbye | 7 | 2/7 → 2/7 | 4/7 → 4/7 | **0/7 → 7/7** |
| run-on | 8 | 0/8 → 0/8 | 0/8 → 0/8 | 4/8 → 7/8 |
| rambling-intro | 6 | 1/6 → 1/6 | 1/6 → 1/6 | 3/6 → 4/6 |
| sequencing | 17 | 6/17 → **7/17** | 7/17 → **8/17** | 12/17 → 16/17 |
| multi-thought | 40 | 19/40 → 19/40 | 22/40 → 22/40 | 36/40 → **40/40** |
| list | 20 | 12/20 → **13/20** | 13/20 → **14/20** | 17/20 → 18/20 |
| filler | 18 | 9/14 → 9/14 | 12/14 → 12/14 | 15/18 → **18/18** |

### What this is honestly worth

The title half of the problem is solved on this evidence: every farewell is
gone, and `trailing-goodbye`, `multi-thought` and `filler` are at 100% clean
titles. That is the visible defect — the words a person reads on the row —
and it was the whole of `trailing-goodbye`'s title score.

The segmentation half barely moved. Routing gained one capture and count
gained one; `run-on` is still 0/8 and `multi-thought` still 19/40. Enumerated
speech is now cut where the speaker said to cut it, and that is a small share
of run-on speech: most of it carries no marker at all, which is a harder
problem and the next one to take.

**The held-out set did not move, at all.** That is the honest headline. This
change was aimed at a family the 389-utterance set varies by mechanism rather
than by content, so there was little there for it to move, but the rule stands:
a change that has not moved the generalisation measure has not been shown to
help on that measure, whatever the everyday numbers say.

**The invention jump is not a result, and was corrected within the hour.** The
number moved from 5/19 to 12/19, and the arithmetic gives it away: **seven of
the nineteen invention cases listed `bye` as the value the reading must not
show**, and 5 + 7 = 12. On the twelve cases that test what the measure is for —
a superseded value, a corrected number, a corrected weekday, an inverted
negation — the score was 5/12 before this change and 5/12 after. Nothing about
invention improved.

The cause was the scorer, not the change: a farewell left in a title is a title
defect, and it was being counted a second time as an invention, so one fix moved
two metrics. The evaluation thread found this, has narrowed `reject` to values
the reading must not *assert*, and added a test that fails if a farewell returns
to that column. Verified here against `everyday.tsv` on `main` rather than taken
on trust: 19 rows carry a reject value and 7 of them are `bye`.

Once that lands, the invention column on both of these sections stops being
comparable with later runs. Treat 5/19 and 12/19 as belonging to a scorer that
no longer exists.

## 2026-09-11 09:56 — complete baseline on `main`

The baseline language improvement work is judged against. It is the first run
that covers every corpus the repository has.

| | |
|---|---|
| commit | `330344a` (`main`, after #28 and #29 merged) |
| run | [CI #50](https://github.com/CalvinSalsali04/speak-it/actions/runs/34586389323), `language_only` dispatch |
| runner | GitHub-hosted `macos-26`, Xcode 26.6 |
| wall clock | 4 min 02 s for the job; 3 min 52 s of it the measurement |

Six instruments, kept apart on purpose. A single accuracy figure across them
would be meaningless: they do not measure the same thing, they do not share a
denominator, and the two that are near ceiling would drown the four that are
not.

### 1. Gating corpus — regression net (self-consistency)

```
rendering=identity  TOTAL 1381 cases, 0 failing, 1381 clean
CRITICAL 0  BEHAVIORAL 0  METADATA 0  COSMETIC 0
```

Unchanged and saturated. This instrument can only confirm that a change broke
nothing already written down. **It is not an accuracy figure and must never be
quoted as one.**

### 2. Everyday speech — held out, 235 captures, by content

Five life domains, 47 captures each, written from the product description and
from how adults dictate. Never tuned against. This is the closest instrument
the repository has to Calvin's north star, and it is the one that should drive
the work.

| domain | routing | count | loss | invention |
|---|---|---|---|---|
| **all domains** | **152/220 (69.1%)** | **172/212 (81.1%)** | **210/224 (93.8%)** | **5/19 (26.3%)** |
| family-health | 27/44 (61.4%) | 35/43 (81.4%) | 45/45 (100.0%) | 0/4 (0.0%) |
| fitness-errands | 34/44 (77.3%) | 34/42 (81.0%) | 44/46 (95.7%) | 1/5 (20.0%) |
| freelance | 29/44 (65.9%) | 33/42 (78.6%) | 41/45 (91.1%) | 1/4 (25.0%) |
| money-travel | 29/44 (65.9%) | 35/43 (81.4%) | 42/45 (93.3%) | 2/3 (66.7%) |
| work-school | 33/44 (75.0%) | 35/42 (83.3%) | 38/43 (88.4%) | 1/3 (33.3%) |

Domains differ by 16 points on routing, which is less than the spread between
families below. **Content domain is not where the problem lives.**

| | |
|---|---|
| over-segmented (split) | 17 |
| under-segmented (merge) | **23** |
| produced nothing at all | 0 |
| item type matched the label | 132/212 |
| genuinely ambiguous | 15 |
| **acted on anyway** | **0 (0.0%)** |

Two things to take from that block. Abstention is perfect on this set — not one
capture a careful reader could not pin down was scheduled or modified anyway.
And **merges outnumber splits, 23 to 17**: see "What this changes" below.

`invention` deserves its own line. Only 19 of the 235 captures carry a value the
reading must *not* show, and on **14 of those 19 it shows it anyway**. The
denominator is small, but a 74% rate on a harm measure is the worst number in
this file.

> **Corrected 2026-09-11 10:25.** Seven of those 19 rows listed `bye` as the
> rejected value, which is a title defect the title metric already counted. The
> figure above is what the scorer reported and is left as recorded, but it is
> not a clean invention rate, and it is not comparable with runs after the
> evaluation thread's narrowing of that column.

#### Title hygiene — 217/235 clean (92.3%)

A lower bound on defects: it counts removable material still in the shown
title, never whether a title reads well.

| domain | clean titles |
|---|---|
| family-health | 44/47 (93.6%) |
| fitness-errands | 45/47 (95.7%) |
| freelance | 41/47 (87.2%) |
| money-travel | 45/47 (95.7%) |
| work-school | 42/47 (89.4%) |

| defect | count |
|---|---|
| title is the whole capture | 8 |
| farewell kept | 7 |
| preamble `number one` kept | 2 |
| preamble `number two` kept | 2 |
| preamble `what happened was` kept | 1 |
| preamble `number three` kept | 1 |

#### Per family — the table that matters

`n` counts captures carrying the tag, so the rows overlap: one capture can be
filler, negation and multi-thought at once.

| family | n | routing | count | title |
|---|---|---|---|---|
| run-on | 8 | **0/8 (0.0%)** | **0/8 (0.0%)** | 4/8 (50.0%) |
| rambling-intro | 6 | **1/6 (16.7%)** | **1/6 (16.7%)** | 3/6 (50.0%) |
| trailing-goodbye | 7 | **2/7 (28.6%)** | 4/7 (57.1%) | **0/7 (0.0%)** |
| sequencing | 17 | **6/17 (35.3%)** | **7/17 (41.2%)** | 12/17 (70.6%) |
| multi-thought | 40 | **19/40 (47.5%)** | **22/40 (55.0%)** | 36/40 (90.0%) |
| operation | 10 | 5/10 (50.0%) | 0/2 (0.0%) | 10/10 (100.0%) |
| cancellation | 12 | 6/12 (50.0%) | 1/4 (25.0%) | 12/12 (100.0%) |
| hedged | 24 | 9/17 (52.9%) | 15/17 (88.2%) | 19/24 (79.2%) |
| list | 20 | 12/20 (60.0%) | 13/20 (65.0%) | 17/20 (85.0%) |
| negation | 38 | 24/38 (63.2%) | 28/34 (82.4%) | 36/38 (94.7%) |
| filler | 18 | 9/14 (64.3%) | 12/14 (85.7%) | 15/18 (83.3%) |
| relative-date | 6 | 4/6 (66.7%) | 5/6 (83.3%) | 6/6 (100.0%) |
| date | 36 | 24/35 (68.6%) | 28/35 (80.0%) | 34/36 (94.4%) |
| person | 31 | 22/31 (71.0%) | 24/30 (80.0%) | 30/31 (96.8%) |
| location | 11 | 8/11 (72.7%) | 9/11 (81.8%) | 10/11 (90.9%) |
| reference | 34 | 27/34 (79.4%) | 28/34 (82.4%) | 33/34 (97.1%) |
| quantity | 29 | 23/29 (79.3%) | 27/29 (93.1%) | 26/29 (89.7%) |
| time | 25 | 20/24 (83.3%) | 23/24 (95.8%) | 24/25 (96.0%) |
| self-correction | 24 | 20/24 (83.3%) | 22/24 (91.7%) | 24/24 (100.0%) |
| false-start | 14 | 12/14 (85.7%) | 12/14 (85.7%) | 13/14 (92.9%) |
| proper-noun | 14 | 12/14 (85.7%) | 11/13 (84.6%) | 12/14 (85.7%) |
| recurrence | 22 | 19/22 (86.4%) | 21/22 (95.5%) | 22/22 (100.0%) |
| repetition | 10 | 10/10 (100.0%) | 10/10 (100.0%) | 10/10 (100.0%) |
| question | 9 | 1/1 (100.0%) | 1/1 (100.0%) | 9/9 (100.0%) |
| ambiguous | 15 | — | — | 14/15 (93.3%) |

### 3. Held-out set — 389 utterances, held out by mechanism

| measure | value | change |
|---|---|---|
| destination correct | 233/320 (72.8%) | unchanged |
| thought count correct | 255/310 (82.3%) | unchanged |
| captures producing nothing | 0 | unchanged |
| genuinely ambiguous | 69 | unchanged |
| **acted on anyway** | **7 (10.1%)** | unchanged |

Identical to the 09:38 run, as it must be: nothing merged between them touched
the parser. Failures were not read; the job cannot read them.

### 4. Development sets — readable, and where fixes are worked out

| set | measure | value |
|---|---|---|
| coordination | clause boundaries correct | 115/121 (95.0%) |
| routed | destination correct | 74/84 (88.1%) |
| routed | thought count correct | 77/79 (97.5%) |
| routed | ambiguous acted on anyway | 3/32 (9.4%) |
| unfinished | unfinished flagged (recall) | 34/57 (59.6%) |
| unfinished | finished misflagged (fallout) | 0/96 (0.0%) |
| unfinished | fragment given a date or reminder | 2 |
| abandonment | withdrawals recognised | 24/24 (100%) |
| abandonment | kept words wrongly withdrawn | 0/24 (0.0%) |

Coordination failures, all six: `occupations` 3 (all over-splits), `brands` 1
(over-split), `multiple-people` 1 (over-split), `three-or-more` 1 (under-split).

Weakest unfinished families: `incomplete-complement` 1/10,
`trailing-function-word` 2/8, `abandoned-midthought` 3/9.

### 5. Synthetic stress — still none

`Tools/LanguageMutations/invariance.sh` has never run against the real engine.
No consistency number exists, and consistency would not be an accuracy number
if it did.

### 6. Public-dataset derived — still none

`Docs/PUBLIC_DATASETS.md` records the licence survey. No data has been
integrated, and no external label has been treated as ground truth.

## What this changes

**The over-splitting hypothesis does not survive first contact with unseen
speech.** It came from the coordination development set, where five of six
failures point one way. On the everyday set, which nothing has been tuned
against, the count goes the other way: 23 merges against 17 splits. The
development set is measuring a narrow question — coordinated noun phrases —
and the held-out sets are measuring whole recordings. Over-splitting is real
and narrow; under-splitting is what real captures actually suffer from.

**The failure is concentrated in discourse structure, not in semantics.** The
five worst families by routing — run-on (0%), rambling-intro (16.7%),
trailing-goodbye (28.6%), sequencing (35.3%), multi-thought (47.5%) — are all
the same situation: one recording carrying several thoughts, wrapped in the
framing people put around speech. The families that read the *content* of a
sentence, once it has been cut out correctly, are in the eighties and nineties.

Title hygiene says the same thing from the other side: 14 of the 18 title
defects are framing material left in place — 7 farewells, 6 numbered
enumerators, 1 narrative opener — and `trailing-goodbye` scores **0/7**.

`grep` for farewell handling in `SpeakIt/` returns nothing. `IntentConsolidation`
owns elaborative framing and deliberately stands down the moment two
substantive clauses are present, so it is a collapse stage for rambling with a
single point rather than a general framing stage. Nothing owns enumerators
(`number one`, `first of all`, `secondly`) either, and an enumerator is a
clause boundary a speaker states out loud. That is one missing layer producing
two visible symptoms.

## 2026-09-11 09:38 — first measured run, PR #28 branch

| | |
|---|---|
| commit | `f3f0e5f` |
| branch | `claude/hearth-thread-tod920` (PR #28) |
| run | [CI #49](https://github.com/CalvinSalsali04/speak-it/actions/runs/34584864381), `language_only` dispatch |
| runner | GitHub-hosted `macos-26`, Xcode 26.6 |
| wall clock | 4 min 12 s for the job; 3 min 56 s of it the measurement itself |

### Gating corpus — self-consistency

```
rendering=identity  TOTAL 1381 cases, 0 failing, 1381 clean
CRITICAL 0  BEHAVIORAL 0  METADATA 0  COSMETIC 0
```

**This instrument is exhausted.** Not near ceiling — at it, with zero failures
at every severity including cosmetic. It can confirm that a change broke
nothing already written down. It cannot report progress, because there is no
remaining headroom in which progress could show.

Two figures in circulation were stale and are corrected here: the runner's own
README quotes 841 cases as sample output, and 999 of 1,022 was reported from a
static read. The measured size is 1,381.

### Held-out set — generalisation

389 utterances written before anyone read the parser.

| measure | value |
|---|---|
| destination correct | 233/320 (72.8%) |
| thought count correct | 255/310 (82.3%) |
| captures producing nothing | 0 |
| genuinely ambiguous | 69 |
| **acted on anyway** | **7 (10.1%)** |

Every row is identical to the baseline recorded on 2026-09-09 in
`Tools/CorpusRunner/heldout/README.md`. That is the most useful thing about
this first run: the harness reproduces numbers arrived at independently by
hand, so the instrument agrees with the one that came before it. The failures
were not read, and the job cannot read them — the wrapper refuses `--verbose`
and `--failures`.

**The gap is 27.2 points.** A saturated regression net at 100% and the honest
instrument at 72.8% is the real size of the problem, and it is the number to
watch rather than either one alone.

### Development sets — where rules are worked out

Not held out. Failures here may be read.

| set | measure | value |
|---|---|---|
| coordination | clause boundaries correct | 115/121 (95.0%) |
| routed | destination correct | 74/84 (88.1%) |
| routed | thought count correct | 77/79 (97.5%) |
| routed | ambiguous acted on anyway | 3/32 (9.4%) |
| unfinished | unfinished flagged (recall) | 34/57 (59.6%) |
| unfinished | finished misflagged (fallout) | 0/96 (0.0%) |
| unfinished | fragment given a date or reminder | 2 |
| abandonment | withdrawals recognised | 24/24 (100%) |
| abandonment | kept words wrongly withdrawn | 0/24 (0.0%) |
| abandonment | withdrawn thought acted on | 0 |

### The weakest families, by measurement rather than by impression

Recall is where the room is; fallout is already zero, which is the safer place
for it to be.

| family | set | score |
|---|---|---|
| `incomplete-complement` | unfinished | **1/10** |
| `trailing-function-word` | unfinished | **2/8** |
| `abandoned-midthought` | unfinished | **3/9** |
| `occupations` | coordination | **1/4**, all three failures over-splits |
| `dangling-infinitive` | unfinished | 18/20 |
| `brands` | coordination | 4/5, the failure an over-split |
| `multiple-people` | coordination | 5/6, the failure an over-split |
| `three-or-more` | coordination | 6/7, the failure an under-split |

Five of the six coordination failures are **over-splits**: the segmenter
inventing a row nobody asked for. That is one direction, not a scatter, and it
is worth treating as one question rather than six.

## What this baseline does not cover

- The everyday corpus (235 captures) was not on `main` when this ran, so the
  report's discovery section reads "none yet". It will appear on its own once
  that lands; the discovery mechanism was exercised and behaved correctly with
  nothing to find.
- `Tools/LanguageMutations/invariance.sh` has still never run against the real
  engine. No consistency number exists.
- These are rules-path numbers from `Tools/PipelineProbe`, not the shipping
  app with its store. See `Tools/PipelineProbe/README.md` for what that cannot
  tell you.

## Everyday corpus — generation 3 (2026-09-11)

The everyday held-out set grew from 235 captures to 255, and its `invention`
measure from 12 cases to 22, so **everyday numbers from before this change are
not comparable to numbers after it.** Compare within a generation, never across.
`Tools/CorpusRunner/everyday/README.md` holds the generation table and the
reasoning.

Two things changed together, deliberately at a pause rather than between two
comparisons:

- Twenty captures added, four per domain. Fifteen carry a genuine superseded
  value — a corrected number, time, weekday, person or place. `invention` had
  been the thinnest measure in the set.
- Ten captures were withdrawn from `invention` (five of them pre-existing). They
  phrase an exclusion, not a repair — `book the small meeting room not the big
  one` — and the excluded value is spoken deliberately, so a faithful title
  contains it. Two of the old ones rejected `not 2D` and `not 6`, strings a
  *correct* title carries. Net effect 12 → 22 cases, all genuine supersessions.
  The withdrawn captures are still scored for routing, count, loss and title,
  so the negation family's routing signal is intact. What no measure reports is
  **invention on a negated or superseded value** — whether the reading treated
  the operative value as operative. That needs a judgement a span test cannot
  make, so it belongs in a readable development set; the everyday README says so
  and warns against closing the gap by re-adding a span test.
- Span matching now anchors its left edge. The old test was a plain substring
  match over normalised text, where `6:40` folds to `6 40` and sits inside
  `16 40`, so a pipeline that correctly discarded a superseded time could be
  reported for inventing it. Direction of the correction is known: `loss` can
  only get stricter, `invention` only less false.

Nothing here was tuned against, and the set stays sealed: it has been scored
non-verbose and its failures have not been read.

## Adversarial held-out set — new instrument, no reading yet (2026-09-11)

`Tools/CorpusRunner/adversarial/` is a third sealed set, 120 captures in 10
pairings of 12. It is a different axis rather than more of the other two:

| set | held out by | what it varies |
|---|---|---|
| `heldout/` (389) | mechanism | one phenomenon per capture |
| `everyday/` (255) | content | ordinary life speech |
| `adversarial/` (120) | interaction | two phenomena deliberately compounded |

The gap it fills is specific. `heldout.tsv` carries exactly one family tag on
all 389 rows, so nothing in the repository asked whether the pipeline's layers
**compose**. Every pairing here is built from two ingredients `heldout/` already
measures separately, so a pairing scoring badly while both ingredients score
well alone is evidence about architecture rather than a missing rule.

**Read a pairing against its ingredients, never on its own** — if an ingredient
is already weak in `heldout/`, a weak pairing says nothing new.

It is scored by the everyday scorer unchanged, so it needs no second
implementation and inherits the defects already found and fixed there. It is
discovered by the existing `score.sh` convention, so `language-metrics.sh`
picks it up with no edit. Its baseline table is empty for the same reason
everyday's was: the engine cannot run in a Linux container, and a number from
anywhere else would be invented.

## Family denominators moved on 2026-09-11, after the generation-3 note

Separate from any generation: five captures gained a `negation` family tag in
PR #33, because they exclude a value with `not` and had never been tagged. That
moves the `negation` row of the per-family tables and nothing else — no capture
was added or removed, and no `reject` span changed, so every headline measure is
untouched.

| set | `negation` from | to |
|---|---|---|
| everyday | 48 | **51** |
| adversarial | 24 | **26** |

Costs nothing today: the last published everyday numbers are the 235-capture
generation, so no `negation` rate from generation 3 has been quoted yet, and the
adversarial set has never been scored. **The next reading is the first for both,
and should be recorded against 51 and 26.**

A generation is about a measure changing. A family denominator can move without
one, which is why it is recorded separately rather than folded into the
generation table.

## How to reproduce

```bash
./Tools/CI/language-metrics.sh --report /tmp/language-metrics.txt
```

Or dispatch `ci.yml` with `language_only`. Record the result here as a new
dated section; do not edit an old one.
