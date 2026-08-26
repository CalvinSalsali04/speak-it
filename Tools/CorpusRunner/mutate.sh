#!/bin/bash
# Mutation driver for the semantic corpus.
#
# Sabotages one algorithm in a mirror of the sources, rebuilds, replays all 841
# corpus cases, and reports whether anything noticed. If deleting an algorithm
# does not move the numbers, the corpus does not protect that behaviour.
#
#   ./Tools/CorpusRunner/mutate.sh <name> <file> <line> '<injected statement>'
#
# The statement is inserted immediately after <line>, which must be the single
# line carrying the function signature. Example — delete person extraction:
#
#   ./Tools/CorpusRunner/mutate.sh people SpeakIt/Repositories/PersonMention.swift 116 'return []'
#
# Compare against the unmutated baseline from ./Tools/CorpusRunner/build.sh.
set -uo pipefail
SP="$(cd "$(dirname "$0")" && pwd)"
SRC="$(cd "$SP/../.." && pwd)"
WORK="${MUTATE_WORK:-${TMPDIR:-/tmp}/SpeakItMutation}"
MIR="$WORK/mirror"
NAME="$1"; FILE="$2"; LINE="$3"; INJECT="$4"

mkdir -p "$MIR"
rsync -a --delete "$SRC/SpeakIt/" "$MIR/SpeakIt/"
rsync -a --delete "$SRC/SpeakItTests/" "$MIR/SpeakItTests/"

python3 - "$MIR/$FILE" "$LINE" "$INJECT" <<'PY'
import sys
path, line, injected = sys.argv[1], int(sys.argv[2]), sys.argv[3]
lines = open(path).read().split("\n")
lines.insert(line, "        " + injected)
open(path, "w").write("\n".join(lines))
PY

export PROBE_OUT="$WORK/build"
if ! "$SP/build.sh" "$MIR" 2>&1 | grep -q "corpus runner built"; then
  echo "MUTATION [$NAME] BUILD FAILED"; exit 1
fi
RESULT="$("$PROBE_OUT/corpus-run" 2>/dev/null)"
echo "MUTATION [$NAME]"
echo "$RESULT" | grep -E "TOTAL|^CRITICAL|BLOCKING"
echo
echo "Families that noticed:"
echo "$RESULT" | awk '
  NF > 6 {
    ok = 1
    for (i = NF - 5; i <= NF; i++) if ($i !~ /^[0-9]+$/) ok = 0
    if (ok && $(NF-3) + $(NF-2) > 0) print "  " $0
  }' 
