# SpeechLab Stress Bank evaluator

This local evaluator validates the immutable `SpeechLab Stress Bank v1` archive,
runs every utterance through the repository's real host-side production rules
path, and writes reproducible failure-discovery evidence under ignored `output/`.
It does not call a model, regenerate data, or modify parser behavior.

```bash
python3 Tools/SpeechLabStressBank/run.py \
  --bank /path/to/speakit_speechlab_10k_bank_v1.zip \
  --output output/speechlab-stress-bank-v1 \
  --build-probe
```

Use `--validate-only` to verify the archive without executing the parser. The
full run emits:

- `validation.json`: row, schema, hash, count, sample, safety, and ambiguity checks
- `run-metadata.json`: bank, Git, source-tree, evaluator, binary, clock, and environment identity
- `probe`: the frozen binary actually executed
- `actual.jsonl`: raw production output
- `results.jsonl`: expected/actual/normalized output and multi-label mismatch dimensions per case
- `clusters.json`: ranked automatic disagreement clusters with examples
- `summary.json`: aggregate, family, phenomenon, structure, ambiguity, and safety totals
- `result-manifest.json`: hashes and byte sizes for reproducibility

The evaluator's `exact_structured_agreement` is a deterministic projection from
the bank's abstract `action`/`object`/`destination` contract onto Speak It's
native title, analysis, route, person, temporal, recurrence, state, and operation
fields. It is intentionally stricter than output-count equality. The source
quote is retained as evidence but does not by itself prove that the parser
understood a field. Rows marked `requires_review` are excluded from the naive
exact-agreement denominator and receive ambiguity-specific outcomes.

Never present the resulting rate as product accuracy. This is synthetic stress
data for failure discovery and regression comparison; Trusted Core remains the
semantic anchor.

After changing evaluator-only comparison logic, reuse the frozen raw production
output without spending another parser run:

```bash
python3 Tools/SpeechLabStressBank/run.py \
  --bank /path/to/speakit_speechlab_10k_bank_v1.zip \
  --output output/speechlab-stress-bank-v1 \
  --probe output/speechlab-stress-bank-v1/probe \
  --reuse-actual output/speechlab-stress-bank-v1/actual.jsonl
```
