import CoreLocation
import Foundation
import os
import SwiftData
import WidgetKit

@MainActor
final class SwiftDataThoughtRepository: ThoughtRepository {
    /// Content-free diagnostics for reminder bookkeeping. Messages name a
    /// state, never an item's words, and nothing here reaches analytics.
    private static let reminderLog = Logger(subsystem: "com.calvinwak.SpeakIt", category: "Reminders")
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
    private var lastPublishedToday: SharedTodaySnapshot?
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

    /// Content-free diagnostics for the capture path. Messages name a state,
    /// never a transcript, and nothing here reaches analytics.
    private static let captureLog = Logger(subsystem: "com.calvinwak.SpeakIt", category: "Capture")

    func recoverUnorganizedCaptures() {
        let completeRawValue = ProcessingStatus.complete.rawValue
        let descriptor = FetchDescriptor<CaptureSession>(
            predicate: #Predicate { session in
                session.processingStatusRawValue != completeRawValue
            },
            sortBy: [SortDescriptor(\CaptureSession.createdAt, order: .forward)]
        )

        // A failed fetch is not "nothing to recover". Skipping recovery
        // removes nothing: every unfinished session keeps its words and its
        // placeholder row, and the next launch tries again. It is logged so
        // a predicate the store stopped translating does not hide there.
        let unfinished: [CaptureSession]?
        do {
            unfinished = try modelContext.fetch(descriptor)
        } catch {
            Self.captureLog.fault("Capture recovery could not fetch unfinished sessions")
            unfinished = nil
        }
        if let sessions = unfinished {
            for session in sessions {
                // An unfinished capture's rows are on screen before recovery
                // reaches them: a `.failed` row waits in Needs review, and an
                // interrupted placeholder is visible from the first frame
                // while audio drafts recover. Once the person has put a hand
                // on one of them, the rows are theirs. Re-reading the words
                // would write the organizer's answer over their edit, and
                // could delete the row or add others beside it, so the
                // session is closed as it stands instead. The transcript is
                // kept, and `Organize again` is still there to ask for it.
                if session.items.contains(where: { Self.carriesPersonsDecision($0) }) {
                    CaptureRecoveryAttemptLedger.finish(session.id)
                    closeSession(session)
                    continue
                }
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
        // A named place held beside a time is not released here any more.
        // Since 2026-09-23 (DEL-18) capture holds it on purpose, as it holds a
        // saved place beside a time, and a launch pass that re-armed its clock
        // would undo that on every start. The pass below asks about a stored
        // place-and-time row instead of releasing it. It runs after the
        // backfill, because the backfill can give an old row the time that
        // makes it one.
        holdUnaskedPlaceAndTimeRowsForReview()
    }

    /// Content-free diagnostics for launch maintenance. Messages name a
    /// state, never an item's words, and nothing here reaches analytics.
    private static let launchMaintenanceLog = Logger(
        subsystem: "com.calvinwak.SpeakIt",
        category: "LaunchMaintenance"
    )

    /// Puts into review a stored place-and-time row that the scheduler
    /// refuses and nothing asks about.
    ///
    /// `ReminderScheduleRequest` declines a row whose
    /// `awaitsPlaceOrTimeChoice` is true, so its clock does not fire, and a
    /// place beside a time is never monitored. Capture asks about every such
    /// row by holding it in review. Rows stored before that hold (DEL-11,
    /// DEL-18) carry `needsClarification == false`: they stay in Today while
    /// nothing is armed and nothing asks. This pass
    /// gives them the same question capture asks, and the editor's one save
    /// (`update`, which marks the row reviewed and the time as set by hand)
    /// answers it.
    ///
    /// Only the review flag and the modification date change. The words, the
    /// place, the dates and the recurrence stay as stored, so choosing the
    /// clock in the editor gives back exactly the reminder the row had.
    ///
    /// Selects exactly: not archived, not completed, not already in review,
    /// not reviewed, a place beside a time, and a time not set by hand
    /// (`isSelectedByUnaskedPlaceAndTimePass`). Idempotent, because a row it
    /// moves is then in review and is no longer selected. A failed fetch
    /// skips the pass until the next launch.
    private func holdUnaskedPlaceAndTimeRowsForReview() {
        let descriptor = FetchDescriptor<CapturedItem>(
            predicate: #Predicate { item in
                item.isArchived == false &&
                    item.completedAt == nil &&
                    item.needsClarification == false &&
                    item.isReviewed == false
            }
        )
        let candidates: [CapturedItem]
        do {
            candidates = try modelContext.fetch(descriptor)
        } catch {
            Self.launchMaintenanceLog.error(
                "Place-and-time review pass could not fetch rows; skipped until the next launch"
            )
            return
        }

        var changed = false
        for item in candidates where Self.isSelectedByUnaskedPlaceAndTimePass(item) {
            item.needsClarification = true
            item.lastModifiedAt = .now
            changed = true
        }
        guard changed else { return }
        do {
            try persistChanges()
        } catch {
            // `persistChanges` rolls the context back, so the rows stay as
            // stored, still refused by the scheduler, and the next launch
            // selects them again.
            Self.launchMaintenanceLog.error(
                "Place-and-time review pass could not save; retried at the next launch"
            )
        }
    }

    /// The whole selection rule of `holdUnaskedPlaceAndTimeRowsForReview`,
    /// including the part its fetch predicate already applies, so a test can
    /// read the rule without a store.
    static func isSelectedByUnaskedPlaceAndTimePass(_ item: CapturedItem) -> Bool {
        !item.isArchived
            && !item.isCompleted
            && !item.needsClarification
            && item.awaitsPlaceOrTimeChoice
    }

    /// Whether a row holds something only the person could have put there.
    ///
    /// Every hand on a row leaves one of these marks: `update` and
    /// `markReviewed` set `isReviewed` (and an edit also stamps `isUserEdited`
    /// on the intents it wrote), `setCompleted` sets `completedAt`, and
    /// `setArchived` sets `isArchived`. No automatic path sets any of them on
    /// a session that is still unfinished: a spoken operation from another
    /// capture could, through `setCompleted` or `update`, so it holds for
    /// review instead (see `awaitsOrganization`). `lastModifiedAt` is
    /// deliberately not used: the organizer and the fallback row stamp it too.
    private static func carriesPersonsDecision(_ item: CapturedItem) -> Bool {
        item.isReviewed
            || item.isCompleted
            || item.isArchived
            || item.temporalIntent?.isUserEdited == true
            || item.locationIntent?.isUserEdited == true
    }

    /// Whether a row belongs to a capture launch recovery has yet to organize.
    /// Such a row is the durable placeholder (or an organized row of a save
    /// that failed), and recovery may still replace it. A single-target
    /// operation holds on it; a broad one leaves it out of what it names (see
    /// `broadOperationCandidates`).
    private static func awaitsOrganization(_ item: CapturedItem) -> Bool {
        guard let session = item.captureSession else { return false }
        return session.processingStatus != .complete
    }

