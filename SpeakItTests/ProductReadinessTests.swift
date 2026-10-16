import CryptoKit
import XCTest
import SwiftData
import StoreKit
import StoreKitTest
@testable import SpeakIt

/// Local StoreKit receipts only. These tests never contact App Store Connect
/// or the disabled referral service, and never create a real purchase.
@MainActor
final class ProductStoreKitTests: XCTestCase {
    private var session: SKTestSession!
    private var store: SubscriptionStore!

    override func setUp() async throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "SpeakIt", withExtension: "storekit"))
        session = try SKTestSession(contentsOf: url)
        session.resetToDefaultState()
        session.clearTransactions()
        session.disableDialogs = true
        // Refuse app purchases unless its entitlement query demonstrably uses
        // Xcode's local server. A missing scheme setup must never ask for an
        // Apple Account or fall through to sandbox/production purchases.
        let canary = try await session.buyProduct(identifier: SubscriptionStore.lifetimeProductID)
        XCTAssertEqual(canary.environment, .xcode)
        var seesLocalReceipt = false
        // This is synthetic local-test evidence only. A non-Xcode environment
        // is counted without recording its account transaction or product.
        let knownSyntheticProducts = Set(SubscriptionStore.productIDs + [SubscriptionStore.lifetimeProductID])
        func describe(_ transaction: StoreKit.Transaction,verification: String) -> String {
            guard transaction.environment == .xcode, knownSyntheticProducts.contains(transaction.productID) else {
                return verification + " claimedEnvironment=" + transaction.environment.rawValue + " transactionDetails=omitted"
            }
            return verification + " claimedEnvironment=xcode id=" + String(transaction.id) + " product=" + transaction.productID
        }
        var diagnostic = [describe(canary,verification:"localCanary")]
        let initialQueryStart=Date.now.timeIntervalSince1970
        var initialVerifiedCount=0,initialUnverifiedCount=0
        for await result in StoreKit.Transaction.currentEntitlements {
            switch result {
            case .verified(let transaction):
                initialVerifiedCount+=1
                diagnostic.append(describe(transaction,verification:"verified"))
                if transaction.id == canary.id, transaction.environment == .xcode {
                    seesLocalReceipt = true
                }
            case .unverified(let transaction,let error):
                initialUnverifiedCount+=1
                let label: String
                switch error {
                case .revokedCertificate: label = "revokedCertificate"
                case .invalidCertificateChain: label = "invalidCertificateChain"
                case .invalidDeviceVerification: label = "invalidDeviceVerification"
                case .invalidEncoding: label = "invalidEncoding"
                case .invalidSignature: label = "invalidSignature"
                case .missingRequiredProperties: label = "missingRequiredProperties"
                @unknown default: label = "unknownVerificationError"
                }
                diagnostic.append(describe(transaction,verification:"unverified:" + label))
            }
        }
        // Freeze the original check before ANY extra async diagnostic read.
        let originalSeesLocalReceipt=seesLocalReceipt
        let initialQueryEnd=Date.now.timeIntervalSince1970
        var rawCanary:[String:Any]=["claimedEnvironment":canary.environment.rawValue,"verification":"UNOBSERVED-raw-SKTestSession-return"]
        if canary.environment == .xcode,knownSyntheticProducts.contains(canary.productID) {
            rawCanary.merge(["id":String(canary.id),"productID":canary.productID,"appBundleID":canary.appBundleID,
                "productType":canary.productType.rawValue,"purchaseUnixSeconds":canary.purchaseDate.timeIntervalSince1970,
                "expirationUnixSeconds":observedDate(canary.expirationDate),"revocationUnixSeconds":observedDate(canary.revocationDate)]) { _,new in new }
        }
        let originalBoundary:[String:Any]=["scope":"Original local canary boundary BEFORE additional diagnostic awaits; monthly body not started",
            "initialSeesVerifiedMatchingLocalReceipt":originalSeesLocalReceipt,"initialVerifiedCount":initialVerifiedCount,
            "initialUnverifiedCount":initialUnverifiedCount,"initialGlobalQueryStartUnixSeconds":initialQueryStart,
            "initialGlobalQueryEndUnixSeconds":initialQueryEnd,"rawCanary":rawCanary,
            "mainBundleID":Bundle.main.bundleIdentifier ?? "UNAVAILABLE","testBundleID":Bundle(for:Self.self).bundleIdentifier ?? "UNAVAILABLE",
            "configurationURL":url.path,"configurationSHA256":(try? Data(contentsOf:url)).map { SHA256.hash(data:$0).map { String(format:"%02x",$0) }.joined() } ?? "UNAVAILABLE"]
        try retainStoreKitObservation("Local-canary-ORIGINAL-boundary-before-diagnostic-await",originalBoundary)
        diagnostic.append("matchingVerifiedLocalReceipt=" + String(seesLocalReceipt))
        for transaction in session.allTransactions() where knownSyntheticProducts.contains(transaction.productIdentifier) {
            diagnostic.append("localSession id=" + String(transaction.identifier) + " product=" + transaction.productIdentifier + " state=" + String(transaction.state.rawValue))
        }
        XCTContext.runActivity(named:"Synthetic local StoreKit canary boundary") { activity in
            let attachment = XCTAttachment(string:diagnostic.joined(separator:"\n"))
            attachment.lifetime = .keepAlways
            activity.add(attachment)
        }
        guard originalSeesLocalReceipt else {
            // Later observations cannot turn the original failed check into a
            // pass or permit monthly app purchases. They identify API/client
            // binding evidence without refresh, sync, finish or another buy.
            try await observeFailedCanaryAfterOriginalBoundary(originalBoundary)
            throw NSError(domain: "SpeakItProductReadiness", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Local canary was not observed as a verified matching current entitlement at the original check; monthly body not executed"])
        }
        session.clearTransactions()
        store = SubscriptionStore()
        store.setDeveloperAccessOverride(.appStore)
    }

    private func observeFailedCanaryAfterOriginalBoundary(_ original:[String:Any]) async throws {
        let latestStart=Date.now.timeIntervalSince1970
        let latest:[String:Any]
        if let value=await StoreKit.Transaction.latest(for:SubscriptionStore.lifetimeProductID) { latest=observedVerification(value) }
        else { latest=["status":"no-latest-transaction"] }
        let latestEnd=Date.now.timeIntervalSince1970
        let targetedStart=Date.now.timeIntervalSince1970
        var targeted:[[String:Any]]=[]
        let targetedStatus:String
        if #available(iOS 18.4, *) {
            targetedStatus="observed"
            for await value in StoreKit.Transaction.currentEntitlements(for:SubscriptionStore.lifetimeProductID) {
                targeted.append(observedVerification(value))
            }
        } else { targetedStatus="SDK-API-unavailable" }
        let targetedEnd=Date.now.timeIntervalSince1970
        try retainStoreKitObservation("Local-canary-SDK-reads-AFTER-original-failure",[
            "scope":"Diagnostic only; original initial boolean remains false; monthly body cannot run",
            "originalBoundary":original,"latestQueryStartUnixSeconds":latestStart,"latestQueryEndUnixSeconds":latestEnd,
            "latest":latest,"targetedEntitlementsStatus":targetedStatus,"targetedQueryStartUnixSeconds":targetedStart,
            "targetedQueryEndUnixSeconds":targetedEnd,"targetedEntitlements":targeted])
    }

    override func tearDownWithError() throws {
        store = nil
        session?.clearTransactions()
        session?.resetToDefaultState()
        session = nil
    }

    func testProductLoadingFailureRetriesAndKeepsFreeAccess() async throws {
        try await session.setSimulatedError(.generic(.networkError(URLError(.notConnectedToInternet))), forAPI: .loadProducts)
        await store.loadProducts(force: true)
        XCTAssertTrue(store.products.isEmpty)
        XCTAssertFalse(store.isLoadingProducts)
        await store.refreshEntitlements()
        XCTAssertFalse(store.hasProAccess)
        try await session.setSimulatedError(nil, forAPI: .loadProducts)
        await store.prepare()
        XCTAssertEqual(Set(store.products.map(\.id)), Set(SubscriptionStore.productIDs))
        XCTAssertEqual(store.monthlyProduct?.price, Decimal(string: "2.99"))
        XCTAssertEqual(store.annualProduct?.price, Decimal(string: "14.99"))
        XCTAssertTrue(store.annualIsBestValue)
    }

    private func storeBoundary(_ phase: String) -> [String: Any] {
        ["phase": phase, "observedUnixSeconds": Date.now.timeIntervalSince1970,
         "hasProAccess": store.hasProAccess,
         "activeProProductIDs": store.activeProProductIDs.sorted(),
         "accessLevel": String(describing: store.accessLevel),
         "developerAccessOverride": store.developerAccessOverride.rawValue]
    }
    
    private func observedDate(_ date: Date?) -> Any {
        if let date { return date.timeIntervalSince1970 }
        return NSNull()
    }
    
    private func observedVerification(_ value: VerificationResult<StoreKit.Transaction>) -> [String: Any] {
        let transaction: StoreKit.Transaction
        let verification: String
        switch value {
        case .verified(let t): transaction = t; verification = "verified"
        case .unverified(let t, let error):
            transaction = t
            let reason: String
            switch error {
            case .revokedCertificate: reason = "revokedCertificate"
            case .invalidCertificateChain: reason = "invalidCertificateChain"
            case .invalidDeviceVerification: reason = "invalidDeviceVerification"
            case .invalidEncoding: reason = "invalidEncoding"
            case .invalidSignature: reason = "invalidSignature"
            case .missingRequiredProperties: reason = "missingRequiredProperties"
            @unknown default: reason = "unknownVerificationError"
            }
            verification = "unverified:" + reason
        }
        var row: [String: Any] = ["verification": verification,
            "claimedEnvironment": transaction.environment.rawValue,
            "observedUnixSeconds": Date.now.timeIntervalSince1970]
        let known = Set(SubscriptionStore.productIDs + [SubscriptionStore.lifetimeProductID])
        guard transaction.environment == .xcode, known.contains(transaction.productID) else {
            row["transactionDetails"] = "omitted-nonlocal-or-unknown-product"
            return row
        }
        // Decimal IDs as strings, avoiding UInt64 -> JSON number precision loss.
        row["id"] = String(transaction.id)
        row["originalID"] = String(transaction.originalID)
        row["productID"] = transaction.productID
        row["appBundleID"] = transaction.appBundleID
        row["productType"] = transaction.productType.rawValue
        row["purchaseUnixSeconds"] = transaction.purchaseDate.timeIntervalSince1970
        row["expirationUnixSeconds"] = observedDate(transaction.expirationDate)
        row["revocationUnixSeconds"] = observedDate(transaction.revocationDate)
        row["isUpgraded"] = transaction.isUpgraded
        // These are claimed fields for an unverified value, never an entitlement grant.
        return row
    }
    
    private func retainStoreKitObservation(_ name: String, _ record: [String: Any]) throws {
        let bytes = try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys, .prettyPrinted])
        let attachment = XCTAttachment(data: bytes, uniformTypeIdentifier: "public.json")
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
    
    private func observeExpirationAfterOriginalAssertions(boundaries: [[String: Any]]) async throws {
        let known = Set(SubscriptionStore.productIDs + [SubscriptionStore.lifetimeProductID])
        let localRows: [[String: Any]] = session.allTransactions().filter {
            known.contains($0.productIdentifier)
        }.map { t in
            ["id": String(t.identifier), "originalID": String(t.originalTransactionIdentifier),
             "productID": t.productIdentifier, "stateRawValue": t.state.rawValue,
             "purchaseUnixSeconds": t.purchaseDate.timeIntervalSince1970,
             "expirationUnixSeconds": observedDate(t.expirationDate),
             "cancelUnixSeconds": observedDate(t.cancelDate),
             "autoRenewingEnabled": t.autoRenewingEnabled,
             "pendingAskToBuyConfirmation": t.pendingAskToBuyConfirmation,
             "hasPurchaseIssue": t.hasPurchaseIssue]
        }
        // Persist immediate values before any diagnostic async suspension can race
        // transaction-update refreshes. Both original final assertions already ran.
        try retainStoreKitObservation("Monthly-expiration-original-boundary-BEFORE-diagnostic-await", [
            "scope": "Local SKTestSession only; test-only observation; no app/account mutation",
            "boundaries": boundaries, "localSessionReadUnixSeconds": Date.now.timeIntervalSince1970,
            "localSessionTransactions": localRows])
        let entitlementStart = Date.now.timeIntervalSince1970
        var entitlements: [[String: Any]] = []
        for await value in StoreKit.Transaction.currentEntitlements {
            entitlements.append(observedVerification(value))
        }
        let entitlementEnd = Date.now.timeIntervalSince1970
        let latestStart = Date.now.timeIntervalSince1970
        let latest: [String: Any]
        if let value = await StoreKit.Transaction.latest(for: SubscriptionStore.monthlyProductID) {
            latest = observedVerification(value)
        } else {
            latest = ["status": "no-latest-transaction"]
        }
        let latestEnd = Date.now.timeIntervalSince1970
        try retainStoreKitObservation("Monthly-expiration-SDK-reads-AFTER-original-assertions", [
            "scope": "Subsequent SDK observations; not simultaneous with original assertion boundary",
            "currentEntitlementsQueryStartUnixSeconds": entitlementStart,
            "currentEntitlementsQueryEndUnixSeconds": entitlementEnd,
            "currentEntitlements": entitlements,
            "monthlyLatestQueryStartUnixSeconds": latestStart,
            "monthlyLatestQueryEndUnixSeconds": latestEnd, "monthlyLatest": latest,
            "storeAfterSDKReads": storeBoundary("after-diagnostic-sdk-reads")])
        try await observeTargetedMonthlyAfterOriginalAndGlobalLatestReads()
    }

    private func observeTargetedMonthlyAfterOriginalAndGlobalLatestReads() async throws {
        let queryStart = Date.now.timeIntervalSince1970
        var rows: [[String: Any]] = []
        let availability: String
        if #available(iOS 18.4, *) {
            availability = "available"
            for await value in StoreKit.Transaction.currentEntitlements(for: SubscriptionStore.monthlyProductID) {
                rows.append(observedVerification(value))
            }
        } else {
            availability = "API-unavailable"
        }
        let queryEnd = Date.now.timeIntervalSince1970
        try retainStoreKitObservation("Monthly-expiration-targeted-SDK-read-AFTER-original-and-global-latest", [
            "scope": "Subsequent local-known targeted SDK observation only; original assertions and earlier reads already completed",
            "productID": SubscriptionStore.monthlyProductID,
            "queryAvailability": availability,
            "queryStartUnixSeconds": queryStart, "queryEndUnixSeconds": queryEnd,
            "observedCount": rows.count, "targetedMonthlyEntitlements": rows,
            "storeAfterTargetedRead": storeBoundary("after-diagnostic-targeted-monthly-read")])
    }

    func testMonthlyPurchaseRestoreReplayAndExpiration() async throws {
        await store.prepare()
        let monthly = try XCTUnwrap(store.monthlyProduct)
        let purchased = await store.purchase(monthly)
        XCTAssertTrue(purchased)
        XCTAssertTrue(store.hasActiveSubscription)
        XCTAssertFalse(store.hasLifetimeProAccess)
        let purchaseBoundary=storeBoundary("after-original-purchase-assertions")
        let count = store.freeCapturesUsed
        store.recordSuccessfulCapture()
        XCTAssertEqual(store.freeCapturesUsed, count)
        await store.refreshEntitlements()
        await store.refreshEntitlements()
        XCTAssertEqual(store.activeProProductIDs, [SubscriptionStore.monthlyProductID])
        let replayBoundary=storeBoundary("after-original-replay-assertion")
        await store.restorePurchases()
        XCTAssertTrue(store.hasProAccess)
        let restoreBoundary=storeBoundary("after-original-restore-assertion")
        try session.expireSubscription(productIdentifier: SubscriptionStore.monthlyProductID)
        await store.refreshEntitlements()
        let expirationBoundary=storeBoundary("post-expire-refresh-before-original-assertions")
        XCTAssertFalse(store.hasProAccess)
        XCTAssertTrue(store.activeProProductIDs.isEmpty)
        try await observeExpirationAfterOriginalAssertions(boundaries:[purchaseBoundary,replayBoundary,restoreBoundary,expirationBoundary])
    }

    func testPendingPurchaseUnlocksOnlyAfterApproval() async throws {
        session.askToBuyEnabled = true
        await store.prepare()
        let annual = try XCTUnwrap(store.annualProduct)
        let purchased = await store.purchase(annual)
        XCTAssertFalse(purchased)
        XCTAssertFalse(store.hasProAccess)
        let pending = try XCTUnwrap(session.allTransactions().first { $0.pendingAskToBuyConfirmation })
        try session.approveAskToBuyTransaction(identifier: pending.identifier)
        // Exercise the transaction observer rather than forcing a refresh.
        let deadline = ContinuousClock.now + .seconds(10)
        while !store.hasProAccess && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertTrue(store.hasProAccess)
        XCTAssertEqual(store.activeProProductIDs, [SubscriptionStore.annualProductID])
    }

    func testCancelledAndOfflinePurchasesNeverUnlockOrSpendAllowance() async throws {
        await store.prepare()
        let monthly = try XCTUnwrap(store.monthlyProduct)
        let count = store.freeCapturesUsed
        for error in [StoreKitError.userCancelled, .networkError(URLError(.notConnectedToInternet))] {
            try await session.setSimulatedError(.generic(error), forAPI: .purchase)
            let purchased = await store.purchase(monthly)
            XCTAssertFalse(purchased)
            XCTAssertFalse(store.hasProAccess)
            XCTAssertFalse(store.isPurchasing)
            XCTAssertEqual(store.freeCapturesUsed, count)
        }
    }

    func testComplimentaryLifetimeEntitlementIsRecognizedButNeverSold() async throws {
        await store.prepare()
        XCTAssertFalse(store.products.contains { $0.id == SubscriptionStore.lifetimeProductID })
        try await session.buyProduct(identifier: SubscriptionStore.lifetimeProductID)
        await store.refreshEntitlements()
        XCTAssertTrue(store.hasLifetimeProAccess)
        XCTAssertFalse(store.hasActiveSubscription)
        await store.restorePurchases()
        XCTAssertTrue(store.hasLifetimeProAccess)
    }
}

