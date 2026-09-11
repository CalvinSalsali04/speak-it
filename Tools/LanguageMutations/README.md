# Language mutations

A discovery instrument. It rewrites a capture in ways that do not change what
the speaker wants, runs both readings through the rules path, and reports where
Speak It answered them differently.

```bash
./Tools/LanguageMutations/invariance.sh Tools/CorpusRunner/devsets/routed.tsv
./Tools/LanguageMutations/invariance.sh Tools/CorpusRunner/devsets/routed.tsv --verbose
```

## Why this exists

The charter is comfortable with very large synthetic volume and warns, rightly,
that volume is not the result. Two million variations of twenty sentence shapes
are not evidence that anything is understood.

The way to get the first without the second is to stop asking whether an
utterance passed. A **disagreement needs no ground truth to be interesting**: if
"buy milk" goes to Today and "um, buy milk" goes to Memory, one of those two is
wrong, and nobody had to write down which in advance. So this can be pointed at
any quantity of language, including language nobody has labelled, and every
finding it produces is real.

## What it measures, and what it does not

**Consistency, not correctness.** A capture the engine gets wrong identically
under every mutation is counted clean here. A run with no disagreements is not
evidence that the product works, and no number from this tool may be quoted as
accuracy. It finds problems; it certifies nothing.

That limit is deliberate and is the price of needing no labels. Correctness is
measured by the corpora under `Tools/CorpusRunner/`, which have expectations
authored against the product contract.

## The families

Each mutation claims one of two strengths, declared in `mutate.py`:

| strength | promise |
|---|---|
| `strict` | the structured result must be identical — destination, rows, titles, dates |
| `structure` | destination and row count must be identical; titles may differ, because the mutation deliberately changed a word |

| family | strength | what it varies |
|---|---|---|
| `filler` | strict | "um", "uh", "like", "you know" between words |
| `repetition` | strict | a stuttered or restarted phrase |
| `unpunctuated` | strict | commas and semicolons the recogniser guessed at |
| `lowercased` | strict | sentence case the recogniser imposed |
| `preamble` | strict | a rambling opening — "okay so", "right" |
| `sign-off` | strict | a trailing "bye", "thanks", "that's it" |
| `contraction` | strict | "want to" → "wanna", "have to" → "hafta" |
| `conjunction` | strict | "and then" → "after that" → "then" |
| `restart` | strict | an abandoned opening before the real one |
| `proper-noun` | structure | one unknown store or person name for another |

`restart` is modelled on Disfl-QA's human-written restarts rather than on an
invented pattern, and it always leaves the original sentence whole at the end,
so the meaning is exactly the original's. See `Docs/PUBLIC_DATASETS.md`.

## The sealed set

`mutate.py` refuses to read anything under `Tools/CorpusRunner/heldout/`.
Mutating a held-out sentence would put near-duplicates of it into a
development-visible file, which destroys the set as a measure of generalisation
just as surely as reading its failures does. Point this at development sets and
at public-derived language.

## Why it is not in the CI metrics job

`Tools/CI/language-metrics.sh` reports the numbers a change is judged on. This
tool reports candidate defects, which are read and triaged rather than tracked,
and it has not yet been run against the real engine — the probe links Apple's
`NaturalLanguage` and needs macOS. Its first real run should be read by a
person, and a family that proves stable can earn a place in the metrics report
afterwards.

## Tests

```bash
cd Tools/LanguageMutations && python3 -m unittest discover
```

They need no Mac and run in the Linux CI job. `test_mutate.py` checks the
property the whole instrument rests on — that a strict mutation keeps every
content word — because a mutation that is not meaning-preserving turns every
disagreement downstream into noise. `test_compare.py` drives the reporter from
a synthetic probe transcript, since the probe itself cannot run on Linux.
