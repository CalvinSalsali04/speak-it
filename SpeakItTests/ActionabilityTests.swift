import XCTest
@testable import SpeakIt

/// Pins the two rules that justify `Actionability` existing at all.
///
/// The semantic corpus already proves the *outcomes* — which surface a sentence
/// lands on, which date survives. These tests exist one level down, on the
/// reading itself, because the corpus can only say that something went wrong,
/// not which of the two questions was answered badly. When "Get shampoo
/// tomorrow" lost its due date, the corpus reported a missing date and the real
/// fault was a type guess three steps upstream.
@MainActor
final class ActionabilityTests: XCTestCase {

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Toronto")!
        return calendar
    }

    private var referenceDate: Date {
        calendar.date(from: DateComponents(year: 2026, month: 8, day: 3, hour: 10, minute: 0))!
    }

    // MARK: Invariant 1 — time never promotes history

    /// A temporal expression is evidence about actionability, never a source of
    /// it. Every sentence here names a clock or a day and every one of them is
    /// a report of something that already happened.
    func testTimeDoesNotMakeHistoryActionable() {
        let history = [
            "Catherine called me at five",
            "I called Catherine at five",
            "I met Alex yesterday",
            "I already paid the rent on Friday",
            "Alex texted me this morning",
            "Mom said the party is Saturday",
            "I didn't call Catherine because she cancelled",
        ]
        for utterance in history {
            XCTAssertEqual(
                ActionabilityReader.read(utterance), .knowledge,
                "\"\(utterance)\" is a record of the past and must stay one"
            )
            let organized = ThoughtOrganizer.organize(
                utterance, referenceDate: referenceDate, calendar: calendar
            )
            XCTAssertFalse(
                organized.itemType.isActionable,
                "\"\(utterance)\" must not reach Today"
            )
            XCTAssertEqual(
                organized.reminderDelivery, .none,
                "\"\(utterance)\" must not schedule anything"
            )
        }
    }

    /// The other half of the same rule: a past-tense frame around something
    /// that did *not* happen leaves the obligation exactly where it was.
    func testUnfulfilledObligationsStayOutstanding() {
        let outstanding = [
            "I forgot to call Catherine at five",
            "I was supposed to submit it Friday",
            "I never called Catherine",
            "I still haven't submitted the form",
            "I keep forgetting to renew my passport",
        ]
        for utterance in outstanding {
            XCTAssertEqual(
                ActionabilityReader.read(utterance), .outstanding,
                "\"\(utterance)\" is still owed"
            )
            XCTAssertTrue(
                ThoughtOrganizer.organize(
                    utterance, referenceDate: referenceDate, calendar: calendar
                ).itemType.isActionable,
                "\"\(utterance)\" belongs on Today"
            )
        }
    }

    // MARK: Invariant 2 — actionable intent keeps its time

    /// The regression this layer was built for. Each of these resolves a date
    /// cleanly; none of them is worded in a way the type rules recognised, and
    /// before the split that was enough to throw the date away.
    func testActionableIntentNeverLosesAResolvedDate() {
        let cases: [(String, Int)] = [
            ("Get shampoo tomorrow", 4),
            ("Grab batteries tomorrow", 4),
            ("Do this Friday", 7),
            ("I gotta finish the essay by Friday", 7),
            ("I was meant to send the invoice Friday", 7),
            ("Dentist Tuesday at 2", 4),
        ]
        for (utterance, expectedDay) in cases {
            let organized = ThoughtOrganizer.organize(
                utterance, referenceDate: referenceDate, calendar: calendar
            )
            guard let due = organized.dueDate else {
                XCTFail("\"\(utterance)\" resolved a date and then discarded it")
                continue
            }
            XCTAssertEqual(
                calendar.component(.day, from: due), expectedDay,
                "\"\(utterance)\" kept a date, but not the one it stated"
            )
        }
    }

    /// A day without a time must not acquire one. Silently promoting "tomorrow"
    /// to 9 AM invents a commitment the person never made, and it is the exact
    /// failure the date-only kind exists to prevent.
    func testDateOnlyActionsDoNotInventAnAlertTime() {
        for utterance in ["Get shampoo tomorrow", "Grab batteries tomorrow", "Do this Friday"] {
            let organized = ThoughtOrganizer.organize(
                utterance, referenceDate: referenceDate, calendar: calendar
            )
            XCTAssertNil(organized.reminderDate, "\"\(utterance)\" asked for no reminder")
            XCTAssertEqual(organized.reminderDelivery, .none)
            XCTAssertEqual(organized.temporalIntent.kind, .dateOnly)
        }
    }

    // MARK: The reading is not the taxonomy

    /// Actionability and type answer different questions, so they must be free
    /// to disagree. A shopping item and a bare appointment are both Today; an
    /// idea and a fact are both Memory; the type still distinguishes all four.
    func testTypeAndActionabilityAreSeparateAxes() {
        XCTAssertEqual(ActionabilityReader.read("Get shampoo tomorrow"), .actionable)
        XCTAssertEqual(ActionabilityReader.read("Dentist Tuesday at 2"), .event)
        XCTAssertEqual(ActionabilityReader.read("Remember Alex likes golf"), .knowledge)
        XCTAssertEqual(ActionabilityReader.read("Basketball statistics app idea"), .ambiguous)

        XCTAssertEqual(
            ThoughtOrganizer.organize("Get shampoo tomorrow", referenceDate: referenceDate, calendar: calendar).itemType,
            .shopping
        )
        XCTAssertEqual(
            ThoughtOrganizer.organize("Dentist Tuesday at 2", referenceDate: referenceDate, calendar: calendar).itemType,
            .event
        )
    }

    func testEpistemicIdeaLanguageIsNotAProposal() throws {
        let text = "I have no idea where my passport is"
        let organized = ThoughtOrganizer.organize(
            text, referenceDate: referenceDate, calendar: calendar
        )
        XCTAssertEqual(organized.itemType, .note)

        let extracted = try XCTUnwrap(
            ThoughtExtractionEngine.extractWithRules(
                text, referenceDate: referenceDate, calendar: calendar
            ).items.first
        )
        XCTAssertEqual(extracted.analysisText, text)
        XCTAssertEqual(extracted.organization.itemType, .note)
    }

    /// `ambiguous` is not `knowledge`. A reading with no opinion must never
    /// demote a type that was read from the wording.
    ///
    /// "The meeting was moved to Thursday" used to be the example here, and it
    /// now reads `.event` outright: a copular sentence about a scheduled thing
    /// on a stated day is a commitment, which is what stopped "the party is
    /// Saturday" from losing its date. The outcome this test was written to
    /// protect — the type and the day both survive — is unchanged, so it is
    /// asserted below rather than deleted, and the invariant itself is pinned
    /// separately by a sentence that really does read `.ambiguous`.
    func testAmbiguousReadingNeverDemotesAType() {
        let organized = ThoughtOrganizer.organize(
            "The meeting was moved to Thursday", referenceDate: referenceDate, calendar: calendar
        )
        XCTAssertEqual(ActionabilityReader.read("The meeting was moved to Thursday"), .event)
        XCTAssertEqual(organized.itemType, .event)
        XCTAssertEqual(
            organized.dueDate.map { calendar.component(.day, from: $0) }, 6,
            "a commitment must keep the day it was moved to"
        )

        // The invariant proper: no opinion, and the type read from the wording
        // survives it.
        XCTAssertEqual(ActionabilityReader.read("Basketball statistics app idea"), .ambiguous)
        XCTAssertEqual(
            ThoughtOrganizer.organize(
                "Basketball statistics app idea", referenceDate: referenceDate, calendar: calendar
            ).itemType,
            .idea,
            "an ambiguous reading must not demote a type the wording already gave"
        )
    }

    // MARK: Memoisation

    /// `ThoughtOrganizer.organize` memoises by its full input, because hot
    /// render paths re-derive the same reading every frame. The memo must be
    /// invisible: identical inputs return the identical reading, and inputs
    /// differing only in reference date or calendar must never bleed into each
    /// other's cached entries.
    func testOrganizeMemoisationKeepsReadingsIndependent() {
        let text = "Remind me to call Ana tomorrow at 5pm"

        let first = ThoughtOrganizer.organize(text, referenceDate: referenceDate, calendar: calendar)
        let repeated = ThoughtOrganizer.organize(text, referenceDate: referenceDate, calendar: calendar)
        XCTAssertEqual(first, repeated, "a cache hit must be indistinguishable from a fresh reading")

        let laterReference = referenceDate.addingTimeInterval(48 * 60 * 60)
        let later = ThoughtOrganizer.organize(text, referenceDate: laterReference, calendar: calendar)
        XCTAssertNotEqual(
            first.reminderDate, later.reminderDate,
            "\"tomorrow\" from a different reference day must not reuse the earlier day's entry"
        )

        var vancouver = Calendar(identifier: .gregorian)
        vancouver.timeZone = TimeZone(identifier: "America/Vancouver")!
        let shifted = ThoughtOrganizer.organize(text, referenceDate: referenceDate, calendar: vancouver)
        XCTAssertNotEqual(
            first.reminderDate, shifted.reminderDate,
            "the same wall clock in a different zone must not reuse the earlier zone's entry"
        )
    }
}
