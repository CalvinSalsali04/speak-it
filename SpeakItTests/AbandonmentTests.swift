import SwiftData
import XCTest
@testable import SpeakIt

/// Whether "never mind" was the person taking their own thought back.
///
/// The development set behind this lives in
/// `Tools/CorpusRunner/devsets/abandonment.tsv` and is scored by
/// `abandonment-score.sh`. What is asserted here is the part that must never
/// regress silently — and, as with the unfinished-thought detector, most of it
/// is sentences that contain the words and are not a withdrawal at all. A rule
/// that withdraws everything scores worse here than one that withdraws nothing,
/// because the cost is not symmetric: a missed withdrawal leaves a row somebody
/// can delete, and a wrong one deletes a thought they meant to keep.
final class AbandonmentTests: XCTestCase {

    private func partition(_ text: String) -> (operations: [CaptureOperationRequest], remainder: String?) {
        CaptureOperationDetector.partition(text)
    }

    private func withdraws(_ text: String) -> Bool {
        partition(text).operations.contains { $0.operation == .retract && $0.target == nil }
    }

    // MARK: - The boundary is structural, not typographical

    /// The release blocker, and the reason it existed.
    ///
    /// All three are one sentence spoken one way. Only the transcriber chose
    /// between the spellings, and before this the comma was the only one that
    /// worked — so the rendering people actually produce when they trail off,
    /// which is the one with no comma in it, became a task dated tomorrow.
    func testTheSameWithdrawalIsReadThroughEveryRendering() {
        for text in [
            "Tomorrow I need to, never mind",
            "Tomorrow I need to... never mind",
            "Tomorrow I need to… never mind",
            "Tomorrow I need to never mind",
            "tomorrow i need to never mind",
            "Tomorrow I need to, um, never mind",
            "Tomorrow I need to, um, wait, never mind"
        ] {
            XCTAssertTrue(withdraws(text), "not read as a withdrawal: \(text)")
        }
    }

    func testAnEllipsisIsThePauseTheRecognizerWroteDown() {
        XCTAssertEqual(
            withdraws("Remind me to, never mind"),
            withdraws("Remind me to... never mind"),
            "a comma and an ellipsis are the same pause and must read the same"
        )
    }

    // MARK: - What separates a withdrawal from an ordinary sentence
    //
    // This is the whole risk of the rule. "Tomorrow I need to never mind" and
    // "I need to forget it" are the same shape — an infinitive that stopped at
    // "to", then two more words — and one of them is an ordinary English
    // sentence. Reading the head as unfinished cannot tell them apart, because
    // the head only looks unfinished once the last two words are taken off it.

    /// A withdrawal that carries its own object can be what the sentence was
    /// reaching for, so it is not evidence that the sentence stopped.
    func testAWellFormedVerbPhraseFinishesTheInfinitiveInsteadOfWithdrawingIt() {
        for text in [
            "I need to forget it",
            "Tomorrow I need to forget it",
            "I have to forget it",
            "Remind me to forget it",
            "I need to scratch that",
            "I want to scratch that",
            "Remind me to scratch that off the list",
            "I need to forget about it",
            "Next week I should forget it"
        ] {
            XCTAssertFalse(withdraws(text), "an ordinary sentence was withdrawn: \(text)")
            XCTAssertNotNil(partition(text).remainder, "\(text) left nothing to create")
        }
    }

    /// "Mind" is transitive in this frame and its object never came, so it
    /// cannot be the thing the infinitive was reaching for.
    func testAWithdrawalWithNoObjectCannotFinishTheInfinitive() {
        XCTAssertTrue(withdraws("Tomorrow I need to never mind"))
        XCTAssertTrue(withdraws("Remind me to never mind"))
        XCTAssertTrue(withdraws("I was going to never mind"))
    }

    /// The one-word difference. If the rule cannot separate these it is reading
    /// the shape of the head rather than what the withdrawal is.
    func testTheMinimalPair() {
        XCTAssertTrue(withdraws("I need to never mind"))
        XCTAssertFalse(withdraws("I need to forget it"))
    }

    func testARepairMarkerAnnouncesAWithdrawalWithoutAPause() {
        XCTAssertTrue(withdraws("I was going to actually never mind"))
        XCTAssertTrue(withdraws("I need to call Sarah, actually never mind"))
    }

    // MARK: - Whose sentence it is

