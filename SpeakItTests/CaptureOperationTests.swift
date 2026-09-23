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

    /// One finished capture holding one row of a fixed kind. Written directly,
    /// as the store holds it, so the row's type is the test's premise rather
    /// than whatever the organizer makes of a sentence today.
    @discardableResult
    private func insertFinishedRow(
        _ text: String,
        type: ItemType,
        reminderDate: Date? = nil,
        personName: String? = nil,
        needsClarification: Bool = false
    ) throws -> UUID {
        let session = CaptureSession(originalTranscription: text, processingStatus: .complete)
        let row = CapturedItem(
            originalTextSegment: text,
            displayTitle: text,
            itemType: type,
            reminderDate: reminderDate,
            personName: personName,
            needsClarification: needsClarification,
            captureSession: session
        )
        container.mainContext.insert(session)
        container.mainContext.insert(row)
        try container.mainContext.save()
        return row.id
    }

    private struct MemoryRows {
        let note: UUID
        let idea: UUID
        let person: UUID
        /// A knowledge row waiting in Needs review: not in Memory yet, and
        /// still not a commitment.
        let heldNote: UUID

        var all: Set<UUID> { [note, idea, person, heldNote] }
    }

    private func insertMemoryRows() throws -> MemoryRows {
        let rows = MemoryRows(
            note: try insertFinishedRow("The spare key is under the blue pot", type: .note),
            idea: try insertFinishedRow("A podcast about city parks", type: .idea),
            person: try insertFinishedRow("Sarah likes oat milk", type: .note, personName: "Sarah"),
            heldNote: try insertFinishedRow("Something about the lease", type: .note, needsClarification: true)
        )
        for id in [rows.note, rows.idea, rows.person] {
            let row = try XCTUnwrap(try allItems().first { $0.id == id })
            XCTAssertTrue(row.belongsInMemory, "precondition: \(row.displayTitle) is a Memory row")
        }
        return rows
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

    /// DEL-25. "Cancel all my reminders" is about commitments, and confirming
    /// it used to delete every active row of every other capture: Memory's
    /// notes, ideas and people facts with the tasks, and each capture's
    /// transcript with its last row.
    ///
    /// Falsifiers: listing broad candidates from `activeItems` alone names the
    /// four knowledge rows, fails the outcome's list and the stored record the
    /// prompt counts, and deletes them on confirmation; drawing the line with
    /// `!belongsInMemory` instead of by kind names the held note. A fix that
    /// also left out a note carrying a reminder (Today's, by the person's own
    /// request) fails on the birthday.
    func testAConfirmedBroadCancelNeverReachesMemory() async throws {
        let milkID = try await capture("Buy milk").primaryItem.id
        let momID = try await capture("Call Mom on Friday").primaryItem.id
        let birthdayID = try insertFinishedRow(
            "Priya's birthday",
            type: .note,
            reminderDate: Date.now.addingTimeInterval(86_400)
        )
        let memory = try insertMemoryRows()
        let actions: Set<UUID> = [milkID, momID, birthdayID]

        let broad = try await capture("Cancel all my reminders")

        guard case let .needsConfirmation(operation, candidateIDs) = try XCTUnwrap(broad.operationOutcome) else {
            return XCTFail("A broad cancel must be held for confirmation")
        }
        XCTAssertEqual(operation, .cancel)
        XCTAssertEqual(Set(candidateIDs), actions, "a broad cancel named a Memory row")
        let reviewRow = try XCTUnwrap(try allItems().first { $0.captureSession?.id == broad.session.id })
        // The editor's "Cancel N items?" counts this record, read again.
        let record = try XCTUnwrap(PendingOperationStore.record(for: reviewRow.id))
        XCTAssertEqual(record.candidateIDs.count, actions.count, "the prompt counts rows confirming would not touch")
        XCTAssertEqual(Set(record.candidateIDs), actions)
        XCTAssertEqual(Set(repository.pendingOperationCandidateIDs(for: reviewRow)), actions)

        try repository.confirmPendingOperation(reviewRow)

        XCTAssertEqual(Set(try allItems().map(\.id)), memory.all, "confirming reached past the rows it counted")
        let words = Set(try container.mainContext.fetch(FetchDescriptor<CaptureSession>()).map(\.originalTranscription))
        for kept in ["The spare key is under the blue pot", "A podcast about city parks", "Sarah likes oat milk", "Something about the lease"] {
            XCTAssertTrue(words.contains(kept), "the transcript went with its row: \(kept)")
        }
    }

    /// The list is fixed when the request is held, and the person can turn a
    /// task into a note before confirming. Confirmation reads each row again
    /// (`heldCandidate`), so the note is neither counted nor deleted, and the
    /// count the prompt shows is the number of rows confirming removes.
    ///
    /// Falsifier: a confirm-time check that asks only whether the capture is
    /// organized counts two and deletes the note.
    func testConfirmingSkipsARowEditedIntoANoteSinceItWasHeld() async throws {
        let milkID = try await capture("Buy milk").primaryItem.id
        let momID = try await capture("Call Mom on Friday").primaryItem.id
        let broad = try await capture("Cancel all my reminders")
        let reviewRow = try XCTUnwrap(try allItems().first { $0.captureSession?.id == broad.session.id })
        let held = try XCTUnwrap(PendingOperationStore.record(for: reviewRow.id)).candidateIDs
        XCTAssertEqual(Set(held), [milkID, momID], "precondition: both were held")

        // What the editor's type picker leaves behind.
        let milk = try XCTUnwrap(try allItems().first { $0.id == milkID })
        milk.itemType = .note
        try container.mainContext.save()
        XCTAssertTrue(milk.belongsInMemory, "precondition: the edited row is a Memory note")

        let counted = repository.pendingOperationCandidateIDs(for: reviewRow)
        XCTAssertEqual(counted, [momID], "the prompt counts a row that is now a note")

        try repository.confirmPendingOperation(reviewRow)

        let remaining = Set(try allItems().map(\.id))
        XCTAssertTrue(remaining.contains(milkID), "a row edited into a note was deleted")
        let actedOn = held.filter { !remaining.contains($0) }
        XCTAssertEqual(actedOn.count, counted.count, "the number confirmed is not the number acted on")
    }

    /// A record stored before DEL-25 can name Memory rows, and it waits in
    /// Needs review until the person answers it. Confirming it now counts
    /// and cancels only the action row.
    ///
    /// Falsifier: a confirm-time check that trusts the stored list counts
    /// five and deletes the four knowledge rows.
    func testConfirmingARecordHeldBeforeTheScopeSkipsItsMemoryRows() async throws {
        let milkID = try await capture("Buy milk").primaryItem.id
        let memory = try insertMemoryRows()
        let broad = try await capture("Cancel all my reminders")
        let reviewRow = try XCTUnwrap(try allItems().first { $0.captureSession?.id == broad.session.id })
        let legacy = [milkID, memory.note, memory.idea, memory.person, memory.heldNote]
        PendingOperationStore.set(operation: .cancel, candidateIDs: legacy, for: reviewRow.id)

        let counted = repository.pendingOperationCandidateIDs(for: reviewRow)
        XCTAssertEqual(counted, [milkID], "the prompt counts Memory rows from an old record")

        try repository.confirmPendingOperation(reviewRow)

        let remaining = Set(try allItems().map(\.id))
        XCTAssertEqual(remaining, memory.all, "confirming an old record reached Memory")
        let actedOn = legacy.filter { !remaining.contains($0) }
        XCTAssertEqual(actedOn.count, counted.count, "the number confirmed is not the number acted on")
    }

    /// "Delete all my notes" keeps no noun either, and reads as the same broad
    /// cancel. With only Memory rows in the store it names nothing, and
    /// confirming it resolves the review row and nothing else.
    ///
    /// Falsifier: any list that reaches Memory names the three rows here and
    /// deletes them on confirmation.
    func testABroadRequestWithOnlyMemoryRowsNamesNothing() async throws {
        let memory = try insertMemoryRows()

        let broad = try await capture("Delete all my notes")

        guard case let .needsConfirmation(_, candidateIDs) = try XCTUnwrap(broad.operationOutcome) else {
            return XCTFail("A broad request must be held for confirmation")
        }
        XCTAssertTrue(candidateIDs.isEmpty, "a broad request named Memory rows")
        let reviewRow = try XCTUnwrap(try allItems().first { $0.captureSession?.id == broad.session.id })
        XCTAssertEqual(PendingOperationStore.record(for: reviewRow.id)?.candidateIDs, [])

        try repository.confirmPendingOperation(reviewRow)

        XCTAssertEqual(Set(try allItems().map(\.id)), memory.all)
    }

    /// Complete-all goes through the same list. The rules never read a broad
    /// completion today, but the confirm path carries one (and the
    /// interpretation bridge can report one), so it is driven here directly.
    ///
    /// Falsifier: a scope applied to cancel alone marks the four knowledge
    /// rows done, which moves them out of Memory into Completed.
    func testAConfirmedBroadCompleteNeverReachesMemory() async throws {
        let milkID = try await capture("Buy milk").primaryItem.id
        let momID = try await capture("Call Mom on Friday").primaryItem.id
        let memory = try insertMemoryRows()

        let session = CaptureSession(
            originalTranscription: "Mark all my tasks done",
            processingStatus: .organizing
        )
        let placeholder = CapturedItem(
            originalTextSegment: session.originalTranscription,
            displayTitle: session.originalTranscription,
            processingConfidence: 0,
            needsClarification: true,
            captureSession: session
        )
        container.mainContext.insert(session)
        container.mainContext.insert(placeholder)
        try container.mainContext.save()

        let outcome = repository.applyCaptureOperation(
            CaptureOperationRequest(
                operation: .complete,
                polarity: .positive,
                target: nil,
                sourceQuote: session.originalTranscription,
                needsReview: true,
                isBroad: true
            ),
            session: session
        )

        guard case let .needsConfirmation(operation, candidateIDs) = outcome else {
            return XCTFail("A broad complete must be held for confirmation")
        }
        XCTAssertEqual(operation, .complete)
        XCTAssertEqual(Set(candidateIDs), [milkID, momID])
        XCTAssertEqual(Set(PendingOperationStore.record(for: placeholder.id)?.candidateIDs ?? []), [milkID, momID])

        try repository.confirmPendingOperation(placeholder)

        let items = try allItems()
        for id in [milkID, momID] {
            XCTAssertEqual(items.first { $0.id == id }?.isCompleted, true, "an action row was not completed")
        }
        for id in memory.all {
            let row = try XCTUnwrap(items.first { $0.id == id }, "a Memory row was removed")
            XCTAssertFalse(row.isCompleted, "a Memory row was marked done: \(row.displayTitle)")
        }
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

/// Removal requests: "delete the reminder to call Dave", "get rid of the gym
/// reminder", "remove the grocery list note".
///
/// The defect these close is **positional**. The rule required the container
/// noun — reminder, task, item, note, alarm, entry — to be the *last word of
/// the sentence*, so it recognised "delete the call Dave reminder" and refused
/// "delete the reminder to call Dave": one request, two word orders. Reading
/// the head of the object noun phrase instead is why the cases below are a
/// family rather than a handful of sentences — each is a different way of
/// putting a container noun at the head of a phrase.
///
/// It is **not** a fix for reach. The container vocabulary is unchanged apart
/// from inflection, and `testACalendarNounIsNotYetAContainer` pins the cases
/// that need a decision instead.
///
/// The negative half matters more than the positive half: reading a phrase
/// differently is only safe if the new reading cannot reach an errand, so each
/// shape that must *not* be read as a removal is pinned here beside the shape
/// that must.
final class StoredRowRemovalTests: XCTestCase {

    private func operation(_ text: String) -> CaptureOperationRequest? {
        CaptureOperationDetector.detect(text)
    }

    // MARK: Head-initial — the container noun takes a complement

    func testPostModifiedContainerNounIsARemoval() {
        for utterance in [
            "Delete the reminder to call Dave",
            "Remove the reminder to water the plants",
            "Delete the note about the picnic",
            "Get rid of the alarm for Tuesday",
            "Remove the task to file the expenses",
        ] {
            let request = operation(utterance)
            XCTAssertEqual(request?.operation, .cancel, "\(utterance) is a removal request")
            XCTAssertEqual(request?.needsReview, false, "\(utterance) names its target")
        }
    }

    func testTheContainerNounIsPeeledOffTheTarget() {
        // The words that name the row are the complement, not the frame.
        // Leaving "reminder to" attached means the target never matches.
        XCTAssertEqual(operation("Delete the reminder to call Dave")?.target, "call dave")
        XCTAssertEqual(operation("Get rid of the alarm for Tuesday")?.target, "tuesday")
    }

    // MARK: Head-final — the container noun closes the phrase

    func testPreModifiedContainerNounIsARemoval() {
        for utterance in [
            "Delete the call Dave reminder",
            "Get rid of the gym reminder",
            "Kill the 7am alarm",
            "Delete the pick up the parcel reminder",
            "Remove the grocery list note",
        ] {
            XCTAssertEqual(
                operation(utterance)?.operation, .cancel,
                "\(utterance) is a removal request"
            )
        }
    }

    // MARK: Errands that only look like removals

    func testAnObjectInTheWorldIsStillAnErrand() {
        for utterance in [
            // No container noun anywhere: the old rule declined these too, and
            // the new one has to keep declining them.
            "Delete the old photos",
            "Get rid of the old couch",
            "Clear the table",
            "Drop the rental car off at noon",
            "Remove the sticker from the laptop",
            // A container noun that is the object of a preposition rather than
            // the head of the phrase. This is the shape a head-final rule
            // would swallow, and the reason the preposition test exists.
            "Drop the kids off at the appointment",
            "Drop the forms in at the meeting",
            // A container noun at the head, post-modified by a place instead
            // of by a complement: a sticky note on a fridge.
            "Remove the note from the fridge",
        ] {
            XCTAssertNil(operation(utterance), "\(utterance) is an errand, not a removal")
        }
    }

    // MARK: The vocabulary this rule may not widen on its own

    func testACalendarNounIsNotYetAContainer() {
        // "Remove the dentist appointment" is not recognised, and that is not
        // the positional defect this class closes — "appointment" has never
        // been one of the nouns this family of verbs may act on. Admitting it
        // would let "remove" and "delete" destroy stored rows that only
        // "cancel" can reach today, and "cancel" earns that reach through a
        // guard these verbs do not have (`cancelsAnArrangement`). Which of the
        // two tiers is right is a product decision, so the gap is pinned here
        // rather than quietly closed.
        for utterance in [
            "Remove the dentist appointment",
            "Remove the team meeting",
            "Delete the Friday event",
        ] {
            XCTAssertNil(
                CaptureOperationDetector.detect(utterance),
                "\(utterance) needs a decision about reach, not a wider noun list"
            )
        }
    }

    func testEraseIsNotOneOfTheseVerbs() {
        // The same boundary as `testACalendarNounIsNotYetAContainer`, drawn on
        // the verb rather than the noun. `erase` was not in either pattern this
        // rule replaces, so admitting it here would make "erase the gym
        // reminder" destroy a stored row that today is an ordinary capture —
        // reach, not shape, and not this change's to take.
        //
        // `ThoughtExtractor` does read `erase`, in a rule that carves words out
        // of a sentence rather than one that deletes a row. That is not a
        // precedent for this list, and the test says so out loud because the
        // next person to grep for the word will find it there first.
        for utterance in [
            "Erase the gym reminder",
            "Erase the reminder to call Dave",
        ] {
            XCTAssertNil(
                CaptureOperationDetector.detect(utterance),
                "\(utterance) would need `erase` admitted deliberately, with its own decision"
            )
        }
    }

    func testARelativeClauseIsNotAComplement() {
        // "That" and "which" open a relative clause, and the peel in
        // `cleaned()` has never handled one. Admitting them here recognised
        // the request and then handed `CaptureTargetMatcher` a target with the
        // frame still on it, which matches nothing. Declining outright reaches
        // the same end state — the words stay an ordinary capture — without
        // the detour.
        XCTAssertNil(operation("Delete the note that Dave called"))
        XCTAssertNil(operation("Remove the reminder which I set yesterday"))
    }

    func testAPolitenessMarkerDoesNotHideTheRequest() {
        // New, and small enough to be missed if it is not pinned: neither
        // pattern this rule replaces tolerated a leading "please", so this
        // sentence used to fall through. `cancelsAnArrangement` has always
        // taken one.
        let request = operation("Please delete the gym reminder")
        XCTAssertEqual(request?.operation, .cancel)
        XCTAssertEqual(request?.needsReview, false)
    }

    func testCancellingAnArrangementIsStillAnErrand() {
        // Unchanged by this work, and pinned here because it is the nearest
        // neighbour: cancelling a subscription is something the person does in
        // the world, not something the app does to a row.
        XCTAssertNil(operation("Cancel my gym membership"))
        XCTAssertNil(operation("Cancel my Netflix subscription"))
    }

    // MARK: Naming no particular row

    func testAContainerNounWithNothingElseIsHeldForConfirmation() {
        for utterance in ["Delete my reminders", "Remove the task", "Clear my notes"] {
            let request = operation(utterance)
            XCTAssertEqual(request?.operation, .cancel, "\(utterance) is a removal request")
            XCTAssertEqual(
                request?.needsReview, true,
                "\(utterance) names no particular row, so it is confirmed rather than run"
            )
        }
    }
}

/// The same family driven through the real store, because recognising the
/// request is only half of it: what matters to a person is whether the right
/// row goes and the others stay.
@MainActor
final class StoredRowRemovalStoreTests: XCTestCase {
    private var container: ModelContainer!
    private var repository: SwiftDataThoughtRepository!

    override func setUpWithError() throws {
        container = try ModelContainer(
            for: PersistenceController.schema,
            migrationPlan: SpeakItMigrationPlan.self,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        repository = SwiftDataThoughtRepository(
            modelContext: container.mainContext,
            requestsReminderAuthorization: false
        )
    }

    override func tearDownWithError() throws {
        repository = nil
        container = nil
    }

    private func capture(_ text: String) async throws -> CaptureCreationResult {
        try await repository.createCaptureResult(
            text: text,
            source: .inAppText,
            createdAt: .now,
            schedulesReminders: false
        )
    }

    private func activeTitles() throws -> [String] {
        try container.mainContext.fetch(FetchDescriptor<CapturedItem>())
            .filter { $0.completedAt == nil && !$0.isArchived }
            .map(\.displayTitle)
    }

    func testDeletingAPostModifiedReminderRemovesThatRowAlone() async throws {
        _ = try await capture("Remind me to call Dave tomorrow")
        _ = try await capture("Buy milk")

        let result = try await capture("Delete the reminder to call Dave")

        guard case let .performed(operation, _, title) = try XCTUnwrap(result.operationOutcome) else {
            return XCTFail("Expected the removal to be performed")
        }
        XCTAssertEqual(operation, .cancel)
        XCTAssertTrue(title.localizedCaseInsensitiveContains("dave"))

        let remaining = try activeTitles()
        XCTAssertFalse(remaining.contains { $0.localizedCaseInsensitiveContains("dave") })
        XCTAssertTrue(
            remaining.contains { $0.localizedCaseInsensitiveContains("milk") },
            "removing one row must not disturb the others, got \(remaining)"
        )
    }

    func testAnUnnamedRemovalDestroysNothing() async throws {
        _ = try await capture("Remind me to call Dave tomorrow")
        _ = try await capture("Buy milk")

        let result = try await capture("Delete my reminders")

        guard case .ambiguous = try XCTUnwrap(result.operationOutcome) else {
            return XCTFail("An unnamed removal is confirmed, never run")
        }
        let remaining = try activeTitles()
        XCTAssertTrue(
            remaining.contains { $0.localizedCaseInsensitiveContains("dave") },
            "nothing may be destroyed while the person is still being asked, got \(remaining)"
        )
        XCTAssertTrue(remaining.contains { $0.localizedCaseInsensitiveContains("milk") })
    }

    func testAnErrandThatMentionsAnObjectIsStillCaptured() async throws {
        let result = try await capture("Get rid of the old couch")
        XCTAssertNil(result.operationOutcome, "this is an errand, not an operation")
        XCTAssertFalse(result.items.isEmpty, "the errand must survive as a row")
    }
}
