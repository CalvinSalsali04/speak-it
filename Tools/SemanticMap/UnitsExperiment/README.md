# The semantic-unit experiment

One question: which grounded representation lets the on-device model recover
complete semantic intentions most reliably without authoring user meaning?
Development evidence on 30 existing captures, not launch accuracy. Nothing
here is production and no arbiter reads it.

- **Candidate 1 (`ranges`)**: the model returns each thought as its first and
  last atom id. The app reconstructs the text as the original slice.
- **Candidate 2 (`labels`)**: the model labels deterministic clause lines
  (`clause_lines.py`, frozen in c97c131 before the gold existed, reading no
  parser output) as `starts` or `continues`.

Both prompts share one paragraph about what a thought is, word for word
(`Sources/UnitsExperiment.swift`). Neither arm has a string field.

## Files

| File | What it is |
| --- | --- |
| `gold/` | The frozen gold, copied byte for byte from the independent author. `gold/README.md` explains it. |
| `captures.jsonl` | The 30 transcripts the gold author saw. |
| `inputs.jsonl` | Atoms and clause lines per capture, from `make_inputs.py`. |
| `families.json` | Per-capture families for the per-family table. |
| `score_units.py` | `precheck` (no model), `score`, `selftest`. |
| `MANIFEST` | sha256 of everything above plus the prompts' Swift file. |
| `run.sh` | The one command: checks the manifest, prechecks, builds, generates once per arm per capture, scores. |

## Running

On an Apple Intelligence Mac, from a clean checkout:

```bash
./Tools/SemanticMap/UnitsExperiment/run.sh
```

It writes one evidence directory under `output/` (`steps.txt`,
`precheck.txt`, `availability.txt`, `results.jsonl`, `score.txt`). It refuses
to generate if any pinned file changed. Everything except generation runs
anywhere:

```bash
python3 Tools/SemanticMap/UnitsExperiment/score_units.py selftest
python3 Tools/SemanticMap/UnitsExperiment/score_units.py precheck \
  --gold Tools/SemanticMap/UnitsExperiment/gold/gold.json \
  --inputs Tools/SemanticMap/UnitsExperiment/inputs.jsonl
python3 Tools/SemanticMap/UnitsExperiment/score_units.py score \
  --gold Tools/SemanticMap/UnitsExperiment/gold/gold.json \
  --inputs Tools/SemanticMap/UnitsExperiment/inputs.jsonl \
  --families Tools/SemanticMap/UnitsExperiment/families.json [--reference DIAG_FOLDER]
```

A prompt, schema or scorer defect found after generation means fixing both
arms, updating `MANIFEST` in its own commit, and rerunning both. Never one.
