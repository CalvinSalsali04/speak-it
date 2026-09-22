import Foundation

// Evidence-based arbitration between the deterministic reading and a grounded
// semantic map. Neither "model wins" nor "rules always win": every semantic
// decision is classified, and the classification decides what happens.
//
//   agree                   both readings say the same thing
//   modelAddsStructure      the map adds grounded structure the rules lacked,
//                           and every deterministic check on the result passes
//   rulesStronger           the deterministic reading has evidence the map
//                           cannot outweigh (a grammar check, content loss)
//   modelViolatesGrounding  a job's output was malformed and refused whole
//   modelConflictsSafety    the map's structure would break a safety invariant
//   unresolved              the readings disagree and neither is decisive;
//                           resolved conservatively and never hidden
//
// What the map is allowed to change, exhaustively:
//
// 1. SPLIT a rules row at a model boundary, when each piece read by the rules
//    pipeline keeps everything the row had (`RefinementGuard.preservesEverything`,
//    the guard Candidate47's hybrid path already uses) and no piece carries an
//    executable value the row did not already carry.
// 2. MERGE adjacent Memory rows the model reads as one thought, when neither
//    carries anything executable. Merging two actions could hide one, so
//    actions are never merged.
// 3. WITHDRAW execution from a row (reminder, due date, recurrence, place
//    trigger) and flag it for review, when the map says the row was corrected,
//    cancelled, made conditional, or is somebody else's words. One-directional:
//    the model can take capability away, never grant it.
// 4. CLEAR a person the rules inferred, when the map and PR #117's
//    `entityKind(in:)` do not both call it a person. Empty person metadata
//    beats an invented person; the map never adds one.
//
// What it can never do: create an operation, a reminder, a date, a place
// trigger, a name or any text. Operations stay entirely the rules path's, and a
// capture carrying one is not arbitrated at all. After arbitration a final
// invariant re-checks that every executable value in the output already
// existed in the rules output, and falls back to the rules reading whole if
// not. That check is a structural guarantee and is reported as one, never as
// model accuracy.

enum Verdict: String, Codable, CaseIterable, Sendable {
    case agree
    case modelAddsStructure
    case rulesStronger
    case modelViolatesGrounding
    case modelConflictsSafety
    case unresolved
}

enum DecisionTopic: String, Codable, CaseIterable, Sendable {
    case capture
    case job
    case segmentation
    case split
    case merge
    case relation
    case entity
    case finalInvariant
}

/// Closed and content-free, so a decision log can be quoted from any set.
enum DecisionReason: String, Codable, CaseIterable, Sendable {
    // capture
    case operationOwnedByRules
    case noMap
    case rulesProducedNothing
    // job
    case jobRefused
    // segmentation
    case unitsNotAccepted
    case rowsNotLocatable
    case boundariesAgree
    // split
    case splitAccepted
    case cutInsideQuotation
    case cutInsideMessageOrReport
    case cutSeparatesCondition
    case cutAfterDanglingWord
    case pieceReadsAsOperation
    case pieceProducedNothing
    case pieceSplitUnderCarriedContext
    case splitLosesContent
    case splitCreatesExecution
    case splitsDisabled
    // merge
    case mergedMemory
    case mergeWouldHideAction
    case mergeNotClean
    case mergesDisabled
    // relation
    case correctionAlreadyResolved
    case withdrawalAlreadyResolved
    case correctedRowStillExecutes
    case withdrawnRowStillExecutes
    case correctedRowStillOwed
    case conditionAlreadyHeld
    case conditionSupportedByRules
    case conditionModelOnly
    case messageContentAlreadyInside
    case messageContentExecutes
    case relationNotActedOn
    case relationTargetsUnlocated
    // entity
    case personConfirmed
    case personRejectedByBoth
    case personRejectedOnTie
    case personKeptByRules
    case modelOnlyPerson
    case entityNotOnARow
    case entityRemovalDisabled
    // final
    case executionOutsideRulesReading
    case structuralGuaranteeHeld
}

