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

## The first run on a device

`first-run.sh` is the whole generating half in one command, for somebody who
has Apple Intelligence and should not have to think about cuts and flags:

```bash
./Tools/InterpretationProbe/first-run.sh              # runon, 1 run
./Tools/InterpretationProbe/first-run.sh runon 3      # three runs, for --spread
./Tools/InterpretationProbe/first-run.sh all 1        # all 631 development captures
```

It builds the probe, prints and records `--availability` (stopping there, with
the reason, if the model is not reachable), cuts the development set to
`id<TAB>capture`, generates, times the run, and says which file to send back.
**Development sets only: the set named has to be one of the `.tsv` files in
`Tools/CorpusRunner/devsets/`, or `all`**, so pointing the generating half at a
sealed set is not something that happens by accident here. It is an allowlist
read from the directory rather than a list of sealed names, for two reasons: a
name is not what reaches the file (`$SET` is interpolated into a path, and
`../heldout/heldout` resolves to the sealed set while matching none of those
names), and a list of what is forbidden permits the next sealed set anybody
adds. The counts, recomputed on this head rather than carried forward:
abandonment 55, coordination 121, framing 45, rambling 85, routed 116, runon
46, unfinished 163, which is 631.

## Comparing the two paths on a development set

`compare.sh` is the evaluation path: it generates a model reading of one or
more development sets and scores both paths through `heldout/score.py`, the
same instrument, so the numbers are comparable rather than merely adjacent.

```bash
./Tools/InterpretationProbe/compare.sh framing routed
```

Three columns per set, because a generative path has no single number: the
parser, the model alone with a refused capture producing nothing, and the model
with the rules answering the refusals. It prints the refusal tally per rule and
leaves one `runs.jsonl` per set for anybody to `--replay` later.

It prints the instructions fingerprint **twice, from two processes**. That is
not decoration: the first version of the fingerprint was Swift's `hashValue`,
which is seeded randomly per process, and it printed two different values for a
byte-identical prompt — `cd888336` on the CI runner and `329d9c7d` on the Mac
that produced the first real run. It is FNV-1a now, and two matching lines are
that being checked rather than assumed.

**`coordination` is refused by name**, and not because it is sealed. It is
scored by `devsets/score.py` against `probe --clauses` output, a format this
probe does not emit, so the two paths cannot be compared on it. Refusing it is
better than printing an empty report that reads like a bad score.

## The input file

One capture per line. A line with no tab is the whole capture. A line with
exactly one tab is `id<TAB>capture`: the id rides along on every record, and
reports that must not print capture text — `--spread` — name captures by it. A
sealed set is the case this exists for.

**A corpus TSV is not this format and the reader refuses one.** The columns after
the utterance are the expected answers, so a reader that split on the first tab
and kept the remainder would hand the model its own labels as if they were words
the person said, and record that string as the grounding input. The run would
fail eventually, at the scorer, but only after the device time had been paid for.
So a line carrying a second tab stops the tool on that line number.

**The layouts differ, and the utterance is not always column two.** Check the
file before cutting rather than reusing a command:

| file | columns | the cut |
|---|---|---|
| `heldout/heldout.tsv` | `id, utterance, family, expected_destination, expected_thoughts` | `cut -f1,2` |
| `devsets/framing, rambling, routed, runon` | the same five | `cut -f1,2` |
| `devsets/abandonment, unfinished, coordination` | different columns; the utterance is still column two | `cut -f1,2` |
| `everyday/everyday.tsv` | `id, domain, utterance, expect, keep, reject, families, note` | `cut -f1,3` |

The dev sets are split across two rows because they do not share a layout —
`abandonment` and `unfinished` are `id, utterance, family, expectation, note`
and `coordination` is four columns — and naming one layout for all seven would
be the mistake this table exists to prevent, one level up. What holds across
every one of them is the only thing the cut needs: the utterance is column two.

`cut -f1,2 everyday.tsv` yields `id<TAB>domain`, which is two fields, so the
reader **accepts** it and the model is handed 255 domain names as captures. That
is not the labels-in-the-prompt failure the two-field rule closes — a domain name
is not the expected answer — but it is the same bought-and-spent device run, and
it looks identical at the scorer, where every block comes back missing. The rule
catches a file that was not cut; it cannot catch a file that was cut wrong.

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
