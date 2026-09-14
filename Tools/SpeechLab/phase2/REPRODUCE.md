# Reproduction

Run from the repository root. Temporary public-source downloads are not
committed.

```sh
curl -L --fail https://storage.googleapis.com/gresearch/presto/presto_v1.zip \
  -o /private/tmp/presto_v1.zip
curl -L --fail https://amazon-massive-nlu-dataset.s3.amazonaws.com/amazon-massive-dataset-1.0.tar.gz \
  -o /private/tmp/amazon-massive-dataset-1.0.tar.gz
curl -L --fail \
  https://raw.githubusercontent.com/google-research-datasets/Taskmaster/d92cb6af3005f1dc09c39e75e7daf4a04905e00b/TM-1-2019/sample.json \
  -o /private/tmp/taskmaster-sample.json
curl -L --fail \
  https://raw.githubusercontent.com/pswietojanski/slurp/8eb16545762be97ace75334109d73824217311f1/dataset/slurp/test.jsonl \
  -o /private/tmp/slurp-test.jsonl

python3 Tools/SpeechLab/phase2/select_public_pilot.py \
  --presto /private/tmp/presto_v1.zip \
  --massive /private/tmp/amazon-massive-dataset-1.0.tar.gz \
  --taskmaster /private/tmp/taskmaster-sample.json \
  --slurp /private/tmp/slurp-test.jsonl \
  --output Tools/SpeechLab/phase2/public/source-records.jsonl

PYTHONDONTWRITEBYTECODE=1 python3 Tools/SpeechLab/phase2/build_corpus.py
PYTHONDONTWRITEBYTECODE=1 python3 Tools/SpeechLab/phase2/quality.py
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s Tools/SpeechLab/tests -v
git diff --check
```

Expected source checksums:

```text
1fc671692cceb31fbda17e351e47f2cc52ee8779042f92dc26674cc0cca2167f  presto_v1.zip
7df623fd2d300a4d235d6ee5bd396c9a28258d3a0ccb29abdb054506eba153f8  amazon-massive-dataset-1.0.tar.gz
83fa11504f6e6a8b32fc4f140db82ed624d0e1fdfd0b48f4f40b60c118ac266d  taskmaster-sample.json
fe3449af69b42fda7163345482556066c35a80f7e552a6d67e212a0e2f0783cc  slurp-test.jsonl
```

None of these commands invokes the production parser or reads sealed failures.
