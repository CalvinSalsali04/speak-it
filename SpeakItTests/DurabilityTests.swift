import SwiftData
import XCTest
@testable import SpeakIt

/// Destruction pass: what survives a kill.
///
/// Semantics are frozen. Nothing here asks whether a phrase was read well; every
/// test asks whether a correct reading *survived* an interruption. The single
/// invariant behind all of them:
///
/// > A spoken thought is either durably saved, safely recoverable, or clearly
/// > unresolved. It never silently disappears and never appears twice.
///
/// A process kill is modelled by discarding the repository and building a new
/// one over the same store, then running the launch recovery sequence in the
/// order `RootView` runs it. Everything durable — SwiftData rows, the draft
/// store, recurrence and pin metadata — outlives the repository object, so what
/// the next launch sees here is what the next launch sees on device.
@MainActor
final class DurabilityTests: XCTestCase {
    private var container: ModelContainer!
    private var repository: SwiftDataThoughtRepository!
    private var delivery: RecordingDelivery!
    private var previousDelivery: ReminderDeliverySink!
    private var previousRecurrences: [RecurrenceRecordSnapshot] = []
    private var previousDeletionRecords: [ICloudDeletionRecord] = []
    private var previousPinRecords: [MemoryPinRecord] = []
    private var previousIdeaStageRecords: [IdeaStageRecord] = []

    /// The two systems a reminder actually lives in, so a test can prove the
    /// notification and the alarm are gone rather than only that the row is.
    ///
    /// Locked because the queued scheduler pass writes here off the main
    /// actor while the test reads.
    private final class RecordingDelivery: @unchecked Sendable {
        private let lock = NSLock()
        private var notifications: Set<String> = []
        private var alarms: Set<UUID> = []

        var pendingNotifications: Set<String> { lock.withLock { notifications } }
        var scheduledAlarms: Set<UUID> { lock.withLock { alarms } }

        func seedNotification(_ identifier: String) {
            lock.withLock { _ = notifications.insert(identifier) }
        }

        func seedAlarm(_ id: UUID) {
            lock.withLock { _ = alarms.insert(id) }
        }

        var sink: ReminderDeliverySink {
            ReminderDeliverySink(
                removeNotifications: { [self] identifiers in
                    lock.withLock { identifiers.forEach { notifications.remove($0) } }
                },
                cancelAlarm: { [self] id in lock.withLock { _ = alarms.remove(id) } },
                pendingIdentifiers: { [self] in lock.withLock { Array(notifications) } },
                scheduledAlarmIDs: { [self] in lock.withLock { Array(alarms) } }
            )
        }
    }

    override func setUpWithError() throws {
        previousRecurrences = RecurrenceStore.snapshots()
        previousDeletionRecords = ICloudDeletionStore.records()
        previousPinRecords = Array(MemoryPinStore.records().values)
        previousIdeaStageRecords = Array(IdeaStageStore.records().values)
        delivery = RecordingDelivery()
        previousDelivery = ReminderScheduler.delivery
        ReminderScheduler.delivery = delivery.sink
        CaptureDraftStore.clear()

        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(
            for: PersistenceController.schema,
            migrationPlan: SpeakItMigrationPlan.self,
            configurations: [configuration]
        )
        repository = makeRepository()
    }

    override func tearDownWithError() throws {
        CaptureDraftStore.clear()
        ReminderScheduler.delivery = previousDelivery
        RecurrenceStore.restore(previousRecurrences)
        ICloudDeletionStore.restore(previousDeletionRecords)
        MemoryPinStore.restore(previousPinRecords)
        IdeaStageStore.restore(previousIdeaStageRecords)
        repository = nil
        container = nil
    }

    // MARK: - Kill and relaunch

    private func makeRepository() -> SwiftDataThoughtRepository {
        SwiftDataThoughtRepository(
            modelContext: container.mainContext,
            placeReminderDelivery: { _, _, _, _ in .scheduled },
            placeReminderCancellation: { _ in },
            requestsReminderAuthorization: false
        )
    }

    /// Drops the repository and runs the launch recovery sequence on a fresh
    /// one, in `RootView`'s order.
    @discardableResult
    private func relaunch() -> SwiftDataThoughtRepository {
        repository = nil
        let next = makeRepository()
        CaptureDraftStore.pruneEmptyTextDrafts()
        CaptureDraftStore.pruneResolvedTombstones()
        next.releaseHandedOffCaptureDrafts()
        next.recoverUnorganizedCaptures()
        next.recoverInterruptedCaptureDraft()
        next.reconcilePendingReminders()
        repository = next
        return next
    }

    /// `ReminderScheduler.synchronize` is fire-and-forget behind a serial tail
    /// task. Asserting that something is *absent* without waiting for that tail
    /// passes for the wrong reason. Draining with an empty, empty-scoped request
    /// waits for the tail and removes nothing.
    private func drainScheduler() async {
        _ = await ReminderScheduler.synchronizeAndVerify(
            [],
            requestAuthorizationIfNeeded: false,
            scope: ReminderSynchronizationScope()
        )
    }

    private func relaunchAndDrain() async {
        relaunch()
        await drainScheduler()
    }

    /// Writes exactly what `createPendingCapture` writes, then stops — the state
    /// a kill between "raw words committed" and "organized" leaves behind.
    @discardableResult
    private func killAfterRawPersistence(
        _ text: String,
        source: CaptureSource = .inAppVoice,
        createdAt: Date = .now,
        status: ProcessingStatus = .pending,
        id: UUID = UUID()
    ) throws -> UUID {
        let session = CaptureSession(
            id: id,
            originalTranscription: text,
            createdAt: createdAt,
            captureSource: source,
            processingStatus: status
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
        container.mainContext.insert(session)
        container.mainContext.insert(placeholder)
        try container.mainContext.save()
        return session.id
    }

    // MARK: - Reading the store

    private func allItems() throws -> [CapturedItem] {
        try container.mainContext.fetch(FetchDescriptor<CapturedItem>())
    }

    private func allSessions() throws -> [CaptureSession] {
        try container.mainContext.fetch(FetchDescriptor<CaptureSession>())
    }

    private func liveItems() throws -> [CapturedItem] {
        try allItems().filter { $0.completedAt == nil && !$0.isArchived }
    }

    private func capture(
        _ text: String,
        source: CaptureSource = .inAppText,
        createdAt: Date = .now
    ) async throws -> CaptureCreationResult {
        try await repository.createCaptureResult(
            text: text,
            source: source,
            createdAt: createdAt,
            schedulesReminders: false
        )
    }

    // MARK: - 1. Capture interruption

    func testKillAfterRawPersistenceRecoversExactlyOneOrganizedThought() throws {
        let text = "Submit the insurance form on Friday"
        _ = try killAfterRawPersistence(text)

        relaunch()

        let sessions = try allSessions()
        let items = try allItems()
        XCTAssertEqual(sessions.count, 1, "The interrupted capture must not be duplicated")
        XCTAssertEqual(sessions[0].originalTranscription, text, "The original words are never rewritten")
        XCTAssertEqual(sessions[0].processingStatus, .complete)
        XCTAssertEqual(items.count, 1)
        XCTAssertFalse(items[0].needsClarification, "Recovery must finish organizing, not leave the placeholder")
    }

    func testRecoveryIsIdempotentAcrossRepeatedRelaunches() throws {
        _ = try killAfterRawPersistence("Pick up the dry cleaning tomorrow at 5")

        relaunch()
        let afterFirst = try allItems().map(\.id).sorted { $0.uuidString < $1.uuidString }
        relaunch()
        relaunch()
        let afterThird = try allItems().map(\.id).sorted { $0.uuidString < $1.uuidString }

        XCTAssertEqual(afterFirst, afterThird, "Relaunching must not create or destroy rows")
        XCTAssertEqual(try allSessions().count, 1)
    }

    func testKillDuringOrganizationRecoversWithoutDuplicatingItems() throws {
        _ = try killAfterRawPersistence(
            "Call the plumber and book the car service",
            status: .organizing
        )

        relaunch()

        let items = try allItems()
        XCTAssertEqual(try allSessions().count, 1)
        XCTAssertEqual(items.count, 2, "Two thoughts were spoken; recovery must produce two, not four")
        XCTAssertEqual(try allSessions()[0].processingStatus, .complete)
    }

    func testFailedSessionIsRetriedRatherThanLeftBehind() throws {
        _ = try killAfterRawPersistence("Email Dana the invoice", status: .failed)

        relaunch()

        XCTAssertEqual(try allSessions()[0].processingStatus, .complete)
        XCTAssertEqual(try allItems().count, 1)
    }

    // MARK: - 1b. A person's hand outranks launch recovery

    /// Two thoughts in one sentence, so a recovery that re-reads the words
    /// produces two rows where the placeholder was one. That makes both an
    /// overwrite and a duplicate visible.
    private let twoThoughts = "Call the plumber and book the car service"

    private func rows(inSession sessionID: UUID) throws -> [CapturedItem] {
        try allItems()
            .filter { $0.captureSession?.id == sessionID }
            .sorted { $0.createdAt < $1.createdAt }
    }

    private func storedSession(_ sessionID: UUID) throws -> CaptureSession {
        try XCTUnwrap(try allSessions().first { $0.id == sessionID })
    }

    /// The placeholder of an interrupted capture is on screen from the first
    /// frame, and launch recovery only reaches it after the audio drafts are
    /// recovered; a `.failed` capture's row waits in Needs review for as long
    /// as it takes. Either way the person can correct the row, through the
    /// editor's own `update`, before a later launch re-reads the words. That
    /// launch used to write the organizer's answer over the correction.
    func testAHandEditOnAnUnfinishedCaptureSurvivesRelaunch() throws {
        let dueDate = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: 45, to: .now))

