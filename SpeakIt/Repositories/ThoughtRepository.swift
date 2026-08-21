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
