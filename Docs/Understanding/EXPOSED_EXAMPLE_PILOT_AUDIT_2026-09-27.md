# Exposed example pilot audit — September 27, 2026

This is development evidence from the user-supplied synthetic pack, not an
independent release gate or a microphone test. The original ZIP and its answer
files were not edited. Its 25 pilot inputs were run through
`SwiftDataThoughtRepository.createCaptureResult` with a new in-memory SwiftData
store for each case, the supplied reference instant and Toronto zone, and
seeded items where supplied. Notification scheduling was disabled; no external
action was performed. The test passes only input text and runtime context to
the repository. The case ID and proposed answer never enter interpretation.

## Answer-key audit before assertions

The broad intention and source ownership in all 25 proposed answers are
supported by their text. No answer was changed to match the implementation.
Several specifications need interpretation before becoming hard assertions:

| Cases | Source-grounded reading and limit |
| --- | --- |
| S001, S013, S097, S101, S105 | A time inside a message or an event description is context, not an alert for sending. The explicitly requested reminder belongs only to its own task. Date-only tasks may still receive the user's configured default notification time; `not_explicit` in this pack means no spoken clock, not notification disabled. |
| S061 | The speaker identifies the saved dentist task and asks to move its date without changing its wording or completion. This is a desired saved-item mutation. The current repository's `.revise` path holds broad amendments for review, so an unchanged seed and a review row are safe incompleteness, never a successful update. |
| S066 | Two seeded appointment reminders are plausible. The envelopes are independent; the cancellation must wait for a target choice. The proposed reply is a second operation that must be tested through a real interaction and repeated to prove idempotency. The current pilot run tests only the initial capture. |
| S069 | “Seven tomorrow” genuinely lacks a.m./p.m. The proposed `dateOnly` form item describes retained intent, not authorization to schedule the app's date-only default notification while the spoken hour remains unresolved. The before-reply state must have no guessed alert; a complete result requires the answer and a final-state check. |
| S072 | “Every twenty four hours” is an elapsed interval through the Toronto clock change, not a daily local-wall-time recurrence. If the app cannot represent that recurrence, a visible unscheduled request is acceptable incomplete recovery. |
| S079 | The bins task should remain visible with an unarmed arrival requirement. The empty initial `items` array must not be read as permission to drop the task while waiting for Home selection and location authorization. A map choice alone does not prove the notification was armed. |
| S044, S103, S110 | One explicitly requested reference note or reflection can contain internal paragraphs and historical actions. Exact titles and one-row string shape are not the core contract; coherent retrieval, no invented Today obligations, and accessible original wording are. |
| S049 | All 30 independent obligations must remain accessible. A checklist is equivalent only when all 30 can be viewed and managed. Row count alone does not prove semantic correctness or recording capacity. |
| S102, S105, S107, S109 | Event-relative timing, ordered dependencies, and a weather condition must remain attached to their task. They do not authorize an inferred alert at the event's start or automatic weather monitoring. A condition the app cannot execute must be visible as such. |

The remaining cases have the same direct source-grounded reading as their
proposed answer. No pilot gold version change was justified. This audit does
not certify the 1,770-case answer key; siblings and compositions are correlated.

## Frozen repository trace

The final 25-case adapter run completed in
`/private/tmp/SpeakItExposedPilotFinal-20260927.xcresult`.
Its raw trace is `Tools/UnderstandingLab/Development/example_pack_pilot_2026-09-27/raw_repository_trace.json`.
Input SHA-256 is
`a1532080ded1a02330b3e8cb4555b8fad8e34cbe036dbc47cadf1c43c2bca996`.
`ThoughtExtractor.swift` SHA-256 was
`076e6b3bdeafb5e184bc7398ce0031a1532b200bc8519be8443eb077a8dd58e2`.
The runner records the full original transcription, seeded before state,
persisted after state, Today/Memory routing, reminder fields, and operation
outcome. It recorded the device's date-only alert setting as 09:00 in all 25
cases. The test passed because it generated a trace; it did not assert gold.

