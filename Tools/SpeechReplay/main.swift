import AVFoundation
import Foundation
import Speech

/// Synthetic development audio only; shares the shipping recognition backend.
/// File/stream replay is not microphone, phone, or production accuracy evidence.
@main
struct SpeechReplay {
    @MainActor
    static func main() async throws {
        let args = CommandLine.arguments
        let ready = await AnalyzerRecognitionSupport.isReady()
        if args.contains("--availability") {
            print("{\"analyzerReady\":\(ready),\"platform\":\"macOS\",\"speechAuthorization\":\(SFSpeechRecognizer.authorizationStatus().rawValue)}")
            return
        }
        guard ready else { throw SpeechRecognitionBackendError.analyzerNotReady }
        guard let pathIndex = args.firstIndex(of: "--audio"), pathIndex + 1 < args.count,
              let outputIndex = args.firstIndex(of: "--output"), outputIndex + 1 < args.count else {
            throw NSError(domain: "SpeechReplay", code: 1, userInfo: [NSLocalizedDescriptionKey: "Use --availability or --audio synthetic.wav --output trace.json [--realtime]"])
        }
        let file = try AVAudioFile(forReading: URL(fileURLWithPath: args[pathIndex + 1]))
        if args.contains("--modern") {
            guard let locale = await Speech.SpeechTranscriber.supportedLocale(equivalentTo: .current),
                  await Speech.SpeechTranscriber.installedLocales.contains(where: {
                      $0.identifier(.bcp47) == locale.identifier(.bcp47)
                  }) else { throw SpeechRecognitionBackendError.analyzerNotReady }
            let module = Speech.SpeechTranscriber(locale: locale, preset: .timeIndexedTranscriptionWithAlternatives)
            let start = ContinuousClock.now
            let analyzer = try await SpeechAnalyzer(inputAudioFile: file, modules: [module], finishAfterFile: true)
            defer { withExtendedLifetime(analyzer) {} }
            var events: [[String: Any]] = []
            for try await result in module.results {
                let c = start.duration(to: .now).components
                events.append(["atSeconds": Double(c.seconds) + Double(c.attoseconds)/1e18,
                    "audioStartSeconds": result.range.start.seconds, "audioEndSeconds": result.range.end.seconds,
                    "kind": "transcript", "text": String(result.text.characters), "final": result.isFinal])
            }
            let trace: [String: Any] = ["schemaVersion": 1, "syntheticDevelopmentOnly": true,
                "platform": "macOS", "engine": "experimental_speech_transcriber_file",
                "receivedFinal": true, "events": events]
            try JSONSerialization.data(withJSONObject: trace, options: [.prettyPrinted,.sortedKeys])
                .write(to: URL(fileURLWithPath: args[outputIndex + 1]))
            print("modern replay events=\(events.count)")
            return
        }
        let backend = AnalyzerRecognitionBackend(inputFormat: file.processingFormat)
        let started = ContinuousClock.now
        func seconds() -> Double {
            let c = started.duration(to: .now).components
            return Double(c.seconds) + Double(c.attoseconds) / 1e18
        }
        var events: [[String: Any]] = []
        var appendedAudioSeconds = 0.0
        var final = false
        var failure: String?
        try await backend.start(contextualPhrases: [], onTranscript: { text, isFinal in
            events.append(["atSeconds": seconds(), "inputAudioSeconds": appendedAudioSeconds, "kind": "transcript", "text": text, "final": isFinal])
            if isFinal { final = true }
        }, onVoiceActivity: {
            events.append(["atSeconds": seconds(), "kind": "voiceActivity"])
        }, onError: { error in
            failure = String(describing: error)
            events.append(["atSeconds": seconds(), "kind": "error", "error": String(describing: error)])
        })
        let setupSeconds = seconds()
        let capacity = AVAudioFrameCount(file.processingFormat.sampleRate / 10)
        while file.framePosition < file.length, failure == nil {
            let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: capacity)!
            try file.read(into: buffer)
            appendedAudioSeconds = Double(file.framePosition) / file.processingFormat.sampleRate
            backend.append(buffer)
            // Keep the forwarder's bounded queue draining even in file mode.
            let delay = args.contains("--realtime") ? 100 : 15
            try await Task.sleep(for: .milliseconds(delay))
        }
        let endAudioSeconds = seconds()
        backend.endAudio()
        let deadline = ContinuousClock.now.advanced(by: .seconds(20))
        while !final, failure == nil, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        let trace: [String: Any] = ["schemaVersion": 1, "syntheticDevelopmentOnly": true,
            "platform": "macOS", "engine": backend.engine.rawValue,
            "mode": args.contains("--realtime") ? "stream_realtime" : "file_forwarding",
            "setupSeconds": setupSeconds, "endAudioSeconds": endAudioSeconds,
            "finishedSeconds": seconds(), "receivedFinal": final,
            "error": failure as Any? ?? NSNull(), "events": events]
        try JSONSerialization.data(withJSONObject: trace, options: [.prettyPrinted, .sortedKeys])
            .write(to: URL(fileURLWithPath: args[outputIndex + 1]))
        backend.cancel()
        print("replay final=\(final) events=\(events.count) setup=\(setupSeconds)s")
        if !final || failure != nil { throw SpeechRecognitionBackendError.unexpectedFinalization }
    }
}
