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
# Data rows are selected by their id, not by dropping comment lines afterwards.
# `cut -f2 | grep -v '^#'` cuts EVERY line first, so a commented header yields
# its second cell -- the bare word "utterance" -- which does not start with a
# `#` and survives the filter. That fed the probe 390 inputs for a 389-capture
# set. Harmless to the score, since results are keyed by text rather than by
# position, but it is a stray capture in every run and it would stop being
# harmless the moment that word appeared in a real one.
grep -E '^C[0-9]+	' "$SP/heldout.tsv" | cut -f2 > /tmp/heldout_utterances.txt
./Tools/PipelineProbe/build/probe /tmp/heldout_utterances.txt > /tmp/heldout_out.txt 2>&1
python3 "$SP/score.py" "$SP/heldout.tsv" /tmp/heldout_out.txt "$@"
