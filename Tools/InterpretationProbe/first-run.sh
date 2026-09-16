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
# are sealed; a run made from one is itself sealed material, and the only sets
# this script can be pointed at are the ones it finds on disk under `devsets/`.
set -euo pipefail

SP="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SP/../.." && pwd)"
cd "$ROOT"

SET="${1:-runon}"
RUNS="${2:-1}"

# An allowlist computed from the directory, not a list of sealed names written
# here. The earlier shape was the list of names and it was wrong in two ways.
# `$SET` is interpolated into a path, so `../heldout/heldout` never met any of
# those names and resolved to the sealed file; and a list of what is forbidden
# permits by default, so the next sealed set anybody adds would be reachable
# with nothing to say so. Naming what is allowed cannot go stale and makes a
# path un-expressible: `../heldout/heldout` is not the name of a file in
# `devsets/`, so it is refused without the refusal having to know about it.
VALID=()
for f in "$ROOT"/Tools/CorpusRunner/devsets/*.tsv; do
  [ -e "$f" ] || continue
  VALID+=("$(basename "$f" .tsv)")
done
if [ ${#VALID[@]} -eq 0 ]; then
  echo "first-run.sh: no development sets under Tools/CorpusRunner/devsets" >&2
  exit 2
fi

SET_OK=0
for name in "${VALID[@]}"; do
  if [ "$SET" = "$name" ]; then SET_OK=1; fi
done
if [ "$SET" = "all" ]; then SET_OK=1; fi
if [ "$SET_OK" -eq 0 ]; then
  echo "first-run.sh: '$SET' is not a development set." >&2
  echo "  A run made from a sealed set holds every capture verbatim and is itself" >&2
  echo "  sealed material, so this script only reads the sets below." >&2
  echo "  Choose one of: ${VALID[*]} all" >&2
  exit 2
fi

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
# No existence check here: the allowlist above was built from these files, so
# by this line `$SET` is either `all` or the basename of one of them. A second
# check would look like the guard without being one.
if [ "$SET" = "all" ]; then
  FILES=("$ROOT"/Tools/CorpusRunner/devsets/*.tsv)
else
  FILES=("$ROOT/Tools/CorpusRunner/devsets/$SET.tsv")
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
