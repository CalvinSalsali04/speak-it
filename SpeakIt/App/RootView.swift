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
    case firstCaptureGuide
    case captureAnywhereSetup
    case tutorialFinished

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
    @Query(
        filter: #Predicate<CaptureSession> { session in
            session.captureSourceRawValue == "tutorial"
        }
    ) private var tutorialSessions: [CaptureSession]

    /// The `@Query` predicate above is a coarse database pre-filter and nothing
    /// more. `#Predicate` cannot call the authorization-aware membership check,
    /// so it re-states Memory membership in raw type strings and cannot know
    /// that a place-blocked item belongs in review instead. Narrowing the result
    /// here is what keeps this badge agreeing with the Memory tab it labels —
    /// without it the dock advertised "Memory 1" over an empty Memory screen.
    private var memoryBadgeCount: Int {
        let authorization = LocationReminderMonitor.shared.authorization
        return openMemoryItems.filter {
            $0.belongsInMemory(authorization: authorization)
        }.count
    }

    @StateObject private var quickActionRouter = QuickActionRouter.shared
    @AppStorage("SpeakIt.hasCompletedWelcome") private var hasCompletedWelcome = false
    @AppStorage("SpeakIt.shouldResumeFirstCaptureGuide")
    private var shouldResumeFirstCaptureGuide = false
    @AppStorage("SpeakIt.firstCapturePlacementSummary")
    private var firstCapturePlacementSummaryRawValue = ""
    @AppStorage("SpeakIt.firstCaptureTutorialStep")
    private var firstCaptureTutorialStep = 0
    @AppStorage(FirstRunTutorialKeys.phase)
    private var tutorialPhaseRawValue = FirstRunTutorialPhase.inactive.rawValue
    @AppStorage(FirstRunTutorialKeys.actionItemID)
    private var tutorialActionItemIDRawValue = ""
    @AppStorage(FirstRunTutorialKeys.ideaItemID)
    private var tutorialIdeaItemIDRawValue = ""
    @AppStorage("SpeakIt.appearance") private var appearanceRawValue = SpeakItAppearance.firstInstallDefault.rawValue

    @State private var selectedDestination: AppDestination = RootView.initialDestination
    @State private var isDockVisible = true
    /// Bumped when the dock button for the destination already on screen is
    /// tapped again. The destination views watch it and pop their pushed
    /// screens, so tapping "Today" from inside the List lands on Today.
    @State private var popToRootSignal = 0
    @State private var destinationNavigationGeneration = 0
    @State private var showsSetupAfterFirstCapture = RootView.initialTutorialMission != nil
    @State private var captureAutoStartsVoice = false
    @State private var captureShowsGuidedExamples = RootView.initialTutorialMission != nil
    @State private var captureTutorialMission = RootView.initialTutorialMission
    @State private var captureOpenedFromExternalSource = false
    @State private var captureInitialText = ""
    @State private var capturePerformance: CapturePerformanceTrace?
    @State private var showsFreeLimit = false
    @State private var activeReferralCode: String?
    @State private var returnsToSetupAfterExternalCapture = false
    @State private var hasPerformedMaintenance = false
    @State private var isImportingSharedCaptures = false
    @State private var sharedImportNotice: String?
    @State private var fullScreenDestination: FullScreenDestination? = RootView.initialFullScreenDestination
    @State private var hasTrackedInitialScreen = false
    // A fresh identity per presentation. `.fullScreenCover(item:)` keys off
    // FullScreenDestination's stable rawValue id, so dismissing and
    // re-presenting the same capture case in quick succession can otherwise
    // let SwiftUI reuse the outgoing CaptureView's @State (typed text,
    // in-flight draft) instead of starting a clean session — see D-2 in
    // FINAL_RELEASE_AUDIT.md.
    @State private var captureSessionToken = UUID()

    private var appearance: SpeakItAppearance {
        SpeakItAppearance(rawValue: appearanceRawValue) ?? .firstInstallDefault
    }

    private static var initialDestination: AppDestination {
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--show-memory") {
            return .library
        }
