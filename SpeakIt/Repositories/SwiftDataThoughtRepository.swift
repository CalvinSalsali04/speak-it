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
    private var isApplyingCloudSnapshot = false
    private var iCloudReconciliationTask: Task<Void, Never>?
    private var locationDeliveriesInFlight: Set<String> = []

    init(
        modelContext: ModelContext,
        placeReminderDelivery: PlaceReminderDelivery? = nil,
        placeReminderCancellation: PlaceReminderCancellation? = nil,
        requestsReminderAuthorization: Bool = true
    ) {
        self.modelContext = modelContext
        self.requestsReminderAuthorization = requestsReminderAuthorization
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
                let extraction = ThoughtExtractionEngine.extractWithRules(
                    session.originalTranscription,
                    referenceDate: session.createdAt
                )
                // A capture that asked to cancel, complete or withdraw must not
                // be rebuilt into an item by recovery. Re-reading the operation
                // is safe: the words have not changed, so the reading has not
                // either.
                var creating = extraction
                if let request = extraction.pendingOperation {
                    let outcome = applyCaptureOperation(request, session: session)
                    if case .notFound = outcome, !extraction.items.isEmpty {
                        creating = ThoughtExtractionEngine.extractWithRules(
                            session.originalTranscription,
                            referenceDate: session.createdAt,
                            permitsOperations: false
                        )
                    } else {
                        if case .notFound = outcome {
                            discardCaptureItems(for: session)
                        }
                        continue
                    }
                }
                ensureFallbackItem(for: session)
                _ = organizePersistedCapture(
                    session: session,
                    extraction: creating,
                    schedulesReminders: true
                )
            }
        }
        polishPersistedDisplayTitles()
        backfillTemporalIntents()
        resolveCombinedPlaceAndTimeHoldouts()
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
        for item in items where item.temporalIntent == nil {
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
            do {
                _ = try performSynchronousCapture(
                    text: draft.transcript,
                    source: draft.captureSource,
                    createdAt: draft.startedAt,
                    schedulesReminder: true
                )
                CaptureDraftStore.clear(id: draft.id)
            } catch {
                // Keep the checkpoint so a later launch can try again.
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
            )
        )
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
            !$0.isArchived && !$0.isCompleted
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
              !item.isArchived, !item.isCompleted,
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
              !current.isArchived, !current.isCompleted,
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
        let active = ((try? modelContext.fetch(descriptor)) ?? [])
            .filter { $0.belongsInToday && $0.isWithinTodayHorizon(relativeTo: now) }
            .sorted(by: todayItemOrder)

        SharedTodayStore.save(
            SharedTodaySnapshot(
                generatedAt: now,
                openCount: active.count,
                items: active.prefix(8).map {
                    SharedTodayItem(
                        id: $0.id,
                        title: $0.displayTitle,
                        dueDate: $0.dueDate,
                        isUrgent: $0.priority == .urgent
                    )
                },
                showsTaskNamesOnLockScreen: LockScreenTodayVisibility.showsTaskNames
            )
        )
        WidgetCenter.shared.reloadTimelines(ofKind: "SpeakItToday")
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
            return .created(duplicate.primaryItem)
        }

        let pending = try createPendingCapture(
            text: normalizedText,
            source: source,
            createdAt: createdAt
        )
        let extraction = ThoughtExtractionEngine.extractWithRules(
            normalizedText,
            referenceDate: createdAt
        )
        var creating = extraction
        if let request = extraction.pendingOperation {
            let outcome = applyCaptureOperation(request, session: pending.session)
            if case .notFound = outcome, !extraction.items.isEmpty {
                creating = ThoughtExtractionEngine.extractWithRules(
                    normalizedText,
                    referenceDate: createdAt,
                    permitsOperations: false
                )
            } else {
                if case .notFound = outcome {
                    discardCaptureItems(for: pending.session)
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
        performance: CapturePerformanceTrace? = nil
    ) async throws -> CaptureCreationResult {
        let normalizedText = try normalizedCaptureText(text)
        if let duplicate = try recentDuplicate(
            text: normalizedText,
            source: source,
            createdAt: createdAt
        ) {
            return duplicate
        }

        let pending = try createPendingCapture(
            text: normalizedText,
            source: source,
            createdAt: createdAt
        )

        performance?.beginSemanticParsing()
        let extraction = await CapturePerformanceContext.$stageRecorder.withValue(
            performance?.stageRecorder
        ) {
            await ThoughtExtractionEngine.extract(
                normalizedText,
                referenceDate: createdAt
            )
        }
        performance?.finishSemanticParsing()
        performance?.beginPersistence()

        // A cancellation, completion or retraction acts on what exists instead
        // of adding to it.
        var creating = extraction
        if let request = extraction.pendingOperation {
            let outcome = applyCaptureOperation(request, session: pending.session)
            if case .notFound = outcome, !extraction.items.isEmpty {
                // The operation matched nothing, but the same capture also
                // said things to create, and those must not go down with it.
                // A misread "cancel the cable" inside a four-errand capture
                // used to delete all four.
                //
                // Re-read the whole transcript rather than the remainder: the
                // operation clause was carved out of it, and in some captures
                // those words survive nowhere else — not in a title, not in a
                // quote. Reading them as something to create is the only way
                // they reach the person at all.
                creating = await ThoughtExtractionEngine.extract(
                    normalizedText,
                    referenceDate: createdAt,
                    permitsOperations: false
                )
            } else {
                // Nothing to create alongside it, so the conservative rule
                // stands: an operation that names nothing invents nothing.
                // See `testCancelWithNoMatchInventsNothing`.
                if case .notFound = outcome {
                    discardCaptureItems(for: pending.session)
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
        session: CaptureSession
    ) -> CaptureOperationOutcome {
        // A retraction withdraws the capture outright.
        if request.operation == .retract {
            discardCaptureItems(for: session)
            return .retracted
        }

        let existing = (try? modelContext.fetch(FetchDescriptor<CapturedItem>())) ?? []
        let searchable = existing.filter { $0.captureSession?.id != session.id }

        // Broad destructive requests are never executed, at any confidence.
        // The capture stays as a review row, which is where confirmation lives.
        if request.isBroad {
            let candidateIDs = CaptureTargetMatcher.activeItems(searchable).map(\.id)
            closeSession(session)
            // The review row itself is a generic placeholder (see
            // `beginCapture`), so what it would do if confirmed has nowhere
            // else to live. Recorded against it here so the editor can offer a
            // real confirm control instead of the dead-end "confirm in Needs
            // review" the receipt used to promise. See
            // Docs/FINAL_RELEASE_AUDIT.md F-1.
            if let placeholderID = session.items.first?.id {
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
            closeSession(session)
            return .ambiguous(
                operation: request.operation,
                candidateIDs: CaptureTargetMatcher.activeItems(searchable).map(\.id)
            )
        }

        let candidates = CaptureTargetMatcher.candidates(for: target, in: searchable)

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
            do {
                switch request.operation {
                case .cancel:
                    // `delete` already tears down notifications, recurrence and
                    // pin metadata; the place monitor is stopped explicitly
                    // because a region outlives the row that asked for it.
                    LocationReminderMonitor.shared.stopMonitoring(itemID: itemID)
                    try delete(item)
                case .complete:
                    try setCompleted(item, completed: true)
                    LocationReminderMonitor.shared.stopMonitoring(itemID: itemID)
                case .reschedule:
                    guard let timing = request.newTimingText,
                          let moved = rescheduledDates(timing, for: item) else {
                        // The move is real but the moment could not be read.
                        // The capture stays for review with the item attached,
                        // so the person picks the time instead of the app.
                        closeSession(session)
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
                case .create, .retract:
                    break
                }
            } catch {
                // The operation could not be applied, so the capture stays for
                // review rather than silently reporting success.
                closeSession(session)
                return .ambiguous(operation: request.operation, candidateIDs: [itemID])
            }
            discardCaptureItems(for: session)
            return .performed(operation: request.operation, itemID: itemID, title: title)

        default:
            closeSession(session)
            return .ambiguous(
                operation: request.operation,
                candidateIDs: candidates.map(\.id)
            )
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
        for item: CapturedItem
    ) -> (dueDate: Date?, reminderDate: Date?, hasTime: Bool)? {
        let anchor = item.reminderDate ?? item.dueDate

        if let offset = RescheduleOffset.parse(timing) {
            guard let anchor else { return nil }
            let moved = anchor.addingTimeInterval(offset)
            guard moved > .now else { return nil }
            return (
                item.dueDate != nil ? moved : nil,
                item.reminderDate != nil || item.dueDate == nil ? moved : nil,
                true
            )
        }

        let organized = ThoughtOrganizer.organize(
            "remind me \(timing)",
            referenceDate: .now,
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
        guard let record = PendingOperationStore.record(for: item.id) else { return }
        for candidateID in record.candidateIDs {
            guard let candidate = try findItem(withID: candidateID) else { continue }
            switch record.operation {
            case .cancel:
                LocationReminderMonitor.shared.stopMonitoring(itemID: candidateID)
                try delete(candidate)
            case .complete:
                try setCompleted(candidate, completed: true)
                LocationReminderMonitor.shared.stopMonitoring(itemID: candidateID)
            case .reschedule, .create, .retract:
                // A reschedule is never broad; nothing to confirm here.
                break
            }
        }
        PendingOperationStore.remove(item.id)
        try delete(item)
    }

    /// Declines a held broad cancel or complete. Nothing the request would
    /// have touched is changed; the review row is removed the same way
    /// confirming it removes the row, since a decline is also a resolution,
    /// not something left to keep asking about.
    func dismissPendingOperation(_ item: CapturedItem) throws {
        PendingOperationStore.remove(item.id)
        try delete(item)
    }

    /// Removes the rows a capture created and closes it.
    ///
    /// Closing matters as much as deleting: `recoverUnorganizedCaptures` rebuilds
    /// a fallback item for any session that is not `.complete`, so a retraction
    /// left open would reappear at the next launch.
    private func discardCaptureItems(for session: CaptureSession) {
        for item in session.items {
            RecurrenceStore.remove(item.id)
            LocationReminderMonitor.shared.stopMonitoring(itemID: item.id)
            modelContext.delete(item)
        }
        closeSession(session)
    }

    /// Marks a capture finished so launch recovery leaves it alone. The
    /// transcript itself is kept: the words are never what gets discarded.
    private func closeSession(_ session: CaptureSession) {
        session.processingStatus = .complete
        try? persistChanges()
    }

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
        let previousRecurrences = RecurrenceStore.snapshots()

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
        // An explicit edit outranks the sentence. The original wording stays in
        // `originalTextSegment` as provenance forever, but the intent is now
        // what the person set by hand, and `isUserEdited` stops any later
        // reparse from quietly reverting it.
        item.temporalIntent = TemporalIntent.userEdited(
            dueDate: edits.dueDate,
            reminderDate: edits.reminderDate,
            recurrence: edits.recurrenceRule,
            sourceText: item.temporalIntent?.sourceText ?? item.originalTextSegment,
            calendar: .autoupdatingCurrent,
            dueDateHasTime: edits.dueDateHasTime
        )
        RecurrenceStore.set(edits.recurrenceRule, for: item.id)

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
        if let personName = item.personName {
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
            reviewed: false
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
            itemType: candidate.organization.itemType
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

    private func makeICloudSnapshot() -> ICloudLibrarySnapshot {
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
                    lastModifiedAt: $0.items.map(\.lastModifiedAt).max() ?? $0.createdAt
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
                    recurrenceRule: RecurrenceStore.rule(for: item.id),
                    temporalIntent: item.temporalIntent
                )
            },
            deletionRecords: ICloudDeletionStore.records(),
            recurrenceRecords: RecurrenceStore.snapshots().filter {
                syncedItemIDs.contains($0.itemID)
            },
            pinRecords: MemoryPinStore.records().values.filter {
                syncedItemIDs.contains($0.itemID)
            },
            ideaStageRecords: IdeaStageStore.records().values.filter {
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
            if let temporalIntent = value.temporalIntent {
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
        ReminderScheduler.synchronize(
            requests,
            requestAuthorizationIfNeeded: requestAuthorizationIfNeeded && requestsReminderAuthorization,
            scope: ReminderSynchronizationScope(
                itemIDs: Set(session.items.map(\.id)),
                captureSessionIDs: [session.id]
            ),
            onCompletion: requests.isEmpty ? nil : { results in
                performance?.markNotificationSchedulingFinished(
                    accepted: results.contains(.scheduled)
                )
            }
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
            guard !items.isEmpty else { return nil }
            return CaptureCreationResult(
                session: session,
                items: items,
                createdNewCapture: false
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
