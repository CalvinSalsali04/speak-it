#!/bin/bash
# The owner's one Mac run: qualifies every commit listed in
# v1-qualification.tsv and writes one evidence directory and one zip.
#
#   ./Tools/CI/v1-qualification.sh                  # every row of the manifest
#   ./Tools/CI/v1-qualification.sh --only rc        # one row, by label, plus baseline
#   ./Tools/CI/v1-qualification.sh --dry-run        # print the plan, run nothing
#   ./Tools/CI/v1-qualification.sh --check-pins     # is every pin its branch's tip? run nothing else
#
# Run --check-pins before the Mac session. Each row names the branch its pin is
# meant to be the tip of; the check fetches origin and exits 1 when any pin is
# behind that tip, off that branch, or unresolvable (or when the fetch fails,
# since it would then be checking stale refs), 0 only when every pin is its
# branch's tip. A full run makes the same check, records it in each row's
# identity.txt with every branch containing the pin, and puts a STALE PIN line
# in SUMMARY.md for each row whose pin is not its branch's tip, so evidence
# about a commit a branch has moved past says so itself. Only the manifest's
# rows are checked: a commit an extra command checks out for itself (the rc
# row's probes check out up to four fixed historical commits) is not a row and is not
# compared with anything.
#
# Each row is checked out into its own fresh worktree at the exact commit the
# manifest pins, so the checkout this script runs from is never touched and a
# dirty tree cannot leak into the evidence. Per row it runs, in order:
#
#   compile      build-for-testing: app, extensions, both test bundles
#   gate         Tools/CI/corpus-gate.sh, every blocking row printed
#   focused      Tools/CI/unit-tests.sh <the row's classes>, with a result
#                bundle kept in the evidence directory, so the cell carries
#                passed/failed/skipped (a skip shows as a skip) and the test's
#                console output can be read afterwards
#   suite        Tools/CI/unit-tests.sh (the whole unit suite), with a result
#                bundle whose failing test identifiers are written to a file
#   release      Tools/CI/release-build.sh. Not gated on the compile: it is
#                its own build (Release, generic device), so it answers its own
#                question even when the simulator compile failed
#   extra        the row's extra command, if any (for example a model run),
#                run with QUALIFICATION_ROW_DIR set to the row's evidence
#                directory so it can write its results there, and
#                QUALIFICATION_CHECKOUT set to this checkout, so it can reach
#                inputs and helpers the pinned tree predates (the rc row's
#                probes: Tools/CI/v1-probes.sh). Anything the
#                command leaves under the tree's output/ is copied there too,
#                because the tree is removed when the row finishes. Not gated
#                on the compile either: it is the row's own command and builds
#                what it needs
#
# Every stage is PASS, FAIL or NOT RUN, and NOT RUN always carries the reason.
# A stage is only NOT RUN when the manifest does not ask for it or a stage it
# needs failed; a failure is never converted into a skip.
#
# Each row is then compared with the row labelled `baseline`, twice:
#
#   suite  a test failing on a row and not on the baseline is NEW, and that
#          list, not the raw count, decides whether a branch broke something.
#          This is how a Mac whose simulator lacks NaturalLanguage assets still
#          gives a usable answer. The list is only a verdict when it measured
#          something: both suites ran, both bundles were read, failures are
#          keyed by `testIdentifierString` (Class/method), and the row ran at
#          least as many tests as the baseline plus the test methods the row's
#          source adds. Otherwise the row says NOT MEASURED or INCOMPLETE, and
#          never "NEW: 0".
#   gate   the gate's blocking rows (severity, field, utterance) are diffed the
#          same way. The gate fails on main because of one known blocking row,
#          so pass or fail alone says nothing; the NEW blocking rows do.
#
# What neither diff can see: a test (or corpus row) that already fails on the
# baseline and fails on a row for a different reason. The diff is on names,
# not on failure messages.
#
# Exit status: 0 when every stage passed and every comparison was measured;
# 1 when any stage failed (expected on a Mac whose simulator is blind, and on
# main while the known gate row fails); 4 when any comparison was NOT MEASURED
# or INCOMPLETE; 2 for a usage error. SUMMARY.md is the answer either way.
#
# Environment:
#   DEVELOPER_DIR               Xcode to use (default /Applications/Xcode.app)
#   SPEAKIT_SIMULATOR_ID        simulator UDID (default: see simulator-id.sh)
#   SPEAKIT_EVIDENCE_ROOT       where evidence goes (default ~/SpeakItEvidence)
#   SPEAKIT_QUALIFICATION_WORK  derived data and suite bundles, one directory
#                               per label and commit (default /tmp/SpeakItQualification)
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
cd "$ROOT" || exit 1

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
MANIFEST="$HERE/v1-qualification.tsv"
ONLY=""
DRY_RUN=0
CHECK_PINS=0
while [ $# -gt 0 ]; do
  case "$1" in
    --only)
      if [ $# -lt 2 ] || [ -z "$2" ]; then
        echo "v1-qualification.sh: --only needs a label" >&2
        exit 2
      fi
      ONLY="$2"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    --check-pins) CHECK_PINS=1; shift ;;
    *) echo "v1-qualification.sh: unknown argument $1" >&2; exit 2 ;;
  esac
done

