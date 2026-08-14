import SwiftData
import SwiftUI

private enum AppDestination: Hashable {
    case today
    case library
}

private enum FullScreenDestination: String, Equatable, Identifiable {
    case welcome
    case captureVoice
    case captureText
    case captureAnywhereSetup

    var id: String { rawValue }
}

struct RootView: View {
    @Environment(\.thoughtRepository) private var repository
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var subscriptionStore: SubscriptionStore
    @Query(
        filter: #Predicate<CapturedItem> { item in
            item.isArchived == false &&
                item.completedAt == nil &&
                item.needsClarification == false &&
                (item.itemTypeRawValue == "note" ||
                    item.itemTypeRawValue == "idea" ||
                    item.itemTypeRawValue == "unclear")
        }
    ) private var openMemoryItems: [CapturedItem]
    @StateObject private var quickActionRouter = QuickActionRouter.shared
    @AppStorage("SpeakIt.hasCompletedWelcome") private var hasCompletedWelcome = false
    @AppStorage("SpeakIt.appearance") private var appearanceRawValue = SpeakItAppearance.system.rawValue

    @State private var selectedDestination: AppDestination = RootView.initialDestination
    @State private var isDockVisible = true
    @State private var showsSetupAfterFirstCapture = false
    @State private var captureAutoStartsVoice = false
    @State private var captureOpenedFromExternalSource = false
    @State private var captureInitialText = ""
    @State private var showsFreeLimit = false
    @State private var returnsToSetupAfterExternalCapture = false
    @State private var hasPerformedMaintenance = false
    @State private var isImportingSharedCaptures = false
    @State private var sharedImportNotice: String?
    @State private var fullScreenDestination: FullScreenDestination? = RootView.initialFullScreenDestination
    @State private var hasTrackedInitialScreen = false

    private var appearance: SpeakItAppearance {
        SpeakItAppearance(rawValue: appearanceRawValue) ?? .system
    }

    private static var initialDestination: AppDestination {
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--show-memory") {
            return .library
        }
#endif
        return .today
    }

    private static var initialFullScreenDestination: FullScreenDestination? {
#if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--ui-testing-reset") {
            return arguments.contains("--ui-testing-skip-welcome") ? nil : .welcome
        }
