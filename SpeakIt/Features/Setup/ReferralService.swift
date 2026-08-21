import Foundation
import Security
import StoreKit
import SwiftUI

enum SummerLaunchSale {
    static let endsAt = ISO8601DateFormatter().date(from: "2026-09-22T04:00:00Z")!
    static let regularAnnualUSPrice = "$29.99"

    static func isActive(at date: Date = .now) -> Bool {
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing-pro-preview") {
            return isWithinSaleWindow(at: date)
        }
#endif
        return isConfigured && isWithinSaleWindow(at: date)
    }

    static func isWithinSaleWindow(at date: Date) -> Bool {
        date < endsAt
    }

    static var endDateText: String {
        endsAt.formatted(.dateTime.month(.wide).day().year())
    }

    private static var isConfigured: Bool {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "SpeakItSummerSaleEnabled") as? String else {
            return false
        }
        return ["YES", "true", "1"].contains(value)
    }
}

enum ReferralProgramConfiguration {
    static var apiBaseURL: URL? {
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing-referrals") {
            return URL(string: "https://referrals.example.invalid")
        }
#endif
        return configuredURL(for: "SpeakItReferralAPIURL")
    }

    static var isEnabled: Bool { apiBaseURL != nil }

    private static func configuredURL(for key: String) -> URL? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
              !value.isEmpty,
              !value.contains("$("),
              let url = URL(string: value),
              url.scheme?.lowercased() == "https",
              url.host != nil,
              url.user == nil,
              url.password == nil else {
            return nil
        }
        return url
    }
}

enum ReferralDeepLink {
    static func code(from url: URL) -> String? {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        if url.scheme?.lowercased() == "speakit",
           url.host?.lowercased() == "referral" {
            return normalizedCode(
                components?.queryItems?.first(where: { $0.name == "code" })?.value
            )
        }
        if url.scheme?.lowercased() == "https",
           url.host?.lowercased() == "speakitapp.ca",
           url.path.hasPrefix("/invite") {
            return normalizedCode(
                components?.queryItems?.first(where: { $0.name == "ref" })?.value
            )
        }
        return nil
    }

    private static func normalizedCode(_ value: String?) -> String? {
        guard let value,
              (8...80).contains(value.utf8.count),
              value.unicodeScalars.allSatisfy({
                  CharacterSet.alphanumerics.contains($0) || $0 == "_" || $0 == "-"
              }) else {
            return nil
        }
        return value
    }
}

enum PendingReferralStore {
    private static let codeKey = "SpeakIt.referral.pendingCode"

    static var code: String? {
        get { UserDefaults.standard.string(forKey: codeKey) }
        set { UserDefaults.standard.set(newValue, forKey: codeKey) }
    }
}

struct ReferralInvite: Decodable {
    let code: String
    let inviteURL: URL
}

struct ReferralProgramStatus: Decodable {
    let successfulReferrals: Int
    let availableRewards: Int
    let claimedRewards: Int
}

struct ReferralAcceptance: Decodable {
    let referralCode: String
    let redemptionURL: URL
}

struct ReferralPromotionalOffer: Decodable {
    let productID: String
    let offerID: String
    let keyID: String
    let nonce: UUID
    let signature: String
    let timestamp: Int
}

enum ReferralRewardClaim: Decodable {
    case offerCode(rewardID: String, redemptionURL: URL)
    case promotionalOffer(rewardID: String, offer: ReferralPromotionalOffer)

    private enum CodingKeys: String, CodingKey {
        case mode
        case rewardID
        case redemptionURL
        case offer
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let mode = try container.decode(String.self, forKey: .mode)
        let rewardID = try container.decode(String.self, forKey: .rewardID)
        switch mode {
        case "offer_code":
            self = .offerCode(
                rewardID: rewardID,
                redemptionURL: try container.decode(URL.self, forKey: .redemptionURL)
            )
        case "promotional_offer":
            self = .promotionalOffer(
                rewardID: rewardID,
                offer: try container.decode(ReferralPromotionalOffer.self, forKey: .offer)
            )
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .mode,
                in: container,
                debugDescription: "Unsupported referral reward mode"
            )
        }
    }
}

private struct ReferralCredentials: Codable {
    let appAccountToken: UUID
    let credential: String
}

enum ReferralIdentityStore {
    private static let service = "com.calvinwak.SpeakIt.referrals"
    private static let account = "anonymousIdentity"

    static let current: (appAccountToken: UUID, credential: String) = {
        if let stored = load() {
            return (stored.appAccountToken, stored.credential)
        }
        let created = ReferralCredentials(
            appAccountToken: UUID(),
            credential: secureCredential()
        )
        persist(created)
        return (created.appAccountToken, created.credential)
    }()