# Rows: label, commit, branch, focused classes, suite, release, extra.
ROWS=()
LABELS=""
HAS_BASELINE=0
while IFS= read -r line; do
  case "$line" in ''|'#'*) continue ;; esac
  fields="$(printf '%s' "$line" | awk -F'\t' '{print NF}')"
  if [ "$fields" != "7" ]; then
    echo "v1-qualification.sh: manifest row has $fields tab-separated fields, not 7: $line" >&2
    exit 2
  fi
  label="$(printf '%s' "$line" | cut -f1)"
  LABELS="$LABELS $label"
  [ "$label" = "baseline" ] && HAS_BASELINE=1
  if [ -n "$ONLY" ] && [ "$label" != "$ONLY" ] && [ "$label" != "baseline" ]; then
    continue
  fi
  ROWS+=("$line")
done < "$MANIFEST"
if [ "$HAS_BASELINE" != "1" ]; then
  echo "v1-qualification.sh: the manifest has no row labelled baseline" >&2
  exit 2
fi
# The baseline row is always selected, so a mistyped label would otherwise run
# the baseline alone and look like a clean run that qualified nothing.
if [ -n "$ONLY" ] && ! printf '%s\n' "$LABELS" | tr ' ' '\n' | grep -qxF -- "$ONLY"; then
  echo "v1-qualification.sh: no manifest row is labelled '$ONLY'. Labels:$LABELS" >&2
  exit 2
fi

# --- Pins against their branches ------------------------------------------
fetch_origin() {
  git fetch --quiet origin
}

# Prints "STATE TIP BEHIND" for a pin and the branch it is meant to be the tip
# of. STATE is one of:
#   TIP         the pin is the branch's tip
#   STALE       the branch contains the pin and has moved BEHIND commits past it
#   OFF-BRANCH  the branch no longer contains the pin (rewritten, or the wrong
#               branch is named)
#   NO-BRANCH   origin has no such branch
#   NO-COMMIT   the pin does not resolve to a commit here
# TIP and BEHIND are "-" where they do not apply.
pin_state() {
  local commit="$1" branch="$2" full tip
  if ! full="$(git rev-parse --quiet --verify "$commit^{commit}" 2>/dev/null)"; then
    echo "NO-COMMIT - -"; return
  fi
  if ! tip="$(git rev-parse --quiet --verify "refs/remotes/origin/$branch^{commit}" 2>/dev/null)"; then
    echo "NO-BRANCH - -"; return
  fi
  if [ "$full" = "$tip" ]; then
    echo "TIP $tip 0"
  elif git merge-base --is-ancestor "$full" "$tip"; then
    echo "STALE $tip $(git rev-list --count "$full..$tip")"
  else
    echo "OFF-BRANCH $tip -"
  fi
}

# One sentence about a row's pin, loud unless the pin is its branch's tip.
pin_sentence() {
  local label="$1" commit="$2" branch="$3" state="$4" tip="$5" behind="$6"
  local short="${commit:0:7}"
  case "$state" in
    TIP) echo "$label: \`$short\` is the tip of origin/$branch." ;;
    STALE) echo "**STALE PIN: $label pins \`$short\`, $behind commit(s) behind the tip of origin/$branch (\`${tip:0:7}\`).** This row's evidence is about a commit its branch has moved past." ;;
    OFF-BRANCH) echo "**STALE PIN: $label pins \`$short\`, which origin/$branch (tip \`${tip:0:7}\`) no longer contains.** The branch was rewritten or the manifest names the wrong one." ;;
    NO-BRANCH) echo "**STALE PIN: $label names origin/$branch, which does not exist.** Nothing says whether \`$short\` is current." ;;
    *) echo "**STALE PIN: $label pins \`$short\`, which does not resolve to a commit here.**" ;;
  esac
}

if [ "$CHECK_PINS" = "1" ]; then
  fetched=1
  if ! fetch_origin; then
    fetched=0
    echo "v1-qualification.sh: git fetch origin failed; the lines below compare with local refs that may be stale" >&2
  fi
  stale=0
  for row in "${ROWS[@]}"; do
    label="$(printf '%s' "$row" | cut -f1)"
    commit="$(printf '%s' "$row" | cut -f2)"
    branch="$(printf '%s' "$row" | cut -f3)"
    read -r state tip behind <<< "$(pin_state "$commit" "$branch")"
    [ "$state" = "TIP" ] || stale=$((stale + 1))
    printf '%-10s %s\n' "$state" "$(pin_sentence "$label" "$commit" "$branch" "$state" "$tip" "$behind" | tr -d '*')"
  done
  if [ "$stale" != "0" ]; then
    echo "v1-qualification.sh: $stale pin(s) are not their branch's tip; repin Tools/CI/v1-qualification.tsv (and the handoff's commit list) before the run" >&2
    exit 1
  fi
  if [ "$fetched" = "0" ]; then
    echo "v1-qualification.sh: every pin matched, but only against refs the failed fetch did not refresh; not vouching for them" >&2
    exit 1
  fi
  echo "Every pin is its branch's tip."
  exit 0
fi

if [ "$DRY_RUN" = "1" ]; then
  echo "Plan (nothing will run):"
  for row in "${ROWS[@]}"; do
    printf '  %s\n' "$(printf '%s' "$row" | tr '\t' '|')"
  done
  exit 0
fi

STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
EVIDENCE_ROOT="${SPEAKIT_EVIDENCE_ROOT:-$HOME/SpeakItEvidence}"
EVIDENCE="$EVIDENCE_ROOT/v1-qualification-$STAMP"
SUMMARY="$EVIDENCE/SUMMARY.md"
WORK="${SPEAKIT_QUALIFICATION_WORK:-/tmp/SpeakItQualification}"

mkdir -p "$EVIDENCE"
echo "v1-qualification: evidence in $EVIDENCE"

# --- Helpers written once, read by every row -------------------------------
PY="$(mktemp -d "${TMPDIR:-/tmp}/v1-qualification-py.XXXXXX")"
trap 'rm -rf "$PY"' EXIT

# Reads an `xcresulttool get test-results summary` JSON. Writes <prefix>-counts.txt
# ("passed failed skipped expectedFailures total"), <prefix>-failures.txt (one
# failing test identifier per line, code-point sorted) and <prefix>-key.txt.
# Writes nothing unless everything was read: a partial read must never look
# like zero failures. Exit 3 means the identifier key is missing.
cat > "$PY/extract.py" <<'PY'
import json, os, sys
path, prefix = sys.argv[1], sys.argv[2]
data = json.load(open(path))
counts = {}
for key in ("passedTests", "failedTests", "skippedTests"):
    value = data.get(key)
    if not isinstance(value, int):
        sys.exit(f"summary has no integer {key} (got {value!r})")
    counts[key] = value
expected = data.get("expectedFailures", 0)
if not isinstance(expected, int):
    expected = 0
failures = data.get("testFailures")
if not isinstance(failures, list):
    sys.exit(f"summary has no testFailures list (got {type(failures).__name__})")
# Keyed on Class/method, never the bare method name: two classes with a
# same-named method would otherwise mask each other, and every unnamed failure
# would collapse into one line.
KEY = "testIdentifierString"
names = set()
for failure in failures:
    if not isinstance(failure, dict):
        sys.exit(f"a testFailures entry is not an object: {failure!r}")
    ident = failure.get(KEY)
    if not isinstance(ident, str) or not ident:
        # The keys it does have, so if a new xcresulttool names the field
        # differently the evidence already holds the fact the fix needs.
        print(f"a failure has no {KEY} (testName {failure.get('testName')!r}; "
              f"its keys are {sorted(failure.keys())}); "
              "refusing to diff on bare method names", file=sys.stderr)
        sys.exit(3)
    names.add(ident)
if counts["failedTests"] > 0 and not names:
    sys.exit(f"summary reports {counts['failedTests']} failed tests and lists none")
total = counts["passedTests"] + counts["failedTests"] + counts["skippedTests"] + expected
def write(suffix, text):
    tmp = f"{prefix}-{suffix}.tmp"
    with open(tmp, "w") as handle:
        handle.write(text)
    return tmp
tmps = [
    (write("counts", f"{counts['passedTests']} {counts['failedTests']} "
                     f"{counts['skippedTests']} {expected} {total}\n"), f"{prefix}-counts.txt"),
    (write("failures", "".join(n + "\n" for n in sorted(names))), f"{prefix}-failures.txt"),
    (write("key", KEY + "\n"), f"{prefix}-key.txt"),
]
for tmp, final in tmps:
    os.replace(tmp, final)
PY

# Reads a corpus gate log. Writes <out> with one line per distinct blocking
# disagreement, "[SEVERITY] field: "utterance"", code-point sorted, and prints
# "<distinct> <reported>". Fails unless the rows it read add up to the
# BLOCKING total the gate reported, so a truncated list cannot pass as a
# short one.
cat > "$PY/gate.py" <<'PY'
import re, sys
log, out = sys.argv[1], sys.argv[2]
lines = open(log, encoding="utf-8", errors="replace").read().splitlines()
totals = {int(m.group(1)) for l in lines for m in [re.search(r"BLOCKING\(crit\+beh\) = (\d+)", l)] if m}
if not totals:
    sys.exit("no 'BLOCKING(crit+beh) = N' line in the gate log (did the gate reach the corpus run?)")
if len(totals) != 1:
    sys.exit(f"the gate log reports different BLOCKING totals: {sorted(totals)}")
reported = totals.pop()
head = re.compile(r'^  \[(CRITICAL|BEHAVIORAL)\] "(.*)"$')
field = re.compile(r"^    (.+?): expected ")
rows, seen = [], 0
for i, line in enumerate(lines):
    m = head.match(line)
    if not m:
        continue
    seen += 1
    f = field.match(lines[i + 1]) if i + 1 < len(lines) else None
    if not f:
        sys.exit(f"blocking row without a field line after it: {line!r}")
    rows.append(f'[{m.group(1)}] {f.group(1)}: "{m.group(2)}"')
if seen != reported:
    sys.exit(f"the gate reports BLOCKING = {reported} but its log lists {seen} blocking rows "
             "(truncated or reformatted output)")
distinct = sorted(set(rows))
with open(out, "w") as handle:
    handle.write("".join(r + "\n" for r in distinct))
print(len(distinct), reported)
PY

# Pulls the text out of `xcresulttool get log --type console` JSON. The item
# schema is not documented where this was written, so it takes every string
# under a "content" key if there are any, and otherwise every string.
cat > "$PY/console.py" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
content, everything = [], []
def walk(node, key=None):
    if isinstance(node, dict):
        for k, v in node.items():
            walk(v, k)
    elif isinstance(node, list):
        for v in node:
            walk(v, key)
    elif isinstance(node, str):
        everything.append(node)
        if key == "content":
            content.append(node)
