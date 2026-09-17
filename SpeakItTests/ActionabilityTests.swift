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

    // MARK: Conditional intent safety

    func testUnsupportedConditionsStayAttachedAndCannotExecute() throws {
        for text in [
            "If Sarah replies, remind me to call Mike.",
            "When Priya responds, remind me to submit the form.",
            "Once the package arrives, inspect it.",
            "Unless Dana objects, publish the note.",
            "Call Mike if Sarah replies.",
            "If they call text me.",
            "Well, if Marco replies, then remind me to buy dish soap!",
            "IF MARCO REPLIES, REMIND ME TO BUY DISH SOAP.",
        ] {
            let result = ThoughtExtractionEngine.extractWithRules(
                text, referenceDate: referenceDate, calendar: calendar
            )
            XCTAssertTrue(result.operations.isEmpty, text)
            XCTAssertEqual(result.items.count, 1, text)
            let item = try XCTUnwrap(result.items.first)
            XCTAssertEqual(item.organization.state, .unsupported(.unsupportedCondition), text)
            XCTAssertEqual(item.organization.temporalIntent.unsupportedTrigger, .condition, text)
            XCTAssertTrue(item.needsReview, text)
            XCTAssertNil(item.organization.dueDate, text)
            XCTAssertNil(item.organization.reminderDate, text)
            XCTAssertEqual(item.organization.reminderDelivery, .none, text)
            XCTAssertNil(item.organization.recurrenceRule, text)
            XCTAssertNotNil(item.suggestedTitle, text)
        }
    }

    func testConditionalScopeCoversConsequencesButNotSiblingsOrLaterSentences() {
        let several = ThoughtExtractionEngine.extractWithRules(
            "If Sarah replies, call Mike and text Priya.",
            referenceDate: referenceDate,
            calendar: calendar
        ).items
        XCTAssertEqual(several.count, 2)
        XCTAssertTrue(several.allSatisfy { $0.organization.state == .unsupported(.unsupportedCondition) })
        XCTAssertTrue(several.allSatisfy { $0.analysisText.lowercased().hasPrefix("if sarah replies") })

        let mixed = ThoughtExtractionEngine.extractWithRules(
            "Buy milk, and if Sarah replies, call Mike.",
            referenceDate: referenceDate,
            calendar: calendar
        ).items
        XCTAssertEqual(mixed.count, 2)
        XCTAssertEqual(mixed.first?.organization.state, .resolved)
        XCTAssertEqual(mixed.last?.organization.state, .unsupported(.unsupportedCondition))

        let stopped = ThoughtExtractionEngine.extractWithRules(
            "If Sarah replies, call Mike. Buy milk.",
            referenceDate: referenceDate,
            calendar: calendar
        ).items
        XCTAssertEqual(stopped.count, 2)
        XCTAssertEqual(stopped.first?.organization.state, .unsupported(.unsupportedCondition))
        XCTAssertEqual(stopped.last?.organization.state, .resolved)
    }

    func testAClockDoesNotTurnAnEventConditionIntoAnUnconditionalReminder() throws {
        let result = ThoughtExtractionEngine.extractWithRules(
            "If Sarah replies, remind me at five to call Mike.",
            referenceDate: referenceDate,
            calendar: calendar
        )
        XCTAssertEqual(result.items.count, 1)
        let item = try XCTUnwrap(result.items.first)
        XCTAssertEqual(item.organization.state, .unsupported(.unsupportedCondition))
        XCTAssertNil(item.organization.dueDate)
        XCTAssertNil(item.organization.reminderDate)
        XCTAssertNil(item.organization.recurrenceRule)
        XCTAssertEqual(item.organization.reminderDelivery, .none)
    }

    func testSupportedLocationAndTemporalConditionsKeepTheirExistingBehavior() throws {
        let atHomeItems = ThoughtExtractionEngine.extractWithRules(
            "When I get home, call Mike.",
            referenceDate: referenceDate,
            calendar: calendar
        ).items
        XCTAssertEqual(atHomeItems.count, 1)
        let atHome = try XCTUnwrap(atHomeItems.first)
        XCTAssertEqual(atHome.organization.state, .resolved)
        XCTAssertNotNil(atHome.organization.locationIntent)
        XCTAssertNotEqual(atHome.organization.temporalIntent.unsupportedTrigger, .condition)

        let afterLunchItems = ThoughtExtractionEngine.extractWithRules(
            "After lunch, call Mike.",
            referenceDate: referenceDate,
            calendar: calendar
        ).items
        XCTAssertEqual(afterLunchItems.count, 1)
        let afterLunch = try XCTUnwrap(afterLunchItems.first)
        XCTAssertEqual(afterLunch.organization.state, .resolved)
        XCTAssertNotNil(afterLunch.organization.dueDate)
        XCTAssertNotEqual(afterLunch.organization.temporalIntent.unsupportedTrigger, .condition)
    }

    func testCorrectionRetainsConditionAndWithdrawalRemovesOnlyConditionalGroup() throws {
        let correctedItems = ThoughtExtractionEngine.extractWithRules(
            "If Sarah replies, call Mike, actually text him.",
            referenceDate: referenceDate,
            calendar: calendar
        ).items
        XCTAssertEqual(correctedItems.count, 1)
        let corrected = try XCTUnwrap(correctedItems.first)
        XCTAssertTrue(corrected.analysisText.lowercased().contains("if sarah replies"))
        XCTAssertTrue(corrected.analysisText.lowercased().contains("text him"))
        XCTAssertFalse(corrected.analysisText.lowercased().contains("call mike"))
        XCTAssertEqual(corrected.organization.state, .unsupported(.unsupportedCondition))

        let withdrawn = ThoughtExtractionEngine.extractWithRules(
            "Buy milk, and if Sarah replies, call Mike, actually forget that.",
            referenceDate: referenceDate,
            calendar: calendar
        )
        XCTAssertEqual(withdrawn.items.count, 1)
        XCTAssertEqual(withdrawn.items.first?.organization.itemType, .shopping)
        XCTAssertEqual(withdrawn.operations.count, 1)
        XCTAssertEqual(withdrawn.operations.first?.operation, .retract)
        XCTAssertEqual(withdrawn.operations.first?.isScoped, true)
    }
}

