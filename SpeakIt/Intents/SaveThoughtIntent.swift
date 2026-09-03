import AppIntents
import Foundation

enum CaptureActivationStore {
    static let lastInvocationKey = "SpeakIt.lastExternalCaptureInvocation"
    static let lastMicrophoneReadyKey = "SpeakIt.lastExternalCaptureMicrophoneReady"
    static let lastSuccessKey = "SpeakIt.lastExternalCaptureSuccess"
    static let lastFailureKey = "SpeakIt.lastExternalCaptureFailure"
    static let lastStartupDurationKey = "SpeakIt.lastExternalCaptureStartupDuration"

    static func markInvoked(at date: Date = .now) {
        UserDefaults.standard.set(date.timeIntervalSince1970, forKey: lastInvocationKey)
    }

    static func markSucceeded(at date: Date = .now) {
        UserDefaults.standard.set(date.timeIntervalSince1970, forKey: lastSuccessKey)
    }

    static func markMicrophoneReady(
        at date: Date = .now,
        startupDuration: Duration
    ) {
        UserDefaults.standard.set(date.timeIntervalSince1970, forKey: lastMicrophoneReadyKey)
        UserDefaults.standard.set(
            Double(CapturePerformanceClock.milliseconds(startupDuration)) / 1_000,
            forKey: lastStartupDurationKey
        )
    }

    static func markFailed(at date: Date = .now) {
        UserDefaults.standard.set(date.timeIntervalSince1970, forKey: lastFailureKey)
    }
}

/// Opens Speak It directly into an auto-starting voice capture. Foregrounding
/// the app before activating the microphone makes Back Tap and Action Button
/// reliable from a cold launch as well as while another app is onscreen.
struct BeginListeningIntent: AppIntent {
    static let title: LocalizedStringResource = "Speak It Capture"
    static let description = IntentDescription(
        "Open Speak It and start listening immediately."
    )
    static let openAppWhenRun = true
    static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    @available(iOS 26.0, *)
    static var supportedModes: IntentModes { .foreground(.immediate) }

    static var parameterSummary: some ParameterSummary {
        Summary("Capture a thought with Speak It")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        let activatedAt = Date.now
        let activationInstant = CapturePerformanceClock.now
        CaptureActivationStore.markInvoked(at: activatedAt)
        QuickActionRouter.shared.requestVoiceCapture(
            activatedAt: activatedAt,
            activationInstant: activationInstant
        )
        return .result()
    }
}

/// The type name intentionally remains stable so an existing personal
/// shortcut can update from the older Speak It action to this background save.
struct SaveThoughtIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Save Speak It Thought"
    static let description = IntentDescription(
        "Save dictated text to Speak It and show the Remembered confirmation."
    )
    static let openAppWhenRun = false

    @Parameter(
        title: "Thought",
        description: "The Dictated Text produced by the previous Shortcut action",
        requestValueDialog: "What should I remember?",
        inputConnectionBehavior: .connectToPreviousIntentResult
    )
    var thought: String

    init() {}

    init(thought: String) {
        self.thought = thought
    }

    static var parameterSummary: some ParameterSummary {
        Summary("Save \(\.$thought)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let normalizedThought = thought.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedThought.isEmpty else {
            await CaptureActivityManager.cancelListening()
            throw RepositoryError.emptyCapture
        }

        await CaptureActivityManager.showOrganizing(normalizedThought)
        let result = try await ExternalCaptureWriter.save(normalizedThought)
        CaptureActivationStore.markSucceeded()
        if result.needsInterpretationConfirmation {
            await CaptureActivityManager.showProblem(
                title: "Needs clarification",
                detail: "Open Speak It to try again or review what was saved."
            )
            return .result(
                dialog: "I’m not completely sure I understood that. Open Speak It to try again or review it."
            )
        } else {
            await CaptureActivityManager.showRemembered(
                normalizedThought,
                context: result.confirmationContext
            )
            return .result(dialog: result.isDuplicate ? "Already captured." : "Remembered.")
        }
    }
}

