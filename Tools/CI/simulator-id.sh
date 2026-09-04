#!/bin/bash
# Prints the UDID of the iPhone simulator the test scripts should use.
#
# Order of preference: SPEAKIT_SIMULATOR_ID when set, then a "SpeakIt-Slim-*"
# pool device (see simulator-pool.sh; booted before shut down), then a booted
# iPhone, then the first available iPhone on the newest installed iOS runtime.
# Every Mac and every CI image carries a different set of simulators, so
# nothing here hard-codes a UDID.
#
# The pool comes first because it is the one place a test run does not collide
# with a simulator somebody is using by hand, or with another session's run.
set -euo pipefail
if [ -n "${SPEAKIT_SIMULATOR_ID:-}" ]; then
  echo "$SPEAKIT_SIMULATOR_ID"
  exit 0
fi
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
xcrun simctl list devices available -j | python3 -c '
import json, re, sys

devices = json.load(sys.stdin)["devices"]

def runtime_version(identifier):
    match = re.search(r"iOS-(\d+)-(\d+)", identifier)
    return (int(match.group(1)), int(match.group(2))) if match else (0, 0)

candidates = []
for runtime, entries in devices.items():
    if "iOS" not in runtime:
        continue
    for device in entries:
        if device.get("isAvailable") and device["name"].startswith("iPhone"):
            candidates.append((
                device["name"].startswith("SpeakIt-Slim-"),
                device.get("state") == "Booted",
                runtime_version(runtime),
                device["udid"],
                device["name"],
            ))
if not candidates:
    sys.exit("simulator-id.sh: no available iPhone simulator; install one in Xcode > Settings > Components")
candidates.sort(reverse=True)
pooled, booted, version, udid, name = candidates[0]
print(f"{name} (iOS {version[0]}.{version[1]}, {'booted' if booted else 'shutdown'}) {udid}", file=sys.stderr)
print(udid)
'
