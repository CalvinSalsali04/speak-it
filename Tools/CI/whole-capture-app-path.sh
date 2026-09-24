#!/bin/bash
# The `app` path of the phase 13 whole-capture evaluation: every capture of an
# input, saved through the repository the capture screen uses, written in the
# pipeline probe's --json shape for Tools/CorpusRunner/wholecapture/score.py.
#
#   Tools/CI/whole-capture-app-path.sh INPUT.jsonl OUTPUT.jsonl
#
# INPUT is JSONL with `id` and `utterance` per line; other keys are ignored, so a
# phase 13 contract can be the input as it stands. OUTPUT must not exist yet and
# must sit outside the repository: it repeats each utterance, and a sealed set's
# words do not belong in a working tree.
#
# Runs only SpeakItTests/WholeCaptureExportTests/testExportsEveryCaptureInTheConfiguredInput
# through unit-tests.sh, handing it the two paths as TEST_RUNNER_ variables,
# then checks that the output holds exactly one line per input id. It prints
# counts only, never ids or text.
#
# What it measures is the repository save path inside the unit-test host, not
# the UI: see the doc comment on WholeCaptureExportTests for what it cannot see.
#
# Environment: as unit-tests.sh (DEVELOPER_DIR, SPEAKIT_SIMULATOR_ID,
# SPEAKIT_DERIVED_DATA, SPEAKIT_RESULT_BUNDLE), plus
#   SPEAKIT_ALLOW_BLIND_TAGGER=1   accept an export read with a blind lexical
#                                  tagger (by default that exits 4: it describes
#                                  the degraded policy, not a phone)
#
# Exit: 0 complete; 1 the test run failed; 2 usage; 3 ids missing, repeated or
# unexpected; 4 read with a blind tagger.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"

usage() {
  echo "usage: $0 INPUT.jsonl OUTPUT.jsonl" >&2
  exit 2
}

[ "$#" -eq 2 ] || usage
INPUT="$(python3 -c 'import os, sys; print(os.path.abspath(sys.argv[1]))' "$1")"
OUTPUT="$(python3 -c 'import os, sys; print(os.path.abspath(sys.argv[1]))' "$2")"

if [ ! -f "$INPUT" ]; then
  echo "whole-capture-app-path.sh: no input at $INPUT" >&2
  exit 2
fi
if [ -e "$OUTPUT" ]; then
  echo "whole-capture-app-path.sh: $OUTPUT exists; an export is written once, so pick a new path" >&2
  exit 2
fi
case "$(python3 -c 'import os, sys; print(os.path.realpath(sys.argv[1]))' "$(dirname "$OUTPUT")")/" in
  "$(python3 -c 'import os, sys; print(os.path.realpath(sys.argv[1]))' "$ROOT")"/*)
    echo "whole-capture-app-path.sh: write the output outside the repository ($ROOT)" >&2
    exit 2
    ;;
esac
mkdir -p "$(dirname "$OUTPUT")"

status=0
TEST_RUNNER_SPEAKIT_WHOLE_CAPTURE_INPUT="$INPUT" \
TEST_RUNNER_SPEAKIT_WHOLE_CAPTURE_OUTPUT="$OUTPUT" \
  "$HERE/unit-tests.sh" SpeakItTests/WholeCaptureExportTests/testExportsEveryCaptureInTheConfiguredInput \
  || status=$?

check=0
python3 - "$INPUT" "$OUTPUT" <<'PY' || check=$?
import json
import os
import sys
from collections import Counter

source, output = sys.argv[1], sys.argv[2]
wanted = Counter()
unreadable_input = 0
for line in open(source, encoding="utf-8").read().splitlines():
    if not line.strip():
        continue
    try:
        row = json.loads(line)
    except ValueError:
        unreadable_input += 1
        continue
    if isinstance(row, dict) and isinstance(row.get("id"), str) and row["id"]:
        wanted[row["id"]] += 1
    else:
        unreadable_input += 1

if not os.path.exists(output):
    print(f"whole-capture app path: no output was written; {sum(wanted.values())} ids missing")
    sys.exit(3)

got = Counter()
errors = unreadable_output = 0
taggers = Counter()
for line in open(output, encoding="utf-8").read().splitlines():
    if not line.strip():
        continue
    try:
        row = json.loads(line)
    except ValueError:
        unreadable_output += 1
        continue
    if row.get("id"):
        got[row["id"]] += 1
    if "error" in row:
        errors += 1
    else:
        taggers[row.get("tagger", "unrecorded")] += 1

missing = sum((wanted - got).values())
repeated = sum(count - 1 for count in got.values() if count > 1)
unexpected = sum(1 for key in got if key not in wanted)
duplicate_input = sum(count - 1 for count in wanted.values() if count > 1)
print(f"whole-capture app path: {sum(wanted.values())} input ids, {sum(got.values())} output lines with an id")
print(f"  missing {missing}, repeated {repeated}, unexpected {unexpected}, "
      f"error lines {errors} (each counts as incorrect)")
if unreadable_input or unreadable_output or duplicate_input:
    print(f"  unreadable input lines {unreadable_input}, unreadable output lines {unreadable_output}, "
          f"duplicate input ids {duplicate_input}")
print("  tagger: " + (", ".join(f"{k} {v}" for k, v in sorted(taggers.items())) or "no reading"))
if missing or repeated or unexpected or unreadable_output or duplicate_input or unreadable_input:
    sys.exit(3)
if taggers.get("blind"):
    print("  BLIND TAGGER: this simulator's lexical tagger answered nothing, so these rows")
    print("  describe the degraded policy, not what a phone does. Run on a machine whose")
    print("  tagger answers, or set SPEAKIT_ALLOW_BLIND_TAGGER=1 to keep it as that.")
    sys.exit(4)
PY

if [ "$check" = "4" ] && [ "${SPEAKIT_ALLOW_BLIND_TAGGER:-}" = "1" ]; then
  echo "whole-capture-app-path.sh: kept a blind-tagger export because SPEAKIT_ALLOW_BLIND_TAGGER=1" >&2
  check=0
fi
if [ "$status" != "0" ]; then
  echo "whole-capture-app-path.sh: the test run exited $status" >&2
  exit 1
fi
exit "$check"
