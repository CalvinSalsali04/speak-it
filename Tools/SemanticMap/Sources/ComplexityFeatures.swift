import Foundation

// Deterministic signals a router might use to decide whether a capture is worth
// Apple's model. Content-free by construction: every field is a count or a
// flag, so a feature record can be written, compared and quoted without quoting
// the capture.
//
// These are CANDIDATES, not a policy. Calvin's instruction was not to hardcode
// "several intentions, long, entities, times, corrections, quotes, conditions,
// pronouns, disagreement" as a router, but to measure which of them actually
// predict the deterministic path failing. So every candidate is recorded for
// every capture, and `score.py --router` measures each one's lift over the
// base failure rate on labelled development captures before any of them is
// allowed to route anything.
//
// Wherever the parser already has a detector for a phenomenon, the feature IS
// that detector: "did `SelfCorrectionResolver` change the text" rather than a
// second list of correction words that could disagree with it. Only three
// features have no production detector to reuse (pronoun references, quote
// marks, sentence marks); those are closed grammatical classes, not phrases.

struct ComplexityFeatures: Codable, Equatable, Sendable {
    // Size. Characters are recorded because the current gate reads them;
    // model tokens live on the route record, where the model is reachable.
    var characters: Int
    var atoms: Int
    var sentenceMarks: Int

    // What the rules path produced.
    var rulesItems: Int
    var rulesOperations: Int
    var rulesNeedsReview: Int
    var rulesUnresolvedState: Int
    var rulesActionable: Int
    var rulesMemory: Int
    var rulesTimed: Int
    var rulesLocated: Int
    var rulesWithPerson: Int

    // Structure the parser itself noticed.
    var clauses: Int
    var clauseItemMismatch: Int
    var consolidated: Bool
    var correctionRepaired: Bool
    var unresolvedNegativeRepair: Bool
    var inCaptureWithdrawal: Bool
    var reportingClauses: Int
    var communicatingClauses: Int
    var conditionalClauses: Int
    var timedClauses: Int
    var personMentions: Int
    var disfluencyCharactersRemoved: Int

    // Closed grammatical classes with no production detector.
    var quotationMarks: Bool
    var thirdPersonReferences: Int

    // Internal disagreement: two deterministic readers of the same row that do
    // not agree on Today versus Memory.
    var routeDisagreements: Int

    /// The shape Calvin named as the gap: a structurally complex capture that
    /// the rules path answered without flagging anything.
    var confidentOnComplex: Bool {
        rulesNeedsReview == 0 && rulesUnresolvedState == 0 && (clauses >= 3 || atoms >= 40)
    }
}

enum ComplexityReader {

    static let references = #"(?i)\b(?:it|that|this|them|those|these|one|he|she|him|her|they)\b"#

    static func read(
        _ transcript: String,
        rules: (items: [ExtractedThought], operations: [CaptureOperationRequest]),
        referenceDate: Date,
        calendar: Calendar
    ) -> ComplexityFeatures {
        let cleaned = DisfluencyFilter.stripped(transcript)
        let clauses = RuleBasedThoughtExtractor.splitClauses(cleaned)
        let acts = clauses.map { ClauseScope.read($0).act }
        let timedClauses = clauses.filter {
            ThoughtOrganizer.organize($0, referenceDate: referenceDate, calendar: calendar)
                .temporalIntent.kind != .none
        }.count
        let conditional = clauses.filter {
            ConditionalIntentScope.dependency(in: $0) != nil || ConditionalIntentScope.standalone(in: $0) != nil
        }.count
        let items = rules.items
        let disagreements = items.filter { item in
            let routedToday = item.organization.itemType.isActionable || item.organization.reminderDate != nil
            let reading = ActionabilityReader.read(item.analysisText)
            guard reading != .ambiguous else { return false }
            return reading.belongsOnToday != routedToday
        }.count

        return ComplexityFeatures(
            characters: transcript.count,
            atoms: Atoms.atomize(transcript).count,
            sentenceMarks: transcript.filter { ".?!".contains($0) }.count,
            rulesItems: items.count,
            rulesOperations: rules.operations.count,
            rulesNeedsReview: items.filter(\.needsReview).count,
            rulesUnresolvedState: items.filter { $0.organization.state.kind != .resolved }.count,
            rulesActionable: items.filter { $0.organization.itemType.isActionable }.count,
            rulesMemory: items.filter { !$0.organization.itemType.isActionable && $0.organization.reminderDate == nil }.count,
            rulesTimed: items.filter { $0.organization.dueDate != nil || $0.organization.reminderDate != nil }.count,
            rulesLocated: items.filter { $0.organization.locationIntent != nil }.count,
            rulesWithPerson: items.filter { $0.organization.personName != nil }.count,
            clauses: clauses.count,
            clauseItemMismatch: abs(clauses.count - items.count),
            consolidated: IntentConsolidator.consolidate(cleaned, clauses: clauses) != nil,
            correctionRepaired: SelfCorrectionResolver.resolved(cleaned) != cleaned,
            unresolvedNegativeRepair: SelfCorrectionResolver.hasUnresolvedNegativeRepair(cleaned),
            inCaptureWithdrawal: !CaptureOperationDetector.resolvingInCaptureCancellations(cleaned).operations.isEmpty,
            reportingClauses: acts.filter { $0 == .reporting }.count,
            communicatingClauses: acts.filter { $0 == .communicating }.count,
            conditionalClauses: conditional,
            timedClauses: timedClauses,
            personMentions: PersonMentionResolver.mentions(in: transcript).count,
            disfluencyCharactersRemoved: max(0, transcript.count - cleaned.count),
            quotationMarks: transcript.contains { "\"“”".contains($0) },
            thirdPersonReferences: transcript.matchCount(of: references),
            routeDisagreements: disagreements
        )
    }
}

extension String {
    func matchCount(of pattern: String) -> Int {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return 0 }
        return expression.numberOfMatches(in: self, range: NSRange(startIndex..., in: self))
    }
}
