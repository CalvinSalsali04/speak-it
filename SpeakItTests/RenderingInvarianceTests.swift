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

// MARK: - Whether the lexical tagger answered at all

/// Whether `NLTagger`'s lexical-class model is present in this process, and a
/// way for an assertion that depends on it to abstain rather than lie.
///
/// `Docs/KNOWN_ISSUES.md` records, verified 2026-09-11 against the framework,
/// that a GitHub-hosted `macos-26` runner's simulator returns `OtherWord` for
/// every token of every sentence while `NLEmbedding` loads normally in the same
/// process. `NaturalLanguageEnvironmentTests` above is the diagnostic that
/// established it.
///
/// **The reason this is a test helper and not a note.** An absent model does
/// not only turn assertions red. `ThoughtCompletion.unfinished` returns nil for
/// everything it does not decide lexically, so on that image every assertion
/// expecting nil passes *without exercising the rule it names*. A blind tagger
/// turns a negative assertion into a tautology, and a tautology is
/// indistinguishable from a rule that holds. Run 35124466497 is the worked
/// example: two failures, twenty-one passes, and the two failures were the only
/// answers in the class that carried information about the tagger-dependent
/// rules at all.
///
/// So the dependent assertions abstain. A skip says "not measured here", which
/// is true and visible in the Skipped column that `Tools/CI/xcresult-failures.py`
/// already prints. A pass would say "measured and correct", which is not.
enum LexicalTagging {

    /// The decision, taken as a function of a tagging rather than of the
    /// machine, so that both of its answers can be injected. Reading the
    /// environment is one line; deciding what the reading *means* is the part
    /// that can be wrong, and it is the part worth testing.
    ///
    /// Blind means no token carried a usable class. A partial answer is not
    /// blindness: a tagger that classes some words and not others is a tagger
    /// that can be wrong, and an assertion that can be wrong should run.
    ///
    /// Since 2026-09-23 the app takes this decision too, in
    /// `LinguisticHealth`, and this helper asks it rather than keeping a copy.
    /// Two copies of one decision can drift; one cannot.
    static func isBlind(_ classes: [NLTag?]) -> Bool {
        LinguisticHealth.isBlind(classes)
    }

    /// A verb, a determiner and a noun. Any one of the three coming back
    /// classed is enough, because the question is whether the model answered at
    /// all and not whether it answered well. The app probes the same sentence.
    static let probe = LinguisticHealth.probe

    /// Read once. The model does not arrive halfway through a run.
    static let isBlindHere: Bool = isBlind(SentenceContext(probe).tokens.map(\.lexicalClass))

    /// The tagging itself, so a skipped test says what was seen rather than
    /// only that something was skipped.
    static var reading: String {
        SentenceContext(probe).tokens
            .map { "\($0.text):\($0.lexicalClass?.rawValue ?? "none")" }
            .joined(separator: " ")
    }

    /// Abstain when the model is absent.
    static func skipIfBlind(file: StaticString = #filePath, line: UInt = #line) throws {
        try XCTSkipIf(
            isBlindHere,
            "NLTagger's lexical-class model is absent in this process, so this "
                + "assertion cannot answer either way. Tagging of the probe: "
                + "\(reading). See Docs/KNOWN_ISSUES.md — the reference "
                + "environment is the author's Mac.",
            file: file,
            line: line
        )
    }
}

/// The helper is itself a guard, so both of its answers are injected.
///
/// A skip helper that never skips is invisible behind a healthy tagger; one
/// that always skips is invisible behind a green suite. Neither can be caught
/// by running it on one machine.
final class LexicalTaggingHealthTests: XCTestCase {

