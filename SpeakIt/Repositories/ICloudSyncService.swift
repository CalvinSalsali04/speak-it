import Foundation

struct ICloudItemSnapshot: Codable, Equatable, Sendable {
    let id: UUID
    let sessionID: UUID
    let originalTextSegment: String
    let displayTitle: String
    let itemType: ItemType
    let category: ItemCategory
    let createdAt: Date
    let dueDate: Date?
    let reminderDate: Date?
    let priority: ItemPriority
    let personName: String?
    let completedAt: Date?
    let isArchived: Bool
    let archivedAt: Date?
    let processingConfidence: Double
    let needsClarification: Bool
    let isReviewed: Bool
    let lastModifiedAt: Date
    /// Kept for decoding version-one snapshots. Version two stores the complete
    /// recurrence relationship in `recurrenceRecords`.
    let recurrenceRule: RecurrenceRule?
    /// Optional so snapshots written before temporal intent existed still
    /// decode. A device receiving one reconstructs the intent from the
    /// preserved wording on its next launch instead of losing it.
    let temporalIntent: TemporalIntent?
}

struct ICloudSessionSnapshot: Codable, Equatable, Sendable {
    let id: UUID
    let originalTranscription: String
    let createdAt: Date
    let captureSource: CaptureSource
    let processingStatus: ProcessingStatus
    let processingError: String?
    let lastModifiedAt: Date?
}

enum ICloudDeletedEntity: String, Codable, Hashable, Sendable {
    case item
    case session
}

struct ICloudDeletionRecord: Codable, Equatable, Sendable {
    let id: UUID
    let entity: ICloudDeletedEntity
    let deletedAt: Date
}

struct ICloudLibrarySnapshot: Codable, Equatable, Sendable {
    let schemaVersion: Int?
    let generatedAt: Date
    let sessions: [ICloudSessionSnapshot]
    let items: [ICloudItemSnapshot]
    let deletionRecords: [ICloudDeletionRecord]?
    let recurrenceRecords: [RecurrenceRecordSnapshot]?
    let pinRecords: [MemoryPinRecord]?
    let ideaStageRecords: [IdeaStageRecord]?

    init(
        schemaVersion: Int = 2,
        generatedAt: Date,
        sessions: [ICloudSessionSnapshot],
        items: [ICloudItemSnapshot],
        deletionRecords: [ICloudDeletionRecord] = [],
        recurrenceRecords: [RecurrenceRecordSnapshot] = [],
        pinRecords: [MemoryPinRecord] = [],
        ideaStageRecords: [IdeaStageRecord] = []
    ) {
        self.schemaVersion = schemaVersion
        self.generatedAt = generatedAt
        self.sessions = sessions
        self.items = items
        self.deletionRecords = deletionRecords
        self.recurrenceRecords = recurrenceRecords
        self.pinRecords = pinRecords
        self.ideaStageRecords = ideaStageRecords
    }

    func hasSameContent(as other: ICloudLibrarySnapshot) -> Bool {
        sessions.sorted(by: { $0.id.uuidString < $1.id.uuidString })
            == other.sessions.sorted(by: { $0.id.uuidString < $1.id.uuidString })
            && items.sorted(by: { $0.id.uuidString < $1.id.uuidString })
            == other.items.sorted(by: { $0.id.uuidString < $1.id.uuidString })
            && (deletionRecords ?? []).sorted(by: ICloudLibrarySnapshot.deletionOrder)
            == (other.deletionRecords ?? []).sorted(by: ICloudLibrarySnapshot.deletionOrder)
            && (recurrenceRecords ?? []).sorted(by: { $0.itemID.uuidString < $1.itemID.uuidString })
            == (other.recurrenceRecords ?? []).sorted(by: { $0.itemID.uuidString < $1.itemID.uuidString })
            && (pinRecords ?? []).sorted(by: { $0.itemID.uuidString < $1.itemID.uuidString })
            == (other.pinRecords ?? []).sorted(by: { $0.itemID.uuidString < $1.itemID.uuidString })
            && (ideaStageRecords ?? []).sorted(by: { $0.itemID.uuidString < $1.itemID.uuidString })
            == (other.ideaStageRecords ?? []).sorted(by: { $0.itemID.uuidString < $1.itemID.uuidString })
    }

