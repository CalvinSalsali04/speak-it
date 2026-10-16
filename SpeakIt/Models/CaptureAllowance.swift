import Foundation
import SwiftData
import Security
import Darwin

/// Snapshot at the raw commit. Later StoreKit changes cannot alter this capture.
enum CaptureAllowancePolicy: Equatable {
    case free
    case pro
    case practice
    case replacement(UUID)
}

extension CaptureSource {
    /// Typing reconstructs the input method; a tutorial draft remains practice.
    var typedRecoverySource: CaptureSource { self == .tutorial ? .tutorial : .inAppText }
}

/// Independent of sessions and their cascade: deleting a thought never refunds
/// a debit or destroys an interrupted capture's billing obligation.
@Model
final class CaptureAllowanceObligation {
    @Attribute(.unique) var id: UUID
    var chargeKey: UUID
    var policyRawValue: String
    var stateRawValue: String
    var finalCharge: Bool?
    var createdAt: Date

    init(id: UUID, chargeKey: UUID, policyRawValue: String,
         stateRawValue: String = "pending", finalCharge: Bool? = nil, createdAt: Date) {
        self.id = id
        self.chargeKey = chargeKey
        self.policyRawValue = policyRawValue
        self.stateRawValue = stateRawValue
        self.finalCharge = finalCharge
        self.createdAt = createdAt
    }
}

/// Credited IDs must outlive the SQLite store: an older restored store can
/// contain an already-paid capture in pending state. A counter alone would
/// charge it twice. At most ten keys can be credited; no user text is stored.
struct CaptureAllowanceJournal: Codable, Equatable {
    var version = 1
    var baseline: Int
    var creditedKeys: Set<UUID> = []
    var used: Int { min(10, baseline + creditedKeys.count) }
}

protocol CaptureAllowanceJournalStorage: AnyObject {
    func read() throws -> CaptureAllowanceJournal?
    func write(_ journal: CaptureAllowanceJournal) throws
    func legacyCount() -> Int
    func mirrorLegacyCount(_ count: Int)
    var identityHistoryAvailable: Bool { get }
}

extension CaptureAllowanceJournalStorage {
    var identityHistoryAvailable: Bool { true }
}

enum CaptureAllowanceStorageError: LocalizedError {
    case busy, unavailable
    var errorDescription: String? {
        switch self {
        case .busy: "Another capture is saving. Your words are kept; try again."
        case .unavailable: "Capture allowance storage is unavailable. Your words are kept; try again."
        }
    }
}

/// Synchronous nonblocking interprocess critical sections only. Never hold
/// this across await; process death releases flock automatically.
final class CaptureAllowanceLock {
    let url: URL
    init(url: URL) { self.url = url }
    func withLock<T>(_ body: () throws -> T) throws -> T {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let descriptor = open(url.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw CaptureAllowanceStorageError.unavailable }
        defer { close(descriptor) }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else { throw CaptureAllowanceStorageError.busy }
        defer { flock(descriptor, LOCK_UN) }
        return try body()
    }
}

