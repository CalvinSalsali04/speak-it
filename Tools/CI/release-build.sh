#!/bin/bash
# Compiles the Release configuration for a generic iOS device without signing.
# This is the compile check CLAUDE.md asks for before app-level work is called
# done: Release-only conditions, dead-stripping and the extension targets all
# get exercised here and nowhere else in the test suite.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
DERIVED_DATA="${SPEAKIT_RELEASE_DERIVED_DATA:-/tmp/SpeakItClaudeRelease}"

xcodebuild build -quiet \
  -project SpeakIt.xcodeproj -scheme SpeakIt -configuration Release \
  -destination 'generic/platform=iOS' \
  -derivedDataPath "$DERIVED_DATA" CODE_SIGNING_ALLOWED=NO
echo "release build ok"
