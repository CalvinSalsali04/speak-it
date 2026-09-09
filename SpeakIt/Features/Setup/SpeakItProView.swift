import StoreKit
import SwiftData
import SwiftUI

/// The published legal documents, in one place so the paywall and the in-app
/// privacy summary cannot point at different things.
///
/// App Review guideline 3.1.2 asks a subscription screen to carry functional
/// links to the terms of use and the privacy policy. The in-app summary
/// (`SpeakItPrivacyView`) explains what Speak It does in plain language, which
/// is the more useful thing to read — but it is not the published policy, so it
/// cannot be what the paywall links to.
enum SpeakItLegal {
    static let privacyPolicy = URL(string: "https://speakitapp.ca/privacy")!
    /// Apple's standard EULA, which is the terms of use for a subscription sold
    /// through the App Store unless a custom agreement is supplied.
    static let termsOfUse = URL(
        string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"
    )!
}

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
    /// Shown once, on the day of the first capture that actually spent part of
    /// the allowance. The product has just demonstrably worked, which is the
    /// only moment before the wall where the offer is about something the
    /// person has seen rather than something they are being promised.
    case firstCapture
    /// Shown once, while free captures remain. Meeting the wall is the worst
    /// time to ask: the person has already been stopped.
    case runningLow


    var analyticsContext: AnalyticsPaywallContext {
        switch self {
        case .account: .account
        case .freeLimit: .freeLimit
        case .firstCapture: .firstCapture
        case .runningLow: .runningLow
        }
    }
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

                    if ReferralProgramConfiguration.isEnabled {
                        referralCard
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
            SpeakItAnalytics.track(.paywallViewed(context: context.analyticsContext))
            await subscriptionStore.prepare()
            if let firstID = subscriptionStore.recommendedProduct?.id {
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
        switch context {
        case .freeLimit:
            return "You’ve used your \(FreePlanAllowance.lifetimeCaptureLimit) free captures."
        case .firstCapture:
            return "Your thought is where it belongs."
        case .runningLow:
            return "\(subscriptionStore.freeCapturesRemaining) free \(captureNoun) left."
        case .account:
            return "More clarity from every thought."
        }
    }

    private var captureNoun: String {
        subscriptionStore.freeCapturesRemaining == 1 ? "capture" : "captures"
    }

    /// Kept as one clause so the number, the noun and the verb cannot disagree.
    /// `ProMoment` guarantees at least four remaining at `.firstCapture`, but a
    /// changed threshold should not be able to produce "1 free captures are".
    private var remainingCapturesClause: String {
        let remaining = subscriptionStore.freeCapturesRemaining
        return remaining == 1
            ? "1 free capture is still waiting for you"
            : "\(remaining) free captures are still waiting for you"
    }

    private var heroDetail: String {
        if subscriptionStore.hasProAccess {
            return "Speak It Pro is active on this Apple Account."
        }
        switch context {
        case .freeLimit:
            return "Everything you saved is still yours. You’ve used all \(FreePlanAllowance.lifetimeCaptureLimit) free captures — upgrade for unlimited capture."
        case .firstCapture:
            return "That is the whole app: you speak, and it lands in Today or Memory. \(remainingCapturesClause) — Pro is here whenever you want the counting to stop."
        case .runningLow:
            return "No rush, and nothing you saved is ever locked. Pro removes the lifetime capture limit whenever you are ready."
        case .account:
            return "Try the complete experience with \(FreePlanAllowance.lifetimeCaptureLimit) free captures. They never expire, and no subscription is needed. Choose Pro when you want unlimited capture."
        }
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
                if let annual = subscriptionStore.annualProduct, showsLaunchOffer(for: annual) {
                    summerSaleHeader
                }
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

            if SummerLaunchSale.isActive() {
                summerSaleHeader
            }

            developerPlanButton(
                .annual,
                title: "Annual",
                price: "$14.99 / year",
                regularPrice: "$29.99 / year",
                detail: "$1.25 a month"
            )
            developerPlanButton(
                .monthly,
                title: "Monthly",
                price: "$2.99 / month",
                regularPrice: nil,
                detail: "Flexible monthly billing"
            )
        }
    }

    private func developerPlanButton(
        _ plan: DeveloperTestPlan,
        title: String,
        price: String,
        regularPrice: String?,
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
                    VStack(alignment: .trailing, spacing: 3) {
                        if let regularPrice, SummerLaunchSale.isActive() {
                            Text("Regularly \(regularPrice)")
                                .font(.caption)
                                .foregroundStyle(Color.speakMuted)
                                .strikethrough()
                        }
                        Text(price)
                            .font(.subheadline.weight(.semibold))
                    }
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
                    if isAnnual && subscriptionStore.annualIsBestValue {
                        bestValueBadge
                    }
                }

                // Swaps axis rather than forcing a width. `fixedSize(horizontal:)`
                // on the price column made it take its full unwrapped width and
                // never compress, so at large Dynamic Type the description was
                // crushed toward nothing and the price itself was clipped off
                // the trailing edge of the card. `ViewThatFits` keeps the
                // side-by-side layout wherever it still fits and stacks below it
                // when it does not.
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .bottom, spacing: 12) {
                        planCaption(isAnnual: isAnnual)
                        Spacer(minLength: 8)
                        priceColumn(product: product, isAnnual: isAnnual, alignment: .trailing)
                            .fixedSize(horizontal: true, vertical: false)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        planCaption(isAnnual: isAnnual)
                        priceColumn(product: product, isAnnual: isAnnual, alignment: .leading)
                    }
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
            planAccessibilityLabel(product: product, isAnnual: isAnnual)
        )
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
    }

    private func planCaption(isAnnual: Bool) -> some View {
        Text(isAnnual ? "One payment each year" : "Flexible monthly billing")
            .font(.footnote)
            .foregroundStyle(Color.speakMuted)
    }

    @ViewBuilder
    private func priceColumn(
        product: Product,
        isAnnual: Bool,
        alignment: HorizontalAlignment
    ) -> some View {
        VStack(alignment: alignment, spacing: 3) {
            if isAnnual,
               showsLaunchOffer(for: product) {
                Text("Standard price \(SummerLaunchSale.regularAnnualUSPrice)")
                    .font(.caption2)
                    .foregroundStyle(Color.speakMuted)
                    .strikethrough()
            }
            Text(product.displayPrice)
                .font(.body.weight(.semibold))
            Text(isAnnual ? "per year" : "per month")
                .font(.caption)
                .foregroundStyle(Color.speakMuted)
        }
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

    private var summerSaleHeader: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Text("SUMMER LAUNCH SALE")
                    .font(.caption2.weight(.bold))
                    .tracking(1.1)
                Text("50% OFF ANNUAL")
                    .font(.caption2.weight(.bold))
                    .tracking(0.4)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .foregroundStyle(Color.speakInverseInk)
                    .background(Color.speakInverseSurface, in: Capsule())
            }
            Text("Annual launch pricing ends \(SummerLaunchSale.endDateText).")
                .font(.footnote)
                .foregroundStyle(Color.speakMuted)
        }
        .accessibilityElement(children: .combine)
    }

    private func planAccessibilityLabel(product: Product, isAnnual: Bool) -> String {
        guard isAnnual, showsLaunchOffer(for: product) else {
            return "\(isAnnual ? "Annual" : "Monthly"), \(product.displayPrice) per \(isAnnual ? "year" : "month")"
        }
        let value = subscriptionStore.annualIsBestValue ? ", best value" : ""
        return "Annual, summer launch price \(product.displayPrice) per year, standard annual price \(SummerLaunchSale.regularAnnualUSPrice), 50 percent off\(value)"
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
            // The developer twin of this button already carries the identifier;
            // the real one did not, so the screen's primary call to action was
            // reachable in tests only by its visible copy — which is the thing
            // most likely to change.
            .accessibilityIdentifier("pro.purchase")
            .disabled(selectedProduct == nil || subscriptionStore.isPurchasing)
            .opacity(selectedProduct == nil ? 0.45 : 1)

            if let selectedProduct {
                Text(
                    purchaseDetail(for: selectedProduct)
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

            // Identifier after the style, the way `pro.purchase` and
            // `pro.redeem-code` do it. `.speakIt` rebuilds the button's
            // accessibility element, so an identifier applied above it does not
            // survive into the tree.
            Button(dismissTitle) { dismiss() }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color.speakInk)
                .frame(minHeight: 44)
                .buttonStyle(.speakIt)
                .accessibilityIdentifier("pro.dismiss")
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
                         : "Choose Monthly · $2.99")
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

            Text(developerPurchaseDetail)
                .font(.caption)
                .foregroundStyle(Color.speakMuted)

            Button(dismissTitle) { dismiss() }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color.speakInk)
                .frame(minHeight: 44)
                .buttonStyle(.speakIt)
                .accessibilityIdentifier("pro.dismiss")
        }
    }

    private var developerPurchaseDetail: String {
        guard selectedDeveloperPlan == .annual else {
            return "$2.99 per month. Auto-renews until cancelled."
        }
        if SummerLaunchSale.isActive() {
            return "Summer launch price · $14.99 per year. Offer ends \(SummerLaunchSale.endDateText). Auto-renews until cancelled."
        }
        return "$29.99 per year. Auto-renews until cancelled."
    }
