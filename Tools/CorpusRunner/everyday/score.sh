#!/bin/bash
# Scores the everyday-speech held-out set and prints failure rates by domain
# and by language family.
#
# READ THIS BEFORE RUNNING IT.
#
# These captures are held out. They were written from the product description
# and from how people dictate, not from the parser, and nothing in them has
# been tuned against. Score the set, record the numbers, move on.
#
# `--failures` prints every failure with its input and the pipeline's actual
# output. That exists for release review. Using one of these captures to steer
# a fix ends the set's usefulness the moment it happens — reproduce the family
# in Tools/CorpusRunner/devsets/ and work there.
set -euo pipefail
SP="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SP/../../.." && pwd)"
cd "$ROOT"
OUT="${EVERYDAY_OUT:-/tmp/speakit-everyday}"
mkdir -p "$OUT"

[ -x Tools/PipelineProbe/build/probe ] || ./Tools/PipelineProbe/build.sh >/dev/null

cut -f3 "$SP/everyday.tsv" | tail -n +2 > "$OUT/utterances.txt"
./Tools/PipelineProbe/build/probe "$OUT/utterances.txt" > "$OUT/probe.txt" 2>&1
python3 "$SP/score.py" "$SP/everyday.tsv" "$OUT/probe.txt" "$@"