    private static func deletionOrder(_ lhs: ICloudDeletionRecord, _ rhs: ICloudDeletionRecord) -> Bool {
        if lhs.entity.rawValue != rhs.entity.rawValue {
            return lhs.entity.rawValue < rhs.entity.rawValue
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}

enum ICloudSyncResult: Equatable, Sendable {
    case disabled
    case unavailable(String)
    case uploaded
    case synchronized
    case upToDate
    case failed(String)

    var isSuccess: Bool {
        switch self {
        case .uploaded, .synchronized, .upToDate: true
        case .disabled, .unavailable, .failed: false
        }
    }

    var userMessage: String {
        switch self {
        case .disabled:
            "iCloud sync is off"
        case let .unavailable(message), let .failed(message):
            message
        case .uploaded, .synchronized, .upToDate:
            "Memory is up to date"
        }
    }
}

enum ICloudDownloadResult: Sendable {
    case snapshot(ICloudLibrarySnapshot)
    case missing
    case failed(String)
}

enum ICloudUploadResult: Equatable, Sendable {
    case succeeded
    case failed(String)
}

@MainActor
enum ICloudSyncState {
    static let enabledKey = "SpeakIt.iCloudSyncEnabled"
    static let lastLocalChangeKey = "SpeakIt.iCloudLastLocalChange"
    static let lastAppliedCloudChangeKey = "SpeakIt.iCloudLastAppliedChange"

    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: enabledKey)
    }

    static var isSignedIn: Bool {
        isCapabilityConfigured && FileManager.default.ubiquityIdentityToken != nil
    }

    static var isCapabilityConfigured: Bool {
        (Bundle.main.object(forInfoDictionaryKey: "SpeakItICloudSyncAvailable") as? String) == "YES"
    }

    static var lastLocalChange: Date {
        Date(timeIntervalSince1970: UserDefaults.standard.double(forKey: lastLocalChangeKey))
    }

    static func markLocalChange(at date: Date = .now) {
        UserDefaults.standard.set(date.timeIntervalSince1970, forKey: lastLocalChangeKey)
    }

    static func markCloudChangeApplied(at date: Date) {
        UserDefaults.standard.set(date.timeIntervalSince1970, forKey: lastAppliedCloudChangeKey)
    }
}

@MainActor
enum ICloudDeletionStore {
    private static let key = "SpeakIt.iCloudDeletionRecords.v2"

