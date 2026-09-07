import SwiftData
import XCTest
@testable import SpeakIt

/// Cancel, complete and retract, driven through the real repository against a
/// real store.
///
/// These exist because the extractor understanding "cancel the dentist
/// reminder" is only half the feature. The half that matters to a person is
/// whether the reminder actually stops arriving — and the failure that would
/// hurt most is the opposite one, where a loose match cancels something they
/// still needed and they only discover it when it never goes off.
@MainActor
final class CaptureOperationTests: XCTestCase {
    private var container: ModelContainer!
    private var repository: SwiftDataThoughtRepository!
    private var previousRecurrences: [RecurrenceRecordSnapshot] = []
    private var delivery: RecordingDelivery!
    private var previousDelivery: ReminderDeliverySink!

    /// Stands in for the two systems a reminder actually lives in, so a test
    /// can prove the notification and the alarm are gone rather than only that
    /// the SwiftData row is.
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
                cancelAlarm: { [self] id in
                    scheduledAlarms.remove(id)
                },
                pendingIdentifiers: { [self] in Array(pendingNotifications) }
            )
        }
    }

    override func setUpWithError() throws {
        previousRecurrences = RecurrenceStore.snapshots()
        delivery = RecordingDelivery()
        previousDelivery = ReminderScheduler.delivery
        ReminderScheduler.delivery = delivery.sink
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(
            for: PersistenceController.schema,
            migrationPlan: SpeakItMigrationPlan.self,
            configurations: [configuration]
        )
        repository = SwiftDataThoughtRepository(
            modelContext: container.mainContext,
            requestsReminderAuthorization: false
        )
    }

    override func tearDownWithError() throws {
        ReminderScheduler.delivery = previousDelivery
        RecurrenceStore.restore(previousRecurrences)
        repository = nil
        container = nil
    }

    // MARK: Helpers

    private func capture(_ text: String) async throws -> CaptureCreationResult {
        try await repository.createCaptureResult(
            text: text,
            source: .inAppText,
            createdAt: .now,
            schedulesReminders: false
        )
    }

    private func allItems() throws -> [CapturedItem] {
        try container.mainContext.fetch(FetchDescriptor<CapturedItem>())
    }

    private func activeTitles() throws -> [String] {
        try allItems()
            .filter { $0.completedAt == nil && !$0.isArchived }
            .map(\.displayTitle)
    }

    // MARK: Cancel

    func testCancelRemovesTheOneMatchingActiveItem() async throws {
        _ = try await capture("Remind me about the dentist on Friday")
        _ = try await capture("Buy milk")

        let result = try await capture("Cancel the dentist reminder")

        guard case let .performed(operation, _, title) = try XCTUnwrap(result.operationOutcome) else {
            return XCTFail("Expected the cancellation to be performed")
        }
        XCTAssertEqual(operation, .cancel)
        XCTAssertTrue(title.localizedCaseInsensitiveContains("dentist"))

        let remaining = try activeTitles()
        XCTAssertFalse(remaining.contains { $0.localizedCaseInsensitiveContains("dentist") })
        XCTAssertTrue(remaining.contains { $0.localizedCaseInsensitiveContains("milk") },
                      "Cancelling one item must not disturb the others")
    }

    func testCancellationCreatesNoItemOfItsOwn() async throws {
        _ = try await capture("Remind me about the dentist on Friday")
        let before = try allItems().count

        let result = try await capture("Cancel the dentist reminder")

        XCTAssertTrue(result.items.isEmpty, "A cancellation is not a new thought")
        XCTAssertEqual(try allItems().count, before - 1)
    }

    func testCancellationNeverReachesIntoMemory() async throws {
        // "Cancel my milk reminder" once deleted "Sarah likes oat milk" — a
        // person fact, not a reminder — because the matcher searched every
        // active item. Knowledge is not a commitment and is never a candidate.
        _ = try await capture("Remember that Sarah likes oat milk")
        _ = try await capture("Remind me to buy milk tomorrow")

        let result = try await capture("Cancel my milk reminder")

        guard case let .performed(operation, _, title) = try XCTUnwrap(result.operationOutcome) else {
            return XCTFail("Expected the one real reminder to be cancelled")
        }
        XCTAssertEqual(operation, .cancel)
        XCTAssertTrue(title.localizedCaseInsensitiveContains("buy milk"))

        let remaining = try activeTitles()
        XCTAssertTrue(
            remaining.contains { $0.localizedCaseInsensitiveContains("oat milk") },
            "the fact about Sarah must still be standing, got \(remaining)"
        )
    }

    func testCancellationWithOnlyAMemoryMatchFindsNothing() async throws {
        _ = try await capture("Remember that Sarah likes oat milk")

        let result = try await capture("Cancel my milk reminder")

        guard case .notFound = try XCTUnwrap(result.operationOutcome) else {
            return XCTFail("A memory is not a reminder; nothing should match")
        }
        XCTAssertTrue(
            try activeTitles().contains { $0.localizedCaseInsensitiveContains("oat milk") },
            "the fact survives the failed lookup untouched"
        )
    }

    func testCancelWithSeveralMatchesAsksInsteadOfGuessing() async throws {
        let first = try await capture("Call Mom on Friday")
        let second = try await capture("Call Mom about the tickets")
        let originalIDs = Set([first.primaryItem.id, second.primaryItem.id])

        let result = try await capture("Cancel the call Mom reminder")

        guard case let .ambiguous(_, candidateIDs) = try XCTUnwrap(result.operationOutcome) else {
            return XCTFail("Expected ambiguity rather than a guess")
        }
        XCTAssertGreaterThan(candidateIDs.count, 1)

        // Nothing may be destroyed while the question is open. The ambiguous
        // capture itself stays as a review row, which is where the person
        // chooses — so assert on the original items rather than on a title
        // search that the review row would also satisfy.
        let surviving = Set(try allItems().map(\.id))
        XCTAssertTrue(originalIDs.isSubset(of: surviving))
    }

    func testVagueTargetIsNeverResolvedAutomatically() async throws {
        _ = try await capture("Remind me about the dentist on Friday")

        let result = try await capture("Don't remind me about that")

        guard case .ambiguous = try XCTUnwrap(result.operationOutcome) else {
            return XCTFail("A pronoun target must be confirmed, not guessed")
        }
        XCTAssertTrue(try activeTitles().contains { $0.localizedCaseInsensitiveContains("dentist") })
    }

    func testCancelWithNoMatchInventsNothing() async throws {
        _ = try await capture("Buy milk")

        let result = try await capture("Cancel the dentist reminder")

        guard case let .notFound(_, target) = try XCTUnwrap(result.operationOutcome) else {
            return XCTFail("Expected a not-found result")
        }
        XCTAssertTrue(target.localizedCaseInsensitiveContains("dentist"))
        // No fake reminder, and no Memory item standing in for the request.
        XCTAssertEqual(try activeTitles(), ["Buy milk"])
    }

    func testBroadCancellationIsNeverExecutedAutomatically() async throws {
        _ = try await capture("Buy milk")
        _ = try await capture("Call Mom on Friday")
        let before = try activeTitles().count

        let result = try await capture("Cancel every reminder")

        guard case .needsConfirmation = try XCTUnwrap(result.operationOutcome) else {
            return XCTFail("A broad destructive request must require confirmation")
        }
        XCTAssertEqual(
            try allItems().filter { $0.completedAt == nil && !$0.isArchived && $0.displayTitle != "Cancel every reminder" }.count,
            before,
            "Nothing may be destroyed without confirmation"
        )
    }

    func testConfirmingAHeldBroadCancellationCancelsEverythingAndRemovesTheReviewRow() async throws {
        _ = try await capture("Buy milk")
        _ = try await capture("Call Mom on Friday")

        let result = try await capture("Cancel every reminder")
        guard case .needsConfirmation = try XCTUnwrap(result.operationOutcome) else {
            return XCTFail("Expected a held broad cancellation")
        }
        let reviewRow = try XCTUnwrap(
            try allItems().first { $0.displayTitle.localizedCaseInsensitiveContains("cancel every reminder") }
        )
        XCTAssertEqual(reviewRow.clarificationRequirement, .pendingOperation)

        try repository.confirmPendingOperation(reviewRow)

        // Everything the request named is gone, and so is the review row
        // itself — it was only ever the confirmation vehicle, not a thought
        // worth keeping once its request is resolved.
        XCTAssertTrue(try allItems().isEmpty)
        XCTAssertNil(PendingOperationStore.record(for: reviewRow.id))
    }

    func testDecliningAHeldBroadCancellationChangesNothing() async throws {
        _ = try await capture("Buy milk")
        _ = try await capture("Call Mom on Friday")
        let before = Set(try activeTitles())

        let result = try await capture("Cancel every reminder")
        guard case .needsConfirmation = try XCTUnwrap(result.operationOutcome) else {
            return XCTFail("Expected a held broad cancellation")
        }
        let reviewRow = try XCTUnwrap(
            try allItems().first { $0.displayTitle.localizedCaseInsensitiveContains("cancel every reminder") }
        )

        try repository.dismissPendingOperation(reviewRow)

        XCTAssertEqual(Set(try activeTitles()), before, "Declining must leave every existing item untouched")
        XCTAssertNil(try allItems().first { $0.id == reviewRow.id }, "The review row itself is resolved, not left behind")
        XCTAssertNil(PendingOperationStore.record(for: reviewRow.id))
    }

    func testRepeatedCancellationOfTheSameThingIsHarmless() async throws {
        _ = try await capture("Remind me about the dentist on Friday")
        _ = try await capture("Buy milk")

        let first = try await capture("Cancel the dentist reminder")
        let second = try await capture("Cancel the dentist reminder")

        guard case .performed = try XCTUnwrap(first.operationOutcome) else {
            return XCTFail("Expected the first cancellation to act")
        }
        guard case .notFound = try XCTUnwrap(second.operationOutcome) else {
            return XCTFail("Expected the repeat to find nothing rather than act again")
        }
        XCTAssertEqual(try activeTitles(), ["Buy milk"])
    }

    func testCancellingARecurringItemRemovesItsRule() async throws {
        _ = try await capture("Remind me every Friday to submit my timesheet")
        let item = try XCTUnwrap(try allItems().first { $0.displayTitle.localizedCaseInsensitiveContains("timesheet") })
        let itemID = item.id
        XCTAssertNotNil(RecurrenceStore.rule(for: itemID), "Precondition: the rule exists")

        _ = try await capture("Cancel the timesheet reminder")

        XCTAssertNil(
            RecurrenceStore.rule(for: itemID),
            "A cancelled repeat must not keep firing"
        )
    }

    // MARK: Complete

    func testCompleteMarksTheMatchingItemDone() async throws {
        _ = try await capture("Call Mom on Friday")

        let result = try await capture("I already called Mom")

        guard case let .performed(operation, itemID, _) = try XCTUnwrap(result.operationOutcome) else {
            return XCTFail("Expected the completion to be performed")
        }
        XCTAssertEqual(operation, .complete)
        let item = try XCTUnwrap(try allItems().first { $0.id == itemID })
        XCTAssertNotNil(item.completedAt)
    }

    func testCompletingSomethingAlreadyCompletedFindsNothingActive() async throws {
        _ = try await capture("Call Mom on Friday")
        _ = try await capture("I already called Mom")

        let second = try await capture("I already called Mom")

        guard case .notFound = try XCTUnwrap(second.operationOutcome) else {
            return XCTFail("Completed items are out of scope for a second completion")
        }
    }

    func testCompletionNeverReachesTheCompletedLog() async throws {
        _ = try await capture("Buy milk")
        let item = try XCTUnwrap(try allItems().first { $0.displayTitle == "Buy milk" })
        try repository.setCompleted(item, completed: true)

        let result = try await capture("Cancel the milk reminder")

        guard case .notFound = try XCTUnwrap(result.operationOutcome) else {
            return XCTFail("An already-completed item must not be cancelled out from under the log")
        }
        XCTAssertNotNil(item.completedAt, "The completed row stays exactly as it was")
    }

    // MARK: Reschedule

    func testRescheduleMovesTheReminderToTheSpokenDay() async throws {
        _ = try await capture("Remind me to call the dentist tomorrow at 2 PM")

        let result = try await capture("Move the dentist reminder to Friday")

        guard case let .performed(operation, itemID, _) = try XCTUnwrap(result.operationOutcome) else {
            return XCTFail("Expected the reschedule to be performed")
        }
        XCTAssertEqual(operation, .reschedule)
        let item = try XCTUnwrap(try allItems().first { $0.id == itemID })
        let moved = try XCTUnwrap(item.reminderDate)
        XCTAssertEqual(Calendar.current.component(.weekday, from: moved), 6,
                       "The reminder must land on a Friday")
        XCTAssertGreaterThan(moved, .now)
        XCTAssertNil(item.completedAt, "A reschedule must never complete or remove the item")
    }

    func testPushBackMovesRelativeToTheScheduledMomentNotTheClock() async throws {
        _ = try await capture("Remind me to call the dentist tomorrow at 2 PM")
        let before = try XCTUnwrap(try allItems()
            .first { $0.displayTitle.localizedCaseInsensitiveContains("dentist") }?.reminderDate)

        let result = try await capture("Push the dentist back an hour")

        guard case let .performed(operation, itemID, _) = try XCTUnwrap(result.operationOutcome) else {
            return XCTFail("Expected the push back to be performed")
        }
        XCTAssertEqual(operation, .reschedule)
        let item = try XCTUnwrap(try allItems().first { $0.id == itemID })
        XCTAssertEqual(item.reminderDate, before.addingTimeInterval(3600),
                       "Back an hour is measured from the scheduled 2 PM, not from now")
    }

    func testRescheduleWithNoDestinationAsksInsteadOfGuessing() async throws {
        _ = try await capture("Remind me to call the dentist tomorrow at 2 PM")
        let before = try allItems()
            .first { $0.displayTitle.localizedCaseInsensitiveContains("dentist") }?.reminderDate

        let result = try await capture("Postpone the dentist")

        guard case let .ambiguous(operation, candidateIDs) = try XCTUnwrap(result.operationOutcome) else {
            return XCTFail("Expected a held reschedule, not a silent guess")
        }
        XCTAssertEqual(operation, .reschedule)
        XCTAssertEqual(candidateIDs.count, 1)
        let after = try allItems()
            .first { $0.displayTitle.localizedCaseInsensitiveContains("dentist") }?.reminderDate
        XCTAssertEqual(after, before, "Nothing may move until the person names the new moment")
    }

    func testMoveWithANonTimeDestinationStaysAnOrdinaryCapture() async throws {
        let result = try await capture("Move the couch to the garage")

        XCTAssertNil(result.operationOutcome, "A physical move is a task, not a reschedule")
        XCTAssertEqual(result.items.count, 1)
        XCTAssertTrue(try activeTitles().contains { $0.localizedCaseInsensitiveContains("couch") })
    }

    // MARK: Retract

    func testRetractionCreatesNothingAtAll() async throws {
        _ = try await capture("Buy milk")
        let before = try allItems().count

        let result = try await capture("Actually never mind")

        guard case .retracted = try XCTUnwrap(result.operationOutcome) else {
            return XCTFail("Expected a retraction")
        }
        XCTAssertTrue(result.items.isEmpty)
        XCTAssertEqual(try allItems().count, before, "A retraction must not leave a fallback item behind")
    }

    func testRetractionSurvivesRelaunchWithoutReappearing() async throws {
        _ = try await capture("Wait no forget that")
        XCTAssertTrue(try allItems().isEmpty)

        // The recovery pass the app runs at every launch.
        repository.recoverUnorganizedCaptures()
        repository.reconcilePendingReminders()

        XCTAssertTrue(
            try allItems().isEmpty,
            "Launch recovery must not rebuild a withdrawn capture into an item"
        )
    }

    func testRetractionKeepsTheTranscriptForProvenance() async throws {
        let result = try await capture("Actually never mind")

        let sessions = try container.mainContext.fetch(FetchDescriptor<CaptureSession>())
        let session = try XCTUnwrap(sessions.first { $0.id == result.session.id })
        XCTAssertEqual(session.originalTranscription, "Actually never mind")
        XCTAssertTrue(session.items.isEmpty)
    }

    // MARK: Free capture accounting

    func testOperationsDoNotSpendAFreeCapture() async throws {
        _ = try await capture("Remind me about the dentist on Friday")

        let cancelled = try await capture("Cancel the dentist reminder")
        let retracted = try await capture("Actually never mind")
        let missing = try await capture("Cancel the plumber reminder")

        XCTAssertFalse(cancelled.consumesFreeCapture)
        XCTAssertFalse(retracted.consumesFreeCapture)
        XCTAssertFalse(missing.consumesFreeCapture)
    }

    func testOrdinaryCaptureStillSpendsAFreeCapture() async throws {
        let result = try await capture("Buy toothpaste")
        XCTAssertTrue(result.consumesFreeCapture)
        XCTAssertNil(result.operationOutcome)
    }

    func testTutorialCaptureIsComplimentaryAndMissionsReachExpectedDestinations() async throws {
        let action = try await repository.createCaptureResult(
            text: TutorialCaptureMission.action.example,
            source: .tutorial,
            createdAt: .now,
            schedulesReminders: false
        )
        XCTAssertFalse(action.consumesFreeCapture)
        XCTAssertEqual(action.session.captureSource, .tutorial)
        XCTAssertTrue(action.primaryItem.belongsInToday)
        XCTAssertEqual(
            MemoryPersonNameResolver.name(for: action.primaryItem)?.lowercased(),
            "maya"
        )
        XCTAssertNotNil(action.primaryItem.dueDate)

        let idea = try await repository.createCaptureResult(
            text: TutorialCaptureMission.idea.example,
            source: .tutorial,
            createdAt: .now.addingTimeInterval(1),
            schedulesReminders: false
        )
        XCTAssertFalse(idea.consumesFreeCapture)
        XCTAssertEqual(idea.primaryItem.itemType, .idea)
        XCTAssertTrue(idea.primaryItem.belongsInMemory)
    }

    func testTutorialCleanupIsScopedIdempotentAndCreatesNoCloudTombstones() async throws {
        let previousPins = Array(MemoryPinStore.records().values)
        let previousStages = Array(IdeaStageStore.records().values)
        let previousGroups = ShoppingGroupStore.snapshot()
        let previousDeletions = ICloudDeletionStore.records()
        defer {
            MemoryPinStore.restore(previousPins)
            IdeaStageStore.restore(previousStages)
            ShoppingGroupStore.restore(previousGroups)
            ICloudDeletionStore.restore(previousDeletions)
        }

        let real = try await capture("The office door code is 2468")
        let practice = try await repository.createCaptureResult(
            text: TutorialCaptureMission.idea.example,
            source: .tutorial,
            createdAt: .now.addingTimeInterval(1),
            schedulesReminders: false
        )
        let practiceID = practice.primaryItem.id
        MemoryPinStore.setPinned(true, for: practiceID)
        IdeaStageStore.setStage(.promising, for: practiceID)
        ShoppingGroupStore.set("Practice", for: practiceID)

        XCTAssertEqual(try repository.deleteTutorialCaptures(), 1)
        XCTAssertEqual(try repository.deleteTutorialCaptures(), 0)

        let sessions = try container.mainContext.fetch(FetchDescriptor<CaptureSession>())
        XCTAssertTrue(sessions.contains { $0.id == real.session.id })
        XCTAssertFalse(sessions.contains { $0.captureSource == .tutorial })
        XCTAssertNil(MemoryPinStore.records()[practiceID])
        XCTAssertNil(IdeaStageStore.records()[practiceID])
        XCTAssertNil(ShoppingGroupStore.group(for: practiceID))
        XCTAssertEqual(ICloudDeletionStore.records(), previousDeletions)
    }

    // MARK: Confirmation copy

    func testConfirmationDescribesTheOperationRatherThanSaying() throws {
        let cancelled = CaptureOperationCopy.make(
            for: .performed(operation: .cancel, itemID: UUID(), title: "Dentist reminder")
        )
        XCTAssertEqual(cancelled.title, "Cancelled")
        XCTAssertEqual(cancelled.detail, "Dentist reminder")

        let completed = CaptureOperationCopy.make(
            for: .performed(operation: .complete, itemID: UUID(), title: "Call Mom")
        )
        XCTAssertEqual(completed.title, "Completed")
        XCTAssertEqual(completed.detail, "Call Mom")

        XCTAssertNotEqual(CaptureOperationCopy.make(for: .retracted).title, "Remembered")
    }

    // MARK: Matching discipline

    func testMatcherRequiresEveryMeaningfulWordOfTheTarget() async throws {
        _ = try await capture("Buy toothpaste")

        // "to" must not prefix-match "toothpaste" and cancel an unrelated errand.
        let result = try await capture("Cancel the tooth fairy reminder")

        guard case .notFound = try XCTUnwrap(result.operationOutcome) else {
            return XCTFail("A partial word overlap must not be enough to destroy an item")
        }
        XCTAssertEqual(try activeTitles(), ["Buy toothpaste"])
    }
}


