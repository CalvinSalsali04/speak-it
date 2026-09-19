import SwiftData
import XCTest
@testable import SpeakIt

/// What the capture surfaces tell the person while Speak It works, and after it
/// has finished.
///
/// Both halves here are the same failure in two places: a screen that had the
/// right answer available and described something else. Nothing in the parser,
/// the repository or the store was wrong in either case, which is why no
/// existing suite could have caught them.
@MainActor
final class CaptureFeedbackTests: XCTestCase {

    // MARK: - The voice screen while the capture is being saved

    /// `SpeechTranscriber.completeFinalization` returns the transcriber to
    /// `.idle` *before* it hands the words to `save`, so the whole of the save
    /// ran with the screen reading its state as idle: "Tap to speak", a resting
    /// orb, and a disabled button whose spoken label said "Start voice
    /// capture". This is the exact frame where on-device refinement gets its
    /// two-second budget.
    func testTheVoiceScreenDoesNotInviteANewCaptureWhileSavingTheLastOne() {
        let saving = CaptureVoiceStatus(
            transcriberState: .idle,
            isSaving: true,
            isRecoveringAudio: false,
            isWaitingForContinuation: false,
            isPreparingEnhancedRecognition: false
        )

        XCTAssertEqual(saving, .saving)
        XCTAssertEqual(saving.orbPhase, .processing)
        XCTAssertNotEqual(saving.title, "Tap to speak")
        XCTAssertNotEqual(saving.subtitle, "Say anything you don’t want to forget.")
        XCTAssertNotEqual(saving.buttonAccessibilityLabel, "Start voice capture")
        XCTAssertTrue(saving.isBusy)
    }

    /// The transition the person actually sees. "Saving your thought…" appears
    /// when the recognizer is asked for its last words and must still be there
    /// while the capture is read and stored — one continuous statement, not a
    /// sentence that appears, disappears and comes back.
    func testFinalizingAndSavingReadAsOneContinuousState() {
        let finalizing = CaptureVoiceStatus(
            transcriberState: .finalizing,
            isSaving: false,
            isRecoveringAudio: false,
            isWaitingForContinuation: false,
            isPreparingEnhancedRecognition: false
        )
        let saving = CaptureVoiceStatus(
            transcriberState: .idle,
            isSaving: true,
            isRecoveringAudio: false,
            isWaitingForContinuation: false,
            isPreparingEnhancedRecognition: false
        )

        XCTAssertEqual(finalizing.title, saving.title)
        XCTAssertEqual(finalizing.orbPhase, saving.orbPhase)
        XCTAssertEqual(finalizing.orbPhase, .processing)
    }

    /// No state may claim a fraction of the work. Nothing in the save reports
    /// how far through it is — the model answers or it does not — so a
    /// percentage or a bar would be an invention.
    func testNoVoiceStateClaimsMeasuredProgress() {
        let digits = CharacterSet.decimalDigits
        for status in CaptureVoiceStatus.everyState {
            XCTAssertNil(
                status.title.rangeOfCharacter(from: digits),
                "\(status) puts a number in its title"
            )
            XCTAssertNil(
                status.subtitle.rangeOfCharacter(from: digits),
                "\(status) puts a number in its subtitle"
            )
            XCTAssertFalse(status.subtitle.contains("%"), "\(status) claims a percentage")
        }
    }

    /// Recovery is the one kind of work that outranks a save, because it is the
    /// path that ends by starting one.
    func testRecoveringTheProtectedRecordingOutranksEveryOtherReading() {
        let status = CaptureVoiceStatus(
            transcriberState: .failed("the recognizer stopped"),
            isSaving: true,
            isRecoveringAudio: true,
            isWaitingForContinuation: false,
            isPreparingEnhancedRecognition: false
        )

        XCTAssertEqual(status, .recovering)
        XCTAssertEqual(status.orbPhase, .processing)
        XCTAssertTrue(status.isBusy)
    }

    /// A state the person can act on is never described as busy, or the notice
    /// that sent them back to the orb would be suppressed.
    func testOnlyWorkInProgressCountsAsBusy() {
        XCTAssertFalse(CaptureVoiceStatus.idle.isBusy)
        XCTAssertFalse(CaptureVoiceStatus.listening(isWaitingForContinuation: false).isBusy)
        XCTAssertFalse(CaptureVoiceStatus.failed.isBusy)
        XCTAssertFalse(CaptureVoiceStatus.permissionDenied.isBusy)
        XCTAssertTrue(CaptureVoiceStatus.finalizing.isBusy)
        XCTAssertTrue(CaptureVoiceStatus.saving.isBusy)
        XCTAssertTrue(CaptureVoiceStatus.recovering.isBusy)
    }

