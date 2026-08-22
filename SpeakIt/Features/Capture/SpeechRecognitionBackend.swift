import AVFoundation
import Foundation
import Speech

/// One live recognition engine behind a capture. The orchestrator in
/// `SpeechTranscriber` owns the microphone, pause detection, and durability;
/// a backend only turns audio buffers into transcript updates.
@MainActor
protocol SpeechRecognitionBackend: AnyObject {
    /// Begins recognition. `onTranscript` receives the full transcript so far
    /// and whether the engine considers it final; `onError` reports a fatal
    /// engine failure. Both are delivered on the main actor.
    func start(
        onTranscript: @escaping @MainActor (String, Bool) -> Void,
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

// MARK: - SFSpeechRecognizer (iOS 17–25, and the analyzer's fallback)

@MainActor
final class LegacyRecognizerBackend: SpeechRecognitionBackend {
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
        onTranscript: @escaping @MainActor (String, Bool) -> Void,
        onError: @escaping @MainActor (Error) -> Void
    ) async throws {
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        request.contextualStrings = SpeechVocabularyStore.contextualPhrases
        // Let iOS choose between its on-device and network recognizers.
        // Hard-requiring the local model can fail when a locale's asset has
        // not finished downloading, even though the recognizer reports support.
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
    private static var hasRequestedInstall = false

    static func isReady() async -> Bool {
        guard Speech.SpeechTranscriber.isAvailable else { return false }
        guard let locale = await Speech.SpeechTranscriber.supportedLocale(
            equivalentTo: .current
        ) else { return false }

        let installed = await Speech.SpeechTranscriber.installedLocales
        if installed.contains(where: {
            $0.identifier(.bcp47) == locale.identifier(.bcp47)
        }) {
            return true
        }

        installModelIfNeeded(for: locale)
        return false
    }

    private static func installModelIfNeeded(for locale: Locale) {
        guard !hasRequestedInstall else { return }
        hasRequestedInstall = true
        Task.detached(priority: .utility) {
            let module = Speech.SpeechTranscriber(
                locale: locale,
                transcriptionOptions: [],
                reportingOptions: [],
                attributeOptions: []
            )
            guard let request = try? await AssetInventory.assetInstallationRequest(
                supporting: [module]
            ) else { return }
            try? await request.downloadAndInstall()
        }
    }
}

@available(iOS 26.0, *)
@MainActor
final class AnalyzerRecognitionBackend: SpeechRecognitionBackend {
    private let inputFormat: AVAudioFormat
    private let forwarder = AnalyzerAudioForwarder()
    private var analyzer: SpeechAnalyzer?
    private var resultsTask: Task<Void, Never>?

    init(inputFormat: AVAudioFormat) {
        self.inputFormat = inputFormat
    }

    func start(
        onTranscript: @escaping @MainActor (String, Bool) -> Void,
        onError: @escaping @MainActor (Error) -> Void
    ) async throws {
        guard let locale = await Speech.SpeechTranscriber.supportedLocale(
            equivalentTo: .current
        ) else {
            throw SpeechRecognitionBackendError.analyzerNotReady
        }

        let module = Speech.SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults, .fastResults],
            attributeOptions: []
        )

        guard let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(
            compatibleWith: [module],
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
        context.contextualStrings = [.general: SpeechVocabularyStore.contextualPhrases]

        analyzer = SpeechAnalyzer(
            inputSequence: stream,
            modules: [module],
            options: nil,
            analysisContext: context
        )

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
