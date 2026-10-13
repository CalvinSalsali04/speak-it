
import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

// Synthetic development input only; no microphone, saved store or real content.
let reference = ISO8601DateFormatter().date(from: "2026-08-03T14:00:00Z")!
var calendar = Calendar(identifier: .gregorian)
calendar.timeZone = TimeZone(identifier: "America/Toronto")!
let configuration = RuntimeExampleConfiguration(libraryURL: URL(fileURLWithPath: "/unused-startup-bank"),
    allowProposed: false, retrievalEnabled: false, manualReferenceIDs: [])
func elapsed(_ start: ContinuousClock.Instant) -> Double {
    let parts = start.duration(to: .now).components
    return Double(parts.seconds) + Double(parts.attoseconds) / 1e18
}
func report(_ fields: [String: Any]) {
    let data = try! JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys])
    print(String(decoding: data, as: UTF8.self))
}
report(["platform": "macOS", "os": ProcessInfo.processInfo.operatingSystemVersionString,
    "syntheticDevelopmentOnly": true, "phoneLatencyQualified": false,
    "systemModelEvictionControlled": false, "prewarmEnabled": false])
let literal = "Buy milk, eggs and cheese at Costco tomorrow at 9 AM."
for pass in 0..<2 {
    let start = ContinuousClock.now
    let rules = ThoughtExtractionEngine.extractWithRules(literal, referenceDate: reference, calendar: calendar)
    let result = await RuntimeExampleInterpreter.interpret(literal, referenceDate: reference, calendar: calendar,
        context: .empty, configuration: configuration, rules: rules)
    report(["kind": "production_literal_path", "pass": pass, "elapsedSeconds": elapsed(start),
            "items": result?.items.count ?? 0, "accepted": result != nil])
}
#if canImport(FoundationModels)
if #available(macOS 26.4, *) {
    let available = SystemLanguageModel.default.availability == .available
    report(["modelAvailable": available, "availability": String(describing: SystemLanguageModel.default.availability)])
    if available {
        let source = "Buy milk and eggs tomorrow. Also ask Priya whether the Friday dinner is still happening, and if she says yes bring the birthday gift."
        let rules = ThoughtExtractionEngine.extractWithRules(source, referenceDate: reference, calendar: calendar)
        for pass in 0..<2 {
            let started = ContinuousClock.now
            // Isolate the shipping model stage; bypassing fast certificates is
            // deliberate. This is not full capture/SwiftData/UI latency.
            let result = await RuntimeFoundationInterpreter.$developmentObserver.withValue({ message in
                if message.hasPrefix("call timing") || message.hasPrefix("call end") || message.hasPrefix("call cancellation") {
                    print("MODEL \(message)")
                }
            }) {
                let work = Task {
                    await RuntimeFoundationInterpreter.interpret(source, referenceDate: reference, calendar: calendar,
                        context: .empty, configuration: configuration, rules: rules, preselectedExamples: [])
                }
                let deadline = Task {
                    do { try await Task.sleep(for: .seconds(20)) } catch { return }
                    work.cancel()
                }
                defer { deadline.cancel() }
                return await work.value
            }
            report(["kind": "production_model_stage", "pass": pass,
                    "processState": pass == 0 ? "first-model-request-in-process" : "second-request-in-process",
                    "elapsedSeconds": elapsed(started), "accepted": result != nil,
                    "reviewItems": result?.items.filter(\.needsReview).count ?? 0,
                    "items": result?.items.count ?? 0])
        }
    }
}
#else
report(["modelAvailable": false, "availability": "frameworkMissing"])
#endif
