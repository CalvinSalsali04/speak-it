#!/bin/bash
#
# App Store 6.9-inch screenshot set for Speak It.
#
# Boots the stock "iPhone 17 Pro Max" simulator, builds the Debug app once,
# installs it, pins the status bar to Apple's 9:41 convention, then shoots the
# tap-free screens with `simctl io screenshot` in light and dark appearance and
# hands the screens that need taps to SpeakItUITests/AppStoreScreenshotTests.
#
# Output: output/app-store-screenshots/{light,dark}/NN-name.png at 1320x2868.
#
#   01-welcome            first run                          (simctl)
#   02-capture            capture screen with a typed thought (UI test)
#   03-today              Today with the marketing fixtures   (simctl)
#   04-memory             Memory with the marketing fixtures  (simctl)
#   05-person             a person's page in Memory           (UI test)
#   06-reminder-setting   default reminder time in settings   (UI test)
#   07-pro                the Speak It Pro paywall            (simctl)
#
# Environment:
#   SPEAKIT_SCREENSHOT_SIMULATOR   simulator UDID (default: the stock iPhone 17 Pro Max)
#   SPEAKIT_SCREENSHOT_DERIVED     derived data path (default /tmp/SpeakItScreenshots)
#   SPEAKIT_SCREENSHOT_OUT         output directory (default output/app-store-screenshots)
#   SPEAKIT_SCREENSHOT_APPEARANCES comma list, default "light,dark"
#   SPEAKIT_SCREENSHOT_SKIP_BUILD  =1 to reuse the app already in derived data
#   SPEAKIT_SCREENSHOT_SKIP_UITEST =1 to skip the tap-driven screens
#   SPEAKIT_SCREENSHOT_PERSON      person page to shoot (default Tom)
#
# Why the appearance is passed twice: the app pins its colour scheme through the
# `SpeakIt.appearance` default in its own container, which this script writes
# with `simctl spawn defaults write` and reads back. But `--ui-testing-reset`
# removes every `SpeakIt.*` key from that domain at launch, so the launch also
# carries `-SpeakIt.appearance <mode>` in the argument domain, which the reset
# cannot touch. Both are done so the written default is honoured by any launch
# that does not reset, and the reset launches used here still render correctly.

set -euo pipefail

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

UDID="${SPEAKIT_SCREENSHOT_SIMULATOR:-51F14279-8FCD-4292-A24E-959F498BD9C3}"
DERIVED="${SPEAKIT_SCREENSHOT_DERIVED:-/tmp/SpeakItScreenshots}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="${SPEAKIT_SCREENSHOT_OUT:-$ROOT/output/app-store-screenshots}"
APPEARANCES="${SPEAKIT_SCREENSHOT_APPEARANCES:-light,dark}"
BUNDLE="com.calvinwak.SpeakIt"
APP="$DERIVED/Build/Products/Debug-iphonesimulator/SpeakIt.app"
DESTINATION="platform=iOS Simulator,id=$UDID"

# Launch arguments shared by every seeded screen. `--ui-testing` keeps the
# store in memory and suppresses the uninvited Pro sheets; the two dismissed-
# discovery keys stand for a person who has closed the Today banners, so the
# seeded rows are what the screenshots show.
COMMON_ARGS=(
  --ui-testing
  --ui-testing-reset
  --ui-testing-skip-welcome
  --ui-testing-pro-preview
  -SpeakIt.hasDismissedProDiscovery YES
  -SpeakIt.hasDismissedCaptureAnywhereDiscovery YES
)

log() { printf '\n== %s\n' "$*"; }