        for status in [ProcessingStatus.pending, .organizing, .failed] {
            let sessionID = try killAfterRawPersistence(twoThoughts, status: status)
            let placeholder = try XCTUnwrap(try rows(inSession: sessionID).first)
            var edits = ItemEdits(
                title: "Call the plumber about the kitchen leak",
                itemType: .task,
                category: .personal,
                dueDate: dueDate,
                reminderDate: nil,
                priority: .high,
                personName: nil,
                needsClarification: false
            )
            edits.locationIntent = .unchanged
            try repository.update(placeholder, with: edits)
            let editedID = placeholder.id
            let editedTitle = placeholder.displayTitle

            relaunch()

            let after = try rows(inSession: sessionID)
            XCTAssertEqual(
                after.map(\.id), [editedID],
                "\(status): recovery must neither delete the edited row nor add rows beside it"
            )
            let row = try XCTUnwrap(after.first)
            XCTAssertEqual(row.displayTitle, editedTitle, "\(status): the typed title was reverted")
            XCTAssertEqual(row.itemType, .task, "\(status)")
            XCTAssertEqual(row.category, .personal, "\(status)")
            XCTAssertEqual(row.priority, .high, "\(status)")
            XCTAssertEqual(row.dueDate, dueDate, "\(status): the hand-picked date was reverted")
            XCTAssertNil(row.reminderDate, "\(status)")
            XCTAssertFalse(row.needsClarification, "\(status)")
            XCTAssertTrue(row.isReviewed, "\(status): recovery reset the review")
            XCTAssertEqual(row.temporalIntent?.isUserEdited, true, "\(status)")

            let session = try storedSession(sessionID)
            XCTAssertEqual(session.processingStatus, .complete, "\(status): left open, it is re-read at every launch")
            XCTAssertEqual(session.originalTranscription, twoThoughts, "The original words are never rewritten")
        }
    }

    /// Marking a row reviewed changes no field, but it is still the person's
    /// decision about that row, and recovery must not undo it.
    func testAReviewedRowOnAFailedCaptureIsNotReReadAtRelaunch() throws {
        let sessionID = try killAfterRawPersistence(twoThoughts, status: .failed)
        let placeholder = try XCTUnwrap(try rows(inSession: sessionID).first)
        let placeholderTitle = placeholder.displayTitle
        try repository.markReviewed(placeholder)

        relaunch()

        let after = try rows(inSession: sessionID)
        XCTAssertEqual(after.map(\.id), [placeholder.id])
        XCTAssertEqual(after.first?.displayTitle, placeholderTitle)
        XCTAssertEqual(after.first?.itemType, .unclear)
        XCTAssertEqual(after.first?.isReviewed, true)
        XCTAssertEqual(try storedSession(sessionID).processingStatus, .complete)
    }

    /// Each mark is enough on its own. The row carries exactly one of them,
    /// so taking any single term out of `carriesPersonsDecision` fails here.
    /// Completing and archiving go through the repository, which leaves only
    /// its own mark on a placeholder. An edit through `update` always marks
    /// the row reviewed as well, so the two intent flags are written alone.
    func testEachMarkOfAPersonsHandKeepsRecoveryOffOnItsOwn() throws {
        let marks: [(name: String, leave: (CapturedItem) throws -> Void)] = [
            ("reviewed", { try self.repository.markReviewed($0) }),
            ("completed", { try self.repository.setCompleted($0, completed: true) }),
            ("archived", { try self.repository.setArchived($0, archived: true) }),
            ("time set by hand", { row in
                row.temporalIntent = TemporalIntent(kind: .none, isUserEdited: true)
                try self.container.mainContext.save()
            }),
            ("place set by hand", { row in
                row.locationIntent = LocationIntent(event: .arrive, place: .home, isUserEdited: true)
                try self.container.mainContext.save()
            }),
        ]

        for (name, leave) in marks {
            let sessionID = try killAfterRawPersistence(twoThoughts, status: .failed)
            let placeholder = try XCTUnwrap(try rows(inSession: sessionID).first)
            try leave(placeholder)
            let carried = [
                placeholder.isReviewed,
                placeholder.isCompleted,
                placeholder.isArchived,
                placeholder.temporalIntent?.isUserEdited == true,
                placeholder.locationIntent?.isUserEdited == true,
            ].filter { $0 }.count
            XCTAssertEqual(carried, 1, "\(name): the row must carry this mark alone")

            relaunch()

            XCTAssertEqual(
                try rows(inSession: sessionID).map(\.id), [placeholder.id],
                "\(name): recovery re-read a capture the person had marked"
            )
            XCTAssertEqual(try storedSession(sessionID).processingStatus, .complete, "\(name)")
        }
    }

    /// The control for the two tests above: the same words in the same states,
    /// with nobody's hand on the row, are still organized at launch. Without
    /// it those tests would also pass for a fix that stopped recovering.
    func testAnUntouchedUnfinishedCaptureIsStillOrganizedAtRelaunch() throws {
        for status in [ProcessingStatus.pending, .organizing, .failed] {
            let sessionID = try killAfterRawPersistence(twoThoughts, status: status)
            let placeholderTitle = try XCTUnwrap(try rows(inSession: sessionID).first).displayTitle

            relaunch()

            let after = try rows(inSession: sessionID)
            XCTAssertEqual(after.count, 2, "\(status): recovery must still split the capture it never finished")
            XCTAssertFalse(
                after.contains { $0.displayTitle == placeholderTitle },
                "\(status): the placeholder was left unorganized"
            )
            XCTAssertFalse(after.contains { $0.isReviewed }, "\(status)")
            XCTAssertEqual(try storedSession(sessionID).processingStatus, .complete, "\(status)")
        }
    }

    /// A spoken operation from a later capture used to reach the placeholder
    /// of an unfinished one, whose segment is the whole transcript. The move
    /// went through `update`, which marks the row reviewed and its time as set
    /// by hand, so the next launch closed the capture as the person's and
    /// "book the car service" was never organized. The move is held for the
    /// person instead, and the capture is still organized at relaunch.
    func testASpokenMoveDoesNotReachThePlaceholderOfAnUnfinishedCapture() async throws {
        let sessionID = try killAfterRawPersistence(twoThoughts)
        let placeholderID = try XCTUnwrap(try rows(inSession: sessionID).first).id

        let move = try await capture("Move the plumber to Friday")

        guard case let .ambiguous(operation, candidateIDs) = try XCTUnwrap(move.operationOutcome) else {
            return XCTFail("A move whose only match is an unorganized placeholder must be held")
        }
        XCTAssertEqual(operation, .reschedule)
        XCTAssertEqual(candidateIDs, [placeholderID])
        XCTAssertFalse(move.items.isEmpty, "the held move stays as a review row")
        let untouched = try rows(inSession: sessionID)
        XCTAssertEqual(untouched.map(\.id), [placeholderID])
        XCTAssertEqual(untouched.first?.isReviewed, false, "the placeholder was marked as the person's")
        XCTAssertNil(untouched.first?.reminderDate, "the placeholder was moved")

        relaunch()

        let after = try rows(inSession: sessionID)
        XCTAssertEqual(after.count, 2, "recovery must still split the capture the move never reached")
        XCTAssertFalse(after.contains { $0.isReviewed })
        XCTAssertEqual(try storedSession(sessionID).processingStatus, .complete)
        XCTAssertFalse(try rows(inSession: move.session.id).isEmpty, "the held move was lost at relaunch")
    }

    /// The same reach with a cancel lost more than the organizing: `delete`
    /// removes a capture along with its last row, so the unfinished capture
    /// went, transcript and all, with "book the car service" in it.
    func testASpokenCancelDoesNotDeleteAnUnfinishedCapture() async throws {
        let sessionID = try killAfterRawPersistence(twoThoughts, status: .failed)

        let cancel = try await capture("Cancel the plumber reminder")

        guard case .ambiguous = try XCTUnwrap(cancel.operationOutcome) else {
            return XCTFail("A cancel whose only match is an unorganized placeholder must be held")
        }
        XCTAssertEqual(
            try storedSession(sessionID).originalTranscription, twoThoughts,
            "The original words are never rewritten"
        )

        relaunch()

        XCTAssertEqual(
            try rows(inSession: sessionID).count, 2,
            "recovery must still split the capture the cancel never reached"
        )
    }

    /// A broad request listed every active row as its candidates, the
    /// placeholder of an unfinished capture included, and confirming it
    /// deleted that capture with its last row, transcript and all. The
    /// finished capture is still cancelled; the unfinished one is not named,
    /// the prompt counts one item, and the capture is organized at relaunch.
    ///
    /// Falsifiers: listing broad candidates from `activeItems` alone fails the
    /// outcome's candidates and the stored record; with the check at
    /// confirmation gone as well, the session, its words and the two rows at
    /// relaunch fail too (the next test covers that check alone); a fix that
    /// also left out finished rows fails on "Buy milk".
    func testAConfirmedBroadCancelLeavesAnUnfinishedCaptureAndItsWords() async throws {
        let milkID = try await capture("Buy milk").primaryItem.id
        let sessionID = try killAfterRawPersistence(twoThoughts, status: .failed)
        let placeholderID = try XCTUnwrap(try rows(inSession: sessionID).first).id

        let broad = try await capture("Cancel every reminder")

        guard case let .needsConfirmation(operation, candidateIDs) = try XCTUnwrap(broad.operationOutcome) else {
            return XCTFail("A broad cancel must be held for confirmation")
        }
        XCTAssertEqual(operation, .cancel)
        XCTAssertEqual(candidateIDs, [milkID], "an unorganized capture was named for deletion")
        let reviewRow = try XCTUnwrap(try rows(inSession: broad.session.id).first)
        XCTAssertEqual(PendingOperationStore.record(for: reviewRow.id)?.candidateIDs, [milkID])
        XCTAssertEqual(
            repository.pendingOperationCandidateIDs(for: reviewRow), [milkID],
            "the prompt would count a capture confirming leaves alone"
        )

        try repository.confirmPendingOperation(reviewRow)

        XCTAssertNil(try allItems().first { $0.id == milkID }, "the finished capture was not cancelled")
        XCTAssertNil(try allItems().first { $0.id == reviewRow.id }, "the review row is resolved")
        XCTAssertEqual(
            try storedSession(sessionID).originalTranscription, twoThoughts,
            "the unfinished capture and its words were deleted"
        )
        let untouched = try rows(inSession: sessionID)
        XCTAssertEqual(untouched.map(\.id), [placeholderID])
        XCTAssertEqual(untouched.first?.isCompleted, false)
        XCTAssertEqual(untouched.first?.isReviewed, false)

        relaunch()

        XCTAssertEqual(
            try rows(inSession: sessionID).count, 2,
            "recovery must still split the capture the cancel never reached"
        )
        XCTAssertEqual(try storedSession(sessionID).processingStatus, .complete)
    }

    /// The list is fixed when the request is held, and a capture can be
    /// unfinished by the time it is confirmed: a record written before this
    /// exclusion existed, or a session `Organize again` left `.failed`. Such a
    /// record names the placeholder directly here, with a complete, which
    /// would stamp the mark recovery reads as the person's hand and close the
    /// capture unorganized.
    ///
    /// Falsifier: confirmation or the prompt count reading the stored list
    /// without checking each row again fails the count, the placeholder's
    /// `isCompleted`, and the two rows at relaunch.
    func testConfirmingAHeldBroadRequestSkipsARowWhoseCaptureIsUnfinishedNow() async throws {
        let milkID = try await capture("Buy milk").primaryItem.id
        let broad = try await capture("Cancel every reminder")
        let reviewRow = try XCTUnwrap(try rows(inSession: broad.session.id).first)
        let sessionID = try killAfterRawPersistence(twoThoughts)
        let placeholderID = try XCTUnwrap(try rows(inSession: sessionID).first).id
        PendingOperationStore.set(
            operation: .complete,
            candidateIDs: [milkID, placeholderID],
            for: reviewRow.id
        )

        XCTAssertEqual(repository.pendingOperationCandidateIDs(for: reviewRow), [milkID])

        try repository.confirmPendingOperation(reviewRow)

        XCTAssertEqual(try allItems().first { $0.id == milkID }?.isCompleted, true)
        let untouched = try rows(inSession: sessionID)
        XCTAssertEqual(untouched.map(\.id), [placeholderID])
        XCTAssertEqual(untouched.first?.isCompleted, false, "the placeholder was marked done")
        XCTAssertNil(PendingOperationStore.record(for: reviewRow.id))

        relaunch()

        XCTAssertEqual(
            try rows(inSession: sessionID).count, 2,
            "recovery must still organize the capture the confirmation skipped"
        )
    }

    /// The control: a row of the same shape and words (the whole transcript,
    /// unreviewed, needing clarification) whose capture is `.complete` is
    /// named and cancelled like any other.
    ///
    /// Falsifier: an exclusion keyed on how the row looks rather than on its
    /// capture's state (needs clarification, zero confidence, a segment equal
    /// to the transcript) keeps this row and fails every assertion below.
    func testABroadCancelStillReachesAPlaceholderShapedRowOfAFinishedCapture() async throws {
        let milkID = try await capture("Buy milk").primaryItem.id
        let sessionID = try killAfterRawPersistence(twoThoughts, status: .complete)
        let rowID = try XCTUnwrap(try rows(inSession: sessionID).first).id

        let broad = try await capture("Cancel every reminder")

        guard case let .needsConfirmation(_, candidateIDs) = try XCTUnwrap(broad.operationOutcome) else {
            return XCTFail("A broad cancel must be held for confirmation")
        }
        XCTAssertEqual(Set(candidateIDs), [milkID, rowID])
        let reviewRow = try XCTUnwrap(try rows(inSession: broad.session.id).first)
        XCTAssertEqual(Set(repository.pendingOperationCandidateIDs(for: reviewRow)), [milkID, rowID])

        try repository.confirmPendingOperation(reviewRow)

        XCTAssertTrue(try allItems().isEmpty, "everything the confirmed request named is cancelled")
    }

    /// Recovery re-reads the words with the rules-only extractor while the live
    /// path uses the full one. If those two disagree about whether a sentence is
    /// an operation, a kill turns "cancel the dentist reminder" into a task
    /// named after the thing the person just cancelled.
    func testRecoveryDoesNotTurnAnInterruptedCancellationIntoATask() async throws {
        _ = try await capture("Remind me about the dentist on Friday")
        _ = try killAfterRawPersistence("Cancel the dentist reminder")

        relaunch()

        let titles = try liveItems().map(\.displayTitle)
        XCTAssertFalse(
            titles.contains { $0.localizedCaseInsensitiveContains("cancel") },
            "An interrupted cancellation must never be recovered as a task: \(titles)"
        )
    }

    func testRecoveryDoesNotTurnAnInterruptedRetractionIntoATask() throws {
        _ = try killAfterRawPersistence("Actually never mind, forget that")

        relaunch()

        let titles = try liveItems().map(\.displayTitle)
        XCTAssertTrue(
            titles.isEmpty,
            "A withdrawn capture must produce nothing, even after a kill: \(titles)"
        )
    }

    // MARK: - 2. Operation interruption

    func testCancellingTheSameReminderTwiceRemovesItOnceAndInventsNothing() async throws {
        _ = try await capture("Remind me about the dentist on Friday")
        _ = try await capture("Buy milk")
        let before = try allItems().count

        _ = try await capture("Cancel the dentist reminder", createdAt: .now)
        let afterFirst = try allItems().count
        let second = try await capture(
            "Cancel the dentist reminder",
            createdAt: Date().addingTimeInterval(60)
        )

        XCTAssertEqual(afterFirst, before - 1)
        XCTAssertEqual(try allItems().count, afterFirst, "The second cancellation must change nothing")
        guard case .notFound = try XCTUnwrap(second.operationOutcome) else {
            return XCTFail("A second cancellation has nothing to act on")
        }
    }

    func testCompletingTheSameItemTwiceGeneratesOneRecurrenceOnly() async throws {
        let created = try await capture("Take out the bins every Tuesday")
        let item = created.primaryItem

        try repository.setCompleted(item, completed: true)
        let afterFirst = try allItems().count
        try repository.setCompleted(item, completed: true)

        XCTAssertEqual(
            try allItems().count,
            afterFirst,
            "Completing twice must not generate a second occurrence"
        )
    }

    func testCancelledItemLeavesNoArmedNotificationBehind() async throws {
        let created = try await capture("Remind me to call the bank on Friday at 9am")
        let item = created.primaryItem
        let identifier = ReminderScheduler.notificationIdentifier(for: item.id)
        delivery.seedNotification(identifier)
        delivery.seedAlarm(item.id)

        _ = try await capture(
            "Cancel the call the bank reminder",
            createdAt: Date().addingTimeInterval(30)
        )
        await drainScheduler()

        XCTAssertFalse(
            delivery.pendingNotifications.contains(identifier),
            "The row is gone; the notification must be gone with it"
        )
    }

    /// An AlarmKit alarm armed before its row was held for review (by an
    /// earlier build, or before a reorganize held it) must be cancelled by
    /// every whole-store pass. `synchronizeAllReminders`, which loading the
    /// sample captures runs, scoped its cancellation on the requests it built,
    /// and a held row builds none, so its alarm survived that pass. It is
    /// scoped on the fetched rows now, as the other two passes are.
    ///
    /// Falsifier: scope `synchronizeAllReminders` on `requests.map(\.itemID)`
    /// again and the seeded alarm is never cancelled.
    func testAWholeStorePassCancelsTheAlarmOfARowHeldForReview() async throws {
        let session = CaptureSession(
            originalTranscription: "Set an alarm for 6:45 tomorrow",
            captureSource: .inAppText,
            processingStatus: .complete
        )
        let held = CapturedItem(
            originalTextSegment: session.originalTranscription,
            displayTitle: "Alarm",
            itemType: .task,
            reminderDate: Date().addingTimeInterval(24 * 60 * 60),
            needsClarification: true,
            captureSession: session
        )
        container.mainContext.insert(session)
        container.mainContext.insert(held)
        try container.mainContext.save()
        delivery.seedAlarm(held.id)
        XCTAssertNil(ReminderScheduleRequest(item: held), "precondition: held, so no request")

        _ = try repository.loadSampleData()
        await drainScheduler()

        XCTAssertFalse(
            delivery.scheduledAlarms.contains(held.id),
            "a held row's alarm must not outlive a whole-store pass"
        )
    }

    /// The kill window inside `delete`: the row is saved before the notification
    /// is torn down. Relaunch has to close that gap on its own.
    func testRelaunchDisarmsANotificationWhoseRowIsAlreadyGone() async throws {
        let created = try await capture("Remind me to call the bank on Friday at 9am")
        let itemID = created.primaryItem.id
        let identifier = ReminderScheduler.notificationIdentifier(for: itemID)

        // Kill between save and teardown: delete the row directly, leaving the
        // notification armed exactly as an interrupted `delete` would.
        container.mainContext.delete(created.primaryItem)
        try container.mainContext.save()
        delivery.seedNotification(identifier)

        await relaunchAndDrain()

        XCTAssertFalse(
            delivery.pendingNotifications.contains(identifier),
            "Relaunch must reconcile away a reminder with no row"
        )
    }

    /// The same kill window for an AlarmKit alarm, which the notification
    /// prefix sweep never reached: its ID is the item ID, and a row that is
    /// gone is in no reconcile scope.
    ///
    /// Falsifier: delete the `cancelOrphanedAlarms` call from
    /// `reconcilePendingReminders`, or have the sink stop reporting
    /// `scheduledAlarmIDs`, and the seeded alarm survives the relaunch.
    func testRelaunchDisarmsAnAlarmWhoseRowIsAlreadyGone() async throws {
        let created = try await capture("Set an alarm for 7 AM to take my pills")
        let itemID = created.primaryItem.id

        container.mainContext.delete(created.primaryItem)
        try container.mainContext.save()
        delivery.seedAlarm(itemID)

        await relaunchAndDrain()

        XCTAssertFalse(
            delivery.scheduledAlarms.contains(itemID),
            "Relaunch must cancel an alarm whose row is gone"
        )
    }

    /// The sweep decides only for alarms with no row. An alarm whose row still
    /// exists is left exactly where it is, next to an orphan that is cancelled
    /// in the same pass.
    ///
    /// Falsifier: make `orphanedAlarmIDs` return `scheduled` unfiltered, and
    /// the live row's alarm is cancelled along with the orphan.
    func testTheOrphanSweepKeepsTheAlarmOfARowThatStillExists() async throws {
        let created = try await capture("Set an alarm for 7 AM to take my pills")
        let liveID = created.primaryItem.id
        let orphanID = UUID()
        delivery.seedAlarm(liveID)
        delivery.seedAlarm(orphanID)

        let store: ModelContainer = container
        ReminderScheduler.cancelOrphanedAlarms(accountedFor: {
            let rows = (try? store.mainContext.fetch(FetchDescriptor<CapturedItem>())) ?? []
            return Set(rows.map(\.id))
        })
        await drainScheduler()

        XCTAssertTrue(delivery.scheduledAlarms.contains(liveID))
        XCTAssertFalse(delivery.scheduledAlarms.contains(orphanID))
    }

    /// Rows that cannot be read are not an empty library. If they were, one
    /// failed fetch would cancel every alarm the person has.
    ///
    /// Falsifier: replace the `let rowIDs = await accountedFor()` guard with
    /// `accountedFor() ?? []`, and both seeded alarms are cancelled.
    func testTheOrphanSweepCancelsNothingWhenTheRowsCannotBeRead() async throws {
        let first = UUID()
        let second = UUID()
        delivery.seedAlarm(first)
        delivery.seedAlarm(second)

        ReminderScheduler.cancelOrphanedAlarms(accountedFor: { nil })
        await drainScheduler()

        XCTAssertEqual(delivery.scheduledAlarms, [first, second])
    }

    /// The pure decision: every listed alarm that no row accounts for, in the
    /// order AlarmKit listed them, and nothing else. A row with no alarm adds
    /// nothing to the answer.
    ///
    /// Falsifier: invert the `contains` test, or return `scheduled`, and the
    /// result names the accounted-for alarm.
    func testOrphanedAlarmsAreTheScheduledOnesNoRowAccountsFor() {
        let orphanA = UUID()
        let kept = UUID()
        let orphanB = UUID()
        let rowWithoutAlarm = UUID()

        XCTAssertEqual(
            ReminderScheduler.orphanedAlarmIDs(
                scheduled: [orphanA, kept, orphanB],
                accountedFor: [kept, rowWithoutAlarm]
            ),
            [orphanA, orphanB]
        )
        XCTAssertEqual(
            ReminderScheduler.orphanedAlarmIDs(scheduled: [], accountedFor: [kept]),
            []
        )
    }

    /// A snoozed occurrence's alarm belongs to its row, so the orphan sweep
    /// keeps it while the row exists, and a cancel of the row removes it.
    ///
    /// Falsifier: drop the `snoozeAlarmID` clause from `orphanedAlarmIDs`, and
    /// the relaunch cancels a live snooze; drop the second `cancelAlarm` from
    /// `cancel(itemID:)`, and the last assertion fails.
    func testASnoozeAlarmIsKeptByItsRowAndCancelledWithIt() {
        let row = UUID()
        let snooze = ReminderScheduler.snoozeAlarmID(for: row)
        let orphan = UUID()
        XCTAssertEqual(
            ReminderScheduler.orphanedAlarmIDs(scheduled: [row, snooze, orphan], accountedFor: [row]),
            [orphan]
        )
        delivery.seedAlarm(row)
        delivery.seedAlarm(snooze)
        ReminderScheduler.cancel(itemID: row)
        XCTAssertTrue(
            delivery.scheduledAlarms.isDisjoint(with: [row, snooze]),
            "cancelling a row must cancel its series and its snooze"
        )
    }

    func testCompletedItemDoesNotKeepAReminderArmedAcrossRelaunch() async throws {
        let created = try await capture("Remind me to call the bank on Friday at 9am")
        let item = created.primaryItem
        let identifier = ReminderScheduler.notificationIdentifier(for: item.id)

        try repository.setCompleted(item, completed: true)
        // Kill before teardown ran: re-arm and relaunch.
        delivery.seedNotification(identifier)

        await relaunchAndDrain()

        XCTAssertFalse(
            delivery.pendingNotifications.contains(identifier),
            "A completed item must not survive relaunch with a live reminder"
        )
    }

    // MARK: - 3. Rapid interaction abuse

    func testTwentyRapidIdenticalSavesProduceOneThought() async throws {
        let createdAt = Date()
        for offset in 0..<20 {
            _ = try await capture(
                "Remember the studio door code is 4821",
                createdAt: createdAt.addingTimeInterval(Double(offset) / 40)
            )
        }

        XCTAssertEqual(try allSessions().count, 1, "Hammering save must not multiply the thought")
        XCTAssertEqual(try allItems().count, 1)
    }

    func testTwoNearlySimultaneousExternalIntentsProduceOneThought() async throws {
        let createdAt = Date()
        let first = try await capture("Remind me to move the car", source: .shortcut, createdAt: createdAt)
        let second = try await capture(
            "Remind me to move the car",
            source: .shortcut,
            createdAt: createdAt.addingTimeInterval(0.2)
        )

        XCTAssertTrue(first.createdNewCapture)
        XCTAssertFalse(second.createdNewCapture, "The second intent is the same thought arriving twice")
        XCTAssertEqual(try allSessions().count, 1)
    }

    func testADuplicateCaptureIsNeverChargedAgainstTheFreeAllowance() async throws {
        let createdAt = Date()
        _ = try await capture("Book the flights", source: .siri, createdAt: createdAt)
        let repeated = try await capture(
            "Book the flights",
            source: .siri,
            createdAt: createdAt.addingTimeInterval(0.3)
        )

        XCTAssertFalse(
            repeated.createdNewCapture,
            "A charged capture is gated on createdNewCapture; a duplicate must not pass it"
        )
    }

    func testRapidDistinctCapturesAllSurvive() async throws {
        let createdAt = Date()
        let texts = (0..<12).map { "Distinct thought number \($0)" }
        for (offset, text) in texts.enumerated() {
            _ = try await capture(text, createdAt: createdAt.addingTimeInterval(Double(offset) / 20))
        }

        XCTAssertEqual(try allSessions().count, texts.count, "Speed must never cost a thought")
        XCTAssertEqual(try allItems().count, texts.count)
    }

    func testNormalCapturesLeaveNoSessionWithoutItems() async throws {
        _ = try await capture("Buy milk")
        _ = try await capture("Call the dentist on Monday")
        _ = try await capture("The wifi password is orangehill")

        let orphans = try allSessions().filter { $0.items.isEmpty }
        XCTAssertTrue(orphans.isEmpty, "Every stored capture should own at least one row")
    }

    // MARK: - 7. Concurrency and interleaved teardown

    /// Two routes delivering the same words at the same moment. Deduplication is
    /// scoped per source, so this documents what actually happens when Siri and
    /// the in-app button both land.
    func testTheSameWordsArrivingByTwoRoutesAtOnce() async throws {
        let createdAt = Date()
        _ = try await capture("Remind me to move the car", source: .siri, createdAt: createdAt)
        _ = try await capture(
            "Remind me to move the car",
            source: .inAppVoice,
            createdAt: createdAt.addingTimeInterval(0.2)
        )

        let sessions = try allSessions()
        XCTAssertEqual(
            sessions.count,
            2,
            "Deduplication is per capture source, so two routes produce two rows"
        )
        XCTAssertTrue(
            sessions.allSatisfy { !$0.items.isEmpty },
            "Whatever the count, neither route may leave an empty session"
        )
    }

    func testTwoShareSheetDeliveriesOfTheSameThoughtCollapse() async throws {
        let createdAt = Date()
        let first = try await capture("Read the Ostrom paper", source: .shareSheet, createdAt: createdAt)
        let second = try await capture(
            "Read the Ostrom paper",
            source: .shareSheet,
            createdAt: createdAt.addingTimeInterval(1)
        )

        XCTAssertTrue(first.createdNewCapture)
        XCTAssertFalse(second.createdNewCapture, "The same share delivered twice is one thought")
        XCTAssertEqual(try allSessions().count, 1)
    }

    /// Cancelling one reminder while another item's teardown is still draining.
    /// The tail is serial, so the risk is one pass overwriting the other's work.
    func testCancellingWhileAnotherTeardownIsStillDrainingLeavesBothCorrect() async throws {
        let keep = try await capture("Remind me to call the bank on Friday at 9am")
        let drop = try await capture("Remind me about the dentist on Friday at 10am")
        let keepIdentifier = ReminderScheduler.notificationIdentifier(for: keep.primaryItem.id)
        let dropIdentifier = ReminderScheduler.notificationIdentifier(for: drop.primaryItem.id)
        delivery.seedNotification(keepIdentifier)
        delivery.seedNotification(dropIdentifier)

        // Two teardowns issued back to back without letting the first settle.
        try repository.delete(drop.primaryItem)
        _ = try await capture(
            "Cancel the call the bank reminder",
            createdAt: Date().addingTimeInterval(30)
        )
        await drainScheduler()

        XCTAssertFalse(delivery.pendingNotifications.contains(dropIdentifier))
        XCTAssertFalse(delivery.pendingNotifications.contains(keepIdentifier))
        XCTAssertTrue(try liveItems().isEmpty, "Both items were removed; neither may survive")
    }

    func testCompletingAndCancellingTheSameItemDoesNotDoubleApply() async throws {
        let created = try await capture("Remind me to send the invoice on Monday")
        let itemID = created.primaryItem.id

        try repository.setCompleted(created.primaryItem, completed: true)
        let cancellation = try await capture(
            "Cancel the send the invoice reminder",
            createdAt: Date().addingTimeInterval(30)
        )
        await drainScheduler()

        // Completed work is not an active target, so the cancellation acts on
        // that item or finds nothing — never acts on it a second time.
        if case let .performed(_, performedID, _) = cancellation.operationOutcome {
            XCTAssertEqual(performedID, itemID, "A cancellation must not reach past its target")
        }
        XCTAssertLessThanOrEqual(
            try allItems().filter { $0.id == itemID }.count,
            1,
            "The item must exist zero or one times, never twice"
        )
        XCTAssertTrue(
            try liveItems().allSatisfy { $0.id != itemID },
            "Completed then cancelled must leave nothing outstanding"
        )
    }

    func testRelaunchingDuringAnUnsettledTeardownStillConverges() async throws {
        let created = try await capture("Remind me to renew the insurance on Friday at 8am")
        let identifier = ReminderScheduler.notificationIdentifier(for: created.primaryItem.id)
        delivery.seedNotification(identifier)

        try repository.delete(created.primaryItem)
        // Killed before the tail drained: relaunch is the second chance.
        await relaunchAndDrain()

        XCTAssertFalse(
            delivery.pendingNotifications.contains(identifier),
            "A teardown interrupted by a kill must be finished by the next launch"
        )
    }

    // MARK: - 8. Daylight saving

    func testReminderDoesNotDriftAcrossTheSpringForwardTransition() async throws {
        defer { restoreTimeZone() }
        setTimeZone("America/Toronto")

        let created = try await capture("Remind me on March 9th at 9am to call the clinic")
        let itemID = created.primaryItem.id
        let originalDue = created.primaryItem.dueDate

        relaunch()
        relaunch()

        let item = try XCTUnwrap(try allItems().first { $0.id == itemID })
        XCTAssertEqual(item.dueDate, originalDue, "A DST boundary must not move a stored reminder")
    }

    func testReminderDoesNotDriftAcrossTheFallBackTransition() async throws {
        defer { restoreTimeZone() }
        setTimeZone("America/Toronto")

        let created = try await capture("Remind me on November 2nd at 1:30am to check the server")
        let itemID = created.primaryItem.id
        let originalDue = created.primaryItem.dueDate

        relaunch()
        relaunch()

        let item = try XCTUnwrap(try allItems().first { $0.id == itemID })
        XCTAssertEqual(item.dueDate, originalDue)
    }

    /// A clock moved by hand is the harshest version: nothing about the stored
    /// intent changed, only what "now" means.
    func testMovingTheClockDoesNotRewriteStoredIntents() async throws {
        let created = try await capture("Remind me tomorrow at 7am to leave for the airport")
        let itemID = created.primaryItem.id
        let originalDue = created.primaryItem.dueDate
        let originalIntent = created.primaryItem.temporalIntent

        // Recovery and the temporal backfill both rerun on every launch and both
        // read the current date. Neither may revisit a row that has an answer.
        for _ in 0..<4 { relaunch() }

        let item = try XCTUnwrap(try allItems().first { $0.id == itemID })
        XCTAssertEqual(item.dueDate, originalDue)
        XCTAssertEqual(item.temporalIntent, originalIntent)
    }

    // MARK: - 4. Interrupted draft recovery

    /// Seeds the checkpoint a killed capture leaves behind: words written down,
    /// never persisted as a thought, old enough for recovery to claim.
    @discardableResult
    private func seedRecoverableDraft(
        _ transcript: String,
        source: CaptureSource = .inAppVoice,
        startedAt: Date = Date().addingTimeInterval(-120)
    ) -> CaptureDraftStore.Draft {
        let draft = CaptureDraftStore.begin(source: source, at: startedAt)
        CaptureDraftStore.update(id: draft.id, transcript: transcript, at: startedAt)
        return CaptureDraftStore.draft(id: draft.id) ?? draft
    }

    func testInterruptedDraftIsRecoveredOnceAndThenReleased() throws {
        seedRecoverableDraft("Order the replacement filter")

        relaunch()

        XCTAssertEqual(try allItems().count, 1)
        XCTAssertEqual(try allItems()[0].originalTextSegment, "Order the replacement filter")
        XCTAssertNil(
            CaptureDraftStore.recoverable(),
            "A recovered draft must be released, or it is recovered again forever"
        )

        relaunch()
        XCTAssertEqual(try allItems().count, 1, "Recovery must not run twice on the same words")
    }

    /// A draft whose words are a cancellation has nothing to hand back. The
    /// question is what happens to the checkpoint afterwards: a draft that is
    /// never released is replayed at every launch.
    func testInterruptedCancellationDraftIsReleasedRatherThanReplayedForever() async throws {
        _ = try await capture("Remind me about the dentist on Friday")
        seedRecoverableDraft("Cancel the dentist reminder")

        relaunch()
        let sessionsAfterFirst = try allSessions().count

        relaunch()
        relaunch()

        XCTAssertNil(
            CaptureDraftStore.recoverable(),
            "An operation draft that cannot produce a row must still be released"
        )
        XCTAssertEqual(
            try allSessions().count,
            sessionsAfterFirst,
            "Replaying the draft each launch accumulates empty capture sessions"
        )
    }

    func testInterruptedRetractionDraftIsReleasedRatherThanReplayedForever() throws {
        seedRecoverableDraft("Actually never mind, forget that")

        relaunch()
        let sessionsAfterFirst = try allSessions().count
        relaunch()
        relaunch()

        XCTAssertNil(CaptureDraftStore.recoverable())
        XCTAssertEqual(try allSessions().count, sessionsAfterFirst)
        XCTAssertTrue(try liveItems().isEmpty, "A withdrawn capture produces nothing")
    }

    func testSeveralInterruptedDraftsAreAllRecovered() throws {
        let base = Date().addingTimeInterval(-600)
        seedRecoverableDraft("Book the dog groomer", startedAt: base)
        seedRecoverableDraft("Renew the parking permit", startedAt: base.addingTimeInterval(60))
        seedRecoverableDraft("Send Priya the address", startedAt: base.addingTimeInterval(120))

        relaunch()

        let segments = Set(try allItems().map(\.originalTextSegment))
        XCTAssertEqual(segments.count, 3, "Every interrupted draft must come back: \(segments)")
        XCTAssertNil(CaptureDraftStore.recoverable())
    }

    /// An audio recovery that stopped partway keeps its words beside the
    /// recording. The launch replay of text checkpoints must not save those
    /// words as the whole capture and release the recording that holds the
    /// rest. Falsifier: `recoverable()` claiming a draft that still has audio
    /// saves one item here and deletes the file.
    func testAPartlyRecoveredRecordingIsNotReplayedAsAWholeCapture() throws {
        let startedAt = Date().addingTimeInterval(-600)
        let draft = CaptureDraftStore.begin(source: .inAppVoice, at: startedAt)
        let audioURL = try XCTUnwrap(CaptureDraftStore.prepareAudioURL(for: draft))
        try Data(repeating: 0x1, count: 1_024).write(to: audioURL, options: .atomic)
        CaptureDraftStore.markFailed(id: draft.id, message: "Timed out", kind: .timedOut)
        // Written old, so the checkpoint's age is not what protects it.
        CaptureDraftStore.keepRecoveredWords(
            "Renew the parking permit and",
            id: draft.id,
            at: startedAt
        )

        relaunch()

        XCTAssertTrue(try allItems().isEmpty)
        XCTAssertEqual(
            CaptureDraftStore.draft(id: draft.id)?.transcript,
            "Renew the parking permit and"
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: audioURL.path))
    }

    // MARK: - 4b. A handoff that committed is not an interruption

    /// What `CaptureView.save` leaves behind when it is killed after recording
    /// the handoff: the draft carries the words and the ID of the session it
    /// was about to commit. Whether that session exists is up to the caller.
    private func seedHandedOffDraft(
        _ transcript: String,
        source: CaptureSource,
        startedAt: Date = Date().addingTimeInterval(-120)
    ) -> (draft: CaptureDraftStore.Draft, sessionID: UUID) {
        let draft = seedRecoverableDraft(transcript, source: source, startedAt: startedAt)
        let sessionID = UUID()
        CaptureDraftStore.recordHandoff(
            id: draft.id,
            transcript: transcript,
            sessionID: sessionID,
            at: startedAt
        )
        return (CaptureDraftStore.draft(id: draft.id) ?? draft, sessionID)
    }

    private func writeRecording(for draft: CaptureDraftStore.Draft) throws -> URL {
        let audioURL = try XCTUnwrap(CaptureDraftStore.prepareAudioURL(for: draft))
        try Data(repeating: 0x1, count: 1_024).write(to: audioURL, options: .atomic)
        return audioURL
    }

    /// Audit D3a. A practice capture is drafted as `.inAppText` but saved as
    /// `.tutorial`, so source-scoped dedupe never matched and a kill after the
    /// commit turned the practice sentence into a real capture with a real
    /// reminder, on a row tutorial cleanup does not delete.
    ///
    /// Falsifier: make `releaseHandedOffCaptureDrafts` release nothing (or stop
    /// `recordHandoff` storing the ID) and `recoverInterruptedCaptureDraft`
    /// replays the draft: two sessions, the second one `.inAppText`.
    func testAKilledPracticeSaveIsNotReplayedAsARealCapture() throws {
        let text = "Tomorrow at 9, ask Maya about the proposal."
        let (draft, sessionID) = seedHandedOffDraft(text, source: .inAppText)
        try killAfterRawPersistence(
            text,
            source: .tutorial,
            createdAt: draft.startedAt,
            id: sessionID
        )

        relaunch()

        let sessions = try allSessions()
        XCTAssertEqual(sessions.count, 1, "A committed practice save must not be replayed")
        XCTAssertEqual(sessions.first?.id, sessionID)
        XCTAssertEqual(sessions.first?.captureSource, .tutorial)
        XCTAssertNil(CaptureDraftStore.draft(id: draft.id), "A committed handoff releases its draft")
        XCTAssertNil(CaptureDraftStore.recoverable())
    }

    /// Audit D3b. A voice draft is replayed from its recording, not its words:
    /// `RootView.recoverInterruptedAudioDrafts` re-transcribes every draft in
    /// `recoverableAudioDrafts()`, and any word the second recognizer hears
    /// differently defeats dedupe. The fix is that a committed draft is no
    /// longer in that list by the time the audio pass reads it, and its
    /// recording is gone because its words are durable. The audio pass itself
    /// needs a recognizer and is not run here.
    ///
    /// Falsifier: make `releaseHandedOffCaptureDrafts` release nothing and the
    /// draft is still listed with its recording, so the audio pass would
    /// re-transcribe it into a second session.
    func testAKilledVoiceSaveIsNotLeftForTheAudioPassToReplay() throws {
        let text = "Call the landlord about the lease"
        let (draft, sessionID) = seedHandedOffDraft(text, source: .inAppVoice)
        let audioURL = try writeRecording(for: draft)
        XCTAssertEqual(
            CaptureDraftStore.recoverableAudioDrafts(minimumAge: 0).map(\.id),
            [draft.id],
            "The seeded recording must be one the audio pass would replay"
        )
        try killAfterRawPersistence(
            text,
            source: .inAppVoice,
            createdAt: draft.startedAt,
            id: sessionID
        )

        relaunch()

        XCTAssertTrue(CaptureDraftStore.recoverableAudioDrafts(minimumAge: 0).isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: audioURL.path))
        let sessions = try allSessions()
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions.first?.originalTranscription, text)
    }

    /// The control. A kill after the handoff was recorded but before the
    /// session committed leaves an ID the store does not hold, and those words
    /// exist nowhere but the draft. It has to be replayed exactly as an
    /// unmarked draft is.
    ///
    /// Falsifier: let `releaseHandedOffCaptureDrafts` clear every handed-off
    /// draft without looking its session up, and this thought is lost: no
    /// session at all.
    func testAHandoffThatNeverCommittedIsStillReplayed() throws {
        let text = "Renew the passport before March"
        let (draft, sessionID) = seedHandedOffDraft(text, source: .inAppText)

        relaunch()

        let sessions = try allSessions()
        XCTAssertEqual(sessions.count, 1, "Uncommitted words must come back")
        XCTAssertEqual(sessions.first?.originalTranscription, text)
        XCTAssertNotEqual(sessions.first?.id, sessionID)
        XCTAssertNil(CaptureDraftStore.draft(id: draft.id))
    }

    /// The control for the recording. An uncommitted voice handoff keeps its
    /// recording and stays listed for the audio pass.
    ///
    /// Falsifier: the same unconditional release deletes the recording, the
    /// only copy of words that never reached the store.
    func testAHandoffThatNeverCommittedKeepsItsRecording() throws {
        let (draft, _) = seedHandedOffDraft(
            "Book the car in for its service",
            source: .inAppVoice
        )
        let audioURL = try writeRecording(for: draft)

        relaunch()

        XCTAssertTrue(FileManager.default.fileExists(atPath: audioURL.path))
        XCTAssertEqual(
            CaptureDraftStore.recoverableAudioDrafts(minimumAge: 0).map(\.id),
            [draft.id]
        )
        XCTAssertTrue(try allSessions().isEmpty, "The text pass leaves audio drafts to the audio pass")
    }

    /// A handoff describes the words it was recorded with. Words checkpointed
    /// afterwards have reached no session, so the mark has to go with them.
    ///
    /// Falsifier: stop `CaptureDraftStore.update` clearing the ID when the
    /// words change, and a committed session vouches for words it never held:
    /// the new words are released instead of replayed.
    func testCheckpointingNewWordsWithdrawsTheHandoff() throws {
        let (draft, sessionID) = seedHandedOffDraft(
            "Text Jordan the gate code",
            source: .inAppText
        )

        CaptureDraftStore.update(id: draft.id, transcript: "Text  Jordan the gate code ")
        XCTAssertEqual(
            CaptureDraftStore.draft(id: draft.id)?.handedOffSessionID,
            sessionID,
            "The same words, differently spaced, are still the handed-off words"
        )

        CaptureDraftStore.update(id: draft.id, transcript: "Text Jordan the new gate code")
        XCTAssertNil(CaptureDraftStore.draft(id: draft.id)?.handedOffSessionID)
    }

    /// The same rule for late audio recovery, which writes its words onto the
    /// draft directly rather than through `update`. Both branches are in this
    /// tree, so the rule has to hold for both writers.
    ///
    /// Falsifier: drop the withdrawal from `leaveRecoveredWordsForToday` and a
    /// stale handoff whose session did commit makes the next launch release
    /// the draft and its recording, taking the newer words with it.
    func testLeavingDifferentRecoveredWordsWithdrawsTheHandoff() throws {
        let (draft, sessionID) = seedHandedOffDraft(
            "Text Jordan the gate code",
            source: .inAppVoice
        )

        CaptureDraftStore.leaveRecoveredWordsForToday(id: draft.id, transcript: "Text  Jordan the gate code ")
        XCTAssertEqual(CaptureDraftStore.draft(id: draft.id)?.handedOffSessionID, sessionID)

        CaptureDraftStore.leaveRecoveredWordsForToday(id: draft.id, transcript: "Text Jordan the new gate code")
        XCTAssertNil(CaptureDraftStore.draft(id: draft.id)?.handedOffSessionID)
    }

    /// `CaptureSession.id` is unique, and SwiftData turns a second insert with
    /// the same unique value into an update. A reused handoff ID must never
    /// become a way to rewrite a person's original words.
    ///
    /// Falsifier: remove the `committedSession` guard at the top of the
    /// session-ID `createCaptureResult`, and the second call either rewrites
    /// the stored transcript or throws on save.
    func testAReusedSessionIDNeverRewritesTheOriginalWords() async throws {
        let sessionID = UUID()
        _ = try await repository.createCaptureResult(
            text: "Water the tomatoes tonight",
            source: .inAppText,
            createdAt: .now,
            schedulesReminders: false,
            performance: nil,
            sessionID: sessionID
        )

        let second = try await repository.createCaptureResult(
            text: "Something else entirely",
            source: .inAppText,
            createdAt: .now,
            schedulesReminders: false,
            performance: nil,
            sessionID: sessionID
        )

        XCTAssertFalse(second.createdNewCapture)
        let sessions = try allSessions()
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions.first?.originalTranscription, "Water the tomatoes tonight")
    }

    // MARK: - 4c. The saves that hand off through `CaptureDraftStore.handOff`

    /// Today's typed recovery and the Save Thought intent's writer both save
    /// through `handOff`, and both are private to a view or to the intent's
    /// file, so this is the lowest seam either has. The commit closure is where the repository call sits in
    /// production; it reads the draft first, which is the moment a kill would
    /// have to find the handoff already written.
    private func commitThroughHandOff(
        draftID: UUID,
        words: String,
        source: CaptureSource
    ) async throws -> (result: CaptureCreationResult, sessionID: UUID) {
        var committedID: UUID?
        let result = try await CaptureDraftStore.handOff(
            draftID: draftID,
            transcript: words
        ) { (sessionID: UUID) async throws -> CaptureCreationResult in
            let before = CaptureDraftStore.draft(id: draftID)
            XCTAssertEqual(
                before?.handedOffSessionID,
                sessionID,
                "The draft must carry the handoff before the commit starts"
            )
            XCTAssertEqual(before?.transcript, words)
            committedID = sessionID
            return try await repository.createCaptureResult(
                text: words,
                source: source,
                createdAt: before?.startedAt ?? .now,
                schedulesReminders: false,
                performance: nil,
                sessionID: sessionID
            )
        }
        return (result, try XCTUnwrap(committedID))
    }

    /// F1, the practice case. `ExternalCaptureWriter` commits a practice
    /// capture as `.tutorial` from a `.shortcut` draft, and source-scoped
    /// dedupe can never match that pair. Killed between the commit and
    /// `CaptureDraftStore.clear`, the next launch's audio pass would
    /// re-transcribe the recording into a second, real capture. The one caller
    /// that passes the writer a draft is compiled out today (the shipped
    /// hardware route is `CaptureView.save`, pinned by
    /// `testAKilledPracticeSaveIsNotReplayedAsARealCapture`); this pins the
    /// helper that route would use, with the mismatched sources.
    ///
    /// Falsifier: drop the `recordHandoff` call from `handOff`, or move it
    /// after `commit`, and the in-closure assertion fails and the draft
    /// survives the relaunch with its recording, listed for the audio pass.
    /// Making the release compare the draft's source with the session's would
    /// fail the same way.
    func testAKilledIntentPracticeSaveIsReleasedDespiteItsDifferentSource() async throws {
        let startedAt = Date().addingTimeInterval(-120)
        let draft = CaptureDraftStore.begin(at: startedAt)
        XCTAssertEqual(draft.captureSource, .shortcut)
        let audioURL = try writeRecording(for: draft)
        let words = "Tomorrow at 9, ask Maya about the proposal."
        CaptureDraftStore.update(id: draft.id, transcript: words, at: startedAt)

        let (result, sessionID) = try await commitThroughHandOff(
            draftID: draft.id,
            words: words,
            source: .tutorial
        )
        XCTAssertEqual(result.session.id, sessionID)
        XCTAssertEqual(result.session.captureSource, .tutorial)
        // Killed here: the intent's `CaptureDraftStore.clear(id:)` never ran.
        XCTAssertNotNil(CaptureDraftStore.draft(id: draft.id))

        relaunch()

        XCTAssertNil(CaptureDraftStore.draft(id: draft.id), "A committed handoff releases its draft")
        XCTAssertTrue(CaptureDraftStore.recoverableAudioDrafts(minimumAge: 0).isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: audioURL.path))
        let sessions = try allSessions()
        XCTAssertEqual(sessions.count, 1, "A committed practice save must not be replayed")
        XCTAssertEqual(sessions.first?.id, sessionID)
        XCTAssertEqual(sessions.first?.captureSource, .tutorial)
    }

    /// F2. Today's typed recovery saves the person's own retyping of a
    /// recording that did not transcribe well, then deletes the recording. A
    /// kill between the two left the recording for the audio pass, whose
    /// re-transcription is by the premise of that screen different from the
    /// typed words, so dedupe would not have caught it.
    ///
    /// Falsifier: drop the `recordHandoff` call from `handOff` (or save the
    /// typed words with the five-argument `createCaptureResult` again) and the
    /// voice draft is still listed with its recording after the relaunch.
    func testAKilledTypedRecoveryIsNotLeftForTheAudioPassToReplay() async throws {
        let startedAt = Date().addingTimeInterval(-600)
        let draft = CaptureDraftStore.begin(source: .inAppVoice, at: startedAt)
        let audioURL = try writeRecording(for: draft)
        CaptureDraftStore.markFailed(id: draft.id, message: "No speech detected")
        let typed = "Pick up the dry cleaning on Thursday"

        let (_, sessionID) = try await commitThroughHandOff(
            draftID: draft.id,
            words: typed,
            source: .inAppText
        )
        // Killed here: `CaptureDraftStore.deleteRecording(id:)` never ran.
        XCTAssertEqual(
            CaptureDraftStore.recoverableAudioDrafts(minimumAge: 0).map(\.id),
            [draft.id],
            "The seeded recording must be one the audio pass would replay"
        )

        relaunch()

        XCTAssertTrue(CaptureDraftStore.recoverableAudioDrafts(minimumAge: 0).isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: audioURL.path))
        let sessions = try allSessions()
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions.first?.id, sessionID)
        XCTAssertEqual(sessions.first?.originalTranscription, typed)
    }

    /// The control for both. A commit that throws before anything reaches the
    /// store leaves the handoff naming a session that does not exist, so the
    /// release keeps the draft, its words and its recording, and the error
    /// reaches the caller, which is what lets typed recovery say nothing was
    /// removed.
    ///
    /// Falsifier: have `handOff` swallow the error, or clear the draft itself,
    /// and the words that never reached the store are gone.
    func testAHandOffWhoseCommitThrowsKeepsTheDraftForReplay() async throws {
        let draft = CaptureDraftStore.begin(source: .inAppVoice)
        let audioURL = try writeRecording(for: draft)
        let typed = "Pick up the dry cleaning on Thursday"

        do {
            _ = try await CaptureDraftStore.handOff(
                draftID: draft.id,
                transcript: typed
            ) { (_: UUID) async throws -> CaptureCreationResult in
                throw RepositoryError.storageUnavailable
            }
            XCTFail("The commit's error must reach the caller")
        } catch {}

        repository.releaseHandedOffCaptureDrafts()

        let kept = try XCTUnwrap(CaptureDraftStore.draft(id: draft.id))
        XCTAssertNotNil(kept.handedOffSessionID)
        XCTAssertEqual(kept.transcript, typed)
        XCTAssertTrue(FileManager.default.fileExists(atPath: audioURL.path))
        XCTAssertTrue(try allSessions().isEmpty)
    }

    // MARK: - 4d. A voice capture that began as typing

    /// Audit D6 (a). The person types a few words, taps "Speak instead" and
    /// speaks. The capture screen keeps its typed draft: `ensureDraft` calls
    /// `updateSource(.inAppVoice)` on it, and `startVoiceCapture` then asks
    /// that draft for its recording file. A call or a kill ends the recording
    /// before any spoken words are checkpointed.
    ///
    /// Falsifier: stop `updateSource` giving the draft a recording file.
    /// `prepareAudioURL` returns nil, as it did before this fix, so the
    /// recognizer records nothing to protect, the screen falls back to typing,
    /// and the spoken words are gone; `writeRecording` fails here on that nil.
    func testAVoiceCaptureStartedFromATypedDraftIsRecoveredFromItsRecording() throws {
        let startedAt = Date().addingTimeInterval(-120)
        let typed = seedRecoverableDraft("Call Dana", source: .inAppText, startedAt: startedAt)
        XCTAssertNil(CaptureDraftStore.audioURL(for: typed))

        CaptureDraftStore.updateSource(
            id: typed.id,
            source: .inAppVoice,
            typedBeforeSpeaking: "Call Dana",
            at: startedAt.addingTimeInterval(5)
        )
        let speaking = try XCTUnwrap(CaptureDraftStore.draft(id: typed.id))
        let audioURL = try writeRecording(for: speaking)
        // The deterministic name, so `deleteRecording` removes it by name too.
        XCTAssertEqual(audioURL.lastPathComponent, "\(typed.id.uuidString).caf")
        // What the screen's `hasRecoverableActiveAudio` reads when the
        // recognizer fails: recovery, not the typing fallback.
        XCTAssertTrue(CaptureDraftStore.hasRecoveryAudio(for: speaking))

        relaunch()

        XCTAssertEqual(
            CaptureDraftStore.recoverableAudioDrafts(minimumAge: 0).map(\.id),
            [typed.id],
            "Today and the launch audio pass must offer the recording"
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: audioURL.path))
        XCTAssertTrue(
            try allSessions().isEmpty,
            "The text pass must leave a draft with a recording to the audio pass, or one thought is saved twice"
        )
    }

    /// Audit D6 (b). A typed save that asks for clarification, then "Try
    /// saying it again". The save clears its draft and empties the editor, and
    /// the empty editor's checkpoint used to begin a new typed draft 220 ms
    /// later. The retry reused that draft: no recording, and the save's time
    /// as the retry's start.
    ///
    /// Falsifier: let `shouldCheckpoint` begin a draft for empty text (return
    /// true for `("", false)`) and the first assertion fails. Revert
    /// `updateSource` and the retry that does land on an empty typed draft has
    /// no recording file, so `writeRecording` fails on the nil URL.
    func testTryingAgainAfterATypedSaveRecordsIntoAProtectedDraft() throws {
        XCTAssertFalse(CaptureDraftStore.shouldCheckpoint("", hasActiveDraft: false))
        XCTAssertFalse(CaptureDraftStore.shouldCheckpoint(" \n ", hasActiveDraft: false))

        // With no draft left behind, the retry's `ensureDraft` begins a voice one.
        let retry = CaptureDraftStore.begin(source: .inAppVoice)
        let retryURL = try writeRecording(for: retry)

        // And a retry that does reuse an empty typed draft is protected alike.
        let reused = CaptureDraftStore.begin(source: .inAppText)
        CaptureDraftStore.updateSource(id: reused.id, source: .inAppVoice)
        let reusedURL = try writeRecording(
            for: try XCTUnwrap(CaptureDraftStore.draft(id: reused.id))
        )

        relaunch()

        XCTAssertEqual(
            Set(CaptureDraftStore.recoverableAudioDrafts(minimumAge: 0).map(\.id)),
            [retry.id, reused.id],
            "An empty transcript beside a recording is still a capture to recover"
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: retryURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: reusedURL.path))
    }

    /// The unchanged side. A draft that is only ever typed gets no recording
    /// file, however often its source is set, and a relaunch replays its words
    /// once. Typing still checkpoints: words with no draft begin one, and
    /// emptying an existing draft still writes the empty text to it.
    ///
    /// Falsifier: drop the `recordsProtectedAudio` condition from
    /// `updateSource`, giving every source change a file, and the typed draft
    /// gains a recording name. Make `shouldCheckpoint` refuse empty text for an
    /// existing draft and erased words would stay on the draft.
    func testATypedOnlyDraftStaysTextOnlyAndIsReplayedOnce() throws {
        XCTAssertTrue(CaptureDraftStore.shouldCheckpoint("Pick", hasActiveDraft: false))
        XCTAssertTrue(CaptureDraftStore.shouldCheckpoint("", hasActiveDraft: true))

        let typed = seedRecoverableDraft("Pick up the dry cleaning", source: .inAppText)
        CaptureDraftStore.updateSource(id: typed.id, source: .inAppText, at: typed.startedAt)
        let stored = try XCTUnwrap(CaptureDraftStore.draft(id: typed.id))
        XCTAssertNil(CaptureDraftStore.audioURL(for: stored))
        XCTAssertNil(try CaptureDraftStore.prepareAudioURL(for: stored))

        relaunch()

        XCTAssertEqual(try allSessions().map(\.originalTranscription), ["Pick up the dry cleaning"])
        XCTAssertNil(CaptureDraftStore.draft(id: typed.id))
        XCTAssertTrue(CaptureDraftStore.recoverableAudioDrafts(minimumAge: 0).isEmpty)

        relaunch()
        XCTAssertEqual(try allSessions().count, 1, "Recovery must not run twice on the same words")
    }

    /// "Type instead" in the middle of a recording sets the draft's source to
    /// typing. The recording it already made stays protected.
    ///
    /// Falsifier: have `updateSource` clear the file name when the source
    /// becomes `.inAppText` and the recording is no longer listed, though the
    /// file is still on disk and may hold the only copy of the words.
    func testSwitchingASpokenDraftToTypingKeepsItsRecording() throws {
        let draft = CaptureDraftStore.begin(source: .inAppVoice)
        let audioURL = try writeRecording(for: draft)

        CaptureDraftStore.updateSource(id: draft.id, source: .inAppText)

        let typing = try XCTUnwrap(CaptureDraftStore.draft(id: draft.id))
        XCTAssertEqual(CaptureDraftStore.audioURL(for: typing), audioURL)
        relaunch()
        XCTAssertEqual(
            CaptureDraftStore.recoverableAudioDrafts(minimumAge: 0).map(\.id),
            [draft.id]
        )
    }

    // MARK: - 4e. Words typed before speaking are kept beside the recording

    /// Recognition supplied by the test, so no recognizer is needed.
    private func recognized(_ words: String) -> (URL) async throws -> String {
        { _ in words }
    }

    /// What the capture screen leaves when the person types, taps "Speak
    /// instead", says a few words and the app is killed: a draft that began as
    /// typing, moved to voice with the editor's words set aside, a spoken
    /// checkpoint joined after them, and a recording.
    private func seedTypedThenSpokenDraft(
        typed: String,
        spokenSoFar: String,
        startedAt: Date = Date().addingTimeInterval(-120)
    ) throws -> (draft: CaptureDraftStore.Draft, audioURL: URL) {
        let draft = seedRecoverableDraft(typed, source: .inAppText, startedAt: startedAt)
        CaptureDraftStore.updateSource(
            id: draft.id,
            source: .inAppVoice,
            typedBeforeSpeaking: typed,
            at: startedAt.addingTimeInterval(5)
        )
        CaptureDraftStore.update(
            id: draft.id,
            transcript: CaptureDraftStore.joined(typedBeforeSpeaking: typed, spoken: spokenSoFar),
            at: startedAt.addingTimeInterval(8)
        )
        let stored = try XCTUnwrap(CaptureDraftStore.draft(id: draft.id))
        return (stored, try writeRecording(for: stored))
    }

    /// Typed words, then speech, then a kill, then the launch audio pass. The
    /// capture must hold both, typed first, in one session.
    ///
    /// Falsifier: make `CaptureAudioRecovery.transcribe` return the
    /// recording's words alone, as the D6 fix's first commit did, and the
    /// session holds "about the invoice tomorrow" without "Call Dana". Drop
    /// the `typedBeforeSpeaking` write from `updateSource` and the draft
    /// forgets the typed words the moment it becomes a voice draft.
    func testTypedWordsBeforeSpeakingSurviveAKillAndARecoveredRecording() async throws {
        let (seeded, _) = try seedTypedThenSpokenDraft(
            typed: "Call Dana",
            spokenSoFar: "about the"
        )
        XCTAssertEqual(seeded.typedBeforeSpeaking, "Call Dana")
        XCTAssertEqual(seeded.transcript, "Call Dana about the")

        relaunch()
        let draft = try XCTUnwrap(CaptureDraftStore.draft(id: seeded.id))
        XCTAssertEqual(CaptureDraftStore.recoverableAudioDrafts(minimumAge: 0).map(\.id), [draft.id])

        // The launch audio pass: read the recording, hand off, commit, clear.
        let words = try await CaptureAudioRecovery.transcribe(
            draft,
            reading: recognized("about the invoice tomorrow")
        )
        XCTAssertEqual(words, "Call Dana about the invoice tomorrow")
        _ = try await commitThroughHandOff(draftID: draft.id, words: words, source: draft.captureSource)
        CaptureDraftStore.clear(id: draft.id)

        XCTAssertEqual(
            try allSessions().map(\.originalTranscription),
            ["Call Dana about the invoice tomorrow"],
            "The original transcript is what was typed and what was said, in that order"
        )
        relaunch()
        XCTAssertEqual(try allSessions().count, 1)
    }

    /// The same draft whose recording the recognizer cannot read. The typed
    /// words stay with the listed recording, Type it starts from them, and
    /// deleting the recording saves them instead of deleting them with it.
    ///
    /// Falsifier: have `deleteRecordingKeepingTypedWords` delete as
    /// `deleteRecording` does and nothing is left to save: no kept draft, and
    /// no session after the relaunch. Have `typeInsteadStartingText` return
    /// "" and a typed reconstruction, which deletes the recording, drops them.
    func testTypedWordsBeforeSpeakingSurviveARecordingThatCannotBeRead() async throws {
        let (draft, audioURL) = try seedTypedThenSpokenDraft(typed: "Call Dana", spokenSoFar: "")
        let noSpeech = NSError(
            domain: "kAFAssistantErrorDomain",
            code: 1110,
            userInfo: [NSLocalizedDescriptionKey: "No speech detected"]
        )

        do {
            _ = try await CaptureAudioRecovery.transcribe(draft, reading: { _ in throw noSpeech })
            XCTFail("The recognizer's failure must reach the caller")
        } catch {
            CaptureDraftStore.markFailed(id: draft.id, error: error)
        }

        let failed = try XCTUnwrap(CaptureDraftStore.draft(id: draft.id))
        XCTAssertEqual(failed.recoveryFailureKind, .noSpeechDetected)
        XCTAssertEqual(failed.transcript, "Call Dana")
        XCTAssertEqual(CaptureDraftStore.recoverableAudioDrafts(minimumAge: 0).map(\.id), [draft.id])
        XCTAssertEqual(CaptureRecoveryPresentation.typeInsteadStartingText(for: failed), "Call Dana")
        XCTAssertTrue(CaptureRecoveryPresentation.keepsTypedWordsOnDelete(failed))

        let kept = try XCTUnwrap(CaptureDraftStore.deleteRecordingKeepingTypedWords(
            id: draft.id,
            at: Date().addingTimeInterval(-60)
        ))
        XCTAssertFalse(FileManager.default.fileExists(atPath: audioURL.path))
        XCTAssertTrue(CaptureDraftStore.recoverableAudioDrafts(minimumAge: 0).isEmpty)
        XCTAssertEqual(kept.transcript, "Call Dana")
        XCTAssertNil(CaptureDraftStore.audioURL(for: kept))

        // Today saves the kept words at once; if it cannot, the launch text
        // pass does. This is the second.
        relaunch()
        XCTAssertEqual(try allSessions().map(\.originalTranscription), ["Call Dana"])
        XCTAssertNil(CaptureDraftStore.draft(id: kept.id))
    }

    /// Typed, Speak instead, and a kill before the recording holds any audio:
    /// permission prompts, model preparation and the recognizer's start all
    /// come before the first buffer lands. The draft intends a recording but
    /// has none the audio pass can read, so the typed words are the whole
    /// capture and the text pass is the only one that can save them.
    ///
    /// This is why the text pass tells a live recording from a draft it may
    /// replay by the audio on disk and not by `recoveryAudioFilename`. A draft
    /// from every source but typing carries that name, from `begin` or from
    /// the switch to speaking, so excluding on it leaves a draft like this
    /// one to neither pass, kept by the launch prune because it has words,
    /// and shown nowhere.
    ///
    /// Falsifier: add `$0.recoveryAudioFilename == nil` to `recoverable()`
    /// and no session is saved, the draft is still there after the relaunch,
    /// and the audio pass does not list it either.
    func testTypedWordsSurviveAKillBeforeTheRecordingHasAudio() throws {
        let startedAt = Date().addingTimeInterval(-120)
        let typed = seedRecoverableDraft("Call Dana", source: .inAppText, startedAt: startedAt)
        CaptureDraftStore.updateSource(
            id: typed.id,
            source: .inAppVoice,
            typedBeforeSpeaking: "Call Dana",
            at: startedAt.addingTimeInterval(5)
        )
        let speaking = try XCTUnwrap(CaptureDraftStore.draft(id: typed.id))
        XCTAssertNotNil(speaking.recoveryAudioFilename, "a recording is intended")
        XCTAssertFalse(CaptureDraftStore.hasRecoveryAudio(for: speaking))
        XCTAssertTrue(CaptureDraftStore.recoverableAudioDrafts(minimumAge: 0).isEmpty)

        relaunch()

        XCTAssertEqual(try allSessions().map(\.originalTranscription), ["Call Dana"])
        XCTAssertNil(CaptureDraftStore.draft(id: typed.id), "The typed words were left to no recovery pass")
        relaunch()
        XCTAssertEqual(try allSessions().count, 1)
    }

    /// Today's Delete saves the kept typed words at once, through
    /// `commitKeptTypedWords`, and the launch text pass is the fallback for
    /// the same draft. Whatever happens between the two, the words are
    /// stored once: one session, not two. Two things make that true, and
    /// each is exercised here rather than assumed.
    ///
    /// The handoff. Killed after Today's commit and before it releases the
    /// draft, the draft names a committed session, and the launch releases
    /// it before the text pass can replay it.
    ///
    /// Deduplication. A replay the handoff did not stop, here the kept draft
    /// as it was before its handoff was recorded, is committed as typing
    /// under the same start time as Today's save, so it lands in the in-app
    /// window and returns the session already stored. The kept draft is
    /// dated a minute back, so the text pass's twelve-second floor is not
    /// what keeps it from replaying.
    ///
    /// Falsifier: make `releaseHandedOffCaptureDrafts` release nothing and
    /// the draft is still there after the release step. Have
    /// `commitKeptTypedWords` commit under `.now` rather than
    /// `kept.startedAt`, or as `.inAppVoice`, and the replay stores a second
    /// session.
    func testTodaysSaveOfKeptTypedWordsAndTheLaunchFallbackStoreThemOnce() async throws {
        let (draft, _) = try seedTypedThenSpokenDraft(typed: "Call Dana", spokenSoFar: "about the")
        let kept = try XCTUnwrap(CaptureDraftStore.deleteRecordingKeepingTypedWords(
            id: draft.id,
            at: Date().addingTimeInterval(-60)
        ))
        XCTAssertEqual(kept.startedAt, draft.startedAt)

        // Today's save, then a kill before it releases the draft.
        let saved = try await CaptureDraftStore.commitKeptTypedWords(kept, to: repository)
        XCTAssertTrue(saved.createdNewCapture)
        XCTAssertEqual(saved.session.originalTranscription, "Call Dana")
        XCTAssertEqual(CaptureDraftStore.draft(id: kept.id)?.handedOffSessionID, saved.session.id)

        // The launch, one step at a time: the release comes first.
        repository = nil
        let launched = makeRepository()
        launched.releaseHandedOffCaptureDrafts()
        XCTAssertNil(
            CaptureDraftStore.draft(id: kept.id),
            "The launch must release a kept draft whose words reached a committed session"
        )
        launched.recoverInterruptedCaptureDraft()
        repository = launched
        XCTAssertEqual(try allSessions().map(\.id), [saved.session.id])

        // A replay the handoff does not stop reaches the text pass and is
        // folded into the stored session.
        CaptureDraftStore.restore([kept])
        XCTAssertNil(CaptureDraftStore.draft(id: kept.id)?.handedOffSessionID)
        relaunch()
        XCTAssertNil(CaptureDraftStore.draft(id: kept.id), "The text pass never replayed the kept draft")
        XCTAssertEqual(
            try allSessions().map(\.id),
            [saved.session.id],
            "Today's save and the launch fallback stored the kept words twice"
        )
    }

    /// A recording with nothing typed before it is deleted outright, as
    /// before. Words typed before speaking and then erased stay erased, both
    /// when the person erases the editor and stops there, and when they
    /// speak again afterwards.
    ///
    /// Erase and stop is the sequence that used to bring them back: type
    /// "Call Dana", Speak instead, speak, Type instead, select all, delete,
    /// leave. The editor's empty checkpoint does not discard a draft that has
    /// a recording, so the draft survives, and recovering the recording read
    /// the set-aside words back in front of it.
    ///
    /// Falsifier: stop `update` clearing `typedBeforeSpeaking` when it
    /// empties the transcript, and the erase-and-stop half fails: the
    /// recovered words are "Call Dana about the invoice", and deleting the
    /// recording keeps "Call Dana" to be saved as a thought. Keep a draft for every
    /// deleted recording and the first half returns one. Set
    /// `typedBeforeSpeaking` only when the editor has words and the
    /// speak-again half gets "Call Dana" back.
    func testOnlyTypedWordsAreKeptAndErasedOnesStayErased() throws {
        let spoken = CaptureDraftStore.begin(source: .inAppVoice)
        _ = try writeRecording(for: spoken)
        XCTAssertFalse(CaptureRecoveryPresentation.keepsTypedWordsOnDelete(spoken))
        XCTAssertNil(CaptureDraftStore.deleteRecordingKeepingTypedWords(id: spoken.id))
        XCTAssertNil(CaptureDraftStore.current())

        // Type, Speak instead, speak, Type instead, erase everything, stop.
        let (draft, audioURL) = try seedTypedThenSpokenDraft(typed: "Call Dana", spokenSoFar: "about the")
        XCTAssertEqual(draft.typedBeforeSpeaking, "Call Dana")
        CaptureDraftStore.updateSource(id: draft.id, source: .inAppText)
        CaptureDraftStore.update(id: draft.id, transcript: "")

        relaunch()
        let erased = try XCTUnwrap(
            CaptureDraftStore.draft(id: draft.id),
            "The recording is still a capture to recover after the editor is emptied"
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: audioURL.path))
        XCTAssertNil(erased.typedBeforeSpeaking, "Erased words were still set aside for recovery")
        XCTAssertEqual(
            CaptureDraftStore.words(for: erased, spoken: "about the invoice"),
            "about the invoice",
            "Recovering the recording brought back the words the person erased"
        )
        XCTAssertEqual(CaptureRecoveryPresentation.typeInsteadStartingText(for: erased), "")
        XCTAssertFalse(CaptureRecoveryPresentation.keepsTypedWordsOnDelete(erased))
        XCTAssertNil(CaptureDraftStore.deleteRecordingKeepingTypedWords(id: draft.id))
        relaunch()
        XCTAssertTrue(try allSessions().isEmpty, "Deleting the recording saved words the person had erased")

        // Erase and speak again at once, before the editor's empty
        // checkpoint lands: the switch itself sets nothing aside.
        let (again, _) = try seedTypedThenSpokenDraft(typed: "Call Dana", spokenSoFar: "about the")
        CaptureDraftStore.updateSource(id: again.id, source: .inAppText)
        CaptureDraftStore.updateSource(id: again.id, source: .inAppVoice, typedBeforeSpeaking: "")
        let respoken = try XCTUnwrap(CaptureDraftStore.draft(id: again.id))
        XCTAssertNil(respoken.typedBeforeSpeaking)
        XCTAssertEqual(CaptureDraftStore.words(for: respoken, spoken: "Email Sam"), "Email Sam")
    }

    // MARK: - 5. Device clock destruction

    /// Moves the process into `identifier`'s time zone, the way stepping off a
    /// plane moves the phone's.
    private func setTimeZone(_ identifier: String) {
        setenv("TZ", identifier, 1)
        NSTimeZone.resetSystemTimeZone()
    }

    private func restoreTimeZone() {
        unsetenv("TZ")
        NSTimeZone.resetSystemTimeZone()
    }

    func testFlyingToHongKongDoesNotMoveAnAlreadyResolvedReminder() async throws {
        defer { restoreTimeZone() }

        setTimeZone("America/Toronto")
        let created = try await capture("Remind me tomorrow at 9am to call the clinic")
        let itemID = created.primaryItem.id
        let originalDue = created.primaryItem.dueDate
        let originalReminder = created.primaryItem.reminderDate

        setTimeZone("Asia/Hong_Kong")
        relaunch()
        var item = try XCTUnwrap(try allItems().first { $0.id == itemID })
        XCTAssertEqual(item.dueDate, originalDue, "A flight must not move a reminder the person already set")
        XCTAssertEqual(item.reminderDate, originalReminder)

        setTimeZone("America/Toronto")
        relaunch()
        item = try XCTUnwrap(try allItems().first { $0.id == itemID })
        XCTAssertEqual(item.dueDate, originalDue, "Flying home must not move it back either")
        XCTAssertEqual(item.reminderDate, originalReminder)
    }

    func testRelaunchingAfterMidnightDoesNotRewriteStoredDates() async throws {
        let result = try await capture("Pay the invoice on Thursday")
        let item = result.primaryItem
        let originalDue = item.dueDate
        let originalIntent = item.temporalIntent

        // Every relaunch reruns recovery and the temporal backfill. Neither may
        // touch a row that already has an answer, whatever day it is now.
        relaunch()
        relaunch()

        let reloaded = try XCTUnwrap(try allItems().first { $0.id == item.id })
        XCTAssertEqual(reloaded.dueDate, originalDue)
        XCTAssertEqual(reloaded.temporalIntent, originalIntent, "A stored intent is never rewritten by a relaunch")
    }

    func testBackfillNeverInventsAnIntentThatMovesAnEditedDate() async throws {
        let result = try await capture("Call the accountant tomorrow")
        let item = result.primaryItem
        let handPickedDate = Calendar.current.date(byAdding: .day, value: 45, to: .now)!

        var edits = ItemEdits(
            title: item.displayTitle,
            itemType: item.itemType,
            category: item.category,
            dueDate: handPickedDate,
            reminderDate: nil,
            priority: item.priority,
            personName: item.personName,
            needsClarification: false
        )
        edits.locationIntent = .unchanged
        try repository.update(item, with: edits)
        let storedDue = try XCTUnwrap(try allItems().first { $0.id == item.id }?.dueDate)

        relaunch()
        relaunch()

        XCTAssertEqual(
            try XCTUnwrap(try allItems().first { $0.id == item.id }?.dueDate),
            storedDue,
            "A hand-picked date outranks what the original wording would parse to"
        )
    }

    // MARK: - 6. Store durability

    /// A library with one of everything the app can hold.
    private func buildRealisticLibrary() async throws {
        let now = Date()
        _ = try await capture("Buy milk", createdAt: now)
        _ = try await capture("Call the dentist on Monday", createdAt: now.addingTimeInterval(30))
        _ = try await capture("Remind me tomorrow at 8am to take the bins out", createdAt: now.addingTimeInterval(60))
        _ = try await capture("Take out the recycling every Tuesday", createdAt: now.addingTimeInterval(90))
        _ = try await capture("The wifi password is orangehill", createdAt: now.addingTimeInterval(120))
        _ = try await capture("Priya's sister is called Meera", createdAt: now.addingTimeInterval(150))
        _ = try await capture("Idea: a calmer way to review the week", createdAt: now.addingTimeInterval(180))
        _ = try await capture("Remind me when I get home to water the plants", createdAt: now.addingTimeInterval(210))
        _ = try await capture("Sort that thing out", createdAt: now.addingTimeInterval(240))

        let items = try allItems()
        if let completable = items.first(where: { $0.displayTitle.localizedCaseInsensitiveContains("milk") }) {
            try repository.setCompleted(completable, completed: true)
        }
    }

    func testARealisticLibrarySurvivesRepeatedSaveCloseReopenCycles() async throws {
        try await buildRealisticLibrary()

        let baselineItems = Set(try allItems().map(\.id))
        let baselineSessions = Set(try allSessions().map(\.id))
        let baselineTranscripts = Set(try allSessions().map(\.originalTranscription))
        XCTAssertFalse(baselineItems.isEmpty)

        for _ in 0..<5 {
            relaunch()
            XCTAssertEqual(Set(try allItems().map(\.id)), baselineItems, "A reopen changed the item set")
            XCTAssertEqual(Set(try allSessions().map(\.id)), baselineSessions, "A reopen changed the session set")
            XCTAssertEqual(
                Set(try allSessions().map(\.originalTranscription)),
                baselineTranscripts,
                "A reopen rewrote somebody's words"
            )
        }
    }

    func testEditAndCompleteSurviveReopeningBetweenEveryStep() async throws {
        let result = try await capture("Draft the quarterly summary")
        let itemID = result.primaryItem.id

        relaunch()
        var item = try XCTUnwrap(try allItems().first { $0.id == itemID })
        var edits = ItemEdits(
            title: "Draft the quarterly summary for Dana",
            itemType: item.itemType,
            category: item.category,
            dueDate: item.dueDate,
            reminderDate: item.reminderDate,
            priority: item.priority,
            personName: "Dana",
            needsClarification: false
        )
        edits.locationIntent = .unchanged
        try repository.update(item, with: edits)

        relaunch()
        item = try XCTUnwrap(try allItems().first { $0.id == itemID })
        XCTAssertEqual(item.displayTitle, "Draft the quarterly summary for Dana")
        XCTAssertEqual(item.personName, "Dana")
        try repository.setCompleted(item, completed: true)

        relaunch()
        item = try XCTUnwrap(try allItems().first { $0.id == itemID })
        XCTAssertTrue(item.isCompleted, "A completion must survive a reopen")
        XCTAssertEqual(item.displayTitle, "Draft the quarterly summary for Dana", "And so must the edit before it")
    }

    func testDeletionStaysDeletedAcrossReopen() async throws {
        _ = try await capture("Cancel the gym membership")
        let doomed = try await capture("Return the library books")
        let doomedID = doomed.primaryItem.id

        try repository.delete(doomed.primaryItem)
        relaunch()

        XCTAssertFalse(
            try allItems().contains { $0.id == doomedID },
            "A deleted thought must not be resurrected by launch recovery"
        )
    }
}