enum DecisionEffect: String, Codable, Sendable {
    case none
    case keptRules
    case splitRow
    case mergedRows
    case withdrewExecution
    case flaggedReview
    case clearedPerson
    case fellBackToRules
}

struct ArbitrationDecision: Codable, Equatable, Sendable {
    var topic: DecisionTopic
    var verdict: Verdict
    var reason: DecisionReason
    var effect: DecisionEffect
    var relation: UnitRelationKind?
    var refusal: JobRefusal?
    var job: String?
}

/// Every behaviour switch, so the harness can report what each rule costs and
/// buys on its own rather than only the bundle.
struct ArbitrationPolicy: Codable, Equatable, Sendable {
    var acceptSplits = true
    var acceptMemoryMerges = true
    var withdrawOn: Set<UnitRelationKind> = [.replaces, .cancels, .isConditionFor, .isMessageContentOf]
    var removeUnconfirmedPersons = true

    static let standard = ArbitrationPolicy()
    static let observeOnly = ArbitrationPolicy(
        acceptSplits: false, acceptMemoryMerges: false, withdrawOn: [], removeUnconfirmedPersons: false
    )
}

struct ArbitrationResult: Sendable {
    var items: [ExtractedThought]
    var operations: [CaptureOperationRequest]
    var decisions: [ArbitrationDecision]
    /// True when anything the map said changed the output.
    var mapChangedOutput: Bool
}

enum Arbiter {

    /// Closed-class words that need what follows them: articles, possessive
    /// determiners, prepositions, conjunctions, negators, auxiliaries and
    /// subject pronouns. A cut after one separates a word from its complement,
    /// which is a grammar fact rather than a judgement. Words that commonly end
    /// a clause on their own ("fix it", "call me", "do that") are deliberately
    /// absent: refusing those cuts would only cost recall, but it would cost it
    /// on the commonest boundary in speech.
    static let danglingWords: Set<String> = [
        "a", "an", "the", "my", "your", "his", "our", "their", "its",
        "to", "of", "for", "with", "at", "in", "on", "by", "from", "about", "into", "onto", "than",
        "and", "or", "but", "if", "when", "because", "unless", "until", "before", "after",
        "not", "dont", "never", "is", "are", "was", "were", "be", "will", "would", "can",
        "could", "should", "must", "have", "has", "had", "do", "does", "did",
        "i", "we", "he", "she", "they",
    ]

    // MARK: Entry point

    static func arbitrate(
        transcript: String,
        rules: (items: [ExtractedThought], operations: [CaptureOperationRequest]),
        map: SemanticMap?,
        policy: ArbitrationPolicy = .standard,
        referenceDate: Date,
        calendar: Calendar
    ) -> ArbitrationResult {
        var decisions: [ArbitrationDecision] = []
        let unchanged = ArbitrationResult(
            items: rules.items, operations: rules.operations, decisions: [], mapChangedOutput: false
        )

        guard let map else {
            return with(unchanged, [decision(.capture, .rulesStronger, .noMap, .keptRules)])
        }
        for (name, job) in [("units", map.unitsJob), ("relations", map.relationsJob), ("entities", map.entitiesJob)]
            where job.outcome == .refused {
            var refused = decision(.job, .modelViolatesGrounding, .jobRefused, .none)
            refused.refusal = job.refusal
            refused.job = name
            decisions.append(refused)
        }
        guard rules.operations.isEmpty else {
            decisions.append(decision(.capture, .rulesStronger, .operationOwnedByRules, .keptRules))
            return with(unchanged, decisions)
        }
        guard !rules.items.isEmpty else {
            decisions.append(decision(.capture, .rulesStronger, .rulesProducedNothing, .keptRules))
            return with(unchanged, decisions)
        }

        let atoms = Atoms.atomize(transcript)
        guard let located = RowLocator.spans(of: rules.items.map(\.rawQuote), in: transcript, atoms: atoms) else {
            decisions.append(decision(.segmentation, .unresolved, .rowsNotLocatable, .keptRules))
            return with(unchanged, decisions)
        }
        var rows = zip(rules.items, located).map { Row(item: $0.0, span: $0.1) }
            .sorted { $0.span.first < $1.span.first }

        // 1 & 2. Segmentation.
        if let units = map.units, map.unitSource == .model {
            rows = arbitrateSegmentation(
                rows, units: units, relations: map.relations ?? [], transcript: transcript, atoms: atoms,
                policy: policy, referenceDate: referenceDate, calendar: calendar, decisions: &decisions
            )
        } else {
            decisions.append(decision(.segmentation, .unresolved, .unitsNotAccepted, .keptRules))
        }

        // 3. Relations, over whichever units the relations job was asked about.
        if let units = map.units, let relations = map.relations {
            rows = arbitrateRelations(
                rows, units: units, relations: relations, transcript: transcript, atoms: atoms,
                policy: policy, decisions: &decisions
            )
        }

        // 4. Entities.
        if let entities = map.entities {
            rows = arbitrateEntities(
                rows, entities: entities, transcript: transcript, atoms: atoms,
                policy: policy, decisions: &decisions
            )
        }

        let items = rows.map(\.item)
        // The structural guarantee: nothing executable that the rules did not
        // already produce. A violation is a bug in this file, and the only
        // safe response to a bug here is the rules reading, whole.
        if !executablesAreSubset(items, of: rules.items) {
            decisions.append(decision(.finalInvariant, .modelConflictsSafety, .executionOutsideRulesReading, .fellBackToRules))
            return with(unchanged, decisions)
        }
        decisions.append(decision(.finalInvariant, .agree, .structuralGuaranteeHeld, .none))
        return ArbitrationResult(
            items: items,
            operations: rules.operations,
            decisions: decisions,
            mapChangedOutput: items != rules.items
        )
    }

