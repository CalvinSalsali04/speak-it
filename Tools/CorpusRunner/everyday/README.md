# Everyday speech — held-out set

255 captures of ordinary adult life, 51 in each of five domains, written from
the product description and from how people actually dictate. **Nothing here has
been tuned against, and nothing here may be tuned against.**

```bash
./Tools/CorpusRunner/everyday/score.sh              # the numbers
./Tools/CorpusRunner/everyday/score.sh --failures   # release review only
python3 Tools/CorpusRunner/everyday/leak-check.py   # boundary check
python3 Tools/CorpusRunner/everyday/test_score.py   # the instrument's own tests
```

The first two need a Mac: the pipeline cannot run anywhere else, because five of
its files depend on Apple's `NaturalLanguage` framework and `NLEmbedding` is what
decides whether an unknown word is a common noun or a name. The last two are
plain Python and run anywhere.

## What this set is for, and what the other sets are for

The repository already carries three kinds of language data, and this is the
fourth. Keeping them apart is the whole point; a set that has been looked at
while rules were being changed cannot answer the question this one exists to
answer.

| set | authored from | may be read during development |
|---|---|---|
| `SpeakItTests/SemanticCorpus*` | the product contract, by the rule author | yes — it is the regression net |
| `Tools/CorpusRunner/devsets/` | whatever is being worked on | yes — that is what it is for |
| `Tools/CorpusRunner/heldout/` | the product description, by mechanism | no |
| `Tools/CorpusRunner/everyday/` | the product description, by life domain | no |

`heldout/` and this set are held out for the same reason but along different
axes. `heldout/` varies the **mechanism**: false starts, homophones, ellipsis,
names-as-nouns. This set varies the **content**: what an adult actually dictates
on a Tuesday, with the disfluency arriving the way it arrives in real speech
rather than as the point of the sentence. A pipeline can be good at one and bad
at the other, which is why both numbers are worth having.

## The domains

| domain | what it covers |
|---|---|
| `work-school` | deadlines, standups, coursework, advisors, deliverables |
| `family-health` | children, appointments, medication, ageing parents, school admin |
| `money-travel` | bills, renewals, flights, itineraries, budgets |
| `freelance` | clients, invoices, scope, rates, proposals |
| `fitness-errands` | training, groceries, the car, the house, returns |

Domains are deliberately the same size. A by-domain failure rate can only be
read against another domain's if the denominators are comparable, and
`test_score.py` fails if they drift more than five captures apart.

## What is measured

Six accuracy measures and one harm measure, reported per domain and per family
and never averaged into a single figure. A set can route 95% of captures
correctly and still invert every negation it meets; one number hides exactly
that.

| measure | what a failure means |
|---|---|
| `routing` | the capture landed on Today when it belonged in Memory, or the reverse |
| `count` | the wrong number of user-visible rows came out |
| `split` | more rows than the speaker meant — a compound noun or a list torn apart |
| `merge` | fewer rows than the speaker meant — separate thoughts run together |
| `loss` | something the speaker said is gone from everything they can see |
| `invention` | the structured reading shows a value the speaker did not mean |
| `title` | the shown title still carries something the pipeline should have removed |
| `unsafe` | a capture no careful reader could pin down was scheduled, dated or modified anyway |

`unsafe` is harm rather than accuracy. Routing can move either way for
defensible reasons; this number should only ever fall.

### Why loss and invention read different surfaces

`loss` is checked against everything the user can see, the verbatim quote
included. If the words survive anywhere, nothing was lost.

`invention` is checked only against the **interpretation** — titles, dates,
reminders, recurrence, person, list, and an operation's target — because the
quote is supposed to hold the speaker's own words, superseded ones and all.
"buy the vanilla one not chocolate" *should* keep "chocolate" in its quote.
Counting that as invention would punish the pipeline for keeping its promise.
So the case labels `chocolate` as a rejected value and the check looks at what
the row decided, not at what the row quotes.

### Title hygiene is a lower bound, not a verdict

