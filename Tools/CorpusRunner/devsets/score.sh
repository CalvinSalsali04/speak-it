#!/bin/bash
# Scores a clause-segmentation development set.
#
# Unlike `heldout/`, these sets are for iteration: read the failures, fix the
# rules, run it again. They exist so that the held-out set never has to be
# looked at during development.
#
#   ./Tools/CorpusRunner/devsets/score.sh coordination [--verbose]
set -euo pipefail
SP="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SP/../../.." && pwd)"
cd "$ROOT"
NAME="${1:?usage: score.sh <devset-name> [--verbose]}"
shift || true
# A development set is named, not pathed. Without this, `../heldout/heldout`
# resolves to a real file and this script prints every held-out failure with
# the matching scorer — a complete unseal from a tool whose whole premise is
# that it only reads sets meant to be read.
case "$NAME" in
  *[!A-Za-z0-9_-]* | "" | -*)
    echo "score.sh: '$NAME' is not a development set name; pass a bare name such as coordination" >&2
    exit 2
    ;;
esac
SET="$SP/$NAME.tsv"
[ -f "$SET" ] || { echo "no such dev set: $SET" >&2; exit 2; }
[ -x Tools/PipelineProbe/build/probe ] || ./Tools/PipelineProbe/build.sh >/dev/null
OUT="${TMPDIR:-/tmp}/devset_$NAME"
grep -v '^#' "$SET" | awk -F'\t' 'NR>0 && $1!="id" && NF>=4 {print $2}' > "$OUT.in"
./Tools/PipelineProbe/build/probe --clauses "$OUT.in" > "$OUT.out" 2>&1
python3 "$SP/score.py" "$SET" "$OUT.out" "$@"
