# Data Model

## CaptureSession

One complete user statement.

| Field | Purpose |
| --- | --- |
| `id` | Stable unique identifier |
| `originalTranscription` | Preserved original input |
| `createdAt` | Capture timestamp |
| `captureSourceRawValue` | Text, future voice, Siri, or Shortcut source |
| `processingStatusRawValue` | Pending, organizing, complete, or failed |
| `processingError` | Recoverable organization failure detail |
| `items` | Cascade relationship to extracted items |

## CapturedItem

One structured thought linked to a capture.

It stores the original segment, editable display title, type, category, dates, priority, person, completion/archive timestamps, confidence, clarification/review flags, last modification time, and optional parent relationship.

Enums are stored as raw strings or integers. This keeps persistence explicit and allows unknown future values to fall back safely.

## UserPreferences

Prepared for future briefing, permissions, Shortcuts setup, and preferred capture method. Phase 1 defines and persists the model but does not expose settings UI.

## Relationship and deletion

`CaptureSession.items` has a cascade delete rule. Deleting the only item also removes its now-unused session. A future multi-item capture can delete one item without removing its siblings or their original session.
