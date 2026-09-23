#!/bin/bash
# The owner's one Mac run: qualifies every commit listed in
# v1-qualification.tsv and writes one evidence directory and one zip.
#
#   ./Tools/CI/v1-qualification.sh                  # every row of the manifest
#   ./Tools/CI/v1-qualification.sh --only pr117     # one row, by label
#   ./Tools/CI/v1-qualification.sh --dry-run        # print the plan, run nothing
#
# Each row is checked out into its own fresh worktree at the exact commit the
# manifest pins, so the checkout this script runs from is never touched and a
# dirty tree cannot leak into the evidence. Per row it runs, in order:
#
#   compile      build-for-testing: app, extensions, both test bundles
#   gate         Tools/CI/corpus-gate.sh
#   focused      Tools/CI/unit-tests.sh <the row's classes>
#   suite        Tools/CI/unit-tests.sh (the whole unit suite), with a result
#                bundle whose failing test names are written to a file
#   release      Tools/CI/release-build.sh
#   extra        the row's extra command, if any (for example a model run)
#
# Every stage is PASS, FAIL or NOT RUN, and NOT RUN always carries the reason.
# A stage is only NOT RUN when the manifest does not ask for it or a stage it
# needs failed; a failure is never converted into a skip. The gate is known to
# fail on main because of one blocking row, so every row's gate output is kept
# and compared with the baseline row's rather than read as pass or fail alone.
#
# The whole-suite failure list of every row is compared with the row labelled
# `baseline`: a test failing on a row and not on the baseline is listed as NEW,
# and that list, not the raw count, is what decides whether a branch broke
# something. This is how a Mac whose simulator lacks NaturalLanguage assets
# still gives a usable answer.
#
# Environment:
#   DEVELOPER_DIR          Xcode to use (default /Applications/Xcode.app)
#   SPEAKIT_SIMULATOR_ID   simulator UDID (default: see simulator-id.sh)
#   SPEAKIT_EVIDENCE_ROOT  where evidence goes (default ~/SpeakItEvidence)
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
cd "$ROOT" || exit 1

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
MANIFEST="$HERE/v1-qualification.tsv"
ONLY=""
DRY_RUN=0
while [ $# -gt 0 ]; do
  case "$1" in
    --only) ONLY="${2:-}"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    *) echo "v1-qualification.sh: unknown argument $1" >&2; exit 2 ;;
  esac
done

STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
EVIDENCE_ROOT="${SPEAKIT_EVIDENCE_ROOT:-$HOME/SpeakItEvidence}"
EVIDENCE="$EVIDENCE_ROOT/v1-qualification-$STAMP"
SUMMARY="$EVIDENCE/SUMMARY.md"

# Rows: label, commit, focused classes, suite, release, extra.
ROWS=()
while IFS= read -r line; do
  case "$line" in ''|'#'*) continue ;; esac
  label="$(printf '%s' "$line" | cut -f1)"
  if [ -n "$ONLY" ] && [ "$label" != "$ONLY" ] && [ "$label" != "baseline" ]; then
    continue
  fi
  ROWS+=("$line")
done < "$MANIFEST"
if [ "${#ROWS[@]}" -eq 0 ]; then
  echo "v1-qualification.sh: no manifest rows selected" >&2
  exit 2
fi

if [ "$DRY_RUN" = "1" ]; then
  echo "Plan (nothing will run):"
  for row in "${ROWS[@]}"; do
    printf '  %s\n' "$(printf '%s' "$row" | tr '\t' '|')"
  done
  exit 0
fi

mkdir -p "$EVIDENCE"
echo "v1-qualification: evidence in $EVIDENCE"

# --- Identity of the machine and the checkout this ran from ----------------
{
  echo "# V1 qualification run $STAMP"
  echo
  echo "| | |"
  echo "|---|---|"
  echo "| script commit | \`$(git rev-parse HEAD)\` |"
  echo "| script checkout clean | $([ -z "$(git status --porcelain)" ] && echo yes || echo NO) |"
  echo "| Xcode | $(xcodebuild -version 2>/dev/null | tr '\n' ' ') |"
  echo "| iOS SDK | $(xcrun --sdk iphonesimulator --show-sdk-version 2>/dev/null) |"
  echo "| macOS | $(sw_vers -productVersion 2>/dev/null) ($(uname -m)) |"
} > "$SUMMARY"

if ! git fetch --quiet origin; then
  echo "v1-qualification.sh: git fetch failed; rows whose commit is missing will FAIL" >&2