#endif

    /// The refusal, worded the same whichever plan source is rendering.
    ///
    /// At the wall there is nothing left to continue with, so "Not now" is the
    /// honest word. Everywhere else — including the two moments Speak It raises
    /// itself — free captures remain and the screen has to say so, or a sheet
    /// nobody asked for reads as a demand.
    private var dismissTitle: String {
        context == .freeLimit ? "Not now" : "Continue using Speak It free"
    }

    private var purchaseButtonTitle: String {
        // Customer- and reviewer-facing. "in this build" is our word for
        // our problem, on the screen that asks them to pay.
        guard let selectedProduct else { return "Pro is being prepared" }
        return selectedProduct.id == SubscriptionStore.annualProductID
            ? "Choose Annual · \(selectedProduct.displayPrice)"
            : "Choose Monthly · \(selectedProduct.displayPrice)"
    }

    private func showsLaunchOffer(for product: Product) -> Bool {
        product.id == SubscriptionStore.annualProductID
            && SummerLaunchSale.isActive()
            && SummerLaunchSale.matchesLaunchPrice(
                price: product.price,
                currencyCode: product.priceFormatStyle.currencyCode
            )
    }

    private func purchaseDetail(for product: Product) -> String {
        let period = product.id == SubscriptionStore.annualProductID ? "year" : "month"
        if product.id == SubscriptionStore.annualProductID,
           showsLaunchOffer(for: product) {
            // The deadline applies to joining the offer. Price preservation
            // must be configured separately in App Store Connect.
            return "Summer launch price · \(product.displayPrice) per year. Offer ends \(SummerLaunchSale.endDateText). Auto-renews until cancelled."
        }
        return "\(product.displayPrice) per \(period). Auto-renews until cancelled."
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

    private var referralCard: some View {
        NavigationLink {
            ReferralProgramView()
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                Label("Give a month. Get a month.", systemImage: "gift.fill")
                    .font(.headline)
                    .foregroundStyle(Color.speakInk)
                Text("Your friend gets one month of Pro free. After Apple verifies that they joined, you get one too.")
                    .font(.subheadline)
                    .foregroundStyle(Color.speakMuted)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Invite a Friend")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.speakInk)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.speakIt)
        .padding(18)
        .background(Color.speakSurface, in: RoundedRectangle(cornerRadius: 22))
        .overlay {
            RoundedRectangle(cornerRadius: 22)
                .stroke(Color.speakDivider, lineWidth: 1)
        }
        .accessibilityIdentifier("pro.referrals")
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
            Button("How data is used") { showsPrivacy = true }
                .buttonStyle(.speakIt)
            // A subscription screen has to carry a link to the policy itself,
            // not only to an in-app summary of it. The Privacy button above
            // opens the explainer, which now ends in this same link.
            Link(destination: SpeakItLegal.privacyPolicy) {
                Text("Privacy Policy")
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            Link(destination: SpeakItLegal.termsOfUse) {
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
                    Text("Pro removes the lifetime capture limit, so you can keep speaking without counting.")
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
