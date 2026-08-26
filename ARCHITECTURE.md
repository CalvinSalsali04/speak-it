# Architecture

## Platform

- SwiftUI application targeting iOS 17+
- SwiftData local persistence
- Speech and AVFoundation for live in-app transcription
- App Intents, AudioRecordingIntent, ActivityKit, and App Shortcuts for background capture
- NaturalLanguage rules with optional Foundation Models refinement on supported devices
- XCTest with in-memory SwiftData stores
- The iOS target uses Apple frameworks only; the optional referral program uses
  the separately deployed Node service in `ReferralService`

## Data flow

```text
Voice or text capture
    ↓
SpeechTranscriber / App Intent
    ↓ raw transcript checkpoint
CaptureDraftStore
    ↓ durable parent + placeholder
ThoughtRepository protocol
    ↓
SwiftDataThoughtRepository
    ↓ ThoughtExtractionEngine
Rule-based extraction → optional on-device Foundation Models refinement
    ↓ atomic item replacement
ModelContext → local SwiftData store
    ↓
ReminderScheduler + @Query-backed SwiftUI views
```

Views may query models with `@Query` for presentation, but they do not insert, mutate, save, or delete persistent models directly. All commands pass through `ThoughtRepository`, injected with a custom SwiftUI environment value.

`PersistenceController.shared` owns the production `ModelContainer`. In-app and outside-the-app capture use the same repository path, so both follow the same extraction, validation, reminder, and durability rules.

Voice data flows through `SpeechTranscriber`: permission request → model preheat → audio engine → first-buffer readiness cue → partial Speech results → adaptive natural-pause detection → final transcript → repository. The Core Audio tap performs only a bounded buffer copy and level measurement; ordered recognition conversion, recovery-file writing, and quality analysis run on `SpeechCaptureAudioProcessor` away from the real-time callback. That processor is synchronously drained before the backend receives `endAudio()`, preserving the final queued syllable. Recognition itself runs behind the `SpeechRecognitionBackend` protocol (`SpeechRecognitionBackend.swift`): on iOS 26+ with the current locale's model installed, capture uses Apple's on-device `SpeechAnalyzer` with the dictation-specific `DictationTranscriber`, progressive high-quality results, N-best/confidence attributes, lingering model retention, and `SpeechDetector` voice activity. This is the Apple path documented to consume contextual strings. Otherwise — older iOS, unsupported locale, or a model still downloading in the background — it falls back to the original `SFSpeechRecognizer` path, so capture is never blocked on a model download. Both backends feed the same orchestration, vocabulary corrections, and durability machinery. Context is ranked and capped at Apple's 100-phrase limit; only the preferred side of an explicit correction is boosted. Outside the app, partial text is mirrored into a Live Activity. During an unfinished voice capture, `CaptureDraftStore` also holds an encrypted-at-rest, backup-excluded temporary recording so recognizer or process interruption cannot silently lose the person’s words. It is deleted immediately after a successful save or intentional discard. A recording whose recovery fails is never removed automatically: Capture history offers Try Again, Type Instead, and a confirmed Delete Recording, and deletion writes a tombstone in `CaptureDraftStore` so a checkpoint written elsewhere cannot resurrect it on the next launch. Failure copy comes from `CaptureRecoveryPresentation`, keyed on `CaptureRecoveryFailureKind` rather than the recognizer's own message.

Natural-pause detection is a bounded state machine rather than one global silence
timer. Apparently complete wording keeps the 1.1-second fast path. Ambiguous
endings show **Still listening…** and wait up to 4 seconds; strong continuation
cues use the same status and wait up to 8 seconds. A new transcript cancels and
reclassifies the pending endpoint. Recent microphone activity can briefly rebase
the decision before the
recognizer catches up, but those deferrals are capped so background noise cannot
hold the microphone open indefinitely. Manual pulse taps, interruptions, and
protected-recording recovery retain their existing precedence. A backend only
reports whole-stream completion after the app closes its audio input; stable
SpeechAnalyzer segment results are assembled without being mistaken for the end
of the user's turn.
Endpoint classification tokenizes spoken letters and numbers independently of
punctuation, so pause-induced formatting such as `tomorrow. At.` cannot hide the
final continuation word. Display and persistence still retain the recognizer's
original punctuation unchanged. The same lexical signature stabilizes partial
results: formatting-only ASR revisions update the visible transcript without
restarting the pause clock or hiding its prompt, while word additions, removals,
or substitutions cancel and rebuild the decision. A retraction to no lexical
content cancels the pending endpoint.
See `VOICE_ENDPOINTING_DECISION.md` for the evidence, edge cases, and beta gate.

`CapturePerformanceTrace` follows the in-app path from activation to microphone
readiness and from the last detected voice activity to a real
`CapturedItemRow` rendered from the final persisted model. OSSignposter stages
separate transcript finalization, semantic parsing, temporal resolution, raw
durability, final persistence, rendering, and later notification acceptance.
All elapsed values use `ContinuousClock`; wall-clock `Date` values never enter
latency arithmetic. Legacy voice activity is timestamped on the audio callback
before UI throttling; iOS 26 uses Apple's trained detector so steady noise does
not extend a turn. The endpoint decision and final transcript are separate
milestones. Recoverable or asynchronously enriched rows are excluded until they
are stable.
Only closed enums and integer durations may enter performance analytics; the
trace never retains or logs user-authored content. See
`PERFORMANCE_BENCHMARKING.md`.

