import Foundation
import Security
import StoreKit

/// Ten free captures is a per-person allowance, so the count has to outlive a
/// delete-and-reinstall. `UserDefaults` does not survive one; a Keychain item
/// does. Both are written and the higher of the two always wins, so the number
/// can only ever move upward — reinstalling, restoring a backup, or clearing
/// the defaults domain cannot mint a fresh allowance.
///
/// Keychain failures are never fatal. If the item cannot be read or written the
/// allowance simply falls back to `UserDefaults`, which is the behavior that
/// shipped before, rather than blocking capture.
enum FreeCaptureLedger {
    private static let service = "com.calvinwak.SpeakIt.freeCaptures"
    private static let account = "lifetimeCaptureCount"

    static func storedCount() -> Int? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let text = String(data: data, encoding: .utf8),
              let count = Int(text) else {
            return nil
        }
        return count
    }

    static func persist(_ count: Int) {
        guard let data = String(count).data(using: .utf8) else { return }

        let status = SecItemUpdate(
            baseQuery as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        guard status == errSecItemNotFound else { return }

        var insert = baseQuery
        insert[kSecValueData as String] = data
        // Readable after the first unlock so a capture arriving from a
        // Shortcut on a locked device can still be counted.
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(insert as CFDictionary, nil)
    }

#if DEBUG
    static func reset() {
        SecItemDelete(baseQuery as CFDictionary)
    }
#endif

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}

/// Ten free captures, once — not ten a month. The free allowance is a trial of
/// the whole product rather than a recurring ration, so a person decides
/// whether Speak It is worth paying for instead of waiting out a reset.
enum FreePlanAllowance {
    static let lifetimeCaptureLimit = 10

    struct Usage: Equatable {
        let captureCount: Int
        /// When this person's free allowance began. Kept for display and for
        /// continuity with installs created under the earlier monthly plan; it
        /// no longer causes the count to reset.
        let startedAt: Date
    }

    /// Clamps stored values without ever handing captures back. An install that
    /// upgraded from the monthly plan keeps the captures it already used, and a
    /// clock moved backwards cannot mint a fresh allowance.
    static func normalizedUsage(
        captureCount: Int,
        startedAt: Date,
        now: Date = .now
    ) -> Usage {
        Usage(
            captureCount: min(max(0, captureCount), lifetimeCaptureLimit),
            startedAt: min(startedAt, now)
        )
    }

    static func remainingCaptures(after captureCount: Int) -> Int {
        max(0, lifetimeCaptureLimit - max(0, captureCount))
    }
}

enum CaptureAccessError: LocalizedError {
    case freeLimitReached

    var errorDescription: String? {
        "You’ve used all \(FreePlanAllowance.lifetimeCaptureLimit) free captures. Open Speak It to upgrade to Pro for unlimited capture."
    }
}

@MainActor
final class SubscriptionStore: ObservableObject {
    enum AccessLevel: Equatable {
        case checking
        case free
        case pro
    }

    static let monthlyProductID = "com.calvinwak.SpeakIt.pro.monthly"
    static let annualProductID = "com.calvinwak.SpeakIt.pro.annual"
    /// A non-consumable used only for Apple-issued creator/complimentary offer
    /// codes. It is deliberately excluded from `productIDs`, so Speak It never
    /// merchandises a lifetime plan in the paywall or starts this purchase
    /// directly. A verified App Store transaction is the only way it unlocks.
    static let lifetimeProductID = "com.calvinwak.SpeakIt.pro.lifetime"
    static let productIDs = [annualProductID, monthlyProductID]
    private static let entitlementProductIDs = Set(productIDs + [lifetimeProductID])

    @Published private(set) var products: [Product] = []
    @Published private(set) var accessLevel: AccessLevel = .checking
    @Published private(set) var activeProProductIDs: Set<String> = []
    @Published private(set) var isLoadingProducts = false
    @Published private(set) var isPurchasing = false
    @Published private(set) var isRestoring = false
    @Published private(set) var freeCapturesUsed: Int
    @Published private(set) var freeAllowanceStartedAt: Date
    @Published var customerMessage: String?
#if DEBUG
    @Published private(set) var developerAccessOverride: DeveloperAccessOverride
    @Published private(set) var isDeveloperCustomerJourneyActive: Bool
#endif

    private var updatesTask: Task<Void, Never>?
    private var hasPrepared = false

    private static let freeCapturesUsedKey = "SpeakIt.freeCapturesUsed"
    /// Storage key predates the move to a lifetime allowance. It is left
    /// unchanged so existing installs keep the captures they have already used.
    private static let freeAllowanceStartedAtKey = "SpeakIt.freePeriodStartedAt"
    private static let cachedProAccessKey = "SpeakIt.cachedProAccess"
#if DEBUG
    private static let developerJourneyKey = "SpeakIt.developerCustomerJourneyActive"
#endif