// MARK: - External delivery teardown

extension CaptureOperationTests {

    /// A cancelled reminder must stop *arriving*, which is a different claim
    /// from its row being deleted. This asserts the exact pending request for
    /// the item is the one removed, and that a neighbouring reminder is
    /// untouched — an over-broad removal would be invisible to a row-count
    /// assertion and very visible to a person.
    func testCancellingRemovesTheExactPendingNotification() async throws {
        _ = try await capture("Remind me about the dentist on Friday")
        _ = try await capture("Remind me about the passport on Friday")

        let dentist = try XCTUnwrap(
            try allItems().first { $0.displayTitle.localizedCaseInsensitiveContains("dentist") }
        )
        let passport = try XCTUnwrap(
            try allItems().first { $0.displayTitle.localizedCaseInsensitiveContains("passport") }
        )

        let dentistIdentifier = ReminderScheduler.notificationIdentifier(for: dentist.id)
        let passportIdentifier = ReminderScheduler.notificationIdentifier(for: passport.id)
        delivery.seedNotification(dentistIdentifier)
        delivery.seedNotification(passportIdentifier)

        let result = try await capture("Cancel the dentist reminder")

        guard case .performed = try XCTUnwrap(result.operationOutcome) else {
            return XCTFail("Expected the cancellation to be performed")
        }
        XCTAssertFalse(
            delivery.pendingNotifications.contains(dentistIdentifier),
            "The cancelled reminder's pending notification must be removed"
        )
        XCTAssertTrue(
            delivery.pendingNotifications.contains(passportIdentifier),
            "Cancelling one reminder must not remove another's notification"
        )
    }

