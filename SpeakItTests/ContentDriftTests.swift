import XCTest
@testable import SpeakIt

/// Asserts that the words a person is shown are words they said.
///
/// Why this suite exists
/// ---------------------
/// The pipeline repairs speech before it understands it, and `sourceQuote` —
/// the field whose entire job is to show the person their own words — was cut
/// from the *repaired* string. Repairs are right to run; the problem is that
/// nothing recorded when one had changed a quote, so there was no way to tell a
/// good repair from a lost word. `TranscriptProvenance` aligns the repaired
/// text back onto the raw transcript, and every row now carries the raw span it
/// came from and whether anything inside it changed.
///
/// What is gated
/// -------------
/// Two different promises, measured apart.
///
/// The **quote** promises fidelity. A token in it that the person never said is
/// a defect unless the row records that a repair ran in its span. That is the
/// gate, and it runs over every utterance in the corpus.
///
/// The **title** promises readability, and the product contract has it
/// paraphrase: "Remind me not to text Dave" is shown as "Don't text Dave",
/// which introduces a word nobody said, on purpose. Counting that as drift
/// would make the gate meaningless, so it is reported and never gates.
///
/// The test deliberately reads `SwiftDataThoughtRepository`'s own display path
/// rather than the raw fields. A preservation test that inspects an optional
/// nobody renders can pass while the thing on screen is wrong.
@MainActor
final class ContentDriftTests: XCTestCase {

    func testRawOccurrenceDiagnosticDetectsARepeatedIntentionRemovedBeforeExtraction() {
        let missing = TranscriptProvenance(
            raw: "Buy milk and buy milk", repaired: "Buy milk"
        ).rawWordsWithoutOrigin()
        XCTAssertEqual(missing.map(\.text), ["and", "buy", "milk"])
        XCTAssertEqual(missing.map(\.id), [2, 3, 4])
        XCTAssertTrue(TranscriptProvenance(
            raw: "Buy milk and buy milk", repaired: "Buy milk and buy milk"
        ).rawWordsWithoutOrigin().isEmpty)
    }

    func testMovedCorrectionWordKeepsItsExactRawOccurrence() {
        let raw = "Text Siobhan about the tickets, sorry Priya"
        let repaired = "Text Priya about the tickets"
        let provenance = TranscriptProvenance(raw: raw, repaired: repaired)
        let missing = provenance.rawWordsWithoutOrigin().map(\.text)
        XCTAssertTrue(missing.contains("siobhan"))
        XCTAssertTrue(missing.contains("sorry"))
        XCTAssertFalse(missing.contains("priya"))
        XCTAssertEqual(provenance.rawSpan(for: repaired.startIndex..<repaired.endIndex), raw)
    }

