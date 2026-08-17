import StoreKit
import SwiftData
import SwiftUI

enum SpeakItSharing {
    private static var configuredAppStoreURL: URL? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "SpeakItAppStoreURL") as? String,
              !value.isEmpty else {
            return nil
        }
        return URL(string: value)
    }

    static var message: String {
        let introduction = "I’ve been using Speak It to turn quick thoughts into organized tasks, ideas, and memories."
        if let configuredAppStoreURL {
            return "\(introduction) \(configuredAppStoreURL.absoluteString)"
        }
        return "\(introduction) Look for “Speak It” on the App Store."
    }
}

enum ProPresentationContext: Equatable {
    case account
    case freeLimit
}

struct SpeakItProView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var subscriptionStore: SubscriptionStore
    @Query private var allItems: [CapturedItem]

    @State private var selectedProductID = SubscriptionStore.annualProductID
    @State private var showsPrivacy = false
    @State private var showsCodeRedemption = false
    @State private var hadProAccessBeforeRedemption = false
#if DEBUG
    @State private var selectedDeveloperPlan = DeveloperTestPlan.annual
#endif

    let context: ProPresentationContext

    init(context: ProPresentationContext = .account) {
        self.context = context
    }

    private var completedCount: Int {
        allItems.lazy.filter(\.isCompleted).count
    }

    private var selectedProduct: Product? {
        subscriptionStore.products.first { $0.id == selectedProductID }
            ?? subscriptionStore.recommendedProduct
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    hero

                    if subscriptionStore.hasProAccess {
                        activeSubscriptionCard
                    } else {
                        valueSummary
                        plans
                        purchaseControls
                        benefits
                    }

                    codeRedemptionCard
                    trustNote
                    legalControls
                }
                .padding(.horizontal, 22)
                .padding(.top, 12)
                .padding(.bottom, 36)
            }
            .scrollIndicators(.hidden)
            .background(Color.speakBackground.ignoresSafeArea())
            .navigationTitle("Speak It Pro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task {
            SpeakItAnalytics.track(.paywallViewed(
                context: context == .freeLimit ? .freeLimit : .account
            ))
            await subscriptionStore.prepare()
            if subscriptionStore.annualProduct == nil,
               let firstID = subscriptionStore.recommendedProduct?.id {
                selectedProductID = firstID
            }
        }
        .sheet(isPresented: $showsPrivacy) {
            SpeakItPrivacyView()
        }
        .offerCodeRedemption(isPresented: $showsCodeRedemption) { result in
            handleCodeRedemptionCompletion(result)
        }
        .alert(
            "Speak It Pro",
            isPresented: Binding(
                get: { subscriptionStore.customerMessage != nil },
                set: { if !$0 { subscriptionStore.customerMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {
                subscriptionStore.customerMessage = nil
            }
        } message: {
            Text(subscriptionStore.customerMessage ?? "")
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.speakInverseSurface)
                    .frame(width: 58, height: 58)

                Image(systemName: "sparkles")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(Color.speakInverseInk)
            }

            Text(heroTitle)
                .font(.title.weight(.semibold))
                .foregroundStyle(Color.speakInk)

            Text(heroDetail)
                .font(.body)
                .foregroundStyle(Color.speakMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var heroTitle: String {
        if subscriptionStore.hasProAccess { return "Your thoughts stay in motion." }
        if context == .freeLimit { return "You’ve used your 10 free captures." }
        return "More clarity from every thought."
    }

    private var heroDetail: String {
        if subscriptionStore.hasProAccess {
            return "Speak It Pro is active on this Apple Account."
        }
        if context == .freeLimit {
            return "Everything you saved is still yours. You’ve used all \(FreePlanAllowance.lifetimeCaptureLimit) free captures — upgrade for unlimited capture."
        }
        return "Your first \(FreePlanAllowance.lifetimeCaptureLimit) captures include the complete experience. Pro removes the capture limit so every thought can keep moving."
    }

    @ViewBuilder
    private var valueSummary: some View {
        if !allItems.isEmpty {
            HStack(spacing: 0) {
                valueMetric(value: allItems.count, label: "organized")
                Divider().frame(height: 42)
                valueMetric(value: completedCount, label: "completed")
            }
            .padding(.vertical, 18)
            .background(Color.speakSurface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.speakDivider, lineWidth: 1)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Speak It has organized \(allItems.count) items and you have completed \(completedCount)")
        }
    }

    private func valueMetric(value: Int, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value.formatted())
                .font(.title2.weight(.semibold))
                .foregroundStyle(Color.speakInk)
            Text(label)
                .font(.footnote)
                .foregroundStyle(Color.speakMuted)
        }
        .frame(maxWidth: .infinity)
    }

    private var benefits: some View {
        VStack(alignment: .leading, spacing: 18) {
            benefit(
                symbol: "infinity",
                title: "Unlimited capture",
                detail: "Keep speaking or typing without a lifetime capture limit."
            )
            benefit(
                symbol: "square.stack.3d.up",
                title: "The complete experience",
                detail: "Keep natural cleanup, Today and Memory routing, reminders, and capture-anywhere workflows."
            )
            benefit(
                symbol: "text.quote",
                title: "Your originals stay intact",
                detail: "Every organized result remains connected to the words you originally captured."
            )
        }
    }

    private func benefit(symbol: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Color.speakInk)
                .frame(width: 38, height: 38)
                .background(Color.speakSurface, in: Circle())
                .overlay { Circle().stroke(Color.speakDivider, lineWidth: 1) }

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.speakInk)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(Color.speakMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var plans: some View {
#if DEBUG
        if subscriptionStore.isDeveloperCustomerJourneyActive,
           subscriptionStore.products.isEmpty {
            developerPlans
        } else {
            appStorePlans
        }
#else
        appStorePlans
#endif
    }

    @ViewBuilder
    private var appStorePlans: some View {
        if subscriptionStore.isLoadingProducts {
            HStack(spacing: 12) {
                ProgressView()
                Text("Loading plans from the App Store…")
                    .font(.subheadline)
                    .foregroundStyle(Color.speakMuted)
            }
            .frame(maxWidth: .infinity, minHeight: 78)
        } else if subscriptionStore.products.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Pro is being prepared")
                    .font(.headline)
                    .foregroundStyle(Color.speakInk)
                Text("Everything you already saved remains available. Plans will appear here as soon as the App Store products are connected.")
                    .font(.subheadline)
                    .foregroundStyle(Color.speakMuted)

                Button("Check again") {
                    Task { await subscriptionStore.loadProducts(force: true) }
                }
                .font(.subheadline.weight(.semibold))
                .padding(.top, 4)
                .buttonStyle(.speakIt)
            }
            .padding(18)
            .background(Color.speakSurface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.speakDivider, lineWidth: 1)
            }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(subscriptionStore.products, id: \.id) { product in
                    planButton(product)
                }
            }
        }
    }

