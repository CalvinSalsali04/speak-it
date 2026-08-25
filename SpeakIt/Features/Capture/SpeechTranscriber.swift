import Accelerate
import AVFoundation
import Combine
import Speech
import SwiftUI
import os

enum SpeechCaptureAudioProfile: String, CaseIterable, Codable, Identifiable, Sendable {
    case spokenAudio = "spoken_audio"
    case measurement
    case voiceProcessed = "voice_processed"

    static let selectionDefaultsKey = "SpeakIt.debug.speechAudioProfile"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .spokenAudio: "Spoken audio"
        case .measurement: "Raw measurement"
        case .voiceProcessed: "Voice processed"
        }
    }

    static var selected: Self {
#if DEBUG
        if let argument = ProcessInfo.processInfo.arguments.first(
            where: { $0.hasPrefix("--speech-audio-profile=") }
        ), let rawValue = argument.split(separator: "=").last,
           let profile = Self(rawValue: String(rawValue)) {
            return profile
        }
        if let stored = UserDefaults.standard.string(forKey: selectionDefaultsKey),
           let profile = Self(rawValue: stored) {
            return profile
        }
#endif
        // Apple uses spokenAudio in its SpeechAnalyzer sample. Unlike
        // measurement mode, it does not explicitly minimize speech-oriented
        // dynamics, making it the safer production baseline for quiet voices.
        return .spokenAudio
    }
}

struct SpeechCaptureAudioQuality: Codable, Equatable, Sendable {
    let rmsDecibels: Double
    let peakDecibels: Double
    let clippedSampleFraction: Double
    let durationMilliseconds: Int
    let profile: SpeechCaptureAudioProfile
    let recognitionEngine: SpeechRecognitionEngine?

    var isVeryQuiet: Bool { rmsDecibels < -42 }
    var isLikelyClipped: Bool { clippedSampleFraction >= 0.005 }
}

enum SpeechCaptureDiagnosticsStore {
    private static let key = "SpeakIt.debug.lastSpeechCaptureQuality"

