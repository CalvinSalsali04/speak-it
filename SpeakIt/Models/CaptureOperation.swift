import Foundation

/// What a person is asking Speak It to *do* with a capture.
///
/// Before this existed, extraction had exactly one verb: create. Every
/// utterance became an item, so "Don't buy milk" became a Buy milk task and
/// "Cancel the dentist reminder" became a task named "Cancel dentist reminder".
/// Both are the reverse of what was said, which is the worst failure this app
/// can have — it is worse than dropping the capture, because the person is not
/// told their meaning was inverted.
///
/// Operations are deliberately *not* persisted models. They describe an intent
/// carried by one capture, resolved at organization time against items that
/// already exist. Nothing here changes the schema.
enum CaptureOperation: String, Codable, Equatable, Sendable {
    /// Make a new item. The default and by far the common case.
    case create
    /// Stop or remove something that already exists.
    case cancel
    /// Mark something that already exists as done.
    case complete
    /// Move something that already exists to a new moment. Non-destructive:
    /// the item keeps everything else about itself and only its timing moves.
    case reschedule
    /// Change an existing row's meaning. Extraction can identify the request
    /// before it can safely resolve every field of the replacement, so an
    /// ungrounded revision is held for review rather than creating a duplicate.
    case revise
    /// Withdraw the capture in progress. Produces nothing at all.
    case retract
}

/// Whether an utterance asserts or denies its content.
///
/// Kept separate from `CaptureOperation` because they answer different
/// questions: polarity is what the sentence *says*, operation is what the app
/// should *do*. "Don't forget Catherine called" is negative in form and still a
/// `.create` — the negation is emphasis attached to remembering, not to the
/// fact. Collapsing the two is exactly how "don't" gets stripped and reversed.
enum CapturePolarity: String, Codable, Equatable, Sendable {
    case positive
    case negative
}

/// A request to act on something the person already has.
///
/// `target` is the person's own words for what to act on — "the dentist
/// reminder", "the gym" — not a resolved identifier. Matching it to a real item
/// is a separate concern that needs the store; extraction only reports what was
/// asked for.
struct CaptureOperationRequest: Equatable, Sendable {
    let operation: CaptureOperation
    let polarity: CapturePolarity
    /// What to act on, in the person's words. `nil` for a bare retraction,
    /// which refers to the capture itself and needs no target.
    let target: String?
    /// The words this was read from, preserved for review and provenance.
    var sourceQuote: String
    /// True when the target is a pronoun or otherwise unresolvable, so the app
    /// must ask rather than guess which item to cancel or complete. Guessing
    /// wrong here destroys the wrong reminder.
    let needsReview: Bool

    /// True for "cancel every reminder" and its relatives. A broad request is
    /// never executed automatically at any confidence, because the blast radius
    /// is everything the person owns.
    let isBroad: Bool

    /// For `.reschedule` only: the person's words for the new moment — "Friday",
    /// "3 PM", "an hour". Kept as words rather than a resolved date because
    /// resolving needs the store (a relative "an hour" moves the *scheduled*
    /// time, not the clock) and extraction only reports what was asked.
    let newTimingText: String?
    /// A spoken old time in "change the saved dentist call from tomorrow to
    /// Friday". The repository verifies it against the selected row before
    /// applying the new time; a stale target stays in review.
    let expectedOldTimingText: String?

    /// True when an operation has already been resolved inside this capture and
    /// must not also be applied to the repository as an operation on an older
    /// item.
    ///
    /// "Buy milk and tomorrow I need to, never mind" retracts the fragment and
    /// nothing else. Read as a whole-capture retraction it discarded the milk
    /// too — a thought the person had finished saying, deleted because of one
    /// they had not. The request still travels with the extraction so the
    /// refinement model stays out of a capture whose words have been withdrawn.
    /// The same marker is used when "skip the pharmacy" has already removed the
    /// pharmacy sibling from a multi-stop capture.
    let isScoped: Bool

    /// Ordered word occurrences in the operation detector's input, not a
    /// word-set match against another clause that happens to read the same.
    /// Transient extraction evidence; no persistent model changes.
    var sourceUnitIDs: Set<Int> = []
    /// The exact earlier intention withdrawn by a scoped local operation.
    /// Empty for an operation against a saved item or an unresolved target.
    var localTargetUnitIDs: Set<Int> = []
    /// Present only when the speaker supplied a complete quoted old title and
    /// complete quoted replacement in one saved-row edit command.
    var savedItemRevision: SavedItemRevision?
    /// An explicit old/new quantity for an identified saved purchase. The
    /// repository still has to prove a unique title/object match before edit.
    var savedQuantityRevision: SavedQuantityRevision?
    /// Remove a named old notification while retaining its saved Today task.
    var savedAlertRemoval: SavedAlertRemoval?
    /// One explicitly requested field change to a saved action — its person
    /// or its place — read from the speaker's own change request. The
    /// repository still has to resolve one target and prove the old value.
    var savedFieldRevision: SavedFieldRevision?
    /// A complete current-source delta bound to a value snapshot captured
    /// BEFORE asynchronous interpretation, never a model-authored target ID.
    var savedAtomicRevision: SavedAtomicRevision?
    var savedRevisionIntent: SavedRevisionIntent? = nil

    var independentCreationUnitIDs: Set<Int> = []
    var captureSource: String? = nil
    init(
        operation: CaptureOperation,
        polarity: CapturePolarity = .negative,
        target: String?,
        sourceQuote: String,
        needsReview: Bool,
        isBroad: Bool = false,
        newTimingText: String? = nil,
        expectedOldTimingText: String? = nil,
        isScoped: Bool = false
    ) {
        self.operation = operation
        self.polarity = polarity
        self.target = target
        self.sourceQuote = sourceQuote
        self.needsReview = needsReview
        self.isBroad = isBroad
        self.newTimingText = newTimingText
        self.expectedOldTimingText = expectedOldTimingText
        self.isScoped = isScoped
    }
}

/// Version-five capture-owned record of one saved-item operation. The source
/// remains immutable on `CaptureSession`; this small record links it to the
/// specific saved target and records both the requested and applied effect.
/// It is written in the same SwiftData save as the target mutation or the
/// pending review row, so reopening the store can distinguish an unanswered
/// question from an already performed operation.
struct CaptureOperationState: Codable, Equatable, Sendable {
    enum Phase: String, Codable, Sendable {
        case pendingChoice
        case performed
        case dismissed
    }