    /// The alarm equivalent. An alarm that survives its item is worse than a
    /// stale notification: it takes over the screen at 7 AM for something the
    /// person explicitly cancelled.
    func testCancellingAnAlarmTearsDownTheAlarmKitAlarm() async throws {
        _ = try await capture("Set an alarm for 7 AM to take my pills")

        let item = try XCTUnwrap(
            try allItems().first { $0.displayTitle.localizedCaseInsensitiveContains("pills") }
        )
        XCTAssertEqual(
            ReminderDelivery.alarm,
            ThoughtOrganizer.organize("Set an alarm for 7 AM to take my pills").reminderDelivery,
            "Precondition: this phrasing is an alarm, not a notification"
        )

        delivery.seedAlarm(item.id)
        let unrelated = UUID()
        delivery.seedAlarm(unrelated)

        let result = try await capture("Cancel the pills alarm")

        guard case .performed = try XCTUnwrap(result.operationOutcome) else {
            return XCTFail("Expected the cancellation to be performed")
        }
        XCTAssertFalse(
            delivery.scheduledAlarms.contains(item.id),
            "A cancelled alarm must be cancelled in AlarmKit, not just deleted from the store"
        )
        XCTAssertTrue(delivery.scheduledAlarms.contains(unrelated))
    }

    /// Completion also has to stop delivery. Marking something done while its
    /// reminder still fires is the same failure wearing a different label.
    func testCompletingTearsDownPendingDelivery() async throws {
        _ = try await capture("Remind me to call Mom on Friday")
        let item = try XCTUnwrap(
            try allItems().first { $0.displayTitle.localizedCaseInsensitiveContains("mom") }
        )
        let identifier = ReminderScheduler.notificationIdentifier(for: item.id)
        delivery.seedNotification(identifier)

        let result = try await capture("I already called Mom")

        guard case .performed = try XCTUnwrap(result.operationOutcome) else {
            return XCTFail("Expected the completion to be performed")
        }
        XCTAssertFalse(delivery.pendingNotifications.contains(identifier))
    }