extension ActionabilityTests {
    func testExplicitMemoryFrameOwnsImperativesAndExecutionWords() throws {
        for text in [
            "Idea for the garden, install a rain barrel tomorrow.",
            "For my notes on the rehearsal, call the conductor before five.",
            "Random thought: send everyone a postcard, not something I need to do now.",
            "Write down that I don't want to cancel the reservation anymore.",
            "I might contact the clinic next week, just save that thought.",
            "Don't make a reminder yet, but I might call Mira tomorrow.",
            "Save this thought: remind me every Monday to call the clinic.",
        ] {
            for rendering in [text, text.lowercased()] {
                let result = ThoughtExtractionEngine.extractWithRules(
                    rendering, referenceDate: referenceDate, calendar: calendar
                )
                XCTAssertTrue(result.operations.isEmpty, rendering)
                XCTAssertEqual(result.items.count, 1, rendering)
                let item = try XCTUnwrap(result.items.first)
                XCTAssertFalse(item.organization.itemType.isActionable, rendering)
                XCTAssertNil(item.organization.dueDate, rendering)
                XCTAssertNil(item.organization.reminderDate, rendering)
                XCTAssertNil(item.organization.recurrenceRule, rendering)
                XCTAssertNil(item.organization.locationIntent, rendering)
            }
        }
    }

    func testExplicitTaskSiblingEndsMemoryScope() throws {
        let result = ThoughtExtractionEngine.extractWithRules(
            "Idea: make the garden bigger. Remind me to call Mira tomorrow at 9 AM.",
            referenceDate: referenceDate, calendar: calendar
        )
        XCTAssertEqual(result.items.count, 2)
        XCTAssertFalse(try XCTUnwrap(result.items.first).organization.itemType.isActionable)
        XCTAssertTrue(try XCTUnwrap(result.items.last).organization.itemType.isActionable)
        XCTAssertNotNil(try XCTUnwrap(result.items.last).organization.reminderDate)
    }