items = data.get("items") if isinstance(data, dict) else None
walk(data)
chosen = content or everything
print(f"# {len(items) if isinstance(items, list) else '?'} items; "
      f"{len(chosen)} strings from {'content keys' if content else 'every string'}")
for text in chosen:
    print(text.rstrip("\n"))
PY

# Test methods the tree's unit-test sources declare. Only differences between
# two trees are used, so helpers that happen to be named test… cancel out.
cat > "$PY/declared.py" <<'PY'
import glob, re, sys
pattern = re.compile(r"\bfunc\s+test[A-Za-z0-9_]*\s*\(")
paths = sorted(glob.glob(f"{sys.argv[1]}/SpeakItTests/*.swift"))
if not paths:
    sys.exit("no SpeakItTests/*.swift in the tree")
print(sum(len(pattern.findall(open(p, encoding="utf-8").read())) for p in paths))
PY

# --- Identity of the machine and the checkout this ran from ----------------
{
  echo "# V1 qualification run $STAMP"
  echo
  echo "| | |"
  echo "|---|---|"
  echo "| script commit | \`$(git rev-parse HEAD)\` |"
  echo "| script checkout clean | $([ -z "$(git status --porcelain)" ] && echo yes || echo NO) |"
  echo "| Xcode | $(xcodebuild -version 2>/dev/null | tr '\n' ' ') |"
  echo "| xcresulttool | $(xcrun xcresulttool version 2>/dev/null | head -1) |"
  echo "| iOS SDK | $(xcrun --sdk iphonesimulator --show-sdk-version 2>/dev/null) |"
  echo "| macOS | $(sw_vers -productVersion 2>/dev/null) ($(uname -m)) |"
} > "$SUMMARY"

FETCHED=1
if ! fetch_origin; then
  FETCHED=0
  echo "v1-qualification.sh: git fetch failed; rows whose commit is missing will FAIL" >&2
fi

SIMULATOR="$("$HERE/simulator-id.sh")" || {
  echo "v1-qualification.sh: no simulator available" >&2
  exit 1
}
export SPEAKIT_SIMULATOR_ID="$SIMULATOR"
echo "| simulator | $(xcrun simctl list devices | grep "$SIMULATOR" | sed 's/^ *//' | head -1) |" >> "$SUMMARY"
echo >> "$SUMMARY"

# Each pin against the branch the manifest says it is the tip of, measured
# after the fetch above and before anything runs, so a branch that moves
# during the run does not change the answer.
STALE_PINS=""
{
  echo "## Pins"
  echo
  [ "$FETCHED" = "1" ] || echo "**git fetch origin failed: these compare with local refs that may themselves be stale.**"
  [ "$FETCHED" = "1" ] || echo
} >> "$SUMMARY"
for row in "${ROWS[@]}"; do
  label="$(printf '%s' "$row" | cut -f1)"
  commit="$(printf '%s' "$row" | cut -f2)"
  branch="$(printf '%s' "$row" | cut -f3)"
  read -r state tip behind <<< "$(pin_state "$commit" "$branch")"
  if [ "$state" != "TIP" ]; then
    STALE_PINS="$STALE_PINS $label"
    echo "v1-qualification.sh: $(pin_sentence "$label" "$commit" "$branch" "$state" "$tip" "$behind" | tr -d '*\`')" >&2
  fi
  echo "- $(pin_sentence "$label" "$commit" "$branch" "$state" "$tip" "$behind")" >> "$SUMMARY"
done
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
# shellcheck disable=SC2329  # invoked indirectly, as run_stage's command
compile_here() {
  xcodebuild build-for-testing -quiet \
    -project SpeakIt.xcodeproj -scheme SpeakIt \
    -destination "platform=iOS Simulator,id=$SPEAKIT_SIMULATOR_ID" \
    -derivedDataPath "$SPEAKIT_DERIVED_DATA" \
    CODE_SIGNING_ALLOWED=NO
}

# Reads a test stage's result bundle into <dir>/<stem>-counts.txt,
# <stem>-failures.txt and <stem>-key.txt, keeping the raw summary JSON. When
# anything cannot be read it writes <stem>.notmeasured with the reason instead,
# and leaves none of the three, so nothing downstream can read "no failures".
read_bundle() {
  local bundle="$1" dir="$2" stem="$3"
  rm -f "$dir/$stem-counts.txt" "$dir/$stem-failures.txt" "$dir/$stem-key.txt" "$dir/$stem.notmeasured"
  if [ ! -d "$bundle" ]; then
    echo "no result bundle at $bundle" > "$dir/$stem.notmeasured"
    return
  fi
  if ! xcrun xcresulttool get test-results summary --path "$bundle" --format json \
      > "$dir/$stem-summary.json" 2> "$dir/$stem-xcresulttool.err"; then
    echo "xcresulttool could not read the result bundle; see $stem-xcresulttool.err" > "$dir/$stem.notmeasured"
    return
  fi
  local status=0
  python3 "$PY/extract.py" "$dir/$stem-summary.json" "$dir/$stem" 2> "$dir/$stem-extract.err" || status=$?
  if [ "$status" = "3" ]; then
    echo "the summary has no testIdentifierString on a failure, so failures cannot be told apart by class ($(tail -n 1 "$dir/$stem-extract.err")); see $stem-extract.err" > "$dir/$stem.notmeasured"
  elif [ "$status" != "0" ]; then
    echo "reading the summary failed (python exit $status): $(tail -n 1 "$dir/$stem-extract.err"); see $stem-extract.err" > "$dir/$stem.notmeasured"
  else
    rm -f "$dir/$stem-extract.err"
  fi
  [ -s "$dir/$stem-xcresulttool.err" ] || rm -f "$dir/$stem-xcresulttool.err"
}