@MainActor
final class ProductShortCaptureTests: XCTestCase {
    func testPredeclaredOrdinaryCapturesThroughProductionRepository() async throws {
        let previousZone = NSTimeZone.default
        NSTimeZone.default = TimeZone(identifier: "America/Toronto")!
        defer { NSTimeZone.default = previousZone }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Toronto")!
        let clock = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 3, hour: 10)))
        let cases: [(String, Int, Int?, ItemType?)] = [
            ("Call Maya", 1, 0, .personFollowUp),
            ("The spare key is in the blue drawer", 0, 1, .note),
            ("I have an idea for a weekly planning app", 0, 1, .idea),
            ("Remind me tomorrow at 9 AM to water the plants", 1, 0, .task),
            ("I do not want to call Maya", 0, nil, nil),
            ("Call Maya. The spare key is in the blue drawer.", 1, 1, nil)
        ]
        for (text, today, memory, type) in cases {
            let configuration = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
            let container = try ModelContainer(for: PersistenceController.schema,
                migrationPlan: SpeakItMigrationPlan.self, configurations: [configuration])
            let repository = SwiftDataThoughtRepository(modelContext: container.mainContext,
                                                        requestsReminderAuthorization: false)
            let result = try await repository.createCaptureResult(text: text, source: .inAppText,
                                                                 createdAt: clock, schedulesReminders: false)
            XCTAssertEqual(result.session.originalTranscription, text, text)
            XCTAssertEqual(result.items.filter(\.belongsInToday).count, today, text)
            if let memory { XCTAssertEqual(result.items.filter(\.belongsInMemory).count, memory, text) }
            if let type { XCTAssertEqual(result.items.first?.itemType, type, text) }
            if text.hasPrefix("Remind me") {
                let due = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 4, hour: 9)))
                XCTAssertEqual(result.items.first?.reminderDate, due, text)
            }
            if text.hasPrefix("I do not") { XCTAssertNil(result.operationOutcome, text) }
        }
    }
}