    private static let referenceDate: Date = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Toronto")!
        return calendar.date(from: DateComponents(
            year: 2026, month: 8, day: 3, hour: 10, minute: 0
        ))!
    }()

    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Toronto")!
        return calendar
    }

    private func words(_ text: String) -> Set<String> {
        Set(
            text.lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { $0.count > 1 }
        )
    }

    func testNoRowQuotesAWordThePersonNeverSaid() {
        var offenders: [String] = []
        var rows = 0
        var explained = 0
        var paraphrasedTitles = 0

        for testCase in CorpusEvaluator.allCases {
            let result = ThoughtExtractionEngine.extractWithRules(
                testCase.utterance,
                referenceDate: Self.referenceDate,
                calendar: Self.calendar
            )
            let said = words(testCase.utterance)

            for item in result.items {
                rows += 1
                if !words(CorpusEvaluator.displayTitle(for: item)).subtracting(said).isEmpty {
                    paraphrasedTitles += 1
                }

                let invented = words(item.sourceQuote).subtracting(said)
                guard !invented.isEmpty else { continue }
                if item.wasRepaired {
                    explained += 1
                    continue
                }
                offenders.append("""
                  "\(testCase.utterance)"
                     quoted but never said: \(invented.sorted().joined(separator: ", "))
                     quote: \(item.sourceQuote)
                     raw:   \(item.rawQuote)
                """)
            }
        }

        XCTAssertGreaterThan(rows, 1_000, "The corpus should produce a row for nearly every case; a collapsed run would make this suite vacuous.")

        guard offenders.isEmpty else {
            return XCTFail("""

            CONTENT DRIFT — \(rows) rows over \(CorpusEvaluator.allCases.count) utterances
            \(offenders.count) quote(s) hold a word the person never said, with no repair recorded.

            \(offenders.joined(separator: "\n"))

            For reference: \(explained) quote(s) differ from their raw span and do
            record a repair, and \(paraphrasedTitles) title(s) paraphrase, which the
            contract allows.
            """)
        }
    }

    /// The raw span is the point of the whole mechanism, so it has to be
    /// populated for real rather than defaulting to the repaired quote and
    /// making the suite above tautological.
    func testEveryRowCarriesARawSpanFromTheTranscript() {
        var checked = 0
        for testCase in CorpusEvaluator.allCases {
            let result = ThoughtExtractionEngine.extractWithRules(
                testCase.utterance,
                referenceDate: Self.referenceDate,
                calendar: Self.calendar
            )
            let said = words(testCase.utterance)
            for item in result.items where !item.rawQuote.isEmpty {
                checked += 1
                // Every word of the raw span must come from the transcript.
                // Unlike the quote there is no repair that can excuse this one:
                // the span is by construction a slice of what was said.
                let strayWords = words(item.rawQuote).subtracting(said)
                XCTAssertTrue(
                    strayWords.isEmpty,
                    "rawQuote for \"\(testCase.utterance)\" holds \(strayWords.sorted()) which is not in the transcript"
                )
            }
        }
        XCTAssertGreaterThan(checked, 1_000)
    }

    // MARK: - The alignment itself

    func testSourceCoverageUsesOccurrencesAndHoldsAnOmittedRepeatedAction() {
        let source = "Call Mom tomorrow and call Mom Friday"
        let items = RuleBasedThoughtExtractor.process(
            source, referenceDate: Self.referenceDate, calendar: Self.calendar
        ).items
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(
            RuleBasedThoughtExtractor.auditSourceCoverage(items, source: source).count, 2
        )

        let incomplete = RuleBasedThoughtExtractor.auditSourceCoverage(
            Array(items.prefix(1)), source: source
        )
        XCTAssertEqual(incomplete.count, 2)
        XCTAssertTrue(incomplete.last?.needsReview == true)
        XCTAssertEqual(incomplete.last?.organization.itemType, .unclear)
        XCTAssertTrue(incomplete.last?.sourceQuote.lowercased().contains("friday") == true)
    }

    func testSourceCoverageLeavesACompleteShortCaptureAlone() {
        let source = "Buy milk tomorrow"
        let items = RuleBasedThoughtExtractor.process(
            source, referenceDate: Self.referenceDate, calendar: Self.calendar
        ).items
        XCTAssertEqual(items.count, 1)
        XCTAssertFalse(items[0].needsReview)
        XCTAssertEqual(
            RuleBasedThoughtExtractor.auditSourceCoverage(items, source: source), items
        )
    }

    func testClaimedLeadFactIsVisibleInTheOwningRowsSourceQuote() throws {
        let spoken = "While I'm here, Mina said she prefers diagrams with labels under them "
            + "rather than legends off to the side; that is useful to remember for future work."
        let items = RuleBasedThoughtExtractor.process(
            spoken, referenceDate: Self.referenceDate, calendar: Self.calendar
        ).items
        let fact = try XCTUnwrap(items.first { $0.analysisText.contains("prefers diagrams") })
        XCTAssertTrue(fact.sourceQuote.contains("Mina said she prefers diagrams"))
        XCTAssertTrue(fact.rawQuote.contains("Mina said she prefers diagrams"))
        XCTAssertEqual(RuleBasedThoughtExtractor.auditSourceCoverage(items, source: spoken).count,
                       items.count)
        let short = RuleBasedThoughtExtractor.process(
            "Buy milk", referenceDate: Self.referenceDate, calendar: Self.calendar
        ).items
        XCTAssertEqual(short.first?.sourceQuote, "Buy milk")
    }

    func testSingleCorrectedIntentionKeepsTheSpokenReplacementInRawQuote() {
        let source = "Email Jordan about the plan, sorry, email Casey"
        let items = RuleBasedThoughtExtractor.process(
            source, referenceDate: Self.referenceDate, calendar: Self.calendar
        ).items
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].rawQuote, source)
        XCTAssertTrue(items[0].wasRepaired)
        XCTAssertTrue(items[0].rawQuote.contains("Casey"))
    }

    func testTwoDatedStoreTripsKeepTheirOwnProducts() {
        let source = "Tomorrow go to Costco and buy milk. Friday go to Costco and buy eggs."
        let items = RuleBasedThoughtExtractor.process(
            source, referenceDate: Self.referenceDate, calendar: Self.calendar
        ).items
        XCTAssertEqual(items.count, 2, "each dated trip should fold into its own product")
        XCTAssertTrue(items[0].sourceQuote.contains("Tomorrow go to Costco"))
        XCTAssertTrue(items[0].rawQuote.contains("Tomorrow go to Costco and buy milk"))
        XCTAssertTrue(items[0].sourceQuote.contains("milk"))
        XCTAssertFalse(items[0].sourceQuote.contains("Friday go to Costco"))
        XCTAssertFalse(items[0].rawQuote.contains("Friday go to Costco"))
        XCTAssertTrue(items[1].sourceQuote.contains("Friday go to Costco"))
        XCTAssertTrue(items[1].rawQuote.contains("Friday go to Costco and buy eggs"))
        XCTAssertTrue(items[1].sourceQuote.contains("eggs"))
        XCTAssertFalse(items[1].sourceQuote.contains("Tomorrow go to Costco"))
        XCTAssertFalse(items[1].rawQuote.contains("Tomorrow go to Costco"))
        XCTAssertTrue(items.allSatisfy { !$0.needsReview })
    }

    func testFoldedStoreContextRemainsInOneRawQuoteAmongSeveralIntentions() {
        let source = "Tomorrow, call the dentist at 9 AM and then go to Costco and get bread, cheese, and eggs, and then also remind me that I have a meeting at 4:15 PM."
        let items = RuleBasedThoughtExtractor.process(
            source, referenceDate: Self.referenceDate, calendar: Self.calendar
        ).items
        XCTAssertEqual(items.count, 5)
        let storeOwners = items.filter { $0.rawQuote.contains("go to Costco") }
        XCTAssertEqual(storeOwners.count, 1)
        XCTAssertTrue(storeOwners[0].rawQuote.contains("and get bread, cheese, and eggs"))
        XCTAssertEqual(storeOwners[0].shoppingGroup, "Costco")
        XCTAssertFalse(items.first?.rawQuote.contains("go to Costco") ?? true)
    }

    func testStoreTripCannotOwnProductsAcrossAnUnrelatedIntention() {
        let source = "Go to Costco. Call Mom. Buy bread."
        let items = RuleBasedThoughtExtractor.process(
            source, referenceDate: Self.referenceDate, calendar: Self.calendar
        ).items
        XCTAssertEqual(items.count, 3)
        XCTAssertTrue(items[0].sourceQuote.contains("Go to Costco"))
        XCTAssertEqual(items[1].organization.itemType, .personFollowUp)
        XCTAssertEqual(items[2].shoppingGroup, "Groceries")
        XCTAssertEqual(items[2].rawQuote, "Buy bread.")
    }

    func testJoinedTemporalCompoundKeepsBothRawWordsOnItsIntention() {
        let source = "To morrow, call dentist at 9 a m and go Costco and get bread, cheese, and eggs, and also remind me I have meeting at 415 p.m."
        let items = RuleBasedThoughtExtractor.process(
            source, referenceDate: Self.referenceDate, calendar: Self.calendar
        ).items
        XCTAssertEqual(items.count, 6)
        XCTAssertTrue(items[0].rawQuote.hasPrefix("To morrow, call dentist"))
        XCTAssertTrue(items[0].wasRepaired)
        XCTAssertEqual(items[0].organization.itemType, .personFollowUp)

        let provenance = TranscriptProvenance(
            raw: "To morrow, call dentist", repaired: "Tomorrow, call dentist"
        )
        XCTAssertTrue(provenance.rawWordsWithoutOrigin().isEmpty)
        XCTAssertEqual(provenance.rawSpan(
            for: provenance.repaired.startIndex..<provenance.repaired.endIndex
        ), "To morrow, call dentist")
    }

    func testRepeatedJoinedDatesKeepTheirOwnRawOccurrences() {
        let source = "To morrow call Mom. To morrow call Dad."
        let items = RuleBasedThoughtExtractor.process(
            source, referenceDate: Self.referenceDate, calendar: Self.calendar
        ).items
        XCTAssertEqual(items.count, 2)
        XCTAssertTrue(items[0].rawQuote.hasPrefix("To morrow call Mom"))
        XCTAssertFalse(items[0].rawQuote.contains("Dad"))
        XCTAssertTrue(items[1].rawQuote.hasPrefix("To morrow call Dad"))
        XCTAssertFalse(items[1].rawQuote.contains("Mom"))
        XCTAssertTrue(items.allSatisfy(\.wasRepaired))
    }

    func testAlignmentReportsASubstitutionAsARepair() {
        let provenance = TranscriptProvenance(
            raw: "Dentist at 230 on Friday",
            repaired: "Dentist at 2:30 on Friday"
        )
        let whole = provenance.repaired.startIndex..<provenance.repaired.endIndex
        XCTAssertTrue(provenance.wasRepaired(in: whole))
        XCTAssertEqual(provenance.rawSpan(for: whole), "Dentist at 230 on Friday")
    }

    func testAlignmentReportsADeletionAsARepair() {
        let provenance = TranscriptProvenance(
            raw: "Um call the uh dentist tomorrow",
            repaired: "call the dentist tomorrow"
        )
        let whole = provenance.repaired.startIndex..<provenance.repaired.endIndex
        XCTAssertTrue(provenance.wasRepaired(in: whole))
    }

    func testAlignmentReportsNoRepairWhenNothingChanged() {
        let provenance = TranscriptProvenance(
            raw: "call the dentist tomorrow",
            repaired: "call the dentist tomorrow"
        )
        let whole = provenance.repaired.startIndex..<provenance.repaired.endIndex
        XCTAssertFalse(provenance.wasRepaired(in: whole))
    }

    func testRawSpanNarrowsToTheClauseAsked() {
        let raw = "um buy milk and call the dentist"
        let repaired = "buy milk and call the dentist"
        let provenance = TranscriptProvenance(raw: raw, repaired: repaired)
        guard let clause = repaired.range(of: "call the dentist") else {
            return XCTFail("fixture no longer contains the clause")
        }
        XCTAssertEqual(provenance.rawSpan(for: clause), "call the dentist")
        XCTAssertFalse(
            provenance.wasRepaired(in: clause),
            "The disfluency was lifted from the other clause, so this one is untouched."
        )
    }

    func testLongCaptureStillAlignsRawWordsPastFormerMatrixLimit() throws {
        let words = (0..<700).map { "item\($0)" }
        let raw = words.joined(separator: " ")
        var repairedWords = words
        repairedWords[350] = "corrected350"
        let repaired = repairedWords.joined(separator: " ")
        let provenance = TranscriptProvenance(raw: raw, repaired: repaired)
        let middle = try XCTUnwrap(repaired.range(of: "corrected350"))
        let tail = try XCTUnwrap(repaired.range(of: "item699"))
        XCTAssertEqual(provenance.rawSpan(for: middle), "item350")
        XCTAssertTrue(provenance.wasRepaired(in: middle))
        XCTAssertEqual(provenance.rawSpan(for: tail), "item699")
        XCTAssertFalse(provenance.wasRepaired(in: tail))
    }
}
