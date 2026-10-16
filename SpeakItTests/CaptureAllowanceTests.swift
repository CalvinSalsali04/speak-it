import Foundation
import SwiftData
import Security
import XCTest
@testable import SpeakIt

/// On-disk SQLite plus an independently persisted ledger. These tests reopen
/// actual stores at the raw-save and external-credit crash boundaries.
@MainActor
final class CaptureAllowanceTests: XCTestCase {
    private var directory: URL!
    private var storage: FileJournal!
    private var lockURL: URL { directory.appendingPathComponent("allowance.lock") }

    private final class FileJournal: CaptureAllowanceJournalStorage {
        let url: URL
        var legacy = 0
        var unreadable = false
        var identityHistoryAvailable = true
        init(url: URL) { self.url = url }
        func read() throws -> CaptureAllowanceJournal? {
            if unreadable { throw CaptureAllowanceStorageError.unavailable }
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            return try JSONDecoder().decode(CaptureAllowanceJournal.self, from: Data(contentsOf: url))
        }
        func write(_ journal: CaptureAllowanceJournal) throws {
            if unreadable { throw CaptureAllowanceStorageError.unavailable }
            try JSONEncoder().encode(journal).write(to: url, options: .atomic)
        }
        func legacyCount() -> Int { legacy }
        func mirrorLegacyCount(_ count: Int) { legacy = max(legacy, count) }
    }

    /// Two real atomic files stand in for the app file and reinstall-surviving
    /// Keychain. This injects failure between those replica writes.
    private final class ReplicaJournal: CaptureAllowanceJournalStorage {
        let file: URL, keychain: URL
        var failKeychainWrites = false
        var legacy = 0
        init(file: URL, keychain: URL) { self.file = file; self.keychain = keychain }
        private func read(_ url: URL) throws -> CaptureAllowanceJournal? {
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            return try JSONDecoder().decode(CaptureAllowanceJournal.self, from: Data(contentsOf: url))
        }
        func keychainValue() throws -> CaptureAllowanceJournal? { try read(keychain) }
        func read() throws -> CaptureAllowanceJournal? {
            let a = try read(file), b = try read(keychain)
            guard var result = a ?? b else { return nil }
            if let b { result.baseline = max(result.baseline, b.baseline); result.creditedKeys.formUnion(b.creditedKeys) }
            return result
        }
        func write(_ journal: CaptureAllowanceJournal) throws {
            let data = try JSONEncoder().encode(journal)
            try data.write(to: file, options: .atomic)
            guard !failKeychainWrites else { throw CaptureAllowanceStorageError.unavailable }
            try data.write(to: keychain, options: .atomic)
        }
        func legacyCount() -> Int { legacy }
        func mirrorLegacyCount(_ count: Int) { legacy = max(legacy, count) }
    }

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("SpeakItAllowance-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        storage = FileJournal(url: directory.appendingPathComponent("journal.json"))
    }
    override func tearDownWithError() throws {
        storage = nil
        try FileManager.default.removeItem(at: directory)
    }
    private func open(_ name: String = "capture") throws -> ModelContainer {
        try ModelContainer(for: PersistenceController.schema, migrationPlan: SpeakItMigrationPlan.self,
            configurations: [ModelConfiguration(schema: PersistenceController.schema,
                url: directory.appendingPathComponent(name + ".store"), cloudKitDatabase: .none)])
    }
    private func allowance(_ container: ModelContainer) -> CaptureAllowance {
        CaptureAllowance(container: container, storage: storage, lockURL: lockURL)
    }
    private func raw(_ allowance: CaptureAllowance, id: UUID = UUID(),
                     policy: CaptureAllowancePolicy = .free) throws -> UUID {
        _ = try allowance.commit(id: id, createdAt: .now, policy: policy) { context in
            context.insert(CaptureSession(id: id, originalTranscription: "Synthetic capture",
                                          processingStatus: .pending))
        }
        return id
    }
    private func rows(_ container: ModelContainer) throws -> [CaptureAllowanceObligation] {
        try ModelContext(container).fetch(FetchDescriptor<CaptureAllowanceObligation>())
    }
    private func repository(_ container: ModelContainer) -> SwiftDataThoughtRepository {
        SwiftDataThoughtRepository(modelContext: container.mainContext, requestsReminderAuthorization: false,
            permitsOnDeviceIntelligence: false, captureAllowance: allowance(container))
    }
    private func capture(_ repository: SwiftDataThoughtRepository, _ text: String,
                         policy: CaptureAllowancePolicy = .free, source: CaptureSource = .inAppText,
                         at: Date = .now) async throws -> CaptureCreationResult {
        try await repository.createCaptureResult(text: text, source: source, createdAt: at,
            allowancePolicy: policy, schedulesReminders: false)
    }