    func testPastModalReflectionDoesNotCreatePresentCommitment() {
        for text in [
            "I should have emailed Mira yesterday about the meeting.",
            "I almost called Mira about the appointment.",
            "I wish I had remembered to call Mira about the meeting.",
            "I was going to apply but I changed my mind.",
        ] {
            XCTAssertEqual(ActionabilityReader.read(text), .knowledge, text)
            XCTAssertFalse(ThoughtOrganizer.organize(
                text, referenceDate: referenceDate, calendar: calendar
            ).itemType.isActionable, text)
        }
        XCTAssertEqual(ActionabilityReader.read("I forgot to email Mira yesterday"), .outstanding)
        XCTAssertEqual(ActionabilityReader.read("Mira asked me to send the plan"), .actionable)
    }

    func testInstitutionAndTopicHeadsAreNotPersonalNames() {
        for text in ["Call Northstar Bank", "Contact University of the Valley",
                     "Email Grant Applications", "Call Northstar claims"] {
            XCTAssertNil(PersonMentionResolver.primary(in: text), text)
        }
        for text in ["Call Mira", "Call Mira at Northstar Bank", "Call Mom"] {
            XCTAssertNotNil(PersonMentionResolver.primary(in: text), text)
        }
    }

    func testMemoryScopeSurvivesARepairOfItsOpeningWords() throws {
        for text in [
            "Note to self, actually, the conference deadline is October twenty second.",
            "Save this number, actually 416 555 0192.",
            "I think rehearsal prep is the thing I keep forgetting about Thursday.",
        ] {
            let result = ThoughtExtractionEngine.extractWithRules(text, referenceDate: referenceDate, calendar: calendar)
            XCTAssertEqual(result.items.count, 1, text)
            let item = try XCTUnwrap(result.items.first)
            XCTAssertFalse(item.organization.itemType.isActionable, text)
            XCTAssertNil(item.organization.reminderDate, text)
            XCTAssertNil(item.organization.recurrenceRule, text)
            XCTAssertTrue(result.operations.isEmpty, text)
        }
    }

    func testUnsupportedTimingConstraintsCannotScheduleTheirPartialInterpretation() throws {
        for text in [
            "Every day at 9 AM until October 20 remind me to stretch.",
            "Every other Monday starting next week remind me to call Mira.",
            "On the last business day of every month remind me to pay rent.",
            "Remind me about the invoice between two and four PM tomorrow.",
            "Remind me two hours before my flight October 22.",
            "Remind me at 9 AM Atlantis time to call Mira.",
        ] {
            let result = ThoughtExtractionEngine.extractWithRules(text, referenceDate: referenceDate, calendar: calendar)
            XCTAssertEqual(result.items.count, 1, text)
            let item = try XCTUnwrap(result.items.first)
            XCTAssertTrue(item.organization.needsClarification, text)
            XCTAssertNil(item.organization.dueDate, text)
            XCTAssertNil(item.organization.reminderDate, text)
            XCTAssertNil(item.organization.recurrenceRule, text)
        }
    }

    func testCalendarOffsetKeepsTheExplicitClockAndNamedZone() throws {
        let result = ThoughtOrganizer.organize(
            "Remind me at 9 AM Bangkok time in two days to call Mira.",
            referenceDate: referenceDate, calendar: calendar
        )
        var namedCalendar = calendar
        namedCalendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Bangkok"))
        let expected = namedCalendar.date(from: DateComponents(year: 2026, month: 8, day: 5, hour: 9))
        XCTAssertEqual(result.reminderDate, expected)
        XCTAssertFalse(result.needsClarification)
    }

