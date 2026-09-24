#!/bin/bash
# PHASE 1 and 3 on the development sets, with no model: how production routes
# each capture, and which rules failures it never asks the model about.
#
#   ./Tools/SemanticMap/census-devsets.sh
#
# Deterministic, so it runs on any Mac with Xcode, including the hosted runner
# behind a `language_only` dispatch. It prints counts and reasons only.
#
# DEVELOPMENT EVIDENCE ONLY. These four sets were read and tuned against for
# months (`Docs/LANGUAGE_BASELINE.md`); a figure from them describes where the
# current parser stands, never how it generalises. A router signal chosen on
# these rows must be re-measured on the fresh slice before it routes anything.
#
# No arguments, ever: the sets are named below rather than discovered, so this
# cannot be aimed at a held-out corpus by a path, and neither `heldout/` nor
# `everyday/` is reachable from this file.
set -euo pipefail
if [ "$#" -ne 0 ]; then
  echo "census-devsets.sh takes no arguments; the sets it reads are named inside it" >&2
  exit 2
fi
SP="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SP/../.." && pwd)"
cd "$ROOT"
[ -x "$SP/build/semantic-map" ] || "$SP/build.sh" >/dev/null
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

for NAME in routed runon framing rambling; do
  SET="Tools/CorpusRunner/devsets/$NAME.tsv"
  grep -v '^#' "$SET" | awk -F'\t' '$1 != "id" && NF >= 5 {print $1 "\t" $2}' > "$WORK/$NAME.in"
  "$SP/build/semantic-map" --census "$WORK/$NAME.in" --out "$WORK/$NAME.census.jsonl"
  "$SP/build/semantic-map" --rules-report "$WORK/$NAME.in" > "$WORK/$NAME.report"
  echo
  echo "################ $NAME ################"
  python3 "$SP/score.py" census "$WORK/$NAME.census.jsonl" --labels "$SET"
  echo
  python3 "$SP/score.py" router "$WORK/$NAME.census.jsonl" --labels "$SET" --report "$WORK/$NAME.report"
done