    func testRawCommitReopensWithWordsAndReservationBeforeAnyDebit() throws {
        let id: UUID
        do {
            let container = try open()
            id = try raw(allowance(container))
            XCTAssertEqual(try storage.read()?.used, 0)
        }
        let reopened = try open()
        let ledger = allowance(reopened)
        let saved = try XCTUnwrap(ModelContext(reopened).fetch(FetchDescriptor<CaptureSession>()).first)
        XCTAssertEqual(saved.id, id)
        XCTAssertEqual(saved.originalTranscription, "Synthetic capture")
        XCTAssertEqual(try ledger.usageIncludingPending(), 1)
        try ledger.reconcile { _ in nil }
        XCTAssertEqual(try storage.read()?.used, 0, "An active organizer cannot be prematurely charged")
        try ledger.settle(id: id, charge: true)
        XCTAssertEqual(try storage.read()?.used, 1)
    }

    func testCreditThenCrashReplaysOnceAfterReopening() throws {
        enum Crash: Error { case injected }
        let id: UUID
        do {
            let container = try open()
            let ledger = allowance(container)
            id = try raw(ledger)
            ledger.afterCredit = { throw Crash.injected }
            XCTAssertThrowsError(try ledger.settle(id: id, charge: true))
            XCTAssertEqual(try rows(container).first?.stateRawValue, "pending")
            XCTAssertEqual(try storage.read()?.used, 1)
        }
        let reopened = try open()
        let ledger = allowance(reopened)
        try ledger.reconcile { _ in nil }
        try ledger.settle(id: id, charge: true)
        XCTAssertEqual(try rows(reopened).first?.stateRawValue, "charged")
        XCTAssertEqual(try storage.read()?.used, 1)
        XCTAssertEqual(try storage.read()?.creditedKeys, [id])
    }

    func testFileCreditMustRepairIdentityReplicaBeforeChargedThenSurvivesReinstallAndOldRestore() throws {
        let replicas = ReplicaJournal(file: directory.appendingPathComponent("app-file.json"),
            keychain: directory.appendingPathComponent("surviving-keychain.json"))
        let container = try open()
        let ledger = CaptureAllowance(container: container, storage: replicas, lockURL: lockURL)
        let id = try raw(ledger)
        replicas.failKeychainWrites = true
        XCTAssertThrowsError(try ledger.settle(id: id, charge: true))
        XCTAssertEqual(try replicas.read()?.creditedKeys, [id])
        XCTAssertEqual(try replicas.keychainValue()?.creditedKeys, [])
        // Readable but stale identity is not enough: repair must succeed.
        XCTAssertThrowsError(try ledger.settle(id: id, charge: true))
        XCTAssertEqual(try rows(container).first?.stateRawValue, "pending")
        replicas.failKeychainWrites = false
        try ledger.settle(id: id, charge: true)
        XCTAssertEqual(try rows(container).first?.stateRawValue, "charged")
        XCTAssertEqual(try replicas.keychainValue()?.creditedKeys, [id])
        try FileManager.default.removeItem(at: replicas.file)
        let restored = try open("older-store-after-reinstall")
        let recovered = CaptureAllowance(container: restored, storage: replicas, lockURL: lockURL)
        _ = try raw(recovered, id: id)
        try recovered.reconcile { _ in nil }
        XCTAssertEqual(try replicas.read()?.used, 1)
        XCTAssertEqual(try replicas.read()?.baseline, 0)
    }

