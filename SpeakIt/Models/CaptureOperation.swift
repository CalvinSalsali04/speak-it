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

    init(
        operation: CaptureOperation,
        polarity: CapturePolarity = .negative,
        target: String?,
        sourceQuote: String,
        needsReview: Bool,
        isBroad: Bool = false
    ) {
        self.operation = operation
        self.polarity = polarity
        self.target = target
        self.sourceQuote = sourceQuote
        self.needsReview = needsReview
        self.isBroad = isBroad
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
/// FINAL_RELEASE_AUDIT.md F-1.
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
