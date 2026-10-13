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
/// Exit, and the walkthrough ended at step 2 without saying anything.
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
        XCTAssertEqual(anchor?.itemType, .idea, "step 5 shows the idea in Memory under Ideas")
    }

    /// The practice screen invites the person's own task as long as it names
    /// someone, so the check has to be loose enough to honour that invitation. A person who
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
            "step 5 shows the row in Ideas, which only holds ideas"
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
                "“\(text)” left no idea for Ideas to show in step 5"
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
    func testAResultNeedingGroupingReviewCannotAdvanceJustBecauseItNamesAPerson() async throws {
        let result = try await practiceResult("Call Mia about the budget tomorrow")
        let item = try XCTUnwrap(result.items.first)
        item.needsClarification = true
        item.semanticState = .contested(.uncertainClauseBoundary)
        XCTAssertNil(TutorialCaptureMission.action.satisfiedItem(in: result))
    }
    func testSeveralPracticeMissesAndBothMissionsKeepAllTenCaptures() async throws {
        var charged = 0
        for text in ["hello testing", "buy milk", "testing again", TutorialCaptureMission.action.example,
                     "call Dana", "buy bread", "hello again", TutorialCaptureMission.idea.example] {
            let result = try await practiceResult(text)
            if result.createdNewCapture && result.consumesFreeCapture { charged += 1 }
            XCTAssertEqual(result.session.captureSource, .tutorial)
        }
        XCTAssertEqual(charged, 0)
        XCTAssertEqual(FreePlanAllowance.remainingCaptures(after: charged), 10)
    }
    func testPracticeDraftIdentitySurvivesModeChangesAndLaunchRecovery() throws {
        let previous = CaptureDraftStore.snapshot()
        CaptureDraftStore.restore([])
        defer { CaptureDraftStore.restore(previous) }
        let draft = CaptureDraftStore.begin(source: .tutorial, at: .now.addingTimeInterval(-60))
        CaptureDraftStore.updateSource(id: draft.id, source: .inAppText)
        CaptureDraftStore.updateSource(id: draft.id, source: .inAppVoice)
        CaptureDraftStore.update(id: draft.id, transcript: "Ask Mia about the budget", at: .now.addingTimeInterval(-30))
        XCTAssertEqual(CaptureDraftStore.draft(id: draft.id)?.captureSource, .tutorial)
        repository.recoverUnorganizedCaptures()
        repository.recoverInterruptedCaptureDraft()
        let sessions = try container.mainContext.fetch(FetchDescriptor<CaptureSession>())
        let session = try XCTUnwrap(sessions.first { $0.originalTranscription == "Ask Mia about the budget" })
        XCTAssertEqual(session.captureSource, .tutorial)
        let result = CaptureCreationResult(session: session, items: session.items)
        XCTAssertFalse(result.consumesFreeCapture)
        XCTAssertNil(CaptureDraftStore.draft(id: draft.id))
    }
    func testPracticeCannotScheduleAnAlertDuringLaterReconciliation() async throws {
        let result = try await practiceResult("Tomorrow at 9, call Mia about the budget")
        XCTAssertTrue(result.items.contains { $0.reminderDate != nil || $0.dueDate != nil })
        for item in result.items { XCTAssertNil(ReminderScheduleRequest(item: item)) }
    }
    func testPracticeOperationsCannotChangeRealSavedThoughts() async throws {
        let real = try await repository.createCaptureResult(text: "Call Mia about the budget tomorrow", source: .inAppText, createdAt: .now,
                                                           schedulesReminders: false)
        let id = real.primaryItem.id
        _ = try await practiceResult("Cancel the call Mia task")
        let kept = try XCTUnwrap(container.mainContext.fetch(FetchDescriptor<CapturedItem>()).first { $0.id == id })
        XCTAssertFalse(kept.isCompleted)
        XCTAssertFalse(kept.isArchived)
        let practice = try await practiceResult("hello testing")
        let request = CaptureOperationRequest(operation: .cancel, target: "call Mia", sourceQuote: "cancel the call Mia task", needsReview: false)
        let outcome = try repository.applyCaptureOperation(request, session: practice.session)
        guard case .needsConfirmation(_, let candidates) = outcome else { return XCTFail("Practice operations must be held") }
        XCTAssertTrue(candidates.isEmpty)
        XCTAssertNotNil(try container.mainContext.fetch(FetchDescriptor<CapturedItem>()).first { $0.id == id })
    }

    func testOutsidePracticeRemainsFreeAfterASlowOrInterruptedSetup() async throws {
        let suite = "SpeakIt.Tests.TutorialOutside." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(FirstRunTutorialPhase.readiness.rawValue, forKey: FirstRunTutorialKeys.phase)
        defaults.set(Date.now.addingTimeInterval(-3_600).timeIntervalSince1970, forKey: "SpeakIt.captureSetupTestBeganAt")
        let before = defaults.persistentDomain(forName: suite) ?? [:]
        let result = try await ExternalCaptureWriter.save("Buy milk", repository: repository, defaults: defaults)
        XCTAssertEqual(result.confirmationContext, "Practice test · free captures untouched")
        let saved = try XCTUnwrap(container.mainContext.fetch(FetchDescriptor<CaptureSession>()).first)
        XCTAssertEqual(saved.captureSource, .tutorial)
        XCTAssertFalse(CaptureCreationResult(session: saved, items: saved.items).consumesFreeCapture)
        XCTAssertEqual(NSDictionary(dictionary: defaults.persistentDomain(forName: suite) ?? [:]), NSDictionary(dictionary: before))
        for phase in FirstRunTutorialPhase.allCases where phase != .readiness {
            XCTAssertFalse(phase.hasComplimentaryCaptureAnywhereTest(beganAt: 1))
        }
        XCTAssertFalse(FirstRunTutorialPhase.readiness.hasComplimentaryCaptureAnywhereTest(beganAt: 0))
    }

}
