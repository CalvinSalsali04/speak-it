# Durability destruction pass — release gate met

Semantics are frozen. This pass asked one question only, and never whether a
phrase could be read better:

> A spoken thought is either durably saved, safely recoverable, or clearly
> unresolved. It never silently disappears and never appears twice.

- Release gate: **0 CRITICAL, 0 BEHAVIORAL** — **met**.
- Full unit suite: **413 tests, 0 failures, 1 skipped**.
- Release compile: **clean, no warnings**.

## How a kill is simulated

A process kill is modelled by discarding the repository and building a new one
over the same store, then running the launch recovery sequence in `RootView`'s
order. Everything durable — SwiftData rows, the draft checkpoint, recurrence and
pin metadata — outlives the repository object, so what the next launch sees in a
test is what the next launch sees on device.

Storage failure is modelled with a real file-backed store opened `allowsSave:
false`, which fails saves the way a full disk or an inaccessible store does.

Upgrade is modelled by writing a real version 1 store to disk, closing it, and
reopening it exactly as the release candidate does — never as a clean install.

## Coverage

| Area | Tests | Result |
| --- | --- | --- |
| Capture interruption and relaunch recovery | 6 | Pass |
| Operation interruption (cancel/complete/retract) | 5 | Pass |
| Rapid interaction abuse | 5 | Pass |
| Concurrency and interleaved teardown | 5 | Pass |
| Daylight saving and clock movement | 3 | Pass |
| Interrupted draft recovery | 4 | Pass |
| Timezone change (Toronto ⇄ Hong Kong) | 1 | Pass |
| Store durability across repeated reopen | 3 | Pass |
| Upgrade from version 1 over existing data | 6 | Pass |
| Storage failure | 5 | Pass |

Files: `SpeakItTests/DurabilityTests.swift` (`DurabilityTests`,
`UpgradeDurabilityTests`, `StorageFailureDurabilityTests`).

## Defects found and fixed

### 1. CRITICAL — an interrupted cancellation was replayed at every launch

**What happened.** A capture interrupted before persistence leaves a draft
checkpoint. `recoverInterruptedCaptureDraft()` replayed it through an entry
point that must return a row, so a cancel, complete or retract — which correctly
produce no row — was reported as `saveFailed`. Recovery read that as "storage is
failing, keep the checkpoint and retry later" and kept the draft **forever**.

**Consequence.** Every launch replayed the operation. The destructive half ran
again each time, against whatever matched *then*. A person who said "cancel the
dentist reminder", was interrupted, and later made a new dentist reminder would
have watched it be cancelled again the next time they opened the app — and again
the launch after that. Each replay also left another empty capture session
behind, so the store grew without bound.

**Measured.** Three relaunches of one interrupted retraction produced three
capture sessions and left the draft still pending.

**Fix.** `SwiftDataThoughtRepository` now distinguishes "the operation was
carried out and left no row" from "the save failed", via a private
`SynchronousCaptureOutcome`. The checkpoint is released once the words have been
acted on; only a genuine persistence failure keeps it, which is the case it
exists for. `createCapture`'s public contract is unchanged.

**Regression cover.** `testInterruptedCancellationDraftIsReleasedRatherThanReplayedForever`,
`testInterruptedRetractionDraftIsReleasedRatherThanReplayedForever`,
`testInterruptedDraftIsRecoveredOnceAndThenReleased`.

### 2. BEHAVIORAL — a failed save left a thought visible that was never written

**What happened.** On a save failure `persistChanges` rolled back. `rollback()`
clears the context's pending-change bookkeeping but leaves the objects
registered, so fetches — and therefore every `@Query` behind Today and Memory —
kept returning rows that never reached the store.

**Consequence.** The person was shown an error *and* the thought at the same
time. The thought then disappeared at the next launch. Nothing was corrupted and
nothing durable was lost — the draft checkpoint was correctly retained — but
from the person's side this is the silent disappearance the app exists to
prevent.

**Measured.** After a failed capture on an unwritable store: 0 rows on disk, 1
row still live in the context.

**Fix.** The discard is now made visible to readers by re-reading the store and
settling the pass, immediately after the rollback.

**Regression cover.** `testAFailedSaveWritesNothingDurable`, which asserts the
durable count and the in-memory count separately so the two failure modes can
never be confused again.

## Verified sound, no change needed

- **The raw transcript is committed before extraction**, so classification can
  never cost a capture. A kill between that commit and organization recovers to
  exactly one organized thought, and recovery is idempotent across repeated
  relaunches.
- **"Remembered" is never shown before persistence succeeds.** The confirmation
  is set inside the success branch of `createCaptureResult`, and the draft is
  discarded only after that.
- **Reminder teardown converges on relaunch.** `delete` saves the row before
  tearing down its notification, which is a kill window; the launch and
  foreground reconcile passes rebuild the pending set from the saved items, so a
  notification with no row is disarmed by the next launch either way.
- **Repeated operations do not double-apply.** A second cancellation reports
  nothing found; completing twice does not generate a second occurrence.
- **Rapid abuse does not multiply thoughts.** Twenty identical saves produce one
  thought; two near-simultaneous external intents produce one; twelve distinct
  rapid captures all survive. A duplicate never passes the `createdNewCapture`
  gate, so it is never charged against the free allowance.
- **Clock and timezone changes never rewrite stored intent.** Toronto → Hong
  Kong → Toronto leaves resolved dates untouched, as do both DST transitions and
  repeated relaunches. The temporal backfill never revisits a row that already
  has an answer, so a hand-picked date outranks what the original wording would
  reparse to.
- **Upgrade over existing data is safe.** A real version 1 store opened as the
  release candidate preserves every thought and session, does not move any
  existing reminder, keeps completion state and Memory/Today destination, and is
  stable across repeated opens. A draft written in the previous single-object
  checkpoint format is still recovered.
- **Storage failure degrades honestly.** A failed save reports failure, writes
  nothing durable, keeps the checkpoint recoverable, does not loop, and leaves
  reads working.

## Observation, not a defect

Deduplication is scoped per capture source. The same words arriving by two
different routes at the same moment — Siri and the in-app button, say — produce
two rows, because those are two capture events rather than one delivered twice.
Same-route repeats do collapse, including two share-sheet deliveries. This is
recorded by `testTheSameWordsArrivingByTwoRoutesAtOnce` so the behaviour is
pinned rather than accidental. Widening the window across sources would risk
suppressing genuinely distinct captures, so it is a backlog question, not a
release one.

## Still requires hands-on iPhone QA

Nothing here replaces the physical matrix. Real force-quit and reboot timing,
AlarmKit and notification delivery, geofence crossing, background audio
interruption, StoreKit entitlement restore across an update, and true
install-over-existing-build upgrade all still need a device.
