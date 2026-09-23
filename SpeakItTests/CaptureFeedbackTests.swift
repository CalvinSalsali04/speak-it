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

    // MARK: - Words typed before speaking, on the voice screen

    /// The voice screen shows the words typed before speaking above the
    /// speech, because a spoken save stores both. VoiceOver reads them as
    /// part of the transcript, marked as typed; with nothing typed it reads
    /// the speech exactly as before.
    ///
    /// Falsifier: return the spoken words alone and the first two assertions
    /// fail; drop the empty check and a screen with nothing typed reads
    /// "Typed:" in front of every transcript.
    func testTheVoiceScreenReadsTypedWordsAsPartOfTheTranscript() {
        XCTAssertEqual(
            CaptureVoiceTranscriptAccessibility.value(typedBeforeSpeaking: "Call Dana", spoken: "about the invoice"),
            "Typed: Call Dana. about the invoice"
        )
        XCTAssertEqual(
            CaptureVoiceTranscriptAccessibility.value(typedBeforeSpeaking: " Call\nDana ", spoken: ""),
            "Typed: Call Dana"
        )
        XCTAssertEqual(
            CaptureVoiceTranscriptAccessibility.value(typedBeforeSpeaking: " \n ", spoken: "about the invoice"),
            "about the invoice"
        )
        XCTAssertEqual(CaptureVoiceTranscriptAccessibility.value(typedBeforeSpeaking: "", spoken: ""), "")
    }

    // MARK: - Type instead after the words have moved to the editor

    /// Type instead folds the spoken words into the editor and then asks the
    /// transcriber to forget them. A finished recording whose save returned
    /// early leaves the transcriber `.idle` with its final words still held,
    /// and that is the state the forgetting used to skip: the next Save &
    /// Close joined those words after an editor that already held them.
    ///
    /// Save & Close is modelled by hand, not run: `CaptureView` is a SwiftUI
    /// view this suite cannot drive. The model is that a later save reads
    /// `transcriber.transcript` and `joined` adds nothing for an empty one,
    /// so what is pinned is the transcriber's edge, that nothing is left for
    /// a later save to read, and not the screen.
    ///
    /// Falsifier: move `releaseTranscript()` in `stopForTyping` back inside
    /// the `else if state != .idle` branch and the `.idle` half fails on the
    /// empty transcript.
    ///
    /// The typing fallback after a voice failure goes through the same call,
    /// from `.failed`, where the run is still open. Falsifier: delete the
    /// `else if state != .idle` branch and the `.failed` half fails, because
    /// nothing closes the run or settles the state.
    func testTypeInsteadForgetsTheSpokenWordsInEveryState() {
        let transcriber = SpeechTranscriber(reportsAudioLevel: false)

        // A finished run: the final result closes it and hands its words on.
        let finished = transcriber.beginRunWithoutAudioForTesting()
        finished.deliverTranscript("and eggs", false)
        let spoken = transcriber.transcript
        finished.deliverTranscript(spoken, true)
        finished.deliverTranscript(spoken, true)
        XCTAssertEqual(transcriber.state, .idle)
        XCTAssertNil(transcriber.activeRunIDForTesting)
        XCTAssertEqual(transcriber.transcript, spoken, "this no longer reproduces the idle state that kept its words")

        XCTAssertFalse(transcriber.stopForTyping(), "a finished run has no Live Activity to end")
        XCTAssertEqual(
            transcriber.transcript,
            "",
            "the transcriber kept words the editor already holds, for the next save to add again"
        )

        // A run still listening: cancelled, and its words forgotten likewise.
        let listening = transcriber.beginRunWithoutAudioForTesting()
        listening.deliverTranscript("and bread", false)
        XCTAssertTrue(transcriber.stopForTyping())
        XCTAssertEqual(transcriber.state, .idle)
        XCTAssertNil(transcriber.activeRunIDForTesting)
        XCTAssertEqual(transcriber.transcript, "")

        // A run that failed before any words: the typing fallback's state.
        let failed = transcriber.beginRunWithoutAudioForTesting()
        failed.deliverError(
            NSError(domain: "SFSpeechRecognitionErrorDomain", code: 216, userInfo: nil)
        )
        guard case .failed = transcriber.state else {
            return XCTFail("this no longer reproduces the failed state the typing fallback reads")
        }
        XCTAssertNotNil(transcriber.activeRunIDForTesting)
        XCTAssertFalse(transcriber.stopForTyping(), "a failed run has no Live Activity left to end")
        XCTAssertEqual(transcriber.state, .idle)
        XCTAssertNil(transcriber.activeRunIDForTesting)
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

    // MARK: - A save belongs to the screen that started it

    /// Discard during a save that is already running. The save has to finish,
    /// because those are the person's words, but its screen is gone: in the
    /// shipped defect the finished save called `onSaved`, and `RootView` closed
    /// whatever capture was up by then, mid-sentence.
    ///
    /// The persistence, the slot, the durable effects and the publishing check
    /// are the shipping `CaptureSaveInFlight.persisting`,
    /// `CaptureSaveSettlement.settle` and `CapturePresentation`. What
    /// `ScreenSave` restates is one line: `CaptureView.save` publishes only
    /// when `settle` says the save still publishes.
    ///
    /// Falsifier: drop `!hasEnded` from `CapturePresentation.publishes` and
    /// the closed-screen count below is 1. Move the `publishes()` guard in
    /// `settle` above the charge and the charged count is 0.
    func testASaveThatFinishesAfterItsScreenWasDiscardedDoesNotCloseTheNextOne() async throws {
        let discarded = ScreenSave()
        let save = try XCTUnwrap(discarded.presentation.beginSave())
        let running = Task { @MainActor in await discarded.run(save) }
        await Task.yield()

        // The person taps Discard, then opens a new capture.
        discarded.presentation.end()
        let next = CapturePresentation()
        XCTAssertNotNil(next.beginSave(), "a new screen starts with its own free save slot")

        discarded.releasePersistence()
        await running.value

        XCTAssertEqual(discarded.persistedCount, 1, "the words must still be stored")
        XCTAssertEqual(discarded.chargedCount, 1, "a stored thought went uncharged because its screen had gone")
        XCTAssertEqual(discarded.endedScreenDraftClearedCount, 1, "the stored thought's draft was left to be recovered again")
        XCTAssertFalse(discarded.presentation.isSaveInFlight)
        XCTAssertEqual(
            discarded.closedScreenCount,
            0,
            "a save whose screen was discarded closed the screen that replaced it"
        )
    }

    /// A "Try saying it again" save that outlives its screen. Its attempt was
    /// already charged, so the retry is free, and the attempt it replaces has
    /// to go, or the person finds both in Needs review. This cannot see where
    /// `CaptureView.save` reads the retry source from (it now holds it from
    /// before the `await`, rather than reading `@State` from a screen that may
    /// be gone); it checks what a late save does once it knows.
    ///
    /// Falsifier: move the `publishes()` guard in
    /// `CaptureSaveSettlement.settle` above the deletion and the deleted count
    /// is 0.
    func testARetryThatFinishesAfterItsScreenWasDiscardedStillReplacesItsAttemptWithoutACharge() async throws {
        let discarded = ScreenSave()
        discarded.replacesRetrySource = true
        let save = try XCTUnwrap(discarded.presentation.beginSave())
        let running = Task { @MainActor in await discarded.run(save) }
        await Task.yield()

        discarded.presentation.end()
        discarded.releasePersistence()
        await running.value

        XCTAssertEqual(discarded.persistedCount, 1)
        XCTAssertEqual(discarded.retrySourceDeletedCount, 1, "the replaced attempt stayed in Needs review beside its retry")
        XCTAssertEqual(discarded.chargedCount, 0, "a clarification retry spent a second free capture")
        XCTAssertEqual(discarded.endedScreenDraftClearedCount, 1)
        XCTAssertEqual(discarded.closedScreenCount, 0)
    }

    /// The order itself, with every effect logged. A late save does all the
    /// durable work and then asks whether it may publish; the draft of a gone
    /// screen is cleared after that answer and only on that answer.
    ///
    /// Falsifier: move the `publishes()` guard in
    /// `CaptureSaveSettlement.settle` above the charge, the analytics event or
    /// the deletion, and the log loses them.
    func testALateSaveDoesEveryDurableThingBeforeAskingWhetherItPublishes() {
        var log: [String] = []
        let settled = CaptureSaveSettlement.settle(
            createdNewCapture: true,
            consumesFreeCapture: true,
            replacesRetrySource: false,
            chargeFreeCapture: { log.append("charge") },
            recordSaved: { log.append("analytics") },
            deleteRetrySource: { log.append("deletion") },
            publishes: {
                log.append("publishes")
                return false
            },
            clearDraftOfEndedScreen: { log.append("draft") }
        )
        XCTAssertEqual(log, ["charge", "analytics", "publishes", "draft"])
        XCTAssertEqual(settled, CaptureSaveSettlement.Settled(publishes: false, retrySourceSurvived: false))

        log = []
        let retry = CaptureSaveSettlement.settle(
            createdNewCapture: true,
            consumesFreeCapture: true,
            replacesRetrySource: true,
            chargeFreeCapture: { log.append("charge") },
            recordSaved: { log.append("analytics") },
            deleteRetrySource: { log.append("deletion") },
            publishes: {
                log.append("publishes")
                return false
            },
            clearDraftOfEndedScreen: { log.append("draft") }
        )
        XCTAssertEqual(log, ["analytics", "deletion", "publishes", "draft"])
        XCTAssertEqual(retry, CaptureSaveSettlement.Settled(publishes: false, retrySourceSurvived: false))
    }

    /// The other side of the same order: a save on its own screen does the
    /// same durable work, publishes, and leaves its draft to the screen, which
    /// clears it as it shows the result. A failed retry cleanup is reported
    /// either way, and only `CaptureView.save` decides who hears about it:
    /// on a gone screen, nobody.
    ///
    /// Falsifier: drop `retrySourceSurvived = true` from `settle`'s `catch`
    /// and the failed cleanup is reported as a success.
    func testASaveOnItsOwnScreenPublishesAndReportsARetryThatCouldNotBeDeleted() {
        struct DeletionRefused: Error {}
        var log: [String] = []
        let settled = CaptureSaveSettlement.settle(
            createdNewCapture: true,
            consumesFreeCapture: true,
            replacesRetrySource: true,
            chargeFreeCapture: { log.append("charge") },
            recordSaved: { log.append("analytics") },
            deleteRetrySource: {
                log.append("deletion")
                throw DeletionRefused()
            },
            publishes: {
                log.append("publishes")
                return true
            },
            clearDraftOfEndedScreen: { log.append("draft") }
        )
        XCTAssertEqual(log, ["analytics", "deletion", "publishes"])
        XCTAssertEqual(settled, CaptureSaveSettlement.Settled(publishes: true, retrySourceSurvived: true))

        // An operation on existing content stores no new thought: no charge,
        // no saved-capture event, nothing to replace.
        log = []
        _ = CaptureSaveSettlement.settle(
            createdNewCapture: false,
            consumesFreeCapture: false,
            replacesRetrySource: false,
            chargeFreeCapture: { log.append("charge") },
            recordSaved: { log.append("analytics") },
            deleteRetrySource: { log.append("deletion") },
            publishes: {
                log.append("publishes")
                return true
            },
            clearDraftOfEndedScreen: { log.append("draft") }
        )
        XCTAssertEqual(log, ["publishes"])
    }

    /// Control for the test above: nothing about the gate may stop a save on
    /// its own screen from closing that screen, exactly once.
    func testASaveOnTheScreenThatStartedItStillClosesItOnce() async throws {
        let screen = ScreenSave()
        let save = try XCTUnwrap(screen.presentation.beginSave())
        let running = Task { @MainActor in await screen.run(save) }
        await Task.yield()
        screen.releasePersistence()
        await running.value

        XCTAssertEqual(screen.persistedCount, 1)
        XCTAssertEqual(screen.chargedCount, 1)
        XCTAssertEqual(screen.endedScreenDraftClearedCount, 0)
        XCTAssertEqual(screen.closedScreenCount, 1)
        XCTAssertTrue(screen.presentation.publishes(save))
    }

    /// One screen, one save of its words at a time, and the slot comes back
    /// when the save is done, because "Try saying it again" saves again on the
    /// same screen.
    ///
    /// Falsifier: drop the `saveInFlight == nil` guard from
    /// `CapturePresentation.beginSave` and the second request is granted.
    func testASecondSaveOfTheSameScreenIsRefusedWhileTheFirstRuns() async throws {
        let screen = ScreenSave()
        let first = try XCTUnwrap(screen.presentation.beginSave())
        let running = Task { @MainActor in await screen.run(first) }
        await Task.yield()

        XCTAssertTrue(screen.presentation.isSaveInFlight)
        XCTAssertNil(
            screen.presentation.beginSave(),
            "a second save of these words started while the first was still being stored"
        )

        screen.releasePersistence()
        await running.value

        XCTAssertFalse(screen.presentation.isSaveInFlight)
        let retry = try XCTUnwrap(screen.presentation.beginSave(), "the slot never came back")
        XCTAssertTrue(screen.presentation.publishes(retry))
        XCTAssertFalse(
            screen.presentation.publishes(first),
            "an older save of this screen may not publish once a newer one started"
        )
    }

    // MARK: - Audio recovery that outlives its screen

    /// Recovery transcribes for up to 25 seconds in a Task the screen does not
    /// cancel. When it finishes after the screen has gone, the words must not
    /// be saved through that screen's `save`, which reads its `@State` and
    /// publishes, and must not be lost: they stay on the draft, beside the
    /// recording, which Today then offers to recover.
    ///
    /// The draft store here is the shipping `CaptureDraftStore`, with a real
    /// recording file on disk.
    ///
    /// Falsifier: drop the `hasEnded` guard from the success arm of
    /// `CaptureRecoveryHandoff.finish` and the words go to `save` instead.
    func testRecoveryThatFinishesAfterItsScreenEndedLeavesTheWordsForToday() throws {
        CaptureDraftStore.clear()
        defer { CaptureDraftStore.clear() }
        let draft = try recordingDraft()
        let owner = CapturePresentation()
        owner.end()
        var saved: [String] = []
        var typed = 0

        let outcome = CaptureRecoveryHandoff.finish(
            .success("buy milk and eggs today"),
            draftID: draft.id,
            owner: owner,
            save: { saved.append($0) },
            continueByTyping: { typed += 1 }
        )

        XCTAssertEqual(outcome, .leftForToday)
        XCTAssertEqual(saved, [])
        XCTAssertEqual(typed, 0)
        let kept = try XCTUnwrap(CaptureDraftStore.draft(id: draft.id))
        XCTAssertEqual(kept.transcript, "buy milk and eggs today")
        XCTAssertEqual(kept.recoveryStatus, .capturing)
        XCTAssertTrue(CaptureDraftStore.hasRecoveryAudio(for: kept))
        XCTAssertEqual(CaptureDraftStore.recoverableAudioDrafts(minimumAge: 0).map(\.id), [draft.id])
    }

    /// Control: on a screen that is still up, recovered words are saved there
    /// and the draft is left for that save to clear.
    func testRecoveryOnItsOwnScreenStillSavesThere() throws {
        CaptureDraftStore.clear()
        defer { CaptureDraftStore.clear() }
        let draft = try recordingDraft()
        var saved: [String] = []

        let outcome = CaptureRecoveryHandoff.finish(
            .success("buy milk and eggs today"),
            draftID: draft.id,
            owner: CapturePresentation(),
            save: { saved.append($0) },
            continueByTyping: { XCTFail("recovered words were sent to typing") }
        )

        XCTAssertEqual(outcome, .returnedToScreen)
        XCTAssertEqual(saved, ["buy milk and eggs today"])
        XCTAssertEqual(CaptureDraftStore.draft(id: draft.id)?.recoveryStatus, .processing)
    }

    /// A failed recovery is recorded on the draft either way, and only a
    /// screen that is still up is switched to typing.
    ///
    /// Falsifier: drop the `hasEnded` guard from the failure arm and the ended
    /// screen is switched to typing.
    func testFailedRecoveryTouchesOnlyAScreenThatIsStillUp() throws {
        struct RecognizerGaveUp: Error {}
        CaptureDraftStore.clear()
        defer { CaptureDraftStore.clear() }
        let draft = try recordingDraft()
        let ended = CapturePresentation()
        ended.end()
        var typed = 0

        let late = CaptureRecoveryHandoff.finish(
            .failure(RecognizerGaveUp()),
            draftID: draft.id,
            owner: ended,
            save: { _ in XCTFail("a failed recovery started a save") },
            continueByTyping: { typed += 1 }
        )
        XCTAssertEqual(late, .leftForToday)
        XCTAssertEqual(typed, 0)
        XCTAssertEqual(CaptureDraftStore.draft(id: draft.id)?.recoveryStatus, .failed)
        XCTAssertTrue(CaptureDraftStore.hasRecoveryAudio(for: draft))

        let live = CaptureRecoveryHandoff.finish(
            .failure(RecognizerGaveUp()),
            draftID: draft.id,
            owner: CapturePresentation(),
            save: { _ in XCTFail("a failed recovery started a save") },
            continueByTyping: { typed += 1 }
        )
        XCTAssertEqual(live, .returnedToScreen)
        XCTAssertEqual(typed, 1)
    }

    /// Discard clears the draft while recovery is still running. The late
    /// result must not bring it back.
    ///
    /// Falsifier: let `leaveRecoveredWordsForToday` insert a draft it did not find.
    func testRecoveryThatFinishesAfterDiscardDoesNotBringTheDraftBack() throws {
        CaptureDraftStore.clear()
        defer { CaptureDraftStore.clear() }
        let draft = try recordingDraft()
        let owner = CapturePresentation()
        owner.end()
        CaptureDraftStore.clear(id: draft.id)

        CaptureRecoveryHandoff.finish(
            .success("buy milk and eggs today"),
            draftID: draft.id,
            owner: owner,
            save: { _ in XCTFail("a discarded recording was saved") },
            continueByTyping: {}
        )

        XCTAssertNil(CaptureDraftStore.draft(id: draft.id))
    }

    /// A voice draft with a protected recording on disk, marked as being
    /// recovered, as `recoverActiveAudio` leaves it.
    private func recordingDraft() throws -> CaptureDraftStore.Draft {
        let draft = CaptureDraftStore.begin(source: .inAppVoice)
        let audioURL = try XCTUnwrap(CaptureDraftStore.prepareAudioURL(for: draft))
        try Data(repeating: 0x1, count: 1_024).write(to: audioURL, options: .atomic)
        CaptureDraftStore.markProcessing(id: draft.id)
        return draft
    }

    /// The finalization window, driven through a real transcriber. Save &
    /// Close landed after the recognizer's first final result and before its
    /// last one, saved the partial wording, and then finalization saved the
    /// final wording as a second capture.
    ///
    /// Persistence here finishes at once and gives the slot back before the
    /// final words arrive, which is the timing under which the shipped defect
    /// stored two captures. While persistence is still running, the slot alone
    /// refuses the second save, and the count could not tell the fix from the
    /// defect.
    ///
    /// Falsifier: remove the `.finalizing` branch from
    /// `CaptureCloseRequest.resolveSaveAndClose` and both assertions on
    /// `saved` fail: the partial wording is stored first and the final wording
    /// is stored beside it.
    func testSaveAndCloseDuringFinalizationSavesTheFinalWordsOnce() {
        let transcriber = SpeechTranscriber(reportsAudioLevel: false)
        let presentation = CapturePresentation()
        var saved: [String] = []
        // `CaptureView.save`'s claim and nothing else of it, with a
        // persistence that returns straight away and frees the slot.
        let save: (String) -> Void = { text in
            guard let claimed = presentation.beginSave() else { return }
            saved.append(text)
            presentation.finishPersisting(claimed)
        }

        let recording = transcriber.beginRunWithoutAudioForTesting { save($0) }
        recording.deliverTranscript("buy milk and eggs", false)
        recording.deliverTranscript("buy milk and eggs", true)
        XCTAssertEqual(transcriber.state, .finalizing)

        let request = CaptureCloseRequest.resolveSaveAndClose(
            isVoiceMode: true,
            transcriberState: transcriber.state,
            isSaveInFlight: presentation.isSaveInFlight,
            isRecoveringAudio: false,
            showsSavedConfirmation: false
        )
        XCTAssertEqual(request, .closeWhenSaveFinishes)
        if request == .saveThenClose {
            save(transcriber.transcript)
        }

        recording.deliverTranscript("buy milk and eggs today", true)
        XCTAssertEqual(transcriber.state, .idle)
        XCTAssertEqual(saved.count, 1, "one recording was stored as \(saved.count) captures")
        XCTAssertEqual(saved.first, transcriber.transcript)
        XCTAssertTrue(saved.first?.contains("today") ?? false, "the partial wording was saved")
    }

    /// Every other answer Save & Close can give, so the fix above cannot have
    /// taken the ordinary save away.
    func testSaveAndCloseOnlyStartsASaveWhenNothingElseOwnsTheWords() {
        func resolve(
            voice: Bool = true,
            state: SpeechTranscriber.State = .idle,
            inFlight: Bool = false,
            recovering: Bool = false,
            confirmed: Bool = false
        ) -> CaptureCloseRequest {
            CaptureCloseRequest.resolveSaveAndClose(
                isVoiceMode: voice,
                transcriberState: state,
                isSaveInFlight: inFlight,
                isRecoveringAudio: recovering,
                showsSavedConfirmation: confirmed
            )
        }

        XCTAssertEqual(resolve(state: .listening), .saveThenClose)
        XCTAssertEqual(resolve(state: .idle), .saveThenClose)
        XCTAssertEqual(resolve(voice: false), .saveThenClose)
        XCTAssertEqual(resolve(voice: false, state: .finalizing), .saveThenClose)
        XCTAssertEqual(resolve(inFlight: true), .closeWhenSaveFinishes)
        XCTAssertEqual(resolve(voice: false, inFlight: true), .closeWhenSaveFinishes)
        XCTAssertEqual(resolve(recovering: true), .closeWhenSaveFinishes)
        XCTAssertEqual(resolve(confirmed: true), .closeSaved)
        XCTAssertEqual(resolve(inFlight: true, confirmed: true), .closeWhenSaveFinishes)
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
    /// Every state as this list was written, with both values of each
    /// associated `Bool`. It is written by hand: the associated values keep
    /// `CaptureVoiceStatus` from synthesizing `CaseIterable`, and nothing
    /// puts a case added later on this list. The exhaustive switch in
    /// `spokenChange` fails to compile on a new case, but it can be satisfied
    /// without touching this list, so a check over `everyState` says nothing
    /// about a case missing from it. Add any new case here by hand.
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

/// One capture screen's save, with persistence held open until the test lets
/// it finish.
///
/// It runs the shipping `CaptureSaveInFlight.persisting` and frees the slot
/// through it, then the shipping `CaptureSaveSettlement.settle`, as
/// `CaptureView.save` does, counting each durable effect. The one line
/// restated is the gate: `CaptureView.save` reaches `onSaved`, whether by
/// Save & Close or by the auto-dismiss timer, only when `settle` says the save
/// still publishes.
@MainActor
private final class ScreenSave {
    let presentation = CapturePresentation()
    /// A "Try saying it again" save, which replaces an already-charged attempt.
    var replacesRetrySource = false
    private(set) var persistedCount = 0
    private(set) var chargedCount = 0
    private(set) var retrySourceDeletedCount = 0
    private(set) var endedScreenDraftClearedCount = 0
    private(set) var closedScreenCount = 0
    private var isReleased = false
    private var resume: CheckedContinuation<Void, Never>?

    func run(_ save: CapturePresentation.Save) async {
        _ = try? await CaptureSaveInFlight.persisting(lower: {
            presentation.finishPersisting(save)
        }) {
            await holdUntilReleased()
            persistedCount += 1
        }
        let settled = CaptureSaveSettlement.settle(
            createdNewCapture: true,
            consumesFreeCapture: true,
            replacesRetrySource: replacesRetrySource,
            chargeFreeCapture: { chargedCount += 1 },
            recordSaved: {},
            deleteRetrySource: { retrySourceDeletedCount += 1 },
            publishes: { presentation.publishes(save) },
            clearDraftOfEndedScreen: { endedScreenDraftClearedCount += 1 }
        )
        guard settled.publishes else { return }
        closedScreenCount += 1
    }

    func releasePersistence() {
        isReleased = true
        resume?.resume()
        resume = nil
    }

    private func holdUntilReleased() async {
        guard !isReleased else { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            resume = continuation
        }
    }
}

/// What Speak It asks VoiceOver to say, and the one rule over all of it:
/// nothing it posts is spoken while a microphone is open. (Audit
/// `v1/audits/accessibility.md`, A11Y-1 to A11Y-5.)
///
/// There is no echo cancellation in the production audio session, so an
/// announcement spoken into an open microphone can be transcribed into the
/// person's original words. These tests ask `VoiceOverAnnouncer`'s decisions
/// directly, with VoiceOver, the speech itself and VoiceOver's finish reports
/// played by the test. What they cannot show is that the real VoiceOver sends
/// the report this relies on, or where its audio goes while the session is
/// `.playAndRecord`; those are the device checks.
@MainActor
final class VoiceOverAnnouncementTests: XCTestCase {
    private var voiceOverRunning = true
    private var spoken: [String] = []
    private var microphoneOpened = false
    private var silentAfter: Duration?

    private func makeAnnouncer(allowance: Duration = .seconds(30)) -> VoiceOverAnnouncer {
        VoiceOverAnnouncer(
            isVoiceOverRunning: { [unowned self] in self.voiceOverRunning },
            speak: { [unowned self] in self.spoken.append($0) },
            allowance: { _ in allowance }
        )
    }

    /// Opens the microphone the way `SpeechTranscriber.start` does: after the
    /// wait, with nothing in between.
    private func openMicrophone(with announcer: VoiceOverAnnouncer, cue: String?) -> Task<Void, Never> {
        Task { @MainActor in
            await announcer.waitUntilMicrophoneMayOpen(cue: cue)
            announcer.microphoneWillOpen()
            self.microphoneOpened = true
        }
    }

    /// Lets a waiting task reach its continuation. Bounded, so a regression
    /// fails here instead of hanging the suite.
    private func untilWaiting(_ announcer: VoiceOverAnnouncer) async {
        for _ in 0..<1_000 where announcer.waitingCount == 0 && !microphoneOpened {
            await Task.yield()
        }
    }

    // MARK: - Nothing is spoken into an open microphone

    /// Falsifier: drop `guard openMicrophones == 0` from
    /// `VoiceOverAnnouncer.decision` and the recovery notice reaches VoiceOver
    /// while the recognizer is capturing.
    func testNothingIsSpokenWhileAMicrophoneIsOpen() {
        let announcer = makeAnnouncer()
        announcer.microphoneWillOpen()

        XCTAssertEqual(announcer.announce("Recovering your words"), .microphoneOpen)
        XCTAssertEqual(spoken, [], "an announcement was spoken into the open microphone")
        XCTAssertEqual(announcer.unfinished, [])
        XCTAssertEqual(announcer.withheldAnnouncements, 1)

        announcer.microphoneDidClose()
        XCTAssertEqual(announcer.announce("Recovering your words"), .speak)
        XCTAssertEqual(spoken, ["Recovering your words"])
    }

    /// Falsifier: make the open microphone a flag rather than a count, and the
    /// first transcriber to close lets announcements through while the second
    /// is still recording.
    func testOneMicrophoneClosingDoesNotReopenSpeechWhileAnotherIsOpen() {
        let announcer = makeAnnouncer()
        announcer.microphoneWillOpen()
        announcer.microphoneWillOpen()
        announcer.microphoneDidClose()

        XCTAssertEqual(announcer.announce("Remembered"), .microphoneOpen)
        XCTAssertEqual(spoken, [])
        XCTAssertEqual(
            VoiceOverAnnouncer.decision(voiceOverRunning: true, openMicrophones: 1),
            .microphoneOpen
        )
    }

    /// The count is process-wide, so a claim that is never given back
    /// withholds every announcement until the app is killed. The transcriber
    /// that took the claim gives it back when it goes, whether or not its
    /// screen remembered to cancel it.
    ///
    /// Falsifier: delete `SpeechTranscriber`'s `deinit`, and the count stays at
    /// one after the transcriber is gone, so the last announcement here is
    /// withheld.
    func testATranscriberReleasedWhileHoldingTheMicrophoneGivesItBack() {
        let announcer = makeAnnouncer()
        var transcriber: SpeechTranscriber? = SpeechTranscriber(reportsAudioLevel: false, announcer: announcer)
        transcriber?.claimMicrophone()
        XCTAssertEqual(announcer.openMicrophones, 1)

        weak var released = transcriber
        transcriber = nil
        XCTAssertNil(released, "the transcriber outlived its last reference, so this proves nothing")
        XCTAssertEqual(announcer.openMicrophones, 0, "a released transcriber kept the microphone claimed")
        XCTAssertEqual(announcer.announce("Remembered"), .speak)
    }

    // MARK: - The microphone does not open over something still being spoken

    /// The case that made "post it before the engine starts" insufficient on
    /// its own: "Try saying it again" posts a notice and opens the microphone
    /// 260 ms later, and VoiceOver is still reading it then.
    ///
    /// Falsifier: have `mayOpenMicrophone` ignore `unfinishedAnnouncements`,
    /// and the microphone opens while the notice and the cue are unspoken.
    func testTheMicrophoneOpensOnlyAfterEverythingPostedHasBeenSpoken() async {
        let announcer = makeAnnouncer()
        let notice = "Try saying it a different way, or include the missing detail."
        announcer.announce(notice)

        let opening = openMicrophone(with: announcer, cue: "Listening")
        await untilWaiting(announcer)
        XCTAssertEqual(spoken, [notice, "Listening"], "the cue is posted before the microphone opens")
        XCTAssertFalse(microphoneOpened, "the microphone opened while the notice was being spoken")

        announcer.announcementDidFinish(notice)
        await untilWaiting(announcer)
        XCTAssertFalse(microphoneOpened, "the microphone opened while the cue was being spoken")

        announcer.announcementDidFinish("Listening")
        await opening.value
        XCTAssertTrue(microphoneOpened)
        XCTAssertEqual(announcer.announce("Still listening"), .microphoneOpen)
    }

    /// Falsifier: release the oldest unfinished announcement on any finish
    /// report, and a report about the receipt opens the microphone while the
    /// cue is still being spoken.
    func testAReportAboutAnotherAnnouncementDoesNotOpenTheMicrophone() async {
        let announcer = makeAnnouncer()
        let opening = openMicrophone(with: announcer, cue: "Listening")
        await untilWaiting(announcer)

        announcer.announcementDidFinish("Remembered. Memory.")
        await untilWaiting(announcer)
        XCTAssertFalse(microphoneOpened, "an unrelated report released the microphone")

        announcer.announcementDidFinish("Listening")
        await opening.value
        XCTAssertTrue(microphoneOpened)
    }

    /// Speak It posts an attributed string, and VoiceOver's finish report may
    /// carry either form. This cannot show which one the real VoiceOver sends
    /// (a device check); it shows that either one releases the wait.
    ///
    /// Falsifier: read the report only as a `String`, and the attributed form
    /// matches nothing, so every wait runs its whole allowance.
    func testAFinishReportIsReadInEitherFormItMayArriveIn() {
        XCTAssertEqual(VoiceOverAnnouncer.spokenText(fromFinishReport: NSAttributedString(string: "Listening")), "Listening")
        XCTAssertEqual(VoiceOverAnnouncer.spokenText(fromFinishReport: "Listening"), "Listening")
        XCTAssertNil(VoiceOverAnnouncer.spokenText(fromFinishReport: nil))
        XCTAssertNil(VoiceOverAnnouncer.spokenText(fromFinishReport: 7))

        let announcer = makeAnnouncer()
        announcer.announce("Listening")
        announcer.announcementDidFinish(
            VoiceOverAnnouncer.spokenText(fromFinishReport: NSAttributedString(string: "Listening"))
        )
        XCTAssertEqual(announcer.unfinished, [], "a report in the attributed form did not match what was posted")
    }

    // MARK: - No cost without VoiceOver, and no permanent hold with it

    /// Falsifier: drop `!voiceOverRunning ||` from `mayOpenMicrophone`, and a
    /// capture waits out the thirty-second allowance of an announcement
    /// VoiceOver will never speak.
    func testWithoutVoiceOverNothingIsSpokenAndTheMicrophoneDoesNotWait() async {
        let announcer = makeAnnouncer()
        announcer.announce("Saving your thought")
        voiceOverRunning = false

        XCTAssertEqual(announcer.announce("Remembered"), .voiceOverOff)
        XCTAssertEqual(spoken, ["Saving your thought"])
        XCTAssertTrue(
            VoiceOverAnnouncer.mayOpenMicrophone(voiceOverRunning: false, unfinishedAnnouncements: 3)
        )

        let started = ContinuousClock.now
        await announcer.waitUntilMicrophoneMayOpen(cue: "Listening")
        XCTAssertLessThan(started.duration(to: .now), .seconds(1), "the microphone waited with VoiceOver off")
        XCTAssertEqual(spoken, ["Saving your thought"], "the cue was posted with VoiceOver off")
    }

    /// Falsifier: remove the timeout task from `untilSilent`, and a finish
    /// report VoiceOver never sends holds the microphone shut for good. The
    /// wait runs in its own task and this test waits for it for five
    /// seconds at most, so that mutation fails here rather than hanging the
    /// suite; the stranded task is left suspended. The lower bound catches
    /// the opposite mutation, a wait that does not wait at all.
    func testALostFinishReportHoldsTheMicrophoneOnlyForItsAllowance() async throws {
        let announcer = makeAnnouncer(allowance: .milliseconds(80))
        let started = ContinuousClock.now
        announcer.announce("Listening")

        let silent = expectation(description: "the allowance ran out and the microphone could open")
        Task { @MainActor in
            await announcer.untilSilent()
            self.silentAfter = started.duration(to: .now)
            silent.fulfill()
        }
        await fulfillment(of: [silent], timeout: 5)

        let waited = try XCTUnwrap(silentAfter, "a lost finish report held the microphone shut")
        XCTAssertGreaterThanOrEqual(waited, .milliseconds(80))
        XCTAssertEqual(announcer.unfinished, [])
    }

    /// Falsifier: have `wakeWaiters` resume only when nothing is unfinished,
    /// and turning VoiceOver off mid-announcement strands a capture waiting
    /// for a report that will never come.
    func testTurningVoiceOverOffReleasesAWaitingMicrophone() async {
        let announcer = makeAnnouncer()
        let opening = openMicrophone(with: announcer, cue: "Listening")
        await untilWaiting(announcer)
        XCTAssertFalse(microphoneOpened)

        voiceOverRunning = false
        announcer.wakeWaiters()
        await opening.value
        XCTAssertTrue(microphoneOpened)
    }

    // MARK: - What is said

    /// Falsifier: join the parts with a full stop regardless, and the receipt
    /// reads "Can you clarify?." aloud.
    func testAReceiptIsReadAsSentences() {
        XCTAssertEqual(
            VoiceOverAnnouncer.sentence(["Can you clarify?", "I understood the thought, but not when."]),
            "Can you clarify? I understood the thought, but not when."
        )
        XCTAssertEqual(
            VoiceOverAnnouncer.sentence(["Remembered", "Today\n2 free captures left"]),
            "Remembered. Today. 2 free captures left."
        )
        XCTAssertEqual(VoiceOverAnnouncer.sentence(["Remembered", ""]), "Remembered.")
    }

    /// Falsifier: announce `.listening` here (the original "Listening" after
    /// the first microphone buffer), and a state entered with the microphone
    /// open is spoken into it.
    func testNoVoiceStateEnteredWithTheMicrophoneOpenIsAnnounced() {
        for old in CaptureVoiceStatus.everyState {
            for new in CaptureVoiceStatus.everyState {
                guard CaptureVoiceStatus.spokenChange(from: old, to: new) != nil else { continue }
                switch new {
                case .listening, .preparing:
                    XCTFail("\(old) to \(new) is announced, and the microphone opens in that state")
                default:
                    break
                }
            }
        }
    }

    /// Falsifier: drop the finalizing-to-saving exception, and one save is
    /// announced twice.
    func testASaveIsAnnouncedOnceAndRecoveryIsAnnounced() {
        XCTAssertEqual(
            CaptureVoiceStatus.spokenChange(from: .listening(isWaitingForContinuation: false), to: .finalizing),
            "Saving your thought"
        )
        XCTAssertNil(CaptureVoiceStatus.spokenChange(from: .finalizing, to: .saving))
        XCTAssertEqual(CaptureVoiceStatus.spokenChange(from: .idle, to: .saving), "Saving your thought")
        XCTAssertNotNil(
            CaptureVoiceStatus.spokenChange(from: .listening(isWaitingForContinuation: false), to: .recovering)
        )
        XCTAssertNil(CaptureVoiceStatus.spokenChange(from: .saving, to: .saving))
    }
}
