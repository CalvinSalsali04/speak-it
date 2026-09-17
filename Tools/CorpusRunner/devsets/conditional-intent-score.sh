#!/bin/bash
set -euo pipefail
SP="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SP/../../.." && pwd)"
OUT="${TMPDIR:-/tmp}/conditional-intent-actual.jsonl"
INPUT="${TMPDIR:-/tmp}/conditional-intent-input.txt"
cd "$ROOT"
[ -x Tools/PipelineProbe/build/probe ] || ./Tools/PipelineProbe/build.sh >/dev/null
python3 -c 'import json,sys; [print(json.loads(line)["utterance"]) for line in open(sys.argv[1])]' \
  "$SP/conditional-intent-10k.jsonl" > "$INPUT"
./Tools/PipelineProbe/build/probe --json "$INPUT" > "$OUT"
python3 "$SP/conditional-intent-score.py" "$SP/conditional-intent-10k.jsonl" "$OUT"
