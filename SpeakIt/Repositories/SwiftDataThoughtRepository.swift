import CoreLocation
import Foundation
import SwiftData
import WidgetKit

@MainActor
final class SwiftDataThoughtRepository: ThoughtRepository {
    private static let externalCaptureDeduplicationWindow: TimeInterval = 5
    private static let inAppCaptureDeduplicationWindow: TimeInterval = 15

    typealias PlaceReminderDelivery = @MainActor (
        UUID,
        String,
        String,
        String
    ) async -> ReminderSchedulingResult
    typealias PlaceReminderCancellation = @MainActor (String) -> Void

    private let modelContext: ModelContext
    private let placeReminderDelivery: PlaceReminderDelivery
    private let placeReminderCancellation: PlaceReminderCancellation
    private let requestsReminderAuthorization: Bool
    private let permitsOnDeviceIntelligence: Bool
    private var isApplyingCloudSnapshot = false
    private var lastPublishedToday: SharedTodaySnapshot?
    private var iCloudReconciliationTask: Task<Void, Never>?
    private var locationDeliveriesInFlight: Set<String> = []

    init(
        modelContext: ModelContext,
        placeReminderDelivery: PlaceReminderDelivery? = nil,
        placeReminderCancellation: PlaceReminderCancellation? = nil,
        requestsReminderAuthorization: Bool = true,
        permitsOnDeviceIntelligence: Bool = true
    ) {
        self.modelContext = modelContext
        self.requestsReminderAuthorization = requestsReminderAuthorization
        self.permitsOnDeviceIntelligence = permitsOnDeviceIntelligence
        self.placeReminderDelivery = placeReminderDelivery ?? { itemID, title, place, identifier in
            await ReminderScheduler.deliverPlaceReminder(
                itemID: itemID,
                title: title,
                placeDescription: place,
                notificationIdentifier: identifier
            )
        }
        self.placeReminderCancellation = placeReminderCancellation ?? { identifier in
            ReminderScheduler.cancelPlaceDelivery(notificationIdentifier: identifier)
        }
    }

    func recoverUnorganizedCaptures() {
        let completeRawValue = ProcessingStatus.complete.rawValue
        let descriptor = FetchDescriptor<CaptureSession>(
            predicate: #Predicate { session in
                session.processingStatusRawValue != completeRawValue
            },
            sortBy: [SortDescriptor(\CaptureSession.createdAt, order: .forward)]
        )

