# Architecture

## Platform

- SwiftUI application targeting iOS 17+
- SwiftData local persistence
- Speech and AVFoundation for live in-app transcription
- App Intents, AudioRecordingIntent, ActivityKit, and App Shortcuts for background capture
- NaturalLanguage rules with optional Foundation Models refinement on supported devices
- XCTest with in-memory SwiftData stores
- No external dependencies or backend

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

Voice data flows through `SpeechTranscriber`: permission request → audio engine → partial Speech results → adaptive natural-pause detection → final transcript → repository. Outside the app, partial text is mirrored into a Live Activity. During an unfinished voice capture, `CaptureDraftStore` also holds an encrypted-at-rest, backup-excluded temporary recording so recognizer or process interruption cannot silently lose the person’s words. It is deleted immediately after a successful save or intentional discard. Failed recordings remain recoverable or deletable in Capture history.

One `CaptureSession` always keeps the complete untouched transcript. Extraction produces up to twelve linked `CapturedItem` records. Rules run immediately on every supported iPhone; Apple Intelligence can refine complex captures locally when Foundation Models are available. Model output is accepted only when every quote is grounded in the original transcript, and deterministic code—not the model—controls dates and reminders.

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