    func testSuccessfulCancellationKeepsIndependentShoppingItem() async throws {
        _ = try await capture("Remind me to call the dentist tomorrow")
        let result = try await capture("Cancel the dentist reminder and buy milk")
        guard case .performed(operation: .cancel, _, _) = result.operationOutcome else {
            return XCTFail("Expected the existing reminder to be cancelled")
        }
        XCTAssertEqual(result.items.count, 1)
        XCTAssertTrue(result.items[0].displayTitle.localizedCaseInsensitiveContains("milk"))
        XCTAssertEqual(result.items[0].itemType, .shopping)
        XCTAssertTrue(result.consumesFreeCapture)
        XCTAssertFalse(try activeTitles().contains { $0.localizedCaseInsensitiveContains("dentist") })
        let retry = try await capture("Cancel the dentist reminder and buy milk")
        XCTAssertTrue(retry.isDuplicate)
        XCTAssertEqual(retry.items.map(\.id), result.items.map(\.id))
    }

    func testAmbiguousCancellationKeepsCreationAndSeparateReview() async throws {
        _ = try await capture("Remind me to call the dentist tomorrow")
        _ = try await capture("Remind me to pay the dentist Friday")
        let result = try await capture("Cancel the dentist reminder and buy milk")
        guard case .ambiguous = result.operationOutcome else { return XCTFail("Expected ambiguity") }
        XCTAssertEqual(result.items.count, 2)
        XCTAssertTrue(result.items.contains { $0.itemType == .shopping && !$0.needsClarification })
        XCTAssertTrue(result.items.contains { $0.needsClarification && $0.originalTextSegment.contains("dentist") })
        XCTAssertEqual(try activeTitles().filter { $0.localizedCaseInsensitiveContains("dentist") }.count, 3)
    }