| Evidence | Initial result |
| --- | ---: |
| Pilot captures / proposed semantic items | 25 / 109 |
| Original transcription exactly preserved | 25 / 25 |
| Newly persisted rows / review rows | 313 / 40 |
| Captures with at least one review row | 23 / 25 |
| Requested saved dentist amendment applied (S061) | 0 / 1 |
| Explicit clarification reply paths exercised | 0 / 3 |
| Thirty-job capacity case rows retained (S049) | 30 / 30 |
| Whole captures automatically correct under strict intended type, time, and grouping | 0 / 25 |
| Natural extended roots automatically correct | 0 / 10 |
| Other pilot roots automatically correct | 0 / 15 |
| Rendering coverage | 25 punctuated roots; 0 transformed siblings |
| Correct after clarification | 0 verified; 3 proposed dialogues unrun |
| Review-only captures with source accessible and no action row (S093, S106) | 2 / 25 |
| Wrong saved targets among two seeded cases | 0 observed; neither desired operation completed |
| Unnecessary whole-capture review of otherwise clear material | At least 2 (S093, S106) |
| Source loss | 0 observed in persisted `CaptureSession.originalTranscription` |
| External effects / notification delivery | Not run; scheduling disabled |

The 30-job case has all 30 obligations, including the last one, but classifies
“water the parsley” as shopping. It is a capacity retention success and a
strict semantic mismatch. The other 22 cases besides S049, S093, and S106
persist wrong or extra rows; S093 and S106 are safe but incomplete whole-source
review, including unnecessary review of clear material. S049 also has a wrong
item type. Thus none is counted as whole-capture automatic correctness.

Specific first visible failures include S001 persisting both six and seven
o'clock photo tasks; S013 assigning the train departure time to the text;
S024 retaining the withdrawn ticket purchase; S031 routing the user's email
task to Memory; S044 splitting a single booklet reference into four rows;
S061 creating nine rows without changing the seeded target; S069 scheduling
19:00 before the a.m./p.m. answer; S072 creating a calendar recurrence for an
elapsed interval; S103 and S110 fragmenting one reflection into 19 and 17
rows. These are persisted/display-model outcomes, not mere parser counts.
The repeated clause-shaped titles and source segments show that intention
ownership was already wrong before persistence for these examples; the trace
does not expose every internal parser stage, so a more precise stage claim
requires a dedicated intermediate trace.

For S001, a separate rules-stage probe on the same words made an early wrong
boundary explicit: the clause splitter divided “The old set would make it
look...” into “The old” and “set would make it look...”. That sentence has no
coordinator; the action-opener heuristic in `ClauseJuxtaposition.pieces` is
the applicable route for treating “set” as a fresh verb. This stage attribution
comes from the code path, not from a separately instrumented stage trace. The
probe also emitted the initial six o'clock request and the later
seven o'clock replacement as separate clauses. The repository trace then
persisted both photo tasks. Thus the observed failure starts before
SwiftData insertion; the later correction is not reconciled to the initial
task. The clause probe uses a fixed August clock, so it is evidence for
segmentation only, not the pilot's October due dates. The exact command
input is `Tools/UnderstandingLab/Development/example_pack_pilot_2026-09-27/S001_clause_probe_input.txt`; it joins the
pilot's whitespace without changing its words.

No seeded distractor or named target was mutated in this run. That is not a
saved-target success: the desired S061 amendment was not applied, and S066's
reply was not exercised. Notification delivery, visible versus silent warning
presentation for every row, duplicate reply effects, and real microphone
continuity remain unmeasured. False Today rows are persisted wrong effects;
their impact must not be masked by exact source preservation.

## Controlled narrative candidate

After the initial trace, two bounded source-owner edits were measured on a
frozen source: a declared single Memory is not downgraded merely because a
historical report inside it has a different speaker; and an explicit “keep the
story/one account of...” frame can own its historical actions. Opposite tests
prove that a later “Call Mira tomorrow” or “I also need to call Pat tomorrow”
stays independent. `ThoughtExtractor.swift` SHA-256 is
`92545926d2c483d7bdff4a2fff72bd70154e3c52b2cbd29a56e06b11ead456e0`.
The raw result is
`Tools/UnderstandingLab/Development/example_pack_pilot_2026-09-27/narrative_candidate_trace.json`
(SHA-256 `21f166d4b250833a50c4326433fce0a3a86c4377ee31905d90e42d2fd209c2d2`).

| Whole-capture measure | Initial | Narrative candidate |
| --- | ---: | ---: |
| Source preserved | 25/25 | 25/25 |
| New persisted rows | 313 | 279 |
| Review rows / captures with review | 40 / 23 | 37 / 21 |
| Source-grounded whole-capture correct candidates | 0/25 | 2/25 (S103, S110) |
| Natural extended roots correct | 0/10 | 2/10 |
| Other pilot roots correct | 0/15 | 0/15 |
| Clarification dialogues completed | 0/3 | 0/3 |
| Requested saved amendment applied | 0/1 | 0/1 |
| Capacity obligations retained (S049) | 30/30 | 30/30 |

