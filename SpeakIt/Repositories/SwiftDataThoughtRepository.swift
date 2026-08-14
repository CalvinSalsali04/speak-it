import CoreLocation
import Foundation
import SwiftData
import WidgetKit

@MainActor
final class SwiftDataThoughtRepository: ThoughtRepository {
    private static let externalCaptureDeduplicationWindow: TimeInterval = 5

    private let modelContext: ModelContext
    private var isApplyingCloudSnapshot = false
    private var iCloudReconciliationTask: Task<Void, Never>?

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
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
        }
        polishPersistedDisplayTitles()
        backfillTemporalIntents()
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

    func recoverInterruptedCaptureDraft() {
        while let draft = CaptureDraftStore.recoverable() {
            do {
                _ = try createCapture(
                    text: draft.transcript,
                    source: draft.captureSource,
                    createdAt: draft.startedAt
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
        let requests = items
            .filter { !$0.isArchived && !$0.isCompleted }
            .compactMap(ReminderScheduleRequest.init(item:))

        ReminderScheduler.synchronize(
            requests,
            requestAuthorizationIfNeeded: false,
            scope: ReminderSynchronizationScope(
                itemIDs: Set(items.map(\.id)),
                captureSessionIDs: Set(items.compactMap { $0.captureSession?.id }),
                replacesAllSpeakItReminders: true
            )
        )
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
        let live = items.filter {
            !$0.isArchived && !$0.isCompleted
                && $0.isLocationTriggered && !$0.constrainsBothPlaceAndTime
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

    /// A monitored region was crossed. Delivers the reminder, and retires the
    /// trigger when it was a one-shot.
    ///
    /// "Next time I get to the gym" stops being monitored once it has fired;
    /// "every time I get to work" keeps its region. Retiring the one-shot here
    /// rather than waiting for the person to complete the item is what stops it
    /// firing again on the next arrival.
    func handleLocationTrigger(itemID: UUID, event: LocationEvent) async {
        // A combined place-and-time request is checked here as well as in
        // reconciliation, because a region left over from before the constraint
        // was recognised would otherwise still deliver at the wrong time.
        guard let item = try? findItem(withID: itemID),
              let intent = item.locationIntent,
              !item.isArchived, !item.isCompleted,
              !item.constrainsBothPlaceAndTime,
              intent.event == event else {
            // Nothing live wants this region. Reconciling removes it.
            LocationReminderMonitor.shared.stopMonitoring(itemID: itemID)
            return
        }

        await ReminderScheduler.deliverPlaceReminder(
            itemID: itemID,
            title: item.displayTitle,
            placeDescription: intent.displayDescription
        )

        if !intent.repeats {
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
        let local = makeICloudSnapshot()
        switch await ICloudSyncService.shared.download() {
        case .missing:
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
            let wasUpToDate = local.hasSameContent(as: cloud)
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
        let active = ((try? modelContext.fetch(descriptor)) ?? [])
            .filter(\.belongsInToday)
            .sorted(by: todayItemOrder)

        SharedTodayStore.save(
            SharedTodaySnapshot(
                generatedAt: .now,
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
        let items = try modelContext.fetch(FetchDescriptor<CapturedItem>()).filter {
            wanted.contains($0.id) && !$0.isArchived
        }

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
            synchronizeAllReminders(requestAuthorizationIfNeeded: false)
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
            synchronizeAllReminders(requestAuthorizationIfNeeded: false)
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

    @discardableResult
    func createCapture(
        text: String,
        source: CaptureSource,
        createdAt: Date,
        schedulesReminder: Bool
    ) throws -> CapturedItem {
        let normalizedText = try normalizedCaptureText(text)
        if let duplicate = try recentExternalDuplicate(
            text: normalizedText,
            source: source,
            createdAt: createdAt
        ) {
            return duplicate.primaryItem
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
        let items = organizePersistedCapture(
            session: pending.session,
            extraction: extraction,
            schedulesReminders: schedulesReminder
        )
        return items.first ?? pending.placeholder
    }

    func createCaptureResult(
        text: String,
        source: CaptureSource,
        createdAt: Date,
        schedulesReminders: Bool = true
    ) async throws -> CaptureCreationResult {
        let normalizedText = try normalizedCaptureText(text)
        if let duplicate = try recentExternalDuplicate(
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

        let extraction = await ThoughtExtractionEngine.extract(
            normalizedText,
            referenceDate: createdAt
        )
        let items = organizePersistedCapture(
            session: pending.session,
            extraction: extraction,
            schedulesReminders: schedulesReminders
        )
        let safeItems = items.isEmpty ? [pending.placeholder] : items
        return CaptureCreationResult(session: pending.session, items: safeItems)
    }

    func update(_ item: CapturedItem, with edits: ItemEdits) throws {
        let normalizedTitle = ThoughtTitleFormatter.polished(edits.title, itemType: edits.itemType)
        guard !normalizedTitle.isEmpty else { throw RepositoryError.emptyTitle }
        let previousRecurrences = RecurrenceStore.snapshots()

        item.displayTitle = normalizedTitle
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
            calendar: .autoupdatingCurrent
        )
        RecurrenceStore.set(edits.recurrenceRule, for: item.id)
        item.isReviewed = true
        item.lastModifiedAt = .now
        do {
            try persistChanges()
        } catch {
            RecurrenceStore.restore(previousRecurrences)
            throw error
        }
        synchronizeReminders(for: item.captureSession, requestAuthorizationIfNeeded: true)
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
            IdeaStageStore.removeMetadata(for: [deletedGeneratedItemID])
        }
        if completed { ReminderScheduler.cancel(itemID: item.id) }
        synchronizeReminders(for: item.captureSession, requestAuthorizationIfNeeded: true)
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
        synchronizeReminders(for: item.captureSession, requestAuthorizationIfNeeded: true)
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
        try persistChanges(
            deletedItemIDs: recurrenceIDs,
            deletedSessionIDs: deletesSession ? sessionID.map { [$0] } ?? [] : []
        )
        recurrenceIDs.forEach(RecurrenceStore.remove)
        MemoryPinStore.removeMetadata(for: recurrenceIDs)
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
        try persistChanges()
        return (session, placeholder)
    }

    @discardableResult
    private func organizePersistedCapture(
        session: CaptureSession,
        extraction: ThoughtExtractionResult,
        schedulesReminders: Bool
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
            IdeaStageStore.removeMetadata(for: extraIDs)
            if schedulesReminders {
                synchronizeReminders(for: session, requestAuthorizationIfNeeded: true)
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
        item.displayTitle = displayTitle(for: candidate)
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
        // A hand-set place outranks the sentence, exactly as a hand-set time
        // does. Reorganizing a capture must not revert it.
        if item.locationIntent?.isUserEdited != true {
            item.locationIntent = organization.locationIntent
        }
        RecurrenceStore.set(organization.recurrenceRule, for: item.id)
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
            displayTitle: displayTitle(for: candidate),
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
            captureSession: session
        )
        RecurrenceStore.set(organization.recurrenceRule, for: item.id)
        return item
    }

    private func displayTitle(for candidate: ExtractedThought) -> String {
        let rawTitle: String
        if let title = candidate.suggestedTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
           !title.isEmpty {
            rawTitle = title
        } else if candidate.organization.reminderDate != nil {
            rawTitle = ReminderCopy.action(from: candidate.analysisText)
        } else {
            rawTitle = candidate.sourceQuote
        }
        return ThoughtTitleFormatter.polished(
            rawTitle,
            itemType: candidate.organization.itemType
        )
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

    private func polishPersistedDisplayTitles() {
        guard let items = try? modelContext.fetch(FetchDescriptor<CapturedItem>()) else { return }
        var changed = false

        for item in items {
            let polished = ThoughtTitleFormatter.polished(
                item.displayTitle,
                itemType: item.itemType
            )
            guard !polished.isEmpty, polished != item.displayTitle else { continue }
            item.displayTitle = polished
            changed = true
        }

        if changed { try? persistChanges() }
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
            modelContext.rollback()
            throw RepositoryError.saveFailed(error.localizedDescription)
        }
    }

    private func makeICloudSnapshot() -> ICloudLibrarySnapshot {
        let sessions = (try? modelContext.fetch(FetchDescriptor<CaptureSession>())) ?? []
        let items = (try? modelContext.fetch(FetchDescriptor<CapturedItem>())) ?? []
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
            recurrenceRecords: RecurrenceStore.snapshots(),
            pinRecords: Array(MemoryPinStore.records().values),
            ideaStageRecords: Array(IdeaStageStore.records().values)
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
        requestAuthorizationIfNeeded: Bool
    ) {
        guard let session else { return }
        let requests = session.items
            .filter { !$0.isArchived && !$0.isCompleted }
            .compactMap(ReminderScheduleRequest.init(item:))
        ReminderScheduler.synchronize(
            requests,
            requestAuthorizationIfNeeded: requestAuthorizationIfNeeded,
            scope: ReminderSynchronizationScope(
                itemIDs: Set(session.items.map(\.id)),
                captureSessionIDs: [session.id]
            )
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
            requestAuthorizationIfNeeded: requestAuthorizationIfNeeded,
            scope: ReminderSynchronizationScope(
                itemIDs: Set(requests.map(\.itemID)),
                captureSessionIDs: Set(requests.compactMap(\.captureSessionID)),
                replacesAllSpeakItReminders: true
            )
        )
    }

    private func findItem(withID id: UUID) throws -> CapturedItem? {
        try modelContext.fetch(FetchDescriptor<CapturedItem>()).first { $0.id == id }
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

    private func recentExternalDuplicate(
        text: String,
        source: CaptureSource,
        createdAt: Date
    ) throws -> CaptureCreationResult? {
        guard source == .shortcut || source == .siri || source == .shareSheet else { return nil }

        let lowerBound = createdAt.addingTimeInterval(-Self.externalCaptureDeduplicationWindow)
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
            return CaptureCreationResult(session: session, items: items)
        }.first
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }

    var captureFingerprint: String {
        components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }
}