    func testFinalOutcomeAndWordsCommitTogetherBeforeDebit() throws {
        let container = try open()
        let ledger = allowance(container)
        let id = try raw(ledger)
        let context = container.mainContext
        let session = try XCTUnwrap(context.fetch(FetchDescriptor<CaptureSession>()).first)
        session.processingStatus = .complete
        try ledger.saveResult(context: context, decisions: [id: false])
        let reopened = try open()
        try allowance(reopened).reconcile { _ in XCTFail("Persisted outcome must be authoritative"); return true }
        XCTAssertEqual(try rows(reopened).first?.stateRawValue, "exempt")
        XCTAssertEqual(try storage.read()?.used, 0)
    }

    func testOlderPendingStoreRestoreDoesNotChargeCreditedIDTwice() throws {
        let container = try open()
        let ledger = allowance(container)
        let id = try raw(ledger)
        try ledger.settle(id: id, charge: true)
        let second = try raw(ledger)
        try ledger.settle(id: second, charge: true)
        // A separate file reproduces the older snapshot: same capture remains
        // pending, while the external durable journal knows it was credited.
        let oldSnapshot = try open("restored-older-snapshot")
        let restoredLedger = allowance(oldSnapshot)
        _ = try raw(restoredLedger, id: id)
        try restoredLedger.reconcile { _ in nil }
        XCTAssertEqual(try rows(oldSnapshot).first?.stateRawValue, "charged")
        XCTAssertEqual(try storage.read()?.used, 2)
        XCTAssertEqual(try restoredLedger.usageIncludingPending(), 2)
    }

    func testDeletingPendingOrChargedSessionCannotRefund() throws {
        let container = try open()
        let ledger = allowance(container)
        let id = try raw(ledger)
        let context = container.mainContext
        try context.fetch(FetchDescriptor<CaptureSession>()).forEach(context.delete)
        try ledger.saveResult(context: context, decisions: [:])
        let reopened = try open()
        try allowance(reopened).reconcile { _ in nil }
        XCTAssertEqual(try storage.read()?.used, 1)
        XCTAssertEqual(try rows(reopened).map(\.id), [id])
        try allowance(reopened).settle(id: id, charge: false)
        XCTAssertEqual(try storage.read()?.used, 1)
    }

    func testClarificationReplacementRetainsRootAndCostsAtMostOnceAfterDeletion() throws {
        let container = try open()
        let ledger = allowance(container)
        let root = try raw(ledger)
        let replacement = try raw(ledger, policy: .replacement(root))
        XCTAssertEqual(try rows(container).first(where: { $0.id == replacement })?.chargeKey, root)
        XCTAssertEqual(try ledger.usageIncludingPending(), 1)
        let context = container.mainContext
        let original = try XCTUnwrap(context.fetch(FetchDescriptor<CaptureSession>()).first(where: { $0.id == root }))
        context.delete(original)
        try ledger.saveResult(context: context, decisions: [:])
        try ledger.reconcile { _ in nil }
        try ledger.settle(id: replacement, charge: true)
        XCTAssertEqual(try storage.read()?.used, 1)
        XCTAssertEqual(try storage.read()?.creditedKeys, [root])
        // An explicit retry of the same capture ID cannot upsert pending over a terminal row.
        _ = try raw(ledger, id: root)
        XCTAssertEqual(try rows(container).first(where: { $0.id == root })?.stateRawValue, "charged")
    }

    func testTwoFileBackedContainersCompeteForTenthSlotAndReleaseExemption() throws {
        storage.legacy = 9
        let first = try open()
        let second = try open()
        let a = allowance(first), b = allowance(second)
        let id = try raw(a)
        XCTAssertEqual(try b.usageIncludingPending(), 10)
        XCTAssertThrowsError(try raw(b)) { XCTAssertTrue($0 is CaptureAccessError) }
        XCTAssertEqual(try ModelContext(second).fetchCount(FetchDescriptor<CaptureSession>()), 1)
        try a.settle(id: id, charge: false)
        _ = try raw(b)
        XCTAssertEqual(try a.usageIncludingPending(), 10)
        XCTAssertEqual(try storage.read()?.used, 9, "Reserved slots must never enter the legacy spent counter")
    }

