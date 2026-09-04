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

    // Found on a device, not by replay. These had data and a registry entry but
    // no runner of their own for a long time, so a blocking regression in them
    // surfaced only in the summary report, which never fails. `testEveryFamilyIsGated`
    // now makes that class of hole impossible; these stay for navigator granularity.
    func testOneWordDictatedAsTwo() { run(.splitCompound, SemanticCorpusH.splitCompound) }
    func testSplitCompoundGuards() { run(.splitCompound, SemanticCorpusH.splitCompoundGuards) }

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

    /// The control group: ordinary speech the parser must leave alone.
    func testOrdinarySpeechIsLeftAlone() { run(.ordinarySpeech, SemanticCorpusN.ordinarySpeech) }

    /// A cancellation only cancels when it is the utterance's own speech act.
    func testSpeechActScope() { run(.speechActScope, SemanticCorpusO.speechActScope) }

    /// "Remind me not to X" and "remind me to not X" are the same sentence.
    func testProhibitiveReminders() { run(.prohibitions, SemanticCorpusP.prohibitions) }

    // MARK: Preservation
    //
    // The product contract says the parser may drop command scaffolding but may
    // never invent user content. Nothing tested that at item granularity: the
    // evaluator compares count, route, dates, person and so on, and `title` is
    // graded cosmetic, so a row could acquire a word nobody spoke and the suite
    // stayed green.

    /// Words a title is allowed to carry that the person did not say.
    ///
    /// Every entry is a *declared* transformation with a reason. The list is
    /// deliberately tiny and adding to it should feel expensive — it is the
    /// only crack through which invented content can reach a row.
    private static let declaredTitleWords: Set<String> = [
        // Shopping canonicalisation. "Grocery list: milk and eggs" and "milk
        // eggs bread" both become rows headed by the acquisition verb, because
        // a shopping row with no verb reads as a fragment.
        "buy",
        // Temporal canonicalisation: the app stores one spelling of an hour or
        // a repeat, so "midday" surfaces as noon, "5ish" as around 5, and
        // "annually" as every year.
        "noon", "around", "every", "year",
        // Negative imperative. The negator is the person's own ("not", "never");
        // English supplies the auxiliary, because "Not eat before the blood
        // test" is not a sentence. See `ReminderPhrasing.isProhibitive`.
        "don't", "don’t",
        // Placeholder copy for a capture that resolved to no nameable action.
        "review", "captured", "thought", "your", "reminder", "alarm", "timer",
        "wake", "up",
        // "Alarm for 6:30" — the preposition belongs to that copy, not to the
        // capture, which may have said only "set two alarms, 6:30 and 6:45".
        "for",
    ]

    private static func contentWords(_ value: String) -> [String] {
        value.lowercased()
            .replacingOccurrences(of: #"[^\p{L}\p{N}'’\s]"#, with: " ", options: .regularExpression)
            .split(separator: " ")
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    /// Whether a word is accounted for by something the person actually said.
    ///
    /// Stem-tolerant, because ordinary morphology and the declared dictation
    /// repairs ("meat" → "meet", "do" → "due") are not invention. Digits are
    /// compared as substrings so a split clock — "830" read as "8:30" — is not
    /// reported as a fabricated "30".
    private static func isAccountedFor(_ word: String, by said: Set<String>) -> Bool {
        if said.contains(word) { return true }
        if word.allSatisfy(\.isNumber) {
            return said.contains { $0.contains(word) || word.contains($0) && $0.allSatisfy(\.isNumber) }
        }
        let head = String(word.prefix(max(3, word.count - 2)))
        return said.contains {
            $0.hasPrefix(head) || word.hasPrefix(String($0.prefix(max(3, $0.count - 2))))
        }
    }

    /// No row may be headed by a word the person never spoke.
    // Families 52-54: the clock and calendar outside North America.
    func testDayMonthOrder() { run(.dayMonthOrder, SemanticCorpusR.dayMonthOrder) }
    func testDayMonthOrderGuards() { run(.dayMonthOrder, SemanticCorpusR.dayMonthGuards) }
    func testInternationalClockForms() { run(.internationalClock, SemanticCorpusR.internationalClock) }
    func testInternationalClockGuards() { run(.internationalClock, SemanticCorpusR.internationalClockGuards) }
    func testWeekdayIdiomsAndOrdinalAdjectives() { run(.calendarIdioms, SemanticCorpusR.calendarIdioms) }
    func testCalendarIdiomGuards() { run(.calendarIdioms, SemanticCorpusR.calendarIdiomGuards) }

    func testNoTitleInventsAWordTheSpeakerDidNotSay() {
        var offenders: [String] = []
        for (_, cases) in CorpusEvaluator.allFamilies {
            for testCase in cases {
                let result = ThoughtExtractionEngine.extractWithRules(
                    testCase.utterance,
                    referenceDate: CorpusEvaluator.referenceDate,
                    calendar: CorpusEvaluator.calendar
                )
                // What the pipeline understood was said: the person's own words,
                // plus whatever the repair layer resolved them to. Repairs are
                // declared transformations with their own tests — "meat" → meet,
                // "do" → due, "next weak" → next week, "midday" → noon — and
                // they reach the title through the quote, so comparing against
                // the quotes as well keeps this gate about *invention* rather
                // than about re-litigating the repair layer.
                let said = Set(Self.contentWords(testCase.utterance))
                    .union(result.items.flatMap { Self.contentWords($0.sourceQuote) })
                for item in result.items {
                    // The *displayed* title, not the raw suggestion. The rules
                    // path leaves `suggestedTitle` nil on most captures, so a
                    // gate reading it directly skipped nearly every row it was
                    // written to protect.
                    let title = CorpusEvaluator.displayTitle(for: item)
                    let invented = Self.contentWords(title)
                        .filter { !Self.declaredTitleWords.contains($0) }
                        .filter { !Self.isAccountedFor($0, by: said) }
                    if !invented.isEmpty {
                        offenders.append(
                            "  \"\(testCase.utterance)\"\n    title \"\(title)\" adds: "
                            + invented.sorted().joined(separator: ", ")
                        )
                    }
                }
            }
        }
        XCTAssertTrue(offenders.isEmpty, """

        TITLES CARRYING WORDS THE SPEAKER DID NOT SAY
        Each of these puts content in front of the person that they never
        provided. If a transformation is genuinely wanted, declare it in
        `declaredTitleWords` with its reason rather than widening the test.

        \(offenders.joined(separator: "\n"))
        """)
    }

    /// Every capture that produces rows must keep some of the person's own
    /// words in at least one of them.
    ///
    /// This is the weaker half of preservation, and deliberately so: dropping
    /// scaffolding is allowed, so a per-word loss test would be a list of
    /// exceptions. What is never allowed is a row that is entirely detached
    /// from the capture it came from.
    func testEveryRowKeepsSomeOfThePersonsWords() {
        var offenders: [String] = []
        for (_, cases) in CorpusEvaluator.allFamilies {
            for testCase in cases {
                let result = ThoughtExtractionEngine.extractWithRules(
                    testCase.utterance,
                    referenceDate: CorpusEvaluator.referenceDate,
                    calendar: CorpusEvaluator.calendar
                )
                guard result.operations.isEmpty else { continue }
                let said = Set(Self.contentWords(testCase.utterance))
                for item in result.items {
                    let quoted = Self.contentWords(item.sourceQuote)
                    if quoted.isEmpty || !quoted.contains(where: { Self.isAccountedFor($0, by: said) }) {
                        offenders.append(
                            "  \"\(testCase.utterance)\" → quote \"\(item.sourceQuote)\""
                        )
                    }
                }
            }
        }
        XCTAssertTrue(offenders.isEmpty, """

        ROWS WHOSE QUOTE SHARES NO WORD WITH THE CAPTURE
        \(offenders.joined(separator: "\n"))
        """)
    }

    // MARK: Coverage of the corpus by the gate
    //
    // The per-family tests above are hand-written, so for a long time a family
    // could be authored, filled with cases, registered in `allFamilies`, and
    // still never gate anything — which is exactly what happened to
    // `splitCompound` and its fifteen device-found cases. The two tests below
    // close that off structurally rather than by anyone remembering.

    /// Gates **every** family in the registry, including any that nobody has
    /// written a `run(...)` for yet.
    ///
    /// This is the real gate. A family added to `CorpusEvaluator.allFamilies`
    /// is protected from the moment it is registered; forgetting to add a
    /// runner costs navigator granularity, not coverage.
    func testEveryFamilyIsGated() {
        var offenders: [String] = []
        var report = ""
        for (family, cases) in CorpusEvaluator.allFamilies {
            var disagreements: [CorpusDisagreement] = []
            for testCase in cases {
                disagreements.append(contentsOf: evaluator.evaluate(testCase))
            }
            let blocking = disagreements.filter { $0.severity >= .behavioral }
            guard !blocking.isEmpty else { continue }
            offenders.append(family.rawValue)
            report += CorpusEvaluator.report(
                title: family.rawValue,
                cases: cases,
                disagreements: disagreements
            )
        }
        guard !offenders.isEmpty else { return }
        XCTFail("""

        FAMILIES WITH BLOCKING DISAGREEMENTS
        \(offenders.joined(separator: ", "))
        \(report)
        """)
    }

    /// Every family the corpus *declares* must actually carry cases.
    ///
    /// A `CorpusFamily` case with no entry in `allFamilies` is a family whose
    /// data file was written and never wired up — indistinguishable, from the
    /// outside, from a family that passes.
    func testEveryDeclaredFamilyHasRegisteredCases() {
        let registered = Set(CorpusEvaluator.allFamilies.map(\.0))
        let empty = CorpusEvaluator.allFamilies
            .filter { $0.1.isEmpty }
            .map { $0.0.rawValue }
        let unregistered = CorpusFamily.allCases
            .filter { !registered.contains($0) }
            .map(\.rawValue)
        XCTAssertTrue(
            unregistered.isEmpty,
            "Declared but never registered in CorpusEvaluator.allFamilies: \(unregistered.joined(separator: ", "))"
        )
        XCTAssertTrue(
            empty.isEmpty,
            "Registered with zero cases: \(empty.joined(separator: ", "))"
        )
    }

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
