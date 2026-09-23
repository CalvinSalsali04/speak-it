# Language baseline

The numbers a language change is judged against. Every figure here came from
one run of `Tools/CI/language-metrics.sh` on a real Mac. Nothing in this file
is an estimate, and nothing in it was produced in a container where the parser
cannot run.

**The newest section marked as a baseline is the current baseline.** A section
that records a change which did not ship says so in its first lines. Older
sections stay as written; they are the record of what was true when they were
measured, not a claim about today.

## Sealed-set cost ledger

Every change that moved a sealed measure, with its direction. **One row per
change, added when the change is measured, never edited afterwards.**

This exists because no individual write-up can show the thing that matters
here. A change costing one row on a sealed set is defensible on its own and
says so honestly in its own section; three such changes are a real decline that
no one section ever displays, and finding it otherwise means reading every
dated section in this file and doing the arithmetic. A cost absorbed silently
into the next figure is how a sealed set degrades invisibly, so a cost that
does not appear here has not been reported.

Sealed sets only — held-out, everyday, adversarial. Development sets are worked
against on purpose and their movements belong in the dated sections.

| date | change | measure | from | to | |
| --- | --- | --- | --- | --- | --- |
| 2026-09-11 | resultive `so` boundary (#57) | held-out thought count | 255/310 | 254/310 | **−1** |
| 2026-09-11 | resultive guard tightened to a statement cause (#57) | — | — | — | no sealed measure moved |
| 2026-09-15 | numbered enumerator decided from its left context | everyday clean titles | 245/255 | 246/255 | **+1** |

**Running total, per measure.** There is no single total here and there will
not be one. Adding 254/310 to 246/255 is collapsing two instruments into one
number, which is the move this file forbids everywhere else; `ledger-check.py`
recomputes each line below from the rows above and fails if a measure moves and
no line names it.

- **held-out thought count: −1 row**, across one change.
- **everyday clean titles: +1 row**, across one change.

Two sealed measures have moved, across two changes. **The two do not cancel and
must not be read as if they did** — they are different sets, different
denominators and different questions, and a reader who nets them to zero has
learned nothing about either. Every other sealed measure — held-out
destination, held-out acted-on-anyway, everyday routing, count, nothing lost
and nothing invented, and every adversarial and consequence measure — has never
been moved by a change recorded here.

**No count of "how many sealed measures there are" is asserted here, and the
one that used to be was wrong twice over.** It read "one of the eight sealed
measures" over a sentence that then enumerated nine, and it described "four
everyday measures" when `everyday/measure-gate.py` names eleven — six forced
and five suppressed — and the adversarial set is scored by the same scorer. The
figure was never derived from anything; it was written in prose and would have
been quoted back as if it had been. If a denominator is wanted, count the names
in `measure-gate.py` and the headline figures `heldout/score.py` prints, which
is a list something maintains rather than a number this file invented.

Caught in review by the evaluation thread, which could not reproduce the eight
from anything enumerable. That is the same defect as the compromised-capture
count earlier the same day: **a published figure has to come from the check
that computes it**, or the first person to re-derive it gets a different
answer.

The ledger is not a budget and no number in it is acceptable by being small.
It is here so the question "has this been drifting?" has an answer that takes
one glance instead of an afternoon.

## Two held-out numbers, and which one a claim may use

Asked for on 2026-09-12, after five held-out captures turned out not to be
unseen. The rule going in was **by ID only**: no capture text and no failure
reason is read or printed to build any of this, and none was.

**The instrument prints this, and this section does not restate the figures.**
`Tools/CorpusRunner/heldout/score.py` computes the totals, the exclusion
categories, the denominators and the per-id subtotal participation, and prints
them on every run. That is deliberate and it is the lesson from the
compromised-capture count that read three when it was five: a published figure
has to come from the check that computes it, or the first person to re-derive
it gets a different answer. What follows is the scheme, not its values.

### The two numbers

**LEGACY** — every labelled capture, including the ones now known not to be
unseen. It is what every section of this file dated before 2026-09-12 means,
and it is kept for exactly that reason. Older numbers are not rewritten, not
recomputed and not quietly corrected; they are marked legacy and left visible.

**CLEAN SEALED** — the same measures over the captures still entitled to carry
a claim about unseen speech. **Use this one for any statement about
generalisation.** It is not a better score and it may read either higher or
lower than legacy: it is the same instrument over a smaller, honest population.

A third distinction cuts across both, and predates neither: **STRICT** compares
a capture against the first number in its label, **RANGE-AWARE** accepts any
count the label permits. Seventy-one captures carry a label like `1-2`, which
is the author recording that both readings are defensible, and strict marks the
upper one wrong. Every thought-count figure published in this file before
2026-09-12 is a strict figure, and is marked so where it appears.

### Why there are four exclusion categories and not one

Each names a different way a capture stopped being unseen, and they are kept
apart because the remedies differ and because collapsing distinct populations
into one flag is the recurring bug in this repository.

| category | what happened | can it be undone |
| --- | --- | --- |
| in tuned material | the capture's text is also a case the rules were tuned against | no |
| verbatim in a document | the text appears in prose under `Docs/` | no — deleting a sentence does not un-see it |
| near tuned material | a near-duplicate of tuned material, by Jaccard ≥ 0.70 | no, and the threshold is a judgement worth disagreeing with |
| exposed without inspection | the text was printed into a session's context, never inspected, never used | no, and it is recorded even though nothing was learned from it |

The first two are *compromised*: the parser may have been shaped by them. The
last two are weaker claims and are still excluded, because the point of the
clean number is that it is the one that can be defended without an argument.

**The excluded total is a UNION and never a sum.** One capture sits in two
categories, which is exactly how the published count once read three when the
answer was five: one limb was reported as the whole. Adding the limbs
overcounts in the other direction. The instrument computes the union and prints
which ids are doubled, so neither mistake can be made from this file.

### Denominators, and which subtotals an excluded capture was feeding

Not every capture feeds every measure, so removing eleven rows does not lower
eleven denominators by eleven. A capture labelled `Ambiguous-*` is excluded
from the destination rate by design — the contract for an unpinnable capture is
to keep it and not act, which the unsafe counter measures instead — so it feeds
the ambiguous subtotal and not the destination one. The instrument prints, per
excluded id, which subtotals it was feeding, so the clean denominators can be
reconciled against the legacy ones by hand rather than taken on trust.

### The guard

`Tools/CorpusRunner/everyday/leak-check.py` compares every sealed set against
tuned material and against the prose in `Docs/`, and fails the run when a
sealed capture becomes referenced in either. `compromised.py` and the leak
check are two separate records of one fact, with a test asserting they agree —
restricted to held-out captures by the file named in each `(file, id)` key,
since the leak check spans every sealed set. They are deliberately **not**
derived from one another: the categories above do not map onto the leak
check's, and deriving would flatten the distinction this section exists to
draw. Two records plus an agreement check has already earned its keep by
catching an error in the newer of the two.

One hazard, recorded because it cost a second exposure of a sealed capture: **an
id is safe to store and unsafe to grep.** Searching the repository root for a
capture id matches that capture's own row and prints the text.

## Three standing rules, two of them learned by paying for them

**Never quote a set total on its own.** On 2026-09-11 `runon.tsv` went from
33/44 to 35/45 on thought count — an improvement by any reading of the total —
while containing a regression that the per-family table made obvious at a
glance: `statement-runon` at 0 of 6 beside `errand-runon` at 6 of 8. The
change that produced the total also broke four cases of the gating corpus. A
total is a weighted average of things that moved in both directions, and it is
the one number that cannot tell you which.

**An instrument's output is the thing under test, not its source.** Four
checks in this repository reported a verdict nobody could act on, and every
one of them had been reviewed by reading its code: a step that wrote failures
to a path nothing collected, the same step skipped on the only run that needed
it, a gate that printed a count and named a command requiring a Mac, and a
mutation harness that ran in an already-broken copy so every measure read as
protected. Run the instrument, read what it prints, and check that a reader
who has only that output can act on it.

A fifth joined them on 2026-09-11, and it is the one that got furthest:
`abandonment-score.py` reads a `KNOWN:` note in the data — a marker written to
*document* a failure — and scores the row as a pass. The report printed
`recall 24/24`, `FALLOUT 0/24` and `documented failures kept on purpose 4` on
adjacent lines, so the contradiction was in the output the whole time and was
read past twice, here and in this file. A figure can come from a real run on a
real Mac, as every figure here does, and still be wrong about the parser. See
"Correction — 2026-09-11" below.

**Every number in this file is the rules path.** `Tools/PipelineProbe` says so
itself: it "runs the **rules path only** … It does not run the Foundation Models
refinement", and `language-metrics.sh` scores through the probe. So 233/320 on
held-out destination is a rules-path figure, and a sentence quoting it as what
an iOS 26 user receives is quoting it wrong.

Today that is exact rather than approximate, and the reason is worth knowing
rather than taking on trust. `RefinementPolicy.shouldRefine`
(`ThoughtExtractor.swift:187`) runs the on-device model only where an item is
already `needsReview`, and not at all above 1,500 characters. For every capture
the rules answered confidently, no refinement happens, so the rules answer *is*
the product answer and the number is the product number.

That makes the caveat a trigger rather than a hedge, and the trigger is one
line of code: **if `shouldRefine` ever fires on anything beyond `needsReview`,
every figure in this file stops describing the product** — not slightly, but for
the whole population that gate newly covers — and stays wrong until an
instrument exists that can run the refined path. Nothing here can measure that
today; `PipelineProbe` has no way to reach it. Whoever widens that gate owns
producing the instrument first.

## Correction — 2026-09-11: the abandonment figures in this file are not what the set scored

**`24/24` and `0/24` are the scorer's numbers, not the set's.** Every place this
file quotes them is marked `†`. They were unverified until 15:45, when a macOS
run with the repaired scorer replaced them.

`Tools/CorpusRunner/devsets/abandonment-score.py` accepts a fifth column, and a
note beginning `KNOWN:` marks a row documented as failing today and kept on
purpose. The scorer neither excludes such a row from the denominator nor reports
it separately: it credits the row as a **pass**. Recall (lines 83–87) and the
mixed row (116–120) increment the same counter a genuine pass increments, and a
marked `Kept` row (99–102) is credited to its family while skipping
`stats["fallout"] += 1` entirely. Each of those three branches is reached only
*because* the case failed. Four rows of `abandonment.tsv` carry the marker:

| row | expected | what its marker says fails today | figure it inflates |
|---|---|---|---|
| ABN20 `I was going to call Mike scratch that` | Abandoned | no licence catches this without also destroying "I need to scratch that" | recall |
| ABN38 `Never mind the gap` | Kept | the cancel pattern reads a named object as managing an item | **fallout** |
| ABN40 `Never mind, buy milk` | Mixed | a leading withdrawal takes the whole capture, milk included | mixed — not published here |
| ABN46 `Call the dentist and I was going to actually never mind` | Mixed | an earlier "call" makes `ClauseScope` read the whole capture as a message | mixed — not published here |

So if the four markers still describe what the parser does, the figures this
file should carry are **recall 23/24 and fallout 1/24** — and the second is the
one that matters. The scorer's own docstring calls fallout "the number that
decides whether this ships", for the stated reason that a missed withdrawal
leaves a row the person can delete while a wrong one deletes a thought they
meant to keep. A documented fallout of 1, printed as 0, is exactly the reading
that decision must not be made on. The mixed row would move from 7/7 to 5/7;
this file has never published it.

**Neither figure is corrected in place, because neither can be measured from a
Linux container** — the probe that feeds the scorer needs Apple's
`NaturalLanguage`. What is established from source is the defect and which rows
it touches; the fallout reading of 1 was reported by the evaluation thread from
their run.

**The scorer is fixed** as of `b326ce8`, and the fix draws the line in the right
place: a `KNOWN:` marker now moves the **exit status** and not the rate. A
documented failure is counted as a failure in recall, fallout and the mixed row;
the report then names the ids and says which part of the total somebody already
owns; and the exit status forgives that part, so a pre-existing defect does not
block a hand run. A marker on a row that has started passing now fails the run
instead, because a suppression that outlives its failure is one nobody is
watching. Both scorers gained self-tests in the same change, which found three
gaps by mutation that no case in the set exercised.

**The run happened at 15:45 and the figures are now measured: recall 23/24,
fallout 1/24, mixed 5/7** — see the 15:45 section above. All three match what
was derived from the scorer's source before any run could check them. The
daggered numbers below stay as each run printed them, because an older section
records what was true when it was measured; the footnote at each site now says
what replaced it.

Two smaller consequences came from the same branch. Both are fixed in
`b326ce8` and both are worth keeping written down, because the shape recurs:

- **The gate could not fail on a documented fallout.** The old exit line was
  `sys.exit(1 if (stats["fallout"] or stats["unsafe"] or stats["unseen"]) else 0)`,
  and a `KNOWN:` fallout never incremented `stats["fallout"]`. A marker written
  to document a failure also silenced the exit code that would have surfaced it.
  It now gates on new fallout only, which is the same forgiveness stated
  deliberately instead of as a side effect.
- **`documented failures kept on purpose (KNOWN:)` counted markers, not
  failures.** It incremented for every marked row that was scored, pass or fail,
  so it would have kept reading 4 after one of them started passing — the moment
  the marker should come off. The report now names the ids of the rows that
  actually failed, and a marker on a row that has started passing fails the run.

**Nothing else in this file is affected**, and that is checkable rather than
inferred. `KNOWN:` appears in exactly two files in the repository,
`abandonment.tsv` and its own scorer — but the stronger argument is that every
other published denominator reconciles with the label file it came from:

| published | denominator | label file says |
|---|---|---|
| coordination 115/121 | 121 | 121 rows, and a row the probe never emitted counts as a **failure** here, not an exclusion |
| routed 74/84, ambiguous 3/32 | 84 and 32 | 116 rows, 32 carrying `Ambiguous` — 116 − 32 = 84 |
| framing 41/45 | 45 | 45 rows, none ambiguous |
| runon 41/46 | 46 | 46 rows, none ambiguous |
| unfinished 34/57 and 0/96 | 57 and 96 | 57 `Incomplete` and 96 `Complete` of 163 rows |
| held-out 233/320 | 320 | 389 rows, 69 carrying `Ambiguous` — 389 − 69 = 320 |

All of those scorers except coordination's drop a labelled row the probe never
emitted out of the denominator rather than failing it. So a denominator arriving
at exactly its label count is positive evidence that none was dropped on the run
these figures came from. That check is available for every rate above and passes
for all of them. It is the check the abandonment figures needed and could not get, because
there the arithmetic departs from the labels by design.

**Two of the five would hide the drop next time**, and the report
`language-metrics.sh` prints is where it would be hidden:

| scorer | a labelled row the probe never emitted |
|---|---|
| coordination, `devsets/score.py` | counted as a **failure**. The denominator stays `len(rows)`, and `--verbose` shows `(no output)`. This is the design the others should have. |
| held-out, `heldout/score.py` — so routed, framing and runon too | dropped from the denominator, but the count prints as `missing probe results` |
| everyday, `everyday/score.py` | dropped, prints `missing probe results`, and `measure-gate.py` mutation-checks that the counter can still report |
| `abandonment-score.py` | dropped, printed as `scored N of M labelled`, and the run fails. Before that it printed **no counter at all** — only an `UNSEEN` entry in the `--verbose` list, which `language-metrics.sh` never asks for. |
| `unfinished-score.py` | dropped, printed the same way, and the run fails. Before that it did **nothing at all**: `stats["unseen"] += 1; continue`, no print, no miss, no exit status. |

So on the report every figure **in this file** comes from, a dropped row was
silent in two of the five sets, and in `unfinished` it was silent on a hand run
too. The reconciliation above stood in for the missing signal, and it was a hand
check rather than an instrument.

**It is an instrument now**, in the two sets that needed it. Both dev-set
scorers print `scored N of M labelled` on every run, clean or not — a line that
appears only on failure is not evidence on the runs where it stays quiet — and
a mismatch fails the run:

```
  scored                        57 of 57 labelled
  scored                        56 of 57 labelled  ← 1 with no probe result, excluded from every rate below
```

`language-metrics.sh` discards dev-set scorer exit codes by design, so this
cannot redden the language job; it stops a hand run, which is where a dropped
row is worth stopping for. The three sealed-set scorers are unchanged: they
already print the count, and coordination still has the strongest answer of the
five — a missing row is a failure and the denominator stays whole. Switching the
others to that would move published rates, so it needs a run and a note rather
than a quiet edit.

## 2026-09-15 — the held-out set has its own per-family table, and it reads the opposite of everyday's on the same family

`heldout/score.py` has printed a per-family table on every run and **no figure
from it has ever been recorded in this file.** Every `run-on` number here is
the everyday set's. That is a gap in the record rather than in the
instrument, and closing it changes a reading this file already made.

Read out of the job log of
[run 34960158656](https://github.com/CalvinSalsali04/speak-it/actions/runs/34960158656)
(`macos-26`, job `Language metrics`, success), not re-run: the run was paid for
by another thread and this section spends nothing. Ids and rates only; no
capture text was read. The head is `707ac32`, which is `66d338d` plus one
unmerged parser change. The three held-out figures this file already records
came back identical to their recorded values — destination 233/320, thought
count strict 254/310, ACTED ON ANYWAY 7 — so the per-family rates below are
`main`'s to within a change that moved none of them.

### The rows worth having

The scorer prints this table under the heading **PER FAMILY (LEGACY
denominators) — one tag per capture**, ranked worst destination rate first.
These eight rows are the ones this file has a reading for; the run prints
thirty.

| family | n | destination | thought count |
| --- | ---: | ---: | ---: |
| ellipsis | 12 | **0/4 (0.0%)** | 4/4 (100.0%) |
| reported-speech | 12 | 3/10 (30.0%) | 10/10 (100.0%) |
| hedged | 12 | 3/9 (33.3%) | 9/9 (100.0%) |
| run-on | 10 | 10/10 (100.0%) | **2/10 (20.0%)** |
| multi-date | 12 | 10/11 (90.9%) | 4/11 (36.4%) |
| conditional | 8 | 5/8 (62.5%) | 4/8 (50.0%) |
| idiom | 12 | 7/10 (70.0%) | 5/10 (50.0%) |
| multi-person | 12 | 10/12 (83.3%) | 6/12 (50.0%) |

**Read `n` the way the scorer says to read it.** Its own note under this table:

> `n` is captures carrying the tag, not the denominator of either rate: read
> each denominator from its own column before quoting a row, because a rate
> over 1 or 2 captures ranks like any other.

So `ellipsis` carries twelve captures and four of them have a scorable
destination. The other eight are not failures and are not successes; they are
outside that column, and the row says nothing about them.

**Two families are printed below the ranking, not in it**: `ambiguous` (n 14)
and `sarcasm` (n 1), both with `—` in both columns. Every capture carrying
those tags is labelled unpinnable, so there is no destination rate for them to
be worst or best at, and they are measured by ACTED ON ANYWAY instead. A
reader who ranks families by this table has to know they were never in the
ranking.

Two of these rows corroborate readings this file already holds from other sets.
**`ellipsis` misses on all four of its scorable captures**, which puts it top
of a ranking ordered by rate — four captures, so the rate is what ranks it and
not the weight of evidence. What makes it worth reading is that the section on
the adversarial set calls `ellipsis × date` **0/10** the worst single reading
in any instrument, and that denominator is not small. **`run-on` is the worst
thought-count family here at 2/10**, over ten captures, and the everyday set
reads `run-on` **0/8** on count. Two sealed sets scored independently — though
both were authored here, so this is corroboration between our own instruments
and not the external evidence the end goal asks for — naming the same two
families is a different class of evidence from either alone.

### Correction: `run-on` at 10/10 and at 0/8 are not a disagreement

The held-out table puts `run-on` destination at **10/10**. The everyday table
puts `run-on` routing at **0/8**. Both are true and they are not the same
measure:

- `heldout/score.py:191` — `ok = "Today" in got["routes"]`. Membership, once
  per capture. A capture that produced one merged row still lands somewhere,
  so **under-segmentation cannot fail this column.**
- `everyday/score.py:264` — `want = Counter(...)` against
  `Counter(r["route"] for r in got["rows"])`, compared with `==`. Multiset
  equality over the rows produced, so a capture that should make two rows and
  makes one fails routing **for that reason alone.** The everyday routing
  column contains the thought count by construction.

So the two sets are **consistent**, and each statement has exactly one source:

- **They reach the right place** — held-out `destination` 10/10, and only
  that, on the ten held-out captures rather than the eight everyday ones.
  Everyday cannot say this at all; see below.
- **Eight of the ten are not split** — held-out `thought count` 2/10, so two
  of them do split correctly.
- **Everyday `routing` 0/8 is the conjunction of those two**, and it cannot be
  taken apart.

**A failing conjunction does not name its failing conjunct.** For a two-thought
capture expected as two Today rows, one row routed Today gives `{Today: 2}`
against `{Today: 1}`, and one row routed **Memory** gives `{Today: 2}` against
`{Memory: 1}`. Both fail the `==` identically. So everyday `run-on` 0/8 is
equally consistent with the destination being right and with it being wrong,
and the title column at 7/8 does not separate them either. Read on its own it
would be a routing failure of unknown shape.

The scorer already knows this about its other column. Directly under the
routing check, `everyday/score.py` reports item type twice — the plain figure
and `of those segmented right`, conditioned on `produced == expected_rows` —
with the comment that the plain one "carries every `count` failure inside it
and reads as a type problem". **Route has no conditioned figure and type
does.** That is the cheapest thing anyone could do to this instrument, and
nothing here needs it: the held-out set answers the question from outside.

**This retires a guess made in the adversarial section.** That section reads
`run-on × self-correction` at 66.7% routing against everyday's `run-on` 0/8 and
concludes the everyday captures must be "harder along some dimension the
adversarial pairing does not carry — likely length and thought count, not the
run-on property itself". The conclusion is right and the reasoning was not
available to it: the gap is not a property of those captures, it is that the
two columns are different functions, and a family that never splits scores zero
on one of them mechanically. **A rate is not comparable to another rate because
the columns share a name.**

### What this does not establish

Nothing here is a new measurement, a new instrument or a new corpus row. It is
one table moved out of a job log and into the record, and one inference in this
file corrected by reading the two scorers. It says nothing about why eight `run-on`
captures in ten are not split — the clause splitter recognising two connectors of the eight
people use is the standing explanation and it is not tested by this. It does
not move any published figure.

The cheapest retest is free: the table is printed by every `language_only`
dispatch, so the next run reprints it and a reader can compare.
## 2026-09-15 — "number two" decided from its left, and the one sealed measure that moved

**The same run, read for a different question.** The section above records
the held-out per-family table out of this run; #91 paid nothing to read it
and states which of its figures were already on record. Nothing here depends
on that table and nothing there depends on this section.

One `macos-26` run, branch `claude/hearth-thread-uq6bmy` at `707ac32`, cut from
`66d338d`:
[run 34960158656](https://github.com/CalvinSalsali04/speak-it/actions/runs/34960158656),
`language_only`, Xcode 26.6, job `Language metrics` **success**.

There is no paired before-run. The "before" column below is the figure already
recorded in this file at `66d338d`, which is the same parser with the one
change removed; the diff against `origin/main` is one property and one
alternative in `ThoughtExtractor.splitClauses`, six `corpusCase` rows, a
regenerated population block and a pinned count. No other executable line
changed, so the movement is attributable to the guard or to nothing.

### The gate, quoted rather than inferred from the job's exit status

```
GATING CORPUS — regression net, authored from the product contract
...
rendering=identity  TOTAL 1410 cases, 0 failing, 1410 clean
CRITICAL 0  BEHAVIORAL 0  METADATA 0  COSMETIC 0
BLOCKING(crit+beh) = 0
corpus gate ok: 0 blocking failures
```

1,404 → 1,410 is the six rows this change adds. **Zero failing is saturated
coverage of a net authored from the contract, not product accuracy**, and it
says the six new rows hold at the labels they were written with — which is the
only thing this container could not establish, since the Swift does not build
here.

### What moved: one measure, one capture

| measure | before (`66d338d`) | after (`707ac32`) | |
| --- | --- | --- | --- |
| everyday clean titles | 245/255 (96.1%) | **246/255 (96.5%)** | **+1** |
| — `work-school` | 47/51 (92.2%) | **48/51 (94.1%)** | **+1** |
| — title defect `preamble 'number two' kept` | 1 | **0** | **−1** |

The remaining title defects are `8 title is the whole capture` and `1 preamble
'what happened was' kept`. In the cost ledger as a gain on **everyday clean
titles**, which is the second sealed measure ever to move; the ledger's single
running total was replaced by one total per measure on the same day, because
`ledger-check.py` refuses to add 246/255 to 254/310 and it was right to.

### What did not move, stated rather than left to be assumed

Every figure this file already records at `66d338d` came back identical:

| set | measures | |
| --- | --- | --- |
| everyday (255) | routing 168/240 · count 193/232 · nothing lost 230/244 · nothing invented 14/22 | — |
| everyday | over-segmented 16 · under-segmented 23 · genuinely ambiguous 15 · ACTED ON ANYWAY 0 | — |
| held-out legacy (389) | destination 233/320 · count strict 254/310 · harm 7 | — |
| adversarial (120) | routing 52/116 · count 78/105 · loss 113/116 · invention 10/24 · clean titles 117/120 · harm 1 | — |
| consequence (56) | destination 51/56 · count strict 34/56 | — |

**Four more figures have no recorded "before" in this file, so "unchanged" is
not something this section may say about them.** Under the rule in "Two
held-out numbers", the clean-sealed measures and range-aware scoring are
printed by `heldout/score.py` on every run and deliberately not restated in
these sections — so there is no earlier value here to compare this run
against, and the honest form is a value rather than a movement. What the run
printed:

| held-out legacy (389) | range-aware count | 271/310 |
| --- | --- | --- |
| held-out clean sealed (378) | destination | 225/310 |
| held-out clean sealed (378) | count strict | 247/301 |
| held-out clean sealed (378) | range-aware count | 263/301 |
| held-out clean sealed (378) | ACTED ON ANYWAY | 7 |

That distinction is small and it is the one this file has been wrong about
before: a figure read off one run and written beside three that *were*
compared reads as a comparison, and the next person quotes it as one.

### The honest size of this

**It is one capture on one sealed measure.** `run-on` is still 0/8 on routing
and 0/8 on count, `multi-thought` 19/40 and 22/40, `sequencing` 7/17 and 8/17:
the family this sits inside did not move at all, and nothing here is evidence
that it will. What the change does is remove a defect that was *stated* in
`Docs/KNOWN_ISSUES.md` as a narrow gap and is now closed, at the price of one
accepted failure pinned as a corpus row.

**The wider fix was sized first and rejected.** The obvious widening — give the
enumerator the same `clauseOpenerPattern` lookahead its sibling rule already
uses — cuts three post-nominal shapes that must stay whole ("the spare key is
under plant pot number two the one by the fence", "our flight leaves from gate
number two the big one upstairs", "my locker is number three the one by the
door"). **The two corpus rows that already existed pass either way**, because
nothing follows the number in them, so the gate as it stood would not have
caught that regression. The three guards above were written for this change and
exist to catch it now. That sizing is the part of this worth keeping; the guard
that shipped is the smaller half of it.

### What review then found, and the two runs it cost

The section above was written after one green run and it was not finished. The
grade on #90 held it on a boundary the change would have **taken away**, which
is the opposite direction from the one being measured and is not visible in any
figure above.

`identifyingNumberContext` declined on a preposition **or** a copula within
three words to the left. The copula arm is right where the number *is* the
thing ("my locker is number three"). It is wrong where a statement has simply
finished and an instruction follows:

| | at `66d338d` | at `707ac32` | at `fc1be70` |
| --- | --- | --- | --- |
| the meeting is tomorrow number two call the dentist | cut | **not cut** | cut |
| my flight is Tuesday number two book the cat sitter | cut | **not cut** | cut |

The old gate cut both, because it asked only whether an instruction followed
the number. **No row in the gating corpus had that shape**, so the gate was
green either way — the same asymmetry this change was written to fix, pointing
the other direction, and found by a reader rather than by an instrument.

The repair splits the lookbehind into `locatingNumberContext` and
`equatingNumberContext`. Both guard the clause-opener alternative; only the
locating arm guards a second alternative whose lookahead is the old gate's own
`actionLeadPattern`. The two rows are pinned.

**Two macOS runs, and the first one failed, which is worth recording rather
than tidying away:**

- [run 34975096286](https://github.com/CalvinSalsali04/speak-it/actions/runs/34975096286)
  on `0f4f589` — **failed**, on exactly the two rows just added, on one field
  of each: `route[0]: expected Memory, got Today`. `count: 2` passed on both,
  so the boundary was restored and the *label* was wrong. Routing was written
  from intuition in the same motion as a splitting fix whose Python emulation
  had been validated against six already-scored rows — and that emulation says
  nothing about routing. A probe that is right about one dimension is not
  evidence about the dimension beside it.
- [run 34976825027](https://github.com/CalvinSalsali04/speak-it/actions/runs/34976825027)
  on `fc1be70` — **success**, after relabelling to `[.today, .today]`:

```
rendering=identity  TOTAL 1412 cases, 0 failing, 1412 clean
CRITICAL 0  BEHAVIORAL 0  METADATA 0  COSMETIC 0
BLOCKING(crit+beh) = 0
corpus gate ok: 0 blocking failures
```

**The repair moved no sealed measure.** Every figure on the green run is
identical to the run at `707ac32` recorded above — everyday 168/240 · 193/232 ·
230/244 · 14/22, clean titles **246/255** with `work-school` 48/51, held-out
233/320 · 254/310 · 271/310 · harm 7, clean sealed 225/310 · 247/301 · 263/301
· harm 7, adversarial 52/116 · 78/105 · 113/116 · 10/24 · 117/120 · harm 1,
consequence 51/56 · 34/56. So the `+1` in the ledger is the enumerator change's
and the repair costs nothing; **no second ledger row is due.**

The label itself was right and the *reason* written beside it took three
attempts, each one wider than the corpus and each killed by a row in it:

| attempt | killed by |
| --- | --- |
| "a dated event is an upcoming item" | `My passport expires in March` — Memory |
| "the named day, not the date" | `The store closes Sunday` — Memory, and `The parcel arrived Friday`, Memory because it already happened |
| **"the speaker has to be somewhere or act by then"** | holds on every row in both clusters |

What survives is the reason one row states for itself: *"an expiry on a named
day is the last moment to act."* `The guests arrive Friday`, `The party is
Saturday` and `The parking pass expires Friday` are Today because the speaker
has to be there or act; `The store closes Sunday` and `Nadia's birthday is
October 12.` are Memory because there is nothing for the speaker to do. A bare
month is knowledge either way, which is a separate cut the notes also state.

**Three passes at one sentence is the point, not an aside.** A stated reason
wider than its own predicate is the defect this file keeps finding in filters,
and the first two attempts here were each contradicted by a row within four
lines of the rows they cited. A corpus note is where a future reader looks the
rule up, so it is the worst place for a rule that is almost right. Caught by
the grade on #90, twice.

## 2026-09-15 — twenty sources are ten populations, and two thirds of the evidence base is test fixtures

**The numbers in this heading and in the prose below are the ones the #71 run
read, and the readable population has grown since.** The generated block in
this same section is regenerated every run and says what it is today — 25
sources, 22 distinct bodies, 12 maximal, after Calvin's #86 added the
trust-closure corpus. The heading is left as the run recorded it, because a
dated finding that is edited to match today's data stops being a record of
anything; what it must not do is go on being quoted as current, which is what
this note is for. The argument the section makes — that a source count is not
a count of independent bodies — is unchanged and is why the gap between twenty
and twenty-five matters less than the gap between twenty-five and twelve.

Every sizing in this file quotes a source count. `plus` is "44 rows over 5
sources"; `wait` is "53 over 15". The census has said since #66 that the source
count "is not a count of independent bodies of material" and printed the
containment pairs, but nobody reduces twenty-eight pairs over twenty sources by
eye, so the caveat read as handled and the twenty is what got quoted — by me,
an hour before writing #71, in the same sentence as "views of one population".

#71 makes the census do the reduction. It is four lines of output and it
changes what the evidence base looks like.

No parser change, no run, no sealed set read. Every figure below is a count
over committed text through `readable_material.readers()`, the same walk the
census and `observation.py` use, reproduced with
`python3 Tools/CorpusRunner/connective-census.py`.

### The reduction

**The block below is generated, not typed.** `baseline_figures.py` recomputes
every figure in it from the corpus walk and `test_baseline_figures.py` fails
when the committed text and a fresh walk disagree, so it describes the corpus
**as it stands now** rather than as it stood on this section's date. Regenerate
it with `python3 Tools/CorpusRunner/baseline_figures.py --write`; do not edit it
by hand. The snapshot this section was written from, on 2026-09-15, was 5,501
distinct utterances over 20 sources reducing to 17 bodies and 10 populations,
of which 3,702 were the gating corpus — kept here so a later regeneration
cannot quietly restate what the section originally said.

<!-- begin generated: population -->

Sources holding exactly the same utterances are one body, grouped first. Then
a body wholly inside another is not a second population. 25 sources reduce to
22 distinct bodies and **12 that sit inside no other**:

| utterances | share of 5,925 | population |
|---:|---:|---|
| 4,088 | 69.0% | the gating corpus in `SpeakItTests` |
| 818 | 13.8% | `Tools/SpeechLab/phase2`, in four byte-identical files |
| 695 | 11.7% | `Tools/SpeechLab/phase2/repair/trust-closure/cases.jsonl` |
| 472 | 8.0% | `Tools/SpeechLab/audit/combined-renderings.jsonl` |
| 163 | 2.8% | `Tools/CorpusRunner/devsets/unfinished.tsv` |
| 123 | 2.1% | `Tools/SpeechLab/phase2/repair/trust-closure/exclusions.jsonl` |
| 121 | 2.0% | `Tools/CorpusRunner/devsets/coordination.tsv` |
| 114 | 1.9% | `Tools/CorpusRunner/devsets/routed.tsv` |
| 85 | 1.4% | `Tools/CorpusRunner/devsets/rambling.tsv` |
| 55 | 0.9% | `Tools/CorpusRunner/devsets/abandonment.tsv` |
| 46 | 0.8% | `Tools/CorpusRunner/devsets/runon.tsv` |
| 45 | 0.8% | `Tools/CorpusRunner/devsets/framing.tsv` |

The four files under `Tools/SpeechLab/phase2` are the same 818 utterances four
times: `adjudication/cases-adjudicated.jsonl`, `data/cases.jsonl`,
`data/renderings.jsonl`, `review/independent-review-pack.jsonl`. A form
appearing only there reads as four sources and is one.

**That column sums to 6,825 and its shares to 115.2%, because the twelve
populations are maximal rather than disjoint.** A body inside no other body
may still overlap one. The excess of 900 counts an utterance once for every
additional maximal population that contains it. Only the union, 5,925, is a
total.

### By kind, and the one place two kinds overlap

Two of the three pairs share nothing: not one utterance is in both
`SpeakItTests` and the SpeechLab tree, and not one is in both the SpeechLab
tree and a development set. The development sets and the fixtures overlap by
114, so the three kinds are 4,088 + 1,333 + 618 = 6,039 against a union of
5,925 and do not add up. Written out so that they do:

| kind | utterances | share of 5,925 |
|---|---:|---:|
| test fixtures only | 3,974 | 67.1% |
| generated renderings (the SpeechLab tree) | 1,333 | 22.5% |
| development sets only | 504 | 8.5% |
| in both a development set and a fixture | 114 | 1.9% |
| **total** | **5,925** | |

**91.5% of everything this project may read — 5,421 of 5,925 — is either a
fixture written to exercise the parser or a rendering generated from a
blueprint.** The material written to look like somebody talking is 618
utterances, of which 504 exist nowhere else.

### The 114 are not spread evenly, and where they land is the interesting part

| development set | also a fixture | of |
|---|---:|---:|
| `abandonment.tsv` | 36 | 55 (65.5%) |
| `runon.tsv` | 13 | 46 (28.3%) |
| `unfinished.tsv` | 45 | 163 (27.6%) |
| `routed.tsv` | 15 | 114 (13.2%) |
| `coordination.tsv` | 12 | 121 (9.9%) |
| `framing.tsv` | 0 | 45 |
| `rambling.tsv` | 0 | 85 |

**That column sums to 121 against a heading of 114**, for the same reason one
level down: 7 of the 114 sit in two development sets each and are counted in
both rows — three in `coordination` and `routed`, two in `abandonment` and
`unfinished`, two in `routed` and `unfinished`. 121 − 7 = 114.

<!-- end generated: population -->

Two sets share nothing with the test suite and three share a quarter or more.
The three that share most — abandonment, run-on, unfinished — are the families
this project has spent the most parser effort on, which is not a coincidence:
a row that motivated a fix tends to end up as the test for that fix.

That is not a historical observation. #79 closed a `routed.tsv` failure on
2026-09-15 and its test carries the row verbatim, so the overlap column above
gained one while the pull request touched no corpus file and every check
stayed green. The table is generated, so it moved; before that it would not
have.

That gives the overlapping rows a status neither bucket describes. They are
the material tuned against *and* the material regressed against, so for the
families where the overlap is heaviest, a green unit suite is partly a
restatement of the examples the rule was written from. It does not make the
suite wrong — a fix should keep passing its motivating case — but the heaviest
row in the table above has most of its set sitting in the test target, which
means a green run on that family is less independent evidence than its row
count suggests, and nothing in the current tooling says by how much.

To be exact about which population this is: the overlap is between the
development sets and the Swift string literals in `SpeakItTests`. It says
nothing about the 1,404-case corpus gate, which is scored from a different
list, and nothing about any sealed set, none of which is read here.

### What this is evidence for, and what it is not

It is not evidence that the corpora are bad. A fixture corpus is the right
shape for regression coverage and that is what `SpeakItTests` is for. (It is
not the 1,404-case corpus gate, which is a different population: what the
census reads here is every Swift string literal in the test target.)

It is evidence about **one thing only: breadth of provenance.** All ten
populations were authored by this project. Not one utterance in the readable
population is speech a person produced without knowing what it was for. That is the
same fact the connective census reached from the other side — four of the
eleven forms it tracks appear in zero readable rows — and it is why five traced
targets are dead on one cause. Our corpora and our parser are blind in the same
places, because the same people wrote both.

A source count hid this. Twenty sources sounds like breadth. Ten populations,
one of which is two thirds and is test fixtures, does not.

### Two things not claimed

**The population is not that many utterances.** The gating corpus is Swift
string literals of twelve characters or more carrying more than one word, so it
picks up assertion messages and explanatory prose beside the test utterances —
"A name followed by a department is an organisation." is counted in it. That
inflates the denominator, so the development-set share in the table above is a
floor rather than a point estimate. It does not touch the provenance finding,
which is about who wrote the material and not how much there is.

**The reduction is by exact utterance set, which is the strict reading.** Two
sources sharing almost all of their rows are two bodies here, not one. The
population count is therefore an upper bound on independent populations, and
the real figure is lower.

## 2026-09-15 — the retrieval-failure sizing left out the one word with volume, and it argues the other way

The 20:38 section below stops the `abandoned-midthought` target on a count:
25 readable sentences contain a retrieval-failure phrase, 6 have one
clause-finally, and all 6 are rows in `unfinished.tsv`. That conclusion still
holds. The count behind it does not cover the family's most common surface
form, and covering it turns a shortage of evidence into evidence against.

No parser change and no run. Every figure here is a count over committed text
taken with `connective-census.py`'s reader, which walks rather than globs and
refuses a source that yields nothing. The population is its 5501 distinct
readable utterances — the corpus files, the SpeechLab tree and the gating
corpus — which is the population **after** the gating corpus was added to that
reader on the same day, roughly three times what a first pass counted. Figures
taken against the smaller population are marked where they appear.

### `wait` was not in the phrase set

The phrases that section names as the six captures' closings are `I forgot`,
`I lost it`, `hold on`, `what was it` and a trailing `I mean`. Counted again
over readable utterances:

| phrase, as that section names it | utterances | where |
|---|---|---|
| `hold on` | 1 | `unfinished.tsv` |
| `what was it` | 1 | `unfinished.tsv` |
| `I forgot` | 9 | 5 `unfinished.tsv`, 4 `SpeakItTests` |
| `I lost it` | 1 | `unfinished.tsv` |
| `I mean`, trailing | 2 | 1 `unfinished.tsv`, 1 `SpeakItTests` |
| **`wait`** | **53** | **34 SpeechLab** (31 of them one frame), 13 `SpeakItTests`, 3 `unfinished.tsv`, 2 `rambling.tsv`, 1 `abandonment.tsv` |

Each phrase is counted as the section writes it, which is not how a first pass
counted them: over the smaller population, `I lost it` read as
`I lost (it|my train)` gave 4 and `I mean` counted anywhere rather than
clause-finally gave 11. Both were caught on
recount by the evaluation thread. They are the same defect this file names
everywhere else — a marker standing in for the judgement it approximates —
committed inside a section arguing that a phrase-keyed detector is the wrong
instrument, which is worth leaving visible rather than quietly correcting.

The five named phrases total **14** on the strict readings, against `wait`'s
**53**.

**`31 of them one frame` was read as 28 by the evaluation thread, and both are
right.** The three that differ are `I was going to, um, ask— wait, …`: a
filler sits inside the frame, so a pattern requiring `going to ask` adjacent
finds 28 and one allowing an interpolation finds 31. Nothing about the row set
differs, which is what both of us first assumed.

Kept at 31, because a hesitation dropped into the middle of a template does
not make it a second template — and the argument here is precisely that these
rows are one generated frame. But the disagreement is the more useful half:
two readers counted "the same frame" stably and differently for two days, and
what separated them was a three-character optional group neither had written
down. A count of a frame is a count of whatever pattern was used for it, and
naming the phrase is not naming the pattern.

`wait` is the marker two of the six failing captures actually turn on — INC49
`Tomorrow I need to, um, wait, I forgot` and INC50 `Next week I should, wait,
I lost it` — and it is the only one of the six forms with more than a handful
of instances. Leaving it out is defensible on its face, because a bare `wait`
is ambiguous in a way `what was it` is not. It is also the omission that
decides the shape of the evidence.

### All 31 of its SpeechLab instances complete the thought

They are one frame, `I was going to ask— wait, …`, and every one of them
carries a finished instruction after the marker: "I was going to ask— wait,
keep track of the Montréal train with Nadia Patel for me." The speaker false-
starts and then says the thing. That is the opposite of the shape
`unfinished.tsv` uses `wait` for.

So a detector reading `wait` as evidence that a frame is still open flags 31
captures that finished, against a `finished misflagged` record of `0/96`. This
is the second falsifier for the family and the first from material nobody here
wrote — the other being `FP27 I think I forgot`, recorded below, which the set
supplies against itself.

The two together bound the shape of any fix more tightly than the sizing did.
A rule keyed on the phrase fails on both. The structural discriminator the
20:38 section proposes — an infinitive or modal frame followed by a finite
clause that cannot fill it — survives both, since `I was going to ask` has its
complement before the marker and `I think` is not a frame of that kind. That
sharpens the design and does not change the decision, which rests on there
being no observations to build against.

### Why 818 new cases did not supply any

The SpeechLab adjudication corpus is the largest readable material the
repository has gained, and it cannot size a family, because a count over it
counts instantiations of a blueprint:

- 818 distinct utterances over **330 distinct five-word stems**;
- the twelve commonest stems account for **308** of the 818;
- `lineage.base_semantic_family` groups them into **137 families over 818
  rows, of which 2 are singletons** — about six renderings per meaning.

So the corpus is 137 meanings rendered six ways, and a count over it counts
renderings.

`phase2/CORPUS-QUALITY-REPORT.md` reports "Structural templates: 816" against
818 cases, with "Largest structural template: 2 records (0.24%)". It caveats
itself in the next paragraph — "not proof of 816 wholly independent syntactic
structures" — and `ADJUDICATION-REPORT.md` lists that gate as passing. The
caveat is right; the headline is the number a reader carries away. Against the
five-word stem the largest bucket is **38 rows, 4.6%**. So the two measures
disagree by a factor of two and a half on distinctness and **nineteen on the
largest bucket**, which is the comparison worth recording: **on this corpus
the skeleton metric is not measuring frame diversity, and no gate is.**

This is not a complaint about the corpus. It was built to test whether one
meaning is read correctly across many renderings, and 44 distinct frames carry
an inserted repetition, which is a real robustness population. Its own report
draws the same line from the other side: "the split remains unfrozen, and
parser evaluation must not be joined to these labels yet." Counting surface
forms is not joining evaluation to the labels, which is why the counts above
are legitimate; scoring these rows would not be.

### What this changes

Not the decision, and not the request for real captures that three stopped
targets rest on. What it changes is what would answer that request. 818 cases
arrived and the readable instance count for the shape under investigation went
from 6 to 6, while the one form with volume gained 31 counter-examples.
**A generated corpus grows the denominator of a robustness test and cannot
grow the numerator of a frequency one.** Those are two questions and they have
to be asked in that order before a family is named.

### What is not claimed

No rate moved and none was measured. The 31 captures were read for their shape
and not scored. That a phrase-keyed detector would flag them is a reading of
the utterances against `ThoughtCompletion.unfinished`, not a run. Nothing here
measures how often anybody actually says any of these things, which is still
the unmeasured quantity and still the reason all of this stops.

## 2026-09-14 — the resultive `so` boundary, measured against a set written by someone else

Two `macos-26` runs over **the same 56 captures**, differing only in the parser:

- **before** — `main` at `acc4249`,
  [run 34904578543](https://github.com/CalvinSalsali04/speak-it/actions/runs/34904578543)
- **after** — this branch at `18c2acb`,
  [run 34905352493](https://github.com/CalvinSalsali04/speak-it/actions/runs/34905352493)

`git diff origin/main HEAD -- SpeakIt/` is two files and 84 executable lines,
all of them #57, and `consequence.tsv` is byte-identical on both sides. So
every movement below is attributable to the resultive boundary and to nothing
else, which is checkable rather than asserted.

### What the set is, and why it counts as independent

Calvin asked for evidence "not authored to fit the implementation... preferably
from another writer, public language data where appropriate, or blinded
generation/rewrite". This is the blinded-generation half. Another thread wrote
it; the generation parameters were committed **before the first capture
existed**, so the ordering is in git rather than in a sentence; and its author
cannot run the engine, because the parser needs Apple's `NaturalLanguage` and
does not build in that container. What it is not: the author had read the rule
under test, which that set's README states rather than hides.

One thing it costs, recorded in the set's own README: **reviewing #62 meant
reading all 56 captures**, and this thread owns parser changes. The evidence
below survives that only because the implementation was frozen first — `git
diff 63e26de HEAD -- SpeakIt/ SpeakItTests/` is empty — so the parser being
measured was chosen with none of these captures in view. For the *next* change
this set is spent.

### What moved

| measure | before (`acc4249`) | after (`18c2acb`) | |
| --- | --- | --- | --- |
| consequence thought count | 30/56 (53.6%) | **34/56 (60.7%)** | **+4** |
| — of the 32 rows that must SPLIT | 6/32 | **10/32** | **+4** |
| — of the 24 rows that must stay WHOLE | 24/24 | 24/24 | — |
| consequence destination | 51/56 | 51/56 | — |
| consequence ACTED ON ANYWAY | 0 | 0 | — |
| everyday routing / count / loss / invention | 168/240 · 193/232 · 230/244 · 14/22 | unchanged | — |
| everyday over- / under-split | 16 · 23 | 16 · 23 | — |
| adversarial | 52/116 · 78/105 | unchanged | — |
| held-out destination / count strict | 233/320 · 254/310 | unchanged | — |
| held-out ACTED ON ANYWAY | 7 | 7 | — |

### Read the guard half honestly, because this is where it is tempting not to

**24/24 on the do-not-split rows is NOT, on its own, evidence of anything.** A
parser that under-splits passes every such row for free, and the split rows sit
at 10 of 32, so most of that 24 is exactly that free pass. Printing it beside a
target rate near the floor and calling it coverage is the defect this file
already names.

What the guard half *does* support is narrower and real. The rule can only fire
where the word `so` appears, and **5 of the 24 whole rows contain it** — `CQ07
CQ09 CQ42 CQ44 CQ50`. Those five are the rows the change could have broken, and
all five held. That is a small, genuine no-cost result, and it is the whole of
what this measurement says about over-splitting.

### The +4 is exactly the shape the rule targets, which is the strongest part

Seven of the 32 split rows contain `so`: `CQ06 CQ08 CQ10 CQ43 CQ45 CQ49 CQ55`.
Of those, **four carry a resultive `so` in front of a first-person obligation**
— the shape #57 admits. The other three open with `so` as a discourse marker
and join their clauses with something else.

The thought count moved by **exactly four**. A rule that had learned something
broader, or something accidental, would not land on precisely the rows its
stated condition describes and no others. The three discourse-`so` rows still
fail, correctly declined.

### The finding that is not about #57

**The change fixes one connector out of eight, and the family has eight.** The
set rotates `and`, `so`, `which means`, a bare comma, `then`, `that means`,
`because of that`, and juxtaposition, five captures each. After the change the
split rows stand at 10 of 32, so **22 captures of one phenomenon — a person
states a fact and then the errand it creates — are still read as one thought.**

That is not an argument against #57, which does what it claims. It is the
measurement saying the phenomenon is a discourse relation and the
implementation is a list of coordinators, and that the next improvement here is
probably not a ninth coordinator. Recorded as a target rather than acted on.

### The verdict, under the policy of 2026-09-12

Calvin's rule: strong independent evidence plus a small unexplained sealed
movement may be merged with the cost documented; weak or self-authored evidence
plus a sealed regression holds; meaningful regression on multiple independent
measures does not merge.

The independent evidence is strong and it is not self-authored. **No measure on
any other set moved in either direction** — everyday, adversarial and held-out
destination are identical to the row. The only negative signal remains the one
held-out thought-count row from 2026-09-11, already in the cost ledger, and
range-aware scoring accepts the count it produces. Merged on that basis.

## 2026-09-14 — the next target, traced to source, and why it is not being built

After #57 the consequence set reported 34 of 56 on thought count, with 22 of
the 32 must-split captures still arriving as one thought. The reading published
beside that number was that the rule fixes one connector of eight, and that the
next improvement is probably not a ninth. This section traces that claim to the
source, tries to size it against every readable set in the repository, and
stops there on purpose.

### What the source says

The splitter does not have a list of eight connectors. It has three unrelated
mechanisms, and three of the eight are in none of them.

| connector | where it is handled |
| --- | --- |
| `and` | `splittableCoordinatorRanges`, a literal regex, and in `connectorRun` |
| `so` | the same regex behind a first-person-obligation lookahead, and in `connectorRun` |
| comma | `splitClauses`, only before an `actionLeadPattern` |
| `then` | `connectorRun`, plus its own branch before a `triggerLeadPattern` |
| juxtaposition | `ClauseJuxtaposition`, its own module |
| `which means` | nowhere |
| `that means` | nowhere |
| `because of that` | nowhere |

The last three occur in `SpeakIt/` only inside comments. `connectorRun` is
`so|and|also|then|plus`, so it carries two more forms the consequence rotation
never used; the table is that rotation's eight and not an inventory of the
splitter.

Counted by mechanism rather than by connector, the picture is sharper than
"eight surface forms". Two of them have a dedicated boundary finder. Four ride
a shared run of connector words that can only open a boundary when an action
or a trigger lead follows it. One has a module to itself. Three have nothing at
all.

The interesting half is not the absence. It is that **the machinery deciding
whether a tail is a thought of its own is already general, and is only ever
consulted at positions a two-word regex nominates.** `isIndependentConjunct`
takes spans into a `SentenceContext` rather than loose strings, asks
`hasSubjectPredicate` and `hasOwnSubject` about them, and already carries a
relation distinction: a `resultive: Bool`, derived from whether the boundary
ends in `so`, which turns on the guard that a consequence needs a cause and
that an imperative is not a fact.

So a stronger design is visible from the source alone, without measuring
anything: candidate boundaries generated separately from the adjudication that
accepts them, each candidate carrying a relation rather than one boolean
hard-wired to one word. `which means`, `that means` and `because of that` are
all resultive and would want precisely the guard `so` already has.

That is a design sketch. It is not a plan, for the reason below.

### Why it is not being built

**Nothing in this repository can size the family.**

`Tools/CorpusRunner/connective-census.py` counts how many readable rows contain
each form, across the seven development sets and SpeechLab's renderings and
audit data. It reads no sealed set: sources come from `corpus_paths.readable()`
plus a declared SpeechLab list checked against `corpus_paths.sealed()` at the
point of use, and it refuses to run rather than score a zero if any source
stops yielding rows.

Run it for the figures rather than reading them here. The load-bearing result
is the one this document does state, because a test recomputes it: **`which
means`, `that means`, `because of that` and `therefore` appear in no readable
row at all**, while `and` and `so` appear in hundreds.
<!-- recomputed: absent-connectives which means, that means, because of that, therefore -->

**The two lists are the same list.** Every connective the splitter handles is
attested in readable material — including `also` and `plus`, which the census
found only because reading `connectorRun` turned them up and which the
consequence rotation never used — and every
connective it does not handle is attested in none. That correspondence is not a
coincidence and it is not a compliment to the parser: the corpora and the rules
were written by the same hands, working from the same intuitions about how a
sentence goes. The parser handles what we thought to write down. A census over
our own material can therefore confirm that a family is unsizeable and can
never establish that one is rare.

**Read that in both directions, and the second one matters more.** A zero is
not evidence that people do not say these things. Every row counted was
authored by this project, so the census largely records what we have thought to
write down, and treating it as a fact about speech would be the circular step
that has already killed four targets.

What it does settle is narrower and sufficient. The only material in which this
family appears at all is the consequence set — and that set's eight-connector
rotation is a **design parameter fixed in advance**, not an observation of how
anyone talks. Choosing the next parser change from where that set fails is
optimising against a sealed set at low resolution, which is the single thing
the set exists to prevent. It would also be the fifth instance of the pattern
that killed the previous four: the readable material could not size the family,
and every example was a sentence written for the occasion.

The readable sets cannot break the tie either: they are at or near their
ceilings, which is why they have stopped producing new targets rather than
because the parser is finished. Their rates are recorded in their own sections
above and are deliberately not repeated here — this document already carries
three copies of them, and a fourth is how the count in `choice-balance.py` came
to be two generations out of date while everything around it was correct.

### What would settle it

Real recordings, which is the open ask from 2026-09-11. Four properties matter
more than the count: whatever someone happened to record rather than captures
picked to match a family we named; more than one speaker, since one author is
still one author; whole recordings rather than sentences; and a portion sealed
before any thread reads a line.

Until then this is recorded as an **architectural observation with a design
sketch and no evidence of use** — which is its honest state — and not as queued
work. Building a relation model for connectives that appear zero times outside
a set authored to exercise them would be the ninth coordinator with a better
vocabulary.

### What is not claimed

- Not that the current splitter is adequate. It plainly under-splits on the
  consequence set, and that number stands unchanged.
- Not that the three absent connectors are rare in speech. This repository
  cannot say either way, and the census says so in its own output.
- Not a measurement of any kind. Nothing here ran the parser: the table of
  mechanisms is read from source and the census reads corpora, in a container
  where the engine does not build.

## 2026-09-14 — correction: I read the wrong column, and what survives it

Commit `bbc9f97` reports that the everyday corpus contains no instance of the
word "so" and that the resultive-`so` rule fires on none of its captures, and
concludes that "everyday unmoved" was vacuous evidence for #57. **That is
wrong, and the cause is my own bug.**

`everyday.tsv` keeps its utterance in the **third** column; the development
sets and `heldout.tsv` keep it in the second. My scan hard-coded column two, so
for the everyday set it searched a different field entirely and found nothing.
`leak-check.py` has a function whose whole purpose is to avoid this, with a
docstring naming these exact files — *"hard-coding a column is how this check
silently starts comparing the wrong field and passing for the wrong reason"* —
and I had read it earlier the same session.

It surfaced because the everyday README describes a `filler` family of 18
captures, which cannot coexist with zero disfluency markers. The instrument
said zero and a document said eighteen, and the document was right.

**Corrected counts, header-driven:**

| corpus | captures | contain "so" | rule can fire on |
|---|---|---|---|
| devsets | 619 | 27 | 7 |
| everyday (sealed) | 255 | 34 | **3** — E02, M03, W28 |
| heldout (sealed) | 389 | 16 | **1** — C283 |
| adversarial (sealed) | 120 | 1 | 0 |

The everyday set is also the **most** spoken-sounding corpus here, not the
least: 24% of its captures carry a spoken marker against 11% for held-out and
9% for the development sets. The opposite of what I published.

### What survives, and it matters for #57

**The claim about adversarial was right and the claim about everyday was
wrong.** The rule cannot reach any adversarial capture, so "adversarial
unmoved" says nothing. It can reach three everyday captures, so "everyday
unmoved" is real evidence — modest, and worth stating precisely: three is an
*upper bound*, because the regex is only half the rule and the left-side
`hasSubjectPredicate` guard cannot be evaluated without the tagger. So the
change affects between zero and three sealed, never-tuned-against captures, and
no everyday measure moved. At worst it did nothing there; at best it handled
three correctly. Neither is a regression.

**The held-out derivation is untouched.** `heldout.tsv` keeps its utterance in
column two, which is what I read, so that count was right: the rule can reach
exactly one held-out capture, C283, and the held-out thought count moved by
exactly one. A rule that changes nothing where its pattern does not match makes
those the same capture. Derived from the rule's reach, not from the sealed
failure, which stays unread.

C283's expected-count label is `1-2`. The strict reading compares against 1, so
splitting it into 2 is marked wrong for producing a count its own label lists
as correct.

### The lesson, which is not the one I would have guessed

I have spent this session cataloguing guards that pass vacuously, and I found
this by looking for one more of them. The bug was not a vacuous guard — it was
a **scan that read the wrong field and returned a confident zero**, which is
the same family as the harvest defect that made `leak-check.py` read 18% of the
gating corpus, and the same family as the `rglob` that descended no symlink.

A zero is the most dangerous result a scan can return, because it is what a
correct scan of clean material returns. Every other number invites the question
"is that right?" and zero invites "good". **A scan that reports zero has to be
run against a case known to be positive before the zero means anything** — the
control the evaluation thread insisted on for its mutation harness, which I did
not apply to my own one-off.

## 2026-09-11 20:38 — `abandoned-midthought` traced: the detector only ever reads the last word

Run 34644656689, macos-26, branch at `8cfa1f5`, `language_only` with
`devset_failures`. No parser change; this run exists to print rows nobody had
looked at. Every rate is unchanged from the 20:14 run.

**`abandoned-midthought` is 3 of 9 and had never had its failures listed.** It
was the only weak family in the set with no recorded analysis — `1/10`
`incomplete-complement` and `2/8` `trailing-function-word` both have one, and
both turned out on inspection to be largely declined-by-design rather than
broken. This one is not.

| id | capture | got |
|---|---|---|
| INC49 | `Tomorrow I need to, um, wait, I forgot` | 1 row, **Today**, resolved, **due=Tue** |
| INC50 | `Next week I should, wait, I lost it` | 1 row, Today, resolved |
| INC51 | `I was going to, uh, hold on` | 1 row, Memory, resolved |
| INC52 | `Remind me to, um, what was it` | 1 row, Today, resolved |
| INC56 | `I need to I need to` | 1 row, Today, resolved |
| INC57 | `I was going to call, I mean` | 1 row, Memory, resolved |

The three that pass — INC53 `I need to, hmm`, INC54 `Tomorrow I want to um`,
INC55 `I have to uh` — are the three whose filler strips to a clause that
**ends on `to`**. That is the whole difference between the halves of this
family, and it names the mechanism exactly.

**`state=resolved` on all six is the part that matters more than the miss.**
These are not captures the app is unsure about. It is confident. Four of the
six become Today tasks, and INC49 is dated Tuesday — one of the set's two
`unsafe` rows, the other being INC33, both already recorded at 15:45. A person
who lost their thought out loud gets a task they never finished asking for,
with a date on it.

### Root cause: `ThoughtCompletion.unfinished` inspects the final token and its
### predecessor, and nothing else

Reading the source rather than inferring from the rates: the function takes
`tokens.last`, tests its lexical class, tests `tokens[tokens.count - 2]` for
`isVerb`, and in the `to` branch counts how many `to` tokens the clause holds.
There is no other reach. Every unfinished thought it can detect is one that
**stops** mid-frame.

So a capture where the speaker opened a frame and then said anything at all
afterwards is invisible to it, however unfinished the frame is. That is not a
missing rule for these six sentences; it is the shape of what the detector can
see. `SemanticGap.incompleteThought` — the representation — already exists and
is right. The gap is reach, not vocabulary.

Five of the six close on a **retrieval failure**: the speaker says the thought
is gone (`I forgot`, `I lost it`, `hold on`, `what was it`, a trailing
`I mean`). Those words are evidence about the material *before* them, and
nothing reads them that way. `SpeechRepair` has a closed `bareWithdrawal` class
for "the speaker took it back" and there is no counterpart for "the speaker
lost it" — the two are different destinations, `Abandoned` against
`Incomplete`, and only one is modelled. INC56 is the separate, already-recorded
marker-count premise.

### Not being built, and the reason is the same one as last time

Sized over readable material with a walk, not a glob, and never touching a
sealed path: **102,420 readable sentences; 25 contain a retrieval-failure
phrase anywhere; 6 have one clause-finally; all 6 are rows in
`unfinished.tsv`.** There is not one instance in the corpus that somebody here
did not write for this purpose.

The set also carries its own falsifier, which is the argument against a quick
fix in one row: **FP27 `I think I forgot` is labelled `Complete`**, as are
FP22 `I forgot my keys` and FP23 `I forgot what Sarah said`. Any rule keyed on
the phrase flags FP27 and puts the first crack in a fallout record that is
`0/96`. The structural discriminator that would survive it — an infinitive or
modal frame followed by a finite clause that cannot fill it, which is why
`I think` is safe and `I need to` is not — reaches INC49, INC50, INC52 and
INC56 and honestly misses INC51 and INC57. Worth building against real
captures. Not worth building against six sentences we wrote, where the
discriminator and the data would have the same author.

**This is the third target in a row to end here**, and the coincidence is the
finding rather than any one of the three:

| target | why it stopped |
|---|---|
| doubled infinitive frame (INC56) | 1 readable instance, ours |
| retrieval-failure tail (this) | 6 readable instances, all ours |
| deliberation, `decision` 1/6 | all readable rows by one author |

Three independent weaknesses, three different layers, one cause: past the
development sets we wrote, there is no material. The instruments are not the
bottleneck any more and neither is the parser. **Recorded here as the
measurement behind the request for real captures**, so that request rests on
three traced failures rather than on a preference.

## 2026-09-11 20:14 — the resultive guard tightened; nothing moved, and a hypothesis died

Run [34642431339](https://github.com/CalvinSalsali04/speak-it/actions/runs/34642431339),
`macos-26`, branch at `63e26de`. Measures the review changes to the section
below. Everything committed after `63e26de` is documentation.

**Every measure is identical to the 19:29 run.** Gating corpus **1404 cases, 0
failing** (three new cases, all passing); held-out 233/320 destination and
**254/310** thought count; everyday 168/240 · 193/232 · 245/255; adversarial
52/116 · 78/105 with over-segmented still 9; rambling 69/73 · 62/73 with
`knowledge-action` spoken still 3/3; coordination, routed, framing and runon
unmoved.

That is the intended result and it was predicted in advance: the change
tightens the resultive guard and cannot loosen it, so the only movement
available to it was a loss, and there was none.

### What changed and why

A review of the section below found two things, both correct, both checked
against source before acting.

**The bound as published was false.** "The change can only ever add a boundary"
is not true: the resultive alternative is written to consume both words of `and
so`, so for "X and so I need to Y" the boundary widens from `␣and␣` to
`␣and␣so␣`, `resultive` computes true off its trailing `so`, and the left-side
requirement lands on a boundary that `and` alone never applied it to. Where X
does not stand alone that is a boundary **removed**. The correct statement is
narrower: *the change adds a boundary where a statement is followed by a
first-person obligation, and changes the extent of an existing `and` boundary
in the single case where `and so` precedes one.*

**The left-side test was carried by its weaker arm.** `leftCanStandAlone` is an
OR whose second arm, `ActionabilityReader.read(left) != .ambiguous`, is true of
a bare imperative — so an instruction could serve as a cause and "Pick up the
dry cleaning so I need to bring the ticket" would split. The guard now reads
`hasSubjectPredicate` alone. The argument for this boundary is that a
commitment is not a property of the fact that prompted it; an instruction is
not a fact. The ticket is *how the dry cleaning gets collected*, and splitting
strands "bring the ticket" as a row that means nothing alone.

Three regression cases, in the shape that had no coverage at all — verified
first: the only `corpusCase` utterances containing `and so` are the two added
here. "The lease ends in March and so I need to draft the renewal" at 2, "Okay
and so I need to call Catherine tomorrow" at 1, and the imperative-cause guard
at 1. The first two are a pair: the same widened boundary has to give opposite
answers on them.

### The negative result

**The held-out row did not come back.** Thought count is 254/310 before and
after, so whatever moved at 19:29 is not an imperative-cause split — that was
the plausible candidate and it is now ruled out. The ledger entry stands at −1.

No further hypothesis about that row will be tested by reading it. What is left
is the honest position: one sealed row moved, the cause is not known, and the
two sealed sets that are not held-out did not move at all.

## 2026-09-11 19:29 — the `so` split: its target family fixed, and one sealed row lost

Run [34638463387](https://github.com/CalvinSalsali04/speak-it/actions/runs/34638463387),
`macos-26`, `language_only` with `devset_failures`, branch at `a64dde6`.
The only parser change since `2cc2ac5` is the resultive-`so` boundary, so every
movement below is attributable to it.

### The target

`knowledge-action` thought count, spoken half: **0/3 → 3/3.** RB17R, RB18R and
RB19R now separate the fact from the errand it caused. The clean half stays
3/3, so the twin gap on that family is closed.

The cause was that clause splitting had one coordinator. `splittableAndRanges`
matched `\s+and\s+` and nothing else; `splitClauses` carries `so` in
`connectorRun` but requires `actionLeadPattern` immediately after, and that
excludes `obligationLead` — so "so book the service" could split and "so I need
to book the service" never could. Every clean twin in the family joins with
`and` and every rambling twin with `so`, which explains all six rows.

### What it cost

| Measure | `2cc2ac5` | `a64dde6` | |
| --- | --- | --- | --- |
| Gating corpus | 1393 cases, 0 failing | **1401 cases, 0 failing** | +8 cases, all passing |
| Held-out destination | 233/320 | 233/320 | — |
| Held-out thought count | 255/310 | **254/310** | **−1** |
| Held-out acted-on-anyway | 7 | 7 | — |
| Everyday routing / count / titles | 168/240 · 193/232 · 245/255 | 168/240 · 193/232 · 245/255 | — |
| Adversarial routing / count | 52/116 · 78/105 | 52/116 · 78/105 | — |
| Adversarial over-segmented | 9 | 9 | — |
| coordination | 115/121 | 115/121 | — |
| routed | 74/84 · 77/79 | 74/84 · 77/79 | — |
| framing | 41/45 · 43/44 | 41/45 · 43/44 | — |
| runon | 42/46 · 35/44 | 42/46 · 35/44 | — |

**The held-out count lost one row and this section does not explain it away.**
That set is scored non-verbose on purpose and its failures are not read to
steer parser work, so which capture moved is not known here and was not looked
up. What can be said: across the three sealed sets — 764 captures — exactly one
measure moved, by one row, and the two sealed sets that are not held-out did
not move at all. That is consistent with the bound the change was designed to
have, and it is still a real loss on the only set that stands in for unseen
speech.

### The over-split risk, bounded from readable material alone

Since which held-out capture moved cannot be looked up, the next best thing is
to bound the rule's reach where the text *can* be read. Over every readable
sentence in the repository — development sets, the unit tests, and prose in
`Docs/` — **13,396 sentences, of which 258 contain the word "so"**:

| | |
| --- | --- |
| readable sentences scanned | 13,396 |
| containing the word `so` | 258 |
| matching the new admission | **14** |
| left untouched | 244 |

So the rule declines 95% of the `so` sentences it sees. One of the fourteen is
a `GUARD:` note scraped out of a test file rather than an utterance, leaving
thirteen, and every one is accounted for:

- **Four are held by the left-side guard and did not split** — "Okay so I need
  to call Catherine tomorrow", "Um so I need to, uh, call the dentist…", "Right
  so I should email the landlord", RB01R. Verified, not assumed: the gate is at
  0 failing over 1,401 cases and `errand-rambling` stayed 8/8.
- **Five split and are correct** — RB17R, RB18R, RB19R (the target family, now
  3/3) and the two new corpus rows, all at their labelled counts.
- **Two rows now over-count, and in both the new boundary is right** — RB30C
  and RB30R, for the reason below.
- **Two split correctly inside rows that already passed** — RB28R and the
  `and then also` corpus row, both still at their labelled counts.

**Zero of the thirteen produced a wrong new boundary by the labels in this
repository.** That does not explain the held-out row and is not offered as
though it did — the held-out set exists precisely because readable material
runs out. It does say the loss is not a systematic over-split: if the rule
fired loosely, 258 `so` sentences and 13,396 readable ones is enough material
for it to show, and it does not.

### RB30 went 4 rows to 5, and the count column was hiding the reason

RB30C and RB30R now over-produce. The boundaries tell a different story from
the count:

- Correct: `[picked up the results and the iron is low again]` `[book a follow
  up]` `[start the supplements]` `[tell Mum]` — 4 rows, cutting at the `so` and
  at two `and`s.
- Before: it cut after "results", missed the `so` entirely, and scored **4** —
  the right number from a missing boundary and a spurious one cancelling.
- Now: the `so` boundary is correct and the spurious "results / iron is low"
  cut survives, so the arithmetic stops cancelling and the row reads 5.

So the regression on this row is the *exposure* of a pre-existing `and`
over-split, not a new defect: "I picked up the blood work results and the iron
is low again" is a result and what the result says, which is one thought. That
is the next change, and it is deliberately not bundled here — two parser
changes in one run make neither attributable.

It is also the concrete demonstration of a claim made earlier today from
reading alone: **a count column cannot see a wrong cut.** RB30 passed for a
week while cutting in the wrong place.

### Labels corrected in the same branch

RB28 and RB30, both twins, wanted 3 thoughts and want 4 — each enumerates four
units. Three of the four rows were failing at 3 and pass at 4, which is the
direction to distrust; the check that makes it honest is that RB28R returned 3
and *passed* against the wrong label and now fails, so the relabel created a
failure rather than only removing them.

RB14 (`give Dimitri the blue chair`) is marked as a known-bad row rather than
fixed. It reaches Memory because `give` is absent from
`ActionabilityReader.actionVerb` and `hasImperativeShape` requires the
determiner directly after the head verb, so a recipient between them blocks the
shape rule — the prepositional form "give the chair *to* Dimitri" passes.
Across 3,020 readable utterances every other double-object dative uses a verb
already on the list, so the only capture the gap costs is the one written for
this set. A real structural blind spot with no measured user impact, recorded
in `dropped-language-candidates`.

### The earlier "filler is not the problem" headline is withdrawn as stated

The 16:54 section below reads the 15 zero-gap pairs as showing filler costs
nothing. It does not support that. Those families' clean twins are at 8/8, 4/4
and 3/3 — at ceiling — so a zero gap has no headroom to appear in. Zero
failures over 15 pairs bounds the per-capture filler cost at about **18%**
(95%), and over errand's 8 pairs alone at about 31%. Not at zero.

What those rows do license: **filler does not break the cases the parser
already handles.** The structural finding is unaffected and is now demonstrated
rather than inferred — the family that fell to 0/3 came back to 3/3 on a change
to clause boundaries and nothing else. Raised by the evaluation thread; the
arithmetic was checked here before accepting it.

## 2026-09-11 16:54 — the rambling set's first reading, and it is not filler

> **Corrected at 19:29 (section above).** The "filler is not the problem"
> reading below overstates what these pairs support: the three zero-gap
> families are at ceiling on their clean halves, so 15 pairs bound the
> per-capture filler cost at about 18%, not at zero. The section is left as it
> was written, because it records what was reported at the time.


Branch `claude/hearth-thread-tod920` at `d9366f1`,
[run 34623965550](https://github.com/CalvinSalsali04/speak-it/actions/runs/34623965550),
`macos-26`. No parser code has changed since `2cc2ac5`, so every other figure
in the 15:45 section below still stands; this section adds one set.

**Why the set exists.** The five readable development sets are at or near their
ceilings — coordination 115/121, routed 74/84, framing 41/45 — while sealed
everyday routes 168/240 and adversarial 52/116. Instruments that almost
everything passes have stopped discriminating, and parser work steered by them
is steered blind. `Tools/CorpusRunner/devsets/rambling.tsv` writes every capture
twice under one id stem, `RB04C` clean and `RB04R` the same content spoken with
filler, so the clean family is a control and **the measurement is the gap
between the twins**, with content held fixed by construction.

*Measured over `rambling.tsv` at 57 rows.* (Added 2026-09-15, recording the
state this run read rather than the state today; `stale_fingerprints` in
`baseline_figures.py` fails once the two differ, which they now do.)

Whole set: destination 54/57, thought count 46/57. Neither number is the
finding, and the per-family gaps are:

| pair | destination (clean → rambling) | thought count (clean → rambling) |
|---|---|---|
| errand (8) | 8/8 → 8/8 | 8/8 → **8/8** |
| restart (4) | 4/4 → 4/4 | 4/4 → **4/4** |
| chained (3) | 3/3 → 3/3 | 3/3 → **3/3** |
| decision (4) | 3/4 → 3/4 | 4/4 → **1/4** |
| knowledge-action (3) | 3/3 → 2/3 | 3/3 → **0/3** |
| long (3) | 3/3 → 3/3 | 1/3 → **2/3** |

`coherent-long`, the guards that must stay one row however long they get, is
7/7 on destination and **5/7 on count**. Those seven rows are **five distinct
contents**, two of them written twice — the set was reviewed after this run and
the guard count above overstates what is being guarded.

**Two corrections to this section, from that review.** Neither changes a
measured figure; both change what the figures are worth.

*The `restart` result is weaker than it reads.* In three of its four pairs, and
in all four `decision` pairs, the clean twin is a **literal suffix** of its
rambling twin. "Return the final clause" therefore scores 7/7 on those rows and
produces a twin gap of exactly zero — which is this instrument's signal for
"filler cost nothing". So the headline stands on `errand` (8 pairs) and
`chained` (3), where the filler is interleaved and no suffix heuristic helps;
`restart`'s 4/4 → 4/4 is consistent with it but is not evidence for it. Five
new pairs put the disfluency mid-utterance with a committed errand in front of
it, so the heuristic returns one row where two are wanted.

*The destination column cannot discriminate on this set.* 51 of the 57 rows
here want Today, so answering "Today" to everything scores 89%, and every
destination twin gap above is a ceiling effect. The count column carries the
signal. The set has since gained rows wanting Memory **and** two thoughts,
because previously every Memory row was `coherent-long` and every
`coherent-long` row wanted one thought — so a single over-splitting defect
would have moved both columns and read as two independent findings.

**The headline is that filler is not the problem.** Errands, false starts and
discourse adjuncts carry their filler at no cost at all — three families, 15
pairs, not one row lost between the clean twin and the spoken one. That is a
real result and it contradicts the assumption the set was built to test. It
also independently confirms what the source reading found earlier today: the
2026-08 rambling analysis's C1, C4, C5 and C11 are fixed, and C6's mid-sentence
`like` is handled for the shapes these rows use.

**What does cost rows is structure.** Knowledge-action — a fact and the errand
it implies — goes 3/3 to 0/3 on count once it is spoken, and deliberation that
lands on a decision goes 4/4 to 1/4. Both are clause-structure problems that
filler merely accompanies.

**One family reports that its own label is suspect, which is the design
working.** `long` is 1/3 clean against 2/3 rambling: the clean twin does worse
than the spoken one, so filler cannot be what breaks it and the honest reading
is that either long captures fail on length regardless, or my thought counts
for those three are wrong. It is listed rather than quietly dropped.

**Do not quote any of these as rates.** The families are three and four
captures wide; 0/3 is three captures. What the set gives on a first reading is
a direction and a named set of rows, not a measurement anybody should put in
front of a decision. The per-row failures were not printed on this run —
`devset-failures.sh` kept its own hardcoded list and the set was only wired into
`language-metrics.sh`, fixed in `178dd05`.

## 2026-09-11 15:45 — `main` at `2cc2ac5`, the abandonment figures measured

Branch `main`,
[run 34617253884](https://github.com/CalvinSalsali04/speak-it/actions/runs/34617253884),
`macos-26`, `language_only` with `devset_failures`. **This is the current
baseline.** No parser code changed between `9d91a0b` and `2cc2ac5`, and that
is checkable rather than asserted: `git diff 9d91a0b 2cc2ac5 -- SpeakIt/
SpeakItTests/` is empty, and the last commit touching `SpeakIt/` at all is
`4739dd8`, an ancestor of `9d91a0b`. The thirteen pull requests in between are
scorers, self-tests and documentation. So the one instrument that moved is the
one that was repaired.

| instrument | 12:34 (`9d91a0b`) | now (`2cc2ac5`) |
|---|---|---|
| **abandonment recall** | 24/24 † | **23/24 (95.8%)** |
| **abandonment fallout** | 0/24 † | **1/24 (4.2%)** |
| **abandonment mixed** | never published | **5/7** |
| abandonment unsafe | not reported | 0 |
| gating corpus | 1393, 0 failing | 1393, 0 failing |
| held-out destination / count | 233/320 · 255/310 | 233/320 · 255/310 |
| held-out acted on anyway | 7 | 7 |
| everyday routing / count | 168/240 · 193/232 | 168/240 · 193/232 |
| everyday loss / invention / titles | 230/244 · 14/22 · 245/255 | 230/244 · 14/22 · 245/255 |
| everyday over- / under-split | 16 · 23 | 16 · 23 |
| everyday acted on anyway | 0 | 0 |
| adversarial routing / count | 52/116 · 78/105 | 52/116 · 78/105 |
| adversarial over- / under-split | 9 · 18 | 9 · 18 |
| adversarial acted on anyway | 1 | 1 |
| coordination | 115/121 | 115/121 |
| routed destination / count / acted on anyway | 74/84 · 77/79 · 3 | 74/84 · 77/79 · 3 |
| framing | 41/45 · 43/44 | 41/45 · 43/44 |
| runon | 42/46 · 35/44 | 42/46 · 35/44 |
| unfinished recall / fallout / unsafe | 34/57 · 0/96 · 2 | 34/57 · 0/96 · 2 |

**The correction was right in all three places, including the one this file had
never printed.** `recall 23/24`, `FALLOUT 1/24`, `mixed 5/7` — derived from
reading the scorer's source on 2026-09-11, before any run could check them. The
fallout is `ABN38 Never mind the gap`, returning `rows=0 retracted=False`: the
cancel pattern reads a named object as an item being managed and deletes words
the speaker kept. All four documented rows are now named in the report itself
rather than counted into a total.

Both scorers' new `scored N of M labelled` lines print on a clean run —
`55 of 55` and `163 of 163` — which is the point of putting them on every run
rather than only on failure. The everyday ranking marks from `2cc2ac5` print
live too: `location 12 9/12 ... ← ranked on invention 0/1` is a family holding
a table position that nothing printed on its line explains, now saying so.

### The two `unsafe` captures, and why they are not a defect of their own

`unfinished` has carried **2 unsafe** — a fragment given a date, reminder or
operation — in every baseline section in this file, with no ids attached and
nothing gating it. They are **INC33 `Tomorrow I want`** and
**INC49 `Tomorrow I need to, um, wait, I forgot`**, both returning
`due=['Tue'] remind=[] op=False`.

Both are also among the 23 recall misses: `rows=1 state=resolved`. Nothing
decided either capture was unfinished, so no guard was asked to decline
anything.

**The scorer cannot establish that, and it reads as though it can.** In
`unfinished-score.py` the `if committed:` branch sits outside the
`if flagged:` / `else:` pair, so a correctly flagged capture still carrying a
date would count as unsafe too. `UNSAFE 2` cannot distinguish "the guard held
on the others" from "there was nothing for it to hold".

**The source settles it, and the capture counts do not.** In
`ThoughtOrganizer.organize`, the `ThoughtCompletion.unfinished` check is the
**first `return` in the function**, and its return names every commitment
field: `dueDate: nil, reminderDate: nil, reminderDelivery: .none,
recurrenceRule: nil, locationIntent: nil`, with the words kept. No path reaches
a commitment without passing it.

That is a proof rather than an association. A flagged capture returns with
every commitment nil, so `committed` is false, so it cannot be counted unsafe.
**`unsafe` therefore reaches 0 when recall reaches 57/57, whatever else is
true.**

**A first draft of this section gave the wrong reason for it, quoting the
guard's own comment: "checked before anything reads a date".** That comment was
false. `dueDate`, `reminderDate`, `reminderDelivery` and `recurrenceRule` are
all resolved forty lines earlier; the guard discards them rather than
preceding them. The conclusion survives because what protects the capture is
the exhaustive `nil` list, not an ordering — but the guard is therefore only as
durable as somebody's memory: `OrganizedThought.init` defaults three fields,
so a future commitment-carrying field with a default would compile at that call
site unchanged and be adopted silently. The comment is corrected in this
change. Removing the defaults is the real fix and is not in this change: it is
**eight construction sites across four files**, and it needs the unit suite.

Found by the evaluation thread reading the source rather than accepting the
quotation — which is the rule this file opens with, applied to this file. It is the recall miss's blast radius, not a hole beside it.

That decides what gets written down. `unsafe` is not its own
`Docs/KNOWN_ISSUES.md` entry — a second entry would double-count one defect,
the way a farewell once counted as both a title defect and an invention. But
the recall gap had no entry either, so the behaviour a person actually meets —
"Tomorrow I want" arriving as a Today task dated tomorrow — was documented
nowhere. It has one now, **"A verb with no object is not read as an unfinished
thought"**, carrying the dated-fragment consequence inside it as the severity.
Close the gap and both halves retire together.

The set corroborates that, and a first draft of this section overstated how
much. The pair is real:

| capture | flagged? | unsafe? |
|---|---|---|
| INC01 `Tomorrow I want to` | yes | no |
| INC33 `Tomorrow I want` | **no** | **yes**, `due=['Tue']` |

**The count around it was wrong, and it was wrong the way a paraphrased
predicate is always wrong.** A regex over the 57 `Incomplete` rows matched
fourteen, and the draft then described them as carrying "a resolvable temporal
expression" and listed eight. Ten are flagged; **four are unflagged — INC05
`Later I should`, INC33, INC49 and INC50 `Next week I should, wait, I lost
it`** — and only two of the four are unsafe. So "the only two unflagged
captures carrying a resolvable temporal are the only two unsafe" was false. The
regex matched `later` and `at some point`, which resolve to no day at all; what
was run and what was reported were different predicates, and the narrowing
happened in the prose rather than in the code.

Why INC05 and INC50 are undated is a hypothesis, not a finding: `later` and
`next week` name no single day, and `wait, I lost it` may reach the abandonment
path and produce no row. Neither has been checked. **Nothing in the conclusion
rests on it**, because the conclusion rests on the early return above.

This also corrects a sizing argument recorded earlier in this workstream — that
26 of the 67 non-`Complete` captures carry a temporal expression, so the guard
declines 24 of 26 and these are two leaks in a working guard. The denominator
was wrong and the mechanism was wrong: nothing declined these two.

### What this makes the next target — narrower than it first looked

`incomplete-complement` is **1/10** and `dangling-infinitive` is **18/20**. The
first reading of that was that nine captures of one shape are undetected and
none of them is declined anywhere. **Reading `ClauseStructure.swift` says
otherwise: four of the nine are recorded declines in the source, with the
measurement that produced each one written beside it.**

| capture | what the detector does |
|---|---|
| `I want`, `I need`, `Tomorrow I want`, `I have to get`, `I should buy` | ends on a verb; **no rule reaches it** |
| `Can you remind me about` | ends on a preposition — excluded because `Meet Mike at` and `remind me an hour before` are the same shape and the second is finished. Three classes were tried and cost four blocking corpus failures. |
| `I need to pick up` | ends on a particle behind a verb — the `previous.isVerb` guard, which is what keeps `follow up`, `check in` and `head out` whole |
| `Add`, `Buy` | a bare imperative verb, **tried and removed**: `NLTagger` calls a one-word "Add" a verb on macOS and something else on iOS |

So the uncovered set is five captures, all one shape: a finite clause ending on
a verb whose object never came. And closing it needs a transitivity judgement —
`I should buy` is unfinished and `I already ate` is not — which is lexical, and
a word list is the thing this file exists not to keep. It may well be another
"out of scope, and honestly so"; it is not the clean unblocked target the first
reading made it look like.

### A better candidate, and it is a false premise rather than a missing rule

The infinitive rule fires only when the clause holds exactly one `to`, on the
stated ground that *"an earlier `to` is exactly the evidence that the frame got
its content"*. That premise is false under a doubled false start.

`INC56 I need to I need to` — tagged `repeated frame, still empty` — holds two
markers, so the rule stands down and the capture is missed. The premise fails
because the first `to` is followed by `I`, not by a verb: the frame it opened
was never filled, so its presence is not evidence of anything.

The doubled frame is not rare, and both sides of it are already covered:

| capture | set | must be |
|---|---|---|
| `I need to I need to` | dev `unfinished` INC56 | flagged |
| a capture opening `I need to I need to …` and then finishing | held-out C002 | **finished** |
| four more opening the same way | everyday W32, M08, L05, E04 | **finished** |

The fix would be to the rule's input rather than a new rule: ask whether an
earlier marker was *filled* — followed by a verb — instead of whether one
exists. It leaves `Remind me to buy milk when I get to` alone, because there
the first `to` is followed by `buy`.

**It was sized and is not being built.** Across the five readable development
sets — 491 captures — 34 end on `to` and **exactly one of them holds a second
marker**: INC56. So the change is worth one row in every corpus anyone here is
allowed to read, and its whole justification is that a premise in the source is
false rather than that a measured number moves. That is what the standing rule
against making one sentence pass is aimed at.

The premise is still false and this section is where it is recorded. What it
needs is captures of that shape. **The honest reading of "34 end on `to` and
one doubles" is a gap in our data, not rarity in speech** — so the output is a
named data gap rather than a rule: a repeated opening frame that then trails
off.

### How the five sealed captures above were obtained, which was wrong

The table naming held-out C002 and everyday W32, M08, L05 and E04 was built by
grepping the sealed sets for the doubled frame, to argue a change was safe.
That is not reading failures, which is what the standing rule names, but it is
what the rule protects: a sealed set stops measuring generalisation the moment
a change is chosen with its contents in view.

The argument did not need it. **The change can only affect a capture that ends
on `to`, so every capture that does not is untouched** — a property, checkable
by a run, and exactly why those five were safe. It is recorded here rather than
quietly dropped, because how a figure was obtained is part of the figure.

## 2026-09-11 12:34 — branch at `9d91a0b`, the two guard repairs that shipped

Branch `claude/hearth-thread-tod920`,
[run 34598981239](https://github.com/CalvinSalsali04/speak-it/actions/runs/34598981239),
`macos-26`, `language_only`. **This is the current baseline** once the branch
merges. Two causes: an ordinal is not an amount, and a complement-taking verb
governs the clause behind it.

| instrument | baseline (`2d8fe760`) | shipped (`9d91a0b`) |
|---|---|---|
| gating corpus | 1393, **0 failing** | 1393, **0 failing** |
| everyday routing / count | 168/240 · 193/232 | 168/240 · 193/232 |
| everyday loss / invention / titles | 230/244 · 14/22 · 245/255 | 230/244 · 14/22 · 245/255 |
| everyday over- / under-split | 16 · 23 | 16 · 23 |
| everyday acted on anyway | 0 | 0 |
| held-out destination / count | 233/320 · 255/310 | **233/320 · 255/310** |
| held-out acted on anyway | 7 | 7 |
| adversarial routing / count | 53/116 · 79/105 | **52/116** · **78/105** |
| adversarial over- / under-split | 8 · 18 | **9** · 18 |
| adversarial titles / loss / invention | 117/120 · 113/116 · 10/24 | unchanged |
| adversarial acted on anyway | 1 | 1 |
| **runon dev destination** | 41/46 | **42/46** |
| **runon dev thought count** | 33/44 | **35/44** |

Every other development set is unchanged: coordination 115/121, routed 74/84
and 77/79 with 3 acted on anyway, framing 41/45 and 43/44, unfinished 34/57
recall with 0/96 fallout and 2 unsafe, abandonment 24/24 with 0/24 †.

† Overstated by the scorer. The repaired scorer measured 23/24 and 1/24
on unchanged parser code at 15:45; see "Correction — 2026-09-11" above.

**The held-out 389 is back to the baseline figure exactly**, which retires the
−1/+2 seen in the two withdrawn runs: all of that movement belonged to the
causes that came out.

### What it fixed, and what it cost

| row | before | after |
|---|---|---|
| RM03 | destination and count both wrong | **passes both** |
| RO05 "remind me the bins go out on Tuesday" | over-split into 2 | **1 row** |
| one capture in `runon-x-repair` | correct | **over-split** |

`errand-runon` is now 8/8 on destination and 7/7 on thought count.
`object-guard` holds at 10/10 on count with RO05's over-split gone.

**The cost is one sealed capture and it is in the direction that matters
most.** Adversarial over-segmentation went from 8 to 9; a wrongly severed row
retrieves under nothing. The capture cannot be inspected — the set reports
rates only — but the cause can be reasoned to: of the two changes only the
ordinal exemption *enables* a cut, so the complement guard cannot have caused
an over-split.

**It was merged anyway, and this is the reason.** The guard being relaxed is
wrong on its own terms: "the 26th" is a complete noun phrase and "$89" is not,
and keeping a rule that cannot tell them apart because one hard composition
capture happens to benefit from the confusion is the wrong trade. The harm it
was causing is worse than the harm it now causes — a capture that lost its
errand entirely ("Priya starts on the 14th order her a laptop" arriving as one
Memory row) costs the user the task, while an extra row on a hard sentence
leaves both halves visible. The everyday set and the 389 are untouched either
way.

Watch adversarial over-segmentation on the next change. If it moves again, the
ordinal exemption is the first thing to re-examine.

## 2026-09-11 12:25 — why the unit suite fails on a GitHub-hosted Mac: answered

Same run, [34597902006](https://github.com/CalvinSalsali04/speak-it/actions/runs/34597902006),
`iOS app` job, `macos-26`. `SpeakItTests/NaturalLanguageEnvironmentTests` asks
Apple's framework directly instead of inferring it from a behaviour that
failed, and this is the first run in which it has ever executed.

**The lexical-class tagger returns nothing on that runner's simulator.** The
failure messages carry the tagging of each sentence, so the answer is in the
job log rather than in an `.xcresult` nobody can download:

```
on:OtherWord the:OtherWord 15th:OtherWord pay:OtherWord the:OtherWord rent:OtherWord
when:OtherWord I:OtherWord finish:OtherWord the:OtherWord essay:OtherWord call:OtherWord dave:OtherWord
I:OtherWord had:OtherWord better:OtherWord luck:OtherWord last:OtherWord time:OtherWord
```

Every token, in every sentence, is `OtherWord`. Not tagged differently — not
tagged. And the two embedding tests **passed**, so `NLEmbedding.wordEmbedding`
loads on the same machine in the same process. It is specifically `NLTagger`'s
`.lexicalClass` that has no model.

That explains every behavioural failure beside it, and each one is a rule
reading the tagger's silence as a fact:

| assertion | what the rule needed |
|---|---|
| `("on the 15th pay the rent") != ("pay the rent")` | "pay" to be a verb |
| `("when I finish the essay call dave") != ("call dave")` | "finish" to be a verb |
| `("actionable") != ("knowledge")` — *I had better luck last time* | "luck" to be a noun |
| `("ambiguous") != ("actionable")` — *Unpack boxes* | the embedding path, reached only after the tag |
| `"buy the milk tomorrow call the dentist"` arrived as one row | "buy" to be a verb |

The corpus gate passes on the same runner minutes earlier because
`Tools/CorpusRunner` runs on the **host**, where the tagger works. The
difference between the two has never been anyone's diff.

**What this does and does not say.** It says the suite cannot be trusted on a
GitHub-hosted `macos-26` simulator for any tagger-dependent assertion, and that
the author's Mac remains the reference environment. It does **not** establish
that a real iPhone can reach the same state; that is a separate question and
this run cannot answer it. What it does establish is the failure *mode* if one
ever did: not a crash and not an error, but every capture quietly reading as
though it had no verbs in it. Recorded in `Docs/KNOWN_ISSUES.md`.

## 2026-09-11 12:20 — branch at `4af3af9`, the three guard repairs alone

Branch `claude/hearth-thread-tod920`,
[run 34597902006](https://github.com/CalvinSalsali04/speak-it/actions/runs/34597902006),
`macos-26`. **Not a baseline.** It is the control for the section below: the
same branch with the statement boundary removed, so every figure here is the
three guard repairs and nothing else.

**The gating corpus is back to 1393 cases, 0 failing at every severity**, which
settles the attribution: all four CRITICAL regressions were the statement
boundary, and none of them was a guard repair.

| instrument | baseline (`2d8fe760`) | four causes (`90434e9`) | three guards (`4af3af9`) |
|---|---|---|---|
| gating corpus failing | 0 | **4 CRITICAL** | 0 |
| everyday routing / count | 168/240 · 193/232 | 168/240 · 193/232 | 168/240 · 193/232 |
| everyday over- / under-split | 16 · 23 | 16 · 23 | 16 · 23 |
| held-out destination / count | 233/320 · 255/310 | 232 · 256 | **232** · **257** |
| held-out acted on anyway | 7 | 7 | 7 |
| adversarial routing / count | 53/116 · 79/105 | 51 · 76 | **52** · **77** |
| adversarial over- / under-split | 8 · 18 | — | **9** · **19** |
| runon dev destination | 41/46 | 41/46 | 41/46 |
| runon dev thought count | 33/44 | 35/45 | **35/45** |

Every other development set is unchanged: coordination 115/121, routed 74/84
and 77/79 with 3 acted on anyway, framing 41/45 and 43/44, unfinished 34/57
recall with 0/96 fallout and 2 unsafe, abandonment 24/24 with 0/24 †.

† Overstated by the scorer. The repaired scorer measured 23/24 and 1/24
on unchanged parser code at 15:45; see "Correction — 2026-09-11" above.

**The everyday set is bit-identical for the third run running.** Neither the
statement boundary nor the guard repairs changed a single one of 255 natural
captures.

### What actually changed, row by row

The `Development-set failures` step now runs on a red run as well as a green
one, so this is read off the log rather than inferred.

| row | before | after | cause |
|---|---|---|---|
| RM03 | count and destination both wrong | **passes** | ordinal is not an amount |
| RO05 "remind me the bins go out on Tuesday" | over-split into 2 | **1 row** | clausal complement |
| RF04 "first thing tomorrow email the landlord about the damp" | over-split into 2 | 1 row, **routed to Memory** | verbless temporal head |
| RE03 "book the car in for Thursday renew my passport" | passes | **merged into 1** | verbless temporal head |
| RE08 "text Marcus about Saturday move the standup to 9:15" | passes | **merged into 1** | verbless temporal head |

Two of the three causes are clean. The third is not, and the row-level view is
the only reason that is visible: at the set level it reads as +2.

### The verbless-temporal-head relaxation is wrong, and why generalises

It accepted any head that carries no verb and ends on a time word, on the
argument that no list of openers can finish while the end of the phrase is
always the time. The argument about openers is right. The conclusion is not,
because **"carries no verb" is the tagger's answer, not a fact.** `NLTagger`
does not reliably call a sentence-initial "book" or "text" a verb, so
"book the car in for Thursday" reads as verbless and ends on a day — an adjunct
by that test, and the errand behind it is swallowed.

The original rule was safe because it *also* demanded a fronting preposition,
which an imperative clause does not have. The preposition is the half of the
test the tagger cannot be wrong about, and it is load-bearing. Removed, with
both captures above kept as the guard in
`ActionabilityTests.testAnAdjunctInFrontOfACutNeedsAPrepositionAndNotJustATime`.

**RF04's real root cause is elsewhere and is the better next target.** Merged
into one row it routes to **Memory**, so `Actionability` does not read
"first thing tomorrow email the landlord about the damp" as an errand at all.
The same fronting vocabulary is the cause in both places; fixing it in the
router is what would make the capture correct, and the over-split was the
symptom rather than the disease.

## 2026-09-11 12:03 — branch at `90434e9`, the statement-boundary attempt, withdrawn

Branch `claude/hearth-thread-tod920`,
[run 34596594804](https://github.com/CalvinSalsali04/speak-it/actions/runs/34596594804),
`macos-26`. **This is not a baseline.** It is the measurement that decided a
change should not ship, recorded because a negative result costs the same
dispatch as a positive one and is worth as much.

The change had four causes, three of them repairs to guards that already
existed and one of them new machinery: a boundary between two juxtaposed
*statements*, proposed where the second clause opened on the speaker's own
possessive, a first-person obligation, or a resolved proper name.

### The verdict, in one table

| instrument | baseline (`2d8fe760`) | this run (`90434e9`) |
|---|---|---|
| gating corpus | 1393 cases, **0** failing | 1393 cases, **4 CRITICAL** |
| everyday routing / count | 168/240 · 193/232 | 168/240 · 193/232 |
| everyday loss / invention / titles | 230/244 · 14/22 · 245/255 | 230/244 · 14/22 · 245/255 |
| everyday over- / under-split | 16 · 23 | 16 · 23 |
| held-out destination / count | 233/320 · 255/310 | **232/320** · **256/310** |
| held-out acted on anyway | 7 | 7 |
| adversarial routing / count | 53/116 · 79/105 | **51/116** · **76/105** |
| adversarial loss / invention / titles | 113/116 · 10/24 · 117/120 | 113/116 · 10/24 · 117/120 |
| runon dev destination | 41/46 | 41/46 |
| runon dev thought count | 33/44 | **35/45** |

The everyday block is bit-identical, family by family and defect by defect, on
255 captures. **The change did nothing at all to natural speech**, cost two
adversarial routings and three adversarial counts, cost one held-out
destination for one held-out count, and broke four cases of the gate.

### The family it was written for did not move

`runon.tsv` reports per family for the first time in this run, which is what
made the verdict readable rather than a single total.

| family | n | destination | thought count |
|---|---|---|---|
| adjunct-guard | 4 | 3/4 (75.0%) | 4/4 (100%) |
| anaphora-guard | 6 | 5/6 (83.3%) | 6/6 (100%) |
| **statement-runon** | 6 | 5/6 (83.3%) | **0/6 (0%)** |
| mixed-runon | 8 | 7/8 (87.5%) | 5/7 (71.4%) |
| object-guard | 10 | 9/10 (90.0%) | 10/10 (100%) |
| bridging-guard | 4 | 4/4 (100%) | 4/4 (100%) |
| errand-runon | 8 | 8/8 (100%) | 6/8 (75.0%) |

`statement-runon` is the family the new machinery was written for and it is
**0 of 6**. Every one of the two counts it gained came from the three guard
repairs, in `errand-runon` and `mixed-runon`. The guard families were not
over-split: `adjunct-guard`, `anaphora-guard`, `object-guard` and
`bridging-guard` are all at 100% on thought count.

The count denominator moved from 44 to 45 because one capture stopped being
read as an Operation, which is a behaviour change rather than a scorer change:
`heldout/score.py` only scores a count where the pipeline produced rows.

### Why it broke the gate, which is the part worth keeping

One case failed in each of four families, and none of them is a run-on
sentence. The gate reported a count and not the rows (see below), so these were
found by tracing every capture of those four families through the rule by hand
rather than read off a log. Three are unambiguous:

| family | capture | where the rule cut |
|---|---|---|
| Semantic keyword collisions | "I have no idea where my passport is" | before `my passport` |
| Ordinary speech (control) | "It reminded me of something my dad used to say" | before `my dad` |
| Intent consolidation | one of two captures opening a clause on `I have to` or `I need to` | before the obligation |

The fourth is in `Filler that collapsed a capture`, whose eight captures
include the same sentence as one of the two Intent-consolidation candidates,
differing only by a full stop — so the same cut fails a case in both families.
Which of the two consolidation captures it is cannot be settled without running
the corpus, and it does not change the cause.

The rule asked whether the words on each side of a cut carry a subject and a
predicate. They do in all four — and **a subject and a predicate do not make a
prefix a finished clause.** "I have no idea where" has both and is plainly
unfinished. "It reminded me of something" has both and is about to be modified
by a relative clause with no relativizer. The test I wrote proves the two sides
are clauses; it never proves the left one is *over*.

That is a general fact about this approach rather than a bug in these four
rows, which is why the rule came out rather than being patched: it fires
constantly on possessives inside subordinate clauses and never once where it
was aimed. The guard list now lives in
`SpeakItTests/ActionabilityTests.testNothingCutsBetweenTwoJuxtaposedStatements`,
carrying both the original seven rows and these four, so the next attempt fails
in a second instead of in a dispatch.

### Two instruments that reported a count and not the rows

Both cost this dispatch and are fixed on the same branch.

- The corpus gate printed `4 blocking failures` and told the reader to run
  `corpus-run --verbose`, which needs a Mac nobody reading a CI log has. It now
  prints the rows.
- The `Development-set failures` step had no `always()`, so the run that went
  red — the only run that needed it — skipped it.

## 2026-09-11 11:26 — `main` at `2d8fe760`, the discourse-framing change merged

Commit `2d8fe760` on `main`,
[run 34593643935](https://github.com/CalvinSalsali04/speak-it/actions/runs/34593643935),
`macos-26`. **This is the current baseline.**

It is the after-picture for the discourse-framing change, and it is the only
run that compares cleanly with the 10:57 section below: same everyday
generation (255 captures, 22 invention cases), same scorer, same corpus data,
one merge apart. The 10:12 section measured the same change against the
235-capture generation with the old invention scorer, so its everyday figures
do not compare with either of these.

Two instruments read for the first time in this run: `runon.tsv`, the
development set written for the next change before that change exists, and the
120-capture adversarial held-out set, which merged after the 10:57 run started.

### What moved, and what did not — everyday, 255 captures

| measure | before (`2c5ac5b`) | after (`2d8fe760`) |
|---|---|---|
| routing | 167/240 (69.6%) | **168/240 (70.0%)** |
| count | 192/232 (82.8%) | **193/232 (83.2%)** |
| nothing lost | 230/244 (94.3%) | 230/244 (94.3%) |
| nothing invented | 14/22 (63.6%) | 14/22 (63.6%) |
| clean titles | 237/255 (92.9%) | **245/255 (96.1%)** |
| over-segmented | 17 | **16** |
| under-segmented | 23 | 23 |
| genuinely ambiguous | 15 | 15 |
| **acted on anyway** | **0** | **0** |

Nothing regressed on any of the four domain-level measures, and no everyday
family lost ground on any of its three. The gating corpus stayed at 1393
cases, 0 failing across all four severities.

| measure | all domains | family-health | fitness-errands | freelance | money-travel | work-school |
|---|---|---|---|---|---|---|
| routing | 168/240 (70.0%) | 30/48 (62.5%) | 37/48 (77.1%) | 34/48 (70.8%) | 32/48 (66.7%) | 35/48 (72.9%) |
| count | 193/232 (83.2%) | 39/47 (83.0%) | 38/46 (82.6%) | 38/46 (82.6%) | 39/47 (83.0%) | 39/46 (84.8%) |
| nothing lost | 230/244 (94.3%) | 49/49 (100%) | 48/50 (96.0%) | 45/49 (91.8%) | 46/49 (93.9%) | 42/47 (89.4%) |
| nothing invented | 14/22 (63.6%) | 0/4 (0%) | 3/4 (75.0%) | 3/5 (60.0%) | 4/5 (80.0%) | 4/4 (100%) |
| clean titles | 245/255 (96.1%) | 50/51 (98.0%) | 51/51 (100%) | 47/51 (92.2%) | 50/51 (98.0%) | 47/51 (92.2%) |

Item type matched the label 145/232, reported and never gated.

### Title hygiene, by defect

| defect | before | after |
|---|---|---|
| farewell kept | 7 | **0** |
| preamble `number one` / `number three` kept | 3 | **0** |
| preamble `number two` kept | 2 | 1 |
| preamble `what happened was` kept | 1 | 1 |
| title is the whole capture | 8 | 8 |

Every farewell is gone. What is left is one enumerator, one preamble, and the
eight captures whose title is the entire recording — which is the segmentation
defect wearing a title-shaped coat, not a hygiene defect.

### Everyday per family, worst routing first

| family | n | routing | count | title |
|---|---|---|---|---|
| run-on | 8 | 0/8 (0%) | 0/8 (0%) | 7/8 (87.5%) |
| rambling-intro | 6 | 1/6 (16.7%) | 1/6 (16.7%) | 4/6 (66.7%) |
| trailing-goodbye | 7 | 2/7 (28.6%) | 4/7 (57.1%) | **7/7 (100%)** |
| sequencing | 17 | 7/17 (41.2%) | 8/17 (47.1%) | 16/17 (94.1%) |
| multi-thought | 40 | 19/40 (47.5%) | 22/40 (55.0%) | **40/40 (100%)** |
| operation | 10 | 5/10 (50.0%) | 0/2 (0%) | 10/10 (100%) |
| cancellation | 12 | 6/12 (50.0%) | 1/4 (25.0%) | 12/12 (100%) |
| hedged | 24 | 9/17 (52.9%) | 15/17 (88.2%) | 22/24 (91.7%) |
| filler | 18 | 9/14 (64.3%) | 12/14 (85.7%) | **18/18 (100%)** |
| list | 20 | 13/20 (65.0%) | 14/20 (70.0%) | 18/20 (90.0%) |
| relative-date | 6 | 4/6 (66.7%) | 5/6 (83.3%) | 6/6 (100%) |
| person | 33 | 23/33 (69.7%) | 26/32 (81.2%) | 32/33 (97.0%) |
| date | 38 | 26/37 (70.3%) | 30/37 (81.1%) | 36/38 (94.7%) |
| negation | 51 | 36/51 (70.6%) | 41/47 (87.2%) | 49/51 (96.1%) |
| location | 12 | 9/12 (75.0%) | 10/12 (83.3%) | 11/12 (91.7%) |
| self-correction | 39 | 30/39 (76.9%) | 37/39 (94.9%) | 39/39 (100%) |
| time | 28 | 21/27 (77.8%) | 26/27 (96.3%) | 27/28 (96.4%) |
| quantity | 34 | 27/34 (79.4%) | 32/34 (94.1%) | 31/34 (91.2%) |
| reference | 34 | 27/34 (79.4%) | 28/34 (82.4%) | 33/34 (97.1%) |
| false-start | 14 | 12/14 (85.7%) | 12/14 (85.7%) | 14/14 (100%) |
| recurrence | 22 | 19/22 (86.4%) | 21/22 (95.5%) | 22/22 (100%) |
| proper-noun | 15 | 13/15 (86.7%) | 12/14 (85.7%) | 15/15 (100%) |
| repetition | 10 | 10/10 (100%) | 10/10 (100%) | 10/10 (100%) |
| question | 9 | 1/1 (100%) | 1/1 (100%) | 9/9 (100%) |
| ambiguous | 15 | — | — | 14/15 (93.3%) |

**How these rows are ordered, because it is not how the scorer orders them.**
Ascending by the printed `routing` column, with `ambiguous` last because it has
no routing rate at all (`—` in routing and count, the everyday equivalent of the
held-out set's `NOT RANKED` block). That is *not* `worst()`, the key
`everyday/score.py` ranks by, which takes the minimum across five measures —
`routing`, `count`, `loss`, `invention`, `title` — of which the table prints
three. In this table two rows sit at 0.000 under that key — `run-on` on
routing 0/8 and `operation` on **count 0/2** — and they are published first and
sixth, which is the proof. In the two earlier sections, where the farewell fix
had not yet landed, a third joins them: `trailing-goodbye` at **title 0/7**,
published third. That one is the example to reach for, because its 0/7 is
printed in the table, so the argument does not need the invisible columns at
all — a reader can see three zeros and see they are not adjacent.

Whoever transcribed these re-sorted them by a column the reader can see, which
is the right instinct and is why the ranking defect fixed in
`everyday/score.py` does not reach this file. Do not "correct" these tables
back to the scorer's order.

The `negation` row is the 51-capture family after PR #33 added the tag to W09,
F05 and F14. It does not compare with the 48-capture row in the 10:57 section.

`n` counts captures carrying the tag, so the rows overlap: one capture can be
filler, negation and multi-thought at once.

### Held-out set — 389 utterances, sealed

Destination 233/320 (72.8%), thought count 255/310 (82.3%), producing nothing
0, genuinely ambiguous 69, **acted on anyway 7 (10.1%)**. Identical to every
run before it. **Nothing has moved the generalisation measure yet**, and that
remains the honest headline for the framing change: it fixed what a person
reads on a row, and it has not been shown to help a speaker the parser has
never met.

### Adversarial held-out set — 120 captures, first reading

Phenomena in combination: each capture crosses two families that are each
already imperfect alone. Written held out, by interaction rather than by
mechanism or content, and never tuned against.

| measure | value |
|---|---|
| routing | 53/116 (45.7%) |
| count | 79/105 (75.2%) |
| nothing lost | 113/116 (97.4%) |
| nothing invented | 10/24 (41.7%) |
| clean titles | 117/120 (97.5%) |
| over-segmented | 8 |
| under-segmented | 18 |
| genuinely ambiguous | 4 |
| **acted on anyway** | **1 (25.0%)** |

**The one row that should only ever fall is not zero here.** Everyday and the
389-set both hold at 0 and 7 respectively; on captures built to be hard, one
of the four ambiguous cases got a confident action. Four cases is a small
denominator and 25% is not a rate worth quoting, but the count is the number
that matters and it is 1, not 0.

Routing at 45.7% against everyday's 70.0% is the headline. Combination is
where the parser is worst, and it is not a uniform collapse:

| pairing | routing | count | nothing lost | nothing invented |
|---|---|---|---|---|
| ellipsis × date | 0/10 (0%) | 1/10 (10.0%) | 10/10 (100%) | — |
| reported speech × operation | 3/12 (25.0%) | 7/7 (100%) | 12/12 (100%) | — |
| idiom × operation | 3/10 (30.0%) | 4/4 (100%) | 10/10 (100%) | — |
| brand-verb × multi-task | 4/12 (33.3%) | 10/12 (83.3%) | 12/12 (100%) | — |
| negation × multi-task | 5/12 (41.7%) | 8/12 (66.7%) | 11/12 (91.7%) | — |
| not-a-time × date | 5/12 (41.7%) | 11/12 (91.7%) | 12/12 (100%) | — |
| conditional × negation | 7/12 (58.3%) | 9/12 (75.0%) | 10/12 (83.3%) | — |
| role × multi-person | 7/12 (58.3%) | 9/12 (75.0%) | 12/12 (100%) | — |
| run-on × self-correction | 8/12 (66.7%) | 8/12 (66.7%) | 12/12 (100%) | 4/12 (33.3%) |
| self-correction × name | 11/12 (91.7%) | 12/12 (100%) | 12/12 (100%) | 6/12 (50.0%) |

**`ellipsis × date` at 0/10 is the worst single reading in any instrument.**
Ellipsis — "and the other one too", "same again next week" — leaves the verb
and often the object to be recovered from the previous clause, and the parser
has no stage that recovers them. Combined with a date it routes nothing right
and counts one in ten.

Worth flagging against a stated prediction: **`run-on × self-correction` reads
66.7% routing here while everyday's `run-on` family reads 0/8.** The
expectation was that combination would compose the two failures and read
worse. It did not, and that is evidence the everyday `run-on` captures are
harder along some dimension the adversarial pairing does not carry — likely
length and thought count, not the run-on property itself. Two sets, two
readings; the everyday one is the one to fix against.

**Corrected 2026-09-15 by the held-out per-family table, at the top of this
file.** The guess above is right and the reason is mechanical rather than a
property of those captures: everyday `routing` is multiset equality over the
rows produced, so it contains the thought count, while held-out `destination`
is membership per capture and cannot fail on under-segmentation. Held-out
`run-on` reads 10/10 on destination and 2/10 on thought count. Those are the
two facts everyday's single bit is the conjunction of, and the conjunction
cannot be read back apart. Do not compare a rate here with a rate there
because the columns share a name.

Title hygiene is near clean at 117/120: 2 titles are the whole capture, 1
opens on `that`.

### Development sets — not a gate, not held out

| set | measure | this run (`2d8fe760`) | last read at |
|---|---|---|---|
| gating corpus | cases / failing | 1393 / **0** | 1381 / 0 at `2c5ac5b`; the change adds 12 cases |
| coordination | boundaries | 115/121 (95.0%) | 115/121 at 10:12, and at 09:56 before the change |
| routed (116) | destination / count | 74/84 (88.1%) / 77/79 (97.5%) | 74/84 at 10:12 and 09:56 |
| routed (116) | acted on anyway | 3 | 3 at 10:12 and 09:56 |
| framing (45) | destination / count | 41/45 (91.1%) / 43/44 (97.7%) | 41/45 at 10:12; the set is newer than 09:56 |
| unfinished | recall / fallout / unsafe | 34/57 / 0/96 / 2 | same at 10:12 and 09:56 |
| abandonment † | recall / fallout | 24/24 / 0/24 | same at 10:12 and 09:56 |
| **runon (46)** | destination | **41/46 (89.1%)** | first reading |
| **runon (46)** | thought count | **33/44 (75.0%)** | first reading |
| **runon (46)** | acted on anyway | **0** | first reading |

† Overstated by the scorer. The repaired scorer measured 23/24 and 1/24
on unchanged parser code at 15:45; see "Correction — 2026-09-11" above.

The right-hand column names where each comparison figure came from rather than
calling it "before": the 10:57 run on `2c5ac5b` reported its gating-corpus
total but its development-set block was not recorded, so the honest comparison
for those sets is the 10:12 / 09:56 pair on the branch, which brackets the same
parser change.

**The shape of `runon.tsv`'s first reading is the finding.** Destination is
89.1% and count is 75.0%: on speech with no marker between two thoughts, the
parser usually routes the capture to the right place and usually fails to
notice there were two thoughts. Eleven of forty-four scored rows have the
wrong count. That is the signature of a missing boundary rather than a
misread meaning, and it is exactly what the set was written to isolate.

The per-row failures are not in this run: the `Development-set failures` step
wrote them to a file nothing collected. The step now prints to the job log.

## 2026-09-11 10:57 — `main` at generation 3, with no parser change in it

Commit `2c5ac5b` on `main`,
[run 34591348628](https://github.com/CalvinSalsali04/speak-it/actions/runs/34591348628),
`macos-26`. This run exists because the unit suite failed on the framing
branch and the same suite had to be run on unchanged `main` to find out whose
failure it was; the language job came free with it.

**This is the before-picture the framing change has to be compared against**,
and it is the first everyday reading at the set's third generation (255
captures, 22 invention cases). It does **not** contain the discourse-framing
change. The 10:12 section below measured that change against the 235-capture
generation, so those two sets of everyday figures do not compare with each
other. These do, once the branch is measured again.

**The unit suite in this same run failed**, and so does the suite on the
framing branch, with an identical list of 57 failing assertions. That is the
state of the suite on a GitHub-hosted `macos-26` runner; the `ios` job had
never run there before today. It does not make the numbers above wrong — they
come from `Tools/CorpusRunner`, a host-side binary that passed its own gate at
1381/1381 in the same job — but they were taken on a commit whose simulator
suite does not pass on that runner, and that belongs next to them until the
failure is understood.

### Everyday held-out set — 255 captures, nothing tuned against them

| measure | all domains | family-health | fitness-errands | freelance | money-travel | work-school |
|---|---|---|---|---|---|---|
| routing | 167/240 (69.6%) | 30/48 (62.5%) | 37/48 (77.1%) | 33/48 (68.8%) | 32/48 (66.7%) | 35/48 (72.9%) |
| count | 192/232 (82.8%) | 39/47 (83.0%) | 38/46 (82.6%) | 37/46 (80.4%) | 39/47 (83.0%) | 39/46 (84.8%) |
| nothing lost | 230/244 (94.3%) | 49/49 (100%) | 48/50 (96.0%) | 45/49 (91.8%) | 46/49 (93.9%) | 42/47 (89.4%) |
| nothing invented | 14/22 (63.6%) | 0/4 (0%) | 3/4 (75.0%) | 3/5 (60.0%) | 4/5 (80.0%) | 4/4 (100%) |

Over-segmented 17, under-segmented 23, produced nothing 0, missing probe
results 0. Genuinely ambiguous 15, **acted on anyway 0**. Item type matched the
label 145/232, reported and never gated.

Clean titles 237/255 (92.9%). The 18 defects: 8 where the title is the whole
capture, 7 farewells kept, 5 numbered preambles kept (`number one` ×2,
`number two` ×2, `number three` ×1), 1 `what happened was`. Fourteen of the
eighteen are framing left in place, which is what the branch change exists to
remove.

### Per family, worst first

| family | n | routing | count | title |
|---|---|---|---|---|
| run-on | 8 | 0/8 (0%) | 0/8 (0%) | 4/8 (50.0%) |
| rambling-intro | 6 | 1/6 (16.7%) | 1/6 (16.7%) | 3/6 (50.0%) |
| trailing-goodbye | 7 | 2/7 (28.6%) | 4/7 (57.1%) | 0/7 (0%) |
| sequencing | 17 | 6/17 (35.3%) | 7/17 (41.2%) | 12/17 (70.6%) |
| multi-thought | 40 | 19/40 (47.5%) | 22/40 (55.0%) | 36/40 (90.0%) |
| operation | 10 | 5/10 (50.0%) | 0/2 (0%) | 10/10 (100%) |
| cancellation | 12 | 6/12 (50.0%) | 1/4 (25.0%) | 12/12 (100%) |
| hedged | 24 | 9/17 (52.9%) | 15/17 (88.2%) | 19/24 (79.2%) |
| list | 20 | 12/20 (60.0%) | 13/20 (65.0%) | 17/20 (85.0%) |
| filler | 18 | 9/14 (64.3%) | 12/14 (85.7%) | 15/18 (83.3%) |
| relative-date | 6 | 4/6 (66.7%) | 5/6 (83.3%) | 6/6 (100%) |
| person | 33 | 23/33 (69.7%) | 26/32 (81.2%) | 32/33 (97.0%) |
| date | 38 | 26/37 (70.3%) | 30/37 (81.1%) | 36/38 (94.7%) |
| negation | 48 | 34/48 (70.8%) | 38/44 (86.4%) | 46/48 (95.8%) |
| location | 12 | 9/12 (75.0%) | 10/12 (83.3%) | 11/12 (91.7%) |
| self-correction | 39 | 30/39 (76.9%) | 37/39 (94.9%) | 39/39 (100%) |
| time | 28 | 21/27 (77.8%) | 26/27 (96.3%) | 27/28 (96.4%) |
| quantity | 34 | 27/34 (79.4%) | 32/34 (94.1%) | 31/34 (91.2%) |
| reference | 34 | 27/34 (79.4%) | 28/34 (82.4%) | 33/34 (97.1%) |
| false-start | 14 | 12/14 (85.7%) | 12/14 (85.7%) | 13/14 (92.9%) |
| recurrence | 22 | 19/22 (86.4%) | 21/22 (95.5%) | 22/22 (100%) |
| proper-noun | 15 | 13/15 (86.7%) | 12/14 (85.7%) | 13/15 (86.7%) |
| repetition | 10 | 10/10 (100%) | 10/10 (100%) | 10/10 (100%) |
| question | 9 | 1/1 (100%) | 1/1 (100%) | 9/9 (100%) |
| ambiguous | 15 | — | — | 14/15 (93.3%) |

Ordered ascending by the printed `routing` column, `ambiguous` last for want of
a routing rate — not by the scorer's `worst()` key. See the note under
"Everyday per family, worst routing first" above.

`n` counts captures carrying the tag, so the rows overlap: one capture can be
filler, negation and multi-thought at once. The negation row here is the
48-capture family; PR #33 later added the tag to W09, F05 and F14, so the next
reading's negation row is out of 51 and does not compare with this one.

### Held-out set — 389 utterances, sealed

Destination 233/320 (72.8%), thought count 255/310 (82.3%), producing nothing
0, genuinely ambiguous 69, **acted on anyway 7 (10.1%)**. Identical to every
previous run. Nothing has moved this number yet.

### Adversarial set

Not in this run: it merged after the run started. Its first reading is still
outstanding.

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
| abandonment † | recall / fallout | 24/24 / 0/24 | 24/24 / 0/24 |
| **framing** (new) | destination | — | 41/45 (91.1%) |
| **framing** (new) | thought count | — | 43/44 (97.7%) |
| **framing** (new) | acted on anyway | — | 0 |

† Overstated by the scorer. The repaired scorer measured 23/24 and 1/24
on unchanged parser code at 15:45; see "Correction — 2026-09-11" above.

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

Ordered ascending by the printed `routing` column, `ambiguous` last for want of
a routing rate — not by the scorer's `worst()` key. See the note under
"Everyday per family, worst routing first" above.

One hairline inversion in this table: `reference` at 79.4% precedes `quantity`
at 79.3%. Left as transcribed rather than silently corrected.

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
| abandonment † | withdrawals recognised | 24/24 (100%) |
| abandonment † | kept words wrongly withdrawn | 0/24 (0.0%) |

† Overstated by the scorer. The repaired scorer measured 23/24 and 1/24
on unchanged parser code at 15:45; see "Correction — 2026-09-11" above.

Coordination failures, all six: `occupations` 3 (all over-splits), `brands` 1
(over-split), `multiple-people` 1 (over-split), `three-or-more` 1 (under-split).

Weakest unfinished families: `incomplete-complement` 1/10,
`trailing-function-word` 2/8 ‡, `abandoned-midthought` 3/9.

‡ Seven of those eight captures are recorded design limits as of `1ca210b`,
declared against `ClauseStructure.swift`'s own "out of scope, and honestly so".
The rate is unchanged and correct; what it means is not. See "What a recorded
limit does to a weakest-family list" below.

> **Later, not here.** `trailing-function-word` reads **3/9** as of `599fb7d`,
> measured on run 35132499870: INC58 added one case and one pass. The `2/8`
> above is what *this* run produced and stays that way. **The movement is a new
> row being scored, not the parser improving** — no executable line of the
> engine changed between the two runs.

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

389 utterances written before anyone read the parser.§

§ **That sentence is not supportable and was retired on 2026-09-11.** It is
left standing here because this section records what was reported at the time.
`heldout.tsv` arrived in `cb2b630`, a commit that also rewrote six parser
sources, seventeen hours after the seven `Docs/PipelineSweep/*.md` analyses of
this parser's behaviour. Commit order is not authoring order, so the claim is
uncheckable rather than false — and five of the 389 are demonstrably not
unseen, two of them in the gating corpus itself and three verbatim in
documents. (This annotation said "three" until 19:54, having counted the
exact-match column and not the union with the prose column.) The figures below
are unchanged and the rows are still counted;
`Tools/CorpusRunner/heldout/README.md` sets out the evidence.

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
| abandonment † | withdrawals recognised | 24/24 (100%) |
| abandonment † | kept words wrongly withdrawn | 0/24 (0.0%) |
| abandonment | withdrawn thought acted on | 0 |

† Overstated by the scorer. The repaired scorer measured 23/24 and 1/24
on unchanged parser code at 15:45; see "Correction — 2026-09-11" above.

### The weakest families, by measurement rather than by impression

Recall is where the room is; fallout is already zero, which is the safer place
for it to be. That holds for `unfinished` as written. For `abandonment` it was
the scorer talking: see "Correction — 2026-09-11" above.

| family | set | score |
|---|---|---|
| `incomplete-complement` | unfinished | **1/10** |
| `trailing-function-word` | unfinished | **2/8** ‡ |
| `abandoned-midthought` | unfinished | **3/9** |
| `occupations` | coordination | **1/4**, all three failures over-splits |
| `dangling-infinitive` | unfinished | 18/20 |
| `brands` | coordination | 4/5, the failure an over-split |
| `multiple-people` | coordination | 5/6, the failure an over-split |
| `three-or-more` | coordination | 6/7, the failure an under-split |

Five of the six coordination failures are **over-splits**: the segmenter
inventing a row nobody asked for. That is one direction, not a scatter, and it
is worth treating as one question rather than six.

### ‡ What a recorded limit does to a weakest-family list

**`trailing-function-word` 2/8 is not the available win it looks like.** Seven
of its eight captures — INC41, INC42, INC43, INC44, INC46, INC47, INC48 — are
declared design limits as of `1ca210b`, citing `ClauseStructure.swift`'s own
record that preposition, conjunction and adverb were each tried as a trailing
class and each removed. "Pick up milk and" and "we're almost out" are the same
tag shape and only one of them is unfinished, so what separates them is *which*
preposition: a word list, which is the thing that file exists not to keep.

The declared captures stay in the denominator on purpose. **A limit is
counted, never subtracted** — it is a label on a row, not an exclusion from the
rate, so a declared capture that still misses is counted as a miss and one that
now passes is counted as a pass. (This used to read "counted as a miss and
never subtracted", which is self-contradictory and was wrong in the case that
matters; see the warning below.) The reason not to subtract is that a ceiling
is a denominator in waiting — publish "so the
reachable total is 50 of 57" once and 34/50 is in the reader's head, and 68% is
a nicer number than 59.6% that nobody earned. It would also be false: what the
source records is a decision about three *tagger classes*, not a property of
the language. The app already measures the speaker's pauses and throws them
away (`Docs/SEGMENTATION_ARCHITECTURE.md`), and a boundary that read timings
would not face this ambiguity at all.

**So the reading to take from the row is "declined with the signals we have",
not "broken" and not "unreachable".** INC45 is the one to look at: "I need to
talk to Sarah about the" ends on a determiner, which that comment does not
cover, and it was deliberately left out of the declaration rather than swept in
— a limit that covered it would be a marker standing in for the judgement it
approximates, which is the error this project keeps paying for.

The declaration cannot outlive the decision: `test_score.py` checks the cited
phrase is still in the source, so implementing the thing and deleting the
comment fails the suite until the declaration goes too.

**Warning: do not subtract the declared count from the family total.** It is
the arithmetic the row invites and it gives the wrong answer. Seven declared
out of eight does not leave one row able to pass, because a limit is a label
and not an exclusion — a declared capture the parser now handles is counted as
a pass like any other. So `2/8` with seven declared is not a contradiction, and
**at least one of the declared seven was passing even here**.

This is not hypothetical. Reading `2/8` as "seven declared, so only INC45 can
pass, so the answer should be 1" is a correct deduction from a false premise,
and it cost a reviewer real confidence in a rule that was behaving. The premise
came from three places that all said it, and all three were wrong: this
document, `devsets/README.md` rule 3, and the scorer's own report. All three
now say *counted, never subtracted*.

Which of the seven is passing is not answerable from a family total — that is
the same reconstruction that failed above, and the totals only ever bound it.
On the current set (`599fb7d`, run 35132499870, 9 rows, 3 OK, INC58 measured
passing) the declared seven contribute `3 − 1 − (INC45 passing ? 1 : 0)`, which
bounded it at one or two.

**Measured, so it no longer rests on that bound.** Run 35137835752 printed:

```
DECLARED LIMITS NOW PASSING   1 of 7
  INC46
```

and the same run's dev-set failure list names INC41 INC42 INC43 INC44 INC47
INC48 and not INC46 — two independent readings of one run agreeing.

**All three passing rows are named by the instrument, none deduced.** INC45 and
INC58 are absent from that failure list as well, so the three are INC45, INC46
and INC58 by direct report. An earlier draft of this paragraph recovered INC45
by subtraction from the family total instead, which works and should still not
be written down: reconstructing a row's identity from `9 cases, 3 OK` is the
exact reasoning this section exists to stop, and the list makes it unnecessary. **This was the first time that line had ever printed against the real
`unfinished.tsv`;** every earlier piece of evidence for it was synthetic, from
the scorer's own self-tests with fabricated probe output.

**INC46 passing is not by itself grounds to remove it from the declaration.**
The reason the declaration cites may still be exactly true while an unrelated
branch answers for that row, in which case the record is worth keeping. Trace
which branch answers before trimming; the declaration changes in its own
pull request, graded by somebody who did not write the instrument that
reported it.

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
