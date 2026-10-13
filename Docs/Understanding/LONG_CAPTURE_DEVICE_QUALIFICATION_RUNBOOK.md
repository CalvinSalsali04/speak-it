# Long-capture device qualification runbook

**Status: planned, not executed.** Use only after the semantic candidate is
frozen and physical-iPhone work is authorized. The locked thresholds are in
`LONG_CAPTURE_RELEASE_CRITERIA.md`; this runbook does not change them.
The founder can perform the matrix on one test iPhone without recruited users.
Record that as one speaker and one device, and do not call it population
validation. Vary the scripts and conditions without calling the readings
independent speakers.

## Freeze and setup

Record the source commit or immutable checkout snapshot, unsigned Release
build result, installed build identifier, iPhone model, iOS version, speech
backend, locale, microphone route, time zone, and exact endpoint policy. Keep
the 10 free lifetime captures and existing personal data out of test scoring
by using an agreed test installation and a documented initial store state.
Preserve each capture's original transcript, recovered recording where
available, ASR text, final rows, Needs Review, and operation/reminder effects
locally. Do not send user-authored content to analytics or a remote scorer.

## Preallocated 36-capture matrix

Write and seal each intended meaning and source owner before recording. Use
varied phrasing; do not read the exposed September gate aloud. Each numbered
slot is one whole capture, including its final row inspection. Cross
quiet/noisy and built-in/Bluetooth routes where the test device permits.

| Slots | Family | Required content |
| --- | --- | --- |
| 01–08 | Clear multi-task | 10, 15, 20, 25, and 30 independent intentions across the group; include mixed dates and an end item. |
| 09–14 | Natural rambling | Fillers, false starts, one or more real commitments, durable facts, uncommitted ideas, and ordinary narration. |
| 15–18 | Coherent Memory | One 1–5 minute account per capture, including a long account near the supported 700-word limit. |
| 19–22 | Mixed Today and Memory | Interleaved actions, knowledge, ideas, shared context, and a late action. |
| 23–26 | Corrections and withdrawals | Revised time/person/object, a withdrawn action, and a separate later operation or new task. |
| 27–30 | Quote/report and alternatives | Reported commands, direct commands, rejected options, and explicit final choices. |
| 31–34 | Temporal/person ownership | Multiple people and times, event-relative actions, group context, and a context change. |
| 35–36 | Beginning/middle/end retention | Meaningful first, middle, and last intentions with unrelated material between them. |

Across these slots, intentionally place silent pauses near 1, 2, 3, 5, and 8
seconds at both complete-sounding and unfinished phrases. Record the actual
pause from local audio rather than treating the scripted value as measured.
Include slow/variable pacing, proper names, dates, negation, and realistic
background speech or noise. Run separate short one-command controls for save
latency and accidental long waiting; do not count them in the 36 long-capture
denominator.

## Exact endpoint and correction demonstration

On the isolated test installation, set the test clock to October 5, 2026 at
09:00 in America/Toronto. Record the actual device time, zone and backend.
Use Continuous, start one capture, say “Remind me at six tonight to send Maya
the kitchen photos.” Pause for a measured five seconds without touching the
phone. Say “Actually, make that seven tonight, not six. Also buy eggs.” Tap
Finish. The microphone must remain active through the pause and stop on the
tap. One capture must contain the complete available source, one photo
reminder at 19:00 and one eggs purchase intention, with no 18:00 reminder or
duplicate photo item. Inspect the persisted row and pending notification
request separately. Repeat with measured 1.8, 1.9, 2.0, 2.1, 3, 8, 15 and
30 second pauses, and repeat a representative subset in deliberate Auto
finish. Record each attempt's actual stop reason and whether later words
reached the same capture. An Auto finish stop is judged against its selected
policy; it is not evidence that Continuous survived the pause.

Before starting, agree on a dedicated test installation and a local export
destination. Xcode's Devices and Simulators window can download that app's
container after a failed or interrupted capture; the protected recovery file
is under `Application Support/CaptureRecovery/` while the draft is unresolved.
Successful verified captures normally clear that temporary file, so do not
describe it as an archive of every successful take. Keep a local operator
record of the spoken script and measured pause, capture ID, transcript,
screen state, final items, notification request identifiers and content-free
endpoint trace. Restore automatic date/time after the session. Do not send
captured text or audio to analytics or a remote scorer.

## Score and attribution

For each capture, compare intended meaning and human verbatim transcript to
the ASR transcript, then compare ASR to persisted result. Label the first
failure stage: microphone endpoint, ASR omission/substitution, semantic owner
or route, operation/reminder, persistence, or UI access. Score exactly one
whole-capture verdict: correct, safe incomplete, or unsafe/silent incomplete.
Record every meaningful source span missing from an independently usable row
or visible review, every extra row, and every false executable interpretation.
An intact original transcript is recovery evidence, not a correct verdict.

For each pause, use the DEBUG-only content-free `SpeechEndpointTrace` to record
timer selection, timer fire, audio stop, ASR final, and callback times. Note
whether speech resumed after the timer and whether its words reached the same
capture. Also record duplicate saves, stuck recording state, missing tail,
recovery path, and time from speech end to persisted row. Compare the short
controls against the existing 1.9-second path. Never infer five-minute
readiness from static text tests or from a single speaker's scripted read.

## Capture response budgets to apply before scoring

Keep the short-path gates already in `Docs/CAPTURE_STRESS_TEST_PLAN.md`.
These additional budgets apply to supported continuous captures up to 300
seconds, using monotonic timestamps on the device; the 360-second case is
stress coverage and must still end in a truthful, recoverable state.

| Boundary | Acceptance budget | Failure disposition |
| --- | --- | --- |
| Finish tap → visible finalizing state | Within 1 second for every attempt; target 250 ms | A continued “Listening” claim after this is a UI failure even if audio later saves. |
| Finish tap → microphone stop requested | Within 1 second, with stop reason `manual` | A later automatic timer is not a substitute for the tap. |
| Last accepted frame → protected file sealed or explicit recoverable failure | Within 5 seconds after Finish | Never show success or delete the only file while the seal is unresolved. |
| Processing progress while source is durable | A truthful state update at least every 5 seconds | A long silent wait is a failure; elapsed time alone never means the result is complete. |
| Finish → final transcript and durable organized output | Within 30 seconds for ≤90-second captures; within the audio duration for 91–300-second captures | Exceeding the budget is a latency failure. Keep the protected source and show recoverable processing or a specific failure; do not count a false receipt as success. |

The budgets measure UI acknowledgement, audio durability, transcription and
semantic persistence separately. They are engineering acceptance targets
chosen before the founder run, not measured results or permission to discard
audio at a deadline. Record every actual duration and device configuration;
an unmet budget blocks acceptance on that configuration without weakening
the locked semantic and safety thresholds.

The independent scorer signs the frozen set and reports per-family numerator,
denominator, safe-review rate, zero-tolerance events, and all raw local result
identifiers. Any source change after viewing failures requires a new sealed
unseen set for the release decision.
