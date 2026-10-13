# Long-capture program review — September 26, 2026

**Decision:** V1 remains blocked. This is an independent-assisted audit of the
current development work, not a new qualification run. The September 24 frozen
unseen candidate scored 1/40 whole captures correct, 5/40 safe review, and
34/40 incorrect, including one capture with two silently lost committed
actions. That set is now development evidence. Later row-count and destination
improvements cannot be converted into a current whole-capture accuracy rate.

The previous rough “55%” planning estimate is not an empirical reliability
measure and should not be used as a launch forecast. The defensible status is:
the safety and extraction foundations have materially improved, but long messy
speech is still unqualified and the live endpoint can cut it off early.

## What was built and what it proves

- Source occurrences now pass through repair, operation partition, and row
  shaping with visible review for several unowned spans. This is stronger than
  transcript preservation alone. It does **not** prove that a word claimed by
  a row belongs to the *right* meaning or intention.
- Clear 25-item development lists now yield individually accessible rows with
  no extraction-stage count cap. This is a meaningful capacity fix, not unseen
  capacity qualification or proof that every 30-item form is safe.
- Bounded temporal/context edges, quote/report ownership, and local correction
  identity fix known general failures and have opposite-direction tests.
  Their many post-row exceptions still need a whole-capture owner audit.
- The newest local completion receipt resolves one class of completed-action
  report and explicit replacement group without acting on an older saved task.
  Its early return in `ThoughtExtractor.process` bypasses the normal repair,
  operation-partition, and full-source audits. The tail is recursively read
  with operations disabled. Its source-ID offset and first-sentence membership
  are computed locally. The focused occurrence test proves one development
  capture, not this path's universal safety.
- The 1,403-case host corpus and focused iOS tests are regression evidence.
  `Tools/UnderstandingLab/README.md` says the rules and corpus share authorship
  and the corpus is at ceiling. The host probe excludes Foundation Models,
  saved-item target resolution, SwiftData persistence, notifications, and UI.

## Highest-risk remaining mechanisms

### 1. Finish the source-and-owner invariant once, across the whole capture

Represent every meaningful original-source occurrence with a typed disposition:
active intention, retained Memory/context, replaced/withdrawn by an identified
local edit, operation against an identified saved item, or visible unresolved
review. For each retained clause, record its speech act and exact owner set
*before* promoting it to a row. The needed roles are bounded: committed action,
recorded knowledge/idea, reported/quoted content, context/elaboration,
capture-management commentary, and genuinely unresolved source.

The invariant is stronger than a count of covered words. A source occurrence
must be linked to the correct semantic owner, and a withdrawal must carry its
old target, edit cue, replacement, and source IDs. Make rows and operations
consume this one representation. Bring the local completion receipt back
through the same audit rather than adding another special early return. This
is a bounded consolidation of current mechanisms, not a new semantic-map
research program or a broad model segmentation experiment.

**Exit test:** opposite controls for distinct actors/objects, direct versus
reported commands, an actually new task versus recap, a second Memory topic
versus elaboration, and same-word repeated occurrences. Add integrated tests
with pre-existing saved tasks plus mixed operation, receipt, and creation in
one capture. Assert exact source-to-owner edges and final behavior, not only
row counts, substrings, or an empty unowned-ID list.

### 2. Make long recording a measured product behavior

`SpeechTranscriber` can finalize a complete-looking tail after 1.9 seconds of
silence. That policy was optimized for short capture and can end a realistic
brain dump during a thinking pause. Keep the microphone/audio record available
through a provisional endpoint in any long-capture candidate, and compare a
measured continuation policy against short-command latency. Do not switch to
one unmeasured long timeout or assume a VAD alone knows the person is done.

Run a local pilot with scripted pauses near 1, 2, 3, 5, and 8 seconds, ordinary
fillers, background noise, and a completed short command. Record premature
session finalization, recovered tail, duplicate saves, and time to saved row.
The policy choice follows this evidence. A physical iPhone installation is
required for final device claims and remains separately authorized.

The iOS 26 backend currently chooses `DictationTranscriber` with the
`.progressiveShortDictation` preset. Apple documents `SpeechTranscriber` for
long-form and conversational audio. Compare both on the **same local recorded
audio** where supported, with omission, tail, proper-name, date, negation,
latency, and resource results. Do not change the shipping backend from an API
description alone. Keep iOS 17–25 as a separate recognition stratum: its
legacy request permits Apple's speech service and is not fully on-device.