/// Keychain survives reinstall; the atomic app-group file provides a shared
/// process-visible mirror. Missing and unreadable are different: never seed a
/// fresh baseline from an already-inclusive legacy count while a journal is
/// merely locked, corrupt or otherwise unreadable.
final class DeviceCaptureAllowanceJournalStorage: CaptureAllowanceJournalStorage {
    private let fileURL: URL
    private let defaults: UserDefaults
    private(set) var identityHistoryAvailable = true
    private static let legacyKey = "SpeakIt.freeCapturesUsed"
    // Match the legacy counter's backup eligibility so a restored inclusive
    // counter is accompanied by its credited identities. Neither item syncs.
    static let keychainAccessibility = kSecAttrAccessibleAfterFirstUnlock
    static let keychainSynchronizable = false
    private static let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "com.calvinwak.SpeakIt.freeCaptures",
        kSecAttrAccount as String: "creditedCaptureJournalV1",
        kSecAttrSynchronizable as String: keychainSynchronizable
    ]
    init(fileURL: URL, defaults: UserDefaults = .standard) {
        self.fileURL = fileURL
        self.defaults = defaults
    }
    func read() throws -> CaptureAllowanceJournal? {
        let file: CaptureAllowanceJournal?
        if FileManager.default.fileExists(atPath: fileURL.path) {
            file = try decode(Data(contentsOf: fileURL))
        } else { file = nil }
        var query = Self.query
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        identityHistoryAvailable = status == errSecSuccess || status == errSecItemNotFound
        guard identityHistoryAvailable else {
            // A valid file permits durable raw capture + local reservation.
            // Credit settlement waits for the identity history to be merged.
            guard let file else { throw CaptureAllowanceStorageError.unavailable }
            return file
        }
        if status == errSecItemNotFound {
            do { _ = try FreeCaptureLedger.readCount() }
            catch {
                // The first V6 journal cannot treat a locked legacy counter
                // as zero. A valid existing file can still hold raw pending.
                identityHistoryAvailable = false
                guard let file else { throw CaptureAllowanceStorageError.unavailable }
                return file
            }
        }
        let keychain: CaptureAllowanceJournal?
        if status == errSecSuccess {
            guard let data = result as? Data else { throw CaptureAllowanceStorageError.unavailable }
            keychain = try decode(data)
        } else { keychain = nil }
        guard var merged = keychain ?? file else { return nil }
        if let file {
            merged.baseline = max(merged.baseline, file.baseline)
            merged.creditedKeys.formUnion(file.creditedKeys)
        }
        guard merged.baseline + merged.creditedKeys.count <= 10 else {
            throw CaptureAllowanceStorageError.unavailable
        }
        return merged
    }
    private func decode(_ data: Data) throws -> CaptureAllowanceJournal {
        let journal = try JSONDecoder().decode(CaptureAllowanceJournal.self, from: data)
        guard journal.version == 1, (0...10).contains(journal.baseline),
              journal.baseline + journal.creditedKeys.count <= 10 else {
            throw CaptureAllowanceStorageError.unavailable
        }
        return journal
    }
    func write(_ journal: CaptureAllowanceJournal) throws {
        let data = try JSONEncoder().encode(journal)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
        let status = SecItemUpdate(Self.query as CFDictionary, [kSecValueData as String: data,
            kSecAttrAccessible as String: Self.keychainAccessibility] as CFDictionary)
        if status == errSecItemNotFound {
            var insert = Self.query
            insert[kSecValueData as String] = data
            insert[kSecAttrAccessible as String] = Self.keychainAccessibility
            guard SecItemAdd(insert as CFDictionary, nil) == errSecSuccess else {
                throw CaptureAllowanceStorageError.unavailable
            }
        } else if status != errSecSuccess { throw CaptureAllowanceStorageError.unavailable }
    }
    func legacyCount() -> Int {
        min(10, max(0, max(defaults.integer(forKey: Self.legacyKey), FreeCaptureLedger.storedCount() ?? 0)))
    }
    func mirrorLegacyCount(_ count: Int) {
        let count = max(count, legacyCount())
        defaults.set(count, forKey: Self.legacyKey)
        FreeCaptureLedger.persist(count)
    }
#if DEBUG
    func reset() {
        SecItemDelete(Self.query as CFDictionary)
        try? FileManager.default.removeItem(at: fileURL)
    }
#endif
}