/// Upgrade, not clean install.
///
/// The failure this guards against does not appear in any simulator run that
/// starts from an empty store: it appears once, on the phones of the people who
/// already trusted the app with their thoughts, and it is unrecoverable by the
/// time anyone sees it. So these tests write a real file-backed store in an
/// older schema, close it, and open it the way the release candidate will.
@MainActor
final class UpgradeDurabilityTests: XCTestCase {
    private var storeURL: URL!

    override func setUpWithError() throws {
        storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpeakItUpgrade-\(UUID().uuidString)")
            .appendingPathExtension("store")
    }

    override func tearDownWithError() throws {
        for suffix in ["", "-shm", "-wal"] {
            let url = URL(fileURLWithPath: storeURL.path + suffix)
            try? FileManager.default.removeItem(at: url)
        }
        storeURL = nil
    }

    /// Writes a version 1 store on disk and closes it, the way a person's phone
    /// holds it before they take the update.
    private func writeVersionOneStore() throws -> (sessionID: UUID, itemIDs: [UUID], due: Date, completedID: UUID) {
        let configuration = ModelConfiguration(
            schema: Schema(versionedSchema: SpeakItSchemaV1.self),
            url: storeURL
        )
        let container = try ModelContainer(
            for: Schema(versionedSchema: SpeakItSchemaV1.self),
            configurations: [configuration]
        )
        let context = ModelContext(container)

        let due = Date(timeIntervalSince1970: 1_800_000_000)
        let session = SpeakItSchemaV1.CaptureSession(
            originalTranscription: "Call the clinic on Thursday and pick up Ana from the airport",
            createdAt: Date(timeIntervalSince1970: 1_799_000_000),
            captureSourceRawValue: "inAppVoice",
            processingStatusRawValue: "complete"
        )
        let first = SpeakItSchemaV1.CapturedItem(
            originalTextSegment: "Call the clinic on Thursday",
            displayTitle: "Call the clinic",
            itemTypeRawValue: "task",
            categoryRawValue: "general",
            createdAt: session.createdAt,
            dueDate: due,
            reminderDate: due,
            captureSession: session
        )
        let second = SpeakItSchemaV1.CapturedItem(
            originalTextSegment: "Pick up Ana from the airport",
            displayTitle: "Pick up Ana from the airport",
            itemTypeRawValue: "task",
            categoryRawValue: "general",
            createdAt: session.createdAt,
            captureSession: session
        )
        let done = SpeakItSchemaV1.CapturedItem(
            originalTextSegment: "Renew the passport",
            displayTitle: "Renew the passport",
            itemTypeRawValue: "task",
            createdAt: session.createdAt,
            completedAt: Date(timeIntervalSince1970: 1_799_500_000),
            captureSession: session
        )
        let note = SpeakItSchemaV1.CapturedItem(
            originalTextSegment: "The studio door code is 4821",
            displayTitle: "The studio door code is 4821",
            itemTypeRawValue: "note",
            categoryRawValue: "reference",
            createdAt: session.createdAt,
            captureSession: session
        )
        [first, second, done, note].forEach(context.insert)
        context.insert(session)
        try context.save()

        return (session.id, [first.id, second.id, done.id, note.id], due, done.id)
    }