cleanup() {
  xcrun simctl status_bar "$UDID" clear >/dev/null 2>&1 || true
  if [ -n "${PREFS:-}" ]; then
    xcrun simctl spawn "$UDID" defaults delete "$PREFS" SpeakIt.appearance >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

# --- 1. Simulator ----------------------------------------------------------
log "Booting $UDID"
xcrun simctl boot "$UDID" >/dev/null 2>&1 || true
xcrun simctl bootstatus "$UDID" -b >/dev/null

# --- 2. Build once, install -------------------------------------------------
if [ "${SPEAKIT_SCREENSHOT_SKIP_BUILD:-0}" != "1" ]; then
  log "Building SpeakIt (Debug, simulator) into $DERIVED"
  xcodebuild build -quiet \
    -project "$ROOT/SpeakIt.xcodeproj" -scheme SpeakIt -configuration Debug \
    -destination "$DESTINATION" -derivedDataPath "$DERIVED" \
    CODE_SIGNING_ALLOWED=NO
fi
[ -d "$APP" ] || { echo "capture.sh: no app at $APP" >&2; exit 1; }
log "Installing $APP"
xcrun simctl install "$UDID" "$APP"

# The app's standard defaults live in its data container on an unsigned build,
# and only the simulator's own cfprefsd sees writes to that plist.
PREFS="$(xcrun simctl get_app_container "$UDID" "$BUNDLE" data)/Library/Preferences/$BUNDLE.plist"

# --- 3. Status bar ----------------------------------------------------------
log "Pinning the status bar"
xcrun simctl status_bar "$UDID" override \
  --time 9:41 --batteryState charged --batteryLevel 100 --cellularBars 4 --wifiBars 3

# --- helpers ----------------------------------------------------------------
terminate() { xcrun simctl terminate "$UDID" "$BUNDLE" >/dev/null 2>&1 || true; }

# launch <mode> <args...>: relaunch the app with the appearance pinned.
launch() {
  local mode="$1"; shift
  terminate
  xcrun simctl spawn "$UDID" defaults delete "$PREFS" SpeakIt.hasLoadedMarketingExamples >/dev/null 2>&1 || true
  xcrun simctl launch "$UDID" "$BUNDLE" "$@" -SpeakIt.appearance "$mode" >/dev/null
}

# wait_for_fixtures: the marketing loader sets this flag once the last of its
# fifteen sentences has been through the pipeline. Measured at 2-3 s here, and
# about 20 s where the on-device model refines the comma sentences, so poll
# the app's own signal rather than sleeping a guessed number.
wait_for_fixtures() {
  local i
  for i in $(seq 1 150); do
    if [ "$(xcrun simctl spawn "$UDID" defaults read "$PREFS" SpeakIt.hasLoadedMarketingExamples 2>/dev/null || true)" = "1" ]; then
      sleep 1.5   # let the lists settle after the last insert
      return 0
    fi
    sleep 1
  done
  echo "capture.sh: fixtures never finished loading" >&2
  return 1
}

shoot() { # shoot <dir> <name>
  xcrun simctl io "$UDID" screenshot "$1/$2.png" >/dev/null 2>&1
  printf '   %s/%s.png\n' "$1" "$2"
}

# --- 4. simctl screens, per appearance ---------------------------------------
IFS=',' read -r -a MODES <<< "$APPEARANCES"
for mode in "${MODES[@]}"; do
  dir="$OUT/$mode"
  mkdir -p "$dir"
  log "Appearance: $mode"

  terminate
  xcrun simctl spawn "$UDID" defaults write "$PREFS" SpeakIt.appearance -string "$mode"
  readback="$(xcrun simctl spawn "$UDID" defaults read "$PREFS" SpeakIt.appearance)"
  [ "$readback" = "$mode" ] || { echo "capture.sh: SpeakIt.appearance read back as '$readback'" >&2; exit 1; }
  echo "   SpeakIt.appearance = $readback"
  xcrun simctl ui "$UDID" appearance "$mode" >/dev/null 2>&1 || true

  # 01 welcome: a reset launch without --ui-testing-skip-welcome is first run.
  launch "$mode" --ui-testing --ui-testing-reset --screenshots
  sleep 4
  shoot "$dir" "01-welcome"

  # 03 Today with the marketing fixtures.
  launch "$mode" "${COMMON_ARGS[@]}" --load-marketing-examples
  wait_for_fixtures
  shoot "$dir" "03-today"

  # 04 Memory with the same fixtures.
  launch "$mode" "${COMMON_ARGS[@]}" --load-marketing-examples --show-memory
  wait_for_fixtures
  shoot "$dir" "04-memory"

  # 07 Pro paywall, opened directly; nothing is purchased.
  launch "$mode" "${COMMON_ARGS[@]}" --show-pro
  sleep 6
  shoot "$dir" "07-pro"
done
terminate

# --- 5. Tap-driven screens through the UI test --------------------------------
if [ "${SPEAKIT_SCREENSHOT_SKIP_UITEST:-0}" != "1" ]; then
  log "Running SpeakItUITests/AppStoreScreenshotTests"
  TEST_RUNNER_SPEAKIT_SCREENSHOT_DIR="$OUT" \
  TEST_RUNNER_SPEAKIT_SCREENSHOT_APPEARANCES="$APPEARANCES" \
  TEST_RUNNER_SPEAKIT_SCREENSHOT_PERSON="${SPEAKIT_SCREENSHOT_PERSON:-Tom}" \
  xcodebuild test -quiet \
    -project "$ROOT/SpeakIt.xcodeproj" -scheme SpeakIt \
    -destination "$DESTINATION" -derivedDataPath "$DERIVED" \
    -only-testing:SpeakItUITests/AppStoreScreenshotTests \
    CODE_SIGNING_ALLOWED=NO
fi

# --- 6. Verify ----------------------------------------------------------------
log "Verifying 1320x2868"
status=0
for png in "$OUT"/*/*.png; do
  size="$(sips -g pixelWidth -g pixelHeight "$png" | awk '/pixelWidth/{w=$2} /pixelHeight/{h=$2} END{print w"x"h}')"
  printf '   %-60s %s\n' "${png#$ROOT/}" "$size"
  [ "$size" = "1320x2868" ] || status=1
done
[ "$status" = 0 ] || { echo "capture.sh: a screenshot is not 1320x2868" >&2; exit 1; }
log "Done: $OUT"