`title` does not score whether a title reads well. That is a judgement no label
can settle, and a number pretending to measure it is a number nobody should
trust. It scores something narrower and checkable: whether the title still
carries material the pipeline is supposed to have removed — a hesitation, a
trailing "bye", a numbered preamble, a stutter, an opening conjunction, or a
long capture whose title is simply the whole capture back.

Every rule fires only on material that is never content in title position.
Ambiguous fillers — `like`, `basically`, `honestly` — are deliberately absent,
because they are ordinary words often enough that flagging them would
manufacture failures. So everything this reports is real, and it misses some:
read it as a floor on title defects, never as a ceiling. Fifteen of the
instrument's tests exist to hold its false-positive rate at zero.

### Item types are reported, never gated

Today versus Memory is the product contract's hard line and is scored. Whether a
particular capture is an `idea` or a `note` is a judgement call a label cannot
settle, so type agreement is printed and never counted as a failure.

It prints on two lines, and the second is the one to read:

```
  item type matched the label 145/232  (reported, never gated)
    of those segmented right  145/192  ← the one that is about types
```

The plain figure cannot separate a type error from a count error. Both sides are
`Counter`s over rows, so a capture the pipeline split or merged wrongly differs
by a whole row and can never match, whatever types it chose — the generation-3
reading has 40 `count` failures and all 40 are inside its 87 type mismatches.
Quoted alone, 62.5% reads as a type problem when a third of it is the
segmentation problem already reported two lines above. Conditioned on correct
segmentation the figure is 75.5%, and the residue is 47 real type
disagreements.

The plain line is unchanged and no generation boundary is crossed; the second
line is additive.

## The label format

One tab-separated row per capture:

```
id  domain  utterance  expect  keep  reject  families  note
```

- **expect** — `|`-separated expected rows as `Route:type`, e.g.
  `Today:task|Memory:note`. `Op:cancel` for a capture that should modify stored
  data rather than create a row. `Ambiguous` on its own for a capture whose
  meaning a careful human reader could not pin down.
- **keep** — `|`-separated spans that must survive somewhere visible. This is
  where date, time, location, person, quantity and negation preservation are
  encoded: `Aug 6`, `17:30`, `Roncesvalles`, `no dairy`, `INV-2026-0412`. Dates
  are written as the probe prints them, in the fixed frame of reference below.
- **reject** — `|`-separated spans that must **not** appear in the
  interpretation: a superseded number, a corrected weekday, an inverted
  negation. `-` when there is nothing to reject.
- **families** — the language phenomena the capture carries, from a closed
  vocabulary, used for the per-family table. One capture usually carries
  several, so the family rows overlap by design. Families carrying fewer than
  about eight captures are too thin to read as a rate; treat them as a pointer
  to write more, not as a measurement.
- **note** — why a careful reader would call the expectation correct. It is
  printed beside every failure so a reviewer does not have to re-derive it.

Frame of reference is **Monday 2026-08-03 10:00 America/Toronto**, matching
`SemanticCorpusTests` and the probe exactly, so anything seen here reproduces as
a corpus case.

Every `Aug N` span is checked against the real calendar by `test_score.py`: the
capture must name that weekday, say "tomorrow" for the following day, or name
the day number outright. A wrong weekday in a held-out label is a false failure
that never goes away, and nobody would think to doubt it.

**Contested readings are not asserted.** "next Tuesday" spoken on a Monday can
honestly mean tomorrow or the week after, so no case in this set turns that
argument into a label. Where a capture contains one, the date is simply left
unasserted and the other properties are scored. A held-out label should be a
thing a careful reader would agree with on sight, not a position.

## Sealed by default

`score.py` prints rates and nothing else unless `--failures` or `--verbose` is
passed. That is a contract, not a convenience: a scorer that needs a flag to
stay sealed can be run from any harness safely, and a scorer that prints
failures by default cannot, because the harness has no way to un-print them.
`test_score.py` asserts it — default output contains no capture text, no failure
detail, and an unrecognised flag does not unseal it either.