    /// Opens the existing store the way the release candidate opens it, and runs
    /// the same launch recovery the app runs.
    private func openAsReleaseCandidate() throws -> (repository: SwiftDataThoughtRepository, container: ModelContainer) {
        let configuration = ModelConfiguration(
            schema: PersistenceController.schema,
            url: storeURL
        )
        let container = try ModelContainer(
            for: PersistenceController.schema,
            migrationPlan: SpeakItMigrationPlan.self,
            configurations: [configuration]
        )
        let repository = SwiftDataThoughtRepository(
            modelContext: container.mainContext,
            placeReminderDelivery: { _, _, _, _ in .scheduled },
            placeReminderCancellation: { _ in },
            requestsReminderAuthorization: false
        )
        repository.recoverUnorganizedCaptures()
        repository.recoverInterruptedCaptureDraft()
        return (repository, container)
    }

    func testEveryThoughtSurvivesTheUpgradeFromVersionOne() throws {
        let seeded = try writeVersionOneStore()

        let opened = try openAsReleaseCandidate()
        let items = try opened.container.mainContext.fetch(FetchDescriptor<CapturedItem>())
        let sessions = try opened.container.mainContext.fetch(FetchDescriptor<CaptureSession>())

        XCTAssertEqual(Set(items.map(\.id)), Set(seeded.itemIDs), "The upgrade lost or invented a thought")
        XCTAssertEqual(sessions.map(\.id), [seeded.sessionID])
        XCTAssertEqual(
            sessions[0].originalTranscription,
            "Call the clinic on Thursday and pick up Ana from the airport",
            "The original words must read back exactly as they were spoken"
        )
    }

