import AVFoundation
import Foundation
import Speech

/// One live recognition engine behind a capture. The orchestrator in
/// `SpeechTranscriber` owns the microphone, pause detection, and durability;
/// a backend only turns audio buffers into transcript updates.
@MainActor
protocol SpeechRecognitionBackend: AnyObject {
    var engine: SpeechRecognitionEngine { get }
    var usesTrainedVoiceActivityDetection: Bool { get }

    /// Begins recognition. `onTranscript` receives the full transcript so far.
    /// The Boolean becomes `true` only after `endAudio()` closes the app-owned
    /// input stream; an engine that stops unexpectedly reports `onError`
    /// instead. This keeps backend segmentation from becoming user-facing
    /// endpointing. All callbacks are delivered on the main actor.
    func start(
        contextualPhrases: [String],
        onTranscript: @escaping @MainActor (String, Bool) -> Void,
        onVoiceActivity: @escaping @MainActor () -> Void,
        onError: @escaping @MainActor (Error) -> Void
    ) async throws

    /// Safe to call from the audio render thread.
    nonisolated func append(_ buffer: AVAudioPCMBuffer)

    /// Signals that no more audio is coming; the engine should finalize.
    func endAudio()

    /// Abandons recognition without expecting further results.
    func cancel()
}

enum SpeechRecognitionBackendError: Error {
    case recognizerUnavailable
    case analyzerNotReady
}

enum SpeechRecognitionEngine: String, Codable, Sendable {
    case speechAnalyzer = "speech_analyzer"
    case legacyRecognizer = "legacy_recognizer"
}

// MARK: - SFSpeechRecognizer (iOS 17–25, and the analyzer's fallback)

@MainActor
final class LegacyRecognizerBackend: SpeechRecognitionBackend {
    let engine = SpeechRecognitionEngine.legacyRecognizer
    let usesTrainedVoiceActivityDetection = false

    private let recognizer: SFSpeechRecognizer
    private let requestBox = LegacyRequestBox()
    private var recognitionTask: SFSpeechRecognitionTask?

    init?(locale: Locale = .current) {
        guard let recognizer = SFSpeechRecognizer(locale: locale),
              recognizer.isAvailable else {
            return nil
        }
        self.recognizer = recognizer
    }

    func start(
        contextualPhrases: [String],
        onTranscript: @escaping @MainActor (String, Bool) -> Void,
        onVoiceActivity: @escaping @MainActor () -> Void,
        onError: @escaping @MainActor (Error) -> Void
    ) async throws {
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        request.contextualStrings = contextualPhrases
        // Let iOS choose between its on-device and network recognizers.
        // Hard-requiring the local model can fail when a locale's asset has
        // not finished downloading, even though the recognizer reports support.
        //
        // This is the one place Speak It lets audio leave the iPhone, and it
        // is what the privacy policy and App Store description disclose: live
        // dictation may be processed by Apple's speech service. Nothing in the
        // app may call live recognition "on-device", and the protected
        // recording behind `CaptureAudioRecovery` must never take this path.
        request.requiresOnDeviceRecognition = false
        requestBox.install(request)

        recognitionTask = recognizer.recognitionTask(with: request) { result, error in
            Task { @MainActor in
                if let result {
                    onTranscript(result.bestTranscription.formattedString, result.isFinal)
                }
                if let error {
                    onError(error)
                }
            }
        }
    }

    nonisolated func append(_ buffer: AVAudioPCMBuffer) {
        requestBox.append(buffer)
    }

    func endAudio() {
        requestBox.endAudio()
    }

    func cancel() {
        requestBox.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
    }
}

/// Hands audio-thread buffers to the recognition request without hopping
/// through the main actor.
private final class LegacyRequestBox: @unchecked Sendable {
    private let lock = NSLock()
    private var request: SFSpeechAudioBufferRecognitionRequest?

    func install(_ request: SFSpeechAudioBufferRecognitionRequest) {
        lock.lock()
        self.request = request
        lock.unlock()
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        let request = request
        lock.unlock()
        request?.append(buffer)
    }

    func endAudio() {
        lock.lock()
        let request = request
        self.request = nil
        lock.unlock()
        request?.endAudio()
    }
}

// MARK: - SpeechAnalyzer (iOS 26+)

/// Whether the higher-accuracy on-device analyzer can serve the current
/// locale right now. When the model merely needs downloading, the download is
/// started in the background and this capture falls back to the legacy
/// recognizer, so a first capture is never blocked on a model download.
@available(iOS 26.0, *)
@MainActor
enum AnalyzerRecognitionSupport {
    private static var installationTask: Task<Bool, Never>?