    // MARK: - The receipt for a capture that produced several things

    /// "Buy milk tomorrow" carries a date and arms nothing. The receipt counted
    /// it as a reminder anyway — `reminderCount` asked only whether the state
    /// was `.time`, never whether anything would fire — while `actionCount`
    /// asked the narrower `isArmed` and counted the same row again as a thing
    /// to do. So one row appeared on two lines, the totals could exceed the
    /// number of things saved, and the app announced a reminder for a row that
    /// will never alert. The row glyph beside it has drawn that distinction
    /// since Docs/FINAL_RELEASE_AUDIT.md B-1/C-1; the count above it did not.
    func testADateNobodyAskedToBeAlertedAboutIsNotCountedAsAReminder() async throws {
        let result = try await captureResult("Buy milk tomorrow and remind me to call the dentist tomorrow at 9am")

        try XCTSkipUnless(result.itemCount > 1, "this capture did not split; the receipt is the single-item one")

        XCTAssertLessThanOrEqual(
            result.actionCount + result.reminderCount + result.memoryCount
                + result.needsReviewCount,
            result.itemCount,
            "the receipt counts a row twice: \(result.receiptContext)"
        )
    }

    /// The counts and the rows must describe the same capture. Every row the
    /// receipt calls a reminder has to be one a row would draw a bell or a pin
    /// beside.
    func testEveryCountedReminderIsSomethingThatWillActuallyFire() async throws {
        for text in [
            "Buy milk tomorrow",
            "Remind me to call mom tomorrow at 5pm",
            "Buy milk tomorrow and remind me to call the dentist tomorrow at 9am",
            "Priya’s birthday is December 4th and pick up the cake on the 3rd"
        ] {
            let result = try await captureResult(text)
            let armed = result.items.filter {
                ItemPresentation.make(for: $0, authorization: authorized).reminderState.isArmed
            }
            XCTAssertLessThanOrEqual(
                result.reminderCount,
                armed.count,
                "\(text) announced \(result.reminderCount) reminders with \(armed.count) armed"
            )
        }
    }

    // MARK: - One recording's words never land in another's

    /// The failure this rule exists for: a late partial from an abandoned
    /// recording arriving while the next recording is `.listening`. The state
    /// check alone accepted it, and `receiveTranscript` assigns rather than
    /// appends, so the new recording's words were replaced by the old ones —
    /// and `save` reads that same property.
    func testALateResultFromAnAbandonedRecordingIsRefused() {
        let abandoned = UUID()
        let current = UUID()

        XCTAssertFalse(
            SpeechTranscriber.acceptsResult(
                from: abandoned,
                currentRun: current,
                state: .listening
            ),
            "the previous recording's words reached the new recording"
        )
        XCTAssertFalse(
            SpeechTranscriber.acceptsResult(
                from: abandoned,
                currentRun: current,
                state: .finalizing
            ),
            "the previous recording's words reached the save"
        )
    }

    /// A run that has ended has no successor yet. Nothing may be accepted into
    /// the gap between "Try saying it again" and the recording it starts.
    func testNothingIsAcceptedOnceTheRunHasEnded() {
        let run = UUID()

        XCTAssertFalse(
            SpeechTranscriber.acceptsResult(from: run, currentRun: nil, state: .listening)
        )
        XCTAssertFalse(
            SpeechTranscriber.acceptsResult(from: run, currentRun: run, state: .idle)
        )
        XCTAssertFalse(
            SpeechTranscriber.acceptsResult(from: run, currentRun: run, state: .failed("stopped"))
        )
        XCTAssertFalse(
            SpeechTranscriber.acceptsResult(from: run, currentRun: run, state: .permissionDenied)
        )
    }

    /// The rule must not be so strict that it drops the run's own results. All
    /// three live states belong to the recording in progress.
    func testTheCurrentRunIsStillHeardInEveryLiveState() {
        let run = UUID()

        for state: SpeechTranscriber.State in [.requestingPermission, .listening, .finalizing] {
            XCTAssertTrue(
                SpeechTranscriber.acceptsResult(from: run, currentRun: run, state: state),
                "the live recording's own result was dropped in \(state)"
            )
        }
    }

    // MARK: - The capture review list

    private var container: ModelContainer!
    private var repository: SwiftDataThoughtRepository!
    private var previousPlaces: [String: SavedPlace] = [:]

    private let authorized = LocationAuthorization(
        status: .always,
        isPrecise: true,
        isRegionMonitoringAvailable: true
    )

