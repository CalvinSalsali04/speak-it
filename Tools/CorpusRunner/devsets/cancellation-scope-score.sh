#!/bin/bash
set -euo pipefail
SP="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SP/../../.." && pwd)"
OUT="${TMPDIR:-/tmp}/cancellation-scope-actual.jsonl"
INPUT="${TMPDIR:-/tmp}/cancellation-scope-input.txt"
cd "$ROOT"
[ -x Tools/PipelineProbe/build/probe ] || ./Tools/PipelineProbe/build.sh >/dev/null
python3 -c 'import json,sys; [print(json.loads(line)["utterance"]) for line in open(sys.argv[1])]' \
  "$SP/cancellation-scope-10k.jsonl" > "$INPUT"
./Tools/PipelineProbe/build/probe --json "$INPUT" > "$OUT"
python3 "$SP/cancellation-scope-score.py" "$SP/cancellation-scope-10k.jsonl" "$OUT"
