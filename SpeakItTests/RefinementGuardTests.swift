import XCTest
@testable import SpeakIt

/// Covers the seam where the on-device refinement model is allowed to replace
/// the rules reading.
///
/// Why this suite exists
/// ---------------------
/// `SemanticCorpusTests` and `RenderingInvarianceTests` both call
/// `ThoughtExtractionEngine.extractWithRules`. Production calls
/// `ThoughtExtractionEngine.extract`, which on an Apple Intelligence device
/// hands the capture to `IntelligentThoughtExtractor` whenever
/// `shouldRefine` says so — and `shouldRefine` returns true for *every* capture
/// the rules split into more than one row.
///
/// So the 666 corpus cases gate a path that a modern iPhone may not run, and
/// the multi-row captures this project worked hardest on are exactly the ones
/// whose outcome the rules no longer decide. The suite is green on the
/// simulator because Apple Intelligence is unavailable there and the model call
/// silently falls back to rules, which is precisely why the gap stayed
/// invisible.
///
/// The model itself cannot be driven in CI. What can be gated is the contract
/// the model's answer has to satisfy before it is allowed to win, so that is
/// what this suite pins — with synthetic refinements standing in for the model,
/// including the ones a model realistically gets wrong.
@MainActor
final class RefinementGuardTests: XCTestCase {

    // MARK: Building refinements by hand

    /// A refined item shaped the way `IntelligentThoughtExtractor.validate`
    /// builds one: a quote lifted from the transcript, optionally with shared
    /// timing carried in front of it as inherited context.
    private func refined(_ quote: String, context: String = "") -> ExtractedThought {
        let analysis = context.isEmpty ? quote : "\(context) \(quote)"
        return ExtractedThought(
            sourceQuote: quote,
            analysisText: analysis,
            suggestedTitle: nil,
            organization: ThoughtOrganizer.organize(
                analysis,
                referenceDate: CorpusEvaluator.referenceDate,
                calendar: CorpusEvaluator.calendar
            ),
            confidence: 0.9,
            needsReview: false
        )
    }

    private func rulesReading(of transcript: String) -> [ExtractedThought] {
        ThoughtExtractionEngine.extractWithRules(
            transcript,
            referenceDate: CorpusEvaluator.referenceDate,
            calendar: CorpusEvaluator.calendar
        ).items
    }

    // MARK: The behaviour that was unguarded

    /// The failure that motivated the guard: two well-formed, perfectly
    /// grounded rows for a capture the rules read as two *different* errands,
    /// one of which is simply gone. Every quote passes the grounding check, so
    /// nothing before this guard could tell.
    func testRefinementThatDropsAnErrandIsRejected() {
        let rules = [refined("call mom tomorrow"), refined("call Alex Friday")]
        let modelLostAlex = [refined("call mom tomorrow")]

        XCTAssertFalse(
            RefinementGuard.preservesEverything(in: modelLostAlex, found: rules),
            "Alex's errand vanished; the rules reading has to win"
        )
    }

    /// The shared verb must not be able to disguise the loss. "Call" appears in
    /// both rows, so a naive overlap test would see the surviving row and call
    /// the dropped one covered.
    func testSharedVerbDoesNotDisguiseADroppedRow() {
        let rules = [refined("call the dentist"), refined("call the pharmacy")]
        let modelLostPharmacy = [refined("call the dentist")]

        XCTAssertFalse(
            RefinementGuard.preservesEverything(in: modelLostPharmacy, found: rules),
            "only the verb survived; 'pharmacy' is what made it a second errand"
        )
    }

    func testEmptyRefinementIsRejected() {
        let rules = [refined("buy milk"), refined("call the vet")]
        XCTAssertFalse(RefinementGuard.preservesEverything(in: [], found: rules))
    }

    // MARK: What the model is still free to do

    /// Merging is a legitimate re-reading. The guard constrains loss, not shape.
    func testMergingTwoRowsIntoOneIsAccepted() {
        let rules = [refined("buy milk"), refined("buy eggs")]
        let merged = [refined("buy milk and eggs")]

        XCTAssertTrue(RefinementGuard.preservesEverything(in: merged, found: rules))
    }

    func testSplittingFurtherIsAccepted() {
        let rules = [refined("buy milk and eggs"), refined("call the vet")]
        let split = [refined("buy milk"), refined("buy eggs"), refined("call the vet")]

        XCTAssertTrue(RefinementGuard.preservesEverything(in: split, found: rules))
    }

    /// Retitling and recategorizing are the model's whole point, and they leave
    /// the quotes alone.
    func testRetitlingIsAccepted() {
        let rules = [refined("email Professor Chen"), refined("book the flight")]
        var retitled = rules
        retitled[0] = ExtractedThought(
            sourceQuote: rules[0].sourceQuote,
            analysisText: rules[0].analysisText,
            suggestedTitle: "Email Professor Chen about the extension",
            organization: rules[0].organization,
            confidence: 0.95,
            needsReview: false
        )

        XCTAssertTrue(RefinementGuard.preservesEverything(in: retitled, found: rules))
    }