final class ProductSharedInboxTests: XCTestCase {
    func testUnreadableShareStaysVisibleWithoutHidingValidSharesOrDeletingBytes() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let payload = SharedCapturePayload(text: "Synthetic reference", createdAt: Date(timeIntervalSince1970: 100))
        let valid = directory.appendingPathComponent("valid.json")
        try JSONEncoder().encode(payload).write(to: valid)
        let corrupt = directory.appendingPathComponent("interrupted.json")
        let bytes = Data("{incomplete synthetic share".utf8)
        try bytes.write(to: corrupt)
        for _ in 0..<2 {
            let inspection = try SharedCaptureInbox.inspect(directory: directory)
            XCTAssertEqual(inspection.pending.map(\.payload), [payload])
            XCTAssertEqual(inspection.unreadableCount, 1)
            XCTAssertEqual(try Data(contentsOf: corrupt), bytes)
        }
    }

    func testMissingInboxIsEmptyButAnInvalidDirectoryThrows() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let missing = try SharedCaptureInbox.inspect(directory: directory)
        XCTAssertTrue(missing.pending.isEmpty)
        XCTAssertEqual(missing.unreadableCount, 0)
        try Data("synthetic file".utf8).write(to: directory)
        defer { try? FileManager.default.removeItem(at: directory) }
        XCTAssertThrowsError(try SharedCaptureInbox.inspect(directory: directory))
    }
}

@MainActor
final class ProductExternalCaptureAccessTests: XCTestCase {
    /// Real repository accounting with a durable, isolated journal. The writer
    /// test must not read, reset, or debit the installed app's allowance.
    private final class Journal: CaptureAllowanceJournalStorage {
        let url: URL
        let defaults: UserDefaults
        init(url: URL, defaults: UserDefaults) {
            self.url = url
            self.defaults = defaults
        }
        func read() throws -> CaptureAllowanceJournal? {
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            return try JSONDecoder().decode(CaptureAllowanceJournal.self, from: Data(contentsOf: url))
        }
        func write(_ journal: CaptureAllowanceJournal) throws {
            try JSONEncoder().encode(journal).write(to: url, options: .atomic)
        }
        func legacyCount() -> Int { defaults.integer(forKey: "SpeakIt.freeCapturesUsed") }
        func mirrorLegacyCount(_ count: Int) {
            defaults.set(max(count, legacyCount()), forKey: "SpeakIt.freeCapturesUsed")
        }
    }

    private struct Fixture {
        let directory: URL
        let suite: String
        let defaults: UserDefaults
        let journal: Journal
        let container: ModelContainer
        let allowance: CaptureAllowance
        let repository: SwiftDataThoughtRepository
    }

    private func openStore(in directory: URL) throws -> ModelContainer {
        try ModelContainer(for: PersistenceController.schema, migrationPlan: SpeakItMigrationPlan.self,
            configurations: [ModelConfiguration(schema: PersistenceController.schema,
                url: directory.appendingPathComponent("capture.store"), cloudKitDatabase: .none)])
    }

    private func fixture() throws -> Fixture {
        let suite = "SpeakItProductReadiness-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.set(DeveloperAccessOverride.free.rawValue, forKey: DeveloperAccessOverride.storageKey)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let journal = Journal(url: directory.appendingPathComponent("allowance.json"), defaults: defaults)
        let container = try openStore(in: directory)
        let allowance = CaptureAllowance(container: container, storage: journal,
            lockURL: directory.appendingPathComponent("allowance.lock"))
        let repository = SwiftDataThoughtRepository(modelContext: container.mainContext,
            requestsReminderAuthorization: false, permitsOnDeviceIntelligence: false,
            captureAllowance: allowance)
        return Fixture(directory: directory, suite: suite, defaults: defaults, journal: journal,
            container: container, allowance: allowance, repository: repository)
    }

    private func remove(_ fixture: Fixture) {
        fixture.defaults.removePersistentDomain(forName: fixture.suite)
        try? FileManager.default.removeItem(at: fixture.directory)
    }

    func testShortcutOperationsKeepAllowanceAndOrdinaryCaptureSpendsIt() async throws {
        let fixture = try fixture()
        defer { remove(fixture) }
        let defaults = fixture.defaults
        let repository = fixture.repository
        // This saved target supplies context; the operation assertions start
        // with all ten trial captures available, as they did before accounting
        // moved into the repository.
        _ = try await repository.createCaptureResult(text: "Remind me about the dentist on Friday",
            source: .inAppText, createdAt: .now, allowancePolicy: .pro, schedulesReminders: false)
        for (source, confirmation) in [
            ("Cancel the dentist reminder", "Cancelled"),
            ("Actually never mind", "Discarded"),
            ("Cancel the plumber reminder", "Couldn't find that")
        ] {
            let result = try await ExternalCaptureWriter.save(source, repository: repository, defaults: defaults,
                captureAdmission: { try fixture.allowance.usageIncludingPending() < FreePlanAllowance.lifetimeCaptureLimit })
            XCTAssertTrue(result.confirmationContext.hasPrefix(confirmation), source)
            XCTAssertFalse(result.needsInterpretationConfirmation, source)
            XCTAssertEqual(defaults.integer(forKey: "SpeakIt.freeCapturesUsed"), 0, source)
        }
        _ = try await ExternalCaptureWriter.save("Buy toothpaste", repository: repository, defaults: defaults,
            captureAdmission: { try fixture.allowance.usageIncludingPending() < FreePlanAllowance.lifetimeCaptureLimit })
        XCTAssertEqual(defaults.integer(forKey: "SpeakIt.freeCapturesUsed"), 1)
        _ = try await ExternalCaptureWriter.save("Buy toothpaste", repository: repository, defaults: defaults,
            captureAdmission: { try fixture.allowance.usageIncludingPending() < FreePlanAllowance.lifetimeCaptureLimit })
        XCTAssertEqual(defaults.integer(forKey: "SpeakIt.freeCapturesUsed"), 1, "Duplicate delivery must not spend twice")
        XCTAssertEqual(try fixture.journal.read()?.used, 1)
    }