/// A hands-free completion path that is intentionally useful from Apple Watch
/// and Siri even when the iPhone app is not onscreen.
struct CompleteNextSpeakItItemIntent: AppIntent {
    static let title: LocalizedStringResource = "Complete Next Speak It Item"
    static let description = IntentDescription(
        "Complete the first open item in Speak It Today."
    )
    static let openAppWhenRun = false
    // Deliberately *not* `.alwaysAllowed`.
    //
    // This is a registered App Shortcut ("Complete my next item in Speak It"),
    // so allowing it on a locked device let anyone holding the phone both
    // perform a destructive write to somebody else's library and hear the task
    // read aloud — the same title the Lock Screen widget withholds by default,
    // on a screen where Settings promises "a locked iPhone never reveals what
    // they are". Requiring authentication is the default, and it is the right
    // default for a write.
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let item = SharedTodayStore.load().items.first else {
            return .result(dialog: "You’re all clear.")
        }
        try await MainActor.run {
            let repository = SwiftDataThoughtRepository(
                modelContext: PersistenceController.shared.mainContext
            )
            try repository.performReminderAction(
                itemIDs: [item.id],
                action: .complete
            )
        }
        return .result(dialog: "Completed \(item.title).")
    }
}

/// Gives Speak It a visible, reliable landing tile on its page in Shortcuts.
/// The tile is the first action in the person's three-action capture shortcut.
struct SpeakItAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: BeginListeningIntent(),
            phrases: [
                "Capture with \(.applicationName)",
                "Remember this with \(.applicationName)"
            ],
            shortTitle: "Speak It Capture",
            systemImageName: "waveform"
        )

        AppShortcut(
            intent: SaveThoughtIntent(),
            phrases: [
                "Save a thought with \(.applicationName)",
                "Dictate to \(.applicationName)"
            ],
            shortTitle: "Dictate a Thought",
            systemImageName: "quote.bubble"
        )

        AppShortcut(
            intent: CompleteNextSpeakItItemIntent(),
            phrases: [
                "Complete my next item in \(.applicationName)",
                "Finish my next task with \(.applicationName)"
            ],
            shortTitle: "Complete Next",
            systemImageName: "checkmark.circle"
        )
    }
}

#if false
// Retained temporarily as migration history only. The shipped hardware action
// uses BeginListeningIntent's foreground route, which is the reliable iOS path.
@available(iOS 18.0, *)
@MainActor
private final class BackgroundCaptureCoordinator {
    static let shared = BackgroundCaptureCoordinator()

    private let transcriber = SpeechTranscriber(reportsAudioLevel: false)
    private var cancellables = Set<AnyCancellable>()
    private var noSpeechTimeoutTask: Task<Void, Never>?
    private var maximumDurationTask: Task<Void, Never>?
    private var transcriptUpdateTask: Task<Void, Never>?
    private var startupRetryTask: Task<Void, Never>?
    private var microphoneStartupTimeoutTask: Task<Void, Never>?
    private var startupAttemptTracker = CaptureStartupAttemptTracker()
    private var ownsCapture = false
    private var startupAttempt = 0
    private var activeDraftID: UUID?
    private var captureStartedAt: Date?
    private var isRecoveringAudio = false
    private var triggerGate = BackgroundCaptureTriggerGate()

    private init() {
        transcriber.$transcript
            .removeDuplicates()
            .sink { [weak self] transcript in
                self?.transcriptDidChange(transcript)
            }
            .store(in: &cancellables)

        transcriber.$state
            .removeDuplicates()
            .sink { [weak self] state in
                self?.stateDidChange(state)
            }
            .store(in: &cancellables)
    }

    func beginCapture() async {
        switch triggerGate.receiveTrigger() {
        case .start:
            await startCapture()
        case .refreshListening:
            await CaptureActivityManager.showListeningReady()
        case .ignoreDuplicate:
            return
        }
    }

    private func startCapture() async {
        ownsCapture = true
        isRecoveringAudio = false
        cancelTimers()
        startupAttempt = 0
        transcriber.cancel()
        let draft = CaptureDraftStore.begin()
        activeDraftID = draft.id
        captureStartedAt = draft.startedAt

        guard await CaptureActivityManager.beginListening(preparing: true) else {
            ownsCapture = false
            triggerGate.transition(to: .idle)
            CaptureActivationStore.markFailed()
            CaptureDraftStore.clear(id: activeDraftID)
            activeDraftID = nil
            captureStartedAt = nil
            return
        }

        await startTranscriberAttempt()
    }