    /// The model is instructed to lift shared timing into `inheritedContext`,
    /// which lands in `analysisText` rather than the quote. A weekday that moved
    /// there has not been lost.
    func testTimingLiftedIntoInheritedContextStillCounts() {
        let rules = [refined("call mom tomorrow"), refined("email Alex Friday")]
        let lifted = [
            refined("call mom", context: "tomorrow"),
            refined("email Alex", context: "Friday"),
        ]

        XCTAssertTrue(RefinementGuard.preservesEverything(in: lifted, found: rules))
    }

    /// A single rules row is not constrained. It cannot be dropped without
    /// emptying the refinement — which `validate` already rejects — and holding
    /// it to full token coverage would refuse the legitimate case of a tight
    /// quote replacing a rambling one.
    func testSingleRulesRowIsNotHeldToTokenCoverage() {
        let rules = [refined("um so I really need to remember to buy milk at some point")]
        let tightened = [refined("buy milk")]

        XCTAssertTrue(RefinementGuard.preservesEverything(in: tightened, found: rules))
    }

    // MARK: The corpus, replayed through the seam

    /// The rules' own reading must always satisfy the guard.
    ///
    /// Without this, a guard that was accidentally too strict would silently
    /// disable refinement everywhere and no test would notice — the app would
    /// simply stop using the model and still look correct.
    func testRulesReadingAlwaysSatisfiesItsOwnGuard() {
        var rejected: [String] = []

        for testCase in CorpusEvaluator.allCases {
            let items = rulesReading(of: testCase.utterance)
            guard items.count > 1 else { continue }
            if !RefinementGuard.preservesEverything(in: items, found: items) {
                rejected.append(testCase.utterance)
            }
        }

        XCTAssertTrue(
            rejected.isEmpty,
            """
            The guard rejected the rules' own output, which would turn off \
            refinement on every Apple Intelligence device:
            \(rejected.prefix(20).map { "  • \($0)" }.joined(separator: "\n"))
            """
        )
    }

    /// Every multi-row capture in the corpus, with one row deleted, must be
    /// rejected.
    ///
    /// This is the assertion that actually closes the hole. `shouldRefine`
    /// sends 100% of multi-row captures to the model, so for each of these the
    /// model losing a row is a live production failure mode, and each one is
    /// now a test.
    func testNoCorpusRowCanBeDroppedByARefinement() {
        var accepted: [String] = []
        var covered = 0

        for testCase in CorpusEvaluator.allCases {
            let items = rulesReading(of: testCase.utterance)
            guard items.count > 1 else { continue }
            covered += 1

            for index in items.indices {
                var lossy = items
                lossy.remove(at: index)
                if RefinementGuard.preservesEverything(in: lossy, found: items) {
                    accepted.append(
                        "\(testCase.utterance)  [dropped: \(items[index].sourceQuote)]"
                    )
                }
            }
        }

        XCTAssertGreaterThan(covered, 20, "expected the corpus to hold multi-row captures")
        XCTAssertTrue(
            accepted.isEmpty,
            """
            A refinement that deleted one of the rules' rows was accepted for \
            \(accepted.count) of \(covered) multi-row captures. Each is a row \
            that can silently disappear on an Apple Intelligence device:
            \(accepted.prefix(25).map { "  • \($0)" }.joined(separator: "\n"))
            """
        )
    }

    /// How much of the corpus production would hand to the model.
    ///
    /// Never fails. It exists so the size of the untested-by-the-model surface
    /// is a number someone can watch rather than a fact rediscovered later.
    func testRefinementExposureSummary() {
        var total = 0
        var refinedCount = 0
        var multiRow = 0

        for testCase in CorpusEvaluator.allCases {
            let items = rulesReading(of: testCase.utterance)
            total += 1
            if items.count > 1 { multiRow += 1 }
            if IntelligentThoughtExtractorExposure.wouldRefine(
                testCase.utterance,
                fallback: items
            ) {
                refinedCount += 1
            }
        }

        let percent = total == 0 ? 0 : Int((Double(refinedCount) / Double(total)) * 100)
        print("""

        REFINEMENT EXPOSURE
        \(String(repeating: "=", count: 60))
        corpus captures                      \(total)
        handed to the on-device model        \(refinedCount)  (\(percent)%)
        of which multi-row (always refined)  \(multiRow)

        On a device with Apple Intelligence these are decided by the model, not
        by the rules the corpus gates. The guard bounds the damage; it does not
        make the model's reading correct.
        """)
    }
}

/// Mirrors `IntelligentThoughtExtractor.shouldRefine` so the exposure summary
/// can run on machines where `FoundationModels` is not importable and the real
/// one does not exist.
///
/// Kept deliberately tiny and adjacent to the original: if the two drift, the
/// number the summary prints is wrong, and the summary says so rather than
/// pretending the surface is smaller than it is.
enum IntelligentThoughtExtractorExposure {
    static func wouldRefine(_ transcript: String, fallback: [ExtractedThought]) -> Bool {
        guard transcript.count <= 1_500 else { return false }
        if fallback.contains(where: { $0.needsReview }) { return true }
        if fallback.count > 1 { return true }
        return transcript.range(
            of: #"(?i)(?:[,;]|\band\b|\balso\b|\bthen\b|\bactually\b|\bi\s+mean\b|\bnot\b|\bsaid\b)"#,
            options: .regularExpression
        ) != nil
    }
}