    static func records() -> [ICloudDeletionRecord] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let values = try? JSONDecoder().decode([ICloudDeletionRecord].self, from: data) else {
            return []
        }
        return values
    }

    static func markDeleted(
        itemIDs: [UUID] = [],
        sessionIDs: [UUID] = [],
        at date: Date = .now
    ) {
        var values = dictionary(from: records())
        for id in itemIDs {
            values[DeletionKey(entity: .item, id: id)] = ICloudDeletionRecord(
                id: id,
                entity: .item,
                deletedAt: date
            )
        }
        for id in sessionIDs {
            values[DeletionKey(entity: .session, id: id)] = ICloudDeletionRecord(
                id: id,
                entity: .session,
                deletedAt: date
            )
        }
        persist(Array(values.values))
    }

    static func replace(with records: [ICloudDeletionRecord]) {
        persist(Array(dictionary(from: records).values))
    }

    static func restore(_ records: [ICloudDeletionRecord]) {
        persist(records)
    }

    private struct DeletionKey: Hashable {
        let entity: ICloudDeletedEntity
        let id: UUID
    }

    private static func dictionary(
        from records: [ICloudDeletionRecord]
    ) -> [DeletionKey: ICloudDeletionRecord] {
        records.reduce(into: [:]) { result, record in
            let key = DeletionKey(entity: record.entity, id: record.id)
            if let current = result[key], current.deletedAt > record.deletedAt { return }
            result[key] = record
        }
    }

    private static func persist(_ records: [ICloudDeletionRecord]) {
        let ordered = records.sorted {
            if $0.entity.rawValue != $1.entity.rawValue {
                return $0.entity.rawValue < $1.entity.rawValue
            }
            return $0.id.uuidString < $1.id.uuidString
        }
        guard !ordered.isEmpty else {
            UserDefaults.standard.removeObject(forKey: key)
            return
        }
        if let data = try? JSONEncoder().encode(ordered) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

enum ICloudSnapshotMerger {
    static func merge(
        local: ICloudLibrarySnapshot,
        cloud: ICloudLibrarySnapshot,
        generatedAt: Date = .now
    ) -> ICloudLibrarySnapshot {
        let deletions = newestDeletions(
            (local.deletionRecords ?? []) + (cloud.deletionRecords ?? [])
        )

        var items = Dictionary(uniqueKeysWithValues: cloud.items.map { ($0.id, $0) })
        for item in local.items {
            if let existing = items[item.id], existing.lastModifiedAt > item.lastModifiedAt {
                continue
            }
            items[item.id] = item
        }
        for deletion in deletions where deletion.entity == .item {
            guard let item = items[deletion.id], deletion.deletedAt >= item.lastModifiedAt else { continue }
            items.removeValue(forKey: deletion.id)
        }

        var sessions = Dictionary(uniqueKeysWithValues: cloud.sessions.map { ($0.id, $0) })
        for session in local.sessions {
            if let existing = sessions[session.id],
               sessionModifiedAt(existing, items: Array(items.values)) > sessionModifiedAt(session, items: Array(items.values)) {
                continue
            }
            sessions[session.id] = session
        }
        for deletion in deletions where deletion.entity == .session {
            guard let session = sessions[deletion.id],
                  deletion.deletedAt >= sessionModifiedAt(session, items: Array(items.values)) else { continue }
            sessions.removeValue(forKey: deletion.id)
            items = items.filter { $0.value.sessionID != deletion.id }
        }

        let validSessionIDs = Set(sessions.keys)
        items = items.filter { validSessionIDs.contains($0.value.sessionID) }
        let validItemIDs = Set(items.keys)

        let recurrences = newestRecords(
            (local.recurrenceRecords ?? []) + (cloud.recurrenceRecords ?? []),
            id: \.itemID,
            modifiedAt: \.modifiedAt
        ).filter {
            validItemIDs.contains($0.itemID)
                && items[$0.itemID]?.recurrenceRule != nil
                && ($0.generatedNextItemID == nil || validItemIDs.contains($0.generatedNextItemID!))
        }
        let pins = newestRecords(
            (local.pinRecords ?? []) + (cloud.pinRecords ?? []),
            id: \.itemID,
            modifiedAt: \.modifiedAt
        ).filter { validItemIDs.contains($0.itemID) }
        let stages = newestRecords(
            (local.ideaStageRecords ?? []) + (cloud.ideaStageRecords ?? []),
            id: \.itemID,
            modifiedAt: \.modifiedAt
        ).filter { validItemIDs.contains($0.itemID) }

        return ICloudLibrarySnapshot(
            generatedAt: generatedAt,
            sessions: sessions.values.sorted { $0.id.uuidString < $1.id.uuidString },
            items: items.values.sorted { $0.id.uuidString < $1.id.uuidString },
            deletionRecords: deletions,
            recurrenceRecords: recurrences,
            pinRecords: pins,
            ideaStageRecords: stages
        )
    }

    private struct DeletionKey: Hashable {
        let entity: ICloudDeletedEntity
        let id: UUID
    }

    private static func newestDeletions(
        _ records: [ICloudDeletionRecord]
    ) -> [ICloudDeletionRecord] {
        var values: [DeletionKey: ICloudDeletionRecord] = [:]
        for record in records {
            let key = DeletionKey(entity: record.entity, id: record.id)
            if let current = values[key], current.deletedAt > record.deletedAt { continue }
            values[key] = record
        }
        return values.values.sorted {
            if $0.entity.rawValue != $1.entity.rawValue {
                return $0.entity.rawValue < $1.entity.rawValue
            }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    private static func newestRecords<Record>(
        _ records: [Record],
        id: KeyPath<Record, UUID>,
        modifiedAt: KeyPath<Record, Date>
    ) -> [Record] {
        var values: [UUID: Record] = [:]
        for record in records {
            let recordID = record[keyPath: id]
            if let current = values[recordID],
               current[keyPath: modifiedAt] > record[keyPath: modifiedAt] {
                continue
            }
            values[recordID] = record
        }
        return values.values.sorted {
            $0[keyPath: id].uuidString < $1[keyPath: id].uuidString
        }
    }

    private static func sessionModifiedAt(
        _ session: ICloudSessionSnapshot,
        items: [ICloudItemSnapshot]
    ) -> Date {
        max(
            session.lastModifiedAt ?? session.createdAt,
            items.lazy
                .filter { $0.sessionID == session.id }
                .map(\.lastModifiedAt)
                .max() ?? .distantPast
        )
    }
}

actor ICloudSyncService {
    static let shared = ICloudSyncService()

    private let containerIdentifier = "iCloud.com.calvinwak.SpeakIt"

    func uploadImmediately(_ snapshot: ICloudLibrarySnapshot) async -> ICloudUploadResult {
        await write(snapshot)
    }

    func download() async -> ICloudDownloadResult {
        guard let url = await documentURL() else {
            return .failed("iCloud Drive is unavailable right now")
        }
        return await withCheckedContinuation { continuation in
            let coordinator = NSFileCoordinator()
            var coordinationError: NSError?
            var result: ICloudDownloadResult = .missing
            coordinator.coordinate(readingItemAt: url, options: [], error: &coordinationError) { coordinatedURL in
                guard FileManager.default.fileExists(atPath: coordinatedURL.path) else {
                    result = .missing
                    return
                }
                do {
                    let data = try Data(contentsOf: coordinatedURL)
                    result = .snapshot(try Self.decoder.decode(ICloudLibrarySnapshot.self, from: data))
                } catch {
                    result = .failed("Speak It couldn’t read the iCloud library. Your local copy was not changed.")
                }
            }
            if coordinationError != nil {
                result = .failed("Speak It couldn’t access iCloud Drive. Your local copy was not changed.")
            }
            continuation.resume(returning: result)
        }
    }

    private func write(_ snapshot: ICloudLibrarySnapshot) async -> ICloudUploadResult {
        guard let url = await documentURL() else {
            return .failed("iCloud Drive is unavailable right now")
        }
        let data: Data
        do {
            data = try Self.encoder.encode(snapshot)
        } catch {
            return .failed("Speak It couldn’t prepare the library for iCloud")
        }

        return await withCheckedContinuation { continuation in
            let coordinator = NSFileCoordinator()
            var coordinationError: NSError?
            var result: ICloudUploadResult = .failed("Speak It couldn’t update iCloud Drive")
            coordinator.coordinate(
                writingItemAt: url,
                options: .forReplacing,
                error: &coordinationError
            ) { coordinatedURL in
                do {
                    try FileManager.default.createDirectory(
                        at: coordinatedURL.deletingLastPathComponent(),
                        withIntermediateDirectories: true
                    )
                    try data.write(to: coordinatedURL, options: [.atomic, .completeFileProtectionUnlessOpen])
                    result = .succeeded
                } catch {
                    result = .failed("Speak It couldn’t update iCloud Drive")
                }
            }
            if coordinationError != nil {
                result = .failed("Speak It couldn’t update iCloud Drive")
            }
            continuation.resume(returning: result)
        }
    }

    private func documentURL() async -> URL? {
        await Task.detached(priority: .utility) { [containerIdentifier] in
            FileManager.default.url(
                forUbiquityContainerIdentifier: containerIdentifier
            )?.appendingPathComponent("Documents", isDirectory: true)
                .appendingPathComponent("SpeakItLibrary.json")
        }.value
    }

    private static let encoder: JSONEncoder = {
        let value = JSONEncoder()
        value.dateEncodingStrategy = .millisecondsSince1970
        value.outputFormatting = [.sortedKeys]
        return value
    }()

    private static let decoder: JSONDecoder = {
        let value = JSONDecoder()
        value.dateDecodingStrategy = .millisecondsSince1970
        return value
    }()
}
