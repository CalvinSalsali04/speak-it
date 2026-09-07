import XCTest
@testable import SpeakIt

/// Synthetic model responses pin the acceptance contract without requiring
/// Apple Intelligence in CI. Clear captures bypass optional refinement;
/// uncertain captures must retain every action and its behavioral metadata.
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
            // The fixture lifts the quote straight out of the transcript, so
            // the raw span is the quote and no repair ran.
            rawQuote: quote,
            wasRepaired: false,
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
            rawQuote: rules[0].rawQuote,
            wasRepaired: rules[0].wasRepaired,
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

    /// Tightening a narrative can remove framing while preserving its action.
    func testSingleRulesRowPreservesItsAction() {
        let rules = [refined("um so I really need to remember to buy milk")]
        let tightened = [refined("buy milk")]

        XCTAssertTrue(RefinementGuard.preservesEverything(in: tightened, found: rules))
    }

    func testDatesWithoutTheirActionsAreRejected() {
        let rules = [refined("call Mom tomorrow"), refined("email Alex Friday")]
        XCTAssertFalse(RefinementGuard.preservesEverything(
            in: [refined("tomorrow"), refined("Friday")], found: rules
        ))
    }

    func testIndependentActionsCannotCollapseIntoOneRow() {
        XCTAssertFalse(RefinementGuard.preservesEverything(
            in: [refined("call Mom and email Alex")],
            found: [refined("call Mom"), refined("email Alex")]
        ))
    }

    func testObjectCannotDisappearIntoInheritedContext() {
        XCTAssertFalse(RefinementGuard.preservesEverything(
            in: [refined("call tomorrow", context: "the dentist")],
            found: [refined("call the dentist tomorrow")]
        ))
    }

    func testClearListDoesNotInvokeOptionalModel() {
        let text = "Call Mom tomorrow and email Alex Friday"
        XCTAssertFalse(RefinementPolicy.shouldRefine(text, fallback: rulesReading(of: text)))
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
        RefinementPolicy.shouldRefine(transcript, fallback: fallback)
    }
}
