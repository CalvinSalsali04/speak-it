# Data Model

## CaptureSession

One complete user statement.

| Field | Purpose |
| --- | --- |
| `id` | Stable unique identifier |
| `originalTranscription` | Preserved original input |
| `createdAt` | Capture timestamp |
| `captureSourceRawValue` | Capture source, including voice and tutorial practice |
| `processingStatusRawValue` | Pending, organizing, complete, or failed |
| `processingError` | Recoverable organization failure detail |
| `operationStateData` | Optional durable saved-item operation receipt, added in V5 |
| `items` | Cascade relationship to extracted items |

## CapturedItem

One structured thought linked to a capture.

It stores the original segment, editable display title, type, category, dates, priority, person, completion/archive timestamps, confidence, clarification/review flags, last modification time, and optional parent relationship.

Enums are stored as raw strings or integers. This keeps persistence explicit and allows unknown future values to fall back safely.

## CaptureAllowanceObligation — V6 candidate

A separate, retained accounting row for every newly committed capture. It has
no relationship to `CaptureSession` or `CapturedItem`, so their deletion and
cascade rules cannot delete an outstanding obligation or refund a debit.

`id` equals the capture session UUID. `chargeKey` identifies its clarification
chain root. `policyRawValue` records the immutable free, Pro, practice or
replacement snapshot. `stateRawValue` moves from pending to charged or exempt;
Pro, practice and replacement rows begin exempt. `finalCharge` is optional until
the definitive result is known, then joins that result's SQLite save.
`createdAt` retains the capture timestamp. No transcript is copied into this row.

The raw session, placeholder and obligation are inserted in one transaction.
Pending free chain keys reserve allowance slots. A charged key is credited at
most once by the separate durable identity journal; deleting rows from capture
history does not remove accounting rows. Tutorial practice remains exempt when
a protected draft is reconstructed by typing. Existing pre-V6 sessions acquire
no invented obligations: their already-used allowance migrates from the greater
legacy Keychain and defaults count.

V6 is a lightweight addition of this entity. Frozen V1–V5 model declarations and
recorded hashes remain unchanged, and the live schema matches frozen V6. Native
`SchemaFreezeTests` migration checks pass for this candidate. Final integrated
release qualification remains pending.

## UserPreferences

Prepared for future briefing, permissions, Shortcuts setup, and preferred capture method. Phase 1 defines and persists the model but does not expose settings UI.

## Relationship and deletion

`CaptureSession.items` has a cascade delete rule. Deleting the only item also removes its now-unused session. A multi-item capture can delete one item without removing its siblings or their original session. Neither operation removes a V6 allowance obligation.


## Optional end-of-named-day deadline metadata

TemporalIntent.deadlineBoundary is an optional encoded-data field with
DeadlineBoundary.endOfNamedDay. It adds no @Model column or schema migration.
Absent metadata decodes as nil and keeps older ordinary-clock behavior.
Unknown or malformed present metadata remains invalid presence; it cannot
fall through to an ordinary start-of-day00:00 interpretation.

A valid boundary retains kind exactDateTime, the spoken CalendarDay and
WallClockTime(0,0), with no calendar window, recurrence, relative duration,
unsupported trigger or user-edited flag. Resolution validates that complete
shape and uses the named local day's calendar interval end. Persisted dueDate
is that exclusive next-day endpoint; the spoken day is not replaced by the
endpoint's date. Intent sourceText retains the entire literal deadline span and its casing.
The source transcript and original segment remain unchanged.

Stored endpoint/intent mismatches, including device-local travel changes,
require review while preserving the stored instant and spoken context. No
automatic retiming or legacy backfill adopts the new interpretation. Unrelated
edits preserve valid boundary metadata; explicit clock edits clear it. A
lossy spoken-day-only reschedule is held for review. Typed fixed-zone consumer
support does not grant source parsing authority for named-zone deadlines.


## Owned clock boundaries (development, October 16, 2026)

`TemporalIntent.clockBoundary` optionally encodes `after` or `before` inside the existing exact-date/time value. Its scalar due date is the source clock's opening/cutoff anchor, not an execution appointment or permission to alert. This adds no SwiftData model column or schema version. Absent metadata preserves old encoded semantics; legacy source is never reparsed to acquire the new relation. Unknown or malformed present metadata remains invalid and requires review.

The initial source proof requires one owned action and one explicit calendar day: today/tomorrow, a named weekday, or a named month plus day. Direct AFTER/BEFORE clock adjuncts can precede or follow the action; existing daypart and clock readers supply the clock. Arithmetic such as quarter after six retains ordinary exact-time meaning. Unsupported ownership, competing clocks, unknown/source named zones, conditions and bare clock bounds do not receive an invented exact appointment. The positive producer preserves an independently chosen Task, Person follow-up or Shopping kind; unsupported event bounds are held.

AFTER opens at the clock anchor and becomes overdue after its owned calendar day ends. BEFORE is the latest cutoff and becomes overdue at that anchor. Requested bound reminders retain their source constraint but remain unscheduled for an exact-time choice. Today, saved-result details, brief, shared widget snapshot and editor retain the relation; invalid or travel-mismatched metadata shows a time review. Unrelated edits preserve original encoded bytes, while an explicit changed date/time clears the bound through the existing user-edited intent factory. Original capture wording stays immutable.
