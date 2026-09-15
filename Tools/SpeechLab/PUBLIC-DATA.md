# Public-data adapter procedures

SpeechLab never downloads these datasets automatically. Download or check out a
version yourself, record its release/hash, review its current license, and pass
the local file to the adapter. Expected local staging paths are examples only
and are ignored by the repository.

```sh
# MASSIVE: extract the en-US JSONL from a local MASSIVE 1.1 copy
python3 Tools/SpeechLab/speechlab.py import-public MASSIVE \
  vendor/speechlab/MASSIVE/en-US.jsonl \
  --output output/speechlab/public/massive-candidates.jsonl

# PRESTO: convert the selected local split to one-JSON-object-per-line first
python3 Tools/SpeechLab/speechlab.py import-public PRESTO \
  vendor/speechlab/PRESTO/review-candidates.jsonl \
  --output output/speechlab/public/presto-candidates.jsonl

# Taskmaster: flatten selected dialogue turns to JSONL with id/text fields
python3 Tools/SpeechLab/speechlab.py import-public Taskmaster \
  vendor/speechlab/Taskmaster/turns.jsonl \
  --output output/speechlab/public/taskmaster-candidates.jsonl

# SLURP text only; do not assume the audio has the same usage terms
python3 Tools/SpeechLab/speechlab.py import-public SLURP-text \
  vendor/speechlab/SLURP/slurp-text.jsonl \
  --output output/speechlab/public/slurp-text-candidates.jsonl
```

Use `--text-field` and `--id-field` for different source schemas. The output is
only a review queue. Every row has `speak_it_blueprint_id: null` and
`review_status: needs_explicit_product_contract`; it cannot enter correctness
evaluation until someone authors and reviews the intended Speak It meaning.

Preserve source URL, release, record ID, license, attribution, modifications,
and whether text/audio were used. Re-check upstream terms before redistribution
or commercial use; registry notes are engineering metadata, not legal advice.
