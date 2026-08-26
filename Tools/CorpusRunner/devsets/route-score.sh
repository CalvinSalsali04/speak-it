#!/bin/bash
# Scores a routing development set with the held-out scorer.
#
# Same instrument, different data: this set is for iteration, `heldout/` is not.
#
#   ./Tools/CorpusRunner/devsets/route-score.sh routed [--verbose]
set -euo pipefail
SP="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SP/../../.." && pwd)"
cd "$ROOT"
NAME="${1:?usage: route-score.sh <devset-name> [--verbose]}"
shift || true
SET="$SP/$NAME.tsv"
[ -f "$SET" ] || { echo "no such dev set: $SET" >&2; exit 2; }
[ -x Tools/PipelineProbe/build/probe ] || ./Tools/PipelineProbe/build.sh >/dev/null
OUT="${TMPDIR:-/tmp}/devroute_$NAME"
grep -v '^#' "$SET" | awk -F'\t' '$1!="id" && NF>=5 {print $2}' > "$OUT.in"
./Tools/PipelineProbe/build/probe "$OUT.in" > "$OUT.out" 2>&1
python3 "$SP/../heldout/score.py" "$SET" "$OUT.out" "$@"
