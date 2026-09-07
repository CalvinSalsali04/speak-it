import XCTest
@testable import SpeakIt

/// Pins the asymmetry that makes `IntentConsolidator` safe to have at all.
///
/// The semantic corpus already proves the outcomes — how many rows a paragraph
/// becomes, what the row says. These tests sit one level down, on the verdict
/// itself, for the same reason `ActionabilityTests` does: the corpus can report
/// that a capture split into three, but not *which* of the two questions was
/// answered badly. Here the two questions are asked separately.
///
/// The invariant under test is that this stage is a **veto, never a splitter**:
/// it either collapses to one item or has no opinion, and having no opinion is
/// the default whenever the wording is not positively narrative.
@MainActor
final class IntentConsolidationTests: XCTestCase {

    private func clauses(_ text: String) -> [String] {
        RuleBasedThoughtExtractor.splitClauses(text)
    }

    private func verdict(_ text: String) -> IntentConsolidator.Consolidation? {
        IntentConsolidator.consolidate(text, clauses: clauses(text))
    }

    func testHedgedIndependentErrandsRemainIndependent() {
        let result = ThoughtExtractionEngine.extractWithRules(
            "I keep meaning to book the dentist and I have to call the bank about the fee and honestly I should just cancel the gym membership"
        )
        XCTAssertEqual(result.items.count, 3)
        for word in ["dentist", "bank", "gym"] {
            XCTAssertTrue(result.items.contains { $0.sourceQuote.contains(word) })
        }
        XCTAssertTrue(result.items.allSatisfy { $0.organization.itemType.isActionable })
    }

    func testPreparatoryPostureAndModalAdverbStayWithTheirAction() {
        for text in [
            "I think I need to sit down and finally do my taxes this weekend",
            "I should rarely call Dana about the refund"
        ] {
            XCTAssertEqual(ThoughtExtractionEngine.extractWithRules(text).items.count, 1, text)
        }
    }

    // MARK: It collapses narrative

    func testNarrativeElaborationCollapsesToItsHeadIntention() {
        let text = "Okay so I've been meaning to do this forever, I keep forgetting, "
            + "and I really need to remember to call the dentist tomorrow "
            + "because I need to ask about my appointment"
        let result = verdict(text)

        XCTAssertNotNil(result, "three clauses, one phone call")
        XCTAssertEqual(result?.title, "call the dentist tomorrow")
        XCTAssertEqual(result?.requiresReview, false)
        XCTAssertEqual(
            result?.analysisText,
            "I really need to remember to call the dentist tomorrow",
            "the reason is dropped: it can carry a date of its own"
        )
    }

    func testAPreambleInsideOneClauseIsStillAPreamble() {
        let result = verdict(
            "honestly the main thing is I just need to call the contractor about the quote"
        )
        XCTAssertEqual(result?.title, "call the contractor about the quote")
    }

    func testATrailingAsideIsDroppedFromTheTitle() {
        let result = verdict(
            "Honestly the thing is I just need to book the hotel, I've been putting it off for ages"
        )
        XCTAssertEqual(result?.title, "book the hotel")
    }

    /// Rambling that never arrives anywhere still becomes one item, but the
    /// paragraph itself must not become an enormous, confidently filed row.
    func testRamblingWithNoIntentionBecomesAShortReviewItem() {
        let text = "So I was thinking earlier today about the whole thing with the garage, "
            + "and how it's been kind of a mess for a while now"
        let result = verdict(text)

        XCTAssertEqual(result?.analysisText, text)
        XCTAssertEqual(result?.title, "Review captured thought")
        XCTAssertEqual(result?.requiresReview, true)
    }

    // MARK: It stands aside for anything else

    func testTwoIndependentIntentionsAreLeftToTheSplitter() {
        XCTAssertNil(verdict("Call the dentist tomorrow, buy milk, and remember Catherine is allergic to peanuts"))
        XCTAssertNil(verdict("The storage code is 4821, and buy detergent"))
        XCTAssertNil(verdict("Remember Alex likes golf and Catherine likes sushi"))
    }

    /// The case that rules out counting substantive clauses on its own.
    ///
    /// "Alex Friday" is not an intention by itself — it has no verb — so a rule
    /// that collapsed whenever it found fewer than two would merge two calls
    /// into one. Nothing here is elaborative, so this stage declines instead.
    func testAnEllipticalSecondClauseIsNotTreatedAsElaboration() {
        XCTAssertNil(verdict("Call Mom tomorrow and Alex Friday"))
    }

    func testAReasonAloneNeverLicensesCollapsing() {
        XCTAssertNil(
            verdict("Call the contractor because I need the quote"),
            "a reason attached to a single intention changes nothing about how many there are"
        )
    }

    func testAListOfObjectsIsUntouched() {
        XCTAssertNil(verdict("Buy milk, eggs and bread"))
    }

    // MARK: Substance

    func testSubstanceIgnoresLeadingDiscourseMarkers() {
        XCTAssertTrue(
            IntentConsolidator.isSubstantive("anyway I want to remember that her birthday is December 4"),
            "\"anyway\" is not what the clause is about"
        )
        XCTAssertTrue(IntentConsolidator.isSubstantive("so buy milk"))
    }

    /// An action pointing back at something already said is not an intention
    /// anybody could act on, and a fact needs far less to stand on than an
    /// action does.
    func testAnActionOnAPronounIsNotSubstantiveButAFactAboutOneIs() {
        XCTAssertFalse(IntentConsolidator.isSubstantive("I've been meaning to do this forever"))
        XCTAssertFalse(IntentConsolidator.isSubstantive("how it's been kind of a mess for a while now"))
        XCTAssertTrue(IntentConsolidator.isSubstantive("remember her birthday is December 4"))
        XCTAssertTrue(IntentConsolidator.isSubstantive("the storage code is 4821"))
    }
}