    func testSeparateWriterContextsShareOneCaptureAndDebitForDuplicateDelivery() async throws {
        let fixture = try fixture()
        defer { remove(fixture) }
        let secondContainer = try openStore(in: fixture.directory)
        let secondAllowance = CaptureAllowance(container: secondContainer, storage: fixture.journal,
            lockURL: fixture.directory.appendingPathComponent("allowance.lock"))
        let secondRepository = SwiftDataThoughtRepository(modelContext: secondContainer.mainContext,
            requestsReminderAuthorization: false, permitsOnDeviceIntelligence: false,
            captureAllowance: secondAllowance)
        XCTAssertEqual(try secondContainer.mainContext.fetchCount(FetchDescriptor<CaptureSession>()), 0)
        let createdAt = Date(timeIntervalSince1970: 1_800_000_000)
        let first = try await ExternalCaptureWriter.save("Buy toothpaste", createdAt: createdAt,
            repository: fixture.repository, defaults: fixture.defaults,
            captureAdmission: { try fixture.allowance.usageIncludingPending() < FreePlanAllowance.lifetimeCaptureLimit })
        XCTAssertFalse(first.isDuplicate)
        let originalContext = ModelContext(fixture.container)
        let original = try XCTUnwrap(originalContext.fetch(FetchDescriptor<CaptureSession>()).first)
        let repeated = try await ExternalCaptureWriter.save("Buy toothpaste", createdAt: createdAt.addingTimeInterval(0.2),
            repository: secondRepository, defaults: fixture.defaults,
            captureAdmission: { try secondAllowance.usageIncludingPending() < FreePlanAllowance.lifetimeCaptureLimit })
        XCTAssertTrue(repeated.isDuplicate)
        let verificationContext = ModelContext(secondContainer)
        let sessions = try verificationContext.fetch(FetchDescriptor<CaptureSession>())
        XCTAssertEqual(sessions.map(\.id), [original.id])
        XCTAssertEqual(sessions.first?.items.map(\.id), original.items.map(\.id))
        let obligations = try verificationContext.fetch(FetchDescriptor<CaptureAllowanceObligation>())
        XCTAssertEqual(obligations.map(\.id), [original.id])
        XCTAssertEqual(obligations.first?.stateRawValue, "charged")
        XCTAssertEqual(try fixture.journal.read()?.creditedKeys, [original.id])
        XCTAssertEqual(fixture.defaults.integer(forKey: "SpeakIt.freeCapturesUsed"), 1)
        XCTAssertEqual(try secondAllowance.usageIncludingPending(), 1)
    }
}

@MainActor
final class ProductCheckpointReadTests: XCTestCase {
    private let key = "SpeakIt.activeCaptureDraft"
    private let prefix = "SpeakIt.activeCaptureDraft.supplemental."

    private func withIsolatedCheckpoints(_ body: () throws -> Void) rethrows {
        let defaults = UserDefaults.standard
        let keys = defaults.dictionaryRepresentation().keys.filter {
            $0 == key || $0.hasPrefix(prefix) || $0 == "SpeakIt.deletedCaptureRecoveryIDs"
        }
        let previous = Dictionary(uniqueKeysWithValues: keys.compactMap { k in
            defaults.object(forKey: k).map { (k, $0) }
        })
        keys.forEach { defaults.removeObject(forKey: $0) }
        defer {
            defaults.dictionaryRepresentation().keys.filter {
                $0 == key || $0.hasPrefix(prefix) || $0 == "SpeakIt.deletedCaptureRecoveryIDs"
            }.forEach { defaults.removeObject(forKey: $0) }
            previous.forEach { defaults.set($0.value, forKey: $0.key) }
        }
        try body()
    }

    func testMalformedCheckpointSurvivesNewCaptureUpdatesAndRetirement() throws {
        try withIsolatedCheckpoints {
            let defaults = UserDefaults.standard
            let original = Data("{incomplete synthetic checkpoint".utf8)
            defaults.set(original, forKey: key)
            XCTAssertTrue(CaptureDraftStore.hasUnreadableCheckpoints)
            let draft = CaptureDraftStore.begin(source: .inAppText)
            CaptureDraftStore.update(id: draft.id, transcript: "Synthetic words retained")
            CaptureDraftStore.markFailed(id: draft.id, message: "Synthetic interruption")
            CaptureDraftStore.pruneEmptyTextDrafts()
            let reread = try XCTUnwrap(CaptureDraftStore.draft(id: draft.id))
            XCTAssertEqual(reread.transcript, "Synthetic words retained")
            XCTAssertEqual(reread.recoveryStatus, .failed)
            XCTAssertEqual(CaptureDraftStore.snapshot().map(\.id), [draft.id])
            XCTAssertEqual(defaults.data(forKey: key), original)
            CaptureDraftStore.clear(id: draft.id)
            XCTAssertTrue(CaptureDraftStore.snapshot().isEmpty)
            XCTAssertTrue(CaptureDraftStore.hasUnreadableCheckpoints)
            XCTAssertEqual(defaults.data(forKey: key), original, "Retiring a known draft cannot discard failed reads")
            let later = CaptureDraftStore.begin(source: .inAppText)
            XCTAssertEqual(CaptureDraftStore.snapshot().map(\.id), [later.id])
            XCTAssertEqual(defaults.data(forKey: key), original)
        }
    }

    func testWrongTypedAndMultipleUnreadableSlotsStayUntouched() {
        withIsolatedCheckpoints {
            let defaults = UserDefaults.standard
            defaults.set("synthetic wrong value type", forKey: key)
            let brokenKey = prefix + "synthetic-broken"
            let bytes = Data("{broken second slot".utf8)
            defaults.set(bytes, forKey: brokenKey)
            let draft = CaptureDraftStore.begin(source: .inAppText)
            CaptureDraftStore.update(id: draft.id, transcript: "New synthetic draft")
            XCTAssertEqual(CaptureDraftStore.snapshot().map(\.id), [draft.id])
            XCTAssertTrue(CaptureDraftStore.hasUnreadableCheckpoints)
            XCTAssertEqual(defaults.string(forKey: key), "synthetic wrong value type")
            XCTAssertEqual(defaults.data(forKey: brokenKey), bytes)
        }
    }

    func testHealthyMirroredSlotsDoNotResurrectARetiredDraft() throws {
        try withIsolatedCheckpoints {
            let defaults = UserDefaults.standard
            let first = CaptureDraftStore.begin(source: .inAppText)
            CaptureDraftStore.update(id: first.id, transcript: "First synthetic draft")
            let mirror = prefix + "synthetic-mirror"
            defaults.set(try XCTUnwrap(defaults.data(forKey: key)), forKey: mirror)
            let second = CaptureDraftStore.begin(source: .inAppText)
            CaptureDraftStore.update(id: second.id, transcript: "Second synthetic draft")
            CaptureDraftStore.clear(id: first.id)
            XCTAssertEqual(CaptureDraftStore.snapshot().map(\.id), [second.id])
            XCTAssertEqual(defaults.data(forKey: key), defaults.data(forKey: mirror))
            XCTAssertFalse(CaptureDraftStore.hasUnreadableCheckpoints)
        }
    }

    func testUnreadableCheckpointKeepsDeletionTombstonesUntilReadable() {
        withIsolatedCheckpoints {
            let defaults = UserDefaults.standard
            let bytes = Data("{unreadable synthetic checkpoint".utf8)
            defaults.set(bytes, forKey: key)
            XCTAssertTrue(CaptureDraftStore.deleteRecording(id: UUID()))
            let future = Date.now.addingTimeInterval(40 * 24 * 60 * 60)
            CaptureDraftStore.pruneResolvedTombstones(now: future)
            XCTAssertEqual(CaptureDraftStore.tombstoneCount(), 1)
            XCTAssertEqual(defaults.data(forKey: key), bytes)
            defaults.set(Data("[]".utf8), forKey: key)
            CaptureDraftStore.pruneResolvedTombstones(now: future)
            XCTAssertEqual(CaptureDraftStore.tombstoneCount(), 0)
        }
    }
}


/// Controlled entitlement snapshots only: no StoreKit session or purchase.
@MainActor
final class SubscriptionEntitlementRefreshTests: XCTestCase {
    @MainActor
    private final class ControlledReader {
        var onRead: (Int) -> Void = { _ in }
        private var nextID = 0
        private var pending: [Int: CheckedContinuation<Set<String>, Never>] = [:]

        func read() async -> Set<String> {
            let id = nextID
            nextID += 1
            return await withCheckedContinuation { continuation in
                pending[id] = continuation
                onRead(id)
            }
        }

        func complete(_ id: Int, with products: Set<String>) throws {
            let continuation = try XCTUnwrap(pending.removeValue(forKey: id))
            continuation.resume(returning: products)
        }

        func releasePending() {
            let remaining = Array(pending.values)
            pending.removeAll()
            for continuation in remaining { continuation.resume(returning: []) }
        }
    }

    func testOlderEntitlementRefreshCannotReplaceNewerAccessOrBackgroundCache() async throws {
        let cases: [(Set<String>, Set<String>)] = [
            ([SubscriptionStore.monthlyProductID], []),
            ([], [SubscriptionStore.lifetimeProductID])
        ]
        for (olderProducts, newerProducts) in cases {
            let suite = "SubscriptionEntitlementRefresh-" + UUID().uuidString
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let reader = ControlledReader()
            defer { reader.releasePending() }
            let olderStarted = expectation(description: "Older entitlement read started")
            let newerStarted = expectation(description: "Newer entitlement read started")
            reader.onRead = { id in
                if id == 0 { olderStarted.fulfill() }
                if id == 1 { newerStarted.fulfill() }
            }
            let store = SubscriptionStore(defaultsForTesting: defaults,
                entitlementReaderForTesting: { await reader.read() })
            let older = Task { await store.refreshEntitlements() }
            await fulfillment(of: [olderStarted], timeout: 5)
            let newer = Task { await store.refreshEntitlements() }
            await fulfillment(of: [newerStarted], timeout: 5)
            try reader.complete(1, with: newerProducts)
            await newer.value
            let expectedAccess: SubscriptionStore.AccessLevel = newerProducts.isEmpty ? .free : .pro
            XCTAssertEqual(store.accessLevel, expectedAccess)
            XCTAssertEqual(store.activeProProductIDs, newerProducts)
            XCTAssertEqual(SubscriptionStore.backgroundCapturePolicy(source: .inAppText, defaults: defaults),
                           newerProducts.isEmpty ? .free : .pro)

            // Complete the older read last, in either Pro/free direction.
            try reader.complete(0, with: olderProducts)
            await older.value
            XCTAssertEqual(store.accessLevel, expectedAccess)
            XCTAssertEqual(store.activeProProductIDs, newerProducts)
            XCTAssertEqual(SubscriptionStore.backgroundCapturePolicy(source: .inAppText, defaults: defaults),
                           newerProducts.isEmpty ? .free : .pro)
        }
    }