Any scorer added to this directory must stay on that side of the line.

## Checking the instrument itself

Two checks run on every pull request, on Linux, in about twenty seconds, and a
third is written but not yet wired into CI. None needs a Mac.

`leak-check.py` compares each sealed set against every corpus development
touches, and against the other sealed sets. It fails on an exact collision or a
Jaccard overlap at or above 0.70. On a clean run it also prints the **closest
miss**, because pass/fail cannot show a set drifting: two sets both reported
clean are in different states if one tops out at 0.31 and the other at 0.68, and
only the second is one careless capture away. That number is reported, never
gated — a warning band would become a number people write captures to stay under,
which is the reason nothing else here gates either.

`measure-gate.py` breaks each of the eleven measures on purpose and requires the
suite to fail. "Protected" means *some* test fails when that measure breaks, not
necessarily the one named after it; that is the property worth having, since it
says a broken measure cannot reach a report.

A mutation harness is only as good as its control. The first version of that
file copied this directory alone into a scratch tree, which left 14 tests
failing before any mutation was applied — so every measure came back
"protected" whatever the mutation did. It reported eleven; the truth was nine,
with `count` and `ambiguous` uncovered until tests were written for them. The
control now runs first and the gate refuses to report if it is red. **If you add
a mutation harness anywhere in this repository, assert its unmutated baseline
passes before trusting a single verdict it prints.**

## The rule

**Do not read the failures while you are changing rules.**

Score the set, record the numbers, move on. `--failures` exists for release
review, not for development. The moment one of these captures is used to steer a
fix, it stops measuring generalisation and this directory is worth nothing.

If a held-out failure looks important enough to fix, reproduce the *family* in
`Tools/CorpusRunner/devsets/`, in its own file, and work there. The held-out
capture stays untouched and keeps measuring.

`leak-check.py` makes that boundary mechanical rather than a promise. It fails
if any capture here also appears — verbatim, or as a near-paraphrase at Jaccard
0.70 or above — in the gating corpus, in a development set, or in the older
held-out set. It locates each corpus's capture by reading its header rather
than assuming a column, because these files do not agree on layout — `heldout`
and the development sets put the utterance second, this set puts it third — and
a guard comparing the wrong field passes for the wrong reason, which is worse
than failing. A corpus file with no `utterance` header stops the check rather
than being skipped. It runs as part of `test_score.py`, which the corpus gate runs, so
a capture cannot leak in unnoticed. It has already caught two: `E04` was a
verbatim copy of a `heldout.tsv` case and `F28` was a paraphrase of one, both
introduced while this set was being written, and both were replaced.

## Comparing runs

A result is only comparable to another if it records what it was run against.
When scoring, record: the date, the commit, the six measures at `ALL DOMAINS`,
the per-domain routing and loss rates, and the `ACTED ON ANYWAY` count. Add a
row to the baseline table below. Do not add a row for a run whose failures were
read during development — say so instead, and treat the number as spent.

## Reading the per-family table

Worst family first, so somebody starts at the top. Two things made that order
a wrong claim, and both are the same mistake the held-out table made: a rate
read without the denominator underneath it.

**A family is ranked on its weakest of five measures, and the table prints
three.** `loss` and `invention` have no column here. So a family could hold the
top row of a worst-first list with `routing`, `count` and `title` all reading
100% — a position nothing on the line explains. A row in that situation now
says so:

```
<family>   18   <routing>   <count>   <title>   ← ranked on invention 0/1
```

The three printed rates in a row like that can each read in the nineties. The
mark is what says the row is not there because of them. (The shape is written
out rather than filled in on purpose: no reading of this set has been taken
since the change, so there is no real row to quote.)

Rows ranked on a printed column carry no mark, because the evidence is already
in front of the reader and a mark on every row is decoration.

**Ties broke on `n`, which is the denominator of nothing here.** `n` counts
captures carrying the tag; each measure is scored over whichever of those it
applies to, and the two are far apart:

