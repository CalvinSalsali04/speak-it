import Foundation
@testable import SpeakIt

/// The semantic torture corpus.
///
/// Every expectation here is authored from the **product contract**, not from
/// observed behaviour. That is deliberate and it is the whole point: a corpus
/// recorded from current output can only ever prove the app still does what it
/// already did. This one states what Speak It is supposed to mean by a
/// sentence, so a failure is a real disagreement that has to be resolved in one
/// of two directions — fix the rule, or fix the expectation because the
/// contract was stated wrong.
///
/// Cases are grouped into families because the repair unit is a *rule*, not a
/// sentence. `SemanticCorpusTests` reports failures clustered by family and by
/// field so the shape of a break is visible before anyone opens the parser.
enum CorpusFamily: String, CaseIterable {
    case normal = "Normal"
    case messySpeech = "Natural messy speech"
    case multipleThoughts = "Multiple thoughts"
    case negation = "Negation"
    case tense = "Past versus future"
    case temporalAmbiguity = "Temporal ambiguity"
    case nonTimeNumbers = "Numbers that are not times"
    case people = "People and names"
    case recurrence = "Recurrence"
    case location = "Location"

    // Families 11-21. The first six vary one axis at a time across intents that
    // already pass in their bare form; the next four finish per-feature
    // coverage; the last stacks them together.
    case filler = "Filler and lead-ins"
    case corrections = "Corrections"
    case outstanding = "Outstanding obligations"
    case completion = "Completion and cancellation"
    case timeOfDay = "Time of day"
    case dateOnly = "Date only"
    case deadlines = "Deadlines versus reminders"
    case alarms = "Alarms"
    case events = "Events"
    case pronouns = "Pronouns and possessives"
    case compositions = "Compositions"

    // Families 22-23, added from TestFlight usage rather than from imagination.
    // Both encode the same principle from opposite directions: what the app is
    // told is not the same as what the app is asked to do.
    case datedFacts = "Dated facts"
    case consolidation = "Intent consolidation"
    // Family 24 pairs real intent signals with ordinary wording that merely
    // contains the same characters or verb shape.
    case collisions = "Semantic keyword collisions"
}


/// How much a given disagreement actually costs the person using the app.
///
/// Without this the corpus treats "Dr Okonkwo" losing its period exactly like
/// "Don't buy milk" creating a Buy milk task, and a release gate built on a
/// flat failure count is unusable — it either blocks on cosmetics or is
/// switched off entirely.
///
/// Severity is derived from *which field* disagrees rather than hand-labelled
/// on every case, because the field is what determines the consequence: a wrong
/// item count or a reversed operation changes what the app does, while a
/// secondary taxonomy label usually does not.
enum CorpusSeverity: Int, Comparable {
    /// The app does something the person did not ask for, or the reverse of
    /// what they asked for. Ships nothing.
    case critical = 3
    /// Observable wrong behaviour: wrong surface, wrong time, wrong repeat.
    case behavioral = 2
    /// A label or attribute that does not change behaviour.
    case metadata = 1
    /// Wording and presentation.
    case cosmetic = 0

    static func < (lhs: CorpusSeverity, rhs: CorpusSeverity) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var label: String {
        switch self {
        case .critical: "CRITICAL"
        case .behavioral: "BEHAVIORAL"
        case .metadata: "METADATA"
        case .cosmetic: "COSMETIC"
        }
    }

    /// The default cost of a given field being wrong.
    static func forField(_ field: String) -> CorpusSeverity {
        let base = field.prefix(while: { $0 != "[" })
        switch base {
        case "count", "operation", "operationTarget":
            return .critical
        case "route", "delivery", "recurrence", "location", "reminderDate", "dueDate", "temporalKind":
            return .behavioral
        case "type", "category", "priority", "person", "needsReview":
            return .metadata
        default:
            return .cosmetic
        }
    }
}

/// Which surface an item belongs on. Mirrors the production contract: either
/// an actionable type or an explicit reminder belongs on Today.
enum CorpusRoute: String {
    case today = "Today"
    case memory = "Memory"

    init(_ thought: OrganizedThought) {
        self = thought.itemType.isActionable || thought.reminderDate != nil ? .today : .memory
    }
}

/// A wall-clock expectation resolved against the fixed corpus reference date.
/// `hour == nil` means the contract expects a day with no time of day attached,
/// which is a distinct outcome from "9 AM" and must not be conflated with it.
struct CorpusDate: Equatable {
    var month: Int
    var day: Int
    var hour: Int?
    var minute: Int = 0

    func resolved(in calendar: Calendar, year: Int = 2026) -> Date? {
        guard let hour else { return nil }
        return calendar.date(from: DateComponents(
            year: year, month: month, day: day, hour: hour, minute: minute
        ))
    }
}

struct CorpusRecurrence: Equatable {
    var frequency: RecurrenceFrequency
    var interval: Int = 1
    var weekdays: [Int] = []
}

struct CorpusPlace: Equatable {
    var event: LocationEvent
    var place: PlaceReference
    var repeats: Bool = false
}

/// One utterance and everything the contract says about it.
///
/// Every assertion field is optional and per-extracted-item. A `nil` field is
/// not asserted at all — a case may pin only the item count, or only routing,
/// without being forced to state a due date it has no opinion about.
struct CorpusCase {
    let family: CorpusFamily
    let utterance: String
    var count: Int?
    var type: [ItemType]?
    var category: [ItemCategory]?
    var priority: [ItemPriority]?
    var route: [CorpusRoute]?
    var title: [String]?
    var person: [String?]?
    var delivery: [ReminderDelivery]?
    var kind: [TemporalKind]?
    var due: [CorpusDate?]?
    var remind: [CorpusDate?]?
    var recurs: [CorpusRecurrence?]?
    var place: [CorpusPlace?]?
    var review: [Bool]?
    /// Operations the utterance requests instead of, or alongside, creating.
    /// An empty array asserts that no operation was requested.
    var operation: [CaptureOperation]?
    /// What each operation acts on, in the person's words.
    var operationTarget: [String?]?
    /// Caps the severity of every disagreement in this case. Used where the
    /// contract is genuinely arguable and should not gate a release.
    var severityCeiling: CorpusSeverity?
    /// Why this case exists, when that is not obvious from the sentence.
    var note: String?
}

/// Compact constructor so a case reads as one line of intent.
func corpusCase(
    _ family: CorpusFamily,
    _ utterance: String,
    count: Int? = nil,
    type: [ItemType]? = nil,
    category: [ItemCategory]? = nil,
    priority: [ItemPriority]? = nil,
    route: [CorpusRoute]? = nil,
    title: [String]? = nil,
    person: [String?]? = nil,
    delivery: [ReminderDelivery]? = nil,
    kind: [TemporalKind]? = nil,
    due: [CorpusDate?]? = nil,
    remind: [CorpusDate?]? = nil,
    recurs: [CorpusRecurrence?]? = nil,
    place: [CorpusPlace?]? = nil,
    review: [Bool]? = nil,
    operation: [CaptureOperation]? = nil,
    operationTarget: [String?]? = nil,
    severityCeiling: CorpusSeverity? = nil,
    note: String? = nil
) -> CorpusCase {
    CorpusCase(
        family: family,
        utterance: utterance,
        count: count,
        type: type,
        category: category,
        priority: priority,
        route: route,
        title: title,
        person: person,
        delivery: delivery,
        kind: kind,
        due: due,
        remind: remind,
        recurs: recurs,
        place: place,
        review: review,
        operation: operation,
        operationTarget: operationTarget,
        severityCeiling: severityCeiling,
        note: note
    )
}
