#!/bin/bash
# Runs the XCTest suite on a simulator. The same script backs the CI job and
# the command in CLAUDE.md, so a green run here is the same evidence as a
# green run there.
#
#   Tools/CI/unit-tests.sh                                  # SpeakItTests (the unit suite)
#   Tools/CI/unit-tests.sh SpeakItTests/TemporalFullPathTests
#   Tools/CI/unit-tests.sh SpeakItUITests                   # the XCUITest suite, slow
#
# Environment:
#   DEVELOPER_DIR            Xcode to use (default /Applications/Xcode.app)
#   SPEAKIT_SIMULATOR_ID     simulator UDID (default: see simulator-id.sh)
#   SPEAKIT_DERIVED_DATA     derived data path (default /tmp/SpeakItClaudeTests)
#   SPEAKIT_RESULT_BUNDLE    write an .xcresult here (default: none)
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
cd "$ROOT"

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
ONLY="${1:-SpeakItTests}"
SIMULATOR="$("$HERE/simulator-id.sh")"
DERIVED_DATA="${SPEAKIT_DERIVED_DATA:-/tmp/SpeakItClaudeTests}"
RESULT_BUNDLE="${SPEAKIT_RESULT_BUNDLE:-}"

args=(
  test -quiet
  -project SpeakIt.xcodeproj
  -scheme SpeakIt
  -destination "platform=iOS Simulator,id=$SIMULATOR"
  -derivedDataPath "$DERIVED_DATA"
  -only-testing:"$ONLY"
  CODE_SIGNING_ALLOWED=NO
)
if [ -n "$RESULT_BUNDLE" ]; then
  rm -rf "$RESULT_BUNDLE"
  args+=(-resultBundlePath "$RESULT_BUNDLE")
fi

echo "xcodebuild ${args[*]}"
status=0
xcodebuild "${args[@]}" || status=$?

# Best-effort pass/fail summary for the GitHub job summary; the .xcresult is
# the authoritative record and is uploaded as an artifact on failure.
if [ -n "$RESULT_BUNDLE" ] && [ -d "$RESULT_BUNDLE" ] && [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  summary_file="$(mktemp)"
  if xcrun xcresulttool get test-results summary --path "$RESULT_BUNDLE" --format json > "$summary_file" 2>/dev/null; then
    python3 - "$ONLY" "$summary_file" <<'PY' >> "$GITHUB_STEP_SUMMARY" || true
import json, sys
data = json.load(open(sys.argv[2]))
print(f"### {sys.argv[1]}")
print()
print("| Result | Passed | Failed | Skipped |")
print("|---|---|---|---|")
print(f"| {data.get('result', '?')} | {data.get('passedTests', '?')} | {data.get('failedTests', '?')} | {data.get('skippedTests', '?')} |")
for failure in data.get("testFailures", [])[:25]:
    print(f"- `{failure.get('testName', '?')}` — {failure.get('failureText', '').strip()[:300]}")
PY
  fi
  rm -f "$summary_file"
fi
exit $status