    /// Before this guard existed, the only thing keeping reported speech safe
    /// was that nobody had said it with a comma. "Sarah said, never mind" split
    /// into two pieces and withdrew the capture; "Sarah said never mind" did
    /// not. The protection was an accident of punctuation, and once a boundary
    /// could be found without a comma it had to become a rule.
    func testSomebodyElsesWithdrawalIsNotTheUsersToMake() {
        for text in [
            "Sarah said never mind",
            "Sarah said, never mind",
            "Sarah said... never mind",
            "sarah said never mind",
            "Mike told me never mind",
            "Mike told me, never mind"
        ] {
            XCTAssertFalse(withdraws(text), "reported speech was read as a withdrawal: \(text)")
        }
    }

    func testMessageContentIsNotAWithdrawalOfTheCapture() {
        for text in [
            "Tell Sarah never mind",
            "Tell Sarah to forget it",
            "Text Sarah that I changed my mind and never mind the old plan"
        ] {
            XCTAssertFalse(withdraws(text), "message content was read as a withdrawal: \(text)")
        }
    }

    func testTheMarkerIsOnlyAWithdrawalWhenItEndsTheThought() {
        for text in ["Buy a Never Mind album", "Never mind is what Sarah always says", "I never mind the cold"] {
            XCTAssertFalse(withdraws(text), "ordinary content was read as a withdrawal: \(text)")
        }
    }

    // MARK: - Scope

    /// A withdrawal takes back the thought it was spoken after, and only that
    /// one. Read as a whole-capture retraction it discarded the milk as well —
    /// a thought the person had finished saying, deleted because of one they
    /// had not.
    func testAWithdrawalTakesBackOneThoughtRatherThanTheCapture() {
        let milk = partition("Buy milk and tomorrow I need to, never mind")
        XCTAssertEqual(milk.remainder, "Buy milk")
        XCTAssertTrue(milk.operations.allSatisfy(\.isScoped))

        let sushi = partition("Sarah hates sushi and remind me to, never mind")
        XCTAssertEqual(sushi.remainder, "Sarah hates sushi")
        XCTAssertTrue(sushi.operations.allSatisfy(\.isScoped))
    }

    /// A withdrawal with nothing in front of it has nothing to scope over, so
    /// it stays what it has always been: the whole capture withdrawn.
    func testAWithdrawalWithNothingBehindItStillTakesTheWholeCapture() {
        let bare = partition("Never mind")
        XCTAssertNil(bare.remainder)
        XCTAssertTrue(bare.operations.contains { $0.operation == .retract })
        XCTAssertFalse(bare.operations.contains(where: \.isScoped))

        XCTAssertFalse(
            partition("Never mind, buy milk").operations.contains(where: \.isScoped),
            "nothing was said before it, so there was nothing for it to scope over"
        )
    }

    func testAWithdrawalThatLeavesNothingIsStillAWholeCaptureRetraction() {
        let alone = partition("Tomorrow I need to, never mind")
        XCTAssertNil(alone.remainder, "the withdrawn fragment must not survive as a row")
        XCTAssertTrue(alone.operations.contains { $0.operation == .retract })
    }
}

/// The same question asked of the app rather than of the rules: what does a
/// person actually end up with.
@MainActor
final class AbandonedCaptureTests: XCTestCase {
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

    private func stored() throws -> [CapturedItem] {
        try container.mainContext.fetch(FetchDescriptor<CapturedItem>())
    }

    private func capture(_ text: String) async throws -> CaptureCreationResult {
        try await repository.createCaptureResult(
            text: text,
            source: .inAppText,
            createdAt: Date(timeIntervalSince1970: 1_786_332_600),
            schedulesReminders: false
        )
    }

    /// The safety contract. An abandoned thought may not leave a commitment
    /// behind it — and it may not leave a Needs review row either, because the
    /// person already said there is nothing there to review.
    func testAnAbandonedThoughtLeavesNothingBehind() async throws {
        for text in [
            "Tomorrow I need to... never mind",
            "Tomorrow I need to never mind",
            "Remind me to never mind",
            "I was going to actually never mind",
            "I need to call Sarah, actually never mind"
        ] {
            let container = try ModelContainer(
                for: PersistenceController.schema,
                migrationPlan: SpeakItMigrationPlan.self,
                configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
            )
            let repo = SwiftDataThoughtRepository(
                modelContext: container.mainContext,
                requestsReminderAuthorization: false
            )
            _ = try await repo.createCaptureResult(
                text: text,
                source: .inAppText,
                createdAt: Date(timeIntervalSince1970: 1_786_332_600),
                schedulesReminders: false
            )
            let items = try container.mainContext.fetch(FetchDescriptor<CapturedItem>())
            XCTAssertTrue(items.isEmpty, "\(text) left \(items.count) row(s): \(items.map(\.displayTitle))")
            for item in items {
                XCTAssertNil(item.dueDate, "\(text) invented a date")
                XCTAssertNil(item.reminderDate, "\(text) invented a reminder")
                XCTAssertNil(item.locationIntent, "\(text) invented a place")
            }
        }
    }

