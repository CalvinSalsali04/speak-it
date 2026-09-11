#!/bin/bash
# Generates meaning-preserving mutations of a set, runs the base utterances and
# their mutations through the rules path, and reports where the answers
# disagreed.
#
#   ./Tools/LanguageMutations/invariance.sh Tools/CorpusRunner/devsets/routed.tsv
#   ./Tools/LanguageMutations/invariance.sh <set> --verbose
#
# Needs macOS: the probe links Apple's NaturalLanguage.
#
# It finds problems; it does not certify the absence of them. A disagreement
# proves one of two answers is wrong without labels, which is what makes volume
# worth anything here. Agreement proves only self-consistency.
#
# The generator refuses to read Tools/CorpusRunner/heldout/, so this cannot be
# pointed at the sealed set by accident.
set -euo pipefail
SP="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SP/../.." && pwd)"
cd "$ROOT" || exit 1
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

SET="${1:?usage: invariance.sh <utterance set> [--verbose]}"
shift || true
[ -f "$SET" ] || { echo "no such set: $SET" >&2; exit 2; }
[ -x Tools/PipelineProbe/build/probe ] || ./Tools/PipelineProbe/build.sh >/dev/null

WORK="${TMPDIR:-/tmp}/SpeakItInvariance"
mkdir -p "$WORK"

python3 "$SP/mutate.py" "$SET" > "$WORK/pairs.tsv"

# Both halves of every pair go through the probe in one run, so the base
# reading a mutation is compared against is the reading from this same build.
awk -F'\t' 'NR > 1 { print $1; print $2 }' "$WORK/pairs.tsv" | sort -u > "$WORK/utterances.txt"
./Tools/PipelineProbe/build/probe "$WORK/utterances.txt" > "$WORK/probe.txt" 2>&1

python3 "$SP/compare.py" "$WORK/pairs.tsv" "$WORK/probe.txt" "$@"
