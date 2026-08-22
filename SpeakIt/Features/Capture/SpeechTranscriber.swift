import Accelerate
import AVFoundation
import Combine
import Speech
import SwiftUI
import os

@MainActor
final class SpeechTranscriber: ObservableObject {
    enum State: Equatable {
        case idle
        case requestingPermission
        case listening
        case finalizing
        case permissionDenied
        case unavailable
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var transcript = ""
    @Published private(set) var audioLevel: CGFloat = 0
    @Published private(set) var hasDetectedAudioInput = false
    private(set) var speechEndpointDetectedAt: CapturePerformanceClock.Instant?
    private(set) var finalTranscriptAt: CapturePerformanceClock.Instant?

    var lastVoiceActivityAt: CapturePerformanceClock.Instant? {
        audioActivityTracker.lastVoiceActivityAt
    }

    private let reportsAudioLevel: Bool
    private let audioActivityTracker = AudioActivityTracker()
    private let audioEngine = AVAudioEngine()
    private var recognitionBackend: (any SpeechRecognitionBackend)?
    private var naturalPauseTask: Task<Void, Never>?
    private var finalizationTimeout: Task<Void, Never>?
    private var audioSessionCancellables = Set<AnyCancellable>()
    private var finalization: ((String) -> Void)?
    private var automaticFinalization: ((String) -> Void)?
    private var hasInstalledTap = false
    private var recoveryAudioFile: AVAudioFile?
    private var activeStartID: UUID?

    private static let completeThoughtPauseMilliseconds = 2_100
    private static let incompleteThoughtPauseMilliseconds = 3_400
    private static let finalizationGracePeriod = Duration.milliseconds(700)

    var isListening: Bool { state == .listening }

    init(reportsAudioLevel: Bool = true) {
        self.reportsAudioLevel = reportsAudioLevel
        observeAudioSessionChanges()
    }

    func start(
        recoveryAudioURL: URL? = nil,
        onAutomaticFinalization: @escaping (String) -> Void
    ) async {
        guard state != .requestingPermission, state != .listening else { return }

        let startID = UUID()
        activeStartID = startID
        state = .requestingPermission
        transcript = ""
        audioLevel = 0
        hasDetectedAudioInput = false
        audioActivityTracker.reset()
        speechEndpointDetectedAt = nil
        finalTranscriptAt = nil
        automaticFinalization = onAutomaticFinalization

        let speechAuthorization = await requestSpeechAuthorization()
        guard activeStartID == startID else { return }
        let microphoneGranted = await requestMicrophoneAuthorization()
        guard activeStartID == startID else { return }

        guard speechAuthorization == .authorized, microphoneGranted else {
            activeStartID = nil
            automaticFinalization = nil
            state = .permissionDenied
            return
        }

        do {
            resetRecognitionResources()

            let audioSession = AVAudioSession.sharedInstance()
            // Recording is intentionally exclusive. Mixing or ducking lets a
            // Reel, podcast, or song leak into transcription; activating a
            // plain record session asks iOS to interrupt that other audio.
            try audioSession.setCategory(.record, mode: .measurement, options: [])
            try audioSession.setActive(true)

            let inputNode = audioEngine.inputNode
            let format = inputNode.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else {
                throw SpeechCaptureError.invalidAudioInput
            }

            let backend = try await Self.makeStartedBackend(
                inputFormat: format,
                onTranscript: { [weak self] text, isFinal in
                    self?.receiveTranscript(text, isFinal: isFinal)
                },
                onError: { [weak self] error in
                    self?.receiveError(error)
                }
            )
            guard activeStartID == startID else {
                backend.cancel()
                resetRecognitionResources()
                return
            }
            recognitionBackend = backend

            let recoveryFile: AVAudioFile?
            if let recoveryAudioURL {
                recoveryFile = try AVAudioFile(
                    forWriting: recoveryAudioURL,
                    settings: format.settings
                )
                recoveryAudioFile = recoveryFile
                CaptureDraftStore.protectAudio(at: recoveryAudioURL)
            } else {
                recoveryFile = nil
            }
            let levelGate = AudioLevelUpdateGate()
            let activityTracker = audioActivityTracker
            let publishesAudioLevel = reportsAudioLevel

            inputNode.installTap(onBus: 0, bufferSize: 2_048, format: format) { [weak self] buffer, _ in
                backend.append(buffer)
                try? recoveryFile?.write(from: buffer)
                guard let level = Self.normalizedLevel(from: buffer) else { return }
                if level > 0.012 {
                    // Record directly on the audio callback, before the 12 Hz UI
                    // throttle or a MainActor hop can shift the apparent final
                    // voice frame later in time.
                    activityTracker.recordVoiceActivity(at: CapturePerformanceClock.now)
                }
                guard levelGate.shouldPublish(
                    level: level,
                    publishesAudioLevel: publishesAudioLevel
                ) else { return }
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if level > 0.012 {
                        hasDetectedAudioInput = true
                    }
                    if reportsAudioLevel {
                        audioLevel = audioLevel * 0.68 + level * 0.32
                    }
                }
            }
            hasInstalledTap = true

            audioEngine.prepare()
            try audioEngine.start()
            guard activeStartID == startID else {
                resetRecognitionResources()
                return
            }
            activeStartID = nil
            state = .listening
        } catch SpeechRecognitionBackendError.recognizerUnavailable {
            guard activeStartID == startID else { return }
            activeStartID = nil
            resetRecognitionResources()
            automaticFinalization = nil
            state = .unavailable
        } catch {
            guard activeStartID == startID else { return }
            activeStartID = nil
            resetRecognitionResources()
            automaticFinalization = nil
            state = .failed(error.localizedDescription)
        }
    }

