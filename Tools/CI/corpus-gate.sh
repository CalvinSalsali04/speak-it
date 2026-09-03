#!/bin/bash
# Builds the host-side pipeline tools and replays the full semantic corpus.
# Fails when any case regresses to a blocking (critical or behavioural)
# severity. Runs in about a minute with no simulator, so it is the first
# thing the iOS CI job does and the cheapest check to run before a push.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

Tools/PipelineProbe/build.sh
Tools/CorpusRunner/build.sh

output="$(Tools/CorpusRunner/build/corpus-run)"
echo "$output" | tail -n 8
blocking="$(echo "$output" | grep -o 'BLOCKING(crit+beh) = [0-9]*' | grep -o '[0-9]*$' || true)"
if [ -z "$blocking" ]; then
  echo "corpus gate: could not read the BLOCKING total from corpus-run" >&2
  exit 1
fi
if [ "$blocking" != "0" ]; then
  echo "corpus gate: $blocking blocking failures (baseline is 0). Run Tools/CorpusRunner/build/corpus-run --verbose to see them." >&2
  exit 1
fi
echo "corpus gate ok: 0 blocking failures"