    func testUpgradeDoesNotMoveAnyExistingReminder() throws {
        let seeded = try writeVersionOneStore()

        let opened = try openAsReleaseCandidate()
        let items = try opened.container.mainContext.fetch(FetchDescriptor<CapturedItem>())
        let clinic = try XCTUnwrap(items.first { $0.displayTitle == "Call the clinic" })

        XCTAssertEqual(clinic.dueDate, seeded.due, "An existing reminder must not move because the app updated")
        XCTAssertEqual(clinic.reminderDate, seeded.due)
    }

    func testUpgradePreservesCompletionAndDestination() throws {
        let seeded = try writeVersionOneStore()

        let opened = try openAsReleaseCandidate()
        let items = try opened.container.mainContext.fetch(FetchDescriptor<CapturedItem>())

        let done = try XCTUnwrap(items.first { $0.id == seeded.completedID })
        XCTAssertTrue(done.isCompleted, "Completed work must not come back as outstanding")

        let note = try XCTUnwrap(items.first { $0.displayTitle == "The studio door code is 4821" })
        XCTAssertEqual(note.itemType, .note, "A Memory note must not be re-sorted into Today by an upgrade")
    }

    /// Version 2 added the stored temporal intent. Old rows have none, and the
    /// backfill invents one from the words — which must never contradict the
    /// date the row already holds.
    func testBackfillGivesOldRowsAnIntentWithoutMovingTheirDates() throws {
        let seeded = try writeVersionOneStore()

        let opened = try openAsReleaseCandidate()
        let items = try opened.container.mainContext.fetch(FetchDescriptor<CapturedItem>())
        let clinic = try XCTUnwrap(items.first { $0.id == seeded.itemIDs[0] })

        XCTAssertNotNil(clinic.temporalIntent, "The backfill should give a pre-v2 row its intent")
        XCTAssertEqual(clinic.dueDate, seeded.due, "And must not move the date while doing it")
    }

