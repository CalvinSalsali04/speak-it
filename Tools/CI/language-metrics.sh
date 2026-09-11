#!/bin/bash
# Every language number this project quotes, from one command.
#
# The engine depends on Apple's NaturalLanguage framework, so it runs on macOS
# and nowhere else. Before this script existed, the corpus gate was the only
# language check CI ran, and the development and held-out numbers came only
# from a hand-run on a Mac — which meant any session without a Mac was editing
# the parser against numbers it could not produce.
#
#   ./Tools/CI/language-metrics.sh            # report to stdout
#   ./Tools/CI/language-metrics.sh --report out.txt
#
# No simulator and no release build: the corpus gate takes about ninety
# seconds and the scorers run off the same host build, so this costs a small
# fraction of the unit-suite job.
#
# Exit status is the corpus gate's. The scorers report; they do not gate,
# because destination accuracy can move either way for defensible reasons and
# a number that blocks a merge is a number people learn to game.
#
# ON THE HELD-OUT SET
#
# It is scored here NON-VERBOSE, always. Tools/CorpusRunner/heldout/README.md
# is the rule: score it, record the number, do not read the failures while you
# are changing rules. This script refuses --verbose and --failures rather than
# forwarding them, so running the metrics can never be the thing that unseals
# the set. A scorer added later must default to non-verbose for the same
# reason: see Tools/CI/README.md.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT" || exit 1
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

REPORT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --report)
      if [ $# -lt 2 ]; then
        echo "language-metrics: --report needs a path" >&2
        exit 2
      fi
      # A flag where the path should be is a typo, and swallowing it would
      # let "--report --verbose" past the refusal below on a technicality.
      case "$2" in
        --*)
          echo "language-metrics: --report needs a path, got $2" >&2
          exit 2
          ;;
      esac
      REPORT="$2"
      shift 2
      ;;
    --verbose | --failures)
      cat >&2 <<'REFUSAL'
language-metrics: --verbose and --failures are refused on purpose.

This script scores the held-out set, and reading its failures while the rules
are being changed is what destroys it as a measure of generalisation. See
Tools/CorpusRunner/heldout/README.md.

Both flags reach failure text: the scorers under Tools/CorpusRunner accept
--verbose, and some accept --failures as well. This script forwards neither.

To review held-out failures at release, run a scorer directly and knowingly:
  ./Tools/CorpusRunner/heldout/score.sh --verbose
REFUSAL
      exit 2
      ;;
    *)
      echo "language-metrics: unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

OUT="$(mktemp)"
trap 'rm -f "$OUT"' EXIT

section() {
  {
    echo
    echo "=================================================================="
    echo "$1"
    echo "=================================================================="
  } >> "$OUT"
}

# The gate first: it builds PipelineProbe and the corpus runner, which every
# scorer below then reuses. Its status is captured rather than fatal so that a
# regression still produces the rest of the picture in the same run.
section "GATING CORPUS — regression net, authored from the product contract"
# The gate prints its last eight lines, which is right for a pass/fail check
# and wrong here: the first real run showed four family rows and nothing else,
# so a future failure would be invisible in the family it belongs to.
CORPUS_GATE_FULL=1 Tools/CI/corpus-gate.sh >> "$OUT" 2>&1
GATE=$?

section "DEVELOPMENT SETS — where rules are worked out; not a gate, not held out"
{
  Tools/CorpusRunner/devsets/score.sh coordination
  Tools/CorpusRunner/devsets/route-score.sh routed
  Tools/CorpusRunner/devsets/route-score.sh framing
  Tools/CorpusRunner/devsets/route-score.sh runon
  Tools/CorpusRunner/devsets/route-score.sh rambling
  Tools/CorpusRunner/devsets/unfinished-score.sh
  Tools/CorpusRunner/devsets/abandonment-score.sh
} >> "$OUT" 2>&1

# Anything the evaluation work adds later is measured without editing this
# script: a corpus directory under Tools/CorpusRunner that exposes an
# executable, argument-free score.sh is picked up here. devsets/ takes a set
# name and heldout/ is scored last on purpose, so both are handled explicitly
# above and below rather than discovered.
section "ADDITIONAL CORPORA — discovered by convention"
FOUND=0
for dir in Tools/CorpusRunner/*/; do
  case "$(basename "$dir")" in
    devsets | heldout | build) continue ;;
  esac
  [ -x "${dir}score.sh" ] || continue
  FOUND=1
  {
    echo
    echo "--- $(basename "$dir") ---"
    "${dir}score.sh"
  } >> "$OUT" 2>&1
done
if [ "$FOUND" -eq 0 ]; then
  echo "  none yet" >> "$OUT"
fi

section "HELD-OUT SET — kept out of development; scored non-verbose. Read Tools/CorpusRunner/heldout/README.md on what its provenance does and does not support before quoting this as generalisation"
Tools/CorpusRunner/heldout/score.sh >> "$OUT" 2>&1

{
  echo
  echo "=================================================================="
  echo "HOW TO READ THIS"
  echo "=================================================================="
  echo "  The gating corpus is authored from the same contract by the same"
  echo "  hand that writes the rules, so it measures self-consistency and is"
  echo "  already near ceiling. The held-out set is the generalisation"
  echo "  measure. A change that moves the first and not the second has not"
  echo "  been shown to help real speakers."
  echo
  echo "  On the held-out block, the line to watch is ACTED ON ANYWAY: a"
  echo "  confident action on a capture no careful reader could pin down."
  echo "  Destination can move either way for defensible reasons. That one"
  echo "  should only ever fall."
} >> "$OUT"

cat "$OUT"

if [ -n "$REPORT" ]; then
  cp "$OUT" "$REPORT"
fi

if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  {
    echo "## Language metrics"
    echo
    echo '```'
    cat "$OUT"
    echo '```'
  } >> "$GITHUB_STEP_SUMMARY"
fi

if [ "$GATE" -ne 0 ]; then
  echo "language-metrics: the corpus gate failed; the scores above still stand" >&2
  exit "$GATE"
fi