@MainActor
final class CaptureAllowance {
    private let container: ModelContainer
    private let storage: any CaptureAllowanceJournalStorage
    private let lock: CaptureAllowanceLock
    /// Fault injection occurs after the external credit and before the local
    /// terminal save. Reopening must repair that exact crash window once.
    var afterCredit: (() throws -> Void)?
    init(container: ModelContainer, storage: any CaptureAllowanceJournalStorage, lockURL: URL) {
        self.container = container
        self.storage = storage
        self.lock = CaptureAllowanceLock(url: lockURL)
    }
    private static var directory: URL {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.calvinwak.SpeakIt")
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("SpeakIt", isDirectory: true)
    }
    static func live(container: ModelContainer) -> CaptureAllowance {
        let directory = directory
        return CaptureAllowance(container: container,
            storage: DeviceCaptureAllowanceJournalStorage(fileURL: directory.appendingPathComponent("capture-allowance.json")),
            lockURL: directory.appendingPathComponent("capture-allowance.lock"))
    }
    private func context() -> ModelContext {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        return context
    }
    private func obligation(_ id: UUID, in context: ModelContext) throws -> CaptureAllowanceObligation? {
        var descriptor = FetchDescriptor<CaptureAllowanceObligation>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }
    private func pending(in context: ModelContext) throws -> [CaptureAllowanceObligation] {
        try context.fetch(FetchDescriptor<CaptureAllowanceObligation>(predicate: #Predicate { $0.stateRawValue == "pending" }))
    }
    private func session(_ id: UUID, in context: ModelContext) throws -> CaptureSession? {
        var descriptor = FetchDescriptor<CaptureSession>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }
    private func journal() throws -> CaptureAllowanceJournal {
        if var journal = try storage.read() {
            let legacy = storage.legacyCount()
            if storage.identityHistoryAvailable, legacy > journal.used {
                journal.baseline += legacy - journal.used
                try storage.write(journal)
            }
            return journal
        }
        guard storage.identityHistoryAvailable else { throw CaptureAllowanceStorageError.unavailable }
        let journal = CaptureAllowanceJournal(baseline: storage.legacyCount())
        try storage.write(journal)
        return journal
    }
    /// Counts distinct pending chain keys before admission. The store save of
    /// the raw session and obligation is one transaction, under the same lock.
    func commit(id: UUID, createdAt: Date, policy: CaptureAllowancePolicy,
                findDuplicate: ((ModelContext) throws -> UUID?)? = nil,
                insertRaw: (ModelContext) throws -> Void) throws -> UUID {
        try lock.withLock {
            let context = self.context()
            guard try obligation(id, in: context) == nil else { return id }
            if let duplicate = try findDuplicate?(context) { return duplicate }
            var key = id
            var mode = "free"
            var exempt = false
            switch policy {
            case .free: break
            case .pro: mode = "pro"; exempt = true
            case .practice: mode = "practice"; exempt = true
            case .replacement(let source):
                mode = "replacement"
                if let prior = try obligation(source, in: context) {
                    key = prior.chargeKey
                    // A clarification replacement never costs another capture,
                    // including a legacy/exempt source. It retains its root key.
                }
                exempt = true
            }
            if !exempt {
                let journal = try journal()
                let pending = Set(try self.pending(in: context).filter { $0.policyRawValue == "free" }
                    .map(\.chargeKey)).subtracting(journal.creditedKeys)
                guard max(journal.used, storage.legacyCount()) + pending.count < 10 else { throw CaptureAccessError.freeLimitReached }
            }
            try insertRaw(context)
            context.insert(CaptureAllowanceObligation(id: id, chargeKey: key, policyRawValue: mode,
                stateRawValue: exempt ? "exempt" : "pending", finalCharge: exempt ? false : nil, createdAt: createdAt))
            try context.save()
            // Migration writes are durable before the first obligation exists.
            // Legacy mirror never adds a second baseline to known credited IDs.
            if !exempt, storage.identityHistoryAvailable {
                // Raw persistence already succeeded. A failed replica repair
                // keeps its obligation pending; never misreport lost words.
                if let journal = try? journal(), (try? storage.write(journal)) != nil {
                    storage.mirrorLegacyCount(journal.used)
                }
            }
            return id
        }
    }
    /// The definitive outcome and final repository result join the same SQLite
    /// transaction. Fresh state under the lock prevents a stale presentation
    /// context from reopening an obligation another process already settled.
    func saveResult(context: ModelContext, decisions: [UUID: Bool]) throws {
        try lock.withLock {
            let fresh = self.context()
            let pendingIDs = Set(try pending(in: fresh).map(\.id))
            for (id, decision) in decisions where pendingIDs.contains(id) {
                if let row = try obligation(id, in: context) { row.finalCharge = decision }
            }
            try context.save()
        }
    }

    func settle(id: UUID, charge: Bool) throws {
        try lock.withLock {
            let context = self.context()
            guard let row = try obligation(id, in: context),
                  row.stateRawValue == "pending" else { return }
            var journal = try journal()
            if charge || journal.creditedKeys.contains(row.chargeKey) {
                guard storage.identityHistoryAvailable else { throw CaptureAllowanceStorageError.unavailable }
            }
            if journal.creditedKeys.contains(row.chargeKey) {
                // The ID may exist only in the file after an interrupted or
                // failed Keychain write. Repair both before terminal state.
                try storage.write(journal)
                storage.mirrorLegacyCount(journal.used)
                row.stateRawValue = "charged"
            } else if !charge {
                row.stateRawValue = "exempt"
            } else {
                guard journal.used < 10 else { throw CaptureAllowanceStorageError.unavailable }
                journal.creditedKeys.insert(row.chargeKey)
                try storage.write(journal)
                storage.mirrorLegacyCount(journal.used)
                try afterCredit?()
                row.stateRawValue = "charged"
            }
            row.finalCharge = charge
            try context.save()
        }
    }
    /// Reconcile only finished results; active organizers keep their reservation.
    /// Missing sessions still owe the charge, because the raw save succeeded.
    func reconcile(outcome: (CaptureSession) -> Bool?) throws {
        let ids: [UUID] = try lock.withLock {
            try pending(in: context()).map(\.id)
        }
        var firstError: (any Error)?
        for id in ids {
            do {
                let decision: Bool? = try lock.withLock {
                    let context = self.context()
                    guard let row = try obligation(id, in: context), row.stateRawValue == "pending" else { return nil }
                    if try journal().creditedKeys.contains(row.chargeKey) { return true }
                    if let decision = row.finalCharge { return decision }
                    guard let session = try session(id, in: context) else { return true }
                    return outcome(session)
                }
                if let decision { try settle(id: id, charge: decision) }
            } catch {
                // An unavailable charge must not strand another capture whose
                // definitive exempt result can safely release its reservation.
                if firstError == nil { firstError = error }
            }
        }
        if let firstError { throw firstError }
    }
    func usageIncludingPending() throws -> Int {
        try lock.withLock {
            let context = self.context()
            let journal = try journal()
            let pending = Set(try self.pending(in: context)
                .filter { $0.policyRawValue == "free" }.map(\.chargeKey))
                .subtracting(journal.creditedKeys)
            if storage.identityHistoryAvailable, (try? storage.write(journal)) != nil {
                storage.mirrorLegacyCount(journal.used)
            }
            return min(10, max(journal.used, storage.legacyCount()) + pending.count)
        }
    }
#if DEBUG
    static func resetLiveJournal() {
        DeviceCaptureAllowanceJournalStorage(fileURL: directory.appendingPathComponent("capture-allowance.json")).reset()
    }
#endif
}