    func testSequencingRepairDoesNotDiscardEarlierTasks() {
        for text in [
            "Buy soap and then, actually, call Mira.",
            "Go to the library and get paper, wait, then go to the office and buy envelopes.",
            "Call Mira, wait, before that email Alex.",
        ] {
            let result = ThoughtExtractionEngine.extractWithRules(text, referenceDate: referenceDate, calendar: calendar)
            XCTAssertEqual(result.items.count, 2, text)
            XCTAssertTrue(result.items.allSatisfy { $0.organization.itemType.isActionable }, text)
        }
    }

    func testReportedInstructionsStayInsideTheRequestedMessage() throws {
        for text in [
            "Text Mira that I said wait then call Alex.",
            "Text Mira that I said wait and then call Alex.",
            "Tell Alex that Sarah said buy milk and then call Mira.",
        ] {
            let result = ThoughtExtractionEngine.extractWithRules(text, referenceDate: referenceDate, calendar: calendar)
            XCTAssertEqual(result.items.count, 1, text)
            XCTAssertTrue(try XCTUnwrap(result.items.first).organization.itemType.isActionable, text)
            XCTAssertTrue(result.operations.isEmpty, text)
        }
    }

    func testSeparateReminderStillLeavesTheMessageScope() {
        let result = ThoughtExtractionEngine.extractWithRules(
            "Text Mira that the meeting is cancelled and remind me to buy soap tomorrow.",
            referenceDate: referenceDate, calendar: calendar
        )
        XCTAssertEqual(result.items.count, 2)
        XCTAssertTrue(result.operations.isEmpty)
    }

    func testRestoredActionsKeepUnresolvedEventScope() {
        for text in [
            "After class, first buy soap, then call Mira, actually after that call Alex.",
            "Before the rehearsal, buy soap and then, actually, call Mira.",
            "After I finish the workshop, buy soap and then, actually, call Mira.",
        ] {
            let result = ThoughtExtractionEngine.extractWithRules(text, referenceDate: referenceDate, calendar: calendar)
            XCTAssertEqual(result.items.count, 1, text)
            XCTAssertTrue(result.items.allSatisfy { $0.needsReview }, text)
            XCTAssertTrue(result.items.allSatisfy { $0.organization.state == .unsupported(.unsupportedCondition) }, text)
            XCTAssertTrue(result.items.allSatisfy { $0.organization.dueDate == nil && $0.organization.reminderDate == nil }, text)
            XCTAssertTrue(result.items.first?.analysisText.lowercased().contains("buy soap") == true, text)
            XCTAssertTrue(result.items.first?.analysisText.lowercased().contains("call mira") == true, text)
        }
    }

    func testIndependentReminderDoesNotInheritUnknownEvent() {
        let result = ThoughtExtractionEngine.extractWithRules(
            "After class, remind me to call Mira, and separately remind me tomorrow at 9 to call Alex.",
            referenceDate: referenceDate, calendar: calendar
        )
        XCTAssertEqual(result.items.count, 2)
        XCTAssertTrue(result.items.first?.needsReview == true)
        XCTAssertTrue(result.items.last?.needsReview == false)
        XCTAssertNotNil(result.items.last?.organization.reminderDate)
    }

    func testOutgoingMessageDoesNotExecuteItsContents() {
        for text in [
            "Text Mira that I set an alarm for 7 AM.",
            "Text Mira I set an alarm for 7 AM.",
            "Text Mira \"set an alarm for 7 AM\".",
            "Tell Mira to set an alarm for 7 AM.",
            "Tell Mira not to set an alarm for 7 AM.",
            "Text Mira that the meeting starts at 9 AM tomorrow.",
            "Tell Mira that I water the plants every Friday.",
            "Tell Alex that if the parcel arrives Sarah will call Mira.",
            "Ask Mira if she can call Alex tomorrow.",
        ] {
            let result = ThoughtExtractionEngine.extractWithRules(text, referenceDate: referenceDate, calendar: calendar)
            XCTAssertEqual(result.items.count, 1, text)
            XCTAssertTrue(result.operations.isEmpty, text)
            XCTAssertTrue(result.items.allSatisfy { !$0.needsReview }, text)
            XCTAssertTrue(result.items.allSatisfy { $0.organization.dueDate == nil && $0.organization.reminderDate == nil && $0.organization.recurrenceRule == nil }, text)
        }
    }