    func testProAndPracticeSnapshotNeverChargeAfterEntitlementChange() throws {
        let container = try open()
        let ledger = allowance(container)
        let pro = try raw(ledger, policy: .pro)
        let practice = try raw(ledger, policy: .practice)
        try ledger.settle(id: pro, charge: true)
        try ledger.settle(id: practice, charge: true)
        XCTAssertEqual(try ledger.usageIncludingPending(), 0)
        XCTAssertEqual(try rows(container).map(\.stateRawValue), ["exempt", "exempt"])
    }

    func testUnreadableJournalCannotReseedInclusiveLegacyCounter() throws {
        let container = try open()
        let ledger = allowance(container)
        let id = try raw(ledger)
        try ledger.settle(id: id, charge: true)
        storage.unreadable = true
        XCTAssertThrowsError(try raw(ledger))
        storage.unreadable = false
        XCTAssertEqual(try storage.read()?.baseline, 0)
        XCTAssertEqual(try storage.read()?.used, 1)
    }

    func testUnavailableCreditDoesNotBlockOtherFinalExemptReservationOnForegroundRepair() throws {
        let container = try open()
        let ledger = allowance(container)
        let chargeable = try raw(ledger)
        let operation = try raw(ledger)
        for session in try container.mainContext.fetch(FetchDescriptor<CaptureSession>()) {
            session.processingStatus = .complete
        }
        try ledger.saveResult(context: container.mainContext, decisions: [chargeable: true, operation: false])
        storage.identityHistoryAvailable = false
        XCTAssertThrowsError(try ledger.reconcile { _ in nil })
        XCTAssertEqual(try rows(container).first(where: { $0.id == operation })?.stateRawValue, "exempt")
        XCTAssertEqual(try rows(container).first(where: { $0.id == chargeable })?.stateRawValue, "pending")
        XCTAssertEqual(try ledger.usageIncludingPending(), 1)
        XCTAssertEqual(storage.legacy, 0, "A pending reservation cannot earn a Pro capture moment")
        XCTAssertNil(ProMoment.due(forCaptureCount: storage.legacy))
        storage.identityHistoryAvailable = true
        try ledger.reconcile { _ in nil }
        XCTAssertEqual(try storage.read()?.used, 1)
        XCTAssertEqual(ProMoment.due(forCaptureCount: storage.legacy), .firstCapture)
    }

    func testFileFallbackReservesRawWithoutCreditingOrReseedingUntilIdentityRepair() throws {
        let container = try open()
        let ledger = allowance(container)
        let first = try raw(ledger)
        try ledger.settle(id: first, charge: true)
        storage.identityHistoryAvailable = false
        storage.legacy = 3
        let pending = try raw(ledger)
        XCTAssertEqual(try ledger.usageIncludingPending(), 4, "Legacy mirror is a conservative capacity floor")
        XCTAssertEqual(try storage.read()?.baseline, 0, "Unreadable identity history must not become a new baseline")
        XCTAssertThrowsError(try ledger.settle(id: pending, charge: true))
        XCTAssertEqual(try rows(container).first(where: { $0.id == pending })?.stateRawValue, "pending")
        // Repair sees the missing credited IDs before using the legacy floor.
        var repaired = try XCTUnwrap(storage.read())
        repaired.creditedKeys.formUnion([UUID(), UUID()])
        try storage.write(repaired)
        storage.identityHistoryAvailable = true
        try ledger.settle(id: pending, charge: true)
        XCTAssertEqual(try storage.read()?.used, 4)
        XCTAssertEqual(try storage.read()?.baseline, 0)
    }

