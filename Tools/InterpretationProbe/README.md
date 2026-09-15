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

**A `runs.jsonl` generated from a sealed set is itself sealed material.** It
holds every capture it was given, verbatim, which is exactly what the seal is
about. Do not commit one, paste one into a thread, attach one to a pull request,
or upload it as a CI artefact; `.gitignore` covers the obvious paths, but the
rule is about where the file goes, not where it sits. Re-scoring a sealed run
means running `--replay` on the machine that holds it and reporting the scorer's
counts.

## The input file

One capture per line. A line with no tab is the whole capture. A line with
exactly one tab is `id<TAB>capture`: the id rides along on every record, and
reports that must not print capture text — `--spread` — name captures by it. A
sealed set is the case this exists for.

**A corpus TSV is not this format and the reader refuses one.** These files are
`id, utterance, family, expected_destination, expected_thoughts` — five columns
in `heldout.tsv` and `devsets/routed.tsv`, eight in `everyday.tsv` — and
everything after the utterance is the expected answer. A reader that split on the
first tab and kept the remainder would hand the model `utterance<TAB>family<TAB>
destination<TAB>count` as the capture and record that string as the grounding
input: the expected answer, in the prompt. The run would fail eventually, at the
scorer, but only after the device time had been paid for. So a line carrying a
second tab stops the tool on that line number, and a corpus file is cut to its
first two columns first, which are already `id<TAB>capture`:

```bash
grep -v '^#' Tools/CorpusRunner/devsets/routed.tsv | tail -n +2 | cut -f1,2 > /tmp/captures.tsv
```

The refusal names the line number and never echoes the line, because the line may
be a sealed capture and a diagnostic is not a place to print one.

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

`--spread` answers a different question from the scorers: how often the same
capture read two ways across runs. It prints counts, a breakdown of how many
distinct readings the unstable captures had, and ids where the input file
supplied them. It never prints capture text, so it is safe to quote from a
sealed run.

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
ever stops being true, and it reads this tool's own sources as well as the app's,
because this is the side that actually holds a set's text in memory. The rule is absolute because a set that has been sent to
somebody's server cannot be made unseen again.