# What a test cell says after its stage verdict.
counts_cell() {
  local dir="$1" stem="$2" passed failed skipped expected total
  if [ -f "$dir/$stem.notmeasured" ]; then
    echo "NOT MEASURED: $(cat "$dir/$stem.notmeasured")"
    return
  fi
  read -r passed failed skipped expected total < "$dir/$stem-counts.txt"
  local cell="passed $passed failed $failed skipped $skipped"
  [ "$expected" != "0" ] && cell="$cell expected-failures $expected"
  if [ "$passed" = "0" ] && [ "$failed" = "0" ]; then
    cell="$cell; RAN NO TEST"
    echo "ran no test" > "$dir/$stem.ranempty"
  fi
  echo "$cell"
}

# The test's printed output, from the bundle, because `xcodebuild -quiet`
# does not put it in the stage log. UNVERIFIED on a real bundle: `get log
# --type console` is in xcresulttool's manual for Xcode 16 and later, but its
# item schema is not documented, and a bundle whose console section is empty
# returns no items rather than an error. The file says which happened, so an
# empty grep is never the only evidence. The bundle stays beside it.
read_console() {
  local bundle="$1" dir="$2" stem="$3"
  local out="$dir/$stem-console.txt" json="$dir/$stem-console.json"
  if [ ! -d "$bundle" ]; then
    echo "# no result bundle, so no console output" > "$out"
    return
  fi
  if ! xcrun xcresulttool get log --type console --path "$bundle" --compact > "$json" 2> "$dir/$stem-console.err"; then
    {
      echo "# xcresulttool get log --type console failed: $(tail -n 1 "$dir/$stem-console.err")"
      echo "# The output is still in $stem.xcresult: open it in Xcode and read the test's console output."
    } > "$out"
    return
  fi
  if ! python3 "$PY/console.py" "$json" > "$out" 2> "$dir/$stem-console.err"; then
    {
      echo "# the console JSON could not be read: $(tail -n 1 "$dir/$stem-console.err")"
      echo "# Raw JSON: $stem-console.json. Bundle: $stem.xcresult."
    } > "$out"
  fi
  [ -s "$dir/$stem-console.err" ] || rm -f "$dir/$stem-console.err"
}

ENV_RESULT="NOT RUN (baseline row missing or did not compile)"
echo "| row | commit | compile | gate | focused | suite | release | extra |" >> "$SUMMARY"
echo "|---|---|---|---|---|---|---|---|" >> "$SUMMARY"