    /// Prefers the higher-accuracy on-device SpeechAnalyzer engine when iOS 26
    /// and its language model are available, falling back to the legacy
    /// recognizer so capture always works — including while the analyzer's
    /// model is still downloading in the background.
    private static func makeStartedBackend(
        inputFormat: AVAudioFormat,
        onTranscript: @escaping @MainActor (String, Bool) -> Void,
        onError: @escaping @MainActor (Error) -> Void
    ) async throws -> any SpeechRecognitionBackend {
        if #available(iOS 26.0, *), await AnalyzerRecognitionSupport.isReady() {
            let analyzerBackend = AnalyzerRecognitionBackend(inputFormat: inputFormat)
            do {
                try await analyzerBackend.start(onTranscript: onTranscript, onError: onError)
                return analyzerBackend
            } catch {
                analyzerBackend.cancel()
            }
        }

        guard let legacyBackend = LegacyRecognizerBackend() else {
            throw SpeechRecognitionBackendError.recognizerUnavailable
        }
        try await legacyBackend.start(onTranscript: onTranscript, onError: onError)
        return legacyBackend
    }

    func stopAndFinalize(_ completion: @escaping (String) -> Void) {
        guard state == .listening else { return }
        beginFinalization(completion)
    }

    func cancel() {
        activeStartID = nil
        naturalPauseTask?.cancel()
        finalizationTimeout?.cancel()
        finalization = nil
        automaticFinalization = nil
        resetRecognitionResources()
        transcript = ""
        audioLevel = 0
        hasDetectedAudioInput = false
        audioActivityTracker.reset()
        speechEndpointDetectedAt = nil
        finalTranscriptAt = nil
        state = .idle
    }

    func resetAfterFailure() {
        activeStartID = nil
        automaticFinalization = nil
        resetRecognitionResources()
        state = .idle
    }

    private func receiveTranscript(_ text: String, isFinal: Bool) {
        guard state == .listening || state == .finalizing else { return }

        transcript = SpeechVocabularyStore.apply(to: text)
        let hasWords = !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        if isFinal {
            if state == .finalizing {
                completeFinalization()
            } else if hasWords, let automaticFinalization {
                beginFinalization(automaticFinalization)
            }
            return
        }

        if state == .listening, hasWords {
            scheduleNaturalPauseFinish()
        }
    }

    private func receiveError(_ error: Error) {
        guard state == .listening || state == .finalizing else { return }

        switch Self.failureResolution(
            isFinalizing: state == .finalizing,
            hasTranscript: !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            hasRecoveryRecording: recoveryAudioFile != nil && hasDetectedAudioInput
        ) {
        case .finalizeTranscript:
            if state == .finalizing {
                completeFinalization()
            } else if let automaticFinalization {
                finalization = automaticFinalization
                markSpeechEndpointDetectedIfNeeded()
                state = .finalizing
                completeFinalization()
            }
        case .recoverRecording, .reportFailure:
            resetRecognitionResources()
            automaticFinalization = nil
            state = .failed(error.localizedDescription)
        }
    }

    enum FailureResolution: Equatable {
        case finalizeTranscript
        case recoverRecording
        case reportFailure
    }

    nonisolated static func failureResolution(
        isFinalizing: Bool,
        hasTranscript: Bool,
        hasRecoveryRecording: Bool
    ) -> FailureResolution {
        if isFinalizing, hasTranscript { return .finalizeTranscript }
        if hasRecoveryRecording { return .recoverRecording }
        if hasTranscript { return .finalizeTranscript }
        return .reportFailure
    }

    nonisolated static func shouldStopForRouteChange(
        _ reason: AVAudioSession.RouteChangeReason
    ) -> Bool {
        switch reason {
        case .oldDeviceUnavailable, .noSuitableRouteForCategory:
            true
        default:
            false
        }
    }

    private func scheduleNaturalPauseFinish() {
        naturalPauseTask?.cancel()
        let delay = Self.naturalPauseDuration(for: transcript)
        naturalPauseTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self, state == .listening else { return }
            guard !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let automaticFinalization else { return }
            beginFinalization(automaticFinalization)
        }
    }

    /// A longer adaptive pause lets somebody breathe between several thoughts
    /// while keeping a short single capture feeling immediate.
    static func naturalPauseDuration(for transcript: String) -> Duration {
        let normalized = transcript
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let continuationPattern = #"(?:\b(?:and|also|then|plus|because|but|or|first|second|third)|one\s+more\s+thing|remind\s+me\s+to|i\s+need\s+to)\s*[,;:-]?$"#
        let looksIncomplete = normalized.range(
            of: continuationPattern,
            options: .regularExpression
        ) != nil
        return .milliseconds(
            looksIncomplete
                ? incompleteThoughtPauseMilliseconds
                : completeThoughtPauseMilliseconds
        )
    }

    private func beginFinalization(_ completion: @escaping (String) -> Void) {
        guard state == .listening else { return }

        naturalPauseTask?.cancel()
        markSpeechEndpointDetectedIfNeeded()
        state = .finalizing
        finalization = completion
        stopAudioInput()
        recognitionBackend?.endAudio()

        finalizationTimeout?.cancel()
        finalizationTimeout = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.finalizationGracePeriod)
            guard !Task.isCancelled else { return }
            self?.completeFinalization()
        }
    }

    private func completeFinalization() {
        guard state == .finalizing else { return }
        finalizationTimeout?.cancel()
        markSpeechEndpointDetectedIfNeeded()
        finalTranscriptAt = CapturePerformanceClock.now
        let completion = finalization
        let finalText = transcript
        finalization = nil
        automaticFinalization = nil
        resetRecognitionResources()
        state = .idle
        completion?(finalText)
    }

    private func markSpeechEndpointDetectedIfNeeded() {
        guard speechEndpointDetectedAt == nil else { return }
        speechEndpointDetectedAt = CapturePerformanceClock.now
        audioActivityTracker.finishEndpointDetection()
    }

    private func stopAudioInput() {
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        if hasInstalledTap {
            audioEngine.inputNode.removeTap(onBus: 0)
            hasInstalledTap = false
        }
        recoveryAudioFile = nil
        audioLevel = 0
    }

    private func resetRecognitionResources() {
        naturalPauseTask?.cancel()
        naturalPauseTask = nil
        stopAudioInput()
        recognitionBackend?.cancel()
        recognitionBackend = nil
        // Don't automatically restart interrupted media after saving. The
        // person can resume it when they are ready, without it competing with
        // the Remembered confirmation.
        try? AVAudioSession.sharedInstance().setActive(false)
    }

    private func observeAudioSessionChanges() {
        let center = NotificationCenter.default

        center.publisher(for: AVAudioSession.interruptionNotification)
            .sink { [weak self] notification in
                Task { @MainActor [weak self] in
                    self?.handleAudioInterruption(notification)
                }
            }
            .store(in: &audioSessionCancellables)

        center.publisher(for: AVAudioSession.routeChangeNotification)
            .sink { [weak self] notification in
                Task { @MainActor [weak self] in
                    self?.handleAudioRouteChange(notification)
                }
            }
            .store(in: &audioSessionCancellables)

        center.publisher(for: AVAudioSession.mediaServicesWereResetNotification)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.failForAudioEnvironmentChange(
                        "The iPhone audio service restarted."
                    )
                }
            }
            .store(in: &audioSessionCancellables)
    }

    private func handleAudioInterruption(_ notification: Notification) {
        guard let rawValue = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              AVAudioSession.InterruptionType(rawValue: rawValue) == .began else {
            return
        }
        failForAudioEnvironmentChange("Recording was interrupted by another audio session.")
    }

    private func handleAudioRouteChange(_ notification: Notification) {
        guard let rawValue = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: rawValue),
              Self.shouldStopForRouteChange(reason) else {
            return
        }
        failForAudioEnvironmentChange("The microphone route changed during capture.")
    }

    private func failForAudioEnvironmentChange(_ message: String) {
        guard state == .listening || state == .finalizing else { return }

        if state == .finalizing,
           !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            completeFinalization()
            return
        }

        finalization = nil
        automaticFinalization = nil
        resetRecognitionResources()
        state = .failed(message)
    }

    private func requestSpeechAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        let currentStatus = SFSpeechRecognizer.authorizationStatus()
        guard currentStatus == .notDetermined else { return currentStatus }

        return await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }

    private func requestMicrophoneAuthorization() async -> Bool {
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            return true
        case .denied:
            return false
        case .undetermined:
            return await withCheckedContinuation { continuation in
                AVAudioApplication.requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        @unknown default:
            return false
        }
    }

    private nonisolated static func normalizedLevel(from buffer: AVAudioPCMBuffer) -> CGFloat? {
        guard let channelData = buffer.floatChannelData?.pointee else { return nil }
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return nil }

        var rms: Float = 0
        vDSP_rmsqv(channelData, 1, &rms, vDSP_Length(frameLength))
        let decibels = 20 * log10(max(rms, 0.000_001))
        return CGFloat(min(max((decibels + 52) / 52, 0), 1))
    }
}

