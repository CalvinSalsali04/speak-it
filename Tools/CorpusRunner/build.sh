#!/bin/bash
# Builds a host-side runner for the FULL semantic corpus against the real
# production sources. Mirrors Tools/PipelineProbe/build.sh slicing.
# Usage: build.sh [ROOT]   (ROOT defaults to the real repo)
set -euo pipefail
SP="$(cd "$(dirname "$0")" && pwd)"
ROOT="${1:-$(cd "$SP/../.." && pwd)}"
OUT="${PROBE_OUT:-$SP/build}"
rm -rf "$OUT"; mkdir -p "$OUT"
cd "$ROOT"

START=$(grep -n '^enum ReminderCopy {' SpeakIt/Repositories/ReminderScheduler.swift | cut -d: -f1)
END=$(awk -v s="$START" 'NR>s && /^}/ {print NR; exit}' SpeakIt/Repositories/ReminderScheduler.swift)
{ echo "import Foundation"; sed -n "${START},${END}p" SpeakIt/Repositories/ReminderScheduler.swift; } > "$OUT/ReminderCopySlice.swift"

CUT=$(grep -n "^// MARK: - Memory.s reading of the same question" SpeakIt/Repositories/PersonMention.swift | cut -d: -f1)
sed -n "1,$((CUT - 1))p" SpeakIt/Repositories/PersonMention.swift > "$OUT/PersonMentionSlice.swift"

LCUT=$(grep -n "^/// Turns a location intent into something monitorable" SpeakIt/Models/LocationIntent.swift | cut -d: -f1)
sed -n "1,$((LCUT - 1))p" SpeakIt/Models/LocationIntent.swift > "$OUT/LocationIntentSlice.swift"

# The corpus and evaluator, with the test-target import removed.
mkdir -p "$OUT/corpus"
for f in SpeakItTests/SemanticCorpus.swift SpeakItTests/SemanticCorpusData*.swift SpeakItTests/CorpusEvaluator.swift; do
  sed 's/^@testable import SpeakIt$//; s/^import XCTest$//' "$f" > "$OUT/corpus/$(basename "$f")"
done

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swiftc -O -o "$OUT/corpus-run" \
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
  "$OUT/ReminderCopySlice.swift" \
  "$OUT"/corpus/*.swift \
  "$SP/../PipelineProbe/shims.swift" "$SP/main.swift" 2>&1 | grep -E 'error:' | head -40 || true
test -x "$OUT/corpus-run" && echo "corpus runner built: $OUT/corpus-run"
