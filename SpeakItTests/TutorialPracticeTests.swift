import SwiftData
import XCTest
@testable import SpeakIt

/// Whether a practice capture can carry the tutorial step it belongs to.
///
/// Every step after a practice capture points at a real row on a real screen —
/// "here it is on Today", "here is Maya in People", "your idea is in Memory".
/// The tutorial used to anchor to whatever the capture happened to produce
/// (`?? result.items.first`), so an off-script sentence sent it to a screen the
/// row was not on. No teaching card rendered there, the only control left was
/// Exit, and the walkthrough ended at step 2 of 8 without saying anything.
///
/// `TutorialCaptureMission.satisfiedItem(in:)` is the one definition of "the
/// practice worked". `RootView` uses it to decide whether to advance and
/// `CaptureView` uses it to decide whether to offer another try, so the two
/// cannot drift apart. These tests run real sentences through the real
/// repository, because the failure this guards against was never in the
/// matching rule — it was in what the pipeline actually returns for the things
/// people say on their first run.
@MainActor
final class TutorialPracticeTests: XCTestCase {
    private var container: ModelContainer!
    private var repository: SwiftDataThoughtRepository!

    override func setUpWithError() throws {
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
        repository = nil
        container = nil
    }

    private func practiceResult(_ text: String) async throws -> CaptureCreationResult {
        try await repository.createCaptureResult(
            text: text,
            source: .tutorial,
            createdAt: .now,
            schedulesReminders: false
        )
    }

    // MARK: - The sentences the steps are built around

    func testTheActionExampleSatisfiesTheActionStep() async throws {
        let result = try await practiceResult(TutorialCaptureMission.action.example)
        let anchor = TutorialCaptureMission.action.satisfiedItem(in: result)

        XCTAssertNotNil(anchor, "the step's own example must always pass its own check")
        XCTAssertEqual(anchor?.itemType, .personFollowUp)
        XCTAssertEqual(
            MemoryPersonNameResolver.name(for: try XCTUnwrap(anchor)),
            "Maya",
            "steps 3 and 4 walk to this person's page, so the name has to be real"
        )
    }

    func testTheIdeaExampleSatisfiesTheIdeaStep() async throws {
        let result = try await practiceResult(TutorialCaptureMission.idea.example)
        let anchor = TutorialCaptureMission.idea.satisfiedItem(in: result)

        XCTAssertNotNil(anchor, "the step's own example must always pass its own check")
        XCTAssertEqual(anchor?.itemType, .idea, "step 6 opens the idea stage picker")
    }

    /// The practice screen says "Say it naturally, or use your own words", so
    /// the check has to be loose enough to honour that invitation. A person who
    /// drops the time, or leads with "remind me to", is still doing the lesson.
    func testTheActionStepAcceptsThePersonsOwnWording() async throws {
        for text in [
            "ask Maya about the proposal",
            "remind me to ask Maya about the proposal",
            "Tomorrow at 9 ask Maya about the proposal",
            "Call Dana about the refund tomorrow"
        ] {
            let result = try await practiceResult(text)
            XCTAssertNotNil(
                TutorialCaptureMission.action.satisfiedItem(in: result),
                "“\(text)” is a task connected to a person and must pass"
            )
        }
    }

    // MARK: - The sentences that used to derail the walkthrough

    /// These all saved fine and all routed somewhere real. What none of them
    /// could do is carry a step that walks to a person, which is why the
    /// tutorial has to notice rather than march on.
    func testOffScriptSentencesDoNotSatisfyTheActionStep() async throws {
        for text in [
            "hello testing one two three",
            "this is a test",
            "testing",
            "buy milk"
        ] {
            let result = try await practiceResult(text)
            XCTAssertNil(
                TutorialCaptureMission.action.satisfiedItem(in: result),
                "“\(text)” has no person to walk to, so the step must ask again"
            )
        }
    }

    func testATaskDoesNotSatisfyTheIdeaStep() async throws {
        let result = try await practiceResult("Tomorrow at 9, ask Maya about the proposal.")
        XCTAssertNil(
            TutorialCaptureMission.idea.satisfiedItem(in: result),
            "step 6 opens the stage picker, which only exists on an idea"
        )
    }

    /// "Cancel that" and "never mind" ask the app to act on something that
    /// already exists rather than to store a thought. Whether that leaves a
    /// review row or nothing at all depends on what is in the store, so this
    /// asserts the part that is true either way: neither leaves the kind of row
    /// the walkthrough walks to. The tutorial used to read such a result as a
    /// completed step and jump the person from step 1 to the final screen.
    func testAnOperationCannotCarryAPracticeStep() async throws {
        for text in ["cancel that", "never mind"] {
            let result = try await practiceResult(text)
            XCTAssertNil(
                TutorialCaptureMission.action.satisfiedItem(in: result),
                "“\(text)” left no task-with-a-person for steps 2 to 4 to point at"
            )
            XCTAssertNil(
                TutorialCaptureMission.idea.satisfiedItem(in: result),
                "“\(text)” left no idea for the stage picker in step 6"
            )
        }
    }

    // MARK: - Capture Anywhere

    /// Nothing downstream points at this row, so any stored capture proves the
    /// outside-the-app trigger worked. It stays deliberately permissive — the
    /// person is testing a button, not practising a sentence.
    func testTheQuickAccessStepAcceptsAnyStoredCapture() async throws {
        for text in [
            TutorialCaptureMission.quickAccess.example,
            "hello testing one two three",
            "buy milk"
        ] {
            let result = try await practiceResult(text)
            XCTAssertNotNil(
                TutorialCaptureMission.quickAccess.satisfiedItem(in: result),
                "“\(text)” reached the app from outside it, which is the whole lesson"
            )
        }
    }

    // MARK: - Practice stays free

    /// A retry must never cost anything. The allowance is a monotonic
    /// Keychain-backed ledger, so a practice capture that charged and then
    /// "refunded" would be neither reliable nor honest.
    func testPracticeCapturesNeverSpendAFreeCapture() async throws {
        for text in [
            TutorialCaptureMission.action.example,
            "hello testing one two three",
            "buy milk"
        ] {
            let result = try await practiceResult(text)
            XCTAssertFalse(
                result.consumesFreeCapture,
                "“\(text)” was practice and must not spend one of the ten"
            )
        }
    }
}
