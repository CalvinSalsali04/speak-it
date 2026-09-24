#!/bin/bash
# The smallest diagnostic model run: does the grounded semantic map recover
# useful structure on the captures production's router hides from the model,
# without damaging complex captures the rules already get right?
#
#   ./Tools/SemanticMap/diagnostic.sh
#
# Needs an Apple Intelligence Mac (it stops before generating anything if the
# model is unavailable). On `rambling` only, and only on the rows `score.py
# select` picks from the rules reading and the labels:
#
#   hidden              every rules failure production never sends to the model
#   confidentOnComplex  every structurally complex capture the rules flagged nothing on
#   control             one rules-correct complex capture per failure: its C/R
#                       twin where there is one, else the nearest in atoms
#
# Every selected capture gets production's model in shadow (so the `asked` arm
# says what today's refinement would do if the router had sent it) and the
# three semantic-map jobs. Everything after the run is deterministic replay.
#
# DEVELOPMENT EVIDENCE. `rambling` was written and read during this work; the
# figures say whether the design is worth a fresh slice, never how it
# generalises, and no router is chosen from them.
#
# No arguments: the set is named here, so this cannot be pointed at a
# held-out corpus. Output stays under output/ (ignored scratch): the run file
# holds capture text and the model's answers and is local evidence only.
set -euo pipefail
if [ "$#" -ne 0 ]; then
  echo "diagnostic.sh takes no arguments; the set it reads is named inside it" >&2
  exit 2
fi
SP="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SP/../.." && pwd)"
cd "$ROOT"
SET="Tools/CorpusRunner/devsets/rambling.tsv"
OUT="output/semantic-map-diagnostic/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$OUT"

"$SP/build.sh" >/dev/null
BIN="$SP/build/semantic-map"
"$BIN" --selfcheck
"$BIN" --availability | tee "$OUT/availability.txt"
if ! grep -q '^availability: *available$' "$OUT/availability.txt"; then
  echo "diagnostic.sh: the model is not available here; nothing was generated" >&2
  exit 1
fi

grep -v '^#' "$SET" | awk -F'\t' '$1 != "id" && NF >= 5 {print $1 "\t" $2}' > "$OUT/rambling.in"
"$BIN" --census "$OUT/rambling.in" --out "$OUT/census.jsonl"
"$BIN" --rules-report "$OUT/rambling.in" > "$OUT/rules-all.report"
python3 "$SP/score.py" select "$OUT/census.jsonl" --labels "$SET" --report "$OUT/rules-all.report" \
  --out "$OUT/diag.in" --groups "$OUT/groups.json" | tee "$OUT/selection.txt"

echo "diagnostic.sh: generating for $(wc -l < "$OUT/diag.in" | tr -d ' ') captures (shadow on, three jobs)" >&2
"$BIN" --run "$OUT/diag.in" --out "$OUT/runs.jsonl" --shadow

"$BIN" --replay "$OUT/runs.jsonl" --arm rules > "$OUT/rules.report"
"$BIN" --replay "$OUT/runs.jsonl" --arm map --records-out "$OUT/map.jsonl" > "$OUT/map.report"
"$BIN" --replay "$OUT/runs.jsonl" --arm asked --records-out "$OUT/asked.jsonl" > "$OUT/asked.report"

{
  python3 "$SP/score.py" trace "$OUT/runs.jsonl"
  echo
  python3 "$SP/score.py" diagnostic --groups "$OUT/groups.json" --labels "$SET" \
    --rules "$OUT/rules.report" --map "$OUT/map.report" --map-records "$OUT/map.jsonl" \
    --asked "$OUT/asked.report" --asked-records "$OUT/asked.jsonl"
} | tee "$OUT/diagnostic.txt"
echo
echo "diagnostic.sh: everything is in $OUT; paste selection.txt and diagnostic.txt (counts and ids only)"
