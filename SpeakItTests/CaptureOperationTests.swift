import SwiftData
import XCTest
@testable import SpeakIt

/// Cancel, complete and retract, driven through the real repository against a
/// real store. The fixture selects deterministic interpretation; dedicated
/// runtime tests exercise proposals and the full reference bank.
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
            requestsReminderAuthorization: false,
            permitsOnDeviceIntelligence: false
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

    func testPluralOwnTasksPersistSeparatelyFromBackgroundMemoryWithoutSavedMutation() async throws {
        let seed = try await capture("Clean the workshop floor")
        let saved = try XCTUnwrap(seed.items.first)
        let savedID = saved.id, oldText = saved.originalTextSegment, oldTitle = saved.displayTitle
        let source = "The spare tape is in the drawer. My actual jobs are to count the crates and label the shelves."
        let result = try await capture(source)
        XCTAssertNil(result.operationOutcome)
        XCTAssertEqual(result.session.originalTranscription, source)
        XCTAssertTrue(result.items.contains { $0.belongsInMemory
            && $0.originalTextSegment.localizedCaseInsensitiveContains("spare tape") })
        for action in ["count the crates", "label the shelves"] {
            let row = try XCTUnwrap(result.items.first { !$0.belongsInMemory
                && !$0.needsClarification && $0.displayTitle.localizedCaseInsensitiveContains(action) }, action)
            XCTAssertEqual(row.captureSession?.id, result.session.id)
            XCTAssertNil(row.reminderDate)
        }
        let retained = try XCTUnwrap(allItems().first { $0.id == savedID })
        XCTAssertEqual(retained.originalTextSegment, oldText)
        XCTAssertEqual(retained.displayTitle, oldTitle)
        XCTAssertNil(retained.completedAt)
        XCTAssertFalse(retained.isArchived)
        XCTAssertEqual(try allItems().filter { $0.id == savedID }.count, 1)
    }

    func testPluralStatusHoldCannotCompleteMatchingSavedTasksOrSwallowLaterAction() async throws {
        let printing = try await capture("Print the label")
        let filing = try await capture("File the form")
        let saved = printing.items + filing.items
        XCTAssertEqual(saved.count, 2)
        let originals = Dictionary(uniqueKeysWithValues: saved.map { ($0.id, $0.originalTextSegment) })
        let prefix = "My actual jobs are to print the label and file the form, but I already printed it."
        let source = prefix + " I need to mail the parcel."
        let result = try await capture(source)
        XCTAssertNil(result.operationOutcome)
        XCTAssertEqual(result.session.originalTranscription, source)
        XCTAssertTrue(result.items.contains { $0.needsClarification
            && $0.originalTextSegment == prefix })
        XCTAssertTrue(result.items.contains { !$0.belongsInMemory && !$0.needsClarification
            && $0.displayTitle.localizedCaseInsensitiveContains("mail the parcel") })
        for row in try allItems().filter({ originals[$0.id] != nil }) {
            XCTAssertEqual(row.originalTextSegment, originals[row.id])
            XCTAssertNil(row.completedAt)
            XCTAssertFalse(row.isArchived)
        }
        XCTAssertEqual(try allItems().filter { originals[$0.id] != nil }.count, 2)
    }

    func testCaptureContrastExclusionKeepsContextAndCannotCancelOlderMatchingCopiesTask() async throws {
        let seed = try await capture("Bring printed copies of the application")
        let saved = try XCTUnwrap(seed.items.first)
        let savedID = saved.id, oldText = saved.originalTextSegment, oldTitle = saved.displayTitle
        let source = "I must bring my ID to the interview, but I don't need to bring printed copies of the application."
        let result = try await capture(source)
        XCTAssertNil(result.operationOutcome)
        XCTAssertEqual(result.session.originalTranscription, source)
        XCTAssertTrue(result.items.contains { !$0.belongsInMemory && !$0.needsClarification
            && $0.displayTitle.localizedCaseInsensitiveContains("bring my ID") })
        XCTAssertFalse(result.items.contains { !$0.belongsInMemory
            && $0.displayTitle.localizedCaseInsensitiveContains("bring printed copies") })
        XCTAssertTrue(result.items.contains { $0.originalTextSegment.localizedCaseInsensitiveContains("don't need to bring printed copies") },
                      "The exclusion must remain accessible on an organized item, beyond the immutable session.")
        let after = try XCTUnwrap(try allItems().first { $0.id == savedID })
        XCTAssertEqual(after.displayTitle, oldTitle)
        XCTAssertEqual(after.originalTextSegment, oldText)
        XCTAssertNil(after.completedAt)
        XCTAssertFalse(after.isArchived)
    }

    func testNonadoptedIdeaDoesNotCancelAnOlderParticleShapedTarget() async throws {
        let session = CaptureSession(originalTranscription: "ahead with it")
        let saved = CapturedItem(originalTextSegment: "ahead with it", displayTitle: "ahead with it",
                                 itemType: .task, captureSession: session)
        container.mainContext.insert(session)
        container.mainContext.insert(saved)
        try container.mainContext.save()
        let source = "Ignore my earlier idea of buying a telescope; I am not going ahead with it."
        let result = try await capture(source)
        XCTAssertNil(result.operationOutcome)
        XCTAssertEqual(result.session.originalTranscription, source)
        XCTAssertFalse(result.items.isEmpty)
        XCTAssertTrue(result.items.allSatisfy(\.belongsInMemory))
        XCTAssertTrue(result.items.contains { $0.originalTextSegment.localizedCaseInsensitiveContains("not going ahead") })
        XCTAssertNil(saved.completedAt)
        XCTAssertFalse(saved.isArchived)
        XCTAssertEqual(saved.originalTextSegment, "ahead with it")
    }

    func testCurrentThoughtCompletionRetainsMemoryWithoutTouchingOlderMatchingPurchase() async throws {
        let seed = try await capture("Buy the tickets")
        let saved = try XCTUnwrap(seed.items.first)
        let id = saved.id, oldText = saved.originalTextSegment, oldTitle = saved.displayTitle
        let source = "Remind me to buy the tickets on Wednesday. Cancel that thought, I already bought them."
        let result = try await capture(source)
        XCTAssertNil(result.operationOutcome, "A proved scoped withdrawal cannot operate on an older saved task.")
        XCTAssertEqual(result.session.originalTranscription, source)
        XCTAssertFalse(result.items.isEmpty)
        XCTAssertTrue(result.items.allSatisfy(\.belongsInMemory))
        XCTAssertTrue(result.items.allSatisfy { $0.reminderDate == nil })
        XCTAssertTrue(result.items.contains { $0.originalTextSegment.localizedCaseInsensitiveContains("bought") })
        let after = try XCTUnwrap(try allItems().first { $0.id == id })
        XCTAssertEqual(after.originalTextSegment, oldText)
        XCTAssertEqual(after.displayTitle, oldTitle)
        XCTAssertNil(after.completedAt)
        XCTAssertFalse(after.isArchived)
    }

    func testProvedLocalWithdrawalDoesNotSwallowNamedSavedCancellationOrLaterAction() async throws {
        let seed = try await capture("Remind me about the dentist on Friday")
        let dentist = try XCTUnwrap(seed.items.first)
        let source = "Remind me to buy the tickets on Wednesday. Cancel that thought, I already bought them. Cancel the dentist reminder. Mail the parcel."
        let result = try await capture(source)
        XCTAssertEqual(result.session.originalTranscription, source)
        guard case let .performed(operation, itemID, _) = result.operationOutcome else {
            return XCTFail("The independently named saved cancellation must survive the local withdrawal.")
        }
        XCTAssertEqual(operation, .cancel)
        XCTAssertEqual(itemID, dentist.id)
        XCTAssertFalse(try allItems().contains { $0.id == dentist.id })
        XCTAssertTrue(result.items.contains { !$0.belongsInMemory && !$0.needsClarification
            && $0.displayTitle.localizedCaseInsensitiveContains("mail the parcel") })
        XCTAssertFalse(result.items.contains { !$0.belongsInMemory
            && $0.displayTitle.localizedCaseInsensitiveContains("buy the tickets") })
        XCTAssertTrue(result.items.contains { $0.belongsInMemory
            && $0.originalTextSegment.localizedCaseInsensitiveContains("bought") })
    }

    // MARK: Cancel

    func testPhysicalOffStatesDoNotRequestSavedItemCancellation() async throws {
        let cases = [
            ("The sauce worked best with lime zest added after the heat was off.",
             "sauce worked best with lime zest added after the heat"),
            ("The heating was off.", "heating"),
            ("The projector is off.", "projector"),
            ("The meeting light is off.", "meeting light"),
            ("The dinner seasoning was off.", "dinner seasoning"),
            ("The power for the meeting is off.", "power for the meeting"),
            ("The projector in the meeting is off.", "projector in the meeting"),
            ("The bell at the conference is off.", "bell at the conference"),
            ("The timer for the class is off.", "timer for the class")
        ]
        // A matching saved task makes this exercise the dangerous mutation
        // path, rather than merely declining an unmatched cancellation.
        let saved = cases.map { _, target in
            let session = CaptureSession(originalTranscription: target)
            let item = CapturedItem(originalTextSegment: target, displayTitle: target,
                                    itemType: .task, captureSession: session)
            container.mainContext.insert(session)
            container.mainContext.insert(item)
            return item
        }
        try container.mainContext.save()
        let savedIDs = Set(saved.map(\.id))
        for (source, _) in cases {
            XCTAssertNil(CaptureOperationDetector.detect(source), source)
            let result = try await capture(source)
            XCTAssertNil(result.operationOutcome, source)
            XCTAssertEqual(result.session.originalTranscription, source)
            XCTAssertFalse(result.items.isEmpty, source)
            XCTAssertTrue(result.items.allSatisfy(\.belongsInMemory), source)
            let retained = try allItems().filter { savedIDs.contains($0.id) }
            XCTAssertEqual(Set(retained.map(\.id)), savedIDs, source)
            XCTAssertTrue(retained.allSatisfy { $0.completedAt == nil && !$0.isArchived }, source)
        }
    }

    func testBareOffStillCancelsScheduledSubjectsAndExplicitCancellation() {
        for source in ["Friday's meeting is off", "The call with Sarah is off",
                       "The dinner on Friday is off", "The meeting of the committee is off",
                       "The in-person meeting is off", "The on-call shift is off",
                       "The one-on-one meeting is off",
                       "The projector booking is cancelled"] {
            XCTAssertEqual(CaptureOperationDetector.detect(source)?.operation, .cancel, source)
        }
    }

    func testSavedCompletionWithLostPunctuationKeepsSourceAndOtherTask() async throws {
        let reference = Date(timeIntervalSince1970: 1_791_205_200)
        let emailSource = CaptureSession(originalTranscription: "Email Asha the corrected poster",
                                         createdAt: reference)
        let printSource = CaptureSession(originalTranscription: "Print the corrected poster",
                                         createdAt: reference)
        let email = CapturedItem(originalTextSegment: emailSource.originalTranscription,
                                 displayTitle: "Email Asha the corrected poster", itemType: .task,
                                 createdAt: reference, captureSession: emailSource)
        let printing = CapturedItem(originalTextSegment: printSource.originalTranscription,
                                    displayTitle: "Print the corrected poster", itemType: .task,
                                    createdAt: reference, captureSession: printSource)
        [emailSource, printSource].forEach(container.mainContext.insert)
        [email, printing].forEach(container.mainContext.insert)
        try container.mainContext.save()
        let source = "mark the saved task to email asha the corrected poster as complete i sent the email this morning do not mark the printing task complete because i have not printed anything yet even though the two tasks are both about the same poster\n\ni am reporting completion of the specific saved email task not asking to send another email or to create a new task called emailed asha the current capture should remain available as evidence of the change there should still be one unfinished printing task after this is processed"
        let result = try await repository.createCaptureResult(
            text: source, source: .inAppVoice, createdAt: reference,
            schedulesReminders: false
        )
        guard case .performed(operation: .complete, itemID: let id, title: _) =
                result.operationOutcome else {
            return XCTFail("Expected the named saved completion: \(String(describing: result.operationOutcome))")
        }
        XCTAssertEqual(id, email.id)
        XCTAssertNotNil(email.completedAt)
        XCTAssertNil(printing.completedAt)
        XCTAssertTrue(result.items.isEmpty, "Explanations must not create Today work")
        XCTAssertEqual(result.session.originalTranscription, source)
        let state = try XCTUnwrap(CaptureOperationState.read(from: result.session.operationStateData))
        XCTAssertEqual(state.phase, .performed)
        XCTAssertEqual(state.targetID, email.id)
        XCTAssertEqual(state.operation, .complete)
        XCTAssertEqual(emailSource.originalTranscription, "Email Asha the corrected poster")
        XCTAssertEqual(printSource.originalTranscription, "Print the corrected poster")
    }

    func testSavedCompletionExplanationDoesNotSwallowIndependentAction() {
        let source = "Mark the saved task to email Asha the corrected poster as complete. I sent the email this morning. Do not mark the printing task complete because I have not printed anything yet even though both tasks are about the same poster. Also buy eggs."
        let partition = CaptureOperationDetector.partitionWithOwnership(source)
        XCTAssertTrue(partition.remainder?.localizedCaseInsensitiveContains("buy eggs") == true)
        XCTAssertTrue(CaptureOperationDetector.partitionWithOwnership(
            "Keep a note that somebody suggested changing the saved task, but do not change any saved item."
        ).operations.isEmpty)
    }

    func testSavedCompletionReceiptSurvivesReopenAndRetry() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpeakIt-completion-receipt-\(UUID().uuidString).store")
        defer { try? FileManager.default.removeItem(at: url) }
        let reference = Date(timeIntervalSince1970: 1_791_205_200)
        let source = "Mark the saved task to email Asha the corrected poster as complete. I sent the email this morning. Do not mark the printing task complete, because I have not printed anything yet, even though the two tasks are both about the same poster."
        let emailID = UUID()
        let printingID = UUID()
        var completionID: UUID!
        do {
            let config = ModelConfiguration(schema: PersistenceController.schema, url: url)
            let store = try ModelContainer(for: PersistenceController.schema,
                                           migrationPlan: SpeakItMigrationPlan.self,
                                           configurations: [config])
            let context = store.mainContext
            let emailSource = CaptureSession(originalTranscription: "Email Asha the corrected poster",
                                             createdAt: reference)
            let printSource = CaptureSession(originalTranscription: "Print the corrected poster",
                                             createdAt: reference)
            context.insert(emailSource)
            context.insert(printSource)
            context.insert(CapturedItem(id: emailID,
                                        originalTextSegment: emailSource.originalTranscription,
                                        displayTitle: "Email Asha the corrected poster",
                                        itemType: .task, createdAt: reference,
                                        captureSession: emailSource))
            context.insert(CapturedItem(id: printingID,
                                        originalTextSegment: printSource.originalTranscription,
                                        displayTitle: "Print the corrected poster",
                                        itemType: .task, createdAt: reference,
                                        captureSession: printSource))
            try context.save()
            let saved = SwiftDataThoughtRepository(modelContext: context,
                                                   requestsReminderAuthorization: false,
            permitsOnDeviceIntelligence: false)
            let result = try await saved.createCaptureResult(
                text: source, source: .inAppVoice, createdAt: reference,
                schedulesReminders: false
            )
            completionID = result.session.id
            guard case .performed(operation: .complete, itemID: let id, title: _) =
                    result.operationOutcome else { return XCTFail("Expected saved completion") }
            XCTAssertEqual(id, emailID)
            XCTAssertTrue(result.items.isEmpty)
        }
        do {
            let config = ModelConfiguration(schema: PersistenceController.schema, url: url)
            let store = try ModelContainer(for: PersistenceController.schema,
                                           migrationPlan: SpeakItMigrationPlan.self,
                                           configurations: [config])
            let context = store.mainContext
            let saved = SwiftDataThoughtRepository(modelContext: context,
                                                   requestsReminderAuthorization: false,
            permitsOnDeviceIntelligence: false)
            let retry = try await saved.createCaptureResult(
                text: source, source: .inAppVoice, createdAt: reference,
                schedulesReminders: false
            )
            XCTAssertTrue(retry.isDuplicate)
            XCTAssertEqual(retry.session.id, completionID)
            guard case .performed(operation: .complete, itemID: let id, title: _) =
                    retry.operationOutcome else { return XCTFail("Expected performed receipt") }
            XCTAssertEqual(id, emailID)
            XCTAssertTrue(retry.items.isEmpty)
            let items = try context.fetch(FetchDescriptor<CapturedItem>())
            XCTAssertEqual(items.filter { $0.id == emailID && $0.isCompleted }.count, 1)
            XCTAssertEqual(items.filter { $0.id == printingID && !$0.isCompleted }.count, 1)
            XCTAssertFalse(items.contains { $0.captureSession?.id == completionID })
            let sessions = try context.fetch(FetchDescriptor<CaptureSession>())
            XCTAssertEqual(sessions.first { $0.id == completionID }?.originalTranscription, source)
            XCTAssertEqual(CaptureOperationState.read(
                from: sessions.first { $0.id == completionID }?.operationStateData
            )?.targetID, emailID)
        }
    }

    func testSavedCancellationUsesSpokenDayToIdentifyTheRightRow() throws {
        let reference = Date(timeIntervalSince1970: 1_791_205_200) // October 5, 2026 09:00 Toronto
        let calendar = Calendar.autoupdatingCurrent
        let today = calendar.startOfDay(for: reference)
        let tomorrow = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: today))
        let dueToday = CapturedItem(
            originalTextSegment: "Return the community room key",
            displayTitle: "Return the community room key", itemType: .task,
            createdAt: reference, dueDate: today
        )
        let dueTomorrow = CapturedItem(
            originalTextSegment: "Return the community room key",
            displayTitle: "Return the community room key", itemType: .task,
            createdAt: reference, dueDate: tomorrow
        )
        let rows = [dueToday, dueTomorrow]

        XCTAssertEqual(
            CaptureTargetMatcher.candidates(
                for: "saved reminder to return the community room key tomorrow",
                in: rows, referenceDate: reference, calendar: calendar
            ).map(\.id), [dueTomorrow.id]
        )
        XCTAssertEqual(
            CaptureTargetMatcher.candidates(
                for: "saved reminder to return the community room key today",
                in: rows, referenceDate: reference, calendar: calendar
            ).map(\.id), [dueToday.id]
        )
        XCTAssertEqual(
            CaptureTargetMatcher.candidates(
                for: "saved reminder to return the community room key tomorrow",
                in: [dueToday], referenceDate: reference, calendar: calendar
            ).count, 0,
            "A matching title on the wrong day must not be cancelled"
        )
    }

    func testLongSavedKeyCancellationActsOnOnlyNamedReminder() async throws {
        let reference = Date(timeIntervalSince1970: 1_791_205_200)
        let calendar = Calendar.autoupdatingCurrent
        let tomorrow = try XCTUnwrap(calendar.date(
            byAdding: .day, value: 1, to: calendar.startOfDay(for: reference)
        ))
        let key = CapturedItem(
            originalTextSegment: "Return the community room key",
            displayTitle: "Return the community room key", itemType: .task,
            createdAt: reference, dueDate: tomorrow
        )
        let library = CapturedItem(
            originalTextSegment: "Return the library book",
            displayTitle: "Return the library book", itemType: .task,
            createdAt: reference, dueDate: tomorrow
        )
        container.mainContext.insert(key)
        container.mainContext.insert(library)
        try container.mainContext.save()
        let source = "Cancel the saved reminder to return the community room key tomorrow. The key has already been handed back, and I do not want the notification. I am cancelling that reminder, not asking you to delete all of my return tasks or all tasks due tomorrow."

        let result = try await repository.createCaptureResult(
            text: source, source: .inAppText, createdAt: reference,
            schedulesReminders: false
        )

        guard case let .performed(operation, itemID, _) = result.operationOutcome else {
            return XCTFail("The named saved reminder should be cancelled: \(String(describing: result.operationOutcome))")
        }
        XCTAssertEqual(operation, .cancel)
        XCTAssertEqual(itemID, key.id)
        XCTAssertFalse(try allItems().contains { $0.id == key.id })
        XCTAssertTrue(try allItems().contains { $0.id == library.id })
        XCTAssertTrue(result.items.isEmpty, "Explanations of this cancellation are not new intentions")
        XCTAssertEqual(result.session.originalTranscription, source)
    }

    func testLongSavedCancellationKeepsIndependentFollowingAction() {
        let source = "Cancel the saved reminder to return the community room key tomorrow. The key has already been handed back, and I do not want the notification. Also buy eggs."
        let partition = CaptureOperationDetector.partitionWithOwnership(source)
        XCTAssertEqual(partition.operations.count, 1)
        XCTAssertEqual(partition.operations.first?.operation, .cancel)
        XCTAssertTrue(partition.remainder?.localizedCaseInsensitiveContains("buy eggs") == true)
        XCTAssertTrue(partition.unownedMeaningfulIDs(in: source).isEmpty)

        let sameSentence = "Cancel the saved reminder to return the community room key tomorrow. The key has already been handed back, and buy eggs."
        let second = CaptureOperationDetector.partitionWithOwnership(sameSentence)
        XCTAssertTrue(second.remainder?.localizedCaseInsensitiveContains("buy eggs") == true)
    }

    func testUnpunctuatedSavedCancellationSeparatesExplanationFromAnIndependentAction() async throws {
        let reference = Date(timeIntervalSince1970: 1_791_205_200)
        let tomorrow = try XCTUnwrap(Calendar.autoupdatingCurrent.date(
            byAdding: .day, value: 1,
            to: Calendar.autoupdatingCurrent.startOfDay(for: reference)
        ))
        let key = CapturedItem(
            originalTextSegment: "Return the community room key",
            displayTitle: "Return the community room key", itemType: .task,
            createdAt: reference, dueDate: tomorrow
        )
        let library = CapturedItem(
            originalTextSegment: "Return the library book",
            displayTitle: "Return the library book", itemType: .task,
            createdAt: reference, dueDate: tomorrow
        )
        container.mainContext.insert(key)
        container.mainContext.insert(library)
        try container.mainContext.save()
        let source = "cancel the saved reminder to return the community room key tomorrow the key has already been handed back and i do not want the notification i am cancelling that reminder not asking you to delete all of my return tasks or all tasks due tomorrow\n\nleave the library book task alone also preserve the original source of the key task and this cancellation request in whatever history the app supports do not silently treat a cancellation as a new reminder to cancel something if cancellation cannot be applied safely make that limitation visible"
        let result = try await repository.createCaptureResult(
            text: source, source: .inAppText, createdAt: reference,
            schedulesReminders: false
        )
        guard case .performed(operation: .cancel, itemID: let cancelledID, title: _) =
                result.operationOutcome else {
            return XCTFail("Expected the unpunctuated named cancellation")
        }
        XCTAssertEqual(cancelledID, key.id)
        XCTAssertTrue(result.items.isEmpty)
        XCTAssertTrue(try allItems().contains { $0.id == library.id })
        XCTAssertEqual(result.session.originalTranscription, source)

        let independent = source + " also buy eggs"
        let partition = CaptureOperationDetector.partitionWithOwnership(independent)
        XCTAssertTrue(partition.remainder?.localizedCaseInsensitiveContains("buy eggs") == true,
                      "A later affirmative request must stay independent")
    }

    func testFullSavedKeyCancellationKeepsTheDistractorAndNoNewTask() async throws {
        let reference = Date(timeIntervalSince1970: 1_791_205_200)
        let calendar = Calendar.autoupdatingCurrent
        let tomorrow = try XCTUnwrap(calendar.date(
            byAdding: .day, value: 1, to: calendar.startOfDay(for: reference)
        ))
        let key = CapturedItem(
            originalTextSegment: "Return the community room key",
            displayTitle: "Return the community room key", itemType: .task,
            createdAt: reference, dueDate: tomorrow
        )
        let library = CapturedItem(
            originalTextSegment: "Return the library book",
            displayTitle: "Return the library book", itemType: .task,
            createdAt: reference, dueDate: tomorrow
        )
        container.mainContext.insert(key)
        container.mainContext.insert(library)
        try container.mainContext.save()
        let source = "Cancel the saved reminder to return the community room key tomorrow. The key has already been handed back, and I do not want the notification. I am cancelling that reminder, not asking you to delete all of my return tasks or all tasks due tomorrow.\n\nLeave the library book task alone. Also preserve the original source of the key task and this cancellation request in whatever history the app supports. Do not silently treat a cancellation as a new reminder to cancel something. If cancellation cannot be applied safely, make that limitation visible."

        let result = try await repository.createCaptureResult(
            text: source, source: .inAppText, createdAt: reference,
            schedulesReminders: false
        )

        guard case let .performed(operation, itemID, _) = result.operationOutcome else {
            return XCTFail("The named saved reminder should be cancelled: \(String(describing: result.operationOutcome))")
        }
        XCTAssertEqual(operation, .cancel)
        XCTAssertEqual(itemID, key.id)
        XCTAssertFalse(try allItems().contains { $0.id == key.id })
        XCTAssertTrue(try allItems().contains { $0.id == library.id }, "The library task must survive")
        XCTAssertTrue(result.items.isEmpty, "Unexpected rows: \(result.items.map(\.displayTitle))")
        XCTAssertEqual(result.session.originalTranscription, source)
    }

    func testPureSavedCancellationKeepsBothSourcesAndDeduplicatesAfterStoreReopen() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpeakIt-cancel-receipt-\(UUID().uuidString).store")
        defer { try? FileManager.default.removeItem(at: url) }
        let previousZone = NSTimeZone.default
        NSTimeZone.default = try XCTUnwrap(TimeZone(identifier: "America/Toronto"))
        defer { NSTimeZone.default = previousZone }
        let clock = Date(timeIntervalSince1970: 1_791_205_200)
        let due = try XCTUnwrap(Calendar.autoupdatingCurrent.date(
            byAdding: .day, value: 1, to: Calendar.autoupdatingCurrent.startOfDay(for: clock)
        ))
        let keyID = UUID()
        let libraryID = UUID()
        let savedSourceID = UUID()
        let source = "Cancel the saved reminder to return the community room key tomorrow. The key has already been handed back, and I do not want the notification. I am cancelling that reminder, not asking you to delete all of my return tasks or all tasks due tomorrow."
        var cancellationCaptureID: UUID!

        do {
            let configuration = ModelConfiguration(schema: PersistenceController.schema, url: url)
            let store = try ModelContainer(for: PersistenceController.schema,
                                           migrationPlan: SpeakItMigrationPlan.self,
                                           configurations: [configuration])
            let context = store.mainContext
            let keySource = CaptureSession(
                id: savedSourceID, originalTranscription: "Return the community room key",
                createdAt: clock
            )
            let librarySource = CaptureSession(
                originalTranscription: "Return the library book", createdAt: clock
            )
            context.insert(keySource)
            context.insert(librarySource)
            context.insert(CapturedItem(
                id: keyID, originalTextSegment: keySource.originalTranscription,
                displayTitle: "Return the community room key", itemType: .task,
                createdAt: clock, dueDate: due, captureSession: keySource
            ))
            context.insert(CapturedItem(
                id: libraryID, originalTextSegment: librarySource.originalTranscription,
                displayTitle: "Return the library book", itemType: .task,
                createdAt: clock, dueDate: due, captureSession: librarySource
            ))
            try context.save()
            let saved = SwiftDataThoughtRepository(modelContext: context,
                                                   requestsReminderAuthorization: false,
            permitsOnDeviceIntelligence: false)
            let result = try await saved.createCaptureResult(
                text: source, source: .inAppVoice, createdAt: clock,
                schedulesReminders: false
            )
            cancellationCaptureID = result.session.id
            guard case .performed(operation: .cancel, itemID: let cancelledID, title: _) =
                    result.operationOutcome else {
                return XCTFail("Expected a performed saved-key cancellation")
            }
            XCTAssertEqual(cancelledID, keyID)
            XCTAssertTrue(result.items.isEmpty)
            XCTAssertEqual(result.session.originalTranscription, source)
            XCTAssertEqual(CaptureOperationState.read(from: result.session.operationStateData)?.phase,
                           .performed)
            XCTAssertEqual(CaptureOperationState.read(from: result.session.operationStateData)?.targetID,
                           keyID)
            XCTAssertNotNil(try context.fetch(FetchDescriptor<CaptureSession>())
                .first { $0.id == savedSourceID }, "Cancellation must retain the saved item's original capture")
        }

        do {
            let configuration = ModelConfiguration(schema: PersistenceController.schema, url: url)
            let store = try ModelContainer(for: PersistenceController.schema,
                                           migrationPlan: SpeakItMigrationPlan.self,
                                           configurations: [configuration])
            let context = store.mainContext
            let saved = SwiftDataThoughtRepository(modelContext: context,
                                                   requestsReminderAuthorization: false,
            permitsOnDeviceIntelligence: false)
            let sessions = try context.fetch(FetchDescriptor<CaptureSession>())
            XCTAssertEqual(sessions.first { $0.id == savedSourceID }?.originalTranscription,
                           "Return the community room key")
            XCTAssertEqual(sessions.first { $0.id == cancellationCaptureID }?.originalTranscription,
                           source)
            let retry = try await saved.createCaptureResult(
                text: source, source: .inAppVoice, createdAt: clock,
                schedulesReminders: false
            )
            XCTAssertTrue(retry.isDuplicate)
            XCTAssertEqual(retry.session.id, cancellationCaptureID)
            guard case .performed(operation: .cancel, itemID: let repeatedID, title: _) =
                    retry.operationOutcome else {
                return XCTFail("Retry must return the durable performed result")
            }
            XCTAssertEqual(repeatedID, keyID)
            let items = try context.fetch(FetchDescriptor<CapturedItem>())
            XCTAssertFalse(items.contains { $0.id == keyID })
            XCTAssertTrue(items.contains { $0.id == libraryID })
            XCTAssertFalse(items.contains { $0.captureSession?.id == cancellationCaptureID })
        }
    }

    func testSavedQuantityRevisionChangesOnlyUniqueBoxesAndKeepsSource() async throws {
        let reference = Date(timeIntervalSince1970: 1_791_205_200)
        let boxSource = CaptureSession(originalTranscription: "Buy four clear storage boxes",
                                       createdAt: reference)
        let labelsSource = CaptureSession(originalTranscription: "Buy four sheets of labels",
                                          createdAt: reference)
        let boxes = CapturedItem(originalTextSegment: boxSource.originalTranscription,
                                 displayTitle: "Buy four clear storage boxes",
                                 itemType: .task, createdAt: reference,
                                 captureSession: boxSource)
        let labels = CapturedItem(originalTextSegment: labelsSource.originalTranscription,
                                  displayTitle: "Buy four sheets of labels",
                                  itemType: .task, createdAt: reference,
                                  captureSession: labelsSource)
        [boxSource, labelsSource].forEach(container.mainContext.insert)
        [boxes, labels].forEach(container.mainContext.insert)
        try container.mainContext.save()
        let source = "Update the saved storage box purchase from four boxes to two boxes. Keep them clear and small enough for under the bed. I am correcting the quantity on that specific task rather than adding a second purchase for two more boxes.\n\nDo not change the four sheets of labels. The repeated number four is not enough to identify a target. Retain an audit connection from this recording to the box update, and do not claim the saved item was changed if the current data model can only keep the request for review."
        XCTAssertNotNil(SavedQuantityRevision.read(source), "The source-first typed parser must read this amendment")
        XCTAssertEqual(CaptureOperationDetector.partitionWithOwnership(source)
            .operations.first?.savedQuantityRevision?.newQuantity, "two")

        let result = try await repository.createCaptureResult(
            text: source, source: .inAppVoice, createdAt: reference,
            schedulesReminders: false
        )
        guard case .performed(operation: .revise, itemID: let revisedID, title: _) =
                result.operationOutcome else {
            return XCTFail("Expected a grounded saved quantity revision: \(String(describing: result.operationOutcome))")
        }
        XCTAssertEqual(revisedID, boxes.id)
        XCTAssertEqual(boxes.displayTitle, "Buy two clear storage boxes small enough for under the bed")
        XCTAssertEqual(boxes.originalTextSegment, "Buy four clear storage boxes")
        XCTAssertEqual(labels.displayTitle, "Buy four sheets of labels")
        XCTAssertTrue(result.items.isEmpty)
        XCTAssertEqual(result.session.originalTranscription, source)
        let state = try XCTUnwrap(CaptureOperationState.read(from: result.session.operationStateData))
        XCTAssertEqual(state.phase, .performed)
        XCTAssertEqual(state.targetID, boxes.id)
        XCTAssertEqual(state.oldTitle, "Buy four clear storage boxes")
        XCTAssertEqual(state.newTitle, boxes.displayTitle)
    }

    func testSavedQuantityRevisionRequiresUniqueObjectAndDoesNotAbsorbNewAction() async throws {
        let source = "Update the saved storage box purchase from four boxes to two boxes. Keep them clear and small enough for under the bed. I am correcting the quantity on that specific task rather than adding a second purchase for two more boxes. Also buy eggs."
        let partition = CaptureOperationDetector.partitionWithOwnership(source)
        XCTAssertTrue(partition.remainder?.localizedCaseInsensitiveContains("buy eggs") == true)
        XCTAssertTrue(CaptureOperationDetector.partitionWithOwnership(
            "Buy two clear storage boxes small enough for under the bed"
        ).operations.isEmpty, "A new purchase is not a saved-item amendment")

        let reference = Date(timeIntervalSince1970: 1_791_205_200)
        let first = CapturedItem(originalTextSegment: "Buy four clear storage boxes",
                                 displayTitle: "Buy four clear storage boxes",
                                 itemType: .task, createdAt: reference)
        let second = CapturedItem(originalTextSegment: "Buy four clear storage boxes",
                                  displayTitle: "Buy four clear storage boxes",
                                  itemType: .task, createdAt: reference)
        let labels = CapturedItem(originalTextSegment: "Buy four sheets of labels",
                                  displayTitle: "Buy four sheets of labels",
                                  itemType: .task, createdAt: reference)
        [first, second, labels].forEach(container.mainContext.insert)
        try container.mainContext.save()
        let request = "Update the saved storage box purchase from four boxes to two boxes. Keep them clear and small enough for under the bed. I am correcting the quantity on that specific task rather than adding a second purchase for two more boxes."
        let result = try await repository.createCaptureResult(
            text: request, source: .inAppVoice, createdAt: reference,
            schedulesReminders: false
        )
        guard case .ambiguous(operation: .revise, candidateIDs: let ids) =
                result.operationOutcome else {
            return XCTFail("Two matching box rows must require review")
        }
        XCTAssertEqual(Set(ids), Set([first.id, second.id]))
        XCTAssertEqual(first.displayTitle, "Buy four clear storage boxes")
        XCTAssertEqual(second.displayTitle, "Buy four clear storage boxes")
        XCTAssertEqual(labels.displayTitle, "Buy four sheets of labels")
    }

    func testSavedQuantityRevisionReceiptSurvivesReopenAndRetry() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpeakIt-quantity-receipt-\(UUID().uuidString).store")
        defer { try? FileManager.default.removeItem(at: url) }
        let reference = Date(timeIntervalSince1970: 1_791_205_200)
        let source = "Update the saved storage box purchase from four boxes to two boxes. Keep them clear and small enough for under the bed. I am correcting the quantity on that specific task rather than adding a second purchase for two more boxes."
        let boxID = UUID()
        let boxSourceID = UUID()
        var amendmentID: UUID!
        do {
            let configuration = ModelConfiguration(schema: PersistenceController.schema, url: url)
            let store = try ModelContainer(for: PersistenceController.schema,
                                           migrationPlan: SpeakItMigrationPlan.self,
                                           configurations: [configuration])
            let context = store.mainContext
            let boxSource = CaptureSession(id: boxSourceID,
                                           originalTranscription: "Buy four clear storage boxes",
                                           createdAt: reference)
            context.insert(boxSource)
            context.insert(CapturedItem(id: boxID,
                                        originalTextSegment: boxSource.originalTranscription,
                                        displayTitle: "Buy four clear storage boxes",
                                        itemType: .task, createdAt: reference,
                                        captureSession: boxSource))
            try context.save()
            let saved = SwiftDataThoughtRepository(modelContext: context,
                                                   requestsReminderAuthorization: false,
            permitsOnDeviceIntelligence: false)
            let first = try await saved.createCaptureResult(
                text: source, source: .inAppVoice, createdAt: reference,
                schedulesReminders: false
            )
            amendmentID = first.session.id
            guard case .performed(operation: .revise, itemID: let id, title: _) =
                    first.operationOutcome else { return XCTFail("Expected the first revision") }
            XCTAssertEqual(id, boxID)
            XCTAssertTrue(first.items.isEmpty)
        }
        do {
            let configuration = ModelConfiguration(schema: PersistenceController.schema, url: url)
            let store = try ModelContainer(for: PersistenceController.schema,
                                           migrationPlan: SpeakItMigrationPlan.self,
                                           configurations: [configuration])
            let context = store.mainContext
            let saved = SwiftDataThoughtRepository(modelContext: context,
                                                   requestsReminderAuthorization: false,
            permitsOnDeviceIntelligence: false)
            let retry = try await saved.createCaptureResult(
                text: source, source: .inAppVoice, createdAt: reference,
                schedulesReminders: false
            )
            XCTAssertTrue(retry.isDuplicate)
            XCTAssertEqual(retry.session.id, amendmentID)
            guard case .performed(operation: .revise, itemID: let id, title: _) =
                    retry.operationOutcome else { return XCTFail("Expected the performed receipt") }
            XCTAssertEqual(id, boxID)
            let items = try context.fetch(FetchDescriptor<CapturedItem>())
            XCTAssertEqual(items.filter { $0.id == boxID }.map(\.displayTitle),
                           ["Buy two clear storage boxes small enough for under the bed"])
            XCTAssertFalse(items.contains { $0.captureSession?.id == amendmentID })
            let sessions = try context.fetch(FetchDescriptor<CaptureSession>())
            XCTAssertEqual(sessions.first { $0.id == boxSourceID }?.originalTranscription,
                           "Buy four clear storage boxes")
            XCTAssertEqual(sessions.first { $0.id == amendmentID }?.originalTranscription,
                           source)
        }
    }

    func testSavedAlertRemovalKeepsTaskAndCancelsOnlyNamedNotification() async throws {
        let previousZone = NSTimeZone.default
        NSTimeZone.default = try XCTUnwrap(TimeZone(identifier: "America/Toronto"))
        defer { NSTimeZone.default = previousZone }
        let reference = Date(timeIntervalSince1970: 1_791_205_200)
        let calendar = Calendar.autoupdatingCurrent
        let tomorrow = try XCTUnwrap(calendar.date(byAdding: .day, value: 1,
                                        to: calendar.startOfDay(for: reference)))
        let atThree = try XCTUnwrap(calendar.date(bySettingHour: 15, minute: 0,
                                        second: 0, of: tomorrow))
        let callSource = CaptureSession(originalTranscription: "Call the room coordinator",
                                        createdAt: reference)
        let deliverySource = CaptureSession(originalTranscription: "Check equipment delivery",
                                            createdAt: reference)
        let call = CapturedItem(originalTextSegment: callSource.originalTranscription,
                                displayTitle: "Call the room coordinator", itemType: .task,
                                createdAt: reference, dueDate: atThree,
                                reminderDate: atThree, captureSession: callSource)
        let equipment = CapturedItem(originalTextSegment: deliverySource.originalTranscription,
                                     displayTitle: "Check equipment delivery", itemType: .task,
                                     createdAt: reference, dueDate: atThree,
                                     reminderDate: atThree, captureSession: deliverySource)
        [callSource, deliverySource].forEach(container.mainContext.insert)
        [call, equipment].forEach(container.mainContext.insert)
        try container.mainContext.save()
        let callNotification = ReminderScheduler.notificationIdentifier(for: call.id)
        let equipmentNotification = ReminderScheduler.notificationIdentifier(for: equipment.id)
        delivery.seedNotification(callNotification)
        delivery.seedNotification(equipmentNotification)
        let source = "Remove the three p.m. notification from the saved task to call the room coordinator tomorrow, but keep the task on tomorrow's list. I still need to make the call; I just do not need the alert. Do not mark the task complete or cancel the call itself.\n\nThe equipment delivery reminder at the same time should stay unchanged. I am naming the call so the app can distinguish them. If notification removal is unavailable without deleting the task, leave the task alone and show the requested change for review rather than losing the obligation."
        XCTAssertNotNil(SavedAlertRemoval.read(source))
        let result = try await repository.createCaptureResult(
            text: source, source: .inAppVoice, createdAt: reference,
            schedulesReminders: false
        )
        guard case .performed(operation: .revise, itemID: let id, title: _) =
                result.operationOutcome else {
            return XCTFail("Expected notification-only saved amendment: \(String(describing: result.operationOutcome))")
        }
        XCTAssertEqual(id, call.id)
        XCTAssertEqual(call.displayTitle, "Call the room coordinator")
        XCTAssertEqual(call.originalTextSegment, "Call the room coordinator")
        XCTAssertNil(call.reminderDate)
        XCTAssertEqual(call.dueDate, tomorrow)
        XCTAssertNil(call.completedAt)
        XCTAssertEqual(equipment.dueDate, atThree)
        XCTAssertEqual(equipment.reminderDate, atThree)
        XCTAssertFalse(delivery.pendingNotifications.contains(callNotification))
        XCTAssertTrue(delivery.pendingNotifications.contains(equipmentNotification))
        XCTAssertTrue(result.items.isEmpty)
        XCTAssertEqual(result.session.originalTranscription, source)
        let state = try XCTUnwrap(CaptureOperationState.read(from: result.session.operationStateData))
        XCTAssertEqual(state.phase, .performed)
        XCTAssertEqual(state.targetID, call.id)
        XCTAssertEqual(state.oldReminderDate, atThree)
        XCTAssertNil(state.newReminderDate)
    }

    func testSavedAlertRemovalHoldsStaleClockAndKeepsIndependentAction() async throws {
        let prefix = "Remove the three p.m. notification from the saved task to call the room coordinator tomorrow, but keep the task on tomorrow's list. I still need to make the call; I just do not need the alert. Do not mark the task complete or cancel the call itself."
        XCTAssertNil(SavedAlertRemoval.read(prefix + " Also buy eggs."))
        XCTAssertNil(SavedAlertRemoval.read("Cancel the call"),
                     "Cancelling the obligation is a different operation")
        let previousZone = NSTimeZone.default
        NSTimeZone.default = try XCTUnwrap(TimeZone(identifier: "America/Toronto"))
        defer { NSTimeZone.default = previousZone }
        let reference = Date(timeIntervalSince1970: 1_791_205_200)
        let calendar = Calendar.autoupdatingCurrent
        let tomorrow = try XCTUnwrap(calendar.date(byAdding: .day, value: 1,
                                        to: calendar.startOfDay(for: reference)))
        let atFour = try XCTUnwrap(calendar.date(bySettingHour: 16, minute: 0,
                                       second: 0, of: tomorrow))
        let call = CapturedItem(originalTextSegment: "Call the room coordinator",
                                displayTitle: "Call the room coordinator", itemType: .task,
                                createdAt: reference, dueDate: atFour,
                                reminderDate: atFour)
        container.mainContext.insert(call)
        try container.mainContext.save()
        let notification = ReminderScheduler.notificationIdentifier(for: call.id)
        delivery.seedNotification(notification)
        let result = try await repository.createCaptureResult(
            text: prefix, source: .inAppVoice, createdAt: reference,
            schedulesReminders: false
        )
        guard case .ambiguous(operation: .revise, candidateIDs: let ids) =
                result.operationOutcome else {
            return XCTFail("A stale spoken clock must hold the amendment")
        }
        XCTAssertEqual(ids, [call.id])
        XCTAssertEqual(call.dueDate, atFour)
        XCTAssertEqual(call.reminderDate, atFour)
        XCTAssertTrue(delivery.pendingNotifications.contains(notification))
    }

    func testSavedAlertRemovalRequiresUniqueTaskAndSurvivesStoreReopen() async throws {
        let previousZone = NSTimeZone.default
        NSTimeZone.default = try XCTUnwrap(TimeZone(identifier: "America/Toronto"))
        defer { NSTimeZone.default = previousZone }
        let reference = Date(timeIntervalSince1970: 1_791_205_200)
        let calendar = Calendar.autoupdatingCurrent
        let tomorrow = try XCTUnwrap(calendar.date(byAdding: .day, value: 1,
                                        to: calendar.startOfDay(for: reference)))
        let atThree = try XCTUnwrap(calendar.date(bySettingHour: 15, minute: 0,
                                        second: 0, of: tomorrow))
        let source = "Remove the three p.m. notification from the saved task to call the room coordinator tomorrow, but keep the task on tomorrow's list. I still need to make the call; I just do not need the alert. Do not mark the task complete or cancel the call itself."
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpeakIt-alert-receipt-\(UUID().uuidString).store")
        defer { try? FileManager.default.removeItem(at: url) }
        let callID = UUID()
        let sourceID = UUID()
        var amendmentID: UUID!
        do {
            let configuration = ModelConfiguration(schema: PersistenceController.schema, url: url)
            let store = try ModelContainer(for: PersistenceController.schema,
                                           migrationPlan: SpeakItMigrationPlan.self,
                                           configurations: [configuration])
            let context = store.mainContext
            let savedSource = CaptureSession(id: sourceID,
                                             originalTranscription: "Call the room coordinator",
                                             createdAt: reference)
            context.insert(savedSource)
            context.insert(CapturedItem(id: callID,
                                        originalTextSegment: savedSource.originalTranscription,
                                        displayTitle: "Call the room coordinator",
                                        itemType: .task, createdAt: reference,
                                        dueDate: atThree, reminderDate: atThree,
                                        captureSession: savedSource))
            try context.save()
            let saved = SwiftDataThoughtRepository(modelContext: context,
                                                   requestsReminderAuthorization: false,
            permitsOnDeviceIntelligence: false)
            let first = try await saved.createCaptureResult(
                text: source, source: .inAppVoice, createdAt: reference,
                schedulesReminders: false
            )
            amendmentID = first.session.id
            guard case .performed(operation: .revise, itemID: let id, title: _) =
                    first.operationOutcome else { return XCTFail("Expected the first alert removal") }
            XCTAssertEqual(id, callID)
        }
        do {
            let configuration = ModelConfiguration(schema: PersistenceController.schema, url: url)
            let store = try ModelContainer(for: PersistenceController.schema,
                                           migrationPlan: SpeakItMigrationPlan.self,
                                           configurations: [configuration])
            let context = store.mainContext
            let saved = SwiftDataThoughtRepository(modelContext: context,
                                                   requestsReminderAuthorization: false,
            permitsOnDeviceIntelligence: false)
            let retry = try await saved.createCaptureResult(
                text: source, source: .inAppVoice, createdAt: reference,
                schedulesReminders: false
            )
            XCTAssertTrue(retry.isDuplicate)
            XCTAssertEqual(retry.session.id, amendmentID)
            guard case .performed(operation: .revise, itemID: let id, title: _) =
                    retry.operationOutcome else { return XCTFail("Expected the durable receipt") }
            XCTAssertEqual(id, callID)
            let items = try context.fetch(FetchDescriptor<CapturedItem>())
            let call = try XCTUnwrap(items.first { $0.id == callID })
            XCTAssertEqual(call.dueDate, tomorrow)
            XCTAssertNil(call.reminderDate)
            XCTAssertFalse(items.contains { $0.captureSession?.id == amendmentID })
            let sessions = try context.fetch(FetchDescriptor<CaptureSession>())
            XCTAssertEqual(sessions.first { $0.id == sourceID }?.originalTranscription,
                           "Call the room coordinator")
            XCTAssertEqual(sessions.first { $0.id == amendmentID }?.originalTranscription,
                           source)
        }

        let first = CapturedItem(originalTextSegment: "Call the room coordinator",
                                 displayTitle: "Call the room coordinator", itemType: .task,
                                 createdAt: reference, dueDate: atThree,
                                 reminderDate: atThree)
        let second = CapturedItem(originalTextSegment: "Call the room coordinator",
                                  displayTitle: "Call the room coordinator", itemType: .task,
                                  createdAt: reference, dueDate: atThree,
                                  reminderDate: atThree)
        container.mainContext.insert(first)
        container.mainContext.insert(second)
        try container.mainContext.save()
        let held = try await repository.createCaptureResult(
            text: source, source: .inAppVoice, createdAt: reference,
            schedulesReminders: false
        )
        guard case .ambiguous(operation: .revise, candidateIDs: let ids) =
                held.operationOutcome else { return XCTFail("Same-title calls must require a choice") }
        XCTAssertEqual(Set(ids), Set([first.id, second.id]))
        XCTAssertEqual(first.reminderDate, atThree)
        XCTAssertEqual(second.reminderDate, atThree)
    }

    func testSavedRowRevisionIsTypedAndHeldWithoutChangingExistingTasks() async throws {
        _ = try await capture("Pick up rental van at Central Depot on Friday")
        _ = try await capture("Return the packing blankets to Ivo")
        let before = try allItems().filter { $0.displayTitle.localizedCaseInsensitiveContains("rental van") }
        XCTAssertEqual(before.count, 1)

        let spoken = "Please change the existing van pickup item to the north branch. "
            + "Download the booking email for offline use."
        let result = try await capture(spoken)

        guard case .ambiguous(operation: .revise, _) = try XCTUnwrap(result.operationOutcome) else {
            return XCTFail("A semantic edit must retain its operation identity in Needs Review")
        }
        // The old place was never spoken, so the edit cannot resolve: the whole
        // capture, including its trailing action, stays one visible review row.
        XCTAssertTrue(result.items.contains { $0.needsClarification
            && $0.originalTextSegment.localizedCaseInsensitiveContains("change the existing") })
        XCTAssertTrue(result.items.contains { $0.needsClarification
            && $0.originalTextSegment == spoken },
                      "An unresolved revision must visibly retain the independent trailing action")
        XCTAssertEqual(before[0].displayTitle, try XCTUnwrap(allItems().first { $0.id == before[0].id }).displayTitle)
        XCTAssertTrue(try activeTitles().contains { $0.localizedCaseInsensitiveContains("blankets") })
        XCTAssertFalse(try activeTitles().contains { $0.localizedCaseInsensitiveContains("north branch")
            && !$0.localizedCaseInsensitiveContains("change") })
    }

    func testExactQuotedQuantityRevisionRetainsSeedAndAmendmentForReview() async throws {
        let seed = try await capture("Buy two bottles of olive oil")
        let original = try XCTUnwrap(seed.items.first)
        let oldID = original.id
        let oldSource = original.originalTextSegment
        let oldTemporalData = original.temporalIntentData
        let oldTitle = original.displayTitle
        let result = try await capture(
            "Change the existing task “\(oldTitle)” to “Buy one bottle of olive oil”"
        )
        guard case let .ambiguous(operation, candidateIDs) = try XCTUnwrap(result.operationOutcome) else {
            return XCTFail("A quoted replacement needs a durable saved-row link before execution")
        }
        XCTAssertEqual(operation, .revise)
        XCTAssertEqual(candidateIDs, [oldID])
        let updated = try XCTUnwrap(allItems().first { $0.id == oldID })
        XCTAssertEqual(updated.displayTitle, oldTitle)
        XCTAssertEqual(updated.originalTextSegment, oldSource)
        XCTAssertEqual(updated.temporalIntentData, oldTemporalData)
        XCTAssertTrue(result.session.originalTranscription.contains("two bottles"))
        XCTAssertTrue(result.session.originalTranscription.contains("one bottle"))
        XCTAssertTrue(result.items.contains(where: \.needsClarification))
    }

    func testQuotedPersonRevisionPreservesExistingTimeIntentUntilReview() async throws {
        let seed = try await capture("Call Maya tomorrow at nine")
        let original = try XCTUnwrap(seed.items.first)
        let oldID = original.id
        let oldDue = original.dueDate
        let oldReminder = original.reminderDate
        let oldTemporalData = original.temporalIntentData
        let result = try await capture(
            "Update the saved task “\(original.displayTitle)” to “Call Tessa”"
        )
        guard case let .ambiguous(operation, candidateIDs) = try XCTUnwrap(result.operationOutcome) else {
            return XCTFail("A complete replacement still needs durable amendment provenance")
        }
        XCTAssertEqual(operation, .revise)
        XCTAssertEqual(candidateIDs, [oldID])
        let updated = try XCTUnwrap(allItems().first { $0.id == oldID })
        XCTAssertEqual(updated.personName, original.personName)
        XCTAssertEqual(updated.dueDate, oldDue)
        XCTAssertEqual(updated.reminderDate, oldReminder)
        XCTAssertEqual(updated.temporalIntentData, oldTemporalData)
    }

    func testQuotedRevisionWithNewDateStaysReviewableWithoutChangingSeed() async throws {
        let seed = try await capture("Call Maya tomorrow at nine")
        let original = try XCTUnwrap(seed.items.first)
        let oldTitle = original.displayTitle
        let oldTemporalData = original.temporalIntentData
        let result = try await capture(
            "Update the saved task “\(oldTitle)” to “Call Tessa next Monday”"
        )
        guard case .ambiguous(operation: .revise, _) = try XCTUnwrap(result.operationOutcome) else {
            return XCTFail("An unmodeled date replacement must remain in review")
        }
        XCTAssertEqual(original.displayTitle, oldTitle)
        XCTAssertEqual(original.temporalIntentData, oldTemporalData)
        XCTAssertTrue(result.items.contains(where: \.needsClarification))
    }

    func testQuotedRevisionWithTwoExactSavedTargetsNeverGuesses() async throws {
        let first = CapturedItem(originalTextSegment: "Call Maya", displayTitle: "Call Maya",
                                 itemType: .personFollowUp)
        let second = CapturedItem(originalTextSegment: "Call Maya", displayTitle: "Call Maya",
                                  itemType: .personFollowUp)
        container.mainContext.insert(first)
        container.mainContext.insert(second)
        try container.mainContext.save()
        let result = try await capture(
            "Change the existing task “Call Maya” to “Call Tessa”"
        )
        guard case .ambiguous(operation: .revise, _) = try XCTUnwrap(result.operationOutcome) else {
            return XCTFail("Two exact targets require user choice")
        }
        XCTAssertEqual(first.displayTitle, "Call Maya")
        XCTAssertEqual(second.displayTitle, "Call Maya")
        XCTAssertTrue(result.items.contains(where: \.needsClarification))
    }

    func testQuotedRevisionWithIndependentNewActionKeepsCompleteSourceReviewable() async throws {
        let seed = try await capture("Call Maya")
        let original = try XCTUnwrap(seed.items.first)
        let result = try await capture(
            "Change the existing task “\(original.displayTitle)” to “Call Tessa”. Buy bread."
        )
        guard case .ambiguous(operation: .revise, _) = try XCTUnwrap(result.operationOutcome) else {
            return XCTFail("A mixed edit must not execute a partial parse")
        }
        XCTAssertEqual(original.displayTitle, "Call Maya")
        XCTAssertTrue(result.items.contains { $0.needsClarification
            && $0.originalTextSegment.localizedCaseInsensitiveContains("Buy bread") })
    }

    func testWorldChangeAndReportedSavedRowEditDoNotBecomeExecutableRevisions() {
        XCTAssertTrue(CaptureOperationDetector.partition("Change the air filter tomorrow").operations.isEmpty)
        XCTAssertTrue(CaptureOperationDetector.partition(
            "Maya said, change the existing van pickup item to the north branch"
        ).operations.isEmpty)
        XCTAssertTrue(CaptureOperationDetector.partition(
            "Maya said, change the existing task “Call Maya” to “Call Tessa”"
        ).operations.isEmpty)
        let mixed = CaptureOperationDetector.partition(
            "Mark the deposit task complete and call Maya"
        )
        XCTAssertEqual(mixed.operations.first?.operation, .complete)
        XCTAssertTrue(mixed.remainder?.localizedCaseInsensitiveContains("call Maya") == true)

        let juxtaposed = CaptureOperationDetector.partition(
            "Don't call Catherine tomorrow call her Friday"
        )
        XCTAssertEqual(juxtaposed.operations.first?.target?.lowercased(),
                       "call catherine tomorrow")
        XCTAssertTrue(juxtaposed.remainder?.localizedCaseInsensitiveContains("call her Friday") == true)
        let nounCollision = CaptureOperationDetector.partition(
            "Don't call my task coordinator tomorrow call her Friday"
        )
        XCTAssertEqual(nounCollision.operations.first?.target?.lowercased(),
                       "call my task coordinator tomorrow")
        XCTAssertTrue(nounCollision.remainder?.localizedCaseInsensitiveContains("call her Friday") == true)
    }

    func testSavedDateAmendmentAndExplicitCancelRequestKeepOperationIdentity() {
        let amendment = CaptureOperationDetector.detect(
            "Change the saved dentist call from tomorrow to Friday, October ninth"
        )
        XCTAssertEqual(amendment?.operation, .reschedule)
        XCTAssertEqual(amendment?.target, "dentist call")
        XCTAssertEqual(amendment?.expectedOldTimingText, "tomorrow")
        XCTAssertEqual(amendment?.newTimingText, "friday, october ninth")

        let choice = CaptureOperationDetector.detect(
            "I need you to cancel the reminder about the appointment tomorrow"
        )
        XCTAssertEqual(choice?.operation, .cancel)
        XCTAssertEqual(choice?.target, "the appointment tomorrow")

        XCTAssertNil(CaptureOperationDetector.detect(
            "I need you to cancel the gym membership"
        ))
        XCTAssertNil(CaptureOperationDetector.detect(
            "Maya said, change the saved dentist call from tomorrow to Friday"
        ))

        let long = "Change the saved dentist call from tomorrow to Friday, October ninth. It is the task about the appointment letter, not the bike shop call. Keep its wording and the fact that it is unfinished. I am changing an existing item rather than asking for a second dentist task. Leave the bike shop call exactly as it was. I have given enough information to distinguish the two saved tasks. If the app cannot safely update the dentist item and preserve the connection to this recording, keep my requested change visible for review instead of claiming it happened or changing a guessed item."
        let grouped = CaptureOperationDetector.partition(long)
        XCTAssertEqual(grouped.operations.count, 1)
        XCTAssertEqual(grouped.operations.first?.operation, .reschedule)
        XCTAssertEqual(grouped.operations.first?.sourceQuote, long)
        XCTAssertNil(grouped.remainder)

        let spoken = "Um, let me think. " + long.replacingOccurrences(
            of: "Leave the bike shop", with: "Right, okay. Leave the bike shop"
        )
        let spokenGrouped = CaptureOperationDetector.partition(spoken)
        XCTAssertEqual(spokenGrouped.operations.count, 1)
        XCTAssertEqual(spokenGrouped.operations.first?.sourceQuote, spoken)
        XCTAssertNil(spokenGrouped.remainder)
        let spokenWithPause = spoken.replacingOccurrences(
            of: "Right, okay.", with: "\n\nRight, okay."
        ) + "\n"
        let pausedGrouped = CaptureOperationDetector.partition(spokenWithPause)
        XCTAssertEqual(pausedGrouped.operations.count, 1)
        XCTAssertNil(pausedGrouped.remainder)
        let parsed = RuleBasedThoughtExtractor.process(spokenWithPause)
        XCTAssertEqual(parsed.operations.count, 1,
                       SpeechRepairPipeline.run(spokenWithPause, trackOrigins: true).corrected)

        let independent = CaptureOperationDetector.partition(
            long + " Also buy envelopes."
        )
        XCTAssertTrue(independent.remainder?.localizedCaseInsensitiveContains("buy envelopes") == true)
    }

    func testAmbiguousSavedCancellationKeepsIndependentEnvelopes() {
        let source = "I need you to cancel the reminder about the appointment tomorrow. I cannot remember whether I called it the clinic visit or the dentist visit when I saved it. Do not guess between them just because one was created more recently. I can choose the right one when I see the names.\n\nAlso buy a packet of envelopes. That is a clear new task unrelated to the appointment, so it can be saved while the cancellation waits. Keep the cancellation request visible and ask me which saved reminder I mean. None of the appointment reminders should change before I select one."
        let result = RuleBasedThoughtExtractor.process(source)
        XCTAssertEqual(result.operations.count, 1,
                       String(describing: result.operations.map { ($0.operation, $0.sourceQuote) }))
        XCTAssertNotNil(ThoughtExtractionEngine.extractWithRules(source).pendingOperation)
        XCTAssertEqual(result.operations.first?.operation, .cancel,
                       SpeechRepairPipeline.run(source, trackOrigins: true).corrected)
        XCTAssertTrue(result.operations.first?.sourceQuote.localizedCaseInsensitiveContains("appointment tomorrow") == true)
        XCTAssertTrue(result.items.contains { $0.sourceQuote.localizedCaseInsensitiveContains("envelopes") },
                      String(describing: result.items.map(\.sourceQuote)))
        XCTAssertEqual(result.items.count, 1,
                       String(describing: result.items.map(\.sourceQuote)))
    }

    func testSavedCancellationChoiceChangesOnlySelectedRowAndRepeatIsIdempotent() async throws {
        let clock = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-05T13:00:00Z"))
        let due = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-06T16:00:00Z"))
        let clinicSession = CaptureSession(originalTranscription: "Clinic visit", createdAt: clock)
        let dentistSession = CaptureSession(originalTranscription: "Dentist visit", createdAt: clock)
        let clinic = CapturedItem(originalTextSegment: "Clinic visit", displayTitle: "Clinic visit",
                                  itemType: .task, category: .general, createdAt: clock,
                                  dueDate: due, captureSession: clinicSession)
        let dentist = CapturedItem(originalTextSegment: "Dentist visit", displayTitle: "Dentist visit",
                                   itemType: .task, category: .general, createdAt: clock,
                                   dueDate: due, captureSession: dentistSession)
        container.mainContext.insert(clinicSession)
        container.mainContext.insert(dentistSession)
        container.mainContext.insert(clinic)
        container.mainContext.insert(dentist)
        try container.mainContext.save()
        let spoken = "I need you to cancel the reminder about the appointment tomorrow. I cannot remember whether I called it the clinic visit or the dentist visit when I saved it. Do not guess between them just because one was created more recently. I can choose the right one when I see the names.\n\nAlso buy a packet of envelopes. That is a clear new task unrelated to the appointment, so it can be saved while the cancellation waits. Keep the cancellation request visible and ask me which saved reminder I mean. None of the appointment reminders should change before I select one."
        let result = try await repository.createCaptureResult(
            text: spoken, source: .inAppVoice, createdAt: clock,
            schedulesReminders: false
        )
        guard case .ambiguous(operation: .cancel, let ids) = try XCTUnwrap(result.operationOutcome) else {
            return XCTFail("Expected a saved cancellation choice")
        }
        XCTAssertEqual(Set(ids), [clinic.id, dentist.id])
        XCTAssertEqual(CaptureOperationState.read(from: result.session.operationStateData)?.phase, .pendingChoice)
        XCTAssertEqual(result.session.originalTranscription, spoken)
        XCTAssertTrue(result.items.contains { $0.displayTitle.localizedCaseInsensitiveContains("envelopes") })
        let review = try XCTUnwrap(result.items.first { $0.displayTitle == "Choose which saved reminder to cancel" })
        XCTAssertEqual(CaptureOperationState.read(from: result.session.operationStateData)?.reviewItemID,
                       review.id)
        XCTAssertEqual(try repository.pendingCaptureOperationChoices(for: review).map(\.id), ids)
        let envelope = try XCTUnwrap(result.items.first {
            $0.displayTitle.localizedCaseInsensitiveContains("envelopes")
        })
        XCTAssertTrue(try repository.pendingCaptureOperationChoices(for: envelope).isEmpty)
        try repository.choosePendingCaptureOperation(review, targetID: clinic.id)
        XCTAssertFalse(try allItems().contains { $0.id == clinic.id })
        XCTAssertTrue(try allItems().contains { $0.id == dentist.id })
        XCTAssertEqual(CaptureOperationState.read(from: result.session.operationStateData)?.targetID, clinic.id)
        try repository.choosePendingCaptureOperation(review, targetID: clinic.id)
        XCTAssertTrue(try allItems().contains { $0.id == dentist.id })
        XCTAssertTrue(try allItems().contains { $0.displayTitle.localizedCaseInsensitiveContains("envelopes") })
    }

    func testSavedDentistDateAmendmentKeepsIdentityProvenanceAndDistractor() async throws {
        let previousZone = NSTimeZone.default
        NSTimeZone.default = try XCTUnwrap(TimeZone(identifier: "America/Toronto"))
        defer { NSTimeZone.default = previousZone }
        let clock = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-05T13:00:00Z"))
        let oldDue = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-06T16:00:00Z"))
        let newDue = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-09T13:00:00Z"))
        let dentistSource = CaptureSession(originalTranscription: "Call the dentist about the appointment letter", createdAt: clock)
        let bikeSource = CaptureSession(originalTranscription: "Call the bike shop about the repaired wheel", createdAt: clock)
        let dentist = CapturedItem(originalTextSegment: dentistSource.originalTranscription,
                                   displayTitle: "Call the dentist about the appointment letter",
                                   itemType: .task, createdAt: clock, dueDate: oldDue,
                                   captureSession: dentistSource)
        let bike = CapturedItem(originalTextSegment: bikeSource.originalTranscription,
                                displayTitle: "Call the bike shop about the repaired wheel",
                                itemType: .task, createdAt: clock, dueDate: oldDue,
                                captureSession: bikeSource)
        for source in [dentistSource, bikeSource] { container.mainContext.insert(source) }
        for row in [dentist, bike] { container.mainContext.insert(row) }
        try container.mainContext.save()
        let notificationID = ReminderScheduler.notificationIdentifier(for: dentist.id)
        let spoken = "Change the saved dentist call from tomorrow to Friday, October ninth. It is the task about the appointment letter, not the bike shop call. Keep its wording and the fact that it is unfinished. I am changing an existing item rather than asking for a second dentist task.\n\nLeave the bike shop call exactly as it was. I have given enough information to distinguish the two saved tasks. If the app cannot safely update the dentist item and preserve the connection to this recording, keep my requested change visible for review instead of claiming it happened or changing a guessed item."
        let result = try await repository.createCaptureResult(text: spoken, source: .inAppVoice,
                                                               createdAt: clock, schedulesReminders: false)
        guard case .performed(operation: .reschedule, itemID: let updatedID, title: _) =
                try XCTUnwrap(result.operationOutcome) else {
            return XCTFail("Expected a completed saved-item date amendment")
        }
        XCTAssertEqual(updatedID, dentist.id)
        XCTAssertEqual(dentist.dueDate, newDue)
        XCTAssertFalse(dentist.isCompleted)
        XCTAssertEqual(dentist.displayTitle, "Call the dentist about the appointment letter")
        XCTAssertEqual(dentist.originalTextSegment, dentistSource.originalTranscription)
        XCTAssertEqual(bike.dueDate, oldDue)
        XCTAssertEqual(bike.displayTitle, "Call the bike shop about the repaired wheel")
        XCTAssertEqual(ReminderScheduler.notificationIdentifier(for: dentist.id), notificationID)
        XCTAssertEqual(result.session.originalTranscription, spoken)
        XCTAssertEqual(CaptureOperationState.read(from: result.session.operationStateData)?.targetID, dentist.id)
        XCTAssertEqual(CaptureOperationState.read(from: result.session.operationStateData)?.phase, .performed)
        XCTAssertTrue(result.items.isEmpty)
        let duplicate = try await repository.createCaptureResult(
            text: spoken, source: .inAppVoice, createdAt: clock,
            schedulesReminders: false
        )
        XCTAssertEqual(duplicate.session.id, result.session.id)
        XCTAssertEqual(dentist.dueDate, newDue)
        XCTAssertEqual(bike.dueDate, oldDue)
    }

    func testSavedDentistDateAmendmentSurvivesStoreReopenAndRetry() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpeakIt-amendment-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("thoughts.store")
        let clock = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-05T13:00:00Z"))
        let oldDue = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-06T16:00:00Z"))
        let newDue = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-09T13:00:00Z"))
        let dentistID = UUID()
        let bikeID = UUID()
        let spoken = "Change the saved dentist call from tomorrow to Friday, October ninth. "
            + "It is the task about the appointment letter, not the bike shop call. "
            + "Keep its wording and the fact that it is unfinished. "
            + "I am changing an existing item rather than asking for a second dentist task. "
            + "Leave the bike shop call exactly as it was."
        var amendmentID: UUID!

        let previousZone = NSTimeZone.default
        NSTimeZone.default = try XCTUnwrap(TimeZone(identifier: "America/Toronto"))
        defer { NSTimeZone.default = previousZone }
        do {
            let configuration = ModelConfiguration(schema: PersistenceController.schema, url: url)
            let store = try ModelContainer(for: PersistenceController.schema,
                                           migrationPlan: SpeakItMigrationPlan.self,
                                           configurations: [configuration])
            let context = store.mainContext
            for (id, title) in [(dentistID, "Call the dentist about the appointment letter"),
                                (bikeID, "Call the bike shop about the repaired wheel")] {
                let source = CaptureSession(originalTranscription: title, createdAt: clock)
                let row = CapturedItem(id: id, originalTextSegment: title,
                                       displayTitle: title, itemType: .task,
                                       createdAt: clock, dueDate: oldDue,
                                       captureSession: source)
                context.insert(source)
                context.insert(row)
            }
            try context.save()
            let saved = SwiftDataThoughtRepository(modelContext: context,
                                                   requestsReminderAuthorization: false,
            permitsOnDeviceIntelligence: false)
            let result = try await saved.createCaptureResult(
                text: spoken, source: .inAppVoice, createdAt: clock,
                schedulesReminders: false
            )
            guard case .performed(operation: .reschedule, itemID: let updatedID, title: _) =
                    try XCTUnwrap(result.operationOutcome) else {
                return XCTFail("Expected a grounded saved date amendment")
            }
            XCTAssertEqual(updatedID, dentistID)
            amendmentID = result.session.id
        }
        do {
            let configuration = ModelConfiguration(schema: PersistenceController.schema, url: url)
            let store = try ModelContainer(for: PersistenceController.schema,
                                           migrationPlan: SpeakItMigrationPlan.self,
                                           configurations: [configuration])
            let context = store.mainContext
            let saved = SwiftDataThoughtRepository(modelContext: context,
                                                   requestsReminderAuthorization: false,
            permitsOnDeviceIntelligence: false)
            let rows = try context.fetch(FetchDescriptor<CapturedItem>())
            let dentist = try XCTUnwrap(rows.first { $0.id == dentistID })
            let bike = try XCTUnwrap(rows.first { $0.id == bikeID })
            XCTAssertEqual(dentist.dueDate, newDue)
            XCTAssertEqual(dentist.displayTitle, "Call the dentist about the appointment letter")
            XCTAssertEqual(dentist.originalTextSegment,
                           "Call the dentist about the appointment letter")
            XCTAssertFalse(dentist.isCompleted)
            XCTAssertEqual(bike.dueDate, oldDue)
            XCTAssertEqual(rows.filter { $0.id == dentistID }.count, 1)
            let receipt = try XCTUnwrap(context.fetch(FetchDescriptor<CaptureSession>())
                .first { $0.id == amendmentID })
            XCTAssertEqual(receipt.originalTranscription, spoken)
            XCTAssertEqual(CaptureOperationState.read(from: receipt.operationStateData)?.phase,
                           .performed)
            XCTAssertEqual(CaptureOperationState.read(from: receipt.operationStateData)?.targetID,
                           dentistID)
            let retry = try await saved.createCaptureResult(
                text: spoken, source: .inAppVoice, createdAt: clock,
                schedulesReminders: false
            )
            XCTAssertEqual(retry.session.id, amendmentID)
            XCTAssertEqual(dentist.dueDate, newDue)
            XCTAssertEqual(bike.dueDate, oldDue)
        }
    }

    func testPendingSavedChoiceSurvivesStoreReopenAndCannotChooseTwice() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpeakIt-choice-\(UUID().uuidString).store")
        defer { try? FileManager.default.removeItem(at: url) }
        let clock = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-05T13:00:00Z"))
        let source = "I need you to cancel the reminder about the appointment tomorrow. I cannot remember whether I called it the clinic visit or the dentist visit when I saved it. Do not guess between them just because one was created more recently. I can choose the right one when I see the names.\n\nAlso buy a packet of envelopes. That is a clear new task unrelated to the appointment, so it can be saved while the cancellation waits. Keep the cancellation request visible and ask me which saved reminder I mean. None of the appointment reminders should change before I select one."
        let originalDue = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-06T04:00:00Z"))
        let clinicID = UUID()
        let dentistID = UUID()
        var reviewID: UUID!
        var captureID: UUID!
        do {
            let configuration = ModelConfiguration(schema: PersistenceController.schema, url: url)
            let store = try ModelContainer(for: PersistenceController.schema,
                                           migrationPlan: SpeakItMigrationPlan.self,
                                           configurations: [configuration])
            let context = store.mainContext
            for (id, title) in [(clinicID, "Clinic visit"), (dentistID, "Dentist visit")] {
                let source = CaptureSession(originalTranscription: title, createdAt: clock)
                let row = CapturedItem(id: id, originalTextSegment: title,
                                       displayTitle: title, itemType: .task,
                                       createdAt: clock, dueDate: originalDue,
                                       temporalIntent: TemporalIntent(kind: .dateOnly,
                                           day: CalendarDay(year: 2026, month: 10, day: 6)),
                                       captureSession: source)
                context.insert(source)
                context.insert(row)
            }
            try context.save()
            let saved = SwiftDataThoughtRepository(modelContext: context,
                                                   requestsReminderAuthorization: false,
            permitsOnDeviceIntelligence: false)
            let answer = try await saved.createCaptureResult(
                text: source,
                source: .inAppVoice, createdAt: clock, schedulesReminders: false
            )
            XCTAssertEqual(answer.session.originalTranscription, source)
            captureID = answer.session.id
            reviewID = try XCTUnwrap(answer.items.first {
                $0.displayTitle == "Choose which saved reminder to cancel"
            }).id
            XCTAssertEqual(CaptureOperationState.read(from: answer.session.operationStateData)?.phase, .pendingChoice)
        }
        do {
            let configuration = ModelConfiguration(schema: PersistenceController.schema, url: url)
            let store = try ModelContainer(for: PersistenceController.schema,
                                           migrationPlan: SpeakItMigrationPlan.self,
                                           configurations: [configuration])
            let context = store.mainContext
            let saved = SwiftDataThoughtRepository(modelContext: context,
                                                   requestsReminderAuthorization: false,
            permitsOnDeviceIntelligence: false)
            let review = try XCTUnwrap(context.fetch(FetchDescriptor<CapturedItem>())
                .first { $0.id == reviewID })
            XCTAssertEqual(review.captureSession?.id, captureID)
            XCTAssertEqual(review.captureSession?.originalTranscription, source)
            XCTAssertEqual(Set(try saved.pendingCaptureOperationChoices(for: review).map(\.id)),
                           [clinicID, dentistID])
            try saved.choosePendingCaptureOperation(review, targetID: dentistID)
            try saved.choosePendingCaptureOperation(review, targetID: dentistID)
            XCTAssertThrowsError(try saved.choosePendingCaptureOperation(review, targetID: clinicID))
            XCTAssertEqual(review.captureSession?.originalTranscription, source)
            let rows = try context.fetch(FetchDescriptor<CapturedItem>())
            let unchangedClinic = try XCTUnwrap(rows.first { $0.id == clinicID })
            XCTAssertEqual(unchangedClinic.originalTextSegment, "Clinic visit")
            XCTAssertEqual(unchangedClinic.displayTitle, "Clinic visit")
            XCTAssertEqual(unchangedClinic.dueDate, originalDue)
            XCTAssertNil(unchangedClinic.reminderDate)
            XCTAssertFalse(unchangedClinic.isCompleted)
            XCTAssertFalse(unchangedClinic.isArchived)
            XCTAssertEqual(rows.filter { $0.id == clinicID }.count, 1)
            XCTAssertEqual(rows.filter { $0.displayTitle.localizedCaseInsensitiveContains("envelopes") }.count, 1)
            XCTAssertFalse(rows.contains { $0.id == dentistID })
            XCTAssertTrue(rows.contains { $0.displayTitle.localizedCaseInsensitiveContains("envelopes") })
            XCTAssertEqual(CaptureOperationState.read(from: review.captureSession?.operationStateData)?.targetID, dentistID)
        }
        do {
            let configuration = ModelConfiguration(schema: PersistenceController.schema, url: url)
            let store = try ModelContainer(for: PersistenceController.schema,
                                           migrationPlan: SpeakItMigrationPlan.self,
                                           configurations: [configuration])
            let context = store.mainContext
            let saved = SwiftDataThoughtRepository(modelContext: context,
                                                   requestsReminderAuthorization: false,
            permitsOnDeviceIntelligence: false)
            let review = try XCTUnwrap(context.fetch(FetchDescriptor<CapturedItem>())
                .first { $0.id == reviewID })
            XCTAssertEqual(CaptureOperationState.read(from: review.captureSession?.operationStateData)?.phase, .performed)
            XCTAssertEqual(CaptureOperationState.read(from: review.captureSession?.operationStateData)?.targetID, dentistID)
            try saved.choosePendingCaptureOperation(review, targetID: dentistID)
            XCTAssertThrowsError(try saved.choosePendingCaptureOperation(review, targetID: clinicID))
            XCTAssertEqual(review.captureSession?.originalTranscription, source)
            let reopenedRows = try context.fetch(FetchDescriptor<CapturedItem>())
            XCTAssertEqual(reopenedRows.filter { $0.displayTitle.localizedCaseInsensitiveContains("envelopes") }.count, 1)
            XCTAssertEqual(reopenedRows.first { $0.id == clinicID }?.dueDate, originalDue)
            let ids = Set(reopenedRows.map(\.id))
            XCTAssertTrue(ids.contains(clinicID))
            XCTAssertFalse(ids.contains(dentistID))
        }
    }

    func testQuotedRevisionTracksDistinctOccurrencesOfRepeatedActionWords() throws {
        let source = "Change the existing task “Call Maya” to “Call Tessa”"
        let revision = try XCTUnwrap(SavedItemRevision.read(source))
        XCTAssertFalse(revision.oldTitleUnitIDs.isEmpty)
        XCTAssertFalse(revision.replacementUnitIDs.isEmpty)
        XCTAssertTrue(revision.oldTitleUnitIDs.isDisjoint(with: revision.replacementUnitIDs))
        XCTAssertEqual(revision.oldTitle, "Call Maya")
        XCTAssertEqual(revision.replacementAction, "Call Tessa")
    }

    func testExplicitSavedRowDeletionAndCompletionKeepTheirTargets() async throws {
        XCTAssertEqual(CaptureOperationDetector.detect(
            "Delete my reminder to pick up hired speaker for the concert"
        )?.operation, .cancel)
        XCTAssertEqual(ThoughtExtractionEngine.extractWithRules(
            "Delete my reminder to pick up hired speaker for the concert"
        ).pendingOperation?.operation, .cancel)
        _ = try await capture("Pick up hired speaker for the concert")
        _ = try await capture("Return the borrowed folding chairs to Leila")
        let deletion = try await capture("Delete my reminder to pick up hired speaker for the concert")
        guard case let .performed(operation, _, _) = try XCTUnwrap(deletion.operationOutcome) else {
            return XCTFail("The explicitly named saved row should be deleted")
        }
        XCTAssertEqual(operation, .cancel)
        XCTAssertTrue(try activeTitles().contains { $0.localizedCaseInsensitiveContains("folding chairs") })

        _ = try await capture("Pay campsite deposit")
        XCTAssertEqual(CaptureOperationDetector.detect(
            "Mark my existing campsite deposit task complete"
        )?.operation, .complete)
        XCTAssertEqual(ThoughtExtractionEngine.extractWithRules(
            "Mark my existing campsite deposit task complete"
        ).pendingOperation?.operation, .complete)
        let completion = try await capture("Mark my existing campsite deposit task complete")
        guard case let .performed(completedOperation, _, _) = try XCTUnwrap(completion.operationOutcome) else {
            return XCTFail("Saved-row metadata should not obscure a uniquely named task")
        }
        XCTAssertEqual(completedOperation, .complete)
    }

    func testReferenceToAWorldObjectIsNotADeletionOfASavedRow() async throws {
        _ = try await capture("Buy a new display board")
        let result = try await capture("Remove the display board from the storeroom")
        XCTAssertNil(result.operationOutcome)
        XCTAssertTrue(try activeTitles().contains { $0.localizedCaseInsensitiveContains("Buy a new display board") })
    }

    func testExposedLongRevisionKeepsSavedIdentityReviewable() async throws {
        _ = try await capture("Pick up rental van at Central Depot on Friday")
        _ = try await capture("Return the packing blankets to Ivo")
        let result = try await capture(
            "The reminder about the rental van has the wrong collection point. I wrote “pick up van at Central Depot,” but the company moved that booking to the north branch on Keel Street. Please change the existing pickup item to the north branch; the collection is still Friday at eight in the morning. I do not need two van pickups. The separate task to return the packing blankets to Ivo still stands; those belong to him, not the van company. I checked the email twice because it also mentions Central Depot in the footer, but the booking line at the top gives the new branch. I should download that confirmation email for offline use in case my phone loses signal on the way. The vehicle size and driver name are unchanged. I was about to tell Ivo about the new van location, then realised he does not need to know until we arrange the blanket handoff, so no message to him now."
        )
        // 2026-10-02: the speaker explicitly asks to change the existing
        // pickup, names the old place, and exactly one saved pickup holds it,
        // so the place is revised on that same row. The day, identity and the
        // unrelated blankets task are untouched, and no second pickup appears.
        guard case .performed(.revise, let itemID, _)? = result.operationOutcome else {
            return XCTFail("expected the grounded place revision, got \(String(describing: result.operationOutcome))")
        }
        let van = try XCTUnwrap(try allItems().first { $0.id == itemID })
        XCTAssertTrue(van.displayTitle.localizedCaseInsensitiveContains("north branch"), van.displayTitle)
        XCTAssertFalse(van.displayTitle.localizedCaseInsensitiveContains("Central Depot"), van.displayTitle)
        XCTAssertTrue(van.originalTextSegment.localizedCaseInsensitiveContains("Central Depot"))
        XCTAssertEqual(try activeTitles().filter { $0.localizedCaseInsensitiveContains("van")
            && $0.localizedCaseInsensitiveContains("pick") }.count, 1)
        XCTAssertTrue(try activeTitles().contains { $0.localizedCaseInsensitiveContains("blankets") })
    }

    func testNamedWithdrawalDoesNotEraseIndependentEarlierOrLaterErrands() async throws {
        let result = try await capture(
            "Buy printer ink and envelopes, no skip envelopes, and call Omar."
        )
        XCTAssertNil(result.operationOutcome)
        XCTAssertEqual(result.items.count, 2)
        let titles = try activeTitles()
        XCTAssertTrue(titles.contains { $0.localizedCaseInsensitiveContains("printer ink") })
        XCTAssertTrue(titles.contains { $0.localizedCaseInsensitiveContains("Omar") })
        XCTAssertFalse(titles.contains { $0.localizedCaseInsensitiveContains("envelopes") })
    }

    func testShoppingListWithdrawalOwnsOnlyItsNamedProduct() async throws {
        let result = try await capture(
            "Put milk on my shopping list. Actually scratch milk. Buy eggs."
        )
        XCTAssertNil(result.operationOutcome)
        let titles = try activeTitles()
        XCTAssertTrue(titles.contains { $0.localizedCaseInsensitiveContains("eggs") })
        XCTAssertFalse(titles.contains { $0.localizedCaseInsensitiveContains("milk") })
    }

    func testNamedWithdrawalDoesNotEraseAnAllergyMemory() {
        let result = ThoughtExtractionEngine.extractWithRules(
            "Remember that Leo is allergic to milk. Scratch milk."
        )
        XCTAssertTrue(result.items.contains { $0.sourceQuote.localizedCaseInsensitiveContains("allergic") })
        XCTAssertFalse(result.operations.contains { $0.isScoped })
    }

    func testUnmatchedNamedWithdrawalStaysReviewableBesideIndependentErrands() async throws {
        let result = try await capture(
            "Buy printer ink, no skip envelopes, and call Omar."
        )
        guard case .ambiguous = try XCTUnwrap(result.operationOutcome) else {
            return XCTFail("An unmatched withdrawal must be held for review")
        }
        XCTAssertEqual(result.items.count, 3)
        XCTAssertEqual(result.items.filter(\.needsClarification).count, 1)
        XCTAssertTrue(try activeTitles().contains { $0.localizedCaseInsensitiveContains("printer ink") })
        XCTAssertTrue(try activeTitles().contains { $0.localizedCaseInsensitiveContains("Omar") })
    }

    func testTwoOperationsStayIndividuallyReviewableWithoutExecutingOnlyFirst() async throws {
        _ = try await capture("Remind me about the dentist on Friday")
        _ = try await capture("Remind me about the plumber on Monday")
        let result = try await capture(
            "Cancel the dentist reminder. Cancel the plumber reminder."
        )
        XCTAssertNil(result.operationOutcome)
        XCTAssertEqual(result.items.count, 2)
        XCTAssertTrue(result.items.allSatisfy(\.needsClarification))
        XCTAssertTrue(try activeTitles().contains { $0.localizedCaseInsensitiveContains("dentist") })
        XCTAssertTrue(try activeTitles().contains { $0.localizedCaseInsensitiveContains("plumber") })
    }

    func testLocalCompletionReceiptKeepsIndependentTailOperation() async throws {
        _ = try await capture("Remind me about the dentist on Friday")
        _ = try await capture("Remind me about the plumber on Monday")

        let result = try await capture(
            "Call the plumber—wait, no, I already called and the visit is booked. "
                + "Cancel the dentist reminder."
        )

        guard case let .performed(operation, _, title) = try XCTUnwrap(result.operationOutcome) else {
            return XCTFail("The independent tail request should reach saved-item resolution")
        }
        XCTAssertEqual(operation, .cancel)
        XCTAssertTrue(title.localizedCaseInsensitiveContains("dentist"))
        let items = try allItems()
        XCTAssertTrue(items.contains { $0.displayTitle.localizedCaseInsensitiveContains("called the plumber")
            && $0.itemType == .note })
        XCTAssertTrue(try activeTitles().contains { $0.localizedCaseInsensitiveContains("plumber") })
        XCTAssertFalse(try activeTitles().contains { $0.localizedCaseInsensitiveContains("dentist") })
    }

    func testLocalCompletionReceiptDoesNotExecuteReportedTailOperation() async throws {
        _ = try await capture("Remind me about the dentist on Friday")

        let result = try await capture(
            "Call the plumber—wait, no, I already called and the visit is booked. "
                + "Maya said, 'Cancel the dentist reminder.'"
        )

        XCTAssertNil(result.operationOutcome)
        XCTAssertTrue(try activeTitles().contains { $0.localizedCaseInsensitiveContains("dentist") })
        XCTAssertTrue(result.items.contains { $0.originalTextSegment.localizedCaseInsensitiveContains("Maya") })
    }

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

    func testCancelWithNoMatchKeepsAReviewableSourceWithoutInventingAReminder() async throws {
        _ = try await capture("Buy milk")

        let result = try await capture("Cancel the dentist reminder")

        guard case let .notFound(_, target) = try XCTUnwrap(result.operationOutcome) else {
            return XCTFail("Expected a not-found result")
        }
        XCTAssertTrue(target.localizedCaseInsensitiveContains("dentist"))
        XCTAssertEqual(result.items.count, 1)
        XCTAssertTrue(result.items[0].needsClarification)
        XCTAssertEqual(result.items[0].originalTextSegment, "Cancel the dentist reminder")
        XCTAssertEqual(result.items[0].itemType, .unclear)
        XCTAssertTrue(try activeTitles().contains("Buy milk"))
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
        let confirmationSessionID = try XCTUnwrap(reviewRow.captureSession?.id)
        let candidateIDs = try allItems().filter { $0.id != reviewRow.id }.map(\.id)

        try repository.confirmPendingOperation(reviewRow)

        // Everything the request named is gone, and so is the review row
        // itself — it was only ever the confirmation vehicle, not a thought
        // worth keeping once its request is resolved.
        XCTAssertTrue(try allItems().isEmpty)
        XCTAssertNil(PendingOperationStore.record(for: reviewRow.id))
        let sessions = try container.mainContext.fetch(FetchDescriptor<CaptureSession>())
        let source = try XCTUnwrap(sessions.first { $0.id == confirmationSessionID })
        XCTAssertEqual(source.originalTranscription, "Cancel every reminder")
        let receipt = try XCTUnwrap(CaptureOperationState.read(from: source.operationStateData))
        XCTAssertEqual(receipt.phase, .performed)
        XCTAssertEqual(receipt.operation, .cancel)
        XCTAssertEqual(Set(receipt.candidateIDs), Set(candidateIDs))
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

    func testBroadCancellationReceiptSurvivesReopenAndRetry() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpeakIt-broad-cancel-receipt-\(UUID().uuidString).store")
        defer { try? FileManager.default.removeItem(at: url) }
        let clock = Date(timeIntervalSince1970: 1_791_205_200)
        let request = "Cancel every reminder"
        var requestID: UUID!
        do {
            let config = ModelConfiguration(schema: PersistenceController.schema, url: url)
            let store = try ModelContainer(for: PersistenceController.schema,
                                           migrationPlan: SpeakItMigrationPlan.self,
                                           configurations: [config])
            let saved = SwiftDataThoughtRepository(modelContext: store.mainContext,
                                                   requestsReminderAuthorization: false,
            permitsOnDeviceIntelligence: false)
            for (index, text) in ["Buy milk", "Call Mom on Friday"].enumerated() {
                _ = try await saved.createCaptureResult(
                    text: text, source: .inAppText,
                    createdAt: clock.addingTimeInterval(Double(index)),
                    schedulesReminders: false
                )
            }
            let held = try await saved.createCaptureResult(
                text: request, source: .inAppText,
                createdAt: clock.addingTimeInterval(2), schedulesReminders: false
            )
            requestID = held.session.id
            let review = try XCTUnwrap(held.items.first)
            try saved.confirmPendingOperation(review)
            XCTAssertTrue(try store.mainContext.fetch(FetchDescriptor<CapturedItem>()).isEmpty)
        }
        do {
            let config = ModelConfiguration(schema: PersistenceController.schema, url: url)
            let store = try ModelContainer(for: PersistenceController.schema,
                                           migrationPlan: SpeakItMigrationPlan.self,
                                           configurations: [config])
            let saved = SwiftDataThoughtRepository(modelContext: store.mainContext,
                                                   requestsReminderAuthorization: false,
            permitsOnDeviceIntelligence: false)
            let retry = try await saved.createCaptureResult(
                text: request, source: .inAppText,
                createdAt: clock.addingTimeInterval(3), schedulesReminders: false
            )
            XCTAssertTrue(retry.isDuplicate)
            XCTAssertEqual(retry.session.id, requestID)
            guard case .performedMany(operation: .cancel, count: 2) = retry.operationOutcome else {
                return XCTFail("Expected a durable broad cancellation receipt")
            }
            XCTAssertTrue(retry.items.isEmpty)
            XCTAssertTrue(try store.mainContext.fetch(FetchDescriptor<CapturedItem>()).isEmpty)
            let sessions = try store.mainContext.fetch(FetchDescriptor<CaptureSession>())
            XCTAssertEqual(sessions.first { $0.id == requestID }?.originalTranscription, request)
            XCTAssertTrue(sessions.contains { $0.originalTranscription == "Buy milk" })
            XCTAssertTrue(sessions.contains { $0.originalTranscription == "Call Mom on Friday" })
        }
    }

    func testBroadCancellationRevalidatesEveryCandidateBeforeDeletingAny() async throws {
        _ = try await capture("Buy milk")
        _ = try await capture("Call Mom on Friday")
        let held = try await capture("Cancel every reminder")
        let review = try XCTUnwrap(held.items.first)
        let milk = try XCTUnwrap(try allItems().first { $0.displayTitle == "Buy milk" })
        try repository.setCompleted(milk, completed: true)

        XCTAssertThrowsError(try repository.confirmPendingOperation(review))
        let items = try allItems()
        XCTAssertNotNil(items.first { $0.id == milk.id && $0.isCompleted })
        XCTAssertNotNil(items.first { $0.displayTitle == "Call Mom on Friday" })
        XCTAssertNotNil(items.first { $0.id == review.id && $0.needsClarification })
        PendingOperationStore.remove(review.id)
    }

    func testRepeatedCancellationOfTheSameThingIsHarmless() async throws {
        _ = try await capture("Remind me about the dentist on Friday")
        _ = try await capture("Buy milk")

        let firstAt = Date.now
        let first = try await repository.createCaptureResult(
            text: "Cancel the dentist reminder", source: .inAppText,
            createdAt: firstAt, schedulesReminders: false
        )
        let immediateRetry = try await repository.createCaptureResult(
            text: "Cancel the dentist reminder", source: .inAppText,
            createdAt: firstAt.addingTimeInterval(1), schedulesReminders: false
        )
        let laterRequest = try await repository.createCaptureResult(
            text: "Cancel the dentist reminder", source: .inAppText,
            createdAt: firstAt.addingTimeInterval(16), schedulesReminders: false
        )

        guard case .performed = try XCTUnwrap(first.operationOutcome) else {
            return XCTFail("Expected the first cancellation to act")
        }
        XCTAssertTrue(immediateRetry.isDuplicate)
        XCTAssertEqual(immediateRetry.session.id, first.session.id)
        guard case .performed = try XCTUnwrap(immediateRetry.operationOutcome) else {
            return XCTFail("An immediate retry should read the durable performed receipt")
        }
        guard case .notFound = try XCTUnwrap(laterRequest.operationOutcome) else {
            return XCTFail("A new request outside the retry window should find no target")
        }
        XCTAssertTrue(try activeTitles().contains("Buy milk"))
        XCTAssertEqual(try allItems().filter(\.needsClarification).count, 1,
                       "only the later new request remains reviewable without acting twice")
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

    func testUnmatchedCompletedStatementRemainsDurablyReviewable() async throws {
        let text = "I already mailed the form"
        let result = try await capture(text)
        guard case .notFound = try XCTUnwrap(result.operationOutcome) else {
            return XCTFail("Expected an unmatched completion receipt")
        }
        XCTAssertEqual(result.items.count, 1)
        XCTAssertEqual(result.items[0].originalTextSegment, text)
        XCTAssertTrue(result.items[0].needsClarification)
        XCTAssertEqual(result.session.processingStatus, .complete)
    }

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
        let clock = Date.now
        _ = try await repository.createCaptureResult(
            text: "Call Mom on Friday", source: .inAppText,
            createdAt: clock, schedulesReminders: false
        )
        let first = try await repository.createCaptureResult(
            text: "I already called Mom", source: .inAppText,
            createdAt: clock.addingTimeInterval(1), schedulesReminders: false
        )
        let retry = try await repository.createCaptureResult(
            text: "I already called Mom", source: .inAppText,
            createdAt: clock.addingTimeInterval(2), schedulesReminders: false
        )
        XCTAssertTrue(retry.isDuplicate)
        XCTAssertEqual(retry.session.id, first.session.id,
                       "A retry reads the performed receipt without completing a second time")

        let second = try await repository.createCaptureResult(
            text: "I already called Mom", source: .inAppText,
            createdAt: clock.addingTimeInterval(30), schedulesReminders: false
        )

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
        XCTAssertTrue(try activeTitles().contains("Buy toothpaste"))
        XCTAssertEqual(result.items.count, 1)
        XCTAssertTrue(result.items[0].needsClarification)
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
            requestsReminderAuthorization: false,
            permitsOnDeviceIntelligence: false
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

/// Complete saved-field scope is proved before an edit receives authority.
/// These controls inspect exact ranges and real rules; repository effects are
/// covered by the adjacent store tests, never inferred from a proposal.
final class SavedFieldRevisionScopeTests: XCTestCase {
    func testRecipientRevisionOwnsOnlyCompletePrefixBeforeIndependentTail() throws {
        let context = "I want to save the phrase 'quiet courts' as an idea."
        let request = "Change my saved dentist reminder so I call Noor instead of Maya"
        for (join, tail) in [
            (", and ", "mail the parcel."),
            (", and ", "remind me to mail the parcel tomorrow at 5 PM."),
            (" and ", "arrange a moisture inspection."),
            ("; ", "I will rinse the bowl."),
            (", ", "I need to count the crates.")
        ] {
            let source = context + " " + request + join + tail
            let field = try XCTUnwrap(SavedFieldRevision.read(source), source)
            XCTAssertEqual(field.field, .person, source)
            XCTAssertEqual(field.itemWords, "dentist", source)
            XCTAssertEqual(field.newValue, "Noor", source)
            XCTAssertEqual(field.statedOldValue, "Maya", source)
            XCTAssertEqual(field.requestSentence, request, source)
            XCTAssertEqual(String(source[field.requestRange]), request, source)
            let start = try XCTUnwrap(field.continuationStart, source)
            XCTAssertEqual(String(source[start...]), tail, source)
            let partition = CaptureOperationDetector.partitionWithOwnership(source)
            let operation = try XCTUnwrap(partition.operations.first, source)
            XCTAssertEqual(partition.operations.count, 1, source)
            XCTAssertFalse(operation.needsReview, source)
            XCTAssertEqual(operation.savedFieldRevision, field, source)
            XCTAssertEqual(operation.sourceQuote, request, source)
            XCTAssertEqual(partition.remainder, context + " " + tail, source)
            let ledger = SourceUnitLedger(source)
            XCTAssertEqual(operation.sourceUnitIDs, ledger.ids(in: field.requestRange), source)
            let tailIDs = ledger.ids(in: start..<source.endIndex)
            XCTAssertFalse(tailIDs.isEmpty, source)
            XCTAssertTrue(tailIDs.isDisjoint(with: operation.sourceUnitIDs), source)
            XCTAssertTrue(tailIDs.isSubset(of: partition.retainedUnitIDs), source)
            XCTAssertTrue(partition.unownedMeaningfulIDs(in: source).isEmpty, source)
        }
    }

    func testIndependentRecipientRevisionTailReachesRealRulesWithoutJoiningRetainedIdea() throws {
        let retained = "I want to save the phrase 'quiet courts' as an idea."
        let request = "Change my saved dentist reminder so I call Noor instead of Maya"
        for tail in ["mail the parcel.", "remind me to mail the parcel tomorrow at 5 PM."] {
            let source = retained + " " + request + ", and " + tail
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Toronto"))
            let clock = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 12, hour: 10)))
            let rules = ThoughtExtractionEngine.extractWithRules(source, referenceDate: clock, calendar: calendar)
            XCTAssertEqual(rules.operations.count, 1, source)
            XCTAssertEqual(rules.operations.first?.savedFieldRevision?.requestSentence, request, source)
            XCTAssertEqual(rules.items.count, 2, source)
            let memory = try XCTUnwrap(rules.items.first { $0.organization.itemType == .idea }, source)
            let action = try XCTUnwrap(rules.items.first { $0.organization.itemType.isActionable }, source)
            XCTAssertEqual(memory.sourceQuote, retained, source)
            XCTAssertTrue(action.sourceQuote.localizedCaseInsensitiveContains("mail the parcel"), source)
            XCTAssertFalse(action.sourceQuote.localizedCaseInsensitiveContains("change my saved"), source)
            XCTAssertFalse(action.needsReview, source)
            if tail.hasPrefix("remind") {
                let date = try XCTUnwrap(action.organization.reminderDate, source)
                XCTAssertEqual(calendar.component(.hour, from: date), 17, source)
            } else {
                XCTAssertNil(action.organization.reminderDate, source)
                XCTAssertNil(action.organization.dueDate, source)
            }
        }
    }

    func testCompletePersonComplementsAndPortableUnicodeRanges() throws {
        for (newName, oldName) in [("Will", "Maya"), ("May", "Maya"),
                                   ("Noor", "Will"), ("Noor", "May"),
                                   ("will", "Maya"), ("may", "Maya")] {
            let source = "Change my saved dentist reminder so I call \(newName) instead of \(oldName)."
            let field = try XCTUnwrap(SavedFieldRevision.read(source), source)
            XCTAssertEqual(field.newValue, newName, source)
            XCTAssertEqual(field.statedOldValue, oldName, source)
        }
        for suffix in ["for the price.", "for the price instead of Maya.", "instead.", "not Maya.", "rather than Maya."] {
            let source = "The mural has a blue door 🟦. Change my saved vegetable box reminder so I ask Tessa " + suffix
            let field = try XCTUnwrap(SavedFieldRevision.read(source), source)
            XCTAssertEqual(field.newValue, "Tessa", source)
            XCTAssertEqual(field.itemWords, "vegetable box", source)
            XCTAssertEqual(String(source[field.requestRange]), field.requestSentence, source)
            XCTAssertNil(field.continuationStart, source)
        }
        let source = "The café is quiet 🟦. Change my saved dentist reminder so I call Zoë instead of Maya, and mail the parcel."
        let field = try XCTUnwrap(SavedFieldRevision.read(source))
        XCTAssertEqual(field.newValue, "Zoë")
        XCTAssertEqual(String(source[field.requestRange]), "Change my saved dentist reminder so I call Zoë instead of Maya")
        XCTAssertEqual(String(source[try XCTUnwrap(field.continuationStart)...]), "mail the parcel.")
    }

    func testUnprovedFieldExtentStaysVisibleAndCannotBeReauthorizedFromPrefix() throws {
        let prefix = "Change my saved dentist reminder so I call Noor instead of Maya"
        for suffix in [
            " and adjust the bracket.",
            " and Noor.",
            ", perhaps mail the parcel.",
            " if Maya is away.",
            " because I might call the library.",
            " and change my saved library reminder so I call Tessa instead of Noor.",
            " and update the saved storage box purchase from four boxes to two boxes.",
            " and cancel my saved library reminder.",
            ". Change my saved library reminder so I call Tessa instead of Noor.",
            ", and say 'cancel the library reminder'."
        ] {
            let source = prefix + suffix
            XCTAssertNil(SavedFieldRevision.read(source), source)
            XCTAssertTrue(SavedFieldRevision.hasUnprovedFieldRequest(source), source)
            let partition = CaptureOperationDetector.partitionWithOwnership(source)
            let held = try XCTUnwrap(partition.operations.first, source)
            XCTAssertEqual(partition.operations.count, 1, source)
            XCTAssertTrue(held.needsReview, source)
            XCTAssertNil(held.savedFieldRevision, source)
            XCTAssertEqual(held.sourceQuote, source, source)
            XCTAssertNil(partition.remainder, source)
            XCTAssertTrue(partition.unownedMeaningfulIDs(in: source).isEmpty, source)
            let direct = try XCTUnwrap(CaptureOperationDetector.detect(prefix, within: source), source)
            XCTAssertTrue(direct.needsReview, source)
            XCTAssertNil(direct.savedFieldRevision, source)
            XCTAssertEqual(direct.sourceQuote, source, source)
        }
    }

    func testAnaphoricTargetRequiresCompleteUniqueSavedItemIntroduction() throws {
        let request = "Change that same item so I ask Tessa for the price."
        for intro in [
            "The vegetable box reminder says to ask Maya for the price.",
            "The vegetable box reminder from yesterday was assigned to Maya.",
            "The vegetable box reminder from yesterday says to ask Maya for the price. She is not handling orders this week."
        ] {
            let source = intro + " " + request
            let field = try XCTUnwrap(SavedFieldRevision.read(source), source)
            XCTAssertTrue(field.itemWords.hasPrefix("The vegetable box reminder"), source)
            XCTAssertFalse(field.itemWords.contains("She is"), source)
            XCTAssertEqual(field.requestSentence, request, source)
            XCTAssertEqual(field.newValue, "Tessa", source)
        }
        for intro in [
            "I want to save the phrase 'ask Maya for the vegetable box price' as an idea.",
            "Maya said the vegetable box reminder says to ask Maya.",
            "'The vegetable box reminder says to ask Maya.'",
            "The vegetable box reminder does not say to ask Maya.",
            "If I had a vegetable box reminder, it would say to ask Maya.",
            "The vegetable box reminder says to ask Maya. The fruit box reminder says to ask Maya.",
            "The vegetable box reminder says to ask Maya, and mail the parcel.",
            "The vegetable box reminder says to ask Maya. She is away and mail the parcel."
        ] {
            let source = intro + " " + request
            XCTAssertNil(SavedFieldRevision.read(source), source)
            let partition = CaptureOperationDetector.partitionWithOwnership(source)
            XCTAssertTrue(partition.operations.allSatisfy { $0.needsReview && $0.savedFieldRevision == nil }, source)
            XCTAssertEqual(partition.operations.first?.sourceQuote, source, source)
        }
    }

    func testOutsideAnaphoricFieldRequestAfterQuotedStopRetainsCompleteReviewOwnership() throws {
        let request = "Change that same item so I ask Tessa for the price."
        for (opening, closing) in [("'", "'"), ("\"", "\""), ("‘", "’"), ("“", "”")] {
            for stop in [".", "!", "?"] {
                let source = opening + "The vegetable box reminder says to ask Maya" + stop
                    + closing + " " + request
                XCTAssertNil(SavedFieldRevision.read(source), source)
                XCTAssertTrue(SavedFieldRevision.hasUnprovedFieldRequest(source), source)
                let partition = CaptureOperationDetector.partitionWithOwnership(source)
                let held = try XCTUnwrap(partition.operations.first, source)
                XCTAssertEqual(partition.operations.count, 1, source)
                XCTAssertEqual(held.operation, .revise, source)
                XCTAssertTrue(held.needsReview, source)
                XCTAssertNil(held.target, source)
                XCTAssertNil(held.savedFieldRevision, source)
                XCTAssertEqual(held.sourceQuote, source, source)
                XCTAssertEqual(held.sourceUnitIDs, Set(SourceUnitLedger(source).words.indices), source)
                XCTAssertNil(partition.remainder, source)
                XCTAssertTrue(partition.retainedUnitIDs.isEmpty, source)
                XCTAssertTrue(partition.unownedMeaningfulIDs(in: source).isEmpty, source)
            }
        }
    }

    func testQuotedStopReviewBoundaryCannotAuthorizeEditOrOrdinaryTodayTask() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Toronto"))
        let clock = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 12, hour: 10)))
        for source in [
            "'The vegetable box reminder says to ask Maya.' Change that same item so I ask Tessa for the price.",
            "Maya said 'The vegetable box reminder says to ask Maya.' Change that same item so I ask Tessa for the price.",
            "If Maya said 'The vegetable box reminder says to ask Maya.' Change my saved vegetable box reminder so I ask Tessa for the price."
        ] {
            // Only the conservative guard gains a quoted-stop boundary. It
            // neither imports a quoted antecedent nor sheds an outer matrix
            // to turn this mixed source into a positive field certificate.
            XCTAssertNil(SavedFieldRevision.read(source), source)
            XCTAssertTrue(SavedFieldRevision.hasUnprovedFieldRequest(source), source)
            let rules = ThoughtExtractionEngine.extractWithRules(source, referenceDate: clock, calendar: calendar)
            XCTAssertEqual(rules.operations.count, 1, source)
            let held = try XCTUnwrap(rules.operations.first, source)
            XCTAssertEqual(held.operation, .revise, source)
            XCTAssertTrue(held.needsReview, source)
            XCTAssertNil(held.savedFieldRevision, source)
            XCTAssertEqual(held.sourceQuote, source, source)
            XCTAssertFalse(rules.items.contains { $0.organization.itemType.isActionable && !$0.needsReview }, source)
        }
        for source in [
            "'Change my saved vegetable box reminder so I ask Tessa for the price.'",
            "Maya said 'Change my saved vegetable box reminder so I ask Tessa for the price.'",
            "'The vegetable box reminder says to ask Maya. Change my saved vegetable box reminder so I ask Tessa for the price."
        ] {
            XCTAssertNil(SavedFieldRevision.read(source), source)
            XCTAssertFalse(CaptureOperationDetector.partitionWithOwnership(source).operations.contains {
                !$0.needsReview && $0.savedFieldRevision != nil
            }, source)
        }
    }

    func testPlaceFieldOwnsCompleteNominalAndKeepsIndependentContextOrAction() throws {
        let request = "Please change the existing pickup item to the north branch on Keel Street"
        for (join, tail) in [("; ", "the collection is still Friday at eight in the morning."),
                             (", and ", "mail the parcel.")] {
            let source = request + join + tail
            let field = try XCTUnwrap(SavedFieldRevision.read(source), source)
            XCTAssertEqual(field.field, .place, source)
            XCTAssertEqual(field.newValue, "north branch on Keel Street", source)
            XCTAssertEqual(field.requestSentence, request, source)
            XCTAssertEqual(CaptureOperationDetector.partitionWithOwnership(source).remainder, tail, source)
        }
        let coordinated = "Change my saved pickup item to the north and south branches."
        XCTAssertEqual(SavedFieldRevision.read(coordinated)?.newValue, "north and south branches")
        XCTAssertNil(SavedFieldRevision.read(coordinated)?.continuationStart)
        for source in [
            "Change my saved pickup item to take the blue kit to Evan.",
            "Change my saved pickup item to the north branch and the garage.",
            "Change my saved pickup item to the north branch if it is open.",
            "Change my saved pickup item to the north branch and adjust the ramp.",
            "Change my saved pickup item to the north branch adjust the ramp."
        ] {
            XCTAssertNil(SavedFieldRevision.read(source), source)
            XCTAssertTrue(CaptureOperationDetector.partitionWithOwnership(source).operations.allSatisfy(\.needsReview), source)
        }
    }

    func testOtherVoiceNegationAndConditionsNeverConstructMutableFieldPlan() {
        let request = "Change my saved dentist reminder so I call Noor instead of Maya"
        for source in [
            "Maya said, " + request + ".",
            "'" + request + ".'",
            "Do not " + request.lowercased() + ".",
            "If Maya is away, " + request.lowercased() + ".",
            "I might " + request.lowercased() + ".",
            "Yesterday I changed my saved dentist reminder so I call Noor instead of Maya."
        ] {
            XCTAssertNil(SavedFieldRevision.read(source), source)
            XCTAssertFalse(CaptureOperationDetector.partitionWithOwnership(source).operations.contains {
                $0.savedFieldRevision != nil && !$0.needsReview
            }, source)
        }
    }
}
