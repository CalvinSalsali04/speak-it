import AVFoundation
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

    // MARK: - The whole lifecycle the stale-callback race lives in

    /// Steps 1 to 13 of the race, driven through the shipping callback path
    /// rather than a description of it.
    ///
    /// `acceptsResult` is already covered above as a rule. What was not covered
    /// is the lifecycle it depends on: that a run's identity is assigned when
    /// the recording starts, dropped when it is abandoned, and replaced by the
    /// next recording's — so the rule is asked a question whose answer is the
    /// one that matters. Every callback fired here is the exact closure a
    /// recognition backend is handed by `start`, and each one runs the real
    /// `receiveTranscript`, `receiveVoiceActivity` or `receiveError`.
    ///
    /// Falsifier: drop the `currentRun == runID` line from `acceptsResult` and
    /// this fails at the first delayed partial, on the assertion below that
    /// recording B still holds its own words.
    func testALateCallbackFromAnAbandonedRecordingNeverReachesTheNextOne() {
        let transcriber = SpeechTranscriber(reportsAudioLevel: false)
        var savedCaptures: [String] = []

        // 1 and 2. Recording A starts and says something.
        let recordingA = transcriber.beginRunWithoutAudioForTesting {
            savedCaptures.append($0)
        }
        XCTAssertEqual(transcriber.state, .listening)
        XCTAssertEqual(transcriber.activeRunIDForTesting, recordingA.id)
        recordingA.deliverVoiceActivity()
        recordingA.deliverTranscript("call the landlord about the lease", false)
        XCTAssertFalse(transcriber.transcript.isEmpty, "recording A heard nothing to lose")

        // 3. A is abandoned. Every route that does this is a live path to the
        //    race: trying an unclear capture again, switching to typing and
        //    back, and both tutorial retries. The backend is dropped here; its
        //    callbacks are not, and the recognizer may still fire them.
        transcriber.cancel()
        XCTAssertNil(transcriber.activeRunIDForTesting)
        XCTAssertEqual(transcriber.state, .idle)

        // 4 and 5. Recording B starts and says something else.
        let recordingB = transcriber.beginRunWithoutAudioForTesting {
            savedCaptures.append($0)
        }
        XCTAssertNotEqual(recordingB.id, recordingA.id)
        XCTAssertEqual(transcriber.activeRunIDForTesting, recordingB.id)
        recordingB.deliverTranscript("book the dentist for Thursday", false)
        let wordsOfB = transcriber.transcript
        XCTAssertTrue(wordsOfB.contains("dentist"), "recording B heard nothing to protect")

        // 6 and 7. A delayed partial from A, arriving while B is listening.
        //    This is the frame the defect shipped in: the state check passed,
        //    and `receiveTranscript` assigns rather than appends.
        recordingA.deliverTranscript("call the landlord about the lease", false)
        XCTAssertEqual(
            transcriber.transcript,
            wordsOfB,
            "the abandoned recording's words replaced the live recording's"
        )

        // 8 and 9. A delayed final from A. Nothing may be saved from it, and B
        //    must still be the recording in progress.
        recordingA.deliverTranscript("call the landlord about the lease", true)
        XCTAssertEqual(transcriber.transcript, wordsOfB)
        XCTAssertEqual(transcriber.state, .listening)
        XCTAssertEqual(transcriber.activeRunIDForTesting, recordingB.id)
        XCTAssertTrue(savedCaptures.isEmpty, "the abandoned recording saved a capture")

        // 10 and 11. A delayed error from A. It belongs to a recording that is
        //    over, so it may not fail or cancel the one that is running.
        recordingA.deliverError(
            NSError(domain: "SFSpeechRecognitionErrorDomain", code: 216, userInfo: nil)
        )
        XCTAssertEqual(transcriber.state, .listening, "the abandoned recording failed the live one")
        XCTAssertEqual(transcriber.transcript, wordsOfB)
        XCTAssertEqual(transcriber.activeRunIDForTesting, recordingB.id)

        // 12 and 13. B finishes on its own. The first final closes the audio
        //    and moves the run to `.finalizing`; the recognizer's last result
        //    completes it. Only B's words are saved.
        recordingB.deliverTranscript(wordsOfB, true)
        XCTAssertEqual(transcriber.state, .finalizing)
        recordingB.deliverTranscript(wordsOfB, true)
        XCTAssertEqual(transcriber.state, .idle)
        XCTAssertNil(transcriber.activeRunIDForTesting)
        XCTAssertEqual(savedCaptures, [wordsOfB])
        XCTAssertFalse(
            savedCaptures.joined().contains("landlord"),
            "the abandoned recording's words were saved as this capture"
        )
    }

    /// The other half of the same rule, and the one a too-strict fix would
    /// break: a run still hears itself in every live state, including after a
    /// previous run has been abandoned.
    func testTheRunInProgressStillHearsItselfAfterAnEarlierOneWasAbandoned() {
        let transcriber = SpeechTranscriber(reportsAudioLevel: false)

        let abandoned = transcriber.beginRunWithoutAudioForTesting()
        abandoned.deliverTranscript("something I changed my mind about", false)
        transcriber.cancel()

        let current = transcriber.beginRunWithoutAudioForTesting()
        current.deliverTranscript("water the plants", false)
        current.deliverTranscript("water the plants on Sunday", false)
        current.deliverVoiceActivity()

        XCTAssertTrue(transcriber.transcript.contains("Sunday"))
        XCTAssertTrue(transcriber.hasDetectedAudioInput)
        XCTAssertEqual(transcriber.state, .listening)
    }

    // MARK: - A stale start releases only what it created (LIF-7)
    //
    // The race: recording A is inside its `makeStartedBackend` await (model
    // preparation can take seconds), the person taps Type instead, Speak
    // instead and the orb, and recording B starts and is listening before A's
    // await returns. These tests stop each run where `start` would stand at
    // that step, which `beginRunWithoutAudioForTesting` cannot: it reports the
    // microphone ready at once.

    /// Falsifier: put `resetRecognitionResources()` back in the stale branch
    /// of `SpeechTranscriber.adoptStartedBackend`. B's backend is then
    /// cancelled and uninstalled, and B still says `.listening`.
    func testAStaleStartReleasesOnlyItsOwnBackendAndLeavesTheNewerRecordingListening() {
        let transcriber = SpeechTranscriber(reportsAudioLevel: false)
        let staleBackend = RecordingRecognitionBackend()
        let currentBackend = RecordingRecognitionBackend()
        defer { transcriber.cancel() }

        let staleRun = transcriber.openRunWithoutAudioForTesting()
        transcriber.cancel()
        let currentRun = transcriber.openRunWithoutAudioForTesting()
        XCTAssertTrue(transcriber.adoptStartedBackendForTesting(currentBackend, for: currentRun))
        transcriber.reportAudioInputReadyForTesting(startID: currentRun)
        XCTAssertEqual(transcriber.state, .listening)

        XCTAssertFalse(transcriber.adoptStartedBackendForTesting(staleBackend, for: staleRun))

        XCTAssertEqual(staleBackend.cancelCount, 1, "the stale run must release the backend it was handed")
        XCTAssertEqual(currentBackend.cancelCount, 0, "the stale run tore down the newer recording")
        XCTAssertTrue(transcriber.isInstalledBackendForTesting(currentBackend))
        XCTAssertFalse(transcriber.isInstalledBackendForTesting(staleBackend))
        XCTAssertEqual(transcriber.state, .listening)
        XCTAssertEqual(transcriber.activeRunIDForTesting, currentRun)

        // And B is still the recording a stop reaches.
        transcriber.cancel()
        XCTAssertEqual(currentBackend.cancelCount, 1)
    }

    /// Falsifier: lower `isPreparingEnhancedRecognition` before the ownership
    /// guard in `adoptStartedBackend`, where `start` used to. The stale run
    /// then hides the newer recording's model preparation. The second half
    /// fails if the owning branch stops lowering it.
    func testAStaleStartLeavesTheNewerRecordingsModelPreparationShowing() {
        let transcriber = SpeechTranscriber(reportsAudioLevel: false)
        defer { transcriber.cancel() }

        let staleRun = transcriber.openRunWithoutAudioForTesting(preparingEnhancedRecognition: true)
        transcriber.cancel()
        XCTAssertFalse(transcriber.isPreparingEnhancedRecognition)
        let currentRun = transcriber.openRunWithoutAudioForTesting(preparingEnhancedRecognition: true)

        XCTAssertFalse(
            transcriber.adoptStartedBackendForTesting(RecordingRecognitionBackend(), for: staleRun)
        )
        XCTAssertTrue(transcriber.isPreparingEnhancedRecognition)
        XCTAssertEqual(transcriber.state, .requestingPermission)

        XCTAssertTrue(
            transcriber.adoptStartedBackendForTesting(RecordingRecognitionBackend(), for: currentRun)
        )
        XCTAssertFalse(transcriber.isPreparingEnhancedRecognition)
    }

    // MARK: - The voice screen for as long as the save runs

    /// The cause, reproduced rather than assumed. `completeFinalization`
    /// returns the transcriber to `.idle` and only then hands the words to
    /// `save`, so the screen was reading `.idle` for the whole of the save —
    /// and the reading it produced invited a capture that could not start.
    func testTheSaveIsHandedItsWordsOnAScreenTheTranscriberHasAlreadyLeft() throws {
        let transcriber = SpeechTranscriber(reportsAudioLevel: false)
        var stateWhenTheSaveBegan: SpeechTranscriber.State?
        var wordsHandedToTheSave: String?

        let recording = transcriber.beginRunWithoutAudioForTesting { finalText in
            stateWhenTheSaveBegan = transcriber.state
            wordsHandedToTheSave = finalText
        }
        recording.deliverTranscript("pick up the prescription before six", false)
        let spoken = transcriber.transcript
        recording.deliverTranscript(spoken, true)
        recording.deliverTranscript(spoken, true)

        XCTAssertEqual(wordsHandedToTheSave, spoken)
        let stateAtTheSave = try XCTUnwrap(
            stateWhenTheSaveBegan,
            "the save was never handed any words, so there is no frame to check"
        )
        XCTAssertEqual(
            stateAtTheSave,
            SpeechTranscriber.State.idle,
            "this test no longer reproduces the frame the defect shipped in"
        )

        let screen = CaptureVoiceStatus(
            transcriberState: stateAtTheSave,
            isSaving: true,
            isRecoveringAudio: false,
            isWaitingForContinuation: false,
            isPreparingEnhancedRecognition: false
        )
        XCTAssertEqual(screen, .saving)
        XCTAssertTrue(screen.disablesCaptureControl)
    }

    /// What the person sees for as long as the save takes, which is the part
    /// that could not be asserted before: the reading has to hold while the
    /// work runs, not merely be correct at one instant.
    ///
    /// The delay here is decided by the test rather than by on-device
    /// refinement or the store, so the window is deterministic and the
    /// assertions are not racing it.
    func testNothingOnTheScreenChangesForAsLongAsTheSaveRuns() async {
        let transcriber = SpeechTranscriber(reportsAudioLevel: false)
        let recording = transcriber.beginRunWithoutAudioForTesting()
        recording.deliverTranscript("pick up the prescription before six", false)
        let spoken = transcriber.transcript
        recording.deliverTranscript(spoken, true)
        recording.deliverTranscript(spoken, true)

        let save = SaveHeldOpenByTheTest()
        func screen() -> CaptureVoiceStatus {
            CaptureVoiceStatus(
                transcriberState: transcriber.state,
                isSaving: save.isSaving,
                isRecoveringAudio: false,
                isWaitingForContinuation: transcriber.isWaitingForContinuation,
                isPreparingEnhancedRecognition: transcriber.isPreparingEnhancedRecognition
            )
        }

        XCTAssertEqual(screen(), .idle, "nothing is saving yet")

        save.begin()
        let running = Task { @MainActor in await save.holdUntilReleased() }
        await Task.yield()

        XCTAssertEqual(screen(), .saving)
        XCTAssertEqual(screen().orbPhase, .processing)
        XCTAssertTrue(screen().isBusy)
        XCTAssertTrue(screen().disablesCaptureControl, "a second capture could start on top of this one")
        XCTAssertNotEqual(screen().title, CaptureVoiceStatus.idle.title)
        XCTAssertNotEqual(screen().subtitle, CaptureVoiceStatus.idle.subtitle)
        XCTAssertNotEqual(screen().buttonAccessibilityLabel, CaptureVoiceStatus.idle.buttonAccessibilityLabel)
        XCTAssertEqual(transcriber.transcript, spoken, "the words left the screen while the save was still running")

        save.succeed()
        await running.value

        XCTAssertEqual(screen(), .idle)
        XCTAssertFalse(screen().isBusy)
        XCTAssertFalse(screen().disablesCaptureControl)
        XCTAssertEqual(screen().title, CaptureVoiceStatus.idle.title)
    }

    /// The failure half. A save that throws puts the person back in front of a
    /// control they can use, and does not take their words with it.
    func testAFailedSaveReturnsTheControlsAndKeepsTheWords() async {
        let transcriber = SpeechTranscriber(reportsAudioLevel: false)
        let recording = transcriber.beginRunWithoutAudioForTesting()
        recording.deliverTranscript("pick up the prescription before six", false)
        let spoken = transcriber.transcript
        recording.deliverTranscript(spoken, true)
        recording.deliverTranscript(spoken, true)

        let save = SaveHeldOpenByTheTest()
        save.begin()
        let running = Task { @MainActor in await save.holdUntilReleased() }
        await Task.yield()
        save.fail()
        await running.value

        let screen = CaptureVoiceStatus(
            transcriberState: transcriber.state,
            isSaving: save.isSaving,
            isRecoveringAudio: false,
            isWaitingForContinuation: false,
            isPreparingEnhancedRecognition: false
        )
        XCTAssertFalse(screen.disablesCaptureControl, "the person was left with nothing to tap")
        XCTAssertFalse(screen.isBusy)
        XCTAssertEqual(transcriber.transcript, spoken, "the failed save took the words with it")
    }

    /// The lifecycle invariant itself, on the function `CaptureView.save`
    /// lowers its flag through: up for as long as persistence runs, and down
    /// exactly once however persistence ends. It has two exits, a return and a
    /// throw; the third row is the throw a cancelled store call surfaces as,
    /// not a cancelled Task.
    ///
    /// Falsifier: replace the `defer` with a `lower()` after the `await` and the
    /// two throwing rows fail, which is the orb left on "Saving" with
    /// every control refused.
    func testTheSavingFlagComesDownOnEveryWayOutOfPersistence() async {
        struct StoreRefused: Error {}
        let endings: [(name: String, persist: () async throws -> Int)] = [
            ("returned", { 1 }),
            ("threw", { throw StoreRefused() }),
            ("threw a cancellation", { throw CancellationError() })
        ]

        for ending in endings {
            var isSaving = true
            var lowered = 0
            var raisedWhileRunning: Bool?

            _ = try? await CaptureSaveInFlight.persisting(lower: {
                isSaving = false
                lowered += 1
            }) {
                raisedWhileRunning = isSaving
                return try await ending.persist()
            }

            XCTAssertEqual(raisedWhileRunning, true, "persistence \(ending.name) with the flag already down")
            XCTAssertFalse(isSaving, "persistence \(ending.name) and left the screen saying Saving")
            XCTAssertEqual(lowered, 1, "persistence \(ending.name) and lowered the flag \(lowered) times")
        }
    }

    /// Recovery outranks a save while it runs, and the control stays refused
    /// for both — the screen never offers a new capture during either.
    func testEveryStateThatIsWorkingRefusesANewCapture() {
        for status in CaptureVoiceStatus.everyState where status.isBusy {
            XCTAssertTrue(
                status.disablesCaptureControl,
                "\(status) is working and still offers to start another capture"
            )
        }
        XCTAssertTrue(
            CaptureVoiceStatus.preparing(isEnhanced: false).disablesCaptureControl,
            "the microphone is not open yet, so a tap would be dropped"
        )
        XCTAssertFalse(CaptureVoiceStatus.idle.disablesCaptureControl)
        XCTAssertFalse(CaptureVoiceStatus.listening(isWaitingForContinuation: false).disablesCaptureControl)
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

/// A save whose length this test decides.
///
/// `isSaving` is `@State` inside `CaptureView`, so a unit test cannot read the
/// real one. What this double does NOT restate is the lowering: its held-open
/// save runs through `CaptureSaveInFlight.persisting`, the function
/// `CaptureView.save` wraps its one `await` in, so the flag comes down here by
/// the shipping code's `defer` and by nothing else. Only the raise is
/// restated, because `CaptureView` does it synchronously before the Task.
@MainActor
private final class SaveHeldOpenByTheTest {
    private struct SaveFailed: Error {}

    private(set) var isSaving = false
    private var outcome: Result<Void, Error>?
    private var resume: CheckedContinuation<Void, Error>?

    func begin() { isSaving = true }

    func holdUntilReleased() async {
        _ = try? await CaptureSaveInFlight.persisting(lower: { isSaving = false }) {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                if let outcome {
                    continuation.resume(with: outcome)
                } else {
                    resume = continuation
                }
            }
        }
    }

    /// Nothing here lowers the flag. If the two paths read the same afterwards,
    /// that is because the shipping function lowers it on both.
    func succeed() { release(.success(())) }

    func fail() { release(.failure(SaveFailed())) }

    private func release(_ result: Result<Void, Error>) {
        outcome = result
        resume?.resume(with: result)
        resume = nil
    }
}

/// A recognition backend that only records what the transcriber asks of it.
/// It never produces a result.
@MainActor
private final class RecordingRecognitionBackend: SpeechRecognitionBackend {
    let engine = SpeechRecognitionEngine.legacyRecognizer
    let usesTrainedVoiceActivityDetection = false
    private(set) var cancelCount = 0

    func start(
        contextualPhrases: [String],
        onTranscript: @escaping @MainActor (String, Bool) -> Void,
        onVoiceActivity: @escaping @MainActor () -> Void,
        onError: @escaping @MainActor (Error) -> Void
    ) async throws {}

    nonisolated func append(_ buffer: AVAudioPCMBuffer) {}

    func endAudio() {}

    func cancel() {
        cancelCount += 1
    }
}