    static var latest: SpeechCaptureAudioQuality? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(SpeechCaptureAudioQuality.self, from: data)
    }

    static func save(_ quality: SpeechCaptureAudioQuality) {
        guard let data = try? JSONEncoder().encode(quality) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}

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
    @Published private(set) var isWaitingForContinuation = false
    @Published private(set) var isPreparingEnhancedRecognition = false
    private(set) var speechEndpointDetectedAt: CapturePerformanceClock.Instant?
    private(set) var finalTranscriptAt: CapturePerformanceClock.Instant?
    private(set) var lastAudioQuality: SpeechCaptureAudioQuality?
    private(set) var recognitionEngine: SpeechRecognitionEngine?

    var lastVoiceActivityAt: CapturePerformanceClock.Instant? {
        audioActivityTracker.lastVoiceActivityAt
    }

    private let reportsAudioLevel: Bool
    private let audioActivityTracker = AudioActivityTracker()
    private let audioQualityTracker = AudioQualityTracker()
    private let audioEngine = AVAudioEngine()
    private var recognitionBackend: (any SpeechRecognitionBackend)?
    private var audioProcessor: SpeechCaptureAudioProcessor?
    private var naturalPauseTask: Task<Void, Never>?
    private var lastEndpointingSignature = ""
    private var audioInputReadyTimeout: Task<Void, Never>?
    private var finalizationTimeout: Task<Void, Never>?
    private var audioSessionCancellables = Set<AnyCancellable>()
    private var finalization: ((String) -> Void)?
    private var automaticFinalization: ((String) -> Void)?
    private var hasInstalledTap = false
    private var recoveryAudioFile: AVAudioFile?
    private var activeStartID: UUID?
    private var audioProfile = SpeechCaptureAudioProfile.spokenAudio

    private static let completeThoughtPauseMilliseconds = 1_100
    private static let continuationPromptPauseMilliseconds = 2_100
    private static let ambiguousThoughtPauseMilliseconds = 4_000
    private static let incompleteThoughtPauseMilliseconds = 8_000
    private static let maximumAudioActivityDeferrals = 2
    private static let audioInputReadyGracePeriod = Duration.seconds(3)
    private static let finalizationGracePeriod = Duration.seconds(2)

    struct NaturalPauseDecision: Equatable {
        let promptAfter: Duration?
        let finishAfter: Duration
    }

    var isListening: Bool { state == .listening }

    init(reportsAudioLevel: Bool = true) {
        self.reportsAudioLevel = reportsAudioLevel
        observeAudioSessionChanges()
    }

    /// Starts the system-owned iOS 26 model installation without opening the
    /// microphone. Onboarding calls this as soon as the person chooses voice,
    /// giving the download a head start before their first tap to record.
    @discardableResult
    static func prepareEnhancedRecognition() async -> Bool {
        guard #available(iOS 26.0, *) else { return false }
        return await AnalyzerRecognitionSupport.prepareForHighAccuracyCapture()
    }

    func start(
        recoveryAudioURL: URL? = nil,
        contextualPhrases: [String] = [],
        prefersEnhancedRecognition: Bool = false,
        forcesLegacyRecognitionForBenchmark: Bool = false,
        onAutomaticFinalization: @escaping (String) -> Void
    ) async {
        guard state != .requestingPermission, state != .listening else { return }

        let startID = UUID()
        activeStartID = startID
        state = .requestingPermission
        transcript = ""
        audioLevel = 0
        hasDetectedAudioInput = false
        isWaitingForContinuation = false
        isPreparingEnhancedRecognition = false
        audioActivityTracker.reset()
        audioQualityTracker.reset()
        lastAudioQuality = nil
        recognitionEngine = nil
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
            audioProfile = SpeechCaptureAudioProfile.selected
            try Self.configureAudioSession(audioSession, profile: audioProfile)
            try audioSession.setActive(true)

            let inputNode = audioEngine.inputNode
            let enablesVoiceProcessing = audioProfile == .voiceProcessed
            if inputNode.isVoiceProcessingEnabled != enablesVoiceProcessing {
                try inputNode.setVoiceProcessingEnabled(enablesVoiceProcessing)
            }
            let format = inputNode.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else {
                throw SpeechCaptureError.invalidAudioInput
            }

            isPreparingEnhancedRecognition = prefersEnhancedRecognition
            let backend = try await Self.makeStartedBackend(
                inputFormat: format,
                contextualPhrases: SpeechVocabularyStore.recognitionContext(
                    additional: contextualPhrases
                ),
                prefersEnhancedRecognition: prefersEnhancedRecognition,
                forcesLegacyRecognitionForBenchmark: forcesLegacyRecognitionForBenchmark,
                onTranscript: { [weak self] text, isFinal in
                    self?.receiveTranscript(text, isFinal: isFinal)
                },
                onVoiceActivity: { [weak self] in
                    self?.receiveVoiceActivity()
                },
                onError: { [weak self] error in
                    self?.receiveError(error)
                }
            )
            isPreparingEnhancedRecognition = false
            guard activeStartID == startID else {
                backend.cancel()
                resetRecognitionResources()
                return
            }
            recognitionBackend = backend
            recognitionEngine = backend.engine

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
            let qualityTracker = audioQualityTracker
            let publishesAudioLevel = reportsAudioLevel
            let firstBufferGate = FirstAudioBufferGate()
            let usesTrainedVoiceActivityDetection = backend.usesTrainedVoiceActivityDetection

            // Core Audio's tap is a real-time callback. Keep it limited to one
            // bounded memory copy plus cheap level metering: conversion, the
            // recognizer append, recovery-file I/O, and quality analysis run in
            // order on a dedicated queue. Draining that queue before endAudio
            // also guarantees the recognizer receives the final microphone
            // buffer before it is asked to finalize.
            let audioProcessor = SpeechCaptureAudioProcessor(
                process: { buffer in
                    backend.append(buffer)
                    try? recoveryFile?.write(from: buffer)
                    qualityTracker.record(buffer)
                },
                onFirstBufferProcessed: { [weak self] in
                    guard firstBufferGate.markReady() else { return }
                    Task { @MainActor [weak self] in
                        self?.markAudioInputReady(startID: startID)
                    }
                }
            )
            self.audioProcessor = audioProcessor

            inputNode.installTap(onBus: 0, bufferSize: 2_048, format: format) { [weak self] buffer, _ in
                audioProcessor.append(buffer)
                guard let level = Self.normalizedLevel(from: buffer) else { return }
                if level > 0.012, !usesTrainedVoiceActivityDetection {
                    // Record directly on the audio callback, before the 12 Hz UI
                    // throttle or a MainActor hop can shift the apparent final
                    // voice frame later in time. iOS 26 uses SpeechDetector
                    // instead so fans and traffic do not masquerade as speech.
                    activityTracker.recordVoiceActivity(at: CapturePerformanceClock.now)
                }
                guard levelGate.shouldPublish(
                    level: level,
                    publishesAudioLevel: publishesAudioLevel
                ) else { return }
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    guard state == .requestingPermission
                            || state == .listening
                            || state == .finalizing else { return }
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
            audioInputReadyTimeout?.cancel()
            audioInputReadyTimeout = Task { @MainActor [weak self] in
                try? await Task.sleep(for: Self.audioInputReadyGracePeriod)
                guard !Task.isCancelled,
                      let self,
                      activeStartID == startID else { return }
                activeStartID = nil
                automaticFinalization = nil
                resetRecognitionResources()
                state = .failed("The microphone did not begin delivering audio.")
            }
        } catch SpeechRecognitionBackendError.recognizerUnavailable {
            guard activeStartID == startID else { return }
            activeStartID = nil
            isPreparingEnhancedRecognition = false
            resetRecognitionResources()
            automaticFinalization = nil
            state = .unavailable
        } catch {
            guard activeStartID == startID else { return }
            activeStartID = nil
            isPreparingEnhancedRecognition = false
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
        contextualPhrases: [String],
        prefersEnhancedRecognition: Bool,
        forcesLegacyRecognitionForBenchmark: Bool,
        onTranscript: @escaping @MainActor (String, Bool) -> Void,
        onVoiceActivity: @escaping @MainActor () -> Void,
        onError: @escaping @MainActor (Error) -> Void
    ) async throws -> any SpeechRecognitionBackend {
        let analyzerIsReady: Bool
        if forcesLegacyRecognitionForBenchmark {
            analyzerIsReady = false
        } else if #available(iOS 26.0, *) {
            analyzerIsReady = prefersEnhancedRecognition
                ? await AnalyzerRecognitionSupport.prepareForHighAccuracyCapture()
                : await AnalyzerRecognitionSupport.isReady()
        } else {
            analyzerIsReady = false
        }

        if #available(iOS 26.0, *), analyzerIsReady {
            let analyzerBackend = AnalyzerRecognitionBackend(inputFormat: inputFormat)
            do {
                try await analyzerBackend.start(
                    contextualPhrases: contextualPhrases,
                    onTranscript: onTranscript,
                    onVoiceActivity: onVoiceActivity,
                    onError: onError
                )
                return analyzerBackend
            } catch {
                analyzerBackend.cancel()
            }
        }

        guard let legacyBackend = LegacyRecognizerBackend() else {
            throw SpeechRecognitionBackendError.recognizerUnavailable
        }
        try await legacyBackend.start(
            contextualPhrases: contextualPhrases,
            onTranscript: onTranscript,
            onVoiceActivity: onVoiceActivity,
            onError: onError
        )
        return legacyBackend
    }

    func stopAndFinalize(_ completion: @escaping (String) -> Void) {
        guard state == .listening else { return }
        beginFinalization(completion)
    }

    func cancel() {
        activeStartID = nil
        naturalPauseTask?.cancel()
        audioInputReadyTimeout?.cancel()
        finalizationTimeout?.cancel()
        finalization = nil
        automaticFinalization = nil
        resetRecognitionResources()
        transcript = ""
        audioLevel = 0
        hasDetectedAudioInput = false
        isWaitingForContinuation = false
        isPreparingEnhancedRecognition = false
        audioActivityTracker.reset()
        speechEndpointDetectedAt = nil
        finalTranscriptAt = nil
        state = .idle
    }

    func resetAfterFailure() {
        activeStartID = nil
        automaticFinalization = nil
        isWaitingForContinuation = false
        isPreparingEnhancedRecognition = false
        resetRecognitionResources()
        state = .idle
    }

    private func markAudioInputReady(startID: UUID) {
        guard state == .requestingPermission, activeStartID == startID else { return }
        audioInputReadyTimeout?.cancel()
        audioInputReadyTimeout = nil
        activeStartID = nil
        state = .listening
    }

    private func receiveVoiceActivity() {
        guard state == .requestingPermission || state == .listening || state == .finalizing else {
            return
        }
        audioActivityTracker.recordVoiceActivity(at: CapturePerformanceClock.now)
        hasDetectedAudioInput = true
    }

    private func receiveTranscript(_ text: String, isFinal: Bool) {
        guard state == .requestingPermission || state == .listening || state == .finalizing else {
            return
        }

        transcript = SpeechVocabularyStore.apply(to: text)
        let hasWords = !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let endpointingSignature = Self.endpointingSignature(for: transcript)
        let hasLexicalContent = !endpointingSignature.isEmpty
        let endpointingContentChanged = endpointingSignature != lastEndpointingSignature

        if state == .listening, endpointingContentChanged {
            lastEndpointingSignature = endpointingSignature
            isWaitingForContinuation = false
            if !hasLexicalContent {
                naturalPauseTask?.cancel()
                naturalPauseTask = nil
            }
        }

        if isFinal {
            if state == .finalizing {
                completeFinalization()
            } else if hasWords, let automaticFinalization {
                beginFinalization(automaticFinalization)
            }
            return
        }

        // Partial ASR commonly restyles capitalization or punctuation after a
        // pause. Those are not new speech and must not restart the endpoint
        // timer or dismiss an already-visible continuation cue. Lexical
        // additions, deletions, and substitutions still cancel and reclassify.
        if state == .listening,
           hasLexicalContent,
           endpointingContentChanged || naturalPauseTask == nil {
            scheduleNaturalPauseFinish()
        }
    }

    private func receiveError(_ error: Error) {
        guard state == .requestingPermission || state == .listening || state == .finalizing else {
            return
        }

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
        isWaitingForContinuation = false
        let decision = Self.naturalPauseDecision(for: transcript)
        let scheduledAt = CapturePerformanceClock.now
        naturalPauseTask = Task { @MainActor [weak self] in
            guard let self else { return }
            var pauseBeganAt = max(lastVoiceActivityAt ?? scheduledAt, scheduledAt)
            var audioActivityDeferralsRemaining = Self.maximumAudioActivityDeferrals

            if let promptAfter = decision.promptAfter {
                guard await waitForPause(
                    promptAfter,
                    pauseBeganAt: &pauseBeganAt,
                    audioActivityDeferralsRemaining: &audioActivityDeferralsRemaining
                ) else { return }
                isWaitingForContinuation = true
            }

            guard await waitForPause(
                decision.finishAfter,
                pauseBeganAt: &pauseBeganAt,
                audioActivityDeferralsRemaining: &audioActivityDeferralsRemaining
            ) else { return }
            guard let automaticFinalization else { return }
            beginFinalization(automaticFinalization)
        }
    }

    private var canContinueAutomaticEndpointing: Bool {
        !Task.isCancelled
            && state == .listening
            && !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Transcript updates normally cancel the pending endpoint. This audio
    /// guard covers the smaller race where the person resumes just before the
    /// timer fires but recognition has not published their new words yet.
    /// Rebasing is bounded so steady background noise cannot listen forever.
    private func waitForPause(
        _ requiredDuration: Duration,
        pauseBeganAt: inout CapturePerformanceClock.Instant,
        audioActivityDeferralsRemaining: inout Int
    ) async -> Bool {
        while canContinueAutomaticEndpointing {
            let elapsed = pauseBeganAt.duration(to: CapturePerformanceClock.now)
            if elapsed < requiredDuration {
                try? await Task.sleep(for: requiredDuration - elapsed)
            }
            guard canContinueAutomaticEndpointing else { return false }

            if audioActivityDeferralsRemaining > 0,
               let lastVoiceActivityAt,
               lastVoiceActivityAt > pauseBeganAt {
                pauseBeganAt = lastVoiceActivityAt
                audioActivityDeferralsRemaining -= 1
                continue
            }
            return true
        }
        return false
    }

    /// A longer adaptive pause lets somebody think without making every
    /// completed capture feel slow. The token list deliberately favors avoiding
    /// a cut-off: a false positive only waits longer, while a false negative can
    /// lose the rest of a thought.
    /// Stable lexical representation used only by endpointing. The recognizer's
    /// original formatted transcript remains untouched for display and saving.
    static func endpointingSignature(for transcript: String) -> String {
        endpointingTokens(for: transcript).joined(separator: " ")
    }

    private static func endpointingTokens(for transcript: String) -> [String] {
        transcript.lowercased().split(whereSeparator: { character in
            !character.isLetter
                && !character.isNumber
                && character != "'"
                && character != "’"
        }).map(String.init).map {
            $0.trimmingCharacters(in: CharacterSet(charactersIn: "'’"))
        }.filter { !$0.isEmpty }
    }

    static func naturalPauseDecision(for transcript: String) -> NaturalPauseDecision {
        // Punctuation in live ASR is inferred formatting and can be introduced
        // by a thinking pause. Build the endpointing tail from spoken lexical
        // tokens instead of trusting periods, commas, quotes, parentheses, or
        // missing whitespace. This does not alter the transcript we display or
        // persist; it only makes the pause decision punctuation-agnostic.
        let lexicalTokens = endpointingTokens(for: transcript)
        let normalized = lexicalTokens.joined(separator: " ")
        let finalToken = lexicalTokens.last
        let strongContinuationTokens: Set<String> = [
            // Connectors and explicit continuation markers.
            "also", "and", "because", "but", "or", "plus", "then",
            // High-signal open slots in capture-style commands.
            "at", "to",
            // An article or possessive normally needs a following noun.
            "a", "an", "my", "our", "the", "their", "your",
            // Explicit hesitations say the speaker still holds the turn.
            "er", "hmm", "uh", "um"
        ]
        let ambiguousContinuationTokens: Set<String> = [
            // These often open another phrase, but are also valid sentence endings.
            "about", "after", "before", "by", "for", "from", "in", "into", "of",
            "on", "until", "with", "without",
            // These may launch a list or hesitation, or complete an ordinary thought.
            "another", "first", "like", "next", "second", "so", "third", "well"
        ]
        let continuationPhrases = [
            "do not forget", "don't forget", "dont forget", "don’t forget", "i have to",
            "i meant to", "i need to", "i want to", "make sure", "one more",
            "one more thing", "remind me", "remind me about", "remind me to"
        ]
        let looksIncomplete = finalToken.map(strongContinuationTokens.contains) == true
            || continuationPhrases.contains(where: {
                normalized == $0 || normalized.hasSuffix(" \($0)")
            })

        if looksIncomplete {
            return NaturalPauseDecision(
                promptAfter: .milliseconds(continuationPromptPauseMilliseconds),
                finishAfter: .milliseconds(incompleteThoughtPauseMilliseconds)
            )
        }
        if finalToken.map(ambiguousContinuationTokens.contains) == true {
            return NaturalPauseDecision(
                promptAfter: .milliseconds(continuationPromptPauseMilliseconds),
                finishAfter: .milliseconds(ambiguousThoughtPauseMilliseconds)
            )
        }
        return NaturalPauseDecision(
            promptAfter: nil,
            finishAfter: .milliseconds(completeThoughtPauseMilliseconds)
        )
    }

    static func naturalPauseDuration(for transcript: String) -> Duration {
        naturalPauseDecision(for: transcript).finishAfter
    }

    private func beginFinalization(_ completion: @escaping (String) -> Void) {
        guard state == .listening else { return }

        naturalPauseTask?.cancel()
        isWaitingForContinuation = false
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
        // `finish` closes submissions and synchronously drains already-copied
        // buffers. `beginFinalization` calls `endAudio` only after this returns,
        // so the last spoken syllable cannot be stranded behind file I/O or
        // analyzer format conversion.
        audioProcessor?.finish()
        audioProcessor = nil
        if lastAudioQuality == nil {
            lastAudioQuality = audioQualityTracker.snapshot(
                profile: audioProfile,
                recognitionEngine: recognitionEngine
            )
            if let lastAudioQuality {
                SpeechCaptureDiagnosticsStore.save(lastAudioQuality)
            }
        }
        recoveryAudioFile = nil
        audioLevel = 0
    }

    private static func configureAudioSession(
        _ audioSession: AVAudioSession,
        profile: SpeechCaptureAudioProfile
    ) throws {
        // All profiles remain exclusive: no mix/duck option is supplied, so a
        // Reel, podcast, or song is interrupted instead of leaking into ASR.
        switch profile {
        case .spokenAudio:
            try audioSession.setCategory(.playAndRecord, mode: .spokenAudio, options: [])
        case .measurement:
            try audioSession.setCategory(.record, mode: .measurement, options: [])
        case .voiceProcessed:
            try audioSession.setCategory(.playAndRecord, mode: .voiceChat, options: [])
        }
    }

    private func resetRecognitionResources() {
        naturalPauseTask?.cancel()
        naturalPauseTask = nil
        audioInputReadyTimeout?.cancel()
        audioInputReadyTimeout = nil
        lastEndpointingSignature = ""
        isWaitingForContinuation = false
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

/// The engine can report that it started before Core Audio has delivered a
/// microphone buffer. Keeping the UI in its preparing state until this gate
/// opens gives the person a truthful cue: when Speak It says "Listening," the
/// recognizer and recovery recording have already received real audio.
final class FirstAudioBufferGate: @unchecked Sendable {
    private let lock = NSLock()
    private var isReady = false

    func markReady() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !isReady else { return false }
        isReady = true
        return true
    }
}

/// Ordered fan-out for microphone buffers. AVAudioEngine owns the tap buffer
/// only for the duration of its callback, so each accepted buffer is copied
/// before returning and then processed away from Core Audio's real-time thread.
final class SpeechCaptureAudioProcessor: @unchecked Sendable {
    private let queue = DispatchQueue(
        label: "com.speakit.capture-audio-processing",
        qos: .userInitiated
    )
    private let lock = NSLock()
    private let process: (AVAudioPCMBuffer) -> Void
    private let onFirstBufferProcessed: () -> Void
    private var isAcceptingInput = true
    private var hasProcessedFirstBuffer = false

    init(
        process: @escaping (AVAudioPCMBuffer) -> Void,
        onFirstBufferProcessed: @escaping () -> Void = {}
    ) {
        self.process = process
        self.onFirstBufferProcessed = onFirstBufferProcessed
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        guard isAcceptingInput,
              let copiedBuffer = Self.copy(buffer) else {
            lock.unlock()
            return
        }
        queue.async { [self] in
            autoreleasepool {
                process(copiedBuffer)
                if !hasProcessedFirstBuffer {
                    hasProcessedFirstBuffer = true
                    onFirstBufferProcessed()
                }
            }
        }
        lock.unlock()
    }

    /// Stops accepting buffers and waits for everything submitted before this
    /// call. Safe to call repeatedly from the capture's main-actor teardown.
    func finish() {
        lock.lock()
        isAcceptingInput = false
        lock.unlock()
        queue.sync {}
    }

    private static func copy(_ source: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let destination = AVAudioPCMBuffer(
            pcmFormat: source.format,
            frameCapacity: source.frameLength
        ) else { return nil }
        destination.frameLength = source.frameLength

        let sourceBuffers = UnsafeMutableAudioBufferListPointer(source.mutableAudioBufferList)
        let destinationBuffers = UnsafeMutableAudioBufferListPointer(
            destination.mutableAudioBufferList
        )
        guard sourceBuffers.count == destinationBuffers.count else { return nil }

        for index in sourceBuffers.indices {
            let sourceBuffer = sourceBuffers[index]
            let destinationBuffer = destinationBuffers[index]
            guard let sourceData = sourceBuffer.mData,
                  let destinationData = destinationBuffer.mData else { continue }
            memcpy(
                destinationData,
                sourceData,
                min(Int(sourceBuffer.mDataByteSize), Int(destinationBuffer.mDataByteSize))
            )
        }
        return destination
    }
}

/// Content-free capture diagnostics. This records only signal statistics—no
/// audio samples and no transcript—so quiet/clipped regressions can be measured
/// without weakening Speak It's local-first privacy model.
final class AudioQualityTracker: @unchecked Sendable {
    private let lock = NSLock()
    private var accumulatedSquares: Double = 0
    private var peakMagnitude: Float = 0
    private var clippedSampleCount = 0
    private var sampleCount = 0
    private var sampleRate: Double = 0

    func reset() {
        lock.lock()
        accumulatedSquares = 0
        peakMagnitude = 0
        clippedSampleCount = 0
        sampleCount = 0
        sampleRate = 0
        lock.unlock()
    }

    func record(_ buffer: AVAudioPCMBuffer) {
        guard let samples = buffer.floatChannelData?.pointee else { return }
        let count = Int(buffer.frameLength)
        guard count > 0 else { return }

        var sumOfSquares: Float = 0
        var peak: Float = 0
        vDSP_svesq(samples, 1, &sumOfSquares, vDSP_Length(count))
        vDSP_maxmgv(samples, 1, &peak, vDSP_Length(count))

        var clipped = 0
        for index in 0..<count where abs(samples[index]) >= 0.98 {
            clipped += 1
        }

        lock.lock()
        accumulatedSquares += Double(sumOfSquares)
        peakMagnitude = max(peakMagnitude, peak)
        clippedSampleCount += clipped
        sampleCount += count
        if sampleRate == 0 { sampleRate = buffer.format.sampleRate }
        lock.unlock()
    }

    func snapshot(
        profile: SpeechCaptureAudioProfile,
        recognitionEngine: SpeechRecognitionEngine?
    ) -> SpeechCaptureAudioQuality? {
        lock.lock()
        let squares = accumulatedSquares
        let peak = peakMagnitude
        let clipped = clippedSampleCount
        let count = sampleCount
        let rate = sampleRate
        lock.unlock()

        guard count > 0, rate > 0 else { return nil }
        let rms = sqrt(squares / Double(count))
        let rmsDecibels = 20 * log10(max(rms, 0.000_001))
        let peakDecibels = 20 * log10(max(Double(peak), 0.000_001))
        return SpeechCaptureAudioQuality(
            rmsDecibels: rmsDecibels,
            peakDecibels: peakDecibels,
            clippedSampleFraction: Double(clipped) / Double(count),
            durationMilliseconds: Int((Double(count) / rate * 1_000).rounded()),
            profile: profile,
            recognitionEngine: recognitionEngine
        )
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