For the narrative candidate, the mutually exclusive whole-capture disposition
is 2 automatic correct, 0 verified after clarification, 2 safe incomplete
(S093 and S106, full-source review only), and 21 wrong persisted
interpretations. The pilot did not exercise a per-case on-screen review flow,
so those 21 cannot honestly be divided into visible and silent wrong outcomes.
No external notification effect was run. False saved Today rows are themselves
wrong local effects, even without an external notification. The 37 review rows
across 21 cases include at least two unnecessary whole-capture reviews; a
complete review-necessity count needs case-level UI adjudication.

S103 and S110 now each persist one Memory with the full account in the item
source and the exact original in `CaptureSession`. No extra Today action or
review row remains. These two are source-grounded correctness judgments on
exposed synthetic cases, not independent release evidence. S044 still splits
one reference note. The other 23 wrong/incomplete cases are
unchanged. The candidate does not solve wrong times, corrections, saved-item
updates, partial clarification, or general long-capture splitting.

## Candidate mechanism check

A bounded change to recognize explicit single-Memory frames was tried with
opposite independent-task controls. Its focused class had 12 failing tests
out of 114, including both new controls and several existing source-owner
tests. The change and its tests were removed; the source hash above was
restored. It is not an improvement claim. The focused class rerun on the
restored source had 10 failures among 112 tests in
`/private/tmp/SpeakItMemoryFrameBaseline-20260927.xcresult`. Those ten
post-handoff failures already existed on the restored source; the proposed
change added two failing controls and resolved none of the inherited failures.
The later reported-voice and story/account edits reduced that focused class
to 8 inherited failures while their new opposite controls passed. A separate
reference-instructions extension was then rejected: it grouped the positive
case but swallowed an independent later “Also email...” task. The attempted
extension and its test were removed; the source returned to the narrative
candidate hash above. No S044 improvement is claimed.

## Final idea-routing candidate

The full suite on the narrative candidate recorded 1,057 passed, 9 failed,
and 3 skipped across three shards. Eight failures were the inherited
`IntentConsolidationTests` source-ownership cases; one was the first-person
“I just thought of an idea” case being filed as a Note. A bounded fix now
recognizes that first-person idea phrase in the organizer and prevents the
extractor's reported-speech owner from demoting it. Opposite controls for
“Alex just thought of an idea” and Alex quoting “I just thought of an idea”
remain Memory facts. The focused `SwiftDataThoughtRepositoryTests` class
passed 325/325 and the 1,403-case corpus gate had zero blocking failures.

The 25 pilot inputs were rerun on that source. The raw trace is
`Tools/UnderstandingLab/Development/example_pack_pilot_2026-09-27/idea_candidate_trace.json`.
Ignoring generated item/session UUIDs and SwiftData fetch order, every
persisted row and field matched the narrative candidate. Consequently the
pilot disposition remains 2 automatic correct, 0 clarified, 2 safe
incomplete, and 21 wrong persisted. This local idea fix is a regression
repair, not a claimed pilot improvement. Exact hashes and result bundles
are in `measurement_manifest.json`.

All 25 evaluated inputs are distinct roots in their punctuated rendering;
no transformed sibling, concise control, opposite control, or composition
from the pack was run through this repository adapter. Family disposition
on the final candidate is:

| Family | Automatic correct | Safe incomplete | Wrong persisted |
| --- | ---: | ---: | ---: |
| Natural extended | 2 | 1 | 7 |
| Negation scope | 0 | 1 | 0 |
| Clarification dialogues | 0 | 0 | 2 |
| Each of the other twelve sampled families | 0 | 0 | 1 each |

This table covers the 25 pilot roots only. It is not a frequency estimate for
the entire exposed pack or real users.

## Separate recording evidence

The default in-app voice screen now starts in continuous mode and waits for
explicit Finish. This code change removes the automatic 1.9-second timer from
the ordinary in-app path and requires protected audio storage before start.
The 1.9-second timer still exists behind an explicit Auto finish choice.
Neither this text pilot nor simulator UI tests can certify physical microphone
continuity, backend duration, file fidelity, or spoken-intention accuracy.