for row in "${ROWS[@]}"; do
  label="$(printf '%s' "$row" | cut -f1)"
  commit="$(printf '%s' "$row" | cut -f2)"
  branch="$(printf '%s' "$row" | cut -f3)"
  focused="$(printf '%s' "$row" | cut -f4)"
  suite="$(printf '%s' "$row" | cut -f5)"
  release="$(printf '%s' "$row" | cut -f6)"
  extra="$(printf '%s' "$row" | cut -f7)"
  dir="$EVIDENCE/$label"
  tree="$EVIDENCE_ROOT/trees/$label-$STAMP"
  mkdir -p "$dir"
  echo "row $label at $commit"

  # The pin against its branch, and every branch that contains it with how far
  # each has moved past it, written before the checkout so a row that fails
  # to check out still says what it was pinned to.
  read -r pin_st pin_tip pin_behind <<< "$(pin_state "$commit" "$branch")"
  commit_cell="\`$commit\`"
  case "$pin_st" in
    TIP) ;;
    STALE) commit_cell="$commit_cell **STALE: $pin_behind behind origin/$branch**" ;;
    *) commit_cell="$commit_cell **STALE: $pin_st for origin/$branch**" ;;
  esac
  {
    echo "pin $commit"
    echo "branch origin/$branch"
    echo "branch tip $pin_tip"
    echo "pin state $pin_st"
    echo "commits the branch tip has beyond the pin $pin_behind"
    echo "containing branches (git branch -r --contains), each with the commits it has beyond the pin:"
    git branch -r --contains "$commit" 2>/dev/null | sed 's/^[* ]*//' | grep -v ' -> ' \
      | while IFS= read -r containing; do
          echo "  $containing $(git rev-list --count "$commit..$containing" 2>/dev/null || echo '?')"
        done
  } > "$dir/identity.txt"

  if ! git worktree add --quiet --detach "$tree" "$commit" > "$dir/checkout.log" 2>&1; then
    echo "commit $commit could not be checked out; see $label/checkout.log" > "$dir/checkout.failed"
    why="NOT RUN (checkout failed)"
    echo "| $label | $commit_cell | FAIL (commit not checkoutable; see checkout.log) | $why | $why | $why | $why | $why |" >> "$SUMMARY"
    continue
  fi
  (
    cd "$tree" || exit 1
    echo "commit $(git rev-parse HEAD)"
    echo "clean $([ -z "$(git status --porcelain)" ] && echo yes || echo NO)"
  ) >> "$dir/identity.txt"
  python3 "$PY/declared.py" "$tree" > "$dir/declared-tests.txt" 2> "$dir/declared-tests.err" \
    || rm -f "$dir/declared-tests.txt"
  [ -s "$dir/declared-tests.err" ] || rm -f "$dir/declared-tests.err"

  # Keyed by label and commit, so a repinned label never builds on top of the
  # previous commit's derived data.
  row_work="$WORK/$label-$(git rev-parse --short=12 "$commit")"
  export SPEAKIT_DERIVED_DATA="$row_work/DerivedData"
  export SPEAKIT_RELEASE_DERIVED_DATA="$row_work/DerivedDataRelease"

  compile_r="$(cd "$tree" && run_stage "$dir" compile compile_here)"
  # Every blocking row printed, however many, so the gate can be diffed.
  gate_r="$(cd "$tree" && run_stage "$dir" gate env CORPUS_GATE_FULL=1 CORPUS_GATE_FAILURE_LINES=1000000 Tools/CI/corpus-gate.sh)"
  if python3 "$PY/gate.py" "$dir/gate.log" "$dir/gate-blocking.txt" > "$dir/gate-blocking.count" 2> "$dir/gate-blocking.err"; then
    read -r _ reported < "$dir/gate-blocking.count"
    gate_r="$gate_r; blocking $reported"
    rm -f "$dir/gate-blocking.err"
  else
    rm -f "$dir/gate-blocking.txt" "$dir/gate-blocking.count"
    gate_r="$gate_r; blocking rows NOT MEASURED"
  fi

  # Whether this simulator's NLTagger has a lexical-class model decides how
  # every tagger-dependent failure is read, so it is asked directly, once, on
  # the baseline tree, and its readout kept rather than inferred from a count.
  if [ "$label" = "baseline" ] && [[ "$compile_r" == PASS* ]]; then
    ENV_RESULT="$(cd "$tree" && run_stage "$dir" natural-language env SPEAKIT_RESULT_BUNDLE="$dir/natural-language.xcresult" Tools/CI/unit-tests.sh SpeakItTests/NaturalLanguageEnvironmentTests)"
    read_bundle "$dir/natural-language.xcresult" "$dir" natural-language
    ENV_RESULT="$ENV_RESULT; $(counts_cell "$dir" natural-language)"
  fi

  if [ "$focused" = "-" ] || [ -z "$focused" ]; then
    focused_r="$(not_run "$dir" focused "none listed")"
  elif [[ "$compile_r" != PASS* ]]; then
    focused_r="$(not_run "$dir" focused "compile failed")"
  else
    focused_r="$(cd "$tree" && run_stage "$dir" focused env SPEAKIT_RESULT_BUNDLE="$dir/focused.xcresult" Tools/CI/unit-tests.sh "$focused")"
    read_bundle "$dir/focused.xcresult" "$dir" focused
    read_console "$dir/focused.xcresult" "$dir" focused
    focused_r="$focused_r; $(counts_cell "$dir" focused)"
  fi

  if [ "$suite" != "yes" ]; then
    suite_r="$(not_run "$dir" suite "not requested for this row")"
  elif [[ "$compile_r" != PASS* ]]; then
    suite_r="$(not_run "$dir" suite "compile failed")"
  else
    bundle="$row_work/suite.xcresult"
    rm -rf "$bundle"
    suite_r="$(cd "$tree" && run_stage "$dir" suite env SPEAKIT_RESULT_BUNDLE="$bundle" Tools/CI/unit-tests.sh SpeakItTests)"
    read_bundle "$bundle" "$dir" suite
    suite_r="$suite_r; $(counts_cell "$dir" suite)"
  fi

  if [ "$release" = "yes" ]; then
    release_r="$(cd "$tree" && run_stage "$dir" release Tools/CI/release-build.sh)"
  else
    release_r="$(not_run "$dir" release "not requested for this row")"
  fi

  if [ "$extra" = "-" ] || [ -z "$extra" ]; then
    extra_r="$(not_run "$dir" extra "none listed")"
  else
    extra_r="$(cd "$tree" && run_stage "$dir" extra env QUALIFICATION_ROW_DIR="$dir" QUALIFICATION_CHECKOUT="$ROOT" /bin/bash -c "$extra")"
  fi
  if [ -d "$tree/output" ]; then
    cp -R "$tree/output" "$dir/tree-output"
  fi

  echo "| $label | $commit_cell | $compile_r | $gate_r | $focused_r | $suite_r | $release_r | $extra_r |" >> "$SUMMARY"
  git worktree remove --force "$tree" > /dev/null 2>&1 || true
done

{
  echo
  echo "NaturalLanguage readout (baseline tree, \`NaturalLanguageEnvironmentTests\`): $ENV_RESULT. A failure here with every token read as OtherWord means this simulator has no lexical-class model; see baseline/natural-language.log and baseline/natural-language-summary.json."
} >> "$SUMMARY"

# --- Every row against the baseline row -----------------------------------
# A comparison is printed as a verdict only when it measured something; every
# other outcome says NOT MEASURED or INCOMPLETE with the reason, and makes the
# script exit 4.
UNMEASURED=0
B="$EVIDENCE/baseline"

