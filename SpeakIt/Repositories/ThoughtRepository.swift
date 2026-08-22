import Foundation
import SwiftData
import SwiftUI

/// What an edit does to a place trigger.
///
/// Three states rather than an optional, because "leave it alone" and "delete
/// it" are different instructions and an `Optional<LocationIntent>` cannot say
/// both. Every editor that does not present place controls sends `.unchanged`,
/// so a screen that never showed the trigger can never silently drop it.
enum LocationIntentEdit: Equatable, Sendable {
    case unchanged
    case update(LocationIntent)
    case remove
}

struct ItemEdits {
    var title: String
    var itemType: ItemType
    var category: ItemCategory
    var dueDate: Date?
    var reminderDate: Date?
    var priority: ItemPriority
    var personName: String?
    var needsClarification: Bool
    var recurrenceRule: RecurrenceRule? = nil
    var locationIntent: LocationIntentEdit = .unchanged
    /// Whether the manually chosen due date includes an intentional clock
    /// time. `false` keeps a spoken or edited day as a day instead of silently
    /// converting its storage midnight into a real 12:00 AM deadline.
    var dueDateHasTime: Bool = true
}

struct ReconciledItemSemantics: Equatable {
    let title: String
    let itemType: ItemType
    let category: ItemCategory
    let personName: String?
}

/// Refreshes fields that depend on a title/person edit without rerunning the
/// original transcript. The edited value is the newest statement of intent;
/// the capture remains untouched as provenance, and explicit picker changes
/// still outrank anything inferred here.
enum ItemEditSemanticReconciler {
    static func reconcile(
        title: String,
        itemType: ItemType,
        category: ItemCategory,
        personName: String?,
        originalTitle: String,
        originalItemType: ItemType,
        originalCategory: ItemCategory,
        originalPersonName: String?
    ) -> ReconciledItemSemantics {
        let editedPerson = normalizedPerson(personName)
        let previousPerson = normalizedPerson(originalPersonName)
        let titleChanged = normalizedText(title) != normalizedText(originalTitle)
        let personChanged: Bool
        switch (editedPerson, previousPerson) {
        case (nil, nil):
            personChanged = false
        case let (edited?, previous?):
            personChanged = edited.localizedCaseInsensitiveCompare(previous) != .orderedSame
        case (.some, nil), (nil, .some):
            personChanged = true
        }

        var resolvedTitle = title
        if personChanged, !titleChanged, let editedPerson {
            resolvedTitle = replacingPersonTarget(
                in: title,
                previousPerson: previousPerson,
                with: editedPerson
            )
        }

        guard titleChanged || personChanged else {
            return ReconciledItemSemantics(
                title: resolvedTitle,
                itemType: itemType,
                category: category,
                personName: editedPerson
            )
        }

        let inferred = ThoughtOrganizer.organize(resolvedTitle)
        let typeWasExplicitlyChanged = itemType != originalItemType
        let categoryWasExplicitlyChanged = category != originalCategory

        var resolvedType = itemType
        if !typeWasExplicitlyChanged {
            switch inferred.itemType {
            case .personFollowUp, .shopping, .idea, .event:
                resolvedType = inferred.itemType
            case .task where originalItemType == .note || originalItemType == .unclear:
                resolvedType = .task
            case .note where originalItemType == .unclear:
                resolvedType = .note
            case .task, .note, .unclear:
                break
            }
        }

        var resolvedPerson = editedPerson
        if !personChanged, titleChanged, let inferredPerson = inferred.personName {
            resolvedPerson = inferredPerson
        }

        var resolvedCategory = category
        if !categoryWasExplicitlyChanged {
            if resolvedType == .personFollowUp || (resolvedType == .note && resolvedPerson != nil) {
                resolvedCategory = .people
            } else if resolvedType != itemType {
                resolvedCategory = inferred.category
            }
        }

        return ReconciledItemSemantics(
            title: resolvedTitle,
            itemType: resolvedType,
            category: resolvedCategory,
            personName: resolvedPerson
        )
    }

    private static func normalizedPerson(_ value: String?) -> String? {
        guard let normalized = value?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !normalized.isEmpty else { return nil }
        return normalized
    }