    var phase: Phase
    let operation: CaptureOperation
    let sourceQuote: String
    let targetWords: String?
    let candidateIDs: [UUID]
    var reviewItemID: UUID? = nil
    var targetID: UUID?
    var targetTitle: String?
    let expectedOldTimingText: String?
    let newTimingText: String?
    var oldDueDate: Date?
    var oldReminderDate: Date?
    var newDueDate: Date?
    var newReminderDate: Date?
    var resolvedAt: Date?
    var oldTitle: String? = nil
    var newTitle: String? = nil
    /// Field-level record of an executed saved-item revision, so the change
    /// can be shown and reversed from the capture that made it.
    var revisedField: String? = nil
    var oldFieldValue: String? = nil
    var newFieldValue: String? = nil
    var oldPersonName: String? = nil
    /// Additive fields in the existing V5 Codable blob. No SwiftData model or
    /// frozen schema shape changes. Older receipts decode these as nil.
    var atomicRevision: SavedAtomicRevision.Receipt? = nil
    var pendingSavedRevision: SavedRevisionIntent? = nil
    var reminderSynchronizationPending: Bool? = nil
    /// Content-free delivery state; a durable edit and an armed alert are
    /// separate facts. Older V5 receipts decode this additive field as nil.
    var reminderSynchronizationStatus: String? = nil

    static func read(from data: Data?) -> Self? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(Self.self, from: data)
    }
}

/// A complete requested saved delta whose target requires a real user choice.
/// All candidate snapshots are actual pre-interpretation context, never model IDs.
struct SavedRevisionIntent: Codable, Equatable, Sendable {
    let targetWords: String
    let replacementAction: String?
    let timingText: String?
    let sourceQuote: String
    let captureSource: String
    let referenceDate: Date
    let timeZoneIdentifier: String
    let candidates: [SavedAtomicRevision.Snapshot]
    var removesAlert: Bool? = nil

