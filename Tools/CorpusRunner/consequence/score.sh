#!/bin/bash
# Scores the consequence set. Sealed: score it, record the rate, move on.
#
# READ THIS BEFORE RUNNING IT.
#
# These 40 captures were written to a phenomenon -- a person states a fact,
# then the errand that fact creates -- with the generation parameters fixed and
# committed BEFORE any capture existed, and with the author unable to see what
# the parser does with any of them, because the engine does not build in the
# container they were written in. That ordering is the entire value of the set.
# Read README.md for what the blindness claim does and does not cover; the
# author had read the rule under test, and the mitigation is structural.
#
# Using one of these captures to steer a fix ends the set the moment it
# happens. Reproduce the shape in Tools/CorpusRunner/devsets/ and work there.
set -euo pipefail
SP="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SP/../../.." && pwd)"
cd "$ROOT"
[ -x Tools/PipelineProbe/build/probe ] || ./Tools/PipelineProbe/build.sh >/dev/null
# Data rows are selected by their id rather than by dropping comment lines.
# `cut -f2 | grep -v '^#'` keeps a commented header's SECOND cell -- the bare
# word "utterance" -- and feeds it to the probe as a capture. Matching the id
# column cannot do that, whatever anyone adds to the header later.
grep -E '^CQ[0-9]+	' "$SP/consequence.tsv" | cut -f2 > /tmp/consequence_utterances.txt
./Tools/PipelineProbe/build/probe /tmp/consequence_utterances.txt > /tmp/consequence_out.txt 2>&1
python3 "$ROOT/Tools/CorpusRunner/heldout/score.py" \
    "$SP/consequence.tsv" /tmp/consequence_out.txt "$@"
