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

## Baseline

Recorded 2026-08-25, after the speech-act scope and prohibitive-reminder work:

| measure | value |
|---|---|
| destination correct | 229/320 (71.6%) |
| thought count correct | 252/310 (81.3%) |
| captures producing nothing | 0 |
| genuinely ambiguous captures | 69 |
| **acted on anyway** | **9 (13.0%)** |

The last row is the one to watch. It counts captures whose meaning a careful
human reader could not pin down, on which the app nevertheless scheduled
something, dated something, or modified stored data. Destination accuracy can
move either way for defensible reasons; that number should only ever fall.

`Ambiguous-preserve` labels come from the original author marking, honestly,
that they could not tell what the speaker meant. They are not parser failures by
construction — they are the cases where guessing is worse than abstaining.
