#!/bin/bash
# Builds the Foundation Models interpretation probe from the live app sources.
#
# Same source slicing as Tools/PipelineProbe/build.sh, plus SpeakIt/Interpretation.
# It links FoundationModels when the toolchain has it; the binary runs either
# way, because everything except `--interpret` is deterministic and needs no
# model. That is deliberate: a CI runner with no Apple Intelligence can still
# build this, run `--availability` to record what it has, `--selfcheck` to prove
# the deterministic half works, and `--replay` to re-score a run somebody else
# generated on hardware.
set -euo pipefail
SP="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SP/../.." && pwd)"
OUT="${PROBE_OUT:-$SP/build}"
mkdir -p "$OUT"
cd "$ROOT"

START=$(grep -n '^enum ReminderCopy {' SpeakIt/Repositories/ReminderScheduler.swift | cut -d: -f1)
END=$(awk -v s="$START" 'NR>s && /^}/ {print NR; exit}' SpeakIt/Repositories/ReminderScheduler.swift)
{ echo "import Foundation"; sed -n "${START},${END}p" SpeakIt/Repositories/ReminderScheduler.swift; } > "$OUT/ReminderCopySlice.swift"

CUT=$(grep -n "^// MARK: - Memory.s reading of the same question" SpeakIt/Repositories/PersonMention.swift | cut -d: -f1)
sed -n "1,$((CUT - 1))p" SpeakIt/Repositories/PersonMention.swift > "$OUT/PersonMentionSlice.swift"

LCUT=$(grep -n "^/// Turns a location intent into something monitorable" SpeakIt/Models/LocationIntent.swift | cut -d: -f1)
sed -n "1,$((LCUT - 1))p" SpeakIt/Models/LocationIntent.swift > "$OUT/LocationIntentSlice.swift"

DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}" xcrun swiftc -O -o "$OUT/interpret" \
  SpeakIt/Repositories/ClauseStructure.swift \
  SpeakIt/Repositories/TranscriptProvenance.swift \
  SpeakIt/Repositories/ThoughtExtractor.swift \
  SpeakIt/Repositories/ThoughtOrganizer.swift \
  SpeakIt/Repositories/SpeechRepair.swift \
  SpeakIt/Repositories/IntentConsolidation.swift \
  SpeakIt/Repositories/Actionability.swift \
  "$OUT/PersonMentionSlice.swift" \
  SpeakIt/Repositories/LocationIntentParser.swift \
  SpeakIt/Repositories/CaptureOperationCopy.swift \
  SpeakIt/Features/Shopping/ShoppingGroups.swift \
  SpeakIt/Models/DomainEnums.swift \
  SpeakIt/Models/CaptureOperation.swift \
  "$OUT/LocationIntentSlice.swift" \
  SpeakIt/Models/TemporalIntent.swift \
  SpeakIt/Models/ReminderTrigger.swift \
  "$OUT/ReminderCopySlice.swift" \
  SpeakIt/Interpretation/CaptureInterpretation.swift \
  SpeakIt/Interpretation/InterpretationPolicy.swift \
  SpeakIt/Interpretation/InterpretationBridge.swift \
  SpeakIt/Interpretation/ModelInterpreter.swift \
  "$SP/../PipelineProbe/shims.swift" \
  "$SP/../PipelineProbe/rowreport.swift" \
  "$SP/main.swift" 2> "$OUT/build-errors.log" || { cat "$OUT/build-errors.log" >&2; exit 1; }
test -x "$OUT/interpret" && echo "interpretation probe built: $OUT/interpret"