    static func read(_ ownedSource: String, captureSource: String, snapshots: [SavedAtomicRevision.Snapshot],
                     referenceDate: Date, calendar: Calendar) -> Self? {
        if let removal = SavedAtomicRevision.alertRemovalEvidence(ownedSource, referenceDate: referenceDate, calendar: calendar) {
            let matches = snapshots.filter { $0.title == removal.title && !$0.archived && $0.completed == nil && !$0.needsClarification }
            var result = Self(targetWords: removal.title, replacementAction: nil, timingText: nil,
                sourceQuote: ownedSource, captureSource: captureSource, referenceDate: referenceDate,
                timeZoneIdentifier: calendar.timeZone.identifier, candidates: matches)
            result.removesAlert = true
            return result
        }
        let change = #"(?is)^\s*(?:please\s+)?(?:change|update|revise|edit)\s+(?:(?:my|the)\s+)?saved\s+["“]([^"”]+)["”]\s*(?:task|reminder|item)?\s+to\s+(.+?)\s+instead[.!]?\s*$"#
        let move = #"(?is)^\s*(?:please\s+)?(?:move|reschedule)\s+(?:(?:my|the)\s+)?saved\s+(?:task|reminder|item)\s+(?:to\s+)?(.+?)\s+to\s+([^.!?]+)[.!]?(?:\s+There\s+are\s+[^.!?]+(?:versions|items)[^.!?]*[.!]?)?\s*$"#
        for (pattern,isMove) in [(change,false),(move,true)] {
            guard let regex = NSRegularExpression.speakItCached(pattern),
                  let match = regex.firstMatch(in: ownedSource,range: NSRange(ownedSource.startIndex...,in: ownedSource)),
                  let targetRange = Range(match.range(at: 1),in: ownedSource),
                  let deltaRange = Range(match.range(at: 2),in: ownedSource) else { continue }
            let target = String(ownedSource[targetRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            let delta = String(ownedSource[deltaRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !target.isEmpty, !delta.isEmpty else { return nil }
            let active = snapshots.filter { !$0.archived && $0.completed == nil && !$0.needsClarification }
            let matches = active.filter { isMove ? $0.title.localizedCaseInsensitiveContains(target) : $0.title == target }
            return Self(targetWords: target,replacementAction: isMove ? nil : delta,timingText: isMove ? delta : nil,
                sourceQuote: ownedSource,captureSource: captureSource,referenceDate: referenceDate,
                timeZoneIdentifier: calendar.timeZone.identifier,candidates: matches)
        }
        return nil
    }

    func confirmedRevision(for snapshot: SavedAtomicRevision.Snapshot) -> SavedAtomicRevision? {
        guard candidates.contains(snapshot) else { return nil }
        if removesAlert == true {
            var calendar = Calendar(identifier: .gregorian)
            guard let zone = TimeZone(identifier: timeZoneIdentifier) else { return nil }
            calendar.timeZone = zone
            guard var result = SavedAtomicRevision.read(sourceQuote, snapshots: [snapshot], referenceDate: referenceDate, calendar: calendar), result.removesAlert else { return nil }
            result.captureSource = captureSource; result.confirmedIntent = self
            return result
        }
        var result = SavedAtomicRevision(expected: snapshot,replacementAction: replacementAction ?? snapshot.title,
            timingText: timingText,referenceDate: referenceDate,timeZoneIdentifier: timeZoneIdentifier,sourceQuote: sourceQuote)
        result.captureSource = captureSource; result.confirmedIntent = self
        return result
    }
}

struct SavedAtomicRevision: Equatable, Sendable {
    struct Snapshot: Codable, Equatable, Sendable {
        let id: UUID
        let parentID: UUID
        let original: String
        let title: String
        let kind: String
        let category: String
        let created: Date
        let modified: Date
        let person: String?
        let due: Date?
        let reminder: Date?
        let completed: Date?
        let archived: Bool
        let archivedAt: Date?
        let reviewed: Bool
        let needsClarification: Bool
        let confidence: Double
        let priority: Int
        let temporal: Data?
        let location: Data?
        let semanticState: String?
        let semanticGap: String?
        var parentOriginal: String? = nil
        var parentCreated: Date? = nil
        var temporalKind: String? = nil
        var reminderTriggerKind: String? = nil
    }
    struct Receipt: Codable, Equatable, Sendable {
        let before: Snapshot
        let after: Snapshot
        let replacementEvidence: String
        let timingEvidence: String?
    }
    let expected: Snapshot
    let replacementAction: String
    let timingText: String?
    let referenceDate: Date
    let timeZoneIdentifier: String
    let sourceQuote: String

    /// Exact full capture and owned edit are distinct for a mixed capture.
    /// These values are transient; immutable CaptureSession still owns all words.
    var captureSource: String? = nil
    var removesAlert: Bool = false
    var confirmedIntent: SavedRevisionIntent? = nil

    /// Deliberately occurrence-grounded and whole-request scoped. The grammar
    /// accepts a complete explicit old title and complete replacement; a verb
    /// and person overlap never identifies the target. Unparsed tail content
    /// remains review rather than being marked handled after a partial edit.
    static func read(_ source: String, snapshots: [Snapshot], referenceDate: Date,
                     calendar: Calendar) -> Self? {
        if let removal = readAlertRemoval(source, snapshots: snapshots,
                                          referenceDate: referenceDate, calendar: calendar) { return removal }
        let pattern = #"(?is)^\s*(?:please\s+)?(?:change|update|revise|edit)\s+(?:(?:my|the|this|that)\s+)?(?:(?:saved|existing|current)\s+)?(?:(?:task|reminder|item|entry)\s+)?[\"“]([^\"”]+)[\"”]\s*(?:(?:task|reminder|item|entry)\s+)?to\s+(.+?)\s*$"#
        guard let regex = NSRegularExpression.speakItCached(pattern),
              let match = regex.firstMatch(in: source, range: NSRange(source.startIndex..., in: source)),
              let oldRange = Range(match.range(at: 1), in: source),
              let tailRange = Range(match.range(at: 2), in: source) else { return nil }
        let old = String(source[oldRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        let candidates = snapshots.filter { $0.title == old && !$0.archived && $0.completed == nil && !$0.needsClarification }
        guard candidates.count == 1, let expected = candidates.first else { return nil }
        var tail = String(source[tailRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        tail = tail.replacingOccurrences(of: #"(?i)\.?\s+(?:keep\s+it\s+(?:as\s+)?|it\s+(?:must\s+)?(?:remain|stays?)\s+)one\s+(?:task|reminder|item)\.?\s*$"#, with: "", options: .regularExpression)
        tail = tail.trimmingCharacters(in: .whitespacesAndNewlines)
        var timing: String?
        if let split = tail.range(of: #"(?i)\s+instead\s*,\s*"#, options: .regularExpression) {
            timing = String(tail[split.upperBound...]).trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ".")))
            tail = String(tail[..<split.lowerBound])
        } else {
            tail = tail.replacingOccurrences(of: #"(?i)\s+instead[.!]?\s*$"#, with: "", options: .regularExpression)
        }
        tail = tail.trimmingCharacters(in: .whitespacesAndNewlines)
        // Quoted old/new titles identify text occurrences, not a typed field
        // patch. Keep these general revisions on the occurrence-linked review
        // path; do not infer which person, quantity, timing or condition to
        // replace, preserve or clear from a new quoted title. Qualified
        // unquoted action edits and explicit alert removal retain their paths.
        guard !tail.hasPrefix("\""), !tail.hasPrefix("“") else { return nil }
        tail = tail.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ".")))
        guard !tail.isEmpty, !tail.contains(";"), !tail.contains("\n"),
              tail.range(of: #"[.!?]\s+\p{L}"#, options: .regularExpression) == nil,
              source.contains(tail), timing.map({ !$0.isEmpty && source.contains($0) }) ?? true,
              ActionabilityReader.read(tail).belongsOnToday else { return nil }
        if let timing {
            guard !timing.contains(";"), !timing.contains("\n"),
                  timing.range(of: #"[.!?]\s+\p{L}|(?i)\b(?:also|actually|instead|cancel|remove|buy|ask|tell|call|email|text|pack|do\s+not|don.t|unless|if)\b"#,
                               options: .regularExpression) == nil else { return nil }
        }
        return Self(expected: expected, replacementAction: tail, timingText: timing,
                    referenceDate: referenceDate, timeZoneIdentifier: calendar.timeZone.identifier,
                    sourceQuote: source)
    }
    static func alertRemovalEvidence(_ source: String, referenceDate: Date,
                                     calendar: Calendar) -> (title: String, dueDay: Date?)? {
        let pattern = #"(?is)^\s*(?:please\s+)?(?:cancel|remove|turn\s+off)\s+(?:only\s+)?the\s+(?:timed\s+alert|alert|notification|alarm)\s+(?:on|from|for)\s+(?:(?:my|the)\s+)?saved\s+["“]([^"”]+)["”]\s*(?:task|reminder|item)?[.!]?\s*(.*)$"#
        guard let regex = NSRegularExpression.speakItCached(pattern),
              let match = regex.firstMatch(in: source,range: NSRange(source.startIndex...,in: source)),
              let titleRange = Range(match.range(at: 1),in: source),
              let tailRange = Range(match.range(at: 2),in: source) else { return nil }
        let title = String(source[titleRange])
        var dueDay: Date?
        let tail = String(source[tailRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        let statements = tail.split(whereSeparator: { ".!?".contains($0) }).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        for statement in statements where !statement.isEmpty {
            if statement.range(of: #"(?i)^(?:i\s+still\s+(?:want|need)\s+to\s+do\s+it|do\s+not\s+(?:complete|delete|remove)\s+the\s+task)$"#,options: .regularExpression) != nil { continue }
            let keep = #"(?i)^keep\s+(?:the\s+)?task(?:\s+and\s+its\s+(.+?)\s+due\s+(?:day|date))?$"#
            guard let regex = NSRegularExpression.speakItCached(keep),
                  let m = regex.firstMatch(in: statement,range: NSRange(statement.startIndex...,in: statement)) else { return nil }
            if let day = Range(m.range(at: 1),in: statement) {
                let reading = ThoughtOrganizer.organize("Check the task on " + String(statement[day]),referenceDate: referenceDate,calendar: calendar)
                guard let wanted = reading.dueDate, !reading.needsClarification, !reading.temporalIntent.kind.carriesTimeOfDay else { return nil }
                if let previous = dueDay, !calendar.isDate(wanted, inSameDayAs: previous) { return nil }
                dueDay = wanted
            }
        }
        return (title, dueDay)
    }
    private static func readAlertRemoval(_ source: String, snapshots: [Snapshot], referenceDate: Date,
                                         calendar: Calendar) -> Self? {
        guard let evidence = alertRemovalEvidence(source, referenceDate: referenceDate, calendar: calendar) else { return nil }
        let candidates = snapshots.filter { $0.title == evidence.title && !$0.archived && $0.completed == nil && !$0.needsClarification }
        guard candidates.count == 1, let expected = candidates.first, expected.reminder != nil else { return nil }
        if let wanted = evidence.dueDay {
            guard let due = expected.due, calendar.isDate(wanted, inSameDayAs: due) else { return nil }
        }
        var result = Self(expected: expected,replacementAction: expected.title,timingText: nil,
                          referenceDate: referenceDate,timeZoneIdentifier: calendar.timeZone.identifier,sourceQuote: source)
        result.removesAlert = true
        return result
    }

}

/// Source-grounded, field-complete title replacement for a saved action.
/// The two occurrence sets are distinct even when a word appears in both
/// titles. A deictic reference, partial changed field, or missing quote cannot
/// construct this value and remains a visible `.revise` review request.
struct SavedItemRevision: Equatable, Sendable {
    let oldTitle: String
    let replacementAction: String
    let oldTitleUnitIDs: Set<Int>
    let replacementUnitIDs: Set<Int>

    /// A saved-row noun may occur before or after its quoted title. An
    /// explicit saved/existing/current marker can also license the row
    /// reference. The licence must occur outside both quoted action spans.
    private static func quotedFields(_ source: String) -> (old: Range<String.Index>, replacement: Range<String.Index>, end: String.Index)? {
        let pattern = #"(?i)^\s*(?:please\s+)?(?:change|update|revise|edit)\s+(?:(?:the|my|that|this)\s+)?(?:(?:existing|saved|current)\s+)?(?:(?:task|reminder|item|entry)\s+)?(?:from\s+)?[\"“]([^\"”]+)[\"”]\s*(?:(?:task|reminder|item|entry)\s+)?to\s+[\"“]([^\"”]+)[\"”]"#
        guard let regex = NSRegularExpression.speakItCached(pattern),
              let match = regex.firstMatch(in: source, range: NSRange(source.startIndex..., in: source)),
              let wholeRange = Range(match.range, in: source),
              let oldRange = Range(match.range(at: 1), in: source),
              let replacementRange = Range(match.range(at: 2), in: source) else { return nil }
        let rowReference = String(source[..<oldRange.lowerBound]) + " " + String(source[oldRange.upperBound..<replacementRange.lowerBound])
        guard rowReference.range(of: #"(?i)\b(?:existing|saved|current|task|reminder|item|entry)\b"#, options: .regularExpression) != nil else { return nil }
        return (oldRange, replacementRange, wholeRange.upperBound)
    }

    /// Recognized quoted row edits with an unparsed tail still cannot donate
    /// a date from their replacement action to generic saved rescheduling.
    /// The entire capture remains visible for review rather than losing words.
    static func hasQuotedReplacement(_ source: String) -> Bool { quotedFields(source) != nil }

    static func read(_ source: String) -> Self? {
        guard let fields = quotedFields(source),
              String(source[fields.end...]).trimmingCharacters(in: .whitespacesAndNewlines)
                .range(of: #"^[.!?]?$"#, options: .regularExpression) != nil else { return nil }
        let oldRange = fields.old, replacementRange = fields.replacement
        let oldTitle = String(source[oldRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        let replacement = String(source[replacementRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !oldTitle.isEmpty, !replacement.isEmpty else { return nil }
        let ledger = SourceUnitLedger(source)
        let oldIDs = ledger.ids(in: oldRange)
        let replacementIDs = ledger.ids(in: replacementRange)
        guard !oldIDs.isEmpty, !replacementIDs.isEmpty,
              oldIDs.isDisjoint(with: replacementIDs) else { return nil }
        return Self(oldTitle: oldTitle, replacementAction: replacement,
                    oldTitleUnitIDs: oldIDs, replacementUnitIDs: replacementIDs)
    }
}

struct SavedQuantityRevision: Equatable, Sendable {
    let objectPhrase: String
    let pluralObject: String
    let oldQuantity: String
    let newQuantity: String
    let existingQuality: String
    let addedConstraint: String

    static func read(_ source: String) -> Self? {
        let spoken = source.replacingOccurrences(
            of: #"(?i)^\s*(?:(?:um|uh|er)\s*,?\s*)?let me think[.!?]\s*"#,
            with: "", options: .regularExpression
        )
        let pattern = #"(?i)^\s*(?:please\s+)?(?:update|change|correct|revise)\s+(?:the|my)\s+(?:saved|existing)\s+([\p{L}\s]+?)\s+purchase\s+from\s+(one|two|three|four|five|six|seven|eight|nine|ten|\d+)\s+([\p{L}]+)\s+to\s+(one|two|three|four|five|six|seven|eight|nine|ten|\d+)\s+([\p{L}]+)\b"#
        guard let regex = NSRegularExpression.speakItCached(pattern),
              let match = regex.firstMatch(in: spoken, range: NSRange(spoken.startIndex..., in: spoken)),
              let whole = Range(match.range, in: spoken) else { return nil }
        func group(_ index: Int) -> String? {
            guard let range = Range(match.range(at: index), in: spoken) else { return nil }
            return String(spoken[range]).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }
        guard let object = group(1), let old = group(2), let plural = group(3),
              let new = group(4), let repeatedPlural = group(5),
              plural == repeatedPlural, old != new,
              let singular = object.split(separator: " ").last,
              plural.hasPrefix(singular) else { return nil }

        // Keep the operation's explanation and audit boundary only when every
        // following statement belongs to this saved edit. An independent
        // affirmative action must go through normal mixed-capture extraction.
        var tail = String(spoken[whole.upperBound...]).lowercased()
        for cue in [#"\bi\s+am\s+correcting\b"#, #"\bright\s*,?\s*okay\b"#,
                    #"\bdo\s+not\s+change\b"#, #"\bthe\s+repeated\s+number\b"#,
                    #"\bretain\s+an\s+audit\s+connection\b"#] {
            tail = tail.replacingOccurrences(of: "(?i)\\s+(" + cue + ")",
                                            with: ". $1", options: .regularExpression)
        }
        let statements = tail.split(whereSeparator: { ".!?".contains($0) })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard let qualityStatement = statements.first,
              qualityStatement.hasPrefix("keep them "),
              let join = qualityStatement.range(of: " and "),
              statements.dropFirst().allSatisfy({ statement in
                  let hasIndependentAction = statement.range(
                      of: #"(?i)\b(?:also|then|and)\s+(?!do\s+not\b)(?:please\s+)?\#(ActionabilityReader.actionVerb)\b"#,
                      options: .regularExpression
                  ) != nil
                  return !hasIndependentAction &&
                      ["i am correcting the quantity", "right okay", "right, okay",
                       "do not change", "the repeated number", "retain an audit connection"]
                          .contains(where: statement.hasPrefix)
              }) else { return nil }
        let quality = String(qualityStatement[qualityStatement.index(
            qualityStatement.startIndex, offsetBy: "keep them ".count)..<join.lowerBound])
        let constraint = String(qualityStatement[join.upperBound...])
        guard !quality.isEmpty, !constraint.isEmpty else { return nil }
        return Self(objectPhrase: object, pluralObject: plural,
                    oldQuantity: old, newQuantity: new,
                    existingQuality: quality, addedConstraint: constraint)
    }

    func replacementTitle(for title: String) -> String? {
        let normalized = title.lowercased()
        let prefix = "buy \(oldQuantity) "
        guard normalized.hasPrefix(prefix),
              normalized.hasSuffix(" \(pluralObject)"),
              normalized.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
                  .contains(existingQuality[...]),
              objectPhrase.split(separator: " ").dropLast().allSatisfy({ word in
                  normalized.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
                      .contains(word)
              }) else { return nil }
        let oldEnd = title.index(title.startIndex, offsetBy: "buy ".count)
        let quantityEnd = title.index(oldEnd, offsetBy: oldQuantity.count)
        var revised = String(title[..<oldEnd]) + newQuantity + String(title[quantityEnd...])
        if !revised.localizedCaseInsensitiveContains(addedConstraint) {
            revised += " " + addedConstraint
        }
        return revised
    }
}

struct SavedAlertRemoval: Equatable, Sendable {
    let targetWords: String
    let dayWord: String
    let oldHour24: Int

    static func read(_ source: String) -> Self? {
        let spoken = source.replacingOccurrences(
            of: #"(?i)^\s*(?:(?:um|uh|er)\s*,?\s*)?let me think[.!?]\s*"#,
            with: "", options: .regularExpression
        )
        let pattern = #"(?i)^\s*(?:please\s+)?remove\s+the\s+(one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|\d{1,2})\s+(a\.?\s*m\.?|p\.?\s*m\.?)\s+notification\s+from\s+the\s+(?:saved|existing)\s+task\s+to\s+([\p{L}\s]+?)\s+(today|tomorrow)\b\s*,?\s*but\s+keep\s+the\s+task\s+on\s+\4'?s\s+list\b"#
        guard let regex = NSRegularExpression.speakItCached(pattern),
              let match = regex.firstMatch(in: spoken, range: NSRange(spoken.startIndex..., in: spoken)),
              let whole = Range(match.range, in: spoken) else { return nil }
        func group(_ index: Int) -> String? {
            guard let range = Range(match.range(at: index), in: spoken) else { return nil }
            return String(spoken[range]).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }
        guard let hourWord = group(1), let meridiem = group(2),
              let target = group(3), let day = group(4),
              let hour = Int(hourWord) ?? ["one": 1, "two": 2, "three": 3,
                                           "four": 4, "five": 5, "six": 6,
                                           "seven": 7, "eight": 8, "nine": 9,
                                           "ten": 10, "eleven": 11,
                                           "twelve": 12][hourWord],
              (1...12).contains(hour) else { return nil }
        let oldHour24 = meridiem.hasPrefix("p") ? (hour % 12) + 12 : hour % 12

        var tail = String(spoken[whole.upperBound...]).lowercased()
        for cue in [#"\bi\s+still\s+need\b"#, #"\bi\s+just\s+do\s+not\b"#,
                    #"\bdo\s+not\s+mark\b"#, #"\bright\s*,?\s*okay\b"#,
                    #"\bthe\s+equipment\s+delivery\s+reminder\b"#,
                    #"\bi\s+am\s+naming\s+the\s+call\b"#,
                    #"\bif\s+notification\s+removal\s+is\s+unavailable\b"#] {
            tail = tail.replacingOccurrences(of: "(?i)\\s+(" + cue + ")",
                                            with: ". $1", options: .regularExpression)
        }
        let statements = tail.split(whereSeparator: { ".!?".contains($0) })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let allowed = ["i still need to make the call", "i just do not need the alert",
                       "do not mark the task complete", "right okay", "right, okay",
                       "the equipment delivery reminder", "i am naming the call",
                       "if notification removal is unavailable"]
        guard !statements.isEmpty,
              statements.allSatisfy({ statement in
                  let independent = statement.range(
                      of: #"(?i)\b(?:also|then|and)\s+(?!do\s+not\b)(?:please\s+)?\#(ActionabilityReader.actionVerb)\b"#,
                      options: .regularExpression
                  ) != nil
                  return !independent && allowed.contains(where: statement.hasPrefix)
              }) else { return nil }
        return Self(targetWords: target, dayWord: day, oldHour24: oldHour24)
    }
}

/// The offset form of a reschedule destination: "back an hour", "by two
/// days". Measured from the item's scheduled moment, not from the clock —
/// pushing a 5 PM dentist back an hour means 6 PM whenever it is said.
enum RescheduleOffset {
    private static let numberWords: [String: Double] = [
        "a": 1, "an": 1, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5,
        "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10,
        "eleven": 11, "twelve": 12, "half": 0.5,
    ]

    static func parse(_ text: String) -> TimeInterval? {
        let pattern = #"^(?:back\s+)?(?:by\s+)?(a|an|half\s+an?|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|\d+)\s+(minutes?|mins?|hours?|days?|weeks?)$"#
        guard let regex = NSRegularExpression.speakItCached(pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges > 2,
              let amountRange = Range(match.range(at: 1), in: text),
              let unitRange = Range(match.range(at: 2), in: text) else {
            return nil
        }
        let amountWord = text[amountRange].lowercased()
        let amount = amountWord.hasPrefix("half")
            ? 0.5
            : (numberWords[amountWord] ?? Double(amountWord) ?? 1)
        let unit = text[unitRange].lowercased()
        let seconds: Double
        if unit.hasPrefix("min") { seconds = 60 }
        else if unit.hasPrefix("hour") { seconds = 3600 }
        else if unit.hasPrefix("week") { seconds = 7 * 24 * 3600 }
        else { seconds = 24 * 3600 }
        return amount * seconds
    }
}

/// What actually happened when an operation was applied to the store.
///
/// Modelled as an outcome rather than a thrown error because "I could not find
/// that reminder" is a normal, reportable result of a well-formed request, not
/// a failure of the app.
enum CaptureOperationOutcome: Equatable, Sendable {
    /// Exactly one confident match was found and acted on.
    case performed(operation: CaptureOperation, itemID: UUID, title: String)
    /// A confirmed broad operation affected the recorded set of saved rows.
    case performedMany(operation: CaptureOperation, count: Int)
    /// Several items matched. The person chooses; the app never guesses.
    case ambiguous(operation: CaptureOperation, candidateIDs: [UUID])
    /// Nothing matched. No item is invented to stand in for the request.
    case notFound(operation: CaptureOperation, target: String)
    /// A broad destructive request, held for explicit confirmation.
    case needsConfirmation(operation: CaptureOperation, candidateIDs: [UUID])
    /// The capture was withdrawn. Produces no items at all.
    case retracted

    var operation: CaptureOperation {
        switch self {
        case let .performed(operation, _, _): operation
        case let .performedMany(operation, _): operation
        case let .ambiguous(operation, _): operation
        case let .notFound(operation, _): operation
        case let .needsConfirmation(operation, _): operation
        case .retracted: .retract
        }
    }

    /// Whether this outcome created a new stored thought. Free captures are
    /// only spent on new thoughts, never on managing existing ones.
    var createsNewThought: Bool { false }
}

/// Holds what a `.needsConfirmation` review row would do if confirmed.
///
/// `CaptureOperation` is deliberately not a persisted model (see above), so
/// the request itself — cancel or complete, and which items it would touch —
/// has nowhere to live once the review row is saved. Without this, the row
/// could only be reclassified as an ordinary Task or Note, which is a
/// destructive request's confirmation path leading nowhere: the person is
/// told to "confirm in Needs review" and finds no control that does it. See
/// Docs/FINAL_RELEASE_AUDIT.md F-1.
///
/// Mirrors `RecurrenceStore`'s sidecar pattern rather than a schema change:
/// this is confirmation state for one still-open review row, not data with a
/// lifetime past that row being resolved.
enum PendingOperationStore {
    private static let key = "SpeakIt.pendingOperation.v1"
    private static let suiteName = "group.com.calvinwak.SpeakIt"
    private static var cachedRecords: [String: StoredPendingOperation]?

    struct StoredPendingOperation: Codable, Equatable, Sendable {
        let operation: CaptureOperation
        let candidateIDs: [UUID]
    }

    static func record(for itemID: UUID) -> StoredPendingOperation? {
        records[itemID.uuidString]
    }

    static func set(operation: CaptureOperation, candidateIDs: [UUID], for itemID: UUID) {
        var values = records
        values[itemID.uuidString] = StoredPendingOperation(
            operation: operation,
            candidateIDs: candidateIDs
        )
        records = values
    }

    static func remove(_ itemID: UUID) {
        var values = records
        values.removeValue(forKey: itemID.uuidString)
        records = values
    }

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: suiteName) ?? .standard
    }

    private static var records: [String: StoredPendingOperation] {
        get {
            if let cachedRecords { return cachedRecords }
            guard let data = defaults.data(forKey: key),
                  let value = try? JSONDecoder().decode([String: StoredPendingOperation].self, from: data) else {
                cachedRecords = [:]
                return [:]
            }
            cachedRecords = value
            return value
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue) else { return }
            cachedRecords = newValue
            defaults.set(data, forKey: key)
        }
    }
}


/// "Change the existing pickup item to the north branch", "Change that same
/// item so I ask Tessa for the price". One field of one saved action, said as
/// the speaker's own request. Quoted, reported, negated or hypothetical
/// wording never constructs this value; neither does a request whose new
/// value cannot be read. Constructing it executes nothing: the repository must
/// resolve exactly one saved target, find the old value in the matching role
/// of that target, and check that the item has not been edited since.
struct SavedFieldRevision: Equatable, Sendable {
    enum Field: String, Codable, Sendable { case person, place }

    let field: Field
    /// The change request sentence, exactly as spoken.
    let requestSentence: String
    /// Words that name the saved item, from the request or the sentence that
    /// introduced it ("the vegetable box reminder from yesterday").
    let itemWords: String
    /// The old value when the speaker said it ("not Maya", "from Central
    /// Depot"); otherwise read from the resolved target and checked against
    /// the rest of the capture.
    let statedOldValue: String?
    let newValue: String
    let requestRange: Range<String.Index>

    static let communicationVerb = #"(?:ask|email|call|text|message|tell|phone|contact|thank|send|invite|remind|meet|pay)"#

    /// The first word of a separately proved same-sentence continuation.
    /// The request range never includes that continuation's words.
    let continuationStart: String.Index?

    private static let requestPattern = #"(?i)^\s*(?:(?:so|and|then|also|ok(?:ay)?)\s*,?\s+)?(?:please\s+)?(?:change|update|correct|fix|amend|switch|edit)\s+(?:the|my|that|this)\s+((?:[\p{L}'’-]+\s+){0,6}?)(?:item|task|reminder|entry|booking)\b(.*)$"#

    private static func sentenceRanges(
        in source: String,
        includingQuotedStopsForReview: Bool = false
    ) -> [Range<String.Index>] {
        // A stop immediately inside a balanced closing quote can expose an
        // outside request to the review guard. It cannot establish an edit
        // or make the quoted words an existing saved-item introduction.
        let quotedStops: Set<String.Index>
        if includingQuotedStopsForReview {
            quotedStops = Set(QuotedSpeechScope.ranges(in: source).compactMap { quote -> String.Index? in
                let closing = source.index(before: quote.upperBound)
                guard closing > quote.lowerBound,
                      ".!?".contains(source[source.index(before: closing)]) else { return nil }
                return quote.upperBound
            })
        } else {
            quotedStops = []
        }
        var result: [Range<String.Index>] = []
        var start = source.startIndex
        var index = start
        while index < source.endIndex {
            let next = source.index(after: index)
            if ".!?".contains(source[index]),
               next == source.endIndex || source[next].isWhitespace,
               !QuotedSpeechScope.protects(index..<next, in: source) {
                result.append(start..<next)
                start = next
            } else if quotedStops.contains(next),
                      next == source.endIndex || source[next].isWhitespace {
                result.append(start..<next)
                start = next
            }
            index = next
        }
        if start < source.endIndex { result.append(start..<source.endIndex) }
        return result
    }

    private static func directRequest(_ sentence: String) -> NSTextCheckingResult? {
        guard let regex = NSRegularExpression.speakItCached(requestPattern),
              let match = regex.firstMatch(in: sentence, range: NSRange(sentence.startIndex..., in: sentence)),
              ClauseScope.read(sentence).act == .direct else { return nil }
        return match
    }

    /// Prevent a failed complete field reading from being reinterpreted by the
    /// generic saved-row detector after it has discarded the competing words.
    /// Quoted, reported and conditional commands grant no direct edit request.
    static func hasUnprovedFieldRequest(_ source: String) -> Bool {
        guard read(source) == nil else { return false }
        return sentenceRanges(in: source, includingQuotedStopsForReview: true).contains { range in
            let sentence = String(source[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard let regex = NSRegularExpression.speakItCached(requestPattern),
                  let match = regex.firstMatch(in: sentence, range: NSRange(sentence.startIndex..., in: sentence)),
                  ClauseScope.read(sentence).act == .direct,
                  let rest = Range(match.range(at: 2), in: sentence) else { return false }
            return sentence[rest].range(of: #"(?i)^\s*(?:so\b|to\b)"#,
                                         options: .regularExpression) != nil
        }
    }

    private static func nominalValue(_ value: String, allowsPlaceCoordination: Bool = false) -> Bool {
        let words = value.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard !words.isEmpty, words.count <= 10,
              value.range(of: #"^[\p{L}\p{N}'’ -]+$"#, options: .regularExpression) != nil,
              value.range(of: #"(?i)\b(?:i|we|you|he|she|they|it|if|unless|when|whenever|once|because|while|although|whether|then|also|but|or|instead|rather|not|never|no|will|shall|must|should|would|could|might|may|is|are|was|were|has|have|had|do|does|did|be|been|being)\b"#,
                          options: .regularExpression) == nil,
              value.range(of: #"(?i)\b(?:\#(ActionabilityReader.actionVerb)|\#(ActionabilityReader.headOnlyImperativeVerb))\b"#,
                          options: .regularExpression) == nil else { return false }
        if words.contains(where: { $0.caseInsensitiveCompare("and") == .orderedSame }) {
            guard allowsPlaceCoordination, words.filter({ $0.lowercased() == "and" }).count == 1 else { return false }
            // A conjunction of direction modifiers is still one place. Other
            // conjunctions need a stronger place-name certificate than this reader.
            let direction = #"(?:north|south|east|west|upper|lower|central|front|rear)"#
            guard value.range(of: #"(?i)^\#(direction)\s+and\s+\#(direction)\s+(?:branch|branches|wing|wings|entrance|entrances|depot|office|offices)$"#,
                              options: .regularExpression) != nil else { return false }
        }
        return true
    }

    private static func communicationTopic(_ value: String) -> Bool {
        guard nominalValue(value) else { return false }
        if RuntimeCurrentNominalProof.read(value) { return true }
        // Portable positive topics keep the existing supported short edit
        // independent of optional NaturalLanguage lexical assets.
        let heads: Set<String> = ["price", "prices", "cost", "costs", "quote", "quotes",
            "detail", "details", "address", "appointment", "booking", "delivery",
            "order", "orders", "receipt", "invoice", "letter", "parcel", "meeting"]
        let modifiers: Set<String> = ["the", "a", "an", "my", "our", "box", "vegetable",
            "rental", "van", "dentist", "library", "new", "old", "existing", "saved",
            "current", "collection", "pickup", "return", "booking", "delivery"]
        let words = value.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        return words.last.map { heads.contains($0) } == true
            && words.dropLast().allSatisfy { modifiers.contains($0) || heads.contains($0) }
    }

    private static func placeValue(_ value: String) -> Bool {
        guard nominalValue(value, allowsPlaceCoordination: true) else { return false }
        if value.range(of: #"(?i)\band\b"#, options: .regularExpression) != nil { return true }
        let heads: Set<String> = ["branch", "depot", "office", "entrance", "exit", "street",
            "road", "lane", "avenue", "drive", "station", "warehouse", "library", "school",
            "shop", "store", "clinic", "hospital", "park", "garage", "venue", "building",
            "room", "gate", "terminal", "centre", "center", "counter", "desk", "wing"]
        let modifiers: Set<String> = ["north", "south", "east", "west", "upper", "lower",
            "central", "front", "rear", "left", "right", "main", "new", "old", "small",
            "large", "red", "blue", "green", "first", "second", "third"]
        func placeNominal(_ text: String) -> Bool {
            var words = text.split(whereSeparator: \.isWhitespace).map(String.init)
            if words.first?.lowercased() == "the" { words.removeFirst() }
            guard (1...5).contains(words.count), let head = words.last else { return false }
            if words.count == 1, ["home", "work", "upstairs", "downstairs"].contains(head.lowercased()) { return true }
            // Proper place names retain their original case. Unknown lowercase
            // words cannot serve as omitted predicates inside a field value.
            let proper: (String) -> Bool = { $0.first?.isUppercase == true }
            guard heads.contains(head.lowercased()) else { return false }
            return words.dropLast().allSatisfy { modifiers.contains($0.lowercased()) || proper($0) }
        }
        let parts = value.replacingOccurrences(of: #"(?i)\s+(?:on|at|in)\s+"#,
            with: "\n", options: .regularExpression).components(separatedBy: "\n")
        return (1...2).contains(parts.count) && parts.allSatisfy(placeNominal)
    }

    private static func personValue(_ value: String) -> Bool {
        // The complete communication clause has already proved this single
        // literal recipient slot. These names are also auxiliary words in a
        // general nominal, which must not disqualify their person role here.
        ["will", "may"].contains(value.lowercased()) || nominalValue(value)
    }

    private static func fieldClause(_ rest: String) -> (Field, String?, String)? {
        let text = rest.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".!?"))
        let person = #"(?i)^so\s+(?:that\s+)?i\s+\#(communicationVerb)\s+([\p{L}][\p{L}'’-]*)(?:\s+(?:for|about|with)\s+((?:(?!(?:instead|rather|not)\b)[\p{L}\p{N}'’-]+\s+){0,7}(?!(?:instead|rather|not)\b)[\p{L}\p{N}'’-]+))?(?:\s*,?\s+(?:(?:instead\s+of|rather\s+than|not)\s+([\p{L}][\p{L}'’-]*)|instead))?$"#
        if let regex = NSRegularExpression.speakItCached(person),
           let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let nameRange = Range(match.range(at: 1), in: text) {
            let name = String(text[nameRange])
            guard personValue(name),
                  !["me", "him", "her", "them", "us", "someone", "somebody", "everyone"]
                    .contains(name.lowercased()) else { return nil }
            if let complement = Range(match.range(at: 2), in: text),
               !communicationTopic(String(text[complement])) { return nil }
            let old = Range(match.range(at: 3), in: text).map { String(text[$0]) }
            guard old.map({ personValue($0) && $0.caseInsensitiveCompare(name) != .orderedSame }) ?? true else { return nil }
            return (.person, old, name)
        }
        let place = #"(?i)^to\s+(?:the\s+)?(.+?)(?:\s*,?\s+(?:instead\s+of|rather\s+than|not)\s+(?:the\s+)?(.+))?$"#
        guard let regex = NSRegularExpression.speakItCached(place),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let newRange = Range(match.range(at: 1), in: text) else { return nil }
        let value = String(text[newRange])
        let old = Range(match.range(at: 2), in: text).map { String(text[$0]) }
        guard placeValue(value),
              old.map({ placeValue($0)
                  && $0.caseInsensitiveCompare(value) != .orderedSame }) ?? true else { return nil }
        return (.place, old, value)
    }

    private static func independentContinuation(_ source: String) -> Bool {
        let text = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !QuotedSpeechScope.hasUnclosedQuote(text),
              ClauseScope.read(text).act != .reporting else { return false }
        // An independently named second edit is a conflict, never a creation
        // whose removal could let the first edit execute.
        if directRequest(text) != nil { return false }
        let savedOperation = #"(?i)^(?:please\s+)?(?:change|update|correct|fix|amend|switch|edit|revise|move|reschedule|cancel|delete|remove|complete|mark)\b.*\b(?:saved|existing|current|same)\b"#
        if text.range(of: savedOperation, options: .regularExpression) != nil { return false }
        let head = #"(?i)^(?:please\s+)?(?:\#(ActionabilityReader.actionVerb)|\#(ActionabilityReader.headOnlyImperativeVerb))\b\s+\S"#
        if text.range(of: head, options: .regularExpression) != nil { return true }
        if ReminderPhrasing.requestsReminder(text), ActionabilityReader.read(text).belongsOnToday { return true }
        let own = #"(?i)^(?:i|we)\s+(?:will|shall|must|should|(?:need|have|want)\s+to|am\s+going\s+to|are\s+going\s+to)\s+\p{L}"#
        if text.range(of: own, options: .regularExpression) != nil { return true }
        // Context remains visible too, such as the unchanged collection day.
        let fact = #"(?i)^(?:the|my|our|this|that)\s+(?:[\p{L}'’-]+\s+){1,6}(?:is|are|was|were|has|have)\b"#
        return text.range(of: fact, options: .regularExpression) != nil
    }

    private static func existingIntroduction(_ sentence: String) -> Bool {
        let text = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".!?"))
        guard QuotedSpeechScope.ranges(in: text).isEmpty,
              !QuotedSpeechScope.hasUnclosedQuote(text) else { return false }
        let prefix = #"(?i)^(?:the|my|our)\s+((?:[\p{L}'’-]+\s+){1,6})(?:reminder|task|item|entry|booking)(?:\s+from\s+(?:yesterday|today|last\s+(?:week|month)))?\s+"#
        guard let range = text.range(of: prefix, options: .regularExpression) else { return false }
        let subject = String(text[range]).lowercased()
        guard subject.range(of: #"\b(?:not|no|never|new|unsaved|possible|proposed|hypothetical|said|reported)\b"#,
                            options: .regularExpression) == nil else { return false }
        let predicate = String(text[range.upperBound...])
        if let says = predicate.range(of: #"(?i)^says\s+to\s+"#, options: .regularExpression) {
            // Reuse the complete person-field complement grammar, without
            // changing an assertion about a saved item into an instruction.
            return fieldClause("so I " + String(predicate[says.upperBound...]))?.0 == .person
        }
        return predicate.range(of: #"(?i)^(?:was|is)\s+assigned\s+to\s+[\p{L}][\p{L}'’-]*$"#,
                               options: .regularExpression) != nil
    }

    private static func antecedent(in source: String, sentences: [Range<String.Index>], before position: Int) -> String? {
        let prior = sentences[max(0, position - 2)..<position].map {
            String(source[$0]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let introductions = prior.filter(existingIntroduction)
        guard introductions.count == 1 else { return nil }
        // One intervening pronoun-status sentence may explain the recipient
        // change. It cannot introduce another task, quotation or actor.
        for (index, sentence) in prior.enumerated() where !existingIntroduction(sentence) {
            // Earlier unrelated context supplies no target words. Only text
            // between the positive introduction and this request needs an
            // antecedent-preserving certificate.
            if prior.suffix(from: index + 1).contains(where: existingIntroduction) { continue }
            guard sentence.range(of: #"(?i)^(?:she|he|they|it)\s+(?:is|are|was|were)\s+(?:not\s+)?(?:available|unavailable|away|handling\s+[\p{L} ]+)(?:\s+(?:this|last|next)\s+(?:week|month))?[.!?]?$"#,
                                 options: .regularExpression) != nil,
                  sentence.range(of: #"(?i)\b(?:and|but|if|unless|because|will|should|must|remind|change|task|item|reminder)\b"#,
                                 options: .regularExpression) == nil,
                  QuotedSpeechScope.ranges(in: sentence).isEmpty else { return nil }
        }
        return introductions.first
    }

    static func read(_ source: String) -> Self? {
        guard source.utf8.count <= 8_192, !QuotedSpeechScope.hasUnclosedQuote(source) else { return nil }
        let sentences = sentenceRanges(in: source)
        var found: Self?
        for (position, sentenceRange) in sentences.enumerated() {
            let raw = String(source[sentenceRange])
            let sentence = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let match = directRequest(sentence),
                  let itemRange = Range(match.range(at: 1), in: sentence),
                  let restRange = Range(match.range(at: 2), in: sentence) else { continue }
            // Two direct field requests or one incomplete request alongside a
            // complete one require clarification of the complete source.
            guard found == nil, QuotedSpeechScope.ranges(in: sentence).isEmpty else { return nil }
            var itemWords = String(sentence[itemRange])
                .replacingOccurrences(of: #"(?i)\b(?:same|existing|saved|current|old)\b"#,
                                      with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
            let introduction = antecedent(in: source, sentences: sentences, before: position)
            let saysSaved = sentence[itemRange].range(of: #"(?i)\b(?:same|existing|saved|current)\b"#,
                                                     options: .regularExpression) != nil || introduction != nil
            guard saysSaved else { return nil }
            if itemWords.isEmpty {
                guard let introduction else { return nil }
                itemWords = introduction
            }
            var certified = fieldClause(String(sentence[restRange]))
            var end = sentence.endIndex
            var continuation: String.Index?
            if certified == nil,
               let boundaries = NSRegularExpression.speakItCached(#"(?i)[,;]\s*(?:(?:and|then|also|but)\s+)?|\s+(?:and|then|also|but)\s+"#) {
                for boundary in boundaries.matches(in: sentence, range: NSRange(sentence.startIndex..., in: sentence)) {
                    guard let seam = Range(boundary.range, in: sentence), seam.lowerBound >= restRange.lowerBound,
                          !QuotedSpeechScope.protects(seam, in: sentence),
                          let prefix = fieldClause(String(sentence[restRange.lowerBound..<seam.lowerBound])),
                          independentContinuation(String(sentence[seam.upperBound...])) else { continue }
                    certified = prefix
                    end = seam.lowerBound
                    continuation = seam.upperBound
                    break
                }
            }
            guard let (field, old, new) = certified else { return nil }
            let leading = raw.distance(from: raw.startIndex,
                to: raw.firstIndex(where: { !$0.isWhitespace }) ?? raw.endIndex)
            let lower = source.index(sentenceRange.lowerBound, offsetBy: leading)
            let upper = source.index(lower, offsetBy: sentence.distance(from: sentence.startIndex, to: end))
            let tailStart = continuation.map { source.index(lower, offsetBy: sentence.distance(from: sentence.startIndex, to: $0)) }
            let exactRange = lower..<upper
            found = Self(field: field, requestSentence: String(source[exactRange]), itemWords: itemWords,
                         statedOldValue: old, newValue: new, requestRange: exactRange,
                         continuationStart: tailStart)
        }
        return found
    }
}
