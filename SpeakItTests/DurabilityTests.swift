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
    private final class RecordingDelivery: @unchecked Sendable {
        private(set) var pendingNotifications: Set<String> = []
        private(set) var scheduledAlarms: Set<UUID> = []

        func seedNotification(_ identifier: String) { pendingNotifications.insert(identifier) }
        func seedAlarm(_ id: UUID) { scheduledAlarms.insert(id) }

        var sink: ReminderDeliverySink {
            ReminderDeliverySink(
                removeNotifications: { [self] identifiers in
                    identifiers.forEach { pendingNotifications.remove($0) }
                },
                cancelAlarm: { [self] id in scheduledAlarms.remove(id) },
                pendingIdentifiers: { [self] in Array(pendingNotifications) }
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
        status: ProcessingStatus = .pending
    ) throws -> UUID {
        let session = CaptureSession(
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
            .recognizerUnavailable, .timedOut, .cancelled, .storageUnavailable, .unknown
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
}
