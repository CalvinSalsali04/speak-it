# Interpretation probe

Runs the Foundation Models interpretation path (`SpeakIt/Interpretation/`)
beside the rules path, in the same frame of reference — Monday 2026-08-03 10:00
America/Toronto — and in the **same report format**, so every language scorer
this project already has can score it unchanged.

```bash
./Tools/InterpretationProbe/build.sh
./Tools/InterpretationProbe/build/interpret --availability
```

## The two halves, and why they are separate

`--interpret` needs a model, which needs an Apple Intelligence device and a
person to run it. Everything after it does not.

```bash
# on a device that has the model
interpret --interpret utterances.txt --out runs.jsonl --runs 3

# anywhere, including a CI runner with no model at all
interpret --replay runs.jsonl
interpret --spread runs.jsonl
```

A `runs.jsonl` record holds the utterance, the exact text the model was given,
the settings it ran under, and the interpretation — or the reason there was
none. So a run made once on hardware can be re-scored by anybody, and a change
to the policy or the bridge is checkable without paying for the model again.

## Scoring it

`--replay` prints the same rows `Tools/PipelineProbe/build/probe` prints (both
use `Tools/PipelineProbe/rowreport.swift`), so:

```bash
interpret --replay runs.jsonl > /tmp/interp.txt
python3 Tools/CorpusRunner/devsets/score.py Tools/CorpusRunner/devsets/runon.tsv /tmp/interp.txt
```

`--fallback` changes the question. Without it, a reading the policy rejected
scores as a failure and you are measuring the model path alone. With it, a
rejected reading falls back to the rules, which is what shipping would do.

`--annotate` adds the disposition and obligation under each row. The scorers
never see it; it is for reading failures by hand.

## What it cannot tell you

- **Whether a reading is right.** It reports what the pipeline produced. The
  scorers say whether that matches a label somebody wrote.
- **Anything about latency on a phone.** This is a Mac binary.
- **Anything about audio.** Like every instrument here, it starts from text.
- **Anything about speech that was not written by this project.** Every
  readable utterance in this repository was authored here.

## Held-out sets

This tool reads a file of utterances it is handed; it never walks a corpus
directory itself. Whoever hands it a sealed set is accountable for that, and the
only model it can reach is the on-device one —
`Tools/CorpusRunner/test_interpretation_isolation.py` fails the build if that
ever stops being true. The rule is absolute because a set that has been sent to
somebody's server cannot be made unseen again.
