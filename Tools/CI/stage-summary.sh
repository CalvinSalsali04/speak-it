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
# does not exist in the job). Writes to stdout and, on CI, to the job summary.
set -euo pipefail

verdict() {
  case "${1:-}" in
    success) echo "PASS" ;;
    failure) echo "FAIL" ;;
    cancelled) echo "CANCELLED" ;;
    *) echo "NOT RUN" ;;
  esac
}

commit="$(git rev-parse HEAD 2>/dev/null || echo unknown)"
xcode="$(xcodebuild -version 2>/dev/null | tr '\n' ' ' || true)"
table="$(cat <<TABLE
| stage | result |
|---|---|
| commit | \`${commit}\` |
| toolchain | ${xcode:-unknown} |
| corpus gate | $(verdict "${GATE:-}") |
| Swift compiled (app, extensions, test bundles) | $(verdict "${COMPILE:-}") |
| tests: ${SELECTION:-SpeakItTests} | $(verdict "${UNIT:-}") |
| Release build | $(verdict "${RELEASE:-}") |
| UI tests | $(verdict "${UI:-}") |
TABLE
)"
echo "$table"
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  echo "$table" >> "$GITHUB_STEP_SUMMARY"
fi