    func testOpeningTheUpgradedStoreRepeatedlyIsStable() throws {
        let seeded = try writeVersionOneStore()

        for pass in 0..<3 {
            let opened = try openAsReleaseCandidate()
            let items = try opened.container.mainContext.fetch(FetchDescriptor<CapturedItem>())
            XCTAssertEqual(
                Set(items.map(\.id)),
                Set(seeded.itemIDs),
                "Pass \(pass) changed the library"
            )
        }
    }

    /// The draft checkpoint format changed from a single object to an array.
    /// A person mid-capture when they took the update must not lose those words.
    func testADraftWrittenByAnOlderBuildIsStillRecoverable() throws {
        CaptureDraftStore.clear()
        defer { CaptureDraftStore.clear() }

        let legacy = CaptureDraftStore.Draft(
            id: UUID(),
            startedAt: Date().addingTimeInterval(-300),
            updatedAt: Date().addingTimeInterval(-300),
            transcript: "Tell Marcus the deposit cleared",
            captureSourceRawValue: nil,
            recoveryAudioFilename: nil,
            recoveryStatusRawValue: nil,
            recoveryFailureMessage: nil
        )
        UserDefaults.standard.set(
            try JSONEncoder().encode(legacy),
            forKey: "SpeakIt.activeCaptureDraft"
        )

        _ = try writeVersionOneStore()
        let opened = try openAsReleaseCandidate()
        let items = try opened.container.mainContext.fetch(FetchDescriptor<CapturedItem>())

        XCTAssertTrue(
            items.contains { $0.originalTextSegment == "Tell Marcus the deposit cleared" },
            "An in-flight capture from the previous build must survive the update"
        )
        XCTAssertNil(CaptureDraftStore.recoverable())
    }

