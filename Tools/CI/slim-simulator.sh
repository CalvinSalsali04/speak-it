#!/bin/bash
# Applies the Speak It SimSlim profile to one simulator.
#
# A stock iOS 26.5 simulator boots about 200 background daemons — Siri,
# Spotlight, photo analysis, wallpaper posters, iCloud, News — and holds about
# 3.7 GB. None of that serves a test run. SimSlim (https://github.com/MobAI-App/simslim,
# MIT) writes persistent launchd disable overrides into the simulator's own
# launchd database, which cuts it to about 60 processes and 0.9 GB, so several
# simulators fit on a 16 GB Mac instead of three or four.
#
#   Tools/CI/slim-simulator.sh <udid>
#
# The profile is Tools/CI/simslim-profile.json. It keeps exactly one daemon,
# com.apple.mobileassetd, because NaturalLanguage loads its tagger and embedding
# assets through it: with it off, every NLTagger/NLEmbedding-backed test fails.
#
# Deliberately opt-in and non-fatal:
#   - Without SimSlim on the PATH it prints how to install it and exits 0.
#   - It only reconfigures simulators named "SpeakIt-Slim-*" (the pool that
#     simulator-pool.sh creates), because slimming disables widgets, Live
#     Activities, Siri and the App Store on that device, which is a surprise on
#     a simulator someone also uses by hand. Set SPEAKIT_SLIM_ANY=1 to override.
#   - A device that already matches the profile is left alone; SimSlim reboots
#     the simulator when it applies changes, and a reboot is not free.
#
# Environment:
#   DEVELOPER_DIR           Xcode to use (default /Applications/Xcode.app)
#   SPEAKIT_SLIM_ANY        set to 1 to slim a simulator outside the pool
#   SIMSLIM_BOOT_TIMEOUT    SimSlim's own boot timeout, e.g. 15m on a slow runner
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
PROFILE="$HERE/simslim-profile.json"
UDID="${1:-}"

if [ -z "$UDID" ]; then
  echo "usage: slim-simulator.sh <udid>" >&2
  exit 2
fi
if ! command -v simslim >/dev/null 2>&1; then
  echo "slim-simulator.sh: simslim is not installed; running $UDID stock." >&2
  echo "  brew install mobai-app/tap/simslim   # https://github.com/MobAI-App/simslim" >&2
  exit 0
fi

name="$(xcrun simctl list devices -j | python3 -c '
import json, sys
udid = sys.argv[1]
for entries in json.load(sys.stdin)["devices"].values():
    for device in entries:
        if device["udid"] == udid:
            print(device["name"]); sys.exit(0)
sys.exit("slim-simulator.sh: no simulator with UDID " + udid)
' "$UDID")"

case "$name" in
  SpeakIt-Slim-*) ;;
  *)
    if [ "${SPEAKIT_SLIM_ANY:-}" != "1" ]; then
      echo "slim-simulator.sh: '$name' is not a SpeakIt-Slim-* pool device; leaving it stock (SPEAKIT_SLIM_ANY=1 overrides)." >&2
      exit 0
    fi
    ;;
esac

if simslim verify "$UDID" --profile "$PROFILE" >/dev/null 2>&1; then
  echo "slim-simulator.sh: $name ($UDID) already matches $(basename "$PROFILE")"
  exit 0
fi

echo "slim-simulator.sh: applying $(basename "$PROFILE") to $name ($UDID); SimSlim will reboot it"
simslim on "$UDID" --profile "$PROFILE"
simslim verify "$UDID" --profile "$PROFILE"
simslim measure "$UDID" || true