    func testTheDecisionReadsATaggingBothWays() {
        let everyTokenUnclassed: [NLTag?] = [.otherWord, .otherWord, .otherWord]
        let noTagAtAll: [NLTag?] = [nil, nil]
        let nothingToRead: [NLTag?] = []
        let oneVerbAmongThem: [NLTag?] = [.otherWord, .verb, .otherWord]
        let theClassTheRulesRead: [NLTag?] = [.determiner]

        XCTAssertTrue(
            LexicalTagging.isBlind(everyTokenUnclassed),
            "every token OtherWord is the documented blind state"
        )
        XCTAssertTrue(
            LexicalTagging.isBlind(noTagAtAll),
            "no class at all is not an answer either"
        )
        XCTAssertTrue(
            LexicalTagging.isBlind(nothingToRead),
            "nothing to read is not a reading"
        )
        XCTAssertFalse(
            LexicalTagging.isBlind(oneVerbAmongThem),
            "one classed token means the model answered, and a wrong answer must stay measurable"
        )
        XCTAssertFalse(
            LexicalTagging.isBlind(theClassTheRulesRead),
            "the class the dependent rules actually read"
        )
    }

    /// An empty or one-word probe would report blindness on every machine and
    /// retire every dependent assertion for good, silently and permanently.
    /// That is the failure this helper exists to prevent, so it is asserted
    /// about the helper too.
    func testTheProbeIsLongEnoughToCarryAnAnswer() {
        XCTAssertGreaterThanOrEqual(
            SentenceContext(LexicalTagging.probe).tokens.count, 4,
            "the probe must be a sentence: \(LexicalTagging.probe)"
        )
    }

    // MARK: The app's own verdict

    /// The verdict the capture pipeline acts on, read from an injected tagging
    /// in both directions, and read from the probe sentence rather than from
    /// whatever text happens to be passed.
    ///
    /// Falsifier: make `LinguisticHealth.verdict` return `.usable`
    /// unconditionally (or tag an empty string instead of `probe`), and the
    /// first assertion (or the last) fails. On a healthy Mac nothing else in
    /// the suite would notice, because no machine the suite runs on is blind
    /// while its tests assert a degraded verdict.
    func testTheProductionVerdictReadsAnInjectedTaggingBothWays() {
        var asked: [String] = []
        let blind = LinguisticHealth.verdict { text in
            asked.append(text)
            return [.otherWord, .otherWord]
        }
        let usable = LinguisticHealth.verdict { _ in [.verb, .determiner] }

        XCTAssertEqual(blind, .blind, "every token OtherWord is the documented blind state")
        XCTAssertEqual(usable, .usable, "a classed verb means the model answered")
        XCTAssertEqual(asked, [LinguisticHealth.probe], "the verdict tags the probe sentence, once")
    }

    /// The test helper and the app take one decision, not two.
    ///
    /// Falsifier: give `LexicalTagging.isBlind` its own body again and change
    /// either copy (for example, count `nil` as a class), and the fixtures
    /// below disagree.
    func testTheTestHelperAndTheAppShareOneDecision() {
        let fixtures: [[NLTag?]] = [
            [.otherWord, .otherWord, .otherWord],
            [nil, nil],
            [],
            [.otherWord, .verb, .otherWord],
            [.determiner],
        ]
        for classes in fixtures {
            XCTAssertEqual(
                LexicalTagging.isBlind(classes),
                LinguisticHealth.isBlind(classes),
                "\(classes)"
            )
        }
        XCTAssertEqual(LexicalTagging.probe, LinguisticHealth.probe)
    }

    /// A blind verdict is probed again on the next read, a usable one is
    /// kept, and the reading cache is emptied exactly once, on the way from
    /// blind to usable.
    ///
    /// Falsifier: cache `.blind` like `.usable` in `VerdictCache.current`, and
    /// the second read stays blind. Drop the `recovered` call, and the count
    /// stays zero.
    func testABlindVerdictIsReprobed() {
        var taggings = 0
        var recoveries = 0
        let cache = LinguisticHealth.VerdictCache(
            tagging: { _ in
                taggings += 1
                return taggings == 1 ? [.otherWord] : [.verb]
            },
            recovered: { recoveries += 1 }
        )

        XCTAssertEqual(cache.current(), .blind)
        XCTAssertEqual(cache.current(), .usable, "a blind verdict must not be sticky")
        XCTAssertEqual(cache.current(), .usable)
        XCTAssertEqual(taggings, 2, "a usable verdict is kept, not probed again")
        XCTAssertEqual(recoveries, 1)
    }