# Why a row's suite cannot be compared, or nothing when it can.
suite_unmeasurable() {
  local dir="$1"
  if [ -f "$dir/checkout.failed" ]; then cat "$dir/checkout.failed"; return; fi
  local status
  status="$(cat "$dir/suite.status" 2>/dev/null || echo "no status")"
  case "$status" in
    "NOT RUN: "*) echo "suite not run: ${status#NOT RUN: }"; return ;;
  esac
  if [ -f "$dir/suite.notmeasured" ]; then cat "$dir/suite.notmeasured"; return; fi
  if [ ! -f "$dir/suite-counts.txt" ]; then echo "suite stage left no counts"; return; fi
}

gate_unmeasurable() {
  local dir="$1"
  if [ -f "$dir/checkout.failed" ]; then cat "$dir/checkout.failed"; return; fi
  if [ ! -f "$dir/gate-blocking.txt" ]; then
    echo "blocking rows could not be read from gate.log: $(tail -n 1 "$dir/gate-blocking.err" 2>/dev/null)"
  fi
}

list_lines() {
  [ -n "$1" ] && printf '%s\n' "$1" | sed 's/^/- /'
}

count_lines() {
  if [ -z "$1" ]; then echo 0; else printf '%s\n' "$1" | grep -c .; fi
}

{
  echo
  echo "## Every row against the baseline row"
  echo
  echo "A test or corpus row that already fails on the baseline and fails on a branch for a"
  echo "new reason is not NEW: both diffs are on names, not on failure messages. Read the"
  echo "failure text of any tagger-dependent test in the region a branch changes."
  echo
} >> "$SUMMARY"

BASE_SUITE_WHY="$(suite_unmeasurable "$B")"
BASE_GATE_WHY="$(gate_unmeasurable "$B")"
BASE_TOTAL=""
if [ -z "$BASE_SUITE_WHY" ]; then
  read -r _ _ _ _ BASE_TOTAL < "$B/suite-counts.txt"
fi
BASE_DECLARED="$(cat "$B/declared-tests.txt" 2>/dev/null || true)"
{
  echo "### baseline"
  echo
  if [ -n "$BASE_SUITE_WHY" ]; then
    echo "Suite: **NOT MEASURED** ($BASE_SUITE_WHY). No row's suite can be compared."
  else
    echo "Suite: ran $BASE_TOTAL tests; its source declares ${BASE_DECLARED:-an unknown number of} test methods; failures keyed by \`$(cat "$B/suite-key.txt")\`; $(count_lines "$(cat "$B/suite-failures.txt")") failing."
    if [ -n "$BASE_DECLARED" ] && [ "$BASE_TOTAL" -lt "$BASE_DECLARED" ]; then
      echo "The baseline ran fewer tests than its source declares; read baseline/suite.log before trusting any row's comparison."
    fi
  fi
  echo
  if [ -n "$BASE_GATE_WHY" ]; then
    echo "Gate: **NOT MEASURED** ($BASE_GATE_WHY). No row's gate can be compared."
  else
    echo "Gate: $(count_lines "$(cat "$B/gate-blocking.txt")") distinct blocking rows:"
    list_lines "$(cat "$B/gate-blocking.txt")"
  fi
  echo
} >> "$SUMMARY"
[ -n "$BASE_SUITE_WHY" ] && UNMEASURED=1
[ -n "$BASE_GATE_WHY" ] && UNMEASURED=1

