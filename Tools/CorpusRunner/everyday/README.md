# Everyday speech — held-out set

235 captures of ordinary adult life, 47 in each of five domains, written from
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
held-out set. It runs as part of `test_score.py`, which the corpus gate runs, so
a capture cannot leak in unnoticed. It has already caught two: `E04` was a
verbatim copy of a `heldout.tsv` case and `F28` was a paraphrase of one, both
introduced while this set was being written, and both were replaced.

## Comparing runs

A result is only comparable to another if it records what it was run against.
When scoring, record: the date, the commit, the six measures at `ALL DOMAINS`,
the per-domain routing and loss rates, and the `ACTED ON ANYWAY` count. Add a
row to the baseline table below. Do not add a row for a run whose failures were
read during development — say so instead, and treat the number as spent.

## Baseline

| date | commit | routing | count | loss | invention | unsafe / ambiguous |
|---|---|---|---|---|---|---|
| _not yet scored_ | | | | | | |

The set and the scorer were built in a Linux container, where the pipeline
cannot be executed at all. The instrument has been tested against hand-written
probe output — 28 cases covering every measure, in `test_score.py` — but no
number in this table can be filled in until `score.sh` is run on a Mac. Until
then this directory is an instrument with no reading, and saying otherwise would
be inventing a result.
