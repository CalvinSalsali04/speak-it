#!/bin/bash
# Scores the explicit-abandonment development set.
#
#   ./Tools/CorpusRunner/devsets/abandonment-score.sh [--verbose]
set -euo pipefail
SP="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SP/../../.." && pwd)"
cd "$ROOT"
[ -x Tools/PipelineProbe/build/probe ] || ./Tools/PipelineProbe/build.sh >/dev/null
OUT="${TMPDIR:-/tmp}/devset_abandonment"
grep -v '^#' "$SP/abandonment.tsv" | awk -F'\t' '$1!="id" && NF>=4 {print $2}' > "$OUT.in"
./Tools/PipelineProbe/build/probe "$OUT.in" > "$OUT.out" 2>&1
python3 "$SP/abandonment-score.py" "$SP/abandonment.tsv" "$OUT.out" "$@"
