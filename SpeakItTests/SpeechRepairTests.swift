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
    func testCompleteCalendarCorrectionUsesFinalDayAndKeepsOriginalAncestry() throws {
        let source = "Set a reminder for Thursday at four in the afternoon, wait, Friday at four in the afternoon, to collect the frames."
        let repair = SpeechRepairPipeline.run(source, trackOrigins: true)
        XCTAssertEqual(repair.selfCorrected,
            "Set a reminder for Friday at four in the afternoon, to collect the frames.")
        XCTAssertFalse(repair.selfCorrected.localizedCaseInsensitiveContains("Thursday"))
        XCTAssertTrue(repair.selfCorrected.localizedCaseInsensitiveContains("Friday at four in the afternoon"))
        XCTAssertTrue(repair.selfCorrected.localizedCaseInsensitiveContains("collect the frames"))
        let license = try XCTUnwrap(SelfCorrectionResolver.calendarFrameRepairIDs(
            input: source, output: repair.selfCorrected))
        let raw = SourceUnitLedger(source)
        let oldDay = try XCTUnwrap(source.range(of: "Thursday"))
        let action = try XCTUnwrap(source.range(of: "collect the frames"))
        let oldClock = try XCTUnwrap(source.range(of: "Thursday at four in the afternoon"))
        let newClock = try XCTUnwrap(source.range(of: "Friday at four in the afternoon"))
        let cue = try XCTUnwrap(source.range(of: ", wait, "))
        XCTAssertEqual(license, raw.ids(in: oldClock).union(raw.ids(in: cue)).union(raw.ids(in: newClock)))
        XCTAssertTrue(raw.ids(in: oldClock).isDisjoint(with: repair.survivingRawWordIDs))
        XCTAssertTrue(raw.ids(in: newClock).isSubset(of: repair.survivingRawWordIDs))
        XCTAssertEqual(SourceUnitLedger(repair.selfCorrected).words.filter { $0.text == "afternoon" }.count, 1)
        let finalWords = SourceUnitLedger(repair.corrected).words
        let finalDay = try XCTUnwrap(finalWords.firstIndex { $0.text == "friday" })
        let finalPeriod = try XCTUnwrap(finalWords.firstIndex { $0.text == "afternoon" })
        XCTAssertEqual(repair.correctedWordRawIDs.count, finalWords.count)
        XCTAssertEqual(try XCTUnwrap(repair.correctedWordRawIDs.dropFirst(finalDay).first),
            raw.ids(in: try XCTUnwrap(source.range(of: "Friday"))))
        XCTAssertEqual(try XCTUnwrap(repair.correctedWordRawIDs.dropFirst(finalPeriod).first), raw.ids(in:
            try XCTUnwrap(source.range(of: "afternoon", options: .backwards))))
        XCTAssertTrue(raw.ids(in: oldDay).isSubset(of: license))
        XCTAssertTrue(raw.ids(in: action).isDisjoint(with: license))
        XCTAssertTrue(raw.ids(in: action).isSubset(of: repair.survivingRawWordIDs))
        let removed = Set(raw.words.indices).subtracting(repair.survivingRawWordIDs)
        XCTAssertTrue(removed.isSubset(of: license))
        XCTAssertTrue(raw.unownedMeaningfulIDs(claimed: repair.survivingRawWordIDs.union(license)).isEmpty)
        XCTAssertNil(SelfCorrectionResolver.calendarFrameRepairIDs(input: source, output: source))
        XCTAssertNil(SelfCorrectionResolver.calendarFrameRepairIDs(input: source, output: "Collect the frames Thursday at 4 PM"))

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Toronto"))
        let previous = NSTimeZone.default
        NSTimeZone.default = calendar.timeZone
        defer { NSTimeZone.default = previous }
        let reference = try XCTUnwrap(calendar.date(from:
            DateComponents(year: 2026, month: 8, day: 3, hour: 10)))
        let processed = RuleBasedThoughtExtractor.process(source, referenceDate: reference, calendar: calendar)
        let result = ThoughtExtractionEngine.extractWithRules(source, referenceDate: reference, calendar: calendar)
        for (items, operations) in [(processed.items, processed.operations), (result.items, result.operations)] {
            XCTAssertTrue(operations.isEmpty)
            XCTAssertEqual(items.count, 1)
            let row = try XCTUnwrap(items.first)
            XCTAssertFalse(row.needsReview)
            XCTAssertEqual(row.rawQuote, source)
            XCTAssertTrue(row.organization.itemType.isActionable)
            let reminder = try XCTUnwrap(row.organization.reminderDate)
            XCTAssertEqual(calendar.dateComponents([.year, .month, .day, .hour, .minute], from: reminder),
                           DateComponents(year: 2026, month: 8, day: 7, hour: 16, minute: 0))
        }
    }

    func testExplicitReminderCalendarRepairKeepsTheSamePlanWithoutLexicalAssets() throws {
        let previous = SentenceContext.taggerDisabledForEvaluation
        defer { SentenceContext.taggerDisabledForEvaluation = previous }
        for disabled in [false, true] {
            SentenceContext.taggerDisabledForEvaluation = disabled
            for wrapper in ["Set a reminder for", "Please create one reminder on", "make a reminder for"] {
                let source = wrapper + " Monday at three in the morning, wait, Tuesday at five in the evening, to wash the tray."
                let expected = wrapper + " Tuesday at five in the evening, to wash the tray."
                let repaired = SelfCorrectionResolver.resolved(source)
                XCTAssertEqual(repaired, expected)
                XCTAssertNotNil(SelfCorrectionResolver.calendarFrameRepairIDs(input: source, output: repaired))
            }
        }
    }

    func testCalendarCorrectionProofDeclinesReportedConditionalAndIndependentFrames() {
        for source in [
            "Maya said, set a reminder for Thursday at four, wait, Friday at four, to collect the frames.",
            "If Maya approves, set a reminder for Thursday at four, wait, Friday at four, to collect the frames.",
            "Save 'Thursday at four, wait, Friday at four' as a note.",
            "Remind me Thursday at four to collect the frames, wait, Friday at four to call Noor.",
            "Remind me Thursday at four, wait, Friday at four, to collect the frames and mail the parcel.",
            "Set a reminder for Thursday at four in the afternoon, wait, Friday at four in the afternoon, to collect the frames, and mail the parcel.",
            "Set a reminder for Thursday at four in the afternoon, wait, Friday at four in the afternoon, to collect the frames if Maya approves.",
            "Set a reminder for Thursday at four in the afternoon, wait, Friday at four in the afternoon, to collect the frames. Remind me to call Noor.",
            "Do not set a reminder for Thursday at four in the afternoon, wait, Friday at four in the afternoon, to collect the frames.",
            "Maya will set a reminder for Thursday at four in the afternoon, wait, Friday at four in the afternoon, to collect the frames.",
            "Save 'Set a reminder for Thursday at four in the afternoon, wait, Friday at four in the afternoon, to collect the frames' as a note."
        ] {
            XCTAssertNil(SelfCorrectionResolver.calendarFrameRepairIDs(
                input: source, output: SelfCorrectionResolver.resolved(source)), source)
        }
    }

    func testAdjacentExclusiveReconsiderationReplacesOnlyOneActionWithExactOrigins() throws {
        let source = "Buy bread. Add replacing the kettle to my list. On second thought, just descale it first. Call Noor."
        let output = SelfCorrectionResolver.resolved(source)
        XCTAssertEqual(output, "Buy bread. descale the kettle first. Call Noor.")
        let repair = SpeechRepairPipeline.run(source, trackOrigins: true)
        XCTAssertEqual(repair.selfCorrected, output)
        let ledger = SourceUnitLedger(source)
        let outputWords = SourceUnitLedger(repair.corrected).words
        XCTAssertEqual(repair.correctedWordRawIDs.count, outputWords.count)
        for (word, origins) in zip(outputWords, repair.correctedWordRawIDs) {
            XCTAssertEqual(origins.count, 1)
            let origin = try XCTUnwrap(origins.first)
            XCTAssertEqual(word.text, ledger.words[origin].text)
        }
        let licensed = try XCTUnwrap(SelfCorrectionResolver.reconsiderationRepairIDs(input: source, output: output))
        let removed = Set(ledger.words.indices).subtracting(repair.survivingRawWordIDs)
        XCTAssertEqual(removed, licensed)
        XCTAssertTrue(licensed.isDisjoint(with: repair.survivingRawWordIDs))
        let keptObject = try XCTUnwrap(source.range(of: "the kettle"))
        let newVerb = try XCTUnwrap(source.range(of: "descale"))
        for kept in [keptObject, newVerb, try XCTUnwrap(source.range(of: "Buy bread")),
                     try XCTUnwrap(source.range(of: "Call Noor"))] {
            XCTAssertTrue(ledger.ids(in: kept).isSubset(of: repair.survivingRawWordIDs))
            XCTAssertTrue(ledger.ids(in: kept).isDisjoint(with: licensed))
        }
        XCTAssertTrue(ledger.unownedMeaningfulIDs(claimed: licensed.union(repair.survivingRawWordIDs)).isEmpty)
        XCTAssertNil(SelfCorrectionResolver.reconsiderationRepairIDs(input: source, output: "descale it"))
        let rows = ThoughtExtractionEngine.extractWithRules(source).items
        XCTAssertEqual(rows.count, 3, rows.map(\.analysisText).joined(separator: " | "))
        XCTAssertTrue(rows.allSatisfy { !$0.needsReview && $0.organization.itemType.isActionable })
        XCTAssertFalse(rows.contains { $0.analysisText.localizedCaseInsensitiveContains("replace") })
        XCTAssertTrue(rows.contains { $0.analysisText.localizedCaseInsensitiveContains("descale the kettle first") })
    }

    func testReconsiderationProofDeclinesCompetingOwnershipObjectsAndUnknownTails() {
        for source in [
            "Maya will replace the kettle. On second thought, just descale it first.",
            "If the seal is broken, replace the kettle. On second thought, just descale it first.",
            "Do not replace the kettle. On second thought, just descale it first.",
            "Replace the kettle and the toaster. On second thought, just descale it first.",
            "Replace the kettle tomorrow. On second thought, just descale it first.",
            "Replace the kettle tonight. On second thought, just descale it first.",
            "Replace the kettle on October 20. On second thought, just descale it first.",
            "Maya said 'Replace the kettle. On second thought, just descale it first.'",
            "Replace the kettle. On second thought, just descale it first and mail the parcel.",
            "Replace the kettle. On second thought, descale it first.",
            "Replace the kettle is broken. On second thought, just descale it first."
        ] {
            XCTAssertNil(SelfCorrectionResolver.reconsiderationRepairIDs(input: source,
                output: SelfCorrectionResolver.resolved(source)), source)
        }
    }

    func testCurrentThoughtWithdrawalKeepsCompletionAndIndependentActionsWithDisjointIDs() throws {
        let source = "Buy bread. Remind me to buy the tickets on Wednesday. Cancel that thought, I already bought them. Call Noor."
        let partition = CaptureOperationDetector.partitionWithOwnership(source)
        XCTAssertEqual(partition.operations.count, 1)
        let operation = try XCTUnwrap(partition.operations.first)
        XCTAssertEqual(operation.operation, .retract)
        XCTAssertTrue(operation.isScoped)
        XCTAssertFalse(operation.needsReview)
        XCTAssertNil(operation.target)
        XCTAssertEqual(operation.sourceQuote, "Cancel that thought")
        XCTAssertTrue(partition.remainder?.contains("Buy bread") == true)
        XCTAssertTrue(partition.remainder?.contains("I already bought them") == true)
        XCTAssertTrue(partition.remainder?.contains("Call Noor") == true)
        XCTAssertFalse(partition.remainder?.contains("buy the tickets") == true)
        let ledger = SourceUnitLedger(source)
        XCTAssertEqual(operation.sourceUnitIDs, ledger.ids(in: try XCTUnwrap(source.range(of: "Cancel that thought"))))
        XCTAssertEqual(operation.localTargetUnitIDs, ledger.ids(in:
            try XCTUnwrap(source.range(of: "Remind me to buy the tickets on Wednesday"))))
        XCTAssertTrue(operation.sourceUnitIDs.isDisjoint(with: partition.retainedUnitIDs))
        XCTAssertTrue(operation.localTargetUnitIDs.isDisjoint(with: partition.retainedUnitIDs))
        XCTAssertTrue(partition.unownedMeaningfulIDs(in: source).isEmpty)
    }

    func testCurrentThoughtCompletionCannotBorrowOtherOwnerObjectOrConditionalAuthority() {
        for source in [
            "Remind me to buy the tickets. Cancel that thought, I already paid the invoice.",
            "Remind me to buy the tickets and buy the envelopes. Cancel that thought, I already bought them.",
            "If Maya approves, buy the tickets. Cancel that thought, I already bought them.",
            "Maya said buy the tickets. Cancel that thought, I already bought them.",
            "Buy the tickets. Maya said 'Cancel that thought, I already bought them.'"
        ] {
            let partition = CaptureOperationDetector.partitionWithOwnership(source)
            XCTAssertFalse(partition.operations.contains { $0.isScoped && !$0.needsReview
                && !$0.localTargetUnitIDs.isEmpty }, source)
        }
        let bare = CaptureOperationDetector.detect("Cancel that thought")
        XCTAssertEqual(bare?.operation, .retract)
        XCTAssertEqual(bare?.needsReview, true)
        XCTAssertEqual(bare?.isScoped, true)
        XCTAssertTrue(SelfCorrectionResolver.localCompletionMatches(action: "Buy the tickets",
            pastVerb: "bought", reportTarget: "them", permitsScopedObjectReference: true))
        XCTAssertFalse(SelfCorrectionResolver.localCompletionMatches(action: "Buy the tickets",
            pastVerb: "bought", reportTarget: "them"))
        XCTAssertFalse(SelfCorrectionResolver.localCompletionMatches(action: "Call Noor",
            pastVerb: "called", reportTarget: "them", permitsScopedObjectReference: true))
    }

    func testCaptureContrastAndNonadoptionCannotBecomeMalformedSavedTargets() {
        let source = "I must bring my ID to the interview, but I don't need to bring printed copies of the application."
        let partition = CaptureOperationDetector.partitionWithOwnership(source)
        XCTAssertTrue(partition.operations.isEmpty)
        XCTAssertEqual(partition.remainder, source)
        XCTAssertTrue(partition.unownedMeaningfulIDs(in: source).isEmpty)
        XCTAssertNil(CaptureOperationDetector.detect("I don't need to bring printed copies of the application", within: source))
        XCTAssertNil(CaptureOperationDetector.detect("I am not going ahead with it"))
        XCTAssertNil(CaptureOperationDetector.detect("We are not going through with the idea"))
        XCTAssertEqual(CaptureOperationDetector.detect("I am not going ahead with the meeting on Friday")?.target,
                       "the meeting on friday")
        for source in ["I don't need to call Mom anymore", "I already called Mom", "Cancel the dentist reminder"] {
            XCTAssertNotNil(CaptureOperationDetector.detect(source), source)
        }
        let saved = "Bring my ID, but I don't need to keep the saved copies reminder anymore."
        XCTAssertEqual(CaptureOperationDetector.partitionWithOwnership(saved).operations.first?.operation, .cancel)
    }

    func testRecipientRepairLicenceDeclinesSentenceInitialJointCallCorrectionWithoutRangeTrap() {
        let source = "I thought of separate calls to Mom and my stepdad about the holiday seating. Actually make it one call with both of them together on November 22. That joint call is the final choice, no timed alert. A seating map with movable magnets is just another possible idea."
        let output = SelfCorrectionResolver.resolved(source)
        XCTAssertNil(SelfCorrectionResolver.repeatedRecipientRepairIDs(
            input: source, output: output),
            "A joint-call plan correction is not a same-sentence recipient repair licence.")
    }

    func testRecipientRepairLicenceDeclinesSentenceBoundaryStackedCuesAndWhitespace() {
        // The cue pattern owns leading whitespace and may stack markers.
        // Its start can lie in the preceding tokenizer sentence while its
        // end lies in the next one. This narrow licence must decline before
        // constructing a suffix range; generic correction semantics remain
        // the resolver's responsibility.
        for separator in [" ", "  ", "\n", "\n\n", "\t", "\r\n"] {
            for marker in ["Actually", "Actually make it", "Sorry, actually", "Wait, actually make it"] {
                let source = "Call Alex." + separator + marker + " call Alice, not Alex."
                let output = SelfCorrectionResolver.resolved(source)
                XCTAssertNil(SelfCorrectionResolver.repeatedRecipientRepairIDs(
                    input: source, output: output), source)
            }
        }
    }

    func testRepeatedRecipientCorrectionKeepsTheOriginalReminderFrame() throws {
        let source = "Remind me Tuesday at nine in the morning to call Alex, sorry, call Alice, not Alex."
        XCTAssertEqual(SelfCorrectionResolver.resolved(source),
                       "Remind me Tuesday at nine in the morning to call Alice")
        let repaired = SpeechRepairPipeline.run(source, trackOrigins: true)
        let removed = repaired.rawWords.indices.filter { !repaired.survivingRawWordIDs.contains($0) }
            .map { repaired.rawWords[$0].text.lowercased() }
        XCTAssertEqual(removed.filter { $0 == "alex" }.count, 2)
        XCTAssertFalse(removed.contains("alice"))
        XCTAssertNotNil(SelfCorrectionResolver.repeatedRecipientRepairIDs(
            input: source, output: repaired.selfCorrected))

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Toronto"))
        let previous = NSTimeZone.default
        NSTimeZone.default = calendar.timeZone
        defer { NSTimeZone.default = previous }
        let reference = try XCTUnwrap(calendar.date(from:
            DateComponents(year: 2026, month: 8, day: 3, hour: 10)))
        let rows = ThoughtExtractionEngine.extractWithRules(
            source, referenceDate: reference, calendar: calendar).items
        XCTAssertEqual(rows.count, 1)
        let row = try XCTUnwrap(rows.first)
        XCTAssertFalse(row.needsReview)
        XCTAssertEqual(row.organization.personName, "Alice")
        XCTAssertEqual(row.rawQuote, source)
        XCTAssertTrue(row.wasRepaired)
        let reminder = try XCTUnwrap(row.organization.reminderDate)
        XCTAssertEqual(calendar.component(.weekday, from: reminder), 3)
        XCTAssertEqual(calendar.component(.hour, from: reminder), 9)
    }

    func testRecipientRepairDeclinesCompetingObjectsActorsAndIndependentActions() throws {
        for source in [
            "Call Alex and Ben, sorry, call Alice, not Alex.",
            "Call Alex, sorry, email Alice, not Alex.",
            "Maya said call Alex, sorry, call Alice, not Alex.",
            "Maya said 'call Alex, sorry, call Alice, not Alex.'",
            "Call Alex, sorry, call Alice and Ben, not Alex.",
            "Call Alex, sorry, call Alice, not Ben.",
        ] {
            XCTAssertEqual(SelfCorrectionResolver.resolved(source), source, source)
            XCTAssertNil(SelfCorrectionResolver.repeatedRecipientRepairIDs(input: source, output: source))
        }
        let independent = "Buy bread. Remind me Tuesday at nine in the morning to call Alex, sorry, call Alice, not Alex."
        let rows = ThoughtExtractionEngine.extractWithRules(independent).items
        XCTAssertEqual(rows.count, 2)
        XCTAssertTrue(rows.allSatisfy { !$0.needsReview })
        XCTAssertTrue(rows.contains { $0.sourceQuote.localizedCaseInsensitiveContains("bread") })
        XCTAssertTrue(rows.contains { $0.rawQuote.contains("Alice") })
        XCTAssertFalse(rows.contains { !$0.needsReview && $0.organization.personName == "Alex" })
        XCTAssertNotNil(try XCTUnwrap(rows.first { $0.organization.personName == "Alice" }).organization.reminderDate)
        // Ordinary rows own words in the repaired creation source. Audit that
        // ledger first, then translate through the actual repair ancestry;
        // original offsets cannot be compared with repaired row IDs directly.
        let repair = SpeechRepairPipeline.run(independent, trackOrigins: true)
        let correctedLedger = SourceUnitLedger(repair.corrected)
        let partition = CaptureOperationDetector.partitionWithOwnership(repair.corrected)
        XCTAssertTrue(partition.operations.isEmpty)
        XCTAssertEqual(partition.remainder, repair.corrected)
        XCTAssertEqual(repair.correctedWordRawIDs.count, correctedLedger.words.count)
        let claims = rows.reduce(into: Set<Int>()) { $0.formUnion($1.sourceUnitIDs) }
        XCTAssertTrue(claims.isSubset(of: Set(correctedLedger.words.indices)))
        XCTAssertTrue(correctedLedger.unownedMeaningfulIDs(claimed: claims).isEmpty)

        let rawLedger = SourceUnitLedger(independent)
        let rawIDs = Set(rawLedger.words.indices)
        XCTAssertEqual(repair.rawWords.map(\.text), rawLedger.words.map(\.text))
        func rawOrigins(of row: ExtractedThought) throws -> Set<Int> {
            var result: Set<Int> = []
            for id in row.sourceUnitIDs {
                let origins = try XCTUnwrap(repair.correctedWordRawIDs.indices.contains(id)
                    ? repair.correctedWordRawIDs[id] : nil)
                XCTAssertFalse(origins.isEmpty)
                XCTAssertTrue(origins.isSubset(of: rawIDs))
                result.formUnion(origins)
            }
            return result
        }
        let bread = try XCTUnwrap(rows.first {
            $0.sourceQuote.localizedCaseInsensitiveContains("bread")
        })
        let alice = try XCTUnwrap(rows.first { $0.organization.personName == "Alice" })
        let breadOrigins = try rawOrigins(of: bread)
        let aliceOrigins = try rawOrigins(of: alice)
        let breadRange = try XCTUnwrap(independent.range(of: "Buy bread"))
        let aliceRange = try XCTUnwrap(independent.range(of: "Alice"))
        XCTAssertEqual(breadOrigins, rawLedger.ids(in: breadRange))
        XCTAssertTrue(rawLedger.ids(in: aliceRange).isSubset(of: aliceOrigins))
        XCTAssertTrue(breadOrigins.isDisjoint(with: aliceOrigins))
        let surviving = breadOrigins.union(aliceOrigins)
        XCTAssertEqual(surviving, repair.survivingRawWordIDs)

        // Only the exact typed recipient correction can account for removed
        // raw occurrences; neither the other action nor Alice may disappear.
        let licensed = try XCTUnwrap(SelfCorrectionResolver.repeatedRecipientRepairIDs(
            input: independent, output: repair.selfCorrected))
        let removed = rawIDs.subtracting(repair.survivingRawWordIDs)
        XCTAssertFalse(removed.isEmpty)
        XCTAssertEqual(removed, licensed)
        XCTAssertTrue(licensed.isDisjoint(with: surviving))
        XCTAssertEqual(surviving.union(licensed), rawIDs)
        XCTAssertTrue(rawLedger.unownedMeaningfulIDs(claimed:
            surviving.union(licensed)).isEmpty)
    }

    func testClockFirstCalendarAdjunctOwnsOneReminderAndNoPhantomRow() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Toronto"))
        let previous = NSTimeZone.default
        NSTimeZone.default = calendar.timeZone
        defer { NSTimeZone.default = previous }
        let reference = try XCTUnwrap(calendar.date(from:
            DateComponents(year: 2026, month: 8, day: 3, hour: 10)))
        for (source, month, day, hour, minute) in [
            ("At 3:20 p.m. on August 8, remind me to check in online for my flight.", 8, 8, 15, 20),
            ("At 11:45 a.m. on October 9, remind me to submit the form.", 10, 9, 11, 45),
        ] {
            XCTAssertEqual(RuleBasedThoughtExtractor.splitClauses(source).count, 1, source)
            let rows = ThoughtExtractionEngine.extractWithRules(
                source, referenceDate: reference, calendar: calendar).items
            XCTAssertEqual(rows.count, 1, source)
            let row = try XCTUnwrap(rows.first)
            XCTAssertFalse(row.needsReview, source)
            XCTAssertEqual(row.rawQuote, source)
            let date = try XCTUnwrap(row.organization.reminderDate, source)
            XCTAssertEqual(calendar.component(.month, from: date), month)
            XCTAssertEqual(calendar.component(.day, from: date), day)
            XCTAssertEqual(calendar.component(.hour, from: date), hour)
            XCTAssertEqual(calendar.component(.minute, from: date), minute)
        }
    }

    func testClockFirstContextDoesNotAuthorizeReportedReminderOrOverrideAnotherSentence() {
        let reported = "At 3:20 p.m. on August 8, Maya said remind me to submit the form."
        XCTAssertFalse(ThoughtExtractionEngine.extractWithRules(reported).items.contains {
            !$0.needsReview && $0.organization.itemType.isActionable
        })
        let separate = "At 3:20 p.m. on August 8, remind me to submit the form. Remind me Monday at noon to call Ben."
        let rows = ThoughtExtractionEngine.extractWithRules(separate).items
        XCTAssertEqual(rows.count, 2)
        XCTAssertTrue(rows.contains { $0.sourceQuote.contains("Monday at noon") })
        XCTAssertTrue(rows.contains { $0.sourceQuote.contains("3:20") })
    }

    func testFrontedCalendarDaySurvivesASiblingsOwnClock() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Toronto"))
        let previous = NSTimeZone.default
        NSTimeZone.default = calendar.timeZone
        defer { NSTimeZone.default = previous }
        let reference = try XCTUnwrap(calendar.date(from:
            DateComponents(year: 2026, month: 8, day: 3, hour: 10)))
        for second in ["remind me at 5 p.m. to call Ben", "call Ben at 5 p.m."] {
            let source = "At 3:20 p.m. on August 8, remind me to submit the form and " + second + "."
            let rows = ThoughtExtractionEngine.extractWithRules(
                source, referenceDate: reference, calendar: calendar).items
            XCTAssertEqual(rows.count, 2, source)
            let ben = try XCTUnwrap(rows.first { $0.sourceQuote.contains("Ben") }, source)
            XCTAssertFalse(ben.needsReview, source)
            let date = try XCTUnwrap(ben.organization.reminderDate, source)
            XCTAssertEqual(calendar.component(.month, from: date), 8)
            XCTAssertEqual(calendar.component(.day, from: date), 8)
            XCTAssertEqual(calendar.component(.hour, from: date), 17)
            XCTAssertTrue(SourceUnitLedger(source).unownedMeaningfulIDs(claimed:
                rows.reduce(into: Set<Int>()) { $0.formUnion($1.sourceUnitIDs) }).isEmpty, source)
        }
        let override = "At 3:20 p.m. on August 8, remind me to submit the form and remind me on August 10 at 5 p.m. to call Ben."
        let own = ThoughtExtractionEngine.extractWithRules(
            override, referenceDate: reference, calendar: calendar).items
        let ben = try XCTUnwrap(own.first { $0.sourceQuote.contains("Ben") })
        XCTAssertEqual(calendar.component(.day, from: try XCTUnwrap(ben.organization.reminderDate)), 10)
    }
    func testNamedClockCorrectionAfterLowercaseStopsRetainsItsOwnerReference() {
        let source = "remind me at six tonight to send maya the kitchen photos. i also need eggs. i have not chosen a shopping time. actually, seven tonight for the photos, because i will not be home at six."
        XCTAssertEqual(SelfCorrectionResolver.resolved(source), source)
    }

    func testRecordingPrefaceDoesNotConditionAnExplicitReminder() {
        XCTAssertTrue(ConditionalIntentScope.isDiscourseIdiom("Before I lose the thread"))
        for source in ["Before Nora confirms", "Before I lose the receipt"] {
            XCTAssertFalse(ConditionalIntentScope.isDiscourseIdiom(source))
        }
        let source = "Before I lose the thread, remind me at six tonight to send Maya the photos"
        XCTAssertEqual(DisfluencyFilter.stripped(source), source)
    }

    func testReferentIdentificationDoesNotBecomeAnObjectCorrection() {
        for source in [
            "The damaged panel is the one I mean.",
            "The one I mean is beside the entrance.",
            "What I mean by a quiet room is somewhere away from the corridor."
        ] {
            XCTAssertEqual(SelfCorrectionResolver.resolved(source), source)
        }
        let repaired = SelfCorrectionResolver.resolved("Buy rye bread, I mean oat bread.")
        XCTAssertTrue(repaired.localizedCaseInsensitiveContains("oat bread"))
        XCTAssertFalse(repaired.localizedCaseInsensitiveContains("rye bread"))
    }

    func testExplicitLocalReplacementWithdrawsOnlyItsUniquePriorAction() {
        let source = "I need to buy the train ticket for the workshop. Also send the organiser my dietary preference. Replace buying the train ticket with texting Dev to confirm the lift."
        let result = CaptureOperationDetector.partitionWithOwnership(source)
        XCTAssertEqual(result.operations.count, 1)
        XCTAssertEqual(result.operations.first?.operation, .retract)
        XCTAssertEqual(result.operations.first?.isScoped, true)
        XCTAssertFalse(result.remainder?.localizedCaseInsensitiveContains("buy the train ticket") == true)
        XCTAssertTrue(result.remainder?.localizedCaseInsensitiveContains("send the organiser") == true)
        XCTAssertTrue(result.remainder?.localizedCaseInsensitiveContains("text Dev") == true)
        XCTAssertTrue(result.unownedMeaningfulIDs(in: source).isEmpty)

        let opposite = CaptureOperationDetector.partitionWithOwnership(
            "Buy a train ticket and separately text Dev to ask about a lift home."
        )
        XCTAssertTrue(opposite.operations.isEmpty)
        XCTAssertTrue(opposite.remainder?.localizedCaseInsensitiveContains("train ticket") == true)
        XCTAssertEqual(RuleBasedThoughtExtractor.splitClauses(
            "Buy a train ticket and separately text Dev to ask about a lift home."
        ), ["Buy a train ticket", "separately text Dev to ask about a lift home"])
        let oppositeExtraction = ThoughtExtractionEngine.extractWithRules(
            "Buy a train ticket and separately text Dev to ask about a lift home."
        )
        XCTAssertEqual(oppositeExtraction.items.count, 2,
                       oppositeExtraction.items.map(\.analysisText).joined(separator: " | "))
        XCTAssertTrue(oppositeExtraction.items.contains {
            $0.organization.itemType == .shopping
                && $0.analysisText.localizedCaseInsensitiveContains("train ticket")
        })
        XCTAssertTrue(oppositeExtraction.items.contains {
            $0.organization.itemType.isActionable
                && $0.analysisText.localizedCaseInsensitiveContains("text Dev")
        }, oppositeExtraction.items.map { "\($0.organization.itemType.rawValue):\($0.analysisText)" }.joined(separator: " | "))

        let full = "I need to buy the train ticket for the workshop. I was going to travel on Thursday morning, and I am saying this before I have checked the lift offer properly. Also send the workshop organiser my dietary preference: vegetarian, not vegan.\n\nNo, I have checked the message now and will get a lift instead. Replace buying the train ticket with texting Dev to confirm that lift. Keep the dietary preference message as a separate task. There was never a train booking to cancel, so do not report that a ticket has been cancelled."
        XCTAssertEqual(ClauseJuxtaposition.pieces(
            in: "Keep the dietary preference message as a separate task."
        ), ["Keep the dietary preference message as a separate task."])
        XCTAssertEqual(ClauseJuxtaposition.pieces(
            in: "Keep the dietary preference, message Dev as a separate task."
        ), ["Keep the dietary preference,", "message Dev as a separate task."])
        let extraction = ThoughtExtractionEngine.extractWithRules(full)
        XCTAssertEqual(extraction.items.count, 2,
                       extraction.items.map(\.analysisText).joined(separator: " | "))
        XCTAssertTrue(extraction.items.contains {
            $0.organization.itemType.isActionable
                && $0.analysisText.localizedCaseInsensitiveContains("dietary preference")
        })
        XCTAssertTrue(extraction.items.contains {
            $0.organization.itemType.isActionable
                && $0.analysisText.localizedCaseInsensitiveContains("text Dev")
                && $0.organization.dueDate == nil
        })
        XCTAssertTrue(extraction.operations.allSatisfy(\.isScoped),
                      extraction.operations.map { "\($0.operation.rawValue):\($0.sourceQuote)" }.joined(separator: " | "))
        XCTAssertFalse(extraction.items.contains {
            $0.organization.itemType == .shopping
                && $0.analysisText.localizedCaseInsensitiveContains("train ticket")
        })
        XCTAssertTrue(extraction.items.contains {
            $0.analysisText.localizedCaseInsensitiveContains("text Dev")
        })
        for variant in [full.lowercased(), full.lowercased().replacingOccurrences(of: ".", with: "")] {
            let rendered = ThoughtExtractionEngine.extractWithRules(variant)
            XCTAssertFalse(RuleBasedThoughtExtractor.splitClauses(variant).contains {
                $0.localizedCaseInsensitiveContains("dietary preference")
                    && $0.localizedCaseInsensitiveContains("checked the message now")
            }, RuleBasedThoughtExtractor.splitClauses(variant).joined(separator: " | "))
            let repaired = SpeechRepairPipeline.run(variant).corrected
            XCTAssertFalse(RuleBasedThoughtExtractor.splitClauses(repaired).contains {
                $0.localizedCaseInsensitiveContains("dietary preference")
                    && $0.localizedCaseInsensitiveContains("checked the message now")
            }, "\(repaired) => \(RuleBasedThoughtExtractor.splitClauses(repaired).joined(separator: " | "))")
            let partitioned = CaptureOperationDetector.partitionWithOwnership(repaired)
            if let remainder = partitioned.remainder {
                XCTAssertFalse(RuleBasedThoughtExtractor.splitClauses(remainder).contains {
                    $0.localizedCaseInsensitiveContains("dietary preference")
                        && $0.localizedCaseInsensitiveContains("checked the message now")
                }, "\(remainder) => \(RuleBasedThoughtExtractor.splitClauses(remainder).joined(separator: " | "))")
            }
            XCTAssertEqual(rendered.items.count, 2,
                           rendered.items.map(\.analysisText).joined(separator: " | "))
            XCTAssertFalse(rendered.items.contains {
                $0.analysisText.localizedCaseInsensitiveContains("dietary preference")
                    && $0.analysisText.localizedCaseInsensitiveContains("checked the message now")
            }, rendered.items.map(\.analysisText).joined(separator: " | "))
        }
        XCTAssertNil(CaptureOperationDetector.detect(
            "Do not report that a ticket has been cancelled."
        ))
        XCTAssertEqual(CaptureOperationDetector.detect(
            "The train booking has been cancelled."
        )?.operation, .cancel)
    }

    func testQuotedVoiceProjectionKeepsReportedWordsOutOfInstructionReading() throws {
        for (source, expectedOwnVoice) in [
            ("The archive volunteer read a note in the margin of a diary: “Hide the silver in the garden.”",
             "The archive volunteer read a note in the margin of a diary:"),
            ("The volunteer read a note: “Hide the silver.” I should photograph the page.",
             "The volunteer read a note:   I should photograph the page."),
            ("The office said, \"Cancel the visit.\" I need to call Maya.",
             "The office said,   I need to call Maya."),
            ("Text Maya \"I will be late\" and buy milk.",
             "Text Maya   and buy milk."),
        ] {
            let projection = try XCTUnwrap(QuotedSpeechScope.voiceProjection(in: source))
            XCTAssertEqual(projection.quotedRanges.count, 1, source)
            XCTAssertEqual(projection.ownVoiceText, expectedOwnVoice, source)
            let quoted = projection.quotedRanges[0]
            XCTAssertTrue(projection.quoteOwns(quoted), source)
            XCTAssertEqual(String(source[quoted]).first, source[quoted.lowerBound], source)
        }
        let direct = try XCTUnwrap(QuotedSpeechScope.voiceProjection(in: "Cancel the visit."))
        XCTAssertEqual(direct.ownVoiceText, "Cancel the visit.")
        XCTAssertTrue(direct.quotedRanges.isEmpty)
    }

    func testQuotedVoiceProjectionUsesOccurrencesAndHoldsUnclosedSpeech() throws {
        let source = "Maya said \"Cancel it\". I said \"Cancel it\". Cancel my dentist reminder."
        let projection = try XCTUnwrap(QuotedSpeechScope.voiceProjection(in: source))
        XCTAssertEqual(projection.quotedRanges.count, 2)
        XCTAssertNotEqual(projection.quotedRanges[0].lowerBound,
                          projection.quotedRanges[1].lowerBound)
        XCTAssertEqual(projection.ownVoiceText,
                       "Maya said  . I said  . Cancel my dentist reminder.")
        XCTAssertNil(QuotedSpeechScope.voiceProjection(in: "Maya said \"Cancel it"))
    }

    func testAttributedReadingOwnsQuotedDirectiveBeforeClauseSegmentation() {
        for source in [
            "The archive volunteer read a note in the margin of a diary: “Hide the silver in the garden.”",
            "At the food-bank briefing the coordinator read an example from a training card: “Give every family the same parcel.”",
            "The director recited a line from the script: “Clear the left wing.”",
            "My colleague quoted the old manual: “Cancel the booking.”",
        ] {
            let reading = ClauseScope.read(source)
            XCTAssertEqual(reading.act, .reporting, source)
            XCTAssertNotNil(reading.complementRange, source)
        }
    }

    func testDirectReadingTaskAndFirstPersonHistoryAreNotThirdPartyReports() {
        for source in [
            "Read the note “Hide the silver in the garden.”",
            "I read the note “Hide the silver in the garden.”",
            "At the library, read the note “Hide the silver in the garden.”",
            "Please quote the manual “Cancel the booking.”",
            "I need to recite the line “Clear the left wing.”",
        ] {
            XCTAssertEqual(ClauseScope.read(source).act, .direct, source)
        }
    }

    func testQuotedSourceOwnerSurvivesClauseSplitAndRouting() {
        for source in [
            "The volunteer recited a line from the script: “Hide the keys in the garden.”",
            "I read a diary line: “Hide the silver in the garden.”",
            "I was at the library when someone read aloud a recipe card: “Add two teaspoons of salt.”",
            "The archive volunteer read a note in the margin of a diary: “Hide the silver in the garden.”",
        ] {
            XCTAssertEqual(QuotedSpeechScope.matrixVoice(in: source), .reported, source)
            XCTAssertEqual(RuleBasedThoughtExtractor.splitClauses(source), [source], source)
            let items = ThoughtExtractionEngine.extractWithRules(source).items
            XCTAssertFalse(items.isEmpty, source)
            XCTAssertTrue(items.allSatisfy { !$0.organization.itemType.isActionable }, source)
            XCTAssertTrue(items.contains { $0.sourceQuote.contains("“") }, source)
        }
    }

    func testQuoteOwnerAllowsDirectMessageAndPostQuoteCommitment() {
        let message = ThoughtExtractionEngine.extractWithRules(
            "Text Maya “I will arrive after seven.”"
        ).items
        XCTAssertEqual(message.count, 1)
        XCTAssertTrue(message[0].organization.itemType.isActionable)

        let direct = ThoughtExtractionEngine.extractWithRules(
            "Read the note “The window is open.”"
        ).items
        XCTAssertEqual(direct.count, 1)
        XCTAssertTrue(direct[0].organization.itemType.isActionable)

        let postQuote = ThoughtExtractionEngine.extractWithRules(
            "The presenter recited “Leave the room now,” and I need to call Maya."
        ).items
        XCTAssertEqual(postQuote.count, 2)
        XCTAssertFalse(postQuote[0].organization.itemType.isActionable)
        XCTAssertTrue(postQuote[1].organization.itemType.isActionable)

        let adopted = ThoughtExtractionEngine.extractWithRules(
            "Maya said “Call the clinic”; I agree: call the clinic."
        ).items
        XCTAssertTrue(adopted.contains { $0.organization.itemType.isActionable })
    }

    func testReportedSubjectPronounsDoNotBecomeIndirectObjects() {
        let own = ClauseScope.read("Priya said I should call the landlord")
        XCTAssertEqual(own.act, .reporting)
        XCTAssertEqual(own.actor, .user)
        XCTAssertTrue(ThoughtExtractionEngine.extractWithRules(
            "Priya said I should call the landlord"
        ).items[0].organization.itemType.isActionable)

        let other = ClauseScope.read("Priya said she should call the landlord")
        XCTAssertEqual(other.act, .reporting)
        XCTAssertNotEqual(other.actor, .user)
        XCTAssertFalse(ThoughtExtractionEngine.extractWithRules(
            "Priya said she should call the landlord"
        ).items[0].organization.itemType.isActionable)
    }

    func testRepairTraceKeepsProductionOrderAndShortCaptureMeaning() {
        for (source, expected) in [
            ("Buy milk", "Buy milk"),
            ("Um, buy milk", "buy milk"),
            ("Call Mom at five, actually six", "Call Mom at six"),
            ("Call Maya and buy eggs, actually Wednesday", "Call Maya and buy eggs Wednesday"),
        ] {
            let result = SpeechRepairPipeline.run(source)
            XCTAssertEqual(result.stages.count, 9)
            XCTAssertEqual(result.stages.first?.input, source)
            XCTAssertEqual(result.stages.last?.output, result.corrected)
            for index in 1..<result.stages.count {
                XCTAssertEqual(result.stages[index].input, result.stages[index - 1].output)
            }
            XCTAssertEqual(result.corrected, expected, source)
        }
    }

    func testThinkingFrameKeepsFiniteProposalButBareCommandNeedsNoRecognizerComma() {
        let proposal = "I was thinking it might make sense to add a dark mode"
        XCTAssertEqual(DisfluencyFilter.stripped(proposal), proposal)
        XCTAssertEqual(ThoughtExtractionEngine.extractWithRules(proposal).items.first?.organization.itemType,
                       .idea)

        let direct = "I was thinking, buy milk"
        XCTAssertEqual(DisfluencyFilter.stripped(direct), "buy milk")
        XCTAssertEqual(ThoughtExtractionEngine.extractWithRules(direct).items.first?.organization.itemType,
                       .shopping)

        let unpunctuated = "I was thinking buy milk"
        XCTAssertEqual(DisfluencyFilter.stripped(unpunctuated), "buy milk")
    }

    func testBareThinkingCommandKeepsRawWordsAndExactDiscourseLicenseAcrossRenderings() throws {
        let previous = SentenceContext.taggerDisabledForEvaluation
        defer { SentenceContext.taggerDisabledForEvaluation = previous }
        for disabled in [false, true] {
            SentenceContext.taggerDisabledForEvaluation = disabled
            for source in ["Like, I was thinking, buy milk", "Like I was thinking buy milk", "I was thinking buy milk", "Right, so, I was thinking buy milk"] {
                let frame = try XCTUnwrap(DisfluencyFilter.imperativeThinkingFrameRange(in: source))
                let repair = SpeechRepairPipeline.run(source, trackOrigins: true)
                XCTAssertEqual(repair.cleaned, "buy milk", source)
                let raw = SourceUnitLedger(source)
                let action = try XCTUnwrap(source.range(of: "buy milk"))
                let licensed = raw.ids(in: frame)
                let removed = Set(raw.words.indices).subtracting(repair.survivingRawWordIDs)
                XCTAssertEqual(removed, licensed, source)
                XCTAssertTrue(raw.ids(in: action).isSubset(of: repair.survivingRawWordIDs), source)
                XCTAssertTrue(raw.unownedMeaningfulIDs(claimed: repair.survivingRawWordIDs.union(licensed)).isEmpty, source)
                XCTAssertEqual(repair.correctedWordRawIDs, raw.words.indices.filter { raw.ids(in: action).contains($0) }.map { Set([$0]) }, source)
                let result = ThoughtExtractionEngine.extractWithRules(source)
                XCTAssertTrue(result.operations.isEmpty, source)
                XCTAssertEqual(result.items.count, 1, source)
                let item = try XCTUnwrap(result.items.first)
                XCTAssertEqual(item.organization.itemType, .shopping, source)
                XCTAssertFalse(item.needsReview, source)
                XCTAssertEqual(item.rawQuote, source)
                XCTAssertEqual(item.sourceQuote, "buy milk")
                XCTAssertNil(item.organization.reminderDate)
            }
        }
        for (source, expected) in [
            ("Well I was thinking call Noor", "call Noor"),
            ("I was thinking please wash the tray", "please wash the tray"),
            ("I was thinking reheat the soup", "reheat the soup"),
            ("I was thinking, call May tomorrow", "call May tomorrow"),
            ("I was thinking call May tomorrow", "call May tomorrow"),
            ("I was thinking, buy milk at No Frills", "buy milk at No Frills"),
            ("I was thinking buy milk at No Frills", "buy milk at No Frills"),
            ("I was thinking remind me to clean the room tomorrow", "remind me to clean the room tomorrow")
        ] {
            XCTAssertEqual(DisfluencyFilter.stripped(source), expected)
        }
    }

    func testThinkingCommandProofDeclinesActualComplementsUncertaintyOtherVoicesAndNegation() {
        for source in [
            "I was thinking I should buy milk",
            "I was thinking, I should buy milk",
            "I was thinking it might make sense to buy milk",
            "I was thinking about buying milk",
            "Like I was thinking about buying milk",
            "I was thinking of buying milk",
            "I was thinking to buy milk",
            "I was thinking buying milk would be helpful",
            "I was thinking \"buy milk\"",
            "Like I was thinking \"buy milk\"",
            "I was thinking buy milk, but that is only an idea",
            "I was thinking buy milk if Maya agrees",
            "I was thinking buy milk maybe tomorrow",
            "I was thinking buy milk or perhaps juice",
            "I was thinking don't buy milk",
            "I was not thinking buy milk",
            "Maya was thinking buy milk",
            "Like Maya was thinking buy milk",
            "'I was thinking buy milk'",
            "I was thinking Maya could buy milk",
            "I was thinking buy milk?",
            "I was thinking buy milk is a good slogan",
            "I was thinking book club Friday",
            "I was thinking text messages are better",
            "I was thinking buy milk. I have not decided."
        ] {
            XCTAssertNil(DisfluencyFilter.imperativeThinkingFrameRange(in: source), source)
            XCTAssertEqual(DisfluencyFilter.stripped(source), DisfluencyFilter.scopePrefix(source), source)
        }
    }

    func testThinkingFrameProvesArgumentsAndLicensesItsCompleteRawPrefix() throws {
        let previous = SentenceContext.taggerDisabledForEvaluation
        defer {
            SentenceContext.taggerDisabledForEvaluation = previous
            SentenceContextCache.invalidate()
        }
        for disabled in [false, true] {
            SentenceContext.taggerDisabledForEvaluation = disabled
            SentenceContextCache.invalidate()
            for (source, expected) in [
                ("The thing is I was thinking buy milk", "buy milk"),
                ("Okay, the thing is I was thinking buy milk", "buy milk"),
                ("The thing is Like, I was thinking buy milk", "buy milk"),
                ("I was thinking call May tomorrow", "call May tomorrow"),
                ("I was thinking buy milk at No Frills", "buy milk at No Frills")
            ] {
                let frame = try XCTUnwrap(DisfluencyFilter.imperativeThinkingFrameRange(in: source), source)
                let ledger = SourceUnitLedger(source)
                let repair = SpeechRepairPipeline.run(source, trackOrigins: true)
                XCTAssertEqual(repair.cleaned, expected, source)
                XCTAssertEqual(Set(ledger.words.indices).subtracting(repair.survivingRawWordIDs),
                               ledger.ids(in: frame), source)
                let rows = ThoughtExtractionEngine.extractWithRules(source).items
                XCTAssertEqual(rows.count, 1, source)
                XCTAssertFalse(rows.first?.needsReview ?? true, source)
                XCTAssertEqual(rows.first?.rawQuote, source, source)
            }
            for source in ["I was thinking book club Friday", "I was thinking text messages are better",
                           "The thing is I was thinking text messages are better"] {
                XCTAssertNil(DisfluencyFilter.imperativeThinkingFrameRange(in: source), source)
                XCTAssertTrue(DisfluencyFilter.stripped(source).contains("I was thinking"), source)
            }
        }
    }

    func testStandaloneHesitationsInLongCaptureDoNotBecomeShopping() {
        let source = "Um, let me think. Remind me to check the equipment logger every twenty four hours. Right, okay. Keep that distinction when the clock changes."
        let rows = ThoughtExtractionEngine.extractWithRules(source).items
        XCTAssertFalse(rows.contains { $0.suggestedTitle?.localizedCaseInsensitiveContains("buy right") == true })
        XCTAssertFalse(rows.contains { $0.suggestedTitle?.localizedCaseInsensitiveContains("buy okay") == true })
        XCTAssertFalse(rows.contains { $0.sourceQuote.localizedCaseInsensitiveContains("let me think") })
        XCTAssertTrue(rows.contains { $0.sourceQuote.localizedCaseInsensitiveContains("equipment logger") })

        let shopping = ThoughtExtractionEngine.extractWithRules("Buy milk. Right, buy bread.").items
        XCTAssertTrue(shopping.contains { $0.analysisText.localizedCaseInsensitiveContains("buy milk") && $0.organization.itemType == .shopping })
        XCTAssertTrue(shopping.contains { $0.analysisText.localizedCaseInsensitiveContains("buy bread") && $0.organization.itemType == .shopping })
        let isolated = ThoughtExtractionEngine.extractWithRules("Let me think").items
        XCTAssertEqual(isolated.count, 1)
        XCTAssertTrue(isolated[0].needsReview)
    }

    func testRepairTraceKeepsRawOccurrenceIdentityAcrossStages() {
        let result = SpeechRepairPipeline.run("Um, call Mom at five, actually six",
                                              trackOrigins: true)
        let words = result.rawWords.map(\.text)
        XCTAssertEqual(words, ["um", "call", "mom", "at", "five", "actually", "six"])
        XCTAssertEqual(result.stages[0].removedRawWordIDs, [0])
        XCTAssertEqual(result.stages[2].removedRawWordIDs, [4, 5])
        XCTAssertTrue(result.survivingRawWordIDs.contains(1))
        XCTAssertTrue(result.survivingRawWordIDs.contains(2))
        XCTAssertTrue(result.survivingRawWordIDs.contains(6))

        let repeated = SpeechRepairPipeline.run("Call Mom, no, call Dad", trackOrigins: true)
        XCTAssertEqual(repeated.rawWords.map(\.text),
                       ["call", "mom", "no", "call", "dad"])
        XCTAssertTrue(repeated.stages[2].removedRawWordIDs.contains(1))
        XCTAssertTrue(repeated.survivingRawWordIDs.contains(4))

        let echoed = SpeechRepairPipeline.run(
            "Buy milk, no wait, buy milk and eggs", trackOrigins: true
        )
        XCTAssertTrue(echoed.stages[2].removedRawWordIDs.isSuperset(of: [0, 1, 2, 3]))
        XCTAssertTrue(echoed.survivingRawWordIDs.isSuperset(of: [4, 5, 6, 7]))

        let joined = SpeechRepairPipeline.run("To morrow call Mom", trackOrigins: true)
        XCTAssertTrue(joined.stages[1].removedRawWordIDs.isEmpty)
        XCTAssertTrue(joined.survivingRawWordIDs.isSuperset(of: [0, 1, 2, 3]))
    }

    func testRawRepairAuditHoldsUnexplainedLossAndRepeatedQuotes() throws {
        let raw = "Call Mom and call Dad"
        let ledger = SourceUnitLedger(raw)
        let lost = SpeechRepairPipeline.Result(
            cleaned: raw, splitCompounds: raw, selfCorrected: "call Dad",
            corrected: "call Dad",
            stages: [SpeechRepairPipeline.Stage(
                kind: .selfCorrection, input: raw, output: "call Dad",
                removedRawWordIDs: [0, 1, 2]
            )], rawWords: ledger.words, survivingRawWordIDs: [3, 4],
            correctedWordRawIDs: []
        )
        let dad = try XCTUnwrap(RuleBasedThoughtExtractor.process("call Dad").items.first)
        XCTAssertTrue(RuleBasedThoughtExtractor.auditRawRepairCoverage(
            lost, raw: raw, items: [dad]
        ))

        let repeated = "Call Mom, call Mom"
        let repeatedLedger = SourceUnitLedger(repeated)
        let ambiguous = SpeechRepairPipeline.Result(
            cleaned: repeated, splitCompounds: repeated,
            selfCorrected: "call Mom", corrected: "call Mom",
            stages: [SpeechRepairPipeline.Stage(
                kind: .selfCorrection, input: repeated, output: "call Mom",
                removedRawWordIDs: [0, 1]
            )], rawWords: repeatedLedger.words, survivingRawWordIDs: [2, 3],
            correctedWordRawIDs: []
        )
        let mom = try XCTUnwrap(RuleBasedThoughtExtractor.process("call Mom").items.first)
        XCTAssertTrue(RuleBasedThoughtExtractor.auditRawRepairCoverage(
            ambiguous, raw: repeated, items: [mom]
        ), "One identical quote cannot silently own both spoken occurrences.")

        let visible = ExtractedThought(
            sourceQuote: "call Dad", rawQuote: raw, wasRepaired: true,
            analysisText: "call Dad", suggestedTitle: nil,
            organization: dad.organization, confidence: 1, needsReview: false
        )
        XCTAssertTrue(RuleBasedThoughtExtractor.auditRawRepairCoverage(
            lost, raw: raw, items: [visible]
        ), "A full raw quote cannot certify interpretation of a deleted action.")
    }

    func testRawRepairAuditLicensesOnlyDisfluencyStage() throws {
        let raw = "Um, call Mom"
        let trace = SpeechRepairPipeline.run(raw, trackOrigins: true)
        let item = try XCTUnwrap(RuleBasedThoughtExtractor.process(raw).items.first)
        XCTAssertFalse(RuleBasedThoughtExtractor.auditRawRepairCoverage(
            trace, raw: raw, items: [item]
        ))
        XCTAssertEqual(item.organization.itemType, .personFollowUp)
        XCTAssertFalse(item.needsReview)

        let modal = "I guess call Mom"
        let modalLedger = SourceUnitLedger(modal)
        let corrupted = SpeechRepairPipeline.Result(
            cleaned: "call Mom", splitCompounds: "call Mom",
            selfCorrected: "call Mom", corrected: "call Mom",
            stages: [SpeechRepairPipeline.Stage(
                kind: .disfluency, input: modal, output: "call Mom",
                removedRawWordIDs: [0, 1]
            )], rawWords: modalLedger.words, survivingRawWordIDs: [2, 3],
            correctedWordRawIDs: []
        )
        XCTAssertTrue(RuleBasedThoughtExtractor.auditRawRepairCoverage(
            corrupted, raw: modal, items: []
        ), "A disfluency-stage label cannot license an uncertainty cue.")

        let multi = "Call Mom and call Dad, actually call Sarah"
        let multiLedger = SourceUnitLedger(multi)
        let erased = SpeechRepairPipeline.Result(
            cleaned: multi, splitCompounds: multi,
            selfCorrected: "call Sarah", corrected: "call Sarah",
            stages: [SpeechRepairPipeline.Stage(
                kind: .selfCorrection, input: multi, output: "call Sarah",
                removedRawWordIDs: Set(0..<multiLedger.words.count - 2)
            )], rawWords: multiLedger.words,
            survivingRawWordIDs: Set((multiLedger.words.count - 2)..<multiLedger.words.count),
            correctedWordRawIDs: []
        )
        XCTAssertTrue(RuleBasedThoughtExtractor.auditRawRepairCoverage(
            erased, raw: multi, items: []
        ), "A local correction cannot license a missing independent action.")
    }

    func testIntentionFrameIsNotDiscardedAsDiscourse() {
        let intention = "I mean to call Mom"
        XCTAssertEqual(DisfluencyFilter.stripped(intention), intention)
        XCTAssertEqual(ActionabilityReader.read(intention), .actionable)
        XCTAssertTrue(ThoughtOrganizer.organize(intention).itemType.isActionable)
        let action = RuleBasedThoughtExtractor.process(intention).items
        XCTAssertEqual(action.count, 1)
        XCTAssertTrue(action[0].organization.itemType.isActionable)
        XCTAssertFalse(action[0].needsReview)
        XCTAssertTrue(action[0].sourceQuote.contains("mean to"))

        let aside = RuleBasedThoughtExtractor.process("I mean, call Mom").items
        XCTAssertEqual(aside.count, 1)
        XCTAssertTrue(aside[0].organization.itemType.isActionable)
        XCTAssertFalse(aside[0].needsReview)
    }

    func testRawRepairAuditLicensesSameSlotCorrectionWithoutLicensingNegation() {
        let corrected = RuleBasedThoughtExtractor.process("Tomorrow, no Friday, remind me about OSAP")
        XCTAssertEqual(corrected.items.count, 1)
        XCTAssertFalse(corrected.items[0].needsReview)
        XCTAssertTrue(corrected.items[0].sourceQuote.lowercased().contains("friday"))

        let raw = "Tomorrow, no call Mom"
        let ledger = SourceUnitLedger(raw)
        let unsupported = SpeechRepairPipeline.Result(
            cleaned: raw, splitCompounds: raw, selfCorrected: "call Mom",
            corrected: "call Mom",
            stages: [SpeechRepairPipeline.Stage(
                kind: .selfCorrection, input: raw, output: "call Mom",
                removedRawWordIDs: [0, 1]
            )], rawWords: ledger.words, survivingRawWordIDs: [2, 3],
            correctedWordRawIDs: []
        )
        XCTAssertTrue(RuleBasedThoughtExtractor.auditRawRepairCoverage(
            unsupported, raw: raw, items: []
        ))
    }

    func testBareWithdrawalKeepsLocalIntentionIdentityThroughRepair() {
        let mixed = "Buy milk and call Sarah, actually never mind"
        XCTAssertEqual(SelfCorrectionResolver.resolved(mixed), mixed)
        let result = RuleBasedThoughtExtractor.process(mixed)
        XCTAssertEqual(result.items.map(\.organization.itemType), [.shopping])
        XCTAssertTrue(result.items.first?.sourceQuote.lowercased().contains("buy milk") == true)
        XCTAssertEqual(result.operations.count, 1)
        XCTAssertEqual(result.operations.first?.operation, .retract)
        XCTAssertEqual(result.operations.first?.isScoped, true)

        let trailing = RuleBasedThoughtExtractor.process(
            "Call Sarah, actually never mind, and buy milk"
        )
        XCTAssertEqual(trailing.items.map(\.organization.itemType), [.shopping])
        XCTAssertEqual(trailing.operations.first?.operation, .retract)
        XCTAssertEqual(trailing.operations.first?.isScoped, true)

        let direct = RuleBasedThoughtExtractor.process(
            "I need to call Sarah, actually never mind"
        )
        XCTAssertTrue(direct.items.isEmpty)
        XCTAssertEqual(direct.operations.first?.operation, .retract)

        let literal = RuleBasedThoughtExtractor.process("Tell Sarah never mind")
        XCTAssertEqual(literal.items.count, 1)
        XCTAssertTrue(literal.operations.isEmpty)
    }

    func testActionReplacementStopsBeforeTheNextIndependentIntention() {
        let coordinated = "Call Sarah, actually email her about the invoice, and buy bread"
        let repaired = SpeechRepairPipeline.run(coordinated).corrected
        let clauses = RuleBasedThoughtExtractor.splitClauses(repaired)
        XCTAssertEqual(clauses.count, 2,
                       "repair=\(repaired), act=\(ClauseScope.read(repaired).act), clauses=\(clauses)")
        for source in [
            "Call Sarah, actually email her, and buy bread",
            "Call Sarah, actually email her and buy bread",
        ] {
            let items = ThoughtExtractionEngine.extractWithRules(source).items
            XCTAssertEqual(items.count, 2, "\(source) → \(items.map(\.analysisText))")
            XCTAssertEqual(items[0].organization.personName, "Sarah", source)
            XCTAssertTrue(items[0].analysisText.lowercased().contains("email"), source)
            XCTAssertFalse(items.contains {
                $0.analysisText.lowercased().hasPrefix("call sarah")
            }, source)
            XCTAssertEqual(items[1].organization.itemType, .shopping, source)
            XCTAssertTrue(items[1].rawQuote.lowercased().contains("bread"), source)
            XCTAssertTrue(items[0].rawQuote.contains("Call Sarah"), source)
            XCTAssertTrue(items[0].rawQuote.contains("email her"), source)
            XCTAssertFalse(items[0].rawQuote.contains("bread"), source)
        }

        let differentTarget = ThoughtExtractionEngine.extractWithRules(
            "Call Sarah, actually email the invoice, and buy bread"
        ).items
        XCTAssertEqual(differentTarget.count, 3)
        XCTAssertTrue(differentTarget.contains {
            $0.analysisText.lowercased().hasPrefix("call sarah")
        })
        XCTAssertTrue(differentTarget.contains {
            $0.analysisText.lowercased().contains("email the invoice")
        })

        let short = ThoughtExtractionEngine.extractWithRules(
            "Call Sarah, actually email her"
        ).items
        XCTAssertEqual(short.count, 1)
        XCTAssertTrue(short[0].analysisText.lowercased().contains("email sarah"))

        for source in [
            "Call Sarah, actually email her about the invoice, and buy bread",
            "Call Sarah, actually email her at five, and buy bread",
        ] {
            let items = ThoughtExtractionEngine.extractWithRules(source).items
            XCTAssertEqual(items.count, 2, "\(source) → \(items.map(\.analysisText))")
            XCTAssertTrue(items[0].analysisText.lowercased().contains("email sarah"), source)
            XCTAssertFalse(items.contains {
                $0.analysisText.lowercased().hasPrefix("call sarah")
            }, source)
            XCTAssertEqual(items[1].organization.itemType, .shopping, source)
            XCTAssertTrue(items[0].rawQuote.contains("Call Sarah"), source)
            XCTAssertTrue(items[0].rawQuote.contains("email her"), source)
            XCTAssertFalse(items[0].rawQuote.contains("bread"), source)
        }

        let possessive = ThoughtExtractionEngine.extractWithRules(
            "Call Sarah, actually email her boss, and buy bread"
        ).items
        XCTAssertEqual(possessive.count, 3)
        XCTAssertTrue(possessive.contains {
            $0.analysisText.lowercased().hasPrefix("call sarah")
        })
    }

    func testSpeechActBoundaryControlsAcrossRunOnAndMessageContent() {
        for source in [
            "Call the dentist tomorrow buy milk and remember Catherine is allergic to peanuts",
            "Text Mike that the meeting is cancelled and remind me to call Sarah"
        ] {
            let repaired = SpeechRepairPipeline.run(source).corrected
            let clauses = RuleBasedThoughtExtractor.splitClauses(repaired)
            let items = ThoughtExtractionEngine.extractWithRules(source).items
            let expected = source.hasPrefix("Call") ? 3 : 2
            let scope = ClauseScope.read(repaired)
            XCTAssertEqual(items.count, expected,
                           "source=\(source), act=\(scope.act), matrix=\(scope.matrix), recipient=\(scope.recipient ?? "nil"), complement=\(scope.complement ?? "nil"), repaired=\(repaired), clauses=\(clauses), items=\(items.map(\.analysisText))")
        }
    }

    func testBarePersonCorrectionUsesUniqueSlotWithoutPunctuation() {
        for (source, expected) in [
            ("Call Catherine tomorrow actually Alex", "Call Alex tomorrow"),
            ("Text Siobhan about the tickets sorry Priya", "Text Priya about the tickets"),
            ("When I get home remind me to call Alex actually Catherine",
             "When I get home remind me to call Catherine"),
        ] {
            XCTAssertEqual(SelfCorrectionResolver.resolved(source), expected, source)
        }

        for source in [
            "Ask Sarah and Maya actually Priya",
            "Tell Sam the client actually Alex likes golf",
            "Remember Alex likes golf actually tennis",
        ] {
            XCTAssertEqual(SelfCorrectionResolver.resolved(source), source)
        }
    }


    func testAdditiveCorrectionMarkerCannotSilentlyWithdrawIndependentAction() {
        for source in [
            "Buy milk, actually I also need to call Mom.",
            "Book the room, actually send the agenda too.",
            "Call Mara, actually mail the invoice.",
        ] {
            XCTAssertEqual(SelfCorrectionResolver.resolved(source), source)
        }

        let additive = ThoughtExtractionEngine.extractWithRules(
            "Buy milk, actually I also need to call Mom."
        ).items
        XCTAssertEqual(additive.count, 2)
        XCTAssertTrue(additive.contains { $0.sourceQuote.localizedCaseInsensitiveContains("milk") })
        XCTAssertTrue(additive.contains { $0.sourceQuote.localizedCaseInsensitiveContains("call Mom") })

        XCTAssertEqual(SelfCorrectionResolver.resolved("Buy milk, actually buy oat milk."),
                       "buy oat milk.")
        XCTAssertEqual(SelfCorrectionResolver.resolved(
            "I need to call Mara, actually I need to email Mara."
        ), "I need to email Mara.")
        XCTAssertEqual(SelfCorrectionResolver.resolved(
            "Call Sarah, actually email her."
        ), "email Sarah.")
        let corrected = ThoughtExtractionEngine.extractWithRules(
            "Call Sarah, actually email her."
        ).items
        XCTAssertEqual(corrected.count, 1)
        XCTAssertEqual(corrected.first?.rawQuote, "Call Sarah, actually email her.")
        XCTAssertTrue(corrected.first?.wasRepaired == true)
        XCTAssertEqual(corrected.first?.organization.personName, "Sarah")
        XCTAssertEqual(SelfCorrectionResolver.resolved(
            "Print the invoice, actually email it."
        ), "email the invoice.")
        XCTAssertEqual(SelfCorrectionResolver.resolved(
            "Call Sarah and Maya, actually email her."
        ), "Call Sarah and Maya, actually email her.")
        let withdrawn = CaptureOperationDetector.partition("Buy milk, no, forget milk.")
        XCTAssertEqual(withdrawn.operations.count, 1)
        XCTAssertNil(withdrawn.remainder)
    }

    func testCorrectionScopesToOneLocalIntentionAcrossACompoundPrefix() {
        let correctedTail = "Buy eggs and call Mom, actually call Dad."
        let repairedTail = SelfCorrectionResolver.resolved(correctedTail)
        XCTAssertTrue(repairedTail.localizedCaseInsensitiveContains("buy eggs"))
        XCTAssertTrue(repairedTail.localizedCaseInsensitiveContains("call Dad"))
        XCTAssertFalse(repairedTail.localizedCaseInsensitiveContains("call Mom"))

        let unrelatedMiddle = "Call Mom and buy eggs, actually call Dad."
        XCTAssertEqual(SelfCorrectionResolver.resolved(unrelatedMiddle), unrelatedMiddle)

        let rows = ThoughtExtractionEngine.extractWithRules(correctedTail).items
        XCTAssertEqual(rows.count, 2)
        XCTAssertTrue(rows.contains { $0.sourceQuote.localizedCaseInsensitiveContains("buy eggs") })
        XCTAssertTrue(rows.contains { $0.sourceQuote.localizedCaseInsensitiveContains("call Dad") })

        XCTAssertEqual(SelfCorrectionResolver.resolved("Call Mom, actually call Dad."),
                       "call Dad.")
        XCTAssertEqual(SelfCorrectionResolver.resolved("Buy eggs and call Mom."),
                       "Buy eggs and call Mom.")
    }

    func testFrontedDateAfterCorrectionKeepsItsActionOwner() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Toronto"))
        let previousZone = NSTimeZone.default
        NSTimeZone.default = calendar.timeZone
        defer { NSTimeZone.default = previousZone }
        let reference = try XCTUnwrap(calendar.date(from:
            DateComponents(year: 2026, month: 8, day: 3, hour: 10)))
        let distinct = "Call Sarah Monday, actually Tuesday call Maya."
        XCTAssertEqual(SelfCorrectionResolver.resolved(distinct), distinct)
        let items = ThoughtExtractionEngine.extractWithRules(
            distinct, referenceDate: reference, calendar: calendar
        ).items
        XCTAssertEqual(items.count, 2)
        XCTAssertTrue(items[0].sourceQuote.contains("Sarah Monday"))
        XCTAssertTrue(items[1].sourceQuote.contains("Tuesday call Maya"))
        if items.count == 2 {
            let sarahDay = try XCTUnwrap(items[0].organization.dueDate)
            let mayaDay = try XCTUnwrap(items[1].organization.dueDate)
            XCTAssertEqual(calendar.component(.weekday, from: sarahDay), 2)
            XCTAssertEqual(calendar.component(.weekday, from: mayaDay), 3)
        }

        let differentVerb = "Call Sarah Monday, actually Tuesday buy milk."
        XCTAssertEqual(SelfCorrectionResolver.resolved(differentVerb), differentVerb)
        let mixed = ThoughtExtractionEngine.extractWithRules(
            differentVerb, referenceDate: reference, calendar: calendar
        ).items
        XCTAssertEqual(mixed.count, 2)
        if mixed.count == 2 {
            XCTAssertEqual(calendar.component(.weekday, from: try XCTUnwrap(mixed[0].organization.dueDate)), 2)
            XCTAssertEqual(calendar.component(.weekday, from: try XCTUnwrap(mixed[1].organization.dueDate)), 3)
        }

        XCTAssertEqual(SelfCorrectionResolver.resolved(
            "Call Sarah Monday, actually Tuesday call Sarah."
        ), "Tuesday call Sarah.")
        XCTAssertEqual(SelfCorrectionResolver.resolved(
            "Call Sarah Monday, actually Tuesday."
        ), "Call Sarah Tuesday.")
    }

    func testComparativeRunOnOpensANewDirectiveAcrossDeviceTagging() {
        XCTAssertEqual(
            ClauseJuxtaposition.pieces(in: "This option is better send the other one instead"),
            ["This option is better", "send the other one instead"]
        )
        XCTAssertEqual(ClauseJuxtaposition.pieces(in: "I better send the other one instead").count, 1)
    }

    func testCausativeLetsKeepsItsVerbInsideOneProposal() {
        XCTAssertEqual(
            ClauseJuxtaposition.pieces(in: "An app lets neighbors create shared calendars").count,
            1
        )
        XCTAssertEqual(
            ClauseJuxtaposition.pieces(in: "Build the prototype create a demo account").count,
            2
        )
    }

    func testWithdrawnActionOwnsItsStandaloneForwardTime() {
        let withdrawn = SelfCorrectionResolver.resolved(
            "For Friday, email Dana—wait, no, I already emailed her"
        )
        XCTAssertFalse(withdrawn.lowercased().contains("for friday"))
        XCTAssertFalse(withdrawn.lowercased().contains("email dana"))
        XCTAssertTrue(withdrawn.lowercased().contains("already emailed"))

        let independent = SelfCorrectionResolver.resolved(
            "The meeting is Friday. Email Dana—wait, no, I already emailed her"
        )
        XCTAssertTrue(independent.contains("The meeting is Friday"))
    }

    func testQuotedReportedOperationStaysOwnedByTheReporter() {
        let source = "Nina said, \"Cancel the reservation and tell everyone the event is off,\" but I need to call the venue tomorrow."
        let partition = CaptureOperationDetector.partition(source)
        XCTAssertTrue(partition.operations.isEmpty)
        XCTAssertTrue(partition.remainder?.contains("Cancel the reservation") == true)
        let items = RuleBasedThoughtExtractor.extract(source)
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items[0].organization.itemType, .note)
        XCTAssertTrue(items[0].sourceQuote.contains("Nina said"))
        XCTAssertTrue(items[0].sourceQuote.contains("Cancel the reservation"))
        XCTAssertTrue(items[1].organization.itemType.isActionable)
        XCTAssertTrue(items[1].sourceQuote.contains("call the venue"))
    }

    func testStraightQuotedMessageDoesNotBecomeCaptureOperation() {
        let text = "Tell Alex 'cancel the meeting and call Nina'"
        XCTAssertTrue(CaptureOperationDetector.partition(text).operations.isEmpty)
        let items = RuleBasedThoughtExtractor.extract(text)
        XCTAssertEqual(items.count, 1)
        XCTAssertTrue(items[0].sourceQuote.contains("cancel the meeting"))
        XCTAssertTrue(QuotedSpeechScope.ranges(in: "Don't cancel the dentist reminder").isEmpty)
    }

    func testUnclosedReportedQuoteStaysOneReviewableNonExecutableCapture() {
        let text = "Nina said, \"Cancel the reservation and call everyone"
        XCTAssertTrue(CaptureOperationDetector.partition(text).operations.isEmpty)
        let items = RuleBasedThoughtExtractor.extract(text)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].organization.itemType, .unclear)
        XCTAssertTrue(items[0].needsReview)
        XCTAssertTrue(items[0].sourceQuote.contains("call everyone"))
    }

    func testUnpunctuatedActionAfterQuoteKeepsItsOwnOwnership() {
        let items = RuleBasedThoughtExtractor.extract(
            "Nina said \"Cancel the meeting\" and call Alex"
        )
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items[0].organization.itemType, .note)
        XCTAssertTrue(items[1].organization.itemType.isActionable)
        XCTAssertTrue(items[1].sourceQuote.contains("call Alex"))
    }

    func testDirectOperationAfterReportedQuotationStillExecutes() {
        let source = "Nina said, \"Keep the reservation.\" Cancel the dentist reminder."
        let partition = CaptureOperationDetector.partition(source)
        XCTAssertEqual(partition.operations.count, 1)
        XCTAssertEqual(partition.operations.first?.operation, .cancel)
        XCTAssertTrue(partition.remainder?.contains("Nina said") == true)
    }

    func testUnquotedReportedCommandsCannotBecomeOperationsAtCommaBoundary() {
        for source in [
            "Sarah said, cancel the dentist appointment. I need to buy milk.",
            "The doctor said, cancel my appointment.",
            "My manager wrote, push the launch back a week.",
            "I told Sarah, cancel the dentist appointment.",
        ] {
            let partition = CaptureOperationDetector.partition(source)
            XCTAssertTrue(partition.operations.isEmpty, source)
            XCTAssertEqual(partition.remainder, source, source)
        }
        let own = CaptureOperationDetector.partition(
            "Sarah said never mind. Cancel the dentist appointment."
        )
        XCTAssertEqual(own.operations.map(\.operation), [.cancel])
    }

    func testCausalReturnToSpeakerAfterReportCanOwnAnOperation() {
        let direct = CaptureOperationDetector.partition(
            "Sarah said she cannot come, so cancel the booking."
        )
        XCTAssertEqual(direct.operations.map(\.operation), [.cancel])
        XCTAssertTrue(direct.remainder?.lowercased().contains("sarah said") == true)

        for reported in [
            "Sarah said, cancel the booking.",
            "Sarah said cancel the booking and tell everyone."
        ] {
            XCTAssertTrue(CaptureOperationDetector.partition(reported).operations.isEmpty, reported)
        }
        let nextSentence = CaptureOperationDetector.partition(
            "Sarah said cancel the booking. Cancel the dentist reminder."
        )
        XCTAssertEqual(nextSentence.operations.map(\.operation), [.cancel])
    }

    func testConsecutiveCorrectionsKeepOneLocalIntentionIdentity() {
        let shopping = ThoughtExtractionEngine.extractWithRules(
            "Buy milk, actually buy bread, actually buy eggs."
        ).items
        XCTAssertEqual(shopping.count, 1)
        XCTAssertEqual(shopping.first?.organization.itemType, .shopping)
        XCTAssertTrue(shopping.first?.analysisText.lowercased().contains("buy eggs") == true)
        XCTAssertTrue(shopping.first?.rawQuote.contains("Buy milk") == true)

        let person = ThoughtExtractionEngine.extractWithRules(
            "Call Sarah, actually email her, actually text her."
        ).items
        XCTAssertEqual(person.count, 1)
        XCTAssertEqual(person.first?.organization.personName, "Sarah")
        XCTAssertTrue(person.first?.analysisText.lowercased().contains("text sarah") == true)
        XCTAssertTrue(person.first?.rawQuote.contains("Call Sarah") == true)

        let additive = ThoughtExtractionEngine.extractWithRules(
            "Call Sarah, actually email her and also text her."
        ).items
        XCTAssertEqual(additive.count, 2)
        XCTAssertEqual(additive.map(\.organization.personName), ["Sarah", "Sarah"])
        let independent = ThoughtExtractionEngine.extractWithRules(
            "Call Sarah then call Mom, actually email her."
        ).items
        XCTAssertEqual(independent.map(\.organization.personName), ["Sarah", "Mom"])
    }

    func testNamedWithdrawalTargetsEarlierLocalIntention() {
        let partition = CaptureOperationDetector.partition(
            "Call TD and return the envelopes. Actually forget the envelopes. Buy stamps."
        )
        XCTAssertTrue(partition.remainder?.contains("Call TD") == true)
        XCTAssertTrue(partition.remainder?.contains("Buy stamps") == true)
        XCTAssertFalse(partition.remainder?.contains("return the envelopes") == true)
        XCTAssertFalse(partition.remainder?.contains(". No,") == true)
        XCTAssertEqual(partition.operations.filter(\.isScoped).count, 1)
    }

    func testOperationSourceAndWithdrawnTargetHaveDistinctOccurrenceIdentities() throws {
        let source = "Buy eggs. Buy milk. Actually forget eggs."
        let ledger = SourceUnitLedger(source)
        let result = CaptureOperationDetector.partition(source)
        let request = try XCTUnwrap(result.operations.first)
        XCTAssertTrue(request.isScoped)
        XCTAssertEqual(request.localTargetUnitIDs,
                       ledger.ids(in: try XCTUnwrap(source.range(of: "Buy eggs"))))
        let eggs = ledger.words.indices.filter { ledger.words[$0].text == "eggs" }
        XCTAssertEqual(eggs.count, 2)
        XCTAssertTrue(request.localTargetUnitIDs.contains(eggs[0]))
        XCTAssertFalse(request.localTargetUnitIDs.contains(eggs[1]))
        XCTAssertTrue(request.sourceUnitIDs.contains(eggs[1]))

        let owned = CaptureOperationDetector.partitionWithOwnership(source)
        XCTAssertEqual(owned.operations.first?.localTargetUnitIDs,
                       request.localTargetUnitIDs)
        XCTAssertFalse(owned.retainedUnitIDs.contains(eggs[0]))
        XCTAssertFalse(owned.retainedUnitIDs.contains(eggs[1]))
        XCTAssertTrue(owned.retainedUnitIDs.contains(
            try XCTUnwrap(ledger.words.firstIndex(where: { $0.text == "milk" }))
        ))

        let direct = CaptureOperationDetector.partition("Cancel the dentist reminder")
        XCTAssertEqual(direct.operations.first?.sourceUnitIDs,
                       Set(SourceUnitLedger("Cancel the dentist reminder").words.indices))
        XCTAssertTrue(direct.operations.first?.localTargetUnitIDs.isEmpty == true)

        let correctionCue = CaptureOperationDetector.partitionWithOwnership(
            "Buy milk, no, forget milk."
        )
        XCTAssertTrue(correctionCue.unownedMeaningfulIDs(in: "Buy milk, no, forget milk.").isEmpty)
        XCTAssertFalse(correctionCue.discourseLinks.isEmpty)

        let emphatic = "Don't buy milk but do pick up bread"
        let emphasized = CaptureOperationDetector.partitionWithOwnership(emphatic)
        XCTAssertTrue(emphasized.unownedMeaningfulIDs(in: emphatic).isEmpty)
        let emphasisWords = SourceUnitLedger(emphatic).words
        let doID = try XCTUnwrap(emphasisWords.firstIndex(where: { $0.text == "do" }))
        XCTAssertTrue(emphasized.discourseLinks.contains { $0.cueUnitIDs.contains(doID)
            && $0.ownerUnitIDs.contains(where: { emphasisWords[$0].text == "pick" }) })

        let unseenSource = "Cancel the dentist reminder. Email Jo."
        let unseenLedger = SourceUnitLedger(unseenSource)
        var partial = CaptureOperationRequest(
            operation: .cancel, target: "dentist reminder",
            sourceQuote: "Cancel the dentist reminder", needsReview: false
        )
        partial.sourceUnitIDs = unseenLedger.ids(in:
            try XCTUnwrap(unseenSource.range(of: "Cancel the dentist reminder")))
        let incomplete = CaptureOperationDetector.Partition(
            operations: [partial], remainder: nil, retainedUnitIDs: [],
            discourseLinks: []
        )
        let hold = RuleBasedThoughtExtractor.reviewUnownedOperationSource(
            incomplete, source: unseenSource, raw: unseenSource
        )
        XCTAssertTrue(hold?.needsReview == true)
        XCTAssertEqual(hold?.sourceQuote, unseenSource)
        XCTAssertNil(RuleBasedThoughtExtractor.reviewUnownedOperationSource(
            CaptureOperationDetector.partitionWithOwnership(unseenSource),
            source: unseenSource, raw: unseenSource
        ))
    }

    func testWithdrawalKeepsSentenceBoundariesAmongSurvivors() {
        let partition = CaptureOperationDetector.partition(
            "Call Mara. Buy ink and envelopes. No, skip the envelopes. Send Omar the draft."
        )
        XCTAssertTrue(partition.remainder?.contains("Call Mara. Buy ink") == true,
                      partition.remainder ?? "nil")
        XCTAssertTrue(partition.remainder?.contains("Send Omar the draft") == true)
    }

    func testSentenceLocalCorrectionPreservesBoundaryBetweenTasks() {
        let resolved = SelfCorrectionResolver.resolved(
            "Call Mara on Tuesday, actually Thursday, about the contract. Buy printer ink."
        )
        XCTAssertTrue(resolved.contains("contract. Buy printer ink"), resolved)
    }

    func testUnmatchedNamedWithdrawalCannotEraseNearbyIntention() {
        let partition = CaptureOperationDetector.partition(
            "Call TD. Skip the envelopes. Buy stamps."
        )
        XCTAssertTrue(partition.remainder?.contains("Call TD") == true)
        XCTAssertTrue(partition.remainder?.contains("Buy stamps") == true)
        XCTAssertEqual(partition.operations.count, 1)
        XCTAssertEqual(partition.operations.first?.target, "envelopes")
        XCTAssertEqual(partition.operations.first?.needsReview, true)
    }

    func testOperationPartitionKeepsNewInstructionAfterSentenceBoundary() {
        let result = CaptureOperationDetector.partition(
            "I already mailed the form. Send the draft to Omar tonight."
        )
        XCTAssertEqual(result.operations.count, 1)
        XCTAssertEqual(result.operations.first?.operation, .complete)
        XCTAssertEqual(result.operations.first?.target, "mailed the form")
        XCTAssertEqual(result.remainder, "Send the draft to Omar tonight")
    }

    func testDoNotCancelDoesNotExecuteCancellation() {
        let result = CaptureOperationDetector.partition(
            "I was going to cancel the dentist. Don't cancel it. Send the draft to Omar tonight."
        )
        XCTAssertTrue(result.operations.isEmpty)
        XCTAssertTrue(result.remainder?.contains("Send the draft to Omar tonight") == true)
    }

    func testAlreadyHavingAnObjectIsNotTaskCompletion() {
        XCTAssertNil(CaptureOperationDetector.detect("I already have a box"))
        XCTAssertEqual(
            CaptureOperationDetector.detect("I already mailed the form")?.operation,
            .complete
        )
    }

    func testPrepositionalFormatNounDoesNotOpenACommand() {
        for source in [
            "The address should be sent as text as well as a photo",
            "Save the message as text",
            "Keep the draft as print rather than audio",
            "Remember the invoice was supplied as copy",
            "She described the lesson as play"
        ] {
            XCTAssertEqual(ClauseJuxtaposition.pieces(in: source), [source], source)
        }
        XCTAssertEqual(ClauseJuxtaposition.pieces(in: "save the draft text Pat"),
                       ["save the draft", "text Pat"])
        XCTAssertEqual(ClauseJuxtaposition.pieces(in: "the address is ready text Pat"),
                       ["the address is ready", "text Pat"])
        XCTAssertEqual(ClauseJuxtaposition.pieces(in: "send the photo print the form"),
                       ["send the photo", "print the form"])
    }

    func testVerbShapedNominalCompoundDoesNotStartNewInstruction() {
        XCTAssertEqual(
            ClauseJuxtaposition.pieces(in: "update the emergency contact form"),
            ["update the emergency contact form"]
        )
        XCTAssertEqual(
            ClauseJuxtaposition.pieces(in: "Dad prefers a phone call after dinner"),
            ["Dad prefers a phone call after dinner"]
        )
    }

    func testCommunicationArtifactHeadKeepsItsMatrixTimeAndFreshCommands() throws {
        let oldTagger = SentenceContext.taggerDisabledForEvaluation
        let oldZone = NSTimeZone.default
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Toronto"))
        NSTimeZone.default = calendar.timeZone
        defer {
            SentenceContext.taggerDisabledForEvaluation = oldTagger
            SentenceContextCache.invalidate()
            NSTimeZone.default = oldZone
        }
        let reference = try XCTUnwrap(calendar.date(from:
            DateComponents(year: 2026, month: 11, day: 16, hour: 9)))
        for disabled in [false, true] {
            SentenceContext.taggerDisabledForEvaluation = disabled
            SentenceContextCache.invalidate()
            let source = "Email the cast the revised rehearsal schedule tonight, we added Sunday afternoons."
            for artifact in [source,
                "Email Sam the updated shift schedule tomorrow.",
                "Text Sam the final rehearsal schedule at 3 PM."] {
                XCTAssertEqual(ClauseJuxtaposition.pieces(in: artifact), [artifact], artifact)
                XCTAssertEqual(ClauseScope.read(artifact).act, .direct, artifact)
                XCTAssertEqual(ClauseScope.instructionText(artifact), artifact, artifact)
            }
            let result = ThoughtExtractionEngine.extractWithRules(source,
                referenceDate: reference, calendar: calendar)
            XCTAssertTrue(result.operations.isEmpty)
            XCTAssertEqual(result.items.count, 1, String(reflecting: result))
            let item = try XCTUnwrap(result.items.first)
            XCTAssertTrue(item.organization.itemType.isActionable)
            XCTAssertFalse(item.needsReview, source)
            XCTAssertEqual(item.rawQuote, source)
            XCTAssertTrue(item.analysisText.hasPrefix("Email"), item.analysisText)
            XCTAssertTrue(item.analysisText.localizedCaseInsensitiveContains("rehearsal schedule"))
            XCTAssertEqual(item.organization.temporalIntent.day, CalendarDay(year: 2026, month: 11, day: 16))
            XCTAssertEqual(item.organization.dueDate, calendar.date(from:
                DateComponents(year: 2026, month: 11, day: 16, hour: 20)))
            XCTAssertNil(item.organization.reminderDate)
            XCTAssertNil(item.organization.recurrenceRule)
            for (text, pieces) in [
                ("Email Sam the invoice call Mike", ["Email Sam the invoice", "call Mike"]),
                ("Text Sam the new address call tonight", ["Text Sam the new address", "call tonight"]),
                ("Email Sam the invoice schedule the rehearsal tomorrow", ["Email Sam the invoice", "schedule the rehearsal tomorrow"]),
                ("The weather is better book the campsite", ["The weather is better", "book the campsite"]),
                ("The old poster faded set the timer", ["The old poster faded", "set the timer"])
            ] {
                XCTAssertEqual(ClauseJuxtaposition.pieces(in: text), pieces, text)
            }
            for verb in ["confirm", "check", "verify"] {
                let text = "Email Sam the invoice " + verb + " they paid."
                XCTAssertEqual(ClauseJuxtaposition.pieces(in: text),
                    ["Email Sam the invoice", verb + " they paid."], text)
            }
            // Neither finite roots nor unproved plural/collective nominal
            // prefixes acquire new artifact authority in either tagger mode.
            for declined in [
                "Tell Sam the clinic won’t schedule tomorrow",
                "Text Priya the team should schedule Friday",
                "Tell Sam the team’ll schedule Monday",
                "Tell Sam the lab managers schedule Friday",
                "Tell Sam the new staff schedule Friday",
                "Tell Sam the finals schedule Friday",
                "Tell Sam the midterms schedule Friday",
                "Tell Sam the classes schedule Friday",
                "Tell Sam the new class schedule Friday",
                "Email Sam the update then shift schedule tomorrow",
                "Email Sam the update also shift schedule tomorrow",
                "Email Sam the update plus shift schedule tomorrow",
                "Email Sam the update now shift schedule tomorrow",
                "Email Sam the invoice - schedule tonight",
                "Email Sam the invoice ’ schedule tonight",
                "Email Sam the let's rehearsal schedule tomorrow",
                "Text Sam the it's revised rehearsal schedule tonight",
                "Email Sam that the revised rehearsal schedule tomorrow"
            ] {
                XCTAssertNil(ClauseScope.nominalCommunicationArtifact(in: declined), declined)
            }
            let modalMessage = "Text Priya the team should schedule Friday"
            XCTAssertEqual(ClauseScope.read(modalMessage).act, .communicating)
            XCTAssertEqual(ClauseScope.instructionText(modalMessage), "Text Priya")
            let explicitMessage = "Tell Sam that the clinic will schedule tomorrow"
            XCTAssertNil(ClauseScope.nominalCommunicationArtifact(in: explicitMessage))
            XCTAssertEqual(ClauseScope.read(explicitMessage).act, .communicating)
            let namedRecipient = "Email Cook the revised rehearsal schedule tonight."
            let owned = try XCTUnwrap(ClauseScope.nominalCommunicationArtifact(in: namedRecipient))
            XCTAssertEqual(owned.matrixRange.lowerBound, namedRecipient.startIndex)
            XCTAssertEqual(ClauseJuxtaposition.pieces(in: namedRecipient), [namedRecipient])
            // Preserve the deliberate one-word limitation; an explicit request
            // without an event remains held, while a supplied object completes.
            XCTAssertNil(ThoughtCompletion.unfinished(in: "Schedule"))
            XCTAssertEqual(ThoughtCompletion.unfinished(in: "Remind me to schedule"), .missingObject)
            XCTAssertEqual(ThoughtCompletion.unfinished(in: "Schedule for tomorrow"), .missingObject)
            XCTAssertEqual(ThoughtCompletion.unfinished(in: "Schedule tonight"), .missingObject)
            XCTAssertEqual(ThoughtCompletion.unfinished(in: "Schedule tomorrow"), .missingObject)
            XCTAssertNil(ThoughtCompletion.unfinished(in: "Schedule it tomorrow"))
            let unfinished = "Remind me to schedule tomorrow."
            XCTAssertEqual(ThoughtCompletion.unfinished(in: unfinished), .missingObject)
            let separated = ThoughtExtractionEngine.extractWithRules("Email Sam the invoice. " + unfinished,
                referenceDate: reference, calendar: calendar)
            XCTAssertEqual(separated.items.count, 2, String(reflecting: separated))
            let held = try XCTUnwrap(separated.items.first {
                $0.rawQuote.localizedCaseInsensitiveContains("schedule tomorrow")
            })
            XCTAssertTrue(held.needsReview)
            XCTAssertNil(held.organization.dueDate)
            XCTAssertNil(held.organization.reminderDate)
        }
    }

    func testNominalMessageRelativeKeepsClausalCommandsIndependent() {
        let previous = SentenceContext.taggerDisabledForEvaluation
        defer {
            SentenceContext.taggerDisabledForEvaluation = previous
            SentenceContextCache.invalidate()
        }
        for disabled in [false, true] {
            SentenceContext.taggerDisabledForEvaluation = disabled
            SentenceContextCache.invalidate()
            let relative = "Email Mr. Tran and ask if Leo can make up the spelling test he missed on Friday."
            XCTAssertEqual(ClauseJuxtaposition.pieces(in: relative), [relative])
            let rows = ThoughtExtractionEngine.extractWithRules(relative).items
            XCTAssertEqual(rows.count, 1)
            XCTAssertNil(rows.first?.organization.dueDate)
            for verb in ["confirm", "check", "verify"] {
                let source = "Email Sam the invoice " + verb + " they paid."
                XCTAssertEqual(ClauseJuxtaposition.pieces(in: source),
                               ["Email Sam the invoice", verb + " they paid."], source)
            }
            for source in [
                "We invoice call records.",
                "Nora said confirm they paid.",
                "Email Sam 'confirm they paid'.",
                "Email Sam to confirm they paid.",
                "Email Sam that we must confirm they paid.",
                "Nora said verify they paid.",
                "Email Sam 'verify they paid'.",
                "Email Sam to verify they paid.",
                "Email Sam that they verify the payment."
            ] {
                XCTAssertEqual(ClauseJuxtaposition.pieces(in: source), [source], source)
            }
        }
    }

    func testCompoundSubjectBeforeModalRetainsItsFinitePredicate() {
        for source in ["No actual phone call should be placed by the app",
                       "The return label is on the parcel"] {
            XCTAssertEqual(ClauseJuxtaposition.pieces(in: source), [source])
        }
        XCTAssertEqual(ClauseJuxtaposition.pieces(in: "the parcel is ready phone Amy"),
                       ["the parcel is ready", "phone Amy"])
    }

    func testVerbShapedSubjectBeforeModalIsNotASecondInstruction() {
        XCTAssertEqual(
            ClauseJuxtaposition.pieces(in: "The old set would make it look as though I had not looked closer"),
            ["The old set would make it look as though I had not looked closer"]
        )
        XCTAssertEqual(
            ClauseJuxtaposition.pieces(in: "The old poster faded set the timer"),
            ["The old poster faded", "set the timer"]
        )
        XCTAssertEqual(
            ClauseJuxtaposition.pieces(in: "The old set would look wrong set the timer"),
            ["The old set would look wrong", "set the timer"]
        )
    }

    func testCompletedReportedQuoteReleasesIndependentNextSentence() {
        XCTAssertEqual(
            RuleBasedThoughtExtractor.splitClauses(
                "The actor said, 'Open the gate.' Lock the shed tomorrow."
            ),
            ["The actor said, 'Open the gate.'", "Lock the shed tomorrow"]
        )
        XCTAssertEqual(
            RuleBasedThoughtExtractor.splitClauses(
                "The guide said 'Keep the map.' The room has a blue door."
            ),
            ["The guide said 'Keep the map.'", "The room has a blue door"]
        )
        XCTAssertEqual(
            RuleBasedThoughtExtractor.splitClauses(
                "Rosa said, 'Call me after lunch.' She was describing her manager's old demand."
            ),
            ["Rosa said, 'Call me after lunch.' She was describing her manager's old demand"]
        )
    }

    func testFrontedTimeStaysWithFollowingInstruction() {
        XCTAssertEqual(
            RuleBasedThoughtExtractor.splitClauses("After lunch, call Theo and book the dentist"),
            ["After lunch, call Theo", "book the dentist"]
        )
    }

    func testWordedFrontedClockStaysWithItsOwnReminder() {
        let paired = "Tomorrow at nine in the morning remind me to phone the bike shop, and at three in the afternoon remind me to collect the repaired wheel"
        let repair = SpeechRepairPipeline.run(paired, trackOrigins: true)
        XCTAssertEqual(repair.corrected, paired)
        XCTAssertTrue(
            SpeechRepairPipeline.run(
                "The meeting is tomorrow morning remind me Thursday at five to call Sam",
                trackOrigins: true
            ).corrected.contains("morning, remind me")
        )
        XCTAssertEqual(
            ClauseJuxtaposition.pieces(in: "Tomorrow at nine in the morning remind me to phone the bike shop"),
            ["Tomorrow at nine in the morning remind me to phone the bike shop"]
        )
        XCTAssertEqual(
            ClauseJuxtaposition.pieces(in: "at three in the afternoon remind me to collect the repaired wheel"),
            ["at three in the afternoon remind me to collect the repaired wheel"]
        )
        XCTAssertEqual(
            RuleBasedThoughtExtractor.splitClauses(paired),
            [
                "Tomorrow at nine in the morning remind me to phone the bike shop",
                "at three in the afternoon remind me to collect the repaired wheel"
            ]
        )
        XCTAssertEqual(
            RuleBasedThoughtExtractor.splitClauses(
                "Sam said tomorrow at nine in the morning remind me to phone the bike shop and at three in the afternoon remind me to collect the wheel"
            ).count,
            1
        )
    }

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
        XCTAssertEqual(
            DisfluencyFilter.stripped("Call Nora. Um, the key is under the mat."),
            "Call Nora. the key is under the mat."
        )
        XCTAssertEqual(
            RuleBasedThoughtExtractor.splitClauses("Call Nora. the key is under the mat."),
            ["Call Nora", "the key is under the mat"]
        )
        XCTAssertEqual(
            RuleBasedThoughtExtractor.splitClauses("Buy stamps. the parcel label has a code."),
            ["Buy stamps", "the parcel label has a code"]
        )
        XCTAssertEqual(RuleBasedThoughtExtractor.splitClauses("Call Dr. Rivera tomorrow"),
                       ["Call Dr. Rivera tomorrow"])
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

    func testHesitationDoesNotBreakCommandComplementsFromMergedMain() {
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

    func testListIntroductionNeedsAnOrdinalAndFollowingActionFromMergedMain() {
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

    func testRepeatedUnfinishedTravelFrameKeepsContextFromMergedMain() {
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

    func testLaterUnrelatedMarkerDoesNotBlockEarlierDateCorrection() {
        let source = "Call Mara on Tuesday, actually Thursday, about the contract. "
            + "Buy printer ink and envelopes. No, skip the envelopes."
        let repaired = SelfCorrectionResolver.resolved(source)
        XCTAssertTrue(repaired.contains("Call Mara on Thursday"))
        XCTAssertFalse(repaired.contains("Call Mara on Tuesday"))
        XCTAssertTrue(repaired.contains("Buy printer ink and envelopes"))
    }

    func testOrdinaryActuallyInLaterSentenceDoesNotRewriteFirstAction() {
        let source = "Call Mara on Tuesday. The client actually approved the contract."
        XCTAssertEqual(SelfCorrectionResolver.resolved(source), source)
    }

    func testConditionalMakeThatKeepsItsConditionAndOrdinaryRepairStillWorks() {
        let conditional = "If cancellation cannot be applied safely, make that limitation visible."
        XCTAssertEqual(SelfCorrectionResolver.resolved(conditional), conditional)
        let lowercased = "cancel the saved reminder. if cancellation cannot be applied safely, make that limitation visible."
        XCTAssertEqual(SelfCorrectionResolver.resolved(lowercased), lowercased)
        let unpunctuated = "cancel the saved reminder if cancellation cannot be applied safely make that limitation visible"
        XCTAssertEqual(SelfCorrectionResolver.resolved(unpunctuated), unpunctuated)
        XCTAssertEqual(
            SelfCorrectionResolver.resolved("Remind me at six, make that seven"),
            "Remind me at seven"
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
            // The tentative proposal remains intact under the newer contract.
            ("I was thinking it might make sense to add a dark mode",
             "I was thinking it might make sense to add a dark mode"),
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
    /// The abstention is the **first** statement here, and an earlier draft had
    /// it between the two assertions so that the string half would still report
    /// on a blind image. That design rested on XCTest recording a failure which
    /// happened before a test throws `XCTSkip`, and nothing in this project
    /// establishes that it does — the suite's only other skips,
    /// `TemporalFullPathTests.swift:157` and `:1055`, are both the first line
    /// of their test. Asserting a framework's ordering from memory is how a
    /// regression in `DisfluencyFilter.stripped` would get reported as a skip,
    /// which is this file's own failure mode turned on itself.
    ///
    /// Nothing is lost by not depending on it. The string claim is asserted by
    /// `testThroatClearingStillComesOff`, which has no skip in it, so removing
    /// the trailing `\S` still fails a test that always runs. This one owns
    /// the second link only, and is still a chain: the repair's output is what
    /// it feeds to the reader.
    func testTheRepairAndTheFragmentRuleAreOneChain() throws {
        try LexicalTagging.skipIfBlind()
        let abandoned = DisfluencyFilter.stripped("I was thinking about")
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
    /// The nil assertion abstains where the tagger is blind, and this one is
    /// the reason the helper exists rather than a convenience. It **passed** on
    /// run 35124466497, and it passed for a reason that has nothing to do with
    /// the hedge: with no lexical model `unfinished` returns nil for every
    /// sentence it does not decide on the word "to", so the assertion could not
    /// have failed there whatever the repair produced. A guard that cannot fire
    /// looks exactly like a guard that holds, and a green tick here was the
    /// more dangerous of the two results that run produced.
    /// Skip first, for the reason given above. `testContemplationIsNotThroatClearing`
    /// asserts that the hedge survives the repair and never abstains, so this
    /// test owns only the reading of what survived.
    func testThePreservedHedgeIsNotReadAsUnfinished() throws {
        try LexicalTagging.skipIfBlind()
        let kept = DisfluencyFilter.stripped("I was thinking of calling Priya")
        XCTAssertNil(
            ThoughtCompletion.unfinished(in: kept),
            "a preserved hedge is a finished sentence, not a trailing fragment"
        )
    }

    func testPrepositionalArtifactHeadKeepsItsConstraintWithoutOpeningACommand() throws {
        let previous = SentenceContext.taggerDisabledForEvaluation
        defer {
            SentenceContext.taggerDisabledForEvaluation = previous
            SentenceContextCache.invalidate()
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Toronto"))
        let reference = try XCTUnwrap(calendar.date(from:
            DateComponents(year: 2026, month: 11, day: 16, hour: 9)))
        for disabled in [false, true] {
            SentenceContext.taggerDisabledForEvaluation = disabled
            SentenceContextCache.invalidate()
            for source in [
                "And take before photos of the whole bathroom for the insurance file before anything gets ripped out.",
                "Take photos for the renovation file before the work starts.",
                "Take photos for the home insurance file before the work starts."
            ] {
                XCTAssertEqual(ClauseJuxtaposition.pieces(in: source), [source], source)
                var trace: RuntimeRuleTrace?
                let result = RuleBasedThoughtExtractor.process(source, referenceDate: reference,
                    calendar: calendar, traceObserver: { trace = $0 })
                XCTAssertTrue(result.operations.isEmpty)
                XCTAssertEqual(result.items.count, 1, String(reflecting: result))
                let item = try XCTUnwrap(result.items.first)
                XCTAssertEqual(item.organization.itemType, .task)
                XCTAssertFalse(item.needsReview)
                XCTAssertTrue(item.analysisText.localizedCaseInsensitiveContains("file before"))
                XCTAssertTrue(item.sourceQuote.localizedCaseInsensitiveContains("file before"))
                XCTAssertTrue(item.rawQuote.localizedCaseInsensitiveContains("file before"))
                XCTAssertNil(item.organization.dueDate)
                XCTAssertNil(item.organization.reminderDate)
                XCTAssertNil(item.organization.personName)
                XCTAssertNil(item.organization.locationIntent)
                let traced = try XCTUnwrap(trace)
                let ledger = SourceUnitLedger(traced.creating)
                XCTAssertTrue(ledger.unownedMeaningfulIDs(after: result.items).isEmpty)
                let object = try XCTUnwrap(traced.creating.range(of: "for "))
                XCTAssertTrue(ledger.ids(in: object.lowerBound..<traced.creating.endIndex)
                    .isSubset(of: item.sourceUnitIDs))
            }
            for (source, expected) in [
                ("Take photos for the insurer file the claim before demolition starts.",
                 ["Take photos for the insurer", "file the claim before demolition starts."]),
                ("Take photos for the insurer file them before demolition starts.",
                 ["Take photos for the insurer", "file them before demolition starts."]),
                ("Take photos for the insurer call before demolition starts.",
                 ["Take photos for the insurer", "call before demolition starts."])
            ] {
                XCTAssertEqual(ClauseJuxtaposition.pieces(in: source), expected, source)
            }
            for source in [
                "Take photos for the insurer; file the claim before demolition starts.",
                "Take photos for the insurance file and call Marco."
            ] {
                let result = ThoughtExtractionEngine.extractWithRules(source,
                    referenceDate: reference, calendar: calendar)
                XCTAssertEqual(result.items.count, 2, String(reflecting: result))
                XCTAssertTrue(result.items.contains {
                    $0.analysisText.lowercased().hasPrefix(source.contains(";") ? "file" : "call")
                }, source)
            }
            for (source, expected) in [
                ("Take photos for the renovation file before closing; call Ann, no, call Jim.", true),
                ("Take photos for the renovation file before closing and call Ann, no, call Jim.", true),
                ("Take photos for the renovation file before closing, no, actually after closing.", false)
            ] {
                let head = try XCTUnwrap(source.range(of: "file before"))
                XCTAssertEqual(ClauseJuxtaposition.isPrepositionalFileObject(in: source,
                    at: head.lowerBound, from: source.startIndex), expected, source)
            }
            let coordinatedFile = "Take photos for the claim and file before demolition starts."
            let coordinatedParts = RuleBasedThoughtExtractor.splitClauses(coordinatedFile)
            XCTAssertEqual(coordinatedParts.count, 2, coordinatedParts.joined(separator: " | "))
            XCTAssertTrue(coordinatedParts.contains { $0.lowercased().hasPrefix("file before") })
            for source in [
                "Marco said, ‘Take photos for the insurance file before anything gets ripped out.’",
                "Do not take photos for the insurance file before anything gets ripped out.",
                "If Marco asks, take photos for the insurance file before anything gets ripped out."
            ] {
                let result = ThoughtExtractionEngine.extractWithRules(source,
                    referenceDate: reference, calendar: calendar)
                XCTAssertFalse(result.items.contains {
                    $0.organization.itemType.isActionable && $0.analysisText.lowercased().hasPrefix("file")
                }, source)
            }
        }
    }
}


extension SpeechRepairTests {
    func testDatedIndependentCommandCannotSupplyAContactAdjunctsFinitePredicate() throws {
        let previous=SentenceContext.taggerDisabledForEvaluation,previousZone=NSTimeZone.default
        var calendar=Calendar(identifier:.gregorian)
        calendar.timeZone=try XCTUnwrap(TimeZone(identifier:"America/Toronto"))
        NSTimeZone.default=calendar.timeZone
        defer {
            NSTimeZone.default=previousZone
            SentenceContext.taggerDisabledForEvaluation=previous
            SentenceContextCache.invalidate()
        }
        let reference=try XCTUnwrap(calendar.date(from:DateComponents(year:2026,month:8,day:3,hour:10)))
        let source="Call Sarah Monday, actually Tuesday buy milk."
        for disabled in [false,true] {
            SentenceContext.taggerDisabledForEvaluation=disabled;SentenceContextCache.invalidate()
            let mode="taggerDisabled=\(disabled)"
            XCTAssertEqual(SelfCorrectionResolver.resolved(source),source,mode)
            XCTAssertEqual(ClauseScope.read(source).act,.direct,mode)
            XCTAssertEqual(RuleBasedThoughtExtractor.splitClauses(source),
                ["Call Sarah Monday","actually Tuesday buy milk"],mode)
            let result=ThoughtExtractionEngine.extractWithRules(source,referenceDate:reference,calendar:calendar)
            XCTAssertEqual(result.items.count,2,mode)
            let call=try XCTUnwrap(result.items.first,mode),purchase=try XCTUnwrap(result.items.last,mode)
            XCTAssertEqual(call.organization.itemType,.personFollowUp,mode)
            XCTAssertEqual(call.organization.personName,"Sarah",mode)
            XCTAssertEqual(purchase.organization.itemType,.shopping,mode)
            XCTAssertEqual(call.sourceQuote,"Call Sarah Monday",mode)
            XCTAssertEqual(purchase.sourceQuote,"actually Tuesday buy milk",mode)
            XCTAssertEqual(purchase.analysisText,"actually Tuesday buy milk",mode)
            XCTAssertEqual(calendar.component(.weekday,from:try XCTUnwrap(call.organization.dueDate)),2,mode)
            XCTAssertEqual(calendar.component(.weekday,from:try XCTUnwrap(purchase.organization.dueDate)),3,mode)
            XCTAssertEqual(call.sourceUnitIDs,Set(0...2),mode)
            XCTAssertEqual(purchase.sourceUnitIDs,Set(3...6),mode)
            XCTAssertTrue(call.sourceUnitIDs.isDisjoint(with:purchase.sourceUnitIDs),mode)
            XCTAssertEqual(call.sourceUnitIDs.union(purchase.sourceUnitIDs),Set(SourceUnitLedger(source).words.indices),mode)
            XCTAssertNil(purchase.organization.personName,mode)
            XCTAssertTrue(result.operations.isEmpty,mode)
            for item in result.items {
                XCTAssertEqual(item.organization.state,.resolved,mode)
                XCTAssertEqual(item.organization.temporalIntent.kind,.dateOnly,mode)
                XCTAssertFalse(item.needsReview,mode);XCTAssertFalse(item.organization.needsClarification,mode)
                XCTAssertNil(item.organization.reminderDate,mode)
                XCTAssertEqual(item.organization.reminderDelivery,.none,mode)
                XCTAssertNil(item.organization.locationIntent,mode)
                XCTAssertNil(item.organization.recurrenceRule,mode)
            }
            let onMonday="Call Sarah on Monday, actually Tuesday buy milk."
            XCTAssertEqual(SelfCorrectionResolver.resolved(onMonday),onMonday,mode)
            XCTAssertEqual(ClauseScope.read(onMonday).act,.direct,mode)
            XCTAssertEqual(RuleBasedThoughtExtractor.splitClauses(onMonday),
                ["Call Sarah on Monday","actually Tuesday buy milk"],mode)
            let onResult=ThoughtExtractionEngine.extractWithRules(onMonday,referenceDate:reference,calendar:calendar)
            XCTAssertEqual(onResult.items.count,2,mode)
            let onCall=try XCTUnwrap(onResult.items.first,mode),onPurchase=try XCTUnwrap(onResult.items.last,mode)
            XCTAssertEqual(onCall.sourceQuote,"Call Sarah on Monday",mode)
            XCTAssertEqual(onPurchase.sourceQuote,"actually Tuesday buy milk",mode)
            XCTAssertEqual(calendar.component(.weekday,from:try XCTUnwrap(onCall.organization.dueDate)),2,mode)
            XCTAssertEqual(calendar.component(.weekday,from:try XCTUnwrap(onPurchase.organization.dueDate)),3,mode)
            XCTAssertEqual(onCall.sourceUnitIDs,Set(0...3),mode)
            XCTAssertEqual(onPurchase.sourceUnitIDs,Set(4...7),mode)
            XCTAssertTrue(onCall.sourceUnitIDs.isDisjoint(with:onPurchase.sourceUnitIDs),mode)
            XCTAssertEqual(onCall.sourceUnitIDs.union(onPurchase.sourceUnitIDs),
                Set(SourceUnitLedger(onMonday).words.indices),mode)
            let opposite="Text Sarah Monday, actually Tuesday works"
            // Frozen native scope is communicating and forced-missing scope
            // is direct; both retain this same whole literal clause. No
            // imperative follows the second date in this established opposite.
            XCTAssertEqual(RuleBasedThoughtExtractor.splitClauses(opposite),[opposite],mode)
            XCTAssertEqual(SelfCorrectionResolver.resolved(opposite),"Text Sarah Tuesday works",mode)
            // Complete finite and explicit quoted bodies remain messages.
            // These assert the source-scope gate, without inventing new output
            // counts for unrelated legacy message continuations.
            for message in [
                "Text Sam Monday is the deadline, actually Tuesday buy milk.",
                "Tell Sam that Monday is the deadline, actually Tuesday buy milk.",
                "Tell Sam 'Monday, actually Tuesday buy milk.'"
            ] {
                XCTAssertEqual(ClauseScope.read(message).act,.communicating,mode+": "+message)
            }
            XCTAssertEqual(ClauseScope.read("Pat said call Sarah Monday, actually Tuesday buy milk.").act,
                .reporting,mode)
        }
    }
}


extension SpeechRepairTests {
    func testPairedCallDetailProtectsOnlyItsExactSourceBoundAskCut() throws {
        let previous = SentenceContext.taggerDisabledForEvaluation
        defer { SentenceContext.taggerDisabledForEvaluation = previous; SentenceContextCache.invalidate() }
        let source = "tomorrow at nine remind me to phone the repair shop and at three remind me to collect the repaired chair both are tomorrow but they are not the same event the first is a phone call the second is the actual collection for the call ask whether the seal is fitted for collection take the repair receipt"
        let start = try XCTUnwrap(source.range(of: "at three")).lowerBound
        let part = String(source[start...])
        for disabled in [false, true] {
            SentenceContext.taggerDisabledForEvaluation = disabled; SentenceContextCache.invalidate()
            let mode = "taggerDisabled=\(disabled)"
            let detail = try XCTUnwrap(RuleBasedThoughtExtractor.pairedCallDetailRange(in: source, forLiteralPart: part), mode)
            XCTAssertEqual(String(part[detail]), "for the call ask whether the seal is fitted ", mode)
            XCTAssertNil(RuleBasedThoughtExtractor.pairedCallDetailRange(in: part, forLiteralPart: part),
                "The second timed part cannot prove the missing first reminder: " + mode)
            let pieces = ClauseJuxtaposition.pieces(in: part, protectingPairedCallDetail: detail)
            XCTAssertTrue(pieces.contains { $0.contains("for the call ask whether") }, mode)
            XCTAssertFalse(pieces.contains { $0.hasPrefix("ask whether") }, mode)
            XCTAssertEqual(ClauseJuxtaposition.pieces(in: part),
                ClauseJuxtaposition.pieces(in: part, protectingPairedCallDetail: nil), mode)
            let laterSource = source + " call Vera Friday at five in the afternoon"
            let laterPart = part + " call Vera Friday at five in the afternoon"
            let laterDetail = try XCTUnwrap(RuleBasedThoughtExtractor.pairedCallDetailRange(
                in: laterSource, forLiteralPart: laterPart), mode)
            XCTAssertEqual(String(laterPart[laterDetail]), String(part[detail]), mode)
            let later = ClauseJuxtaposition.pieces(in: laterPart, protectingPairedCallDetail: laterDetail)
            XCTAssertTrue(later.contains { $0.hasPrefix("call Vera Friday") }, mode)
            for opposed in [
                "Sam said " + source,
                "If the alarm rings " + source,
                "Don't " + source,
                "Keep a note: '" + source + "'",
                source.replacingOccurrences(of: "phone the repair shop", with: "wash the tools"),
                source.replacingOccurrences(of: "remind me to collect", with: "collect"),
                source + " " + part
            ] {
                XCTAssertNil(RuleBasedThoughtExtractor.pairedCallDetailRange(in: opposed, forLiteralPart: part), mode + opposed)
            }
            XCTAssertNil(RuleBasedThoughtExtractor.pairedCallDetailRange(in: source,
                forLiteralPart: part.replacingOccurrences(of: "the seal", with: "the valve")), mode)
            let commaSource = source.replacingOccurrences(of: "for the call ask", with: "for the call, ask")
            let commaPart = part.replacingOccurrences(of: "for the call ask", with: "for the call, ask")
            XCTAssertNotNil(RuleBasedThoughtExtractor.pairedCallDetailRange(in: commaSource, forLiteralPart: commaPart), mode)
            let commaPieces = RuleBasedThoughtExtractor.splitClauses(commaSource)
            XCTAssertTrue(commaPieces.contains { $0.contains("for the call, ask whether") }, mode)
            XCTAssertFalse(commaPieces.contains { $0.hasPrefix("ask whether the seal") }, mode)
            let outside = source + ", ask whether the office is open"
            let outsidePieces = RuleBasedThoughtExtractor.splitClauses(outside)
            XCTAssertTrue(outsidePieces.contains { $0.hasPrefix("ask whether the office is open") }, mode)
            XCTAssertTrue(outsidePieces.contains { $0.contains("for the call ask whether the seal") }, mode)
        }
    }
}
