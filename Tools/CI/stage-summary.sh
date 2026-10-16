#!/bin/bash
# Prints what an iOS CI job established, one stage per line.
#
# GitHub reports a step that did not run as `skipped`, and a skipped check
# renders grey rather than red, which is how green pull requests came to be
# read as "the app builds" when no Swift had been compiled. Here a stage that
# did not run says NOT RUN, and nothing but `success` says PASS.
#
# Reads GATE, COMPILE, UNIT, SELECTION, RELEASE and UI from the environment:
# step outcomes (success, failure, cancelled, skipped, or empty when the step
# does not exist in the job). UNIT_PASSED, UNIT_FAILED and UNIT_SKIPPED (and the
# same three for UI_) are the counts `unit-tests.sh` read from the result
# bundle, printed beside the verdict: one word hides whether a red selection is
# the NaturalLanguage diagnostic failing on purpose or a rule failing by
# accident. GATE_BLOCKING is the corpus gate's BLOCKING(crit+beh) count, which
# the gate step reads back out of the gate's own log, for the same reason: a
# bare FAIL cannot tell one known blocking row from forty regressions. Writes to
# stdout and, on CI, to the job summary.
set -euo pipefail

verdict() {
  case "${1:-}" in
    success) echo "PASS" ;;
    failure) echo "FAIL" ;;
    cancelled) echo "CANCELLED" ;;
    *) echo "NOT RUN" ;;
  esac
}

# A test stage's verdict with its counts. A stage that ran but left no counts
# says so, so a missing number is never read as zero.
tested() {
  local outcome="$1" passed="$2" failed="$3" skipped="$4"
  case "$outcome" in
    success|failure) ;;
    *) verdict "$outcome"; return ;;
  esac
  if [ -n "$passed" ]; then
    echo "$(verdict "$outcome") ($passed passed, $failed failed, $skipped skipped)"
  else
    echo "$(verdict "$outcome") (no test counts: no readable result bundle; see the step log)"
  fi
}

# The gate's verdict with its blocking count. A gate that ran but left no
# count (it stopped before corpus-run printed one) says so rather than showing
# a number it does not have.
gated() {
  local outcome="$1" blocking="$2"
  case "$outcome" in
    success|failure) ;;
    *) verdict "$outcome"; return ;;
  esac
  if [ -n "$blocking" ]; then
    echo "$(verdict "$outcome") ($blocking blocking)"
  else
    echo "$(verdict "$outcome") (no blocking count: the gate stopped before corpus-run reported one; see the step log)"
  fi
}

commit="$(git rev-parse HEAD 2>/dev/null || echo unknown)"
xcode="$(xcodebuild -version 2>/dev/null | tr '\n' ' ' || true)"
table="$(cat <<TABLE
| stage | result |
|---|---|
| commit | \`${commit}\` |
| toolchain | ${xcode:-unknown} |
| corpus gate | $(gated "${GATE:-}" "${GATE_BLOCKING:-}") |
| Swift compiled (app, extensions, test bundles) | $(verdict "${COMPILE:-}") |
| tests: ${SELECTION:-SpeakItTests} | $(tested "${UNIT:-}" "${UNIT_PASSED:-}" "${UNIT_FAILED:-}" "${UNIT_SKIPPED:-}") |
| Release build (separate Release compile, not gated on the one above) | $(verdict "${RELEASE:-}") |
| UI tests | $(tested "${UI:-}" "${UI_PASSED:-}" "${UI_FAILED:-}" "${UI_SKIPPED:-}") |
TABLE
)"
echo "$table"
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  echo "$table" >> "$GITHUB_STEP_SUMMARY"
fi
