#!/bin/bash
# Every development-set failure, with the input and what the pipeline did.
#
# WHY THIS EXISTS
#
# The development sets are for iteration — read the failures, fix the layer,
# run it again — and until now the only way to read one was on a Mac. A session
# without a Mac could see that `run-on` scored 0 of 8 and could not see a single
# failing case, so it was reduced to guessing at the shape of the defect. That
# is the loop this reopens.
#
# WHAT IT WILL NOT DO
#
# It never touches a held-out corpus. The five scorers below are named
# explicitly rather than discovered, so a new directory under
# Tools/CorpusRunner cannot be picked up here by accident — including one that
# is held out. `Tools/CorpusRunner/heldout/` and `Tools/CorpusRunner/everyday/`
# are the two that exist today, and neither is reachable from this file.
#
# Tools/CI/language-metrics.sh is the opposite instrument: it scores everything
# and prints no failure text at all. Keep it that way. If you want a held-out
# failure at release, run its scorer directly and knowingly:
#
#   ./Tools/CorpusRunner/heldout/score.sh --verbose
#
#   ./Tools/CI/devset-failures.sh
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT" || exit 1
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

# No arguments, ever. A path here would be the one way to aim this at a corpus
# it must not read.
if [ $# -gt 0 ]; then
  echo "devset-failures: takes no arguments; it runs the development sets and only those" >&2
  exit 2
fi

[ -x Tools/PipelineProbe/build/probe ] || ./Tools/PipelineProbe/build.sh >/dev/null || exit 1

section() {
  echo
  echo "=================================================================="
  echo "$1"
  echo "=================================================================="
}

section "COORDINATION — where clause boundaries fall"
Tools/CorpusRunner/devsets/score.sh coordination --verbose 2>&1

section "ROUTED — destination, and action on a capture nobody can pin down"
Tools/CorpusRunner/devsets/route-score.sh routed --verbose 2>&1

section "FRAMING — the frame around speech: sign-offs, enumeration"
Tools/CorpusRunner/devsets/route-score.sh framing --verbose 2>&1

section "UNFINISHED — whether a thought was finished at all"
Tools/CorpusRunner/devsets/unfinished-score.sh --verbose 2>&1

section "ABANDONMENT — whether the speaker took the thought back"
Tools/CorpusRunner/devsets/abandonment-score.sh --verbose 2>&1

echo
echo "=================================================================="
echo "HOW TO READ THIS"
echo "=================================================================="
echo "  These sets are developed against on purpose, so a failure here is"
echo "  something to fix rather than something to protect. Fixing one case"
echo "  is not the point: find the family it belongs to, fix the layer, and"
echo "  check the held-out numbers afterwards with language-metrics.sh."
