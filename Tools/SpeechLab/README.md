# SpeechLab

SpeechLab is the provenance-first evaluation system for Speak It's production
understanding pipeline. It creates intended semantics before wording, validates
every boundary, and retains every evaluated case in indexed SQLite. It does not
change parser behavior, use source-dataset labels as product truth, call a
network model, or claim that consistency is accuracy.

## What is here

- `schema/`: versioned JSON Schema contracts for blueprints, renderings,
  evaluation rows, and failure signatures.
- `config/phenomena.json`: 64 defined speech phenomena, each with examples,
  counterexamples, preservation policy, affected metrics, safety level, and
  blind-mutation suitability.
- `config/semantic-dimensions.json`: semantic axes and invalid combinations.
- `data/family-definitions.jsonl`: 260 authored semantic family recipes.
- `data/blueprints.jsonl`: 260 hash-identified intended meanings.
- `data/renderings.jsonl`: 260 fluent bases plus 64 dedicated phenomenon
  variants (324 deterministic initial renderings total).
- `Sources/`: contracts, catalog, evaluation, coverage, clustering, exchange,
  and public-data adapters.
- `artifacts/coverage/`: coverage report and 64-case greedy set-cover diagnostic.
- `artifacts/export-for-ai/`: compact handoff package for an external ChatGPT.
- `tests/`: offline unit/integration tests.

The production interface is `Tools/PipelineProbe/build/probe --json`. It
compiles the real repository sources and emits items and operations. SpeechLab
stores exact expected and actual JSON plus hashes and metric-level decisions.

## Quick start

```sh
./Tools/PipelineProbe/build.sh
python3 Tools/SpeechLab/speechlab.py validate
python3 Tools/SpeechLab/speechlab.py coverage
python3 Tools/SpeechLab/speechlab.py evaluate \
  --preset diagnostic --database output/speechlab/diagnostic.sqlite
python3 Tools/SpeechLab/speechlab.py integrity \
  --database output/speechlab/diagnostic.sqlite
python3 -m unittest discover -s Tools/SpeechLab/tests -v
```

The run ID hashes the config, selected dataset, and probe binary. Rerunning the
same command resumes idempotently. `--worker-count N --worker-index I` creates
stable, non-overlapping SHA-256 partitions. SQLite primary keys prevent a case
from executing twice inside one run. Each committed batch is complete before
progress advances.

## Focused, broad, and stress runs

```sh
# One or more phenomena
python3 Tools/SpeechLab/speechlab.py evaluate --preset focused \
  --phenomenon self-correction-time --phenomenon recurrence \
  --database output/speechlab/focused.sqlite

# Current broad set (the default ceiling is 10,000)
python3 Tools/SpeechLab/speechlab.py evaluate --preset broad \
  --database output/speechlab/broad.sqlite

# Explicit large-N run; expand data first, then partition workers
python3 Tools/SpeechLab/speechlab.py evaluate --preset stress --limit 100000 \
  --worker-count 8 --worker-index 0 \
  --database output/speechlab/stress-worker-0.sqlite
```

Use one database per worker. Partition overlap is impossible for a fixed
dataset/config because assignment is `sha256(rendering_id) % worker_count`.
Merge tooling should reject duplicate `(run_id, rendering_id)` keys rather than
silently replace them.

## External ChatGPT generation

Create the compact generation handoff:

```sh
python3 Tools/SpeechLab/speechlab.py export-ai \
  --output Tools/SpeechLab/artifacts/export-for-ai --batch-size 50
```

Give ChatGPT these files:

- `artifacts/export-for-ai/blueprint-batch.jsonl`
- `artifacts/export-for-ai/generation-request.json`
- `artifacts/export-for-ai/uncovered-dimensions.json`
- `artifacts/export-for-ai/coverage-summary.json`
- `artifacts/export-for-ai/failure-pack.jsonl` after failures exist

Import returned JSONL without trusting it blindly:

```sh
python3 Tools/SpeechLab/speechlab.py import-renderings returned.jsonl \
  --output output/speechlab/renderings-reviewed-next.jsonl
```

The importer validates blueprint ownership, ID/lineage, phenomena, duplicates,
near duplicates, lengths, and required anchors. External renderings default to
`meaning_preservation: uncertain`; human review must promote them.

After a run, export a compact clustered failure pack:

```sh
python3 Tools/SpeechLab/speechlab.py failure-pack \
  --database output/speechlab/diagnostic.sqlite --run-id RUN_ID \
  --output Tools/SpeechLab/artifacts/export-for-ai/failure-pack.jsonl
```

Literal signatures preserve the exact delta. Directional signatures replace
names, locations, facts, and numeric values while preserving field, direction,
position/count, route/type, time, polarity, and compound failure information.

## Public corpora

No dataset is downloaded automatically. Inspect the registry:

```sh
python3 Tools/SpeechLab/speechlab.py adapter-registry \
  --output Tools/SpeechLab/config/public-corpora.json
```

Then import a local JSONL copy, for example:

```sh
python3 Tools/SpeechLab/speechlab.py import-public MASSIVE path/to/en-US.jsonl \
  --output output/speechlab/massive-candidates.jsonl
```

PRESTO, MASSIVE, Taskmaster, and SLURP-text are registered. Imported rows are
review candidates with `speak_it_blueprint_id: null`; source intent labels are
retained only as provenance and never become Speak It ground truth.

## Retention proof

`results.payload_json` contains input text, exact expected structure, exact
actual probe output, semantic hashes, every metric, difference data, timing,
probe hash, and environment metadata. `payload_hash` detects corruption.
`speechlab.py integrity` verifies SQLite, hashes, schemas, IDs, and uniqueness.
The run refuses to complete unless retained row count equals selected case
count. This is the invariant the previous 2M campaign lacked.

## Known initial-data gaps

The first set proves infrastructure and structural breadth; it is not a user
accuracy benchmark. It contains no permissioned production speech, human audio,
reviewed public-corpus blueprint mappings, or external-AI renderings yet. Some
deterministic variants are intentionally marked uncertain. Store-dependent
cancellation is represented in capture context and expected operations, but the
current probe cannot execute against SwiftData. Foundation Models and audio/ASR
are also outside the rules-only probe. These gaps are visible, not scored away.

See [SCALE.md](SCALE.md) and [SEALED-HOLDOUT.md](SEALED-HOLDOUT.md).