### 3. Qualify the integrated shipping path, not only its host rules

Before an unseen gate, freeze a source commit and build hash. Use an executable
app-level harness with controlled clock/zone and seeded saved items; record
CaptureSession, extracted rows, Needs Review, operations, reminders, and the
optional on-device refinement branch when eligible. Run the host rules probe
as a diagnostic baseline, explicitly separate from the app-level verdict.
Test day boundaries, time zones, and daylight-saving changes outside the
sealed long-capture set.

For microphone evaluation, preserve local audio, a human verbatim transcript,
the ASR transcript, and final structured results. Score endpoint, recognition,
semantic interpretation, persistence, and UI separately. Apple APIs provide
timing/confidence metadata that the current backend requests or has available
but flattens to strings; retaining audio offsets for disputed words would make
review and error attribution more precise. Confidence is evidence, not a
correctness guarantee.

## Anti-loop release sequence

1. **Stop patching exposed sentences.** Cluster current development failures
   by the two mechanisms above. Accept a code change only with a written
   invariant, opposite controls, and a short/simple regression. Keep the old
   gates as regression evidence.
2. **Implement and audit the bounded source-role/owner representation.** Retire
   bypasses and post-row exception paths where the common representation can
   decide. If an owner is genuinely unresolved, preserve it visibly in review
   with no executable interpretation.
3. **Measure endpoint and same-audio ASR alternatives in parallel.** This is
   independent of semantic tuning and may be the dominant product risk.
4. **Run full exact-code verification.** Corpus, full iOS suite, Release build,
   seeded persistence/operation/notification tests, and the integrated harness
   must pass or have a traced, explicitly blocking failure. A compile or
   rules-only pass cannot substitute for this step.
5. **Freeze once.** Independently author and seal at least 240 unseen text
   captures across the 12 locked families with expected meanings and source
   owners before running the candidate. Preserve every raw output and verdict.
   Score whole capture correct, safe incomplete, and unsafe/silent incomplete
   by family. If code changes after seeing the set, commission a new sealed set.
6. **Run a 30+ physical-microphone gate once device work is authorized** on the frozen build,
   preallocating clear lists, messy captures, duration bands, pauses, speakers,
   devices/OS paths, and noise. Protect short-capture latency as an opposite
   product control. Record failure stage and recoverability for every capture.

The locked criteria remain in `LONG_CAPTURE_RELEASE_CRITERIA.md`. Before the
new gate is sealed, supplement its procedure with exact build hashes, seeded
store setup, independent adjudication, a minimum clear-list denominator in
the device set, and an explicit clock/zone matrix. Do not lower the locked
acceptance thresholds after seeing results. Zero observed safety events in a
finite set is a required gate, not proof of a near-zero population failure
rate.

## Research basis and rejected shortcuts

- Google research distinguishes speech/silence detection from whether the
  speaker has finished; a fixed silence boundary can miss filler and speaking
  rate cues. Its long-form ASR work also describes why VAD segmentation can
  split hesitations within one intended phrase. These support a measured
  endpoint policy, not adoption of a new model by assertion.
  <https://research.google/pubs/improved-end-of-query-detection-for-streaming-speech-recognition/>
  <https://research.google/pubs/e2e-segmenter-joint-segmenting-and-decoding-for-long-form-asr/>
- Apple documents long-form `SpeechTranscriber`, finalized versus volatile
  results, audio time ranges, and local file transcription. Compare its actual
  output to the current backend before making a product change.
  <https://developer.apple.com/videos/play/wwdc2025/277/>
- ASR errors differ in their downstream harm; word error rate alone does not
  score names, dates, negation, or task ownership adequately.
  <https://aclanthology.org/L16-1297/>
- Do not add a broad Foundation Models segmentation experiment, a server-side
  transcript service, or an open-source parser/VAD dependency as a shortcut.
  A narrow on-device adjudicator is a later option only for residual ambiguity
  after the deterministic owner representation and measured gates exist.

## Evidence boundaries

This review inspected current source and documentation and included independent
read-only code, validation, and primary-source research reviews. It did not
modify the shipping app, run a new unseen qualification, or use a physical
iPhone. The previous 1/40 frozen gate, later development probes, 1,403-case
regression corpus, focused simulator checks, and Release compile answer
different questions and must remain labelled separately.