    private func startTranscriberAttempt() async {
        guard ownsCapture else { return }

        triggerGate.transition(to: .preparing)
        let attemptID = startupAttemptTracker.begin()
        armMicrophoneStartupTimeout(for: attemptID)
        let recoveryURL = activeDraft.flatMap {
            try? CaptureDraftStore.prepareAudioURL(for: $0)
        }
        await transcriber.start(recoveryAudioURL: recoveryURL) { [weak self] finalText in
            Task { @MainActor in
                await self?.persistAndFinish(finalText)
            }
        }

        // A watchdog may have replaced this attempt while the async start was
        // suspended. In that case its completion belongs to the old attempt
        // and must not cancel or advance the newer one's timeout.
        guard startupAttemptTracker.clear(ifCurrent: attemptID) else { return }
        microphoneStartupTimeoutTask?.cancel()
        microphoneStartupTimeoutTask = nil
        guard transcriber.state == .listening else { return }
        startupAttempt = 0
        triggerGate.transition(to: .listening)
        CaptureActivationStore.markMicrophoneReady(startedAt: captureStartedAt ?? .now)
        await CaptureActivityManager.showListeningReady(alertsUser: true)
        armCaptureTimeouts()
    }

    private func armMicrophoneStartupTimeout(for attemptID: UUID) {
        microphoneStartupTimeoutTask?.cancel()
        microphoneStartupTimeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: CaptureReliabilityPolicy.microphoneStartupTimeout)
            guard !Task.isCancelled,
                  let self,
                  self.ownsCapture,
                  self.startupAttemptTracker.isCurrent(attemptID),
                  self.triggerGate.phase == .preparing else { return }

