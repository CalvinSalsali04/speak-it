#!/bin/bash
# Runs the XCTest suite on a simulator. The same script backs the CI job and
# the command in CLAUDE.md, so a green run here is the same evidence as a
# green run there.
#
#   Tools/CI/unit-tests.sh                                  # SpeakItTests (the unit suite)
#   Tools/CI/unit-tests.sh SpeakItTests/TemporalFullPathTests
#   Tools/CI/unit-tests.sh SpeakItTests/AbandonmentTests,SpeakItTests/SpeechRepairTests
#   Tools/CI/unit-tests.sh SpeakItUITests                   # the XCUITest suite, slow
#   SPEAKIT_SHARDS=3 Tools/CI/unit-tests.sh                 # the unit suite across three slim simulators
#
# Environment:
#   DEVELOPER_DIR            Xcode to use (default /Applications/Xcode.app)
#   SPEAKIT_SIMULATOR_ID     simulator UDID (default: see simulator-id.sh)
#   SPEAKIT_DERIVED_DATA     derived data path (default /tmp/SpeakItClaudeTests)
#   SPEAKIT_RESULT_BUNDLE    write an .xcresult here (default: none; one per shard when sharded).
#                            With one, a run that exits 0 having run no test
#                            (0 passed, 0 failed) exits 3 instead, and on CI the
#                            counts become the step's outputs passed/failed/skipped
#   SPEAKIT_SHARDS           run a whole target across N pool simulators (default 1;
#                            see simulator-pool.sh — the pool is slimmed with SimSlim
#                            when it is installed, so N devices fit where one stock
#                            simulator used to)
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
cd "$ROOT"

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
ONLY="${1:-SpeakItTests}"
DERIVED_DATA="${SPEAKIT_DERIVED_DATA:-/tmp/SpeakItClaudeTests}"
RESULT_BUNDLE="${SPEAKIT_RESULT_BUNDLE:-}"
SHARDS="${SPEAKIT_SHARDS:-1}"

# Reads the failing assertions out of an .xcresult and prints them.
#
# They go to stdout as well as to the GitHub job summary on purpose. The
# .xcresult is the authoritative record and is uploaded as an artifact, but an
# artifact is downloaded from a blob host, and a session reviewing a CI failure
# may not be able to reach one - which leaves a list of test names and no
# message. The job log is the one place every reader can already see.
#
# Also leaves the bundle's counts in COUNT_PASSED, COUNT_FAILED and
# COUNT_SKIPPED (empty when there is no readable bundle), and says so on stderr
# when there is none, rather than returning quietly.
COUNT_PASSED=""
COUNT_FAILED=""
COUNT_SKIPPED=""
summarize() {
  local title="$1" bundle="$2"
  COUNT_PASSED=""; COUNT_FAILED=""; COUNT_SKIPPED=""
  [ -n "$bundle" ] || return 0
  if [ ! -d "$bundle" ]; then
    echo "unit-tests.sh: no result bundle at $bundle, so no test counts" >&2
    return 0
  fi
  local summary_file text_file counts
  summary_file="$(mktemp)"
  text_file="$(mktemp)"
  if xcrun xcresulttool get test-results summary --path "$bundle" --format json > "$summary_file" 2>/dev/null; then
    python3 "$HERE/xcresult-failures.py" "$title" "$summary_file" > "$text_file" 2>/dev/null || true
    cat "$text_file"
    if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
      cat "$text_file" >> "$GITHUB_STEP_SUMMARY"
    fi
    # Integers or nothing: a count this script cannot read is left empty, never
    # guessed as zero.
    counts="$(python3 -c '
import json, sys
d = json.load(open(sys.argv[1]))
values = [d.get(k) for k in ("passedTests", "failedTests", "skippedTests")]
if all(isinstance(v, int) for v in values):
    print(*values)
' "$summary_file" 2>/dev/null || true)"
    if [ -n "$counts" ]; then
      read -r COUNT_PASSED COUNT_FAILED COUNT_SKIPPED <<< "$counts"
    else
      echo "unit-tests.sh: $bundle has no readable passed/failed/skipped counts" >&2
    fi
  else
    echo "unit-tests.sh: xcresulttool could not read $bundle, so no test counts" >&2
  fi
  rm -f "$summary_file" "$text_file"
}