#endif
        let phase = initialTutorialPhase
        if phase == .showPeople || phase == .showPerson || phase == .showIdea {
            return .library
        }
        return .today
    }

    private static var initialTutorialPhase: FirstRunTutorialPhase {
        FirstRunTutorialPhase(
            rawValue: UserDefaults.standard.string(forKey: FirstRunTutorialKeys.phase) ?? ""
        ) ?? .inactive
    }

    private static var initialTutorialMission: TutorialCaptureMission? {
        initialTutorialPhase.mission
    }

    private static var initialFullScreenDestination: FullScreenDestination? {
#if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--show-capture-anywhere") {
            return .captureAnywhereSetup
        }
        if arguments.contains("--show-first-capture-guide") {
            return .firstCaptureGuide
        }
        if arguments.contains("--ui-testing-reset") {
            return arguments.contains("--ui-testing-skip-welcome") ? nil : .welcome
        }
#endif
        let defaults = UserDefaults.standard
        switch initialTutorialPhase {
        case .captureAction, .captureIdea:
            return .captureVoice
        case .readiness:
            return .firstCaptureGuide
        case .complete:
            return .tutorialFinished
        case .showToday, .showPeople, .showPerson, .showIdea:
            return nil
        case .inactive:
            break
        }
        if !defaults.bool(forKey: "SpeakIt.hasCompletedWelcome") {
            return .welcome
        }
        if defaults.bool(forKey: "SpeakIt.shouldResumeFirstCaptureGuide") {
            return .firstCaptureGuide
        }
        return nil
    }

    var body: some View {
        // A real layout row rather than an overlay or a safe-area inset. Today
        // and Memory hide their navigation bars, and both of those approaches
        // let their scroll content start underneath the banner instead of below
        // it — the screen header stayed permanently half-covered, and on a
        // pushed Memory screen the Back button went with it.
        VStack(spacing: 0) {
            if let inAppTutorialStep {
                TutorialBanner(step: inAppTutorialStep, onExit: endTutorialEarly)
            }

            ZStack(alignment: .bottom) {
                Group {
                    switch selectedDestination {
                    case .today:
                        NavigationStack {
                            TodayView(
                                onCapture: { presentCapture() },
                                onDockVisibilityChange: setDockVisibility,
                                popToRootSignal: popToRootSignal,
                                tutorialSpotlight: tutorialSpotlight(for: .today),
                                onTutorialPrimary: advanceFromTodaySpotlight,
                                onEndTutorial: endTutorialEarly
                            )
                        }
                    case .library:
                        NavigationStack {
                            LibraryView(
                                onCapture: { presentCapture() },
                                onDockVisibilityChange: setDockVisibility,
                                popToRootSignal: popToRootSignal,
                                tutorialSpotlight: libraryTutorialSpotlight,
                                onTutorialPrimary: advanceFromLibrarySpotlight,
                                onEndTutorial: endTutorialEarly
                            )
                        }
                    }
                }
                // Both destinations have a NavigationStack at their root. Give
                // each stack an explicit identity so SwiftUI never reuses a Today
                // row, swipe-action layer, or scroll offset while showing Memory.
                .id(
                    selectedDestination == .today
                        ? "today-\(destinationNavigationGeneration)"
                        : "memory-\(destinationNavigationGeneration)"
                )

                captureDock
                    .offset(y: isDockVisible ? 0 : 116)
                    .opacity(isDockVisible ? 1 : 0)
                    // The capture screen's Type instead control occupies the same
                    // bottom region as this dock. Keep the covered dock out of the
                    // hit-test tree so it cannot swallow that first tap.
                    .allowsHitTesting(isDockVisible && fullScreenDestination == nil)
                    .animation(.smooth(duration: 0.24), value: isDockVisible)
            }
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
                    onSkip: { completeWelcome(analyticsPath: .exploreFirst) },
                    onLoadExamples: loadTestExamples
                )
            case .captureVoice:
                captureView(initialMode: .voice)
                    .id(captureSessionToken)
            case .captureText:
                captureView(initialMode: .text)
                    .id(captureSessionToken)
            case .firstCaptureGuide:
                SpeakItReadinessView(
                    isOnboarding: true,
                    tutorialStep: tutorialPhase.isActive ? .finishSetup : nil,
                    onFinished: finishTutorialReadiness
                )
            case .captureAnywhereSetup:
                CaptureAnywhereSetupView(
                    showsOnboardingProgress: true,
                    tutorialStep: tutorialPhase.isActive ? .captureAnywhere : nil,
                    onFinished: tutorialPhase == .readiness
                        ? continueFromCaptureAnywhereSetup
                        : nil
                )
            case .tutorialFinished:
                TutorialFinishedView(
                    remainingFreeCaptures: subscriptionStore.freeCapturesRemaining,
                    onContinue: completeTutorial
                )
            }
        }
        .sheet(isPresented: $showsFreeLimit) {
            SpeakItProView(context: .freeLimit)
        }
        .sheet(
            isPresented: Binding(
                get: { activeReferralCode != nil },
                set: { if !$0 { activeReferralCode = nil } }
            )
        ) {
            NavigationStack {
                ReferralProgramView(initialReferralCode: activeReferralCode)
            }
            .environmentObject(subscriptionStore)
        }
        .task {
            repairInterruptedTutorialIfNeeded()
            if hasCompletedWelcome,
               ReferralProgramConfiguration.isEnabled,
               let pendingCode = PendingReferralStore.code {
                activeReferralCode = pendingCode
            }
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
            if ProcessInfo.processInfo.arguments.contains("--load-marketing-examples"),
               let repository,
               !UserDefaults.standard.bool(forKey: "SpeakIt.hasLoadedMarketingExamples") {
                // Home first. A "when I get home" capture with no Home configured
                // is a blocked reminder, and a blocked reminder is exactly the
                // Needs review row these fixtures exist to avoid.
                if SavedPlaceStore.place(for: .home) == nil {
                    SavedPlaceStore.set(
                        SavedPlace(
                            latitude: 43.6532,
                            longitude: -79.3832,
                            label: "Home"
                        ),
                        for: .home
                    )
                }
                let referenceDate = Date.now
                var pinnable: [String: UUID] = [:]
                for (index, text) in (SampleDataLibrary.Marketing.today
                    + SampleDataLibrary.Marketing.memory).enumerated() {
                    let result = try? await repository.createCaptureResult(
                        text: text,
                        source: .sample,
                        createdAt: referenceDate.addingTimeInterval(Double(index) / 100),
                        schedulesReminders: false
                    )
                    if let item = result?.items.first {
                        pinnable[text] = item.id
                    }
                }
                for text in SampleDataLibrary.Marketing.pinned {
                    guard let id = pinnable[text] else { continue }
                    MemoryPinStore.setPinned(true, for: id)
                }
                UserDefaults.standard.set(true, forKey: "SpeakIt.hasLoadedMarketingExamples")
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
            // The word embedding behind person and role detection takes a few
            // hundred milliseconds to load the first time it is touched, and
            // that first touch used to land inside the first Memory render.
            Task.detached(priority: .utility) {
                PersonMentionResolver.preloadEmbedding()
                ActionabilityReader.preloadEmbedding()
            }
            CaptureDraftStore.pruneEmptyTextDrafts()
            CaptureDraftStore.pruneResolvedTombstones()
            await recoverInterruptedAudioDrafts()
            repository?.recoverUnorganizedCaptures()
            repository?.recoverInterruptedCaptureDraft()
            repository?.reconcileSharedTodayActions()
            repository?.reconcilePendingReminders()
            // Regions are crossed while the app is in the background, so the
            // handler has to be installed before monitoring resumes rather than
            // when a view happens to appear.
            LocationReminderMonitor.shared.onRegionEvent = {
                itemID, event, triggerRevision, regionIdentifier in
                Task { @MainActor in
                    await repository?.handleLocationTrigger(
                        itemID: itemID,
                        event: event,
                        triggerRevision: triggerRevision,
                        regionIdentifier: regionIdentifier
                    )
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
            //
            // A foreground is also the retry point for regions iOS refused. The
            // usual cause is no network reachability, which is exactly the kind
            // of thing that has often fixed itself by the next time the app is
            // opened, so the failures are forgotten first and the reminders get
            // a genuine second attempt rather than being told again.
            LocationReminderMonitor.shared.clearMonitoringFailures()
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
            // New access is a new chance for a region that was refused under the
            // old access, so those are retried too.
            LocationReminderMonitor.shared.clearMonitoringFailures()
            repository?.reconcileLocationReminders()
        }
        // iOS refused a region after accepting the call to monitor it. What the
        // app believes it is watching is now wrong, so the monitored set is
        // rebuilt — this one *without* clearing the failures, since retrying
        // here would only produce the same refusal and the same notification.
        .onReceive(
            NotificationCenter.default.publisher(
                for: LocationReminderMonitor.monitoringDidFailNotification
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
            // "Memory Pulse" is an internal codename that appears nowhere the
            // person can see, so VoiceOver was the only place it surfaced.
            .accessibilityHint("Opens capture. Starts listening, or switch to typing.")
            .accessibilityIdentifier("dock.capture")
            .frame(maxWidth: .infinity)

            destinationButton(
                title: "Memory",
                destination: .library,
                badgeCount: memoryBadgeCount
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
            guard selectedDestination != destination else {
                // Tapping the destination already on screen means "take me
                // back to it": pop whatever it has pushed — the List, a
                // Memory collection — instead of doing nothing.
                popToRootSignal += 1
                isDockVisible = true
                return
            }
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
        // Branches on the value, not on nil-ness: an empty Memory has a badge
        // count of zero, so this used to announce "Memory, 0 open" on every
        // pass through the dock.
        .accessibilityLabel(
            (badgeCount ?? 0) > 0 ? "\(title), \(badgeCount ?? 0) open" : title
        )
        .accessibilityIdentifier("dock.\(title.lowercased())")
        .accessibilityAddTraits(selectedDestination == destination ? .isSelected : [])
    }

    private func beginFirstCapture() {
        showsSetupAfterFirstCapture = true
        firstCaptureTutorialStep = 0
        firstCapturePlacementSummaryRawValue = ""
        tutorialActionItemIDRawValue = ""
        tutorialIdeaItemIDRawValue = ""
        setTutorialPhase(.captureAction)
        captureTutorialMission = .action
        SpeakItAnalytics.track(.onboardingStarted)
        // The iOS 26 speech model is a system-owned one-time asset. Begin that
        // work as soon as the person commits to voice so their first tutorial
        // recording does not silently use the older fallback recognizer.
        Task { await SpeechTranscriber.prepareEnhancedRecognition() }
        // Entering the capture surface is not a completed onboarding. Persist
        // success only after the first thought is actually saved so cancelling
        // permission or closing an empty capture can return to Welcome.
        fullScreenDestination = nil
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            presentCapture(entry: .onboarding)
        }
    }

    private func repairInterruptedTutorialIfNeeded() {
        switch tutorialPhase {
        case .showToday, .showPeople, .showPerson:
            let current = UUID(uuidString: tutorialActionItemIDRawValue).flatMap {
                tutorialItem($0)
            }
            if current.flatMap({ tutorialPersonName(for: $0) }) != nil { return }
            if let replacement = tutorialItems.first(where: {
                tutorialPersonName(for: $0) != nil
                    && ($0.itemType == .personFollowUp || $0.itemType.isActionable)
            }) {
                tutorialActionItemIDRawValue = replacement.id.uuidString
            } else {
                setTutorialPhase(.captureAction)
                captureTutorialMission = .action
                showsSetupAfterFirstCapture = true
                fullScreenDestination = .captureVoice
            }
        case .showIdea:
            guard let id = UUID(uuidString: tutorialIdeaItemIDRawValue),
                  tutorialSessions.contains(where: { session in
                      session.items.contains(where: { $0.id == id })
                  }) else {
                setTutorialPhase(.captureIdea)
                captureTutorialMission = .idea
                showsSetupAfterFirstCapture = true
                fullScreenDestination = .captureVoice
                return
            }
        default:
            break
        }
    }

    private var tutorialItems: [CapturedItem] {
        tutorialSessions.flatMap(\.items)
    }

    private func tutorialItem(_ id: UUID) -> CapturedItem? {
        tutorialItems.first(where: { $0.id == id })
    }

    private func tutorialPersonName(for item: CapturedItem) -> String? {
        let name = MemoryPersonNameResolver.name(for: item) ?? item.personName
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private func completeWelcome(analyticsPath: AnalyticsCaptureEntry = .dock) {
        if FirstRunTutorialPhase(rawValue: tutorialPhaseRawValue)?.isActive == true {
            endTutorialEarly()
            return
        }
        shouldResumeFirstCaptureGuide = false
        markWelcomeComplete(analyticsPath: analyticsPath)
        fullScreenDestination = nil
        if ReferralProgramConfiguration.isEnabled,
           let pendingCode = PendingReferralStore.code {
            Task { @MainActor in
                await Task.yield()
                activeReferralCode = pendingCode
            }
        }
    }

    private func markWelcomeComplete(analyticsPath: AnalyticsCaptureEntry) {
        guard !hasCompletedWelcome else { return }
        SpeakItAnalytics.track(.onboardingCompleted(path: analyticsPath))
        hasCompletedWelcome = true
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
        guard captureTutorialMission != nil || subscriptionStore.canCreateCapture else {
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
        // The first capture is the tutorial: the person tapped "Try it now"
        // and deserves something concrete to try.
        captureShowsGuidedExamples = entry == .onboarding || captureTutorialMission != nil
        captureOpenedFromExternalSource = fromExternalSource
        captureInitialText = initialText
        let source: AnalyticsCaptureSource = initialMode == .text ? .text : .voice
        capturePerformance = CapturePerformanceTrace(
            source: source,
            activatedAt: CapturePerformanceClock.now,
            recordsExternalActivation: fromExternalSource
        )
        captureSessionToken = UUID()
        fullScreenDestination = initialMode == .text ? .captureText : .captureVoice
    }

    private func setDockVisibility(_ visible: Bool) {
#if DEBUG
        // Layout UI tests need to exercise the bottom scroll limit with the
        // overlay present. Normal full swipes hide it before that state can be
        // measured, so this launch-only switch freezes visibility without
        // changing any production behavior.
        if ProcessInfo.processInfo.arguments.contains("--ui-testing-keep-dock-visible") {
            return
        }
#endif
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
            initialText: captureInitialText,
            performance: capturePerformance,
            autoDismissesSingleItemConfirmation: !showsSetupAfterFirstCapture,
            showsGuidedExamples: captureShowsGuidedExamples,
            tutorialMission: captureTutorialMission,
            onSaveSucceeded: markFirstCaptureSucceeded,
            onCancelled: handleCaptureCancelled,
            onTutorialEnded: endTutorialEarly
        ) {
            let completedTutorialPhase = tutorialPhase
            if captureOpenedFromExternalSource {
                CaptureActivationStore.markSucceeded()
            }
            if completedTutorialPhase == .showToday {
                selectedDestination = .today
            } else if completedTutorialPhase == .showIdea {
                selectedDestination = .library
            } else if showsSetupAfterFirstCapture {
                let placement = FirstCapturePlacementSummary(
                    storedValue: firstCapturePlacementSummaryRawValue
                ).primary
                selectedDestination = placement.belongsToMemory ? .library : .today
            } else {
                selectedDestination = .today
            }
            isDockVisible = true
            captureAutoStartsVoice = false
            captureShowsGuidedExamples = false
            captureOpenedFromExternalSource = false
            captureInitialText = ""
            capturePerformance = nil

            if returnsToSetupAfterExternalCapture {
                returnsToSetupAfterExternalCapture = false
                captureTutorialMission = nil
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(420))
                    fullScreenDestination = .captureAnywhereSetup
                }
                return
            }

            if completedTutorialPhase == .showToday || completedTutorialPhase == .showIdea {
                captureTutorialMission = nil
                showsSetupAfterFirstCapture = true
                fullScreenDestination = nil
                return
            }

            guard showsSetupAfterFirstCapture else {
                fullScreenDestination = nil
                return
            }
            showsSetupAfterFirstCapture = false
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(450))
                fullScreenDestination = .firstCaptureGuide
            }
        }
    }

    private func markFirstCaptureSucceeded(_ result: CaptureCreationResult) {
        guard showsSetupAfterFirstCapture else { return }
        if result.session.captureSource == .tutorial,
           tutorialPhase == .captureAction || captureTutorialMission == .action {
            // Returning early here means the practice did not produce what the
            // next three steps walk to. The capture screen stays up and offers
            // another try, so this is a pause rather than a dead end.
            guard let anchor = TutorialCaptureMission.action.satisfiedItem(in: result) else { return }
            tutorialActionItemIDRawValue = anchor.id.uuidString
            setTutorialPhase(.showToday)
            shouldResumeFirstCaptureGuide = false
            markWelcomeComplete(analyticsPath: .onboarding)
            return
        }
        if result.session.captureSource == .tutorial,
           tutorialPhase == .captureIdea || captureTutorialMission == .idea {
            guard let anchor = TutorialCaptureMission.idea.satisfiedItem(in: result) else { return }
            tutorialIdeaItemIDRawValue = anchor.id.uuidString
            setTutorialPhase(.showIdea)
            // The first mission is nested inside People. Rebuild Memory's
            // pushed destination so the second mission lands in Ideas instead
            // of leaving the old person profile above it.
            destinationNavigationGeneration += 1
            return
        }
        if captureTutorialMission == .quickAccess {
            return
        }
        // The durable save is the success boundary. Keep the receipt onscreen,
        // but make sure relaunching from it resumes after the completed action
        // instead of making the person repeat their first capture.
        firstCapturePlacementSummaryRawValue = FirstCapturePlacementSummary
            .make(from: result)
            .storedValue
        shouldResumeFirstCaptureGuide = true
        markWelcomeComplete(analyticsPath: .onboarding)
    }

    private func handleCaptureCancelled() {
        guard showsSetupAfterFirstCapture else { return }
        if captureTutorialMission == .idea {
            captureTutorialMission = nil
            setTutorialPhase(.showPerson)
            selectedDestination = .library
            return
        }
        if captureTutorialMission == .action {
            captureTutorialMission = nil
            cleanupTutorialData()
            setTutorialPhase(.inactive)
        }
        if captureTutorialMission == .quickAccess {
            captureTutorialMission = nil
            returnsToSetupAfterExternalCapture = false
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(520))
                fullScreenDestination = .captureAnywhereSetup
            }
            return
        }
        showsSetupAfterFirstCapture = false
        shouldResumeFirstCaptureGuide = false
        hasCompletedWelcome = false
        SpeakItAnalytics.track(.onboardingAbandoned)
        Task { @MainActor in
            // Let the full-screen capture finish its dismissal before asking
            // SwiftUI to present Welcome again. Presenting during the outgoing
            // animation can be dropped by the presentation coordinator.
            try? await Task.sleep(for: .milliseconds(520))
            guard !hasCompletedWelcome, fullScreenDestination == nil else { return }
            fullScreenDestination = .welcome
        }
    }

    private var tutorialPhase: FirstRunTutorialPhase {
        FirstRunTutorialPhase(rawValue: tutorialPhaseRawValue) ?? .inactive
    }

    /// The tutorial steps that happen on the person's real Today and Memory
    /// screens, where a teaching card sits directly against their own thoughts.
    /// Those are the steps that need something permanent on screen saying a
    /// tutorial is running; the rest own a full screen and say so themselves.
    private var inAppTutorialStep: TutorialStep? {
        switch tutorialPhase {
        case .showToday, .showPeople, .showPerson, .showIdea:
            return tutorialPhase.step
        default:
            return nil
        }
    }

    private var libraryTutorialSpotlight: TutorialSpotlight? {
        switch tutorialPhase {
        case .showPeople:
            return tutorialSpotlight(for: .people)
        case .showPerson:
            return tutorialSpotlight(for: .person)
        case .showIdea:
            return tutorialSpotlight(for: .idea)
        default:
            return nil
        }
    }

    private func tutorialSpotlight(
        for placement: TutorialSpotlightPlacement
    ) -> TutorialSpotlight? {
        let rawID: String
        switch placement {
        case .today:
            guard tutorialPhase == .showToday else { return nil }
            rawID = tutorialActionItemIDRawValue
        case .people:
            guard tutorialPhase == .showPeople else { return nil }
            rawID = tutorialActionItemIDRawValue
        case .person:
            guard tutorialPhase == .showPerson else { return nil }
            rawID = tutorialActionItemIDRawValue
        case .idea:
            guard tutorialPhase == .showIdea else { return nil }
            rawID = tutorialIdeaItemIDRawValue
        }
        guard let itemID = UUID(uuidString: rawID) else { return nil }
        let anchor = tutorialItem(itemID)
        return TutorialSpotlight(
            itemID: itemID,
            placement: placement,
            personName: anchor.flatMap { tutorialPersonName(for: $0) },
            // The same grouping Today itself sorts by, so the card names the
            // section the row is genuinely sitting in rather than the one the
            // scripted example would have produced.
            todaySection: placement == .today
                ? anchor.map { TodayActionTiming.group(for: $0) }
                : nil,
            isDueTomorrow: anchor?.dueDate.map {
                Calendar.autoupdatingCurrent.isDateInTomorrow($0)
            } ?? false
        )
    }

    private func setTutorialPhase(_ phase: FirstRunTutorialPhase) {
        tutorialPhaseRawValue = phase.rawValue
    }

    private func advanceFromTodaySpotlight() {
        guard tutorialPhase == .showToday else { return }
        setTutorialPhase(.showPeople)
        selectedDestination = .library
        isDockVisible = true
    }

    private func advanceFromLibrarySpotlight() {
        switch tutorialPhase {
        case .showPeople:
            setTutorialPhase(.showPerson)
        case .showPerson:
            setTutorialPhase(.captureIdea)
            captureTutorialMission = .idea
            showsSetupAfterFirstCapture = true
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(360))
                presentCapture(entry: .onboarding)
            }
        case .showIdea:
            setTutorialPhase(.readiness)
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(360))
                fullScreenDestination = .captureAnywhereSetup
            }
        default:
            break
        }
    }

    private func continueFromCaptureAnywhereSetup() {
        guard tutorialPhase == .readiness else { return }
        fullScreenDestination = nil
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(360))
            guard tutorialPhase == .readiness, fullScreenDestination == nil else { return }
            fullScreenDestination = .firstCaptureGuide
        }
    }

    private func finishTutorialReadiness() {
        guard cleanupTutorialData() else { return }
        SpeakItAnalytics.track(.firstCaptureGuideCompleted)
        shouldResumeFirstCaptureGuide = false
        firstCaptureTutorialStep = 0
        setTutorialPhase(.complete)
        subscriptionStore.refreshFreeAllowance()
        fullScreenDestination = .tutorialFinished
    }

    private func completeTutorial() {
        setTutorialPhase(.inactive)
        tutorialActionItemIDRawValue = ""
        tutorialIdeaItemIDRawValue = ""
        captureTutorialMission = nil
        showsSetupAfterFirstCapture = false
        hasCompletedWelcome = true
        selectedDestination = .today
        isDockVisible = true
        fullScreenDestination = nil
    }

    private func endTutorialEarly() {
        guard cleanupTutorialData() else { return }
        setTutorialPhase(.inactive)
        tutorialActionItemIDRawValue = ""
        tutorialIdeaItemIDRawValue = ""
        captureTutorialMission = nil
        showsSetupAfterFirstCapture = false
        shouldResumeFirstCaptureGuide = false
        hasCompletedWelcome = true
        selectedDestination = .today
        isDockVisible = true
        fullScreenDestination = nil
        subscriptionStore.refreshFreeAllowance()
        sharedImportNotice = "Practice examples removed · Free captures untouched"
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            sharedImportNotice = nil
        }
    }

    @discardableResult
    private func cleanupTutorialData() -> Bool {
        guard let repository else {
            sharedImportNotice = "Practice cleanup will retry when storage is ready"
            return false
        }
        do {
            _ = try repository.deleteTutorialCaptures()
            return true
        } catch {
            sharedImportNotice = "Practice examples couldn’t be removed yet"
            return false
        }
    }

    private func handleQuickAction(_ request: QuickActionRouter.Request?) {
        guard let request else { return }
        defer { quickActionRouter.consume(request) }

        if fullScreenDestination == .captureVoice || fullScreenDestination == .captureText {
            return
        }

        let isTutorialTest = isActiveCaptureAnywhereTutorialTest
        subscriptionStore.refreshFreeAllowance()
        guard isTutorialTest || subscriptionStore.canCreateCapture else {
            SpeakItAnalytics.track(.freeLimitReached(used: subscriptionStore.freeCapturesUsed))
            showsFreeLimit = true
            return
        }

        hasCompletedWelcome = true
        showsSetupAfterFirstCapture = isTutorialTest
        captureTutorialMission = isTutorialTest ? .quickAccess : nil
        returnsToSetupAfterExternalCapture = isTutorialTest
        selectedDestination = .today
        isDockVisible = true
        captureAutoStartsVoice = request.autoStartsVoiceCapture
        captureOpenedFromExternalSource = true
        capturePerformance = CapturePerformanceTrace(
            source: request.initialMode == .text ? .text : .voice,
            activatedAt: request.activationInstant,
            recordsExternalActivation: true
        )
        SpeakItAnalytics.track(.captureStarted(
            mode: request.initialMode == .text ? .text : .voice,
            entry: .quickAction
        ))
        captureSessionToken = UUID()
        fullScreenDestination = request.initialMode == .text ? .captureText : .captureVoice
    }

    private func handleDeepLink(_ url: URL) {
        if let referralCode = ReferralDeepLink.code(from: url) {
            PendingReferralStore.code = referralCode
            if hasCompletedWelcome, ReferralProgramConfiguration.isEnabled {
                activeReferralCode = referralCode
            }
            return
        }

        guard url.scheme?.lowercased() == "speakit" else { return }

        if url.host?.lowercased() == "setup" {
            hasCompletedWelcome = true
            shouldResumeFirstCaptureGuide = false
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

        // A capture already on screen is not restarted. A second Back Tap, or a
        // widget tap while capture is open, would otherwise tear down the sheet
        // and rebuild it — discarding whatever had been said or typed into it.
        if fullScreenDestination == .captureVoice || fullScreenDestination == .captureText {
            return
        }

        let isTutorialTest = isActiveCaptureAnywhereTutorialTest
        subscriptionStore.refreshFreeAllowance()
        guard isTutorialTest || subscriptionStore.canCreateCapture else {
            SpeakItAnalytics.track(.freeLimitReached(used: subscriptionStore.freeCapturesUsed))
            showsFreeLimit = true
            return
        }

        let activatedAt = Date.now
        let activationInstant = CapturePerformanceClock.now
        CaptureActivationStore.markInvoked(at: activatedAt)
        let isReturningFromSetup = fullScreenDestination == .captureAnywhereSetup
            || isTutorialTest

        hasCompletedWelcome = true
        showsSetupAfterFirstCapture = isTutorialTest
        captureTutorialMission = isTutorialTest ? .quickAccess : nil
        returnsToSetupAfterExternalCapture = isReturningFromSetup
        selectedDestination = .today
        isDockVisible = true
        captureAutoStartsVoice = true
        captureOpenedFromExternalSource = true
        capturePerformance = CapturePerformanceTrace(
            source: .voice,
            activatedAt: activationInstant,
            recordsExternalActivation: true
        )
        SpeakItAnalytics.track(.captureStarted(mode: .voice, entry: .deepLink))
        captureSessionToken = UUID()
        fullScreenDestination = .captureVoice
    }

    private var isActiveCaptureAnywhereTutorialTest: Bool {
        guard tutorialPhase == .readiness else { return false }
        let beganAt = UserDefaults.standard.double(
            forKey: "SpeakIt.captureSetupTestBeganAt"
        )
        guard beganAt > 0 else { return false }
        return Date.now.timeIntervalSince1970 - beganAt < 30 * 60
    }

    private func importSharedCaptures() async {
        guard !isImportingSharedCaptures, let repository else { return }
        isImportingSharedCaptures = true
        defer { isImportingSharedCaptures = false }

        var importedCount = 0
        var blockedByFreeLimit = false
        for pending in SharedCaptureInbox.pending() {
            subscriptionStore.refreshFreeAllowance()
            guard subscriptionStore.canCreateCapture else {
                // The Share sheet already told the person "Ready in Speak It"
                // and played a success haptic — it cannot know about the
                // allowance. Breaking silently left the payload in the shared
                // inbox and repeated the same silent break on every foreground,
                // so a thought they were told was safe simply never appeared.
                blockedByFreeLimit = true
                break
            }
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
                if result.createdNewCapture {
                    // Cancelling, completing or withdrawing manages existing
                    // content rather than storing a new thought, so it does not
                    // spend one of the ten free captures.
                    if result.consumesFreeCapture {
                        subscriptionStore.recordSuccessfulCapture()
                    }
                    SpeakItAnalytics.track(.captureSaved(
                        source: .shareSheet,
                        itemCount: result.itemCount,
                        needsReviewCount: result.needsReviewCount,
                        plan: subscriptionStore.hasProAccess ? .pro : .free
                    ))
                    importedCount += 1
                }
            } catch {
                // Leave this and later files in the shared inbox. The next
                // activation retries them without duplicating completed work.
                break
            }
        }

        if blockedByFreeLimit {
            let waiting = SharedCaptureInbox.pending().count
            withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
                sharedImportNotice = waiting == 1
                    ? "1 shared thought is waiting — your free captures are used up"
                    : "\(waiting) shared thoughts are waiting — your free captures are used up"
            }
            showsFreeLimit = true
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
            // A recording the recognizer has already read and found no words in
            // will not read differently on the next launch. Re-running it every
            // activation only churns the card's state; it stays listed, and a
            // deliberate retry from capture history is still available.
            guard !draft.recoveryFailureKind.stopsPromisingRecovery else { continue }
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
                if result.createdNewCapture {
                    // Cancelling, completing or withdrawing manages existing
                    // content rather than storing a new thought, so it does not
                    // spend one of the ten free captures.
                    if result.consumesFreeCapture {
                        subscriptionStore.recordSuccessfulCapture()
                    }
                    SpeakItAnalytics.track(.captureSaved(
                        source: .recovery,
                        itemCount: result.itemCount,
                        needsReviewCount: result.needsReviewCount,
                        plan: subscriptionStore.hasProAccess ? .pro : .free
                    ))
                    recoveredCount += 1
                }
            } catch {
                CaptureDraftStore.markFailed(id: draft.id, error: error)
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
