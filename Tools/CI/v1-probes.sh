#!/bin/bash
# The rc row's extra command in v1-qualification.tsv: every Mac probe the owner
# handoff used to ask for by hand, run against the tree in the current
# directory (the rc row's worktree at the rc pin) and written into one evidence
# directory. v1-qualification.sh runs it as
#
#   "$QUALIFICATION_CHECKOUT/Tools/CI/v1-probes.sh" "$QUALIFICATION_ROW_DIR/probes"
#
# The inputs (Tools/CI/v1-probes/*.txt) live beside this script in the
# qualification checkout, not in the tree, because they are the qualification's
# questions and the rc pin predates them. The tools that answer (the probe and
# the scorers) are the tree's own, except where a step names fixed commits
# (151-unchanged, 136-timing), which build their own probes.
#
# Steps, one line each in steps.txt (step, PASS or FAIL, detail):
#
#   build            Tools/PipelineProbe, built from this tree
#   dec24            december-24.txt through the probe: report, JSON and a
#                    table (dec24.tsv). Recorded, not judged: GATE-1 waits on
#                    the owner's Q5. PASS means the probe exited 0 and gave
#                    exactly one answer per sentence (count.py)
#   151-held         reported-speech-held.txt: every capture gives exactly one
#                    row, held for review, gap reportedSpeech, no due date, no
#                    reminder. A verdict
#   151-unchanged    reported-speech-unchanged.txt: #151 changes only the
#                    sentences it means to, measured at its merge. Every
#                    capture's rows are identical at AFTER_151 (the merge) and
#                    BEFORE_151 (its first parent), both fixed below, so the
#                    answer is #151's isolated effect whatever lands on the
#                    candidate later; what the candidate does with reported
#                    speech is 151-held, run at the tree. A verdict, and FAIL
#                    before any probe runs if either commit is missing,
#                    AFTER_151's first parent is not BEFORE_151, or AFTER_151
#                    is not in this tree's history
#   candidate-controls  the same control sentences through the probe already
#                    built at this tree, against the AFTER_151 answers: every
#                    control reads at the candidate as it did at #151's merge,
#                    so nothing merged since has started holding (or otherwise
#                    changed) an ordinary sentence. A verdict; no extra build
#   136-conditional  Tools/CorpusRunner/devsets/conditional-intent-score.sh (72 rows)
#   136-cancellation Tools/CorpusRunner/devsets/cancellation-scope-score.sh (187 rows)
#   136-timing       #136's R1 timing: one long unpunctuated capture, 200 times,
#                    three runs each, before the place-name cap (BEFORE_CAP),
#                    with the cap alone (CAP_ONLY) and at this tree. Recorded
#   d19-picks        the typed inputs for the handoff's by-hand M3 session:
#                    refinement-eligible captures from the development sets
#                    (never the held-out set) and five ineligible controls.
#                    Recorded
#
# The four fixed commits below are not manifest rows, so --check-pins does not
# look at them. They do not need it: each is a historical commit chosen for what
# it lacks, not a branch tip, and a commit never moves. Each is checked out into
# a temporary worktree of the tree's repository and removed on exit.
#
# Exit 0 when every step passed, 1 otherwise. steps.txt says which.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
INPUTS="$HERE/v1-probes"
if [ $# -ne 1 ] || [ -z "$1" ]; then
  echo "usage: v1-probes.sh <output directory>  (run from the tree to probe)" >&2
  exit 2
fi
OUT="$1"
TREE="$(pwd)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

# #136 immediately before 26e69c0, "Bound the place-name time search to the
# phrase's last five words (R1)", and that commit alone.
BEFORE_CAP=11c93d79301c89c66c485b8b7963afa80cf0253d
CAP_ONLY=26e69c0c4c40553d326d21e89376f2550d1ae16e
# "Merge #151 ... into the V1 candidate" and its first parent: the candidate
# with and without #151 and nothing else. 151-unchanged checks that the one is
# the other's first parent and that the merge is in the tree's history.
AFTER_151=5f2c2d3b297d0b96796a7b7b13816bfe0ed74025
BEFORE_151=a9f75173ba44b60a85d9a358089ac78f90749bf0
LONG_CAPTURE="Remind me when I get home from the long weekend away with the whole family and the dog and our neighbours from the cottage down the road Friday to call Mom"

if ! git -C "$TREE" rev-parse --verify --quiet HEAD > /dev/null; then
  echo "v1-probes.sh: $TREE is not a git checkout" >&2
  exit 2
fi
mkdir -p "$OUT"
SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/v1-probes.XXXXXX")"
WORKTREES=()
# shellcheck disable=SC2329  # invoked by the EXIT trap
cleanup() {
  for wt in ${WORKTREES[@]+"${WORKTREES[@]}"}; do
    git -C "$TREE" worktree remove --force "$wt" > /dev/null 2>&1 || true
  done
  rm -rf "$SCRATCH"
}
trap cleanup EXIT

STEPS="$OUT/steps.txt"
: > "$STEPS"
# A re-run into the same directory must not let one step read another
# step's answers from an earlier run: candidate-controls reads
# 151-unchanged.jsonl, and a guard failure there writes none.
rm -f "$OUT"/*.jsonl "$OUT"/*.tsv
FAILED=0
record() {
  printf '%s\t%s\t%s\n' "$1" "$2" "$3" >> "$STEPS"
  echo "v1-probes: $1 $2 $3" >&2
  [ "$2" = "PASS" ] || FAILED=1
}

{
  echo "tree $(git -C "$TREE" rev-parse HEAD)"
  echo "tree clean $([ -z "$(git -C "$TREE" status --porcelain)" ] && echo yes || echo NO)"
  echo "inputs from $(git -C "$HERE" rev-parse HEAD 2>/dev/null || echo unknown)"
  python3 - "$INPUTS"/*.txt <<'PY'
import hashlib, os, sys
for path in sys.argv[1:]:
    print(f"input {os.path.basename(path)} sha256 {hashlib.sha256(open(path, 'rb').read()).hexdigest()}")
PY
  echo "before the place-name cap $BEFORE_CAP"
  echo "the place-name cap alone $CAP_ONLY"
  echo "#151's merge into the candidate $AFTER_151"
  echo "the candidate before #151 $BEFORE_151"
} > "$OUT/identity.txt"

# --- Helpers ---------------------------------------------------------------
cat > "$SCRATCH/table.py" <<'PY'
# One line per row of `probe --json` output: capture number, row number, the
# fields a reader needs, then the text. Dates are shown in the probe's own
# frame zone, America/Toronto, and as Unix seconds.
import json, sys
from datetime import datetime, timezone
try:
    from zoneinfo import ZoneInfo
    ZONE = ZoneInfo("America/Toronto")
except Exception:
    ZONE = timezone.utc
def when(value):
    if value is None:
        return "-"
    return datetime.fromtimestamp(value, ZONE).strftime("%Y-%m-%d %H:%M %Z") + f" ({int(value)})"
cols = ["capture", "row", "rows", "title", "route", "needsReview", "due", "reminder",
        "delivery", "state", "stateGap", "unsupportedTrigger", "operations", "text"]
print("\t".join(cols))
for n, line in enumerate(open(sys.argv[1], encoding="utf-8"), 1):
    capture = json.loads(line)
    ops = ",".join(o["operation"] for o in capture["operations"]) or "-"
    items = capture["items"] or [{}]
    for r, item in enumerate(items, 1):
        print("\t".join(str(x) for x in [
            n, r if capture["items"] else "-", len(capture["items"]),
            item.get("title", "-"), item.get("route", "-"), item.get("needsReview", "-"),
            when(item.get("due")), when(item.get("reminder")), item.get("delivery", "-"),
            item.get("state", "-"), item.get("stateGap") or "-",
            item.get("unsupportedTrigger") or "-", ops, capture["text"]]))
PY

cat > "$SCRATCH/count.py" <<'PY'
# One probe answer per input sentence, the sentences filtered the way the
# probe filters them (blank lines and lines starting with '#' skipped).
import sys
inputs = [l for l in open(sys.argv[1], encoding="utf-8") if l.strip() and not l.startswith("#")]
got = [l for l in open(sys.argv[2], encoding="utf-8") if l.strip()]
print(f"{len(got)}/{len(inputs)}")
sys.exit(0 if len(got) == len(inputs) else 1)
PY

cat > "$SCRATCH/held.py" <<'PY'
# #151: every capture gives exactly one row, held for review, with gap
# reportedSpeech and no due date and no reminder.
import json, sys
inputs = [l.rstrip("\n") for l in open(sys.argv[1], encoding="utf-8")]
inputs = [l for l in inputs if l.strip() and not l.startswith("#")]
got = [json.loads(l) for l in open(sys.argv[2], encoding="utf-8")]
if len(got) != len(inputs):
    sys.exit(f"{len(inputs)} inputs but {len(got)} probe answers")
bad = 0
for text, capture in zip(inputs, got):
    items = capture["items"]
    why = []
    if len(items) != 1:
        why.append(f"{len(items)} rows")
    else:
        item = items[0]
        if item.get("needsReview") is not True:
            why.append("not held for review")
        if item.get("stateGap") != "reportedSpeech":
            why.append(f"gap {item.get('stateGap')}")
        if item.get("due") is not None:
            why.append("has a due date")
        if item.get("reminder") is not None:
            why.append("has a reminder")
    bad += bool(why)
    print(f"{'FAIL' if why else 'PASS'}\t{text}\t{'; '.join(why) or 'one held row, reportedSpeech, no date'}")
print(f"# {len(inputs) - bad}/{len(inputs)} as #151 requires")
sys.exit(1 if bad else 0)
PY

cat > "$SCRATCH/unchanged.py" <<'PY'
# Every capture's rows are identical in two answer files. By default the two
# sides are #151's merge and its first parent; argv[3] and argv[4] rename them
# (the candidate-controls step compares the candidate with #151's merge).
import json, sys
before = [json.loads(l) for l in open(sys.argv[1], encoding="utf-8")]
after = [json.loads(l) for l in open(sys.argv[2], encoding="utf-8")]
before_name = sys.argv[3] if len(sys.argv) > 3 else "before #151"
after_name = sys.argv[4] if len(sys.argv) > 4 else "with #151"
if len(before) != len(after):
    sys.exit(f"{len(before)} answers {before_name} but {len(after)} {after_name}")
bad = 0
for b, a in zip(before, after):
    if b["text"] != a["text"]:
        sys.exit(f"inputs out of step: {b['text']!r} against {a['text']!r}")
    same = b["items"] == a["items"] and b["operations"] == a["operations"]
    bad += not same
    print(f"{'SAME' if same else 'CHANGED'}\t{a['text']}")
    if not same:
        print(f"  {before_name}: {json.dumps(b, sort_keys=True)}")
        print(f"  {after_name}: {json.dumps(a, sort_keys=True)}")
print(f"# {len(after) - bad}/{len(after)} the same {after_name} as {before_name}")
sys.exit(1 if bad else 0)
PY

cat > "$SCRATCH/devset-inputs.py" <<'PY'
# Utterances of every development set, one per line, and a parallel id list.
# Never reads the held-out set.
import glob, os, sys
devsets, texts_out, ids_out = sys.argv[1], sys.argv[2], sys.argv[3]
with open(texts_out, "w", encoding="utf-8") as texts, open(ids_out, "w", encoding="utf-8") as ids:
    for path in sorted(glob.glob(os.path.join(devsets, "*.tsv"))):
        name = os.path.basename(path)[:-4]
        for line in open(path, encoding="utf-8"):
            line = line.rstrip("\n")
            if not line.strip() or line.startswith("#"):
                continue
            cols = line.split("\t")
            if len(cols) < 2 or cols[0] == "id":
                continue
            text = cols[1].strip()
            # The probe skips blank lines and lines starting with '#'.
            if not text or text.startswith("#"):
                continue
            texts.write(text + "\n")
            ids.write(f"{name}\t{cols[0]}\n")
PY

cat > "$SCRATCH/d19.py" <<'PY'
# The typed inputs for the handoff's M3 (#146's two-second budget, D19 in the
# audit). Eligible: no operation, at most 1,500 characters, and at least one
# row held for review. Picks, in this order and at most 30: the eight captures
# the audit names, where still eligible; then the remaining eligible captures,
# alternating one-row and multi-row rules readings, in file order. Controls:
# five ineligible captures with no operation, alternating the same way, as the
# rules-only timing baseline.
import json, sys
ids_path, json_path, out_dir = sys.argv[1], sys.argv[2], sys.argv[3]
ids = [l.rstrip("\n").split("\t") for l in open(ids_path, encoding="utf-8")]
got = [json.loads(l) for l in open(json_path, encoding="utf-8")]
if len(ids) != len(got):
    sys.exit(f"{len(ids)} development-set captures but {len(got)} probe answers")
NAMED = ["RB14R", "RB15R", "RB29C", "RB34R", "RB35R", "RB37R", "RB21R", "RB45R"]
rows = []
for (devset, cid), capture in zip(ids, got):
    items = capture["items"]
    eligible = (not capture["operations"] and len(capture["text"]) <= 1500
                and any(i.get("needsReview") is True for i in items))
    rows.append(dict(devset=devset, id=cid, text=capture["text"], items=items,
                     ops=capture["operations"], eligible=eligible))
def line(n, row, why):
    items = row["items"]
    return "\t".join(str(x) for x in [
        n, row["devset"], row["id"], why, len(items),
        sum(1 for i in items if i.get("needsReview") is True),
        " | ".join(f"{i.get('title')} ({i.get('route')}{', review' if i.get('needsReview') else ''})" for i in items) or "-",
        row["text"]])
def alternate(pool, limit):
    one = [r for r in pool if len(r["items"]) == 1]
    multi = [r for r in pool if len(r["items"]) > 1]
    picked = []
    while len(picked) < limit and (one or multi):
        for bucket in (one, multi):
            if bucket and len(picked) < limit:
                picked.append(bucket.pop(0))
    return picked
by_id = {r["id"]: r for r in rows if r["devset"] == "rambling"}
named_report, picks = [], []
for cid in NAMED:
    r = by_id.get(cid)
    if r is None:
        named_report.append(f"{cid}\tnot in rambling.tsv")
    elif r["eligible"]:
        named_report.append(f"{cid}\teligible")
        picks.append((r, "named"))
    else:
        reason = "has an operation" if r["ops"] else ("over 1,500 characters" if len(r["text"]) > 1500 else "no row held for review")
        named_report.append(f"{cid}\tNOT eligible ({reason})")
taken = {id(r) for r, _ in picks}
rest = [r for r in rows if r["eligible"] and id(r) not in taken]
for r in alternate(rest, 30 - len(picks)):
    picks.append((r, "one-row" if len(r["items"]) == 1 else "multi-row"))
controls = alternate([r for r in rows if not r["eligible"] and not r["ops"] and r["items"]], 5)
header = "n\tset\tid\twhy\trules rows\trows held\trules reading\ttext\n"
with open(f"{out_dir}/d19-picks.tsv", "w", encoding="utf-8") as f:
    f.write(header)
    for n, (r, why) in enumerate(picks, 1):
        f.write(line(n, r, why) + "\n")
    for n, r in enumerate(controls, len(picks) + 1):
        f.write(line(n, r, "control") + "\n")
with open(f"{out_dir}/d19-eligible.tsv", "w", encoding="utf-8") as f:
    f.write(header)
    for n, r in enumerate([r for r in rows if r["eligible"]], 1):
        f.write(line(n, r, "eligible") + "\n")
with open(f"{out_dir}/d19-named.txt", "w", encoding="utf-8") as f:
    f.write("\n".join(named_report) + "\n")
eligible = sum(r["eligible"] for r in rows)
print(f"{len(rows)} development-set captures, {eligible} eligible; "
      f"{len(picks)} picks ({sum(1 for _, w in picks if w == 'named')} named), {len(controls)} controls")
PY

# Builds the probe in a tree; the build log goes to $2.
build_probe() {
  (cd "$1" && ./Tools/PipelineProbe/build.sh) > "$2" 2>&1
}

# Checks a fixed commit out into a temporary worktree and builds its probe.
# Sets WT to the worktree, or leaves it empty and returns 1.
WT=""
historical_probe() {
  local commit="$1" name="$2"
  WT="$SCRATCH/$name"
  if ! git -C "$TREE" worktree add --quiet --detach "$WT" "$commit" > "$OUT/$name-checkout.log" 2>&1; then
    WT=""
    return 1
  fi
  WORKTREES+=("$WT")
  rm -f "$OUT/$name-checkout.log"
  build_probe "$WT" "$OUT/$name-build.log" || { WT=""; return 1; }
}

# --- build -------------------------------------------------------------------
PROBE="$TREE/Tools/PipelineProbe/build/probe"
if build_probe "$TREE" "$OUT/build.log" && [ -x "$PROBE" ]; then
  record build PASS "Tools/PipelineProbe built from the tree"
else
  record build FAIL "the probe did not build; see build.log. Every probe step below is FAIL"
  PROBE=""
fi

# --- dec24 -------------------------------------------------------------------
if [ -n "$PROBE" ] \
  && "$PROBE" "$INPUTS/december-24.txt" > "$OUT/dec24-report.txt" 2>&1 \
  && "$PROBE" --json "$INPUTS/december-24.txt" > "$OUT/dec24.jsonl" 2> "$OUT/dec24.err" \
  && python3 "$SCRATCH/table.py" "$OUT/dec24.jsonl" > "$OUT/dec24.tsv" 2>> "$OUT/dec24.err"; then
  if answered="$(python3 "$SCRATCH/count.py" "$INPUTS/december-24.txt" "$OUT/dec24.jsonl" 2>> "$OUT/dec24.err")"; then
    record dec24 PASS "$answered sentences answered, recorded in dec24.tsv; read, not judged"
  else
    record dec24 FAIL "the probe answered ${answered:-an unreadable number of} sentences (answers/sentences); see dec24.jsonl"
  fi
  [ -s "$OUT/dec24.err" ] || rm -f "$OUT/dec24.err"
else
  record dec24 FAIL "see dec24.err"
fi

# --- 151-held ----------------------------------------------------------------
if [ -z "$PROBE" ]; then
  record 151-held FAIL "no probe"
elif "$PROBE" --json "$INPUTS/reported-speech-held.txt" > "$OUT/151-held.jsonl" 2> "$OUT/151-held.err" \
  && python3 "$SCRATCH/table.py" "$OUT/151-held.jsonl" > "$OUT/151-held.tsv" 2>> "$OUT/151-held.err"; then
  if python3 "$SCRATCH/held.py" "$INPUTS/reported-speech-held.txt" "$OUT/151-held.jsonl" > "$OUT/151-held.txt" 2>> "$OUT/151-held.err"; then
    record 151-held PASS "$(tail -n 1 "$OUT/151-held.txt" | sed 's/^# //')"
  else
    record 151-held FAIL "$(tail -n 1 "$OUT/151-held.txt" 2>/dev/null | sed 's/^# //'); see 151-held.txt"
  fi
  [ -s "$OUT/151-held.err" ] || rm -f "$OUT/151-held.err"
else
  record 151-held FAIL "the probe failed; see 151-held.err"
fi

# --- 151-unchanged -----------------------------------------------------------
# Both sides are fixed commits, never the tree, so a later merge into the
# candidate cannot be charged to #151.
AFTER_PARENT="$(git -C "$TREE" rev-parse --verify --quiet "$AFTER_151^1" || echo none)"
MISSING=""
for pinned in "$AFTER_151" "$BEFORE_151"; do
  git -C "$TREE" cat-file -e "$pinned^{commit}" 2>/dev/null || MISSING="$MISSING ${pinned:0:7}"
done
if [ -n "$MISSING" ]; then
  record 151-unchanged FAIL "the commit is missing from this repository:$MISSING (AFTER_151 ${AFTER_151:0:7}, BEFORE_151 ${BEFORE_151:0:7}); fetch origin, or fix the constants in Tools/CI/v1-probes.sh"
elif [ "$AFTER_PARENT" != "$BEFORE_151" ]; then
  record 151-unchanged FAIL "AFTER_151 ${AFTER_151:0:7}'s first parent is ${AFTER_PARENT:0:7}, not BEFORE_151 ${BEFORE_151:0:7}: the pair is not one merge and its first parent, so it would not isolate #151. Fix the constants in Tools/CI/v1-probes.sh"
elif ! git -C "$TREE" merge-base --is-ancestor "$AFTER_151" HEAD 2>/dev/null; then
  record 151-unchanged FAIL "AFTER_151 ${AFTER_151:0:7} is not in the tree's history: the candidate being qualified does not contain this #151 merge, so its effect measured there says nothing about this tree"
else
  after_probe=""
  before_probe=""
  if [ "$(git -C "$TREE" rev-parse HEAD)" = "$AFTER_151" ] && [ -n "$PROBE" ]; then
    after_probe="$PROBE"
  elif historical_probe "$AFTER_151" after-151; then
    after_probe="$WT/Tools/PipelineProbe/build/probe"
  fi
  if historical_probe "$BEFORE_151" before-151; then
    before_probe="$WT/Tools/PipelineProbe/build/probe"
  fi
  if [ -z "$after_probe" ] || [ -z "$before_probe" ]; then
    record 151-unchanged FAIL "could not check out or build ${AFTER_151:0:7} or ${BEFORE_151:0:7}; see after-151-*.log and before-151-*.log"
  elif "$after_probe" --json "$INPUTS/reported-speech-unchanged.txt" > "$OUT/151-unchanged.jsonl" 2> "$OUT/151-unchanged.err" \
    && "$before_probe" --json "$INPUTS/reported-speech-unchanged.txt" > "$OUT/151-unchanged-before.jsonl" 2>> "$OUT/151-unchanged.err"; then
    if python3 "$SCRATCH/unchanged.py" "$OUT/151-unchanged-before.jsonl" "$OUT/151-unchanged.jsonl" > "$OUT/151-unchanged.txt" 2>> "$OUT/151-unchanged.err"; then
      record 151-unchanged PASS "$(tail -n 1 "$OUT/151-unchanged.txt" | sed 's/^# //'), at its merge ${AFTER_151:0:7} against ${BEFORE_151:0:7}"
    else
      record 151-unchanged FAIL "$(tail -n 1 "$OUT/151-unchanged.txt" 2>/dev/null | sed 's/^# //'); see 151-unchanged.txt"
    fi
    [ -s "$OUT/151-unchanged.err" ] || rm -f "$OUT/151-unchanged.err"
  else
    record 151-unchanged FAIL "a probe failed; see 151-unchanged.err"
  fi
fi

# --- candidate-controls ------------------------------------------------------
# The control sentences at the candidate, against #151's merge: the
# over-holding check at the commit being qualified, with the probe built above.
if [ -z "$PROBE" ]; then
  record candidate-controls FAIL "no probe"
elif [ ! -s "$OUT/151-unchanged.jsonl" ]; then
  record candidate-controls FAIL "no answers from #151's merge to compare with; see the 151-unchanged line"
elif "$PROBE" --json "$INPUTS/reported-speech-unchanged.txt" > "$OUT/candidate-controls.jsonl" 2> "$OUT/candidate-controls.err"; then
  if python3 "$SCRATCH/unchanged.py" "$OUT/151-unchanged.jsonl" "$OUT/candidate-controls.jsonl" \
      "at #151's merge ${AFTER_151:0:7}" "at the candidate $(git -C "$TREE" rev-parse --short HEAD)" \
      > "$OUT/candidate-controls.txt" 2>> "$OUT/candidate-controls.err"; then
    record candidate-controls PASS "$(tail -n 1 "$OUT/candidate-controls.txt" | sed 's/^# //')"
  else
    record candidate-controls FAIL "$(tail -n 1 "$OUT/candidate-controls.txt" 2>/dev/null | sed 's/^# //'); see candidate-controls.txt"
  fi
  [ -s "$OUT/candidate-controls.err" ] || rm -f "$OUT/candidate-controls.err"
else
  record candidate-controls FAIL "the probe failed; see candidate-controls.err"
fi

# --- 136-conditional, 136-cancellation ---------------------------------------
# The scorers write their probe answers under TMPDIR; kept beside the scores.
for scorer in conditional-intent cancellation-scope; do
  step="136-${scorer%%-*}"
  [ "$scorer" = cancellation-scope ] && step=136-cancellation
  mkdir -p "$SCRATCH/$scorer"
  if [ -z "$PROBE" ]; then
    record "$step" FAIL "no probe"
  elif (cd "$TREE" && TMPDIR="$SCRATCH/$scorer" "./Tools/CorpusRunner/devsets/$scorer-score.sh") > "$OUT/$step.txt" 2>&1; then
    record "$step" PASS "$(grep -m1 'passed:' "$OUT/$step.txt" | tr -s ' ' | sed 's/^ //')"
  else
    record "$step" FAIL "$(grep -m1 'passed:' "$OUT/$step.txt" | tr -s ' ' | sed 's/^ //'); see $step.txt"
  fi
  cp "$SCRATCH/$scorer/$scorer-actual.jsonl" "$OUT/$step-actual.jsonl" 2>/dev/null || true
done

# --- 136-timing --------------------------------------------------------------
LONG_FILE="$SCRATCH/long-capture.txt"
for _ in $(seq 200); do echo "$LONG_CAPTURE"; done > "$LONG_FILE"
TIMING_BINS=""
TIMING_NAMES=""
if historical_probe "$BEFORE_CAP" before-cap; then
  TIMING_BINS="$WT/Tools/PipelineProbe/build/probe"; TIMING_NAMES="before-cap:$BEFORE_CAP"
fi
if historical_probe "$CAP_ONLY" cap-only; then
  TIMING_BINS="$TIMING_BINS $WT/Tools/PipelineProbe/build/probe"; TIMING_NAMES="$TIMING_NAMES cap-only:$CAP_ONLY"
fi
if [ -n "$PROBE" ]; then
  TIMING_BINS="$TIMING_BINS $PROBE"; TIMING_NAMES="$TIMING_NAMES rc-pin:$(git -C "$TREE" rev-parse HEAD)"
fi
bins=()
names=()
read -r -a bins <<< "$TIMING_BINS"
read -r -a names <<< "$TIMING_NAMES"
if [ "${#bins[@]}" != "3" ]; then
  record 136-timing FAIL "only ${#bins[@]} of 3 probes built; see before-cap-*.log, cap-only-*.log, build.log"
fi
{
  echo "# 200 copies of: $LONG_CAPTURE"
  printf 'build\tcommit\trun\tseconds\n'
} > "$OUT/136-timing.tsv"
timing_ok=1
TIMEFORMAT='%R'
# Bash 3.2 (macOS) treats an empty array as unbound under set -u, hence the guard.
[ "${#bins[@]}" -gt 0 ] && for run in 1 2 3; do
  for i in "${!bins[@]}"; do
    name="${names[$i]%%:*}"
    commit="${names[$i]#*:}"
    if secs="$( { time "${bins[$i]}" "$LONG_FILE" > /dev/null 2> "$SCRATCH/timing.err"; } 2>&1 )"; then
      printf '%s\t%s\t%s\t%s\n' "$name" "$commit" "$run" "$secs" >> "$OUT/136-timing.tsv"
    else
      printf '%s\t%s\t%s\tFAILED: %s\n' "$name" "$commit" "$run" "$(tail -n 1 "$SCRATCH/timing.err")" >> "$OUT/136-timing.tsv"
      timing_ok=0
    fi
  done
done
if [ "${#bins[@]}" = "3" ]; then
  if [ "$timing_ok" = "1" ]; then
    record 136-timing PASS "$(awk -F'\t' 'NR>2 {s[$1]=s[$1] " " $4} END {printf "before-cap%s; cap-only%s; rc-pin%s (seconds, three runs each)", s["before-cap"], s["cap-only"], s["rc-pin"]}' "$OUT/136-timing.tsv")"
  else
    record 136-timing FAIL "a timed run failed; see 136-timing.tsv"
  fi
fi

# --- d19-picks ---------------------------------------------------------------
if [ -z "$PROBE" ]; then
  record d19-picks FAIL "no probe"
elif python3 "$SCRATCH/devset-inputs.py" "$TREE/Tools/CorpusRunner/devsets" "$SCRATCH/devsets.txt" "$SCRATCH/devsets.ids" 2> "$OUT/d19.err" \
  && "$PROBE" --json "$SCRATCH/devsets.txt" > "$SCRATCH/devsets.jsonl" 2>> "$OUT/d19.err" \
  && summary="$(python3 "$SCRATCH/d19.py" "$SCRATCH/devsets.ids" "$SCRATCH/devsets.jsonl" "$OUT" 2>> "$OUT/d19.err")"; then
  record d19-picks PASS "$summary; d19-picks.tsv, d19-named.txt"
  [ -s "$OUT/d19.err" ] || rm -f "$OUT/d19.err"
else
  record d19-picks FAIL "see d19.err"
fi

echo >> "$STEPS"
if [ "$FAILED" = "0" ]; then
  echo "# every step passed" >> "$STEPS"
else
  echo "# at least one step FAILED" >> "$STEPS"
fi
exit "$FAILED"