    // MARK: Segmentation

    struct Row {
        var item: ExtractedThought
        var span: AtomSpan
    }

    static func arbitrateSegmentation(
        _ rows: [Row],
        units: [AtomSpan],
        relations: [UnitRelation],
        transcript: String,
        atoms: [SemanticAtom],
        policy: ArbitrationPolicy,
        referenceDate: Date,
        calendar: Calendar,
        decisions: inout [ArbitrationDecision]
    ) -> [Row] {
        let cuts = Set(units.dropLast().map(\.last))
        var proposed = false

        // Splits: a model cut strictly inside a rules row.
        var afterSplits: [Row] = []
        for row in rows {
            let interior = cuts.filter { $0 >= row.span.first && $0 < row.span.last }.sorted()
            guard !interior.isEmpty else { afterSplits.append(row); continue }
            proposed = true
            guard policy.acceptSplits else {
                decisions.append(decision(.split, .unresolved, .splitsDisabled, .keptRules))
                afterSplits.append(row)
                continue
            }
            switch split(
                row, at: interior, units: units, relations: relations, transcript: transcript, atoms: atoms,
                referenceDate: referenceDate, calendar: calendar
            ) {
            case let .success(pieces):
                decisions.append(decision(.split, .modelAddsStructure, .splitAccepted, .splitRow))
                afterSplits.append(contentsOf: pieces)
            case let .failure(refusal):
                decisions.append(decision(.split, refusal.verdict, refusal.reason, .keptRules))
                afterSplits.append(row)
            }
        }

        // Merges: two adjacent rows with no model cut anywhere between them.
        var merged: [Row] = []
        for row in afterSplits {
            // Pieces of one split row share its span; they were just divided
            // on purpose and are never candidates for re-joining.
            guard let previous = merged.last, previous.span.last < row.span.first else {
                merged.append(row)
                continue
            }
            let gap = previous.span.last ..< row.span.first
            let modelSeparates = cuts.contains { gap.contains($0) }
            guard !modelSeparates else { merged.append(row); continue }
            proposed = true
            guard policy.acceptMemoryMerges else {
                decisions.append(decision(.merge, .unresolved, .mergesDisabled, .keptRules))
                merged.append(row)
                continue
            }
            if isExecutableOrOwed(previous.item) || isExecutableOrOwed(row.item) {
                decisions.append(decision(.merge, .rulesStronger, .mergeWouldHideAction, .keptRules))
                merged.append(row)
                continue
            }
            guard let span = AtomSpan(first: previous.span.first, last: row.span.last),
                  let text = Atoms.slice(transcript, atoms, span) else {
                merged.append(row)
                continue
            }
            let reading = RuleBasedThoughtExtractor.process(
                text, referenceDate: referenceDate, calendar: calendar, permitsOperations: true
            )
            if reading.operations.isEmpty, reading.items.count == 1, let only = reading.items.first,
               !isExecutableOrOwed(only),
               RefinementGuard.preservesEverything(in: [only], found: [previous.item, row.item]) {
                decisions.append(decision(.merge, .modelAddsStructure, .mergedMemory, .mergedRows))
                merged[merged.count - 1] = Row(item: only, span: span)
            } else {
                decisions.append(decision(.merge, .unresolved, .mergeNotClean, .keptRules))
                merged.append(row)
            }
        }

        if !proposed {
            decisions.append(decision(.segmentation, .agree, .boundariesAgree, .none))
        }
        return merged
    }