private final class AudioLevelUpdateGate: @unchecked Sendable {
    private let lock = NSLock()
    private var lastPublishTime: TimeInterval = 0
    private var hasPublishedDetection = false

    func shouldPublish(level: CGFloat, publishesAudioLevel: Bool) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        let detectedForFirstTime = level > 0.012 && !hasPublishedDetection
        if detectedForFirstTime { hasPublishedDetection = true }

        let now = ProcessInfo.processInfo.systemUptime
        let levelRefreshIsDue = publishesAudioLevel && now - lastPublishTime >= 1.0 / 12.0
        if levelRefreshIsDue { lastPublishTime = now }
        return detectedForFirstTime || levelRefreshIsDue
    }
}

private final class AudioActivityTracker: @unchecked Sendable {
    private let lock = NSLock()
    private var recordedLastVoiceActivityAt: CapturePerformanceClock.Instant?
    private var endpointCandidateState: OSSignpostIntervalState?

    var lastVoiceActivityAt: CapturePerformanceClock.Instant? {
        lock.lock()
        defer { lock.unlock() }
        return recordedLastVoiceActivityAt
    }

    func recordVoiceActivity(at instant: CapturePerformanceClock.Instant) {
        lock.lock()
        CapturePerformanceSignposts.endSpeechEndpointCandidate(endpointCandidateState)
        recordedLastVoiceActivityAt = instant
        endpointCandidateState = CapturePerformanceSignposts.beginSpeechEndpointCandidate()
        lock.unlock()
    }