| family | n | captures scored for invention |
|---|---|---|
| `person` | 33 | 2 |
| `recurrence` | 22 | 1 |
| `filler` | 18 | 1 |
| `proper-noun` | 15 | 1 |
| `false-start` | 14 | 1 |
| `location` | 12 | 1 |

Six of the set's 25 families are in that position, and fifteen have no
invention denominator at all. Under the old key, `recurrence` at `invention
0/1` outranked `run-on` at `routing 0/8` — 22 against 8 on paper, 1 against 8
in evidence. The tie is now broken on the denominator of the ranking measure
itself, then on the family name so the order never depends on spelling.

**A family with nothing scored at all is not ranked.** It used to score 1.0,
which is where a family that passes everything belongs. Reaching that needs
every capture carrying the tag to be missing from the probe output — which is
not hypothetical: one label against an empty probe run does it, and the first
draft of the fix asserted it could not happen and was corrected by the suite.

The adversarial set is scored by this same file and is not affected in
practice: its invention denominators are 0, 12 or 24, never thin.

**The published worst-families table below is not in this order and never
was**, so nothing in it needs revisiting and nobody should "fix" it to match.
The rule for every hand-transcribed table of this set is: **ascending by the
printed `routing` column, with `ambiguous` last for want of one.**

Checkable from the figures rather than taken on trust. In the generation-3
table below — which predates the discourse-framing fix — three of its eight
rows sit at 0.000 under the scorer's key: `run-on` on routing 0/8,
`trailing-goodbye` on **title 0/7**, `operation` on count 0/2. They are
published first, third and sixth, and the scorer would have led with
`operation`. `trailing-goodbye` is the example to reach for because its zero is
printed, so the argument needs none of the invisible columns.

**That example does not travel.** `trailing-goodbye` is title 7/7 in
`Docs/LANGUAGE_BASELINE.md`'s post-fix table, where only two rows sit at 0.000.
Attach the claim to a table before making it; the reasoning survives, the count
does not.

`ambiguous` is last in every one of those tables because it has **no routing or
count rate at all** — its captures are unpinnable, so only `title` is scored.
The scorer agrees without being told to: with one rate available it ranks on
that rate, lands last, and carries no mark, because `title` is a printed column
and the `—` cells beside it say the rest. Whoever transcribed these tables
arrived at the same place by hand.

What the change above affects is the scorer's own output, not those tables.
`Docs/LANGUAGE_BASELINE.md` states the rule under each of them, including one
recorded hairline inversion that was left alone rather than silently corrected.

**And a note on how this section was nearly wrong.** Its first draft said the
published table "was ordered by the old key — treat the order as unverified
until the next reading". That was an assumption wearing a caveat: checking it
against the table's own figures took a minute, and it would have sent somebody
to fix a table that was already right. **A claim that something is unverified
is itself a claim, and needs the same check as a claim that something is
wrong** — it is the same move as a `1.0` fallback or a `KNOWN:` marker, a way
of not having a number while looking careful about it.

No rate changes either way — only where rows sit in the report.

## Generations

The set grows, and a measure whose denominator moved is not comparable across
the move. Each change below opens a new generation; compare rows within one,
never across.

| generation | from | captures | invention cases | span matching |
|---|---|---|---|---|
| 1 | 2026-09-11 | 235 | 19, of which 7 were farewells | substring |
| 2 | 2026-09-11 | 235 | 12 (farewell cases cleared) | substring |
| 3 | 2026-09-11 | 255 | 22 | left-anchored |

`Tools/CorpusRunner/generations.tsv` records this set at generation 3, and
`generation-check.py` reports whether a capture's text has changed without a
new row above. **It does not run in CI yet** — wiring it needs a one-step
change to `.github/workflows/ci.yml`, split into its own pull request because
this repository's automation cannot merge a workflow edit. Until that lands it
is a command somebody has to remember to run. It also cannot tell a legitimate
generation from a quiet edit — they are the same diff — so the rows above still
do the real work; the check only makes the edit impossible to make silently.