    struct SplitRefusal: Error {
        let verdict: Verdict
        let reason: DecisionReason
    }

    static func split(
        _ row: Row,
        at cuts: [Int],
        units: [AtomSpan],
        relations: [UnitRelation],
        transcript: String,
        atoms: [SemanticAtom],
        referenceDate: Date,
        calendar: Calendar
    ) -> Result<[Row], SplitRefusal> {
        guard let rowText = Atoms.slice(transcript, atoms, row.span) else {
            return .failure(SplitRefusal(verdict: .unresolved, reason: .pieceProducedNothing))
        }
        let rowStart = atoms[row.span.first].range.lowerBound
        let reading = ClauseScope.read(rowText)
        let dependency = ConditionalIntentScope.dependency(in: rowText)

        var pieces: [AtomSpan] = []
        var start = row.span.first
        for cut in cuts {
            if let span = AtomSpan(first: start, last: cut) { pieces.append(span) }
            start = cut + 1
        }
        if let span = AtomSpan(first: start, last: row.span.last) { pieces.append(span) }

        // Safety and grammar at each cut, before anything is read.
        for cut in cuts {
            guard let boundary = Atoms.boundaryIndex(after: cut, in: atoms) else { continue }
            if ClauseScope.isInsideQuotation(boundary, in: transcript) {
                return .failure(SplitRefusal(verdict: .modelConflictsSafety, reason: .cutInsideQuotation))
            }
            if reading.act != .direct, let complement = reading.complementRange {
                // `ClauseScope.read` trims its input and returns indexes into
                // the trimmed copy. A row slice starts and ends on an atom, so
                // the copy has the same contents, and UTF-16 offsets are the
                // coordinate both strings share.
                let offset = transcript.utf16.distance(from: rowStart, to: boundary)
                let lower = complement.lowerBound.utf16Offset(in: rowText)
                let upper = complement.upperBound.utf16Offset(in: rowText)
                if offset > lower, offset < upper {
                    return .failure(SplitRefusal(verdict: .modelConflictsSafety, reason: .cutInsideMessageOrReport))
                }
            }
            let word = Atoms.folded(transcript[atoms[cut].range])
            if danglingWords.contains(word) {
                return .failure(SplitRefusal(verdict: .rulesStronger, reason: .cutAfterDanglingWord))
            }
        }
        let texts = pieces.compactMap { Atoms.slice(transcript, atoms, $0) }
        guard texts.count == pieces.count else {
            return .failure(SplitRefusal(verdict: .unresolved, reason: .pieceProducedNothing))
        }
        if dependency != nil, texts.contains(where: { ConditionalIntentScope.standalone(in: $0) != nil }) {
            return .failure(SplitRefusal(verdict: .modelConflictsSafety, reason: .cutSeparatesCondition))
        }

        // Read each piece with the rules pipeline, carrying a leading day or
        // time only where the map says one thought gives context to another,
        // and only the words `leadingTemporalContext` finds in the source
        // thought. The context is the transcript's own words; the model only
        // said which thought it belongs to.
        var rowsOut: [Row] = []
        for (index, piece) in pieces.enumerated() {
            let text = texts[index]
            let context = carriedContext(
                into: piece, units: units, relations: relations, transcript: transcript, atoms: atoms
            ).flatMap { $0.lowercased().contains(text.lowercased()) ? nil : $0 }
            let input = context.map { "\($0) \(text)" } ?? text
            let result = RuleBasedThoughtExtractor.process(
                input, referenceDate: referenceDate, calendar: calendar, permitsOperations: true
            )
            guard result.operations.isEmpty else {
                return .failure(SplitRefusal(verdict: .modelConflictsSafety, reason: .pieceReadsAsOperation))
            }
            guard !result.items.isEmpty else {
                return .failure(SplitRefusal(verdict: .rulesStronger, reason: .pieceProducedNothing))
            }
            if context != nil {
                guard result.items.count == 1, let only = result.items.first else {
                    return .failure(SplitRefusal(verdict: .unresolved, reason: .pieceSplitUnderCarriedContext))
                }
                // The row shows the person's own words for this piece; the
                // carried day lives in the analysis, exactly as the rules
                // path's own inheritance keeps it.
                let reframed = ExtractedThought(
                    sourceQuote: text,
                    rawQuote: text,
                    wasRepaired: only.wasRepaired,
                    analysisText: only.analysisText,
                    suggestedTitle: only.suggestedTitle,
                    organization: only.organization,
                    confidence: only.confidence,
                    needsReview: only.needsReview,
                    shoppingGroup: only.shoppingGroup
                )
                rowsOut.append(Row(item: reframed, span: piece))
            } else {
                rowsOut.append(contentsOf: result.items.map { Row(item: $0, span: piece) })
            }
        }

        let items = rowsOut.map(\.item)
        guard RefinementGuard.preservesEverything(in: items, found: [row.item]) else {
            return .failure(SplitRefusal(verdict: .rulesStronger, reason: .splitLosesContent))
        }
        guard executablesAreSubset(items, of: [row.item]) else {
            return .failure(SplitRefusal(verdict: .unresolved, reason: .splitCreatesExecution))
        }
        return .success(rowsOut)
    }