    func testUnreadableLegacyIdentityCannotSeedFirstJournalOrSaveRaw() throws {
        let container = try open()
        storage.legacy = 8
        storage.identityHistoryAvailable = false
        XCTAssertThrowsError(try raw(allowance(container)))
        XCTAssertNil(try storage.read())
        XCTAssertEqual(storage.legacy, 8)
        XCTAssertEqual(try ModelContext(container).fetchCount(FetchDescriptor<CaptureSession>()), 0)
        storage.identityHistoryAvailable = true
        _ = try raw(allowance(container))
        XCTAssertEqual(try storage.read()?.baseline, 8)
        XCTAssertEqual(try allowance(container).usageIncludingPending(), 9)
    }

    func testLedgerIdentityMatchesLegacyBackupEligibilityAndDoesNotSynchronize() {
        XCTAssertEqual(DeviceCaptureAllowanceJournalStorage.keychainAccessibility as String,
            FreeCaptureLedger.keychainAccessibility as String)
        XCTAssertEqual(DeviceCaptureAllowanceJournalStorage.keychainAccessibility as String,
            kSecAttrAccessibleAfterFirstUnlock as String)
        XCTAssertFalse(DeviceCaptureAllowanceJournalStorage.keychainSynchronizable)
    }

    func testTypedRecoveryPreservesPracticeSourceAndNeverConsumesTrial() async throws {
        for source in CaptureSource.allCases {
            XCTAssertEqual(source.typedRecoverySource, source == .tutorial ? .tutorial : .inAppText)
        }
        let container = try open()
        let result = try await capture(repository(container), "Buy apples", policy: .free,
            source: CaptureSource.tutorial.typedRecoverySource)
        XCTAssertEqual(result.session.captureSource, .tutorial)
        XCTAssertFalse(result.consumesFreeCapture)
        XCTAssertEqual(try allowance(container).usageIncludingPending(), 0)
    }

    func testReinstallKeepsLegacyBaselineAndExternalCredits() throws {
        storage.legacy = 7
        let old = try open()
        let oldLedger = allowance(old)
        let id = try raw(oldLedger)
        try oldLedger.settle(id: id, charge: true)
        let fresh = try open("reinstall")
        XCTAssertEqual(try allowance(fresh).usageIncludingPending(), 8)
        XCTAssertEqual(try storage.read()?.baseline, 7)
        XCTAssertEqual(try storage.read()?.creditedKeys, [id])
    }

    func testLockIsNonblockingAndDoesNotCommitWordsWhenBusy() throws {
        let container = try open()
        let ledger = allowance(container)
        try CaptureAllowanceLock(url: lockURL).withLock {
            XCTAssertThrowsError(try raw(ledger)) { XCTAssertTrue($0 is CaptureAllowanceStorageError) }
        }
        XCTAssertEqual(try ModelContext(container).fetchCount(FetchDescriptor<CaptureSession>()), 0)
        _ = try raw(ledger)
        XCTAssertEqual(try ledger.usageIncludingPending(), 1)
    }

    func testProductionRepositoryRejectsMissingPolicyAndTutorialForcesExemption() async throws {
        let container = try open()
        let saved = repository(container)
        do {
            _ = try await saved.createCaptureResult(text: "Buy apples", source: .inAppText,
                createdAt: .now, schedulesReminders: false)
            XCTFail("A metered repository must require an explicit policy snapshot")
        } catch { XCTAssertEqual(error as? RepositoryError, .storageUnavailable) }
        _ = try await capture(saved, "Buy apples", policy: .free, source: .tutorial)
        XCTAssertEqual(try allowance(container).usageIncludingPending(), 0)
        XCTAssertEqual(try rows(container).first?.policyRawValue, "practice")
    }

