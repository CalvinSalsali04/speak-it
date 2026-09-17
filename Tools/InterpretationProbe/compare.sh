#!/bin/bash
# Generate a model reading of one or more development sets and score both paths
# through the same instrument.
#
#   ./Tools/InterpretationProbe/compare.sh framing routed
#
# The generating half needs a Mac with Apple Intelligence; CI reports
# `deviceNotEligible`, so this cannot run there. The scoring half is
# `--replay`, which needs no model, so the run files this writes can be scored
# again anywhere by anybody.
#
# Three columns per set, because a generative path does not have one number:
#
#   parser              what the deterministic pipeline does today
#   model only          the model's reading, with a refused capture producing
#                       nothing, which is what shadow mode would deliver if it
#                       had no fallback
#   model + fallback    a refused capture answered by the rules instead
#
# Development sets only: the set named has to be one of the `.tsv` files in
# `Tools/CorpusRunner/devsets/`. A run made from a sealed set holds every
# capture verbatim and is itself sealed material.
set -euo pipefail

SP="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SP/../.." && pwd)"
cd "$ROOT"

[ "$#" -gt 0 ] || { echo "usage: compare.sh <dev-set> [<dev-set> ...]" >&2; exit 2; }

DEVSETS="$ROOT/Tools/CorpusRunner/devsets"
VALID=()
for f in "$DEVSETS"/*.tsv; do
  [ -e "$f" ] || continue
  VALID+=("$(basename "$f" .tsv)")
done

# An allowlist read from the directory, not a list of sealed names written here.
# A name is not what reaches the file: `$SET` is interpolated into a path, so a
# denylist would let `../heldout/heldout` through while matching none of it.
for SET in "$@"; do
  ok=0
  for name in "${VALID[@]}"; do
    if [ "$SET" = "$name" ]; then ok=1; fi
  done
  if [ "$ok" -eq 0 ]; then
    echo "compare.sh: '$SET' is not a development set." >&2
    echo "  Choose from: ${VALID[*]}" >&2
    exit 2
  fi
  # coordination is scored by `devsets/score.py` against `probe --clauses`
  # output, a format the interpretation probe does not emit. Refused by name
  # rather than left to produce an empty report that reads like a bad score.
  if [ "$SET" = "coordination" ]; then
    echo "compare.sh: 'coordination' is scored against a clause format this probe" >&2
    echo "  does not emit, so the two paths cannot be compared on it." >&2
    exit 2
  fi
done

OUT="${SPEAKIT_RUN_DIR:-$SP/runs}"
mkdir -p "$OUT"

echo "Building the probe…"
"$SP/build.sh"
echo

# Twice, from two processes. The fingerprint identifies which prompt produced a
# run, and the first version of it was Swift's `hashValue`, which is seeded
# randomly per process: it printed two different values for a byte-identical
# prompt. Two matching lines here is that fix being checked rather than trusted.
"$SP/build/interpret" --availability | tee "$OUT/availability.txt"
echo "second process, same prompt:"
"$SP/build/interpret" --availability | grep '^instructions:'
echo

if ! grep -q '^availability: *available$' "$OUT/availability.txt"; then
  echo "The model is not available on this machine, so there is nothing to generate." >&2
  echo "The line above says which reason the framework gave; send it back as it is." >&2
  exit 1
fi

for SET in "$@"; do
  INPUT="$OUT/$SET.captures.tsv"
  RUNS="$OUT/$SET.jsonl"
  # Every routing development set is `id, utterance, …`. The header is dropped
  # by matching `id` in column one rather than by position, because it is not
  # always the first line.
  grep -v '^#' "$DEVSETS/$SET.tsv" \
    | awk -F'\t' '$1 != "id" && NF>=2 {print $1 "\t" $2}' > "$INPUT"
  COUNT=$(wc -l < "$INPUT" | tr -d ' ')
  echo "Interpreting $COUNT captures from '$SET'. Nothing leaves this machine."
  START=$(date +%s)
  "$SP/build/interpret" --interpret "$INPUT" --out "$RUNS" --runs 1
  echo "  $SET: ${COUNT} captures in $(( $(date +%s) - START ))s"
  echo
done

for SET in "$@"; do
  RUNS="$OUT/$SET.jsonl"
  echo "################ $SET ################"
  echo "=== PARSER ==="
  "$ROOT/Tools/CorpusRunner/devsets/route-score.sh" "$SET" || true
  echo "=== MODEL ONLY ==="
  "$SP/build/interpret" --replay "$RUNS" > "$OUT/$SET.model.out"
  python3 "$ROOT/Tools/CorpusRunner/heldout/score.py" \
    "$DEVSETS/$SET.tsv" "$OUT/$SET.model.out" || true
  echo "=== MODEL PLUS RULES FALLBACK ==="
  "$SP/build/interpret" --replay "$RUNS" --fallback > "$OUT/$SET.fallback.out"
  python3 "$ROOT/Tools/CorpusRunner/heldout/score.py" \
    "$DEVSETS/$SET.tsv" "$OUT/$SET.fallback.out" || true
  echo "=== REFUSALS ==="
  grep -h 'rejected' "$OUT/$SET.model.out" | sort | uniq -c || echo "  none"
  echo
done

echo "Run files, one per set — send these back:"
for SET in "$@"; do echo "  $OUT/$SET.jsonl"; done
echo "They hold development-set captures only, so they are safe to share."