            if self.startupAttempt < CaptureReliabilityPolicy.maximumStartupAttempts - 1 {
                self.scheduleStartupRetry()
            } else {
                await self.failCapture(
                    title: "Microphone took too long",
                    detail: "Try again after unlocking your iPhone."
                )
            }
        }
    }

    private func armCaptureTimeouts() {
        noSpeechTimeoutTask?.cancel()
        maximumDurationTask?.cancel()

        noSpeechTimeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled,
                  let self,
                  self.ownsCapture,
                  self.transcriber.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return
            }
            if self.hasRecoverableActiveAudio {
                await self.recoverCapturedAudio()
            } else {
                await self.failCapture(
                    title: "I didn’t hear anything",
                    detail: "Start Speak It again when you’re ready."
                )
            }
        }

        maximumDurationTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(60))
            guard !Task.isCancelled, let self, self.ownsCapture else { return }
            let currentText = self.transcriber.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            if currentText.isEmpty {
                if self.hasRecoverableActiveAudio {
                    await self.recoverCapturedAudio()
                } else {
                    await self.failCapture(
                        title: "Nothing captured",
                        detail: "Start Speak It again when you’re ready."
                    )
                }
            } else {
                self.transcriber.stopAndFinalize { [weak self] finalText in
                    Task { @MainActor in
                        await self?.persistAndFinish(finalText)
                    }
                }
            }
        }
    }

    private func transcriptDidChange(_ transcript: String) {
        guard ownsCapture else { return }
        let normalized = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }

        noSpeechTimeoutTask?.cancel()
        noSpeechTimeoutTask = nil
        guard transcriptUpdateTask == nil else { return }
        transcriptUpdateTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled, let self, self.ownsCapture else { return }
            let latest = self.transcriber.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            if !latest.isEmpty {
                if let draftID = self.activeDraftID {
                    CaptureDraftStore.update(id: draftID, transcript: latest)
                }
                await CaptureActivityManager.updateTranscript(latest)
            }
            self.transcriptUpdateTask = nil
        }
    }

    private func stateDidChange(_ state: SpeechTranscriber.State) {
        guard ownsCapture else { return }

        if state == .finalizing {
            triggerGate.transition(to: .finalizing)
        }

        if case .failed = state, hasRecoverableActiveAudio {
            Task { @MainActor [weak self] in
                await self?.recoverCapturedAudio()
            }
            return
        }

        if state.isTransientCaptureFailure,
           startupAttempt < CaptureReliabilityPolicy.maximumStartupAttempts - 1 {
            scheduleStartupRetry()
            return
        }

        let message: (title: String, detail: String)? = switch state {
        case .permissionDenied:
            ("Voice access needed", "Open Speak It once and allow Microphone and Speech Recognition.")
        case .unavailable:
            ("Voice unavailable", "Try again in a moment, or capture inside Speak It.")
        case .failed:
            ("Couldn’t start listening", "Try again in a moment, or capture inside Speak It.")
        default:
            nil
        }

        guard let message else { return }
        Task { @MainActor [weak self] in
            await self?.failCapture(title: message.title, detail: message.detail)
        }
    }

    private func scheduleStartupRetry() {
        startupAttempt += 1
        noSpeechTimeoutTask?.cancel()
        maximumDurationTask?.cancel()
        transcriptUpdateTask?.cancel()
        noSpeechTimeoutTask = nil
        maximumDurationTask = nil
        transcriptUpdateTask = nil
        startupRetryTask?.cancel()
        microphoneStartupTimeoutTask?.cancel()
        microphoneStartupTimeoutTask = nil
        startupAttemptTracker.invalidate()
        triggerGate.transition(to: .preparing)
        transcriber.resetAfterFailure()

        let delay = CaptureReliabilityPolicy.retryDelay(afterFailedAttempt: startupAttempt)
        startupRetryTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self, self.ownsCapture else { return }
            await self.startTranscriberAttempt()
            self.startupRetryTask = nil
        }
    }

    private func persistAndFinish(_ text: String) async {
        guard ownsCapture else { return }
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            if hasRecoverableActiveAudio {
                await recoverCapturedAudio()
            } else {
                await failCapture(
                    title: "I didn’t catch that",
                    detail: "Start Speak It again and speak naturally."
                )
            }
            return
        }

        isRecoveringAudio = false
        triggerGate.transition(to: .finalizing)
        cancelTimers()
        let draftID = activeDraftID
        let createdAt = captureStartedAt ?? .now

        do {
            await CaptureActivityManager.showOrganizing(normalized)
            let result = try await ExternalCaptureWriter.save(normalized, createdAt: createdAt)
            CaptureDraftStore.clear(id: draftID)
            activeDraftID = nil
            captureStartedAt = nil
            CaptureActivationStore.markSucceeded()
            if result.needsInterpretationConfirmation {
                await CaptureActivityManager.showProblem(
                    title: "Needs clarification",
                    detail: "Open Speak It to try again or review what was saved."
                )
            } else {
                await CaptureActivityManager.showRemembered(
                    normalized,
                    context: result.confirmationContext
                )
            }
            ownsCapture = false
            triggerGate.transition(to: .idle)
        } catch {
            if let draftID {
                CaptureDraftStore.markFailed(
                    id: draftID,
                    message: "Local storage was unavailable."
                )
            }
            activeDraftID = nil
            captureStartedAt = nil
            ownsCapture = false
            triggerGate.transition(to: .idle)
            CaptureActivationStore.markFailed()
            await CaptureActivityManager.showProblem(
                title: "Recording kept",
                detail: "Open Speak It to recover your words."
            )
        }
    }

    private func failCapture(title: String, detail: String) async {
        guard ownsCapture else { return }
        ownsCapture = false
        isRecoveringAudio = false
        triggerGate.transition(to: .idle)
        CaptureActivationStore.markFailed()
        cancelTimers()
        transcriber.cancel()
        let draft = activeDraft
        let keptRecording = draft.map(CaptureDraftStore.hasRecoveryAudio(for:)) == true
        if let draft, keptRecording {
            CaptureDraftStore.markFailed(id: draft.id, message: detail)
        } else {
            CaptureDraftStore.clear(id: activeDraftID)
        }
        activeDraftID = nil
        captureStartedAt = nil
        await CaptureActivityManager.showProblem(
            title: keptRecording ? "Recording kept" : title,
            detail: keptRecording ? "Open Speak It to recover your words." : detail
        )
    }

    private var activeDraft: CaptureDraftStore.Draft? {
        guard let activeDraftID else { return nil }
        return CaptureDraftStore.draft(id: activeDraftID)
    }

    private var hasRecoverableActiveAudio: Bool {
        guard transcriber.hasDetectedAudioInput, let activeDraft else { return false }
        return CaptureDraftStore.hasRecoveryAudio(for: activeDraft)
    }

    private func recoverCapturedAudio() async {
        guard ownsCapture, !isRecoveringAudio, let draft = activeDraft else { return }
        isRecoveringAudio = true
        triggerGate.transition(to: .recovering)
        cancelTimers()
        transcriber.resetAfterFailure()
        CaptureDraftStore.markProcessing(id: draft.id)
        await CaptureActivityManager.showOrganizing("Recovering your words…")

        do {
            let recoveredText = try await CaptureAudioRecovery.transcribe(draft)
            isRecoveringAudio = false
            await persistAndFinish(recoveredText)
        } catch {
            await failCapture(
                title: "Couldn’t recover yet",
                detail: error.localizedDescription
            )
        }
    }

    private func cancelTimers() {
        noSpeechTimeoutTask?.cancel()
        maximumDurationTask?.cancel()
        transcriptUpdateTask?.cancel()
        startupRetryTask?.cancel()
        microphoneStartupTimeoutTask?.cancel()
        startupAttemptTracker.invalidate()
        noSpeechTimeoutTask = nil
        maximumDurationTask = nil
        transcriptUpdateTask = nil
        startupRetryTask = nil
        microphoneStartupTimeoutTask = nil
    }
}