    /// Drafts written before the handoff existed carry no `handedOffSessionID`
    /// key at all. They must decode as "not handed off" and be replayed, never
    /// be dropped because the key is missing or treated as already saved.
    /// Written as a plain JSON object on purpose: encoding a `Draft` would
    /// prove only that this build reads what this build writes.
    ///
    /// Falsifier: make `handedOffSessionID` non-optional and the array fails
    /// to decode, `allDrafts()` returns nothing, and the words are gone.
    func testADraftWrittenBeforeHandoffsStillDecodesAndRecovers() throws {
        CaptureDraftStore.clear()
        defer { CaptureDraftStore.clear() }

        let id = UUID()
        let written = Date().addingTimeInterval(-300).timeIntervalSinceReferenceDate
        // Exactly the keys an earlier build wrote, with `Date` in its default
        // Codable form, seconds since the reference date.
        let olderBuildDrafts: [[String: Any]] = [[
            "id": id.uuidString,
            "startedAt": written,
            "updatedAt": written,
            "transcript": "Ask Dana for the invoice number",
            "captureSourceRawValue": "inAppText",
            "recoveryStatusRawValue": "capturing",
        ]]
        UserDefaults.standard.set(
            try JSONSerialization.data(withJSONObject: olderBuildDrafts),
            forKey: "SpeakIt.activeCaptureDraft"
        )

        let decoded = try XCTUnwrap(CaptureDraftStore.draft(id: id), "The old format must decode")
        XCTAssertNil(decoded.handedOffSessionID)
        XCTAssertEqual(CaptureDraftStore.recoverable()?.id, id)

        _ = try writeVersionOneStore()
        let opened = try openAsReleaseCandidate()
        let items = try opened.container.mainContext.fetch(FetchDescriptor<CapturedItem>())

        XCTAssertTrue(
            items.contains { $0.originalTextSegment == "Ask Dana for the invoice number" },
            "A pre-handoff draft must still be replayed after the update"
        )
        XCTAssertNil(CaptureDraftStore.draft(id: id))
    }
}

/// Storage that refuses to write.
///
/// The invariant under failure is narrow and absolute: the app may not claim a
/// thought was kept unless it was, and the words must still be recoverable
/// afterwards. A read-only store is the closest honest stand-in for a full disk
/// or a store the system will not let us write to.
@MainActor
final class StorageFailureDurabilityTests: XCTestCase {
    private var storeURL: URL!
    private var container: ModelContainer!
    private var repository: SwiftDataThoughtRepository!

    override func setUpWithError() throws {
        CaptureDraftStore.clear()
        storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpeakItReadOnly-\(UUID().uuidString)")
            .appendingPathExtension("store")

        // The file has to exist before it can be opened read-only.
        let seedConfiguration = ModelConfiguration(schema: PersistenceController.schema, url: storeURL)
        _ = try ModelContainer(
            for: PersistenceController.schema,
            migrationPlan: SpeakItMigrationPlan.self,
            configurations: [seedConfiguration]
        )

        let readOnly = ModelConfiguration(
            schema: PersistenceController.schema,
            url: storeURL,
            allowsSave: false
        )
        container = try ModelContainer(
            for: PersistenceController.schema,
            migrationPlan: SpeakItMigrationPlan.self,
            configurations: [readOnly]
        )
        repository = SwiftDataThoughtRepository(
            modelContext: container.mainContext,
            placeReminderDelivery: { _, _, _, _ in .scheduled },
            placeReminderCancellation: { _ in },
            requestsReminderAuthorization: false
        )
    }

    override func tearDownWithError() throws {
        CaptureDraftStore.clear()
        repository = nil
        container = nil
        for suffix in ["", "-shm", "-wal"] {
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: storeURL.path + suffix))
        }
        storeURL = nil
    }

    func testAFailedSaveReportsFailureRatherThanSuccess() async throws {
        do {
            _ = try await repository.createCaptureResult(
                text: "Move the standing meeting to Thursday",
                source: .inAppVoice,
                createdAt: .now,
                schedulesReminders: false
            )
            XCTFail("A store that cannot save must not report a saved thought")
        } catch let error as RepositoryError {
            guard case .saveFailed = error else {
                return XCTFail("Expected a save failure, got \(error)")
            }
        }
    }

    func testAFailedSaveWritesNothingDurable() async throws {
        _ = try? await repository.createCaptureResult(
            text: "Move the standing meeting to Thursday",
            source: .inAppVoice,
            createdAt: .now,
            schedulesReminders: false
        )

        let inMemoryItems = try container.mainContext.fetch(FetchDescriptor<CapturedItem>()).count
        let inMemorySessions = try container.mainContext.fetch(FetchDescriptor<CaptureSession>()).count

        // What actually reached the file, read through a context that shares
        // none of the failed one's pending state.
        let verification = ModelContext(container)
        let durableItems = try verification.fetch(FetchDescriptor<CapturedItem>()).count
        let durableSessions = try verification.fetch(FetchDescriptor<CaptureSession>()).count

        XCTAssertEqual(durableItems, 0, "A failed save must not persist a row")
        XCTAssertEqual(durableSessions, 0, "A failed save must not persist a session")
        XCTAssertEqual(
            inMemoryItems,
            0,
            "The rolled-back row is still live in the context, so Today and Memory will show a thought that was never saved"
        )
        XCTAssertEqual(inMemorySessions, 0)
    }

    /// The point of the checkpoint. If storage is refusing writes, the words are
    /// the only thing left, and they have to still be there for the next launch.
    func testAnUnwritableStoreKeepsTheDraftRecoverable() throws {
        let startedAt = Date().addingTimeInterval(-120)
        let draft = CaptureDraftStore.begin(source: .inAppVoice, at: startedAt)
        CaptureDraftStore.update(
            id: draft.id,
            transcript: "Tell Dana the deposit cleared",
            at: startedAt
        )

        repository.recoverInterruptedCaptureDraft()

        let survivor = CaptureDraftStore.recoverable()
        XCTAssertEqual(
            survivor?.transcript,
            "Tell Dana the deposit cleared",
            "Storage refusing to write is exactly when the checkpoint must be kept"
        )
    }

    func testRecoveryOnAnUnwritableStoreDoesNotSpinForever() throws {
        let startedAt = Date().addingTimeInterval(-120)
        for index in 0..<3 {
            let draft = CaptureDraftStore.begin(
                source: .inAppVoice,
                at: startedAt.addingTimeInterval(Double(index))
            )
            CaptureDraftStore.update(
                id: draft.id,
                transcript: "Interrupted thought \(index)",
                at: startedAt.addingTimeInterval(Double(index))
            )
        }

        // The failure path must stop, not retry the same unwritable draft in a
        // loop. Completing at all is the assertion.
        repository.recoverInterruptedCaptureDraft()

        XCTAssertNotNil(CaptureDraftStore.recoverable(), "Nothing may be dropped on the way out")
    }

    func testReadingTheLibraryStillWorksWhenWritingDoesNot() async throws {
        // Recovery and reconciliation run on every launch. On a store that
        // cannot be written they must degrade quietly rather than crash.
        repository.recoverUnorganizedCaptures()
        repository.reconcilePendingReminders()
        repository.reconcileSharedTodayActions()
        _ = repository.reconcileLocationReminders()

        XCTAssertTrue(try container.mainContext.fetch(FetchDescriptor<CapturedItem>()).isEmpty)
    }
}

/// The escape hatch on a recording that cannot be recovered.
///
/// TestFlight found the dead end these cover: a protected recording whose
/// recovery returns "No speech detected" stayed listed as ready to recover, and
/// the Today attention card had no way to be resolved. The invariant is one
/// line longer than the file's:
///
/// > A recording is recoverable, reconstructable, or deletable — and a failed
/// > attempt never costs the person the recording.
@MainActor
final class CaptureRecoveryEscapeTests: XCTestCase {
    override func setUpWithError() throws {
        CaptureDraftStore.clear()
    }

    override func tearDownWithError() throws {
        CaptureDraftStore.clear()
    }

    /// Exactly what the recognizer hands back when it read the audio and found
    /// nothing in it.
    private var noSpeechError: NSError {
        NSError(
            domain: "kAFAssistantErrorDomain",
            code: 1110,
            userInfo: [NSLocalizedDescriptionKey: "No speech detected"]
        )
    }

    private func makeProtectedRecording(
        startedAt: Date = Date(timeIntervalSince1970: 1_800_000_000).addingTimeInterval(-120)
    ) throws -> (draft: CaptureDraftStore.Draft, audioURL: URL) {
        let draft = CaptureDraftStore.begin(source: .inAppVoice, at: startedAt)
        let audioURL = try XCTUnwrap(CaptureDraftStore.prepareAudioURL(for: draft))
        try Data(repeating: 0x1, count: 1_024).write(to: audioURL, options: .atomic)
        CaptureDraftStore.protectAudio(at: audioURL)
        return (draft, audioURL)
    }

    // MARK: - A failed attempt costs nothing

    func testAFailedRecoveryKeepsTheRecording() throws {
        let (draft, audioURL) = try makeProtectedRecording()

        CaptureDraftStore.markProcessing(id: draft.id)
        CaptureDraftStore.markFailed(id: draft.id, error: noSpeechError)

        XCTAssertTrue(
            FileManager.default.fileExists(atPath: audioURL.path),
            "A failed transcription must never remove the only copy of the words"
        )
        let stored = try XCTUnwrap(CaptureDraftStore.draft(id: draft.id))
        XCTAssertEqual(stored.recoveryStatus, .failed)
        XCTAssertEqual(stored.recoveryFailureKind, .noSpeechDetected)
        XCTAssertEqual(
            CaptureDraftStore.recoverableAudioDrafts(minimumAge: 0).map(\.id),
            [draft.id],
            "The recording stays listed so another attempt is still possible"
        )
    }

    func testRetryCanBeAttemptedRepeatedly() throws {
        let (draft, audioURL) = try makeProtectedRecording()

        for attempt in 1...4 {
            CaptureDraftStore.markProcessing(id: draft.id)
            XCTAssertEqual(
                CaptureDraftStore.draft(id: draft.id)?.recoveryStatus,
                .processing,
                "Attempt \(attempt) has to be able to start"
            )
            CaptureDraftStore.markFailed(id: draft.id, error: noSpeechError)

            XCTAssertTrue(
                FileManager.default.fileExists(atPath: audioURL.path),
                "Attempt \(attempt) must leave the recording in place"
            )
            XCTAssertEqual(
                CaptureDraftStore.recoverableAudioDrafts(minimumAge: 0).map(\.id),
                [draft.id],
                "Attempt \(attempt) must leave the recording retryable"
            )
        }
    }

    // MARK: - Deleting always works

    func testDeletingSucceedsAfterATranscriptionFailure() throws {
        let (draft, audioURL) = try makeProtectedRecording()
        CaptureDraftStore.markFailed(id: draft.id, error: noSpeechError)

        XCTAssertTrue(CaptureDraftStore.deleteRecording(id: draft.id))

        XCTAssertNil(CaptureDraftStore.draft(id: draft.id))
        XCTAssertFalse(FileManager.default.fileExists(atPath: audioURL.path))
    }

    /// The escape hatch cannot depend on the file still being there, or on the
    /// recognizer having ever succeeded.
    func testDeletingSucceedsWhenTheRecordingFileIsAlreadyGone() throws {
        let (draft, audioURL) = try makeProtectedRecording()
        CaptureDraftStore.markFailed(id: draft.id, error: noSpeechError)
        try FileManager.default.removeItem(at: audioURL)

        XCTAssertTrue(CaptureDraftStore.deleteRecording(id: draft.id))
        XCTAssertNil(CaptureDraftStore.draft(id: draft.id))
    }

    func testDeletingClearsTheTodayAttentionBanner() throws {
        let (draft, _) = try makeProtectedRecording()
        CaptureDraftStore.markFailed(id: draft.id, error: noSpeechError)

        let banner = CaptureDraftStore.recoverableAudioDrafts(minimumAge: 0)
        XCTAssertEqual(banner.count, 1, "The card is on Today before the delete")

        // Today rebuilds the card from this notification, so a silent delete
        // would leave the card standing until the next launch.
        let notified = expectation(
            forNotification: CaptureDraftStore.recoveryDidChangeNotification,
            object: nil
        )
        CaptureDraftStore.deleteRecording(id: draft.id)
        wait(for: [notified], timeout: 1)

        XCTAssertTrue(
            CaptureDraftStore.recoverableAudioDrafts(minimumAge: 0).isEmpty,
            "Today must have nothing left to show attention for"
        )
    }

    func testARelaunchDoesNotResurrectADeletedRecording() throws {
        let (draft, audioURL) = try makeProtectedRecording()
        CaptureDraftStore.markFailed(id: draft.id, error: noSpeechError)

        // A checkpoint written before the person deleted, replayed afterwards.
        let staleCheckpoint = CaptureDraftStore.snapshot()
        XCTAssertEqual(staleCheckpoint.map(\.id), [draft.id])

        CaptureDraftStore.deleteRecording(id: draft.id)
        CaptureDraftStore.restore(staleCheckpoint)
        try Data(repeating: 0x1, count: 1_024).write(to: audioURL, options: .atomic)

        // The launch sequence, in RootView's order.
        CaptureDraftStore.pruneEmptyTextDrafts()

        XCTAssertTrue(CaptureDraftStore.isDeleted(draft.id))
        XCTAssertNil(CaptureDraftStore.draft(id: draft.id))
        XCTAssertTrue(
            CaptureDraftStore.recoverableAudioDrafts(minimumAge: 0).isEmpty,
            "A deleted recording must not come back on the next launch"
        )
    }

    // MARK: - Saying what actually happened

    func testNoSpeechStopsCallingTheRecordingReadyToRecover() throws {
        let (draft, _) = try makeProtectedRecording()
        CaptureDraftStore.markFailed(id: draft.id, error: noSpeechError)
        let stored = try XCTUnwrap(CaptureDraftStore.draft(id: draft.id))

        let row = CaptureRecoveryPresentation.row(for: stored)
        XCTAssertEqual(row.title, "Couldn’t recover")
        XCTAssertTrue(row.stopsPromisingRecovery)
        XCTAssertEqual(
            CaptureRecoveryPresentation.sectionTitle(for: [stored]),
            "Needs attention",
            "\"Ready to recover\" promises a retry that is not expected to work"
        )
        XCTAssertFalse(
            CaptureRecoveryPresentation.attentionDetail(for: [stored]).contains("Tap to recover")
        )
    }

    func testAnUntriedRecordingIsStillReadyToRecover() throws {
        let (draft, _) = try makeProtectedRecording()
        let stored = try XCTUnwrap(CaptureDraftStore.draft(id: draft.id))

        XCTAssertEqual(CaptureRecoveryPresentation.sectionTitle(for: [stored]), "Ready to recover")
        XCTAssertFalse(CaptureRecoveryPresentation.row(for: stored).stopsPromisingRecovery)
    }

    func testRecoveryFailuresAreDescribedSpecificallyRatherThanGenerically() {
        let title = CaptureRecoveryPresentation.alertTitle(for: .noSpeechDetected)
        XCTAssertEqual(title, "Couldn’t recover this recording")

        let message = CaptureRecoveryPresentation.alertMessage(for: .noSpeechDetected)
        XCTAssertTrue(message.contains("didn’t find any words"))
        XCTAssertTrue(
            message.contains("delete the recording"),
            "The alert has to name the way out of the dead end"
        )
        XCTAssertFalse(message.contains("Something went wrong"))
        XCTAssertFalse(
            message.contains(title),
            "An alert whose message repeats its title has told the person nothing"
        )
    }

    func testEveryFailureAlertNamesAWayForwardWithoutRepeatingItsTitle() {
        let kinds: [CaptureRecoveryFailureKind] = [
            .noSpeechDetected, .missingRecording, .permissionRequired,
            .recognizerUnavailable, .onDeviceRecognitionUnavailable, .timedOut,
            .cancelled, .storageUnavailable, .unknown
        ]
        for kind in kinds {
            let title = CaptureRecoveryPresentation.alertTitle(for: kind)
            let message = CaptureRecoveryPresentation.alertMessage(for: kind)
            XCTAssertFalse(title.isEmpty, "\(kind) needs a title")
            XCTAssertFalse(
                message.contains(title),
                "\(kind) repeats its title in the message"
            )
            XCTAssertTrue(
                message.contains("Try again") || message.contains("type the thought"),
                "\(kind) has to name something the person can do next"
            )
        }
    }