    func testRepositoryContentDuplicateOperationAndMixedMatchExistingContract() async throws {
        let container = try open()
        let saved = repository(container)
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let first = try await capture(saved, "Call the dentist tomorrow", at: start)
        XCTAssertTrue(first.consumesFreeCapture)
        XCTAssertEqual(try allowance(container).usageIncludingPending(), 1)
        let duplicate = try await capture(saved, "Call the dentist tomorrow", at: start.addingTimeInterval(1))
        XCTAssertTrue(duplicate.isDuplicate)
        XCTAssertEqual(try allowance(container).usageIncludingPending(), 1)
        let operation = try await capture(saved, "Mark the dentist task complete", at: start.addingTimeInterval(20))
        XCTAssertNotNil(operation.operationOutcome)
        XCTAssertFalse(operation.consumesFreeCapture)
        XCTAssertEqual(try allowance(container).usageIncludingPending(), 1)
        _ = try await capture(saved, "Call the clinic tomorrow", policy: .pro, at: start.addingTimeInterval(40))
        let mixed = try await capture(saved, "Mark the clinic task complete. Also buy eggs.", at: start.addingTimeInterval(60))
        XCTAssertNotNil(mixed.operationOutcome)
        XCTAssertTrue(mixed.consumesFreeCapture)
        XCTAssertEqual(try allowance(container).usageIncludingPending(), 2)
        let reopened = try open()
        repository(reopened).recoverUnorganizedCaptures()
        XCTAssertEqual(try allowance(reopened).usageIncludingPending(), 2)
    }

    func testOperationOutcomeSurvivesSessionDeletionBeforeSettlement() async throws {
        for mixed in [false, true] {
            let container = try open(mixed ? "mixed-delete" : "operation-delete")
            let saved = repository(container)
            let start = Date(timeIntervalSince1970: 1_800_000_000)
            _ = try await capture(saved, "Remind me about the dentist on Friday", policy: .pro, at: start)
            let result = try await saved.createCaptureResult(
                text: mixed ? "Cancel the dentist reminder. Also buy milk." : "Cancel the dentist reminder",
                source: .inAppText, createdAt: start.addingTimeInterval(20), allowancePolicy: .free,
                schedulesReminders: false, onDurablySaved: { [self] _ in storage.unreadable = true })
            XCTAssertNotNil(result.operationOutcome)
            XCTAssertEqual(result.consumesFreeCapture, mixed)
            let row = try XCTUnwrap(rows(container).first(where: { $0.id == result.session.id }))
            XCTAssertEqual(row.stateRawValue, "pending")
            XCTAssertEqual(row.finalCharge, mixed, "Outcome must join the operation's result transaction")
            container.mainContext.delete(result.session)
            try allowance(container).saveResult(context: container.mainContext, decisions: [:])
            storage.unreadable = false
            let reopened = try open(mixed ? "mixed-delete" : "operation-delete")
            repository(reopened).reconcileCaptureAllowance()
            XCTAssertEqual(try storage.read()?.used, mixed ? 1 : 0)
        }
    }

    /// Preserve the simulator's unrelated checkpoint state and isolate the
    /// crash-attempt ledger. These cases create text checkpoints, never audio.
    private func withIsolatedRecoveryCheckpoint(_ body: () async throws -> Void) async throws {
        let defaults = UserDefaults.standard
        func isCheckpointKey(_ key: String) -> Bool {
            key == "SpeakIt.activeCaptureDraft"
                || key.hasPrefix("SpeakIt.activeCaptureDraft.supplemental.")
                || key == "SpeakIt.deletedCaptureRecoveryIDs"
        }
        let previous = defaults.dictionaryRepresentation().filter { isCheckpointKey($0.key) }
        for key in previous.keys { defaults.removeObject(forKey: key) }
        let suite = "SpeakItAllowanceRecovery-\(UUID().uuidString)"
        let attempts = try XCTUnwrap(UserDefaults(suiteName: suite))
        let previousAttempts = CaptureRecoveryAttemptLedger.defaults
        CaptureRecoveryAttemptLedger.defaults = attempts
        defer {
            for key in defaults.dictionaryRepresentation().keys where isCheckpointKey(key) {
                defaults.removeObject(forKey: key)
            }
            for (key, value) in previous { defaults.set(value, forKey: key) }
            CaptureRecoveryAttemptLedger.defaults = previousAttempts
            attempts.removePersistentDomain(forName: suite)
        }
        try await body()
    }