    static func carriedContext(
        into piece: AtomSpan,
        units: [AtomSpan],
        relations: [UnitRelation],
        transcript: String,
        atoms: [SemanticAtom]
    ) -> String? {
        guard let target = units.firstIndex(where: { $0.contains(piece.first) }) else { return nil }
        for relation in relations where relation.kind == .givesContextTo && relation.to == target {
            guard relation.from < units.count,
                  let source = Atoms.slice(transcript, atoms, units[relation.from]),
                  let context = RuleBasedThoughtExtractor.leadingTemporalContext(in: source) else { continue }
            return context
        }
        return nil
    }

    // MARK: Relations

    static func arbitrateRelations(
        _ rows: [Row],
        units: [AtomSpan],
        relations: [UnitRelation],
        transcript: String,
        atoms: [SemanticAtom],
        policy: ArbitrationPolicy,
        decisions: inout [ArbitrationDecision]
    ) -> [Row] {
        var rows = rows
        for relation in relations {
            guard relation.from < units.count, relation.to < units.count else { continue }
            let source = units[relation.from]
            let target = units[relation.to]
            var note = decision(.relation, .unresolved, .relationNotActedOn, .none)
            note.relation = relation.kind

            switch relation.kind {
            case .replaces, .cancels:
                // Rows about the earlier thought that are not also about the
                // later one: those are what the correction or withdrawal took
                // back, if the model is right.
                let affected = rows.indices.filter { rows[$0].span.overlaps(target) && !rows[$0].span.overlaps(source) }
                let resolved: DecisionReason = relation.kind == .replaces ? .correctionAlreadyResolved : .withdrawalAlreadyResolved
                if affected.isEmpty {
                    note.verdict = .agree
                    note.reason = resolved
                } else if affected.contains(where: { isExecutable(rows[$0].item) }) {
                    note.reason = relation.kind == .replaces ? .correctedRowStillExecutes : .withdrawnRowStillExecutes
                    if policy.withdrawOn.contains(relation.kind) {
                        for index in affected { rows[index].item = withdrawn(rows[index].item) }
                        note.effect = .withdrewExecution
                    }
                } else if affected.contains(where: { rows[$0].item.organization.itemType.isActionable }) {
                    note.reason = .correctedRowStillOwed
                    if policy.withdrawOn.contains(relation.kind) {
                        for index in affected { rows[index].item = flagged(rows[index].item) }
                        note.effect = .flaggedReview
                    }
                } else {
                    note.reason = resolved
                    note.verdict = .agree
                }

            case .isConditionFor:
                let affected = rows.indices.filter { rows[$0].span.overlaps(target) && !rows[$0].span.overlaps(source) }
                let held = affected.allSatisfy { !isExecutable(rows[$0].item) || rows[$0].item.organization.state.kind != .resolved }
                if affected.isEmpty || held {
                    note.verdict = .agree
                    note.reason = .conditionAlreadyHeld
                } else {
                    let first = min(source.first, target.first)
                    let last = max(source.last, target.last)
                    let supported = AtomSpan(first: first, last: last)
                        .flatMap { Atoms.slice(transcript, atoms, $0) }
                        .map { ConditionalIntentScope.dependency(in: $0) != nil } ?? false
                    note.reason = supported ? .conditionSupportedByRules : .conditionModelOnly
                    if policy.withdrawOn.contains(.isConditionFor) {
                        for index in affected where isExecutable(rows[index].item) {
                            rows[index].item = withdrawn(rows[index].item)
                        }
                        note.effect = .withdrewExecution
                    }
                }

            case .isMessageContentOf:
                // The content's own rows, where they are not part of the row
                // that carries the message.
                let affected = rows.indices.filter { rows[$0].span.overlaps(source) && !rows[$0].span.overlaps(target) }
                if affected.isEmpty || !affected.contains(where: { isExecutable(rows[$0].item) }) {
                    note.verdict = .agree
                    note.reason = .messageContentAlreadyInside
                } else {
                    note.reason = .messageContentExecutes
                    if policy.withdrawOn.contains(.isMessageContentOf) {
                        for index in affected where isExecutable(rows[index].item) {
                            rows[index].item = withdrawn(rows[index].item)
                        }
                        note.effect = .withdrewExecution
                    }
                }

            case .givesContextTo, .continues, .unclear:
                // Consumed by segmentation where it applies; recorded here so
                // the harness can count how often the model says it.
                break
            }
            decisions.append(note)
        }
        return rows
    }

