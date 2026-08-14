import Foundation
import SwiftData
import SwiftUI

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
}

@MainActor
struct CaptureCreationResult {
    let session: CaptureSession
    let items: [CapturedItem]

    var primaryItem: CapturedItem { items[0] }
    var itemCount: Int { items.count }
    var reminderCount: Int { items.filter { $0.reminderDate != nil }.count }
    var needsReviewCount: Int { items.filter(\.needsClarification).count }
    var actionCount: Int {
        items.filter { $0.belongsInToday && $0.reminderDate == nil }.count
    }
    var memoryCount: Int {
        items.filter(\.belongsInMemory).count
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
    func handleLocationTrigger(itemID: UUID, event: LocationEvent) async
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
        schedulesReminders: Bool
    ) async throws -> CaptureCreationResult

    func update(_ item: CapturedItem, with edits: ItemEdits) throws
    func setCompleted(_ item: CapturedItem, completed: Bool) throws
    func setArchived(_ item: CapturedItem, archived: Bool) throws
    func markReviewed(_ item: CapturedItem) throws
    func delete(_ item: CapturedItem) throws
    func split(_ item: CapturedItem, into parts: [String]) throws
    func merge(_ items: [CapturedItem]) throws
    func undoOrganization(_ session: CaptureSession) throws
    func reorganize(_ session: CaptureSession) throws
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