    func testExhaustedDraftDuplicatePreservesCompletedCaptureAndOperation() async throws {
        for isOperation in [false, true] {
            try await withIsolatedRecoveryCheckpoint {
                let name = isOperation ? "completed-operation-draft" : "completed-content-draft"
                let container = try open(name)
                let saved = repository(container)
                let createdAt = Date.now.addingTimeInterval(-120)
                if isOperation {
                    _ = try await capture(saved, "Remind me about the dentist on Friday", policy: .pro,
                        at: createdAt.addingTimeInterval(-20))
                }
                let text = isOperation ? "Cancel the dentist reminder" : "Buy milk"
                let result = try await capture(saved, text, at: createdAt)
                XCTAssertEqual(result.session.processingStatus, .complete)
                if isOperation {
                    guard case .performed = result.operationOutcome else {
                        return XCTFail("The fixture must contain a completed saved operation")
                    }
                    XCTAssertTrue(result.items.isEmpty)
                }
                let sessionID = result.session.id
                let operationState = result.session.operationStateData
                let itemIDs = result.items.map(\.id)
                let titles = result.items.map(\.displayTitle)
                let reviewFlags = result.items.map(\.needsClarification)
                let sessionCount = try container.mainContext.fetchCount(FetchDescriptor<CaptureSession>())
                let obligationCount = try rows(container).count
                let journal = try storage.read()
                let draft = CaptureDraftStore.begin(source: .inAppText, at: createdAt)
                CaptureDraftStore.update(id: draft.id, transcript: text, at: createdAt)
                for _ in 0..<CaptureRecoveryAttemptLedger.maximumAttempts {
                    CaptureRecoveryAttemptLedger.begin(draft.id)
                }

                saved.recoverInterruptedCaptureDraft()

                XCTAssertNil(CaptureDraftStore.recoverable())
                XCTAssertEqual(CaptureRecoveryAttemptLedger.attempts(for: draft.id), 0)
                XCTAssertEqual(CaptureRecoveryAttemptLedger.attempts(for: sessionID), 0,
                    "A leftover checkpoint must not quarantine an already completed capture")
                let reopened = try open(name)
                let context = ModelContext(reopened)
                let persisted = try XCTUnwrap(context.fetch(FetchDescriptor<CaptureSession>()).first { $0.id == sessionID })
                XCTAssertEqual(persisted.processingStatus, .complete)
                XCTAssertNil(persisted.processingError)
                XCTAssertEqual(persisted.originalTranscription, text)
                XCTAssertEqual(persisted.operationStateData, operationState)
                XCTAssertEqual(persisted.items.map(\.id), itemIDs)
                XCTAssertEqual(persisted.items.map(\.displayTitle), titles)
                XCTAssertEqual(persisted.items.map(\.needsClarification), reviewFlags)
                XCTAssertEqual(try context.fetchCount(FetchDescriptor<CaptureSession>()), sessionCount)
                XCTAssertEqual(try rows(reopened).count, obligationCount)
                XCTAssertEqual(try storage.read(), journal, "Duplicate recovery cannot add a debit")
            }
        }
    }

