import Foundation
@testable import SpeakIt

/// One disagreement between the contract and what the engine produced.
struct CorpusDisagreement {
    let utterance: String
    let field: String
    let expected: String
    let actual: String
    let note: String?
    let severity: CorpusSeverity
}

/// Runs corpus cases against the engine and describes the disagreements.
///
/// This used to live inside `SemanticCorpusTests` as private methods, which
/// meant the corpus could only ever be asked one question: *does the engine
/// agree with the contract when the sentence is written the way we wrote it?*
///
/// That is not the question a voice app needs answered. The same sentence
/// reaches the parser differently depending on which recognizer served it —
/// see `RenderingInvarianceTests` — so the evaluator takes a `rendering`
/// transform and the corpus can be replayed through any number of them.
struct CorpusEvaluator {

    /// Monday 2026-08-03 10:00 America/Toronto. Every suite that reads the
    /// corpus shares this instant so "tomorrow" and "Friday" mean one thing.
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Toronto")!
        return calendar
    }

    static var referenceDate: Date {
        calendar.date(from: DateComponents(
            year: 2026, month: 8, day: 3, hour: 10, minute: 0
        ))!
    }

    let calendar: Calendar
    let referenceDate: Date

    /// How the utterance reaches the parser. The identity transform is the
    /// corpus as authored; the invariance suite supplies degradations that a
    /// real recognizer produces.
    let rendering: (String) -> String

    /// Caps every disagreement this evaluator reports. A rendering that is
    /// known to lose information the contract depends on can be reported
    /// without gating a release.
    let severityCeiling: CorpusSeverity?

    init(
        calendar: Calendar = CorpusEvaluator.calendar,
        referenceDate: Date = CorpusEvaluator.referenceDate,
        severityCeiling: CorpusSeverity? = nil,
        rendering: @escaping (String) -> String = { $0 }
    ) {
        self.calendar = calendar
        self.referenceDate = referenceDate
        self.severityCeiling = severityCeiling
        self.rendering = rendering
    }

    // MARK: Field comparison

    func evaluate(_ testCase: CorpusCase) -> [CorpusDisagreement] {
        let utterance = rendering(testCase.utterance)
        let result = ThoughtExtractionEngine.extractWithRules(
            utterance,
            referenceDate: referenceDate,
            calendar: calendar
        )
        let items = result.items
        var found: [CorpusDisagreement] = []

        func record(_ field: String, _ expected: String, _ actual: String) {
            var severity = CorpusSeverity.forField(field)
            if let ceiling = testCase.severityCeiling, severity > ceiling {
                severity = ceiling
            }
            if let ceiling = severityCeiling, severity > ceiling {
                severity = ceiling
            }
            found.append(CorpusDisagreement(
                utterance: utterance,
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
                if normalizedTarget(actual) != normalizedTarget(expected) {
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
        each(testCase.recurs, "recurrence", { describeRecurrence($0.organization.recurrenceRule) }, { describeExpectedRecurrence($0) })
        each(testCase.place, "location", { describePlace($0.organization.locationIntent) }, { describeExpectedPlace($0) })

        return found
    }

    /// An operation target is the person's own words, so a rendering that
    /// removes punctuation changes the string without changing the meaning.
    /// Comparing on words alone keeps the assertion about *what was cancelled*.
    private func normalizedTarget(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: #"[^\p{L}\p{N}\s]"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
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
}

// MARK: - Reporting

extension CorpusEvaluator {

    /// Builds the clustered report for one family, or `nil` when the family
    /// agrees with the contract completely.
    ///
    /// The clustering is the design, not a convenience. A flat list of 40
    /// failing sentences invites 40 special cases, which is how a parser rots.
    /// A report that says *"Negation: 9 of 12 cases disagree on `count`"* names
    /// a single broken rule and one place to fix it.
    static func report(
        title: String,
        cases: [CorpusCase],
        disagreements: [CorpusDisagreement]
    ) -> String {
        let affected = Set(disagreements.map(\.utterance)).count
        var report = """

        ── \(title) ──
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

        return report
    }

    /// Every family in the corpus, in the order the report reads best.
    static var allFamilies: [(CorpusFamily, [CorpusCase])] {
        [
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
            (.delegation, SemanticCorpusE.delegation),
            (.assistant, SemanticCorpusE.assistant),
            (.calendarEdges, SemanticCorpusE.calendarEdges),
            (.dictation, SemanticCorpusE.dictation),
            (.contentPreservation, SemanticCorpusF.contentPreservation),
            (.runOnSpeech, SemanticCorpusF.runOnSpeech),
            (.openers, SemanticCorpusF.openers),
            (.clockForms, SemanticCorpusF.clockForms),
            (.calendarVocabulary, SemanticCorpusF.calendarVocabulary),
            (.managingItems, SemanticCorpusF.managingItems),
            (.listsAndPeople, SemanticCorpusF.listsAndPeople),
            (.wordInterior, SemanticCorpusG.wordInterior),
            (.negationIntegrity, SemanticCorpusG.negationIntegrity),
            (.renderingLoss, SemanticCorpusG.renderingLoss),
            (.splitCompound, SemanticCorpusH.splitCompound),
            (.splitCompound, SemanticCorpusH.splitCompoundGuards),
            (.paragraphs, SemanticCorpusH.paragraphs),
            (.elidedComplementizer, SemanticCorpusI.elidedComplementizer),
            (.elidedComplementizer, SemanticCorpusI.elidedComplementizerGuards),
            (.hedgedProposals, SemanticCorpusI.hedgedProposals),
            (.hedgedProposals, SemanticCorpusI.hedgedProposalGuards),
            (.fillerCollapse, SemanticCorpusJ.fillerCollapse),
            (.quantitiesNotClocks, SemanticCorpusK.quantitiesNotClocks),
            (.quantitiesNotClocks, SemanticCorpusK.quantityGuards),
            (.listCommands, SemanticCorpusL.listCommands),
            (.listCommands, SemanticCorpusL.listCommandGuards),
            (.structuralReadings, SemanticCorpusM.occupationsAreNotPeople),
            (.structuralReadings, SemanticCorpusM.structuralGuards),
        ]
    }

    static var allCases: [CorpusCase] { allFamilies.flatMap(\.1) }
}