    /// The first probe of a process that reads usable empties the reading
    /// cache too, not only a probe that follows a blind one. The rules run
    /// before the probe, so a capture read before the first probe (a cold
    /// launch from Back Tap or an App Intent, before prewarm) may have cached
    /// readings taken without the model. A first probe that reads blind
    /// empties nothing, and neither does a usable verdict read from the cache.
    ///
    /// Falsifier: go back to `last == .blind` alone in `VerdictCache.current`,
    /// and the first count stays zero.
    func testTheFirstUsableVerdictEmptiesTheReadingCache() {
        var recoveries = 0
        let cache = LinguisticHealth.VerdictCache(
            tagging: { _ in [.verb] },
            recovered: { recoveries += 1 }
        )
        XCTAssertEqual(cache.current(), .usable)
        XCTAssertEqual(recoveries, 1, "nothing had checked before, so the cache may hold blind readings")
        XCTAssertEqual(cache.current(), .usable)
        XCTAssertEqual(recoveries, 1, "a kept verdict must not empty the cache again")

        var blindRecoveries = 0
        let blind = LinguisticHealth.VerdictCache(
            tagging: { _ in [.otherWord] },
            recovered: { blindRecoveries += 1 }
        )
        XCTAssertEqual(blind.current(), .blind)
        XCTAssertEqual(blind.current(), .blind)
        XCTAssertEqual(blindRecoveries, 0, "a blind verdict has nothing to recover from")
    }

    /// Production probes; only a test harness is inert; an override beats
    /// both. This is the test that fails if the default path stops probing.
    ///
    /// Falsifier: make `policyVerdict` return `.usable` for `.probe` (or
    /// return `hostDefault` as `.probe` inside this host), and the matching
    /// assertion fails. The last two assertions are the mechanism every other
    /// test in the suite relies on: if this host stopped reading as inert, the
    /// degraded policy would switch itself on across the whole suite on a
    /// blind simulator.
    func testTheProductionDefaultProbesAndOnlyAHarnessIsInert() {
        var measured = 0
        let readsBlind: () -> LinguisticHealth.Tagger = { measured += 1; return .blind }
        let readsUsable: () -> LinguisticHealth.Tagger = { measured += 1; return .usable }

        XCTAssertEqual(LinguisticHealth.policyVerdict(override: nil, host: .probe, measure: readsBlind), .blind)
        XCTAssertEqual(LinguisticHealth.policyVerdict(override: nil, host: .probe, measure: readsUsable), .usable)
        XCTAssertEqual(measured, 2, "the production default must actually probe")

        XCTAssertEqual(LinguisticHealth.policyVerdict(override: nil, host: .inert, measure: readsBlind), .usable)
        XCTAssertEqual(LinguisticHealth.policyVerdict(override: nil, host: .forcedBlind, measure: readsUsable), .blind)
        XCTAssertEqual(measured, 2, "a harness and a forced launch do not probe")

        XCTAssertEqual(LinguisticHealth.policyVerdict(override: .blind, host: .inert, measure: readsUsable), .blind)
        XCTAssertEqual(LinguisticHealth.policyVerdict(override: .usable, host: .probe, measure: readsBlind), .usable)
        XCTAssertEqual(measured, 2, "an override is not second-guessed by a probe")

        XCTAssertEqual(LinguisticHealth.hostDefault, .inert, "the unit-test host must read as a harness")
        XCTAssertEqual(LinguisticHealth.effective, .usable)
    }
}
