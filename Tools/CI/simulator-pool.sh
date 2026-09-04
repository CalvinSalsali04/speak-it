#!/bin/bash
# Ensures a pool of slim simulators exists and prints their UDIDs, one per line.
#
#   Tools/CI/simulator-pool.sh          # one device, SpeakIt-Slim-1
#   Tools/CI/simulator-pool.sh 3        # SpeakIt-Slim-1 … SpeakIt-Slim-3
#
# Each device is an iPhone on the newest installed iOS runtime, named
# "SpeakIt-Slim-N", created if missing, slimmed with Tools/CI/simslim-profile.json
# (see slim-simulator.sh; a no-op without SimSlim installed), and booted.
#
# Two things this buys:
#   - unit-tests.sh can shard the suite across the pool (SPEAKIT_SHARDS=N).
#   - Concurrent sessions stop displacing each other's test bundle on the one
#     simulator everybody reaches for. Give each session its own pool device
#     via SPEAKIT_SIMULATOR_ID.
#
# The pool is ordinary simulators in the default device set. Delete one with
# `xcrun simctl delete <udid>`; nothing here deletes anything.
#
# Environment:
#   DEVELOPER_DIR                Xcode to use (default /Applications/Xcode.app)
#   SPEAKIT_POOL_DEVICE_TYPE     simctl device type (default: iPhone 17, else the newest iPhone)
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
COUNT="${1:-1}"
case "$COUNT" in
  ''|*[!0-9]*) echo "usage: simulator-pool.sh [count]" >&2; exit 2 ;;
esac

runtime="$(xcrun simctl list runtimes -j | python3 -c '
import json, sys
runtimes = [r for r in json.load(sys.stdin)["runtimes"] if r["platform"] == "iOS" and r["isAvailable"]]
if not runtimes:
    sys.exit("simulator-pool.sh: no iOS runtime installed; add one in Xcode > Settings > Components")
runtimes.sort(key=lambda r: [int(x) for x in r["version"].split(".")])
print(runtimes[-1]["identifier"])
')"

device_type="${SPEAKIT_POOL_DEVICE_TYPE:-}"
if [ -z "$device_type" ]; then
  device_type="$(xcrun simctl list devicetypes -j | python3 -c '
import json, sys
types = [t for t in json.load(sys.stdin)["devicetypes"] if t["productFamily"] == "iPhone"]
exact = [t for t in types if t["name"] == "iPhone 17"]
print((exact or types[-1:])[0]["identifier"])
')"
fi

existing="$(xcrun simctl list devices -j | python3 -c '
import json, sys
for runtime, entries in json.load(sys.stdin)["devices"].items():
    for device in entries:
        if device["name"].startswith("SpeakIt-Slim-") and device.get("isAvailable"):
            print(device["name"], device["udid"], device.get("state", ""))
')"

for index in $(seq 1 "$COUNT"); do
  name="SpeakIt-Slim-$index"
  udid="$(echo "$existing" | awk -v n="$name" '$1 == n {print $2; exit}')"
  if [ -z "$udid" ]; then
    udid="$(xcrun simctl create "$name" "$device_type" "$runtime")"
    echo "simulator-pool.sh: created $name ($udid) on $runtime" >&2
  fi
  "$HERE/slim-simulator.sh" "$udid" >&2
  state="$(echo "$existing" | awk -v n="$name" '$1 == n {print $3; exit}')"
  if [ "$state" != "Booted" ]; then
    xcrun simctl boot "$udid" >/dev/null 2>&1 || true
  fi
  echo "$udid"
done
