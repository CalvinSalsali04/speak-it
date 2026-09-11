#!/bin/bash
# Scores the adversarial held-out set: phenomena in combination.
#
# READ THIS BEFORE RUNNING IT.
#
# These captures are held out and nothing in them has been tuned against.
# Each one compounds two phenomena that `heldout/heldout.tsv` already tests
# one at a time, so this set answers a question neither other set asks: do the
# pipeline's layers compose? A failure here on a pair whose ingredients both
# score well alone is evidence about architecture rather than about a missing
# rule, which is the most useful thing an evaluation set can tell you.
#
# `--failures` prints every failure with its input and the pipeline's output.
# That exists for release review. Steering a fix with one of these captures
# ends the set's usefulness the moment it happens — reproduce the pairing in
# Tools/CorpusRunner/devsets/ and work there.
set -euo pipefail
SP="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SP/../../.." && pwd)"
cd "$ROOT"
OUT="${ADVERSARIAL_OUT:-/tmp/speakit-adversarial}"
mkdir -p "$OUT"

[ -x Tools/PipelineProbe/build/probe ] || ./Tools/PipelineProbe/build.sh >/dev/null

grep -v '^#' "$SP/adversarial.tsv" | cut -f3 | tail -n +2 > "$OUT/utterances.txt"
./Tools/PipelineProbe/build/probe "$OUT/utterances.txt" > "$OUT/probe.txt" 2>&1
python3 "$SP/../everyday/score.py" "$SP/adversarial.tsv" "$OUT/probe.txt" "$@"