    func testCancelledNewerEntitlementRefreshDoesNotInvalidateOlderValidRead() async throws {
        let cases: [(Set<String>, Set<String>)] = [
            ([SubscriptionStore.monthlyProductID], []),
            ([], [SubscriptionStore.lifetimeProductID])
        ]
        for (olderProducts, cancelledProducts) in cases {
            let suite = "SubscriptionEntitlementCancelledNewer-" + UUID().uuidString
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            // Begin with the opposite cached state so the older read must
            // actually publish, rather than merely preserve an initial value.
            defaults.set(olderProducts.isEmpty, forKey: "SpeakIt.cachedProAccess")
            let reader = ControlledReader()
            defer { reader.releasePending() }
            let olderStarted = expectation(description: "Older valid entitlement read started")
            let newerStarted = expectation(description: "Newer cancelled entitlement read started")
            reader.onRead = { id in
                if id == 0 { olderStarted.fulfill() }
                if id == 1 { newerStarted.fulfill() }
            }
            let store = SubscriptionStore(defaultsForTesting: defaults,
                entitlementReaderForTesting: { await reader.read() })
            let initialAccess = store.accessLevel
            let older = Task { await store.refreshEntitlements() }
            await fulfillment(of: [olderStarted], timeout: 5)
            let newer = Task { await store.refreshEntitlements() }
            await fulfillment(of: [newerStarted], timeout: 5)
            newer.cancel()
            try reader.complete(1, with: cancelledProducts)
            await newer.value
            XCTAssertEqual(store.accessLevel, initialAccess)
            XCTAssertTrue(store.activeProProductIDs.isEmpty)

            try reader.complete(0, with: olderProducts)
            await older.value
            XCTAssertEqual(store.accessLevel, olderProducts.isEmpty ? .free : .pro)
            XCTAssertEqual(store.activeProProductIDs, olderProducts)
            XCTAssertEqual(SubscriptionStore.backgroundCapturePolicy(source: .inAppText, defaults: defaults),
                           olderProducts.isEmpty ? .free : .pro)
        }
    }

    func testCancelledEntitlementRefreshKeepsLastVerifiedAccessAndBackgroundCache() async throws {
        let suite = "SubscriptionEntitlementCancellation-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let reader = ControlledReader()
        defer { reader.releasePending() }
        let initialStarted = expectation(description: "Verified entitlement read started")
        let cancelledStarted = expectation(description: "Cancelled entitlement read started")
        reader.onRead = { id in
            if id == 0 { initialStarted.fulfill() }
            if id == 1 { cancelledStarted.fulfill() }
        }
        let store = SubscriptionStore(defaultsForTesting: defaults,
            entitlementReaderForTesting: { await reader.read() })
        let initial = Task { await store.refreshEntitlements() }
        await fulfillment(of: [initialStarted], timeout: 5)
        try reader.complete(0, with: [SubscriptionStore.lifetimeProductID])
        await initial.value
        XCTAssertTrue(store.hasLifetimeProAccess)
        let cancelled = Task { await store.refreshEntitlements() }
        await fulfillment(of: [cancelledStarted], timeout: 5)
        cancelled.cancel()
        // A dependency can finish after cancellation; it still cannot publish.
        try reader.complete(1, with: [])
        await cancelled.value
        XCTAssertTrue(store.hasLifetimeProAccess)
        XCTAssertEqual(store.accessLevel, .pro)
        XCTAssertEqual(store.activeProProductIDs, [SubscriptionStore.lifetimeProductID])
        XCTAssertEqual(SubscriptionStore.backgroundCapturePolicy(source: .inAppText, defaults: defaults), .pro)
    }
}