    func finishEndpointDetection() {
        lock.lock()
        let candidate = endpointCandidateState
        endpointCandidateState = nil
        lock.unlock()
        CapturePerformanceSignposts.endSpeechEndpointCandidate(candidate)
    }

    func reset() {
        lock.lock()
        let candidate = endpointCandidateState
        recordedLastVoiceActivityAt = nil
        endpointCandidateState = nil
        lock.unlock()
        CapturePerformanceSignposts.endSpeechEndpointCandidate(candidate)
    }
}

/// Reprocesses the protected temporary recording when live recognition fails.
/// It intentionally uses the same system recognizer and vocabulary corrections
/// as normal capture, keeping recovery local to the app's existing speech path.
enum CaptureAudioRecovery {
    static func transcribe(_ draft: CaptureDraftStore.Draft) async throws -> String {
        guard let url = await CaptureDraftStore.audioURL(for: draft),
              await CaptureDraftStore.hasRecoveryAudio(for: draft) else {
            throw CaptureAudioRecoveryError.missingRecording
        }
        return try await transcribeAudio(at: url)
    }

    static func transcribeAudio(at url: URL) async throws -> String {
        guard SFSpeechRecognizer.authorizationStatus() == .authorized else {
            throw CaptureAudioRecoveryError.permissionRequired
        }
        guard let recognizer = SFSpeechRecognizer(locale: .current), recognizer.isAvailable else {
            throw CaptureAudioRecoveryError.recognizerUnavailable
        }

        let request = SFSpeechURLRecognitionRequest(url: url)
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        request.contextualStrings = SpeechVocabularyStore.contextualPhrases
        request.requiresOnDeviceRecognition = false

        let completion = AudioRecoveryCompletion()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                completion.install(continuation)
                let task = recognizer.recognitionTask(with: request) { result, error in
                    if let result {
                        let text = SpeechVocabularyStore.apply(
                            to: result.bestTranscription.formattedString
                        )
                        completion.updateLatest(text)
                        if result.isFinal {
                            completion.finish(with: .success(text))
                            return
                        }
                    }

                    if let error {
                        if let latest = completion.latestNonemptyTranscript {
                            completion.finish(with: .success(latest))
                        } else {
                            completion.finish(with: .failure(error))
                        }
                    }
                }
                completion.setRecognitionTask(task)

                let timeoutTask = Task {
                    try? await Task.sleep(for: .seconds(25))
                    guard !Task.isCancelled else { return }
                    if let latest = completion.latestNonemptyTranscript {
                        completion.finish(with: .success(latest))
                    } else {
                        completion.finish(with: .failure(CaptureAudioRecoveryError.timedOut))
                    }
                }
                completion.setTimeoutTask(timeoutTask)
            }
        } onCancel: {
            completion.finish(with: .failure(CancellationError()))
        }
    }
}

