#!/bin/bash
# Archives the app with automatic (cloud-managed) signing and uploads the
# archive to App Store Connect. Used by .github/workflows/testflight.yml.
#
# Required environment:
#   ASC_KEY_ID, ASC_ISSUER_ID   App Store Connect API key identifiers
#   ASC_KEY_PATH                path to the matching AuthKey_<id>.p8
# Optional:
#   SPEAKIT_ANALYTICS_KEY       PostHog project key; empty keeps analytics off
#   SPEAKIT_ARCHIVE_DIR         where the archive and export land
#
# Not yet exercised end to end: the secrets above have never been configured
# for this repository. Treat the first run as a rehearsal.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

: "${ASC_KEY_ID:?ASC_KEY_ID is required}"
: "${ASC_ISSUER_ID:?ASC_ISSUER_ID is required}"
: "${ASC_KEY_PATH:?ASC_KEY_PATH is required}"
[ -f "$ASC_KEY_PATH" ] || { echo "no key at $ASC_KEY_PATH" >&2; exit 1; }

OUT="${SPEAKIT_ARCHIVE_DIR:-/tmp/SpeakItArchive}"
rm -rf "$OUT"; mkdir -p "$OUT"
ARCHIVE="$OUT/SpeakIt.xcarchive"

auth=(
  -allowProvisioningUpdates
  -authenticationKeyPath "$ASC_KEY_PATH"
  -authenticationKeyID "$ASC_KEY_ID"
  -authenticationKeyIssuerID "$ASC_ISSUER_ID"
)

xcodebuild archive -quiet \
  -project SpeakIt.xcodeproj -scheme SpeakIt -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE" \
  "${auth[@]}" \
  SPEAKIT_ANALYTICS_KEY="${SPEAKIT_ANALYTICS_KEY:-}"

xcodebuild -exportArchive -quiet \
  -archivePath "$ARCHIVE" \
  -exportOptionsPlist Tools/CI/ExportOptions.plist \
  -exportPath "$OUT/export" \
  "${auth[@]}"

echo "uploaded $ARCHIVE to App Store Connect"
