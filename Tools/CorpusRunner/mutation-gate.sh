#!/bin/bash
# Standing mutation gate.
#
# Sabotages each named subsystem in turn and reports how many blocking corpus
# failures that causes. The question it answers is the only one that establishes
# whether a test suite protects anything: **if I delete this, does anything
# fail?** A subsystem that can be deleted for free is either dead code or
# untested, and both are worth knowing before a redesign touches it.
#
#   ./Tools/CorpusRunner/mutation-gate.sh          # run every mutation
#   ./Tools/CorpusRunner/mutation-gate.sh people   # run matching ones only
#
# Exit status is non-zero when a subsystem survives its own deletion.
set -uo pipefail
SP="$(cd "$(dirname "$0")" && pwd)"
FILTER="${1:-}"
THRESHOLD="${MUTATION_MIN_BLOCKING:-3}"

# name | file | signature line | injected statement
MUTATIONS=(
  "person-mentions|SpeakIt/Repositories/PersonMention.swift|static func mentions(in text: String) -> [PersonMention] {|return []"
  "disfluency-filter|SpeakIt/Repositories/SpeechRepair.swift|static func stripped(_ text: String) -> String {|return text"
  "split-compound|SpeakIt/Repositories/SpeechRepair.swift|static func rejoined(_ text: String) -> String {|return text"
  "clause-splitting|SpeakIt/Repositories/ThoughtExtractor.swift|static func splitClauses(_ text: String) -> [String] {|return [text]"
  "conjunct-independence|SpeakIt/Repositories/ThoughtExtractor.swift|private static func isIndependentConjunct(|return false"
  "cancellation-scope|SpeakIt/Repositories/SpeechRepair.swift|cancellationIsEmbedded(_ text: String) -> Bool {|return false"
  "cancellation-reversal|SpeakIt/Repositories/SpeechRepair.swift|cancellationIsTakenBack(_ text: String) -> Bool {|return false"
  "prohibitive-reminders|SpeakIt/Repositories/ThoughtOrganizer.swift|static func isProhibitive(_ text: String) -> Bool {|return false"
  "series-wall-clock|SpeakIt/Repositories/ThoughtOrganizer.swift|static func statedWallClock(in text: String) -> WallClockTime? {|return nil"
  "episode-continuation|SpeakIt/Repositories/ThoughtExtractor.swift|private static func continuesTheSameEpisode(|return false"
  "clause-scope|SpeakIt/Repositories/ClauseStructure.swift|static func read(_ clause: String) -> Reading {|return Reading(act: .direct, matrix: clause, complement: nil, complementRange: nil, speaker: nil, recipient: nil, actor: .unresolved)"
  "sentence-context|SpeakIt/Repositories/ClauseStructure.swift|func tokens(in range: Range<String.Index>) -> [Token] {|return []"
  "action-ownership|SpeakIt/Repositories/Actionability.swift|private static func obligationBelongsToAnotherPerson(_ text: String) -> Bool {|return false"
  "unsettled-time|SpeakIt/Repositories/ClauseStructure.swift|static func unsettled(in text: String) -> Unsettled? {|return nil"
  "day-month-order|SpeakIt/Repositories/ThoughtOrganizer.swift|private static func dayBeforeMonth(|return nil"
  "zero-padded-morning|SpeakIt/Repositories/ThoughtOrganizer.swift|private static func isZeroPaddedMorning(_ hourToken: String) -> Bool {|return false"
  "bare-half-hour|SpeakIt/Repositories/ThoughtOrganizer.swift|private static func bareHalfHour(in text: String) -> ParsedTime? {|return nil"
  "spoken-24-hour|SpeakIt/Repositories/ThoughtOrganizer.swift|private static func twentyFourHourSpoken(in text: String) -> ParsedTime? {|return nil"
  "clock-face-by-ear|SpeakIt/Repositories/ThoughtOrganizer.swift|private static func spokenClockFaceByEar(in text: String) -> ParsedTime? {|return nil"
  "past-weekday|SpeakIt/Repositories/ThoughtOrganizer.swift|private static func isPastReference(to weekdayName: String, in text: String) -> Bool {|return false"
  "week-after-weekday|SpeakIt/Repositories/ThoughtOrganizer.swift|private static func namesTheWeekAfter(_ weekdayName: String, in text: String) -> Bool {|return false"
)

printf '%-24s %10s %10s   %s\n' "SUBSYSTEM" "BLOCKING" "FAILING" "VERDICT"
printf -- '---------------------------------------------------------------------\n'
status=0
for entry in "${MUTATIONS[@]}"; do
  IFS='|' read -r name file sig inject <<< "$entry"
  [ -n "$FILTER" ] && [[ "$name" != *"$FILTER"* ]] && continue
  start=$(grep -nF -- "$sig" "$SP/../../$file" | head -1 | cut -d: -f1)
  # Swift signatures wrap across lines. The statement has to land inside the
  # body, so walk forward to the line that actually opens it.
  line=$(awk -v s="$start" 'NR>=s && /\{[[:space:]]*$/ {print NR; exit}' "$SP/../../$file")
  if [ -z "$start" ] || [ -z "$line" ]; then
    printf '%-24s %10s %10s   %s\n' "$name" "-" "-" "SIGNATURE NOT FOUND — update this script"
    status=1; continue
  fi
  out=$("$SP/mutate.sh" "$name" "$file" "$line" "$inject" 2>/dev/null)
  blocking=$(echo "$out" | grep -o 'BLOCKING(crit+beh) = [0-9]*' | grep -o '[0-9]*$')
  failing=$(echo "$out" | sed -n 's/.*TOTAL [0-9]* cases, \([0-9]*\) failing.*/\1/p')
  blocking=${blocking:-0}; failing=${failing:-0}
  if [ "$blocking" -ge "$THRESHOLD" ]; then verdict="protected"
  else verdict="UNPROTECTED — deleting this costs $blocking blocking failures"; status=1; fi
  printf '%-24s %10s %10s   %s\n' "$name" "$blocking" "$failing" "$verdict"
done
printf -- '---------------------------------------------------------------------\n'
echo "baseline blocking is 0; threshold is $THRESHOLD (set MUTATION_MIN_BLOCKING to change)"
exit $status