    func testQuotedOperationsDoNotEscapeMessageBoundaries() {
        for text in [
            "Text Mira \"set an alarm for 7 AM and cancel the old one\".",
            "Tell Mira to buy milk and cancel the grocery reminder.",
            "Text Mira that I will buy milk and cancel the grocery reminder.",
            "Sarah said to buy milk and cancel the grocery reminder.",
            "Text Mira ‘buy milk, cancel the grocery reminder’.",
            "Sarah said \"buy milk cancel the grocery reminder\".",
        ] {
            let result = ThoughtExtractionEngine.extractWithRules(text, referenceDate: referenceDate, calendar: calendar)
            XCTAssertEqual(result.items.count, 1, text)
            XCTAssertTrue(result.operations.isEmpty, text)
        }
        let outer = ThoughtExtractionEngine.extractWithRules(
            "Text Mira \"buy milk and cancel the old one\", and cancel my gym reminder.",
            referenceDate: referenceDate, calendar: calendar
        )
        XCTAssertEqual(outer.items.count, 1)
        XCTAssertEqual(outer.operations.count, 1)
        XCTAssertEqual(outer.operations.first?.target, "my gym reminder")
    }

    func testCalendarModifierDoesNotBindAnUnknownEvent() {
        for text in [
            "Remind me to call Mira after class tomorrow morning.",
            "After I finish class tomorrow morning, remind me to call Mira.",
            "Remind me to call Mira before the meeting tomorrow afternoon.",
            "After class October 22, remind me to call Mira.",
            "Remind me to call Mira before the meeting December 24.",
            "Remind me before the office closes December 24.",
        ] {
            let result = ThoughtExtractionEngine.extractWithRules(text, referenceDate: referenceDate, calendar: calendar)
            XCTAssertEqual(result.items.count, 1, text)
            XCTAssertTrue(result.items.allSatisfy { $0.needsReview }, text)
            XCTAssertTrue(result.items.allSatisfy { $0.organization.dueDate == nil && $0.organization.reminderDate == nil }, text)
            XCTAssertTrue(result.operations.isEmpty, text)
        }
    }

    func testMessageReminderUsesOuterClockAndRetainsInnerClock() {
        let result = ThoughtExtractionEngine.extractWithRules(
            "Remind me tomorrow at 10 AM to text Mira that the meeting starts at 9 AM.",
            referenceDate: referenceDate, calendar: calendar
        )
        XCTAssertEqual(result.items.count, 1)
        if let item = result.items.first, let reminder = item.organization.reminderDate {
            XCTAssertEqual(calendar.component(.hour, from: reminder), 10)
            XCTAssertTrue(item.suggestedTitle?.contains("9 AM") == true)
        } else {
            XCTFail("The explicitly requested message reminder was lost")
        }
    }

    func testModifiedObjectDoesNotDetachAProhibition() {
        for object in ["a hard drive", "a portable drive", "an expensive watch", "a new iron"] {
            let text = "Remind me not to buy \(object) tomorrow."
            let result = ThoughtExtractionEngine.extractWithRules(text, referenceDate: referenceDate, calendar: calendar)
            XCTAssertEqual(result.items.count, 1, text)
            XCTAssertTrue(result.operations.isEmpty, text)
            XCTAssertNotNil(result.items.first?.organization.reminderDate, text)
            XCTAssertTrue(result.items.first?.analysisText.lowercased().contains("not to buy \(object)") == true, text)
        }
    }

    func testDiscourseDoesNotHideAnExplicitMemoryFrame() {
        for text in [
            "Actually, random thought about tuition, maybe redesign the menu, not something I need to do right now.",
            "Actually, save this number exactly, 416 555 0199.",
            "Note to self, yeah, the application deadline is October twenty second.",
        ] {
            let result = ThoughtExtractionEngine.extractWithRules(text, referenceDate: referenceDate, calendar: calendar)
            XCTAssertEqual(result.items.count, 1, text)
            XCTAssertTrue(result.operations.isEmpty, text)
            XCTAssertTrue(result.items.allSatisfy { !$0.organization.itemType.isActionable }, text)
            XCTAssertTrue(result.items.allSatisfy { $0.organization.dueDate == nil && $0.organization.reminderDate == nil }, text)
        }
    }