private final class AudioRecoveryCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<String, Error>?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var timeoutTask: Task<Void, Never>?
    private var latestTranscript = ""
    private var didFinish = false

    var latestNonemptyTranscript: String? {
        lock.lock()
        defer { lock.unlock() }
        let normalized = latestTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }

    func install(_ continuation: CheckedContinuation<String, Error>) {
        lock.lock()
        self.continuation = continuation
        let alreadyFinished = didFinish
        lock.unlock()
        if alreadyFinished {
            continuation.resume(throwing: CaptureAudioRecoveryError.cancelled)
        }
    }

    func setRecognitionTask(_ task: SFSpeechRecognitionTask) {
        lock.lock()
        if didFinish {
            lock.unlock()
            task.cancel()
        } else {
            recognitionTask = task
            lock.unlock()
        }
    }

    func setTimeoutTask(_ task: Task<Void, Never>) {
        lock.lock()
        if didFinish {
            lock.unlock()
            task.cancel()
        } else {
            timeoutTask = task
            lock.unlock()
        }
    }

    func updateLatest(_ text: String) {
        lock.lock()
        latestTranscript = text
        lock.unlock()
    }

    func finish(with result: Result<String, Error>) {
        lock.lock()
        guard !didFinish else {
            lock.unlock()
            return
        }
        didFinish = true
        let continuation = continuation
        self.continuation = nil
        let task = recognitionTask
        recognitionTask = nil
        let timeout = timeoutTask
        timeoutTask = nil
        lock.unlock()

        task?.cancel()
        timeout?.cancel()
        continuation?.resume(with: result)
    }
}

private enum SpeechCaptureError: LocalizedError {
    case invalidAudioInput

    var errorDescription: String? {
        "Speak It couldn’t access a valid microphone input."
    }
}

private enum CaptureAudioRecoveryError: LocalizedError, CaptureRecoveryFailureDescribing {
    case missingRecording
    case permissionRequired
    case recognizerUnavailable
    case timedOut
    case cancelled

    var errorDescription: String? {
        switch self {
        case .missingRecording:
            "The temporary recording is no longer available."
        case .permissionRequired:
            "Speech Recognition access is needed to recover this recording."
        case .recognizerUnavailable:
            "Speech Recognition is temporarily unavailable."
        case .timedOut:
            "Recovery took too long. Your recording is still safe."
        case .cancelled:
            "Recovery was cancelled."
        }
    }

    var captureRecoveryFailureKind: CaptureRecoveryFailureKind {
        switch self {
        case .missingRecording: .missingRecording
        case .permissionRequired: .permissionRequired
        case .recognizerUnavailable: .recognizerUnavailable
        case .timedOut: .timedOut
        case .cancelled: .cancelled
        }
    }
}
