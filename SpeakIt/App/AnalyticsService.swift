import Foundation

enum AnalyticsPlan: String, Sendable {
    case free
    case pro
    case monthly
    case annual
}

enum AnalyticsScreen: String, Sendable {
    case today
    case memory
}

enum AnalyticsCaptureMode: String, Sendable {
    case voice
    case text
}

enum AnalyticsCaptureEntry: String, Sendable {
    case dock
    case onboarding
    case quickAction = "quick_action"
    case deepLink = "deep_link"
    case testPrompt = "test_prompt"
}

enum AnalyticsCaptureSource: String, Sendable {
    case voice
    case text
    case shareSheet = "share_sheet"
    case recovery
}

enum AnalyticsPaywallContext: String, Sendable {
    case account
    case freeLimit = "free_limit"
}

enum AnalyticsSearchResultBucket: String, Sendable {
    case none
    case oneToFive = "1_to_5"
    case sixOrMore = "6_or_more"

    init(resultCount: Int) {
        switch resultCount {
        case ...0: self = .none
        case 1...5: self = .oneToFive
        default: self = .sixOrMore
        }
    }
}

enum SpeakItAnalyticsEvent: Sendable {
    case appInstalled
    case appOpened(plan: AnalyticsPlan)
    case screenViewed(AnalyticsScreen)
    case onboardingCompleted(path: AnalyticsCaptureEntry)
    /// The optional on-device profile was created for the first time. Carries
    /// no properties: the name and email never leave the phone.
    case profileCreated
    case captureStarted(mode: AnalyticsCaptureMode, entry: AnalyticsCaptureEntry)
    case captureSaved(source: AnalyticsCaptureSource, itemCount: Int, needsReviewCount: Int, plan: AnalyticsPlan)
    case captureFailed(source: AnalyticsCaptureSource, category: String)
    case freeLimitReached(used: Int)
    case paywallViewed(context: AnalyticsPaywallContext)
    case planSelected(AnalyticsPlan)
    case purchaseStarted(AnalyticsPlan)
    case purchaseCompleted(AnalyticsPlan)
    case purchasePending(AnalyticsPlan)
    case purchaseCancelled(AnalyticsPlan)
    case purchaseFailed(AnalyticsPlan)
    case purchasesRestored(hasPro: Bool)
    case taskCompletionChanged(completed: Bool)
    case memoryCollectionOpened(collection: String)
    case memorySearchPerformed(results: AnalyticsSearchResultBucket)

    var name: String {
        switch self {
        case .appInstalled: "app_installed"
        case .appOpened: "app_opened"
        case .screenViewed: "screen_viewed"
        case .onboardingCompleted: "onboarding_completed"
        case .profileCreated: "profile_created"
        case .captureStarted: "capture_started"
        case .captureSaved: "capture_saved"
        case .captureFailed: "capture_failed"
        case .freeLimitReached: "free_limit_reached"
        case .paywallViewed: "paywall_viewed"
        case .planSelected: "plan_selected"
        case .purchaseStarted: "purchase_started"
        case .purchaseCompleted: "purchase_completed"
        case .purchasePending: "purchase_pending"
        case .purchaseCancelled: "purchase_cancelled"
        case .purchaseFailed: "purchase_failed"
        case .purchasesRestored: "purchases_restored"
        case .taskCompletionChanged: "task_completion_changed"
        case .memoryCollectionOpened: "memory_collection_opened"
        case .memorySearchPerformed: "memory_search_performed"
        }
    }

    /// This is deliberately a closed property vocabulary. There is no API for
    /// callers to attach arbitrary strings, which prevents user-authored words
    /// from reaching analytics by accident.
    var properties: [String: Any] {
        switch self {
        case .appInstalled:
            [:]
        case .appOpened(let plan):
            ["plan": plan.rawValue]
        case .screenViewed(let screen):
            ["screen": screen.rawValue]
        case .onboardingCompleted(let path):
            ["entry": path.rawValue]
        case .profileCreated:
            [:]
        case .captureStarted(let mode, let entry):
            ["mode": mode.rawValue, "entry": entry.rawValue]
        case .captureSaved(let source, let itemCount, let needsReviewCount, let plan):
            [
                "source": source.rawValue,
                "item_count": max(0, itemCount),
                "needs_review_count": max(0, needsReviewCount),
                "plan": plan.rawValue
            ]
        case .captureFailed(let source, let category):
            ["source": source.rawValue, "error_category": Self.safeCategory(category)]
        case .freeLimitReached(let used):
            ["free_captures_used": max(0, used)]
        case .paywallViewed(let context):
            ["context": context.rawValue]
        case .planSelected(let plan),
             .purchaseStarted(let plan),
             .purchaseCompleted(let plan),
             .purchasePending(let plan),
             .purchaseCancelled(let plan),
             .purchaseFailed(let plan):
            ["plan": plan.rawValue]
        case .purchasesRestored(let hasPro):
            ["has_pro": hasPro]
        case .taskCompletionChanged(let completed):
            ["completed": completed]
        case .memoryCollectionOpened(let collection):
            ["collection": Self.safeCollection(collection)]
        case .memorySearchPerformed(let results):
            ["result_bucket": results.rawValue]
        }
    }