#endif
        return UserDefaults.standard.bool(forKey: "SpeakIt.hasCompletedWelcome") ? nil : .welcome
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                switch selectedDestination {
                case .today:
                    NavigationStack {
                        TodayView(
                            onCapture: { presentCapture() },
                            onDockVisibilityChange: setDockVisibility
                        )
                    }
                case .library:
                    NavigationStack {
                        LibraryView(
                            onCapture: { presentCapture() },
                            onDockVisibilityChange: setDockVisibility
                        )
                    }
                }
            }
            // Both destinations have a NavigationStack at their root. Give
            // each stack an explicit identity so SwiftUI never reuses a Today
            // row, swipe-action layer, or scroll offset while showing Memory.
            .id(selectedDestination)
            .safeAreaInset(edge: .bottom) {
                // Keep the scroll viewport stable while the dock moves. Changing
                // this inset during a drag made long lists visibly jump.
                Color.clear.frame(height: 86)
            }

            captureDock
                .offset(y: isDockVisible ? 0 : 116)
                .opacity(isDockVisible ? 1 : 0)
                .allowsHitTesting(isDockVisible)
                .animation(.smooth(duration: 0.24), value: isDockVisible)
        }
        .tint(.speakInk)
        .preferredColorScheme(appearance.preferredColorScheme)
        .overlay(alignment: .top) {
            if let sharedImportNotice {
                Label(sharedImportNotice, systemImage: "checkmark")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.speakInverseInk)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 48)
                    .background(Color.speakInverseSurface, in: Capsule())
                    .shadow(color: .black.opacity(0.16), radius: 16, y: 8)
                    .padding(.top, 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(20)
            }
        }
        .fullScreenCover(item: $fullScreenDestination) { destination in
            switch destination {
            case .welcome:
                WelcomeView(
                    onFirstCapture: beginFirstCapture,
                    onSkip: { completeWelcome() },
                    onLoadExamples: loadTestExamples
                )
            case .captureVoice:
                captureView(initialMode: .voice)
            case .captureText:
                captureView(initialMode: .text)
            case .captureAnywhereSetup:
                CaptureAnywhereSetupView(showsOnboardingProgress: true)
            }
        }
        .sheet(isPresented: $showsFreeLimit) {
            SpeakItProView(context: .freeLimit)
        }
        .task {
            if !hasTrackedInitialScreen {
                hasTrackedInitialScreen = true
                SpeakItAnalytics.track(.screenViewed(
                    selectedDestination == .today ? .today : .memory
                ))
            }
            handleQuickAction(quickActionRouter.pendingRequest)
            guard !hasPerformedMaintenance else { return }
            hasPerformedMaintenance = true
#if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--load-examples"),
               let repository {
                _ = try? repository.loadSampleData(referenceDate: .now)
            }
            if ProcessInfo.processInfo.arguments.contains("--load-memory-examples"),
               let repository,
               !UserDefaults.standard.bool(forKey: "SpeakIt.hasLoadedMemoryQAExamples") {
                let referenceDate = Date.now
                for (index, text) in SampleDataLibrary.memoryExamples.enumerated() {
                    _ = try? await repository.createCaptureResult(
                        text: text,
                        source: .sample,
                        createdAt: referenceDate.addingTimeInterval(Double(index) / 100),
                        schedulesReminders: false
                    )
                }
                UserDefaults.standard.set(true, forKey: "SpeakIt.hasLoadedMemoryQAExamples")
            }
            if ProcessInfo.processInfo.arguments.contains("--load-today-examples"),
               let repository,
               !UserDefaults.standard.bool(forKey: "SpeakIt.hasLoadedTodayQAExamples") {
                let referenceDate = Date.now
                for (index, text) in SampleDataLibrary.todayExamples.enumerated() {
                    _ = try? await repository.createCaptureResult(
                        text: text,
                        source: .sample,
                        createdAt: referenceDate.addingTimeInterval(Double(index) / 100),
                        schedulesReminders: false
                    )
                }
                UserDefaults.standard.set(true, forKey: "SpeakIt.hasLoadedTodayQAExamples")
            }
#endif
            // Keep database recovery and reminder reconciliation out of the
            // App Intent cold-start path so a hardware trigger can reach the microphone
            // with as little main-actor work as possible.
            await Task.yield()
            CaptureDraftStore.pruneEmptyTextDrafts()
            await recoverInterruptedAudioDrafts()
            repository?.recoverUnorganizedCaptures()
            repository?.recoverInterruptedCaptureDraft()
            repository?.reconcileSharedTodayActions()
            repository?.reconcilePendingReminders()
            // Regions are crossed while the app is in the background, so the
            // handler has to be installed before monitoring resumes rather than
            // when a view happens to appear.
            LocationReminderMonitor.shared.onRegionEvent = { itemID, event in
                Task { @MainActor in
                    await repository?.handleLocationTrigger(itemID: itemID, event: event)
                }
            }
            repository?.reconcileLocationReminders()
            _ = await repository?.reconcileICloudSync()
            await importSharedCaptures()
        }
        .onChange(of: quickActionRouter.pendingRequest) { _, request in
            handleQuickAction(request)
        }
        .onChange(of: selectedDestination) { _, destination in
            SpeakItAnalytics.track(.screenViewed(
                destination == .today ? .today : .memory
            ))
        }
        .onOpenURL(perform: handleDeepLink)
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            repository?.reconcileSharedTodayActions()
            // Self-healing pass. SwiftData and UNUserNotificationCenter are two
            // stores that can fall out of step — a scheduling call that failed,
            // a crash between saving and scheduling, notifications revoked in
            // Settings, or requests orphaned by an edit. Rebuilding the pending
            // set from the saved items on every foreground repairs all of them
            // without the app needing to know which one happened.
            repository?.reconcilePendingReminders()
            // The same argument, for the same reason, against CoreLocation:
            // regions can be orphaned by an edit, stranded by a delete that
            // happened while the app was closed, invalidated by a changed Home
            // address, or stopped by a permission revoked in Settings.
            repository?.reconcileLocationReminders()
            Task {
                _ = await repository?.reconcileICloudSync()
                await importSharedCaptures()
            }
        }
        // Location permission changed in Settings while the app was open. The
        // reminders have not changed meaning, so nothing is deleted — the
        // monitored set is simply rebuilt for whatever access now exists.
        .onReceive(
            NotificationCenter.default.publisher(
                for: LocationReminderMonitor.authorizationDidChangeNotification
            )
        ) { _ in
            repository?.reconcileLocationReminders()
        }
        // Home or Work moved. Every reminder that says "home" still says "home";
        // only where that resolves to has changed, so re-resolving is a
        // reconcile rather than an edit to any of them.
        .onReceive(NotificationCenter.default.publisher(for: SavedPlaceStore.didChangeNotification)) { _ in
            repository?.reconcileLocationReminders()
        }
        .onReceive(NotificationCenter.default.publisher(for: .speakItMemoryMetadataDidChange)) { _ in
            ICloudSyncState.markLocalChange()
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(500))
                _ = await repository?.reconcileICloudSync()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .speakItUseTestPrompt)) { notice in
            guard let text = notice.object as? String, !text.isEmpty else { return }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(320))
                presentCapture(initialMode: .text, initialText: text, entry: .testPrompt)
            }
        }
    }

    private var captureDock: some View {
        HStack(spacing: 8) {
            destinationButton(title: "Today", destination: .today)

            Button {
                presentCapture()
            } label: {
                ZStack {
                    Circle()
                        .fill(Color.speakInverseSurface)
                        .frame(width: 58, height: 58)
                        .shadow(color: .black.opacity(0.14), radius: 14, y: 8)

                    Image(systemName: "waveform")
                        .font(.system(size: 21, weight: .medium))
                        .foregroundStyle(Color.speakInverseInk)
                }
            }
            .buttonStyle(.speakIt)
            .accessibilityLabel("Capture a thought")
            .accessibilityHint("Opens the Memory Pulse with a typing option")
            .accessibilityIdentifier("dock.capture")
            .frame(maxWidth: .infinity)

            destinationButton(
                title: "Memory",
                destination: .library,
                badgeCount: openMemoryItems.count
            )
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.speakSurface, in: RoundedRectangle(cornerRadius: 25, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 25, style: .continuous)
                .stroke(Color.speakDivider, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.09), radius: 22, y: 10)
        .padding(.horizontal, 22)
        .padding(.bottom, 8)
    }

    private func destinationButton(
        title: String,
        destination: AppDestination,
        badgeCount: Int? = nil
    ) -> some View {
        Button {
            guard selectedDestination != destination else { return }
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                selectedDestination = destination
                isDockVisible = true
            }
        } label: {
            HStack(spacing: 6) {
                Text(title)
                    .font(.subheadline.weight(.medium))

                if let badgeCount, badgeCount > 0 {
                    Text(badgeCount > 99 ? "99+" : "\(badgeCount)")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Color.speakInverseInk)
                        .padding(.horizontal, badgeCount > 9 ? 6 : 0)
                        .frame(minWidth: 19, minHeight: 19)
                        .background(Color.speakInverseSurface, in: Capsule())
                        .accessibilityHidden(true)
                }
            }
            .foregroundStyle(
                selectedDestination == destination ? Color.speakInk : Color.speakMuted
            )
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.speakIt)
        .accessibilityLabel(
            badgeCount.map { "\(title), \($0) open" } ?? title
        )
        .accessibilityIdentifier("dock.\(title.lowercased())")
        .accessibilityAddTraits(selectedDestination == destination ? .isSelected : [])
    }

    private func beginFirstCapture() {
        showsSetupAfterFirstCapture = true
        completeWelcome(analyticsPath: .onboarding)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            presentCapture(entry: .onboarding)
        }
    }

    private func completeWelcome(analyticsPath: AnalyticsCaptureEntry = .dock) {
        SpeakItAnalytics.track(.onboardingCompleted(path: analyticsPath))
        hasCompletedWelcome = true
        fullScreenDestination = nil
    }

    private func loadTestExamples() {
        completeWelcome(analyticsPath: .testPrompt)
        selectedDestination = .today
        isDockVisible = true

        Task { @MainActor in
            _ = await ReminderScheduler.requestNotificationAuthorizationIfNeeded()
            guard let repository else { return }
            do {
                let result = try repository.loadSampleData(referenceDate: .now)
                let notice = result.addedAnything
                    ? "\(result.addedItemCount) test examples ready"
                    : "Test examples already loaded"
                withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
                    sharedImportNotice = notice
                }
                try? await Task.sleep(for: .seconds(3))
                withAnimation(.easeOut(duration: 0.2)) {
                    if sharedImportNotice == notice { sharedImportNotice = nil }
                }
            } catch {
                let notice = "Examples couldn’t be loaded"
                withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
                    sharedImportNotice = notice
                }
            }
        }
    }

    private func presentCapture(entry: AnalyticsCaptureEntry = .dock) {
        presentCapture(
            initialMode: .voice,
            autoStartsVoiceCapture: true,
            entry: entry
        )
    }

    private func presentCapture(
        initialMode: CaptureInitialMode,
        autoStartsVoiceCapture: Bool = false,
        fromExternalSource: Bool = false,
        initialText: String = "",
        entry: AnalyticsCaptureEntry = .dock
    ) {
        guard fullScreenDestination == nil else { return }
        subscriptionStore.refreshFreeAllowance()
        guard subscriptionStore.canCreateCapture else {
            SpeakItAnalytics.track(.freeLimitReached(used: subscriptionStore.freeCapturesUsed))
            showsFreeLimit = true
            return
        }
        SpeakItAnalytics.track(.captureStarted(
            mode: initialMode == .text ? .text : .voice,
            entry: entry
        ))
        isDockVisible = true
        captureAutoStartsVoice = autoStartsVoiceCapture
        captureOpenedFromExternalSource = fromExternalSource
        captureInitialText = initialText
        fullScreenDestination = initialMode == .text ? .captureText : .captureVoice
    }

    private func setDockVisibility(_ visible: Bool) {
        guard isDockVisible != visible else { return }
        withAnimation(.easeOut(duration: 0.22)) {
            isDockVisible = visible
        }
    }

    @ViewBuilder
    private func captureView(initialMode: CaptureInitialMode) -> some View {
        CaptureView(
            initialMode: initialMode,
            autoStartsVoiceCapture: captureAutoStartsVoice,
            initialText: captureInitialText
        ) {
            if captureOpenedFromExternalSource {
                CaptureActivationStore.markSucceeded()
            }
            selectedDestination = .today
            isDockVisible = true
            fullScreenDestination = nil
            captureAutoStartsVoice = false
            captureOpenedFromExternalSource = false
            captureInitialText = ""

            if returnsToSetupAfterExternalCapture {
                returnsToSetupAfterExternalCapture = false
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(420))
                    fullScreenDestination = .captureAnywhereSetup
                }
                return
            }

            guard showsSetupAfterFirstCapture else { return }
            showsSetupAfterFirstCapture = false
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(450))
                fullScreenDestination = .captureAnywhereSetup
            }
        }
    }

    private func handleQuickAction(_ request: QuickActionRouter.Request?) {
        guard let request else { return }
        defer { quickActionRouter.consume(request) }

        if fullScreenDestination == .captureVoice || fullScreenDestination == .captureText {
            return
        }

        subscriptionStore.refreshFreeAllowance()
        guard subscriptionStore.canCreateCapture else {
            SpeakItAnalytics.track(.freeLimitReached(used: subscriptionStore.freeCapturesUsed))
            showsFreeLimit = true
            return
        }

        hasCompletedWelcome = true
        showsSetupAfterFirstCapture = false
        selectedDestination = .today
        isDockVisible = true
        captureAutoStartsVoice = request.autoStartsVoiceCapture
        captureOpenedFromExternalSource = true
        SpeakItAnalytics.track(.captureStarted(
            mode: request.initialMode == .text ? .text : .voice,
            entry: .quickAction
        ))
        fullScreenDestination = request.initialMode == .text ? .captureText : .captureVoice
    }

    private func handleDeepLink(_ url: URL) {
        guard url.scheme?.lowercased() == "speakit" else { return }

        if url.host?.lowercased() == "setup" {
            hasCompletedWelcome = true
            selectedDestination = .today
            isDockVisible = true
            fullScreenDestination = .captureAnywhereSetup
            return
        }

        // The Lock Screen widget only ever opens Today. It must not skip welcome
        // and must not start a capture the user did not ask for.
        if url.host?.lowercased() == "today" {
            guard hasCompletedWelcome else { return }
            fullScreenDestination = nil
            selectedDestination = .today
            isDockVisible = true
            return
        }

        guard url.host?.lowercased() == "capture" else { return }

        subscriptionStore.refreshFreeAllowance()
        guard subscriptionStore.canCreateCapture else {
            SpeakItAnalytics.track(.freeLimitReached(used: subscriptionStore.freeCapturesUsed))
            showsFreeLimit = true
            return
        }

        CaptureActivationStore.markInvoked()
        let isReturningFromSetup = fullScreenDestination == .captureAnywhereSetup

        hasCompletedWelcome = true
        showsSetupAfterFirstCapture = false
        returnsToSetupAfterExternalCapture = isReturningFromSetup
        selectedDestination = .today
        isDockVisible = true
        captureAutoStartsVoice = true
        captureOpenedFromExternalSource = true
        SpeakItAnalytics.track(.captureStarted(mode: .voice, entry: .deepLink))
        fullScreenDestination = .captureVoice
    }

    private func importSharedCaptures() async {
        guard !isImportingSharedCaptures, let repository else { return }
        isImportingSharedCaptures = true
        defer { isImportingSharedCaptures = false }

        var importedCount = 0
        for pending in SharedCaptureInbox.pending() {
            subscriptionStore.refreshFreeAllowance()
            guard subscriptionStore.canCreateCapture else { break }
            // Clamped again on read: `captureText` appends the source URL after
            // the extension's own clamp, and a queued file may predate it.
            let text = CaptureTextLimit.clamp(
                pending.payload.captureText
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            )
            guard !text.isEmpty else {
                SharedCaptureInbox.remove(at: pending.url)
                continue
            }

            do {
                let result = try await repository.createCaptureResult(
                    text: text,
                    source: .shareSheet,
                    createdAt: pending.payload.createdAt,
                    schedulesReminders: true
                )
                SharedCaptureInbox.remove(at: pending.url)
                subscriptionStore.recordSuccessfulCapture()
                SpeakItAnalytics.track(.captureSaved(
                    source: .shareSheet,
                    itemCount: result.itemCount,
                    needsReviewCount: result.needsReviewCount,
                    plan: subscriptionStore.hasProAccess ? .pro : .free
                ))
                importedCount += 1
            } catch {
                // Leave this and later files in the shared inbox. The next
                // activation retries them without duplicating completed work.
                break
            }
        }

        guard importedCount > 0 else { return }
        let notice = importedCount == 1
            ? "Shared thought remembered"
            : "\(importedCount) shared thoughts remembered"
        withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
            sharedImportNotice = notice
        }
        try? await Task.sleep(for: .seconds(2.8))
        withAnimation(.easeOut(duration: 0.2)) {
            if sharedImportNotice == notice { sharedImportNotice = nil }
        }
    }

    private func recoverInterruptedAudioDrafts() async {
        guard let repository else { return }
        var recoveredCount = 0

        for draft in CaptureDraftStore.recoverableAudioDrafts() {
            CaptureDraftStore.markProcessing(id: draft.id)
            do {
                let recoveredText = try await CaptureAudioRecovery.transcribe(draft)
                let result = try await repository.createCaptureResult(
                    text: recoveredText,
                    source: draft.captureSource,
                    createdAt: draft.startedAt,
                    schedulesReminders: true
                )
                CaptureDraftStore.clear(id: draft.id)
                subscriptionStore.recordSuccessfulCapture()
                SpeakItAnalytics.track(.captureSaved(
                    source: .recovery,
                    itemCount: result.itemCount,
                    needsReviewCount: result.needsReviewCount,
                    plan: subscriptionStore.hasProAccess ? .pro : .free
                ))
                recoveredCount += 1
            } catch {
                CaptureDraftStore.markFailed(
                    id: draft.id,
                    message: error.localizedDescription
                )
            }
        }

        guard recoveredCount > 0 else { return }
        let notice = recoveredCount == 1
            ? "Interrupted capture recovered"
            : "\(recoveredCount) interrupted captures recovered"
        withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
            sharedImportNotice = notice
        }
        try? await Task.sleep(for: .seconds(3.2))
        withAnimation(.easeOut(duration: 0.2)) {
            if sharedImportNotice == notice { sharedImportNotice = nil }
        }
    }
}

struct RootView_Previews: PreviewProvider {
    @MainActor
    static var previews: some View {
        let preview = PreviewData.make()
        return RootView()
            .modelContainer(preview.container)
            .environment(\.thoughtRepository, preview.repository)
            .environmentObject(SubscriptionStore())
    }
}
