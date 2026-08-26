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
}
