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

    // MARK: Somebody else's advice stays held

    /// The rules hold "Sarah said I should call Mike tomorrow at 3" for review
    /// with nothing armed (case 4 of the 2026-09-16 reported-speech ruling),
    /// and a held row invites the model. Splitting the frame into a row of its
    /// own covers every token of the capture, so the quote checks pass, and
    /// the action half organizes on its own words as a task dated tomorrow.
    /// The rules reading has to win, and so it does when the model keeps the
    /// whole quote but hands back the armed organization.
    func testRefinementCannotArmHeldReportedAdvice() throws {
        let transcript = "Sarah said I should call Mike tomorrow at 3"
        let rules = rulesReading(of: transcript)
        let held = try XCTUnwrap(rules.first)
        XCTAssertEqual(rules.count, 1)
        XCTAssertEqual(held.organization.state, .underspecified(.reportedSpeech))

        let action = refined("I should call Mike tomorrow at 3")
        // The canned answer has to be the dangerous one, or the rejection
        // below proves nothing about the guard.
        XCTAssertNotNil(action.organization.dueDate)
        let split = [refined("Sarah said"), action]
        XCTAssertFalse(
            RefinementGuard.preservesEverything(in: split, found: rules),
            "the split handed back a dated task for somebody else's advice"
        )

        let wholeQuoteArmed = ExtractedThought(
            sourceQuote: held.sourceQuote,
            rawQuote: held.rawQuote,
            wasRepaired: held.wasRepaired,
            analysisText: held.analysisText,
            suggestedTitle: "Call Mike",
            organization: action.organization,
            confidence: 0.95,
            needsReview: false
        )
        XCTAssertFalse(RefinementGuard.preservesEverything(in: [wholeQuoteArmed], found: rules))
    }

    /// The control. The same split, with the action half still held and
    /// undated, is a legitimate re-reading and passes. The two refinements
    /// differ only in that row's organization, so the rejection above is the
    /// guard's and not the quote checks'.
    func testRefinementThatKeepsReportedAdviceHeldIsAccepted() throws {
        let rules = rulesReading(of: "Sarah said I should call Mike tomorrow at 3")
        let held = try XCTUnwrap(rules.first)
        let action = refined("I should call Mike tomorrow at 3")
        let stillHeld = ExtractedThought(
            sourceQuote: action.sourceQuote,
            rawQuote: action.rawQuote,
            wasRepaired: action.wasRepaired,
            analysisText: action.analysisText,
            suggestedTitle: "Call Mike",
            organization: held.organization,
            confidence: 0.9,
            needsReview: true
        )
        XCTAssertTrue(RefinementGuard.preservesEverything(
            in: [refined("Sarah said"), stillHeld], found: rules
        ))
    }

    /// The same split on advice that names an alarm. The rules hold it through
    /// the pipeline's safety net rather than the organizer alone, and the net
    /// used to hand the row back as `.resolved`, which this guard did not
    /// read as somebody else's words, and the resolved check could accept a
    /// split in which any one row kept the held row's empty fields.
    func testRefinementCannotArmHeldAdviceThatNamesAnAlarm() throws {
        let rules = rulesReading(of: "Mike told me I should set an alarm for 6")
        let held = try XCTUnwrap(rules.first)
        XCTAssertEqual(rules.count, 1)
        XCTAssertEqual(held.organization.state, .underspecified(.reportedSpeech))

        let action = refined("I should set an alarm for 6")
        // The canned answer has to be the dangerous one, or the rejection
        // below proves nothing about the guard.
        XCTAssertNotNil(action.organization.reminderDate)
        XCTAssertFalse(
            RefinementGuard.preservesEverything(in: [refined("Mike told me"), action], found: rules),
            "the split armed an alarm for somebody else's advice"
        )
    }

    /// Every other hold of the safety net, the same way. A negation the net
    /// keeps as one empty row must not come back from the model as a dated
    /// errand beside a row that keeps the empty fields.
    func testRefinementCannotArmAnythingTheSafetyNetHeld() throws {
        let rules = rulesReading(of: "Don't call Mike tomorrow")
        let held = try XCTUnwrap(rules.first)
        XCTAssertEqual(rules.count, 1)
        XCTAssertTrue(held.needsReview)
        XCTAssertEqual(held.organization.itemType, .unclear)
        XCTAssertNil(held.organization.dueDate)

        let action = refined("call Mike tomorrow")
        // The dangerous answer, or the rejection proves nothing.
        XCTAssertNotNil(action.organization.dueDate)
        // And a frame row the resolved check alone would accept, or the
        // rejection could be that check's rather than the net's.
        let frame = refined("Don't")
        XCTAssertFalse(frame.organization.itemType.isActionable)
        XCTAssertNil(frame.organization.personName)
        XCTAssertFalse(
            RefinementGuard.preservesEverything(in: [refined("Don't"), action], found: rules),
            "the split turned a negation into a dated errand"
        )

        // The control: the same split with nothing armed on either row is a
        // re-reading the guard still lets through.
        let stillHeld = ExtractedThought(
            sourceQuote: action.sourceQuote,
            rawQuote: action.rawQuote,
            wasRepaired: action.wasRepaired,
            analysisText: action.analysisText,
            suggestedTitle: nil,
            organization: held.organization,
            confidence: 0.9,
            needsReview: true
        )
        XCTAssertTrue(RefinementGuard.preservesEverything(
            in: [refined("Don't"), stillHeld], found: rules
        ))
    }

    /// A row that matches no rules row at all is the last way in: a quote of
    /// filler alone, grounded because "Don't" normalizes to "don t", carrying
    /// the errand in its context. Beside a held row it may not arm anything.
    func testAnUnmatchedRowCannotArmACaptureTheSafetyNetHeld() throws {
        let rules = rulesReading(of: "Don't call Mike tomorrow")
        let held = try XCTUnwrap(rules.first)
        XCTAssertEqual(rules.count, 1)

        let smuggled = refined("t", context: "call Mike tomorrow")
        XCTAssertNotNil(smuggled.organization.dueDate)
        XCTAssertFalse(
            RefinementGuard.preservesEverything(in: [held, smuggled], found: rules),
            "a filler row carried a dated errand past the held negation"
        )
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

/// The refinement budget caps how long a capture waits for the model. The
/// model call is stood in for by work that ignores cancellation, which is the
/// case the task group this replaced could not bound: it waited for every
/// child, so a model that kept going held the capture past the budget. Two of
/// these fail under that task group (the budget and the cancelled capture
/// ending the wait); the rest pin the behaviour around them.
final class BudgetedWorkTests: XCTestCase {

    /// Work that pays no attention to cancellation and answers after `delay`.
    private static func stubborn(_ value: Int, after delay: TimeInterval) async -> Int? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().asyncAfter(deadline: .now() + delay) {
                continuation.resume(returning: value)
            }
        }
    }

    func testTheBudgetEndsTheWaitEvenWhenTheWorkIgnoresCancellation() async {
        let clock = ContinuousClock()
        let start = clock.now
        let result = await BudgetedWork.firstResult(within: .milliseconds(200)) {
            await BudgetedWorkTests.stubborn(1, after: 5)
        }
        XCTAssertNil(result, "An answer that came after the budget has to be dropped")
        XCTAssertLessThan(
            clock.now - start, .seconds(2),
            "The capture waited for the work instead of the budget"
        )
    }

    func testAnAnswerInsideTheBudgetDoesNotWaitOutTheBudget() async {
        let clock = ContinuousClock()
        let start = clock.now
        let result = await BudgetedWork.firstResult(within: .seconds(10)) { () async -> Int? in 42 }
        XCTAssertEqual(result, 42)
        XCTAssertLessThan(
            clock.now - start, .seconds(5),
            "A finished answer waited out the rest of the budget"
        )
    }

    func testANilAnswerInsideTheBudgetEndsTheWaitAtOnce() async {
        let clock = ContinuousClock()
        let start = clock.now
        let result = await BudgetedWork.firstResult(within: .seconds(10)) { () async -> Int? in nil }
        XCTAssertNil(result)
        XCTAssertLessThan(
            clock.now - start, .seconds(5),
            "A model that declined waited out the rest of the budget"
        )
    }

    func testCancellingTheCaptureEndsTheWait() async {
        let clock = ContinuousClock()
        let start = clock.now
        let waiting = Task {
            await BudgetedWork.firstResult(within: .seconds(10)) {
                await BudgetedWorkTests.stubborn(1, after: 5)
            }
        }
        waiting.cancel()
        let result = await waiting.value
        XCTAssertNil(result)
        XCTAssertLessThan(
            clock.now - start, .seconds(2),
            "A cancelled capture kept waiting for the work"
        )
    }

    func testTheWorkThatLostIsCancelled() async {
        let recorder = EventRecorder()
        let result = await BudgetedWork.firstResult(within: .milliseconds(100)) { () async -> Int? in
            do {
                try await Task.sleep(for: .seconds(30))
                return 1
            } catch {
                await recorder.record()
                return nil
            }
        }
        XCTAssertNil(result)
        var polls = 0
        while !(await recorder.happened), polls < 40 {
            polls += 1
            try? await Task.sleep(for: .milliseconds(50))
        }
        let cancelled = await recorder.happened
        XCTAssertTrue(cancelled, "The work past the budget was left running uncancelled")
    }

    /// The budget stops the wait, not the work, so an abandoned call can
    /// still be running when the next capture asks. It gets nothing at once
    /// rather than a second call beside the first, and the token comes back
    /// when the abandoned work ends.
    func testASecondCallIsRefusedWhileAnAbandonedOneStillRuns() async {
        let token = InFlightToken(staleAfter: .seconds(60))
        let first = await BudgetedWork.firstResult(within: .milliseconds(100), oneAtATime: token) {
            await BudgetedWorkTests.stubborn(1, after: 3)
        }
        XCTAssertNil(first)

        let clock = ContinuousClock()
        let start = clock.now
        let second = await BudgetedWork.firstResult(within: .seconds(5), oneAtATime: token) { () async -> Int? in 2 }
        XCTAssertNil(second, "A second call started while the abandoned one still ran")
        XCTAssertLessThan(
            clock.now - start, .seconds(1),
            "A refused call waited instead of answering at once"
        )

        var third: Int?
        var polls = 0
        while third == nil, polls < 120 {
            polls += 1
            try? await Task.sleep(for: .milliseconds(50))
            third = await BudgetedWork.firstResult(within: .seconds(1), oneAtATime: token) { () async -> Int? in 3 }
        }
        XCTAssertEqual(third, 3, "The token never came back after the abandoned work ended")
    }

    func testACancelledCaptureNeverStartsTheWork() async {
        let token = InFlightToken(staleAfter: .seconds(60))
        let recorder = EventRecorder()
        let waiting = Task { () async -> Int? in
            withUnsafeCurrentTask { $0?.cancel() }
            return await BudgetedWork.firstResult(within: .seconds(10), oneAtATime: token) { () async -> Int? in
                await recorder.record()
                return 1
            }
        }
        let result = await waiting.value
        XCTAssertNil(result)
        let started = await recorder.happened
        XCTAssertFalse(started, "A capture cancelled before the call still started it")
        XCTAssertNotNil(token.claim(), "A capture that never ran the work kept the token")
    }

    /// A capture cancelled after it claimed the token has already started
    /// the work, and only the work gives the token back. It must still do so.
    func testACaptureCancelledMidCallStillGivesTheTokenBack() async {
        let token = InFlightToken(staleAfter: .seconds(60))
        let waiting = Task {
            await BudgetedWork.firstResult(within: .seconds(10), oneAtATime: token) {
                await BudgetedWorkTests.stubborn(1, after: 0.5)
            }
        }
        try? await Task.sleep(for: .milliseconds(50))
        // Otherwise the cancellation could land before the claim, and the
        // test would pass without ever taking the path it is about.
        XCTAssertNil(token.claim(), "The call had not claimed the token before the cancellation")
        waiting.cancel()
        let result = await waiting.value
        XCTAssertNil(result)

        var claimed: InFlightToken.Claim?
        var polls = 0
        while claimed == nil, polls < 60 {
            polls += 1
            try? await Task.sleep(for: .milliseconds(50))
            claimed = token.claim()
        }
        XCTAssertNotNil(claimed, "A capture cancelled mid-call kept the token")
    }

    /// A call that never returns must not turn refinement off for good.
    func testAClaimThatNeverEndsIsTakenOverAfterItsDeadline() async {
        let takeovers = EventRecorder()
        let token = InFlightToken(staleAfter: .seconds(3)) {
            _ = Task { await takeovers.record() }
        }
        let stuck = token.claim()
        XCTAssertNotNil(stuck)
        XCTAssertNil(token.claim(), "A second claim was admitted beside a live one")

        try? await Task.sleep(for: .milliseconds(3_200))
        let fresh = token.claim()
        XCTAssertNotNil(fresh, "A call that never ended held the token for good")
        if let stuck { token.release(stuck) }
        XCTAssertNil(
            token.claim(),
            "A late release from the abandoned call freed its replacement's claim"
        )
        var polls = 0
        while !(await takeovers.happened), polls < 40 {
            polls += 1
            try? await Task.sleep(for: .milliseconds(50))
        }
        let observed = await takeovers.happened
        XCTAssertTrue(observed, "A takeover happened and nothing could see it")
    }
}

private actor EventRecorder {
    private(set) var happened = false

    func record() {
        happened = true
    }
}