    override func setUpWithError() throws {
        previousPlaces = SavedPlaceStore.snapshot()
        SavedPlaceStore.restore([:])
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
        SavedPlaceStore.restore(previousPlaces)
        repository = nil
        container = nil
    }

    private func captureResult(_ text: String) async throws -> CaptureCreationResult {
        try await repository.createCaptureResult(
            text: text,
            source: .inAppText,
            createdAt: .now,
            schedulesReminders: false
        )
    }

    private func item(_ text: String) throws -> CapturedItem {
        try repository.createCapture(
            text: text,
            source: .inAppText,
            createdAt: .now,
            schedulesReminder: false
        )
    }

    private func reading(for item: CapturedItem) -> (ItemPresentation, String) {
        let presentation = ItemPresentation.make(for: item, authorization: authorized)
        return (
            presentation,
            CaptureReviewRowReading.spokenLabel(for: item, presentation: presentation)
        )
    }

    /// The review list is the only screen a multi-item capture is read on right
    /// after saving — the receipt behind it shows one row and a count. It used
    /// to print a title and "Category · Type" and stop, so a capture with a
    /// time in it could not be checked against what was heard on the one screen
    /// built for checking it.
    func testAReviewRowCarriesTheTimeItWasGiven() throws {
        let scheduled = try item("Remind me to call mom tomorrow at 5pm")
        let (presentation, label) = reading(for: scheduled)

        let timing = try XCTUnwrap(
            presentation.primaryTimingText,
            "the shared reading has no timing to show, so this asserts nothing"
        )
        XCTAssertTrue(
            label.contains(timing),
            "the review row omits \(timing) from \(label)"
        )
    }

    /// A dated task and an armed reminder were the same row here: same title,
    /// same type line, nothing to separate them. The glyph that separates them
    /// everywhere else is now available to this row too.
    func testADatedTaskAndAnArmedReminderDoNotReadIdentically() throws {
        let armed = try item("Remind me to call mom tomorrow at 5pm")
        let dated = try item("Buy milk tomorrow")

        let armedPresentation = ItemPresentation.make(for: armed, authorization: authorized)
        let datedPresentation = ItemPresentation.make(for: dated, authorization: authorized)

        XCTAssertEqual(armedPresentation.alertSymbolName, "bell.fill")
        XCTAssertNil(
            datedPresentation.alertSymbolName,
            "a date nobody asked to be alerted about must not show an alert glyph"
        )
        XCTAssertNotNil(armedPresentation.alertAccessibilityHint)
        XCTAssertNil(datedPresentation.alertAccessibilityHint)
    }

    /// The row used to mark an unresolved item with a bare question mark whose
    /// only description was the words "Needs review" — which says that
    /// something is wrong and never what. Today's review section has named the
    /// gap since it was written; this row now uses the same sentence.
    func testAHeldRowNamesItsGapRatherThanOnlyMarkingOne() throws {
        let unresolved = try item("Remind me about the thing")
        let (presentation, label) = reading(for: unresolved)

        let requirement = try XCTUnwrap(
            presentation.reviewRequirement,
            "this capture was not held for review, so it cannot test the held row"
        )
        XCTAssertNotEqual(requirement, "Needs review")
        XCTAssertTrue(
            label.contains(requirement),
            "the review row omits \(requirement) from \(label)"
        )
    }

    /// Nothing on this screen may read as though the item has already acted.
    /// The row describes a schedule and an outstanding question; it never
    /// reports a delivery.
    func testAReviewRowDescribesWhatWillHappenRatherThanWhatHas() throws {
        for text in [
            "Remind me to call mom tomorrow at 5pm",
            "Buy milk tomorrow",
            "Remind me about the thing",
            "Priya’s birthday is December 4th"
        ] {
            let (_, label) = reading(for: try item(text))
            for claim in ["Sent", "Delivered", "Reminded", "Notified", "Done"] {
                XCTAssertFalse(
                    label.contains(claim),
                    "\(label) claims \(claim) happened"
                )
            }
        }
    }
}

extension CaptureVoiceStatus {
    /// Every state, so a check that must hold for all of them cannot quietly
    /// miss one that is added later.
    static var everyState: [CaptureVoiceStatus] {
        [
            .idle,
            .preparing(isEnhanced: true),
            .preparing(isEnhanced: false),
            .listening(isWaitingForContinuation: true),
            .listening(isWaitingForContinuation: false),
            .finalizing,
            .saving,
            .recovering,
            .permissionDenied,
            .unavailable,
            .failed
        ]
    }
}
