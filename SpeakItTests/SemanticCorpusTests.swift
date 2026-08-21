import XCTest
@testable import SpeakIt

/// Runs the semantic torture corpus and reports failures **clustered by family
/// and by field**.
///
/// The clustering is the design, not a convenience. A flat list of 40 failing
/// sentences invites 40 special cases, which is how a parser rots. A report
/// that says *"Negation: 9 of 12 cases disagree on `count`"* names a single
/// broken rule and one place to fix it.
///
/// A failure here is a disagreement, not automatically a bug. Expectations are
/// authored from the product contract, so each cluster resolves either by
/// changing the rule or by correcting a contract statement that was wrong.
@MainActor
final class SemanticCorpusTests: XCTestCase {

    // MARK: Fixed frame of reference

    /// Monday 2026-08-03 10:00 America/Toronto. Matches the anchor already used
    /// by `SwiftDataThoughtRepositoryTests` so the two suites agree on what
    /// "tomorrow" and "Friday" mean.
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Toronto")!
        return calendar
    }

    private var referenceDate: Date {
        calendar.date(from: DateComponents(
            year: 2026, month: 8, day: 3, hour: 10, minute: 0
        ))!
    }

    // MARK: One failure record

    private struct Disagreement {
        let utterance: String
        let field: String
        let expected: String
        let actual: String
        let note: String?
        let severity: CorpusSeverity
    }

    // MARK: Field comparison

    /// Compares one case against what the engine actually produced.
    private func evaluate(_ testCase: CorpusCase) -> [Disagreement] {
        let result = ThoughtExtractionEngine.extractWithRules(
            testCase.utterance,
            referenceDate: referenceDate,
            calendar: calendar
        )
        let items = result.items
        var found: [Disagreement] = []

        func record(_ field: String, _ expected: String, _ actual: String) {
            var severity = CorpusSeverity.forField(field)
            if let ceiling = testCase.severityCeiling, severity > ceiling {
                severity = ceiling
            }
            found.append(Disagreement(
                utterance: testCase.utterance,
                field: field,
                expected: expected,
                actual: actual,
                note: testCase.note,
                severity: severity
            ))
        }

        // Operations are checked before item count, because a cancellation
        // legitimately creates nothing and the two facts explain each other.
        if let expectedOperations = testCase.operation {
            let actual = result.operations.map(\.operation.rawValue).joined(separator: ",")
            let expected = expectedOperations.map(\.rawValue).joined(separator: ",")
            if actual != expected {
                record("operation", expected.isEmpty ? "none" : expected, actual.isEmpty ? "none" : actual)
            }
        }
        if let expectedTargets = testCase.operationTarget {
            for (index, value) in expectedTargets.enumerated() where index < result.operations.count {
                let actual = result.operations[index].target ?? "nil"
                let expected = value ?? "nil"
                if actual != expected {
                    record("operationTarget", expected, actual)
                }
            }
        }

        if let expectedCount = testCase.count, items.count != expectedCount {
            record("count", "\(expectedCount)", "\(items.count)")
            // Per-item fields cannot be meaningfully compared against a
            // different number of items, so stop here for this case.
            return found
        }

        func each<T>(_ expected: [T]?, _ field: String, _ actual: (ExtractedThought) -> String, _ describe: (T) -> String) {
            guard let expected else { return }
            for (index, value) in expected.enumerated() where index < items.count {
                let actualValue = actual(items[index])
                let expectedValue = describe(value)
                if actualValue != expectedValue {
                    let position = expected.count > 1 ? "[\(index)]" : ""
                    record(field + position, expectedValue, actualValue)
                }
            }
        }

        each(testCase.type, "type", { $0.organization.itemType.rawValue }, { $0.rawValue })
        each(testCase.category, "category", { $0.organization.category.rawValue }, { $0.rawValue })
        each(testCase.priority, "priority", { String($0.organization.priority.rawValue) }, { String($0.rawValue) })
        each(testCase.route, "route", { CorpusRoute($0.organization).rawValue }, { $0.rawValue })
        each(testCase.person, "person", { $0.organization.personName ?? "nil" }, { $0 ?? "nil" })
        each(testCase.delivery, "delivery", { $0.organization.reminderDelivery.rawValue }, { $0.rawValue })
        each(testCase.kind, "temporalKind", { $0.organization.temporalIntent.kind.rawValue }, { $0.rawValue })
        each(testCase.review, "needsReview", { $0.needsReview ? "true" : "false" }, { $0 ? "true" : "false" })
        each(testCase.title, "title", { $0.suggestedTitle ?? $0.sourceQuote }, { $0 })

        for mismatch in compareDates(testCase.due, "dueDate", items, { $0.organization.dueDate }) {
            record(mismatch.0, mismatch.1, mismatch.2)
        }
        for mismatch in compareDates(testCase.remind, "reminderDate", items, { $0.organization.reminderDate }) {
            record(mismatch.0, mismatch.1, mismatch.2)
        }
        each(testCase.recurs, "recurrence", { self.describeRecurrence($0.organization.recurrenceRule) }, { self.describeExpectedRecurrence($0) })
        each(testCase.place, "location", { self.describePlace($0.organization.locationIntent) }, { self.describeExpectedPlace($0) })

        return found
    }

    /// Dates need their own comparison because a *date-only* expectation is
    /// satisfied by any instant on that calendar day. The app stores such a day
    /// as midnight, so rendering both sides the same way would make every
    /// date-only case fail on a time component the contract never asked about.
    private func compareDates(
        _ expected: [CorpusDate?]?,
        _ field: String,
        _ items: [ExtractedThought],
        _ actual: (ExtractedThought) -> Date?
    ) -> [(String, String, String)] {
        var mismatches: [(String, String, String)] = []
        guard let expected else { return mismatches }
        for (index, value) in expected.enumerated() where index < items.count {
            let actualDate = actual(items[index])
            let position = expected.count > 1 ? "[\(index)]" : ""
            let matched: Bool
            if let value {
                if let actualDate {
                    let parts = calendar.dateComponents([.month, .day, .hour, .minute], from: actualDate)
                    if value.hour == nil {
                        matched = parts.month == value.month && parts.day == value.day
                    } else {
                        matched = parts.month == value.month && parts.day == value.day
                            && parts.hour == value.hour && parts.minute == value.minute
                    }
                } else {
                    matched = false
                }
            } else {
                matched = actualDate == nil
            }
            if !matched {
                mismatches.append((field + position, describeExpected(value), describeDate(actualDate)))
            }
        }
        return mismatches
    }

    // MARK: Descriptions
    //
    // Everything is compared as a string so a mismatch reads as a sentence in
    // the report rather than as two opaque struct dumps.

    /// A date-only expectation must not be satisfied by an invented time of
    /// day, so the description keeps the distinction visible.
    private func describeDate(_ date: Date?) -> String {
        guard let date else { return "nil" }
        let parts = calendar.dateComponents([.month, .day, .hour, .minute], from: date)
        return String(format: "%02d-%02d %02d:%02d", parts.month ?? 0, parts.day ?? 0, parts.hour ?? 0, parts.minute ?? 0)
    }

    private func describeExpected(_ expected: CorpusDate?) -> String {
        guard let expected else { return "nil" }
        guard let hour = expected.hour else {
            return String(format: "%02d-%02d (date-only)", expected.month, expected.day)
        }
        return String(format: "%02d-%02d %02d:%02d", expected.month, expected.day, hour, expected.minute)
    }

    private func describeRecurrence(_ rule: RecurrenceRule?) -> String {
        guard let rule else { return "nil" }
        let days = rule.weekdays.isEmpty ? "" : " days\(rule.weekdays.sorted())"
        return "\(rule.frequency.rawValue) x\(rule.interval)\(days)"
    }

    private func describeExpectedRecurrence(_ expected: CorpusRecurrence?) -> String {
        guard let expected else { return "nil" }
        let days = expected.weekdays.isEmpty ? "" : " days\(expected.weekdays.sorted())"
        return "\(expected.frequency.rawValue) x\(expected.interval)\(days)"
    }

    private func describePlace(_ intent: LocationIntent?) -> String {
        guard let intent else { return "nil" }
        return "\(intent.event.rawValue) \(describeReference(intent.place)) repeats=\(intent.repeats)"
    }

    private func describeExpectedPlace(_ expected: CorpusPlace?) -> String {
        guard let expected else { return "nil" }
        return "\(expected.event.rawValue) \(describeReference(expected.place)) repeats=\(expected.repeats)"
    }

    private func describeReference(_ reference: PlaceReference) -> String {
        switch reference {
        case .home: "home"
        case .work: "work"
        case .currentLocation: "current"
        case let .named(value):
            // "gym" and "the gym" are the same place. A leading article is not
            // a product failure.
            "named(\(value.lowercased().replacingOccurrences(of: #"^the\s+"#, with: "", options: .regularExpression)))"
        }
    }

    // MARK: Family runner

    /// Runs one family and fails once, with a report describing the shape of
    /// the break rather than a wall of individual assertions.
    private func run(_ family: CorpusFamily, _ cases: [CorpusCase]) {
        var disagreements: [Disagreement] = []
        for testCase in cases {
            disagreements.append(contentsOf: evaluate(testCase))
        }

        guard !disagreements.isEmpty else { return }

        let blocking = disagreements.filter { $0.severity >= .behavioral }
        let affected = Set(disagreements.map(\.utterance)).count
        var report = """

        ── \(family.rawValue) ──
        \(affected) of \(cases.count) utterances disagree with the contract \
        (\(disagreements.count) field mismatches).

        By field:
        """

        let byField = Dictionary(grouping: disagreements, by: \.field)
            .sorted { ($0.value.count, $1.key) > ($1.value.count, $0.key) }
        for (field, entries) in byField {
            report += "\n  \(field): \(entries.count)"
        }

        report += "\n\nBy severity:"
        for severity in [CorpusSeverity.critical, .behavioral, .metadata, .cosmetic] {
            let count = disagreements.filter { $0.severity == severity }.count
            if count > 0 { report += "\n  \(severity.label): \(count)" }
        }

        report += "\n\nCases:"
        for entry in disagreements.sorted(by: { $0.severity > $1.severity }) {
            report += "\n  [\(entry.severity.label)] \"\(entry.utterance)\"\n    \(entry.field): expected \(entry.expected), got \(entry.actual)"
            if let note = entry.note {
                report += "\n    contract: \(note)"
            }
        }

        // Metadata and cosmetic disagreements are reported, not gated. The
        // release rule is zero CRITICAL and zero BEHAVIORAL; the rest is triage.
        if blocking.isEmpty {
            print(report)
            return
        }

        XCTFail(report)
    }

    // MARK: Families
    //
    // One test per family so Xcode's navigator shows which rule is broken.

    func testNormalUtterances() { run(.normal, SemanticCorpusA.normal) }
    func testNaturalMessySpeech() { run(.messySpeech, SemanticCorpusA.messySpeech) }
    func testMultipleThoughts() { run(.multipleThoughts, SemanticCorpusA.multipleThoughts) }
    func testNegation() { run(.negation, SemanticCorpusA.negation) }
    func testPastVersusFuture() { run(.tense, SemanticCorpusA.tense) }
    func testTemporalAmbiguity() { run(.temporalAmbiguity, SemanticCorpusB.temporalAmbiguity) }
    func testNumbersThatAreNotTimes() { run(.nonTimeNumbers, SemanticCorpusB.nonTimeNumbers) }
    func testPeopleAndNames() { run(.people, SemanticCorpusB.people) }
    func testRecurrence() { run(.recurrence, SemanticCorpusB.recurrence) }
    func testLocation() { run(.location, SemanticCorpusB.location) }

    // The variation grid: one axis bent at a time, across intents whose bare
    // form already passes.
    func testFillerAndLeadIns() { run(.filler, SemanticCorpusC.filler) }
    func testCorrections() { run(.corrections, SemanticCorpusC.corrections) }
    func testOutstandingObligations() { run(.outstanding, SemanticCorpusC.outstanding) }
    func testCompletionAndCancellation() { run(.completion, SemanticCorpusC.completion) }
    func testTimeOfDay() { run(.timeOfDay, SemanticCorpusC.timeOfDay) }
    func testDateOnly() { run(.dateOnly, SemanticCorpusC.dateOnly) }
    func testDeadlinesVersusReminders() { run(.deadlines, SemanticCorpusD.deadlines) }
    func testAlarms() { run(.alarms, SemanticCorpusD.alarms) }
    func testEvents() { run(.events, SemanticCorpusD.events) }
    func testPronounsAndPossessives() { run(.pronouns, SemanticCorpusD.pronouns) }

    /// Everything at once. Every ingredient passes elsewhere; this asks whether
    /// the features are actually independent of each other.
    func testCompositions() { run(.compositions, SemanticCorpusD.compositions) }

    // Written from TestFlight usage. See `SemanticCorpusDataE.swift`.
    func testDatedFacts() { run(.datedFacts, SemanticCorpusE.datedFacts) }
    func testIntentConsolidation() { run(.consolidation, SemanticCorpusE.consolidation) }
    func testSemanticKeywordCollisions() { run(.collisions, SemanticCorpusE.collisions) }

    /// Never fails. Prints the corpus-wide picture so triage can start from the
    /// biggest cluster instead of from whichever test ran first.
    func testCorpusSummaryReport() {
        let families: [(CorpusFamily, [CorpusCase])] = [
            (.normal, SemanticCorpusA.normal),
            (.messySpeech, SemanticCorpusA.messySpeech),
            (.multipleThoughts, SemanticCorpusA.multipleThoughts),
            (.negation, SemanticCorpusA.negation),
            (.tense, SemanticCorpusA.tense),
            (.temporalAmbiguity, SemanticCorpusB.temporalAmbiguity),
            (.nonTimeNumbers, SemanticCorpusB.nonTimeNumbers),
            (.people, SemanticCorpusB.people),
            (.recurrence, SemanticCorpusB.recurrence),
            (.location, SemanticCorpusB.location),
            (.filler, SemanticCorpusC.filler),
            (.corrections, SemanticCorpusC.corrections),
            (.outstanding, SemanticCorpusC.outstanding),
            (.completion, SemanticCorpusC.completion),
            (.timeOfDay, SemanticCorpusC.timeOfDay),
            (.dateOnly, SemanticCorpusC.dateOnly),
            (.deadlines, SemanticCorpusD.deadlines),
            (.alarms, SemanticCorpusD.alarms),
            (.events, SemanticCorpusD.events),
            (.pronouns, SemanticCorpusD.pronouns),
            (.compositions, SemanticCorpusD.compositions),
            (.datedFacts, SemanticCorpusE.datedFacts),
            (.consolidation, SemanticCorpusE.consolidation),
            (.collisions, SemanticCorpusE.collisions),
        ]

        var lines = ["", "SEMANTIC CORPUS SUMMARY", String(repeating: "=", count: 60)]
        var totalCases = 0
        var totalFailing = 0
        var fieldTotals: [String: Int] = [:]
        var severityTotals: [CorpusSeverity: Int] = [:]

        for (family, cases) in families {
            var disagreements: [Disagreement] = []
            for testCase in cases {
                disagreements.append(contentsOf: evaluate(testCase))
            }
            let failing = Set(disagreements.map(\.utterance)).count
            totalCases += cases.count
            totalFailing += failing
            for entry in disagreements {
                let base = entry.field.prefix(while: { $0 != "[" })
                fieldTotals[String(base), default: 0] += 1
                severityTotals[entry.severity, default: 0] += 1
            }
            let blocking = disagreements.filter { $0.severity >= .behavioral }.count
            let status = blocking == 0 ? (failing == 0 ? "PASS" : "PASS (non-blocking)") : "FAIL"
            lines.append(String(format: "%-26s %4d cases  %4d failing  %@",
                                (family.rawValue as NSString).utf8String!, cases.count, failing, status))
        }

        lines.append(String(repeating: "-", count: 60))
        lines.append("TOTAL  \(totalCases) cases, \(totalFailing) failing, \(totalCases - totalFailing) passing")
        lines.append("")
        lines.append("By severity (release gate: 0 CRITICAL, 0 BEHAVIORAL):")
        for severity in [CorpusSeverity.critical, .behavioral, .metadata, .cosmetic] {
            lines.append("  \(severity.label): \(severityTotals[severity] ?? 0)")
        }
        lines.append("")
        lines.append("Field mismatches across the whole corpus:")
        for (field, count) in fieldTotals.sorted(by: { ($0.value, $1.key) > ($1.value, $0.key) }) {
            lines.append("  \(field): \(count)")
        }
        print(lines.joined(separator: "\n"))
    }
}
