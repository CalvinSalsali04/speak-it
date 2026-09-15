# SpeechLab data-quality audit

This directory audits the measurement system, not the production parser. It
contains no sealed cases and does not use parser output as ground truth.

Reproduce the candidate cohort and validation:

```sh
python3 Tools/SpeechLab/audit/generate_candidates.py
python3 Tools/SpeechLab/speechlab.py import-renderings \
  Tools/SpeechLab/audit/ai-candidates.jsonl \
  --output Tools/SpeechLab/audit/combined-renderings.jsonl
```

The generated cohort is deliberately small: 50 exported blueprints with three
different spoken realizations each. All candidates remain semantically
`uncertain` until human review.

Run the retained evaluation and reproduce audit/review artifacts:

```sh
python3 Tools/SpeechLab/speechlab.py evaluate \
  --renderings Tools/SpeechLab/audit/combined-renderings.jsonl \
  --preset stress --database output/speechlab/data-quality-audit.sqlite
python3 Tools/SpeechLab/audit/audit_data_quality.py \
  --database output/speechlab/data-quality-audit.sqlite --run-id RUN_ID
```

Start with `DATA-QUALITY-AUDIT.md`, then use `human-review-set.csv` for the
bounded 400-row review. The JSONL version preserves structured expected and
actual behavior.
