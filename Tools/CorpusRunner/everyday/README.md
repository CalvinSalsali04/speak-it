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

## Generations

The set grows, and a measure whose denominator moved is not comparable across
the move. Each change below opens a new generation; compare rows within one,
never across.

| generation | from | captures | invention cases | span matching |
|---|---|---|---|---|
| 1 | 2026-09-11 | 235 | 19, of which 7 were farewells | substring |
| 2 | 2026-09-11 | 235 | 12 (farewell cases cleared) | substring |
| 3 | 2026-09-11 | 255 | 22 | left-anchored |

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
  `reject` span. **Negation is consequently unmeasured by `invention` and by
  nothing else either — that is a real gap in this instrument, named rather than
  papered over.** Measuring it needs a judgement about which value the reading
  treated as operative, which a span test cannot make.

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

## Baseline

| date | commit | routing | count | loss | invention | title | unsafe / ambiguous |
|---|---|---|---|---|---|---|---|
| 2026-09-11 | `330344a` | 152/220 (69.1%) | 172/212 (81.1%) | 210/224 (93.8%) | 5/19 (26.3%)* | 217/235 (92.3%) | **0 / 15** |

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
