# Capture performance benchmark

## Product metrics

Speak It has two headline latency metrics:

- `CaptureReadyLatency`: capture activation to the microphone actually running.
- `CaptureToOrganizedLatency`: the last detected voice activity to a real row
  rendered from the final persisted `CapturedItem`.

The saved confirmation deliberately renders `CapturedItemRow` from the
repository result. An “Organizing…” placeholder does not end either metric.
Notification scheduling, analytics delivery, current-location resolution, and
cloud synchronization happen after persistence and do not hold up the row.

Every elapsed value is calculated with Swift's monotonic `ContinuousClock`.
`Date` remains only for persisted calendar facts and human-readable diagnostic
timestamps; it is never subtracted to produce performance latency. Changing the
device time or time zone during a capture therefore cannot corrupt a sample.

## Instrumented milestones

The `com.calvinwak.SpeakIt` / `CapturePipeline` signpost stream records:

| Milestone or interval | Meaning |
| --- | --- |
| `CaptureActivated` | The app accepted the capture entry action |
| `CaptureReadyLatency` | Activation to the audio engine reaching Listening |
| `MicrophoneReady` | Audio input is genuinely running |
| `SpeechEndpointDetection` | A candidate interval restarted on each useful audio frame; the final interval before `EndOfSpeechDetected` is last useful audio → endpoint decision |
| `EndOfSpeechDetected` | Manual stop or the adaptive pause detector finalized input |
| `TranscriptFinalization` | End detection to the final transcript callback |
| `FinalTranscriptAvailable` | Text handed to the repository |
| `RawCapturePersistence` | Immutable transcript and fallback row committed |
| `SemanticParsing` | Extraction/classification, including any on-device refinement |
| `TemporalResolution` | Deterministic date, time, recurrence, and place parsing |
| `OrganizedPersistence` | Final organized items committed to SwiftData |
| `SwiftDataSaveComplete` | The final persistence transaction returned |
| `EndDetectionToOrganizedLatency` | End detection to the real organized row rendering |
| `OrganizedRowVisible` | The persisted row is onscreen |
| `RowToNotificationScheduling` | Organized row rendering to the independent notification result, when rendering wins the race |
| `NotificationSchedulingFinished` | The independent notification request finished, whether accepted or not |
| `NotificationAcceptedBySystem` | At least one scheduled reminder was accepted later |

The privacy-safe `capture_performance` analytics event reports integer
milliseconds and a closed capture kind only. It never includes a transcript,
title, person, date, place, recording, search term, or identifier. Analytics is
still disabled unless the existing build key is configured and the person has
left analytics enabled.

`capture_total_ms` uses the last detected voice activity as its origin. Because
that point is known retrospectively from audio activity, the analytics sample
uses the monotonic audio-callback instant directly. In Instruments, inspect the
final `SpeechEndpointDetection` candidate followed by
`EndDetectionToOrganizedLatency`; together they are the same golden path.

Only a completed, stable repository result enters the headline distribution.
Pending/failed sessions are recoverable and may be reorganized later, so they
are excluded. An unresolved “here” location is also excluded because its
background coordinate snapshot can legitimately change the row's routing.
No semantic or temporal pass runs after a normal completed result is returned.

## Targets

These are product targets for a normal short capture on a real iPhone 13, not
simulator pass/fail thresholds.

| Stage | Great | Acceptable | Investigate |
| --- | ---: | ---: | ---: |
| Final voice activity → end detected | < 300 ms | < 600 ms | > 1,000 ms |
| End detected → final transcript | < 300 ms | < 600 ms | > 1,000 ms |
| Semantic parsing, excluding temporal work | < 100 ms | < 250 ms | > 500 ms |
| Temporal resolution | < 50 ms | < 150 ms | > 300 ms |
| Final organized persistence | < 50 ms | < 150 ms | > 300 ms |
| Persistence → organized row | < 50 ms | < 150 ms | > 300 ms |
| Final voice activity → organized row | < 500 ms | < 1,000 ms | > 1,500 ms |

Report p50, p90, p95, and worst case. Do not use the mean as the release gate.

## Automated gate

`testSemanticCaptureCorpusHasASignpostedPerformanceRegressionGate` runs 204
rule-based captures per measurement pass using the small smoke corpus below. It
records `SemanticParsing` with `XCTOSSignpostMetric` and fails when monotonic
elapsed p95 exceeds 250 ms per capture on the test host.

- `Call Catherine tomorrow at 5`
- `Catherine's birthday is May 3`
- `Remind me in one hour to message Catherine`
- `Finish Friday, remind me Wednesday at 4`
- `Call Mom tomorrow and email Alex Friday`
- `The storage room code is 4821, and buy laundry detergent`

The normal test command runs the gate as part of `SpeakItTests`. In Xcode, add a
performance-test baseline after collecting stable CI history so XCTest also
flags distribution drift in its signpost measurement.

This six-phrase corpus is a performance smoke test, not evidence of semantic
correctness. Keep the larger semantic torture corpus as a separate correctness
gate. A fast wrong classification fails the product even when this test passes.

## Speech Accuracy Lab

Debug builds expose **Account & Settings → Developer testing → Measure speech
accuracy**. Run this on a physical iPhone: simulator or synthetic speech is not
evidence of real microphone accuracy. The lab asks the person to read twelve
fixed phrases spanning ordinary language, names, dates/times, numbers,
self-correction, opening/final words, longer capture, and a quiet voice.

For every take it records no audio and calculates two distinct local metrics:

- **Content accuracy:** `1 - word edit distance / reference words`, weighted
  across all words. Capitalization, punctuation, diacritics, and equivalent
  spoken-number formatting such as `four thirty` versus `4:30` are ignored.
- **Critical-detail accuracy:** exact normalized recovery of the case's names,
  dates, times, quantities, and other high-cost details. This is the primary
  release metric; high average word accuracy cannot hide a wrong person or time.

The scorer also reports exact-transcript rate, requested and actual recognizer
backend, microphone profile, and content-free signal quality. A developer-only
selector runs the same set through enhanced iOS 26 dictation or the legacy
recognizer; it does not alter production routing. The fixed expected sentence
is never passed to the recognizer as contextual vocabulary. Results stay in the
debug build's local settings; the exported text report contains
expected/recognized text and metrics but never audio.

Treat fewer than 30 recordings per configuration as an early signal, 30–99 as
directionally useful, and 100 or more as the minimum credible local benchmark.
For an audio-profile or recognizer decision, use the same speaker, phone, room,
distance, and phrase count for every configuration, alternate configuration
order between rounds, and compare critical-detail accuracy first, then weighted
content accuracy, then latency/energy. Do not select a path from Apple's raw
confidence alone.

## Physical-device run

Use a release-like build and Instruments’ `os_signposts` instrument, filtered
to subsystem `com.calvinwak.SpeakIt` and category `CapturePipeline`. Record 30
captures for each condition in a Release build without the debugger attached,
then export the trace with the build number:

- warm app on Today;
- cold launch then capture;
- Home Screen Quick Action;
- Back Tap or the fastest configured external entry route;
- simple memory (`Catherine likes sushi`);
- simple task (`Call Catherine`);
- timed action (`Call Catherine at 5`);
- relative reminder (`Remind me in one hour`);
- complex temporal (`Finish Friday but remind me Wednesday`);
- a 20-second thought and a multi-thought capture;
- 10, 500, and 2,000 stored items;
- Airplane Mode and Low Power Mode;
- phone warm after prolonged use;
- immediately after a local-midnight or time-zone change.

For every capture, record correctness beside the timings: expected and actual
destination, title correctness, reminder correctness, and whether review was
required. Calculate the headline p50/p90/p95/worst only from captures whose
final destination, title, and reminder were manually verified as correct.
`pipeline_complete` in analytics means the save pipeline finished; it is not a
claim of semantic correctness and must never be used as that filter.

The iOS Speech path still needs a same-device comparison against
`SpeechAnalyzer` on iOS 26+. Use the same 30–50 recorded sentences and compare
time to first partial, time to final transcript, word accuracy, names, numbers,
dates, CPU, and energy. Keep the current fallback until device evidence shows a
meaningful improvement.

## Library scale policy

Speak It Pro has no user-visible capture or item-count ceiling. "Unlimited
capture" remains the product contract; available local or iCloud storage can
fail independently, but the app must not turn either condition into a hidden
item quota. A storage failure must preserve recoverable input, explain the
problem, and leave existing data untouched.

Capacity engineering is measured in persisted `CapturedItem` rows rather than
capture sessions because one statement can produce several items and rows drive
query, rendering, search, and snapshot costs.

Use this internal scale ladder:

- 10,000 items: routine heavy-user benchmark;
- 50,000 items: minimum long-lived Pro-library target;
- 100,000 items: stress test, not a customer-facing promise.

At 10,000 and 50,000 items, record cold launch, first usable Today render,
Memory open, exact and non-exact search, capture-to-organized-row latency,
iCloud snapshot encode/decode/merge duration, snapshot byte size, and peak
memory. Measure manual-stop processing separately from automatic endpointing. Manual-stop
processing retains the under-one-second target; automatic-stop latency includes
the 1.9-second complete-speech silence window (4/8 seconds for uncertain or
incomplete endings) plus processing. These are targets and configured windows,
not measured iPhone results.

Do not add these data sets to the routine unit-test run. Generate them only for
the dedicated physical-device scale pass. If all-library fetching, in-memory
search, or whole-file iCloud snapshots fail the 50,000-item pass, fix those
operations with indexing, bounded queries, or incremental synchronization; do
not impose a Pro item cap.

## Known render hot spots

A source audit on 2026-09-03 closed the cheap, behaviour-neutral cases (shared
intent decoder, memoized person names, predicate lookups by ID, cached regexes,
the editor's cached delivery reading, embedding warm-up at launch, Today's
timer built once — see `DECISIONS.md`). What is still open is measurable on a
large library and belongs to the next performance pass:

- **`TodayView` recomputes its section chain several times per `body`.**
  `activeActions`, `overdue`, `scheduledToday`, `noDate` and `comingUp` are
  computed properties referenced from a dozen places in one render; each is a
  full filter plus a sort. Compute one sections value per pass.
- **`reminderSignature` joins one string per render** and is compared by
  SwiftUI on every pass; the first evaluation also runs the pipeline for every
  timed item before the delivery cache is warm. Hash instead of join, and warm
  the cache off the main actor at launch.
- **Launch and every foreground run unbounded fetches** in
  `backfillTemporalIntents`, `resolveCombinedPlaceAndTimeHoldouts` and
  `reconcilePendingReminders`. Add predicates so they scan the rows that need
  work rather than the whole table.
- **Memory home counts each collection with its own pass** over the active
  items; four cards, one pass each. One pass, four counts.
- **`makeICloudSnapshot` fetches the whole table after every save**, on the
  main actor, debounced two seconds.