@MainActor
final class ProductMidnightDeadlineConsumerTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "America/Toronto")!
        return value
    }

    private func date(_ day: Int, _ hour: Int = 0, calendar: Calendar? = nil) throws -> Date {
        try XCTUnwrap((calendar ?? self.calendar).date(from:
            DateComponents(year: 2026, month: 11, day: day, hour: hour)))
    }

    private func intent(zone: String = "America/Toronto") -> TemporalIntent {
        TemporalIntent(kind: .exactDateTime, day: CalendarDay(year: 2026, month: 11, day: 18),
            time: WallClockTime(hour: 0, minute: 0), timeZoneIdentifier: zone,
            timeZoneBehavior: .fixed, sourceText: "Submit the report by Wednesday at midnight.",
            deadlineBoundary: .endOfNamedDay)
    }

    private func container() throws -> ModelContainer {
        try ModelContainer(for: PersistenceController.schema, migrationPlan: SpeakItMigrationPlan.self,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)])
    }

    func testLegacyBackfillNeverAdoptsNewEndOfDayBoundary() throws {
        let oldZone = NSTimeZone.default
        NSTimeZone.default = calendar.timeZone
        defer { NSTimeZone.default = oldZone }
        let source = "Submit the report by Wednesday at midnight."
        let anchor = try date(16, 9)
        XCTAssertEqual(ThoughtOrganizer.organize(source, referenceDate: anchor, calendar: calendar)
            .temporalIntent.deadlineBoundary, .endOfNamedDay,
            "The fixture must exercise a newly recognized deadline, not an unrelated fallback")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("legacy-midnight-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let configuration = ModelConfiguration(schema: PersistenceController.schema,
            url: directory.appendingPathComponent("capture.store"), cloudKitDatabase: .none)
        var expected: [UUID: Date] = [:]
        var oldIntentID = UUID()
        var oldIntentData: Data?
        do {
            let disk = try ModelContainer(for: PersistenceController.schema,
                migrationPlan: SpeakItMigrationPlan.self, configurations: [configuration])
            for day in [18, 19] {
                let session = CaptureSession(originalTranscription: source, createdAt: anchor,
                    captureSource: .inAppText, processingStatus: .complete)
                let item = CapturedItem(originalTextSegment: source, displayTitle: "Submit the report",
                    itemType: .task, createdAt: anchor, dueDate: try date(day),
                    semanticState: .resolved, captureSession: session)
                disk.mainContext.insert(session); disk.mainContext.insert(item)
                expected[item.id] = item.dueDate
            }
            let existing = CapturedItem(originalTextSegment: source, displayTitle: "Submit the report",
                itemType: .task, createdAt: anchor, dueDate: try date(18),
                temporalIntent: TemporalIntent(kind: .exactDateTime,
                    day: CalendarDay(year: 2026, month: 11, day: 18),
                    time: WallClockTime(hour: 0, minute: 0), sourceText: source), semanticState: .resolved)
            disk.mainContext.insert(existing)
            oldIntentID = existing.id; oldIntentData = existing.temporalIntentData
            expected[existing.id] = existing.dueDate
            try disk.mainContext.save()
        }
        let disk = try ModelContainer(for: PersistenceController.schema,
            migrationPlan: SpeakItMigrationPlan.self, configurations: [configuration])
        let context = ModelContext(disk)
        let repository = SwiftDataThoughtRepository(modelContext: context,
            requestsReminderAuthorization: false, permitsOnDeviceIntelligence: false)
        for _ in 0..<2 {
            repository.recoverUnorganizedCaptures()
            let items = try context.fetch(FetchDescriptor<CapturedItem>())
            XCTAssertEqual(items.count, 3)
            for item in items {
                XCTAssertEqual(item.dueDate, expected[item.id])
                XCTAssertNil(item.reminderDate)
                XCTAssertNil(item.temporalIntent?.deadlineBoundary,
                    "Even a preexisting Thu00 endpoint is not evidence of new deadline authority")
                if item.id == oldIntentID { XCTAssertEqual(item.temporalIntentData, oldIntentData) }
                else {
                    XCTAssertEqual(item.temporalIntent?.day, item.dueDate.flatMap { CalendarDay(from: $0, calendar: calendar) })
                    XCTAssertEqual(item.temporalIntent?.time, WallClockTime(hour: 0, minute: 0))
                }
                XCTAssertEqual(item.originalTextSegment, source)
            }
        }
    }

    func testUnrelatedEditsPreserveBoundaryAndExplicitDateActionsClearIt() throws {
        let oldZone = NSTimeZone.default
        NSTimeZone.default = calendar.timeZone
        defer { NSTimeZone.default = oldZone }
        let disk = try container(), context = ModelContext(disk)
        let repository = SwiftDataThoughtRepository(modelContext: context,
            requestsReminderAuthorization: false, permitsOnDeviceIntelligence: false)
        let original = intent(), endpoint = try XCTUnwrap(original.endOfDayDeadlineDate(calendar: calendar))
        let item = CapturedItem(originalTextSegment: original.sourceText!, displayTitle: "Submit the report",
            itemType: .task, createdAt: try date(16, 9), dueDate: endpoint,
            temporalIntent: original, semanticState: .resolved)
        context.insert(item); try context.save()
        let originalData = item.temporalIntentData
        func edits(due: Date?, title: String = "Submit the finished report", person: String? = nil) -> ItemEdits {
            ItemEdits(title: title, itemType: .task, category: .general, dueDate: due,
                reminderDate: nil, priority: .normal, personName: person,
                needsClarification: false, dueDateHasTime: true)
        }
        try repository.update(item, with: edits(due: endpoint))
        XCTAssertEqual(item.temporalIntentData, originalData)
        try repository.update(item, with: edits(due: endpoint, person: "Amina"))
        XCTAssertEqual(item.temporalIntentData, originalData)
        try repository.update(item, with: edits(due: endpoint, person: "Amina"))
        XCTAssertEqual(item.temporalIntentData, originalData, "No-op saves retain exact encoded intent")
        let chosen = endpoint.addingTimeInterval(2 * 3_600)
        try repository.update(item, with: edits(due: chosen, person: "Amina"))
        XCTAssertEqual(item.dueDate, chosen)
        XCTAssertNil(item.temporalIntent?.deadlineBoundary)
        XCTAssertEqual(item.temporalIntent?.isUserEdited, true)
        // This fixture has no session: no notification request is constructed.
        item.dueDate = endpoint; item.reminderDate = nil; item.temporalIntent = original
        try context.save()
        try repository.performReminderAction(itemIDs: [item.id], action: .tomorrow)
        XCTAssertNotNil(item.reminderDate)
        XCTAssertEqual(item.dueDate, item.reminderDate)
        XCTAssertNil(item.temporalIntent?.deadlineBoundary)
        XCTAssertEqual(item.temporalIntent?.isUserEdited, true)
        XCTAssertEqual(item.temporalIntent?.sourceText, original.sourceText)
        XCTAssertEqual(item.originalTextSegment, original.sourceText)
    }

    func testSharedAndBriefConsumersKeepBoundaryTruthfulAndPrivate() throws {
        let oldZone = NSTimeZone.default
        NSTimeZone.default = calendar.timeZone
        defer { NSTimeZone.default = oldZone }
        let original = intent(), endpoint = try XCTUnwrap(original.endOfDayDeadlineDate(calendar: calendar))
        let row = CapturedItem(originalTextSegment: original.sourceText!, displayTitle: "Submit the report",
            itemType: .task, dueDate: endpoint, temporalIntent: original, semanticState: .resolved)
        let label = try XCTUnwrap(ItemPresentation.endOfDayDeadlineLabel(for: row,
            calendar: calendar, locale: Locale(identifier: "en_US")))
        let shared = SwiftDataThoughtRepository.sharedTodayItem(for: row, calendar: calendar,
            locale: Locale(identifier: "en_US"))
        XCTAssertEqual(shared.deadline?.day, 18)
        XCTAssertEqual(shared.deadline?.timeZoneIdentifier, "America/Toronto")
        XCTAssertEqual(shared.timingText(now: try date(18, 10), calendar: calendar), label)
        XCTAssertEqual(try JSONDecoder().decode(SharedTodayItem.self,
            from: JSONEncoder().encode(shared)), shared)
        let legacy = SharedTodayItem(id: UUID(), title: "Ordinary clock", dueDate: endpoint, isUrgent: false)
        let decodedLegacy = try JSONDecoder().decode(SharedTodayItem.self, from: JSONEncoder().encode(legacy))
        XCTAssertNil(decodedLegacy.deadline); XCTAssertNil(decodedLegacy.deadlineNeedsReview)
        XCTAssertEqual(decodedLegacy.timingText(now: try date(18, 10), calendar: calendar), "Tomorrow")
        var snapshot = SharedTodaySnapshot(generatedAt: try date(18, 10), openCount: 1, items: [shared])
        XCTAssertTrue(LockScreenTodayVisibility.summary(for: snapshot, titleLimit: 3,
            now: try date(18, 10), calendar: calendar).rows.isEmpty)
        snapshot.showsTaskNamesOnLockScreen = true
        let visible = LockScreenTodayVisibility.summary(for: snapshot, titleLimit: 3,
            now: try date(18, 10), calendar: calendar)
        XCTAssertEqual(visible.rows.first?.timeText, label)
        XCTAssertFalse(visible.accessibilityText.contains(" at By end"))
        XCTAssertEqual(CaptureSessionReviewView.savedDueDateSummary(dueDate: endpoint,
            temporalData: try JSONEncoder().encode(original), temporalKind: TemporalKind.exactDateTime.rawValue,
            calendar: calendar, locale: Locale(identifier: "en_US")), label)
        XCTAssertNil(ReminderScheduleRequest(item: row), "A due-only boundary does not create an alert")
        let authorization = LocationAuthorization(status: .denied, isPrecise: true, isRegionMonitoringAvailable: true)
        let projected = MorningBriefPlanner.projectedItems(from: [row], authorization: authorization, now: try date(17, 8))
        XCTAssertEqual(projected.count, 1)
        XCTAssertEqual(projected.first?.deadlineIntent, original)
        let plan = MorningBriefPlanner.plan(items: projected, now: try date(17, 8),
            time: WallClockTime(hour: 9, minute: 0), calendar: calendar,
            includesNames: true, locale: Locale(identifier: "en_US"))
        XCTAssertEqual(plan.count, 2)
        XCTAssertEqual(plan[0].dueToday, 1); XCTAssertEqual(plan[0].overdue, 0)
        XCTAssertEqual(plan[0].lead?.detail, label)
        XCTAssertEqual(plan[1].dueToday, 0); XCTAssertEqual(plan[1].overdue, 1)
        XCTAssertEqual(plan[1].lead?.detail, "overdue since yesterday")
        XCTAssertTrue(MorningBriefPlanner.plan(items: projected, now: try date(17, 8),
            time: WallClockTime(hour: 9, minute: 0), calendar: calendar).allSatisfy { $0.lead == nil })
        // Absolute London caption keeps source Wednesday; local bucket/age
        // use the last included calendar day, without shifting the endpoint.
        let london = intent(zone: "Europe/London")
        let londonEndpoint = try XCTUnwrap(london.endOfDayDeadlineDate(calendar: calendar))
        let brief = MorningBriefItem(dueDate: londonEndpoint, title: "Submit the report", deadlineIntent: london)
        XCTAssertEqual(TodayActionTiming.group(for: londonEndpoint, deadlineIntent: london,
            relativeTo: try date(17, 20), calendar: calendar), .comingUp)
        var tokyo = calendar; tokyo.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Tokyo"))
        XCTAssertEqual(TodayActionTiming.group(for: londonEndpoint, deadlineIntent: london,
            relativeTo: try date(19, 8, calendar: tokyo), calendar: tokyo), .today)
        XCTAssertEqual(MorningBriefPlanner.detail(for: brief, isOverdue: true,
            on: try date(20, 9, calendar: tokyo), calendar: tokyo), "overdue since yesterday")
        var deviceLocal = original
        deviceLocal.timeZoneBehavior = .deviceLocal
        let localRow = CapturedItem(originalTextSegment: original.sourceText!, displayTitle: "Submit the report",
            itemType: .task, dueDate: endpoint, temporalIntent: deviceLocal, semanticState: .resolved)
        let cached = SwiftDataThoughtRepository.sharedTodayItem(for: localRow, calendar: calendar,
            locale: Locale(identifier: "en_US"))
        XCTAssertEqual(cached.deadline?.followsDeviceLocal, true)
        var londonCalendar = calendar
        londonCalendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/London"))
        XCTAssertEqual(cached.timingText(now: try date(18, 10, calendar: londonCalendar),
            calendar: londonCalendar), "Deadline time needs review",
            "A cached Toronto device-local snapshot cannot claim unqualified London midnight")
        let cachedSnapshot = SharedTodaySnapshot(generatedAt: try date(18, 10), openCount: 1,
            items: [cached], showsTaskNamesOnLockScreen: true)
        XCTAssertEqual(LockScreenTodayVisibility.summary(for: cachedSnapshot, titleLimit: 3,
            now: try date(18, 10, calendar: londonCalendar), calendar: londonCalendar)
            .rows.first?.timeText, "Deadline time needs review")
        XCTAssertEqual(localRow.dueDate, endpoint, "Presentation validation cannot retime the task")
        let fixedRow = CapturedItem(originalTextSegment: london.sourceText!, displayTitle: "Submit the report",
            itemType: .task, dueDate: londonEndpoint, temporalIntent: london, semanticState: .resolved)
        let fixedCached = SwiftDataThoughtRepository.sharedTodayItem(for: fixedRow, calendar: calendar,
            locale: Locale(identifier: "en_US"))
        XCTAssertEqual(fixedCached.deadline?.followsDeviceLocal, false)
        let fixedLabel = try XCTUnwrap(ItemPresentation.endOfDayDeadlineLabel(for: fixedRow,
            calendar: calendar, locale: Locale(identifier: "en_US")))
        XCTAssertTrue(fixedLabel.contains("GMT"))
        XCTAssertEqual(fixedCached.timingText(now: try date(18, 10), calendar: calendar), fixedLabel)
        let missingBehavior = SharedTodayItem.Deadline(year: 2026, month: 11, day: 18,
            timeZoneIdentifier: "America/Toronto", summary: label)
        XCTAssertNil(missingBehavior.validatedSummary(for: endpoint, calendar: calendar))
        var unknownJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(missingBehavior)) as? [String: Any])
        unknownJSON["followsDeviceLocal"] = "future-behavior"
        let unknownBehavior = try JSONDecoder().decode(SharedTodayItem.Deadline.self,
            from: JSONSerialization.data(withJSONObject: unknownJSON))
        XCTAssertNil(unknownBehavior.followsDeviceLocal)
        XCTAssertNil(unknownBehavior.validatedSummary(for: endpoint, calendar: calendar))
        row.dueDate = endpoint.addingTimeInterval(3_600) // Same intent, unmatched stored endpoint.
        let mismatched = SwiftDataThoughtRepository.sharedTodayItem(for: row, calendar: calendar)
        XCTAssertEqual(mismatched.deadlineNeedsReview, true)
        XCTAssertEqual(mismatched.timingText(now: try date(18, 10), calendar: calendar), "Deadline time needs review")
        XCTAssertEqual(CaptureSessionReviewView.savedDueDateSummary(dueDate: row.dueDate,
            temporalData: row.temporalIntentData, temporalKind: row.temporalKindRawValue,
            calendar: calendar), "Deadline time needs review")
        XCTAssertEqual(TodayActionTiming.group(for: row, relativeTo: try date(18, 10), calendar: calendar), .noDate)
    }

    func testLossyBoundaryReschedulesHoldWhileExplicitClockAndOrdinaryMovesWork() throws {
        let oldZone = NSTimeZone.default
        NSTimeZone.default = calendar.timeZone
        defer { NSTimeZone.default = oldZone }
        for (boundary, timing, performed) in [(true, "Friday", false),
            (true, "back an hour", false), (true, "November 20 at 9 AM", true),
            (false, "Friday", true), (false, "back an hour", true)] {
            let disk = try container(), context = ModelContext(disk)
            let repository = SwiftDataThoughtRepository(modelContext: context,
                requestsReminderAuthorization: false, permitsOnDeviceIntelligence: false)
            let boundaryIntent = intent()
            let endpoint = try XCTUnwrap(boundaryIntent.endOfDayDeadlineDate(calendar: calendar))
            let savedSession = CaptureSession(originalTranscription: "Submit the report", createdAt: try date(16, 9),
                captureSource: .inAppText, processingStatus: .complete)
            let saved = CapturedItem(originalTextSegment: "Submit the report", displayTitle: "Submit the report",
                itemType: .task, dueDate: endpoint,
                temporalIntent: boundary ? boundaryIntent : TemporalIntent.userEdited(dueDate: endpoint,
                    reminderDate: nil, recurrence: nil, sourceText: "Submit the report", calendar: calendar),
                semanticState: .resolved, captureSession: savedSession)
            let source = "Move the report to " + timing
            let capture = CaptureSession(originalTranscription: source, createdAt: try date(16, 9),
                captureSource: .inAppText, processingStatus: .pending)
            let placeholder = CapturedItem(originalTextSegment: source, displayTitle: source,
                needsClarification: true, captureSession: capture)
            context.insert(savedSession); context.insert(saved); context.insert(capture); context.insert(placeholder)
            try context.save()
            let before = saved.temporalIntentData
            let request = CaptureOperationRequest(operation: .reschedule, polarity: .positive,
                target: "report", sourceQuote: source, needsReview: false, newTimingText: timing)
            let result = try repository.applyCaptureOperation(request, session: capture, schedulesReminders: false)
            let message = "boundary=\(boundary), timing=\(timing)"
            if performed {
                guard case let .performed(operation: .reschedule, itemID: movedID, _) = result else {
                    XCTFail("Expected exact supported move: " + message); continue
                }
                XCTAssertEqual(movedID, saved.id, message)
                XCTAssertNotEqual(saved.dueDate, endpoint, message)
                XCTAssertNil(saved.temporalIntent?.deadlineBoundary, message)
                XCTAssertEqual(saved.temporalIntent?.isUserEdited, true, message)
            } else {
                guard case .ambiguous(operation: .reschedule, _) = result else {
                    XCTFail("Expected review without tuple authority: " + message); continue
                }
                XCTAssertEqual(saved.dueDate, endpoint, message)
                XCTAssertEqual(saved.temporalIntentData, before, message)
            }
            XCTAssertNil(saved.reminderDate, message)
            XCTAssertEqual(saved.originalTextSegment, "Submit the report", message)
            XCTAssertEqual(savedSession.originalTranscription, "Submit the report", message)
        }
    }
}


