import SwiftData
import XCTest
@testable import SpeakIt

/// The interpreter's verdict has to survive the trip into storage.
///
/// The pipeline has always produced a `SemanticState` — how settled a reading
/// is, plus the named `SemanticGap` when it is not — and until version 4 it was
/// dropped between `OrganizedThought` and `CapturedItem`. Everything downstream
/// then reconstructed a reason from the item's own fields, which is a different
/// answer arrived at by different means: "Let me know if the meeting is Tuesday
/// or Wednesday" came back as "Task or note?" because the reading had been
/// reduced to `itemType == .unclear` on the way in.
///
/// These tests are about the plumbing only. Nothing here asks whether a sentence
/// was read well — `SemanticCorpusTests` does that — and nothing here changes
/// what any sentence resolves to.
@MainActor
final class SemanticStatePersistenceTests: XCTestCase {
    private var storeURL: URL!
    private var previousRecurrences: [RecurrenceRecordSnapshot] = []
    /// Every container opened during a test, kept alive until it ends.
    ///
    /// Releasing a `ModelContainer` resets its context, and touching any model
    /// instance that came from it after that is a trap, not an error. These
    /// tests deliberately open a second container over the same file to prove a
    /// value reached the disk, so the first one has to outlive the comparison.
    private var openContainers: [ModelContainer] = []

    override func setUpWithError() throws {
        previousRecurrences = RecurrenceStore.snapshots()
        storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpeakItSemantic-\(UUID().uuidString)")
            .appendingPathExtension("store")
    }