    private static func normalizedText(_ value: String) -> String {
        value
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func replacingPersonTarget(
        in title: String,
        previousPerson: String?,
        with editedPerson: String
    ) -> String {
        if let previousPerson {
            let pattern = "(?i)(?<![\\p{L}\\p{N}])"
                + NSRegularExpression.escapedPattern(for: previousPerson)
                + "(?![\\p{L}\\p{N}])"
            if let range = title.range(of: pattern, options: .regularExpression) {
                return conciseActionTitle(
                    title.replacingCharacters(in: range, with: editedPerson)
                )
            }
        }

        let relation = #"(?:mom|mum|mother|dad|father|grandma|grandmother|grandpa|grandfather|sister|brother|aunt|uncle|cousin|nephew|niece|wife|husband|spouse|partner|son|daughter|friend|boss|manager|colleague|coworker|neighbour|neighbor|teacher|professor|doctor|dentist|therapist|trainer|roommate|landlord|supervisor)"#
        let description = #"(?i)\b(?:my|the|our|his|her|their)\s+(?:(?:favorite|favourite|best|close|older|younger|oldest|youngest)\s+){0,2}"#
            + relation + #"\b"#
        guard let range = title.range(of: description, options: .regularExpression) else {
            return title
        }
        return conciseActionTitle(
            title.replacingCharacters(in: range, with: editedPerson)
        )
    }

    /// The day is already structured timing. Once an edit makes the target
    /// precise, keep the visible thought focused on the action instead of
    /// repeating a fronted date in both the title and its due field.
    private static func conciseActionTitle(_ title: String) -> String {
        let body = ActionabilityReader.actionBody(title)
        return body.isEmpty ? title : ThoughtTitleFormatter.polished(body, itemType: .task)
    }
}

@MainActor
struct CaptureCreationResult {
    let session: CaptureSession
    let items: [CapturedItem]
    /// False when capture was an obvious near-immediate retransmission and the
    /// existing durable result was returned instead of inserting another row.
    let createdNewCapture: Bool

    /// Set when the capture asked the app to act on something that already
    /// exists rather than to store a new thought. `items` is then empty for
    /// every outcome except the ones that deliberately keep a review row.
    let operationOutcome: CaptureOperationOutcome?

    init(
        session: CaptureSession,
        items: [CapturedItem],
        createdNewCapture: Bool = true,
        operationOutcome: CaptureOperationOutcome? = nil
    ) {
        self.session = session
        self.items = items
        self.createdNewCapture = createdNewCapture
        self.operationOutcome = operationOutcome
    }

    /// Whether this capture should spend one of the ten free captures.
    ///
    /// Managing existing content is not creating a thought, so cancel, complete
    /// and retract are free. A request that produced a review row still counts
    /// as a stored thought, because that row is real and the person can act on
    /// it.
    var consumesFreeCapture: Bool {
        guard let operationOutcome else { return true }
        switch operationOutcome {
        case .performed, .notFound, .retracted:
            return false
        case .ambiguous, .needsConfirmation:
            return !items.isEmpty
        }
    }

    /// Only meaningful when the capture created something. Callers that can
    /// receive an operation must check `operationOutcome` first.
    var primaryItem: CapturedItem { items[0] }
    var hasItems: Bool { !items.isEmpty }
    var itemCount: Int { items.count }
    var isDuplicate: Bool { !createdNewCapture }

    /// One reading per saved item, computed against a single authorization
    /// snapshot so every count in the receipt describes the same instant.
    private var presentations: [ItemPresentation] {
        let authorization = LocationReminderMonitor.shared.authorization
        return items.map { ItemPresentation.make(for: $0, authorization: authorization) }
    }

    /// Counted from the derived state rather than from `needsClarification`
    /// alone. The stored flag only knows what the *sentence* left unresolved; a
    /// place reminder waiting on a Home address is blocked by what the *device*
    /// lacks, and reading only the flag is what let a blocked item be announced
    /// as a ready action and be counted twice.
    var needsReviewCount: Int {
        presentations.filter(\.requiresReview).count
    }

    var reminderCount: Int {
        presentations.filter { presentation in
            switch presentation.reminderState {
            case .time, .place: !presentation.requiresReview
            case .none, .blockedPlace: false
            }
        }.count
    }

    var actionCount: Int {
        presentations.filter { presentation in
            switch presentation.destination {
            case .overdue, .todayScheduled, .comingUp, .whenYouHaveTime:
                // Reminders are counted on their own line; this is the
                // "things to do" remainder, so the two never double-count.
                return !presentation.reminderState.isArmed
            case .needsReview, .memory:
                return false
            }
        }.count
    }

    var memoryCount: Int {
        presentations.filter { $0.destination == .memory }.count
    }