    static func isReady() async -> Bool {
        guard let locale = await DictationTranscriber.supportedLocale(
            equivalentTo: .current
        ) else { return false }

        if await isInstalled(locale) { return true }

        installModelIfNeeded(for: locale)
        return false
    }

    /// Performs the same one-time installation as `isReady`, but waits for it.
    /// The first tutorial capture uses this path so it never silently drops to
    /// the older recognizer merely because the system asset was still arriving.
    static func prepareForHighAccuracyCapture() async -> Bool {
        guard let locale = await DictationTranscriber.supportedLocale(
            equivalentTo: .current
        ) else { return false }
        if await isInstalled(locale) { return true }

        let task = modelInstallationTask(for: locale)
        let succeeded = await task.value
        if !succeeded {
            // A later capture may occur after connectivity returns. Do not pin
            // the process to a completed failure for the rest of its lifetime.
            installationTask = nil
        }
        return succeeded
    }

    private static func installModelIfNeeded(for locale: Locale) {
        _ = modelInstallationTask(for: locale)
    }

    private static func modelInstallationTask(for locale: Locale) -> Task<Bool, Never> {
        if let installationTask { return installationTask }

        let task = Task { @MainActor in
            let module = DictationTranscriber(locale: locale, preset: .progressiveShortDictation)
            do {
                guard let request = try await AssetInventory.assetInstallationRequest(
                    supporting: [module]
                ) else {
                    return await isInstalled(locale)
                }
                try await request.downloadAndInstall()
                return await isInstalled(locale)
            } catch {
                return false
            }
        }
        installationTask = task
        return task
    }

    private static func isInstalled(_ locale: Locale) async -> Bool {
        let installed = await DictationTranscriber.installedLocales
        return installed.contains {
            $0.identifier(.bcp47) == locale.identifier(.bcp47)
        }
    }
}

@available(iOS 26.0, *)
@MainActor
final class AnalyzerRecognitionBackend: SpeechRecognitionBackend {
    let engine = SpeechRecognitionEngine.speechAnalyzer
    let usesTrainedVoiceActivityDetection = true

    private let inputFormat: AVAudioFormat
    private let forwarder = AnalyzerAudioForwarder()
    private var analyzer: SpeechAnalyzer?
    private var resultsTask: Task<Void, Never>?
    private var detectorResultsTask: Task<Void, Never>?

    init(inputFormat: AVAudioFormat) {
        self.inputFormat = inputFormat
    }

    func start(
        contextualPhrases: [String],
        onTranscript: @escaping @MainActor (String, Bool) -> Void,
        onVoiceActivity: @escaping @MainActor () -> Void,
        onError: @escaping @MainActor (Error) -> Void
    ) async throws {
        guard let locale = await DictationTranscriber.supportedLocale(
            equivalentTo: .current
        ) else {
            throw SpeechRecognitionBackendError.analyzerNotReady
        }

        // DictationTranscriber is Apple's task-specific dictation path and is
        // the SpeechAnalyzer module documented to consume contextual strings.
        // Start from the progressive preset for responsive live text, then ask
        // it to retain the N-best/acoustic evidence needed by accurate results.
        var preset = DictationTranscriber.Preset.progressiveShortDictation
        preset.reportingOptions.insert(.alternativeTranscriptions)
        preset.attributeOptions.formUnion([.audioTimeRange, .transcriptionConfidence])
        let module = DictationTranscriber(locale: locale, preset: preset)
        let detector = SpeechDetector(
            detectionOptions: .init(sensitivityLevel: .medium),
            reportResults: true
        )
        let modules: [any SpeechModule] = [module, detector]

        guard let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(
            compatibleWith: modules,
            considering: inputFormat
        ) else {
            throw SpeechRecognitionBackendError.analyzerNotReady
        }

        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
        try forwarder.prepare(
            inputFormat: inputFormat,
            analyzerFormat: analyzerFormat,
            continuation: continuation
        )

        let context = AnalysisContext()
        context.contextualStrings = [.general: contextualPhrases]

        let analyzer = SpeechAnalyzer(
            modules: modules,
            options: .init(priority: .userInitiated, modelRetention: .lingering)
        )
        try await analyzer.setContext(context)
        // Preheating before the microphone announces readiness avoids losing
        // the first few words to lazy model initialization. Lingering model
        // retention makes a second capture warm without retaining any audio.
        try await analyzer.prepareToAnalyze(in: analyzerFormat)
        try await analyzer.start(inputSequence: stream)
        self.analyzer = analyzer

        let assembly = TranscriptAssembly()
        resultsTask = Task { @MainActor [weak self] in
            do {
                for try await result in module.results {
                    let text = String(result.text.characters)
                    if result.isFinal {
                        assembly.commit(text)
                    } else {
                        assembly.replaceVolatile(text)
                    }
                    guard self != nil, !Task.isCancelled else { return }
                    onTranscript(assembly.transcript, false)
                }
                guard self != nil, !Task.isCancelled else { return }
                onTranscript(assembly.transcript, true)
            } catch {
                guard self != nil, !Task.isCancelled else { return }
                onError(error)
            }
        }

        detectorResultsTask = Task { @MainActor [weak self] in
            do {
                for try await result in detector.results {
                    guard self != nil, !Task.isCancelled else { return }
                    if result.speechDetected {
                        onVoiceActivity()
                    }
                }
            } catch {
                // Recognition remains authoritative. A detector failure only
                // removes the small resume-speech endpointing guard; it must
                // never discard an otherwise valid transcript.
            }
        }
    }