    override func tearDownWithError() throws {
        RecurrenceStore.restore(previousRecurrences)
        openContainers.removeAll()
        for suffix in ["", "-shm", "-wal"] {
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: storeURL.path + suffix))
        }
        storeURL = nil
    }

    /// A real file-backed store opened the way the app opens it. File-backed on
    /// purpose: an in-memory container can round-trip a value through a live
    /// object graph without it ever reaching a column.
    private func openStore() throws -> ModelContainer {
        let configuration = ModelConfiguration(schema: PersistenceController.schema, url: storeURL)
        let container = try ModelContainer(
            for: PersistenceController.schema,
            migrationPlan: SpeakItMigrationPlan.self,
            configurations: [configuration]
        )
        openContainers.append(container)
        return container
    }

    private func makeRepository(_ container: ModelContainer) -> SwiftDataThoughtRepository {
        SwiftDataThoughtRepository(
            modelContext: container.mainContext,
            placeReminderDelivery: { _, _, _, _ in .scheduled },
            placeReminderCancellation: { _ in },
            requestsReminderAuthorization: false
        )
    }

    /// Writes one item carrying `state`, closes the store, and reads it back
    /// through a container built from scratch.
    private func roundTrip(_ state: SemanticState?) throws -> CapturedItem {
        let id = UUID()
        do {
            let context = try openStore().mainContext
            let session = CaptureSession(originalTranscription: "Round trip")
            let item = CapturedItem(
                id: id,
                originalTextSegment: "Round trip",
                displayTitle: "Round trip",
                semanticState: state,
                captureSession: session
            )
            context.insert(item)
            context.insert(session)
            try context.save()
        }

        let reopened = try openStore()
        let items = try reopened.mainContext.fetch(FetchDescriptor<CapturedItem>())
        return try XCTUnwrap(items.first { $0.id == id })
    }

    // MARK: - Every state survives storage

    func testResolvedSurvivesAClosedAndReopenedStore() throws {
        let item = try roundTrip(.resolved)

        XCTAssertEqual(item.semanticState, .resolved)
        XCTAssertTrue(item.hasRecordedSemanticState)
        XCTAssertEqual(item.semanticStateRawValue, "resolved")
        XCTAssertNil(item.semanticGapRawValue, "A resolved reading has no gap to store")
    }

    func testUnderspecifiedSurvivesWithItsExactGap() throws {
        let item = try roundTrip(.underspecified(.ambiguousTemporalScope))

        XCTAssertEqual(item.semanticState, .underspecified(.ambiguousTemporalScope))
        XCTAssertEqual(item.semanticState?.gap, .ambiguousTemporalScope)
        XCTAssertEqual(item.semanticStateRawValue, "underspecified")
        XCTAssertEqual(item.semanticGapRawValue, "ambiguousTemporalScope")
        XCTAssertFalse(item.semanticState?.permitsAction ?? true)
    }

    func testContestedSurvivesWithItsExactGap() throws {
        let item = try roundTrip(.contested(.ambiguousActor))

        XCTAssertEqual(item.semanticState, .contested(.ambiguousActor))
        XCTAssertEqual(item.semanticStateRawValue, "contested")
        XCTAssertEqual(item.semanticGapRawValue, "ambiguousActor")
    }

    func testUnsupportedSurvivesWithItsExactGap() throws {
        let item = try roundTrip(.unsupported(.unsupportedCondition))

        XCTAssertEqual(item.semanticState, .unsupported(.unsupportedCondition))
        XCTAssertEqual(item.semanticStateRawValue, "unsupported")
        XCTAssertEqual(item.semanticGapRawValue, "unsupportedCondition")
    }

    /// Every combination the type can express, not a sample of them. A gap that
    /// is added later and forgotten here fails immediately.
    func testEveryStateAndGapCombinationRoundTripsExactly() throws {
        let container = try openStore()
        let context = container.mainContext
        let session = CaptureSession(originalTranscription: "All combinations")
        context.insert(session)

        var expected: [UUID: SemanticState] = [:]
        var states: [SemanticState] = [.resolved]
        for gap in SemanticGap.allCases {
            states.append(.underspecified(gap))
            states.append(.contested(gap))
            states.append(.unsupported(gap))
        }
        XCTAssertEqual(states.count, 1 + SemanticGap.allCases.count * 3)

        for state in states {
            let item = CapturedItem(
                originalTextSegment: "All combinations",
                displayTitle: "All combinations",
                semanticState: state,
                captureSession: session
            )
            expected[item.id] = state
            context.insert(item)
        }
        try context.save()

        let reopened = try openStore()
        let items = try reopened.mainContext.fetch(FetchDescriptor<CapturedItem>())
        XCTAssertEqual(items.count, expected.count)
        for item in items {
            XCTAssertEqual(
                item.semanticState,
                expected[item.id],
                "\(String(describing: expected[item.id])) did not survive storage"
            )
        }
    }

    /// The architecture carries exactly one reason per reading, so there is no
    /// ordering to be deterministic about and no collection to store. Written
    /// down rather than assumed: if `SemanticState` ever grows more than one
    /// gap, this is where the persisted form has to be reconsidered.
    func testAStateCarriesExactlyOneGap() {
        XCTAssertNil(SemanticState.resolved.gap)
        for gap in SemanticGap.allCases {
            XCTAssertEqual(SemanticState.underspecified(gap).gap, gap)
            XCTAssertEqual(SemanticState.contested(gap).gap, gap)
            XCTAssertEqual(SemanticState.unsupported(gap).gap, gap)
        }
    }

    // MARK: - Values this build cannot read

    /// A newer build writing a state name this one does not know must not be
    /// read as "understood". Every unreadable value falls back to the
    /// pre-version-4 behaviour, which is the conservative direction.
    func testAnUnknownStateNameReadsAsNoVerdictRatherThanResolved() throws {
        let container = try openStore()
        let context = container.mainContext
        let item = CapturedItem(originalTextSegment: "Future", displayTitle: "Future")
        item.semanticStateRawValue = "provisional"
        context.insert(item)
        try context.save()

        XCTAssertNil(item.semanticState)
        XCTAssertTrue(
            item.hasRecordedSemanticState,
            "Something recorded a verdict here; this build simply cannot read it"
        )
    }

    func testAnUnknownGapNameDoesNotBecomeAGaplessState() throws {
        let item = CapturedItem(originalTextSegment: "Future", displayTitle: "Future")
        item.semanticStateRawValue = "underspecified"
        item.semanticGapRawValue = "someReasonFromLater"

        XCTAssertNil(
            item.semanticState,
            "Dropping an unreadable gap would report 'nothing is missing' about a row that says otherwise"
        )
    }

    func testAKindThatNeedsAReasonAndHasNoneIsNotRepairedIntoResolved() {
        XCTAssertNil(SemanticState(kind: .underspecified, gap: nil))
        XCTAssertNil(SemanticState(kind: .contested, gap: nil))
        XCTAssertNil(SemanticState(kind: .unsupported, gap: nil))
        XCTAssertNil(SemanticState(kind: .resolved, gap: .missingAction))
        XCTAssertEqual(SemanticState(kind: .resolved, gap: nil), .resolved)
    }

    /// The raw strings are storage. Renaming one silently reinterprets every
    /// row already written with the old name.
    func testStoredNamesAreTheOnesAlreadyOnDisk() {
        XCTAssertEqual(
            SemanticState.Kind.allCases.map(\.rawValue).sorted(),
            ["contested", "resolved", "underspecified", "unsupported"]
        )
        XCTAssertEqual(
            SemanticGap.allCases.map(\.rawValue).sorted(),
            [
                "ambiguousActor",
                "ambiguousPerson",
                "ambiguousTemporalScope",
                "missingAction",
                "reportedSpeech",
                "uncertainClauseBoundary",
                "unsupportedCondition"
            ]
        )
    }

    // MARK: - The interpreter's verdict actually reaches the row

    /// End to end, through the real capture path and a real store: a sentence
    /// that names a day and never settles on it is recorded as exactly that.
    func testAnUnsettledTimeCaptureRecordsItsGapAndSurvivesARelaunch() throws {
        let container = try openStore()
        let repository = makeRepository(container)
        let item = try repository.createCapture(
            text: "Let me know if the meeting is Tuesday or Wednesday",
            source: .inAppText,
            createdAt: .now,
            schedulesReminder: false
        )
        let id = item.id

        XCTAssertEqual(item.semanticState, .underspecified(.ambiguousTemporalScope))

        let reopened = try openStore()
        let items = try reopened.mainContext.fetch(FetchDescriptor<CapturedItem>())
        let reloaded = try XCTUnwrap(items.first { $0.id == id })

        XCTAssertEqual(
            reloaded.semanticState,
            .underspecified(.ambiguousTemporalScope),
            "The verdict must survive the process, not just the object"
        )
        XCTAssertNil(reloaded.reminderDate, "An unsettled time still schedules nothing")
        XCTAssertNil(reloaded.dueDate)
    }

    func testAnOrdinaryCaptureRecordsThatItWasResolved() throws {
        let container = try openStore()
        let repository = makeRepository(container)
        let item = try repository.createCapture(
            text: "Buy milk on the way home tomorrow",
            source: .inAppText,
            createdAt: .now,
            schedulesReminder: false
        )

        XCTAssertEqual(item.semanticState, .resolved)
        XCTAssertTrue(item.hasRecordedSemanticState)
    }

    /// A capture created by this build is never mistaken for a legacy row.
    func testEveryInterpretedRowCarriesAVerdict() throws {
        let container = try openStore()
        let repository = makeRepository(container)
        try repository.createCapture(
            text: "Call the clinic on Thursday and pick up Ana from the airport",
            source: .inAppText,
            createdAt: .now,
            schedulesReminder: false
        )

        let items = try container.mainContext.fetch(FetchDescriptor<CapturedItem>())
        XCTAssertGreaterThan(items.count, 1)
        for item in items {
            XCTAssertTrue(
                item.hasRecordedSemanticState,
                "\(item.displayTitle) looks like a pre-version-4 row"
            )
        }
    }

    // MARK: - Needs review reads the verdict instead of guessing

    /// The product change this whole pass exists for.
    ///
    /// The sentence names two days and settles on neither. Before version 4 the
    /// only trace of that left on the row was `itemType == .unclear`, so the
    /// review list asked "Task or note?" — a question about something the person
    /// never left unclear.
    func testReviewNamesTheRecordedGapRatherThanTheOldGuess() throws {
        let container = try openStore()
        let repository = makeRepository(container)
        let item = try repository.createCapture(
            text: "Let me know if the meeting is Tuesday or Wednesday",
            source: .inAppText,
            createdAt: .now,
            schedulesReminder: false
        )

        XCTAssertTrue(item.needsClarification)
        XCTAssertEqual(item.clarificationRequirement, .ambiguousTemporalScope)
        XCTAssertNotEqual(
            item.clarificationRequirement,
            .type,
            "The person did not leave the type unclear; they left the day unsettled"
        )
        XCTAssertEqual(item.clarificationRequirement?.listLabel, "Time not settled")
        XCTAssertEqual(item.clarificationRequirement?.editorPrompt, "Pick the day you meant")
        XCTAssertEqual(
            item.clarificationRequirement?.editorField,
            .time,
            "Setting a reminder is what closes it, so that is the field to mark"
        )
    }

    /// Every gap has to reach the person as a reason, and two of them
    /// deliberately reuse a label that already said the right thing.
    func testEveryGapMapsOntoAReviewReasonAPersonCanRead() {
        for gap in SemanticGap.allCases {
            let requirement = ClarificationRequirement(gap)
            XCTAssertFalse(requirement.listLabel.isEmpty)
            XCTAssertFalse(requirement.editorPrompt.isEmpty)
        }
        XCTAssertEqual(ClarificationRequirement(.unsupportedCondition), .unsupportedConditionTrigger)
        XCTAssertEqual(ClarificationRequirement(.uncertainClauseBoundary), .splitDecision)
        XCTAssertEqual(ClarificationRequirement(.ambiguousPerson), .ambiguousPerson)
        XCTAssertEqual(ClarificationRequirement(.ambiguousPerson).editorField, .person)
    }

    /// A recorded gap outranks the reconstruction, but not the facts above it:
    /// a held destructive request and a place trigger are states of the device
    /// and the item, not readings of the sentence, and both still win.
    func testDeviceAndTriggerReasonsStillOutrankTheRecordedGap() throws {
        let item = CapturedItem(
            originalTextSegment: "Remind me to grab milk when I get home",
            displayTitle: "Grab milk",
            itemType: .task,
            needsClarification: true,
            locationIntent: LocationIntent(event: .arrive, place: .home),
            semanticState: .underspecified(.ambiguousTemporalScope)
        )

        XCTAssertEqual(
            item.clarificationRequirement,
            .locationTrigger,
            "What the device is waiting for is not answered by what the sentence left open"
        )
    }

    /// A row with no recorded verdict keeps exactly the reason it had before
    /// version 4 existed.
    func testALegacyRowKeepsThePreVersionFourDerivation() {
        let unclear = CapturedItem(
            originalTextSegment: "Something about the thing",
            displayTitle: "Something about the thing",
            itemType: .unclear,
            needsClarification: true
        )
        XCTAssertFalse(unclear.hasRecordedSemanticState)
        XCTAssertEqual(unclear.clarificationRequirement, .type)

        let followUp = CapturedItem(
            originalTextSegment: "Call them tomorrow",
            displayTitle: "Call them",
            itemType: .personFollowUp,
            needsClarification: true
        )
        XCTAssertEqual(followUp.clarificationRequirement, .person)
    }

    /// A row nothing is known about must not be treated as understood.
    func testALegacyRowIsNeverReportedAsResolved() {
        let legacy = CapturedItem(originalTextSegment: "Old row", displayTitle: "Old row")
        XCTAssertNil(legacy.semanticState)
        XCTAssertFalse(legacy.hasRecordedSemanticState)
        XCTAssertNotEqual(legacy.semanticState, .resolved)
    }

    // MARK: - Nothing else moved

    /// Re-organizing an existing capture rewrites the verdict along with
    /// everything else it rewrites, rather than leaving a stale one behind.
    func testReorganizingACaptureRewritesTheRecordedVerdict() throws {
        let container = try openStore()
        let repository = makeRepository(container)
        let item = try repository.createCapture(
            text: "Buy milk tomorrow",
            source: .inAppText,
            createdAt: .now,
            schedulesReminder: false
        )
        XCTAssertEqual(item.semanticState, .resolved)

        item.semanticState = .contested(.reportedSpeech)
        try container.mainContext.save()

        let session = try XCTUnwrap(item.captureSession)
        try repository.reorganize(session)

        XCTAssertEqual(
            item.semanticState,
            .resolved,
            "A fresh reading must replace the stored verdict, not sit beside it"
        )
    }

    func testTheStoredVerdictDoesNotChangeDestinationOrScheduling() throws {
        let container = try openStore()
        let repository = makeRepository(container)
        let before = try repository.createCapture(
            text: "Remind me to call the clinic tomorrow at nine",
            source: .inAppText,
            createdAt: .now,
            schedulesReminder: false
        )

        let type = before.itemType
        let reminder = before.reminderDate
        let due = before.dueDate
        XCTAssertTrue(before.belongsInToday)
        XCTAssertNotNil(reminder, "This phrasing is meant to produce an alarm")
        XCTAssertEqual(before.semanticState, .resolved)

        // Overwriting the verdict by hand must not move the row: the state is a
        // record of a decision, not an input to destination or scheduling.
        before.semanticState = .unsupported(.unsupportedCondition)
        XCTAssertTrue(before.belongsInToday)
        XCTAssertEqual(before.reminderDate, reminder)
        XCTAssertEqual(before.dueDate, due)
        XCTAssertEqual(before.itemType, type)
    }
}