    var receiptContext: String {
        guard itemCount > 1 else {
            return ReminderScheduler.confirmationContext(for: primaryItem)
        }

        var parts = ["\(itemCount) things"]
        if actionCount > 0 {
            parts.append("\(actionCount) action\(actionCount == 1 ? "" : "s")")
        }
        if reminderCount > 0 {
            parts.append("\(reminderCount) reminder\(reminderCount == 1 ? "" : "s")")
        }
        if memoryCount > 0 {
            parts.append("\(memoryCount) memor\(memoryCount == 1 ? "y" : "ies")")
        }
        if needsReviewCount > 0 {
            parts.append("\(needsReviewCount) to review")
        }
        return parts.joined(separator: " · ")
    }
}

@MainActor
protocol ThoughtRepository: AnyObject, Sendable {
    func recoverUnorganizedCaptures()
    func recoverInterruptedCaptureDraft()
    func reconcilePendingReminders()
    /// Rebuilds monitored regions from the saved place reminders. The location
    /// counterpart of `reconcilePendingReminders()`.
    @discardableResult
    func reconcileLocationReminders() -> LocationMonitorReconciliation
    /// Delivers a place reminder whose region was just crossed.
    func handleLocationTrigger(
        itemID: UUID,
        event: LocationEvent,
        triggerRevision: Int?,
        regionIdentifier: String?
    ) async
    /// Looks up a name for a frozen "here", on explicit request only.
    ///
    /// Never called during capture. Reverse-geocoding sends a coordinate to
    /// Apple, and doing that unasked for a cosmetic label is the one thing that
    /// would take the "here" path off-device. Returns the stored name, or `nil`
    /// when nothing usable was found — the reminder is unaffected either way.
    @discardableResult
    func nameCurrentLocationSnapshot(itemID: UUID) async -> String?
    func reconcileSharedTodayActions()
    func reconcileICloudSync() async -> ICloudSyncResult
    func publishSharedTodaySnapshot()
    func performReminderAction(itemIDs: [UUID], action: ReminderAction) throws
    func loadSampleData(referenceDate: Date) throws -> SampleDataLoadResult

    @discardableResult
    func createCapture(
        text: String,
        source: CaptureSource,
        createdAt: Date
    ) throws -> CapturedItem

    func createCaptureResult(
        text: String,
        source: CaptureSource,
        createdAt: Date,
        schedulesReminders: Bool,
        performance: CapturePerformanceTrace?
    ) async throws -> CaptureCreationResult

    /// Adds typed (or keyboard-dictated) entries straight onto a named
    /// shopping list, bypassing semantic parsing: the person already said
    /// which list and what the items are, and running "milk" through the
    /// organizer would classify a one-word answer as unclear.
    @discardableResult
    func addShoppingItems(
        _ entries: [String],
        group: String,
        createdAt: Date
    ) throws -> [CapturedItem]

    func update(_ item: CapturedItem, with edits: ItemEdits) throws
    func setCompleted(_ item: CapturedItem, completed: Bool) throws
    func setArchived(_ item: CapturedItem, archived: Bool) throws
    func markReviewed(_ item: CapturedItem) throws
    func delete(_ item: CapturedItem) throws
    func confirmPendingOperation(_ item: CapturedItem) throws
    func dismissPendingOperation(_ item: CapturedItem) throws
    func split(_ item: CapturedItem, into parts: [String]) throws
    func merge(_ items: [CapturedItem]) throws
    func undoOrganization(_ session: CaptureSession) throws
    func reorganize(_ session: CaptureSession) throws
}

extension ThoughtRepository {
    @discardableResult
    func addShoppingItems(
        _ entries: [String],
        group: String
    ) throws -> [CapturedItem] {
        try addShoppingItems(entries, group: group, createdAt: .now)
    }

    func createCaptureResult(
        text: String,
        source: CaptureSource,
        createdAt: Date,
        schedulesReminders: Bool
    ) async throws -> CaptureCreationResult {
        try await createCaptureResult(
            text: text,
            source: source,
            createdAt: createdAt,
            schedulesReminders: schedulesReminders,
            performance: nil
        )
    }
}

enum RepositoryError: LocalizedError, Equatable {
    case emptyCapture
    case emptyTitle
    case invalidSplit
    case invalidMerge
    case storageUnavailable
    case saveFailed(String)

    var errorDescription: String? {
        switch self {
        case .emptyCapture:
            "Enter something you want to remember."
        case .emptyTitle:
            "The title cannot be empty."
        case .invalidSplit:
            "Enter between two and twelve non-empty thoughts."
        case .invalidMerge:
            "Choose at least two thoughts from the same capture."
        case .storageUnavailable:
            "Speak It couldn’t open local storage. Your existing memories have not been changed."
        case let .saveFailed(message):
            "Speak It couldn’t save that change. \(message)"
        }
    }
}

private struct ThoughtRepositoryEnvironmentKey: EnvironmentKey {
    static let defaultValue: (any ThoughtRepository)? = nil
}

extension EnvironmentValues {
    var thoughtRepository: (any ThoughtRepository)? {
        get { self[ThoughtRepositoryEnvironmentKey.self] }
        set { self[ThoughtRepositoryEnvironmentKey.self] = newValue }
    }
}