Inside rule-based extraction the order is: speech repair, then operation
partitioning, then **intent consolidation**, then clause splitting, then
organizing. Consolidation (`IntentConsolidator`) answers *how many things were
said* before anything answers *what they are*. It can only ever collapse a
capture to one item, never split one, and it fires only when the wording is
positively narrative — so a paragraph elaborating on a single phone call becomes
one row, while a list of three errands is left to the splitter untouched.

Destination is decided by two independent readings that must agree.
`ActionabilityReader` reads the wording; `CapturedItem.belongsInToday` /
`belongsInMemory` read the stored item. Both follow one rule: **a date says when
something is true, not that there is something to do.** A resolved date never
moves a fact to Today; only a reminder — asked for out loud, or set by hand in
the editor — does. Memory then splits People from Reference purely on whether
the item names somebody.

Semantic readers match grammatical evidence, never arbitrary substrings.
Taxonomy uses whole words and explicit phrase frames; a bare clock is read only
when the item or reminder context permits one; and motion-shaped words require
a spatial complement before they create a place trigger. A fronted condition
belongs to the instruction after its comma rather than becoming a second item.
When that condition is clear but cannot be monitored (for example payday or
another event completing), its temporal intent records an unsupported
condition and Needs review says **Trigger not supported** instead of pretending
the user omitted a time.

### The structural layer

`ClauseStructure.swift` holds the linguistic reading the rest of the pipeline
asks questions of. It exists because the same question kept being answered by a
different local rule each time.

`SentenceContext` tags a whole clause once with `NLTagger` and keeps the token
spans, so a rule can ask about a *part* of a sentence without re-tagging that
part on its own. That matters because `NLTagger` is contextual and answers
differently about a fragment: "cassava" is a Noun in "buy plantains and cassava"
and a Verb by itself. It never lets `nameType` decide a clause boundary — that
tag only fires on a capitalized token, and a reading that turns on it is a
reading the speaker cannot control.

`ClauseScope` finds one boundary: where the matrix speech act ends and a
reported or quoted proposition begins. It distinguishes reporting ("Sarah
said…"), communicating ("text Mike that…") and reminding, recovers the speaker
and recipient when structure gives them, and reads the actor — deliberately
including `unresolved`, because inventing one puts a task on Today that nobody
agreed to do. It is not a dependency parser and not recursive.

`TemporalCommitment` answers whether a stated day was settled on. Two candidate
days, a hedge with nobody behind it, or a question all mean the resolver's
instant is not a plan.

`SemanticState` records how settled a reading is — `resolved`,
`underspecified`, `contested`, `unsupported` — with a named `SemanticGap` rather
than a numeric confidence. A person can be shown a reason; nobody can be shown a
0.62. Actionability stays asymmetric: anything short of `resolved` may still
produce a row and may not produce an alarm.

`TranscriptProvenance` keeps what was said beside what was read. The repair
chain runs before understanding, which is the right order, but `sourceQuote` is
cut from the repaired text — so every row also carries `rawQuote`, the span of
the original transcript it came from, and `wasRepaired`. `ContentDriftTests`
asserts across the whole corpus that no quote holds a word the person never
said unless a repair is recorded in its span. Titles are exempt and reported
separately, because the contract has them paraphrase.

One `CaptureSession` always keeps the complete untouched transcript. Extraction produces up to twelve linked `CapturedItem` records. Rules run immediately on every supported iPhone; Apple Intelligence can refine complex captures locally when Foundation Models are available. Model output is accepted only when every quote is grounded in the original transcript, and deterministic code—not the model—controls dates and reminders.

## Referral boundary

The core product does not depend on Speak It servers. When the production
referral URL is configured, the app keeps a random UUID and credential in
Keychain and uses the UUID as StoreKit's `appAccountToken`. Only that identifier,
referral codes, and App Store-signed transaction data cross the boundary. The
backend verifies Apple's JWS, prevents self-referral and replay, and records a
minimal referral/reward ledger. It never receives thoughts, audio, tasks,
memories, profile fields, contacts, places, or analytics events.

```text
Keychain UUID + credential
    ↓ accept/share invite
ReferralService ledger
    ↓ redeem Apple offer code
StoreKit signed transaction JWS
    ↓ verify with Apple root certificates
Qualified referral → one reward
    ↓
Apple one-time offer code or signed promotional offer
```

The Release configuration keeps the referral API URL empty by default. This is
a truthfulness gate: reward language is not visible unless a deployment is
explicitly connected.

## Boundaries

- `Models`: stored entities and raw-value domain enums
- `Repositories`: validation, write operations, transactions, and persistence errors
- `Features`: screen-specific presentation and interaction
- `Intents`: system-visible actions and Siri/App Shortcut phrases
- `Components`: reusable rows, empty states, and error presentation
- `Preview Content`: isolated in-memory sample environment
- `SpeakItTests`: repository contract and persistence behaviour

## Failure strategy

- Validate before insertion.
- Insert and commit the raw capture plus placeholder before organization work.
- Replace the placeholder with all extracted children in one second transaction.
- Roll back failed writes and surface a user-readable error.
- Do not clear capture text unless persistence succeeds.
- Queue interrupted drafts so a later Back Tap cannot overwrite an earlier capture.
- Retry recognition from protected temporary audio after a live-recognizer failure; never discard it unless persistence succeeds or the person explicitly deletes it.
- Voice transcription is not reported as saved until the repository save succeeds.
- Never execute destructive, negated, hypothetical, or reported instructions; retain them as reviewable items.