#if DEBUG
    private var developerPlans: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("DEVELOPER PURCHASE PREVIEW")
                .font(.caption2.weight(.bold))
                .tracking(1.1)
                .foregroundStyle(Color.speakMuted)

            developerPlanButton(
                .annual,
                title: "Annual",
                price: "$14.99 / year",
                detail: "$1.25 a month · save 37%"
            )
            developerPlanButton(
                .monthly,
                title: "Monthly",
                price: "$1.99 / month",
                detail: "Flexible monthly billing"
            )
        }
    }

    private func developerPlanButton(
        _ plan: DeveloperTestPlan,
        title: String,
        price: String,
        detail: String
    ) -> some View {
        let isSelected = selectedDeveloperPlan == plan
        return Button {
            selectedDeveloperPlan = plan
            SpeakItAnalytics.track(.planSelected(plan == .annual ? .annual : .monthly))
        } label: {
            VStack(alignment: .leading, spacing: 11) {
                HStack(spacing: 10) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 21, weight: .medium))
                    Text(title)
                        .font(.body.weight(.semibold))
                    Spacer(minLength: 8)
                    if plan == .annual {
                        bestValueBadge
                    }
                }

                HStack(alignment: .bottom, spacing: 12) {
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(Color.speakMuted)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    Text(price)
                        .font(.subheadline.weight(.semibold))
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: true, vertical: false)
                }
            }
            .foregroundStyle(Color.speakInk)
            .padding(16)
            .background(Color.speakSurface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(isSelected ? Color.speakInk : Color.speakDivider, lineWidth: isSelected ? 2 : 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.speakIt)
        .accessibilityIdentifier("pro.plan.\(plan == .annual ? "annual" : "monthly")")
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
    }
