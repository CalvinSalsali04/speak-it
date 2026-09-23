#!/bin/bash
# The semantic-unit experiment, end to end, in one invocation on an Apple
# Intelligence Mac. Writes one evidence directory; prints PASS/FAIL per step.
#
#   ./Tools/SemanticMap/UnitsExperiment/run.sh [evidence-dir]
#
# Refuses to generate unless the frozen gold, the inputs, the scorer and the
# prompts hash to the values pinned in MANIFEST, so the model can never be run
# against a gold, scorer or prompt changed after the fact. One greedy
# generation per candidate per capture.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
OUT="${1:-$ROOT/output/units-experiment-$(date +%Y%m%d-%H%M%S)}"
mkdir -p "$OUT"
cd "$ROOT" || exit 1
status=0
step() { echo "== $1"; }
pass() { echo "PASS $1" | tee -a "$OUT/steps.txt"; }
fail() { echo "FAIL $1" | tee -a "$OUT/steps.txt"; status=1; }

step "identity"
{ git rev-parse HEAD; git status --porcelain -- Tools/SemanticMap SpeakIt; } > "$OUT/identity.txt"
if [ -n "$(git status --porcelain -- Tools/SemanticMap SpeakIt)" ]; then fail "clean tree (Tools/SemanticMap, SpeakIt)"; else pass "clean tree"; fi

step "frozen inputs"
check_hash() {
  local want got
  want=$(awk -v f="$1" '$2 == f {print $1}' "$HERE/MANIFEST")
  got=$(shasum -a 256 "$ROOT/$1" | cut -d' ' -f1)
  if [ -n "$want" ] && [ "$want" = "$got" ]; then pass "hash $1"; else fail "hash $1 (manifest ${want:-missing}, file $got)"; fi
}
for f in $(awk '{print $2}' "$HERE/MANIFEST"); do check_hash "$f"; done
python3 "$HERE/make_inputs.py" "$HERE/captures.jsonl" | cmp -s - "$HERE/inputs.jsonl" \
  && pass "inputs regenerate identically" || fail "inputs regenerate identically"
if [ $status -ne 0 ]; then echo "refusing to generate: the frozen inputs do not check out"; exit 1; fi

step "scorer selftest"
python3 "$HERE/score_units.py" selftest > "$OUT/selftest.txt" 2>&1 && pass "scorer selftest" || fail "scorer selftest"
python3 "$HERE/decide.py" selftest >> "$OUT/selftest.txt" 2>&1 && pass "decision selftest" || fail "decision selftest"

step "representability (no model)"
python3 "$HERE/score_units.py" precheck --gold "$HERE/gold/gold.json" --inputs "$HERE/inputs.jsonl" > "$OUT/precheck.txt" 2>&1 \
  && pass "precheck" || fail "precheck"

step "build the probe"
"$ROOT/Tools/SemanticMap/build.sh" > "$OUT/build.txt" 2>&1 && pass "build" || { fail "build"; cat "$OUT/build.txt"; exit 1; }
"$ROOT/Tools/SemanticMap/build/semantic-map" --availability > "$OUT/availability.txt" 2>&1
grep -q "availability:      available" "$OUT/availability.txt" && pass "model available" || { fail "model available"; cat "$OUT/availability.txt"; exit 1; }

step "generate (one greedy pass per candidate per capture)"
"$ROOT/Tools/SemanticMap/build/semantic-map" --units-experiment "$HERE/inputs.jsonl" --out "$OUT/results.jsonl" 2> "$OUT/generate.log" \
  && pass "generation wrote $(wc -l < "$OUT/results.jsonl" | tr -d ' ') records" || fail "generation"

step "score"
python3 "$HERE/score_units.py" score --gold "$HERE/gold/gold.json" --inputs "$HERE/inputs.jsonl" \
  --results "$OUT/results.jsonl" --families "$HERE/families.json" > "$OUT/score.txt" 2>&1 \
  && pass "score" || fail "score"

step "decide (the rule pinned in DECISION_PLAN.md)"
python3 "$HERE/decide.py" --gold "$HERE/gold/gold.json" --inputs "$HERE/inputs.jsonl" \
  --results "$OUT/results.jsonl" --families "$HERE/families.json" > "$OUT/decision.txt" 2>&1 \
  && pass "decision: $(tail -n 1 "$OUT/decision.txt")" || fail "decision"

echo
echo "evidence: $OUT  (results.jsonl holds integers, labels and ids only; no capture text)"
exit $status