    private static func load() -> ReferralCredentials? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else {
            return nil
        }
        return try? JSONDecoder().decode(ReferralCredentials.self, from: data)
    }

    private static func persist(_ credentials: ReferralCredentials) {
        guard let data = try? JSONEncoder().encode(credentials) else { return }
        SecItemDelete(baseQuery as CFDictionary)
        var insert = baseQuery
        insert[kSecValueData as String] = data
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(insert as CFDictionary, nil)
    }

    private static func secureCredential() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            return "\(UUID().uuidString)\(UUID().uuidString)"
        }
        return Data(bytes).base64EncodedString()
    }

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}

actor ReferralClient {
    static let shared = ReferralClient()

    nonisolated var appAccountToken: UUID {
        ReferralIdentityStore.current.appAccountToken
    }

    private let session: URLSession
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init(session: URLSession = .shared) {
        self.session = session
    }

    func createInvite() async throws -> ReferralInvite {
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing-referrals") {
            return ReferralInvite(
                code: "preview-referral",
                inviteURL: URL(string: "https://speakitapp.ca/invite/?ref=preview-referral")!
            )
        }
#endif
        return try await request(path: "/v1/referrals/invite", method: "POST")
    }

    func accept(code: String) async throws -> ReferralAcceptance {
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing-referrals") {
            return ReferralAcceptance(
                referralCode: code,
                redemptionURL: URL(string: "https://apps.apple.com/redeem?ctx=offercodes&id=123&code=PREVIEW")!
            )
        }
#endif
        let acceptance: ReferralAcceptance = try await request(
            path: "/v1/referrals/accept",
            method: "POST",
            body: ["code": code]
        )
        PendingReferralStore.code = code
        return acceptance
    }

    func status() async throws -> ReferralProgramStatus {
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing-referrals") {
            return ReferralProgramStatus(
                successfulReferrals: 1,
                availableRewards: 1,
                claimedRewards: 0
            )
        }
#endif
        return try await request(path: "/v1/referrals/status", method: "GET")
    }

    func claimReward() async throws -> ReferralRewardClaim {
        try await request(path: "/v1/rewards/claim", method: "POST")
    }

    func verifyTransaction(_ signedTransaction: String) async {
        guard ReferralProgramConfiguration.isEnabled else { return }
        struct VerificationRequest: Encodable {
            let signedTransaction: String
            let referralCode: String?
        }
        struct VerificationResponse: Decodable {
            let referralQualified: Bool
        }
        do {
            let response: VerificationResponse = try await request(
                path: "/v1/transactions/verify",
                method: "POST",
                body: VerificationRequest(
                    signedTransaction: signedTransaction,
                    referralCode: PendingReferralStore.code
                )
            )
            if response.referralQualified {
                PendingReferralStore.code = nil
            }
        } catch ReferralClientError.server(let code, _) where Self.terminalReferralErrors.contains(code) {
            PendingReferralStore.code = nil
        } catch {
            // StoreKit remains authoritative for local access. Server sync is
            // retried from current entitlements on the next launch or restore.
        }
    }

    private func request<Response: Decodable>(
        path: String,
        method: String
    ) async throws -> Response {
        try await perform(path: path, method: method, body: nil)
    }

    private func request<Response: Decodable, Body: Encodable>(
        path: String,
        method: String,
        body: Body
    ) async throws -> Response {
        try await perform(path: path, method: method, body: encoder.encode(body))
    }

    private func perform<Response: Decodable>(
        path: String,
        method: String,
        body: Data?
    ) async throws -> Response {
        guard let baseURL = ReferralProgramConfiguration.apiBaseURL,
              let url = URL(string: path, relativeTo: baseURL)?.absoluteURL else {
            throw ReferralClientError.notConfigured
        }
        let credentials = ReferralIdentityStore.current
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(
            credentials.appAccountToken.uuidString.lowercased(),
            forHTTPHeaderField: "X-SpeakIt-App-Account-Token"
        )
        request.setValue("Bearer \(credentials.credential)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ReferralClientError.invalidResponse
        }
        guard 200..<300 ~= http.statusCode else {
            let serverError = try? decoder.decode(ServerError.self, from: data)
            throw ReferralClientError.server(
                code: serverError?.error ?? "server_error",
                message: serverError?.message
                    ?? "The referral service is unavailable. Please try again."
            )
        }
        return try decoder.decode(Response.self, from: data)
    }

    private static let terminalReferralErrors: Set<String> = [
        "friend_offer_not_verified",
        "invite_already_used",
        "friend_already_referred",
        "referral_not_accepted",
        "referral_not_found",
        "self_referral",
        "transaction_owner_conflict"
    ]
}

private struct ServerError: Decodable {
    let error: String
    let message: String
}

enum ReferralClientError: LocalizedError {
    case notConfigured
    case invalidResponse
    case server(code: String, message: String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            "Referrals are not connected in this build."
        case .invalidResponse:
            "The referral service returned an invalid response."
        case .server(_, let message):
            message
        }
    }
}

struct ReferralProgramView: View {
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var subscriptionStore: SubscriptionStore

    @State private var invite: ReferralInvite?
    @State private var status: ReferralProgramStatus?
    @State private var isWorking = false
    @State private var errorMessage: String?

    let initialReferralCode: String?

