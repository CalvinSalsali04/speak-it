#!/bin/bash
# The first real interpretation run, on a Mac that has Apple Intelligence.
#
# CI cannot do this: the hosted runner reports `deviceNotEligible`, so every
# number comparing the model path against the parser has to be generated on
# somebody's eligible device and replayed elsewhere. This is the generating
# half. `--replay` is the scoring half and runs anywhere.
#
#   ./Tools/InterpretationProbe/first-run.sh              # runon, 1 run
#   ./Tools/InterpretationProbe/first-run.sh runon 3      # three runs, for spread
#   ./Tools/InterpretationProbe/first-run.sh all 1        # every development set
#
# Development sets only, on purpose. The held-out, everyday and adversarial sets
# are sealed; a run made from one is itself sealed material, and this script
# refuses to point at them so that choice is never made by accident here.
set -euo pipefail

SP="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SP/../.." && pwd)"
cd "$ROOT"

SET="${1:-runon}"
RUNS="${2:-1}"

case "$SET" in
  heldout|everyday|adversarial|consequence)
    # Named from the glob rather than from a list written here, so a development
    # set added later is offered without anybody remembering to edit this line.
    names=""
    for f in "$ROOT"/Tools/CorpusRunner/devsets/*.tsv; do
      [ -e "$f" ] || continue
      names="${names:+$names }$(basename "$f" .tsv)"
    done
    echo "first-run.sh: '$SET' is a sealed set." >&2
    echo "  A run made from one holds every capture verbatim and is sealed material." >&2
    echo "  Development sets only from here: $names" >&2
    exit 2
    ;;
esac

INPUT="$SP/captures.tsv"
OUTPUT="$SP/runs.jsonl"

# Every development set is `id, utterance, …` with the utterance in column two,
# checked per file rather than assumed — see the table in README.md. The cut
# leaves exactly `id<TAB>capture`, which is what the probe's reader accepts; a
# third field makes it refuse, which is the point.
#
# The header row is dropped by matching `id` in column one rather than by
# skipping the first line, because it is not always the first line: in
# `abandonment.tsv` a blank line comes before it. Counted rather than assumed —
# 88 lines, 57 non-comment, one blank, one header, 55 captures. A positional
# skip would take the header on six files and a capture on the seventh, with
# nothing to notice it by.
: > "$INPUT"
if [ "$SET" = "all" ]; then
  FILES=("$ROOT"/Tools/CorpusRunner/devsets/*.tsv)
else
  FILES=("$ROOT/Tools/CorpusRunner/devsets/$SET.tsv")
  if [ ! -f "${FILES[0]}" ]; then
    echo "first-run.sh: no development set named '$SET'" >&2
    exit 2
  fi
fi
for file in "${FILES[@]}"; do
  grep -v '^#' "$file" | awk -F'\t' '$1 != "id" && NF>=2 {print $1 "\t" $2}' >> "$INPUT"
done
COUNT=$(wc -l < "$INPUT" | tr -d ' ')

echo "Building the probe…"
"$SP/build.sh"

echo
"$SP/build/interpret" --availability | tee "$SP/availability.txt"
echo

if ! grep -q '^availability: *available$' "$SP/availability.txt"; then
  echo "The model is not available on this machine, so there is nothing to generate." >&2
  echo "The line above says which reason the framework gave. Send it back as it is;" >&2
  echo "it is a fact about this machine and worth recording either way." >&2
  exit 1
fi

echo "Interpreting $COUNT captures from '$SET', $RUNS run(s) each."
echo "Nothing leaves this machine: the model is on-device and the probe has no network."
echo
START=$(date +%s)
"$SP/build/interpret" --interpret "$INPUT" --out "$OUTPUT" --runs "$RUNS"
ELAPSED=$(( $(date +%s) - START ))

echo
echo "Done in ${ELAPSED}s for $COUNT captures x $RUNS run(s)."
echo "Send back this one file:"
echo "  $OUTPUT"
echo
echo "It holds development-set captures only, so it is safe to share."