        if let sessions = try? modelContext.fetch(descriptor) {
            for session in sessions {
                // Recovery re-reads the words at every launch. If those words
                // trap the rules pipeline, one capture becomes a crash on
                // every launch until the app is deleted. The launch is counted
                // before the risky work and cleared after it, so a session
                // that has already cost two launches keeps its durable
                // fallback row in Needs review instead of being read again.
                let attempts = CaptureRecoveryAttemptLedger.begin(session.id)
                guard attempts <= CaptureRecoveryAttemptLedger.maximumAttempts else {
                    quarantine(session)
                    continue
                }
                recoverOrganization(of: session)
                CaptureRecoveryAttemptLedger.finish(session.id)
            }
        }
        polishPersistedDisplayTitles()
        backfillTemporalIntents()
        resolveCombinedPlaceAndTimeHoldouts()
    }

    private func recoverOrganization(of session: CaptureSession) {
        let extraction = ThoughtExtractionEngine.extractWithRules(
            session.originalTranscription,
            referenceDate: session.createdAt,
            permitsOperations: session.captureSource != .tutorial
        )
        // A capture that asked to cancel, complete or withdraw must not
        // be rebuilt into an item by recovery. Re-reading the operation
        // is safe: the words have not changed, so the reading has not
        // either.
        var creating = extraction.reviewingMultipleOperations()
        if let request = extraction.pendingOperation {
            guard let outcome = try? applyCaptureOperation(request, session: session) else {
                // The pending capture remains durable and can be retried on
                // another launch; never claim a choice hold was saved here.
                return
            }
            if case .notFound = outcome, !extraction.items.isEmpty {
                creating = ThoughtExtractionEngine.extractWithRules(
                    session.originalTranscription,
                    referenceDate: session.createdAt,
                    permitsOperations: false
                )
            } else {
                if case .notFound = outcome {
                    // The lookup failed, but the words still belong to this
                    // capture. Keep its pending review row for later recovery.
                    ensureFallbackItem(for: session)
                    closeSession(session)
                }
                return
            }
        }
        ensureFallbackItem(for: session)
        _ = organizePersistedCapture(
            session: session,
            extraction: creating,
            schedulesReminders: true
        )
    }

    /// Leaves a capture as the words the person said, filed for review, and
    /// stops reading them at launch. The original transcript is untouched.
    private func quarantine(_ session: CaptureSession) {
        ensureFallbackItem(for: session)
        session.processingStatus = .failed
        session.processingError = CaptureRecoveryAttemptLedger.quarantineMessage
        CaptureRecoveryAttemptLedger.quarantine(session.id)
        try? persistChanges()
    }

    /// Releases items that older builds held in review for naming a *named*
    /// place and a time together ("when I go to Sobeys, remind me … in one
    /// hour").
    ///
    /// A named place cannot be geofenced, so for those sentences the stated
    /// time wins at capture, and legacy holdouts are re-derived the same way:
    /// reparse the untouched original wording, keep the timed reading, drop
    /// the unenforceable place trigger. A reminder whose moment has already
    /// passed lands as an honest overdue row rather than staying stuck.
    ///
    /// A combination built on a *saved* place — "when I get home tonight" —
    /// is deliberately left alone: it is held for review at capture on
    /// purpose, because Speak It can enforce either half and must ask which.
    /// A place the person set by hand in the editor is never touched either.
    private func resolveCombinedPlaceAndTimeHoldouts() {
        guard let items = try? modelContext.fetch(FetchDescriptor<CapturedItem>()) else { return }
        var changed = false

        for item in items
        where !item.isArchived
            && !item.isCompleted
            && item.locationIntent.map({ intent in
                if case .named = intent.place { true } else { false }
            }) == true
            && item.locationIntent?.isUserEdited != true
            && (item.temporalKind ?? TemporalKind.none) != TemporalKind.none {
            let reparsed = ThoughtOrganizer.organize(
                item.originalTextSegment,
                referenceDate: item.createdAt
            )
            item.locationIntent = nil
            if item.reminderDate == nil { item.reminderDate = reparsed.reminderDate }
            if item.dueDate == nil { item.dueDate = reparsed.dueDate }
            item.temporalIntent = reparsed.temporalIntent
            item.needsClarification = reparsed.needsClarification
            item.lastModifiedAt = .now
            changed = true
        }

        guard changed else { return }
        // Best effort, idempotent: an interrupted pass leaves the rest for the
        // next launch. Scheduling happens in `reconcilePendingReminders`.
        try? modelContext.save()
    }

    /// Gives rows written before schema version 2 the temporal intent they were
    /// never able to store.
    ///
    /// The recovery is only possible because Speak It never discards what a
    /// person actually said: reparsing `originalTextSegment` against the item's
    /// own `createdAt` reconstructs the same intent the capture would produce
    /// today. Where the wording no longer yields one — an item whose date was
    /// set by hand in the editor, say — the intent is recorded as an exact
    /// instant rather than invented, because a stored `9:00` on an old row is
    /// not evidence the person ever said nine o'clock.
    ///
    /// Resolved dates are never rewritten here. A person's existing reminders
    /// must not move because the app learned to describe them better.
    private func backfillTemporalIntents() {
        guard let items = try? modelContext.fetch(FetchDescriptor<CapturedItem>()) else { return }
        var changed = false

        // Only rows that have no intent at all. A user-edited one is never
        // revisited, and neither is one already reconstructed.
        // An unresolved row does not authorize adopting timing from its words.
        // In particular a missing-target revision must remain the same held
        // request after launch; its "tomorrow" is not a new task's date.
        for item in items where item.temporalIntent == nil && item.itemType != .unclear {
            item.temporalIntent = reconstructedIntent(for: item)
            changed = true
        }

        guard changed else { return }
        // Best effort. An interrupted backfill simply leaves rows for the next
        // launch, which is why this is idempotent and lives outside migration.
        try? modelContext.save()
    }

    private func reconstructedIntent(for item: CapturedItem) -> TemporalIntent {
        let reparsed = ThoughtOrganizer.organize(
            item.originalTextSegment,
            referenceDate: item.createdAt
        ).temporalIntent

        // Trust the reparse only when it agrees with what is actually stored.
        // Wording that resolved to a different day than the row holds means the
        // date was changed after capture, and the row is the truth.
        if reparsed.kind != .none {
            let calendar = Calendar.autoupdatingCurrent
            let storedDay = item.dueDate.flatMap { CalendarDay(from: $0, calendar: calendar) }
            if reparsed.day == nil || storedDay == nil || reparsed.day == storedDay {
                return reparsed
            }
        }

        guard let stored = item.dueDate ?? item.reminderDate else {
            return .none
        }
        let calendar = Calendar.autoupdatingCurrent
        let components = calendar.dateComponents([.hour, .minute], from: stored)
        return TemporalIntent(
            kind: .exactDateTime,
            day: CalendarDay(from: stored, calendar: calendar),
            time: WallClockTime(hour: components.hour ?? 0, minute: components.minute ?? 0),
            timeZoneIdentifier: calendar.timeZone.identifier,
            timeZoneBehavior: .deviceLocal,
            sourceText: item.originalTextSegment
        )
    }

    /// Replays the checkpoints left behind by captures that never finished.
    ///
    /// A checkpoint is released once the words have been acted on — whether that
    /// produced a thought or carried out a cancellation that produced none.
    /// Keeping it past that point is not caution, it is a repeat: the draft is
    /// replayed at every launch, and for a cancel or a complete that means the
    /// destructive half runs again each time, against whatever now matches. A
    /// person who re-made the reminder they had cancelled would watch it be
    /// cancelled again the next time they opened the app.
    ///
    /// Only a genuine persistence failure keeps the checkpoint, which is the
    /// case it exists for.
    func recoverInterruptedCaptureDraft() {
        while let draft = CaptureDraftStore.recoverable() {
            // Same guard as `recoverUnorganizedCaptures`: a checkpoint whose
            // words trap the pipeline has already cost two launches by the
            // time this is true, so the words are committed as they are, for
            // review, and the checkpoint is released.
            let attempts = CaptureRecoveryAttemptLedger.begin(draft.id)
            guard attempts <= CaptureRecoveryAttemptLedger.maximumAttempts else {
                do {
                    let pending = try createPendingCapture(
                        text: draft.transcript,
                        source: draft.captureSource,
                        createdAt: draft.startedAt
                    )
                    quarantine(pending.session)
                    CaptureDraftStore.clear(id: draft.id)
                    CaptureRecoveryAttemptLedger.finish(draft.id)
                } catch {
                    // Nothing can be written; the checkpoint stays.
                    break
                }
                continue
            }
            do {
                _ = try performSynchronousCapture(
                    text: draft.transcript,
                    source: draft.captureSource,
                    createdAt: draft.startedAt,
                    schedulesReminder: true
                )
                CaptureDraftStore.clear(id: draft.id)
                CaptureRecoveryAttemptLedger.finish(draft.id)
            } catch {
                // Keep the checkpoint so a later launch can try again. The
                // process survived, so this launch does not count against
                // the draft.
                CaptureRecoveryAttemptLedger.finish(draft.id)
                break
            }
        }
    }

    func reconcilePendingReminders() {
        guard let items = try? modelContext.fetch(FetchDescriptor<CapturedItem>()) else { return }
        advanceOverdueRecurrences(items: items, now: .now)
        guard let refreshedItems = try? modelContext.fetch(FetchDescriptor<CapturedItem>()) else { return }
        let requests = refreshedItems
            .filter { !$0.isArchived && !$0.isCompleted }
            .compactMap(ReminderScheduleRequest.init(item:))

        ReminderScheduler.synchronize(
            requests,
            requestAuthorizationIfNeeded: false,
            scope: ReminderSynchronizationScope(
                itemIDs: Set(refreshedItems.map(\.id)),
                captureSessionIDs: Set(refreshedItems.compactMap { $0.captureSession?.id }),
                replacesAllSpeakItReminders: true
            ),
            onAcknowledgment: { [weak self] report in
                self?.acknowledgeAtomicRevisionReminders(report)
            }
        )
    }

    /// The morning brief is planned from the same rows Today shows, so the
    /// counts it carries are the counts the person will find when they open
    /// the app. Each shopping list counts once, like its card on Today.
    /// Runs on every foreground and background; see
    /// `HabitNotificationScheduler`.
    func refreshMorningBrief() {
        let now = Date.now
        if HabitNotificationScheduler.settleAnswers(now: now) {
            SpeakItAnalytics.track(.morningBriefDisabled(source: .autoStop))
        }
        guard HabitDefaults.morningBriefEnabled else {
            Task { await HabitNotificationScheduler.removeAll() }
            return
        }
        guard let items = try? modelContext.fetch(FetchDescriptor<CapturedItem>()) else { return }
        let authorization = LocationReminderMonitor.shared.authorization
        let briefItems = MorningBriefPlanner.projectedItems(
            from: items, authorization: authorization, now: now
        )
        let calendar = Calendar.autoupdatingCurrent
        let entries = MorningBriefPlanner.plan(
            items: briefItems,
            now: now,
            time: HabitDefaults.morningBriefTime,
            calendar: calendar,
            // A brief lands on the Lock Screen, so it names a task only where
            // the person already said a locked phone may show task names. The
            // widget and the Live Activity read the same preference; with it
            // off, the brief is exactly the counts-only notification that
            // shipped before.
            includesNames: LockScreenTodayVisibility.showsTaskNames
        )
        Task {
            await HabitNotificationScheduler.synchronize(entries: entries, calendar: calendar)
        }
    }

    /// Advances a recurring reminder that has gone overdue without either a
    /// native repeating trigger to keep it firing or the person completing
    /// it — the "first Monday every month" family from
    /// Docs/FINAL_RELEASE_AUDIT.md H-1/E-1 that `ReminderScheduleRequest`'s
    /// `repeatingComponents` cannot express as a single static calendar
    /// match (ordinal-weekday, multi-weekday, `interval` above 1,
    /// elapsed-time). Run from the same self-healing pass as
    /// `reconcilePendingReminders`, so a series like this keeps moving
    /// forward simply by the app being opened again, the same way a missed
    /// notification schedule repairs itself, without requiring the missed
    /// occurrence to ever be marked done.
    ///
    /// Completion-anchored rules are deliberately excluded: their next date
    /// is defined as "after this one is completed," so advancing one without
    /// a completion would invent a date the person never asked for.
    private func advanceOverdueRecurrences(items: [CapturedItem], now: Date) {
        let previousRecurrences = RecurrenceStore.snapshots()
        var advancedAny = false
        for item in items {
            guard !item.isArchived, !item.isCompleted,
                  let rule = RecurrenceStore.rule(for: item.id),
                  rule.anchor == .scheduledDate,
                  RecurrenceStore.generatedNextItemID(for: item.id) == nil,
                  let session = item.captureSession,
                  let fireDate = item.reminderDate,
                  fireDate <= now,
                  let nextDate = nextRecurrenceDate(for: item, rule: rule, completedAt: now)
            else { continue }

            let reminderOffset = item.reminderDate.flatMap { reminder in
                item.dueDate.map { reminder.timeIntervalSince($0) }
            } ?? 0

            // A rule `repeatingComponents` *can* express is armed as a single
            // native repeating trigger, so it is one row that keeps recurring
            // rather than a chain of successors. It used to be excluded here
            // entirely, which killed the series: nothing advanced the row past
            // the occurrence that had just fired, `ReminderScheduleRequest`
            // drops an item whose reminder is in the past, and the very next
            // foreground cancelled every pending Speak It notification and
            // re-added nothing. "Remind me every day at 8" alerted once, ever,
            // and then sat in Today as a stale overdue row.
            //
            // Rolling this row forward is all it needs: the caller re-fetches
            // after this pass, so the request is future-dated again and the
            // repeating trigger is re-armed on the same run.
            if ReminderScheduleRequest.repeatingComponents(rule: rule, fireDate: fireDate) != nil {
                let carried = carriedIntent(from: item, toOccurrenceOn: nextDate)
                // Only move a due date the row already had. Giving one to a
                // reminder-only row would move it out of "When you have time"
                // and into "Coming up", quietly changing what kind of thing it
                // is on a pass whose whole job is to keep it firing.
                if item.dueDate != nil { item.dueDate = nextDate }
                item.reminderDate = nextDate.addingTimeInterval(reminderOffset)
                item.temporalIntent = carried
                item.lastModifiedAt = now
                advancedAny = true
                continue
            }

            let next = CapturedItem(
                originalTextSegment: item.originalTextSegment,
                displayTitle: item.displayTitle,
                itemType: item.itemType,
                category: item.category,
                createdAt: now,
                dueDate: nextDate,
                reminderDate: nextDate.addingTimeInterval(reminderOffset),
                priority: item.priority,
                personName: item.personName,
                processingConfidence: item.processingConfidence,
                needsClarification: false,
                isReviewed: item.isReviewed,
                lastModifiedAt: now,
                temporalIntent: carriedIntent(from: item, toOccurrenceOn: nextDate),
                captureSession: session
            )
            // The next occurrence is generated, not interpreted, so it has no
            // verdict of its own. It is the same reading as the one it came
            // from, which is why the verdict is carried rather than left empty —
            // empty means "nothing was ever recorded", and something was.
            next.copySemanticRecord(from: item)
            modelContext.insert(next)
            RecurrenceStore.inherit(from: item.id, to: next.id)
            RecurrenceStore.link(completed: item.id, to: next.id)
            advancedAny = true
        }
        guard advancedAny else { return }
        do {
            try persistChanges()
        } catch {
            RecurrenceStore.restore(previousRecurrences)
        }
    }

    /// Rebuilds CoreLocation's monitored regions from the saved place reminders.
    ///
    /// The location twin of `reconcilePendingReminders()`, and deliberately the
    /// same shape: rebuild one store from the other rather than trying to keep
    /// every mutation paired. It repairs an edit that orphaned a region, a
    /// delete that happened while the app was closed, a permission revoked in
    /// Settings, and a Home address that changed — without needing to know which
    /// one happened.
    ///
    /// Returns what is monitored and, for everything that is not, why. Nothing
    /// is ever deleted or disabled here: a blocked reminder keeps its meaning
    /// and simply reports what it is waiting for.
    @discardableResult
    func reconcileLocationReminders() -> LocationMonitorReconciliation {
        guard let items = try? modelContext.fetch(FetchDescriptor<CapturedItem>()) else {
            return LocationMonitorReconciliation()
        }
        let monitor = LocationReminderMonitor.shared
        let authorization = monitor.authorization

        // A request that also constrained a time is excluded rather than
        // monitored. Watching the region alone would fire "when I get home
        // tonight" on a 2pm arrival, which is the half of the sentence the
        // person was most specific about. It waits in review instead.
        // A one-shot that has already fired is excluded here rather than in
        // `LocationReminderResolver`, so the reminder's *appearance* is
        // untouched: the task is still outstanding, still in Today, still
        // showing what it is waiting for. Only the region goes away. Retiring it
        // in the resolver would have quietly reclassified a live task as
        // non-actionable, which is a different and much larger change than
        // "stop watching this place".
        let live = items.filter {
            $0.captureSession?.captureSource != .tutorial
                && !$0.isArchived && !$0.isCompleted && !$0.needsClarification
                && $0.isLocationTriggered && !$0.constrainsBothPlaceAndTime
                && $0.locationIntent?.isRetired != true
        }
        var reconciliation = monitor.reconcile(
            live.compactMap { $0.locationMonitorRequest(authorization: authorization) }
        )
        // Items that never produced a request are blocked for a reason the
        // monitor never saw — a missing Home, an unsearched place name — so
        // their blockers are merged in here rather than being lost.
        for item in live where reconciliation.monitored.contains(item.id) == false {
            if reconciliation.blocked[item.id] == nil,
               let blocker = item.locationBlocker(authorization: authorization) {
                reconciliation.blocked[item.id] = blocker
            }
        }
        return reconciliation
    }

    /// The shortest gap between two deliveries of a repeating place reminder.
    ///
    /// A repeating trigger has no final firing to record, so duplicate delivery
    /// is suppressed by time instead. Five minutes absorbs both a redelivered
    /// delegate event and GPS boundary bounce (inside/outside/inside around a
    /// driveway) without turning a quick errand into several notifications.
    static let locationTriggerCooldown: TimeInterval = 5 * 60

    /// A monitored region was crossed. Delivers the reminder, and retires the
    /// trigger when it was a one-shot.
    ///
    /// "Next time I get to the gym" stops being monitored once it has fired;
    /// "every time I get to work" keeps its region.
    ///
    /// A short-lived in-memory claim closes duplicate concurrent callbacks while
    /// notification authorization and scheduling are awaited. `firedAt` is only
    /// persisted after scheduling succeeds: denied notifications must never
    /// retire a one-shot that the person did not receive.
    func handleLocationTrigger(
        itemID: UUID,
        event: LocationEvent,
        triggerRevision: Int? = nil,
        regionIdentifier: String? = nil
    ) async {
        // A combined place-and-time request is checked here as well as in
        // reconciliation, because a region left over from before the constraint
        // was recognised would otherwise still deliver at the wrong time.
        guard let item = try? findItem(withID: itemID),
              let intent = item.locationIntent,
              !item.isArchived, !item.isCompleted, !item.needsClarification,
              !item.constrainsBothPlaceAndTime else {
            // Nothing live wants this region. Reconciling removes it.
            LocationReminderMonitor.shared.stopMonitoring(itemID: itemID)
            return
        }

        // A different event or revision is a callback from the region an edit
        // replaced. Do not stop by item ID here: that would also tear down the
        // new region that should remain armed.
        guard intent.event == event,
              triggerRevision == nil || intent.triggerRevision == triggerRevision else { return }

        if let regionIdentifier {
            let authorization = LocationReminderMonitor.shared.authorization
            guard let currentRequest = item.locationMonitorRequest(
                authorization: authorization
            ), LocationReminderMonitor.regionIdentifier(for: currentRequest) == regionIdentifier else {
                // This is most commonly an event from the old Home region after
                // Home was changed or removed. It is not an event for the current
                // reminder, even though the item ID still exists.
                return
            }
        }

        let now = Date.now
        if let firedAt = intent.firedAt {
            guard intent.repeats else {
                // Already delivered, and it only ever had one delivery to give.
                // The region should not have survived to send this.
                LocationReminderMonitor.shared.stopMonitoring(itemID: itemID)
                return
            }
            guard now.timeIntervalSince(firedAt) >= Self.locationTriggerCooldown else { return }
        }

        let deliveryKey = "\(itemID.uuidString).\(event.rawValue).r\(intent.triggerRevision)"
        guard locationDeliveriesInFlight.insert(deliveryKey).inserted else { return }
        defer { locationDeliveriesInFlight.remove(deliveryKey) }

        let notificationIdentifier = "SpeakIt.place.\(itemID.uuidString).r\(intent.triggerRevision).\(UUID().uuidString)"
        let result = await placeReminderDelivery(
            itemID,
            item.displayTitle,
            intent.displayDescription,
            notificationIdentifier
        )
        guard result == .scheduled else {
            // The crossing was detected but nothing reached the person. Keep the
            // trigger live so notification permission can be repaired and a
            // later genuine crossing can still deliver it.
            return
        }

        // Every await is an edit/completion/deletion window. Re-read the item and
        // accept the delivery only if the callback still describes the current
        // active trigger. A stale request that was already accepted by iOS is
        // explicitly withdrawn before it can appear.
        guard let current = try? findItem(withID: itemID),
              var currentIntent = current.locationIntent,
              !current.isArchived, !current.isCompleted, !current.needsClarification,
              !current.constrainsBothPlaceAndTime,
              currentIntent.event == event,
              currentIntent.triggerRevision == intent.triggerRevision,
              regionIdentifier == nil || current.locationMonitorRequest(
                authorization: LocationReminderMonitor.shared.authorization
              ).map(LocationReminderMonitor.regionIdentifier(for:)) == regionIdentifier else {
            placeReminderCancellation(notificationIdentifier)
            return
        }

        currentIntent.firedAt = now
        current.locationIntent = currentIntent
        try? modelContext.save()

        // Once scheduling has succeeded and the saved trigger still matches,
        // retire a one-shot immediately. The persisted marker prevents a later
        // launch from reconstructing it; the in-flight claim covered callbacks
        // that arrived while scheduling was suspended.
        if !currentIntent.repeats {
            LocationReminderMonitor.shared.stopMonitoring(itemID: itemID)
        }
    }

    func reconcileSharedTodayActions() {
        for pending in SharedTodayStore.pendingActions() {
            do {
                switch pending.action.kind {
                case .complete:
                    try performReminderAction(
                        itemIDs: [pending.action.itemID],
                        action: .complete
                    )
                }
                // Stamped with the action's own time, not the time this drain
                // runs: the person finished the task when they tapped the
                // widget, which may be hours before the app was next opened,
                // and the brief's answer window is measured against that.
                HabitDefaults.lastOffAppOutcomeAt = pending.action.createdAt
                SharedTodayStore.removeAction(at: pending.url)
            } catch {
                break
            }
        }
        publishSharedTodaySnapshot()
    }

    func reconcileICloudSync() async -> ICloudSyncResult {
        guard ICloudSyncState.isEnabled else { return .disabled }
        guard ICloudSyncState.isSignedIn else {
            return .unavailable("Sign in to iCloud in Settings to sync")
        }
        switch await ICloudSyncService.shared.download() {
        case .missing:
            // Taken *after* the download, for the same reason as the merge
            // below: a capture saved while the download was in flight must be
            // in the file this uploads.
            let local = makeICloudSnapshot()
            // `.missing` answers a local-filesystem question, not a cloud one:
            // it is `fileExists` on a container whose metadata sync is
            // asynchronous, so a library this device has simply not been told
            // about yet looks identical to an account that has none. Uploading
            // an empty library in that state overwrites the cloud copy, and
            // when that copy is the only one left — a delete-and-reinstall, or
            // new hardware — there is nothing to restore it from.
            //
            // An empty local library is never worth writing over a cloud file
            // whose existence we could not establish. A real first sync always
            // has something in it, so the legitimate path is untouched.
            //
            // Reported as success rather than failure: for the person this is
            // the ordinary "nothing captured yet" case, and there is genuinely
            // nothing to send. The next sync, once they have said something,
            // uploads normally.
            guard !local.sessions.isEmpty || !local.items.isEmpty else {
                return .upToDate
            }
            switch await ICloudSyncService.shared.uploadImmediately(local) {
            case .succeeded:
                ICloudSyncState.markCloudChangeApplied(at: local.generatedAt)
                return .uploaded
            case let .failed(message):
                return .failed(message)
            }
        case let .failed(message):
            // A read or decode failure is never treated as an empty cloud file.
            // This prevents a damaged/unavailable cloud copy from being replaced.
            return .failed(message)
        case let .snapshot(cloud):
            // Read the local library now, not before the download.
            //
            // `applyICloudSnapshot` deletes every row the merged snapshot does
            // not contain, so merging against a library read before a
            // multi-second `await` deleted anything captured during that
            // window: the new row was in neither half of the merge, and the
            // apply treated it as a row the cloud had removed. This runs on
            // every launch and every foreground, and speaking a thought while
            // it ran was enough to lose it.
            let local = makeICloudSnapshot()
            let wasUpToDate = local.hasSameContent(as: cloud)
            // Nothing below can change anything when the two sides already
            // match, and this runs on every launch and every foreground — so
            // the common case was rewriting every row in the store and
            // re-uploading a byte-identical file for no reason.
            if wasUpToDate { return .upToDate }
            let merged = ICloudSnapshotMerger.merge(local: local, cloud: cloud)
            do {
                try applyICloudSnapshot(merged)
            } catch {
                return .failed(error.localizedDescription)
            }
            switch await ICloudSyncService.shared.uploadImmediately(merged) {
            case .succeeded:
                ICloudSyncState.markCloudChangeApplied(at: merged.generatedAt)
                return wasUpToDate ? .upToDate : .synchronized
            case let .failed(message):
                return .failed(message)
            }
        }
    }

    func publishSharedTodaySnapshot() {
        // The store narrows to live items, then `belongsInToday` decides
        // membership. Restating that rule as a `#Predicate` would both exceed
        // the type-checker's budget and risk drifting from the model.
        let descriptor = FetchDescriptor<CapturedItem>(
            predicate: #Predicate { item in
                item.isArchived == false &&
                    item.completedAt == nil &&
                    item.needsClarification == false
            }
        )
        let now = Date.now
        guard let candidates = try? modelContext.fetch(descriptor) else { return }
        var count = 0
        var first: [CapturedItem] = []
        for item in candidates where item.belongsInToday && item.isWithinTodayHorizon(relativeTo: now) {
            count += 1
            let insertion = first.firstIndex { todayItemOrder(item, $0) } ?? first.count
            if insertion < 8 {
                first.insert(item, at: insertion)
                if first.count > 8 { first.removeLast() }
            }
        }
        let snapshot = SharedTodaySnapshot(
            generatedAt: now,
            openCount: count,
            items: first.map {
                SharedTodayItem(id: $0.id, title: $0.displayTitle, dueDate: $0.dueDate,
                                isUrgent: $0.priority == .urgent)
            },
            showsTaskNamesOnLockScreen: LockScreenTodayVisibility.showsTaskNames
        )
        if let previous = lastPublishedToday,
           previous.openCount == snapshot.openCount, previous.items == snapshot.items,
           previous.showsTaskNamesOnLockScreen == snapshot.showsTaskNamesOnLockScreen,
           now.timeIntervalSince(previous.generatedAt) < 60 { return }
        if SharedTodayStore.save(snapshot) {
            lastPublishedToday = snapshot
            WidgetCenter.shared.reloadTimelines(ofKind: "SpeakItToday")
        }
    }


    func performReminderAction(itemIDs: [UUID], action: ReminderAction) throws {
        guard !itemIDs.isEmpty else { return }
        let wanted = Set(itemIDs)
        let items = try modelContext.fetch(
            FetchDescriptor<CapturedItem>(
                predicate: #Predicate { itemIDs.contains($0.id) && $0.isArchived == false }
            )
        ).filter { wanted.contains($0.id) }

        switch action {
        case .complete:
            for item in items where !item.isCompleted {
                try setCompleted(item, completed: true)
            }
        case .snoozeTenMinutes:
            let date = Date.now.addingTimeInterval(10 * 60)
            for item in items where !item.isCompleted {
                item.reminderDate = date
                item.lastModifiedAt = .now
            }
            try persistChanges()
            rescheduleReminders(touching: items)
        case .tomorrow:
            let calendar = Calendar.autoupdatingCurrent
            guard let day = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: .now)) else {
                return
            }
            for item in items where !item.isCompleted {
                let sourceDate = item.reminderDate ?? item.dueDate
                let hour = sourceDate.map { calendar.component(.hour, from: $0) } ?? 9
                let minute = sourceDate.map { calendar.component(.minute, from: $0) } ?? 0
                let date = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
                item.reminderDate = date
                if item.dueDate != nil { item.dueDate = date }
                item.lastModifiedAt = .now
            }
            try persistChanges()
            rescheduleReminders(touching: items)
        }
    }

    /// Reschedules only the captures a notification action actually touched.
    ///
    /// These paths used to call `synchronizeAllReminders`, whose scope sets
    /// `replacesAllSpeakItReminders` — so the first thing it did was remove
    /// *every* pending Speak It notification and re-add them one at a time
    /// across several awaits, from a task nobody waits on. That runs on the
    /// background launch iOS grants for a notification action, and iOS may
    /// suspend the app the moment the handler returns. Snoozing one reminder
    /// should never put every other reminder on the phone at risk.
    private func rescheduleReminders(touching items: [CapturedItem]) {
        var handled: Set<UUID> = []
        for item in items {
            guard let session = item.captureSession,
                  handled.insert(session.id).inserted else { continue }
            synchronizeReminders(for: session, requestAuthorizationIfNeeded: false)
        }
    }

    func loadSampleData(referenceDate: Date = .now) throws -> SampleDataLoadResult {
        let existingSessions = try modelContext.fetch(FetchDescriptor<CaptureSession>())
        let existingSampleTexts = Set(
            existingSessions
                .filter { $0.captureSource == .sample }
                .map(\.originalTranscription)
        )
        let missingExamples = SampleDataLibrary.examples.filter {
            !existingSampleTexts.contains($0)
        }
        var insertedItemIDs: [UUID] = []

        for (index, text) in missingExamples.enumerated() {
            let createdAt = referenceDate.addingTimeInterval(Double(index) / 1_000)
            let session = CaptureSession(
                originalTranscription: text,
                createdAt: createdAt,
                captureSource: .sample,
                processingStatus: .organizing
            )
            modelContext.insert(session)

            let extraction = ThoughtExtractionEngine.extractWithRules(
                text,
                referenceDate: createdAt
            )
            for (itemIndex, candidate) in extraction.items.enumerated() {
                let item = makeItem(
                    from: candidate,
                    session: session,
                    createdAt: createdAt.addingTimeInterval(Double(itemIndex) / 1_000_000),
                    reviewed: true
                )
                modelContext.insert(item)
                insertedItemIDs.append(item.id)
            }
            session.processingStatus = .complete
        }

        if !missingExamples.isEmpty {
            do {
                try persistChanges()
            } catch {
                insertedItemIDs.forEach(RecurrenceStore.remove)
                throw error
            }
            synchronizeAllReminders(requestAuthorizationIfNeeded: true)
        }

        let sampleSessions = try modelContext.fetch(FetchDescriptor<CaptureSession>())
            .filter { $0.captureSource == .sample }
        return SampleDataLoadResult(
            addedCaptureCount: missingExamples.count,
            addedItemCount: insertedItemIDs.count,
            totalCaptureCount: sampleSessions.count,
            totalItemCount: sampleSessions.reduce(0) { $0 + $1.items.count }
        )
    }

    /// Practice sessions are deliberately identified by capture source rather
    /// than by remembered UUIDs. If the app is killed between either mission
    /// and cleanup, the next attempt still finds every disposable row.
    @discardableResult
    func deleteTutorialCaptures() throws -> Int {
        let tutorialRawValue = CaptureSource.tutorial.rawValue
        let sessions = try modelContext.fetch(FetchDescriptor<CaptureSession>(
            predicate: #Predicate { session in
                session.captureSourceRawValue == tutorialRawValue
            }
        ))
        guard !sessions.isEmpty else { return 0 }

        let itemIDs = sessions.flatMap(\.items).map(\.id)
        sessions.forEach(modelContext.delete)

        // Practice is never included in an iCloud snapshot, so cleanup must
        // not mint cloud tombstones for IDs that no other device has seen.
        try persistChanges()

        for itemID in itemIDs {
            RecurrenceStore.remove(itemID)
            PendingOperationStore.remove(itemID)
            LocationReminderMonitor.shared.stopMonitoring(itemID: itemID)
            ReminderScheduler.cancel(itemID: itemID)
        }
        MemoryPinStore.removeMetadata(for: itemIDs)
        ShoppingGroupStore.removeMetadata(for: itemIDs)
        IdeaStageStore.removeMetadata(for: itemIDs)
        publishSharedTodaySnapshot()
        return sessions.count
    }

    @discardableResult
    func createCapture(
        text: String,
        source: CaptureSource = .inAppText,
        createdAt: Date = .now
    ) throws -> CapturedItem {
        try createCapture(
            text: text,
            source: source,
            createdAt: createdAt,
            schedulesReminder: true
        )
    }

    /// What the synchronous capture path actually did.
    ///
    /// A cancellation or a retraction finishes successfully while leaving no row
    /// to hand back. That is a *result*, not a failure, and the two must be
    /// distinguishable: a caller that cannot tell them apart will treat a
    /// completed operation as unfinished work and try it again.
    private enum SynchronousCaptureOutcome {
        case created(CapturedItem)
        case operationHandled
    }

    @discardableResult
    func createCapture(
        text: String,
        source: CaptureSource,
        createdAt: Date,
        schedulesReminder: Bool
    ) throws -> CapturedItem {
        switch try performSynchronousCapture(
            text: text,
            source: source,
            createdAt: createdAt,
            schedulesReminder: schedulesReminder
        ) {
        case let .created(item):
            return item
        case .operationHandled:
            // This entry point must hand back a row, so callers that need to
            // tell the difference use `createCaptureResult` instead.
            throw RepositoryError.saveFailed("That request managed an existing item.")
        }
    }

    private func performSynchronousCapture(
        text: String,
        source: CaptureSource,
        createdAt: Date,
        schedulesReminder: Bool
    ) throws -> SynchronousCaptureOutcome {
        let normalizedText = try normalizedCaptureText(text)
        if let duplicate = try recentDuplicate(
            text: normalizedText,
            source: source,
            createdAt: createdAt
        ) {
            if schedulesReminder { retryPendingAtomicRevisionDelivery(duplicate.session) }
            if (duplicate.operationOutcome?.operation == .cancel
                || duplicate.operationOutcome?.operation == .complete
                || duplicate.operationOutcome?.operation == .revise),
               duplicate.items.isEmpty {
                return .operationHandled
            }
            return .created(duplicate.primaryItem)
        }

        let pending = try createPendingCapture(
            text: normalizedText,
            source: source,
            createdAt: createdAt
        )
        let extraction = ThoughtExtractionEngine.extractWithRules(
            normalizedText,
            referenceDate: createdAt,
            permitsOperations: source != .tutorial
        )
        var creating = extraction.reviewingMultipleOperations()
        if let request = extraction.pendingOperation {
            // A revision spoken alongside independent new content organizes
            // that content first, below, and then edits the saved item while
            // preserving it.
            // A revision spoken beside independent content edits the saved
            // item and keeps that content only when the edit can actually be
            // resolved; otherwise the whole capture stays one visible review
            // row, so an unresolved edit never leaves loose new rows behind.
            let editable = request.savedFieldRevision.map {
                if case .resolved = resolveSavedFieldRevision($0, session: pending.session) { return true }
                return false
            } ?? false
            let sourceSeparated = request.captureSource == normalizedText
                && !request.independentCreationUnitIDs.isEmpty
                && request.independentCreationUnitIDs == extraction.items.reduce(into: Set<Int>()) { $0.formUnion($1.sourceUnitIDs) }
                && request.independentCreationUnitIDs.isDisjoint(with: request.sourceUnitIDs)
                && RuntimeProposalGuard.covers(normalizedText, quotes: [request.sourceQuote] + extraction.items.map(\.sourceQuote))
            if request.operation == .revise, extraction.items.isEmpty || (!editable && !sourceSeparated) {
                let outcome = try applyCaptureOperation(request, session: pending.session,
                                                    schedulesReminders: schedulesReminder)
                if case .performed = outcome { return .operationHandled }
                return .created(orderedItems(in: pending.session).first ?? pending.placeholder)
            }
            let retained = extraction.items.isEmpty ? [] : organizePersistedCapture(
                session: pending.session,
                extraction: extraction,
                schedulesReminders: schedulesReminder
            )
            guard extraction.items.isEmpty || pending.session.processingStatus == .complete else {
                return .created(retained.first ?? pending.placeholder)
            }
            let outcome = try applyCaptureOperation(
                request, session: pending.session, preservingItemIDs: Set(retained.map(\.id)),
                schedulesReminders: schedulesReminder
            )
            if case .notFound = outcome, !extraction.items.isEmpty {
                creating = ThoughtExtractionEngine.extractWithRules(
                    normalizedText,
                    referenceDate: createdAt,
                    permitsOperations: false
                )
            } else {
                if case .notFound = outcome {
                    // A transient not-found receipt is not a durable home for
                    // the person's words. The pending row stays in review.
                    ensureFallbackItem(for: pending.session)
                    closeSession(pending.session)
                }
                guard let survivor = orderedItems(in: pending.session).first else {
                    return .operationHandled
                }
                return .created(survivor)
            }
        }
        let items = organizePersistedCapture(
            session: pending.session,
            extraction: creating,
            schedulesReminders: schedulesReminder
        )
        return .created(items.first ?? pending.placeholder)
    }

    @discardableResult
    func addShoppingItems(
        _ entries: [String],
        group: String,
        createdAt: Date
    ) throws -> [CapturedItem] {
        let names = entries
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let listName = group.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !names.isEmpty, !listName.isEmpty else { return [] }

        // A real capture session, so the entry keeps the durability and
        // provenance every other item has: the words as given, committed
        // before anything else happens.
        let pending = try createPendingCapture(
            text: names.joined(separator: ", "),
            source: .inAppText,
            createdAt: createdAt
        )

        let organization = OrganizedThought(
            itemType: .shopping,
            category: .shopping,
            priority: .normal,
            personName: nil,
            dueDate: nil,
            reminderDate: nil,
            reminderDelivery: .none,
            recurrenceRule: nil,
            needsClarification: false
        )
        let thoughts = names.map { name in
            ExtractedThought(
                sourceQuote: name,
                // A name the person typed onto a list. No repair chain ran, so
                // the quote is already what they wrote.
                rawQuote: name,
                wasRepaired: false,
                analysisText: name,
                suggestedTitle: name,
                organization: organization,
                confidence: 1,
                needsReview: false,
                shoppingGroup: listName
            )
        }

        let items = organizePersistedCapture(
            session: pending.session,
            extraction: ThoughtExtractionResult(items: thoughts, method: .rules),
            schedulesReminders: false
        )
        guard pending.session.processingStatus == .complete else {
            throw RepositoryError.saveFailed(
                pending.session.processingError ?? "Could not save the list items."
            )
        }
        return items
    }

    func createCaptureResult(
        text: String,
        source: CaptureSource,
        createdAt: Date,
        schedulesReminders: Bool = true,
        performance: CapturePerformanceTrace? = nil,
        onDurablySaved: (@MainActor (DurableCaptureReceipt) -> Void)? = nil
    ) async throws -> CaptureCreationResult {
        let normalizedText = try normalizedCaptureText(text)
        if let duplicate = try recentDuplicate(
            text: normalizedText,
            source: source,
            createdAt: createdAt
        ) {
            if schedulesReminders { retryPendingAtomicRevisionDelivery(duplicate.session) }
            return duplicate
        }

        let pending = try createPendingCapture(
            text: normalizedText,
            source: source,
            createdAt: createdAt
        )

        onDurablySaved?(DurableCaptureReceipt(
            sessionID: pending.session.id,
            originalTranscription: pending.session.originalTranscription,
            isPractice: pending.session.captureSource == .tutorial
        ))
#if DEBUG
        // Hold the real persisted-to-organized boundary for deterministic UI QA.
        // A release build has neither this argument nor a delayed save path.
        if ProcessInfo.processInfo.arguments.contains("--ui-testing"),
           ProcessInfo.processInfo.arguments.contains("--ui-testing-delay-organization") {
            try await Task.sleep(for: .seconds(4))
        }
#endif

        performance?.beginSemanticParsing()
        let extraction = await CapturePerformanceContext.$stageRecorder.withValue(
            performance?.stageRecorder
        ) {
            await ThoughtExtractionEngine.extract(
                normalizedText,
                referenceDate: createdAt,
                permitsOnDeviceIntelligence: permitsOnDeviceIntelligence,
                permitsOperations: source != .tutorial,
                runtimeContext: source == .tutorial || !permitsOnDeviceIntelligence || RuntimeExampleConfiguration.current == nil ? .empty : RuntimeCaptureContext(savedItems:
                    ((try? modelContext.fetch(FetchDescriptor<CapturedItem>())) ?? [])
                        .filter { $0.captureSession?.id != pending.session.id }
                        .map { RuntimeCaptureContext.SavedItem(id: $0.id.uuidString, title: $0.displayTitle, modifiedAt: $0.lastModifiedAt,
                            originalText: $0.originalTextSegment, itemType: $0.itemType.rawValue,
                            personName: $0.personName, dueDate: $0.dueDate, reminderDate: $0.reminderDate,
                            isReviewed: $0.isReviewed, isArchived: $0.isArchived, isCompleted: $0.completedAt != nil,
                            snapshot: atomicSnapshot($0)) },
                    hasHome: SavedPlaceStore.place(for: .home) != nil,
                    hasWork: SavedPlaceStore.place(for: .work) != nil)
            )
        }
        performance?.finishSemanticParsing()
        performance?.beginPersistence()

        // Commit the independent creations before acting on an existing row.
        // A failed organization must never leave the operation performed but
        // the new thoughts unsaved. A retry sees the durable capture via dedup.
        var creating = extraction.reviewingMultipleOperations()
        if let request = extraction.pendingOperation {
            // A revision spoken beside independent content edits the saved
            // item and keeps that content only when the edit can actually be
            // resolved; otherwise the whole capture stays one visible review
            // row, so an unresolved edit never leaves loose new rows behind.
            let editable = request.savedFieldRevision.map {
                if case .resolved = resolveSavedFieldRevision($0, session: pending.session) { return true }
                return false
            } ?? false
            let sourceSeparated = request.captureSource == normalizedText
                && !request.independentCreationUnitIDs.isEmpty
                && request.independentCreationUnitIDs == extraction.items.reduce(into: Set<Int>()) { $0.formUnion($1.sourceUnitIDs) }
                && request.independentCreationUnitIDs.isDisjoint(with: request.sourceUnitIDs)
                && RuntimeProposalGuard.covers(normalizedText, quotes: [request.sourceQuote] + extraction.items.map(\.sourceQuote))
            if request.operation == .revise, extraction.items.isEmpty || (!editable && !sourceSeparated) {
                let outcome = try applyCaptureOperation(request, session: pending.session,
                                                    schedulesReminders: schedulesReminders)
                performance?.finishPersistence()
                return CaptureCreationResult(
                    session: pending.session,
                    items: orderedItems(in: pending.session),
                    operationOutcome: outcome
                )
            }
            let retained = extraction.items.isEmpty ? [] : organizePersistedCapture(
                session: pending.session,
                extraction: extraction,
                schedulesReminders: schedulesReminders,
                performance: performance
            )
            guard extraction.items.isEmpty || pending.session.processingStatus == .complete else {
                performance?.finishPersistence()
                return CaptureCreationResult(session: pending.session, items: retained)
            }
            let outcome = try applyCaptureOperation(
                request, session: pending.session, preservingItemIDs: Set(retained.map(\.id)),
                schedulesReminders: schedulesReminders
            )
            if case .notFound = outcome, !extraction.items.isEmpty {
                // An unmatched cancellation can itself be an errand. Preserve
                // the established full-transcript fallback in that case.
                creating = await ThoughtExtractionEngine.extract(
                    normalizedText, referenceDate: createdAt,
                    permitsOnDeviceIntelligence: permitsOnDeviceIntelligence, permitsOperations: false
                )
            } else {
                if case .notFound = outcome {
                    ensureFallbackItem(for: pending.session)
                    closeSession(pending.session)
                }
                performance?.finishPersistence()
                return CaptureCreationResult(
                    session: pending.session,
                    items: orderedItems(in: pending.session),
                    operationOutcome: outcome
                )
            }
        }

        let items = organizePersistedCapture(
            session: pending.session,
            extraction: creating,
            schedulesReminders: schedulesReminders,
            performance: performance
        )
        performance?.finishPersistence()
        let safeItems = items.isEmpty ? [pending.placeholder] : items
        if source != .tutorial {
            SpeechVocabularyStore.rememberContextualPhrases(
                safeItems.compactMap(\.personName)
            )
        }
        return CaptureCreationResult(session: pending.session, items: safeItems)
    }

    // MARK: - Capture operations

    /// Applies a cancel, complete or retract request against what already
    /// exists.
    ///
    /// The conservative rule throughout: act automatically only on exactly one
    /// confident match. Zero matches reports nothing found rather than
    /// inventing an item to satisfy the sentence; several matches, a vague
    /// target, or a broad destructive request all keep the capture as a Needs
    /// review row so the person decides. Guessing here deletes the wrong
    /// reminder, and the person may not find out until it fails to arrive.
    @discardableResult
    func applyCaptureOperation(
        _ request: CaptureOperationRequest,
        session: CaptureSession,
        preservingItemIDs: Set<UUID> = [],
        schedulesReminders: Bool = true
    ) throws -> CaptureOperationOutcome {
        // Practice may demonstrate organization; it cannot mutate real saved
        // thoughts, including model-proposed operations or recovered captures.
        guard session.captureSource != .tutorial else {
            holdOperation(request, in: session, preserving: preservingItemIDs)
            return .needsConfirmation(operation: request.operation, candidateIDs: [])
        }
        // A retraction withdraws the capture outright.
        if request.operation == .retract {
            if request.needsReview {
                holdOperation(request, in: session, preserving: preservingItemIDs)
                return .ambiguous(operation: .retract, candidateIDs: [])
            }
            discardCaptureItems(for: session, preserving: preservingItemIDs)
            return .retracted
        }

        // A semantic revision may change the title, object, person, quantity,
        // timing, or constraints together. Even an exact old/new title pair
        // lacks a durable link from this amendment capture to the saved row.
        // Keep the full source visible and leave existing rows untouched.
        if request.operation == .revise {
            if let revision = request.savedAtomicRevision {
                return try applyAtomicRevision(revision, request: request, session: session,
                    preservingItemIDs: preservingItemIDs, schedulesReminders: schedulesReminders)
            }
            if let intent = request.savedRevisionIntent {
                return try holdSavedRevision(intent, request: request, session: session, preservingItemIDs: preservingItemIDs)
            }
            return applySavedItemRevision(request, session: session,
                                          preservingItemIDs: preservingItemIDs,
                                          schedulesReminders: schedulesReminders)
        }

        let existing = (try? modelContext.fetch(FetchDescriptor<CapturedItem>())) ?? []
        let searchable = existing.filter { $0.captureSession?.id != session.id }

        // Broad destructive requests are never executed, at any confidence.
        // The capture stays as a review row, which is where confirmation lives.
        if request.isBroad {
            let candidateIDs = CaptureTargetMatcher.activeItems(searchable).map(\.id)
            holdOperation(request, in: session, preserving: preservingItemIDs)
            // The review row itself is a generic placeholder (see
            // `beginCapture`), so what it would do if confirmed has nowhere
            // else to live. Recorded against it here so the editor can offer a
            // real confirm control instead of the dead-end "confirm in Needs
            // review" the receipt used to promise. See
            // Docs/FINAL_RELEASE_AUDIT.md F-1.
            if let placeholderID = session.items.first(where: { !preservingItemIDs.contains($0.id) })?.id {
                PendingOperationStore.set(
                    operation: request.operation,
                    candidateIDs: candidateIDs,
                    for: placeholderID
                )
            }
            return .needsConfirmation(operation: request.operation, candidateIDs: candidateIDs)
        }

        // A pronoun target names nothing. Ask rather than guess.
        guard let target = request.target, !target.isEmpty, !request.needsReview else {
            holdOperation(request, in: session, preserving: preservingItemIDs)
            return .ambiguous(
                operation: request.operation,
                candidateIDs: CaptureTargetMatcher.activeItems(searchable).map(\.id)
            )
        }

        let candidates = CaptureTargetMatcher.candidates(
            for: target, in: searchable, referenceDate: session.createdAt
        )

        if request.operation == .cancel,
           let alternatives = explicitSpokenAlternatives(
               in: session.originalTranscription, among: searchable
           ) {
            return try holdAlternativeChoice(
                request, in: session, candidateIDs: alternatives.map(\.id),
                preserving: preservingItemIDs
            )
        }

        switch candidates.count {
        case 0:
            // Nothing in the store matches, so this capture was never about an
            // existing row: "cancel my Spotify" with no Spotify item is a new
            // errand phrased as a cancellation, not a request to change one.
            //
            // This used to call `discardCaptureItems`, which deleted the whole
            // capture — and in a multi-errand capture it deleted every other
            // errand with it, including words that survived nowhere else
            // because the operation clause had been carved out of the
            // remainder. The session is left intact for the caller to create
            // from instead. See the convergence note in
            // Docs/PIPELINE_SWEEP_FINDINGS.md (rambling C2, domains C5, routing R11).
            return .notFound(operation: request.operation, target: target)

        case 1:
            let item = candidates[0]
            let itemID = item.id
            let title = item.displayTitle
            if request.operation == .cancel {
                return applyGroundedSavedCancellation(
                    request, to: item, session: session,
                    preservingItemIDs: preservingItemIDs
                )
            }
            if request.operation == .complete {
                return applyGroundedSavedCompletion(
                    request, to: item, session: session,
                    preservingItemIDs: preservingItemIDs
                )
            }
            if request.operation == .reschedule,
               request.expectedOldTimingText != nil {
                return applyGroundedSavedDateAmendment(
                    request, to: item, session: session,
                    preservingItemIDs: preservingItemIDs,
                    schedulesReminders: schedulesReminders
                )
            }
            do {
                switch request.operation {
                case .cancel:
                    // The capture-owned, source-retaining path above handles
                    // every single-target cancellation before this switch.
                    break
                case .complete:
                    // The capture-owned receipt path above handles every
                    // uniquely matched completion before this switch.
                    break
                case .reschedule:
                    guard let timing = request.newTimingText,
                          let moved = rescheduledDates(timing, for: item) else {
                        // The move is real but the moment could not be read.
                        // The capture stays for review with the item attached,
                        // so the person picks the time instead of the app.
                        holdOperation(request, in: session, preserving: preservingItemIDs)
                        return .ambiguous(operation: .reschedule, candidateIDs: [itemID])
                    }
                    try update(item, with: ItemEdits(
                        title: item.displayTitle,
                        itemType: item.itemType,
                        category: item.category,
                        dueDate: moved.dueDate,
                        reminderDate: moved.reminderDate,
                        priority: item.priority,
                        personName: item.personName,
                        needsClarification: false,
                        recurrenceRule: RecurrenceStore.rule(for: itemID),
                        locationIntent: .unchanged,
                        dueDateHasTime: moved.hasTime
                    ))
                case .revise, .create, .retract:
                    break
                }
            } catch {
                // The operation could not be applied, so the capture stays for
                // review rather than silently reporting success.
                holdOperation(request, in: session, preserving: preservingItemIDs)
                return .ambiguous(operation: request.operation, candidateIDs: [itemID])
            }
            discardCaptureItems(for: session, preserving: preservingItemIDs)
            return .performed(operation: request.operation, itemID: itemID, title: title)

        default:
            holdOperation(request, in: session, preserving: preservingItemIDs)
            return .ambiguous(
                operation: request.operation,
                candidateIDs: candidates.map(\.id)
            )
        }
    }

    /// Commit the performed receipt and saved-row deletion together. The
    /// target's original CaptureSession remains even when this was its only
    /// item: cancelling a reminder does not withdraw the words that created
    /// it. A retry after the save reads the V5 receipt instead of attempting
    /// the cancellation again or inventing a new task from its wording.
    private func applyGroundedSavedCancellation(
        _ request: CaptureOperationRequest,
        to item: CapturedItem,
        session: CaptureSession,
        preservingItemIDs: Set<UUID>
    ) -> CaptureOperationOutcome {
        let itemID = item.id
        let title = item.displayTitle
        let previousRecord = session.operationStateData
        do {
            let state = CaptureOperationState(
                phase: .performed, operation: .cancel,
                sourceQuote: request.sourceQuote, targetWords: request.target,
                candidateIDs: [itemID], targetID: itemID, targetTitle: title,
                expectedOldTimingText: nil, newTimingText: nil,
                oldDueDate: item.dueDate, oldReminderDate: item.reminderDate,
                newDueDate: nil, newReminderDate: nil, resolvedAt: .now
            )
            session.operationStateData = try JSONEncoder().encode(state)
            let disposable = session.items.filter { !preservingItemIDs.contains($0.id) }
            disposable.forEach(modelContext.delete)
            modelContext.delete(item)
            session.processingStatus = .complete
            try persistChanges(deletedItemIDs: [itemID] + disposable.map(\.id))

            RecurrenceStore.remove(itemID)
            MemoryPinStore.removeMetadata(for: [itemID])
            ShoppingGroupStore.removeMetadata(for: [itemID])
            IdeaStageStore.removeMetadata(for: [itemID])
            LocationReminderMonitor.shared.stopMonitoring(itemID: itemID)
            ReminderScheduler.cancel(itemID: itemID)
            return .performed(operation: .cancel, itemID: itemID, title: title)
        } catch {
            session.operationStateData = previousRecord
            holdOperation(request, in: session, preserving: preservingItemIDs)
            return .ambiguous(operation: .cancel, candidateIDs: [itemID])
        }
    }

    /// The completion, capture-owned receipt and removal of its temporary
    /// review row reach the store in one save. A crash after that save cannot
    /// turn a relaunch or repeated capture into another task or another
    /// completion. `setCompleted` still advances a recurring task normally.
    private func applyGroundedSavedCompletion(
        _ request: CaptureOperationRequest,
        to item: CapturedItem,
        session: CaptureSession,
        preservingItemIDs: Set<UUID>
    ) -> CaptureOperationOutcome {
        let itemID = item.id
        let title = item.displayTitle
        do {
            let state = CaptureOperationState(
                phase: .performed, operation: .complete,
                sourceQuote: request.sourceQuote, targetWords: request.target,
                candidateIDs: [itemID], targetID: itemID, targetTitle: title,
                expectedOldTimingText: nil, newTimingText: nil,
                oldDueDate: item.dueDate, oldReminderDate: item.reminderDate,
                newDueDate: item.dueDate, newReminderDate: item.reminderDate,
                resolvedAt: .now
            )
            session.operationStateData = try JSONEncoder().encode(state)
            let disposable = session.items.filter { !preservingItemIDs.contains($0.id) }
            disposable.forEach(modelContext.delete)
            session.processingStatus = .complete
            try setCompleted(item, completed: true)
            LocationReminderMonitor.shared.stopMonitoring(itemID: itemID)
            return .performed(operation: .complete, itemID: itemID, title: title)
        } catch {
            // `persistChanges` rolled back the whole context on a failed
            // save. Keep the immutable source visible as a review item.
            holdOperation(request, in: session, preserving: preservingItemIDs)
            return .ambiguous(operation: .complete, candidateIDs: [itemID])
        }
    }

    /// A speaker who explicitly names two possible saved titles has given us
    /// candidate evidence, not permission to choose one. Resolve each phrase
    /// only if it identifies a different, active Today row.
    private func explicitSpokenAlternatives(
        in source: String,
        among items: [CapturedItem]
    ) -> [CapturedItem]? {
        let pattern = #"(?i)\b(?:called|named)\s+it\s+(?:the\s+)?(.+?)\s+or\s+(?:the\s+)?(.+?)\s+when\s+i\s+saved\s+it\b"#
        guard let regex = NSRegularExpression.speakItCached(pattern),
              let match = regex.firstMatch(in: source, range: NSRange(source.startIndex..., in: source)),
              let first = Range(match.range(at: 1), in: source),
              let second = Range(match.range(at: 2), in: source) else { return nil }
        let a = CaptureTargetMatcher.candidates(for: String(source[first]), in: items)
        let b = CaptureTargetMatcher.candidates(for: String(source[second]), in: items)
        guard a.count == 1, b.count == 1, a[0].id != b[0].id else { return nil }
        return [a[0], b[0]]
    }

    private func holdAlternativeChoice(
        _ request: CaptureOperationRequest,
        in session: CaptureSession,
        candidateIDs: [UUID],
        preserving itemIDs: Set<UUID>
    ) throws -> CaptureOperationOutcome {
        var state = CaptureOperationState(
            phase: .pendingChoice, operation: request.operation,
            sourceQuote: session.originalTranscription, targetWords: request.target,
            candidateIDs: candidateIDs, targetID: nil, targetTitle: nil,
            expectedOldTimingText: nil, newTimingText: nil,
            oldDueDate: nil, oldReminderDate: nil,
            newDueDate: nil, newReminderDate: nil, resolvedAt: nil
        )
        if let review = session.items.first(where: { !itemIDs.contains($0.id) }) {
            state.reviewItemID = review.id
        } else {
            let review = CapturedItem(
                originalTextSegment: request.sourceQuote,
                displayTitle: "Choose which saved reminder to cancel",
                createdAt: session.createdAt.addingTimeInterval(0.1),
                processingConfidence: 0,
                needsClarification: true,
                captureSession: session
            )
            modelContext.insert(review)
            state.reviewItemID = review.id
        }
        session.operationStateData = try JSONEncoder().encode(state)
        session.processingStatus = .complete
        try persistChanges()
        return .ambiguous(operation: request.operation, candidateIDs: candidateIDs)
    }

    /// A named old/new date is an amendment to one saved row. Verify that the
    /// old date still describes that row, then save the new date and the
    /// capture-owned receipt together. Only timing fields change; the saved
    /// title, completion, original wording and row ID remain intact.
    private func applyGroundedSavedDateAmendment(
        _ request: CaptureOperationRequest,
        to item: CapturedItem,
        session: CaptureSession,
        preservingItemIDs: Set<UUID>,
        schedulesReminders: Bool
    ) -> CaptureOperationOutcome {
        func hold() -> CaptureOperationOutcome {
            holdOperation(request, in: session, preserving: preservingItemIDs)
            return .ambiguous(operation: .reschedule, candidateIDs: [item.id])
        }
        guard let oldText = request.expectedOldTimingText,
              let newText = request.newTimingText,
              let currentDate = item.dueDate ?? item.reminderDate else { return hold() }
        let calendar = Calendar.autoupdatingCurrent
        let oldReading = ThoughtOrganizer.organize(
            "remind me \(oldText)", referenceDate: session.createdAt,
            calendar: calendar
        )
        guard let oldDate = oldReading.dueDate ?? oldReading.reminderDate,
              CalendarDay(from: oldDate, calendar: calendar)
                == CalendarDay(from: currentDate, calendar: calendar),
              let moved = rescheduledDates(newText, for: item,
                                           referenceDate: session.createdAt) else { return hold() }

        let oldDueDate = item.dueDate
        let oldReminderDate = item.reminderDate
        let previousRecord = session.operationStateData
        let previousProcessingStatus = session.processingStatus
        do {
            let state = CaptureOperationState(
                phase: .performed, operation: .reschedule,
                sourceQuote: request.sourceQuote, targetWords: request.target,
                candidateIDs: [item.id], targetID: item.id,
                targetTitle: item.displayTitle,
                expectedOldTimingText: oldText, newTimingText: newText,
                oldDueDate: oldDueDate, oldReminderDate: oldReminderDate,
                newDueDate: moved.dueDate, newReminderDate: moved.reminderDate,
                resolvedAt: .now
            )
            session.operationStateData = try JSONEncoder().encode(state)
            item.dueDate = moved.dueDate
            item.reminderDate = moved.reminderDate
            item.temporalIntent = TemporalIntent.userEdited(
                dueDate: moved.dueDate, reminderDate: moved.reminderDate,
                recurrence: RecurrenceStore.rule(for: item.id),
                sourceText: item.temporalIntent?.sourceText ?? item.originalTextSegment,
                calendar: calendar, dueDateHasTime: moved.hasTime
            )
            item.lastModifiedAt = .now
            let disposable = session.items.filter { !preservingItemIDs.contains($0.id) }
            disposable.forEach(modelContext.delete)
            session.processingStatus = .complete
            try persistChanges(deletedItemIDs: disposable.map(\.id))
            if schedulesReminders {
                synchronizeReminders(for: item.captureSession,
                                     requestAuthorizationIfNeeded: true)
            }
            return .performed(operation: .reschedule, itemID: item.id,
                              title: item.displayTitle)
        } catch {
            session.operationStateData = previousRecord
            session.processingStatus = previousProcessingStatus
            return hold()
        }
    }

    func atomicSnapshot(_ item: CapturedItem) -> SavedAtomicRevision.Snapshot? {
        guard let parentID = item.captureSession?.id else { return nil }
        return .init(id: item.id, parentID: parentID, original: item.originalTextSegment,
            title: item.displayTitle, kind: item.itemTypeRawValue, category: item.categoryRawValue,
            created: item.createdAt, modified: item.lastModifiedAt, person: item.personName,
            due: item.dueDate, reminder: item.reminderDate, completed: item.completedAt,
            archived: item.isArchived, archivedAt: item.archivedAt, reviewed: item.isReviewed,
            needsClarification: item.needsClarification, confidence: item.processingConfidence,
            priority: item.priorityRawValue, temporal: item.temporalIntentData,
            location: item.locationIntentData, semanticState: item.semanticStateRawValue,
            semanticGap: item.semanticGapRawValue, parentOriginal: item.captureSession?.originalTranscription, parentCreated: item.captureSession?.createdAt,
            temporalKind: item.temporalKindRawValue, reminderTriggerKind: item.reminderTriggerKindRawValue)
    }

    private func applyAtomicRevision(_ revision: SavedAtomicRevision,
                                     request: CaptureOperationRequest, session: CaptureSession,
                                     preservingItemIDs: Set<UUID>, schedulesReminders: Bool) throws -> CaptureOperationOutcome {
        let previousRecord = session.operationStateData
        let previousStatus = session.processingStatus
        func hold() -> CaptureOperationOutcome {
            holdOperation(request, in: session, preserving: preservingItemIDs)
            return .ambiguous(operation: .revise, candidateIDs: [revision.expected.id])
        }
        // Receipt replay precedes old-title matching: the successful revision
        // necessarily changed that title. A later edit never gets overwritten.
        if let state = CaptureOperationState.read(from: previousRecord), state.phase == .performed {
            guard state.operation == .revise, state.sourceQuote == revision.sourceQuote,
                  state.atomicRevision?.before == revision.expected,
                  state.targetID == revision.expected.id else {
                throw RepositoryError.saveFailed("This capture already has a saved change record.")
            }
            if schedulesReminders, state.reminderSynchronizationPending == true {
                // The commit may have survived while OS scheduling failed or
                // was interrupted. Replay retries delivery from today's rows,
                // without repeating the historical mutation or its receipt.
                retryPendingAtomicRevisionDelivery(session)
            }
            return .performed(operation: .revise, itemID: revision.expected.id,
                              title: state.newTitle ?? state.targetTitle ?? revision.replacementAction)
        }
        var calendar = Calendar(identifier: .gregorian)
        guard let zone = TimeZone(identifier: revision.timeZoneIdentifier),
              revision.referenceDate == session.createdAt,
              session.originalTranscription == (revision.captureSource ?? revision.sourceQuote),
              request.sourceQuote == revision.sourceQuote,
              session.originalTranscription.contains(revision.sourceQuote),
              !request.needsReview else { return hold() }
        calendar.timeZone = zone
        var reparsed = SavedAtomicRevision.read(revision.sourceQuote, snapshots: [revision.expected],
            referenceDate: session.createdAt, calendar: calendar)
        reparsed?.captureSource = revision.captureSource
        if let confirmation = revision.confirmedIntent {
            guard let pending = CaptureOperationState.read(from: previousRecord),
                  pending.phase == .pendingChoice, pending.pendingSavedRevision == confirmation,
                  pending.candidateIDs.contains(revision.expected.id) else { return hold() }
            reparsed = confirmation.confirmedRevision(for: revision.expected)
        }
        guard reparsed == revision,
              let item = try findItem(withID: revision.expected.id),
              atomicSnapshot(item) == revision.expected, item.captureSession?.id != session.id,
              !item.belongsInMemory, !item.isCompleted, !item.isArchived, !item.needsClarification,
              item.locationIntent == nil, RecurrenceStore.rule(for: item.id) == nil else { return hold() }
        let all = try modelContext.fetch(FetchDescriptor<CapturedItem>())
        guard all.filter({ $0.displayTitle == revision.expected.title && !$0.isArchived && !$0.isCompleted
            && !$0.belongsInMemory && $0.captureSession?.id != session.id }).count == 1
            || revision.confirmedIntent != nil else { return hold() }

        let action = ThoughtOrganizer.organize(revision.replacementAction,
            referenceDate: session.createdAt, calendar: calendar)
        let taskFamily: Set<ItemType> = [.task, .personFollowUp]
        let compatibleKind = action.itemType == item.itemType
            || (taskFamily.contains(action.itemType) && taskFamily.contains(item.itemType))
        let preserveAction = revision.removesAlert || (revision.confirmedIntent.map { $0.replacementAction == nil } ?? false)
        if !preserveAction {
            guard action.itemType.isActionable, !action.needsClarification,compatibleKind,
                  ActionabilityReader.read(revision.replacementAction).belongsOnToday,
                  action.locationIntent == nil,action.recurrenceRule == nil else { return hold() }
        }
        var due = item.dueDate, reminder = item.reminderDate, intent = item.temporalIntent
        let replacementHasTiming = !preserveAction && (action.dueDate != nil || action.reminderDate != nil)
        if let confirmation = revision.confirmedIntent, let timing = confirmation.timingText {
            let explicit = ThoughtOrganizer.organize("Check the task on " + timing,referenceDate: session.createdAt,calendar: calendar)
            guard let day = explicit.dueDate, !explicit.needsClarification else { return hold() }
            let explicitClock = explicit.temporalIntent.kind.carriesTimeOfDay
            if explicitClock, let oldDue = item.dueDate, let oldReminder = item.reminderDate, oldDue != oldReminder { return hold() }
            func preserveClock(_ old: Date, on chosenDay: Date, carriesClock: Bool) -> Date? {
                guard carriesClock else { return calendar.startOfDay(for: chosenDay) }
                let clock = calendar.dateComponents([.hour,.minute,.second],from: old)
                return calendar.date(bySettingHour: clock.hour ?? 0,minute: clock.minute ?? 0,second: clock.second ?? 0,of: chosenDay)
            }
            if explicitClock {
                due = item.dueDate == nil ? nil : day; reminder = item.reminderDate == nil ? nil : day
            } else {
                if let oldDue = item.dueDate {
                    guard let preserved = preserveClock(oldDue,on: day,carriesClock: !item.isDateOnly) else { return hold() }
                    due = preserved
                }
                if let oldReminder = item.reminderDate {
                    // Preserve the reminder's calendar-day lead and its own
                    // wall clock, rather than collapsing it onto the deadline.
                    let anchor = item.dueDate ?? oldReminder
                    let lead = calendar.dateComponents([.day],from: calendar.startOfDay(for: anchor),to: calendar.startOfDay(for: oldReminder)).day ?? 0
                    guard let reminderDay = calendar.date(byAdding: .day,value: lead,to: day),
                          let preserved = preserveClock(oldReminder,on: reminderDay,carriesClock: true) else { return hold() }
                    reminder = preserved
                }
            }
            guard [due,reminder].compactMap({ $0 }).allSatisfy({ $0 > session.createdAt }) else { return hold() }
            intent = TemporalIntent.userEdited(dueDate: due,reminderDate: reminder,recurrence: nil,sourceText: timing,
                calendar: calendar,dueDateHasTime: explicitClock || !item.isDateOnly)
        } else if !revision.removesAlert, revision.timingText != nil || replacementHasTiming {
            if let oldDue = item.dueDate, let oldReminder = item.reminderDate,
               oldDue != oldReminder { return hold() }
            // A clock in the replacement is part of the same delta even when
            // the speaker did not use the optional "instead," separator.
            let timing = revision.timingText ?? revision.replacementAction
            let reading = revision.timingText == nil ? action : ThoughtOrganizer.organize("remind me \(timing)", referenceDate: session.createdAt, calendar: calendar)
            guard !reading.needsClarification, reading.locationIntent == nil,
                  reading.recurrenceRule == nil, let moment = reading.reminderDate ?? reading.dueDate,
                  moment > session.createdAt else { return hold() }
            if revision.timingText != nil, replacementHasTiming {
                guard (action.reminderDate ?? action.dueDate) == moment else { return hold() }
            }
            due = item.dueDate != nil || item.reminderDate == nil ? moment : nil
            reminder = item.reminderDate != nil ? moment : nil
            intent = TemporalIntent.userEdited(dueDate: due, reminderDate: reminder, recurrence: nil,
                sourceText: timing, calendar: calendar,
                dueDateHasTime: reading.temporalIntent.kind.carriesTimeOfDay)
        }
        if revision.removesAlert { reminder = nil } // Deadline and its precision remain unchanged.
        let title = preserveAction ? item.displayTitle : ThoughtTitleFormatter.polished(revision.replacementAction, itemType: item.itemType)
        // All identity, source, interpretation and delta checks finish before
        // any mutable field changes. No await splits this transaction.
        do {
            item.displayTitle = title
            if !preserveAction { item.personName = action.personName }
            item.dueDate = due; item.reminderDate = reminder
            if !revision.removesAlert { item.temporalIntent = intent }
            item.lastModifiedAt = Date(timeIntervalSinceReferenceDate: max(
                Date.now.timeIntervalSinceReferenceDate,
                session.createdAt.timeIntervalSinceReferenceDate,
                revision.expected.modified.timeIntervalSinceReferenceDate + 0.001))
            guard let after = atomicSnapshot(item) else { throw RepositoryError.saveFailed("The saved item's source is unavailable.") }
            var state = CaptureOperationState(phase: .performed, operation: .revise,
                sourceQuote: revision.sourceQuote, targetWords: revision.expected.title,
                candidateIDs: [item.id], targetID: item.id, targetTitle: title,
                expectedOldTimingText: nil, newTimingText: revision.timingText,
                oldDueDate: revision.expected.due, oldReminderDate: revision.expected.reminder,
                newDueDate: due, newReminderDate: reminder, resolvedAt: .now)
            state.reviewItemID = CaptureOperationState.read(from: previousRecord)?.reviewItemID
            state.oldTitle = revision.expected.title; state.newTitle = title
            state.oldPersonName = revision.expected.person
            state.atomicRevision = .init(before: revision.expected, after: after,
                replacementEvidence: revision.replacementAction, timingEvidence: revision.timingText)
            state.reminderSynchronizationPending = reminder != nil || revision.removesAlert
            state.reminderSynchronizationStatus = revision.removesAlert ? "cancellationPending" : reminder == nil ? nil : "pending"
            session.operationStateData = try JSONEncoder().encode(state)
            let disposable = session.items.filter { !preservingItemIDs.contains($0.id) }
            disposable.forEach(modelContext.delete)
            session.processingStatus = .complete
            try persistChanges(deletedItemIDs: disposable.map(\.id))
        } catch {
            // persistChanges rolls back fields and deleted placeholders. Keep
            // the caller's registered amendment consistent with durable state.
            modelContext.rollback()
            session.operationStateData = previousRecord
            session.processingStatus = previousStatus
            throw error
        }
        // OS delivery follows the durable commit. Launch reconciliation reads
        // the current rows after a crash here; retry never repeats the mutation.
        if schedulesReminders {
            synchronizeAtomicRevisionReminders(amendment: session, target: item)
        }
        return .performed(operation: .revise, itemID: item.id, title: item.displayTitle)
    }

    private func holdSavedRevision(_ intent: SavedRevisionIntent, request: CaptureOperationRequest,
                                   session: CaptureSession, preservingItemIDs: Set<UUID>) throws -> CaptureOperationOutcome {
        guard intent.captureSource == session.originalTranscription, intent.sourceQuote == request.sourceQuote,
              intent.referenceDate == session.createdAt else {
            holdOperation(request,in: session,preserving: preservingItemIDs)
            return .ambiguous(operation: .revise,candidateIDs: [])
        }
        let previous = session.operationStateData; let status = session.processingStatus
        do {
            let review: CapturedItem
            if let existing = session.items.first(where: { !preservingItemIDs.contains($0.id) }) { review = existing }
            else {
                review = CapturedItem(originalTextSegment: intent.sourceQuote,displayTitle: intent.sourceQuote,
                    itemType: .unclear,createdAt: session.createdAt.addingTimeInterval(0.1),processingConfidence: 0,
                    needsClarification: true,captureSession: session)
                modelContext.insert(review)
            }
            review.needsClarification = true
            var state = CaptureOperationState(phase: .pendingChoice,operation: .revise,sourceQuote: intent.sourceQuote,
                targetWords: intent.targetWords,candidateIDs: intent.candidates.map(\.id),targetID: nil,targetTitle: nil,
                expectedOldTimingText: nil,newTimingText: intent.timingText,oldDueDate: nil,oldReminderDate: nil,
                newDueDate: nil,newReminderDate: nil,resolvedAt: nil)
            state.reviewItemID = review.id; state.pendingSavedRevision = intent
            session.operationStateData = try JSONEncoder().encode(state); session.processingStatus = .complete
            try persistChanges()
            return .ambiguous(operation: .revise,candidateIDs: intent.candidates.map(\.id))
        } catch {
            modelContext.rollback(); session.operationStateData = previous; session.processingStatus = status; throw error
        }
    }

    private func retryPendingAtomicRevisionDelivery(_ amendment: CaptureSession) {
        guard let state = CaptureOperationState.read(from: amendment.operationStateData),
              state.phase == .performed, state.reminderSynchronizationPending == true,
              let receipt = state.atomicRevision else { return }
        if let target = try? findItem(withID: receipt.after.id) {
            synchronizeAtomicRevisionReminders(amendment: amendment, target: target)
        } else {
            reconcilePendingReminders()
        }
    }

    private func synchronizeAtomicRevisionReminders(amendment: CaptureSession, target: CapturedItem) {
        guard let parent = target.captureSession,
              CaptureOperationState.read(from: amendment.operationStateData)?.atomicRevision != nil else { return }
        let requests = parent.items.filter { !$0.isArchived && !$0.isCompleted }
            .compactMap(ReminderScheduleRequest.init(item:))
        ReminderScheduler.synchronize(requests,
            requestAuthorizationIfNeeded: requestsReminderAuthorization,
            scope: ReminderSynchronizationScope(itemIDs: Set(parent.items.map(\.id)), captureSessionIDs: [parent.id]),
            onAcknowledgment: { [weak self] report in
                self?.acknowledgeAtomicRevisionReminders(report)
            })
    }

    #if DEBUG
    func acknowledgeAtomicRevisionRemindersForTesting(_ report: ReminderBatchAcknowledgment) {
        acknowledgeAtomicRevisionReminders(report)
    }
    #endif

    private func acknowledgeAtomicRevisionReminders(_ report: ReminderBatchAcknowledgment) {
        guard let sessions = try? modelContext.fetch(FetchDescriptor<CaptureSession>()) else { return }
        var changed = false, stale = false
        let previous = sessions.map { ($0, $0.operationStateData) }
        for amendment in sessions {
            guard var state = CaptureOperationState.read(from: amendment.operationStateData),
                  state.phase == .performed, state.reminderSynchronizationPending == true,
                  let receipt = state.atomicRevision else { continue }
            let current = try? findItem(withID: receipt.after.id)
            if current.flatMap(atomicSnapshot) != receipt.after {
                // A later edit/deletion supersedes this historical delivery
                // request. It does not acknowledge the old alert as armed.
                state.reminderSynchronizationPending = false
                state.reminderSynchronizationStatus = "superseded"
                stale = true
            } else if receipt.after.reminder == nil, receipt.before.reminder != nil {
                let oldDelivery = ItemPresentation.parsedReminderDelivery(segment: receipt.before.original,
                    createdAt: receipt.before.created, parentSource: receipt.before.parentOriginal,
                    parentCreatedAt: receipt.before.parentCreated)
                if report.cancelledItemIDs.contains(receipt.after.id),
                   oldDelivery != .alarm || report.cancelledAlarmItemIDs.contains(receipt.after.id) {
                    state.reminderSynchronizationPending = false
                    state.reminderSynchronizationStatus = "cancelled"
                } else { continue } // No OS cancellation proof, including an empty acknowledgment.
            } else if let time = receipt.after.reminder, time <= ReminderSchedulingClock.now {
                state.reminderSynchronizationPending = false
                state.reminderSynchronizationStatus = "expired"
            } else if report.requests[receipt.after.id] != current.flatMap(ReminderScheduleRequest.init(item:)) {
                continue // A successful older pass cannot acknowledge a newer clock/title/delivery.
            } else if report.items[receipt.after.id] == .scheduled {
                state.reminderSynchronizationPending = false
                state.reminderSynchronizationStatus = "scheduled"
            } else if let result = report.items[receipt.after.id] {
                state.reminderSynchronizationStatus = result == .denied ? "denied"
                    : result == .needsPermission ? "needsPermission" : "failed"
            } else { continue } // No target acknowledgment, including [] and expired requests.
            guard let encoded = try? JSONEncoder().encode(state), encoded != amendment.operationStateData else { continue }
            amendment.operationStateData = encoded; changed = true
        }
        if changed {
            do { try persistChanges() }
            catch { for (session, data) in previous { session.operationStateData = data }; return }
        }
        // The scheduler serializes passes. A stale callback must replace its
        // old OS snapshot with the current rows; the superseded receipt avoids
        // a loop when that fresh pass finishes.
        if stale { reconcilePendingReminders() }
    }

    /// Preserve an occurrence-grounded revision request for review. Even an
    /// exact old/new title pair cannot execute yet: CaptureSession owns one
    /// set of items, and updating another session's item would leave no
    /// durable relationship from this amendment transcript to that saved row.
    /// A transient performed receipt is insufficient after restart or sync.
    private func applySavedItemRevision(
        _ request: CaptureOperationRequest,
        session: CaptureSession,
        preservingItemIDs: Set<UUID>,
        schedulesReminders: Bool
    ) -> CaptureOperationOutcome {
        func hold(_ candidates: [UUID] = []) -> CaptureOperationOutcome {
            holdOperation(request, in: session, preserving: preservingItemIDs)
            return .ambiguous(operation: .revise, candidateIDs: candidates)
        }
        if let removal = request.savedAlertRemoval {
            let existing = (try? modelContext.fetch(FetchDescriptor<CapturedItem>())) ?? []
            let active = CaptureTargetMatcher.activeItems(existing).filter {
                $0.captureSession?.id != session.id && !$0.belongsInMemory
            }
            let candidates = CaptureTargetMatcher.candidates(
                for: removal.targetWords + " " + removal.dayWord,
                in: active, referenceDate: session.createdAt,
                calendar: .autoupdatingCurrent
            )
            guard candidates.count == 1, let item = candidates.first,
                  let oldReminder = item.reminderDate,
                  Calendar.autoupdatingCurrent.component(.hour, from: oldReminder)
                    == removal.oldHour24,
                  RecurrenceStore.rule(for: item.id) == nil else {
                return hold(candidates.map(\.id))
            }
            let calendar = Calendar.autoupdatingCurrent
            let previousDue = item.dueDate
            let previousIntent = item.temporalIntent
            let previousRecord = session.operationStateData
            let dateOnly = calendar.startOfDay(for: item.dueDate ?? oldReminder)
            do {
                var state = CaptureOperationState(
                    phase: .performed, operation: .revise,
                    sourceQuote: request.sourceQuote, targetWords: request.target,
                    candidateIDs: [item.id], targetID: item.id,
                    targetTitle: item.displayTitle,
                    expectedOldTimingText: nil, newTimingText: nil,
                    oldDueDate: previousDue, oldReminderDate: oldReminder,
                    newDueDate: dateOnly, newReminderDate: nil,
                    resolvedAt: .now
                )
                state.oldTitle = item.displayTitle
                state.newTitle = item.displayTitle
                session.operationStateData = try JSONEncoder().encode(state)
                item.dueDate = dateOnly
                item.reminderDate = nil
                item.temporalIntent = TemporalIntent.userEdited(
                    dueDate: dateOnly, reminderDate: nil, recurrence: nil,
                    sourceText: previousIntent?.sourceText ?? item.originalTextSegment,
                    calendar: calendar, dueDateHasTime: false
                )
                item.lastModifiedAt = .now
                let disposable = session.items.filter { !preservingItemIDs.contains($0.id) }
                disposable.forEach(modelContext.delete)
                session.processingStatus = .complete
                try persistChanges(deletedItemIDs: disposable.map(\.id))
                ReminderScheduler.cancel(itemID: item.id)
                return .performed(operation: .revise, itemID: item.id,
                                  title: item.displayTitle)
            } catch {
                item.dueDate = previousDue
                item.reminderDate = oldReminder
                item.temporalIntent = previousIntent
                session.operationStateData = previousRecord
                return hold([item.id])
            }
        }
        if let field = request.savedFieldRevision {
            return applySavedFieldRevision(field, request: request, session: session,
                                           preservingItemIDs: preservingItemIDs,
                                           schedulesReminders: schedulesReminders,
                                           hold: hold)
        }
        if let quantity = request.savedQuantityRevision {
            let existing = (try? modelContext.fetch(FetchDescriptor<CapturedItem>())) ?? []
            let candidates = CaptureTargetMatcher.activeItems(existing).filter {
                $0.captureSession?.id != session.id && !$0.belongsInMemory
                    && quantity.replacementTitle(for: $0.displayTitle) != nil
            }
            guard candidates.count == 1,
                  let item = candidates.first,
                  let revisedTitle = quantity.replacementTitle(for: item.displayTitle) else {
                return hold(candidates.map(\.id))
            }
            let oldTitle = item.displayTitle
            let previousRecord = session.operationStateData
            do {
                var state = CaptureOperationState(
                    phase: .performed, operation: .revise,
                    sourceQuote: request.sourceQuote, targetWords: request.target,
                    candidateIDs: [item.id], targetID: item.id,
                    targetTitle: revisedTitle,
                    expectedOldTimingText: nil, newTimingText: nil,
                    oldDueDate: item.dueDate, oldReminderDate: item.reminderDate,
                    newDueDate: item.dueDate, newReminderDate: item.reminderDate,
                    resolvedAt: .now
                )
                state.oldTitle = oldTitle
                state.newTitle = revisedTitle
                session.operationStateData = try JSONEncoder().encode(state)
                item.displayTitle = revisedTitle
                item.lastModifiedAt = .now
                let disposable = session.items.filter { !preservingItemIDs.contains($0.id) }
                disposable.forEach(modelContext.delete)
                session.processingStatus = .complete
                try persistChanges(deletedItemIDs: disposable.map(\.id))
                if schedulesReminders {
                    synchronizeReminders(for: item.captureSession,
                                         requestAuthorizationIfNeeded: true)
                }
                return .performed(operation: .revise, itemID: item.id,
                                  title: revisedTitle)
            } catch {
                item.displayTitle = oldTitle
                session.operationStateData = previousRecord
                return hold([item.id])
            }
        }
        guard let revision = request.savedItemRevision,
              !revision.oldTitleUnitIDs.isEmpty,
              !revision.replacementUnitIDs.isEmpty,
              revision.oldTitleUnitIDs.isDisjoint(with: revision.replacementUnitIDs),
              request.sourceUnitIDs.isSuperset(of: revision.oldTitleUnitIDs),
              request.sourceUnitIDs.isSuperset(of: revision.replacementUnitIDs) else {
            return hold()
        }
        let existing = (try? modelContext.fetch(FetchDescriptor<CapturedItem>())) ?? []
        let active = CaptureTargetMatcher.activeItems(existing).filter {
            $0.captureSession?.id != session.id && !$0.belongsInMemory
        }
        func normalized(_ text: String) -> String {
            text.trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                .lowercased()
        }
        let candidates = active.filter { normalized($0.displayTitle) == normalized(revision.oldTitle) }
        return hold(candidates.map(\.id))
    }

    /// Executes one explicitly requested field change on a saved action, or
    /// holds it for review. Every condition below must hold, or nothing on
    /// the saved item changes and the request stays visible:
    /// - exactly one active saved action (from another capture) carries the
    ///   old value in the requested role — the person after a communication
    ///   verb, or the place after "at"/"to"/"from" — exactly once;
    /// - that target also shares words with how the speaker named the item;
    /// - the old value was actually said somewhere in this capture;
    /// - the item has not been edited since this capture was spoken.
    /// Only the matching span of the title and, for a person, the person field
    /// change. Due date, reminder, recurrence, place monitoring, category,
    /// original segment and identity are untouched, and the capture keeps a
    /// record of the old and new values.
    private func applySavedFieldRevision(
        _ field: SavedFieldRevision,
        request: CaptureOperationRequest,
        session: CaptureSession,
        preservingItemIDs: Set<UUID>,
        schedulesReminders: Bool,
        hold: ([UUID]) -> CaptureOperationOutcome
    ) -> CaptureOperationOutcome {
        let resolution = resolveSavedFieldRevision(field, session: session)
        guard case let .resolved(item, oldValue, titleRange) = resolution else {
            if case let .unresolved(candidates) = resolution { return hold(candidates) }
            return hold([])
        }
        return performSavedFieldRevision(field, request: request, session: session, item: item,
                                         oldValue: oldValue, titleRange: titleRange,
                                         preservingItemIDs: preservingItemIDs,
                                         schedulesReminders: schedulesReminders, hold: hold)
    }

    enum SavedFieldResolution {
        case resolved(CapturedItem, String, Range<String.Index>)
        case unresolved([UUID])
    }

    /// Whether a field revision can execute, without changing anything. The
    /// capture paths use this to decide between editing the saved item beside
    /// the capture's independent content and holding the whole capture.
    func resolveSavedFieldRevision(_ field: SavedFieldRevision, session: CaptureSession) -> SavedFieldResolution {
        let source = session.originalTranscription
        func stems(_ text: String) -> Set<String> {
            let stop: Set<String> = ["the", "and", "for", "with", "that", "this", "from", "into",
                                     "item", "task", "reminder", "entry", "same", "existing", "saved",
                                     "change", "update", "about", "yesterday", "says"]
            var result = Set<String>()
            for piece in text.lowercased().split(whereSeparator: { !$0.isLetter }) {
                let word = String(piece)
                guard word.count >= 3, !stop.contains(word) else { continue }
                let stem: String = word.count > 4 && word.hasSuffix("s") ? String(word.dropLast()) : word
                result.insert(stem)
                // "pickup" names the same thing as "pick up".
                if stem.hasSuffix("up"), stem.count > 4 { result.insert(String(stem.dropLast(2))) }
            }
            return result
        }
        func escaped(_ value: String) -> String { NSRegularExpression.escapedPattern(for: value) }
        /// The one span of `title` holding `old` in the requested role.
        func roleSpan(in title: String, old: String) -> NSRange? {
            let pattern: String
            switch field.field {
            case .person:
                pattern = #"(?i)\b"# + SavedFieldRevision.communicationVerb + #"\s+("# + escaped(old) + #")\b"#
            case .place:
                pattern = #"(?i)\b(?:at|to|from)\s+(?:the\s+)?("# + escaped(old) + #")\b"#
            }
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
            let matches = regex.matches(in: title, range: NSRange(title.startIndex..., in: title))
            guard matches.count == 1 else { return nil }
            return matches[0].range(at: 1)
        }
        /// The old value the target holds in that role, when not stated.
        func impliedOld(of item: CapturedItem) -> String? {
            switch field.field {
            case .person:
                if let person = item.personName { return person }
                // The recipient slot of the title: "Ask Maya for the price".
                let title = item.displayTitle
                guard let regex = try? NSRegularExpression(
                    pattern: #"(?i)\b"# + SavedFieldRevision.communicationVerb + #"\s+([A-Z][\p{L}'’-]+)\b"#),
                      let match = regex.firstMatch(in: title, range: NSRange(title.startIndex..., in: title)),
                      let range = Range(match.range(at: 1), in: title),
                      title[range].first?.isUppercase == true else { return nil }
                return String(title[range])
            case .place:
                let title = item.displayTitle
                guard let regex = try? NSRegularExpression(
                    pattern: #"\b(?:(?:[Aa]t|[Ff]rom)\s+(?:the\s+)?([A-Z][\p{L}'’-]*(?:\s+[A-Z][\p{L}'’-]*){0,3})|[Tt]o\s+(?:the\s+)?([A-Z][\p{L}'’-]*(?:\s+[A-Z][\p{L}'’-]*){1,3}))(?:\s+(?:on|by|this|next|before|after|tomorrow|today|tonight)\b.*)?\s*$"#),
                      let match = regex.firstMatch(in: title, range: NSRange(title.startIndex..., in: title)),
                      // "to Evan" is a recipient; a "to" place needs a
                      // multi-word name ("to Maple Road").
                      let range = Range(match.range(at: 1), in: title) ?? Range(match.range(at: 2), in: title)
                else { return nil }
                return String(title[range]).trimmingCharacters(in: .whitespaces)
            }
        }
        let existing = (try? modelContext.fetch(FetchDescriptor<CapturedItem>())) ?? []
        let active = CaptureTargetMatcher.activeItems(existing).filter {
            $0.captureSession?.id != session.id && !$0.belongsInMemory
        }
        let named = stems(field.itemWords)
        var matches: [(item: CapturedItem, old: String, span: NSRange)] = []
        // Only a settled saved action can be revised. A held review row (an
        // earlier unresolved capture) quotes the same words and must never
        // become the target of an edit.
        for item in active where item.itemType.isActionable && !item.needsClarification {
            guard let old = field.statedOldValue ?? impliedOld(of: item), !old.isEmpty,
                  old.caseInsensitiveCompare(field.newValue) != .orderedSame,
                  let span = roleSpan(in: item.displayTitle, old: old) else { continue }
            let titleStems = stems(item.displayTitle).subtracting(stems(old))
            guard !titleStems.isDisjoint(with: named) else { continue }
            // The old value must have been spoken in this capture: a request
            // that never names what it replaces cannot prove its target.
            guard source.range(of: #"(?i)\b"# + escaped(old) + #"\b"#,
                               options: .regularExpression) != nil else { continue }
            if field.field == .person,
               let person = item.personName,
               person.caseInsensitiveCompare(old) != .orderedSame { continue }
            matches.append((item, old, span))
        }
        guard matches.count == 1, let chosen = matches.first,
              let titleRange = Range(chosen.span, in: chosen.item.displayTitle) else {
            return .unresolved(matches.map(\.item.id))
        }
        let item = chosen.item
        // A newer edit wins over this older capture's interpretation.
        guard item.lastModifiedAt <= session.createdAt.addingTimeInterval(1),
              item.completedAt == nil, !item.isArchived else {
            return .unresolved([item.id])
        }
        return .resolved(item, chosen.old, titleRange)
    }

    private func performSavedFieldRevision(
        _ field: SavedFieldRevision, request: CaptureOperationRequest, session: CaptureSession,
        item: CapturedItem, oldValue: String, titleRange: Range<String.Index>,
        preservingItemIDs: Set<UUID>, schedulesReminders: Bool,
        hold: ([UUID]) -> CaptureOperationOutcome
    ) -> CaptureOperationOutcome {
        let oldTitle = item.displayTitle
        let oldPerson = item.personName
        let newTitle = oldTitle.replacingCharacters(in: titleRange, with: field.newValue)
        let previousRecord = session.operationStateData
        do {
            var state = CaptureOperationState(
                phase: .performed, operation: .revise,
                sourceQuote: request.sourceQuote, targetWords: request.target,
                candidateIDs: [item.id], targetID: item.id, targetTitle: newTitle,
                expectedOldTimingText: nil, newTimingText: nil,
                oldDueDate: item.dueDate, oldReminderDate: item.reminderDate,
                newDueDate: item.dueDate, newReminderDate: item.reminderDate,
                resolvedAt: .now
            )
            state.oldTitle = oldTitle
            state.newTitle = newTitle
            state.revisedField = field.field.rawValue
            state.oldFieldValue = oldValue
            state.newFieldValue = field.newValue
            state.oldPersonName = oldPerson
            session.operationStateData = try JSONEncoder().encode(state)
            item.displayTitle = newTitle
            if field.field == .person { item.personName = field.newValue }
            item.lastModifiedAt = .now
            let disposable = session.items.filter { !preservingItemIDs.contains($0.id) }
            disposable.forEach(modelContext.delete)
            session.processingStatus = .complete
            try persistChanges(deletedItemIDs: disposable.map(\.id))
            if schedulesReminders {
                synchronizeReminders(for: item.captureSession, requestAuthorizationIfNeeded: true)
            }
            return .performed(operation: .revise, itemID: item.id, title: newTitle)
        } catch {
            item.displayTitle = oldTitle
            item.personName = oldPerson
            session.operationStateData = previousRecord
            return hold([item.id])
        }
    }

    /// Resolves the spoken destination of a reschedule against one item.
    ///
    /// Two shapes: an offset from the scheduled moment ("back an hour",
    /// "by two days"), and an absolute moment read by the same temporal
    /// engine every capture uses ("Friday", "3 PM", "tomorrow after work").
    /// Whichever timing fields the item already carries are the ones that
    /// move; an item with no timing at all gains a reminder, because a person
    /// moving it "to Friday" is asking to hear about it then.
    private func rescheduledDates(
        _ timing: String,
        for item: CapturedItem,
        referenceDate: Date = .now
    ) -> (dueDate: Date?, reminderDate: Date?, hasTime: Bool)? {
        let anchor = item.reminderDate ?? item.dueDate

        if let offset = RescheduleOffset.parse(timing) {
            guard let anchor else { return nil }
            let moved = anchor.addingTimeInterval(offset)
            guard moved > referenceDate else { return nil }
            return (
                item.dueDate != nil ? moved : nil,
                item.reminderDate != nil || item.dueDate == nil ? moved : nil,
                true
            )
        }

        let organized = ThoughtOrganizer.organize(
            "remind me \(timing)",
            referenceDate: referenceDate,
            calendar: .autoupdatingCurrent
        )
        guard let moment = organized.reminderDate ?? organized.dueDate else { return nil }
        let hasTime = organized.temporalIntent.kind.carriesTimeOfDay
        return (
            item.dueDate != nil ? moment : nil,
            item.reminderDate != nil || item.dueDate == nil ? moment : nil,
            hasTime
        )
    }

    /// Carries out a held broad cancel or complete, once the person has
    /// explicitly confirmed it from the review row.
    ///
    /// Applies the same per-item actions the exact-match single-target path
    /// already uses — cancelling stops location monitoring and deletes,
    /// completing marks done and stops monitoring — so a confirmed broad
    /// request behaves exactly like the same operation performed one item at a
    /// time. The review row itself was only ever the confirmation vehicle, so
    /// it is removed once its request is resolved rather than left behind as
    /// a permanent row with nothing left to say. See Docs/FINAL_RELEASE_AUDIT.md F-1.
    func confirmPendingOperation(_ item: CapturedItem) throws {
        guard item.captureSession?.captureSource != .tutorial else {
            throw RepositoryError.saveFailed("Practice cannot change your saved thoughts.")
        }
        guard let record = PendingOperationStore.record(for: item.id) else { return }
        if record.operation == .cancel {
            guard let session = item.captureSession else {
                throw RepositoryError.saveFailed("The original request is unavailable. No saved item changed.")
            }
            // Revalidate the exact IDs shown at confirmation time. A stale
            // candidate must hold the entire broad operation, not allow a
            // partial delete of the remaining candidates.
            let candidates = try record.candidateIDs.map { try findItem(withID: $0) }
            guard candidates.allSatisfy({ candidate in
                guard let candidate else { return false }
                return candidate.completedAt == nil && !candidate.isArchived
                    && !candidate.belongsInMemory && candidate.captureSession?.id != session.id
            }) else {
                throw RepositoryError.saveFailed("A saved item changed. Review this cancellation again.")
            }
            let targets = candidates.compactMap { $0 }
            let state = CaptureOperationState(
                phase: .performed, operation: .cancel,
                sourceQuote: session.originalTranscription, targetWords: nil,
                candidateIDs: record.candidateIDs, targetID: nil,
                targetTitle: nil, expectedOldTimingText: nil, newTimingText: nil,
                oldDueDate: nil, oldReminderDate: nil,
                newDueDate: nil, newReminderDate: nil, resolvedAt: .now
            )
            session.operationStateData = try JSONEncoder().encode(state)
            targets.forEach(modelContext.delete)
            modelContext.delete(item)
            session.processingStatus = .complete
            try persistChanges(deletedItemIDs: record.candidateIDs + [item.id])
            PendingOperationStore.remove(item.id)
            for candidateID in record.candidateIDs {
                RecurrenceStore.remove(candidateID)
                MemoryPinStore.removeMetadata(for: [candidateID])
                ShoppingGroupStore.removeMetadata(for: [candidateID])
                IdeaStageStore.removeMetadata(for: [candidateID])
                LocationReminderMonitor.shared.stopMonitoring(itemID: candidateID)
                ReminderScheduler.cancel(itemID: candidateID)
            }
            return
        }
        for candidateID in record.candidateIDs {
            guard let candidate = try findItem(withID: candidateID) else { continue }
            switch record.operation {
            case .cancel:
                LocationReminderMonitor.shared.stopMonitoring(itemID: candidateID)
                try delete(candidate)
            case .complete:
                try setCompleted(candidate, completed: true)
                LocationReminderMonitor.shared.stopMonitoring(itemID: candidateID)
            case .reschedule, .revise, .create, .retract:
                // A reschedule is never broad; nothing to confirm here.
                break
            }
        }
        PendingOperationStore.remove(item.id)
        try delete(item)
    }

    func pendingCaptureOperationChoices(for item: CapturedItem) throws -> [CapturedItem] {
        guard let state = CaptureOperationState.read(from: item.captureSession?.operationStateData),
              state.phase == .pendingChoice,
              state.reviewItemID == item.id else { return [] }
        return try state.candidateIDs.compactMap { id in
            guard let candidate = try findItem(withID: id),
                  candidate.completedAt == nil, !candidate.isArchived,
                  !candidate.belongsInMemory else { return nil }
            if let intent = state.pendingSavedRevision, !intent.candidates.contains(where: { $0 == atomicSnapshot(candidate) }) { return nil }
            return candidate
        }
    }

    /// A reply selects exactly one stored ID. The V5 receipt and deletion are
    /// committed together; a repeated reply after relaunch sees `.performed`
    /// and returns without deleting a second row.
    func choosePendingCaptureOperation(_ item: CapturedItem, targetID: UUID) throws {
        guard let session = item.captureSession else {
            throw RepositoryError.saveFailed("The saved-item question is no longer available.")
        }
        try choosePendingCaptureOperation(session: session, reviewItemID: item.id, targetID: targetID)
    }

    /// Stable reply identity survives deletion of the temporary question row.
    func choosePendingCaptureOperation(captureSessionID: UUID, reviewItemID: UUID, targetID: UUID) throws {
        guard let session = try modelContext.fetch(FetchDescriptor<CaptureSession>()).first(where: { $0.id == captureSessionID }) else {
            throw RepositoryError.saveFailed("The saved-item question is no longer available.")
        }
        try choosePendingCaptureOperation(session: session, reviewItemID: reviewItemID, targetID: targetID)
    }

    private func choosePendingCaptureOperation(session: CaptureSession, reviewItemID: UUID, targetID: UUID) throws {
        guard session.captureSource != .tutorial else {
            throw RepositoryError.saveFailed("Practice cannot change your saved thoughts.")
        }
        guard var state = CaptureOperationState.read(from: session.operationStateData),
              state.reviewItemID == reviewItemID else {
            throw RepositoryError.saveFailed("The saved-item question is no longer available.")
        }
        if state.phase == .performed, state.targetID == targetID {
            if state.reminderSynchronizationPending == true { retryPendingAtomicRevisionDelivery(session) }
            return
        }
        if let intent = state.pendingSavedRevision {
            guard state.phase == .pendingChoice, state.operation == .revise,
                  state.candidateIDs.contains(targetID), let target = try findItem(withID: targetID),
                  let snapshot = atomicSnapshot(target), intent.candidates.contains(snapshot),
                  let revision = intent.confirmedRevision(for: snapshot) else {
                throw RepositoryError.saveFailed("That saved item has changed. Review the requested edit again.")
            }
            var request = CaptureOperationRequest(operation: .revise,polarity: .positive,target: snapshot.title,
                sourceQuote: intent.sourceQuote,needsReview: false)
            request.savedAtomicRevision = revision
            let preserved = Set(session.items.filter { $0.id != reviewItemID }.map(\.id))
            let outcome = try applyAtomicRevision(revision,request: request,session: session,
                preservingItemIDs: preserved,schedulesReminders: true)
            guard case .performed = outcome else {
                throw RepositoryError.saveFailed("The complete change needs more information. The saved item is unchanged.")
            }
            return
        }
        guard state.phase == .pendingChoice,
              state.reviewItemID == reviewItemID,
              state.operation == .cancel,
              state.candidateIDs.contains(targetID),
              let target = try findItem(withID: targetID),
              target.completedAt == nil, !target.isArchived,
              !target.belongsInMemory else {
            throw RepositoryError.saveFailed("That saved reminder has changed. Review the request again.")
        }
        guard let item = session.items.first(where: { $0.id == reviewItemID }) else {
            throw RepositoryError.saveFailed("The saved-item question is no longer available.")
        }
        state.phase = .performed
        state.targetID = targetID
        state.targetTitle = target.displayTitle
        state.oldDueDate = target.dueDate
        state.oldReminderDate = target.reminderDate
        state.resolvedAt = .now
        session.operationStateData = try JSONEncoder().encode(state)
        item.isArchived = true
        item.needsClarification = false
        modelContext.delete(target)
        try persistChanges(deletedItemIDs: [targetID])
        RecurrenceStore.remove(targetID)
        MemoryPinStore.removeMetadata(for: [targetID])
        ShoppingGroupStore.removeMetadata(for: [targetID])
        IdeaStageStore.removeMetadata(for: [targetID])
        LocationReminderMonitor.shared.stopMonitoring(itemID: targetID)
        ReminderScheduler.cancel(itemID: targetID)
    }

    /// Declines a held broad cancel or complete. Nothing the request would
    /// have touched is changed; the review row is removed the same way
    /// confirming it removes the row, since a decline is also a resolution,
    /// not something left to keep asking about.
    func dismissPendingOperation(_ item: CapturedItem) throws {
        if let session = item.captureSession,
           var state = CaptureOperationState.read(from: session.operationStateData),
           state.phase == .pendingChoice,
           state.reviewItemID == item.id {
            state.phase = .dismissed
            state.resolvedAt = .now
            session.operationStateData = try JSONEncoder().encode(state)
            item.isArchived = true
            item.needsClarification = false
            try persistChanges()
            return
        }
        PendingOperationStore.remove(item.id)
        try delete(item)
    }

    /// Removes the rows a capture created and closes it.
    ///
    /// Closing matters as much as deleting: `recoverUnorganizedCaptures` rebuilds
    /// a fallback item for any session that is not `.complete`, so a retraction
    /// left open would reappear at the next launch.
    private func discardCaptureItems(for session: CaptureSession, preserving itemIDs: Set<UUID> = []) {
        for item in session.items where !itemIDs.contains(item.id) {
            RecurrenceStore.remove(item.id)
            LocationReminderMonitor.shared.stopMonitoring(itemID: item.id)
            modelContext.delete(item)
        }
        closeSession(session)
    }

    private func holdOperation(
        _ request: CaptureOperationRequest,
        in session: CaptureSession,
        preserving itemIDs: Set<UUID>
    ) {
        if !itemIDs.isEmpty, !session.items.contains(where: { !itemIDs.contains($0.id) }) {
            let review = CapturedItem(
                originalTextSegment: request.sourceQuote,
                displayTitle: request.sourceQuote,
                createdAt: session.createdAt.addingTimeInterval(0.1),
                processingConfidence: 0,
                needsClarification: true,
                captureSession: session
            )
            modelContext.insert(review)
        }
        closeSession(session)
    }

    /// Marks a capture finished so launch recovery leaves it alone. The
    /// transcript itself is kept: the words are never what gets discarded.
    private func closeSession(_ session: CaptureSession) {
        let previousStatus = session.processingStatus
        session.processingStatus = .complete
        do { try persistChanges() }
        catch {
            // The store remains authoritative after rollback. SwiftData can
            // leave an already registered model's enum property cached; do
            // not report processing complete when that status never saved.
            session.processingStatus = previousStatus
        }
    }

#if DEBUG
    /// Disposable UI fixtures stay behind both UI-test launch flags in RootView.
    /// All persistent writes remain inside the repository.
    func seedSavedRevisionChoiceQA() throws {
        let descriptor = FetchDescriptor<CapturedItem>()
        guard try modelContext.fetch(descriptor).isEmpty else { return }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = .current
        for number in 1...3 {
            let original = "Email Lina the panel diagram by October 20 at \(3 + number * 2) PM. Remind me October 19 at \(7 + number * 2) \(number == 3 ? "PM" : "AM")."
            let due = calendar.date(from: DateComponents(year:2026,month:10,day:20,hour:15 + number * 2))!
            let alert = calendar.date(from: DateComponents(year:2026,month:10,day:19,hour:7 + number * 2))!
            // 13:00 is 1 PM, not 13 PM, in the immutable source.
            let source = number == 3 ? "Email Lina the panel diagram by October 20 at 9 PM. Remind me October 19 at 1 PM." : original
            let created = calendar.date(from:DateComponents(year:2026,month:10,day:4,hour:18,second:number))!
            let parent = CaptureSession(id:UUID(uuidString:"B1000000-0000-4000-8000-00000000000\(number)")!,originalTranscription:source,createdAt:created,captureSource:.inAppText,processingStatus:.complete)
            let temporal = TemporalIntent(kind:.exactDateTime,day:CalendarDay(from:due,calendar:calendar),
                time:WallClockTime(hour:15 + number * 2,minute:0),timeZoneIdentifier:calendar.timeZone.identifier,
                timeZoneBehavior:.deviceLocal,sourceText:source)
            let row = CapturedItem(id:UUID(uuidString:"A1000000-0000-4000-8000-00000000000\(number)")!,originalTextSegment:source,
                displayTitle:"Email Lina the panel diagram",itemType:.task,category:.general,createdAt:created,dueDate:due,
                reminderDate:alert,personName:"Lina",lastModifiedAt:created,temporalIntent:temporal,semanticState:.resolved,captureSession:parent)
            modelContext.insert(parent); modelContext.insert(row)
        }
        try persistChanges()
    }
    func mutateSavedRevisionChoiceQA() throws {
        guard let row = try findItem(withID:UUID(uuidString:"A1000000-0000-4000-8000-000000000003")!),
              try modelContext.fetch(FetchDescriptor<CaptureSession>()).contains(where: { CaptureOperationState.read(from:$0.operationStateData)?.pendingSavedRevision != nil }) else { return }
        row.personName = "Keira" // Keep timestamp: whole snapshot must detect it.
        try persistChanges()
    }

    func seedSplitDecisionQA() throws {
        let original = "A quiet room and a window over the garden."
        let session = CaptureSession(originalTranscription: original, captureSource: .sample, processingStatus: .complete)
        let item = CapturedItem(originalTextSegment: original, displayTitle: "Room and garden window",
            itemType: .note, needsClarification: true,
            semanticState: .contested(.uncertainClauseBoundary), captureSession: session)
        modelContext.insert(session)
        modelContext.insert(item)
        try persistChanges()
    }

    func seedRuntimeClarificationQA() throws {
        let clock = Date.now; var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .autoupdatingCurrent
        let day = calendar.date(from: DateComponents(year: 2026,month: 11,day: 19))!
        for (title,original,person,gap,due) in [
            ("Email Rowan about the panel","Email Rowan about the panel; I need to confirm which Rowan.","Rowan",SemanticGap.ambiguousPerson,Optional<Date>.none),
            ("Inspect the hinge","Inspect the hinge on November 19 or November 20.",nil,SemanticGap.ambiguousTemporalScope,Optional(day))
        ] {
            let session = CaptureSession(originalTranscription: original,createdAt: clock,captureSource: .sample,processingStatus: .complete)
            let intent: TemporalIntent? = due.map { TemporalIntent(kind: .dateOnly,day: CalendarDay(from: $0,calendar: calendar),
                time: nil,timeZoneIdentifier: calendar.timeZone.identifier,timeZoneBehavior: .deviceLocal,sourceText: original) }
            let item = CapturedItem(originalTextSegment: original,displayTitle: title,itemType: .task,category: .general,
                createdAt: clock,dueDate: due,reminderDate: nil,personName: person,processingConfidence: 0,needsClarification: true,
                temporalIntent: intent,semanticState: .underspecified(gap),captureSession: session)
            modelContext.insert(session); modelContext.insert(item)
        }
        try persistChanges()
    }
#endif

    func update(_ item: CapturedItem, with edits: ItemEdits) throws {
        // A person's own wording is not framing to be unwrapped. `reduceFrames`
        // is off here so somebody who types "We need to talk to the landlord"
        // gets what they typed, and the tidying that is genuinely about
        // presentation — whitespace, stray punctuation, sentence case — still
        // runs.
        let normalizedTitle = ThoughtTitleFormatter.polished(
            edits.title,
            itemType: edits.itemType,
            reduceFrames: false
        )
        guard !normalizedTitle.isEmpty else { throw RepositoryError.emptyTitle }
        let clarifiesObject = item.semanticState == .underspecified(.ambiguousObject)
            || (item.semanticState == .contested(.ambiguousObject)
                && normalizedTitle != item.displayTitle)
        let previousRecurrences = RecurrenceStore.snapshots()
        // A person, destination or title correction is not a timing answer.
        // Preserve the typed condition/day/clock unless a temporal field was
        // actually changed by this edit. In particular, do not erase an
        // unresolved prerequisite while accepting a recipient correction.
        let temporalFieldsChanged = item.dueDate != edits.dueDate
            || item.reminderDate != edits.reminderDate
            || RecurrenceStore.rule(for: item.id) != edits.recurrenceRule
            || (edits.dueDate != nil && item.isDateOnly == edits.dueDateHasTime)
            || edits.clarifiedGap == .ambiguousTemporalScope

        if !edits.needsClarification, let answered = edits.clarifiedGap,
           item.semanticGapRawValue == answered.rawValue { item.semanticState = .resolved }
        item.displayTitle = normalizedTitle
        // Only a title the automatic pass would disagree with needs protecting.
        // Recording every edit would freeze the title of anyone who only
        // changed a due date.
        if ThoughtTitleFormatter.polished(normalizedTitle, itemType: edits.itemType) == normalizedTitle {
            HandEditedTitleStore.forget(item.id)
        } else {
            HandEditedTitleStore.remember(item.id)
        }
        item.itemType = edits.itemType
        item.category = edits.category
        item.dueDate = edits.dueDate
        item.reminderDate = edits.reminderDate
        item.priority = edits.priority
        item.personName = edits.personName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        item.needsClarification = edits.needsClarification
        if clarifiesObject, !edits.needsClarification {
            item.semanticState = .resolved
        }
        if item.semanticState == .underspecified(.ambiguousTemporalScope),
           !edits.needsClarification, edits.reminderDate != nil {
            item.semanticState = .resolved
        }
        // An explicit edit outranks the sentence. The original wording stays in
        // `originalTextSegment` as provenance forever, but the intent is now
        // what the person set by hand, and `isUserEdited` stops any later
        // reparse from quietly reverting it.
        if temporalFieldsChanged {
            item.temporalIntent = TemporalIntent.userEdited(
                dueDate: edits.dueDate,
                reminderDate: edits.reminderDate,
                recurrence: edits.recurrenceRule,
                sourceText: item.temporalIntent?.sourceText ?? item.originalTextSegment,
                calendar: .autoupdatingCurrent,
                dueDateHasTime: edits.dueDateHasTime
            )
            RecurrenceStore.set(edits.recurrenceRule, for: item.id)
        }

        // The same rule the temporal half follows: an explicit edit outranks the
        // sentence, and `isUserEdited` stops a later reparse from reverting it.
        var locationChanged = false
        switch edits.locationIntent {
        case .unchanged:
            break
        case var .update(intent):
            if let previous = item.locationIntent {
                let triggerChanged = intent.event != previous.event
                    || intent.place != previous.place
                    || intent.repeats != previous.repeats
                    || intent.resolvedPlace != previous.resolvedPlace
                if triggerChanged {
                    intent.triggerRevision = previous.triggerRevision + 1
                    intent.firedAt = nil
                } else {
                    // Saving an editor that was opened before a crossing must not
                    // resurrect a spent one-shot with its stale local copy.
                    intent.triggerRevision = previous.triggerRevision
                    intent.firedAt = previous.firedAt
                }
            }
            intent.isUserEdited = true
            item.locationIntent = intent
            locationChanged = true
        case .remove:
            item.locationIntent = nil
            locationChanged = true
        }

        item.isReviewed = true
        item.lastModifiedAt = .now
        do {
            try persistChanges()
        } catch {
            RecurrenceStore.restore(previousRecurrences)
            throw error
        }
        synchronizeReminders(for: item.captureSession, requestAuthorizationIfNeeded: true)
        // Regions are registered from stored intents, so a trigger that was
        // changed or removed has to be re-reconciled or iOS keeps watching the
        // old one. Turning a place reminder off in the editor and still being
        // notified at that place is exactly the failure this prevents.
        if locationChanged {
            reconcileLocationReminders()
        }
        if item.captureSession?.captureSource != .tutorial, let personName = item.personName {
            SpeechVocabularyStore.rememberContextualPhrases([personName])
        }
    }

    func setCompleted(_ item: CapturedItem, completed: Bool) throws {
        let completedAt = Date.now
        let previousRecurrences = RecurrenceStore.snapshots()
        var deletedGeneratedItemID: UUID?

        if completed, !item.isCompleted,
           RecurrenceStore.generatedNextItemID(for: item.id) == nil,
           let rule = RecurrenceStore.rule(for: item.id),
           let session = item.captureSession,
           let nextDate = nextRecurrenceDate(for: item, rule: rule, completedAt: completedAt) {
            let reminderOffset = item.reminderDate.flatMap { reminder in
                item.dueDate.map { reminder.timeIntervalSince($0) }
            } ?? 0
            let next = CapturedItem(
                originalTextSegment: item.originalTextSegment,
                displayTitle: item.displayTitle,
                itemType: item.itemType,
                category: item.category,
                createdAt: completedAt,
                dueDate: nextDate,
                reminderDate: item.reminderDate == nil ? nil : nextDate.addingTimeInterval(reminderOffset),
                priority: item.priority,
                personName: item.personName,
                processingConfidence: item.processingConfidence,
                needsClarification: false,
                isReviewed: item.isReviewed,
                lastModifiedAt: completedAt,
                temporalIntent: carriedIntent(from: item, toOccurrenceOn: nextDate),
                captureSession: session
            )
            // Same reading, carried forward. See `advanceOverdueRecurrences`.
            next.copySemanticRecord(from: item)
            modelContext.insert(next)
            RecurrenceStore.inherit(from: item.id, to: next.id)
            RecurrenceStore.link(completed: item.id, to: next.id)
        } else if !completed,
                  let generatedID = RecurrenceStore.generatedNextItemID(for: item.id),
                  let generated = try findItem(withID: generatedID),
                  !generated.isCompleted {
            modelContext.delete(generated)
            RecurrenceStore.remove(generatedID)
            RecurrenceStore.clearGeneratedLink(for: item.id)
            deletedGeneratedItemID = generatedID
        }

        item.completedAt = completed ? completedAt : nil
        item.lastModifiedAt = .now
        do {
            try persistChanges(deletedItemIDs: deletedGeneratedItemID.map { [$0] } ?? [])
        } catch {
            RecurrenceStore.restore(previousRecurrences)
            throw error
        }
        if let deletedGeneratedItemID {
            MemoryPinStore.removeMetadata(for: [deletedGeneratedItemID])
            ShoppingGroupStore.removeMetadata(for: [deletedGeneratedItemID])
            IdeaStageStore.removeMetadata(for: [deletedGeneratedItemID])
        }
        if completed { ReminderScheduler.cancel(itemID: item.id) }
        // Completing or reopening work is not the moment to interrupt with a
        // permission prompt. Any reminder in this session was already created
        // deliberately; reconcile it against the current permission and let
        // the existing permission UI explain a missing grant.
        synchronizeReminders(for: item.captureSession, requestAuthorizationIfNeeded: false)
    }

    func setArchived(_ item: CapturedItem, archived: Bool) throws {
        item.isArchived = archived
        item.archivedAt = archived ? .now : nil
        item.lastModifiedAt = .now
        try persistChanges()
        if archived {
            ReminderScheduler.cancel(itemID: item.id)
            if MemoryPinStore.records()[item.id]?.isPinned == true {
                MemoryPinStore.setPinned(false, for: item.id)
            }
        }
        // Restoring an archived item can make an old reminder live again, but
        // it must not surface a surprise system prompt from a fire-and-forget
        // repository mutation.
        synchronizeReminders(for: item.captureSession, requestAuthorizationIfNeeded: false)
    }

    func markReviewed(_ item: CapturedItem) throws {
        item.isReviewed = true
        item.needsClarification = false
        item.lastModifiedAt = .now
        try persistChanges()
    }

    func delete(_ item: CapturedItem) throws {
        let itemID = item.id
        let session = item.captureSession
        let deletesSession = (session?.items.count ?? 0) <= 1
        let recurrenceIDs = deletesSession ? (session?.items.map(\.id) ?? [itemID]) : [itemID]
        let sessionID = session?.id
        if let session, deletesSession {
            modelContext.delete(session)
        } else {
            modelContext.delete(item)
        }
        if session?.captureSource == .tutorial {
            try persistChanges()
        } else {
            try persistChanges(
                deletedItemIDs: recurrenceIDs,
                deletedSessionIDs: deletesSession ? sessionID.map { [$0] } ?? [] : []
            )
        }
        recurrenceIDs.forEach(RecurrenceStore.remove)
        MemoryPinStore.removeMetadata(for: recurrenceIDs)
        ShoppingGroupStore.removeMetadata(for: recurrenceIDs)
        IdeaStageStore.removeMetadata(for: recurrenceIDs)
        ReminderScheduler.synchronize(
            [],
            requestAuthorizationIfNeeded: false,
            scope: ReminderSynchronizationScope(
                itemIDs: Set(recurrenceIDs),
                captureSessionIDs: sessionID.map { Set([$0]) } ?? []
            )
        )
        if !deletesSession {
            synchronizeReminders(for: session, requestAuthorizationIfNeeded: false)
        }
    }

    func keepAsOneThought(_ item: CapturedItem) throws {
        let operation = CaptureOperationState.read(from: item.captureSession?.operationStateData)
        guard PendingOperationStore.record(for: item.id) == nil,
              !(operation?.phase == .pendingChoice
                && (operation?.reviewItemID == nil || operation?.reviewItemID == item.id)) else {
            throw RepositoryError.saveFailed("Confirm or decline the saved change separately.")
        }
        guard item.clarificationRequirement == .splitDecision else {
            throw RepositoryError.saveFailed("This item needs a different answer before it can leave review.")
        }

        let recordedSplit = item.semanticState?.gap == .uncertainClauseBoundary
        if recordedSplit { item.semanticState = .resolved }
        item.isReviewed = true
        // Grouping says nothing about an unknown destination or recipient.
        // A legacy row has only one review Bool; do not assume that its missing
        // time was answered just because the broad split heuristic came first.
        let missingPerson = item.itemType == .personFollowUp
            && item.personName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false
        item.needsClarification = item.itemType == .unclear || missingPerson
            || (!recordedSplit && item.itemType.isActionable && item.reminderDate == nil)
        item.lastModifiedAt = .now
        try persistChanges()
        // This decision never reparses the words, changes timing, or requests
        // notification permission. Original capture and sibling rows stay put.
    }

    func split(_ item: CapturedItem, into parts: [String]) throws {
        let normalizedParts = parts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard normalizedParts.count >= 2, normalizedParts.count <= 12 else {
            throw RepositoryError.invalidSplit
        }
        guard let session = item.captureSession else {
            throw RepositoryError.saveFailed("The original capture is unavailable.")
        }
        // A completed split keeps the first row's identity and creates its
        // children at deterministic offsets. Recognize only that exact saved
        // result before replaying an identical editor submission; otherwise
        // a second tap/relaunch would insert duplicate reminders. Different
        // edited parts or missing children still use the ordinary mutation.
        if item.isReviewed, item.originalTextSegment == normalizedParts[0],
           normalizedParts.dropFirst().enumerated().allSatisfy({ offset, part in
               let childDate = item.createdAt.addingTimeInterval(Double(offset + 1) / 1_000)
               return session.items.contains {
                   $0.id != item.id && $0.isReviewed
                       && $0.createdAt == childDate && $0.originalTextSegment == part
               }
           }) {
            return
        }
        let previousRecurrences = RecurrenceStore.snapshots()

        let candidates = normalizedParts.map { part -> ExtractedThought in
            let organization = ThoughtOrganizer.organize(
                part,
                referenceDate: session.createdAt
            )
            return ExtractedThought(
                sourceQuote: part,
                rawQuote: part,
                wasRepaired: false,
                analysisText: part,
                suggestedTitle: nil,
                organization: organization,
                confidence: 1,
                needsReview: organization.needsClarification
            )
        }

        apply(candidates[0], to: item, createdAt: item.createdAt, reviewed: true)
        for (offset, candidate) in candidates.dropFirst().enumerated() {
            let newItem = makeItem(
                from: candidate,
                session: session,
                createdAt: item.createdAt.addingTimeInterval(Double(offset + 1) / 1_000),
                reviewed: true
            )
            modelContext.insert(newItem)
        }
        session.processingStatus = .complete
        session.processingError = nil
        do {
            try persistChanges()
        } catch {
            RecurrenceStore.restore(previousRecurrences)
            throw error
        }
        synchronizeReminders(for: session, requestAuthorizationIfNeeded: true)
    }

    func merge(_ items: [CapturedItem]) throws {
        let uniqueByID = items.reduce(into: [UUID: CapturedItem]()) { result, item in
            result[item.id] = item
        }
        let uniqueItems = uniqueByID.values.sorted(by: itemOrder)
        guard uniqueItems.count >= 2,
              let session = uniqueItems.first?.captureSession,
              uniqueItems.allSatisfy({ $0.captureSession?.id == session.id }) else {
            throw RepositoryError.invalidMerge
        }

        let target = uniqueItems[0]
        let previousRecurrences = RecurrenceStore.snapshots()
        let removed = Array(uniqueItems.dropFirst())
        let sourceText = uniqueItems.map(\.originalTextSegment).joined(separator: " and ")
        let title = uniqueItems.map(\.displayTitle).joined(separator: " & ")
        let organization = ThoughtOrganizer.organize(
            sourceText,
            referenceDate: session.createdAt
        )
        let candidate = ExtractedThought(
            sourceQuote: sourceText,
            // Joined from the stored `originalTextSegment`s, which are already
            // the person's words.
            rawQuote: sourceText,
            wasRepaired: false,
            analysisText: sourceText,
            suggestedTitle: title,
            organization: organization,
            confidence: 1,
            needsReview: organization.needsClarification
        )
        apply(candidate, to: target, createdAt: target.createdAt, reviewed: true)
        let removedIDs = removed.map(\.id)
        removed.forEach(modelContext.delete)
        session.processingStatus = .complete
        session.processingError = nil
        do {
            try persistChanges(deletedItemIDs: removedIDs)
        } catch {
            RecurrenceStore.restore(previousRecurrences)
            throw error
        }
        removedIDs.forEach {
            RecurrenceStore.remove($0)
            ReminderScheduler.cancel(itemID: $0)
        }
        MemoryPinStore.removeMetadata(for: removedIDs)
        ShoppingGroupStore.removeMetadata(for: removedIDs)
        IdeaStageStore.removeMetadata(for: removedIDs)
        synchronizeReminders(for: session, requestAuthorizationIfNeeded: true)
    }

    func undoOrganization(_ session: CaptureSession) throws {
        let operation = CaptureOperationState.read(from: session.operationStateData)
        guard operation?.phase != .performed else {
            throw RepositoryError.saveFailed("This capture records a saved change. Edit the saved item to change it again.")
        }
        guard operation?.phase != .pendingChoice,
              session.items.allSatisfy({ PendingOperationStore.record(for: $0.id) == nil }) else {
            throw RepositoryError.saveFailed("Confirm or decline the saved change before undoing organization.")
        }
        let previousRecurrences = RecurrenceStore.snapshots()
        ensureFallbackItem(for: session)
        let ordered = orderedItems(in: session)
        guard let target = ordered.first else { return }
        let removed = Array(ordered.dropFirst())
        let rawOrganization = OrganizedThought(
            itemType: .unclear,
            category: .general,
            priority: .normal,
            personName: nil,
            dueDate: nil,
            reminderDate: nil,
            reminderDelivery: .none,
            recurrenceRule: nil,
            needsClarification: true
        )
        apply(
            ExtractedThought(
                sourceQuote: session.originalTranscription,
                // The fallback that keeps an unreadable capture: the untouched
                // transcript is both the quote and the raw span.
                rawQuote: session.originalTranscription,
                wasRepaired: false,
                analysisText: session.originalTranscription,
                suggestedTitle: session.originalTranscription,
                organization: rawOrganization,
                confidence: 0,
                needsReview: true
            ),
            to: target,
            createdAt: session.createdAt,
            // Undo is an explicit grouping decision, not another request for
            // the splitter to reconsider the same transcript. Type stays
            // unclear and review stays on until the person chooses a purpose.
            reviewed: true
        )
        let removedIDs = removed.map(\.id)
        removed.forEach(modelContext.delete)
        session.processingStatus = .complete
        session.processingError = nil
        do {
            try persistChanges(deletedItemIDs: removedIDs)
        } catch {
            RecurrenceStore.restore(previousRecurrences)
            throw error
        }
        removedIDs.forEach {
            RecurrenceStore.remove($0)
            ReminderScheduler.cancel(itemID: $0)
        }
        MemoryPinStore.removeMetadata(for: removedIDs)
        ShoppingGroupStore.removeMetadata(for: removedIDs)
        IdeaStageStore.removeMetadata(for: removedIDs)
        synchronizeReminders(for: session, requestAuthorizationIfNeeded: false)
    }

    func reorganize(_ session: CaptureSession) throws {
        guard CaptureOperationState.read(from: session.operationStateData)?.phase != .performed else {
            throw RepositoryError.saveFailed("This capture records a saved change. Edit the saved item to change it again.")
        }
        ensureFallbackItem(for: session)
        let extraction = ThoughtExtractionEngine.extractWithRules(
            session.originalTranscription,
            referenceDate: session.createdAt
        )
        _ = organizePersistedCapture(
            session: session,
            extraction: extraction,
            schedulesReminders: true
        )
    }

    private func normalizedCaptureText(_ text: String) throws -> String {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { throw RepositoryError.emptyCapture }
        return normalized
    }

    private func createPendingCapture(
        text: String,
        source: CaptureSource,
        createdAt: Date
    ) throws -> (session: CaptureSession, placeholder: CapturedItem) {
        let session = CaptureSession(
            originalTranscription: text,
            createdAt: createdAt,
            captureSource: source,
            processingStatus: .pending
        )
        let placeholder = CapturedItem(
            originalTextSegment: text,
            displayTitle: ThoughtTitleFormatter.polished(text, itemType: .unclear),
            createdAt: createdAt,
            processingConfidence: 0,
            needsClarification: true,
            isReviewed: false,
            lastModifiedAt: createdAt,
            captureSession: session
        )
        modelContext.insert(session)
        modelContext.insert(placeholder)

        // The raw words are committed before extraction so classification can
        // never cost somebody a capture.
        let signpost = CapturePerformanceSignposts.begin("RawCapturePersistence")
        defer { CapturePerformanceSignposts.end("RawCapturePersistence", signpost) }
        try persistChanges()
        return (session, placeholder)
    }

    @discardableResult
    private func organizePersistedCapture(
        session: CaptureSession,
        extraction: ThoughtExtractionResult,
        schedulesReminders: Bool,
        performance: CapturePerformanceTrace? = nil
    ) -> [CapturedItem] {
        let previousRecurrences = RecurrenceStore.snapshots()
        session.processingStatus = .organizing
        let candidates = extraction.items.isEmpty
            ? ThoughtExtractionEngine.extractWithRules(
                session.originalTranscription,
                referenceDate: session.createdAt
            ).items
            : extraction.items
        let oldItems = orderedItems(in: session)
        ensureFallbackItem(for: session)
        let existingItems = orderedItems(in: session)
        var organized: [CapturedItem] = []

        for (index, candidate) in candidates.enumerated() {
            let createdAt = session.createdAt.addingTimeInterval(Double(index) / 1_000)
            if index < existingItems.count {
                let item = existingItems[index]
                apply(candidate, to: item, createdAt: createdAt, reviewed: false)
                organized.append(item)
            } else {
                let item = makeItem(
                    from: candidate,
                    session: session,
                    createdAt: createdAt,
                    reviewed: false
                )
                modelContext.insert(item)
                organized.append(item)
            }
        }

        let extras = Array(existingItems.dropFirst(candidates.count))
        let extraIDs = extras.map(\.id)
        extras.forEach(modelContext.delete)
        session.processingStatus = .complete
        session.processingError = nil

        do {
            try persistChanges(deletedItemIDs: extraIDs)
            extraIDs.forEach {
                RecurrenceStore.remove($0)
                ReminderScheduler.cancel(itemID: $0)
            }
            MemoryPinStore.removeMetadata(for: extraIDs)
            ShoppingGroupStore.removeMetadata(for: extraIDs)
            IdeaStageStore.removeMetadata(for: extraIDs)
            if schedulesReminders {
                synchronizeReminders(
                    for: session,
                    requestAuthorizationIfNeeded: true,
                    performance: performance
                )
            }
            freezeCurrentLocationSnapshots(in: organized)
            return organized.sorted(by: itemOrder)
        } catch {
            RecurrenceStore.restore(previousRecurrences)
            // The first transaction already made the raw transcript durable.
            session.processingStatus = .failed
            session.processingError = error.localizedDescription
            try? modelContext.save()
            return oldItems.isEmpty ? orderedItems(in: session) : oldItems
        }
    }

    /// Freezes the coordinate behind any `"here"` in this capture.
    ///
    /// Deliberately fire-and-forget rather than part of the save. Capture
    /// durability outranks convenience: a location fix can take seconds or never
    /// arrive at all, and blocking the transcript on it would risk the one thing
    /// that must never be lost. The thought is already persisted when this runs,
    /// and an unresolved `"here"` is an honest, recoverable state that reports
    /// `locationUnavailable` rather than a wrong place.
    private func freezeCurrentLocationSnapshots(in items: [CapturedItem]) {
        let unresolved = items.filter {
            $0.locationIntent?.place == .currentLocation
                && $0.locationIntent?.resolvedPlace == nil
        }
        guard !unresolved.isEmpty else { return }
        let itemIDs = unresolved.map(\.id)
        Task { [weak self] in
            await self?.resolveCurrentLocationSnapshots(itemIDs: itemIDs)
        }
    }

    private func resolveCurrentLocationSnapshots(itemIDs: [UUID]) async {
        let provider = CurrentLocationProvider()
        // A fix iOS already has is *better* than a fresh one here, not merely
        // cheaper: it is closer in time to the moment the person said "here".
        // Requesting a new one can take seconds, by which time they may have
        // walked out of the very region being pinned.
        let coordinate: CLLocationCoordinate2D
        if let recent = provider.recentCoordinate {
            coordinate = recent
        } else if let fetched = try? await provider.currentCoordinate() {
            coordinate = fetched
        } else {
            // Nothing to record. The reminder keeps saying "here" and keeps
            // reporting that it could not be placed, which is recoverable.
            return
        }

        let resolved = ResolvedPlace(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            resolvedAt: .now
        )

        for itemID in itemIDs {
            guard let item = try? findItem(withID: itemID),
                  var intent = item.locationIntent,
                  intent.place == .currentLocation,
                  // An edit that happened while the fix was in flight wins. The
                  // person's own choice always outranks a late arrival.
                  intent.resolvedPlace == nil,
                  !intent.isUserEdited else { continue }
            intent.resolvedPlace = resolved
            item.locationIntent = intent
        }
        try? persistChanges()
        reconcileLocationReminders()

        // Deliberately no reverse-geocode here.
        //
        // Naming the spot would send the person's exact coordinate to Apple for
        // a purely cosmetic label — the one location call they never asked for,
        // on the one path that is otherwise entirely on-device: speak a thought,
        // freeze a coordinate, monitor a region, no network at all. "when you
        // leave here" is already perfectly legible, so the label is not worth
        // transmitting a position for. Naming is offered explicitly instead, in
        // `nameCurrentLocationSnapshot(itemID:)`.
    }

    /// Names a frozen "here", on explicit request only.
    ///
    /// Separate from capture on purpose: this is the point where the person has
    /// asked for the label, which makes the lookup theirs to initiate rather
    /// than something the app does behind them. Returns the name it stored, or
    /// `nil` when the lookup found nothing usable — the reminder is unaffected
    /// either way, because it fires on the coordinate.
    @discardableResult
    func nameCurrentLocationSnapshot(itemID: UUID) async -> String? {
        guard let item = try? findItem(withID: itemID),
              let intent = item.locationIntent,
              intent.place == .currentLocation,
              let resolved = intent.resolvedPlace else { return nil }

        let placemarks = try? await CLGeocoder().reverseGeocodeLocation(
            CLLocation(latitude: resolved.latitude, longitude: resolved.longitude)
        )
        guard let placemark = placemarks?.first else { return nil }
        let name = placemark.name ?? placemark.thoroughfare ?? placemark.locality
        guard let name, !name.isEmpty else { return nil }

        // Re-read after the await: the item may have been edited while the
        // lookup was in flight, and an explicit edit outranks a late arrival.
        guard let fresh = try? findItem(withID: itemID),
              var freshIntent = fresh.locationIntent,
              freshIntent.place == .currentLocation,
              var freshResolved = freshIntent.resolvedPlace,
              freshResolved.matchedName == nil else { return nil }
        freshResolved.matchedName = name
        freshIntent.resolvedPlace = freshResolved
        fresh.locationIntent = freshIntent
        try? persistChanges()
        return name
    }

    private func apply(
        _ candidate: ExtractedThought,
        to item: CapturedItem,
        createdAt: Date,
        reviewed: Bool
    ) {
        let organization = candidate.organization
        item.originalTextSegment = candidate.sourceQuote
        item.displayTitle = displayTitle(
            for: candidate,
            spokenFallback: item.captureSession?.originalTranscription ?? ""
        )
        item.itemType = organization.itemType
        item.category = organization.category
        item.priority = organization.priority
        item.personName = organization.personName
        item.dueDate = organization.dueDate
        item.reminderDate = organization.reminderDate
        item.createdAt = createdAt
        item.processingConfidence = candidate.confidence
        item.needsClarification = organization.needsClarification || candidate.needsReview
        item.isReviewed = reviewed
        item.lastModifiedAt = .now
        item.temporalIntent = organization.temporalIntent
        // The interpreter's own verdict, kept rather than dropped. Before
        // version 4 this line did not exist and every screen that wanted the
        // reason re-derived one from the fields below — see
        // `CapturedItem.semanticState`.
        item.semanticState = organization.state
        // A hand-set place outranks the sentence, exactly as a hand-set time
        // does. Reorganizing a capture must not revert it.
        if item.locationIntent?.isUserEdited != true {
            var reparsed = organization.locationIntent
            // Reorganizing re-reads the same sentence, so it must not hand a
            // spent one-shot a second life. The delivery already happened; it is
            // a fact about this reminder, not a reading of the wording. Carried
            // over only when the reparse still names the same crossing — a
            // genuinely different place or direction is a different reminder and
            // has not fired yet.
            if let previous = item.locationIntent, previous.firedAt != nil,
               reparsed?.event == previous.event, reparsed?.place == previous.place {
                reparsed?.firedAt = previous.firedAt
            }
            item.locationIntent = reparsed
        }
        RecurrenceStore.set(organization.recurrenceRule, for: item.id)
        ShoppingGroupStore.set(
            organization.itemType == .shopping ? candidate.shoppingGroup : nil,
            for: item.id
        )
    }

    private func makeItem(
        from candidate: ExtractedThought,
        session: CaptureSession,
        createdAt: Date,
        reviewed: Bool
    ) -> CapturedItem {
        let organization = candidate.organization
        let item = CapturedItem(
            originalTextSegment: candidate.sourceQuote,
            displayTitle: displayTitle(
                for: candidate,
                spokenFallback: session.originalTranscription
            ),
            itemType: organization.itemType,
            category: organization.category,
            createdAt: createdAt,
            dueDate: organization.dueDate,
            reminderDate: organization.reminderDate,
            priority: organization.priority,
            personName: organization.personName,
            processingConfidence: candidate.confidence,
            needsClarification: organization.needsClarification || candidate.needsReview,
            isReviewed: reviewed,
            lastModifiedAt: .now,
            temporalIntent: organization.temporalIntent,
            locationIntent: organization.locationIntent,
            semanticState: organization.state,
            captureSession: session
        )
        RecurrenceStore.set(organization.recurrenceRule, for: item.id)
        ShoppingGroupStore.set(
            organization.itemType == .shopping ? candidate.shoppingGroup : nil,
            for: item.id
        )
        return item
    }

    private func displayTitle(
        for candidate: ExtractedThought,
        spokenFallback: String
    ) -> String {
        // A complete filler-only capture has no meaningful prefix to polish
        // away. Preserve all its original audible words, including "you know".
        if RuntimeShortSourceCertificate.isDisfluencyOnly(spokenFallback) {
            return spokenFallback.trimmingCharacters(in:.whitespacesAndNewlines)
        }
        let rawTitle: String
        if let title = candidate.suggestedTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
           !title.isEmpty {
            rawTitle = title
        } else if candidate.organization.reminderDate != nil {
            rawTitle = ReminderCopy.action(from: candidate.analysisText)
        } else {
            rawTitle = candidate.sourceQuote
        }
        let polished = ThoughtTitleFormatter.polished(
            rawTitle,
            itemType: candidate.organization.itemType,
            personName: candidate.organization.personName
        )
        if !polished.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return polished
        }
        // A capture that is nothing but filler — "um", "uh", "hmm", "yeah" —
        // reaches here with every text field already empty: extraction drops
        // filler, so `sourceQuote`, `rawQuote` and `analysisText` are all "".
        // The row is still created, and a row with no words renders as a blank
        // line the person cannot read or tap by name, and that VoiceOver
        // announces as "Complete ." The session transcript is the one place
        // those words survive, and showing them back is exactly the promise the
        // app is built on.
        for fallback in [
            candidate.rawQuote,
            candidate.sourceQuote,
            candidate.analysisText,
            spokenFallback
        ] {
            let trimmed = fallback.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            return trimmed.prefix(1).uppercased() + trimmed.dropFirst()
        }
        return polished
    }

    private func ensureFallbackItem(for session: CaptureSession) {
        guard session.items.isEmpty else { return }
        let item = CapturedItem(
            originalTextSegment: session.originalTranscription,
            displayTitle: ThoughtTitleFormatter.polished(
                session.originalTranscription,
                itemType: .unclear
            ),
            createdAt: session.createdAt,
            processingConfidence: 0,
            needsClarification: true,
            captureSession: session
        )
        modelContext.insert(item)
    }

    /// Bumped when `ThoughtTitleFormatter` changes what a title should read.
    /// Version 2 is `ObligationFrame`.
    /// Internal rather than private so a test can put a fresh install back on
    /// the clock; the stamp is process-wide and would otherwise leak from one
    /// test into the next.
    static let titlePolishVersionKey = "SpeakIt.titlePolishFormatterVersion"
    static let titlePolishVersion = 2

    /// Brings titles written by an older formatter up to the current contract,
    /// **once per formatter version** rather than on every launch.
    ///
    /// It used to run unconditionally, on the main actor, over every row in the
    /// store, at every launch — paying for a rewrite that had already happened.
    /// Worse, it re-entered on its own output, so a formatter that was not
    /// idempotent kept shortening the same title across successive launches.
    /// Stamping the version makes the pass converge and makes a bad reduction a
    /// bug that can be fixed rather than damage that has already been written.
    ///
    /// A title the person typed themselves is never touched — see
    /// `HandEditedTitleStore`. The original wording is not touched either, by
    /// anything, ever: `originalTextSegment` and the session transcript are not
    /// written here.
    private func polishPersistedDisplayTitles() {
        let defaults = UserDefaults.standard
        guard defaults.integer(forKey: Self.titlePolishVersionKey) < Self.titlePolishVersion else {
            return
        }
        guard let items = try? modelContext.fetch(FetchDescriptor<CapturedItem>()) else {
            // Deliberately unstamped. The store can be unreachable at the first
            // launch after an upgrade — protected data is not available until
            // the first unlock after a reboot — and stamping here would retire
            // the migration having done nothing, leaving the person's whole
            // backlog on the old formatter forever. Not stamping costs one
            // cheap fetch on the next launch instead.
            return
        }
        var changed = false

        for item in items {
            guard !HandEditedTitleStore.contains(item.id) else { continue }
            let polished = ThoughtTitleFormatter.polished(
                item.displayTitle,
                itemType: item.itemType
            )
            guard !polished.isEmpty, polished != item.displayTitle else { continue }
            // Only rewrite where the rewrite settles. `polished` is written for
            // a *transcript*, and `ReminderCopy` inside it will happily read an
            // already-stored title as if it were one more spoken sentence:
            // "Set an alarm for 6 AM" becomes "Alarm", and running again would
            // take more. Requiring a fixpoint means this pass can only ever
            // move a title to somewhere it would also have landed if it had
            // been written by the current formatter in the first place.
            guard ThoughtTitleFormatter.polished(polished, itemType: item.itemType) == polished else {
                continue
            }
            item.displayTitle = polished
            changed = true
        }

        if changed {
            // Same reasoning: a failed save must not retire the migration, or
            // the rewrite is lost and never attempted again.
            do { try persistChanges() } catch { return }
        }
        defaults.set(Self.titlePolishVersion, forKey: Self.titlePolishVersionKey)
    }

    private func orderedItems(in session: CaptureSession) -> [CapturedItem] {
        session.items.sorted(by: itemOrder)
    }

    private func itemOrder(_ lhs: CapturedItem, _ rhs: CapturedItem) -> Bool {
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private func persistChanges(
        deletedItemIDs: [UUID] = [],
        deletedSessionIDs: [UUID] = []
    ) throws {
        let previousDeletionRecords = ICloudDeletionStore.records()
        if !deletedItemIDs.isEmpty || !deletedSessionIDs.isEmpty {
            ICloudDeletionStore.markDeleted(
                itemIDs: deletedItemIDs,
                sessionIDs: deletedSessionIDs
            )
        }
        do {
            try modelContext.save()
            publishSharedTodaySnapshot()
            guard !isApplyingCloudSnapshot else { return }
            ICloudSyncState.markLocalChange()
            if ICloudSyncState.isEnabled {
                iCloudReconciliationTask?.cancel()
                iCloudReconciliationTask = Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .seconds(2))
                    guard !Task.isCancelled, let self else { return }
                    _ = await self.reconcileICloudSync()
                }
            }
        } catch {
            ICloudDeletionStore.restore(previousDeletionRecords)
            // Nothing reached the store, so the whole in-memory delta has to
            // go — and it has to go for *readers*, not just for the context's
            // own bookkeeping. `rollback()` alone does the latter: it clears the
            // pending changes while leaving the objects registered, so a fetch,
            // and therefore every `@Query` behind Today and Memory, keeps
            // returning rows that were never written. The person would be shown
            // an error and the thought at the same time, and the thought would
            // be gone at the next launch — the silent disappearance this app
            // exists to prevent.
            //
            // Re-reading the store is what makes the discard visible; the
            // processing pass then settles it. `testAFailedSaveWritesNothingDurable`
            // is what keeps this from quietly regressing.
            modelContext.rollback()
            _ = try? modelContext.fetchCount(FetchDescriptor<CapturedItem>())
            modelContext.processPendingChanges()
            throw RepositoryError.saveFailed(error.localizedDescription)
        }
    }

    /// Build 20 used an isolated store under the same app identity. Import it
    /// once, by stable IDs, without modifying or deleting that source store.
    /// The marker is written only after the merged library is durable.
    func importBuild20LibraryIfPresent(
        at sourceURL: URL? = nil,
        preferences: UserDefaults? = nil,
        sharedPreferences: UserDefaults? = nil,
        completionDefaults: UserDefaults = .standard
    ) throws {
        let marker = "SpeakIt.build20LibraryImported.v1"
        guard !completionDefaults.bool(forKey: marker) else { return }
        let url = sourceURL ?? FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        )[0].appendingPathComponent("SpeakItPreview/preview.store")
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let configuration = ModelConfiguration(
            schema: PersistenceController.schema, url: url,
            allowsSave: false, cloudKitDatabase: .none
        )
        let source = try ModelContainer(
            for: PersistenceController.schema,
            migrationPlan: SpeakItMigrationPlan.self, configurations: [configuration]
        )
        // Do not treat a failed fetch as an empty successful import.
        _ = try source.mainContext.fetch(FetchDescriptor<CaptureSession>())
        _ = try source.mainContext.fetch(FetchDescriptor<CapturedItem>())
        let prefs = preferences ?? UserDefaults(suiteName: "com.calvinwak.SpeakIt.preview-preferences")!
        let shared = sharedPreferences ?? UserDefaults(suiteName: "group.com.calvinwak.SpeakItPreview")!
        let metadata = try Build20Metadata(preferences: prefs, shared: shared)
        let reader = SwiftDataThoughtRepository(
            modelContext: source.mainContext, requestsReminderAuthorization: false
        )
        let incoming = reader.makeICloudSnapshot(legacy: metadata)
        let merged = ICloudSnapshotMerger.merge(local: makeICloudSnapshot(), cloud: incoming)
        try applyICloudSnapshot(merged)
        let importedIDs = Set(incoming.items.map(\.id))
        for id in metadata.handEditedTitles where importedIDs.contains(id) {
            HandEditedTitleStore.remember(id)
        }
        completionDefaults.set(true, forKey: marker)
    }

    private struct Build20Metadata {
        struct StoredRecurrence: Decodable {
            let rule: RecurrenceRule
            let seriesID: UUID
            let generatedNextItemID: UUID?
            let modifiedAt: Date?
        }
        let recurrences: [RecurrenceRecordSnapshot]
        let pins: [MemoryPinRecord]
        let ideas: [IdeaStageRecord]
        let shoppingGroups: [String: String]
        let handEditedTitles: Set<UUID>

        init(preferences: UserDefaults, shared: UserDefaults) throws {
            func read<T: Decodable>(_ type: T.Type, key: String, from defaults: UserDefaults) throws -> T? {
                guard let data = defaults.data(forKey: key) else { return nil }
                return try JSONDecoder().decode(type, from: data)
            }
            let stored = try read([String: StoredRecurrence].self, key: "SpeakIt.recurrence.v1", from: shared) ?? [:]
            recurrences = stored.compactMap { key, value in
                guard let id = UUID(uuidString: key) else { return nil }
                return RecurrenceRecordSnapshot(itemID: id, rule: value.rule,
                    seriesID: value.seriesID, generatedNextItemID: value.generatedNextItemID,
                    modifiedAt: value.modifiedAt ?? .distantPast)
            }
            pins = try read([MemoryPinRecord].self, key: "SpeakIt.pinnedMemoryRecords.v1", from: preferences)
                ?? MemoryPinStore.decode(preferences.string(forKey: MemoryPinStore.key) ?? "").map {
                    MemoryPinRecord(itemID: $0, isPinned: true, modifiedAt: .distantPast)
                }
            ideas = try read([IdeaStageRecord].self, key: "SpeakIt.ideaStageRecords.v1", from: preferences)
                ?? IdeaStageStore.decode(preferences.string(forKey: IdeaStageStore.key) ?? "").map {
                    IdeaStageRecord(itemID: $0.key, stage: $0.value, modifiedAt: .distantPast)
                }
            shoppingGroups = try read([String: String].self, key: "SpeakIt.shoppingGroups.v1", from: shared) ?? [:]
            handEditedTitles = Set((shared.stringArray(forKey: "SpeakIt.handEditedTitles.v1") ?? []).compactMap(UUID.init(uuidString:)))
        }
    }

    private func makeICloudSnapshot(legacy: Build20Metadata? = nil) -> ICloudLibrarySnapshot {

        // Practice is local, temporary UI state. Never upload it, even if the
        // user enables iCloud while the tutorial is still open.
        let sessions = ((try? modelContext.fetch(FetchDescriptor<CaptureSession>())) ?? [])
            .filter { $0.captureSource != .tutorial }
        let syncedSessionIDs = Set(sessions.map(\.id))
        let items = ((try? modelContext.fetch(FetchDescriptor<CapturedItem>())) ?? [])
            .filter { item in
                guard let sessionID = item.captureSession?.id else { return false }
                return syncedSessionIDs.contains(sessionID)
            }
        let syncedItemIDs = Set(items.map(\.id))
        return ICloudLibrarySnapshot(
            generatedAt: .now,
            sessions: sessions.map {
                ICloudSessionSnapshot(
                    id: $0.id,
                    originalTranscription: $0.originalTranscription,
                    createdAt: $0.createdAt,
                    captureSource: $0.captureSource,
                    processingStatus: $0.processingStatus,
                    processingError: $0.processingError,
                    lastModifiedAt: max(
                        $0.items.map(\.lastModifiedAt).max() ?? $0.createdAt,
                        CaptureOperationState.read(from: $0.operationStateData)?.resolvedAt ?? $0.createdAt
                    ),
                    operationStateData: $0.operationStateData
                )
            },
            items: items.compactMap { item in
                guard let sessionID = item.captureSession?.id else { return nil }
                return ICloudItemSnapshot(
                    id: item.id,
                    sessionID: sessionID,
                    originalTextSegment: item.originalTextSegment,
                    displayTitle: item.displayTitle,
                    itemType: item.itemType,
                    category: item.category,
                    createdAt: item.createdAt,
                    dueDate: item.dueDate,
                    reminderDate: item.reminderDate,
                    priority: item.priority,
                    personName: item.personName,
                    completedAt: item.completedAt,
                    isArchived: item.isArchived,
                    archivedAt: item.archivedAt,
                    processingConfidence: item.processingConfidence,
                    needsClarification: item.needsClarification,
                    isReviewed: item.isReviewed,
                    lastModifiedAt: item.lastModifiedAt,
                    recurrenceRule: legacy.map { value in value.recurrences.first { $0.itemID == item.id }?.rule } ?? RecurrenceStore.rule(for: item.id),
                    temporalIntent: item.temporalIntent,
                    portableSemantics: ICloudItemSemantics(
                        temporalIntent: item.temporalIntent,
                        locationIntent: item.locationIntent,
                        semanticStateRawValue: item.semanticStateRawValue,
                        semanticGapRawValue: item.semanticGapRawValue,
                        shoppingGroup: legacy.map { $0.shoppingGroups[item.id.uuidString] } ?? ShoppingGroupStore.group(for: item.id)
                    )
                )
            },
            deletionRecords: legacy == nil ? ICloudDeletionStore.records() : [],
            recurrenceRecords: (legacy?.recurrences ?? RecurrenceStore.snapshots()).filter {
                syncedItemIDs.contains($0.itemID)
            },
            pinRecords: (legacy?.pins ?? Array(MemoryPinStore.records().values)).filter {
                syncedItemIDs.contains($0.itemID)
            },
            ideaStageRecords: (legacy?.ideas ?? Array(IdeaStageStore.records().values)).filter {
                syncedItemIDs.contains($0.itemID)
            }
        )
    }

    private func applyICloudSnapshot(_ snapshot: ICloudLibrarySnapshot) throws {
        isApplyingCloudSnapshot = true
        defer { isApplyingCloudSnapshot = false }

        let existingSessions = try modelContext.fetch(FetchDescriptor<CaptureSession>())
        let existingItems = try modelContext.fetch(FetchDescriptor<CapturedItem>())
        let sessionsByID = Dictionary(uniqueKeysWithValues: existingSessions.map { ($0.id, $0) })
        let itemsByID = Dictionary(uniqueKeysWithValues: existingItems.map { ($0.id, $0) })
        var importedSessions: [UUID: CaptureSession] = [:]

        for value in snapshot.sessions {
            let session = sessionsByID[value.id] ?? CaptureSession(
                id: value.id,
                originalTranscription: value.originalTranscription,
                createdAt: value.createdAt,
                captureSource: value.captureSource,
                processingStatus: value.processingStatus,
                processingError: value.processingError
            )
            if sessionsByID[value.id] == nil { modelContext.insert(session) }
            session.originalTranscription = value.originalTranscription
            session.createdAt = value.createdAt
            session.captureSource = value.captureSource
            session.processingStatus = value.processingStatus
            session.processingError = value.processingError
            if let operationStateData = value.operationStateData {
                let local = CaptureOperationState.read(from: session.operationStateData)
                let incoming = try? JSONDecoder().decode(
                    CaptureOperationState.self, from: operationStateData
                )
                let localIsResolved = local?.phase == .performed || local?.phase == .dismissed
                let incomingIsPending = incoming?.phase == .pendingChoice
                if !(localIsResolved && incomingIsPending) {
                    session.operationStateData = operationStateData
                }
            }
            importedSessions[value.id] = session
        }

        for value in snapshot.items {
            guard let session = importedSessions[value.sessionID] else { continue }
            let item = itemsByID[value.id] ?? CapturedItem(
                id: value.id,
                originalTextSegment: value.originalTextSegment,
                displayTitle: value.displayTitle,
                captureSession: session
            )
            if itemsByID[value.id] == nil { modelContext.insert(item) }
            item.originalTextSegment = value.originalTextSegment
            item.displayTitle = value.displayTitle
            item.itemType = value.itemType
            item.category = value.category
            item.createdAt = value.createdAt
            item.dueDate = value.dueDate
            item.reminderDate = value.reminderDate
            // Only overwrite when the incoming snapshot actually carries an
            // intent. An older device that cannot express one must not erase
            // what this device already knows.
            if let semantics = value.portableSemantics {
                item.temporalIntent = semantics.temporalIntent
                item.locationIntent = semantics.locationIntent
                item.semanticStateRawValue = semantics.semanticStateRawValue
                item.semanticGapRawValue = semantics.semanticGapRawValue
            } else if let temporalIntent = value.temporalIntent {
                item.temporalIntent = temporalIntent
            }
            item.priority = value.priority
            item.personName = value.personName
            item.completedAt = value.completedAt
            item.isArchived = value.isArchived
            item.archivedAt = value.archivedAt
            item.processingConfidence = value.processingConfidence
            item.needsClarification = value.needsClarification
            item.isReviewed = value.isReviewed
            item.lastModifiedAt = value.lastModifiedAt
            item.captureSession = session
        }

        let cloudItemIDs = Set(snapshot.items.map(\.id))
        let cloudSessionIDs = Set(snapshot.sessions.map(\.id))
        let removedItemIDs = existingItems
            .filter { !cloudItemIDs.contains($0.id) }
            .map(\.id)
        for item in existingItems where !cloudItemIDs.contains(item.id) {
            RecurrenceStore.remove(item.id)
            modelContext.delete(item)
        }
        for session in existingSessions where !cloudSessionIDs.contains(session.id) {
            modelContext.delete(session)
        }
        try persistChanges()

        if let recurrenceRecords = snapshot.recurrenceRecords {
            RecurrenceStore.replace(with: recurrenceRecords, for: cloudItemIDs)
            let recurrenceIDs = Set(recurrenceRecords.map(\.itemID))
            for value in snapshot.items where value.recurrenceRule != nil && !recurrenceIDs.contains(value.id) {
                RecurrenceStore.set(
                    value.recurrenceRule,
                    for: value.id,
                    modifiedAt: value.lastModifiedAt
                )
            }
        } else {
            // Version-one snapshots only contained a rule. Preserve backwards
            // compatibility while immediately upgrading on the next upload.
            for value in snapshot.items {
                RecurrenceStore.set(
                    value.recurrenceRule,
                    for: value.id,
                    modifiedAt: value.lastModifiedAt
                )
            }
        }
        for value in snapshot.items {
            if let semantics = value.portableSemantics {
                ShoppingGroupStore.set(semantics.shoppingGroup, for: value.id)
            }
        }
        MemoryPinStore.apply(snapshot.pinRecords ?? [])
        IdeaStageStore.apply(snapshot.ideaStageRecords ?? [])
        MemoryPinStore.removeMetadata(for: removedItemIDs)
        ShoppingGroupStore.removeMetadata(for: removedItemIDs)
        IdeaStageStore.removeMetadata(for: removedItemIDs)
        ICloudDeletionStore.replace(with: snapshot.deletionRecords ?? [])
        reconcilePendingReminders()
    }

    private func todayItemOrder(_ lhs: CapturedItem, _ rhs: CapturedItem) -> Bool {
        switch (lhs.dueDate, rhs.dueDate) {
        case let (left?, right?) where left != right:
            return left < right
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        default:
            if lhs.priority != rhs.priority { return lhs.priority > rhs.priority }
            return lhs.createdAt < rhs.createdAt
        }
    }

    private func synchronizeReminders(
        for session: CaptureSession?,
        requestAuthorizationIfNeeded: Bool,
        performance: CapturePerformanceTrace? = nil
    ) {
        guard let session else { return }
        let requests = session.items
            .filter { !$0.isArchived && !$0.isCompleted }
            .compactMap(ReminderScheduleRequest.init(item:))
        var completion: (@MainActor ([ReminderSchedulingResult]) -> Void)? = nil
        if !requests.isEmpty {
            completion = { results in
                performance?.markNotificationSchedulingFinished(accepted:results.contains(.scheduled))
            }
        }
        ReminderScheduler.synchronize(
            requests,
            requestAuthorizationIfNeeded: requestAuthorizationIfNeeded && requestsReminderAuthorization,
            scope: ReminderSynchronizationScope(
                itemIDs: Set(session.items.map(\.id)),
                captureSessionIDs: [session.id]
            ),
            onCompletion: completion
        )
    }

    private func synchronizeAllReminders(requestAuthorizationIfNeeded: Bool) {
        let descriptor = FetchDescriptor<CapturedItem>(
            predicate: #Predicate { item in
                item.reminderDate != nil && item.isArchived == false && item.completedAt == nil
            }
        )
        let requests = (try? modelContext.fetch(descriptor))?.compactMap(ReminderScheduleRequest.init(item:)) ?? []
        ReminderScheduler.synchronize(
            requests,
            requestAuthorizationIfNeeded: requestAuthorizationIfNeeded && requestsReminderAuthorization,
            scope: ReminderSynchronizationScope(
                itemIDs: Set(requests.map(\.itemID)),
                captureSessionIDs: Set(requests.compactMap(\.captureSessionID)),
                replacesAllSpeakItReminders: true
            )
        )
    }

    private func findItem(withID id: UUID) throws -> CapturedItem? {
        var descriptor = FetchDescriptor<CapturedItem>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    /// The intent to give the occurrence generated when a recurring item is
    /// completed.
    ///
    /// A series is one request repeated, so every occurrence must carry the same
    /// meaning — above all the wall clock it was asked for. Leaving the generated
    /// item without an intent looks harmless, because the *first* completion
    /// still has the original item to read `preferredWallClock` from. It is not:
    /// from the second occurrence onward there is nothing to read, `nextDate`
    /// falls back to deriving each occurrence from the previous resolved
    /// instant, and a single daylight-saving nudge becomes the series' new time
    /// forever. "Every day at 2:30 AM" silently becomes "every day at 3:00 AM".
    ///
    /// Only `day` moves forward: it describes which occurrence this is, while
    /// the clock, zone, recurrence, provenance, and `isUserEdited` all describe
    /// the request itself and must not be re-derived.
    private func carriedIntent(
        from item: CapturedItem,
        toOccurrenceOn nextDate: Date
    ) -> TemporalIntent? {
        guard var intent = item.temporalIntent else { return nil }
        // The day is read in the intent's own calendar, so a series pinned to a
        // named zone ("every day at 9 AM Toronto time") keeps advancing by
        // Toronto days rather than by the travelling device's days.
        intent.day = CalendarDay(
            from: nextDate,
            calendar: intent.calendar(default: .autoupdatingCurrent)
        )
        return intent
    }

    private func nextRecurrenceDate(
        for item: CapturedItem,
        rule: RecurrenceRule,
        completedAt: Date
    ) -> Date? {
        // The clock the series was actually asked for, so a daylight-saving
        // nudge on one occurrence cannot become the new time for every
        // occurrence after it.
        let preferredWallClock = item.temporalKind == .calendarRecurrence
            ? item.temporalIntent?.time
            : nil

        var next = rule.nextDate(
            scheduledDate: item.dueDate ?? item.reminderDate,
            completedAt: completedAt,
            preferredWallClock: preferredWallClock
        )
        var attempts = 0
        while let value = next, value <= completedAt, attempts < 120 {
            next = rule.nextDate(
                scheduledDate: value,
                completedAt: completedAt,
                preferredWallClock: preferredWallClock
            )
            attempts += 1
        }
        return next
    }

    private func recentDuplicate(
        text: String,
        source: CaptureSource,
        createdAt: Date
    ) throws -> CaptureCreationResult? {
        let window: TimeInterval
        switch source {
        case .shortcut, .siri, .shareSheet:
            window = Self.externalCaptureDeduplicationWindow
        case .inAppText, .inAppVoice, .tutorial:
            window = Self.inAppCaptureDeduplicationWindow
        case .sample:
            return nil
        }

        let lowerBound = createdAt.addingTimeInterval(-window)
        let upperBound = createdAt.addingTimeInterval(0.5)
        let sourceRawValue = source.rawValue
        var descriptor = FetchDescriptor<CaptureSession>(
            predicate: #Predicate { session in
                session.createdAt >= lowerBound &&
                    session.createdAt <= upperBound &&
                    session.captureSourceRawValue == sourceRawValue
            },
            sortBy: [SortDescriptor(\CaptureSession.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = 8

        let fingerprint = text.captureFingerprint
        return try modelContext.fetch(descriptor).lazy.compactMap { session in
            guard session.originalTranscription.captureFingerprint == fingerprint else { return nil }
            let items = self.orderedItems(in: session)
            let operationOutcome: CaptureOperationOutcome? = {
                guard let state = CaptureOperationState.read(from: session.operationStateData) else { return nil }
                switch state.phase {
                case .performed:
                    if let targetID = state.targetID {
                        return .performed(operation: state.operation, itemID: targetID,
                                          title: state.targetTitle ?? state.targetWords ?? "Saved item")
                    }
                    return .performedMany(operation: state.operation,
                                          count: state.candidateIDs.count)
                case .pendingChoice:
                    return .ambiguous(operation: state.operation, candidateIDs: state.candidateIDs)
                case .dismissed:
                    return .ambiguous(operation: state.operation, candidateIDs: [])
                }
            }()
            guard !items.isEmpty || operationOutcome != nil else { return nil }
            return CaptureCreationResult(
                session: session,
                items: items,
                createdNewCapture: false,
                operationOutcome: operationOutcome
            )
        }.first
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }

    var captureFingerprint: String {
        folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .joined(separator: " ")
    }
}

/// Counts launches that began recovering a capture and never finished.
///
/// Launch recovery re-runs extraction over every capture that did not finish
/// organizing. A capture whose words trap the rules pipeline would therefore
/// crash the app at every launch, and the only way out was deleting it. Each
/// launch increments a capture's count *before* the risky work and clears it
/// *after*; a trap leaves the increment behind. Once a capture has cost
/// `maximumAttempts` launches it is quarantined: its durable fallback row
/// stays in Needs review and its words are never re-read at launch. A thrown
/// error is not a trap, so the caller clears the count on that path too.
///
/// Lives in `UserDefaults` rather than the store on purpose: a persistent model
/// change needs a schema version, and the ledger must survive a process that
/// dies mid-write.
enum CaptureRecoveryAttemptLedger {
    static let key = "SpeakIt.captureRecoveryAttempts"
    static let maximumAttempts = 2
    static let quarantineMessage =
        "Speak It couldn’t organize this capture. The words are kept exactly as they were said."

    /// Overridable so a test can run against a scratch suite.
    static var defaults: UserDefaults = .standard

    static func attempts(for id: UUID) -> Int {
        (defaults.dictionary(forKey: key) as? [String: Int])?[id.uuidString] ?? 0
    }

    /// Records that a launch is about to recover this capture and returns the
    /// number of launches, including this one, that have tried.
    @discardableResult
    static func begin(_ id: UUID) -> Int {
        var counts = (defaults.dictionary(forKey: key) as? [String: Int]) ?? [:]
        let next = min((counts[id.uuidString] ?? 0) + 1, maximumAttempts + 1)
        counts[id.uuidString] = next
        defaults.set(counts, forKey: key)
        return next
    }

    static func finish(_ id: UUID) {
        var counts = (defaults.dictionary(forKey: key) as? [String: Int]) ?? [:]
        guard counts.removeValue(forKey: id.uuidString) != nil else { return }
        if counts.isEmpty {
            defaults.removeObject(forKey: key)
        } else {
            defaults.set(counts, forKey: key)
        }
    }

    /// Marks a capture as one that must never be re-read at launch.
    static func quarantine(_ id: UUID) {
        var counts = (defaults.dictionary(forKey: key) as? [String: Int]) ?? [:]
        counts[id.uuidString] = maximumAttempts + 1
        defaults.set(counts, forKey: key)
    }

    static func reset() {
        defaults.removeObject(forKey: key)
    }
}