    init(initialReferralCode: String? = nil) {
        self.initialReferralCode = initialReferralCode
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                if let initialReferralCode {
                    friendCard(code: initialReferralCode)
                } else {
                    inviteCard
                    rewardStatus
                }
                terms
            }
            .padding(22)
        }
        .background(Color.speakBackground.ignoresSafeArea())
        .navigationTitle("Invite a Friend")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard initialReferralCode == nil else { return }
            await loadStatus()
        }
        .alert(
            "Referral",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: "gift.fill")
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(Color.speakInverseInk)
                .frame(width: 56, height: 56)
                .background(Color.speakInverseSurface, in: RoundedRectangle(cornerRadius: 17))
            Text("Give a month. Get a month.")
                .font(.title.weight(.semibold))
                .foregroundStyle(Color.speakInk)
            Text("Invite a friend to Speak It. They get one month of Pro free, and after Apple verifies that they joined, you get one too.")
                .font(.body)
                .foregroundStyle(Color.speakMuted)
        }
    }

    private var inviteCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Your invite")
                .font(.headline)
            if let invite {
                ShareLink(
                    item: invite.inviteURL,
                    subject: Text("Try Speak It free for a month"),
                    message: Text("I use Speak It to turn quick thoughts into organized tasks and memories. This invite gives you one month of Pro free.")
                ) {
                    Label("Share Invite", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .foregroundStyle(Color.speakInverseInk)
                        .background(Color.speakInverseSurface, in: RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.speakIt)
                .accessibilityIdentifier("referral.share")
            } else {
                Button {
                    Task { await createInvite() }
                } label: {
                    HStack {
                        if isWorking { ProgressView().tint(Color.speakInverseInk) }
                        Text("Create Invite")
                    }
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .foregroundStyle(Color.speakInverseInk)
                    .background(Color.speakInverseSurface, in: RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.speakIt)
                .disabled(isWorking)
                .accessibilityIdentifier("referral.create")
            }
        }
        .referralCardStyle()
    }

    @ViewBuilder
    private var rewardStatus: some View {
        if let status {
            VStack(alignment: .leading, spacing: 12) {
                Text("Your rewards")
                    .font(.headline)
                Text("\(status.successfulReferrals) successful invite\(status.successfulReferrals == 1 ? "" : "s")")
                    .foregroundStyle(Color.speakMuted)
                if status.availableRewards > 0 {
                    Button("Claim one free month") {
                        Task { await claimReward() }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.speakInk)
                    .disabled(isWorking)
                    .accessibilityIdentifier("referral.claim")
                } else {
                    Text("A reward appears here after Apple verifies your friend’s subscription.")
                        .font(.subheadline)
                        .foregroundStyle(Color.speakMuted)
                }
            }
            .referralCardStyle()
        }
    }

    private func friendCard(code: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Your free month is ready", systemImage: "checkmark.seal")
                .font(.headline)
            Text("Apple will confirm your eligibility and show the full offer terms before anything starts.")
                .font(.subheadline)
                .foregroundStyle(Color.speakMuted)
            Button {
                Task { await redeemFriendOffer(code: code) }
            } label: {
                HStack {
                    if isWorking { ProgressView().tint(Color.speakInverseInk) }
                    Text("Redeem One Free Month")
                }
                .frame(maxWidth: .infinity, minHeight: 52)
                .foregroundStyle(Color.speakInverseInk)
                .background(Color.speakInverseSurface, in: RoundedRectangle(cornerRadius: 16))
            }
            .buttonStyle(.speakIt)
            .disabled(isWorking)
            .accessibilityIdentifier("referral.redeem-friend")
        }
        .referralCardStyle()
    }

    private var terms: some View {
        Text("One reward per new referred subscriber. No self-referrals or duplicate transactions. Maximum 12 rewards per calendar year. Apple verifies every subscription and reward; sharing or cancelling the share sheet does not create a reward.")
            .font(.caption)
            .foregroundStyle(Color.speakMuted)
    }

    @MainActor
    private func createInvite() async {
        isWorking = true
        defer { isWorking = false }
        do {
            invite = try await ReferralClient.shared.createInvite()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func redeemFriendOffer(code: String) async {
        isWorking = true
        defer { isWorking = false }
        do {
            let acceptance = try await ReferralClient.shared.accept(code: code)
            openURL(acceptance.redemptionURL)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func loadStatus() async {
        do {
            status = try await ReferralClient.shared.status()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func claimReward() async {
        isWorking = true
        defer { isWorking = false }
        do {
            switch try await ReferralClient.shared.claimReward() {
            case .offerCode(_, let redemptionURL):
                openURL(redemptionURL)
            case .promotionalOffer(_, let offer):
                _ = await subscriptionStore.purchaseReferralReward(offer)
            }
            status = try? await ReferralClient.shared.status()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private extension View {
    func referralCardStyle() -> some View {
        self
            .padding(18)
            .background(Color.speakSurface, in: RoundedRectangle(cornerRadius: 20))
            .overlay {
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color.speakDivider, lineWidth: 1)
            }
    }
}