private extension SpeechTranscriber.State {
    var isTransientCaptureFailure: Bool {
        switch self {
        case .unavailable, .failed:
            true
        default:
            false
        }
    }
}
#endif

@MainActor
private enum ExternalCaptureWriter {
    struct Result: Sendable {
        let confirmationContext: String
        let isDuplicate: Bool
        let needsInterpretationConfirmation: Bool
    }

    static func save(_ thought: String, createdAt: Date = .now) async throws -> Result {
        guard PersistenceController.initializationError == nil else {
            throw RepositoryError.storageUnavailable
        }
        // Clamp here rather than at each call site: everything reaching this
        // function came from another process (Shortcuts, Siri, the Action
        // Button) and cannot be assumed to be a reasonable length.
        let thought = CaptureTextLimit.clamp(thought)
        let defaults = UserDefaults.standard
        let tutorialBeganAt = defaults.double(forKey: "SpeakIt.captureSetupTestBeganAt")
        let isTutorialTest = defaults.string(forKey: FirstRunTutorialKeys.phase)
            == FirstRunTutorialPhase.readiness.rawValue
            && tutorialBeganAt > 0
            && createdAt.timeIntervalSince1970 - tutorialBeganAt < 30 * 60
        guard isTutorialTest || SubscriptionStore.canCreateBackgroundCapture(now: createdAt) else {
            throw CaptureAccessError.freeLimitReached
        }

        let repository = SwiftDataThoughtRepository(
            modelContext: PersistenceController.shared.mainContext
        )
        let capture = try await repository.createCaptureResult(
            text: thought,
            source: isTutorialTest ? .tutorial : .shortcut,
            createdAt: createdAt,
            // The outside-the-app path awaits and verifies one schedule below.
            // Avoid a second asynchronous scheduler racing the verified request.
            schedulesReminders: false
        )
        if capture.createdNewCapture, !isTutorialTest {
            SubscriptionStore.recordBackgroundCapture(now: createdAt)
        }

        if isTutorialTest {
            return Result(
                confirmationContext: "Practice test · free captures untouched",
                isDuplicate: capture.isDuplicate,
                needsInterpretationConfirmation: capture.needsInterpretationConfirmation
            )
        }

        let confirmationContext: String
        if capture.isDuplicate {
            return Result(
                confirmationContext: "Already captured",
                isDuplicate: true,
                needsInterpretationConfirmation: capture.needsInterpretationConfirmation
            )
        }
        let requests = capture.items.compactMap(ReminderScheduleRequest.init(item:))
        if !requests.isEmpty {
            let schedulingResults = await ReminderScheduler.synchronizeAndVerify(
                requests,
                requestAuthorizationIfNeeded: true
            )
            if schedulingResults.allSatisfy({ $0 == .scheduled }) {
                confirmationContext = capture.itemCount == 1
                    ? ReminderScheduler.confirmationContext(for: capture.primaryItem)
                    : multiItemContext(for: capture)
            } else if schedulingResults.contains(.denied) {
                confirmationContext = "Reminders are off in Settings"
            } else if schedulingResults.contains(.needsPermission) {
                confirmationContext = "Reminder needs permission"
            } else {
                confirmationContext = "Reminder couldn’t be scheduled"
            }
        } else {
            confirmationContext = capture.itemCount == 1
                ? ReminderScheduler.confirmationContext(for: capture.primaryItem)
                : multiItemContext(for: capture)
        }

        return Result(
            confirmationContext: confirmationContext,
            isDuplicate: false,
            needsInterpretationConfirmation: capture.needsInterpretationConfirmation
        )
    }

    private static func multiItemContext(for capture: CaptureCreationResult) -> String {
        capture.receiptContext
    }
}
