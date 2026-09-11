#!/bin/bash
# Builds the host-side pipeline tools and replays the full semantic corpus.
# Fails when any case regresses to a blocking (critical or behavioural)
# severity. Runs in about a minute with no simulator, so it is the first
# thing the iOS CI job does and the cheapest check to run before a push.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

python3 Tools/CorpusRunner/test_score.py
# The everyday held-out instrument, and the check that nothing in it has
# leaked into a corpus that gets tuned against. Both are plain Python, so
# they cost nothing here and catch a leak on the commit that introduces it
# rather than at the release that trusts the number.
python3 Tools/CorpusRunner/everyday/test_score.py
python3 Tools/CorpusRunner/everyday/measure-gate.py
Tools/PipelineProbe/build.sh
Tools/CorpusRunner/build.sh

output="$(Tools/CorpusRunner/build/corpus-run)"
# As a gate, the verdict is the last eight lines and the family table is
# noise. In a metrics report it is the opposite: the table names which family
# moved, and a summary that cannot say where a failure is makes the reader
# open the run log anyway. CORPUS_GATE_FULL=1 keeps the whole thing.
if [ "${CORPUS_GATE_FULL:-0}" = "1" ]; then
  echo "$output"
else
  echo "$output" | tail -n 8
fi
blocking="$(echo "$output" | grep -o 'BLOCKING(crit+beh) = [0-9]*' | grep -o '[0-9]*$' || true)"
if [ -z "$blocking" ]; then
  echo "corpus gate: could not read the BLOCKING total from corpus-run" >&2
  exit 1
fi
if [ "$blocking" != "0" ]; then
  echo "corpus gate: $blocking blocking failures (baseline is 0). The rows follow." >&2
  # Printing them, rather than naming the command that would print them.
  # Telling the reader to "run corpus-run --verbose" assumes the reader has a
  # Mac; on CI nobody does, the .xcresult and the artifact both live on a blob
  # host a session may not reach, and the job log is the one place every
  # reader can already see. A red gate that reports only a count costs a whole
  # dispatch to turn into four sentences — it cost one on 2026-09-11.
  # `|| true` so that a non-zero exit or a SIGPIPE from `head` cannot cut
  # the script off before the verdict below.
  Tools/CorpusRunner/build/corpus-run --verbose 2>&1 \
    | head -n "${CORPUS_GATE_FAILURE_LINES:-300}" || true
  exit 1
fi
echo "corpus gate ok: 0 blocking failures"