    init() {
        let defaults = UserDefaults.standard
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing-reset") {
            defaults.removeObject(forKey: Self.freeCapturesUsedKey)
            defaults.removeObject(forKey: Self.freeAllowanceStartedAtKey)
            defaults.removeObject(forKey: Self.cachedProAccessKey)
            defaults.removeObject(forKey: DeveloperAccessOverride.storageKey)
            defaults.removeObject(forKey: Self.developerJourneyKey)
            // The Keychain deliberately survives reinstalls, so a UI test run
            // has to clear it explicitly or the allowance carries over.
            FreeCaptureLedger.reset()
        }
        if ProcessInfo.processInfo.arguments.contains("--ui-testing-pro-preview") {
            defaults.set(DeveloperAccessOverride.free.rawValue, forKey: DeveloperAccessOverride.storageKey)
            defaults.set(true, forKey: Self.developerJourneyKey)
        }
#endif
        let storedStart = defaults.object(forKey: Self.freeAllowanceStartedAtKey) as? Date ?? .now
        let normalizedUsage = FreePlanAllowance.normalizedUsage(
            captureCount: Self.storedCaptureCount(defaults: defaults),
            startedAt: storedStart
        )
        freeCapturesUsed = normalizedUsage.captureCount
        freeAllowanceStartedAt = normalizedUsage.startedAt
#if DEBUG
        developerAccessOverride = DeveloperAccessOverride(
            rawValue: defaults.string(forKey: DeveloperAccessOverride.storageKey) ?? ""
        ) ?? .appStore
        isDeveloperCustomerJourneyActive = defaults.bool(forKey: Self.developerJourneyKey)
#endif
        Self.persistFreeUsage(normalizedUsage, defaults: defaults)
        updatesTask = observeTransactionUpdates()
        Task { await refreshEntitlements() }
    }

    deinit {
        updatesTask?.cancel()
    }

    var hasProAccess: Bool {
#if DEBUG
        switch developerAccessOverride {
        case .appStore:
            break
        case .free:
            return false
        case .pro:
            return true
        }
#endif
        return accessLevel == .pro
    }

    var hasLifetimeProAccess: Bool {
        activeProProductIDs.contains(Self.lifetimeProductID)
    }

    var hasActiveSubscription: Bool {
        !activeProProductIDs.isDisjoint(with: Self.productIDs)
    }

    var freeCapturesRemaining: Int {
        hasProAccess
            ? FreePlanAllowance.lifetimeCaptureLimit
            : FreePlanAllowance.remainingCaptures(after: freeCapturesUsed)
    }

    var canCreateCapture: Bool {
        hasProAccess || freeCapturesRemaining > 0
    }

    /// Re-reads what another process (the Siri intent, the share extension) may
    /// have recorded since this store was last read. The free allowance never
    /// renews, so this only ever moves the count forward.
    func refreshFreeAllowance(now: Date = .now) {
        let stored = Self.normalizedStoredUsage(defaults: .standard, now: now)
        let usage = FreePlanAllowance.normalizedUsage(
            captureCount: max(stored.captureCount, freeCapturesUsed),
            startedAt: min(stored.startedAt, freeAllowanceStartedAt),
            now: now
        )
        guard usage.captureCount != freeCapturesUsed || usage.startedAt != freeAllowanceStartedAt else {
            return
        }
        freeCapturesUsed = usage.captureCount
        freeAllowanceStartedAt = usage.startedAt
        Self.persistFreeUsage(usage)
    }

    func recordSuccessfulCapture(now: Date = .now) {
        refreshFreeAllowance(now: now)
        guard !hasProAccess else { return }
        freeCapturesUsed = min(
            FreePlanAllowance.lifetimeCaptureLimit,
            freeCapturesUsed + 1
        )
        Self.persistFreeUsage(
            .init(captureCount: freeCapturesUsed, startedAt: freeAllowanceStartedAt)
        )
    }

#if DEBUG
    func setDeveloperAccessOverride(_ override: DeveloperAccessOverride) {
        developerAccessOverride = override
        UserDefaults.standard.set(override.rawValue, forKey: DeveloperAccessOverride.storageKey)
    }

    func startDeveloperCustomerJourney() {
        isDeveloperCustomerJourneyActive = true
        UserDefaults.standard.set(true, forKey: Self.developerJourneyKey)
        setDeveloperAccessOverride(.free)
        setDeveloperFreeCapturesUsed(0)
        customerMessage = nil
    }

    func setDeveloperFreeCapturesUsed(_ captureCount: Int) {
        freeCapturesUsed = min(max(0, captureCount), FreePlanAllowance.lifetimeCaptureLimit)
        freeAllowanceStartedAt = .now
        Self.persistFreeUsage(
            .init(captureCount: freeCapturesUsed, startedAt: freeAllowanceStartedAt),
            allowingDecrease: true
        )
    }

    func completeDeveloperPurchase() {
        setDeveloperAccessOverride(.pro)
        customerMessage = "Test purchase complete. You now see the same Pro state a subscribed customer sees. No charge or App Store receipt was created."
    }

    func endDeveloperCustomerJourney() {
        isDeveloperCustomerJourneyActive = false
        UserDefaults.standard.set(false, forKey: Self.developerJourneyKey)
        setDeveloperAccessOverride(.appStore)
        customerMessage = nil
    }
