#!/bin/bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
OUT="${SPEAKIT_SPEECH_REPLAY_BUILD:-$HERE/build}"
mkdir -p "$OUT"
DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}" xcrun swiftc -parse-as-library -O \
  "$ROOT/SpeakIt/Features/Capture/SpeechRecognitionBackend.swift" "$HERE/main.swift" -o "$OUT/speech-replay"