    nonisolated func append(_ buffer: AVAudioPCMBuffer) {
        forwarder.forward(buffer)
    }

    func endAudio() {
        forwarder.finishInput()
        let analyzer = analyzer
        Task {
            try? await analyzer?.finalizeAndFinishThroughEndOfInput()
        }
    }

    func cancel() {
        resultsTask?.cancel()
        resultsTask = nil
        detectorResultsTask?.cancel()
        detectorResultsTask = nil
        forwarder.finishInput()
        let analyzer = analyzer
        self.analyzer = nil
        Task {
            await analyzer?.cancelAndFinishNow()
        }
    }
}

/// Converts microphone buffers to the analyzer's preferred format and yields
/// them into its input stream, entirely off the main actor.
@available(iOS 26.0, *)
private final class AnalyzerAudioForwarder: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: AsyncStream<AnalyzerInput>.Continuation?
    private var converter: AVAudioConverter?
    private var analyzerFormat: AVAudioFormat?

    func prepare(
        inputFormat: AVAudioFormat,
        analyzerFormat: AVAudioFormat,
        continuation: AsyncStream<AnalyzerInput>.Continuation
    ) throws {
        var converter: AVAudioConverter?
        if inputFormat != analyzerFormat {
            guard let created = AVAudioConverter(from: inputFormat, to: analyzerFormat) else {
                throw SpeechRecognitionBackendError.analyzerNotReady
            }
            converter = created
        }
        lock.lock()
        self.continuation = continuation
        self.converter = converter
        self.analyzerFormat = analyzerFormat
        lock.unlock()
    }

    func forward(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        let continuation = continuation
        let converter = converter
        let analyzerFormat = analyzerFormat
        lock.unlock()
        guard let continuation else { return }

        guard let converter, let analyzerFormat else {
            continuation.yield(AnalyzerInput(buffer: buffer))
            return
        }

        let ratio = analyzerFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 16
        guard let converted = AVAudioPCMBuffer(
            pcmFormat: analyzerFormat,
            frameCapacity: capacity
        ) else { return }

        var gaveInput = false
        var conversionError: NSError?
        let status = converter.convert(to: converted, error: &conversionError) { _, inputStatus in
            if gaveInput {
                inputStatus.pointee = .noDataNow
                return nil
            }
            gaveInput = true
            inputStatus.pointee = .haveData
            return buffer
        }
        guard status != .error, converted.frameLength > 0 else { return }
        continuation.yield(AnalyzerInput(buffer: converted))
    }

    func finishInput() {
        lock.lock()
        let continuation = continuation
        self.continuation = nil
        lock.unlock()
        continuation?.finish()
    }
}

/// Assembles the analyzer's finalized segments and current volatile guess into
/// one visible transcript.
final class TranscriptAssembly {
    private var finalized = ""
    private var volatile = ""

    var transcript: String {
        Self.joined(finalized, volatile)
    }

    func commit(_ segment: String) {
        finalized = Self.joined(finalized, segment)
        volatile = ""
    }

    func replaceVolatile(_ text: String) {
        volatile = text
    }

    static func joined(_ head: String, _ tail: String) -> String {
        guard !head.isEmpty else { return tail }
        guard !tail.isEmpty else { return head }
        if let last = head.last, let first = tail.first,
           !last.isWhitespace, !first.isWhitespace {
            return head + " " + tail
        }
        return head + tail
    }
}
