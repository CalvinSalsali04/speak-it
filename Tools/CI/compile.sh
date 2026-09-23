#!/bin/bash
# Compiles the app, its extensions and both test bundles for a simulator,
# without running a test.
#
# This exists so "the Swift compiled" is its own answer. `unit-tests.sh` builds
# and tests in one xcodebuild, so a red run could not say whether a single
# file compiled, and a job stopped earlier looked the same as one where the
# Swift never met a compiler. Point `unit-tests.sh` at the same derived data
# afterwards and its build step is incremental.
#
#   Tools/CI/compile.sh
#
# Environment:
#   DEVELOPER_DIR            Xcode to use (default /Applications/Xcode.app)
#   SPEAKIT_SIMULATOR_ID     simulator UDID (default: see simulator-id.sh)
#   SPEAKIT_DERIVED_DATA     derived data path (default /tmp/SpeakItClaudeTests)
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
cd "$ROOT"

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
DERIVED_DATA="${SPEAKIT_DERIVED_DATA:-/tmp/SpeakItClaudeTests}"
SIMULATOR="$("$HERE/simulator-id.sh")"

xcodebuild build-for-testing -quiet \
  -project SpeakIt.xcodeproj \
  -scheme SpeakIt \
  -destination "platform=iOS Simulator,id=$SIMULATOR" \
  -derivedDataPath "$DERIVED_DATA" \
  CODE_SIGNING_ALLOWED=NO
echo "compile ok"