    func testIndependentClockClauseSurvivesARequestToSaveTheThought() {
        let text = "Tomorrow work on the notes, actually do not make that a reminder, just save the thought, and then at 2 PM call Sam."
        let result = ThoughtExtractionEngine.extractWithRules(text, referenceDate: referenceDate, calendar: calendar)
        XCTAssertEqual(result.items.count, 2)
        XCTAssertTrue(result.operations.isEmpty)
        XCTAssertFalse(result.items.first?.organization.itemType.isActionable ?? true)
        XCTAssertNotNil(result.items.last?.organization.dueDate)
        XCTAssertEqual(result.items.last?.organization.personName, "Sam")
    }

    func testFactualCommaClauseDoesNotInventShoppingAction() {
        for text in ["Mom likes white flowers, okay done.", "My brother prefers black coffee, that is all."] {
            let result = ThoughtExtractionEngine.extractWithRules(text, referenceDate: referenceDate, calendar: calendar)
            XCTAssertEqual(result.items.count, 1, text)
            XCTAssertTrue(result.items.allSatisfy { !$0.organization.itemType.isActionable }, text)
            XCTAssertTrue(result.operations.isEmpty, text)
        }
    }

    func testFrontedDayBelongsToTheRequestedReminderClock() {
        for text in ["October 22 remind me at 5 PM to call Mira.", "Tomorrow, remind me at 5 PM to call Mira."] {
            let result = ThoughtExtractionEngine.extractWithRules(text, referenceDate: referenceDate, calendar: calendar)
            XCTAssertEqual(result.items.count, 1, text)
            guard let item = result.items.first, let due = item.organization.dueDate,
                  let alert = item.organization.reminderDate else { XCTFail(text); continue }
            XCTAssertEqual(due, alert, text)
            XCTAssertEqual(calendar.component(.hour, from: alert), 17, text)
        }
    }

    func testDateOnlyDeadlineDoesNotOverwriteExplicitAlertClock() {
        let result = ThoughtExtractionEngine.extractWithRules(
            "Remind me Wednesday at 5 PM to finish the report Friday.",
            referenceDate: referenceDate, calendar: calendar
        )
        XCTAssertEqual(result.items.count, 1)
        guard let item = result.items.first, let due = item.organization.dueDate,
              let alert = item.organization.reminderDate else { return XCTFail("Missing deadline or alert") }
        XCTAssertEqual(calendar.component(.weekday, from: due), 6)
        XCTAssertEqual(calendar.component(.weekday, from: alert), 4)
        XCTAssertEqual(calendar.component(.hour, from: alert), 17)
    }

    func testSequencedRecipientDoesNotChangeRoutingWithNameSpelling() {
        for name in ["Mila", "Alex"] {
            let text = "Tomorrow at 4 PM, first work on interview notes, then call Lyft about it, actually after that call \(name) at Lyft, not Niko."
            let result = ThoughtExtractionEngine.extractWithRules(text, referenceDate: referenceDate, calendar: calendar)
            XCTAssertEqual(result.items.count, 3, text)
            XCTAssertEqual(result.items.last?.organization.personName, name, text)
            XCTAssertTrue(result.items.last?.organization.itemType.isActionable == true, text)
            XCTAssertEqual(result.items.first?.organization.dueDate, result.items.last?.organization.dueDate, text)
        }
    }

    func testSharedCalendarPrefixDoesNotDemoteLaterActions() {
        for lead in ["The end of the month", "Tomorrow morning at 4 PM"] {
            let text = "\(lead), buy pens and call Mira."
            let result = ThoughtExtractionEngine.extractWithRules(text, referenceDate: referenceDate, calendar: calendar)
            XCTAssertEqual(result.items.count, 2, text)
            XCTAssertTrue(result.items.allSatisfy { $0.organization.itemType.isActionable && $0.organization.dueDate != nil }, text)
            XCTAssertEqual(result.items.first?.organization.dueDate, result.items.last?.organization.dueDate, text)
        }
    }

