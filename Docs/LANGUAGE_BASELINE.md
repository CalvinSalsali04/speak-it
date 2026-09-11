# Language baseline

The numbers a language change is judged against. Every figure here came from
one run of `Tools/CI/language-metrics.sh` on a real Mac. Nothing in this file
is an estimate, and nothing in it was produced in a container where the parser
cannot run.

## 2026-09-11 — first measured baseline

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
