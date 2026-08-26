#!/bin/bash
# Scores the held-out set and prints one number.
#
# READ THIS BEFORE RUNNING IT.
#
# These 389 utterances were written **without reading any implementation
# source**, from the product description alone. That is what makes them a
# measure of generalisation rather than of self-consistency: the gating corpus
# is authored from the same contract by the same person who writes the rules, so
# it can only ever say whether the app still agrees with itself.
#
# The rule: **do not read the failures while you are changing rules.** Score at
# release, record the number, move on. The moment a specific held-out sentence
# is used to steer a fix, the set stops being held out and this file is worth
# nothing.
set -euo pipefail
SP="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SP/../../.." && pwd)"
cd "$ROOT"
[ -x Tools/PipelineProbe/build/probe ] || ./Tools/PipelineProbe/build.sh >/dev/null
cut -f2 "$SP/heldout.tsv" | grep -v '^#' > /tmp/heldout_utterances.txt
./Tools/PipelineProbe/build/probe /tmp/heldout_utterances.txt > /tmp/heldout_out.txt 2>&1
python3 "$SP/score.py" "$SP/heldout.tsv" /tmp/heldout_out.txt "$@"