# ---------------------------------------------------------------------------
# One simulator, one xcodebuild. The path every CI run takes today.
# ---------------------------------------------------------------------------
if [ "$SHARDS" = "1" ] || [[ "$ONLY" == */* ]]; then
  SIMULATOR="$("$HERE/simulator-id.sh")"
  args=(
    test -quiet
    -project SpeakIt.xcodeproj
    -scheme SpeakIt
    -destination "platform=iOS Simulator,id=$SIMULATOR"
    -derivedDataPath "$DERIVED_DATA"
    CODE_SIGNING_ALLOWED=NO
  )
  # A comma-separated list is several -only-testing arguments, not one.
  # Iterating on a defect usually means two or three classes — the one that
  # failed and the one that is supposed to protect it — and passing them as a
  # single identifier matched nothing and reported a build that ran no tests.
  IFS=',' read -r -a only_classes <<< "$ONLY"
  for only_class in "${only_classes[@]}"; do
    [ -n "$only_class" ] && args+=(-only-testing:"$only_class")
  done
  if [ -n "$RESULT_BUNDLE" ]; then
    rm -rf "$RESULT_BUNDLE"
    args+=(-resultBundlePath "$RESULT_BUNDLE")
  fi

  echo "xcodebuild ${args[*]}"
  status=0
  xcodebuild "${args[@]}" || status=$?
  summarize "$ONLY" "$RESULT_BUNDLE"
  # The step's counts, for the stage table that closes a CI job. Written only
  # when they were read, so an absent count stays absent there too.
  if [ -n "${GITHUB_OUTPUT:-}" ] && [ -n "$COUNT_PASSED" ]; then
    {
      echo "passed=$COUNT_PASSED"
      echo "failed=$COUNT_FAILED"
      echo "skipped=$COUNT_SKIPPED"
    } >> "$GITHUB_OUTPUT"
  fi
  # A selection that matches nothing builds, runs no test and exits 0, which a
  # typo in a dispatched class name turns into a PASS. Only a clean exit with a
  # readable bundle that ran no test is changed; a run that failed keeps its
  # own status, and a run that ran anything is untouched.
  #
  # The two shapes of "nothing ran" have different causes. With skips, the
  # selection matched and every test in it abstained, which on a simulator
  # without NLTagger's lexical-class model is skipIfBlind doing its job; only
  # with no skips either is a mistyped class name the likely reading. Both
  # still exit 3, because neither measured anything.
  if [ "$status" = "0" ] && [ -n "$COUNT_PASSED" ] \
    && [ "$COUNT_PASSED" = "0" ] && [ "$COUNT_FAILED" = "0" ]; then
    if [ "${COUNT_SKIPPED:-0}" -gt 0 ] 2>/dev/null; then
      echo "unit-tests.sh: every test in '$ONLY' skipped (0 passed, 0 failed, $COUNT_SKIPPED skipped), so nothing was measured; likely skipIfBlind on a simulator without NLTagger's lexical-class model, not a mistyped class name" >&2
    else
      echo "unit-tests.sh: '$ONLY' ran no test (0 passed, 0 failed, 0 skipped); check the class names" >&2
    fi
    status=3
  fi
  exit $status
fi

# ---------------------------------------------------------------------------
# Sharded: build once, then run the target's test classes across N pool
# simulators at the same time. Classes are packed greedily by their number of
# test methods, so the one class that holds a third of the suite does not end
# up beside the rest of the suite on the same device.
# ---------------------------------------------------------------------------
case "$SHARDS" in
  ''|*[!0-9]*|0) echo "unit-tests.sh: SPEAKIT_SHARDS must be a positive integer" >&2; exit 2 ;;
esac
case "$ONLY" in
  SpeakItTests|SpeakItUITests) ;;
  *) echo "unit-tests.sh: sharding applies to a whole target (SpeakItTests or SpeakItUITests)" >&2; exit 2 ;;
esac

# /bin/bash on macOS is 3.2, which has no mapfile and treats an empty array
# as unbound under set -u, hence the read loops and the ${arr[@]+…} idiom.
DEVICES=()
while IFS= read -r line; do
  [ -n "$line" ] && DEVICES+=("$line")
done < <("$HERE/simulator-pool.sh" "$SHARDS")
if [ "${#DEVICES[@]}" -ne "$SHARDS" ]; then
  echo "unit-tests.sh: simulator-pool.sh produced ${#DEVICES[@]} devices, expected $SHARDS" >&2
  exit 1
fi

# Shard assignment: class name per line, prefixed by its shard index.
ASSIGNMENTS=()
while IFS= read -r line; do
  [ -n "$line" ] && ASSIGNMENTS+=("$line")
done < <(python3 - "$ONLY" "$SHARDS" <<'PY'
import glob, re, sys
target, shards = sys.argv[1], int(sys.argv[2])
declaration = re.compile(r"^\s*(?:@MainActor\s+)?(?:final\s+)?class\s+([A-Za-z0-9_]+)\s*:\s*XCTestCase\b", re.M)
counts = {}
for path in sorted(glob.glob(f"{target}/*.swift")):
    source = open(path).read()
    heads = list(declaration.finditer(source))
    for index, head in enumerate(heads):
        end = heads[index + 1].start() if index + 1 < len(heads) else len(source)
        body = source[head.end():end]
        counts[head.group(1)] = len(re.findall(r"\bfunc\s+test[A-Za-z0-9_]*\s*\(", body))
if not counts:
    sys.exit(f"unit-tests.sh: found no XCTestCase classes under {target}/")
loads = [0] * shards
buckets = [[] for _ in range(shards)]
for name, count in sorted(counts.items(), key=lambda item: (-item[1], item[0])):
    lightest = loads.index(min(loads))
    loads[lightest] += max(count, 1)
    buckets[lightest].append(name)
for index, bucket in enumerate(buckets):
    for name in bucket:
        print(f"{index} {name}")
PY
)

echo "unit-tests.sh: building $ONLY once into $DERIVED_DATA"
xcodebuild build-for-testing -quiet \
  -project SpeakIt.xcodeproj -scheme SpeakIt \
  -destination "platform=iOS Simulator,id=${DEVICES[0]}" \
  -derivedDataPath "$DERIVED_DATA" CODE_SIGNING_ALLOWED=NO

LOG_DIR="$(mktemp -d "${TMPDIR:-/tmp}/speakit-shards.XXXXXX")"
pids=()
for index in $(seq 0 $((SHARDS - 1))); do
  only_args=()
  for assignment in "${ASSIGNMENTS[@]}"; do
    [ "${assignment%% *}" = "$index" ] && only_args+=(-only-testing:"$ONLY/${assignment#* }")
  done
  if [ "${#only_args[@]}" -eq 0 ]; then
    echo "unit-tests.sh: shard $index has no classes (fewer classes than shards); skipping" >&2
    continue
  fi
  bundle_args=()
  if [ -n "$RESULT_BUNDLE" ]; then
    rm -rf "$RESULT_BUNDLE-shard-$index"
    bundle_args=(-resultBundlePath "$RESULT_BUNDLE-shard-$index")
  fi
  echo "unit-tests.sh: shard $index on ${DEVICES[$index]}: ${only_args[*]#-only-testing:}"
  (
    xcodebuild test-without-building -quiet \
      -project SpeakIt.xcodeproj -scheme SpeakIt \
      -destination "platform=iOS Simulator,id=${DEVICES[$index]}" \
      -derivedDataPath "$DERIVED_DATA" \
      "${only_args[@]}" ${bundle_args[@]+"${bundle_args[@]}"} CODE_SIGNING_ALLOWED=NO \
      > "$LOG_DIR/shard-$index.log" 2>&1
  ) &
  pids+=($!)
done

status=0
for pid in ${pids[@]+"${pids[@]}"}; do
  if ! wait "$pid"; then
    status=1
  fi
done

for index in $(seq 0 $((SHARDS - 1))); do
  log="$LOG_DIR/shard-$index.log"
  [ -f "$log" ] || continue
  failures="$(grep -cE "^.*error: .*(failed|XCTAssert)" "$log" || true)"
  echo "unit-tests.sh: shard $index finished; $failures failing assertion line(s); log $log"
  grep -E "error: " "$log" | head -40 || true
  [ -n "$RESULT_BUNDLE" ] && summarize "$ONLY shard $index" "$RESULT_BUNDLE-shard-$index"
done
exit $status
