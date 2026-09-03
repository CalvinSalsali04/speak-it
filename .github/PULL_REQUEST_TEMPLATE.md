## What changed

<!-- One or two sentences. Link the DECISIONS.md entry if this records a decision. -->

## Why

<!-- The observed behaviour or need, not the implementation. -->

## Verification

<!-- Paste the actual evidence: script names and their tail output, screenshots for UI. -->

- [ ] `Tools/CI/corpus-gate.sh` passes (rules-path changes)
- [ ] `Tools/CI/unit-tests.sh` passes
- [ ] `Tools/CI/release-build.sh` passes (app-level changes)
- [ ] UI tests or simulator screenshots for changed screens
- [ ] Still needs hands-on iPhone QA: <!-- list, or "none" -->

## Product and privacy contract

- [ ] Today stays for action, Memory stays for knowledge
- [ ] No original transcript is overwritten; interrupted drafts are preserved
- [ ] No user-authored content reaches analytics; `PrivacyInfo.xcprivacy` still matches
- [ ] Persistent model changes ship with a versioned schema and migration

## Docs

- [ ] `Docs/DECISIONS.md`, `Docs/KNOWN_ISSUES.md`, or `CHANGELOG.md` updated where behaviour, limits, or pricing changed
