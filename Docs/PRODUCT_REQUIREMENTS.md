# Product Requirements

## Phase 1 objective

Prove that a typed thought can be stored safely and managed locally without voice, Siri, AI, notifications, or a backend.

## Functional requirements

- Create a `CaptureSession` containing the immutable original text, capture source, timestamp, and processing state.
- Create a linked `CapturedItem` for the manually entered thought.
- Persist both records with SwiftData before showing success.
- Show due, incomplete, unarchived items on Today.
- Show recent, unreviewed, unclear, unscheduled, and completed items in Inbox.
- Show archived items in the Inbox archive scope.
- Allow title, type, category, priority, due date, person, and clarification state to be edited.
- Allow completion and undo completion.
- Allow archive and restore.
- Require explicit confirmation before permanent deletion.
- Preserve original text through every edit.
- Provide useful empty and persistence-error states.
- Label interactive controls for assistive technologies.

## Acceptance criteria

- A non-empty text capture creates exactly one session and one linked item.
- Whitespace-only text is rejected.
- Saved items are visible from a new `ModelContext`.
- Editing structured fields does not change the original capture.
- Completion, archive, and restoration persist.
- Deleting a single-item capture removes the item and its orphaned session.
- The app has Today, Capture, and Inbox destinations.
- The project contains seeded SwiftUI previews and automated repository tests.

## Out of scope

- Microphone and speech recognition
- Siri, App Intents, Shortcuts, Back Tap, and Action Button
- Automatic splitting, classification, date parsing, or language models
- Notifications and briefing preferences
- Accounts, sync, cloud services, analytics, purchases, or third-party dependencies
