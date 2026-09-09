# September 9 continuation review

Reviewed the existing uncommitted implementation and Claude's project notes.
This is a scoped continuation review, not a claim that every backlog proposal
is implemented or every release gate is closed.

## Changes made in this pass

- Fixed the missing morning-brief tap handler. A default notification action
  queues Today independently of capture requests, including before the root
  view exists. Existing capture drafts are not dismissed. If Today is already
  showing a pushed list, it returns to the root.
- A direct tap answers an old brief; dismissal and ordinary reminder taps do
  not alter the brief's unanswered counter. Added two regression tests.
- Corrected the obsolete pricing warning using the September 9 account status
  already recorded in this repository. No new App Store Connect changes were
  made in this pass.
- Replaced unsupported gamification claims with primary-source evidence in
  `GAMIFICATION_PROPOSAL.md` and corrected the associated decision rationale.

## Research conclusions

Apple's [default notification action documentation](https://developer.apple.com/documentation/usernotifications/unnotificationdefaultactionidentifier)
confirms that opening from a notification reaches the delegate callback. That
callback previously ignored briefs. Apple's [local notification documentation](https://developer.apple.com/documentation/usernotifications/scheduling-a-notification-locally-from-your-app)
also distinguishes foreground handling from system-managed background delivery.
Opening the app remains a proxy for reading a brief, not proof of delivery.

Duolingo reports a **3.3% relative Day 14 retention improvement** for separating
daily goals from streaks in its [experiment report](https://blog.duolingo.com/improving-the-streak/).
Its [habit article](https://blog.duolingo.com/how-duolingo-streak-builds-habit/)
reports **0.38% relative daily-active growth** for allowing two freezes. These
are different interventions and measurements. Neither validates a five-brief
auto-stop threshold or predicts Speak It's retention. The previously cited
2020 CHI abandonment claim was not verified and was withdrawn.

The existing Foundation Models path already checks availability and locale,
uses the general model, and validates model output against the rules result.
Apple's [generation guidance](https://developer.apple.com/documentation/FoundationModels/generating-content-and-performing-tasks-with-foundation-models)
and [locale guidance](https://developer.apple.com/documentation/foundationmodels/supporting-languages-and-locales-with-foundation-models)
support retaining these runtime checks. They do not establish extraction
accuracy. Device model quality and cancellation latency remain unmeasured in
this pass; the existing cooperative-cancellation limitation still applies.

## What remains open

- Real-device microphone, interruptions, Back Tap, lock-screen notifications,
  Focus/Scheduled Summary, iCloud, accessibility, and StoreKit Sandbox flows.
- Annual price scheduling, subscription approval, and the other distribution
  gates recorded in `APP_STORE_SUBMISSION.md` and the pricing status document.
- Generalization of speech routing: the existing held-out report records
  233/320 destinations correct and 7/69 ambiguous captures acted on. Those are
  historical measurements, not this pass's results. A clean authored regression
  corpus must not be presented as 100% accuracy on unseen speech.
- Milestones and weekly summaries remain proposals, not release requirements.

## Verification

- Semantic corpus: **1,381/1,381 clean**, zero failures in any severity.
- Referral service: **8/8 tests passed**.
- Website conversion and stage JavaScript: syntax checks passed.
- Whitespace/diff check: passed.
- Unsigned Release build: passed. The first rebuilding attempt was blocked by
  sandbox restrictions on Swift macro plugins; the permitted rerun passed.
- Focused simulator run: **12/12 passed**, zero skips or failures: eleven
  morning-brief tests and the Today/Memory/account navigation UI test.
  Result bundle: `/tmp/SpeakItReviewFocused.xcresult`.
- Removed a redundant `try` from the nonthrowing temporal-invariant test after
  the focused build exposed a compiler warning. The final full suite includes it.
- The first full-suite attempt shared Claude's active simulator/build directory.
  Only this review's waiting process was interrupted; the final run uses
  SpeakIt-Slim-2 and `/tmp/SpeakItReviewFocused` independently.
- Final full suite: **791 passed, 0 failed, 6 skipped** (797 total), in
  `/tmp/SpeakItReviewFull.xcresult`. The run completed in about ten minutes.
  Skips are the notification-center integration tests in `TemporalFullPathTests`:
  deleting, editing, spring-forward trigger timing, relaunch deletion recovery,
  repeated reconciliation, and timed shopping-list notification content. They
  are not counted as passes; actual notification delivery still needs device QA.
- Final full-suite compilation reported no compiler warnings. Final diff check passed.

## Further continuation after the usage reset

The full UI suite was completed rather than relying on the single navigation
check: **24 passed, one failed, zero skipped**. The failure demanded an
unverified permanent renewal-price promise that the product had deliberately
removed. Its exact-copy assertion was corrected, and the paywall rerun passed
alongside eighteen actionability tests (**19/19**). The saved dark-appearance
accessibility screenshot was inspected: tutorial copy and visible controls fit
without visible clipping. This is visual evidence for that screen, not a full
VoiceOver audit.

The six notification skips from the first pass were closed locally. Apple's
[provisional permission workflow](https://developer.apple.com/documentation/usernotifications/asking-permission-to-use-notifications)
lets the test helper obtain authorization on a fresh test install without a
prompt. Existing denial is respected. The temporal suite then passed **25**,
skipping only the mutually exclusive unauthorized-state test; that state had
already passed in the previous unapproved environment. No production permission
behavior changed.

The parser now preserves bare day-as-topic phrases such as "that Thursday
thing" for review without a deadline. Explicit actions and temporal prepositions
retain their dates. The authored corpus remains **1,381/1,381 clean**.
Development-set acted-on ambiguous captures fell **4/32 → 3/32**.

The scoring instrument also needed correction: it called development data held
out and omitted empty ambiguous captures from its content-loss counter. Both
are corrected, with two synthetic regression tests now in the corpus gate.
The held-out set was scored once without reading failures: **233/320** routes,
**255/310** thought counts, **7/69** ambiguous captures acted on, **0** missing
outputs, **0** captures lost. These numbers did not improve; no broader gain is
claimed. Development labels for reported instructions and prohibitions still
conflict with later product decisions and should not be treated as independent
ground truth.

A direct runtime check of `SystemLanguageModel.default.availability` on this Mac
returned **appleIntelligenceNotEnabled**. No model benchmark ran, and no system
Apple Intelligence setting was changed. The remaining on-device quality and
latency unknowns are therefore tied to a verified environmental constraint.

Final unsigned Release compilation passed using the isolated directory
`/tmp/SpeakItContinuationRelease`. The initial attempt hit another build's lock
in the shared default directory; no other process was interrupted.
Final full-suite verification: **802 passed, 0 failed, 1 skipped** (803 total)
in `/tmp/SpeakItContinuationFull.xcresult`, about ten minutes. The remaining
skip is the mutually exclusive denied-permission case. Release and diff checks
also pass. The two scorer regression tests pass and are wired into the canonical
corpus gate.

Pricing research identified Apple's documented schedule-change flow, distinct
from editing Starting Price. The official guide does not explain the missing
account control. A live read-only follow-up hit an expired App Store Connect
session; account changes remain unverified and none were made. Details and the
primary source are in `APP_STORE_PRICING_STATUS_2026-09-09.md`.