    func testSynchronousMixedCaptureKeepsNewItem() throws {
        _ = try repository.createCapture(text: "Remind me to call the dentist tomorrow")
        let item = try repository.createCapture(text: "Cancel the dentist reminder and buy milk")
        XCTAssertEqual(item.itemType, .shopping)
        XCTAssertTrue(item.displayTitle.localizedCaseInsensitiveContains("milk"))
    }

    // MARK: A misread operation must not take the capture with it

    /// The capture that named this defect. `CaptureOperationDetector` splits on
    /// `and`, reads "cancel the cable" as a request against an existing row,
    /// finds nothing in the store to act on — and the zero-match branch used to
    /// discard the whole session. All four errands disappeared. Only the
    /// transcript survived, on `CaptureSession`, where nothing surfaces it.
    ///
    /// See the convergence note in Docs/PIPELINE_SWEEP_FINDINGS.md: three separate
    /// sweep lanes reached this same branch.
    func testAMisreadCancellationDoesNotDestroyTheOtherErrands() async throws {
        let result = try await capture(
            "call Rogers about the bill and cancel the cable and keep the internet and ask about the loyalty discount"
        )

        let titles = try activeTitles()
        XCTAssertFalse(titles.isEmpty, "the capture must not vanish, got \(titles)")
        XCTAssertFalse(result.items.isEmpty, "the result must carry the rows it created")
        XCTAssertTrue(
            titles.contains { $0.localizedCaseInsensitiveContains("Rogers") },
            "the first errand must survive, got \(titles)"
        )
        XCTAssertTrue(
            titles.contains { $0.localizedCaseInsensitiveContains("loyalty") },
            "the last errand must survive, got \(titles)"
        )
    }