    // MARK: Entities

    static func arbitrateEntities(
        _ rows: [Row],
        entities: [EntityEvidence],
        transcript: String,
        atoms: [SemanticAtom],
        policy: ArbitrationPolicy,
        decisions: inout [ArbitrationDecision]
    ) -> [Row] {
        var rows = rows
        for entity in entities {
            guard let words = Atoms.slice(transcript, atoms, entity.span) else { continue }
            let entityTokens = Set(Atoms.atomize(words).map { Atoms.folded(words[$0.range]) })
            let owners = rows.indices.filter { index in
                guard let person = rows[index].item.organization.personName else { return false }
                let personTokens = Set(Atoms.atomize(person).map { Atoms.folded(person[$0.range]) }).subtracting([""])
                return !personTokens.isEmpty && personTokens.isSubset(of: entityTokens)
                    && rows[index].span.overlaps(entity.span)
            }
            if owners.isEmpty {
                let verdict: Verdict = entity.kind == .person ? .unresolved : .agree
                let reason: DecisionReason = entity.kind == .person ? .modelOnlyPerson : .entityNotOnARow
                decisions.append(decision(.entity, verdict, reason, .none))
                continue
            }
            for index in owners {
                if entity.kind == .person {
                    decisions.append(decision(.entity, .agree, .personConfirmed, .none))
                    continue
                }
                let deterministic = PersonMentionResolver.entityKind(in: rows[index].item.sourceQuote)
                if deterministic == .person {
                    decisions.append(decision(.entity, .rulesStronger, .personKeptByRules, .keptRules))
                    continue
                }
                guard policy.removeUnconfirmedPersons else {
                    decisions.append(decision(.entity, .unresolved, .entityRemovalDisabled, .none))
                    continue
                }
                let bothReject = deterministic != .unknown
                rows[index].item = withoutPerson(rows[index].item)
                decisions.append(decision(
                    .entity,
                    bothReject ? .agree : .modelAddsStructure,
                    bothReject ? .personRejectedByBoth : .personRejectedOnTie,
                    .clearedPerson
                ))
            }
        }
        return rows
    }