fi

SIMULATOR="$("$HERE/simulator-id.sh")" || {
  echo "v1-qualification.sh: no simulator available" >&2
  exit 1
}
export SPEAKIT_SIMULATOR_ID="$SIMULATOR"
echo "| simulator | $(xcrun simctl list devices | grep "$SIMULATOR" | sed 's/^ *//' | head -1) |" >> "$SUMMARY"
echo >> "$SUMMARY"

# Runs one stage. Arguments: row dir, stage name, then the command.
# Records the command, the exit status and the log, and prints PASS or FAIL.
run_stage() {
  local dir="$1" stage="$2"
  shift 2
  local log="$dir/$stage.log"
  echo "  $stage: $*" >&2
  {
    echo "\$ $*"
    echo "started $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  } > "$log"
  local status=0
  "$@" >> "$log" 2>&1 || status=$?
  echo "finished $(date -u +%Y-%m-%dT%H:%M:%SZ) exit $status" >> "$log"
  echo "$status" > "$dir/$stage.status"
  if [ "$status" = "0" ]; then echo "PASS"; else echo "FAIL (exit $status)"; fi
}

not_run() {
  local dir="$1" stage="$2" reason="$3"
  echo "NOT RUN: $reason" > "$dir/$stage.status"
  echo "NOT RUN ($reason)"
}

# The compile, run inside a row's tree. Inline rather than Tools/CI/compile.sh
# because the commits being qualified may predate that script, and running
# this checkout's copy would compile this checkout instead of the row.
compile_here() {
  xcodebuild build-for-testing -quiet \
    -project SpeakIt.xcodeproj -scheme SpeakIt \
    -destination "platform=iOS Simulator,id=$SPEAKIT_SIMULATOR_ID" \
    -derivedDataPath "$SPEAKIT_DERIVED_DATA" \
    CODE_SIGNING_ALLOWED=NO
}

# Failing test identifiers from a result bundle, one per line, sorted.
failing_tests() {
  local bundle="$1" out="$2"
  local json
  json="$(mktemp)"
  if xcrun xcresulttool get test-results summary --path "$bundle" --format json > "$json" 2>/dev/null; then
    python3 - "$json" > "$out" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
names = sorted({f.get("testIdentifierString") or f.get("testName", "?")
                for f in data.get("testFailures", [])})
print("\n".join(names))
PY
    python3 - "$json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
print(f"passed {d.get('passedTests', '?')} failed {d.get('failedTests', '?')} "
      f"skipped {d.get('skippedTests', '?')}")
PY
  else
    echo "no readable result bundle" > "$out"
    echo "no readable result bundle"
  fi
  rm -f "$json"
}

ENV_RESULT="NOT RUN (baseline row missing or did not compile)"
echo "| row | commit | compile | gate | focused | suite | release | extra |" >> "$SUMMARY"
echo "|---|---|---|---|---|---|---|---|" >> "$SUMMARY"

for row in "${ROWS[@]}"; do
  label="$(printf '%s' "$row" | cut -f1)"
  commit="$(printf '%s' "$row" | cut -f2)"
  focused="$(printf '%s' "$row" | cut -f3)"
  suite="$(printf '%s' "$row" | cut -f4)"
  release="$(printf '%s' "$row" | cut -f5)"
  extra="$(printf '%s' "$row" | cut -f6)"
  dir="$EVIDENCE/$label"
  tree="$EVIDENCE_ROOT/trees/$label-$STAMP"
  mkdir -p "$dir"
  echo "row $label at $commit"

  compile_r="NOT RUN"; gate_r="NOT RUN"; focused_r="NOT RUN"; suite_r="NOT RUN"
  release_r="NOT RUN"; extra_r="NOT RUN"

  if ! git worktree add --quiet --detach "$tree" "$commit" > "$dir/checkout.log" 2>&1; then
    compile_r="FAIL (commit $commit not checkoutable; see checkout.log)"
    echo "| $label | \`$commit\` | $compile_r | | | | | |" >> "$SUMMARY"
    continue
  fi
  (
    cd "$tree" || exit 1
    echo "commit $(git rev-parse HEAD)"
    echo "clean $([ -z "$(git status --porcelain)" ] && echo yes || echo NO)"
  ) > "$dir/identity.txt"

  export SPEAKIT_DERIVED_DATA="/tmp/SpeakItQualification/$label/DerivedData"
  export SPEAKIT_RELEASE_DERIVED_DATA="/tmp/SpeakItQualification/$label/DerivedDataRelease"

  compile_r="$(cd "$tree" && run_stage "$dir" compile compile_here)"
  gate_r="$(cd "$tree" && run_stage "$dir" gate env CORPUS_GATE_FULL=1 Tools/CI/corpus-gate.sh)"

  # Whether this simulator's NLTagger has a lexical-class model decides how
  # every tagger-dependent failure is read, so it is asked directly, once, on
  # the baseline tree, and its readout kept rather than inferred from a count.
  if [ "$label" = "baseline" ] && [[ "$compile_r" == PASS* ]]; then
    ENV_RESULT="$(cd "$tree" && run_stage "$dir" natural-language Tools/CI/unit-tests.sh SpeakItTests/NaturalLanguageEnvironmentTests)"
  fi

  if [ "$focused" = "-" ] || [ -z "$focused" ]; then
    focused_r="$(not_run "$dir" focused "none listed")"
  elif [[ "$compile_r" != PASS* ]]; then
    focused_r="$(not_run "$dir" focused "compile failed")"
  else
    focused_r="$(cd "$tree" && run_stage "$dir" focused Tools/CI/unit-tests.sh "$focused")"
  fi

  if [ "$suite" != "yes" ]; then
    suite_r="$(not_run "$dir" suite "not requested for this row")"
  elif [[ "$compile_r" != PASS* ]]; then
    suite_r="$(not_run "$dir" suite "compile failed")"
  else
    bundle="/tmp/SpeakItQualification/$label/suite.xcresult"
    rm -rf "$bundle"
    suite_r="$(cd "$tree" && run_stage "$dir" suite env SPEAKIT_RESULT_BUNDLE="$bundle" Tools/CI/unit-tests.sh SpeakItTests)"
    counts="$(failing_tests "$bundle" "$dir/suite-failures.txt")"
    suite_r="$suite_r; $counts"
  fi

  if [ "$release" = "yes" ]; then
    release_r="$(cd "$tree" && run_stage "$dir" release Tools/CI/release-build.sh)"
  else
    release_r="$(not_run "$dir" release "not requested for this row")"
  fi

  if [ "$extra" = "-" ] || [ -z "$extra" ]; then
    extra_r="$(not_run "$dir" extra "none listed")"
  else
    extra_r="$(cd "$tree" && run_stage "$dir" extra /bin/bash -c "$extra")"
  fi

  echo "| $label | \`$commit\` | $compile_r | $gate_r | $focused_r | $suite_r | $release_r | $extra_r |" >> "$SUMMARY"
  git worktree remove --force "$tree" > /dev/null 2>&1 || true
done

{
  echo
  echo "NaturalLanguage readout (baseline tree, \`NaturalLanguageEnvironmentTests\`): $ENV_RESULT. A failure here with every token read as OtherWord means this simulator has no lexical-class model; see baseline/natural-language.log."
} >> "$SUMMARY"

# --- New failures against the baseline row --------------------------------
if [ -f "$EVIDENCE/baseline/suite-failures.txt" ]; then
  {
    echo
    echo "## Whole-suite failures against the baseline row"
    echo
  } >> "$SUMMARY"
  for row in "${ROWS[@]}"; do
    label="$(printf '%s' "$row" | cut -f1)"
    [ "$label" = "baseline" ] && continue
    file="$EVIDENCE/$label/suite-failures.txt"
    [ -f "$file" ] || continue
    new="$(comm -13 "$EVIDENCE/baseline/suite-failures.txt" "$file" | grep -v '^$' || true)"
    fixed="$(comm -23 "$EVIDENCE/baseline/suite-failures.txt" "$file" | grep -v '^$' || true)"
    {
      echo "### $label"
      echo
      echo "NEW (fail here, pass on baseline): $(printf '%s' "$new" | grep -c . || true)"
      [ -n "$new" ] && printf '%s\n' "$new" | sed 's/^/- /'
      echo
      echo "no longer failing: $(printf '%s' "$fixed" | grep -c . || true)"
      [ -n "$fixed" ] && printf '%s\n' "$fixed" | sed 's/^/- /'
      echo
    } >> "$SUMMARY"
  done
fi

ZIP="$EVIDENCE_ROOT/v1-qualification-$STAMP.zip"
(cd "$EVIDENCE_ROOT" && zip -qr "$ZIP" "v1-qualification-$STAMP") || true
echo
cat "$SUMMARY"
echo
echo "Evidence: $EVIDENCE"
echo "Upload this one file to the project: $ZIP"