    /// The same branch reached through a different phrasing, and with a date on
    /// the line: the deposit and the 15th used to go down with the unmatched
    /// "cancel the other waitlist".
    func testAMisreadCancellationKeepsTheDatedErrandBesideIt() async throws {
        _ = try await capture(
            "they need the deposit by the 15th so pay the deposit and cancel the other waitlist"
        )

        let titles = try activeTitles()
        XCTAssertFalse(titles.isEmpty, "the capture must not vanish, got \(titles)")
        XCTAssertTrue(
            titles.contains { $0.localizedCaseInsensitiveContains("deposit") },
            "the errand that had a deadline must survive, got \(titles)"
        )
    }
}

/// The analyzer engine reports finalized segments and a volatile tail
/// separately; the person must always see them stitched into one transcript.
final class TranscriptAssemblyTests: XCTestCase {
    func testVolatileTextFollowsFinalizedSegments() {
        let assembly = TranscriptAssembly()
        assembly.commit("Set an alarm for nine,")
        assembly.replaceVolatile("nine thirty")
        XCTAssertEqual(assembly.transcript, "Set an alarm for nine, nine thirty")
    }

    func testCommitReplacesVolatileGuess() {
        let assembly = TranscriptAssembly()
        assembly.replaceVolatile("by milk")
        assembly.commit("Buy milk")
        assembly.replaceVolatile("and bread")
        XCTAssertEqual(assembly.transcript, "Buy milk and bread")
    }

    func testJoinedDoesNotDoubleSpaces() {
        XCTAssertEqual(TranscriptAssembly.joined("Hello ", "there"), "Hello there")
        XCTAssertEqual(TranscriptAssembly.joined("Hello", "there"), "Hello there")
        XCTAssertEqual(TranscriptAssembly.joined("", "there"), "there")
        XCTAssertEqual(TranscriptAssembly.joined("Hello", ""), "Hello")
    }
}
