import XCTest
@testable import SpeakIt

/// Runs the semantic torture corpus and reports failures **clustered by family
/// and by field**.
///
/// The comparison itself lives in `CorpusEvaluator`, because the corpus is
/// asked more than one question: this suite asks whether the engine agrees
/// with the contract, and `RenderingInvarianceTests` asks whether it still
/// agrees when the recognizer renders the same sentence differently.
///
/// A failure here is a disagreement, not automatically a bug. Expectations are
/// authored from the product contract, so each cluster resolves either by
/// changing the rule or by correcting a contract statement that was wrong.
@MainActor
final class SemanticCorpusTests: XCTestCase {

    private let evaluator = CorpusEvaluator()

    // MARK: Family runner

    /// Runs one family and fails once, with a report describing the shape of
    /// the break rather than a wall of individual assertions.
    private func run(_ family: CorpusFamily, _ cases: [CorpusCase]) {
        var disagreements: [CorpusDisagreement] = []
        for testCase in cases {
            disagreements.append(contentsOf: evaluator.evaluate(testCase))
        }

        guard !disagreements.isEmpty else { return }

        let blocking = disagreements.filter { $0.severity >= .behavioral }
        let report = CorpusEvaluator.report(
            title: family.rawValue,
            cases: cases,
            disagreements: disagreements
        )

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
    func testDelegationAndThirdPerson() { run(.delegation, SemanticCorpusE.delegation) }
    func testAssistantConventions() { run(.assistant, SemanticCorpusE.assistant) }
    func testSpokenCalendarEdges() { run(.calendarEdges, SemanticCorpusE.calendarEdges) }
    func testDictationRenderings() { run(.dictation, SemanticCorpusE.dictation) }

    // Written from a sweep of realistic utterances. See `SemanticCorpusDataF.swift`.
    func testRepairsPreserveContent() { run(.contentPreservation, SemanticCorpusF.contentPreservation) }
    func testRunOnSpeech() { run(.runOnSpeech, SemanticCorpusF.runOnSpeech) }
    func testDiscourseOpeners() { run(.openers, SemanticCorpusF.openers) }
    func testClockForms() { run(.clockForms, SemanticCorpusF.clockForms) }
    func testCalendarVocabulary() { run(.calendarVocabulary, SemanticCorpusF.calendarVocabulary) }
    func testManagingExistingItems() { run(.managingItems, SemanticCorpusF.managingItems) }
    func testListsAndPeople() { run(.listsAndPeople, SemanticCorpusF.listsAndPeople) }
    func testMultiClauseParagraphs() { run(.paragraphs, SemanticCorpusH.paragraphs) }
    // Families G had no runner of their own, so a blocking regression in them
    // showed up only in the summary report that never fails.
    func testRulesMatchingInsideAWord() { run(.wordInterior, SemanticCorpusG.wordInterior) }
    func testNegationsReadAsCorrections() { run(.negationIntegrity, SemanticCorpusG.negationIntegrity) }
    func testContentLostInOneRenderingOnly() { run(.renderingLoss, SemanticCorpusG.renderingLoss) }

    // From one capture made on a device. See `SemanticCorpusDataI.swift`.
    func testElidedComplementizers() { run(.elidedComplementizer, SemanticCorpusI.elidedComplementizer) }
    func testElidedComplementizerGuards() { run(.elidedComplementizer, SemanticCorpusI.elidedComplementizerGuards) }
    func testHedgedProposals() { run(.hedgedProposals, SemanticCorpusI.hedgedProposals) }
    func testHedgedProposalGuards() { run(.hedgedProposals, SemanticCorpusI.hedgedProposalGuards) }

    // Filler that tripped the consolidation veto. See `SemanticCorpusDataI.swift`.
    func testFillerThatCollapsedACapture() { run(.fillerCollapse, SemanticCorpusJ.fillerCollapse) }

    // A repair that edited the person's own words. See `SemanticCorpusDataI.swift`.
    func testQuantitiesAreNotRewrittenAsClocks() { run(.quantitiesNotClocks, SemanticCorpusK.quantitiesNotClocks) }
    func testQuantityGuardsKeepRealClockReadings() { run(.quantitiesNotClocks, SemanticCorpusK.quantityGuards) }

    // List commands parsed as a frame. See `SemanticCorpusDataI.swift`.
    func testListCommandsAsAFrame() { run(.listCommands, SemanticCorpusL.listCommands) }
    func testListCommandGuards() { run(.listCommands, SemanticCorpusL.listCommandGuards) }

    // Structure replacing vocabulary. See `SemanticCorpusDataI.swift`.
    func testOccupationsAreNotPeople() { run(.structuralReadings, SemanticCorpusM.occupationsAreNotPeople) }
    func testStructuralReadingGuards() { run(.structuralReadings, SemanticCorpusM.structuralGuards) }

    /// Never fails. Prints the corpus-wide picture so triage can start from the
    /// biggest cluster instead of from whichever test ran first.
    func testCorpusSummaryReport() {
        var lines = ["", "SEMANTIC CORPUS SUMMARY", String(repeating: "=", count: 60)]
        var totalCases = 0
        var totalFailing = 0
        var fieldTotals: [String: Int] = [:]
        var severityTotals: [CorpusSeverity: Int] = [:]

        for (family, cases) in CorpusEvaluator.allFamilies {
            var disagreements: [CorpusDisagreement] = []
            for testCase in cases {
                disagreements.append(contentsOf: evaluator.evaluate(testCase))
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
