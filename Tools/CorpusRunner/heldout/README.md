# Held-out set

389 utterances written **before anyone read the parser**, from the product
description alone.

```bash
./Tools/CorpusRunner/heldout/score.sh
./Tools/CorpusRunner/heldout/score.sh --verbose   # only at release
```

## Why it is separate from the corpus

`SpeakItTests/SemanticCorpus*` is authored from the product contract by the same
person who writes the rules. That makes it an excellent regression net and a
poor progress meter: it can tell you the app still agrees with itself, and it
cannot tell you whether the app generalises. It currently runs at 999 of 1,022
clean with zero blocking failures, so as an instrument it is at ceiling.

This set is the other half. Nobody consulted the implementation while writing
it, so agreement here is evidence about language rather than about memory.

## The rule

**Do not read the failures while you are changing rules.**

Score it, record the number, move on. The moment one of these sentences is used
to steer a fix, it stops being held out and this directory is worth nothing.
`--verbose` exists for release review, not for development.

If a held-out failure looks important enough to fix, write a *new* case for it
in the gating corpus, in its own family, and fix that. The held-out sentence
stays untouched and keeps measuring.

## Reading the per-family table

The scorer prints a family row for every tag, worst destination rate first, and
that ordering is what triage starts from. Two things decide whether a row can
carry the weight of being read that way.

**`n` is not the denominator.** `n` counts captures carrying the tag; the
destination rate is computed only over captures the set commits to a
destination. A capture labelled `Ambiguous-*` is excluded by design — the
contract for an unpinnable capture is to keep it and not act on it, which
`ACTED ON ANYWAY` measures instead. Sixty-nine of the 389 captures are labelled
that way, and they are not spread evenly: seventeen of the thirty-two families
have a destination denominator below their row count. Read the denominator from
its own column, never from `n`.

**Five families cannot be ranked on destination, or barely can.**

| family | captures | scorable for destination |
|---|---|---|
| `ambiguous` | 14 | **0** |
| `sarcasm` | 1 | **0** |
| `hypothetical` | 4 | **1** |
| `question` | 12 | **1** |
| `ellipsis` | 12 | **4** |

`ambiguous` and `sarcasm` are unrankable by construction and the scorer now
prints them under `NOT RANKED` rather than in the list; they are measured by
`ACTED ON ANYWAY`. `hypothetical` and `question` produce a rate that one
capture decides. Quote those as named cases — "0 of 1" — and never as a
percentage; a single capture is a direction, not a measurement.

That is also why `ellipsis` 0 of 4 is worth what it is worth. It is the worst
destination row in the set and it rests on four captures, which is enough to
say the stage is weak and not enough to size the work.

Until this was fixed the ordering misled twice over: a family with nothing
scorable scored 1.0 and sorted to the bottom, where a family that passes
everything belongs, and ties broke alphabetically, so a rate over one capture
could sit above a rate over twenty-one. Ranking is now rate first, then
denominator descending, and `Tools/CorpusRunner/test_score.py` holds both.

None of this needs the engine: it is the composition of the label file, so it
changes only when the set does. A retag moves these denominators without
opening a generation — see below.

## Generations

A generation opens when a capture's **text** changes — edited, added or
removed. Numbers never compare across one. A retagged family, a changed note
or a rewritten README is not a generation; family denominators move
independently and are tracked separately where that applies.

| generation | recorded | captures | what changed |
|---|---|---|---|
| 1 | 2026-09-11 | 389 | first record. Generation 1 is this set as it stands today, not a reconstruction of its history. |

`Tools/CorpusRunner/generations.tsv` holds the same number for every sealed
set, and `everyday/generation-check.py` reports whether a capture here has changed
without a new row above. **It runs on every pull request that touches `Tools/CorpusRunner/**`**, in the
`language-tools` job beside the leak check — not in the corpus gate, which
needs a Mac and is dispatch-only, so a guard living there would not run on the
pull request that introduces the edit it exists to catch. Run it by hand with

    python3 Tools/CorpusRunner/everyday/generation-check.py

What it proves once wired is narrow and worth stating: it cannot tell a
legitimate new generation from a quiet edit, because they are the same diff.
The row above does the real work — the check only makes the edit impossible to
make silently.

## Baseline

Recorded 2026-08-25, after the contextual-semantic (Phase 2) work. The previous
column is the speech-act scope and prohibitive-reminder baseline it replaced.

| measure | before | after | 2026-09-08 |
|---|---|---|---|
| destination correct | 229/320 (71.6%) | 229/320 (71.6%) | 231/320 (72.2%) |
| thought count correct | 252/310 (81.3%) | 251/310 (81.0%) | 250/310 (80.6%) |
| captures producing nothing | 0 | 0 | 0 |
| genuinely ambiguous captures | 69 | 69 | 69 |
| **acted on anyway** | **9 (13.0%)** | **8 (11.6%)** | **8 (11.6%)** |

The 2026-09-08 column was scored once, non-verbose, after the arguable corpus
cases were decided (`Docs/DECISIONS.md`, same date). The failures were not
read: the one-count movement is recorded, not chased. Scored once more on
2026-09-09 after the development-set pass: identical on every row. Scored a
third time the same day after the forty-capture batch (`Docs/DECISIONS.md`):
destination 230/320, thought count 251/310, nothing produced 0, acted on
anyway 8 — one case each way, not read. Scored again after the two agent
rounds of 2026-09-09 (`Docs/DECISIONS.md`, same date): destination 233/320
(72.8%), thought count 255/310 (82.3%), nothing produced 0, acted on anyway
7 (10.1%). All three rows moved the right way; still not read.

The rules that moved the last row were developed against
`Tools/CorpusRunner/devsets/`, not against these sentences. On that development
set the same change took unsafe actions from 8/22 to 2/32, and only one of them
carried here — which is the honest reading of how much the development families
overlap the ambiguity this set contains, and is worth knowing.

The last row is the one to watch. It counts captures whose meaning a careful
human reader could not pin down, on which the app nevertheless scheduled
something, dated something, or modified stored data. Destination accuracy can
move either way for defensible reasons; that number should only ever fall.

`Ambiguous-preserve` labels come from the original author marking, honestly,
that they could not tell what the speaker meant. They are not parser failures by
construction — they are the cases where guessing is worse than abstaining.

September 9 continuation: one non-verbose evaluation after the date-topic guard
returned the same final baseline: 233/320 destination, 255/310 thought count,
7/69 ambiguous captures acted on, zero missing outputs and zero captures lost.
The scorer now reports dataset origin and actual size rather than calling every
input held-out, and includes empty ambiguous captures in the content-loss count.
The held-out examples and individual failures were not read.