    static let allowedPropertyKeys: Set<String> = [
        "plan", "screen", "entry", "mode", "source", "item_count",
        "needs_review_count", "error_category", "free_captures_used",
        "context", "has_pro", "completed", "collection", "result_bucket"
    ]

    private static let allowedErrorCategories: Set<String> = [
        "storage", "organization", "speech", "network", "unknown"
    ]

    private static let allowedCollections: Set<String> = [
        "pinned", "ideas", "people", "reference", "archive"
    ]

    private static func safeCategory(_ category: String) -> String {
        allowedErrorCategories.contains(category) ? category : "unknown"
    }

    private static func safeCollection(_ collection: String) -> String {
        allowedCollections.contains(collection) ? collection : "reference"
    }
}

@MainActor
enum SpeakItAnalytics {
    static let enabledKey = "SpeakIt.analytics.isEnabled"

    private static let installIDKey = "SpeakIt.analytics.installID"
    private static let installEventSentKey = "SpeakIt.analytics.installEventSent"
    private static let projectKeyInfoKey = "SpeakItAnalyticsKey"
    private static let hostInfoKey = "SpeakItAnalyticsHost"
    private static let defaultHost = "https://us.i.posthog.com"

    static func recordAppOpen(plan: AnalyticsPlan) {
        guard let configuration else { return }
        let defaults = UserDefaults.standard
        if !defaults.bool(forKey: installEventSentKey) {
            send(.appInstalled, configuration: configuration)
            defaults.set(true, forKey: installEventSentKey)
        }
        send(.appOpened(plan: plan), configuration: configuration)
    }

    static func track(_ event: SpeakItAnalyticsEvent) {
        guard let configuration else { return }
        send(event, configuration: configuration)
    }

    static var isConfigured: Bool { configuration != nil }

    private struct Configuration {
        let projectKey: String
        let captureURL: URL
    }

    private static var configuration: Configuration? {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: enabledKey) == nil {
            defaults.set(true, forKey: enabledKey)
        }
        guard defaults.bool(forKey: enabledKey) else { return nil }

        guard let key = Bundle.main.object(forInfoDictionaryKey: projectKeyInfoKey) as? String else {
            return nil
        }
        let trimmedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty, !trimmedKey.contains("$(") else { return nil }

        let configuredHost = (Bundle.main.object(forInfoDictionaryKey: hostInfoKey) as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let host = configuredHost.flatMap { $0.isEmpty ? nil : $0 } ?? defaultHost
        guard let baseURL = URL(string: host),
              baseURL.scheme == "https",
              let captureURL = URL(string: "capture/", relativeTo: baseURL)?.absoluteURL else {
            return nil
        }
        return Configuration(projectKey: trimmedKey, captureURL: captureURL)
    }

    private static func send(_ event: SpeakItAnalyticsEvent, configuration: Configuration) {
        let invalidKeys = Set(event.properties.keys).subtracting(SpeakItAnalyticsEvent.allowedPropertyKeys)
        guard invalidKeys.isEmpty else {
            assertionFailure("Analytics event contains a property outside the privacy allowlist")
            return
        }

        var properties = event.properties
        properties["distinct_id"] = anonymousInstallID
        properties["platform"] = "ios"
        properties["app_version"] = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        properties["app_build"] = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
        properties["$lib"] = "speakit-ios"
        properties["$geoip_disable"] = true
        properties["$process_person_profile"] = false

        let body: [String: Any] = [
            "api_key": configuration.projectKey,
            "event": event.name,
            "timestamp": ISO8601DateFormatter().string(from: .now),
            "properties": properties
        ]
        guard JSONSerialization.isValidJSONObject(body),
              let data = try? JSONSerialization.data(withJSONObject: body) else {
            return
        }

        var request = URLRequest(url: configuration.captureURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 8
        request.httpBody = data
        URLSession.shared.dataTask(with: request).resume()
    }

    private static var anonymousInstallID: String {
        let defaults = UserDefaults.standard
        if let existing = defaults.string(forKey: installIDKey), UUID(uuidString: existing) != nil {
            return existing
        }
        let newValue = UUID().uuidString.lowercased()
        defaults.set(newValue, forKey: installIDKey)
        return newValue
    }
}
