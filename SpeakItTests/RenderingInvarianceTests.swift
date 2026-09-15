import XCTest
import NaturalLanguage
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

// MARK: - The linguistic environment the rules are written against

/// Asserts what the parser assumes about Apple's tagger and word embedding,
/// directly, instead of inferring it from a behaviour that failed.
///
/// Why this suite exists
/// ---------------------
/// Almost every routing rule is a structural query over one `NLTagger` answer.
/// `Actionability.withoutFrontedAdjunct` cuts "on the 15th" off "pay the rent"
/// only because the tagger calls "pay" a verb and finds no verb in the span in
/// front of it; `Actionability.isOrdinaryEnglishWord` reads "Unpack boxes" as
/// an errand only because `NLEmbedding` holds "pack". Neither rule names a
/// phrase, which is the point of writing them that way — and it makes the
/// app's behaviour a function of what the framework answers on the machine it
/// is running on.
///
/// That is not hypothetical. On 2026-09-11 the unit suite failed on a
/// GitHub-hosted `macos-26` runner with 57 assertions that pass on the
/// author's Mac, on unchanged `main` as well as on a branch, while
/// `Tools/CorpusRunner` replayed the same corpus against the same sources on
/// the same runner minutes earlier with zero failures. The difference between
/// those two is the simulator runtime. Every failing assertion turned on a
/// part-of-speech or vocabulary judgement.
///
/// These tests answer the question the behaviour tests can only raise. A
/// failure here says the framework on this machine does not answer the way the
/// rules assume, and names the answer it gave instead; a pass here alongside a
/// behavioural failure rules the framework out. It lives in this file because
/// it is the same kind of fact as the rest of it: something outside the app
/// decides what the app does, and the suite states what it is relying on.
final class NaturalLanguageEnvironmentTests: XCTestCase {

    /// The whole sentence's tagging, as the failure message so the reading is
    /// recoverable from a log without an `.xcresult`.
    private func tagging(_ text: String) -> String {
        SentenceContext(text).tokens
            .map { "\($0.text):\($0.lexicalClass?.rawValue ?? "none")" }
            .joined(separator: " ")
    }

    private func tag(_ word: String, in text: String) -> NLTag? {
        SentenceContext(text).tokens
            .first { $0.text.lowercased() == word }?.lexicalClass
    }

    func testTheEnglishWordEmbeddingLoads() {
        XCTAssertNotNil(
            NLEmbedding.wordEmbedding(for: .english),
            "NLEmbedding.wordEmbedding(for: .english) is nil on this machine. "
                + "PersonMention and Actionability both fail closed without it."
        )
    }

    func testTheEmbeddingHoldsTheOrdinaryWordsTheRulesAskAbout() throws {
        let embedding = try XCTUnwrap(NLEmbedding.wordEmbedding(for: .english))
        for word in ["pack", "scale", "kettle", "rent", "invoice", "luck"] {
            XCTAssertTrue(embedding.contains(word), "embedding does not hold \(word)")
        }
    }

    func testAFrontedAdjunctIsTaggedAsOneAndTheVerbBehindItAsAVerb() {
        for (text, verb) in [
            ("on the 15th pay the rent", "pay"),
            ("by friday send the invoice", "send"),
            ("after dinner call mom", "call"),
            ("tomorrow morning email the landlord", "email"),
        ] {
            XCTAssertEqual(tag(verb, in: text), .verb, tagging(text))
            let context = SentenceContext(text)
            guard let verbStart = context.tokens
                .first(where: { $0.text.lowercased() == verb })?.range.lowerBound
            else { continue }
            XCTAssertTrue(
                context.isVerbless(in: text.startIndex..<verbStart),
                "the span in front of \(verb) holds a verb — " + tagging(text)
            )
        }
    }

    func testASubjectInsideAFrontedConditionIsTagged() {
        let text = "when I finish the essay call dave"
        XCTAssertEqual(tag("i", in: text), .pronoun, tagging(text))
        XCTAssertEqual(tag("finish", in: text), .verb, tagging(text))
        XCTAssertEqual(tag("call", in: text), .verb, tagging(text))
    }

    /// What separates "I had better luck last time" from "I had better call
    /// the bank tomorrow" is one token's part of speech and nothing else.
    func testHadBetterIsSeparatedByTheTagOfTheWordAfterIt() {
        let knowledge = "I had better luck last time"
        XCTAssertEqual(tag("luck", in: knowledge), .noun, tagging(knowledge))
        let action = "I had better call the bank tomorrow"
        XCTAssertEqual(tag("call", in: action), .verb, tagging(action))
    }
}