    private func recoverOrganization(of session: CaptureSession) {
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

    /// Gives a row with no stored intent the temporal intent it was never able
    /// to store: a row written before schema version 2.
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
    ///
    /// `temporalIntent` is nil for two different rows: one with no intent data,
    /// and one whose data is there but will not decode. Only the first is
    /// backfilled. Data that will not decode may be a shape a newer build
    /// wrote, and replacing it would destroy it for good, so it is kept as it
    /// is and reported, the way a snooze reports `unreadableIntent`. The
    /// intent is written with `backfillTemporalIntentKeepingTrigger`, never
    /// through the setter, so a row's trigger is not re-derived: a place
    /// reminder stays one. The setter was safe here too, but only because the
    /// trigger column arrived a schema version after the intent, so a row
    /// with no intent data had no trigger to flip. This makes it hold by
    /// construction.
    private func backfillTemporalIntents() {
        guard let items = try? modelContext.fetch(FetchDescriptor<CapturedItem>()) else { return }
        var changed = false
        var unreadable = 0
        var unencodable = 0

        // Only rows with no readable intent. A user-edited one is never
        // revisited, and neither is one already reconstructed.
        for item in items where item.temporalIntent == nil {
            guard item.temporalIntentData == nil else {
                unreadable += 1
                continue
            }
            if item.backfillTemporalIntentKeepingTrigger(reconstructedIntent(for: item)) {
                changed = true
            } else {
                unencodable += 1
            }
        }
        if unreadable > 0 || unencodable > 0 {
            Self.reminderLog.fault(
                "Launch backfill left rows without an intent: unreadable \(unreadable, privacy: .public), unencodable \(unencodable, privacy: .public)"
            )
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
        // A checkpoint whose words already reached a committed session is not
        // interrupted; replaying it is how one thought became two. Releasing
        // here protects this text pass whoever calls it. It does nothing for
        // the audio pass, which runs earlier and re-transcribes any draft with
        // a recording: that pass is protected only by `RootView` calling
        // `releaseHandedOffCaptureDrafts()` before
        // `recoverInterruptedAudioDrafts()`, so that ordering is load-bearing
        // and this call does not make it redundant.
        releaseHandedOffCaptureDrafts()
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

    /// Releases every draft whose words provably reached the store.
    ///
    /// A save of a draft's words records the session ID on the draft before
    /// it commits that session, and clears the draft only after persistence
    /// returns (`CaptureView.save`, the two audio recoveries, and
    /// `CaptureDraftStore.handOff` for Today's typed recovery and the Save
    /// Thought intent's writer). A kill between the two used to leave both behind, and
    /// launch recovery replayed the draft into a second session: always for a
    /// practice capture, whose session is `.tutorial` while its draft is not,
    /// and for a voice capture whenever re-transcribing the recording came out
    /// in different words. A committed session is finished by
    /// `recoverUnorganizedCaptures`, so the draft has nothing left to protect.
    ///
    /// Proof is the session itself, read from the store. A handoff whose
    /// session is not found is left exactly as it was and replayed, because a
    /// duplicate is recoverable and a lost thought is not. There are three ways
    /// not to find it: killed before the commit, the commit failed, or the
    /// lookup itself threw. The `try?` folds the third into the first two on
    /// purpose, so it conflates "the store failed" with "no such session" in
    /// the direction that keeps the words. Whatever replaces the `try?` must
    /// never treat a failed read as proof of a commit.
    ///
    /// The recording is deleted only on the release path, which is the same
    /// point a normal save deletes it: after the words are durable.
    func releaseHandedOffCaptureDrafts() {
        for draft in CaptureDraftStore.handedOffDrafts() {
            guard let sessionID = draft.handedOffSessionID,
                  (try? committedSession(id: sessionID)) != nil else { continue }
            CaptureDraftStore.clear(id: draft.id)
        }
    }

    private func committedSession(id: UUID) throws -> CaptureSession? {
        var descriptor = FetchDescriptor<CaptureSession>(
            predicate: #Predicate { session in session.id == id }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    func reconcilePendingReminders() {
        guard let items = try? modelContext.fetch(FetchDescriptor<CapturedItem>()) else { return }
        let now = Date.now
        // DEL-23: a row whose alarm may be ringing now keeps it through this
        // pass, neither stopped nor re-armed. Read before the rows are rolled
        // forward, which erases the ring from them. Completed, archived, held
        // and disarmed rows are never in this set, so their alarms still go.
        let alarmsMayBeAlerting = Set(
            items.filter { ReminderScheduler.alarmMayBeAlerting($0, now: now) }.map(\.id)
        )
        advanceOverdueRecurrences(items: items, now: now)
        guard let refreshedItems = try? modelContext.fetch(FetchDescriptor<CapturedItem>()) else { return }
        let requests = refreshedItems
            .filter { !$0.isArchived && !$0.isCompleted }
            .compactMap { ReminderScheduleRequest.forScheduling($0) }

        ReminderScheduler.synchronize(
            requests,
            requestAuthorizationIfNeeded: false,
            scope: ReminderSynchronizationScope(
                itemIDs: Set(refreshedItems.map(\.id)),
                captureSessionIDs: Set(refreshedItems.compactMap { $0.captureSession?.id }),
                replacesAllSpeakItReminders: true,
                alarmsLeftAlone: alarmsMayBeAlerting
            )
        )
        // The pass above reaches an alarm only through a row it can name, so an
        // alarm whose row is already gone (removed by iCloud, or by a kill
        // between `delete`'s save and its teardown) would still ring. Every
        // row that still exists protects its alarm here; whether that row
        // should ring is the pass above's decision, not this sweep's.
        ReminderScheduler.cancelOrphanedAlarms(accountedFor: { [weak self] in
            self?.itemIDsAccountingForAlarms()
        })
    }

    /// Every item ID in the store, or `nil` when the store cannot be read, which
    /// the orphan sweep treats as "cancel nothing".
    private func itemIDsAccountingForAlarms() -> Set<UUID>? {
        guard let items = try? modelContext.fetch(FetchDescriptor<CapturedItem>()) else {
            return nil
        }
        return Set(items.map(\.id))
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

            let reminderOffset = seriesReminderOffset(of: item)

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
            // repeating trigger is re-armed on the same run. A row held for
            // review is rolled too: it stays the one held row, still held, and
            // what it proposes stays the next occurrence rather than a day
            // that has already gone.
            if ReminderScheduleRequest.repeatingComponents(rule: rule, fireDate: fireDate) != nil {
                let carried = carriedIntent(from: item, toOccurrenceOn: nextDate)
                // Only move a due date the row already had. Giving one to a
                // reminder-only row would move it out of "When you have time"
                // and into "Coming up", quietly changing what kind of thing it
                // is on a pass whose whole job is to keep it firing.
                if item.dueDate != nil { item.dueDate = nextDate }
                item.reminderDate = nextDate.addingTimeInterval(reminderOffset)
                // `carried` is nil when the row's intent bytes will not
                // decode, and writing that through the setter erased the
                // bytes the launch backfill had just kept, on every relaunch
                // after the occurrence fired. Nothing readable means nothing
                // to move forward, so the bytes stay.
                item.carryTemporalIntent(carried)
                item.lastModifiedAt = now
                advancedAny = true
                continue
            }

            // No successor is generated while the system holds the source for
            // review (`ItemPresentation.mayArmTime`). A successor is a copy of an
            // unconfirmed reading: generated un-held, it carried "except this
            // Friday" out of review as a clean armed row in Today; generated
            // held, it would add one more review row asking the same question
            // on every foreground after every missed occurrence, because a
            // held row never fires and so is always overdue. The source stays
            // the one place the question is asked, and once the person
            // resolves it the next pass continues the series from it.
            guard ItemPresentation.mayArmTime(item) else { continue }

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
                // `true` only for a hold the person set themselves; see
                // `setCompleted`.
                needsClarification: item.needsClarification,
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
    ///
    /// Runs synchronously on the main actor, on every foreground and after
    /// every mutation that touches a place, including an in-app capture, where
    /// the receipt needs the answer before it is shown. So the fetch is scoped
    /// in the store to live rows that carry a place, rather than materialising
    /// every item to filter here.
    ///
    /// Scoped on `locationIntentData`, not on `reminderTriggerKindRawValue`,
    /// although the second exists to save decoding a blob. It is not an exact
    /// mirror of "has a place": the `temporalIntent` setter writes `time` over
    /// `location` whenever a timed intent is stored after the place, and
    /// clears the column when a later untimed one replaces it, and a store
    /// written by an earlier build can hold a live place reminder whose column
    /// reads `time` or nothing. (A place set by hand, then a date moved by
    /// voice, then a reorganize with no time used to produce one in the app;
    /// the reorganize now keeps a time set by hand, so that sequence ends on a
    /// combined row instead.) A predicate on that column would never plan such
    /// a row (`testALivePlaceWithNoTriggerKindIsStillPlanned`). The blob column is
    /// the definition: the `locationIntent` setter writes it exactly when a
    /// place is stored.
    @discardableResult
    func reconcileLocationReminders() -> LocationMonitorReconciliation {
        let descriptor = FetchDescriptor<CapturedItem>(
            predicate: #Predicate { item in
                item.locationIntentData != nil &&
                    item.isArchived == false &&
                    item.completedAt == nil
            }
        )
        // A predicate the store cannot translate fails here, at fetch time,
        // not at compile time. Swallowed, it would leave every place reminder
        // unplanned on every path without a trace, so it is logged.
        let items: [CapturedItem]
        do {
            items = try modelContext.fetch(descriptor)
        } catch {
            Self.reminderLog.fault("Place reminder reconcile could not fetch its rows")
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
        // A row the system holds for review is excluded the same way: it is
        // not a live reminder yet, so it is neither watched nor reported
        // blocked (`hasLivePlaceTrigger`, which reads `ItemPresentation.mayArmPlace`).
        let live = items.filter {
            $0.hasLivePlaceTrigger && $0.locationIntent?.isRetired != true
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

    /// Re-plans the region budget after a mutation that touched a place
    /// reminder, rather than waiting for the next foreground.
    ///
    /// The budget is shared, so one item's change moves another's answer:
    /// completing, archiving, deleting or dating a watched place reminder frees
    /// a slot the 19th is waiting for, and capturing one can take the last
    /// slot. Only a reconcile turns that into a region and into what the rows
    /// show (`LocationReminderMonitor.unwatchedRegions`). These paths used to
    /// stop the one region or nothing at all, which left the waiting reminder
    /// shown as blocked while a slot sat free, or a new one shown as armed with
    /// no region, until the app next came to the foreground.
    ///
    /// Callers pass whether a place reminder was involved, read *before* the
    /// mutation where the mutation removes the item, so an edit to a plain task
    /// does not pay for a fetch of every item.
    private func reconcileLocationReminders(ifTouchingPlaces touchesPlaces: Bool) {
        guard touchesPlaces else { return }
        reconcileLocationReminders()
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
        // A row held for review is refused here too (`hasLivePlaceTrigger`),
        // because a region registered before the hold was recognised, or
        // before this build, would otherwise still deliver it.
        guard let item = try? findItem(withID: itemID),
              let intent = item.locationIntent,
              item.hasLivePlaceTrigger else {
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
              current.hasLivePlaceTrigger,
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
            // The retired region was a slot. Hand it to whichever reminder the
            // budget had turned away.
            reconcileLocationReminders()
        }
    }

    func reconcileSharedTodayActions() {
        reconcileSharedTodayActions(
            authorization: LocationReminderMonitor.shared.authorization,
            now: .now
        )
    }

    /// Applies the widget's queued taps, except a completion of a row Today
    /// now holds for review.
    ///
    /// The widget draws from a file written the last time the app ran. A
    /// permission revoked in Settings while the app was closed reaches no
    /// delegate and republishes nothing, so the file can still offer a row
    /// Today would now hold, and a tap on it is queued here. Applying it would
    /// complete the row the person is about to be asked about, through the
    /// widget rather than the shortcut. So the queued tap is dropped and the
    /// row waits in Needs review. Dropping loses a tap the person made;
    /// keeping it would re-apply forever or complete a held row, and the
    /// person can still finish it from Needs review in one tap. A dropped tap
    /// is not an outcome either, so the morning brief does not count it as
    /// something finished away from the app.
    ///
    /// `actionsIn` names the queue's folder for a test; `nil` is the app
    /// group's, which is what every caller in the app uses.
    func reconcileSharedTodayActions(
        authorization: LocationAuthorization,
        now: Date,
        actionsIn directory: URL? = nil
    ) {
        let pendingActions = directory.map { SharedTodayStore.pendingActions(in: $0) }
            ?? SharedTodayStore.pendingActions()
        for pending in pendingActions {
            do {
                switch pending.action.kind {
                case .complete:
                    if let item = try findItem(withID: pending.action.itemID),
                       item.requiresReview(authorization: authorization) {
                        SharedTodayStore.removeAction(at: pending.url)
                        // `continue` moves on to the next queued tap. The
                        // `break` in the catch below is not its twin: it sits
                        // outside the `switch`, so as an unlabeled `break` it
                        // leaves the whole loop (inside the `switch` it would
                        // only end the `switch`). The model store failing to
                        // answer a read or a write stops the drain, and every
                        // remaining tap is retried at the next one.
                        continue
                    }
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
            guard let local = readICloudSnapshot() else { return Self.unreadableLibrary }
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
            guard let local = readICloudSnapshot() else { return Self.unreadableLibrary }
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
        let now = Date.now
        guard let snapshot = makeSharedTodaySnapshot(
            authorization: LocationReminderMonitor.shared.authorization,
            now: now
        ) else { return }
        if let previous = lastPublishedToday,
           previous.openCount == snapshot.openCount, previous.items == snapshot.items,
           previous.showsTaskNamesOnLockScreen == snapshot.showsTaskNamesOnLockScreen,
           now.timeIntervalSince(previous.generatedAt) < 60 { return }
        if SharedTodayStore.save(snapshot) {
            lastPublishedToday = snapshot
            WidgetCenter.shared.reloadTimelines(ofKind: "SpeakItToday")
        }
    }

    /// What the widget, the Lock Screen summary and "Complete my next item"
    /// are allowed to see, judged against one authorization answer.
    ///
    /// Membership is `belongsOnTodaySurface(authorization:relativeTo:)`, the
    /// predicate Today itself partitions on, and nothing restated beside it.
    /// This used to read the stored `belongsInToday` with a stored
    /// `needsClarification == false` prefilter, which knows what the sentence
    /// left open but not what the device lacks: a place reminder with location
    /// permission denied sat in Today's Needs review while the widget counted
    /// it, offered it a complete button, and let the App Shortcut complete it
    /// as the next item. A row held for review is neither counted nor offered.
    ///
    /// Takes the authorization rather than reading it so a test can pin the
    /// device state; `publishSharedTodaySnapshot()` passes the live one, as
    /// every other non-UI caller of `LocationReminderMonitor` does.
    func makeSharedTodaySnapshot(
        authorization: LocationAuthorization,
        now: Date
    ) -> SharedTodaySnapshot? {
        // The store narrows to live items; the model decides membership.
        // Restating that rule as a `#Predicate` would both exceed the
        // type-checker's budget and risk drifting from the model.
        let descriptor = FetchDescriptor<CapturedItem>(
            predicate: #Predicate { item in
                item.isArchived == false && item.completedAt == nil
            }
        )
        // On a failed fetch there is no snapshot, never an empty one made from
        // a store that could not be read. What `nil` means is the caller's:
        // publishing keeps the widget's last snapshot, and "Complete my next
        // item" reports the store unavailable, so the log names only the cause.
        let candidates: [CapturedItem]
        do {
            candidates = try modelContext.fetch(descriptor)
        } catch {
            Self.reminderLog.fault("Today snapshot could not fetch its rows")
            return nil
        }
        var count = 0
        var first: [CapturedItem] = []
        for item in candidates
        where item.belongsOnTodaySurface(authorization: authorization, relativeTo: now) {
            count += 1
            let insertion = first.firstIndex { todayItemOrder(item, $0) } ?? first.count
            if insertion < 8 {
                first.insert(item, at: insertion)
                if first.count > 8 { first.removeLast() }
            }
        }
        return SharedTodaySnapshot(
            generatedAt: now,
            openCount: count,
            items: first.map {
                SharedTodayItem(id: $0.id, title: $0.displayTitle, dueDate: $0.dueDate,
                                isUrgent: $0.priority == .urgent)
            },
            showsTaskNamesOnLockScreen: LockScreenTodayVisibility.showsTaskNames
        )
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
                // A snooze moves this occurrence, never the series. Before the
                // alert is displaced, a recurring item records where its series
                // put it, and a second snooze keeps that first record rather
                // than taking the already-snoozed time as the series' own.
                if RecurrenceStore.rule(for: item.id) != nil,
                   let seriesReminder = item.seriesReminderDate {
                    recordSnoozeDisplacement(of: item, from: seriesReminder)
                }
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
                let recurs = RecurrenceStore.rule(for: item.id) != nil
                // A recurring occurrence moves to tomorrow at its series' own
                // alert, not at a snoozed one: "every day at 8", snoozed and
                // then sent to tomorrow, is due tomorrow at 8, not 8:10.
                let ownReminder = recurs ? item.seriesReminderDate : item.reminderDate
                let sourceDate = ownReminder ?? item.dueDate
                let hour = sourceDate.map { calendar.component(.hour, from: $0) } ?? 9
                let minute = sourceDate.map { calendar.component(.minute, from: $0) } ?? 0
                let date = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
                item.reminderDate = date
                if let dueDate = item.dueDate {
                    if recurs, let ownReminder {
                        // Keep the series' distance between alert and due
                        // date, so the occurrence after this one is carried
                        // forward from the clock the series repeats at.
                        item.dueDate = date.addingTimeInterval(dueDate.timeIntervalSince(ownReminder))
                    } else {
                        item.dueDate = date
                    }
                }
                // The occurrence now sits on its series' own alert again, so
                // there is no displacement left to remember.
                if recurs { item.setSnoozedFromReminderDate(nil) }
                item.lastModifiedAt = .now
            }
            try persistChanges()
            rescheduleReminders(touching: items)
        }
    }

    /// Records the series alert a snooze is about to displace, and refuses to
    /// fail quietly.
    ///
    /// The snooze decides to record from `RecurrenceStore`, which lives in
    /// UserDefaults, while the record lives in the row's intent blob. A
    /// recurring row with no intent is one the launch backfill has not reached
    /// yet. It gets the backfill's own reconstruction here, so the record has
    /// somewhere to go and the next occurrence is computed from the series
    /// rather than from the snoozed time. Any other failure is logged, with
    /// the reason only, and stops a Debug build, except `unreadableIntent`:
    /// the launch backfill keeps undecodable data on purpose, so a row in
    /// that state is one the app chose to leave, and a Debug trap on the
    /// person's snooze of it would be hostile. It is logged the same way.
    private func recordSnoozeDisplacement(of item: CapturedItem, from seriesReminder: Date) {
        var outcome = item.setSnoozedFromReminderDate(seriesReminder)
        if outcome == .noIntent {
            // Not through the `temporalIntent` setter, which would turn a
            // recurring place reminder into a clock reminder.
            item.backfillTemporalIntentKeepingTrigger(reconstructedIntent(for: item))
            outcome = item.setSnoozedFromReminderDate(seriesReminder)
        }
        guard !outcome.isWritten else { return }
        Self.reminderLog.fault(
            "Recurring snooze recorded no series alert: \(outcome.rawValue, privacy: .public)"
        )
        guard outcome != .unreadableIntent else { return }
        assertionFailure("Recurring snooze recorded no series alert: \(outcome.rawValue)")
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
        let touchesPlaces = sessions.flatMap(\.items).contains { $0.locationIntent != nil }
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
        reconcileLocationReminders(ifTouchingPlaces: touchesPlaces)
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
            let retained = extraction.items.isEmpty ? [] : organizePersistedCapture(
                session: pending.session,
                extraction: extraction,
                schedulesReminders: schedulesReminder
            )
            guard extraction.items.isEmpty || pending.session.processingStatus == .complete else {
                return .created(retained.first ?? pending.placeholder)
            }
            let outcome = applyCaptureOperation(
                request, session: pending.session, preservingItemIDs: Set(retained.map(\.id))
            )
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
        try await createCaptureResult(
            text: text,
            source: source,
            createdAt: createdAt,
            schedulesReminders: schedulesReminders,
            performance: performance,
            sessionID: UUID()
        )
    }

    func createCaptureResult(
        text: String,
        source: CaptureSource,
        createdAt: Date,
        schedulesReminders: Bool,
        performance: CapturePerformanceTrace?,
        sessionID: UUID
    ) async throws -> CaptureCreationResult {
        let normalizedText = try normalizedCaptureText(text)
        // `id` is unique, and SwiftData treats inserting a second model with a
        // unique value as an update. Reusing a handed-off ID must therefore
        // return what is there rather than overwrite its original words.
        if let committed = try committedSession(id: sessionID) {
            return CaptureCreationResult(
                session: committed,
                items: orderedItems(in: committed),
                createdNewCapture: false
            )
        }
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
            createdAt: createdAt,
            id: sessionID
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

        // Commit the independent creations before acting on an existing row.
        // A failed organization must never leave the operation performed but
        // the new thoughts unsaved. A retry sees the durable capture via dedup.
        var creating = extraction
        if let request = extraction.pendingOperation {
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
            let outcome = applyCaptureOperation(
                request, session: pending.session, preservingItemIDs: Set(retained.map(\.id))
            )
            if case .notFound = outcome, !extraction.items.isEmpty {
                // An unmatched cancellation can itself be an errand. Preserve
                // the established full-transcript fallback in that case.
                creating = await ThoughtExtractionEngine.extract(
                    normalizedText, referenceDate: createdAt, permitsOperations: false
                )
            } else {
                if case .notFound = outcome { discardCaptureItems(for: pending.session) }
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
        preservingItemIDs: Set<UUID> = []
    ) -> CaptureOperationOutcome {
        // A retraction withdraws the capture outright, unless it has to ask
        // first. The detector never marks one that way; the degraded language
        // policy marks every operation that way, because whether a "never
        // mind" is the speaker's or sits inside a message is read by the
        // tagger it could not use. Held, the capture keeps its words in Needs
        // review instead of being discarded on that reading.
        if request.operation == .retract {
            guard !request.needsReview else {
                holdOperation(request, in: session, preserving: preservingItemIDs)
                return .ambiguous(operation: .retract, candidateIDs: [])
            }
            discardCaptureItems(for: session, preserving: preservingItemIDs)
            return .retracted
        }

        // A failed fetch is not "nothing matches". Read as empty, it would
        // reach `.notFound`, and the caller would file "cancel my dentist" as
        // a new task while the dentist reminder stayed armed. Held for review
        // instead, the way an operation that could not be applied is held.
        let existing: [CapturedItem]
        do {
            existing = try modelContext.fetch(FetchDescriptor<CapturedItem>())
        } catch {
            Self.captureLog.fault("A spoken operation could not read the store; held for review")
            holdOperation(request, in: session, preserving: preservingItemIDs)
            return .ambiguous(operation: request.operation, candidateIDs: [])
        }
        let searchable = existing.filter { $0.captureSession?.id != session.id }

        // Broad destructive requests are never executed, at any confidence.
        // The capture stays as a review row, which is where confirmation lives.
        if request.isBroad {
            let candidateIDs = Self.broadOperationCandidates(in: searchable).map(\.id)
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

        // A pronoun target names nothing. Ask rather than guess. A request
        // that needs review for any other reason (a reschedule with no new
        // moment, every operation read while the tagger was blind) is held
        // here too, before any candidate is touched.
        guard let target = request.target, !target.isEmpty, !request.needsReview else {
            holdOperation(request, in: session, preserving: preservingItemIDs)
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
            // A row of a capture that was never organized is a placeholder,
            // not a commitment: its segment is the whole transcript, so "move
            // the plumber to Friday" matches "Call the plumber and book the
            // car service". Acting on it would stamp the marks that launch
            // recovery reads as the person's hand (and a cancel would delete
            // the whole capture with its transcript), so the other thought
            // would never be organized. It is held for the person instead.
            // Not dropped from the search: as the only match, dropping it
            // would report nothing found and drop the request, and beside
            // another match it would make that one look certain.
            guard !Self.awaitsOrganization(item) else {
                holdOperation(request, in: session, preserving: preservingItemIDs)
                return .ambiguous(operation: request.operation, candidateIDs: [itemID])
            }
            // The search refuses rows in Memory (`belongsInMemory`), and a
            // knowledge row held in Needs review is not in Memory: the `.unclear`
            // safety row for reported speech, a note waiting on a question. As
            // the one match it used to be deleted, and `delete` takes the
            // capture's transcript with its last row. Only an action row is
            // acted on without the person (DEL-26). Held rather than dropped,
            // for the reason given above: dropping it would report nothing
            // found and file the sentence as a new errand.
            guard item.isActionKind else {
                holdOperation(request, in: session, preserving: preservingItemIDs)
                return .ambiguous(operation: request.operation, candidateIDs: [itemID])
            }
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
                case .create, .retract:
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
            // Read one at a time, as each earlier delete may have taken a row.
            guard let candidate = try heldCandidate(candidateID) else { continue }
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

    func pendingOperationCandidateIDs(for item: CapturedItem) -> [UUID] {
        guard let record = PendingOperationStore.record(for: item.id) else { return [] }
        return ((try? heldCandidates(of: record)) ?? []).map(\.id)
    }

    /// What a broad request may act on: every active row on Today's action
    /// side, except those of a capture launch recovery has yet to organize.
    ///
    /// Nothing in Memory. "Cancel all my reminders" and "delete all my tasks"
    /// are about commitments. The list used to be every active row, so
    /// confirming one deleted Memory's notes, ideas and people facts with the
    /// tasks, and a capture's transcript went with its last row. The
    /// single-target search (`CaptureTargetMatcher.candidates`) refuses only
    /// rows that are in Memory now (`belongsInMemory`). This line is drawn by
    /// kind instead, so it is the stricter of the two: a knowledge row waiting
    /// in Needs review is in neither destination, and it is left out here.
    /// That exclusion is this path's alone; it says nothing about what a
    /// single-target cancel can reach. The parser keeps no noun for a broad
    /// request (`target` is nil, so "reminders", "tasks" and "notes" all read
    /// the same), and nothing narrower than the action side can be read from
    /// it.
    ///
    /// Nothing unorganized. Such a row is a placeholder whose capture still
    /// holds words nobody has organized, and `delete` removes a capture with
    /// its last row, so a confirmed "cancel all my reminders" used to delete
    /// the unfinished capture and its transcript; a confirmed complete stamped
    /// the mark that makes recovery close it unorganized. Unlike the
    /// single-target search, dropping the row here makes nothing else look
    /// certain: a broad request is always held, and nothing it names is
    /// touched until the person confirms a count that now leaves the row out.
    ///
    /// `heldCandidate` asks both questions again at confirmation.
    private static func broadOperationCandidates(in items: [CapturedItem]) -> [CapturedItem] {
        CaptureTargetMatcher.activeItems(items).filter { $0.isActionKind && !awaitsOrganization($0) }
    }

    /// The rows a held broad request still names, read again at confirmation.
    ///
    /// The list was fixed when the request was held, and a row can stop
    /// qualifying after that: `Organize again` leaves a session `.failed` when
    /// its save fails, an edit can turn a task into a note, and a record
    /// written before candidates excluded unorganized captures or Memory rows
    /// may still name one. The prompt's count and the confirmation both read
    /// this, so the number the person confirms is the number acted on. Rows
    /// deleted since are skipped, as before.
    private func heldCandidates(
        of record: PendingOperationStore.StoredPendingOperation
    ) throws -> [CapturedItem] {
        try record.candidateIDs.compactMap { try heldCandidate($0) }
    }

    private func heldCandidate(_ id: UUID) throws -> CapturedItem? {
        guard let item = try findItem(withID: id),
              item.isActionKind,
              !Self.awaitsOrganization(item) else { return nil }
        return item
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
    private func discardCaptureItems(for session: CaptureSession, preserving itemIDs: Set<UUID> = []) {
        var discardedIDs: [UUID] = []
        for item in session.items where !itemIDs.contains(item.id) {
            discardedIDs.append(item.id)
            RecurrenceStore.remove(item.id)
            LocationReminderMonitor.shared.stopMonitoring(itemID: item.id)
            modelContext.delete(item)
        }
        closeSession(session)
        // No scheduling pass follows a discard, so nothing else would stop
        // delivery for these rows.
        discardedIDs.forEach(ReminderScheduler.cancel(itemID:))
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
        // A row the system held for review arms nothing (`ItemPresentation`'s
        // `mayArmTime` and `mayArmPlace`). Saving here is the person resolving
        // or confirming it, so whatever it now may arm has to be armed by this
        // save, not by the next launch.
        let placeCouldArmBefore = ItemPresentation.mayArmPlace(item)

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
            // Not a confirmation. The editor sends a place it showed back as
            // `.update`, which marks it; `.unchanged` comes from callers that
            // never showed the place, such as the voice reschedule, and
            // marking it there would exempt a combined place-and-time row from
            // the launch pass that resolves it, for good.
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
        // notified at that place is exactly the failure this prevents. The
        // same holds when the save released a held place row with the place
        // untouched: nothing else would register its region until the next
        // foreground.
        //
        // An unchanged place counts too. A date set beside it (by the editor
        // or by a spoken "move it to Friday") holds the place, which frees its
        // slot, and clearing the date wants the slot back. That already covers
        // every released hold on a row with a place; the hold's own term is
        // kept so the reason stays named where it is decided.
        reconcileLocationReminders(
            ifTouchingPlaces: locationChanged
                || item.locationIntent != nil
                || ItemPresentation.mayArmPlace(item) != placeCouldArmBefore
        )
        if let personName = item.personName {
            SpeechVocabularyStore.rememberContextualPhrases([personName])
        }
    }

    func setCompleted(_ item: CapturedItem, completed: Bool) throws {
        let completedAt = Date.now
        let previousRecurrences = RecurrenceStore.snapshots()
        var deletedGeneratedItemID: UUID?

        // No successor while the system holds the row for review: see
        // `advanceOverdueRecurrences`, which follows the same rule.
        if completed, !item.isCompleted,
           ItemPresentation.mayArmTime(item),
           RecurrenceStore.generatedNextItemID(for: item.id) == nil,
           let rule = RecurrenceStore.rule(for: item.id),
           let session = item.captureSession,
           let nextDate = nextRecurrenceDate(for: item, rule: rule, completedAt: completedAt) {
            let reminderOffset = seriesReminderOffset(of: item)
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
                // Only a row that may arm reaches here, so this is `true` only
                // when the person turned Needs review on themselves. Their
                // flag follows the series, with the edited intent that keeps
                // it armed.
                needsClarification: item.needsClarification,
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
            // The removed occurrence is no longer in the session, so the
            // session-scoped pass below cannot name it; only this can.
            ReminderScheduler.cancel(itemID: deletedGeneratedItemID)
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
        reconcileLocationReminders(ifTouchingPlaces: item.locationIntent != nil)
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
        reconcileLocationReminders(ifTouchingPlaces: item.locationIntent != nil)
    }

    /// Clears the hold without the editor. Clearing it releases whatever the
    /// row was withholding (`mayArmTime`, `mayArmPlace`), so this reconciles
    /// the same way `update` does rather than leaving the reminder unarmed
    /// until the next foreground.
    func markReviewed(_ item: CapturedItem) throws {
        item.isReviewed = true
        item.needsClarification = false
        item.lastModifiedAt = .now
        try persistChanges()
        synchronizeReminders(for: item.captureSession, requestAuthorizationIfNeeded: false)
        if item.locationIntent != nil {
            reconcileLocationReminders()
        }
    }

    func delete(_ item: CapturedItem) throws {
        let itemID = item.id
        let session = item.captureSession
        let deletesSession = (session?.items.count ?? 0) <= 1
        let recurrenceIDs = deletesSession ? (session?.items.map(\.id) ?? [itemID]) : [itemID]
        let sessionID = session?.id
        // Read before the delete: afterwards there is no item left to ask.
        let touchesPlaces = item.locationIntent != nil
            || (deletesSession && session?.items.contains(where: { $0.locationIntent != nil }) == true)
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
        // Delivery stops here, synchronously, not only in the queued pass
        // below. That pass waits behind every earlier one, which can include a
        // pass sitting on a permission prompt, and a kill in that window used
        // to leave a cancelled alarm armed. The queued pass stays: it
        // re-cancels anything an earlier pass arms after this line.
        recurrenceIDs.forEach(ReminderScheduler.cancel(itemID:))
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
        reconcileLocationReminders(ifTouchingPlaces: touchesPlaces)
    }

    /// The session is fetched by id and its rows are read from it now, so
    /// whatever Split, Merge, Organize again or Undo did to the capture since
    /// somebody last looked, this deletes exactly what is there. A row those
    /// tools already deleted is not in `session.items` any more and is never
    /// touched; a session that is already gone is a no-op.
    ///
    /// Nothing outside the store is cleaned up until the store has saved: a
    /// refused save rolls the context back and throws, and the capture is
    /// still there, reminders and all.
    @discardableResult
    func deleteCapture(sessionID: UUID) throws -> Int {
        var descriptor = FetchDescriptor<CaptureSession>(
            predicate: #Predicate { $0.id == sessionID }
        )
        descriptor.fetchLimit = 1
        guard let session = try modelContext.fetch(descriptor).first else { return 0 }

        let itemIDs = session.items.map(\.id)
        let isTutorial = session.captureSource == .tutorial
        // Read before the delete: afterwards there is no row left to ask.
        let touchesPlaces = session.items.contains { $0.locationIntent != nil }
        // The cascade takes every row the session has, the same way `delete`
        // removes a session with its last row.
        modelContext.delete(session)
        if isTutorial {
            // Practice never reaches iCloud, so it mints no tombstones.
            try persistChanges()
        } else {
            try persistChanges(deletedItemIDs: itemIDs, deletedSessionIDs: [sessionID])
        }

        // Delivery stops here, synchronously, not only in the queued pass
        // below. That pass waits behind every earlier one, which can include a
        // pass sitting on a permission prompt, and a kill in that window would
        // leave the replaced attempt's alarm armed. The queued pass stays: it
        // re-cancels anything an earlier pass arms after this line.
        itemIDs.forEach(ReminderScheduler.cancel(itemID:))
        for itemID in itemIDs {
            RecurrenceStore.remove(itemID)
            PendingOperationStore.remove(itemID)
            LocationReminderMonitor.shared.stopMonitoring(itemID: itemID)
        }
        MemoryPinStore.removeMetadata(for: itemIDs)
        ShoppingGroupStore.removeMetadata(for: itemIDs)
        IdeaStageStore.removeMetadata(for: itemIDs)
        ReminderScheduler.synchronize(
            [],
            requestAuthorizationIfNeeded: false,
            scope: ReminderSynchronizationScope(
                itemIDs: Set(itemIDs),
                captureSessionIDs: [sessionID]
            )
        )
        // A place reminder waiting for a region slot gets the one this frees
        // now, not at the next foreground (see `delete`).
        reconcileLocationReminders(ifTouchingPlaces: touchesPlaces)
        return itemIDs.count
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

        // Read before `apply` rewrites the item: the re-parse can take its
        // place away, which frees a slot.
        let hadPlaceReminder = item.locationIntent != nil
        apply(candidates[0], to: item, createdAt: item.createdAt, reviewed: true)
        var created: [CapturedItem] = []
        for (offset, candidate) in candidates.dropFirst().enumerated() {
            let newItem = makeItem(
                from: candidate,
                session: session,
                createdAt: item.createdAt.addingTimeInterval(Double(offset + 1) / 1_000),
                reviewed: true
            )
            modelContext.insert(newItem)
            created.append(newItem)
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
        // Each part is parsed like a capture, so a part can be a new place
        // reminder, and it is watched now rather than at the next foreground.
        reconcileLocationReminders(
            ifTouchingPlaces: hadPlaceReminder
                || item.locationIntent != nil
                || created.contains(where: { $0.locationIntent != nil })
        )
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

        let target = survivingRow(of: uniqueItems)
        let previousRecurrences = RecurrenceStore.snapshots()
        let removed = uniqueItems.filter { $0.id != target.id }
        // Read before the removed items are deleted and the target re-parsed.
        let hadPlaceReminder = uniqueItems.contains(where: { $0.locationIntent != nil })
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
        // The first row's slot, so the joined words keep their place in the
        // list even when a later row is the one that survives.
        apply(candidate, to: target, createdAt: uniqueItems[0].createdAt, reviewed: true)
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
        // A merged-away place reminder frees its slot, and the merged
        // sentence can carry a place of its own.
        reconcileLocationReminders(
            ifTouchingPlaces: hadPlaceReminder || target.locationIntent != nil
        )
    }

    func undoOrganization(_ session: CaptureSession) throws {
        let previousRecurrences = RecurrenceStore.snapshots()
        ensureFallbackItem(for: session)
        let ordered = orderedItems(in: session)
        guard !ordered.isEmpty else { return }
        let target = survivingRow(of: ordered)
        let removed = ordered.filter { $0.id != target.id }
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
        createdAt: Date,
        id: UUID = UUID()
    ) throws -> (session: CaptureSession, placeholder: CapturedItem) {
        let session = CaptureSession(
            id: id,
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
        // Read before `apply` rewrites them: a reorganize can take a place away.
        let hadPlaceReminder = existingItems.contains { $0.locationIntent != nil }
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
                // The place twin of the line above. Without it a place
                // reminder captured in the app was not watched until the next
                // foreground, and the receipt could not know whether it had
                // taken the last slot. Inside this branch on purpose, although
                // the flag is named for scheduling: every caller that turns it
                // off is a tutorial capture (`schedulesReminders:
                // tutorialMission == nil` in CaptureView, an expression, so a
                // search for `: false` misses it), a DEBUG sample loader, the
                // shopping list, or `SaveThoughtIntent`, which reconciles
                // places itself straight after its save returns.
                reconcileLocationReminders(
                    ifTouchingPlaces: hadPlaceReminder
                        || organized.contains(where: { $0.locationIntent != nil })
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
        // A time set by hand outranks the sentence, the same rule the place
        // follows below and the same mark: `update(_:with:)` stamps
        // `isUserEdited` on the intent it writes, and nothing else does. The
        // time is one family — due date, reminder date, intent and the
        // repeat rule are all written by that one editor save — so it is kept
        // or re-read whole, never field by field, or a kept 4 PM would sit
        // beside a re-read "every Monday". Everything else here is still the
        // system's reading and refreshes. `isReviewed` alone is not this
        // mark: `markReviewed` accepts the reading, it does not replace it.
        let keepsHandSetTime = item.temporalIntent?.isUserEdited == true
        item.originalTextSegment = candidate.sourceQuote
        item.displayTitle = displayTitle(
            for: candidate,
            spokenFallback: item.captureSession?.originalTranscription ?? ""
        )
        item.itemType = organization.itemType
        item.category = organization.category
        item.priority = organization.priority
        item.personName = organization.personName
        if !keepsHandSetTime {
            item.dueDate = organization.dueDate
            item.reminderDate = organization.reminderDate
        }
        item.createdAt = createdAt
        item.processingConfidence = candidate.confidence
        item.needsClarification = organization.needsClarification || candidate.needsReview
        item.isReviewed = reviewed
        item.lastModifiedAt = .now
        // Written back even when kept, in the same order as before: the
        // setter keeps `reminderTriggerKindRawValue` in step, and the place
        // written after it relies on finding the time's answer there.
        item.temporalIntent = keepsHandSetTime ? item.temporalIntent : organization.temporalIntent
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
        if !keepsHandSetTime {
            RecurrenceStore.set(organization.recurrenceRule, for: item.id)
        }
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

    /// The row a merge or an undo keeps, when it folds several rows into one.
    ///
    /// The earliest row that is still open: not completed, not archived. Only
    /// when every row is closed does the earliest row survive as it is. The
    /// survivor's `completedAt` and `isArchived` are never written by `apply`,
    /// so choosing the survivor *is* choosing the result's state. Taking the
    /// earliest row regardless folded open work into a row already marked done
    /// or archived: it left Today, `synchronizeReminders` skipped it, and its
    /// reminder was cancelled with nothing re-armed. A done row resurfacing as
    /// open costs a tap; open work buried under a done one costs the reminder.
    /// Decided 2026-09-23 in `Docs/DECISIONS.md`.
    ///
    /// The survivor is picked rather than the first row reopened, because
    /// reopening in place would bypass `setCompleted`, which owns the link to a
    /// completed series occurrence's generated successor.
    ///
    /// `ordered` must be non-empty and in `itemOrder`.
    private func survivingRow(of ordered: [CapturedItem]) -> CapturedItem {
        ordered.first(where: { !$0.isCompleted && !$0.isArchived }) ?? ordered[0]
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

    private static let unreadableLibrary = ICloudSyncResult.failed(
        "Speak It couldn’t read this iPhone’s library. Nothing was synced or changed."
    )

    /// The local snapshot, or nil, logged, when the store cannot be read. The
    /// sync stops there rather than merging and applying from nothing.
    private func readICloudSnapshot() -> ICloudLibrarySnapshot? {
        do {
            return try makeICloudSnapshot()
        } catch {
            Self.captureLog.fault("iCloud sync could not read the local library; nothing was merged")
            return nil
        }
    }

    /// Throws when the store cannot be read. An empty snapshot built from a
    /// failed fetch would merge as "this iPhone has nothing", and
    /// `applyICloudSnapshot` then deletes every local row the cloud copy does
    /// not hold, which is everything captured since the last upload.
    private func makeICloudSnapshot() throws -> ICloudLibrarySnapshot {
        // Practice is local, temporary UI state. Never upload it, even if the
        // user enables iCloud while the tutorial is still open.
        let sessions = try modelContext.fetch(FetchDescriptor<CaptureSession>())
            .filter { $0.captureSource != .tutorial }
        let syncedSessionIDs = Set(sessions.map(\.id))
        let items = try modelContext.fetch(FetchDescriptor<CapturedItem>())
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
                    temporalIntent: item.temporalIntent,
                    portableSemantics: ICloudItemSemantics(
                        temporalIntent: item.temporalIntent,
                        locationIntent: item.locationIntent,
                        semanticStateRawValue: item.semanticStateRawValue,
                        semanticGapRawValue: item.semanticGapRawValue,
                        shoppingGroup: ShoppingGroupStore.group(for: item.id)
                    )
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
            if let semantics = value.portableSemantics {
                // A snapshot's nil intent is what `makeICloudSnapshot` writes
                // for a row whose bytes did not decode (nothing in the app
                // clears an intent to nil: the organizer and the editor always
                // write one). Applied to that same row coming back, it erased
                // the bytes the launch backfill keeps.
                item.carryTemporalIntent(semantics.temporalIntent)
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
        // A row another device deleted stops ringing now rather than when the
        // queued whole-library reconcile below reaches it.
        removedItemIDs.forEach(ReminderScheduler.cancel(itemID:))

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
            .compactMap { ReminderScheduleRequest.forScheduling($0) }
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

    /// Replaces every pending Speak It notification with one per live timed
    /// row. The scope sets `replacesAllSpeakItReminders`, so the pass first
    /// removes every pending `SpeakIt.reminder.` and `SpeakIt.session.`
    /// request and then adds only what this fetch returned.
    ///
    /// That is why a failed fetch must stop the pass rather than read as an
    /// empty list: an empty list here removes every time reminder on the
    /// phone and arms none. On failure what iOS already holds is kept, and
    /// rows this pass would have added wait for the next reconcile.
    private func synchronizeAllReminders(requestAuthorizationIfNeeded: Bool) {
        let descriptor = FetchDescriptor<CapturedItem>(
            predicate: #Predicate { item in
                item.reminderDate != nil && item.isArchived == false && item.completedAt == nil
            }
        )
        let items: [CapturedItem]
        do {
            items = try modelContext.fetch(descriptor)
        } catch {
            Self.reminderLog.fault("Full reminder sync could not fetch its rows; kept what is scheduled")
            return
        }
        let requests = items.compactMap { ReminderScheduleRequest.forScheduling($0) }
        // Scoped on the fetched items, not on the requests, as the other two
        // scopes are. A row held for review makes no request, so a
        // requests-only scope never called `cancel(itemID:)` for it: the
        // notification still went with `replacesAllSpeakItReminders`, and an
        // AlarmKit alarm armed before the hold did not.
        ReminderScheduler.synchronize(
            requests,
            requestAuthorizationIfNeeded: requestAuthorizationIfNeeded && requestsReminderAuthorization,
            scope: ReminderSynchronizationScope(
                itemIDs: Set(items.map(\.id)),
                captureSessionIDs: Set(items.compactMap { $0.captureSession?.id }),
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
        // A snooze belonged to the occurrence being left behind.
        intent.snoozedFromReminderDate = nil
        // The day is read in the intent's own calendar, so a series pinned to a
        // named zone ("every day at 9 AM Toronto time") keeps advancing by
        // Toronto days rather than by the travelling device's days.
        intent.day = CalendarDay(
            from: nextDate,
            calendar: intent.calendar(default: .autoupdatingCurrent)
        )
        return intent
    }

    /// How far a series puts its alert from its due date, which every next
    /// occurrence keeps.
    ///
    /// Read from `seriesReminderDate`, not `reminderDate`. A snoozed
    /// `reminderDate` minus the due date is the snooze, and carrying that
    /// forward turned "every day at 8", snoozed ten minutes, into "every day
    /// at 8:10" for every occurrence after it.
    private func seriesReminderOffset(of item: CapturedItem) -> TimeInterval {
        guard let reminder = item.seriesReminderDate, let due = item.dueDate else { return 0 }
        return reminder.timeIntervalSince(due)
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
            // A reminder-only series has no due date to anchor on; its anchor
            // is its own alert, never a snoozed one.
            scheduledDate: item.dueDate ?? item.seriesReminderDate,
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

        // Failing safe here means saving the capture. This lookup only decides
        // whether an identical capture from the last few seconds already
        // exists, and a thrown error would abort the capture before anything
        // is written, so a person's words could be lost to a lookup that
        // guards against a double tap. A Siri, Shortcut or Share capture has
        // no draft to fall back on. Treating the failure as "no duplicate" at
        // worst stores the same words twice, which the person can delete;
        // words never stored cannot be recovered. The failure is logged.
        let recent: [CaptureSession]
        do {
            recent = try modelContext.fetch(descriptor)
        } catch {
            Self.captureLog.fault("Capture deduplication could not fetch recent sessions; saving anyway")
            return nil
        }
        let fingerprint = text.captureFingerprint
        return recent.lazy.compactMap { session in
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
