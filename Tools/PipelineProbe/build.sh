#!/bin/bash
# Builds the standalone transcription probe from the live app sources.
# ReminderCopy is sliced out of ReminderScheduler.swift (which imports AlarmKit
# and UIKit and therefore cannot be compiled for the host) so the probe always
# tracks the real copy logic rather than a drifting duplicate.
set -euo pipefail
SP="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SP/../.." && pwd)"
OUT="${PROBE_OUT:-$SP/build}"
mkdir -p "$OUT"
cd "$ROOT"

START=$(grep -n '^enum ReminderCopy {' SpeakIt/Repositories/ReminderScheduler.swift | cut -d: -f1)
END=$(awk -v s="$START" 'NR>s && /^}/ {print NR; exit}' SpeakIt/Repositories/ReminderScheduler.swift)
{ echo "import Foundation"; sed -n "${START},${END}p" SpeakIt/Repositories/ReminderScheduler.swift; } > "$OUT/ReminderCopySlice.swift"

# PersonMention's tail resolves names for Memory rows and needs the SwiftData
# model. Extraction never calls it, so the probe compiles the file up to that
# section marker.
CUT=$(grep -n "^// MARK: - Memory.s reading of the same question" SpeakIt/Repositories/PersonMention.swift | cut -d: -f1)
sed -n "1,$((CUT - 1))p" SpeakIt/Repositories/PersonMention.swift > "$OUT/PersonMentionSlice.swift"

# LocationIntent's tail turns an intent into a monitorable region, which needs
# CoreLocation and the saved-place store. Parsing stops well before that.
LCUT=$(grep -n "^/// Turns a location intent into something monitorable" SpeakIt/Models/LocationIntent.swift | cut -d: -f1)
sed -n "1,$((LCUT - 1))p" SpeakIt/Models/LocationIntent.swift > "$OUT/LocationIntentSlice.swift"

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swiftc -O -o "$OUT/probe" \
  SpeakIt/Repositories/ClauseStructure.swift \
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
  "$OUT/ReminderCopySlice.swift" "$SP/shims.swift" "$SP/main.swift" 2>&1 | grep -E 'error:' || true
test -x "$OUT/probe" && echo "probe built: $OUT/probe"