    /// The recognizer's own wording ("The operation could not be completed") is
    /// the generic message this fix removes, so it must not reach the person
    /// through the failure copy either.
    func testAnUnclassifiedFailureStillReadsAsAWholeSentence() throws {
        let (draft, _) = try makeProtectedRecording()
        CaptureDraftStore.markFailed(
            id: draft.id,
            message: "The operation could not be completed",
            kind: .unknown
        )
        let stored = try XCTUnwrap(CaptureDraftStore.draft(id: draft.id))

        let detail = CaptureRecoveryPresentation.row(for: stored).detail
        XCTAssertEqual(detail, "Recovery didn’t finish. The recording is still safe.")
        XCTAssertFalse(detail.contains("The operation could not be completed"))

        let message = CaptureRecoveryPresentation.alertMessage(for: .unknown)
        XCTAssertEqual(
            message,
            "The recording is still safe. Try again, or type the thought yourself."
        )
    }

    /// Every string that names a protected recording says it stays on this
    /// iPhone. A language with no on-device model refuses recovery rather than
    /// uploading the file, and the refusal says so, keeps the recording, and
    /// names the two things the person can still do.
    func testALanguageWithoutAnOnDeviceModelRefusesRecoveryInsteadOfUploading() throws {
        let (draft, audioURL) = try makeProtectedRecording()
        CaptureDraftStore.markFailed(
            id: draft.id,
            message: "This language has no on-device speech model",
            kind: .onDeviceRecognitionUnavailable
        )
        let stored = try XCTUnwrap(CaptureDraftStore.draft(id: draft.id))

        XCTAssertTrue(
            FileManager.default.fileExists(atPath: audioURL.path),
            "Refusing to upload must not cost the person the recording"
        )
        XCTAssertEqual(stored.recoveryFailureKind, .onDeviceRecognitionUnavailable)
        XCTAssertTrue(
            stored.recoveryFailureKind.stopsPromisingRecovery,
            "Tapping again cannot succeed until a local model exists, so the row must stop promising it"
        )

        let row = CaptureRecoveryPresentation.row(for: stored)
        XCTAssertEqual(row.title, "Couldn’t recover")
        XCTAssertTrue(row.detail.contains("won’t send the recording to Apple"))
        XCTAssertTrue(row.detail.contains("stays safe here"))

        let title = CaptureRecoveryPresentation.alertTitle(for: .onDeviceRecognitionUnavailable)
        let message = CaptureRecoveryPresentation.alertMessage(for: .onDeviceRecognitionUnavailable)
        XCTAssertEqual(title, "Recovery would leave this iPhone")
        XCTAssertTrue(message.contains("Apple’s speech service"), "The refusal has to say where the audio would have gone")
        XCTAssertTrue(message.contains("type the thought"))
        XCTAssertTrue(message.contains("delete the recording"))
        XCTAssertFalse(message.contains("Try again"), "A retry is not expected to work here, so the alert must not suggest one")
        XCTAssertFalse(message.contains(title))
    }

    /// A header promising recovery over a row that says the opposite is exactly
    /// how the dead end read.
    func testAnyFailureRetiresTheReadyToRecoverHeader() throws {
        let (draft, _) = try makeProtectedRecording()
        CaptureDraftStore.markFailed(id: draft.id, message: "Timed out", kind: .timedOut)
        let stored = try XCTUnwrap(CaptureDraftStore.draft(id: draft.id))

        XCTAssertEqual(CaptureRecoveryPresentation.sectionTitle(for: [stored]), "Needs attention")
        XCTAssertEqual(
            CaptureRecoveryPresentation.attentionDetail(for: [stored]),
            "A recording couldn’t be recovered. Tap to try again, type it, or delete it."
        )
    }

    func testTransientFailuresStayRetryableAndKeepPromisingRecovery() throws {
        let (draft, _) = try makeProtectedRecording()
        CaptureDraftStore.markFailed(
            id: draft.id,
            message: "Recovery took too long.",
            kind: .timedOut
        )
        let stored = try XCTUnwrap(CaptureDraftStore.draft(id: draft.id))

        XCTAssertFalse(
            stored.recoveryFailureKind.stopsPromisingRecovery,
            "A timeout says nothing about whether the recording has words in it"
        )
        XCTAssertEqual(CaptureRecoveryPresentation.row(for: stored).title, "Needs attention")
    }

    // MARK: - Tombstones do not accumulate forever

    /// Once no checkpoint and no audio remain, nothing can reintroduce the
    /// recording, so the entry that suppressed it is dead weight.
    func testAResolvedTombstoneIsPrunedAfterItsRetentionWindow() throws {
        let (draft, _) = try makeProtectedRecording()
        CaptureDraftStore.markFailed(id: draft.id, error: noSpeechError)
        CaptureDraftStore.deleteRecording(id: draft.id)
        XCTAssertEqual(CaptureDraftStore.tombstoneCount(), 1)

        CaptureDraftStore.pruneResolvedTombstones(
            now: Date().addingTimeInterval(CaptureDraftStore.tombstoneRetention + 60)
        )

        XCTAssertEqual(CaptureDraftStore.tombstoneCount(), 0)
        XCTAssertFalse(CaptureDraftStore.isDeleted(draft.id))
    }

    /// The window exists so a stale checkpoint that has not landed yet still
    /// loses. Pruning immediately would reopen the hole the tombstone closed.
    func testAFreshTombstoneSurvivesPruning() throws {
        let (draft, _) = try makeProtectedRecording()
        CaptureDraftStore.markFailed(id: draft.id, error: noSpeechError)
        let staleCheckpoint = CaptureDraftStore.snapshot()
        CaptureDraftStore.deleteRecording(id: draft.id)

        CaptureDraftStore.pruneResolvedTombstones()

        XCTAssertTrue(CaptureDraftStore.isDeleted(draft.id))
        CaptureDraftStore.restore(staleCheckpoint)
        XCTAssertTrue(CaptureDraftStore.recoverableAudioDrafts(minimumAge: 0).isEmpty)
    }

    /// A leftover audio file is exactly what a tombstone still has to suppress,
    /// however old the deletion is.
    func testATombstoneOutlivesItsRetentionWhileTheAudioFileRemains() throws {
        let (draft, audioURL) = try makeProtectedRecording()
        CaptureDraftStore.markFailed(id: draft.id, error: noSpeechError)
        let staleCheckpoint = CaptureDraftStore.snapshot()
        CaptureDraftStore.deleteRecording(id: draft.id)
        try Data(repeating: 0x1, count: 1_024).write(to: audioURL, options: .atomic)

        CaptureDraftStore.pruneResolvedTombstones(
            now: Date().addingTimeInterval(CaptureDraftStore.tombstoneRetention + 60)
        )

        XCTAssertTrue(CaptureDraftStore.isDeleted(draft.id))
        CaptureDraftStore.restore(staleCheckpoint)
        XCTAssertTrue(
            CaptureDraftStore.recoverableAudioDrafts(minimumAge: 0).isEmpty,
            "An orphaned recording file must not outlive the person's decision"
        )
    }

    func testTombstonesStayBoundedUnderRepeatedDeletions() throws {
        for _ in 0..<80 {
            let draft = CaptureDraftStore.begin(source: .inAppVoice)
            let url = try XCTUnwrap(CaptureDraftStore.prepareAudioURL(for: draft))
            try Data(repeating: 0x1, count: 1_024).write(to: url, options: .atomic)
            CaptureDraftStore.markFailed(id: draft.id, error: noSpeechError)
            CaptureDraftStore.deleteRecording(id: draft.id)
        }

        XCTAssertLessThanOrEqual(
            CaptureDraftStore.tombstoneCount(),
            50,
            "Deleting failed captures must not grow UserDefaults without bound"
        )
        XCTAssertTrue(CaptureDraftStore.recoverableAudioDrafts(minimumAge: 0).isEmpty)
    }

    func testAnUnrecognizedNoSpeechErrorIsStillClassifiedByItsWording() {
        let opaque = NSError(
            domain: "SomeOtherDomain",
            code: 42,
            userInfo: [NSLocalizedDescriptionKey: "No speech detected"]
        )
        XCTAssertEqual(CaptureRecoveryFailureKind(error: opaque), .noSpeechDetected)
    }

    // MARK: - An incomplete pass is never the whole recording

    /// Every caller saves a success and then deletes the recording, so a pass
    /// that stopped before the end has to come back as a failure.
    private func incompleteFailure(
        _ result: Result<String, Error>,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> Error? {
        switch result {
        case .success(let text):
            XCTFail("Reported as the whole recording: \(text)", file: file, line: line)
            return nil
        case .failure(let error):
            return error
        }
    }

    /// Falsifier: the timeout branch returning `.success(latest)` again, as it
    /// did before, fails the unwrap below.
    func testATimedOutPassWithWordsSoFarIsNeverReportedAsComplete() throws {
        let error = try XCTUnwrap(incompleteFailure(
            CaptureAudioRecovery.outcome(latest: " buy milk and call ", ending: .timedOut)
        ))

        XCTAssertEqual(CaptureRecoveryFailureKind(error: error), .timedOut)
        XCTAssertFalse(
            CaptureRecoveryFailureKind(error: error).stopsPromisingRecovery,
            "Another attempt has to stay on offer"
        )
        XCTAssertEqual(CaptureAudioRecovery.partialTranscript(in: error), "buy milk and call")
    }

    /// Falsifier: the error branch returning `.success(latest)` fails the
    /// unwrap; forwarding the recognizer's own no-speech error fails the kind,
    /// because words were found and the row would stop offering a retry.
    func testAnErroredPassWithWordsSoFarIsNeverReportedAsComplete() throws {
        let error = try XCTUnwrap(incompleteFailure(
            CaptureAudioRecovery.outcome(
                latest: "buy milk and call",
                ending: .failed(noSpeechError)
            )
        ))

        XCTAssertEqual(CaptureRecoveryFailureKind(error: error), .unknown)
        XCTAssertFalse(CaptureRecoveryFailureKind(error: error).stopsPromisingRecovery)
        XCTAssertEqual(CaptureAudioRecovery.partialTranscript(in: error), "buy milk and call")
    }

    /// Falsifier: a final result that fails, or that hands back the older
    /// partial instead of the final text, fails the equality.
    func testOnlyAFinalResultIsReportedAsComplete() throws {
        let result = CaptureAudioRecovery.outcome(
            latest: "buy milk",
            ending: .finished("buy milk and call mom")
        )

        XCTAssertEqual(try result.get(), "buy milk and call mom")
    }

    /// Falsifier: treating whitespace as words would report partial text, and
    /// losing the forwarded error would stop a no-speech recording from
    /// being described as one.
    func testAPassThatReadNothingKeepsItsExistingFailure() throws {
        for latest in [nil, "", "   "] as [String?] {
            let timedOut = try XCTUnwrap(incompleteFailure(
                CaptureAudioRecovery.outcome(latest: latest, ending: .timedOut)
            ))
            XCTAssertEqual(CaptureRecoveryFailureKind(error: timedOut), .timedOut)
            XCTAssertNil(CaptureAudioRecovery.partialTranscript(in: timedOut))

            let failed = try XCTUnwrap(incompleteFailure(
                CaptureAudioRecovery.outcome(latest: latest, ending: .failed(noSpeechError))
            ))
            XCTAssertEqual(CaptureRecoveryFailureKind(error: failed), .noSpeechDetected)
            XCTAssertNil(CaptureAudioRecovery.partialTranscript(in: failed))
        }
    }

    /// What a caller does with an incomplete pass: the words it read are kept
    /// beside the recording, and the recording stays listed for another try.
    /// Falsifier: keeping the words by any route that releases the draft or
    /// the audio, or letting a shorter pass shrink a longer checkpoint.
    ///
    /// This test calls `keepRecoveredWords` itself, so on its own it does not
    /// notice that call being deleted from `transcribe`.
    /// `testTranscribeStoresTheWordsAnIncompletePassRead` pins that edge
    /// through the `reading:` seam.
    func testAnIncompletePassKeepsTheRecordingAndTheWordsItRead() throws {
        let (draft, audioURL) = try makeProtectedRecording()
        CaptureDraftStore.update(id: draft.id, transcript: "buy milk")
        let error = try XCTUnwrap(incompleteFailure(
            CaptureAudioRecovery.outcome(latest: "buy milk and call the", ending: .timedOut)
        ))
        let partial = try XCTUnwrap(CaptureAudioRecovery.partialTranscript(in: error))

        CaptureDraftStore.keepRecoveredWords(partial, id: draft.id)
        CaptureDraftStore.markFailed(id: draft.id, error: error)

        XCTAssertTrue(FileManager.default.fileExists(atPath: audioURL.path))
        let stored = try XCTUnwrap(CaptureDraftStore.draft(id: draft.id))
        XCTAssertEqual(stored.transcript, "buy milk and call the")
        XCTAssertEqual(stored.recoveryFailureKind, .timedOut)
        XCTAssertEqual(CaptureRecoveryPresentation.row(for: stored).title, "Needs attention")
        XCTAssertEqual(
            CaptureDraftStore.recoverableAudioDrafts(minimumAge: 0).map(\.id),
            [draft.id]
        )

        CaptureDraftStore.keepRecoveredWords("buy", id: draft.id)
        XCTAssertEqual(CaptureDraftStore.draft(id: draft.id)?.transcript, "buy milk and call the")
    }

    /// The edge from `transcribe` to the draft, with the recognition pass
    /// replaced by the failure an incomplete pass produces. Falsifier: deleting
    /// the `keepRecoveredWords` call from `transcribe(_:reading:)` leaves the
    /// stored transcript at `"buy milk"`; returning the partial as a success
    /// fails the `XCTFail`.
    ///
    /// Not covered, because both need a recognizer or a view: that
    /// `transcribeAudio(at:)` really ends its timed-out and errored passes
    /// through `outcome`, and that the capture screen's `recoverActiveAudio`
    /// reads the stored words back before it switches to typing.
    func testTranscribeStoresTheWordsAnIncompletePassRead() async throws {
        let (draft, audioURL) = try makeProtectedRecording()
        CaptureDraftStore.update(id: draft.id, transcript: "buy milk")
        let pass = CaptureAudioRecovery.outcome(latest: "buy milk and call the", ending: .timedOut)

        do {
            let text = try await CaptureAudioRecovery.transcribe(draft, reading: { _ in
                try pass.get()
            })
            XCTFail("Reported as the whole recording: \(text)")
        } catch {
            XCTAssertEqual(CaptureRecoveryFailureKind(error: error), .timedOut)
        }

        XCTAssertEqual(CaptureDraftStore.draft(id: draft.id)?.transcript, "buy milk and call the")
        XCTAssertTrue(FileManager.default.fileExists(atPath: audioURL.path))
    }

    /// After a failed pass the capture screen offers the kept words only when
    /// they carry on from what the live recognizer showed, compared without
    /// case or punctuation. Falsifiers: seeding from the live transcript alone
    /// (the old behaviour) fails the first assertion; a longer-text-wins rule
    /// fails the third, dropping "mom", which the person had already seen.
    func testTheCaptureScreenOffersKeptWordsOnlyWhenTheyCarryOnFromTheLiveOnes() {
        XCTAssertEqual(
            CaptureAudioRecovery.wordsToOffer(
                live: "buy milk and call",
                kept: "Buy milk, and call the plumber"
            ),
            "Buy milk, and call the plumber"
        )
        XCTAssertEqual(
            CaptureAudioRecovery.wordsToOffer(live: "buy milk and call the", kept: "buy milk and call"),
            "buy milk and call the"
        )
        XCTAssertEqual(
            CaptureAudioRecovery.wordsToOffer(
                live: "buy milk and call mom",
                kept: "Buy milk, and call the plumber"
            ),
            "buy milk and call mom"
        )
        // A kept word that only starts with the live one changes that word.
        XCTAssertEqual(
            CaptureAudioRecovery.wordsToOffer(live: "buy milk", kept: "buy milkshake"),
            "buy milk"
        )
        for live in ["", "   "] {
            XCTAssertEqual(
                CaptureAudioRecovery.wordsToOffer(live: live, kept: "buy milk and call"),
                "buy milk and call"
            )
        }
        XCTAssertEqual(
            CaptureAudioRecovery.wordsToOffer(live: " buy milk and call ", kept: ""),
            "buy milk and call"
        )
    }
}
