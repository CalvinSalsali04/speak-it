import XCTest
@testable import SpeakIt

/// What the deterministic layer does with a reading once it has been accepted.
///
/// The claim these tests exist to hold: the generative path can only ever take
/// capability away from a row. It decides which words belong together and what
/// the speaker was doing with them; every date, type, category and trigger on
/// the row is produced by `ThoughtOrganizer`, the same function the rules path
/// calls, and the overrides run in one direction.
final class InterpretationBridgeTests: XCTestCase {

    /// Monday 2026-08-03 10:00 America/Toronto — the frame `SemanticCorpusTests`
    /// and the pipeline probe use, pinned here for the same reason: CI runners
    /// and travelling Macs are not in Toronto.
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Toronto")!
        return calendar
    }()

    private var referenceDate: Date {
        calendar.date(from: DateComponents(year: 2026, month: 8, day: 3, hour: 10, minute: 0))!
    }

    private func row(_ segment: InterpretedSegment) -> InterpretationBridge.Row {
        InterpretationBridge.row(for: segment, referenceDate: referenceDate, calendar: calendar)
    }

    // MARK: The deterministic half still does the resolving

    /// The load-bearing case. The interpretation contains the word "tomorrow"
    /// and no date; the row has a reminder, because `ThoughtOrganizer` read the
    /// word. Nothing the model returns can be a date, because the schema has no
    /// field for one.
    func testAStatedObligationKeepsExactlyWhatTheOrganizerResolved() {
        let segment = InterpretedSegment(
            quote: "email the landlord tomorrow at 3 PM",
            carriedContext: "remind me to",
            obligation: .speakerOwes,
            temporalText: "tomorrow at 3 PM",
            temporalRole: .reminderRequest,
            suggestedTitle: "Email the landlord"
        )
        let result = row(segment)
        let deterministic = ThoughtOrganizer.organize(
            segment.analysisText, referenceDate: referenceDate, calendar: calendar
        )
        // Stated, first-person, owed: nothing is withdrawn, so the row is
        // exactly the reading the rules path would have produced from the same
        // words. The interpretation supplied which words, and nothing else.
        XCTAssertFalse(result.demoted)
        XCTAssertEqual(result.thought.organization, deterministic)
        XCTAssertEqual(result.thought.suggestedTitle, "Email the landlord")
    }

    // MARK: The overrides only ever withdraw

    func testReportedSpeechKeepsTheWordsAndLosesTheSchedule() {
        let result = row(InterpretedSegment(
            quote: "she'd drop off the keys tomorrow",
            disposition: .reported,
            obligation: .otherOwes,
            attributedTo: "priya",
            temporalText: "tomorrow",
            temporalRole: .eventTime
        ))
        XCTAssertFalse(result.thought.organization.itemType.isActionable)
        XCTAssertNil(result.thought.organization.reminderDate)
        XCTAssertNil(result.thought.organization.dueDate)
        XCTAssertEqual(result.thought.organization.reminderDelivery, .none)
        XCTAssertEqual(result.thought.organization.state.gap, .reportedSpeech)
        XCTAssertTrue(result.thought.needsReview)
        // The person's words survive. A quoted sentence is still worth keeping;
        // it is only not an errand.
        XCTAssertEqual(result.thought.sourceQuote, "she'd drop off the keys tomorrow")
    }

    func testAnAbandonedThoughtIsKeptAndSaysWhyItWasWithheld() {
        let result = row(InterpretedSegment(
            quote: "I need to ring the",
            disposition: .abandoned,
            obligation: .speakerOwes
        ))
        XCTAssertNil(result.thought.organization.reminderDate)
        XCTAssertEqual(result.thought.organization.state.gap, .incompleteThought)
        XCTAssertTrue(result.thought.needsReview)
    }

    /// Someone else's errand, said in the speaker's own voice, is still not the
    /// speaker's errand — and this is the half the disposition cannot catch,
    /// because the sentence is perfectly well-formed and finished.
    func testSomebodyElsesObligationDoesNotBecomeATask() {
        let result = row(InterpretedSegment(
            quote: "Dmitri needs to file the permit",
            obligation: .otherOwes,
            personNamed: "Dmitri"
        ))
        XCTAssertFalse(result.thought.organization.itemType.isActionable)
        XCTAssertNil(result.thought.organization.reminderDate)
    }

    func testAHypotheticalNeverSchedules() {
        let result = row(InterpretedSegment(
            quote: "I might email the landlord tomorrow",
            disposition: .hypothetical,
            obligation: .speakerOwes,
            temporalText: "tomorrow",
            temporalRole: .deadline
        ))
        XCTAssertNil(result.thought.organization.reminderDate)
        XCTAssertNil(result.thought.organization.recurrenceRule)
        XCTAssertNil(result.thought.organization.locationIntent)
    }

    // MARK: The role fields are read, not merely recorded

    /// "Ask Dmitri about Friday" has a weekday in it and nothing due. The rules
    /// reach that by inference and get it wrong often enough that the family
    /// has a name; when the interpretation says outright that the time is the
    /// topic, the schedule comes off whatever the organizer resolved.
    func testATimeThatIsTheTopicSchedulesNothing() {
        let result = row(InterpretedSegment(
            quote: "ask Dmitri about Friday",
            obligation: .speakerOwes,
            temporalText: "Friday",
            temporalRole: .topic,
            personNamed: "Dmitri"
        ))
        XCTAssertNil(result.thought.organization.dueDate)
        XCTAssertNil(result.thought.organization.reminderDate)
        XCTAssertEqual(result.thought.organization.reminderDelivery, .none)
        XCTAssertNil(result.thought.organization.recurrenceRule)
    }

    /// A standing fact's clock is not a repeating errand.
    func testAStandingFactDoesNotRecur() {
        let result = row(InterpretedSegment(
            quote: "the nursery closes at six on weekdays",
            obligation: .noObligation,
            temporalText: "at six on weekdays",
            temporalRole: .standingFact
        ))
        XCTAssertNil(result.thought.organization.recurrenceRule)
        XCTAssertNil(result.thought.organization.reminderDate)
    }

    /// Only an arrival or a departure keeps a place trigger. A place the person
    /// merely named cannot arm a geofence through this path — and neither can a
    /// segment where the model named no role at all, which is the cost of that
    /// rule and is chosen: a geofence on a mentioned place is the failure
    /// nobody can undo.
    func testOnlyAnArrivalOrDepartureKeepsAPlaceTrigger() {
        let mentioned = row(InterpretedSegment(
            quote: "email the landlord about the Steeles office",
            obligation: .speakerOwes,
            locationText: "the Steeles office",
            locationRole: .mention
        ))
        XCTAssertNil(mentioned.thought.organization.locationIntent)

        let unnamed = row(InterpretedSegment(
            quote: "email the landlord when I get to the office",
            obligation: .speakerOwes
        ))
        XCTAssertNil(unnamed.thought.organization.locationIntent)
    }

    /// The asymmetry that decides this one: a reminder nobody asked for is
    /// loud and dismissed in a tap, and a deadline quietly dropped is never
    /// seen again. So an unsettled actor keeps whatever the rules resolved and
    /// is shown to the person instead.
    func testAnUnsettledActorKeepsItsScheduleAndIsFlagged() {
        let segment = InterpretedSegment(
            quote: "the permit filing by Friday at 3 PM",
            obligation: .unclear,
            temporalText: "Friday at 3 PM",
            temporalRole: .deadline
        )
        let result = row(segment)
        let deterministic = ThoughtOrganizer.organize(
            segment.analysisText, referenceDate: referenceDate, calendar: calendar
        )
        XCTAssertEqual(result.thought.organization.dueDate, deterministic.dueDate)
        XCTAssertEqual(result.thought.organization.reminderDate, deterministic.reminderDate)
        XCTAssertTrue(result.thought.organization.needsClarification)
        XCTAssertTrue(result.thought.needsReview)
    }

    // MARK: Which segments become rows

    func testCorrectedAndAsideSpansProduceNoRows() {
        let interpretation = CaptureInterpretation(segments: [
            InterpretedSegment(quote: "order the oat flour", disposition: .corrected, supersededBy: "order the rye flour"),
            InterpretedSegment(quote: "order the rye flour", obligation: .speakerOwes),
            InterpretedSegment(quote: "anyway where was I going with this", disposition: .aside, obligation: .noObligation),
        ])
        let rows = InterpretationBridge.rows(
            for: interpretation, referenceDate: referenceDate, calendar: calendar
        )
        XCTAssertEqual(rows.map(\.thought.sourceQuote), ["order the rye flour"])
    }

    func testAnAbandonedSpanStillProducesARow() {
        let interpretation = CaptureInterpretation(segments: [
            InterpretedSegment(quote: "collect the dry cleaning stub", obligation: .speakerOwes),
            InterpretedSegment(quote: "and I should also probably", disposition: .abandoned),
        ])
        let rows = InterpretationBridge.rows(
            for: interpretation, referenceDate: referenceDate, calendar: calendar
        )
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows.last?.disposition, .abandoned)
    }

    // MARK: Operations

    func testAnOperationOnlyTheModelSawArrivesNeedingReview() {
        let interpretation = CaptureInterpretation(operations: [
            InterpretedOperation(kind: .cancel, quote: "cancel the roof inspection", targetText: "the roof inspection")
        ])
        let requests = InterpretationBridge.operations(for: interpretation, rulesRead: [])
        XCTAssertEqual(requests.count, 1)
        XCTAssertTrue(requests[0].needsReview)
        XCTAssertEqual(requests[0].target, "the roof inspection")
    }

    func testAnOperationBothReadingsFoundDoesNotNeedReview() {
        let interpretation = CaptureInterpretation(operations: [
            InterpretedOperation(kind: .cancel, quote: "cancel the roof inspection", targetText: "the roof inspection")
        ])
        let requests = InterpretationBridge.operations(for: interpretation, rulesRead: [.cancel])
        XCTAssertFalse(requests[0].needsReview)
    }

    func testABroadRequestAlwaysNeedsReviewAndIsMarkedBroad() {
        let interpretation = CaptureInterpretation(operations: [
            InterpretedOperation(
                kind: .cancel, quote: "scrap every single reminder", targetText: "every single reminder", scope: .broad
            )
        ])
        let requests = InterpretationBridge.operations(for: interpretation, rulesRead: [.cancel])
        XCTAssertTrue(requests[0].isBroad)
        XCTAssertTrue(requests[0].needsReview)
    }

    /// A reschedule keeps the person's words for the new moment and never a
    /// resolved one: "an hour" means an hour from the item's scheduled time,
    /// which cannot be known without the store.
    func testARescheduleCarriesWordsRatherThanAMoment() {
        let interpretation = CaptureInterpretation(operations: [
            InterpretedOperation(
                kind: .reschedule,
                quote: "push the roof inspection back an hour",
                targetText: "the roof inspection",
                newTimingText: "an hour"
            )
        ])
        let requests = InterpretationBridge.operations(for: interpretation, rulesRead: [.reschedule])
        XCTAssertEqual(requests[0].newTimingText, "an hour")
    }

    // MARK: Confidence

    /// Confidence widens review and never narrows it: a model that is sure is
    /// not thereby allowed to skip a check.
    func testLowConfidenceAddsReviewAndHighConfidenceRemovesNone() {
        let unsure = row(InterpretedSegment(
            quote: "email the landlord", obligation: .speakerOwes, confidencePercent: 40
        ))
        XCTAssertTrue(unsure.thought.needsReview)

        let sure = row(InterpretedSegment(
            quote: "she'd drop off the keys",
            disposition: .reported,
            obligation: .otherOwes,
            confidencePercent: 100
        ))
        XCTAssertTrue(sure.thought.needsReview)
    }
}