@MainActor
final class ProductClockBoundaryPersistenceTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "America/Toronto")!
        return value
    }
    private func date(_ day: Int, _ hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour))!
    }
    private func configuration(_ suffix: String) throws -> (URL, ModelConfiguration) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(suffix + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return (directory, ModelConfiguration(schema: PersistenceController.schema,
            url: directory.appendingPathComponent("capture.store"), cloudKitDatabase: .none))
    }

    func testLegacyEncodedClockAndNilDataBackfillDoNotAdoptNewBoundaryOnReopen() throws {
        let source = "Call Mira on Wednesday after 6 PM."
        let (directory, configuration) = try configuration("legacy-clock-boundary-")
        defer { try? FileManager.default.removeItem(at: directory) }
        let legacyData = Data(#"{"kind":"exactDateTime","day":{"year":2026,"month":11,"day":18},"time":{"hour":18,"minute":0},"sourceText":"Call Mira on Wednesday after 6 PM."}"#.utf8)
        var encodedID = UUID(), nilID = UUID()
        do {
            let disk = try ModelContainer(for: PersistenceController.schema,
                migrationPlan: SpeakItMigrationPlan.self, configurations: [configuration])
            for encoded in [true, false] {
                let session = CaptureSession(originalTranscription: source, createdAt: date(16, 9),
                    captureSource: .inAppText, processingStatus: .complete)
                let item = CapturedItem(originalTextSegment: source, displayTitle: source,
                    itemType: .personFollowUp, createdAt: date(16, 9), dueDate: date(18, 18),
                    personName: "Mira", semanticState: .resolved, captureSession: session)
                if encoded {
                    item.temporalIntentData = legacyData; item.temporalKindRawValue = TemporalKind.exactDateTime.rawValue
                    encodedID = item.id
                } else { nilID = item.id }
                disk.mainContext.insert(session); disk.mainContext.insert(item)
            }
            try disk.mainContext.save()
        }
        let disk = try ModelContainer(for: PersistenceController.schema,
            migrationPlan: SpeakItMigrationPlan.self, configurations: [configuration])
        let context = ModelContext(disk)
        // Zone changes are confined to legacy parsing/backfill, with no UN assertions inside.
        let previous = NSTimeZone.default
        NSTimeZone.default = calendar.timeZone
        let repository: SwiftDataThoughtRepository
        do {
            defer { NSTimeZone.default = previous }
            XCTAssertEqual(ThoughtOrganizer.organize(source, referenceDate: date(16, 9), calendar: calendar)
                .temporalIntent.clockBoundary, .after, "The upgrade fixture must exercise new source authority")
            repository = SwiftDataThoughtRepository(modelContext: context,
                requestsReminderAuthorization: false, permitsOnDeviceIntelligence: false)
            repository.recoverUnorganizedCaptures(); repository.recoverUnorganizedCaptures()
        }
        let rows = try context.fetch(FetchDescriptor<CapturedItem>())
        XCTAssertEqual(Set(rows.map(\.id)), [encodedID, nilID])
        for item in rows {
            XCTAssertEqual(item.dueDate, date(18, 18)); XCTAssertNil(item.reminderDate)
            XCTAssertNil(item.temporalIntent?.clockBoundary)
            XCTAssertEqual(item.originalTextSegment, source)
            XCTAssertEqual(item.captureSession?.originalTranscription, source)
            if item.id == encodedID { XCTAssertEqual(item.temporalIntentData, legacyData) }
            else { XCTAssertEqual(item.temporalIntent?.time, WallClockTime(hour: 18, minute: 0)) }
        }
        _ = repository
    }

    func testClockBoundaryPersistsThroughReopenAndUnrelatedEditButExplicitClockEditClears() throws {
        let source = "Check the report on Wednesday after 6 PM."
        let intent = TemporalIntent(kind: .exactDateTime,
            day: CalendarDay(year: 2026, month: 11, day: 18), time: WallClockTime(hour: 18, minute: 0),
            timeZoneIdentifier: calendar.timeZone.identifier, timeZoneBehavior: .fixed,
            sourceText: source, clockBoundary: .after)
        let (directory, configuration) = try configuration("clock-boundary-")
        defer { try? FileManager.default.removeItem(at: directory) }
        var rowID = UUID(), sessionID = UUID()
        var encoded: Data?
        do {
            let disk = try ModelContainer(for: PersistenceController.schema,
                migrationPlan: SpeakItMigrationPlan.self, configurations: [configuration])
            let session = CaptureSession(originalTranscription: source, createdAt: date(16, 9),
                captureSource: .inAppText, processingStatus: .complete)
            let item = CapturedItem(originalTextSegment: source, displayTitle: source, itemType: .task,
                createdAt: date(16, 9), dueDate: date(18, 18), temporalIntent: intent,
                semanticState: .resolved, captureSession: session)
            rowID = item.id; sessionID = session.id; encoded = item.temporalIntentData
            disk.mainContext.insert(session); disk.mainContext.insert(item); try disk.mainContext.save()
        }
        let disk = try ModelContainer(for: PersistenceController.schema,
            migrationPlan: SpeakItMigrationPlan.self, configurations: [configuration])
        let context = ModelContext(disk)
        let repository = SwiftDataThoughtRepository(modelContext: context,
            requestsReminderAuthorization: false, permitsOnDeviceIntelligence: false)
        repository.recoverUnorganizedCaptures(); repository.recoverUnorganizedCaptures()
        let item = try XCTUnwrap(context.fetch(FetchDescriptor<CapturedItem>()).first)
        XCTAssertEqual(item.id, rowID); XCTAssertEqual(item.captureSession?.id, sessionID)
        XCTAssertEqual(item.temporalIntentData, encoded); XCTAssertEqual(item.originalTextSegment, source)
        XCTAssertEqual(item.captureSession?.originalTranscription, source); XCTAssertNil(item.reminderDate)
        func edits(_ due: Date) -> ItemEdits {
            ItemEdits(title: "Check the revised report", itemType: .task, category: .general,
                dueDate: due, reminderDate: nil, priority: .normal, personName: nil,
                needsClarification: false, dueDateHasTime: true)
        }
        try repository.update(item, with: edits(date(18, 18)))
        XCTAssertEqual(item.temporalIntentData, encoded, "Unrelated title changes preserve exact encoded relation")
        for action in [ReminderAction.snoozeTenMinutes, .tomorrow] {
            XCTAssertThrowsError(try repository.performReminderAction(itemIDs: [item.id], action: action))
            XCTAssertEqual(item.temporalIntentData, encoded)
            XCTAssertEqual(item.dueDate, date(18, 18)); XCTAssertNil(item.reminderDate)
        }
        try repository.update(item, with: edits(date(18, 19)))
        XCTAssertEqual(item.temporalIntent?.isUserEdited, true); XCTAssertNil(item.temporalIntent?.clockBoundary)
        XCTAssertEqual(item.dueDate, date(18, 19)); XCTAssertEqual(item.originalTextSegment, source)
        XCTAssertNil(item.reminderDate); XCTAssertNil(ReminderScheduleRequest(item: item))
        let reopened = ModelContext(disk)
        let final = try XCTUnwrap(reopened.fetch(FetchDescriptor<CapturedItem>()).first)
        XCTAssertEqual(final.id, rowID); XCTAssertEqual(final.temporalIntent?.isUserEdited, true)
        XCTAssertNil(final.temporalIntent?.clockBoundary); XCTAssertEqual(final.dueDate, date(18, 19))
    }


    func testClockBoundarySavedMovesRejectConflictingOldClockAndLossyConfirmedDay() throws {
        let previous = NSTimeZone.default
        NSTimeZone.default = calendar.timeZone
        defer { NSTimeZone.default = previous }
        let original = "Check the report on Wednesday after 6 PM."
        let bound = TemporalIntent(kind: .exactDateTime,
            day: CalendarDay(year: 2026, month: 11, day: 18), time: WallClockTime(hour: 18, minute: 0),
            timeZoneIdentifier: calendar.timeZone.identifier, timeZoneBehavior: .fixed,
            sourceText: original, clockBoundary: .after)
        for (old, performed) in [("Wednesday after 5 PM", false), ("Wednesday before 6 PM", false),
                                  ("Wednesday at 5 PM", false), ("Wednesday at 6 PM", false),
                                  ("Wednesday after 6 PM", true), ("Wednesday", true)] {
            let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
            let store = try ModelContainer(for: PersistenceController.schema,
                migrationPlan: SpeakItMigrationPlan.self, configurations: [configuration])
            let context = store.mainContext
            let repository = SwiftDataThoughtRepository(modelContext: context,
                requestsReminderAuthorization: false, permitsOnDeviceIntelligence: false)
            let savedSession = CaptureSession(originalTranscription: original, createdAt: date(16, 8),
                captureSource: .inAppText, processingStatus: .complete)
            let saved = CapturedItem(originalTextSegment: original, displayTitle: "Check the report",
                itemType: .task, createdAt: date(16, 8), dueDate: date(18, 18), temporalIntent: bound,
                semanticState: .resolved, captureSession: savedSession)
            let source = "Change the saved Check the report from \(old) to November 20 at 9 AM."
            let capture = CaptureSession(originalTranscription: source, createdAt: date(16, 9),
                captureSource: .inAppText, processingStatus: .pending)
            let placeholder = CapturedItem(originalTextSegment: source, displayTitle: source,
                needsClarification: true, captureSession: capture)
            context.insert(savedSession); context.insert(saved); context.insert(capture); context.insert(placeholder)
            try context.save()
            let data = saved.temporalIntentData
            let request = CaptureOperationRequest(operation: .reschedule, polarity: .positive,
                target: "report", sourceQuote: source, needsReview: false,
                newTimingText: "November 20 at 9 AM", expectedOldTimingText: old)
            let outcome = try repository.applyCaptureOperation(request, session: capture, schedulesReminders: false)
            if performed {
                guard case let .performed(operation: .reschedule, itemID: movedID, _) = outcome else {
                    XCTFail("Supported exact move held: \(old)"); continue
                }
                XCTAssertEqual(movedID, saved.id, old)
                XCTAssertEqual(saved.dueDate, date(20, 9), old)
                XCTAssertNil(saved.temporalIntent?.clockBoundary, old)
                XCTAssertEqual(saved.temporalIntent?.isUserEdited, true, old)
            } else {
                guard case .ambiguous(operation: .reschedule, _) = outcome else {
                    XCTFail("Conflicting old clock/relation changed a saved bound: \(old)"); continue
                }
                XCTAssertEqual(saved.dueDate, date(18, 18), old)
                XCTAssertEqual(saved.temporalIntentData, data, old)
            }
            XCTAssertNil(saved.reminderDate, old); XCTAssertEqual(saved.originalTextSegment, original, old)
            XCTAssertEqual(savedSession.originalTranscription, original, old)
        }
        // Real pending-choice path: a day-only confirmation cannot inherit the
        // lower-bound clock, while a complete explicit AT replacement can.
        for (timing, performed) in [("Friday", false), ("November 20 at 9 AM", true)] {
            let store = try ModelContainer(for: PersistenceController.schema,
                migrationPlan: SpeakItMigrationPlan.self,
                configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
            let context = store.mainContext
            let repository = SwiftDataThoughtRepository(modelContext: context,
                requestsReminderAuthorization: false, permitsOnDeviceIntelligence: false)
            let parent = CaptureSession(originalTranscription: original, createdAt: date(16, 8),
                captureSource: .inAppText, processingStatus: .complete)
            let saved = CapturedItem(originalTextSegment: original, displayTitle: "Check the report",
                itemType: .task, createdAt: date(16, 8), dueDate: date(18, 18), temporalIntent: bound,
                semanticState: .resolved, captureSession: parent)
            let source = "Move my saved task Check the report to \(timing)."
            let capture = CaptureSession(originalTranscription: source, createdAt: date(16, 9),
                captureSource: .inAppText, processingStatus: .pending)
            let placeholder = CapturedItem(originalTextSegment: source, displayTitle: source,
                needsClarification: true, captureSession: capture)
            context.insert(parent); context.insert(saved); context.insert(capture); context.insert(placeholder)
            try context.save()
            let data = saved.temporalIntentData
            let snapshot = try XCTUnwrap(repository.atomicSnapshot(saved))
            let pending = try XCTUnwrap(SavedRevisionIntent.read(source, captureSource: source,
                snapshots: [snapshot], referenceDate: capture.createdAt, calendar: calendar))
            var request = CaptureOperationRequest(operation: .revise, polarity: .positive,
                target: "report", sourceQuote: source, needsReview: false)
            request.savedRevisionIntent = pending
            _ = try repository.applyCaptureOperation(request, session: capture, schedulesReminders: false)
            if performed {
                try repository.choosePendingCaptureOperation(placeholder, targetID: saved.id)
                XCTAssertEqual(saved.dueDate, date(20, 9))
                XCTAssertNil(saved.temporalIntent?.clockBoundary)
                XCTAssertEqual(saved.temporalIntent?.isUserEdited, true)
            } else {
                XCTAssertThrowsError(try repository.choosePendingCaptureOperation(placeholder, targetID: saved.id))
                XCTAssertEqual(saved.dueDate, date(18, 18)); XCTAssertEqual(saved.temporalIntentData, data)
            }
            XCTAssertNil(saved.reminderDate)
            XCTAssertEqual(saved.originalTextSegment, original); XCTAssertEqual(parent.originalTranscription, original)
        }
    }
}
