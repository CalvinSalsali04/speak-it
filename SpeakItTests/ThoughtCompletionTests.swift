import SwiftData
import XCTest
@testable import SpeakIt

/// Whether the sentence finished, and whether saying so costs anything.
///
/// The detector's value is entirely in the gap between two numbers: how many
/// unfinished thoughts it catches, and how many finished ones it interrupts.
/// The second number is the one that decides whether it ships, so most of this
/// file is finished sentences that look like fragments.
///
/// The development set behind it lives in
/// `Tools/CorpusRunner/devsets/unfinished.tsv` and is scored by
/// `unfinished-score.sh`. What is asserted here is the part that must never
/// regress silently.
final class ThoughtCompletionTests: XCTestCase {

    // MARK: - The minimal pairs
    //
    // One word apart. If the detector cannot separate these it is reading
    // length, not structure.

    func testAnInfinitiveWithoutItsVerbIsUnfinished() {
        for text in [
            "Tomorrow I want to",
            "I need to",
            "I was going to",
            "I have to",
            "I meant to",
            "Remind me to",
            "Don't forget to",
            "Tomorrow remind me to",
            "Set a reminder to",
            "Remind me at five to",
            "Next week I was going to"
        ] {
            XCTAssertEqual(
                ThoughtCompletion.unfinished(in: text),
                .danglingInfinitive,
                "\(text) announced a verb that never came"
            )
        }
    }

    func testTheSameSentenceWithItsVerbIsFinished() {
        for text in [
            "Tomorrow I want to run",
            "I need to call Sarah",
            "I was going to call Mike",
            "I have to renew my passport",
            "I meant to email her",
            "Remind me to buy milk",
            "Don't forget to send the invoice",
            "Tomorrow remind me to call the clinic",
            "Set a reminder to water the plants",
            "Next week I was going to visit Ana"
        ] {
            XCTAssertNil(
                ThoughtCompletion.unfinished(in: text),
                "\(text) is a finished thought and must not be interrupted"
            )
        }
    }

    // MARK: - Mutation protection
    //
    // A detector that answers the same thing every time is worthless in one
    // direction and harmful in the other. These two tests fail for
    // `return .danglingInfinitive` and for `return nil` respectively, so
    // neither degenerate implementation can pass the suite.

    func testTheDetectorIsNotAlwaysTrue() {
        let finished = [
            "Buy milk", "Call my mother", "I need milk", "Tomorrow I want pizza",
            "Tomorrow is busy", "I forgot my keys", "Remind me tomorrow",
            "Maybe tomorrow", "Milk", "That is all", "Sarah wants to leave",
            "I want to go", "I need to follow up", "Don't forget to check in"
        ]
        let flagged = finished.filter { ThoughtCompletion.unfinished(in: $0) != nil }
        XCTAssertTrue(
            flagged.isEmpty,
            "A detector that flags finished thoughts is worse than none: \(flagged)"
        )
    }

    func testTheDetectorIsNotAlwaysFalse() {
        let fragments = ["Tomorrow I want to", "Remind me to", "I need to", "I was going to"]
        let missed = fragments.filter { ThoughtCompletion.unfinished(in: $0) == nil }
        XCTAssertTrue(missed.isEmpty, "The detector caught nothing at all: \(missed)")
    }

    // MARK: - The false positives that cost real captures
    //
    // Each of these was flagged by a wider version of the rule and each one is
    // a finished thought. They are the reason the preposition, conjunction and
    // adverb classes are not in the detector.

    func testWordClassesThatAlsoEndFinishedSentencesAreNotTreatedAsDangling() {
        for text in [
            "I haven't submitted the report yet",              // yet/Conjunction
            "Call Catherine tomorrow at five and remind me an hour before", // before/Preposition
            "Buy dog food, we're almost out",                  // out/Preposition
            "Remind me tomorrow",                              // tomorrow/Adverb
            "Maybe tomorrow",
            "I keep meaning to write that down",               // down/Adverb
            "That is all",                                     // all/Determiner after a copula
            "I need to follow up",                             // particle verb
            "Don't forget to check in",
            "I should probably head out",
            "Tomorrow I want to sleep in"
        ] {
            XCTAssertNil(
                ThoughtCompletion.unfinished(in: text),
                "\(text) is finished; flagging it interrupts somebody who said what they meant"
            )
        }
    }

    /// Somebody else's trailing sentence is not the user's to finish.
    func testAReportedUnfinishedSentenceIsNotTheUsersToFinish() {
        XCTAssertNil(ThoughtCompletion.unfinished(in: "She said she needs to"))
        XCTAssertNil(ThoughtCompletion.unfinished(in: "Sarah said never mind"))
        XCTAssertNil(ThoughtCompletion.unfinished(in: "Mike told me he forgot"))
    }

    /// A one-word capture is a capture, not a fragment.
    ///
    /// A bare imperative — "Add", "Buy" — is deliberately *not* detected. The
    /// rule existed briefly and was removed: `NLTagger` reads a one-word "Add"
    /// as a verb on macOS and not on iOS, so the development tools and the
    /// shipping app disagreed about the same four characters.
    func testALoneWordIsNotTreatedAsAFragment() {
        XCTAssertNil(ThoughtCompletion.unfinished(in: "Milk"), "a lone noun is a capture")
        XCTAssertNil(ThoughtCompletion.unfinished(in: "LCBO"))
        XCTAssertNil(ThoughtCompletion.unfinished(in: "Add"), "known limitation, asserted so it stays known")
    }

    func testADanglingDeterminerIsUnfinished() {
        XCTAssertEqual(
            ThoughtCompletion.unfinished(in: "I need to talk to Sarah about the"),
            .trailingFunctionWord
        )
    }