Generation 3 changed two things at once, deliberately, at a pause between runs
rather than between two comparisons:

- **Twenty captures added**, four per domain, each carrying a genuine superseded
  value: a corrected number, time, weekday, person, place, or a contrast the
  reading must not invert. The other measures gain 20 captures and shift
  slightly for that reason alone.
- **Contrast captures no longer assert invention.** Ten captures phrase an
  exclusion rather than a repair — `book the small meeting room not the big
  one`. The excluded value is spoken deliberately, so a title that preserves the
  contrast is faithful, and a substring test over the reading cannot tell
  `excluded the big room` from `booked the big room`. Two of them were worse
  than ambiguous: W38 and E20 rejected the strings `not 2D` and `not 6`, which a
  *correct* title contains. All ten keep their captures and their `negation`
  family label, and `test_score.py` now fails if a `negation` capture is given a
  `reject` span.

**What is now unmeasured is narrower than "negation", and the distinction
matters.** All 48 negation-family captures are still scored for routing, count,
loss and title — negation is one of the weaker routing families in the set, and
that signal is intact. What no measure here reports is **invention on a negated
or superseded value**: whether the reading treated the operative value as the
operative one. That needs a judgement a span test cannot make, so its home is a
readable development set. Do not close this gap by re-adding a `reject` span to
a contrast capture — that is the defect this section exists to record.

Between the twenty added and the ten withdrawn, `invention` moves from 12 cases
to 22, all of them genuine supersessions, so its rate sits on a different
denominator from every earlier row.
- **Span matching now anchors its left edge.** It was a plain substring test over
  normalised text, where `6:40` folds to `6 40` — which sits inside `16 40`. A
  pipeline that read a corrected time *correctly* could be reported for inventing
  the value it had discarded. The right edge stays open, because labels are
  written in the spoken form (`500 gram`) and a rendering may inflect it
  (`500 grams`); a suffix match cannot manufacture a failure. The fix is in
  `carries()` and is covered four ways in `test_score.py`.

The direction of the matching change is known even though it has not yet been
re-run: `loss` can only get stricter and `invention` can only get less false. It
also fixes a latent case that predates the new captures — F33 rejects `8:45`,
which the old matcher would have found inside a rendered `18:45`.

### Family denominators move independently of generations

A generation is about a *measure* changing — its cases or its matching. A
family's denominator can move without any of that, because a capture gained or
lost a family tag. Those edits are invisible in the table above and still make
a per-family rate incomparable, so they are recorded here:

| date | family | from | to | why |
|---|---|---|---|---|
| 2026-09-11 | `negation` (everyday) | 48 | 51 | W09, F05 and F14 exclude a value with `not` and carried no tag |

No capture and no `reject` span changed in that edit, so every headline measure
is untouched — only the `negation` row of the per-family table moves. The
matching edit on the adversarial set is recorded in its own README.

## Baseline

| date | commit | routing | count | loss | invention | title | unsafe / ambiguous |
|---|---|---|---|---|---|---|---|
| 2026-09-11 | `330344a` | 152/220 (69.1%) | 172/212 (81.1%) | 210/224 (93.8%) | 5/19 (26.3%)* | 217/235 (92.3%) | **0 / 15** |
| 2026-09-11 | `2c5ac5b` | 167/240 (69.6%) | 192/232 (82.8%) | 230/244 (94.3%) | 14/22 (63.6%) | 237/255 (92.9%) | **0 / 15** |

*Generation 1. The invention column used the 19-case measure, 7 of whose cases
were farewells; it is not comparable to any later row. The whole row predates
generation 3, so every column in it is a generation-1 reading.

First reading, from `language_only` run 34586389323 on `macos-26`. Scored
non-verbose; the failures were not read. Over-segmented 17, under-segmented 23,
captures producing nothing 0, item type agreed on 132/212.

By domain, routing and loss:

| domain | routing | count | loss | title |
|---|---|---|---|---|
| work-school | 33/44 (75.0%) | 35/42 (83.3%) | 38/43 (88.4%) | 42/47 (89.4%) |
| family-health | 27/44 (61.4%) | 35/43 (81.4%) | 45/45 (100.0%) | 44/47 (93.6%) |
| money-travel | 29/44 (65.9%) | 35/43 (81.4%) | 42/45 (93.3%) | 45/47 (95.7%) |
| freelance | 29/44 (65.9%) | 33/42 (78.6%) | 41/45 (91.1%) | 41/47 (87.2%) |
| fitness-errands | 34/44 (77.3%) | 34/42 (81.0%) | 44/46 (95.7%) | 45/47 (95.7%) |

Three things to carry forward rather than the headline.

**Nothing was acted on that should not have been.** 0 of 15 ambiguous captures
were scheduled, dated or modified, and no capture produced nothing at all. The
harm measure is clean on its first reading, which is the row that should only
ever fall.

**Under-segmentation is larger than over-segmentation here** — 23 merges against
17 splits. That runs opposite to the clause-segmentation reading on the older
held-out set, where five of six failures were over-splits. Both can be true:
they are different sets measuring different content. It means neither direction
should be assumed to be *the* segmentation problem without saying which set the
claim comes from.

### Generation 3, commit `2c5ac5b`, run 34591348628

The second row above. `language_only` on `macos-26`, scored non-verbose. This is
the **before** picture for the discourse-framing work: it predates #30, and it
also predates #32 and #33, so the adversarial set is absent from it and the
`negation` family denominator is still 48.

**Do not read it against the generation-1 row.** Both the cases and the span
matching changed between them; 69.1% and 69.6% are not a movement, they are two
different measurements. The first genuine comparison will be this row against
the next one.

| domain | routing | count | loss | invention | title |
|---|---|---|---|---|---|
| fitness-errands | 37/48 (77.1%) | 38/46 (82.6%) | 48/50 (96.0%) | 3/4 | 49/51 (96.1%) |
| work-school | 35/48 (72.9%) | 39/46 (84.8%) | 42/47 (89.4%) | 4/4 | 46/51 (90.2%) |
| freelance | 33/48 (68.8%) | 37/46 (80.4%) | 45/49 (91.8%) | 3/5 | 45/51 (88.2%) |
| money-travel | 32/48 (66.7%) | 39/47 (83.0%) | 46/49 (93.9%) | 4/5 | 49/51 (96.1%) |
| family-health | 30/48 (62.5%) | 39/47 (83.0%) | 49/49 (100.0%) | 0/4 | 48/51 (94.1%) |

**The domain column is not where the failures live, and this table should not be
read as if it were.** All five domains sit inside one standard error of the
whole-set routing rate: at n=48 and p=0.696 that is ±6.6 points, and the spread
is 62.5% to 77.1%. A chi-square across the five gives 2.9 on 4 degrees of
freedom, against 9.49 for significance at 0.05 — no evidence that the subject a
person is talking about predicts whether Speak It understands them. The same
test across fourteen families gives 54.9 on 13 degrees of freedom, against
22.36. **Failure is a function of how people speak, not what they speak about.**

That is worth stating plainly because per-domain rates are the natural thing to
quote and would send work in the wrong direction. Balanced domains were the
right design — they make this testable — but their value is as a control, not
as a diagnosis.

The invention column is 4 or 5 cases per domain and is not a rate at any domain
granularity. `family-health` reads 0/4: four named cases, not 0%.

Worst families, which is where the structure actually is. **Sorted by the
printed `routing` column, not by the scorer's own ranking** — see "Reading the
per-family table" above for why the two differ and why this table is right as
it stands:


| family | n | routing | count | title |
|---|---|---|---|---|
| run-on | 8 | 0/8 (0.0%) | 0/8 (0.0%) | 4/8 (50.0%) |
| rambling-intro | 6 | 1/6 (16.7%) | 1/6 (16.7%) | 3/6 (50.0%) |
| trailing-goodbye | 7 | 2/7 (28.6%) | 4/7 (57.1%) | 0/7 (0.0%) |
| sequencing | 17 | 6/17 (35.3%) | 7/17 (41.2%) | 12/17 (70.6%) |
| multi-thought | 40 | 19/40 (47.5%) | 22/40 (55.0%) | 36/40 (90.0%) |
| operation | 10 | 5/10 (50.0%) | 0/2 | 10/10 (100.0%) |
| cancellation | 12 | 6/12 (50.0%) | 1/4 | 12/12 (100.0%) |
| hedged | 24 | 9/17 (52.9%) | 15/17 (88.2%) | 19/24 (79.2%) |

Every family that reads meaning *after* a correct cut is in the eighties or
nineties: `self-correction` 30/39, `quantity` 27/34, `time` 21/27, `recurrence`
19/22, `repetition` 10/10. The five worst are all about finding the boundaries
of a thought inside speech that has framing around it.

Two caveats that belong next to these numbers rather than in a message:

1. **The simulator suite was red on the same commit and the same runner.** The
   corpus gate passed 1381/1381 natively in that job, and these figures come
   from the host-side runner, so they are not invalidated. But `SpeakItTests`
   failed with 57 assertions on `macos-26` at `2c5ac5b`, identically to an
   unrelated branch, so it is the state of the suite on that image rather than
   anyone's diff. Until that is understood, every figure here was taken on a
   commit whose simulator tests do not pass on that runner.
2. **`item type matched the label` is 145/232 (62.5%)** — and a third of that
   gap is the `count` failure printed two lines above it, not a type problem.
   See *Item types are reported, never gated* for why the comparison cannot
   separate them. Conditioned on correct segmentation it is 145/192 (75.5%),
   leaving 47 genuine type disagreements. Still reported, still never gated,
   and still nobody's investigation — but 62.5% is not the number to
   investigate.

**`invention` was measuring two things and has been corrected.** Seven of its
nineteen cases listed `bye` as the rejected value. A farewell left in a title is
a title defect, and `title` already counts it — so when the discourse-framing
change of 2026-09-11 removed farewells, `invention` moved 5/19 → 12/19 with the
jump being exactly those seven captures and not one superseded value resolved.
On the twelve cases that actually test a superseded value, the score was 5/12
before that change and 5/12 after: **unchanged**. One fix had been counted
twice.

`reject` now carries only values the reading must not assert — a superseded
number, a corrected weekday, an inverted negation — and `test_score.py` fails if
a farewell is ever added back. The measure is 22 cases, thickened as described
below, and should be
done as a deliberate, announced addition rather than silently between two
comparisons.

Worst families by routing: `run-on` 0/8, `rambling-intro` 1/6,
`trailing-goodbye` 2/7, `sequencing` 6/17, `multi-thought` 19/40. On title
hygiene, `trailing-goodbye` is 0/7 — "bye" reaches the title every time it is
spoken. Families below about eight captures are pointers to write more, not
measurements.

The set and the scorer were built in a Linux container, where the pipeline
cannot be executed at all. The instrument has been tested against hand-written
probe output — 46 cases covering every measure, in `test_score.py` — but no
number in this table can be filled in until `score.sh` is run on a Mac. Until
then this directory is an instrument with no reading, and saying otherwise would
be inventing a result.

The runner itself has been exercised end to end against a stand-in probe: the
shell plumbing extracts all 255 captures, invokes the probe and renders the full
report, so the only unrun link in the chain is the pipeline. If this block is
missing or empty in a language-metrics report, the cause is the engine or the
build, not this script.

Those tests are not ceremony. Three of them caught real defects in the scorer
while it was being written: operation targets were not counted as visible
output, so every correctly handled cancellation scored as data loss; a field
pattern used `\s`, which matches a newline, so an empty field read the next
line's value as its own; and two captures written for this set turned out to be
a copy and a paraphrase of `heldout.tsv` cases.