    // MARK: Row edits, every one of them capability-removing

    static func isExecutable(_ item: ExtractedThought) -> Bool {
        let organization = item.organization
        return organization.reminderDate != nil || organization.dueDate != nil
            || organization.recurrenceRule != nil || organization.locationIntent != nil
    }

    static func isExecutableOrOwed(_ item: ExtractedThought) -> Bool {
        isExecutable(item) || item.organization.itemType.isActionable
    }

    static func withdrawn(_ item: ExtractedThought) -> ExtractedThought {
        let old = item.organization
        return rebuilt(item, organization: OrganizedThought(
            itemType: old.itemType,
            category: old.category,
            priority: old.priority,
            personName: old.personName,
            dueDate: nil,
            reminderDate: nil,
            reminderDelivery: .none,
            recurrenceRule: nil,
            needsClarification: true,
            temporalIntent: old.temporalIntent,
            locationIntent: nil,
            state: old.state
        ), needsReview: true)
    }

    static func flagged(_ item: ExtractedThought) -> ExtractedThought {
        rebuilt(item, organization: item.organization, needsReview: true)
    }

    static func withoutPerson(_ item: ExtractedThought) -> ExtractedThought {
        let old = item.organization
        return rebuilt(item, organization: OrganizedThought(
            itemType: old.itemType == .personFollowUp ? .task : old.itemType,
            category: old.category == .people ? .general : old.category,
            priority: old.priority,
            personName: nil,
            dueDate: old.dueDate,
            reminderDate: old.reminderDate,
            reminderDelivery: old.reminderDelivery,
            recurrenceRule: old.recurrenceRule,
            needsClarification: old.needsClarification,
            temporalIntent: old.temporalIntent,
            locationIntent: old.locationIntent,
            state: old.state
        ), needsReview: item.needsReview)
    }

    static func rebuilt(_ item: ExtractedThought, organization: OrganizedThought, needsReview: Bool) -> ExtractedThought {
        ExtractedThought(
            sourceQuote: item.sourceQuote,
            rawQuote: item.rawQuote,
            wasRepaired: item.wasRepaired,
            analysisText: item.analysisText,
            suggestedTitle: item.suggestedTitle,
            organization: organization,
            confidence: item.confidence,
            needsReview: needsReview,
            shoppingGroup: item.shoppingGroup
        )
    }

    /// Every executable value in `items` already exists somewhere in `rules`.
    static func executablesAreSubset(_ items: [ExtractedThought], of rules: [ExtractedThought]) -> Bool {
        let reminders = Set(rules.compactMap(\.organization.reminderDate))
        let dues = Set(rules.compactMap(\.organization.dueDate))
        let places = rules.compactMap(\.organization.locationIntent)
        let recurrences = rules.compactMap(\.organization.recurrenceRule)
        return items.allSatisfy { item in
            let organization = item.organization
            if let date = organization.reminderDate, !reminders.contains(date) { return false }
            if let date = organization.dueDate, !dues.contains(date) { return false }
            if let place = organization.locationIntent, !places.contains(place) { return false }
            if let rule = organization.recurrenceRule, !recurrences.contains(rule) { return false }
            return true
        }
    }

    // MARK: Plumbing

    static func decision(
        _ topic: DecisionTopic, _ verdict: Verdict, _ reason: DecisionReason, _ effect: DecisionEffect
    ) -> ArbitrationDecision {
        ArbitrationDecision(topic: topic, verdict: verdict, reason: reason, effect: effect)
    }

    static func with(_ result: ArbitrationResult, _ decisions: [ArbitrationDecision]) -> ArbitrationResult {
        var copy = result
        copy.decisions = decisions
        return copy
    }
}
