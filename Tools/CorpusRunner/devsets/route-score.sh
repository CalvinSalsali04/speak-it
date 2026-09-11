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
# A development set is named, not pathed. Without this, `../heldout/heldout`
# resolves to a real file and this script prints every held-out failure with
# the matching scorer — a complete unseal from a tool whose whole premise is
# that it only reads sets meant to be read.
case "$NAME" in
  *[!A-Za-z0-9_-]* | "" | -*)
    echo "route-score.sh: '$NAME' is not a development set name; pass a bare name such as routed" >&2
    exit 2
    ;;
esac
SET="$SP/$NAME.tsv"
[ -f "$SET" ] || { echo "no such dev set: $SET" >&2; exit 2; }
[ -x Tools/PipelineProbe/build/probe ] || ./Tools/PipelineProbe/build.sh >/dev/null
OUT="${TMPDIR:-/tmp}/devroute_$NAME"
grep -v '^#' "$SET" | awk -F'\t' '$1!="id" && NF>=5 {print $2}' > "$OUT.in"
./Tools/PipelineProbe/build/probe "$OUT.in" > "$OUT.out" 2>&1
python3 "$SP/../heldout/score.py" "$SET" "$OUT.out" "$@"
