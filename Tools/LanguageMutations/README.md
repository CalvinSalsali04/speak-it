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

Each mutation claims one of three strengths, declared in `mutate.py`:

| strength | promise |
|---|---|
| `strict` | the structured result must be identical — destination, rows, titles, dates |
| `structure` | destination and row count must be identical; titles may differ, because the mutation deliberately changed a word |
| `divergent` | the two readings must **not** be identical — the mutation changed what the speaker means, so one answer cannot serve for both |

`divergent` inverts the test rather than adding a label, and it needs no ground
truth for the same reason the others do not: it never says which reading is
right, only that the engine has to tell the two apart. "call Sarah" and "don't
call Sarah" have several defensible answers between them and no shared one.

**A divergent family has three outcomes, and the report has a column for each.**
Every divergent family works by adding words, and a row title is built from the
person's words, so the title differs almost by construction. If that counted as
the engine noticing, the test would be satisfiable by string propagation: Speak
It could answer "don't call Sarah" with an open Today errand titled "Don't call
Sarah" and the run would be clean. So:

| column | what it means |
|---|---|
| `disagreed` | literally the same answer on both sides — the engine is blind to the distinction |
| `title-only` | the row title moved and nothing the person acts on did — same destination, rows, operation and dates |
| neither | the destination, row count, operation or dates moved: the engine acted differently |

**Read the `title-only` column before treating a family's zero as
understanding.** It is not a pass and not a defect; it is the finding that the
words survived and the consequence did not.

| family | strength | what it varies |
|---|---|---|
| `filler` | strict | "um", "uh", "like", "you know" between words |
| `repetition` | strict | a stuttered or restarted phrase |
| `unpunctuated` | strict | commas and semicolons the recogniser guessed at |
| `lowercased` | strict | sentence case the recogniser imposed |
| `preamble` | strict | a rambling opening — "okay so", "right" |
| `sign-off` | strict | a trailing "bye", "thanks", "that's it" |
| `contraction` | strict | "want to" → "wanna", "have to" → "hafta" |
| `modality` | divergent | "call Sarah" → "I might call Sarah" |
| `negation` | divergent | "call Sarah" → "don't call Sarah" |
| `completion` | divergent | "buy milk" → "I already bought milk" |
| `reported` | divergent | "call Mike" → "Sarah said to call Mike" |
| `reported-obligation` | divergent | "call Mike" → "Sarah said I should call Mike" |
| `conjunction` | strict | "and then" → "after that" → "then" |
| `restart` | strict | an abandoned opening before the real one |
| `proper-noun` | structure | one unknown store or person name for another |

`restart` is modelled on Disfl-QA's human-written restarts rather than on an
invented pattern, and it always leaves the original sentence whole at the end,
so the meaning is exactly the original's. See `Docs/PUBLIC_DATASETS.md`.

Two further limits of the divergent families, stated so a clean report is not
misread:

- **They only apply to a bare imperative errand.** Prefixing "don't" onto "the
  garage code is 4821" is not English, so a set of statements yields nothing
  from them and a zero there means "not applicable", never "passed".
- **They compare a mutation against its base, never against each other.**
  `reported` and `reported-obligation` are both required to differ from "call
  Mike"; whether "Sarah said call Mike" differs from "Sarah said I should call
  Mike" is a pairwise question this harness does not ask, and it is one of the
  distinctions Calvin's section 9 asks to survive.

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
