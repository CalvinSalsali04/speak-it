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

    func testDayNamedAsPlaceholderTopicDoesNotCreateACommitment() throws {
        for text in ["the whole Thursday thing", "that Friday stuff", "this Monday thing"] {
            let result = ThoughtExtractionEngine.extractWithRules(
                text, referenceDate: referenceDate, calendar: calendar
            )
            XCTAssertTrue(result.operations.isEmpty, text)
            XCTAssertEqual(result.items.count, 1, text)
            let item = try XCTUnwrap(result.items.first)
            XCTAssertEqual(item.rawQuote, text)
            XCTAssertEqual(item.organization.state, .underspecified(.ambiguousTemporalScope), text)
            XCTAssertNil(item.organization.dueDate, text)
            XCTAssertNil(item.organization.reminderDate, text)
            XCTAssertNil(item.organization.recurrenceRule, text)
            XCTAssertTrue(item.organization.needsClarification, text)
        }
    }

    func testExplicitTimingAndActionsAreNotPlaceholderTopics() {
        for text in ["the thing on Tuesday", "the Tuesday meeting",
                     "handle that Thursday thing tomorrow",
                     "remind me tomorrow about that Friday stuff"] {
            XCTAssertNil(TemporalCommitment.unsettled(in: text), text)
            let item = ThoughtOrganizer.organize(text, referenceDate: referenceDate, calendar: calendar)
            XCTAssertNotNil(item.dueDate, text)
        }
    }

    func testPastPossessionComparisonsStayInMemory() {
        for text in [
            "I had better luck last time",
            "I had better service at that hotel",
            "We had better seats at the concert",
            "I had better reception yesterday",
            "I had better overall results last year",
        ] {
            XCTAssertEqual(ActionabilityReader.read(text), .knowledge, text)
            let items = ThoughtExtractionEngine.extractWithRules(
                text, referenceDate: referenceDate, calendar: calendar
            ).items
            XCTAssertEqual(items.count, 1, text)
            XCTAssertEqual(items.first?.analysisText, text, text)
            XCTAssertEqual(items.first?.organization.itemType, .note, text)
            XCTAssertNil(items.first?.organization.dueDate, text)
            XCTAssertNil(items.first?.organization.reminderDate, text)
        }
    }

    func testHadBetterActionsAndExplicitRemindersStillWork() throws {
        for text in [
            "I had better call the bank tomorrow",
            "We had better pay the rent tomorrow",
            "I had better not call the bank tomorrow",
        ] {
            XCTAssertEqual(ActionabilityReader.read(text), .actionable, text)
            let item = ThoughtOrganizer.organize(text, referenceDate: referenceDate, calendar: calendar)
            XCTAssertTrue(item.itemType.isActionable, text)
            XCTAssertNotNil(item.dueDate, text)
        }
        let reminder = ThoughtOrganizer.organize(
            "Remind me tomorrow that I had better luck last time",
            referenceDate: referenceDate, calendar: calendar
        )
        XCTAssertNotNil(reminder.reminderDate)
        XCTAssertEqual(reminder.reminderDelivery, .notification)

        let items = ThoughtExtractionEngine.extractWithRules(
            "I had better luck last time and I need to call the bank tomorrow",
            referenceDate: referenceDate, calendar: calendar
        ).items
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items.first?.organization.itemType, .note)
        let action = try XCTUnwrap(items.last)
        XCTAssertTrue(action.organization.itemType.isActionable)
        XCTAssertEqual(action.organization.dueDate,
                       calendar.date(from: DateComponents(year: 2026, month: 8, day: 4)))
    }

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

    func testSocialMealsAreEventsWithoutChangingFoodPurchases() {
        for text in [
            "Grab lunch with Sam at noon",
            "Get dinner with Maya tomorrow",
            "Grab coffee with Mom tomorrow",
            "grab coffee with mom tomorrow",
        ] {
            let items = ThoughtExtractionEngine.extractWithRules(
                text, referenceDate: referenceDate, calendar: calendar
            ).items
            XCTAssertEqual(items.count, 1, text)
            XCTAssertEqual(items.first?.organization.itemType, .event, text)
            XCTAssertNotNil(items.first?.organization.dueDate, text)
            XCTAssertNil(items.first?.organization.reminderDate, text)
        }
        for text in [
            "Grab lunch with fries at noon",
            "Grab coffee with milk tomorrow",
            "Grab milk with Sam tomorrow",
            "Buy lunch with Sam tomorrow",
            "Grab lunch for Sam tomorrow",
        ] {
            XCTAssertEqual(ThoughtOrganizer.organize(
                text, referenceDate: referenceDate, calendar: calendar
            ).itemType, .shopping, text)
        }
        XCTAssertEqual(ThoughtOrganizer.organize(
            "I grabbed lunch with Sam yesterday",
            referenceDate: referenceDate, calendar: calendar
        ).itemType, .note)
    }

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

    /// A verb the embedding does not know is still a verb when it is a
    /// productive prefix on a stem it does know, and a possessive name is a
    /// determiner. Neither reading may admit a name or a pronoun contraction.
    func testPrefixedVerbsAndPossessiveDeterminersReadAsErrands() {
        for text in ["Descale kettle", "descale kettle", "Unpack boxes", "Give Mom's recipe to Catherine", "Check it's working"] {
            XCTAssertEqual(ActionabilityReader.read(text), .actionable, text)
        }
        for text in ["Devon Smith", "Regina King", "Preston Hall", "Rebecca Miles", "hope he's okay"] {
            XCTAssertNotEqual(ActionabilityReader.read(text), .actionable, text)
        }
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

    // MARK: - Fronted adjuncts

    /// A prepositional phrase in front of the verb is context for the action.
    /// The body the reader tests has to start at the verb, or "on the 15th pay
    /// the rent" is a note about the fifteenth. The test is structural — no
    /// verb and no subject in the span, in the tagging of the whole sentence —
    /// so a coordinated subject or a real clause is left alone.
    func testAFrontedAdjunctIsContextNotTheAction() {
        XCTAssertEqual(ActionabilityReader.actionBody("on the 15th pay the rent"), "pay the rent")
        XCTAssertEqual(ActionabilityReader.actionBody("by friday send the invoice"), "send the invoice")
        XCTAssertEqual(ActionabilityReader.actionBody("after dinner call mom"), "call mom")
        XCTAssertEqual(ActionabilityReader.actionBody("after lunch book the dentist"), "book the dentist")
        XCTAssertEqual(
            ActionabilityReader.actionBody("before the 10th submit the expense report"),
            "submit the expense report"
        )
        XCTAssertEqual(
            ActionabilityReader.actionBody("before and after photos are in the folder"),
            "before and after photos are in the folder"
        )
        // A subject behind the preposition makes it a clause, which the
        // condition reading below owns rather than this one.
        XCTAssertEqual(ActionabilityReader.actionBody("on the fence about the job"), "on the fence about the job")
        // Deictic days, a demonstrative object, and a lowercased name the
        // tagger calls a verb.
        XCTAssertEqual(ActionabilityReader.actionBody("tomorrow morning email the landlord"), "email the landlord")
        XCTAssertEqual(ActionabilityReader.actionBody("after that book the dentist"), "book the dentist")
        XCTAssertEqual(ActionabilityReader.actionBody("tomorrow at 9 call sarah"), "call sarah")
    }

    /// The clause splitter reads the same structure: a verbless head that
    /// opens on a preposition is not a clause, so nothing is cut in front of
    /// the verb that follows it. A head with a verb in it keeps its cut.
    func testTheClauseSplitterDoesNotCutAfterAFrontedAdjunct() {
        XCTAssertEqual(ClauseJuxtaposition.pieces(in: "on the 1st renew the car insurance"),
                       ["on the 1st renew the car insurance"])
        XCTAssertEqual(ClauseJuxtaposition.pieces(in: "in the morning call Dave"),
                       ["in the morning call Dave"])
        XCTAssertEqual(ClauseJuxtaposition.pieces(in: "buy milk call the dentist"),
                       ["buy milk", "call the dentist"])
        XCTAssertEqual(ClauseJuxtaposition.pieces(in: "tomorrow morning email the landlord"),
                       ["tomorrow morning email the landlord"])
    }

    /// An ordinal ends a noun phrase; an amount modifies the noun behind it.
    ///
    /// The guard that reads a digit in front of a verb-shaped word exists for
    /// "the $89 charge", where the number belongs to the phrase that follows.
    /// "The 26th" is finished, and the guard was swallowing the boundary
    /// behind every spoken date, so a fact and the errand it prompted arrived
    /// as one row that kept the fact and lost the errand.
    func testAnOrdinalDoesNotReadAsAnAmountInFrontOfAVerb() {
        XCTAssertEqual(
            ClauseJuxtaposition.pieces(in: "Priya starts on the 14th order her a laptop"),
            ["Priya starts on the 14th", "order her a laptop"]
        )
        XCTAssertEqual(
            ClauseJuxtaposition.pieces(in: "the invoice went out on the 3rd chase the payment"),
            ["the invoice went out on the 3rd", "chase the payment"]
        )
        // A fronted ordinal is still an adjunct, not a clause of its own.
        XCTAssertEqual(
            ClauseJuxtaposition.pieces(in: "on the 1st renew the car insurance"),
            ["on the 1st renew the car insurance"]
        )
    }

    /// An adjunct in front of a cut has to announce itself with a preposition,
    /// and a verbless head ending on a time is not enough on its own.
    ///
    /// Measured on 2026-09-11 (run 34597902006). Accepting any verbless head
    /// that ends on a time — so that "first thing tomorrow email the landlord"
    /// would stop being cut — lost the boundary in both captures below.
    /// `NLTagger` does not reliably call a sentence-initial "book" or "text" a
    /// verb, so a head that is plainly an instruction reads as verbless and
    /// ends on a day, and the rule swallowed the errand behind it. The
    /// preposition is the half of the test the tagger cannot be wrong about.
    ///
    /// The over-split that relaxation was aimed at is real and still open:
    /// "first thing tomorrow email the landlord about the damp" arrives as two
    /// rows. Its root cause is the same vocabulary in `Actionability`, which
    /// routes the merged capture to Memory rather than Today, so the fix
    /// belongs there and wants its own measurement.
    func testAnAdjunctInFrontOfACutNeedsAPrepositionAndNotJustATime() {
        XCTAssertEqual(
            ClauseJuxtaposition.pieces(in: "book the car in for Thursday renew my passport"),
            ["book the car in for Thursday", "renew my passport"]
        )
        XCTAssertEqual(
            ClauseJuxtaposition.pieces(in: "text Marcus about Saturday move the standup to 9:15"),
            ["text Marcus about Saturday", "move the standup to 9:15"]
        )
        // A head with a verb in it is a clause and keeps its cut.
        XCTAssertEqual(
            ClauseJuxtaposition.pieces(in: "buy the milk tomorrow call the dentist"),
            ["buy the milk tomorrow", "call the dentist"]
        )
    }

    /// A complement-taking verb governs the clause behind it, so the verb in
    /// that clause is its predicate rather than a fresh instruction.
    func testAClausalComplementIsNotASecondInstruction() {
        for text in [
            "remind me the bins go out on Tuesday",
            "I told Ines the meeting moved to Thursday",
            "remember the car needs an oil change",
        ] {
            XCTAssertEqual(ClauseJuxtaposition.pieces(in: text), [text], text)
        }
    }

    /// Nothing cuts between two juxtaposed **statements**, and this is the
    /// list any rule that one day does must leave alone.
    ///
    /// A rule was written and measured on 2026-09-11 (run 34596594804). It cut
    /// where the second clause opened on the speaker's own possessive, a
    /// first-person obligation, or a resolved proper name — and it gained
    /// nothing at all on `statement-runon`, the development family it was
    /// written for, which stayed at 0 of 6 on thought count. It also broke four
    /// cases of the gating corpus, and all four say the same thing: a subject
    /// and a predicate in the words in front of the cut **do not make those
    /// words a finished clause**. "I have no idea where" has both and is
    /// plainly unfinished; so does "It reminded me of something", which a
    /// relative clause with no relativizer is about to modify.
    ///
    /// The first block is the original guard list, and it remains the hard
    /// part: structurally these are the same shape as the sentences a
    /// boundary rule wants to cut — complete clause, noun phrase, verb — so
    /// nothing but whether the second half is findable alone separates them,
    /// and a row severed wrongly retrieves under nothing. The second block is
    /// what the measured attempt actually broke, kept here so the next one
    /// fails in a second rather than in a dispatch.
    func testNothingCutsBetweenTwoJuxtaposedStatements() {
        for text in [
            // Findable only through the clause in front of them.
            "the dentist is on Pine Street the parking is round the back",
            "the boiler pressure sits at one bar the manual says one and a half",
            "we booked the Halifax hotel the deposit is non refundable",
            "the car is due its service the mileage limit is thirty thousand",
            "the recipe takes an hour it serves six",
            "Priya moved to the Toronto office she starts on the 14th",
            "our lease runs to March the rent is fixed until then",
            // A head that is unfinished despite carrying a subject and a verb.
            "I have no idea where my passport is",
            "It reminded me of something my dad used to say",
            "I keep telling myself I'll get to it and I never do, anyway I have to renew my passport",
            // A verb of saying or thinking takes the whole clause behind it,
            // whoever it is aimed at.
            "I told Priya yesterday Marcus is bringing the deck",
            "I think Priya is bringing the deck",
            "Sarah said Marcus is chairing the panel this year",
        ] {
            XCTAssertEqual(ClauseJuxtaposition.pieces(in: text), [text], text)
        }
    }

    /// A condition on the speaker in front of the verb is a trigger, and the
    /// body the reader tests starts behind it. A statement behind the
    /// condition is not an errand, and "before I forget" is not a condition.
    func testAFrontedConditionIsATriggerNotTheAction() {
        XCTAssertEqual(ActionabilityReader.actionBody("when I finish the essay call dave"), "call dave")
        XCTAssertEqual(ActionabilityReader.actionBody("after I get paid book the trip"), "book the trip")
        XCTAssertEqual(ActionabilityReader.actionBody("as soon as I land text mom"), "text mom")
        XCTAssertEqual(ActionabilityReader.actionBody("before I forget call dave"), "call dave")
        XCTAssertEqual(
            ActionabilityReader.actionBody("when I was young I loved the beach"),
            "when I was young I loved the beach"
        )
        XCTAssertEqual(ClauseJuxtaposition.pieces(in: "after I finish the essay call Dave"),
                       ["after I finish the essay call Dave"])
    }

    /// A condition with nothing behind it is the whole capture. The subject
    /// sat one token from the end here, and the range the reader walked to
    /// find the body ran backwards — a runtime trap on every one of these at
    /// save time, from voice, typing, Siri and the share sheet alike.
    func testAFrontedConditionWithNoBodyIsLeftAlone() {
        for text in [
            "Every time I sneeze",
            "Every time I stretch",
            "As soon as I",
            "As soon as I can",
            "After that we leave",
            "every time we",
            "when I",
        ] {
            XCTAssertEqual(ActionabilityReader.actionBody(text), text, text)
            XCTAssertNoThrow(ActionabilityReader.read(text), text)
            let items = ThoughtExtractionEngine.extractWithRules(
                text, referenceDate: referenceDate, calendar: calendar
            ).items
            XCTAssertFalse(items.isEmpty, text)
        }
    }

    /// On the right of a conjunction the boundary is the "and": "book the
    /// dentist and before dinner call Mom" used to be cut at "call", so the
    /// first row read "Book the dentist and before dinner" and carried the
    /// second errand's date.
    func testAFrontedAdjunctAfterAConjunctionStaysWithItsErrand() {
        XCTAssertEqual(RuleBasedThoughtExtractor.splitClauses("book the dentist and before dinner call mom"),
                       ["book the dentist", "before dinner call mom"])
        XCTAssertEqual(RuleBasedThoughtExtractor.splitClauses("book the dentist and tomorrow call mom"),
                       ["book the dentist", "tomorrow call mom"])
        XCTAssertEqual(RuleBasedThoughtExtractor.splitClauses("I called the plumber and he never showed"),
                       ["I called the plumber and he never showed"])
    }
}
