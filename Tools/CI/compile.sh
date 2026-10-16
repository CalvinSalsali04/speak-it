#!/bin/bash
# Compiles the app, its extensions and both test bundles for a simulator,
# without running a test.
#
# This exists so "the Swift compiled" is its own answer. `unit-tests.sh` builds
# and tests in one xcodebuild, so a red run could not say whether a single
# file compiled, and a job stopped earlier looked the same as one where the
# Swift never met a compiler. Point `unit-tests.sh` at the same derived data
# afterwards and its build step is incremental. After the build it checks
# that the app, both extensions and both test bundles exist, and names them.
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

# The five products the scheme is meant to build. `-quiet` prints nothing on
# success, so without this "compile ok" would say the same thing if a target
# dropped out of the scheme's build. Searched for by name anywhere under the
# simulator products, because Xcode embeds extensions and test bundles inside
# their hosts. This proves each bundle exists, not that this run rebuilt it: on
# a fresh derived-data path (every hosted CI run) that is the same thing, on a
# reused one it is not. It also cannot notice a Swift file missing from
# project.pbxproj; nothing short of a test that needs the file can.
PRODUCTS="$DERIVED_DATA/Build/Products/Debug-iphonesimulator"
missing=()
found=()
for product in SpeakIt.app SpeakItLiveActivity.appex SpeakItShareExtension.appex \
  SpeakItTests.xctest SpeakItUITests.xctest; do
  if [ -n "$(find "$PRODUCTS" -name "$product" -print -quit 2>/dev/null)" ]; then
    found+=("$product")
  else
    missing+=("$product")
  fi
done
if [ "${#missing[@]}" -gt 0 ]; then
  echo "compile.sh: the build succeeded but did not produce: ${missing[*]} (looked under $PRODUCTS)" >&2
  exit 1
fi
echo "compile ok: ${found[*]}"
