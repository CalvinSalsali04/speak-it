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
    func testShortcutOperationsKeepAllowanceAndOrdinaryCaptureSpendsIt() async throws {
        let suite = "SpeakItProductReadiness-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let previousLedger = FreeCaptureLedger.storedCount()
        FreeCaptureLedger.reset()
        defer {
            defaults.removePersistentDomain(forName: suite)
            FreeCaptureLedger.reset()
            if let previousLedger { FreeCaptureLedger.persist(previousLedger) }
        }
        defaults.set(DeveloperAccessOverride.free.rawValue, forKey: DeveloperAccessOverride.storageKey)
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: PersistenceController.schema,
            migrationPlan: SpeakItMigrationPlan.self, configurations: [configuration])
        let repository = SwiftDataThoughtRepository(modelContext: container.mainContext,
                                                    requestsReminderAuthorization: false)
        _ = try await repository.createCaptureResult(text: "Remind me about the dentist on Friday",
            source: .inAppText, createdAt: .now, schedulesReminders: false)
        for (source, confirmation) in [
            ("Cancel the dentist reminder", "Cancelled"),
            ("Actually never mind", "Discarded"),
            ("Cancel the plumber reminder", "Couldn't find that")
        ] {
            let result = try await ExternalCaptureWriter.save(source, repository: repository, defaults: defaults)
            XCTAssertTrue(result.confirmationContext.hasPrefix(confirmation), source)
            XCTAssertFalse(result.needsInterpretationConfirmation, source)
            XCTAssertEqual(defaults.integer(forKey: "SpeakIt.freeCapturesUsed"), 0, source)
        }
        _ = try await ExternalCaptureWriter.save("Buy toothpaste", repository: repository, defaults: defaults)
        XCTAssertEqual(defaults.integer(forKey: "SpeakIt.freeCapturesUsed"), 1)
        _ = try await ExternalCaptureWriter.save("Buy toothpaste", repository: repository, defaults: defaults)
        XCTAssertEqual(defaults.integer(forKey: "SpeakIt.freeCapturesUsed"), 1, "Duplicate delivery must not spend twice")
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