    /// The rule reads structure, so it must not depend on how the recognizer
    /// punctuated or cased the sentence.
    func testTheReadingSurvivesHowTheRecognizerWroteItDown() {
        for text in ["Tomorrow I want to", "tomorrow i want to", "Tomorrow I want to.", "TOMORROW I WANT TO"] {
            XCTAssertEqual(
                ThoughtCompletion.unfinished(in: text),
                .danglingInfinitive,
                "rendering changed the reading: \(text)"
            )
        }
        for text in ["Tomorrow I want to run", "tomorrow i want to run", "Tomorrow I want to run."] {
            XCTAssertNil(ThoughtCompletion.unfinished(in: text), "rendering changed the reading: \(text)")
        }
    }

    func testEveryReasonReportsTheSameGap() {
        for reason in ThoughtCompletion.Unfinished.allCases {
            XCTAssertEqual(reason.gap, .incompleteThought)
        }
    }
}

/// What an unfinished thought becomes once it reaches a row.
@MainActor
final class IncompleteThoughtCaptureTests: XCTestCase {
    private var container: ModelContainer!
    private var repository: SwiftDataThoughtRepository!
    private var previousRecurrences: [RecurrenceRecordSnapshot] = []

    override func setUpWithError() throws {
        previousRecurrences = RecurrenceStore.snapshots()
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
        RecurrenceStore.restore(previousRecurrences)
        repository = nil
        container = nil
    }

    /// The safety contract. A fragment must not acquire a commitment.
    func testAnUnfinishedThoughtInventsNothing() throws {
        for text in ["Tomorrow I want to", "Tomorrow remind me to", "Remind me at five to"] {
            let item = try repository.createCapture(
                text: text,
                source: .inAppText,
                createdAt: .now,
                schedulesReminder: false
            )
            XCTAssertNil(item.dueDate, "\(text) was given a date it never named")
            XCTAssertNil(item.reminderDate, "\(text) was given a reminder with nothing in it")
            XCTAssertNil(item.locationIntent)
            XCTAssertEqual(item.temporalKind ?? .none, TemporalKind.none)
            XCTAssertFalse(item.itemType.isActionable, "\(text) became an action")
            XCTAssertTrue(item.needsClarification)
            XCTAssertEqual(item.semanticState, .underspecified(.incompleteThought))
        }
    }

    /// The words themselves are never the thing that gets dropped.
    func testTheOriginalWordsSurviveAnUnfinishedCapture() throws {
        let item = try repository.createCapture(
            text: "Tomorrow I want to",
            source: .inAppText,
            createdAt: .now,
            schedulesReminder: false
        )
        XCTAssertEqual(item.captureSession?.originalTranscription, "Tomorrow I want to")
        XCTAssertFalse(item.originalTextSegment.isEmpty)
    }

    func testReviewNamesTheUnfinishedThoughtRatherThanGuessing() throws {
        let item = try repository.createCapture(
            text: "Tomorrow I want to",
            source: .inAppText,
            createdAt: .now,
            schedulesReminder: false
        )
        XCTAssertEqual(item.clarificationRequirement, .incompleteThought)
        XCTAssertEqual(item.clarificationRequirement?.listLabel, "Unfinished thought")
        XCTAssertNotEqual(item.clarificationRequirement, .type)
    }

    /// A finished thought captured beside an unfinished one keeps its meaning.
    func testAFinishedThoughtSurvivesBesideAnUnfinishedOne() throws {
        try repository.createCapture(
            text: "Buy milk and tomorrow I want to",
            source: .inAppText,
            createdAt: .now,
            schedulesReminder: false
        )
        let items = try container.mainContext.fetch(FetchDescriptor<CapturedItem>())
        XCTAssertGreaterThanOrEqual(items.count, 2, "the finished half was thrown away")
        XCTAssertTrue(
            items.contains { $0.itemType == .shopping || $0.displayTitle.localizedCaseInsensitiveContains("milk") },
            "Buy milk stopped being a thought because the sentence after it stopped"
        )
    }

    /// The new gap rides the version 4 columns. No schema change, and it has to
    /// survive the store being closed and reopened.
    func testTheUnfinishedVerdictSurvivesAStoreRoundTrip() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpeakItUnfinished-\(UUID().uuidString)")
            .appendingPathExtension("store")
        defer {
            for suffix in ["", "-shm", "-wal"] {
                try? FileManager.default.removeItem(at: URL(fileURLWithPath: url.path + suffix))
            }
        }
        func open() throws -> ModelContainer {
            try ModelContainer(
                for: PersistenceController.schema,
                migrationPlan: SpeakItMigrationPlan.self,
                configurations: [ModelConfiguration(schema: PersistenceController.schema, url: url)]
            )
        }

        let first = try open()
        let writer = SwiftDataThoughtRepository(
            modelContext: first.mainContext,
            requestsReminderAuthorization: false
        )
        let id = try writer.createCapture(
            text: "Tomorrow I want to",
            source: .inAppText,
            createdAt: .now,
            schedulesReminder: false
        ).id

        let reopened = try open()
        let items = try reopened.mainContext.fetch(FetchDescriptor<CapturedItem>())
        let reloaded = try XCTUnwrap(items.first { $0.id == id })

        XCTAssertEqual(reloaded.semanticState, .underspecified(.incompleteThought))
        XCTAssertEqual(reloaded.semanticGapRawValue, "incompleteThought")
        XCTAssertEqual(reloaded.clarificationRequirement, .incompleteThought)
        XCTAssertNil(reloaded.dueDate)
        XCTAssertNil(reloaded.reminderDate)
    }
}