    /// The words themselves are never the thing that gets discarded. A
    /// withdrawal drops the rows; the transcript stays exactly where every
    /// other capture keeps it.
    func testTheOriginalWordsSurviveAWithdrawal() async throws {
        let result = try await capture("Tomorrow I need to... never mind")
        XCTAssertEqual(result.session.originalTranscription, "Tomorrow I need to... never mind")
        XCTAssertTrue(try stored().isEmpty)

        let sessions = try container.mainContext.fetch(FetchDescriptor<CaptureSession>())
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions.first?.originalTranscription, "Tomorrow I need to... never mind")
    }

    /// A withdrawal is about the sentence being spoken, not about anything the
    /// person said yesterday. This is the line between abandoning a thought and
    /// issuing a destructive command.
    func testAWithdrawalNeverTouchesWhatIsAlreadyStored() async throws {
        _ = try await capture("Buy milk")
        _ = try await capture("Call the dentist on Friday")
        let before = try stored().map(\.displayTitle).sorted()
        XCTAssertEqual(before.count, 2)

        _ = try await capture("Tomorrow I need to... never mind")

        let after = try stored().map(\.displayTitle).sorted()
        XCTAssertEqual(after, before, "a withdrawal reached back into the store")
    }

    /// The finished half of a capture survives the unfinished half being taken
    /// back. Before the withdrawal was scoped it went down with it.
    func testAFinishedThoughtSurvivesTheWithdrawalOfTheOneAfterIt() async throws {
        _ = try await capture("Buy milk and tomorrow I need to, never mind")
        let items = try stored()
        XCTAssertEqual(items.count, 1, "expected the milk alone, got \(items.map(\.displayTitle))")
        XCTAssertTrue(
            items[0].displayTitle.localizedCaseInsensitiveContains("milk"),
            "the surviving row was \(items[0].displayTitle)"
        )
        XCTAssertNil(items[0].dueDate)
        XCTAssertNil(items[0].reminderDate)
    }

    func testAFactSurvivesTheWithdrawalOfTheReminderSpokenAfterIt() async throws {
        _ = try await capture("Sarah hates sushi and remind me to, never mind")
        let items = try stored()
        XCTAssertEqual(items.count, 1, "expected the fact alone, got \(items.map(\.displayTitle))")
        XCTAssertTrue(items[0].displayTitle.localizedCaseInsensitiveContains("sushi"))
        XCTAssertNil(items[0].reminderDate, "a withdrawn reminder was scheduled anyway")
    }

    /// A thought finished *after* the withdrawal is not covered by it.
    func testAThoughtSpokenAfterTheWithdrawalIsNotCoveredByIt() async throws {
        _ = try await capture("Tomorrow I need to... never mind, but buy milk")
        let items = try stored()
        XCTAssertEqual(items.count, 1, "got \(items.map(\.displayTitle))")
        XCTAssertTrue(items[0].displayTitle.localizedCaseInsensitiveContains("milk"))
        XCTAssertNil(items[0].dueDate, "the withdrawn half left its date on the surviving row")
    }

    /// Reported speech is kept, as a note, with the words intact.
    func testSomebodyElsesWithdrawalIsKeptAsAMemory() async throws {
        _ = try await capture("Sarah said never mind")
        let items = try stored()
        XCTAssertEqual(items.count, 1)
        XCTAssertFalse(items[0].itemType.isActionable)
        XCTAssertTrue(items[0].displayTitle.localizedCaseInsensitiveContains("never mind"))
    }

    /// A reminder whose content happens to be "forget it" is a reminder.
    func testAnOrdinaryThoughtThatContainsTheWordsIsStillSaved() async throws {
        _ = try await capture("Remind me to forget it")
        let items = try stored()
        XCTAssertEqual(items.count, 1, "an ordinary sentence was withdrawn")
        XCTAssertTrue(items[0].displayTitle.localizedCaseInsensitiveContains("forget"))
    }
}