#endif

    var hasAvailablePlans: Bool {
#if DEBUG
        !products.isEmpty || isDeveloperCustomerJourneyActive
#else
        !products.isEmpty
#endif
    }

    var annualProduct: Product? {
        products.first { $0.id == Self.annualProductID }
    }

    var monthlyProduct: Product? {
        products.first { $0.id == Self.monthlyProductID }
    }

    var recommendedProduct: Product? {
        annualProduct ?? monthlyProduct
    }

    func prepare() async {
        guard !hasPrepared else { return }
        hasPrepared = true
        await refreshEntitlements()
        await loadProducts()
    }

    func loadProducts(force: Bool = false) async {
        guard force || products.isEmpty else { return }
        guard !isLoadingProducts else { return }

        isLoadingProducts = true
        defer { isLoadingProducts = false }

        do {
            let loaded = try await Product.products(for: Self.productIDs)
            products = loaded.sorted { lhs, rhs in
                Self.productRank(lhs.id) < Self.productRank(rhs.id)
            }
        } catch {
            // A development build can run before the matching products exist
            // in App Store Connect. Keep the free app fully usable and allow a
            // manual retry from the Pro screen instead of showing a launch error.
            products = []
        }
    }

    @discardableResult
    func purchase(_ product: Product) async -> Bool {
        guard Self.productIDs.contains(product.id), !isPurchasing else { return false }
        let analyticsPlan = Self.analyticsPlan(for: product.id)
        SpeakItAnalytics.track(.purchaseStarted(analyticsPlan))
        isPurchasing = true
        defer { isPurchasing = false }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try verified(verification)
                await transaction.finish()
                await refreshEntitlements()
                customerMessage = hasProAccess
                    ? "Speak It Pro is ready. Thank you for supporting the app."
                    : "Your purchase completed, but access is still updating. Try Restore Purchases if it does not appear shortly."
                SpeakItAnalytics.track(.purchaseCompleted(analyticsPlan))
                return hasProAccess

            case .pending:
                SpeakItAnalytics.track(.purchasePending(analyticsPlan))
                customerMessage = "The purchase is pending approval. Speak It will unlock Pro automatically when Apple completes it."
                return false

            case .userCancelled:
                SpeakItAnalytics.track(.purchaseCancelled(analyticsPlan))
                return false

            @unknown default:
                SpeakItAnalytics.track(.purchaseFailed(analyticsPlan))
                customerMessage = "The App Store returned an unfamiliar purchase state. No charge was confirmed."
                return false
            }
        } catch {
            SpeakItAnalytics.track(.purchaseFailed(analyticsPlan))
            customerMessage = "The purchase couldn’t be completed. \(error.localizedDescription)"
            return false
        }
    }

    func restorePurchases() async {
        guard !isRestoring else { return }
        isRestoring = true
        defer { isRestoring = false }

        do {
            try await AppStore.sync()
            await refreshEntitlements()
            customerMessage = hasProAccess
                ? "Your Speak It Pro purchase has been restored."
                : "No active Speak It Pro subscription was found for this Apple Account."
            SpeakItAnalytics.track(.purchasesRestored(hasPro: hasProAccess))
        } catch {
            SpeakItAnalytics.track(.purchasesRestored(hasPro: false))
            customerMessage = "Purchases couldn’t be restored. \(error.localizedDescription)"
        }
    }

    func refreshEntitlements() async {
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--simulate-pro") {
            accessLevel = .pro
            return
        }
