import XCTest
@testable import SpeakIt

/// Replays the entire semantic corpus through the ways a **recognizer** can
/// render the same spoken sentence, and asserts the app behaves identically.
///
/// Why this suite exists
/// ---------------------
/// `SpeechTranscriber.makeStartedBackend` runs two engines: the iOS 26
/// `SpeechAnalyzer` when its model is installed, and `SFSpeechRecognizer`
/// otherwise — on iOS 17-25, while the analyzer model downloads, and whenever
/// the analyzer fails to start. They do not punctuate identically, and neither
/// one punctuates a fast talker reliably.
///
/// Nearly every rule in `SpeechRepair.swift` and every clause boundary in
/// `ThoughtExtractor.swift` was originally written against a comma. That made
/// the app's behaviour a function of *which recognizer answered*, which is not
/// a thing a person can see, control, or report a bug about. It also made the
/// same defect arrive over and over wearing a different sentence: a repair
/// would be added for one phrasing, and the next recording would render without
/// the comma and fail again.
///
/// The corpus already states what each sentence must mean. This suite asserts
/// that the meaning survives the rendering, so the class of bug cannot return
/// one sentence at a time.
///
/// What is gated
/// -------------
/// Same rule as the corpus: zero CRITICAL and zero BEHAVIORAL. Title wording
/// legitimately changes when punctuation does, and `title` is a cosmetic field,
/// so it is reported and never gates.
@MainActor
final class RenderingInvarianceTests: XCTestCase {

    /// One way a recognizer can write down what was said.
    private struct Rendering {
        let name: String
        let describe: String
        let transform: (String) -> String
        /// Whether disagreements under this rendering block a release.
        let gates: Bool
    }

    /// Strips every mark a recognizer may decline to emit.
    ///
    /// Sentence-ending marks go too: a person who dictates three errands in one
    /// breath gets one unpunctuated run, and that is the single most common
    /// real-world rendering.
    private static func unpunctuated(_ text: String) -> String {
        text
            .replacingOccurrences(of: #"[,;:.!?]"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    private static let renderings: [Rendering] = [
        Rendering(
            name: "comma-free",
            describe: "every comma dropped, sentence marks kept",
            transform: {
                $0.replacingOccurrences(of: #"\s*,\s*"#, with: " ", options: .regularExpression)
                    .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                    .trimmingCharacters(in: .whitespaces)
            },
            gates: true
        ),
        Rendering(
            name: "unpunctuated",
            describe: "no punctuation at all, as a fast talker is transcribed",
            transform: unpunctuated,
            gates: true
        ),
        Rendering(
            name: "lowercased",
            describe: "no capitalization, as an unrecognized name is transcribed",
            transform: { $0.lowercased() },
            // Reported, not gated. Person parsing legitimately reads
            // capitalization as evidence, and a recognizer that lowercases a
            // name has already destroyed information the app cannot recover.
            // Tracked so the cost stays visible.
            gates: false
        ),
    ]

    // MARK: The gate

    func testMeaningSurvivesCommaFreeRendering() {
        assertInvariant(named: "comma-free")
    }

    func testMeaningSurvivesUnpunctuatedRendering() {
        assertInvariant(named: "unpunctuated")
    }

    func testLowercasedRenderingIsReported() {
        assertInvariant(named: "lowercased")
    }

    private func assertInvariant(named name: String) {
        guard let rendering = Self.renderings.first(where: { $0.name == name }) else {
            return XCTFail("Unknown rendering \(name)")
        }

        let evaluator = CorpusEvaluator(
            severityCeiling: rendering.gates ? nil : .metadata,
            rendering: rendering.transform
        )

        var byFamily: [(CorpusFamily, [CorpusCase], [CorpusDisagreement])] = []
        for (family, cases) in CorpusEvaluator.allFamilies {
            var disagreements: [CorpusDisagreement] = []
            for testCase in cases {
                // A case whose utterance is unchanged by the rendering is
                // already covered by `SemanticCorpusTests`; replaying it here
                // would only pad the report.
                guard rendering.transform(testCase.utterance) != testCase.utterance else { continue }
                disagreements.append(contentsOf: evaluator.evaluate(testCase))
            }
            if !disagreements.isEmpty {
                byFamily.append((family, cases, disagreements))
            }
        }

        let all = byFamily.flatMap(\.2)
        guard !all.isEmpty else { return }

        var report = """

        RENDERING INVARIANCE — \(rendering.name)
        \(rendering.describe)
        \(String(repeating: "=", count: 60))
        The corpus states what each sentence must mean. Every disagreement below
        is the app behaving differently because of how the recognizer wrote the
        sentence down, not because of what the person said.
        """
        for (family, cases, disagreements) in byFamily {
            report += CorpusEvaluator.report(
                title: family.rawValue,
                cases: cases,
                disagreements: disagreements
            )
        }

        let blocking = all.filter { $0.severity >= .behavioral }
        if blocking.isEmpty {
            print(report)
            return
        }
        XCTFail(report)
    }

    /// Never fails. Prints how much of the corpus is rendering-sensitive, so a
    /// regression in this direction is visible as a number rather than as a
    /// surprise months later.
    func testRenderingSensitivitySummary() {
        var lines = ["", "RENDERING SENSITIVITY", String(repeating: "=", count: 60)]

        for rendering in Self.renderings {
            let evaluator = CorpusEvaluator(rendering: rendering.transform)
            var applicable = 0
            var failing = Set<String>()
            var severityTotals: [CorpusSeverity: Int] = [:]

            for testCase in CorpusEvaluator.allCases {
                guard rendering.transform(testCase.utterance) != testCase.utterance else { continue }
                applicable += 1
                for entry in evaluator.evaluate(testCase) {
                    failing.insert(testCase.utterance)
                    severityTotals[entry.severity, default: 0] += 1
                }
            }

            let counts = [CorpusSeverity.critical, .behavioral, .metadata, .cosmetic]
                .map { "\($0.label) \(severityTotals[$0] ?? 0)" }
                .joined(separator: "  ")
            lines.append("")
            lines.append("\(rendering.name): \(failing.count) of \(applicable) affected utterances disagree")
            lines.append("  \(counts)")
        }

        print(lines.joined(separator: "\n"))
    }
}
