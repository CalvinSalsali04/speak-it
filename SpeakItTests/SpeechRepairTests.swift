import XCTest
@testable import SpeakIt

/// String-level tests for the repairs in `SpeechRepair.swift`.
///
/// The semantic corpus already covers what a repaired sentence *means*, and
/// that is the right gate for most of this file. It is the wrong gate for two
/// kinds of defect:
///
/// - A repair that deletes words but changes nothing else. Every gating field
///   agrees, and the corpus reports the difference as COSMETIC — but the words
///   are gone from the row title and, in the worst cases, from the quote.
/// - A repair that must *not* fire. Proving a rewrite did not happen needs the
///   string, not a field comparison.
///
/// Both are asserted here, where the contract is exactly string in, string out.
final class SpeechRepairTests: XCTestCase {

    // MARK: - Split compounds

    /// The recognizer writes one word as two when it hears a pause inside it.
    /// Every temporal alternation in the app matches whole tokens, so a split
    /// temporal is invisible to all of them. See corpus family 39.
    func testASplitCompoundIsRejoined() {
        let cases: [(String, String)] = [
            ("To morrow at nine, ask Maya about the proposal.",
             "Tomorrow at nine, ask Maya about the proposal."),
            ("Call the dentist to morrow.", "Call the dentist tomorrow."),
            ("To night at eight, call Mom.", "Tonight at eight, call Mom."),
            ("To day at four, send the invoice.", "Today at four, send the invoice."),
            ("Buy milk this week end.", "Buy milk this weekend."),
            ("Set an alarm for mid night.", "Set an alarm for midnight."),
            ("Her birth day is in June.", "Her birthday is in June."),
        ]
        for (input, expected) in cases {
            XCTAssertEqual(SplitCompoundRepair.rejoined(input), expected, "input: \(input)")
        }
    }

    /// Case is carried from the fragment the recognizer capitalized, so a
    /// sentence-leading repair still reads as a sentence.
    func testRejoiningKeepsTheCaseTheRecognizerUsed() {
        XCTAssertEqual(SplitCompoundRepair.rejoined("to morrow"), "tomorrow")
        XCTAssertEqual(SplitCompoundRepair.rejoined("To morrow"), "Tomorrow")
        XCTAssertEqual(SplitCompoundRepair.rejoined("To Morrow"), "Tomorrow")
        XCTAssertEqual(SplitCompoundRepair.rejoined("to morrow's deadline"), "tomorrow's deadline")
    }

    /// The reason this is a gated rule and not a word list. Each of these is a
    /// real phrase whose meaning a rejoin would destroy.
    func testSpacedPairsThatAreOrdinaryEnglishAreLeftAlone() {
        let untouched = [
            // "to day"/"to night" inside a range: the "to" belongs to the span.
            "Our day to day operations need a review.",
            "The shift runs from dusk to night.",
            "We moved the standup from morning to night.",
            "He works from dawn to night on the farm.",
            // Pairs that are simply two words, and mean something else joined.
            "I need some time to think about the offer.",
            "Call the clinic any time after noon.",
            "I go for a walk every day.",
            "I do not want to do this any more.",
            // A word boundary the rejoin must respect.
            "The week ended badly.",
        ]
        for text in untouched {
            XCTAssertEqual(SplitCompoundRepair.rejoined(text), text, "must not be rewritten")
        }
    }

    // MARK: - Self-correction

    /// "actually" is an ordinary adverb far more often than a repair
    /// announcement. Treating it as one licensed the resolver to discard the
    /// words in front of it, which deleted the subject of the sentence.
    func testActuallyAsAnOrdinaryAdverbKeepsTheSentence() {
        let untouched = [
            "tell Sam the client actually approved it",
            "check whether the standing desk actually helps",
            "the deploy actually went fine",
            "the numbers actually improved last quarter",
            "research whether standing desks actually do anything",
            "i actually finished the report",
            "she actually said yes",
        ]
        for text in untouched {
            XCTAssertEqual(SelfCorrectionResolver.resolved(text), text, "must not be rewritten")
        }
    }

    /// The other half: a genuine unpunctuated repair is still found and placed.
    /// "actually" stays in the detection pattern; what it no longer does on its
    /// own is license a discard. `repairSlot` and `echoesThePrefix` are the
    /// evidence that a repair was actually meant.
    func testAGenuineCorrectionAfterActuallyStillResolves() {
        XCTAssertEqual(
            SelfCorrectionResolver.resolved("meeting at three actually four"),
            "meeting at four"
        )
        XCTAssertEqual(
            SelfCorrectionResolver.resolved("buy oat milk actually almond milk"),
            "buy almond milk"
        )
        XCTAssertEqual(
            SelfCorrectionResolver.resolved("call Sarah actually call Alex"),
            "call Alex"
        )
    }

    /// The negation cases the resolver used to invert. An allergy note is the
    /// worst possible place to drop a "no".
    func testOrdinaryNoIsNotReadAsACorrection() {
        let untouched = [
            "Sarah has no dairy at all",
            "she has no shellfish allergy",
            "the venue has no wheelchair access",
            "we have no milk left",
            "the office is closed this week so no standup",
            "I have no idea what the code is",
        ]
        for text in untouched {
            XCTAssertEqual(SelfCorrectionResolver.resolved(text), text, "must not be rewritten")
        }
    }
}