#endif

        var activeProductIDs: Set<String> = []
        for await result in StoreKit.Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  Self.entitlementProductIDs.contains(transaction.productID),
                  transaction.revocationDate == nil,
                  !transaction.isUpgraded else {
                continue
            }

            if let expirationDate = transaction.expirationDate,
               expirationDate <= .now {
                continue
            }
            activeProductIDs.insert(transaction.productID)
        }
        activeProProductIDs = activeProductIDs
        let foundProEntitlement = !activeProductIDs.isEmpty
        accessLevel = foundProEntitlement ? .pro : .free
        UserDefaults.standard.set(foundProEntitlement, forKey: Self.cachedProAccessKey)
    }

    private func observeTransactionUpdates() -> Task<Void, Never> {
        Task { [weak self] in
            for await update in StoreKit.Transaction.updates {
                guard !Task.isCancelled else { return }
                guard case .verified(let transaction) = update else { continue }
                await transaction.finish()
                await self?.refreshEntitlements()
            }
        }
    }

    private func verified<Value>(_ result: VerificationResult<Value>) throws -> Value {
        switch result {
        case .verified(let value):
            return value
        case .unverified:
            throw SubscriptionStoreError.failedVerification
        }
    }

    private static func productRank(_ productID: String) -> Int {
        switch productID {
        case annualProductID: 0
        case monthlyProductID: 1
        default: 2
        }
    }

    private static func analyticsPlan(for productID: String) -> AnalyticsPlan {
        productID == annualProductID ? .annual : .monthly
    }


    /// Writes both stores. `allowingDecrease` exists only for the DEBUG
    /// customer-journey tools; the shipping paths never lower the count.
    private static func persistFreeUsage(
        _ usage: FreePlanAllowance.Usage,
        defaults: UserDefaults = .standard,
        allowingDecrease: Bool = false
    ) {
        let count = allowingDecrease
            ? usage.captureCount
            : max(usage.captureCount, storedCaptureCount(defaults: defaults))
        defaults.set(count, forKey: freeCapturesUsedKey)
        defaults.set(usage.startedAt, forKey: freeAllowanceStartedAtKey)
        FreeCaptureLedger.persist(count)
    }

    /// The highest count either store knows about. A reinstall wipes defaults
    /// but not the Keychain, so the Keychain is what makes the allowance stick
    /// to the person rather than to the installation.
    private static func storedCaptureCount(defaults: UserDefaults) -> Int {
        max(
            defaults.integer(forKey: freeCapturesUsedKey),
            FreeCaptureLedger.storedCount() ?? 0
        )
    }

    static func canCreateBackgroundCapture(
        defaults: UserDefaults = .standard,
        now: Date = .now
    ) -> Bool {
#if DEBUG
        let override = DeveloperAccessOverride(
            rawValue: defaults.string(forKey: DeveloperAccessOverride.storageKey) ?? ""
        ) ?? .appStore
        if override == .pro { return true }
        if override == .free { return backgroundFreeAllowance(defaults: defaults, now: now) }
#endif
        if defaults.bool(forKey: cachedProAccessKey) { return true }
        return backgroundFreeAllowance(defaults: defaults, now: now)
    }

    static func recordBackgroundCapture(
        defaults: UserDefaults = .standard,
        now: Date = .now
    ) {
        guard !backgroundHasProAccess(defaults: defaults) else { return }
        let usage = normalizedStoredUsage(defaults: defaults, now: now)
        persistFreeUsage(
            .init(
                captureCount: min(
                    FreePlanAllowance.lifetimeCaptureLimit,
                    usage.captureCount + 1
                ),
                startedAt: usage.startedAt
            ),
            defaults: defaults
        )
    }

    private static func backgroundFreeAllowance(
        defaults: UserDefaults,
        now: Date
    ) -> Bool {
        let usage = normalizedStoredUsage(defaults: defaults, now: now)
        persistFreeUsage(usage, defaults: defaults)
        return FreePlanAllowance.remainingCaptures(after: usage.captureCount) > 0
    }

    private static func normalizedStoredUsage(
        defaults: UserDefaults,
        now: Date
    ) -> FreePlanAllowance.Usage {
        let start = defaults.object(forKey: freeAllowanceStartedAtKey) as? Date ?? now
        return FreePlanAllowance.normalizedUsage(
            captureCount: storedCaptureCount(defaults: defaults),
            startedAt: start,
            now: now
        )
    }

    private static func backgroundHasProAccess(defaults: UserDefaults) -> Bool {
#if DEBUG
        let override = DeveloperAccessOverride(
            rawValue: defaults.string(forKey: DeveloperAccessOverride.storageKey) ?? ""
        ) ?? .appStore
        if override == .pro { return true }
        if override == .free { return false }
#endif
        return defaults.bool(forKey: cachedProAccessKey)
    }
}

#if DEBUG
enum DeveloperAccessOverride: String, CaseIterable, Identifiable {
    case appStore
    case free
    case pro

    static let storageKey = "SpeakIt.developerAccessOverride"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .appStore: "App Store"
        case .free: "Free"
        case .pro: "Pro"
        }
    }

    var symbol: String {
        switch self {
        case .appStore: "apple.logo"
        case .free: "person"
        case .pro: "checkmark.seal"
        }
    }
}
#endif

private enum SubscriptionStoreError: LocalizedError {
    case failedVerification

    var errorDescription: String? {
        "The App Store transaction could not be verified."
    }
}