for row in "${ROWS[@]}"; do
  label="$(printf '%s' "$row" | cut -f1)"
  [ "$label" = "baseline" ] && continue
  dir="$EVIDENCE/$label"
  {
    echo "### $label"
    echo
    why="$(suite_unmeasurable "$dir")"
    if [ -n "$BASE_SUITE_WHY" ]; then
      echo "Suite: **NOT MEASURED** (the baseline suite was not measured)."
      UNMEASURED=1
    elif [ "$why" = "suite not run: not requested for this row" ]; then
      echo "Suite: no comparison (whole suite not requested for this row)."
    elif [ -n "$why" ]; then
      echo "Suite: **NOT MEASURED** ($why)."
      UNMEASURED=1
    else
      suite_measured=0
      read -r passed failed skipped expected total < "$dir/suite-counts.txt"
      row_declared="$(cat "$dir/declared-tests.txt" 2>/dev/null || true)"
      new="$(LC_ALL=C comm -13 "$B/suite-failures.txt" "$dir/suite-failures.txt" | grep -v '^$' || true)"
      fixed="$(LC_ALL=C comm -23 "$B/suite-failures.txt" "$dir/suite-failures.txt" | grep -v '^$' || true)"
      if [ -z "$BASE_DECLARED" ] || [ -z "$row_declared" ]; then
        echo "Suite: **NOT MEASURED** (the test methods the source declares could not be counted, so there is no expected total; see declared-tests.err). Ran $total, baseline $BASE_TOTAL."
        echo
        echo "Failing here and not on the baseline, NOT a verdict: $(count_lines "$new")"
        list_lines "$new"
        UNMEASURED=1
      else
        wanted=$((BASE_TOTAL + row_declared - BASE_DECLARED))
        tally="ran $total (passed $passed, failed $failed, skipped $skipped); expected $wanted = baseline $BASE_TOTAL + $((row_declared - BASE_DECLARED)) test methods this row's source adds"
        if [ "$total" -lt "$wanted" ]; then
          echo "Suite: **INCOMPLETE: $((wanted - total)) tests short.** $tally. A crashed, timed-out or partial run; the list below is not a verdict. Read $label/suite.log."
          echo
          echo "Failing here and not on the baseline, among the tests that did run: $(count_lines "$new")"
          list_lines "$new"
          UNMEASURED=1
        else
          suite_measured=1
          echo "Suite: measured, keyed by \`$(cat "$dir/suite-key.txt")\`; $tally."
          [ "$total" -gt "$wanted" ] && echo "It ran $((total - wanted)) more tests than expected; the declared-method count may be off, so read the totals."
          echo
          echo "NEW (fail here, pass on baseline): $(count_lines "$new")"
          list_lines "$new"
        fi
      fi
      echo
      if [ "$suite_measured" = "1" ]; then
        echo "No longer failing: $(count_lines "$fixed")"
      else
        echo "Failing on the baseline and not here, NOT a verdict (they may not have run): $(count_lines "$fixed")"
      fi
      list_lines "$fixed"
    fi
    echo
    gwhy="$(gate_unmeasurable "$dir")"
    if [ -n "$BASE_GATE_WHY" ]; then
      echo "Gate: **NOT MEASURED** (the baseline gate was not measured)."
      UNMEASURED=1
    elif [ -n "$gwhy" ]; then
      echo "Gate: **NOT MEASURED** ($gwhy)."
      UNMEASURED=1
    else
      gnew="$(LC_ALL=C comm -13 "$B/gate-blocking.txt" "$dir/gate-blocking.txt" | grep -v '^$' || true)"
      gfixed="$(LC_ALL=C comm -23 "$B/gate-blocking.txt" "$dir/gate-blocking.txt" | grep -v '^$' || true)"
      echo "Gate: NEW blocking rows (blocking here, not on baseline): $(count_lines "$gnew")"
      list_lines "$gnew"
      echo
      echo "Gate: blocking on baseline and not here: $(count_lines "$gfixed")"
      list_lines "$gfixed"
    fi
    echo
  } >> "$SUMMARY"
done
# The loop above runs in the current shell (a brace group, not a pipeline),
# so UNMEASURED set inside it survives.

# --- Exit status -----------------------------------------------------------
FAILED_STAGES=""
NOT_MEASURED=""
for row in "${ROWS[@]}"; do
  label="$(printf '%s' "$row" | cut -f1)"
  dir="$EVIDENCE/$label"
  [ -f "$dir/checkout.failed" ] && FAILED_STAGES="$FAILED_STAGES $label/checkout"
  for status_file in "$dir"/*.status; do
    [ -f "$status_file" ] || continue
    case "$(cat "$status_file")" in
      0|"NOT RUN: "*) ;;
      *) FAILED_STAGES="$FAILED_STAGES $label/$(basename "$status_file" .status)" ;;
    esac
  done
  for empty in "$dir"/*.ranempty; do
    [ -f "$empty" ] && FAILED_STAGES="$FAILED_STAGES $label/$(basename "$empty" .ranempty)(ran-no-test)"
  done
  # A test stage whose bundle could not be read is unmeasured even where no
  # comparison depends on it (focused, the NaturalLanguage readout).
  for unread in "$dir"/*.notmeasured; do
    [ -f "$unread" ] && NOT_MEASURED="$NOT_MEASURED $label/$(basename "$unread" .notmeasured)"
  done
done
[ -n "$NOT_MEASURED" ] && UNMEASURED=1

ZIP="$EVIDENCE_ROOT/v1-qualification-$STAMP.zip"
EXIT=0
[ -n "$FAILED_STAGES" ] && EXIT=1
[ "$UNMEASURED" = "1" ] && EXIT=4
{
  echo "## Exit status $EXIT"
  echo
  echo "Failed stages:${FAILED_STAGES:- none}"
  echo
  if [ -n "$STALE_PINS" ]; then
    echo "**Stale pins:$STALE_PINS.** Those rows qualified a commit that is not their branch's tip; see Pins above."
  else
    echo "Every pin was its branch's tip when the run started."
  fi
  echo
  if [ "$UNMEASURED" = "1" ]; then
    echo "At least one comparison is NOT MEASURED or INCOMPLETE; those rows carry no verdict."
    [ -n "$NOT_MEASURED" ] && echo "Result bundles not read:$NOT_MEASURED"
  else
    echo "Every comparison was measured."
  fi
} >> "$SUMMARY"

zip_status=0
(cd "$EVIDENCE_ROOT" && zip -qr "$ZIP" "v1-qualification-$STAMP") || zip_status=$?
echo
cat "$SUMMARY"
echo
echo "Evidence: $EVIDENCE"
if [ "$zip_status" = "0" ] && [ -f "$ZIP" ]; then
  echo "Upload this one file to the project: $ZIP"
else
  echo "ZIP FAILED (exit $zip_status): $ZIP was not written. Compress $EVIDENCE by hand and upload that." >&2
  [ "$EXIT" = "0" ] && EXIT=1
fi
echo "Derived data and whole-suite bundles are kept under $WORK; delete it when the evidence is uploaded."
exit "$EXIT"