    func testExhaustedDraftDuplicateStillQuarantinesPendingCaptureOnce() async throws {
        try await withIsolatedRecoveryCheckpoint {
            let container = try open("pending-duplicate-draft")
            let ledger = allowance(container)
            let id = UUID()
            let createdAt = Date.now.addingTimeInterval(-120)
            let text = "Unfinished synthetic capture"
            _ = try ledger.commit(id: id, createdAt: createdAt, policy: .free) { context in
                let session = CaptureSession(id: id, originalTranscription: text,
                    createdAt: createdAt, captureSource: .inAppText, processingStatus: .pending)
                context.insert(session)
                context.insert(CapturedItem(originalTextSegment: text, displayTitle: text,
                    createdAt: createdAt, processingConfidence: 0, needsClarification: true,
                    captureSession: session))
            }
            let draft = CaptureDraftStore.begin(source: .inAppText, at: createdAt)
            CaptureDraftStore.update(id: draft.id, transcript: text, at: createdAt)
            for _ in 0..<CaptureRecoveryAttemptLedger.maximumAttempts {
                CaptureRecoveryAttemptLedger.begin(draft.id)
            }

            repository(container).recoverInterruptedCaptureDraft()

            XCTAssertNil(CaptureDraftStore.recoverable())
            XCTAssertEqual(CaptureRecoveryAttemptLedger.attempts(for: draft.id), 0)
            let reopened = try open("pending-duplicate-draft")
            let context = ModelContext(reopened)
            let sessions = try context.fetch(FetchDescriptor<CaptureSession>())
            let session = try XCTUnwrap(sessions.first)
            XCTAssertEqual(sessions.map(\.id), [id])
            XCTAssertEqual(session.processingStatus, .failed)
            XCTAssertEqual(session.processingError, CaptureRecoveryAttemptLedger.quarantineMessage)
            XCTAssertEqual(session.originalTranscription, text)
            XCTAssertEqual(session.items.count, 1)
            XCTAssertTrue(try XCTUnwrap(session.items.first).needsClarification)
            XCTAssertGreaterThan(CaptureRecoveryAttemptLedger.attempts(for: id),
                CaptureRecoveryAttemptLedger.maximumAttempts)
            XCTAssertEqual(try rows(reopened).map(\.id), [id])
            XCTAssertEqual(try storage.read()?.used, 1)
            XCTAssertEqual(try storage.read()?.creditedKeys, [id])
        }
    }

    /// Production construction and callers cannot silently use the unmetered
    /// convenience APIs retained for legacy test and preview fixtures.
    func testEveryProductionCapturePathSuppliesAccountingAndPolicy() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let files = ["SpeakIt/App/SpeakItApp.swift", "SpeakIt/Intents/SaveThoughtIntent.swift",
                     "SpeakIt/App/RootView.swift", "SpeakIt/Features/Capture/CaptureView.swift",
                     "SpeakIt/Features/Shopping/ShoppingListView.swift", "SpeakIt/Features/Today/TodayView.swift",
                     "SpeakIt/Features/Library/LibraryView.swift"]
        for file in files {
            let source = try String(contentsOf: root.appendingPathComponent(file), encoding: .utf8)
            for marker in ["SwiftDataThoughtRepository(", "repository.createCaptureResult(", "repository.addShoppingItems(", "repository.addMemoryNote("] {
                var remainder = source[...]
                while let match = remainder.range(of: marker) {
                    let tail = remainder[match.upperBound...]
                    var depth = 1, end = tail.startIndex
                    for index in tail.indices {
                        if tail[index] == "(" { depth += 1 }
                        if tail[index] == ")" { depth -= 1 }
                        if depth == 0 { end = index; break }
                    }
                    let arguments = tail[..<end]
                    XCTAssertTrue(arguments.contains(marker == "SwiftDataThoughtRepository(" ? "captureAllowance:" : "allowancePolicy:"), file + " " + marker)
                    remainder = tail[end...].dropFirst()
                }
            }
            XCTAssertFalse(source.contains("recordBackgroundCapture("), file)
            XCTAssertFalse(source.contains("recordSuccessfulCapture("), file)
        }
        let history = try String(contentsOf: root.appendingPathComponent("SpeakIt/Features/Today/TodayView.swift"), encoding: .utf8)
            .components(separatedBy: "struct CaptureHistoryView:")[1]
        XCTAssertTrue(history.contains("draft.captureSource.typedRecoverySource"))
        XCTAssertEqual(history.components(separatedBy: "subscriptionStore.refreshFreeAllowance()").count - 1, 2)
        let repositorySource = try String(contentsOf: root.appendingPathComponent("SpeakIt/Repositories/SwiftDataThoughtRepository.swift"), encoding: .utf8)
        let recovery = repositorySource.components(separatedBy: "func recoverInterruptedCaptureDraft()")[1]
            .components(separatedBy: "func reconcilePendingReminders()")[0]
        XCTAssertEqual(recovery.components(separatedBy: "allowancePolicy: SubscriptionStore.backgroundCapturePolicy").count - 1, 2)
    }
}