#endif

    private func planButton(_ product: Product) -> some View {
        let isSelected = selectedProductID == product.id
        let isAnnual = product.id == SubscriptionStore.annualProductID

        return Button {
            selectedProductID = product.id
            SpeakItAnalytics.track(.planSelected(isAnnual ? .annual : .monthly))
        } label: {
            VStack(alignment: .leading, spacing: 11) {
                HStack(spacing: 10) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 21, weight: .medium))
                    Text(isAnnual ? "Annual" : "Monthly")
                        .font(.body.weight(.semibold))
                    Spacer(minLength: 8)
                    if isAnnual {
                        bestValueBadge
                    }
                }

                HStack(alignment: .bottom, spacing: 12) {
                    Text(isAnnual ? "One payment each year" : "Flexible monthly billing")
                        .font(.footnote)
                        .foregroundStyle(Color.speakMuted)
                    Spacer(minLength: 8)
                    VStack(alignment: .trailing, spacing: 3) {
                        Text(product.displayPrice)
                            .font(.body.weight(.semibold))
                        Text(isAnnual ? "per year" : "per month")
                            .font(.caption)
                            .foregroundStyle(Color.speakMuted)
                    }
                    .fixedSize(horizontal: true, vertical: false)
                }
            }
            .foregroundStyle(Color.speakInk)
            .padding(16)
            .background(Color.speakSurface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(isSelected ? Color.speakInk : Color.speakDivider, lineWidth: isSelected ? 2 : 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.speakIt)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("pro.plan.\(isAnnual ? "annual" : "monthly")")
        .accessibilityLabel(
            "\(isAnnual ? "Annual" : "Monthly"), \(product.displayPrice) per \(isAnnual ? "year" : "month")"
        )
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
    }

    private var bestValueBadge: some View {
        Text("BEST VALUE")
            .font(.caption2.weight(.bold))
            .tracking(0.5)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .foregroundStyle(Color.speakInverseInk)
            .background(Color.speakInverseSurface, in: Capsule())
            .accessibilityIdentifier("pro.best-value")
    }

    @ViewBuilder
    private var purchaseControls: some View {
#if DEBUG
        if subscriptionStore.isDeveloperCustomerJourneyActive,
           subscriptionStore.products.isEmpty {
            developerPurchaseControls
        } else {
            appStorePurchaseControls
        }
#else
        appStorePurchaseControls
#endif
    }

    private var appStorePurchaseControls: some View {
        VStack(spacing: 12) {
            Button {
                guard let selectedProduct else { return }
                Task {
                    let purchased = await subscriptionStore.purchase(selectedProduct)
                    if purchased { selectedProductID = selectedProduct.id }
                }
            } label: {
                HStack(spacing: 10) {
                    if subscriptionStore.isPurchasing {
                        ProgressView().tint(Color.speakInverseInk)
                    }
                    Text(purchaseButtonTitle)
                        .font(.headline)
                }
                .foregroundStyle(Color.speakInverseInk)
                .frame(maxWidth: .infinity, minHeight: 56)
                .background(Color.speakInverseSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .buttonStyle(.speakIt)
            .disabled(selectedProduct == nil || subscriptionStore.isPurchasing)
            .opacity(selectedProduct == nil ? 0.45 : 1)

            if let selectedProduct {
                Text(
                    "\(selectedProduct.displayPrice) per \(selectedProduct.id == SubscriptionStore.annualProductID ? "year" : "month"). Auto-renews until cancelled."
                )
                .font(.caption)
                .foregroundStyle(Color.speakMuted)
                .multilineTextAlignment(.center)
            }

            Button {
                Task { await subscriptionStore.restorePurchases() }
            } label: {
                HStack(spacing: 8) {
                    if subscriptionStore.isRestoring { ProgressView() }
                    Text("Restore Purchases")
                }
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(Color.speakMuted)
            .disabled(subscriptionStore.isRestoring)
            .buttonStyle(.speakIt)

            Button(context == .freeLimit ? "Not now" : "Continue using Speak It free") { dismiss() }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color.speakInk)
                .frame(minHeight: 44)
                .buttonStyle(.speakIt)
        }
    }

#if DEBUG
    private var developerPurchaseControls: some View {
        VStack(spacing: 12) {
            Button {
                let analyticsPlan: AnalyticsPlan = selectedDeveloperPlan == .annual ? .annual : .monthly
                SpeakItAnalytics.track(.purchaseStarted(analyticsPlan))
                subscriptionStore.completeDeveloperPurchase()
                SpeakItAnalytics.track(.purchaseCompleted(analyticsPlan))
            } label: {
                VStack(spacing: 3) {
                    Text(selectedDeveloperPlan == .annual
                         ? "Choose Annual · $14.99"
                         : "Choose Monthly · $1.99")
                        .font(.headline)
                    Text("Developer test · no charge")
                        .font(.caption)
                        .opacity(0.78)
                }
                .foregroundStyle(Color.speakInverseInk)
                .frame(maxWidth: .infinity, minHeight: 58)
                .background(Color.speakInverseSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .buttonStyle(.speakIt)
            .accessibilityIdentifier("pro.purchase")

            Text(selectedDeveloperPlan == .annual
                 ? "$14.99 per year. Auto-renews until cancelled."
                 : "$1.99 per month. Auto-renews until cancelled.")
                .font(.caption)
                .foregroundStyle(Color.speakMuted)

            Button("Not now") { dismiss() }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color.speakInk)
                .frame(minHeight: 44)
                .buttonStyle(.speakIt)
        }
    }
#endif

    private var purchaseButtonTitle: String {
        guard let selectedProduct else { return "Plans unavailable in this build" }
        return selectedProduct.id == SubscriptionStore.annualProductID
            ? "Choose Annual · \(selectedProduct.displayPrice)"
            : "Choose Monthly · \(selectedProduct.displayPrice)"
    }

    private var activeSubscriptionCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Pro is active", systemImage: "checkmark.seal.fill")
                .font(.headline)
                .foregroundStyle(Color.speakInk)

            Text(activeSubscriptionDetail)
                .font(.subheadline)
                .foregroundStyle(Color.speakMuted)

#if DEBUG
            if subscriptionStore.isDeveloperCustomerJourneyActive,
               subscriptionStore.developerAccessOverride == .pro {
                Label("Developer test subscription · no charge", systemImage: "hammer")
                    .font(.subheadline.weight(.semibold))
            } else if subscriptionStore.hasActiveSubscription {
                manageSubscriptionLink
            }
#else
            if subscriptionStore.hasActiveSubscription {
                manageSubscriptionLink
            }
#endif
        }
        .padding(18)
        .background(Color.speakSurface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.speakDivider, lineWidth: 1)
        }
    }

    private var activeSubscriptionDetail: String {
#if DEBUG
        if subscriptionStore.isDeveloperCustomerJourneyActive,
           subscriptionStore.developerAccessOverride == .pro {
            return "This is the customer-facing Pro state. The developer purchase did not create an App Store receipt or charge."
        }
#endif
        if subscriptionStore.hasLifetimeProAccess {
            if subscriptionStore.hasActiveSubscription {
                return "Lifetime Pro is active on this Apple Account. An active subscription is also associated with the account and can be managed below."
            }
            return "Lifetime Pro is active permanently and is available on devices using this Apple Account."
        }
        return "Your subscription is managed securely by Apple and is available on devices using this Apple Account."
    }

    private var manageSubscriptionLink: some View {
        Link(destination: URL(string: "https://apps.apple.com/account/subscriptions")!) {
            Label("Manage Subscription", systemImage: "arrow.up.right")
                .font(.subheadline.weight(.semibold))
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
    }

    private var trustNote: some View {
        Label {
            Text("No Speak It account is required. Payment and Pro access are handled by Apple. Your existing thoughts never become locked.")
                .font(.footnote)
                .foregroundStyle(Color.speakMuted)
        } icon: {
            Image(systemName: "lock.shield")
                .foregroundStyle(Color.speakMuted)
        }
    }

    private var codeRedemptionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Have a code?")
                .font(.headline)
                .foregroundStyle(Color.speakInk)

            Text("Redeem a Speak It offer code securely with the App Store.")
                .font(.subheadline)
                .foregroundStyle(Color.speakMuted)

            Button {
                hadProAccessBeforeRedemption = subscriptionStore.hasProAccess
                showsCodeRedemption = true
            } label: {
                Label("Redeem Code", systemImage: "giftcard")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .foregroundStyle(Color.speakInk)
                    .background(
                        Color.speakSurface,
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.speakDivider, lineWidth: 1)
                    }
                    .contentShape(Rectangle())
            }
            .buttonStyle(.speakIt)
            .accessibilityIdentifier("pro.redeem-code")
        }
        .padding(18)
        .background(
            Color.speakSurface.opacity(0.45),
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
    }

    private func handleCodeRedemptionCompletion(_ result: Result<Void, Error>) {
        switch result {
        case .success:
            Task {
                await subscriptionStore.refreshEntitlements()
                guard !hadProAccessBeforeRedemption,
                      subscriptionStore.hasProAccess else { return }
                subscriptionStore.customerMessage = subscriptionStore.hasLifetimeProAccess
                    ? "Lifetime Speak It Pro is ready on this Apple Account."
                    : "Speak It Pro is ready on this Apple Account."
            }
        case .failure(let error):
            subscriptionStore.customerMessage =
                "The App Store couldn’t open code redemption. \(error.localizedDescription)"
        }
    }

    private var legalControls: some View {
        HStack(spacing: 20) {
            Button("Privacy") { showsPrivacy = true }
                .buttonStyle(.speakIt)
            Link(destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!) {
                Text("Terms")
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            ShareLink(
                item: SpeakItSharing.message,
                subject: Text("Speak It")
            ) {
                Text("Share Speak It")
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(Color.speakMuted)
        .frame(maxWidth: .infinity)
    }
}

#if DEBUG
private enum DeveloperTestPlan {
    case annual
    case monthly
}
#endif

struct ProDiscoveryCard: View {
    let itemCount: Int
    let onExplore: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(Color.speakInverseInk)
                    .frame(width: 42, height: 42)
                    .background(Color.speakInverseSurface, in: Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text("You’ve organized \(itemCount) thoughts")
                        .font(.headline)
                        .foregroundStyle(Color.speakInk)
                    Text("See how Pro can make your writing, Memory, and schedules even more useful.")
                        .font(.subheadline)
                        .foregroundStyle(Color.speakMuted)
                }

                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.speakMuted)
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.speakIt)
                .accessibilityLabel("Dismiss Speak It Pro suggestion")
            }

            Button(action: onExplore) {
                Text("Explore Speak It Pro")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.speakInverseInk)
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.speakIt)
            .background(Color.speakInverseSurface, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        }
        .padding(18)
        .background(Color.speakSurface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.speakDivider, lineWidth: 1)
        }
    }
}
