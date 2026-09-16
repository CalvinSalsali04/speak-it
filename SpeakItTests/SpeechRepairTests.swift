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

    func testHesitationDoesNotBreakCommandComplements() {
        for (input, expected) in [
            ("set alarm, um, for one hour from now", "set alarm for one hour from now"),
            ("please wake, um, me up at seven thirty am", "please wake me up at seven thirty am"),
            ("please sound, um, an alarm", "please sound an alarm"),
            ("I wanna, um, get up at six am", "I wanna get up at six am"),
            ("Today when, um, I go shopping", "Today when I go shopping"),
            ("call Maya, um, email Alex", "call Maya, email Alex"),
            ("Do not, um, call Maya", "Do not call Maya"),
        ] {
            XCTAssertEqual(DisfluencyFilter.stripped(input), expected)
        }
        let fluent = "Today we have a few errands that we need to do number one we need to call Maya"
        for source in ["Um, " + fluent, fluent.replacingOccurrences(of: "we have", with: "we, um, have")] {
            XCTAssertEqual(DisfluencyFilter.stripped(source), DisfluencyFilter.stripped(fluent))
        }
    }

    func testListIntroductionNeedsAnOrdinalAndFollowingAction() {
        XCTAssertEqual(DisfluencyFilter.stripped(
            "Tomorrow we have several errands that we need to do first we need to go to Cedar Lane"),
            "Tomorrow. we need to go to Cedar Lane")
        for source in ["We have a couple goals that we need to accomplish",
                       "We have several goals that we need to accomplish number one is better sleep",
                       "After we eat we need to call Mom",
                       "We need to go after we finish work"] {
            XCTAssertEqual(DisfluencyFilter.stripped(source), source)
        }
    }

    func testRepeatedUnfinishedTravelFrameKeepsContext() {
        XCTAssertEqual(
            SelfCorrectionResolver.resolved("Today when I go shopping, I want to go to or actually first I wanna go to Lucky star"),
            "Today when I go shopping, I wanna go to Lucky star"
        )
        XCTAssertEqual(
            SelfCorrectionResolver.resolved("Tomorrow I need to drive to, sorry I want to drive to the office"),
            "Tomorrow I want to drive to the office"
        )
        for text in ["I want to go to Reading or actually stay home",
                     "I want to go to", "I do not want to go to the mall"] {
            XCTAssertEqual(SelfCorrectionResolver.resolved(text), text)
        }
    }

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

    /// "I was thinking" is two different things and the strip treated them as
    /// one.
    ///
    /// In front of a clause the speaker owes it is throat-clearing and comes
    /// off. In front of its own complement it is the sentence's verb, and the
    /// modality lives in it: "I was thinking of calling Priya" says the errand
    /// was contemplated, not committed to. Removing it left "of calling
    /// Priya" — a fragment with no sign that anything was hedged, in a set
    /// where that hedge is the whole label.
    func testContemplationIsNotThroatClearing() {
        for text in [
            "I was thinking of calling Priya",
            "I was thinking about the wedding",
            "I was thinking about calling Mike",
        ] {
            XCTAssertEqual(DisfluencyFilter.stripped(text), text, "the hedge must survive")
        }
    }

    /// The other half, which the fix must not take with it.
    ///
    /// The last case is why the rule needs a complement and not just a
    /// preposition: "I was thinking about" with nothing behind it has to keep
    /// stripping, because the lone "about" it leaves is what
    /// `ClauseStructure.unfinished` reads as a trailing function word. That is
    /// how an abandoned thought is recognised instead of becoming an errand.
    func testThroatClearingStillComesOff() {
        for (input, expected) in [
            ("I was thinking, buy milk", "buy milk"),
            ("I was thinking it might make sense to add a dark mode",
             "it might make sense to add a dark mode"),
            ("I was thinking about", "about"),
        ] {
            XCTAssertEqual(DisfluencyFilter.stripped(input), expected)
        }
    }

    /// The two rules as one chain, executed rather than read.
    ///
    /// `testThroatClearingStillComesOff` asserts what the repair produces and
    /// the comment above it asserts what the next stage does with it. Nobody
    /// had run the second half: the claim that the lone "about" is read as a
    /// trailing function word was a reading of `ClauseStructure`, twice, by
    /// two people. Two readings agreeing is not a measurement.
    ///
    /// This is also the guard on the trailing `\S` in the repair rule, from
    /// the far side. Remove it and "I was thinking about" stops stripping,
    /// arrives here as four tokens, falls to the multi-token path — which
    /// accepts `.determiner` and not `.preposition` — and returns nil. Both
    /// assertions below fail, and an abandoned thought would have become an
    /// errand.
    func testTheRepairAndTheFragmentRuleAreOneChain() {
        let abandoned = DisfluencyFilter.stripped("I was thinking about")
        XCTAssertEqual(abandoned, "about", "the repair must leave the bare marker")
        XCTAssertEqual(
            ThoughtCompletion.unfinished(in: abandoned),
            .trailingFunctionWord,
            "the token the repair produces must be the one this branch reads"
        )
    }

    /// And the contemplation the fix preserves is not a fragment either.
    ///
    /// The hedge survives the repair, so what reaches the next stage is a whole
    /// sentence. Asserted because "keeps the words" and "is still read as
    /// finished" are two different claims and only the first was tested.
    func testThePreservedHedgeIsNotReadAsUnfinished() {
        let kept = DisfluencyFilter.stripped("I was thinking of calling Priya")
        XCTAssertEqual(kept, "I was thinking of calling Priya")
        XCTAssertNil(
            ThoughtCompletion.unfinished(in: kept),
            "a preserved hedge is a finished sentence, not a trailing fragment"
        )
    }
}
