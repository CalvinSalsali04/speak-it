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
    func testConditionalOpenersCannotBecomeReportingSubjects() throws {
        let previous = SentenceContext.taggerDisabledForEvaluation
        defer {
            SentenceContext.taggerDisabledForEvaluation = previous
            SentenceContextCache.invalidate()
        }
        for disabled in [false, true] {
            SentenceContext.taggerDisabledForEvaluation = disabled
            SentenceContextCache.invalidate()
            for opener in ["If", "Unless", "When", "Once", "After", "Before"] {
                let source = "\(opener) Pat confirms, buy wine for dinner at 7 PM."
                XCTAssertNotEqual(ClauseScope.read(source).act, .reporting, source)
                let result = ThoughtExtractionEngine.extractWithRules(source,
                    referenceDate: referenceDate, calendar: calendar)
                XCTAssertEqual(result.items.count, 1, source)
                let row = try XCTUnwrap(result.items.first, source)
                XCTAssertEqual(row.organization.itemType, .shopping, source)
                XCTAssertEqual(row.organization.state, .unsupported(.unsupportedCondition), source)
                XCTAssertTrue(row.needsReview, source)
                XCTAssertNil(row.organization.dueDate, source)
                XCTAssertNil(row.organization.reminderDate, source)
                XCTAssertEqual(row.rawQuote, source)
                XCTAssertTrue(result.operations.isEmpty, source)
            }
            for reporter in ["Pat", "Sarah Jane", "Tillie", "Whenna"] {
                let source = "\(reporter) confirms that the store closes at 7 PM."
                XCTAssertEqual(ClauseScope.read(source).act, .reporting, source)
                let result = ThoughtExtractionEngine.extractWithRules(source,
                    referenceDate: referenceDate, calendar: calendar)
                XCTAssertFalse(result.items.contains { $0.organization.itemType.isActionable }, source)
            }
            for source in [
                "If Pat says buy wine.",
                "If Pat confirms, Maya says buy wine.",
                "Till Lindemann says buy wine.",
                "The phrase ‘If Pat confirms, buy wine’ is printed on the poster."
            ] {
                let result = ThoughtExtractionEngine.extractWithRules(source,
                    referenceDate: referenceDate, calendar: calendar)
                XCTAssertFalse(result.items.contains { $0.organization.itemType.isActionable && !$0.needsReview }, source)
                XCTAssertFalse(result.items.contains { $0.organization.reminderDate != nil }, source)
                XCTAssertTrue(result.operations.isEmpty, source)
            }
        }
    }

    func testPrenominalAcquisitionRescueRequiresPhysicalSourceEvidence() async {
        let nativeReady = await SentenceContext.prepareEnglishAssets()
        SentenceContextCache.invalidate()
        print("Prenominal native fixture: \(SentenceContext.taggerAvailability()) ready=\(nativeReady)")
        XCTAssertTrue(nativeReady, "The unknown-head native positive requires prepared English tagging assets")
        for (object, source) in [
            ("washed potatoes", "Get washed potatoes."),
            ("a box of glazed doughnuts", "Get a box of glazed doughnuts.")
        ] {
            let context = SentenceContextCache.context(for: source)
            let evidence = context.tokens.map { "\($0.text)=\($0.lexicalClass?.rawValue ?? "nil")" }.joined(separator: " ")
            XCTAssertTrue(ShoppingGroupParser.certifiesPrenominalAcquisitionObject(object, in: source),
                "\(source) native=\(SentenceContext.taggerAvailability()) tokens=\(evidence) resultGlazed=\(ActionabilityReader.isResultParticiple("glazed"))")
            let result = ThoughtExtractionEngine.extractWithRules(source,
                referenceDate: referenceDate, calendar: calendar)
            XCTAssertEqual(result.items.count, 1, source)
            XCTAssertEqual(result.items.first?.organization.itemType, .shopping, source)
            XCTAssertEqual(result.items.first?.rawQuote, source, source)
        }
        for (object, source) in [
            ("potatoes washed", "Get potatoes washed."),
            ("ready", "Get ready."),
            ("washed potatoes", "Maya said get washed potatoes."),
            ("washed potatoes", "Do not get washed potatoes."),
            ("washed potatoes", "Get ‘washed potatoes’."),
            ("a box of not glazed doughnuts", "Get a box of not glazed doughnuts."),
            ("a box of dogs chased eggs", "Get a box of dogs chased eggs."),
            ("a box of glazed doughnuts if needed", "Get a box of glazed doughnuts if needed."),
            ("my washed potatoes", "Get my washed potatoes."),
            ("those washed potatoes", "Get those washed potatoes."),
            ("a box of my doughnuts", "Get a box of my doughnuts."),
            ("a box of old toys", "Get a box of old toys."),
            ("a box of signed forms", "Get a box of signed forms."),
            ("a box of returned items", "Get a box of returned items."),
            ("a box of labeled files", "Get a box of labeled files."),
            ("a bag of donated clothes", "Get a bag of donated clothes."),
            ("a box of sorted samples", "Get a box of sorted samples."),
            ("a box of scanned receipts", "Get a box of scanned receipts."),
            ("a box of business cards", "Get a box of business cards."),
            ("paid invoices", "Get paid invoices."),
            ("printed tickets", "Get printed tickets."),
            ("a box of printed tickets", "Get a box of printed tickets."),
            ("washed potatoes", "Get washed potatoes delivered."),
            ("washed", "Get washed."),
            ("washed and dressed", "Get washed and dressed."),
            ("a box of glazed doughnuts", "Don't get a box of glazed doughnuts.")
        ] {
            XCTAssertFalse(ShoppingGroupParser.certifiesPrenominalAcquisitionObject(object, in: source), source)
        }
        let wasDisabled = SentenceContext.taggerDisabledForEvaluation
        defer {
            SentenceContext.taggerDisabledForEvaluation = wasDisabled
            SentenceContextCache.invalidate()
        }
        SentenceContext.taggerDisabledForEvaluation = true
        SentenceContextCache.invalidate()
        XCTAssertTrue(ShoppingGroupParser.certifiesPrenominalAcquisitionObject("washed potatoes", in: "Get washed potatoes."))
        XCTAssertFalse(ShoppingGroupParser.certifiesPrenominalAcquisitionObject("a box of glazed doughnuts", in: "Get a box of glazed doughnuts."))
    }



    func testForeignResponsibilitiesAndServiceSchedulesDoNotAuthorizeOwnTasks() {
        let cases = [
            "The museum offers a quiet hour on Wednesday mornings.",
            "At our meeting the treasurer took responsibility for sending the receipts.",
            "Our designer has a deadline on the twelfth for the logo sketches.",
            "The kitchen fitter must check the wall before installing the cabinets.",
            "I heard that the librarian has to close early today because of a staffing problem.",
            "A note in the margin says 'ask for extra copies'; I want to know later what the old editor wrote."
        ]
        for taggerDisabled in [false, true] {
            let previous = SentenceContext.taggerDisabledForEvaluation
            SentenceContext.taggerDisabledForEvaluation = taggerDisabled
            defer { SentenceContext.taggerDisabledForEvaluation = previous }
            for source in cases {
                XCTAssertFalse(ActionabilityReader.read(source).belongsOnToday, source)
                let result = ThoughtExtractionEngine.extractWithRules(source,
                    referenceDate: referenceDate, calendar: calendar)
                XCTAssertFalse(result.items.contains { $0.organization.itemType.isActionable }, source)
                XCTAssertFalse(result.items.contains { $0.organization.reminderDate != nil }, source)
                XCTAssertFalse(result.items.isEmpty, source)
                XCTAssertTrue(result.operations.isEmpty, source)
            }
        }
    }

    func testOwnAdoptionAndAppointmentsSurviveForeignResponsibilityGuards() {
        for source in [
            "I will send the receipts tomorrow.",
            "Remind me to check the designer's deadline tomorrow at 4 PM.",
            "My deadline is August twelfth.",
            "Dentist appointment on Friday at 3 PM.",
            "Maya said I need to send the receipts tomorrow."
        ] {
            XCTAssertTrue(ActionabilityReader.read(source).belongsOnToday, source)
            let result = ThoughtExtractionEngine.extractWithRules(source,
                referenceDate: referenceDate, calendar: calendar)
            XCTAssertTrue(result.items.contains { $0.organization.itemType.isActionable }, source)
        }
    }

    func testExplicitCaptureRetentionUsesExternalPurposeWithoutLexicalAssets() throws {
        let previous = SentenceContext.taggerDisabledForEvaluation
        SentenceContext.taggerDisabledForEvaluation = true
        defer { SentenceContext.taggerDisabledForEvaluation = previous }
        let cases: [(String, ItemType)] = [
            ("I want to save the phrase 'quiet courts, bright lamps' as a design thought.", .idea),
            ("I need to retain the phrase ‘narrow paths, wide skies’ as an idea.", .idea),
            ("I would like to keep the phrase \"blue doors, open rooms\" as a Memory.", .note),
            ("We want to record the window layout as a design thought.", .idea),
            ("We need to save the seating pattern as an idea.", .idea),
            ("We would like to retain this description as reference.", .note),
            ("Please save 'small courtyards, deep shadows' as a thought.", .idea),
            ("Save the phrase 'mail the parcel tomorrow' as an idea.", .idea),
            ("I want to save the phrase 'remind me to call Noor tomorrow at 5 PM' as a Memory.", .note),
            ("Save that cooking guidance.", .note),
            ("I want to retain this gardening advice.", .note),
            ("Please keep those design thoughts.", .idea),
            ("Save these reference notes.", .note)
        ]
        for (source, kind) in cases {
            XCTAssertEqual(ActionabilityReader.explicitCaptureRetentionKind(source), kind, source)
            XCTAssertEqual(ActionabilityReader.retainedContentKind(source), kind, source)
            XCTAssertEqual(ActionabilityReader.read(source), .knowledge, source)
            XCTAssertEqual(ActionabilityReader.read(ActionabilityReader.actionBody(source)), .knowledge, source)
            let result = ThoughtExtractionEngine.extractWithRules(source,
                referenceDate: referenceDate, calendar: calendar)
            XCTAssertEqual(result.items.count, 1, source)
            let row = try XCTUnwrap(result.items.first, source)
            XCTAssertEqual(row.organization.itemType, kind, source)
            XCTAssertFalse(row.needsReview, source)
            XCTAssertEqual(row.rawQuote, source, source)
            XCTAssertEqual(row.sourceQuote, source, source)
            XCTAssertNil(row.organization.dueDate, source)
            XCTAssertNil(row.organization.reminderDate, source)
            XCTAssertEqual(row.organization.reminderDelivery, .none, source)
            XCTAssertEqual(row.organization.temporalIntent.kind, .none, source)
            XCTAssertTrue(result.operations.isEmpty, source)
        }
    }

    func testCaptureRetentionRequiresCompleteOwnScopeAndExternalLabel() {
        let rejected = [
            "Maya wants to save the phrase 'quiet courts' as a thought.",
            "I wanted to save the phrase 'quiet courts' as a thought.",
            "I would have liked to save the phrase 'quiet courts' as a thought.",
            "I do not want to save the phrase 'quiet courts' as a thought.",
            "I no longer need to save the phrase 'quiet courts' as a thought.",
            "If the sketch works, I want to save the phrase 'quiet courts' as a thought.",
            "Maya said, ‘I want to save the phrase quiet courts as a thought.’",
            "‘I want to save the phrase quiet courts as a thought.’",
            "I want to save the phrase 'quiet courts as a thought'.",
            "Save the file 'quiet courts as an idea'.",
            "I want to save the phrase 'quiet courts as a thought.",
            "I want to save '' as a thought.",
            "I want to save 'quiet courts' and 'bright lamps' as a thought.",
            "I want to save the phrase 'quiet courts' as a thought tomorrow.",
            "I want to save that cooking guidance at five.",
            "Save that cooking guidance when I get home.",
            "I want to save the phrase 'quiet courts' and I will mail the parcel as a note.",
            "Save the phrase 'quiet courts' and arrange the chairs as a note.",
            "Save the phrase 'quiet courts', rinse the tray as a note.",
            "Save the phrase 'quiet courts' as a note, and I will mail the parcel.",
            "Save the phrase 'quiet courts' as a note with diagrams and arrange the chairs.",
            "I need to save the phrase 'quiet courts' as a thought and mail the parcel.",
            "Save that cooking guidance and please rinse the tray.",
            "I want to save the courier sends guidance as Memory.",
            "I want to save the idea before I mail the parcel as a note.",
            "I will save the window layout as an idea.",
            "Remind me to save the phrase 'quiet courts' as a thought at five."
        ]
        for source in rejected {
            XCTAssertNil(ActionabilityReader.explicitCaptureRetentionKind(source), source)
            XCTAssertNil(ActionabilityReader.retainedContentKind(source), source)
        }
        XCTAssertNil(ActionabilityReader.explicitCaptureRetentionKind(
            "I want to save '" + String(repeating: "a", count: 8_192) + "' as a thought."))
        // A label entirely inside a quotation cannot classify an outside file
        // task. The quoted words have no authority over its destination.
        XCTAssertTrue(ActionabilityReader.read("Save the file 'quiet courts as an idea'.").belongsOnToday)
    }

    func testRealWorldSavingRemainsActionableWithoutLexicalAssets() {
        let previous = SentenceContext.taggerDisabledForEvaluation
        SentenceContext.taggerDisabledForEvaluation = true
        defer { SentenceContext.taggerDisabledForEvaluation = previous }
        for source in ["Save the backup file before closing the laptop.",
                       "I need to save the report tomorrow.",
                       "Save money for the train ticket.",
                       "We need to save the injured bird's life.",
                       "Remind me to save the report tomorrow at five."] {
            XCTAssertNil(ActionabilityReader.explicitCaptureRetentionKind(source), source)
            XCTAssertTrue(ActionabilityReader.read(source).belongsOnToday, source)
            let result = ThoughtExtractionEngine.extractWithRules(source,
                referenceDate: referenceDate, calendar: calendar)
            XCTAssertTrue(result.items.contains { $0.organization.itemType.isActionable }, source)
        }
    }

    func testExplicitCaptureRetentionCannotAbsorbAnIndependentTaskOrReminder() throws {
        let retained = "I want to save the phrase 'quiet courts, bright lamps' as a design thought."
        for continuation in ["I need to mail the parcel.", "Arrange the chairs.",
                             "Remind me to rinse the tray tomorrow at 5 PM."] {
            for source in [retained + " " + continuation,
                           continuation + " " + retained,
                           String(retained.dropLast()) + " and " + continuation.lowercased()] {
                XCTAssertNil(ActionabilityReader.explicitCaptureRetentionKind(source), source)
                let result = ThoughtExtractionEngine.extractWithRules(source,
                    referenceDate: referenceDate, calendar: calendar)
                let memory = try XCTUnwrap(result.items.first {
                    !$0.organization.itemType.isActionable && $0.rawQuote.contains("quiet courts")
                }, source)
                let action = try XCTUnwrap(result.items.first {
                    $0.organization.itemType.isActionable && !$0.needsReview
                }, source)
                XCTAssertFalse(memory.needsReview, source)
                XCTAssertFalse(action.rawQuote.contains("quiet courts"), source)
                XCTAssertTrue(memory.sourceUnitIDs.isDisjoint(with: action.sourceUnitIDs), source)
                XCTAssertTrue(result.operations.isEmpty, source)
                let claims = result.items.reduce(into: Set<Int>()) { $0.formUnion($1.sourceUnitIDs) }
                XCTAssertTrue(SourceUnitLedger(source).unownedMeaningfulIDs(claimed: claims).isEmpty, source)
                if continuation.hasPrefix("Remind") {
                    XCTAssertNotNil(action.organization.reminderDate, source)
                    XCTAssertNil(memory.organization.reminderDate, source)
                }
            }
        }
    }

    func testWouldLikeRetentionKeepsItsOwnVoiceAndSeparateUnknownVerbReminder() throws {
        let previous = SentenceContext.taggerDisabledForEvaluation
        SentenceContext.taggerDisabledForEvaluation = true
        defer { SentenceContext.taggerDisabledForEvaluation = previous }
        let retained = "I would like to keep the phrase \"blue doors, open rooms\" as a Memory."
        let reminder = "Remind me to collate the pamphlets tomorrow at 5 PM."
        for source in [retained + " " + reminder,
                       reminder + " " + retained,
                       String(retained.dropLast()) + " and " + reminder.lowercased()] {
            XCTAssertNil(ActionabilityReader.explicitCaptureRetentionKind(source), source)
            let result = ThoughtExtractionEngine.extractWithRules(source,
                referenceDate: referenceDate, calendar: calendar)
            XCTAssertEqual(result.items.count, 2, source)
            let memory = try XCTUnwrap(result.items.first {
                $0.rawQuote.contains("blue doors, open rooms")
            }, source)
            let action = try XCTUnwrap(result.items.first {
                $0.rawQuote.contains("collate the pamphlets")
            }, source)
            XCTAssertEqual(memory.organization.itemType, .note, source)
            XCTAssertFalse(memory.needsReview, source)
            XCTAssertTrue(memory.rawQuote.contains("\"blue doors, open rooms\""), source)
            XCTAssertFalse(memory.rawQuote.contains("collate"), source)
            XCTAssertNil(memory.organization.dueDate, source)
            XCTAssertNil(memory.organization.reminderDate, source)
            XCTAssertTrue(action.organization.itemType.isActionable, source)
            XCTAssertFalse(action.needsReview, source)
            XCTAssertFalse(action.rawQuote.contains("blue doors"), source)
            XCTAssertEqual(action.organization.reminderDate,
                calendar.date(from: DateComponents(year: 2026, month: 8, day: 4, hour: 17)), source)
            XCTAssertEqual(action.organization.reminderDelivery, .notification, source)
            XCTAssertTrue(memory.sourceUnitIDs.isDisjoint(with: action.sourceUnitIDs), source)
            XCTAssertTrue(SourceUnitLedger(source).unownedMeaningfulIDs(claimed:
                memory.sourceUnitIDs.union(action.sourceUnitIDs)).isEmpty, source)
            XCTAssertTrue(result.operations.isEmpty, source)
        }
    }

    func testQuotedReminderWithinWouldLikeRetentionDoesNotOpenAnAction() throws {
        let source = "I would like to keep the phrase \"Remind me to collate the pamphlets tomorrow at 5 PM.\" as a Memory."
        let result = ThoughtExtractionEngine.extractWithRules(source,
            referenceDate: referenceDate, calendar: calendar)
        XCTAssertEqual(result.items.count, 1, source)
        let memory = try XCTUnwrap(result.items.first, source)
        XCTAssertEqual(memory.organization.itemType, .note, source)
        XCTAssertFalse(memory.needsReview, source)
        XCTAssertEqual(memory.rawQuote, source, source)
        XCTAssertEqual(memory.sourceQuote, source, source)
        XCTAssertNil(memory.organization.dueDate, source)
        XCTAssertNil(memory.organization.reminderDate, source)
        XCTAssertEqual(memory.organization.reminderDelivery, .none, source)
        XCTAssertEqual(memory.sourceUnitIDs, Set(SourceUnitLedger(source).words.indices), source)
        XCTAssertTrue(result.operations.isEmpty, source)
    }

    func testRepeatedActionPrefixPeelingPreservesCaseUnicodeAndCompleteRelations() {
        let cases = [
            ("PLEASE call Zoë about 🧪", "call Zoë about 🧪"),
            ("Urgent: EMAIL José about café", "EMAIL José about café"),
            ("Remember to text my sister-in-law’s partner about 🎂", "text my sister-in-law’s partner about 🎂"),
            ("Please call Jose\u{301} about the résumé", "call Jose\u{301} about the résumé")
        ]
        // Repeated reads exercise warm compiled patterns with changing UTF-16
        // lengths; only the spoken framing may disappear from the action body.
        for _ in 0..<3 {
            for (source, expected) in cases {
                XCTAssertEqual(ActionabilityReader.actionBody(source), expected, source)
                XCTAssertTrue(ActionabilityReader.read(source).belongsOnToday, source)
            }
        }
    }

    func testClosedClauseBoundariesWithoutLexicalAssets() {
        let previous = SentenceContext.taggerDisabledForEvaluation
        SentenceContext.taggerDisabledForEvaluation = true
        defer { SentenceContext.taggerDisabledForEvaluation = previous }
        for object in ["hard drive", "portable speaker", "expensive watch", "electric iron"] {
            let source = "Remind me not to buy an \(object) tomorrow."
            let rows = ThoughtExtractionEngine.extractWithRules(source).items
            XCTAssertEqual(rows.count, 1, source)
            XCTAssertTrue(rows[0].analysisText.contains("not to buy"), source)
            XCTAssertFalse(rows[0].needsReview, source)
        }
        let conditional = ThoughtExtractionEngine.extractWithRules(
            "Buy milk, and if Sarah replies, call Mike."
        ).items
        XCTAssertEqual(conditional.count, 2)
        XCTAssertTrue(conditional.contains { $0.organization.itemType == .shopping && !$0.needsReview })
        XCTAssertTrue(conditional.contains { $0.analysisText.contains("if Sarah replies") && $0.needsReview })
    }

    func testNegatedCapturedOperationStatusDoesNotDeclareAnotherObligation() {
        for source in ["I have not withdrawn that job.", "I haven't deleted that task.",
                       "I have not cancelled this reminder.",
                       "I know the last few sentences doubled back on the first ones, but I have not withdrawn that job."] {
            XCTAssertEqual(ActionabilityReader.read(source), .knowledge, source)
        }
        for source in ["I have not submitted the form", "I still haven't prepared the report",
                       "I have not returned the watering can", "I haven't cancelled the appointment",
                       "I still need to cancel that task", "Buy bread, but I have not withdrawn that job"] {
            XCTAssertTrue(ActionabilityReader.read(source).belongsOnToday, source)
        }
    }

    func testOrdinalNominalCommitmentExposesOnlyActualAction() {
        for (source, body) in [
            ("The last definite thing is to text Laila about borrowing the folding table.", "text Laila about borrowing the folding table."),
            ("The next definite thing is to email Jo the draft.", "email Jo the draft."),
            ("The first actual action is to call the caretaker.", "call the caretaker.")
        ] {
            XCTAssertEqual(ActionabilityReader.actionBody(source).lowercased(), body.lowercased())
            XCTAssertTrue(ActionabilityReader.read(source).belongsOnToday)
        }
        for source in ["Pat said the last definite thing is to email Jo the draft.",
                       "The last possible thing would be to email Jo the draft.",
                       "The first actual action was to call the caretaker."] {
            XCTAssertEqual(ActionabilityReader.read(source), .knowledge, source)
        }
    }

    func testArtifactCreationHistoryDoesNotCreateEventsOrHideUnfinishedActions() {
        for history in ["I scanned a receipt today", "We printed the agenda yesterday",
                        "I wrote a draft this morning", "I took a picture last night",
                        "We prepared the report today"] {
            XCTAssertEqual(ActionabilityReader.read(history), .knowledge, history)
        }
        for obligation in ["Scan the receipt today", "I need to print the agenda tomorrow",
                           "Remind me to write the draft tonight", "I forgot to scan the receipt",
                           "I never printed the agenda", "I still have not prepared the report"] {
            XCTAssertTrue(ActionabilityReader.read(obligation).belongsOnToday, obligation)
        }
    }

    func testNominalFactReadingDoesNotOwnMessageConditionOrLaterCommand() {
        for source in [
            "Call Maya if she is free", "Message Jo that dinner is at seven",
            "Tell Sarah the meeting is off", "Tell Mom dinner is off",
            "Tell Chen the interview is off", "Text Jordan that brunch is off",
            "invoice 1042 is thirty days overdue chase it",
            "Print quality is poor check it", "Return policy is unclear confirm that"
        ] {
            XCTAssertTrue(ActionabilityReader.read(source).belongsOnToday, source)
        }
        XCTAssertEqual(ActionabilityReader.read("Print quality was poor."), .knowledge)
        XCTAssertEqual(ActionabilityReader.read("Call button is broken."), .knowledge)
        XCTAssertEqual(ActionabilityReader.read("Print quality was poor because we forgot to check it."), .knowledge)
    }

    func testCompoundNominalPredicatesAndPluralCompletedHistoryKeepTheirScope() {
        for source in ["Print quality was poor.", "Call button is broken.", "Return policy was unclear.",
                       "We returned the projector.", "We already emailed Pat."] {
            XCTAssertEqual(ActionabilityReader.read(source), .knowledge, source)
        }
        for source in ["Print the report.", "Call Amy.", "Return the projector.",
                       "Remind me that print quality was poor."] {
            XCTAssertTrue(ActionabilityReader.read(source).belongsOnToday, source)
        }
        XCTAssertNotEqual(ActionabilityReader.read("We have not returned the projector."), .knowledge)
        let mixed = ThoughtExtractionEngine.extractWithRules("We returned the projector. I will print the form.").items
        XCTAssertEqual(mixed.count, 2)
        XCTAssertTrue(mixed.contains { $0.organization.itemType == .note && $0.sourceQuote.contains("returned") })
        XCTAssertTrue(mixed.contains { $0.organization.itemType.isActionable && $0.sourceQuote.contains("print") })
    }

    func testDeclaredTaskEntryAndCalendarYearExposeActualActionHead() {
        for (source, body) in [
            ("Add my task to send Pat the address.", "send Pat the address."),
            ("Put a task to print the report.", "print the report."),
            ("Save the to-do to call Amy.", "call Amy."),
            ("On October 06, 2026, return the projector to Noor.", "return the projector to Noor."),
            ("On May 12, 2027, print the form.", "print the form."),
            ("December 3 2026 send Lee the recipe.", "send Lee the recipe.")
        ] {
            XCTAssertEqual(ActionabilityReader.actionBody(source).lowercased(), body.lowercased(), source)
            XCTAssertTrue(ActionabilityReader.read(source).belongsOnToday, source)
        }
        for source in ["On October 06, 2026, print quality was poor.", "On May 12, 2025, we returned the projector."] {
            let body = ActionabilityReader.actionBody(source)
            XCTAssertEqual(ActionabilityReader.read(source), .knowledge,
                "body=\(body) predicateRead=\(ActionabilityReader.read(body))")
        }
        XCTAssertTrue(ActionabilityReader.actionBody("Add my task to the finished list.").lowercased().hasPrefix("add"))
    }

    func testDeclaredTaskBodyAndBareCommandDifferential() {
        for (source, body) in [
            ("The final task is this return the borrowed trolley to Gabe", "return the borrowed trolley to Gabe"),
            ("My task is to print the form", "print the form"),
            ("The next action is that call Noor", "call Noor")
        ] {
            let expected = ThoughtExtractionEngine.extractWithRules(body).items
            XCTAssertTrue(expected.first?.organization.itemType.isActionable == true)
            let actual = ThoughtExtractionEngine.extractWithRules(source).items
            XCTAssertEqual(actual.filter { $0.organization.itemType.isActionable }.count, expected.count,
                "bodyRead=\(ActionabilityReader.read(body)) sourceRead=\(ActionabilityReader.read(source)) source=\(source)")
        }
        XCTAssertEqual(ActionabilityReader.read("Pat said the final task is this return the trolley"), .knowledge)
        XCTAssertFalse(ActionabilityReader.read("The final task is this").belongsOnToday)
        XCTAssertEqual(ActionabilityReader.read("My task is complete"), .knowledge)
    }

    func testNominalRecordingFrameWithoutColonRequiresFiniteFactBody() {
        for source in ["A fact I want to keep the cabinet is locked", "One note we need to retain the spare labels are in the drawer", "The detail I would like to remember near the end of this recording our router has two ports"] {
            XCTAssertNotNil(ActionabilityReader.declaredFactRecordingBody(source), source)
            XCTAssertEqual(ActionabilityReader.read(source), .knowledge, source)
        }
        XCTAssertNil(ActionabilityReader.declaredFactRecordingBody("A fact I want to keep beside the printer"))
        XCTAssertNil(ActionabilityReader.declaredFactRecordingBody("The note I want to keep in the drawer"))
        XCTAssertNil(ActionabilityReader.declaredFactRecordingBody("Pat said a fact I want to keep the cabinet is locked"))
    }

    func testExplicitFactObjectAndDestinationFrameKeepsKnowledge() {
        for source in [
            "Keep only this fact as a note, not a task: The cabinet is locked.",
            "Save that information as a memory: The access code is 3421.",
            "Retain the detail as a note, not a reminder: Pat prefers green tea."
        ] {
            XCTAssertNotNil(ActionabilityReader.declaredFactRecordingBody(source))
            XCTAssertEqual(ActionabilityReader.read(source), .knowledge, source)
        }
        XCTAssertTrue(ActionabilityReader.read("Keep the note beside the printer.").belongsOnToday)
        XCTAssertNil(ActionabilityReader.declaredFactRecordingBody("Keep the file as a reference."))
        XCTAssertTrue(ActionabilityReader.read("Keep this fact as a note: I need to call Amy.").belongsOnToday)
    }

    func testPlantCareVerbDoesNotBecomeShoppingForItsProductNamedObject() {
        XCTAssertEqual(ThoughtOrganizer.organize("Water the parsley").itemType, .task)
        XCTAssertEqual(ThoughtOrganizer.organize("Buy parsley").itemType, .shopping)
        XCTAssertEqual(ThoughtOrganizer.organize("Parsley, milk and bread").itemType, .shopping)
    }

    func testAlsoNeedProductListIsShoppingButInfinitiveIsAnAction() {
        XCTAssertEqual(ThoughtOrganizer.organize("I also need oat milk and eggs").itemType,
                       .shopping)
        XCTAssertEqual(ThoughtOrganizer.organize("I need oat milk and eggs").itemType,
                       .shopping)
        XCTAssertEqual(ThoughtOrganizer.organize("I also need to call the dentist").itemType,
                       .task)
    }

    func testFirstPersonTaskStatementKeepsItsOwnActionOwner() {
        XCTAssertTrue(ActionabilityReader.read(
            "My own task is to email the instructor a photo of the damaged sign"
        ).belongsOnToday)
        for source in [
            "Their task is to email the instructor",
            "My task was to email the instructor",
            "The instructor said my task is to email the coordinator"
        ] {
            XCTAssertFalse(ActionabilityReader.read(source).belongsOnToday, source)
        }
    }

    func testPresentOwnedPluralNominalFramesExposeActionBodiesWithNumberAgreement() {
        for (source, expected) in [
            ("My actual job is to count the boxes.", "count the boxes."),
            ("Our actual responsibilities are to weigh the flour and wash the bowl.", "weigh the flour and wash the bowl."),
            ("My actual jobs are to count the boxes and label the shelves.", "count the boxes and label the shelves."),
            ("Our two current tasks tomorrow are to wash the bowl and clean the shelf.", "wash the bowl and clean the shelf."),
            ("Our own remaining responsibilities before lunch are to file the receipt and call Zoë.", "file the receipt and call Zoë."),
            ("My only outstanding commitments on Friday are to email José and print the form.", "email José and print the form.")
        ] {
            XCTAssertEqual(ActionabilityReader.taskEntryBody(source), expected, source)
            XCTAssertEqual(ActionabilityReader.actionBody(source), expected, source)
            XCTAssertTrue(ActionabilityReader.read(source).belongsOnToday, source)
        }
        for source in [
            "My actual jobs is to count the boxes.",
            "My actual job are to count the boxes.",
            "Our remaining responsibilities are count the boxes.",
            "My possible jobs are to count the boxes.",
            "Our tasks after Dana calls are to count the boxes.",
            "Our tasks that Dana mentioned are to count the boxes."
        ] {
            XCTAssertNil(ActionabilityReader.taskEntryBody(source), source)
        }
    }

    func testOwnedPluralActionsRemainTodayAcrossMemoryAndQuotationBoundaries() throws {
        let previous = SentenceContext.taggerDisabledForEvaluation
        defer { SentenceContext.taggerDisabledForEvaluation = previous }
        let declaration = "My actual jobs are to count the crates and label the shelves."
        for disabled in [true, false] {
            SentenceContext.taggerDisabledForEvaluation = disabled
            for source in [
                declaration,
                "The spare tape is in the drawer. " + declaration,
                "The spare tape is in the drawer. " + declaration.lowercased(),
                "The spare tape is in the drawer " + declaration,
                "Dana said, ‘Use the old cartons.’ " + declaration,
                "Dana said, ‘Use the old cartons,’ as an example. " + declaration,
            ] {
                let result = ThoughtExtractionEngine.extractWithRules(source,
                    referenceDate: referenceDate, calendar: calendar)
                XCTAssertTrue(result.operations.isEmpty, source)
                let actions = result.items.filter { $0.organization.itemType.isActionable && !$0.needsReview }
                XCTAssertEqual(actions.count, 2, source)
                XCTAssertTrue(actions.contains { $0.analysisText.localizedCaseInsensitiveContains("count the crates") }, source)
                XCTAssertTrue(actions.contains { $0.analysisText.localizedCaseInsensitiveContains("label the shelves") }, source)
                XCTAssertFalse(result.items.contains { !$0.organization.itemType.isActionable
                    && $0.analysisText.localizedCaseInsensitiveContains("count the crates") }, source)
                XCTAssertTrue(actions.allSatisfy { $0.organization.reminderDate == nil
                    && $0.organization.dueDate == nil }, source)
                if source != declaration {
                    XCTAssertTrue(result.items.contains { $0.organization.itemType == .note
                        && !$0.analysisText.localizedCaseInsensitiveContains("count the crates") }, source)
                }
                let ledger = SourceUnitLedger(source)
                let claimed = result.items.reduce(into: Set<Int>()) { $0.formUnion($1.sourceUnitIDs) }
                XCTAssertTrue(ledger.unownedMeaningfulIDs(claimed: claimed).isEmpty, source)
                if actions.count == 2 {
                    XCTAssertTrue(actions[0].sourceUnitIDs.isDisjoint(with: actions[1].sourceUnitIDs), source)
                }
                XCTAssertTrue(result.items.allSatisfy { !$0.sourceUnitIDs.isEmpty
                    && $0.sourceUnitIDs.isSubset(of: Set(ledger.words.indices)) }, source)
            }
        }
    }

    func testPluralTaskCoordinationPreservesObjectsConditionsAndFullLiteral() {
        for source in [
            "My jobs are to pack the maps and the compass and clean the table.",
            "Our actual tasks are to count the crates and to label the shelves.",
            "Our remaining tasks tomorrow are to count the crates and label the shelves."
        ] {
            let result = ThoughtExtractionEngine.extractWithRules(source,
                referenceDate: referenceDate, calendar: calendar)
            XCTAssertTrue(result.operations.isEmpty, source)
            XCTAssertFalse(result.items.isEmpty, source)
            XCTAssertTrue(result.items.allSatisfy { $0.organization.itemType.isActionable && !$0.needsReview }, source)
            let meaning = result.items.map(\.analysisText).joined(separator: " ").lowercased()
            if source.contains("maps") {
                XCTAssertTrue(meaning.contains("maps") && meaning.contains("compass")
                    && meaning.contains("clean the table"), source)
                XCTAssertFalse(result.items.contains { $0.analysisText.lowercased() == "the compass" }, source)
            } else {
                XCTAssertTrue(meaning.contains("count the crates") && meaning.contains("label the shelves"), source)
            }
            XCTAssertTrue(SourceUnitLedger(source).unownedMeaningfulIDs(claimed:
                result.items.reduce(into: Set<Int>()) { $0.formUnion($1.sourceUnitIDs) }).isEmpty, source)
        }
        // A fronted condition governs both predicates; neither becomes an
        // unconditional task just because an owned plural frame was found.
        let conditional = "If the room opens, my actual jobs are to count the crates and label the shelves."
        let result = ThoughtExtractionEngine.extractWithRules(conditional,
            referenceDate: referenceDate, calendar: calendar)
        XCTAssertTrue(result.operations.isEmpty)
        XCTAssertFalse(result.items.contains { $0.organization.itemType.isActionable && !$0.needsReview
            && !$0.analysisText.localizedCaseInsensitiveContains("if the room opens") })
        XCTAssertEqual(result.items.count, 2)
        XCTAssertTrue(result.items.allSatisfy { $0.analysisText.localizedCaseInsensitiveContains("if the room opens")
            && $0.needsReview && $0.organization.reminderDate == nil })
        let escaped = conditional.dropLast() + ", but I will clean the table regardless."
        let separate = ThoughtExtractionEngine.extractWithRules(String(escaped),
            referenceDate: referenceDate, calendar: calendar)
        XCTAssertTrue(separate.operations.isEmpty)
        let independent = separate.items.filter { $0.organization.itemType.isActionable && !$0.needsReview }
        XCTAssertEqual(independent.count, 1)
        XCTAssertTrue(independent.first?.analysisText.localizedCaseInsensitiveContains("clean the table") == true)
        XCTAssertFalse(independent.first?.analysisText.localizedCaseInsensitiveContains("if the room opens") == true)
        XCTAssertEqual(separate.items.filter { $0.analysisText.localizedCaseInsensitiveContains("if the room opens")
            && $0.needsReview }.count, 2)
        let ledger = SourceUnitLedger(String(escaped))
        XCTAssertTrue(ledger.unownedMeaningfulIDs(claimed:
            separate.items.reduce(into: Set<Int>()) { $0.formUnion($1.sourceUnitIDs) }).isEmpty)
    }

    func testPluralOwnedNominalFramesDoNotAdoptPastForeignQuotedDeniedOrHypotheticalActs() {
        for source in [
            "Their actual jobs are to count the crates and label the shelves.",
            "Her actual job is to count the crates and label the shelves.",
            "Noor's remaining responsibilities are to weigh the flour and wash the bowl.",
            "My actual jobs were to count the crates and label the shelves.",
            "My actual jobs would be to count the crates and label the shelves.",
            "Our remaining tasks could be to count the crates and label the shelves.",
            "If my actual jobs are to count the crates and label the shelves, the plan will be easy.",
            "Our actual responsibilities are not to count the crates or label the shelves.",
            "Dana said that my actual jobs are to count the crates and label the shelves.",
            "Dana asked whether my actual jobs are to count the crates and label the shelves.",
            "Dana said, ‘Use the old cartons.’ If my actual jobs are to count the crates and label the shelves, the plan will be easy.",
            "Dana wrote, ‘My actual jobs are to count the crates and label the shelves.’",
            "Dana wrote, ‘My actual jobs are to count the crates and label the shelves.",
            "I have not agreed that my actual jobs are to count the crates and label the shelves.",
            "We haven't promised that our remaining tasks are to count the crates and label the shelves.",
        ] {
            let result = ThoughtExtractionEngine.extractWithRules(source,
                referenceDate: referenceDate, calendar: calendar)
            XCTAssertTrue(result.operations.isEmpty, source)
            XCTAssertFalse(result.items.contains { $0.organization.itemType.isActionable && !$0.needsReview }, source)
        }
        let independent = "Their actual jobs are to count the crates and label the shelves. But I will clean the table."
        let result = ThoughtExtractionEngine.extractWithRules(independent,
            referenceDate: referenceDate, calendar: calendar)
        let actions = result.items.filter { $0.organization.itemType.isActionable && !$0.needsReview }
        XCTAssertEqual(actions.count, 1)
        XCTAssertTrue(actions.first?.analysisText.localizedCaseInsensitiveContains("clean the table") == true)
        XCTAssertFalse(actions.contains { $0.analysisText.localizedCaseInsensitiveContains("label the shelves") })
        for source in [
            "Her job is to count the crates; please wash the bowl.",
            "Their actual jobs are to count the crates and label the shelves, but I will clean the table.",
            "My actual jobs were to count the crates and label the shelves; please wash the bowl.",
            "Her job was to count the crates and label the shelves; I will clean the table.",
            "My jobs would be to count the crates and label the shelves; please wash the bowl.",
            "I have not agreed that my actual jobs are to count the crates and label the shelves; please wash the bowl."
        ] {
            let result = ThoughtExtractionEngine.extractWithRules(source,
                referenceDate: referenceDate, calendar: calendar)
            let actions = result.items.filter { $0.organization.itemType.isActionable && !$0.needsReview }
            XCTAssertTrue(result.operations.isEmpty, source)
            XCTAssertEqual(actions.count, 1, source)
            XCTAssertTrue(actions.first.map { $0.analysisText.localizedCaseInsensitiveContains("wash the bowl")
                || $0.analysisText.localizedCaseInsensitiveContains("clean the table") } == true, source)
            XCTAssertFalse(actions.contains { $0.analysisText.localizedCaseInsensitiveContains("count the crates")
                || $0.analysisText.localizedCaseInsensitiveContains("label the shelves") }, source)
            let ledger = SourceUnitLedger(source)
            XCTAssertTrue(ledger.unownedMeaningfulIDs(claimed:
                result.items.reduce(into: Set<Int>()) { $0.formUnion($1.sourceUnitIDs) }).isEmpty, source)
        }
        for source in [
            "Their actual jobs are to count the crates and label the shelves; remind me tomorrow to clean the table.",
            "My actual jobs were to count the crates and label the shelves; please remind me tomorrow to clean the table."
        ] {
            let result = ThoughtExtractionEngine.extractWithRules(source,
                referenceDate: referenceDate, calendar: calendar)
            let actions = result.items.filter { $0.organization.itemType.isActionable && !$0.needsReview }
            XCTAssertTrue(result.operations.isEmpty, source)
            XCTAssertEqual(actions.count, 1, source)
            XCTAssertTrue(actions.first?.analysisText.localizedCaseInsensitiveContains("clean the table") == true, source)
            XCTAssertNotNil(actions.first?.organization.reminderDate, source)
            XCTAssertFalse(actions.contains { $0.analysisText.localizedCaseInsensitiveContains("count the crates")
                || $0.analysisText.localizedCaseInsensitiveContains("label the shelves") }, source)
            let ledger = SourceUnitLedger(source)
            XCTAssertTrue(ledger.unownedMeaningfulIDs(claimed:
                result.items.reduce(into: Set<Int>()) { $0.formUnion($1.sourceUnitIDs) }).isEmpty, source)
        }
    }

    func testPluralStatusNeverUsesSingularCompletionCertificateAndPreservesTailAncestry() throws {
        for prefix in [
            "My actual jobs are to print the label and file the form, but I already printed it.",
            "Our remaining tasks are to wash the bowl and clean the shelf, but we no longer need to wash it.",
            "My actual jobs are to print the label, but I have not already printed it.",
            "My actual jobs are to print the label, but I would already have printed it.",
            "My actual jobs are to print the label, but Dana said ‘I already printed it’.",
            "My actual jobs are to print the label, but I already printed the invoice.",
        ] {
            for tail in ["", " I need to file the label at 230 tomorrow.",
                         " Change my saved dentist reminder so I call Noor instead of Maya."] {
                let source = prefix + tail
                let result = ThoughtExtractionEngine.extractWithRules(source,
                    referenceDate: referenceDate, calendar: calendar)
                let held = try XCTUnwrap(result.items.first { $0.rawQuote == prefix && $0.needsReview }, source)
                XCTAssertFalse(result.items.contains { $0.rawQuote == prefix
                    && $0.organization.itemType == .note && !$0.needsReview }, source)
                let ledger = SourceUnitLedger(source)
                let boundary = source.index(source.startIndex, offsetBy: prefix.count)
                XCTAssertEqual(held.sourceUnitIDs, ledger.ids(in: source.startIndex..<boundary), source)
                let itemIDs = result.items.reduce(into: Set<Int>()) { $0.formUnion($1.sourceUnitIDs) }
                let operationIDs = result.operations.reduce(into: Set<Int>()) { $0.formUnion($1.sourceUnitIDs) }
                XCTAssertTrue(ledger.unownedMeaningfulIDs(claimed: itemIDs.union(operationIDs)).isEmpty, source)
                if tail.contains("Change") {
                    let revision = try XCTUnwrap(result.operations.first, source)
                    XCTAssertEqual(revision.operation, .revise, source)
                    XCTAssertEqual(revision.captureSource, source)
                    XCTAssertEqual(revision.independentCreationUnitIDs, itemIDs, source)
                    XCTAssertTrue(revision.sourceUnitIDs.isDisjoint(with: itemIDs), source)
                } else {
                    XCTAssertTrue(result.operations.isEmpty, source)
                    if !tail.isEmpty {
                        let action = try XCTUnwrap(result.items.first { $0.organization.itemType.isActionable
                            && !$0.needsReview }, source)
                        XCTAssertTrue(action.rawQuote.contains("230"), source)
                        XCTAssertTrue(action.sourceUnitIDs.isDisjoint(with: held.sourceUnitIDs), source)
                    }
                }
            }
        }
    }

    func testPresentOwnedNominalTaskModifiersShareActionBodyAndPreserveCompleteSource() {
        for (source, body) in [
            ("My one job after lunch is to print the return label.", "print the return label."),
            ("Our only responsibility before the meeting is to email Zoë the revised plan.", "email Zoë the revised plan."),
            ("My remaining task tomorrow is to return the projector to Noor.", "return the projector to Noor."),
            ("Our own next commitment on Friday is to call the office about the permit.", "call the office about the permit."),
            ("My only outstanding job for this afternoon is to file the receipt.", "file the receipt.")
        ] {
            XCTAssertEqual(ActionabilityReader.taskEntryBody(source), body, source)
            XCTAssertTrue(ActionabilityReader.read(source).belongsOnToday, source)
            let result = ThoughtExtractionEngine.extractWithRules(source)
            XCTAssertTrue(result.operations.isEmpty, source)
            XCTAssertEqual(result.items.count, 1, source)
            XCTAssertTrue(result.items.first?.organization.itemType.isActionable == true, source)
            XCTAssertEqual(result.items.first?.rawQuote, source, source)
            XCTAssertEqual(result.items.first?.sourceQuote, source, source)
        }
        let scheduled = ThoughtOrganizer.organize("My remaining task tomorrow is to return the projector.",
            referenceDate: referenceDate, calendar: calendar)
        XCTAssertEqual(scheduled.dueDate.map { calendar.startOfDay(for: $0) },
            calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: referenceDate)))
    }

    func testNominalTaskModifiersDoNotLicenseAnotherOwnerPastHypotheticalOrDeniedAction() {
        for source in [
            "Their one job after lunch is to print the label.",
            "My one job after lunch was to print the label.",
            "My only task tomorrow would be to return the projector.",
            "If my only task is to print the form, the afternoon will be easy.",
            "My remaining responsibility before lunch is not to call the office.",
            "Dana said my one job after lunch is to print the label.",
            #"Dana wrote, "My one job after lunch is to print the label.""#,
            "My one job after lunch is to print the label, but I already printed it.",
            "My remaining job is to return the projector, but I no longer need to return it."
        ] {
            XCTAssertFalse(ActionabilityReader.read(source).belongsOnToday, source)
            let result = ThoughtExtractionEngine.extractWithRules(source)
            XCTAssertFalse(result.items.contains { $0.organization.itemType.isActionable && !$0.needsReview }, source)
        }
        for source in ["My possible task after lunch is to print the form.",
                       "My job after Dana calls is to print the form.",
                       "My job that Dana mentioned is to print the form."] {
            XCTAssertNil(ActionabilityReader.taskEntryBody(source), source)
        }
    }

    func testFiniteReportedAgreementRetainsContentAndOwnActionAdoptionStaysActionable() {
        for source in [
            "The team agreed that the report should be shorter.",
            "The committee agrees that the room should stay quiet.",
            "Dana agreed that the gate should remain closed.",
            "We agreed that the report should use larger type."
        ] {
            XCTAssertEqual(ActionabilityReader.read(source), .knowledge, source)
            let result = ThoughtExtractionEngine.extractWithRules(source)
            XCTAssertTrue(result.operations.isEmpty, source)
            XCTAssertFalse(result.items.contains { $0.organization.itemType.isActionable && !$0.needsReview }, source)
            XCTAssertTrue(result.items.contains { $0.sourceQuote == source }, source)
        }
        for source in ["I agreed to call the office tomorrow.",
                       "We agreed to print the revised report.",
                       "The team agreed that I should call the office.",
                       "Dana asked me to print the report."] {
            XCTAssertTrue(ActionabilityReader.read(source).belongsOnToday, source)
        }
    }

    func testNominalTaskStatusBindsCurrentObjectWithoutSavedEffects() {
        let originalTaggerSetting = SentenceContext.taggerDisabledForEvaluation
        defer { SentenceContext.taggerDisabledForEvaluation = originalTaggerSetting }
        for disabled in [true, false] {
            SentenceContext.taggerDisabledForEvaluation = disabled
            for source in [
                "My one job after lunch is to print the label, but I already printed it.",
                "Our only task tomorrow is to file the label, but we already filed the label.",
                "My remaining responsibility is to wash the bowl, but I already washed it.",
                "My remaining job is to return the projector, but I no longer need to return it.",
                "Our only task is to clean the shelf, but we no longer have to clean the shelf.",
            ] {
                for permitsOperations in [true, false] {
                    let result = ThoughtExtractionEngine.extractWithRules(source, permitsOperations: permitsOperations)
                    XCTAssertTrue(result.operations.isEmpty, source)
                    XCTAssertTrue(result.items.contains { $0.rawQuote == source && $0.analysisText == source }, source)
                    XCTAssertTrue(result.items.allSatisfy {
                        $0.organization.itemType == .note && !$0.needsReview
                            && $0.organization.dueDate == nil && $0.organization.reminderDate == nil
                            && $0.organization.reminderDelivery == .none
                    }, source)
                    XCTAssertEqual(result.items.reduce(into: Set<Int>()) { $0.formUnion($1.sourceUnitIDs) },
                                   Set(SourceUnitLedger(source).words.indices), source)
                }
            }
        }
    }

    func testCurrentNominalStatusPreservesIndependentLaterActionsAndNamedSavedChanges() {
        for source in [
            "My one job is to print the label, but I already printed it. I need to mail the parcel.",
            "My one job is to print the label, but I already printed it, and I need to call Noor.",
            "Our remaining task is to wash the bowl, but we no longer need to wash it. Please file the receipt.",
        ] {
            let result = ThoughtExtractionEngine.extractWithRules(source)
            XCTAssertTrue(result.operations.isEmpty, source)
            XCTAssertTrue(result.items.contains { $0.organization.itemType == .note && $0.rawQuote.contains("but") }, source)
            XCTAssertTrue(result.items.contains { $0.organization.itemType.isActionable && !$0.needsReview }, source)
            XCTAssertFalse(result.items.contains { $0.organization.itemType.isActionable && $0.analysisText.contains("print the label") }, source)
            let ledger = SourceUnitLedger(source)
            let claimed = result.items.reduce(into: Set<Int>()) { $0.formUnion($1.sourceUnitIDs) }
            XCTAssertTrue(ledger.unownedMeaningfulIDs(claimed: claimed).isEmpty, source)
            for memory in result.items where memory.organization.itemType == .note {
                XCTAssertFalse(memory.sourceUnitIDs.isEmpty, source)
                for action in result.items where action.organization.itemType.isActionable {
                    XCTAssertTrue(memory.sourceUnitIDs.isDisjoint(with: action.sourceUnitIDs), source)
                }
            }
        }
        let source = "My one job is to print the label, but I already printed it. Cancel my saved dentist reminder."
        let result = ThoughtExtractionEngine.extractWithRules(source)
        XCTAssertTrue(result.items.contains { $0.organization.itemType == .note && $0.rawQuote.contains("printed it") })
        XCTAssertTrue(result.operations.contains { $0.target?.localizedCaseInsensitiveContains("dentist") == true })
        XCTAssertFalse(result.operations.contains { $0.sourceQuote.contains("printed it") })
        XCTAssertEqual(result.operations.first?.captureSource, source)
        XCTAssertEqual(result.operations.first?.independentCreationUnitIDs,
                       result.items.reduce(into: Set<Int>()) { $0.formUnion($1.sourceUnitIDs) })
    }

    func testNominalStatusOwnershipSurvivesTailRepairRepeatedWordsAndSavedRevision() throws {
        let prefix = "My one job is to print the label, but I already printed it."
        for tail in ["I need to file the label at 230 tomorrow.",
                     "Change my saved dentist reminder so I call Noor instead of Maya."] {
            let source = prefix + " " + tail
            let result = ThoughtExtractionEngine.extractWithRules(source)
            let ledger = SourceUnitLedger(source)
            let boundary = source.index(source.startIndex, offsetBy: prefix.count)
            let memory = try XCTUnwrap(result.items.first { $0.rawQuote == prefix }, source)
            XCTAssertEqual(memory.sourceUnitIDs, ledger.ids(in: source.startIndex..<boundary), source)
            let itemIDs = result.items.reduce(into: Set<Int>()) { $0.formUnion($1.sourceUnitIDs) }
            let operationIDs = result.operations.reduce(into: Set<Int>()) { $0.formUnion($1.sourceUnitIDs) }
            XCTAssertTrue(ledger.unownedMeaningfulIDs(claimed: itemIDs.union(operationIDs)).isEmpty, source)
            XCTAssertTrue(itemIDs.union(operationIDs).isSubset(of: Set(ledger.words.indices)), source)
            XCTAssertTrue(memory.sourceUnitIDs.isDisjoint(with: operationIDs), source)
            if tail.hasPrefix("Change") {
                let request = try XCTUnwrap(result.operations.first, source)
                XCTAssertEqual(request.operation, .revise, source)
                XCTAssertEqual(request.savedFieldRevision?.newValue, "Noor", source)
                XCTAssertEqual(request.captureSource, source)
                XCTAssertEqual(request.independentCreationUnitIDs, itemIDs, source)
                XCTAssertTrue(request.independentCreationUnitIDs.isDisjoint(with: request.sourceUnitIDs), source)
            } else {
                let action = try XCTUnwrap(result.items.first { $0.organization.itemType.isActionable }, source)
                XCTAssertFalse(action.needsReview, source)
                XCTAssertTrue(action.rawQuote.contains("230"), source)
                XCTAssertTrue(action.sourceUnitIDs.isDisjoint(with: memory.sourceUnitIDs), source)
            }
        }
    }

    func testNominalStatusCannotCloseDifferentObjectOwnerOrConditionalAction() {
        for source in [
            "My one job is to print the label, but I already printed the invoice.",
            "My one job is to print the label, but Maya already printed the invoice.",
            "My one job is to print the label, but I have not already printed it.",
            "My one job is to print the label, but I would already have printed it.",
            "My one job is to print the label, but I already printed it if the printer worked.",
            "My one job is to print the label, but I no longer need to file it.",
            "My one job is to print the label, but I no longer need to print it unless Maya asks.",
            "My one job is to print the label and the invoice, but I already printed it.",
            "My one job is to print the label, but Maya said ‘I already printed it’.",
        ] {
            let result = ThoughtExtractionEngine.extractWithRules(source)
            XCTAssertFalse(result.items.contains {
                $0.rawQuote == source && $0.organization.itemType == .note && !$0.needsReview
            }, source)
            XCTAssertTrue(result.operations.isEmpty, source)
            XCTAssertTrue(result.items.contains { $0.rawQuote == source && $0.needsReview }, source)
            XCTAssertTrue(result.items.allSatisfy {
                $0.organization.dueDate == nil && $0.organization.reminderDate == nil
            }, source)
            XCTAssertEqual(result.items.reduce(into: Set<Int>()) { $0.formUnion($1.sourceUnitIDs) },
                           Set(SourceUnitLedger(source).words.indices), source)
        }
    }

    func testUnprovedNominalStatusKeepsIndependentLaterWorkAndSavedRevision() throws {
        for prefix in [
            "My one job is to print the label, but I have not already printed it.",
            "My one job is to print the label, but Maya already printed the invoice.",
            "My one job is to print the label, but Maya said ‘I already printed it’.",
        ] {
            for tail in ["I need to mail the parcel.",
                         "Change my saved dentist reminder so I call Noor instead of Maya."] {
                let source = prefix + " " + tail
                let result = ThoughtExtractionEngine.extractWithRules(source)
                let ledger = SourceUnitLedger(source)
                let boundary = source.index(source.startIndex, offsetBy: prefix.count)
                let held = try XCTUnwrap(result.items.first { $0.rawQuote == prefix && $0.needsReview }, source)
                XCTAssertEqual(held.sourceUnitIDs, ledger.ids(in: source.startIndex..<boundary), source)
                let itemIDs = result.items.reduce(into: Set<Int>()) { $0.formUnion($1.sourceUnitIDs) }
                if tail.hasPrefix("Change") {
                    let request = try XCTUnwrap(result.operations.first, source)
                    XCTAssertEqual(request.operation, .revise, source)
                    XCTAssertEqual(request.captureSource, source)
                    XCTAssertEqual(request.independentCreationUnitIDs, itemIDs, source)
                    XCTAssertTrue(request.sourceUnitIDs.isDisjoint(with: itemIDs), source)
                } else {
                    XCTAssertTrue(result.operations.isEmpty, source)
                    let action = try XCTUnwrap(result.items.first { $0.organization.itemType.isActionable && !$0.needsReview }, source)
                    XCTAssertTrue(action.analysisText.contains("mail the parcel"), source)
                    XCTAssertTrue(held.sourceUnitIDs.isDisjoint(with: action.sourceUnitIDs), source)
                }
                let operationIDs = result.operations.reduce(into: Set<Int>()) { $0.formUnion($1.sourceUnitIDs) }
                XCTAssertTrue(ledger.unownedMeaningfulIDs(claimed: itemIDs.union(operationIDs)).isEmpty, source)
            }
        }
    }

    func testKeepNoteAboutEventRecordsKnowledgeWithoutDemotingPhysicalErrand() {
        XCTAssertEqual(ActionabilityReader.read(
            "Keep a note about what happened in the workshop"
        ), .knowledge)
        XCTAssertEqual(ThoughtOrganizer.organize(
            "Keep a note about what happened in the workshop"
        ).itemType, .note)
        XCTAssertTrue(ActionabilityReader.read(
            "Keep a note on your desk"
        ).belongsOnToday)
    }

    func testUnresolvedSelectionIsNotAnOverdueTask() {
        for text in [
            "I have not chosen between the ferry and the tram",
            "We still haven't decided whether to mail or submit online",
            "I haven't selected a camera yet",
            "I have not picked which option to use",
        ] {
            XCTAssertEqual(ActionabilityReader.read(text), .knowledge, text)
        }
        for text in [
            "I have not paid the invoice",
            "I haven't booked the train",
            "I haven't picked up the parcel",
            "I need to decide between the ferry and the tram",
        ] {
            XCTAssertTrue(ActionabilityReader.read(text).belongsOnToday, text)
        }
        XCTAssertFalse(ActionabilityReader.read("Mara has not chosen a route").belongsOnToday)
    }

    func testFirstPersonScheduledActivitySurvivesSharedVerbVocabulary() {
        for source in [
            "A week on Friday we leave for Spain",
            "We leave for the station Tuesday",
            "I pack the folder on Thursday",
        ] {
            let organized = ThoughtOrganizer.organize(
                source, referenceDate: referenceDate, calendar: calendar
            )
            XCTAssertTrue(organized.itemType.isActionable, source)
            XCTAssertNotNil(organized.dueDate, source)
        }
        for source in [
            "We left for Spain last Friday",
            "Maya said we leave for Spain Friday",
            "The leave policy is in the folder",
            "Maya is on leave this week",
        ] {
            XCTAssertFalse(ActionabilityReader.read(source).belongsOnToday, source)
        }
    }

    func testVisibleTaskConditionIsNotAnUnsupportedReminderTrigger() {
        for text in [
            "Set aside the spare key for Elena when she visits",
            "Call Dave when I get paid",
            "Text Mom after we land",
            "Set aside the key once Elena visits",
        ] {
            let items = ThoughtExtractionEngine.extractWithRules(text).items
            XCTAssertEqual(items.count, 1, text)
            guard let item = items.first else { continue }
            XCTAssertTrue(item.organization.itemType.isActionable, text)
            XCTAssertFalse(item.organization.needsClarification, text)
            XCTAssertNil(item.organization.temporalIntent.unsupportedTrigger, text)
            XCTAssertTrue((item.suggestedTitle ?? item.sourceQuote).lowercased().contains(
                text.contains("after") ? "after" : (text.contains("once") ? "once" : "when")
            ), "The condition must remain visible on the action row: \(text)")
            XCTAssertNil(item.organization.reminderDate, text)
        }

        for text in [
            "When I get paid, call Dave",
            "After I land, text Mom",
            "Remind me to call Dave when I get paid",
        ] {
            let items = ThoughtExtractionEngine.extractWithRules(text).items
            XCTAssertEqual(items.count, 1, text)
            XCTAssertTrue(items[0].organization.needsClarification, text)
            XCTAssertEqual(items[0].organization.temporalIntent.unsupportedTrigger, .condition, text)
            XCTAssertNil(items[0].organization.reminderDate, text)
        }

        let fact = ThoughtExtractionEngine.extractWithRules(
            "The spare key is in the drawer when Elena visits"
        ).items
        XCTAssertEqual(fact.count, 1)
        XCTAssertEqual(fact[0].organization.itemType, .note)
        XCTAssertFalse(fact[0].organization.needsClarification)
    }

    func testOrdinalObjectIsNotADateButAnOrdinalDateStillIs() {
        XCTAssertFalse(
            ActionabilityReader.read("The director wants the second line slower and a pause before bridge")
                .belongsOnToday
        )
        XCTAssertFalse(
            ThoughtExtractionEngine.extractWithRules("The director wants the second line slower").items[0]
                .organization.itemType.isActionable
        )
        XCTAssertTrue(ActionabilityReader.read("The meeting is on the second at noon").belongsOnToday)
        XCTAssertTrue(ActionabilityReader.read("On the first don’t forget the rent").belongsOnToday)
        XCTAssertEqual(
            ThoughtOrganizer.organize(
                "On the 1st renew the car insurance",
                referenceDate: referenceDate, calendar: calendar
            ).dueDate,
            calendar.date(from: DateComponents(year: 2026, month: 9, day: 1))
        )
    }

    func testAnaphoricRecordingRequestOwnsThePrecedingFact() {
        let items = ThoughtExtractionEngine.extractWithRules(
            "The director wants the second line slower. Remember that staging note. "
                + "Return the rehearsal key tomorrow."
        ).items
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items[0].organization.itemType, .note)
        XCTAssertTrue(items[0].sourceQuote.contains("Remember that staging note"))
        XCTAssertTrue(items[1].organization.itemType.isActionable)

        let separate = ThoughtExtractionEngine.extractWithRules(
            "The director wants the second line slower. Remember to return the key tomorrow."
        ).items
        XCTAssertEqual(separate.count, 2)
        XCTAssertTrue(separate[1].organization.itemType.isActionable)
    }

    func testExplicitFactRecordingFrameDoesNotBecomePhysicalKeepAction() {
        let memory = ThoughtExtractionEngine.extractWithRules(
            "At the start of this recording I want to keep a detail: the cinema had green seats"
        ).items
        XCTAssertEqual(memory.count, 1)
        XCTAssertEqual(memory[0].organization.itemType, .note)
        let physical = ThoughtExtractionEngine.extractWithRules("I want to keep a file in the drawer").items
        XCTAssertEqual(physical.count, 1)
        XCTAssertTrue(physical[0].organization.itemType.isActionable)
    }

    func testFirstPersonPromiseRemainsAnActionAndOtherOwnersStayKnowledge() {
        XCTAssertTrue(ActionabilityReader.read("I promised to update the contact sheet by Friday").belongsOnToday)
        XCTAssertTrue(ActionabilityReader.read("Separately, I promised to update the contact sheet by Friday").belongsOnToday)
        XCTAssertTrue(ActionabilityReader.read("We agreed to call the office").belongsOnToday)
        XCTAssertFalse(ActionabilityReader.read("Mira promised to update the contact sheet").belongsOnToday)
        XCTAssertFalse(ActionabilityReader.read("I promised to call the office, and I already called").belongsOnToday)
    }

    func testLearningAPropositionIsKnowledgeUnlessItContainsOwnCommitment() {
        XCTAssertEqual(ActionabilityReader.read(
            "At the garden meeting I learned that the north bed keeps moisture longer"
        ), .knowledge)
        XCTAssertEqual(ActionabilityReader.read(
            "I learned that I need to call the office tomorrow"
        ), .actionable)
        XCTAssertEqual(ActionabilityReader.read(
            "I found the blue tin, which I want to remember"
        ), .knowledge)
        XCTAssertTrue(ActionabilityReader.read("I need to find the blue tin").belongsOnToday)
    }

    func testConditionalObligationDoesNotTakeOwnershipFromFactualMatrix() {
        for text in [
            "The spare key is in the drawer, which helps if I have to leave early",
            "The paper statement is in the drawer if I have to find it again",
            "The clinic opens at nine if I need to go",
        ] {
            XCTAssertEqual(ActionabilityReader.read(text), .knowledge, text)
            XCTAssertEqual(
                ThoughtExtractionEngine.extractWithRules(text).items.first?.organization.itemType,
                .note, text
            )
        }
        for text in [
            "Call Maya if she is free",
            "I need to call Maya if she is free",
            "I promised to call Maya if she is free",
            "I learned that I need to call Maya",
        ] {
            XCTAssertTrue(ActionabilityReader.read(text).belongsOnToday, text)
        }
        XCTAssertTrue(ActionabilityReader.read(
            "The key is in the drawer if I need it, and I need to call Maya"
        ).belongsOnToday)
    }

    func testPropositionalKeepIsMemoryAndPhysicalKeepRemainsAnAction() {
        let fact = ThoughtExtractionEngine.extractWithRules(
            "What I actually want to keep is that Rosa prefers advance notice"
        ).items
        XCTAssertEqual(fact.count, 1)
        XCTAssertEqual(fact[0].organization.itemType, .note)
        let action = ThoughtExtractionEngine.extractWithRules("Keep the file in the drawer").items
        XCTAssertEqual(action.count, 1)
        XCTAssertTrue(action[0].organization.itemType.isActionable)
        let recording = ThoughtExtractionEngine.extractWithRules(
            "Keep in mind that Rosa prefers advance notice"
        ).items
        XCTAssertEqual(recording.count, 1)
        XCTAssertEqual(recording[0].organization.itemType, .note)
        for adverb in ["actually", "really", "also"] {
            let source = "What I \(adverb) want to keep is that Rosa prefers advance notice"
            let reading = ActionabilityReader.read(source)
            XCTAssertEqual(reading, .knowledge, adverb)
            let rows = ThoughtExtractionEngine.extractWithRules(source).items
            XCTAssertEqual(rows.count, 1, adverb)
            XCTAssertEqual(
                ThoughtTitleFormatter.polished(
                    rows.first?.suggestedTitle ?? rows.first?.sourceQuote ?? "",
                    itemType: .note
                ),
                "Rosa prefers advance notice", adverb
            )
        }
        XCTAssertEqual(
            ActionabilityReader.read("I also want to keep a file in the drawer"),
            .actionable
        )
    }

    func testDescribedQuotedImperativeStaysKnowledgeWhileExplicitReminderActs() {
        XCTAssertEqual(
            ActionabilityReader.read("If I say 'pick up' while describing that routine, it is not a shopping task"),
            .knowledge
        )
        XCTAssertEqual(
            ActionabilityReader.read("If I say 'call Mom', remind me to call her"),
            .actionable
        )
    }

    func testEmphaticNeedListIsShoppingWithoutSwallowingAnInfinitive() {
        let groceries = ThoughtExtractionEngine.extractWithRules("We do need eggs and rice").items
        XCTAssertFalse(groceries.isEmpty)
        XCTAssertTrue(groceries.allSatisfy { $0.organization.itemType.isActionable })
        let conversation = ThoughtExtractionEngine.extractWithRules("We do need to talk to Jo").items
        XCTAssertEqual(conversation.count, 1)
        XCTAssertNotEqual(conversation[0].organization.itemType, .shopping)
    }

    func testThinkingFrameSeparatesAnIdeaFromACommittedAction() {
        let idea = ThoughtExtractionEngine.extractWithRules(
            "I was thinking of calling Mom", referenceDate: referenceDate,
            calendar: calendar
        )
        XCTAssertEqual(idea.items.count, 1)
        XCTAssertEqual(idea.items[0].organization.itemType, .idea)
        XCTAssertFalse(idea.items[0].organization.itemType.isActionable)
        XCTAssertFalse(idea.items[0].needsReview)
        XCTAssertEqual(idea.items[0].rawQuote, "I was thinking of calling Mom")

        let committed = ThoughtExtractionEngine.extractWithRules(
            "I should call Mom", referenceDate: referenceDate, calendar: calendar
        )
        XCTAssertEqual(committed.items.count, 1)
        XCTAssertTrue(committed.items[0].organization.itemType.isActionable)

        let imperative = ThoughtExtractionEngine.extractWithRules(
            "Like, I was thinking, buy milk", referenceDate: referenceDate,
            calendar: calendar
        )
        XCTAssertEqual(imperative.items.count, 1)
        XCTAssertEqual(imperative.items[0].organization.itemType, .shopping)
    }

    func testSequencingOpenerKeepsACommittedActionOnToday() {
        XCTAssertTrue(ActionabilityReader.read("First, email the landlord").belongsOnToday)
        XCTAssertEqual(ActionabilityReader.actionBody("First, email the landlord"), "email the landlord")
        XCTAssertFalse(ActionabilityReader.read("The first aid kit is in the cupboard").belongsOnToday)
        XCTAssertEqual(ActionabilityReader.read("Separately, remember that the key is in the drawer"), .knowledge)
        XCTAssertTrue(ActionabilityReader.read("Separately, remember to take the key").belongsOnToday)
    }

    func testShortPerformableImperativesDoNotDependOnDeviceTagging() {
        for source in ["Swap the batteries", "Ring my insurance agent", "Create a checklist",
                       "Sharpen garden shears", "Unclog the sink", "Reheat the soup"] {
            XCTAssertTrue(ActionabilityReader.read(source).belongsOnToday, source)
        }
        for source in ["The swap was costly", "The ring is gold",
                       "The soup was reheated yesterday"] {
            XCTAssertFalse(ActionabilityReader.read(source).belongsOnToday, source)
        }
    }

    func testHoldImperativeDoesNotPromoteNominalFiniteQuotedOrReportedUses() throws {
        let previous = SentenceContext.taggerDisabledForEvaluation
        defer {
            SentenceContext.taggerDisabledForEvaluation = previous
            SentenceContextCache.invalidate()
        }
        for disabled in [false, true] {
            SentenceContext.taggerDisabledForEvaluation = disabled
            SentenceContextCache.invalidate()
            let command = "Hold the order."
            XCTAssertTrue(ActionabilityReader.read(command).belongsOnToday, command)
            let result = ThoughtExtractionEngine.extractWithRules(command,
                referenceDate: referenceDate, calendar: calendar)
            XCTAssertEqual(result.items.count, 1, command)
            let item = try XCTUnwrap(result.items.first, command)
            XCTAssertEqual(item.organization.itemType, .task, command)
            XCTAssertFalse(item.needsReview, command)
            XCTAssertNil(item.organization.dueDate, command)
            XCTAssertNil(item.organization.reminderDate, command)
            for source in [
                "The hold order is temporary.",
                "Hold orders are temporary.",
                "The warehouse holds the order.",
                "The phrase 'hold the order' is printed on the form.",
                "Nadia said, 'Hold the order.'"
            ] {
                XCTAssertFalse(ActionabilityReader.read(source).belongsOnToday, source)
                let reading = ThoughtExtractionEngine.extractWithRules(source,
                    referenceDate: referenceDate, calendar: calendar)
                XCTAssertFalse(reading.items.contains { $0.organization.itemType.isActionable }, source)
                XCTAssertTrue(reading.operations.isEmpty, source)
            }
        }
    }

    func testRequiredResultStatesCreateSeparateJobsWithoutInventingObjects() {
        let jobs = ThoughtExtractionEngine.extractWithRules(
            "The house needs the windows cleaned and the gutters cleared"
        ).items
        XCTAssertEqual(jobs.count, 2)
        XCTAssertTrue(jobs.allSatisfy { $0.organization.itemType.isActionable })
        XCTAssertTrue(jobs[0].sourceQuote.contains("windows cleaned"))
        XCTAssertTrue(jobs[1].sourceQuote.contains("gutters cleared"))
        XCTAssertEqual(ThoughtExtractionEngine.extractWithRules(
            "The museum needs the blue and white posters"
        ).items.count, 1)
    }

    func testExplainedObligationBelongingToAnotherPersonStaysKnowledge() {
        XCTAssertEqual(
            ActionabilityReader.read(
                "She explained that the early numbers were estimates and that the family should keep the printed instructions"
            ),
            .knowledge
        )
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Toronto")!
        return calendar
    }

    private var referenceDate: Date {
        calendar.date(from: DateComponents(year: 2026, month: 8, day: 3, hour: 10, minute: 0))!
    }

    // MARK: Invariant 1 — time never promotes history

    func testContractedCalendarFactsDoNotInventEvents() {
        for source in ["It's Monday.", "It’s Monday.", "That's Friday.", "That’s Friday.",
                       "It is Monday.", "That is Friday."] {
            XCTAssertFalse(ActionabilityReader.read(source).belongsOnToday, source)
            let result = ThoughtExtractionEngine.extractWithRules(source,
                referenceDate: referenceDate, calendar: calendar)
            XCTAssertEqual(result.items.count, 1, source)
            XCTAssertEqual(result.items.first?.rawQuote, source)
            XCTAssertEqual(result.items.first?.organization.itemType, .note, source)
            XCTAssertNil(result.items.first?.organization.dueDate, source)
            XCTAssertNil(result.items.first?.organization.reminderDate, source)
        }
    }

    func testContractedDeadlinesAndExplicitAppointmentsKeepTheirDates() {
        for source in ["It's due Friday.", "It’s due Friday.", "That's Tuesday at two.",
                       "It's Tuesday at two.", "The meeting is Monday.",
                       "Maya's meeting is Monday.", "Remind me Friday that it's Monday."] {
            let result = ThoughtExtractionEngine.extractWithRules(source,
                referenceDate: referenceDate, calendar: calendar)
            XCTAssertEqual(result.items.count, 1, source)
            XCTAssertEqual(result.items.first?.rawQuote, source)
            XCTAssertTrue(result.items.first?.organization.itemType.isActionable == true, source)
            XCTAssertNotNil(result.items.first?.organization.dueDate, source)
        }
    }

    func testPossessiveEventDayDoesNotScheduleAnAction() {
        let context = ThoughtOrganizer.organize(
            "Text Leo the address for Saturday's dinner",
            referenceDate: referenceDate, calendar: calendar
        )
        XCTAssertEqual(context.itemType, .personFollowUp)
        XCTAssertNil(context.dueDate)
        let direct = ThoughtOrganizer.organize(
            "Text Leo Saturday",
            referenceDate: referenceDate, calendar: calendar
        )
        XCTAssertEqual(direct.itemType, .personFollowUp)
        XCTAssertNotNil(direct.dueDate)
        let object = ThoughtOrganizer.organize(
            "Buy Monday's newspaper",
            referenceDate: referenceDate, calendar: calendar
        )
        XCTAssertEqual(object.itemType, .shopping)
        XCTAssertNil(object.dueDate)
    }

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
        XCTAssertEqual(items.count, 2, String(describing: items.map(\.analysisText)))
        XCTAssertEqual(items.first?.organization.itemType, .note)
        let action = try XCTUnwrap(items.last)
        XCTAssertTrue(action.organization.itemType.isActionable)
        XCTAssertEqual(action.organization.dueDate,
                       calendar.date(from: DateComponents(year: 2026, month: 8, day: 4)))

        let sharedFact = ThoughtExtractionEngine.extractWithRules(
            "I had better luck last time and better service at the hotel",
            referenceDate: referenceDate, calendar: calendar
        ).items
        XCTAssertEqual(sharedFact.count, 1)
        XCTAssertEqual(sharedFact.first?.organization.itemType, .note)
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
        for text in ["Devon Smith", "Regina King", "Preston Hall", "Rebecca Miles", "hope he's okay", "Unhappy clients"] {
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
        XCTAssertEqual(ActionabilityReader.actionBody("at the store buy milk"), "buy milk")
        XCTAssertEqual(ActionabilityReader.actionBody("on the way home from work pick up milk"), "pick up milk")
        XCTAssertEqual(ActionabilityReader.actionBody("after class submit my assignment"), "submit my assignment")
        XCTAssertEqual(ActionabilityReader.actionBody("this weekend clean the garage"), "clean the garage")
        XCTAssertEqual(ActionabilityReader.actionBody("at the store the milk is cheaper"),
                       "at the store the milk is cheaper")
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
        XCTAssertEqual(ActionabilityReader.actionBody("while I'm out there grab stamps"), "grab stamps")
        XCTAssertEqual(ActionabilityReader.actionBody("while I'm out there I feel better"),
                       "while I'm out there I feel better")
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

    func testCompleteCommandAfterFrontedTimeCanEndBeforeAnotherCommand() {
        XCTAssertEqual(
            ClauseJuxtaposition.pieces(in: "tomorrow buy cheese after class submit my assignment before midnight ask Alex about Sunday"),
            ["tomorrow buy cheese after class", "submit my assignment before midnight", "ask Alex about Sunday"]
        )
        XCTAssertEqual(
            ClauseJuxtaposition.pieces(in: "after lunch call Mom buy bread"),
            ["after lunch call Mom", "buy bread"]
        )
        XCTAssertEqual(ClauseJuxtaposition.pieces(in: "after lunch call Mom"),
                       ["after lunch call Mom"])
        XCTAssertEqual(ClauseJuxtaposition.pieces(in: "tomorrow morning email the landlord"),
                       ["tomorrow morning email the landlord"])
    }

    func testCoordinatedPrepositionalObjectsOwnFollowingAside() {
        XCTAssertEqual(
            RuleBasedThoughtExtractor.splitClauses("Split the cabin rental with Tom and Alice it's $1200 total so $400 each"),
            ["Split the cabin rental with Tom and Alice it's $1200 total so $400 each"]
        )
        XCTAssertEqual(
            RuleBasedThoughtExtractor.splitClauses("Plan dinner with Ben and Maya it's their anniversary"),
            ["Plan dinner with Ben and Maya it's their anniversary"]
        )
        XCTAssertEqual(
            RuleBasedThoughtExtractor.splitClauses("Split the cabin rental with Tom and call Alice later"),
            ["Split the cabin rental with Tom", "call Alice later"]
        )
        XCTAssertEqual(
            RuleBasedThoughtExtractor.splitClauses("Split the cabin rental with Tom and Alice then send the receipt"),
            ["Split the cabin rental with Tom and Alice", "send the receipt"]
        )
        XCTAssertEqual(
            RuleBasedThoughtExtractor.splitClauses("Split rent with Tom and Alice she already paid"),
            ["Split rent with Tom and Alice", "she already paid"]
        )
        XCTAssertEqual(
            RuleBasedThoughtExtractor.splitClauses("Split rent with Tom and Alice I need to pay Friday"),
            ["Split rent with Tom and Alice", "I need to pay Friday"]
        )
        XCTAssertEqual(
            RuleBasedThoughtExtractor.splitClauses("Maya said split rent with Tom and Alice she already paid"),
            ["Maya said split rent with Tom and Alice she already paid"]
        )
        XCTAssertEqual(
            RuleBasedThoughtExtractor.splitClauses("Text Maya that I split rent with Tom and Alice I need to pay Friday"),
            ["Text Maya that I split rent with Tom and Alice I need to pay Friday"]
        )
        XCTAssertEqual(
            RuleBasedThoughtExtractor.splitClauses("Split rent with Tom and Alice I guess"),
            ["Split rent with Tom and Alice I guess"]
        )
    }

    func testAnaphoricMemoryContinuationKeepsOneRetrievalIdentity() {
        let linked = RuleBasedThoughtExtractor.process(
            "Remember the lighthouse has a red door. It faces the harbor."
        ).items
        XCTAssertEqual(linked.count, 1)
        XCTAssertEqual(linked.first?.organization.itemType, .note)
        XCTAssertTrue(linked.first?.sourceQuote.contains("It faces the harbor") == true)
        XCTAssertTrue(linked.first?.rawQuote.contains("red door") == true)

        let unrelatedPerson = RuleBasedThoughtExtractor.process(
            "Remember the spare key is under the mat. She prefers tea."
        ).items
        XCTAssertEqual(unrelatedPerson.count, 2)
        let personContinuation = RuleBasedThoughtExtractor.process(
            "Remember Mum's recipe uses fennel. She adds it last."
        ).items
        XCTAssertEqual(personContinuation.count, 1)

        let fragment = RuleBasedThoughtExtractor.process(
            "Remember Dad likes almond cake. Almond cake, not chocolate."
        ).items
        XCTAssertEqual(fragment.count, 1)
        XCTAssertTrue(fragment.first?.sourceQuote.contains("not chocolate") == true)

        let newRecording = RuleBasedThoughtExtractor.process(
            "Remember the lighthouse has a red door. Remember the ferry leaves at seven."
        ).items
        XCTAssertEqual(newRecording.count, 2)
        let newAction = RuleBasedThoughtExtractor.process(
            "Remember the lighthouse has a red door. Call Maya tomorrow."
        ).items
        XCTAssertEqual(newAction.count, 2)
        XCTAssertEqual(newAction.map { $0.organization.itemType.isActionable }, [false, true])

        let contrast = RuleBasedThoughtExtractor.process(
            "Buy almond cake, not chocolate."
        ).items
        XCTAssertEqual(contrast.count, 1)
        XCTAssertEqual(contrast.first?.organization.itemType, .shopping)
        XCTAssertFalse(contrast.contains { $0.suggestedTitle?.lowercased().contains("buy not") == true })
        let bareList = RuleBasedThoughtExtractor.process("Milk, eggs, bread.").items
        XCTAssertEqual(bareList.count, 3)
        XCTAssertTrue(bareList.allSatisfy { $0.organization.itemType == .shopping })

        let excluded = RuleBasedThoughtExtractor.process("Milk, eggs, not sugar.").items
        XCTAssertEqual(excluded.filter { $0.organization.itemType == .shopping }.count, 2)
        XCTAssertTrue(excluded.contains {
            $0.needsReview && $0.sourceQuote.lowercased().contains("not sugar")
        })
        XCTAssertFalse(excluded.contains {
            $0.suggestedTitle?.lowercased().contains("buy not") == true
        })
        let branded = RuleBasedThoughtExtractor.process("No Name milk, eggs.").items
        XCTAssertEqual(branded.count, 2)
        XCTAssertTrue(branded.allSatisfy { $0.organization.itemType == .shopping })
        let negative = RuleBasedThoughtExtractor.process("No sugar, eggs.").items
        XCTAssertFalse(negative.contains {
            $0.suggestedTitle?.lowercased().contains("buy no sugar") == true
        })
    }

    func testPossibleActionsDoNotBecomeCommittedTodayRows() {
        for source in [
            "I might call Mom tomorrow",
            "I could walk by the river later",
            "We may visit the gallery on Saturday",
            "We could add the bread to the list",
        ] {
            let item = RuleBasedThoughtExtractor.process(source).items.first
            XCTAssertEqual(item?.organization.itemType, .note, source)
            XCTAssertFalse(item?.organization.itemType.isActionable == true, source)
        }
        XCTAssertEqual(ThoughtOrganizer.organize("I will call Mom tomorrow").itemType,
                       .personFollowUp)
        XCTAssertEqual(ThoughtOrganizer.organize("I should call Mom tomorrow").itemType,
                       .personFollowUp)
        XCTAssertEqual(ThoughtOrganizer.organize("I could use eggs and milk").itemType,
                       .shopping)
        let laterCommitment = RuleBasedThoughtExtractor.process(
            "I could call Mom, but I will call her tomorrow"
        ).items
        XCTAssertEqual(laterCommitment.count, 2)
        XCTAssertFalse(laterCommitment[0].organization.itemType.isActionable)
        XCTAssertTrue(laterCommitment[1].organization.itemType.isActionable)
    }

    func testFrontedNowKeepsTimingWithoutTurningAFactIntoAnAction() {
        let action = RuleBasedThoughtExtractor.process("Now book the dentist").items
        XCTAssertEqual(action.count, 1)
        XCTAssertTrue(action[0].organization.itemType.isActionable)
        XCTAssertEqual(action[0].organization.priority, .urgent)
        XCTAssertFalse(action[0].needsReview)
        XCTAssertTrue(action[0].rawQuote.lowercased().contains("now"))

        let fact = RuleBasedThoughtExtractor.process(
            "Now is a bad time to book the dentist"
        ).items
        XCTAssertEqual(fact.count, 1)
        XCTAssertFalse(fact[0].organization.itemType.isActionable)
        XCTAssertEqual(fact[0].organization.priority, .normal)
    }

    func testNewSubjectOwnsFactAfterActionWithoutBorrowingItsVerb() {
        XCTAssertEqual(RuleBasedThoughtExtractor.splitClauses("Buy milk and Sarah hates sushi"),
                       ["Buy milk", "Sarah hates sushi"])
        XCTAssertEqual(ThoughtOrganizer.organize("Sarah hates sushi").itemType, .note)
        let items = ThoughtExtractionEngine.extractWithRules("Buy milk and Sarah hates sushi").items
        XCTAssertEqual(items.count, 2, String(describing: items.map(\.analysisText)))
        XCTAssertEqual(items.last?.sourceQuote, "Sarah hates sushi")
        XCTAssertEqual(items.last?.analysisText, "Sarah hates sushi")
        XCTAssertEqual(items.last?.organization.itemType, .note)
        XCTAssertEqual(RuleBasedThoughtExtractor.splitClauses("Remember Alex likes golf and hates mornings"),
                       ["Remember Alex likes golf and hates mornings"])
        XCTAssertEqual(RuleBasedThoughtExtractor.splitClauses("Remember Alex likes golf and Catherine hates sushi"),
                       ["Remember Alex likes golf", "Catherine hates sushi"])
    }

    func testPunctuatedFrontedContextDoesNotHideAnImperative() {
        for source in [
            "Before the talk, test that the microphone pairs with my phone",
            "Before the talk test that the microphone pairs with my phone",
            "After the meeting, check the spare cable"
        ] {
            let items = ThoughtExtractionEngine.extractWithRules(source).items
            XCTAssertEqual(items.count, 1, source)
            XCTAssertTrue(items[0].organization.itemType.isActionable, source)
            XCTAssertTrue(items[0].needsReview, source)
            XCTAssertEqual(items[0].organization.state, .unsupported(.unsupportedCondition), source)
            XCTAssertNil(items[0].organization.reminderDate, source)
            XCTAssertNil(items[0].organization.dueDate, source)
            XCTAssertEqual(items[0].rawQuote, source, source)
        }
        for source in [
            "Before the talk, the microphone pairs with my phone",
            "At the venue, the spare cable is in the bag",
            "Test that the microphone pairs with my phone"
        ] {
            let items = ThoughtExtractionEngine.extractWithRules(source).items
            XCTAssertEqual(items.count, 1, source)
            XCTAssertEqual(items[0].organization.itemType.isActionable,
                           source.hasPrefix("Test"), source)
        }
        // A dated test can itself be a Today event. It must still remain one
        // proposition, without inventing a second imperative named "test".
        let event = ThoughtExtractionEngine.extractWithRules(
            "The fire alarm test is Thursday"
        ).items
        XCTAssertEqual(event.count, 1)
        XCTAssertEqual(event[0].rawQuote, "The fire alarm test is Thursday")
        XCTAssertNil(event[0].organization.reminderDate)
        let history = ThoughtExtractionEngine.extractWithRules(
            "The microphone test was yesterday"
        ).items
        XCTAssertEqual(history.count, 1)
        XCTAssertFalse(history[0].organization.itemType.isActionable)

        for source in [
            "On the wall call button is broken.",
            "At the office print quality is poor."
        ] {
            let items = ThoughtExtractionEngine.extractWithRules(source).items
            XCTAssertEqual(items.count, 1, source)
            XCTAssertFalse(items[0].organization.itemType.isActionable, source)
            XCTAssertEqual(items[0].rawQuote, source, source)
        }
        for source in [
            "On the wall call Mom.",
            "At the office print the report."
        ] {
            let items = ThoughtExtractionEngine.extractWithRules(source).items
            XCTAssertEqual(items.count, 1, source)
            XCTAssertTrue(items[0].organization.itemType.isActionable, source)
        }
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
        XCTAssertTrue(corrected.analysisText.lowercased().contains("text mike"))
        XCTAssertEqual(corrected.organization.personName, "Mike")
        XCTAssertEqual(corrected.rawQuote, "If Sarah replies, call Mike, actually text him.")
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
        let fixtures: [(String, Int, [String])] = [
            ("Buy soap and then, actually, call Mira.", 2, ["soap", "Mira"]),
            ("Go to the library and get paper, wait, then go to the office and buy envelopes.",
             4, ["library", "paper", "office", "envelopes"]),
            ("Call Mira, wait, before that email Alex.", 2, ["Mira", "Alex"]),
        ]
        for (text, count, actions) in fixtures {
            let result = ThoughtExtractionEngine.extractWithRules(text, referenceDate: referenceDate, calendar: calendar)
            XCTAssertEqual(result.items.count, count, text)
            XCTAssertTrue(result.items.allSatisfy { $0.organization.itemType.isActionable }, text)
            for action in actions {
                XCTAssertTrue(result.items.contains { $0.analysisText.localizedCaseInsensitiveContains(action) },
                              "Missing \(action): \(text)")
            }
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

extension ActionabilityTests {
    func testNamedFirstPersonWithdrawalIsKnowledgeThroughSharedReaderAndRulesFallback() {
        let old = SentenceContext.taggerDisabledForEvaluation
        defer { SentenceContext.taggerDisabledForEvaluation = old; SentenceContextCache.invalidate() }
        for blind in [false, true] {
            SentenceContext.taggerDisabledForEvaluation = blind; SentenceContextCache.invalidate()
            for source in [
                "I no longer want to post the ticket link.",
                "We no longer want to wash the car.",
                "I no longer want to print the invoice.",
                "I no longer want to polish the brass plate."
            ] {
                XCTAssertTrue(ActionabilityReader.isUnadoptedAction(source), source)
                XCTAssertEqual(ActionabilityReader.read(source), .knowledge, source)
                let result = ThoughtExtractionEngine.extractWithRules(source,
                    referenceDate: referenceDate, calendar: calendar)
                XCTAssertFalse(result.items.contains { $0.organization.itemType.isActionable
                    && !$0.needsReview && !$0.organization.needsClarification }, source)
                XCTAssertTrue(result.operations.isEmpty, source)
                XCTAssertEqual(result.items.map(\.rawQuote), [source], source)
            }
        }
    }
    func testNamedWithdrawalKeepsIndependentCommitmentAndAddressedNegativePayload() throws {
        let old = SentenceContext.taggerDisabledForEvaluation
        defer { SentenceContext.taggerDisabledForEvaluation = old; SentenceContextCache.invalidate() }
        for blind in [false, true] {
            SentenceContext.taggerDisabledForEvaluation = blind; SentenceContextCache.invalidate()
            for source in [
                "I no longer want to post the draft, but I still need to print the invoice.",
                "I no longer want to post the draft, but polish the brass plate."
            ] {
                XCTAssertFalse(ActionabilityReader.isUnadoptedAction(source), source)
                XCTAssertTrue(ActionabilityReader.read(source).belongsOnToday, source)
                let result = ThoughtExtractionEngine.extractWithRules(source,
                    referenceDate: referenceDate, calendar: calendar)
                let active = result.items.filter { $0.organization.itemType.isActionable
                    && !$0.needsReview && !$0.organization.needsClarification }
                XCTAssertFalse(active.isEmpty, source)
                XCTAssertFalse(active.contains { $0.analysisText.lowercased().hasPrefix("post ") }, source)
                XCTAssertTrue(active.contains { $0.analysisText.lowercased().contains("print the invoice")
                    || $0.analysisText.lowercased().contains("polish the brass plate") }, source)
                XCTAssertTrue(result.operations.isEmpty, source)
            }
            for source in [
                "I want to post the ticket link.",
                "Text Sam that I no longer want to post the ticket link."
            ] {
                XCTAssertFalse(ActionabilityReader.isUnadoptedAction(source), source)
                XCTAssertTrue(ActionabilityReader.read(source).belongsOnToday, source)
            }
            for source in [
                "Lorraine said, 'I no longer want to post the ticket link.'",
                "Lorraine said I no longer want to post the ticket link.",
                "If prices change, I no longer want to post the ticket link.",
                "I never said I no longer want to post the ticket link."
            ] { XCTAssertFalse(ActionabilityReader.isUnadoptedAction(source), source) }
        }
    }
}


extension ActionabilityTests {
    func testNamedWithdrawalKeepsOwnWantAndContractedPositiveContinuations() {
        let old = SentenceContext.taggerDisabledForEvaluation
        defer { SentenceContext.taggerDisabledForEvaluation = old; SentenceContextCache.invalidate() }
        for blind in [false, true] {
            SentenceContext.taggerDisabledForEvaluation = blind; SentenceContextCache.invalidate()
            let repeated = (1...24).map { "I no longer want to print invoice number \($0)" }
                .joined(separator: ", but ") + "."
            XCTAssertTrue(ActionabilityReader.isUnadoptedAction(repeated))
            XCTAssertEqual(ActionabilityReader.read(repeated), .knowledge)
            let finalOwnAct = String(repeated.dropLast()) + ", but I still want to print the final invoice."
            XCTAssertFalse(ActionabilityReader.isUnadoptedAction(finalOwnAct))
            XCTAssertTrue(ActionabilityReader.read(finalOwnAct).belongsOnToday)
            for source in [
                "I no longer want to post the draft, but I still want to print the invoice.",
                "I no longer want to post the draft, but I'll print the invoice.",
                "I no longer want to post the draft, but Text Sam that I will print the invoice marked \"final\"."
            ] {
                XCTAssertFalse(ActionabilityReader.isUnadoptedAction(source), source)
                XCTAssertTrue(ActionabilityReader.read(source).belongsOnToday, source)
                let result = ThoughtExtractionEngine.extractWithRules(source,
                    referenceDate: referenceDate, calendar: calendar)
                let active = result.items.filter { $0.organization.itemType.isActionable
                    && !$0.needsReview && !$0.organization.needsClarification }
                XCTAssertTrue(active.contains { $0.analysisText.localizedCaseInsensitiveContains("print the invoice") }, source)
                if source.contains("but Text Sam") {
                    XCTAssertEqual(active.count, 1, source)
                    XCTAssertTrue(active.allSatisfy { $0.analysisText.hasPrefix("Text Sam") }, source)
                    XCTAssertEqual(active.first?.organization.personName, "Sam", source)
                }
                XCTAssertFalse(active.contains { $0.analysisText.lowercased().hasPrefix("post ") }, source)
                XCTAssertTrue(result.operations.isEmpty, source)
            }
            for source in [
                "I no longer want to post the draft, but I no longer want to print the invoice.",
                "I no longer want to post the draft, but I have not agreed to print the invoice.",
                "I no longer want to post the draft, but Lorraine said she will print the invoice.",
                "I no longer want to post the draft, but \"I will print the invoice\"."
            ] {
                XCTAssertTrue(ActionabilityReader.isUnadoptedAction(source), source)
                XCTAssertFalse(ActionabilityReader.read(source).belongsOnToday, source)
            }
        }
    }
}