    func testDatedDiscourseIdiomKeepsSiblingDates() {
        let text = "Before I forget today go to the salon and get a hard drive and then go to the embassy and buy a water bottle."
        let result = ThoughtExtractionEngine.extractWithRules(text, referenceDate: referenceDate, calendar: calendar)
        XCTAssertTrue((2...3).contains(result.items.count))
        XCTAssertTrue(result.items.allSatisfy { $0.organization.itemType.isActionable && !$0.needsReview && $0.organization.dueDate != nil })
        XCTAssertEqual(result.items.first?.organization.dueDate, result.items.last?.organization.dueDate)
    }

    func testIndependentMessageDoesNotSwallowLocalCancellation() {
        for text in [
            "Text Noah about dinner and call Noah tomorrow, actually cancel the call.",
            "Message Mira regarding the invoice and book the dentist, actually cancel the dentist."
        ] {
            let result = ThoughtExtractionEngine.extractWithRules(text, referenceDate: referenceDate, calendar: calendar)
            XCTAssertEqual(result.items.count, 1, text)
            XCTAssertEqual(result.operations.count, 1, text)
            XCTAssertEqual(result.operations.first?.isScoped, true, text)
        }
    }

    func testLocalCancellationPreservesUnresolvedScopeAndAmbiguity() {
        for text in [
            "After class call Alex and buy milk, actually cancel the call.",
            "Call Alex tomorrow and call Mira Friday, actually cancel the call."
        ] {
            let result = ThoughtExtractionEngine.extractWithRules(text, referenceDate: referenceDate, calendar: calendar)
            XCTAssertEqual(result.items.count, 1, text)
            XCTAssertTrue(result.items.allSatisfy { $0.needsReview && $0.organization.reminderDate == nil }, text)
        }
    }

    func testCanceledVisitKeepsIndependentCallAndInheritedDay() {
        let text = "Tomorrow go to Costco and buy milk and call Maya, actually cancel Costco."
        let result = ThoughtExtractionEngine.extractWithRules(text, referenceDate: referenceDate, calendar: calendar)
        XCTAssertEqual(result.items.count, 1)
        XCTAssertEqual(result.items.first?.organization.personName, "Maya")
        XCTAssertNotNil(result.items.first?.organization.dueDate)
        XCTAssertEqual(result.operations.first?.isScoped, true)
    }

    func testCalendarCorrectionDoesNotReplaceTheActionObject() {
        let text = "Before class I need to go to the car wash for a suitcase, actually October 22."
        let result = ThoughtExtractionEngine.extractWithRules(text, referenceDate: referenceDate, calendar: calendar)
        XCTAssertEqual(result.items.count, 1)
        XCTAssertTrue(result.items.first?.analysisText.lowercased().contains("suitcase") == true)
        XCTAssertTrue(result.items.first?.needsReview == true)
    }

    func testCorrectedRelativeDateBelongsToEverySibling() {
        let text = "Wednesday I need to go to the mall and buy a water bottle actually in two days."
        let result = ThoughtExtractionEngine.extractWithRules(text, referenceDate: referenceDate, calendar: calendar)
        XCTAssertFalse(result.items.isEmpty)
        XCTAssertTrue(result.items.allSatisfy { $0.organization.dueDate != nil })
        XCTAssertEqual(result.items.first?.organization.dueDate, result.items.last?.organization.dueDate)
    }

    func testPurposeForDoesNotTurnAProductIntoAContact() {
        let result = ThoughtExtractionEngine.extractWithRules(
            "Next Monday I need to go to the stadium for contact lens solution.",
            referenceDate: referenceDate, calendar: calendar
        )
        XCTAssertTrue(result.items.allSatisfy { $0.organization.personName == nil })
    }

}
