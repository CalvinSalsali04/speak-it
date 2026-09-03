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
    let sourceQuote: String
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

    /// True when a bare withdrawal has already taken back the one thought it
    /// was spoken after, and must not also be applied to the capture as a whole.
    ///
    /// "Buy milk and tomorrow I need to, never mind" retracts the fragment and
    /// nothing else. Read as a whole-capture retraction it discarded the milk
    /// too — a thought the person had finished saying, deleted because of one
    /// they had not. The request still travels with the extraction so the
    /// refinement model stays out of a capture whose words have been withdrawn.
    let isScoped: Bool

    init(
        operation: CaptureOperation,
        polarity: CapturePolarity = .negative,
        target: String?,
        sourceQuote: String,
        needsReview: Bool,
        isBroad: Bool = false,
        newTimingText: String? = nil,
        isScoped: Bool = false
    ) {
        self.operation = operation
        self.polarity = polarity
        self.target = target
        self.sourceQuote = sourceQuote
        self.needsReview = needsReview
        self.isBroad = isBroad
        self.newTimingText = newTimingText
        self.isScoped = isScoped
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
