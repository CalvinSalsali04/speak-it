import SwiftData
import SwiftUI
import UIKit
import UserNotifications

private struct TodayDisclosureHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// Keeps disclosure rows alive and animates one clipped region. This avoids
/// staggered insert/fade transitions and repeated lazy layout passes when a
/// multi-row Today section opens on a physical device.
private struct TodayDisclosureContent<Content: View>: View {
    let isExpanded: Bool
    @ViewBuilder let content: Content

    @State private var measuredHeight: CGFloat = 0

    var body: some View {
        content
            .fixedSize(horizontal: false, vertical: true)
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: TodayDisclosureHeightPreferenceKey.self,
                        value: proxy.size.height
                    )
                }
            }
            .frame(height: isExpanded ? measuredHeight : 0, alignment: .top)
            .clipped()
            .allowsHitTesting(isExpanded)
            .accessibilityHidden(!isExpanded)
            .onPreferenceChange(TodayDisclosureHeightPreferenceKey.self) { height in
                guard height > 0, abs(measuredHeight - height) > 0.5 else { return }
                var transaction = Transaction(animation: nil)
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    measuredHeight = height
                }
            }
    }
}

private struct CompletionUndo: Identifiable {
    let id = UUID()
    let item: CapturedItem
}

enum TodayActionTiming: Equatable {
    case overdue
    case today
    case comingUp
    case noDate

    static func group(
        for dueDate: Date?,
        isDateOnly: Bool = false,
        calendarDay: CalendarDay? = nil,
        relativeTo now: Date = .now,
        calendar: Calendar = .autoupdatingCurrent
    ) -> TodayActionTiming {
        // "August 15" means August 15 wherever the person is standing. When the
        // day itself was recorded, compare days directly and never go through
        // the stored instant: a Toronto midnight read in Los Angeles is the
        // previous afternoon, which would silently shift the item a day.
        if isDateOnly, let calendarDay {
            guard let today = CalendarDay(from: now, calendar: calendar) else { return .noDate }
            if calendarDay == today { return .today }
            return isBefore(calendarDay, today) ? .overdue : .comingUp
        }

        guard let dueDate else { return .noDate }

        // A day with no time of day is not overdue until the day itself ends.
        // Comparing its start against the clock is what used to make "buy milk
        // tomorrow" read as overdue at 9:01 the next morning, for a task that
        // was never due at a time at all.
        if isDateOnly {
            if calendar.isDate(dueDate, inSameDayAs: now) { return .today }
            return dueDate < calendar.startOfDay(for: now) ? .overdue : .comingUp
        }

        if dueDate < now { return .overdue }
        if calendar.isDate(dueDate, inSameDayAs: now) { return .today }
        return .comingUp
    }

    /// Convenience for the common case of grouping a stored item.
    static func group(
        for item: CapturedItem,
        relativeTo now: Date = .now,
        calendar: Calendar = .autoupdatingCurrent
    ) -> TodayActionTiming {
        group(
            for: item.dueDate,
            isDateOnly: item.isDateOnly,
            calendarDay: item.isDateOnly ? item.temporalIntent?.day : nil,
            relativeTo: now,
            calendar: calendar
        )
    }

    private static func isBefore(_ lhs: CalendarDay, _ rhs: CalendarDay) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }
}

struct TodayView: View {
    @Environment(\.thoughtRepository) private var repository
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var subscriptionStore: SubscriptionStore
    @Query(
        filter: #Predicate<CapturedItem> { $0.isArchived == false },
        sort: \CapturedItem.createdAt,
        order: .reverse
    ) private var allItems: [CapturedItem]
    @Query(
        filter: #Predicate<CaptureSession> { $0.processingStatusRawValue != "complete" },
        sort: \CaptureSession.createdAt,
        order: .reverse
    ) private var captureSessions: [CaptureSession]

    let onCapture: () -> Void
    let onDockVisibilityChange: (Bool) -> Void

    @State private var selectedItem: CapturedItem?
    @State private var errorMessage: String?
    @State private var showsCaptureSetup = false
    @State private var showsReminderSettings = false
    @State private var showsCompletedLog = false
    @State private var showsSpeechVocabulary = false
    @State private var showsPrivacy = false
    @State private var showsICloudSync = false
    @State private var showsSpeakItPro = TodayView.initialShowsSpeakItPro
    @State private var showsCaptureHistory = false
    @State private var selectedRecoverySession: CaptureSession?
    @State private var recoveryAudioDrafts: [CaptureDraftStore.Draft] = []
    @State private var reminderAccessStatus = ReminderAccessStatus.ready
    @State private var completionUndo: CompletionUndo?
    @State private var dockScrollPolicy = DockScrollPolicy()
    @State private var reportsDockVisible = true
    @State private var showsUpcoming = TodayView.initialShowsUpcoming
    @State private var showsNoDate = true
    @State private var showsSampleDataResult = false
    @State private var sampleDataResultMessage = ""
    @State private var showsAccountSettings = TodayView.initialShowsAccountSettings
    @State private var referenceNow = Date.now
    @AppStorage("SpeakIt.shortcutSetupCompleted") private var shortcutSetupCompleted = false
    @AppStorage("SpeakIt.hasDismissedProDiscovery") private var hasDismissedProDiscovery = false

    init(
        onCapture: @escaping () -> Void,
        onDockVisibilityChange: @escaping (Bool) -> Void = { _ in }
    ) {
        self.onCapture = onCapture
        self.onDockVisibilityChange = onDockVisibilityChange
    }

    private static var initialShowsUpcoming: Bool {
#if DEBUG
        ProcessInfo.processInfo.arguments.contains("--expand-today-upcoming")
#else
        false
#endif
    }

    private static var initialShowsSpeakItPro: Bool {
#if DEBUG
        ProcessInfo.processInfo.arguments.contains("--show-pro")
#else
        false
#endif
    }

    private static var initialShowsAccountSettings: Bool {
#if DEBUG
        ProcessInfo.processInfo.arguments.contains("--show-account")
#else
        false
#endif
    }

    private var activeActions: [CapturedItem] {
        allItems.filter(\.belongsInToday)
    }

    private var needsReview: [CapturedItem] {
        allItems
            .filter { !$0.isArchived && !$0.isCompleted && $0.needsClarification }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private var overdue: [CapturedItem] {
        activeActions
            .filter { TodayActionTiming.group(for: $0, relativeTo: referenceNow) == .overdue }
            .sorted(by: chronologicalBefore)
    }

    private var scheduledToday: [CapturedItem] {
        return activeActions
            .filter { TodayActionTiming.group(for: $0, relativeTo: referenceNow) == .today }
            .sorted(by: chronologicalBefore)
    }

    private var upNext: CapturedItem? {
        scheduledToday.first
    }

    private var remainingToday: [CapturedItem] {
        guard let upNext else { return scheduledToday }
        return scheduledToday.filter { $0.id != upNext.id }
    }

    private var noDate: [CapturedItem] {
        activeActions
            .filter { TodayActionTiming.group(for: $0, relativeTo: referenceNow) == .noDate }
            .sorted(by: prioritizedBefore)
    }

    private var comingUp: [CapturedItem] {
        activeActions
            .filter { TodayActionTiming.group(for: $0, relativeTo: referenceNow) == .comingUp }
            .sorted(by: chronologicalBefore)
    }

    private var isEmpty: Bool {
        activeActions.isEmpty && needsReview.isEmpty
    }

    private var completedToday: [CapturedItem] {
        allItems
            .filter { item in
                guard !item.isArchived, let completedAt = item.completedAt else { return false }
                // Derived from the same reference clock as every other section,
                // so the whole screen agrees on which day it is the instant the
                // device rolls past local midnight.
                return Calendar.autoupdatingCurrent.isDate(completedAt, inSameDayAs: referenceNow)
            }
            .sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
    }

    private var pendingReminderRequests: [ReminderScheduleRequest] {
        allItems
            .filter { !$0.isArchived && !$0.isCompleted }
            .compactMap(ReminderScheduleRequest.init(item:))
    }

    private var capturesNeedingAttention: [CaptureSession] {
        captureSessions.filter { session in
            if session.processingStatus == .failed { return true }
            guard session.processingStatus != .complete else { return false }
            return referenceNow.timeIntervalSince(session.createdAt) > 10
        }
    }

    private var reminderSignature: String {
        pendingReminderRequests
            .map { "\($0.itemID.uuidString)-\($0.fireDate.timeIntervalSince1970)" }
            .sorted()
            .joined(separator: "|")
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 28) {
                header
                    .dockScrollTopAnchor()

                if shouldShowProDiscovery {
                    ProDiscoveryCard(
                        itemCount: allItems.count,
                        onExplore: { showsSpeakItPro = true },
                        onDismiss: { hasDismissedProDiscovery = true }
                    )
                }

                if !shortcutSetupCompleted {
                    doubleTapCard
                }

                if !pendingReminderRequests.isEmpty, reminderAccessStatus != .ready {
                    reminderPermissionCard
                }

                if !capturesNeedingAttention.isEmpty || !recoveryAudioDrafts.isEmpty {
                    captureRecoveryCard
                }

                if !needsReview.isEmpty {
                    reviewSection
                }

                if isEmpty {
                    emptyState
                } else {
                    if !overdue.isEmpty || upNext != nil {
                        nowSection
                    }

                    if !remainingToday.isEmpty {
                        thoughtSection(
                            title: "Rest of today",
                            detail: "Scheduled before the day ends",
                            items: remainingToday
                        )
                    }

                    if !comingUp.isEmpty {
                        collapsibleThoughtSection(
                            title: "Coming up",
                            detail: "Scheduled tomorrow or later",
                            items: comingUp,
                            isExpanded: $showsUpcoming
                        )
                    }

                    if !noDate.isEmpty {
                        collapsibleThoughtSection(
                            title: "When you have time",
                            detail: "Ready to do · no date set",
                            items: noDate,
                            isExpanded: $showsNoDate
                        )
                    }
                }

                if !completedToday.isEmpty {
                    completedTodayLink
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 18)
            .padding(.bottom, 40)
        }
        .contentMargins(.bottom, 28, for: .scrollContent)
        .coordinateSpace(name: DockScroll.coordinateSpace)
        .scrollBounceBehavior(.basedOnSize)
        .modifier(DockScrollObserver(onScroll: handleDockScroll))
        .onPreferenceChange(DockScrollTopAnchorKey.self) { anchor in
            guard !DockScroll.readsScrollGeometry else { return }
            handleDockScroll(DockScroll.scrolled(topAnchor: anchor))
        }
        .scrollIndicators(.hidden)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(item: $selectedItem) { item in
            ItemEditorView(item: item)
        }
        .sheet(isPresented: $showsCaptureSetup) {
            CaptureAnywhereSetupView()
        }
        .sheet(isPresented: $showsReminderSettings) {
            ReminderSettingsView()
        }
        .sheet(isPresented: $showsCompletedLog) {
            CompletedLogView()
        }
        .sheet(isPresented: $showsSpeechVocabulary) {
            SpeechVocabularyView()
        }
        .sheet(isPresented: $showsPrivacy) {
            SpeakItPrivacyView()
        }
        .sheet(isPresented: $showsICloudSync) {
            ICloudSyncSettingsView()
        }
        .sheet(isPresented: $showsSpeakItPro) {
            SpeakItProView()
        }
        .sheet(isPresented: $showsCaptureHistory) {
            CaptureHistoryView()
        }
        .sheet(isPresented: $showsAccountSettings) {
            AccountSettingsView()
        }
        .sheet(item: $selectedRecoverySession) { session in
            NavigationStack {
                CaptureSessionReviewView(session: session)
            }
        }
        .alert("Test examples", isPresented: $showsSampleDataResult) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(sampleDataResultMessage)
        }
        .repositoryErrorAlert($errorMessage)
        .speakScreenStyle()
        .overlay(alignment: .bottom) {
            if let completionUndo {
                UndoToast(message: "Task completed") {
                    undoCompletion(completionUndo)
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 96)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(10)
            }
        }
        .task(id: reminderSignature) {
            reminderAccessStatus = await ReminderScheduler.accessStatus(
                for: pendingReminderRequests
            )
        }
        .task {
            await subscriptionStore.prepare()
        }
        .onAppear {
            referenceNow = .now
            reloadRecoveryAudioDrafts()
            reportsDockVisible = true
            onDockVisibilityChange(true)
        }
        .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { date in
            referenceNow = date
        }
        // Three signals, because none of them covers the others. The minute
        // timer only runs while the app is awake; `NSCalendarDayChanged` is the
        // system's precise "the local calendar day is now different" event;
        // `significantTimeChange` also covers carrier time and DST. Returning
        // to the foreground re-reads the clock outright, so a device that was
        // asleep across midnight is correct before the first frame is drawn.
        .onReceive(
            // Posted off the main thread, unlike the UIKit notifications below.
            NotificationCenter.default.publisher(for: .NSCalendarDayChanged)
                .receive(on: RunLoop.main)
        ) { _ in
            referenceNow = .now
        }
        .onReceive(
            NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)
        ) { _ in
            referenceNow = .now
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            referenceNow = .now
            // Notification permission can be revoked in Settings while Speak It
            // is suspended. Re-reading it here is what turns the permission card
            // back on for reminders that are saved but can no longer alert.
            Task {
                reminderAccessStatus = await ReminderScheduler.accessStatus(
                    for: pendingReminderRequests
                )
            }
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: CaptureDraftStore.recoveryDidChangeNotification
            )
        ) { _ in
            reloadRecoveryAudioDrafts()
        }
    }

    private var header: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 6) {
                Text(referenceNow.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                    .font(SpeakItTypography.eyebrow)
                    .foregroundStyle(Color.speakMuted)

                Text("Today")
                    .font(SpeakItTypography.screenTitle)
                    .foregroundStyle(Color.speakInk)
            }

            Spacer()

            Button {
                showsAccountSettings = true
            } label: {
                Image(systemName: subscriptionStore.hasProAccess
                      ? "person.crop.circle.fill.badge.checkmark"
                      : "person.crop.circle")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(Color.speakInk)
                    .frame(width: 44, height: 44)
                    .background(Color.speakSurface, in: Circle())
                    .overlay {
                        Circle().stroke(Color.speakDivider, lineWidth: 1)
                    }
            }
            .buttonStyle(.speakIt)
            .accessibilityLabel("Account and settings")
            .accessibilityIdentifier("today.account")
        }
    }

    private var shouldShowProDiscovery: Bool {
        allItems.count >= 5 &&
            subscriptionStore.hasAvailablePlans &&
            !subscriptionStore.hasProAccess &&
            !hasDismissedProDiscovery
    }

    private func loadTestExamples() {
        Task { @MainActor in
            _ = await ReminderScheduler.requestNotificationAuthorizationIfNeeded()
            guard let repository else { return }
            do {
                let result = try repository.loadSampleData(referenceDate: .now)
                sampleDataResultMessage = result.addedAnything
                    ? "Added \(result.addedCaptureCount) captures containing \(result.addedItemCount) organized items."
                    : "The complete example library is already loaded. Nothing was duplicated."
                showsSampleDataResult = true
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private var completedTodayLink: some View {
        Button {
            showsCompletedLog = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Color.speakMuted)

                Text("\(completedToday.count) completed today")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.speakInk)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.speakMuted)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.speakIt)
        .background(
            Color.speakSurface,
            in: RoundedRectangle(cornerRadius: 17, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .stroke(Color.speakDivider, lineWidth: 1)
        }
        .accessibilityHint("Opens your completed task history")
    }

    private var reminderPermissionCard: some View {
        HStack(spacing: 14) {
            Image(systemName: reminderAccessStatus == .denied ? "bell.slash" : "bell")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.speakInk)
                .frame(width: 42, height: 42)
                .background(Color.speakSurface, in: Circle())
                .overlay { Circle().stroke(Color.speakDivider, lineWidth: 1) }

            VStack(alignment: .leading, spacing: 3) {
                Text(reminderAccessStatus == .denied ? "Reminders are off" : "Make reminders work")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.speakInk)
                Text(reminderAccessStatus == .denied ? "Allow alerts in Settings so timed thoughts can reach you." : "Allow alerts for the timed thought you just captured.")
                    .font(.caption)
                    .foregroundStyle(Color.speakMuted)
                    .lineLimit(2)
            }

            Spacer(minLength: 6)

            Button(reminderAccessStatus == .denied ? "Settings" : "Allow") {
                if reminderAccessStatus == .denied {
                    if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                        openURL(settingsURL)
                    }
                } else {
                    Task {
                        _ = await ReminderScheduler.requestAccessAndSchedule(
                            pendingReminderRequests
                        )
                        reminderAccessStatus = await ReminderScheduler.accessStatus(
                            for: pendingReminderRequests
                        )
                    }
                }
            }
            .font(.subheadline.weight(.semibold))
            .buttonStyle(.speakIt)
            .foregroundStyle(Color.speakInk)
        }
        .padding(16)
        .background(
            Color.speakSurface,
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.speakDivider, lineWidth: 1)
        }
    }

    private var captureRecoveryCard: some View {
        Button {
            showsCaptureHistory = true
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.speakInk)
                    .frame(width: 42, height: 42)
                    .background(Color.speakSurface, in: Circle())
                    .overlay { Circle().stroke(Color.speakDivider, lineWidth: 1) }

                VStack(alignment: .leading, spacing: 3) {
                    let recoveryCount = capturesNeedingAttention.count + recoveryAudioDrafts.count
                    Text(recoveryCount == 1 ? "One capture needs attention" : "\(recoveryCount) captures need attention")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.speakInk)
                    Text(recoveryAudioDrafts.isEmpty
                         ? "Your original words are safe. Tap to organize again or keep them untouched."
                         : "A protected recording is safe on this iPhone. Tap to recover it.")
                        .font(.caption)
                        .foregroundStyle(Color.speakMuted)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 6)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.speakMuted)
            }
            .padding(16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.speakIt)
        .background(
            Color.speakSurface,
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.speakDivider, lineWidth: 1)
        }
        .accessibilityHint("Opens the original capture and recovery actions")
    }

    private func reloadRecoveryAudioDrafts() {
        recoveryAudioDrafts = CaptureDraftStore.recoverableAudioDrafts(minimumAge: 0)
    }

    private var doubleTapCard: some View {
        Button {
            showsCaptureSetup = true
        } label: {
            HStack(spacing: 15) {
                ZStack {
                    Circle()
                        .stroke(Color.speakInverseInk.opacity(0.16), lineWidth: 1)
                        .frame(width: 48, height: 48)

                    Image(systemName: shortcutSetupCompleted ? "checkmark" : "waveform")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.speakInverseInk)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(shortcutSetupCompleted ? "Quick capture is ready" : "Capture from anywhere")
                        .font(.headline)
                        .foregroundStyle(Color.speakInverseInk)

                    Text(shortcutSetupCompleted ? "Use your chosen iPhone trigger to speak." : "Lock Screen, Action Button, or Back Tap. Pick one and test it.")
                        .font(.subheadline)
                        .foregroundStyle(Color.speakInverseInk.opacity(0.62))
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.speakInverseInk.opacity(0.45))
            }
            .padding(17)
            .contentShape(Rectangle())
        }
        .buttonStyle(.speakIt)
        .background(
            Color.speakInverseSurface,
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
        .accessibilityIdentifier("today.doubleTapSetup")
        .accessibilityHint(shortcutSetupCompleted ? "Reopens the setup guide" : "Opens the one-time setup guide")
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Your day is clear.")
                .font(.title2.weight(.semibold))
            Text("Capture anything on your mind. Speak It will decide whether it belongs here or in Memory.")
                .foregroundStyle(Color.speakMuted)

            Button(action: onCapture) {
                Label("Capture a thought", systemImage: "waveform")
                    .font(.headline)
                    .foregroundStyle(Color.speakInverseInk)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.speakIt)
            .background(
                Color.speakInverseSurface,
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .accessibilityIdentifier("today.captureThought")
        }
        .padding(.top, 54)
    }

    private var reviewSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Needs review", count: needsReview.count)

            VStack(spacing: 0) {
                ForEach(needsReview) { item in
                    Button {
                        selectedItem = item
                    } label: {
                        HStack(spacing: 13) {
                            Image(systemName: "questionmark.circle")
                                .font(.system(size: 19, weight: .medium))
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.displayTitle)
                                    .font(.body.weight(.medium))
                                    .multilineTextAlignment(.leading)
                                Text(reviewRequirementLabel(item))
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(Color.speakWarning)
                                    .multilineTextAlignment(.leading)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.speakMuted)
                        }
                        .foregroundStyle(Color.speakInk)
                        .padding(.vertical, 13)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.speakIt)
                    .accessibilityLabel("\(item.displayTitle). \(reviewRequirementLabel(item))")
                    .accessibilityHint("Opens this item so you can supply what is missing")
                    Divider().overlay(Color.speakDivider)
                }
            }
            .padding(.horizontal, 15)
            .background(Color.speakSurface, in: RoundedRectangle(cornerRadius: 18))
            .overlay {
                RoundedRectangle(cornerRadius: 18).stroke(Color.speakDivider, lineWidth: 1)
            }
        }
    }

    private func reviewRequirementLabel(_ item: CapturedItem) -> String {
        (item.clarificationRequirement ?? .confirmation).listLabel
    }

    private func focusCard(_ item: CapturedItem) -> some View {
        HStack(spacing: 14) {
            Button {
                toggleCompleted(item)
            } label: {
                Image(systemName: "circle")
                    .font(.system(size: 27, weight: .regular))
                    .foregroundStyle(Color.speakInverseInk.opacity(0.62))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.speakIt)
            .accessibilityLabel("Complete \(item.displayTitle)")
            .accessibilityIdentifier("item.complete.\(item.displayTitle)")

            Button {
                selectedItem = item
            } label: {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text(item.displayTitle)
                            .font(.body.weight(.medium))
                            .foregroundStyle(Color.speakInverseInk)
                            .multilineTextAlignment(.leading)

                        Text(itemContext(item))
                            .font(.caption)
                            .foregroundStyle(Color.speakInverseInk.opacity(0.58))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    if let dueDate = item.dueDate {
                        Text(dueDate.formatted(date: .omitted, time: .shortened))
                            .font(.caption)
                            .foregroundStyle(Color.speakInverseInk.opacity(0.68))
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.speakIt)
            .accessibilityLabel("Edit \(item.displayTitle)")
            .accessibilityIdentifier("item.edit.\(item.displayTitle)")
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 104)
        .background(
            Color.speakInverseSurface,
            in: RoundedRectangle(cornerRadius: 23, style: .continuous)
        )
        .shadow(color: .black.opacity(0.12), radius: 18, y: 10)
    }

    private var nowSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(
                "Now",
                count: overdue.count + (upNext == nil ? 0 : 1),
                detail: "Overdue and next scheduled"
            )

            if !overdue.isEmpty {
                VStack(spacing: 0) {
                    Divider().overlay(Color.speakDivider)
                    ForEach(overdue) { item in
                        swipeToComplete(item) {
                            CapturedItemRow(
                                item: item,
                                showsCreatedDate: false,
                                onToggleCompleted: { toggleCompleted(item) },
                                onEdit: { selectedItem = item }
                            )
                            .padding(.vertical, 12)
                        }
                        Divider().overlay(Color.speakDivider)
                    }
                }
            }

            if let upNext {
                swipeToComplete(upNext) {
                    focusCard(upNext)
                }
            }
        }
    }

    private func thoughtSection(
        title: String,
        detail: String? = nil,
        items: [CapturedItem]
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(title, count: items.count, detail: detail)

            VStack(spacing: 0) {
                Divider().overlay(Color.speakDivider)

                ForEach(items) { item in
                    swipeToComplete(item) {
                        CapturedItemRow(
                            item: item,
                            showsCreatedDate: false,
                            onToggleCompleted: { toggleCompleted(item) },
                            onEdit: { selectedItem = item }
                        )
                        .padding(.vertical, 12)
                    }

                    Divider().overlay(Color.speakDivider)
                }
            }
        }
    }

    private func collapsibleThoughtSection(
        title: String,
        detail: String,
        items: [CapturedItem],
        isExpanded: Binding<Bool>
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                let nextValue = !isExpanded.wrappedValue
                if accessibilityReduceMotion {
                    var transaction = Transaction(animation: nil)
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        isExpanded.wrappedValue = nextValue
                    }
                } else {
                    withAnimation(.smooth(duration: 0.26, extraBounce: 0)) {
                        isExpanded.wrappedValue = nextValue
                    }
                }
            } label: {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(title)
                            .font(SpeakItTypography.sectionTitle)

                        Text(detail)
                            .font(SpeakItTypography.sectionDetail)
                    }
                    Spacer()
                    Text("\(items.count)")
                        .font(SpeakItTypography.sectionDetail.weight(.medium))
                    Image(systemName: isExpanded.wrappedValue ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.bold))
                        .contentTransition(.symbolEffect(.replace))
                }
                .foregroundStyle(Color.speakMuted)
                .contentShape(Rectangle())
            }
            .buttonStyle(.speakIt)
            .accessibilityValue(isExpanded.wrappedValue ? "Expanded" : "Collapsed")
            .accessibilityIdentifier("today.section.\(title == "Coming up" ? "comingUp" : "noDate")")

            TodayDisclosureContent(isExpanded: isExpanded.wrappedValue) {
                VStack(spacing: 0) {
                    Divider().overlay(Color.speakDivider)
                    ForEach(items) { item in
                        swipeToComplete(item, isEnabled: isExpanded.wrappedValue) {
                            CapturedItemRow(
                                item: item,
                                showsCreatedDate: false,
                                onToggleCompleted: { toggleCompleted(item) },
                                onEdit: { selectedItem = item }
                            )
                            .padding(.vertical, 12)
                        }
                        Divider().overlay(Color.speakDivider)
                    }
                }
                .padding(.top, 10)
            }
        }
    }

    private func sectionHeader(
        _ title: String,
        count: Int,
        detail: String? = nil
    ) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(SpeakItTypography.sectionTitle)

                if let detail {
                    Text(detail)
                        .font(SpeakItTypography.sectionDetail)
                }
            }
            Spacer()
            Text("\(count)")
                .font(SpeakItTypography.sectionDetail.weight(.medium))
        }
        .foregroundStyle(Color.speakMuted)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private func itemContext(_ item: CapturedItem) -> String {
        "\(item.category.displayName) · \(item.itemType.displayName)"
    }

    private func swipeToComplete<Content: View>(
        _ item: CapturedItem,
        isEnabled: Bool = true,
        @ViewBuilder content: () -> Content
    ) -> some View {
        SwipeActionRow(
            actionTitle: "Done",
            systemImage: "checkmark",
            accessibilityLabel: "Complete \(item.displayTitle)",
            isEnabled: isEnabled,
            action: { complete(item) },
            content: content
        )
    }

    private func prioritizedBefore(_ lhs: CapturedItem, _ rhs: CapturedItem) -> Bool {
        if lhs.priority != rhs.priority { return lhs.priority > rhs.priority }
        return (lhs.dueDate ?? .distantFuture) < (rhs.dueDate ?? .distantFuture)
    }

    private func chronologicalBefore(_ lhs: CapturedItem, _ rhs: CapturedItem) -> Bool {
        let leftDate = lhs.dueDate ?? .distantFuture
        let rightDate = rhs.dueDate ?? .distantFuture
        if leftDate != rightDate { return leftDate < rightDate }
        return lhs.priority > rhs.priority
    }

    private func handleDockScroll(_ scrolled: CGFloat) {
        guard let visibility = dockScrollPolicy.update(scrolled: scrolled) else { return }
        updateDockVisibility(visibility)
    }

    private func updateDockVisibility(_ visible: Bool) {
        guard reportsDockVisible != visible else { return }
        reportsDockVisible = visible
        onDockVisibilityChange(visible)
    }

    private func toggleCompleted(_ item: CapturedItem) {
        if item.isCompleted {
            performCompletionChange(item, completed: false, offersUndo: false)
        } else {
            complete(item)
        }
    }

    private func complete(_ item: CapturedItem) {
        performCompletionChange(item, completed: true, offersUndo: true)
    }

    private func performCompletionChange(
        _ item: CapturedItem,
        completed: Bool,
        offersUndo: Bool
    ) {
        guard let repository else {
            errorMessage = "Local storage is unavailable."
            return
        }

        do {
            try withAnimation(.easeInOut(duration: 0.22)) {
                try repository.setCompleted(item, completed: completed)
            }
            SpeakItAnalytics.track(.taskCompletionChanged(completed: completed))
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            if offersUndo { showCompletionUndo(for: item) }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func showCompletionUndo(for item: CapturedItem) {
        let notice = CompletionUndo(item: item)
        withAnimation(.snappy(duration: 0.24)) {
            completionUndo = notice
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(5))
            guard completionUndo?.id == notice.id else { return }
            withAnimation(.easeOut(duration: 0.2)) {
                completionUndo = nil
            }
        }
    }

    private func undoCompletion(_ notice: CompletionUndo) {
        performCompletionChange(notice.item, completed: false, offersUndo: false)
        withAnimation(.easeOut(duration: 0.18)) {
            completionUndo = nil
        }
    }
}

struct CaptureHistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.thoughtRepository) private var repository
    @Query(sort: \CaptureSession.createdAt, order: .reverse) private var sessions: [CaptureSession]

    @State private var recoveryDrafts: [CaptureDraftStore.Draft] = []
    @State private var recoveringDraftID: UUID?
    @State private var selectedSession: CaptureSession?
    @State private var errorMessage: String?
    @State private var successNotice: String?

    var body: some View {
        NavigationStack {
            List {
                if !recoveryDrafts.isEmpty {
                    Section {
                        ForEach(recoveryDrafts, id: \.id) { draft in
                            recoveryRow(draft)
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button(role: .destructive) {
                                        CaptureDraftStore.clear(id: draft.id)
                                        reloadDrafts()
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                        }
                    } header: {
                        Text("Ready to recover")
                    } footer: {
                        Text("These temporary recordings stay only on this iPhone and are deleted after a successful recovery.")
                    }
                }

                Section("Recent captures") {
                    if sessions.isEmpty {
                        Text("Your successful captures will appear here.")
                            .foregroundStyle(Color.speakMuted)
                    } else {
                        ForEach(Array(sessions.prefix(40)), id: \.id) { session in
                            Button {
                                selectedSession = session
                            } label: {
                                sessionRow(session)
                            }
                            .buttonStyle(.speakIt)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color.speakBackground)
            .navigationTitle("Capture history")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $selectedSession) { session in
                NavigationStack {
                    CaptureSessionReviewView(session: session)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { selectedSession = nil }
                            }
                        }
                }
            }
            .repositoryErrorAlert($errorMessage)
            .overlay(alignment: .top) {
                if let successNotice {
                    Label(successNotice, systemImage: "checkmark")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.speakInverseInk)
                        .padding(.horizontal, 16)
                        .frame(minHeight: 46)
                        .background(Color.speakInverseSurface, in: Capsule())
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .onAppear(perform: reloadDrafts)
            .onReceive(
                NotificationCenter.default.publisher(
                    for: CaptureDraftStore.recoveryDidChangeNotification
                )
            ) { _ in
                reloadDrafts()
            }
        }
        .preferredColorScheme(nil)
    }

    private func recoveryRow(_ draft: CaptureDraftStore.Draft) -> some View {
        Button {
            recover(draft)
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(Color.speakSurface)
                        .frame(width: 42, height: 42)
                    if recoveringDraftID == draft.id {
                        ProgressView()
                            .tint(Color.speakInk)
                    } else {
                        Image(systemName: "waveform.badge.exclamationmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color.speakInk)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(recoveringDraftID == draft.id ? "Recovering your words…" : "Interrupted voice capture")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.speakInk)
                    Text("\(draft.captureSource.displayName) · \(draft.startedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(Color.speakMuted)
                    if let message = draft.recoveryFailureMessage,
                       draft.recoveryStatus == .failed {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(Color.speakMuted)
                            .lineLimit(2)
                    }
                }

                Spacer(minLength: 8)

                Image(systemName: "arrow.clockwise")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.speakMuted)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.speakIt)
        .disabled(recoveringDraftID != nil)
        .accessibilityHint("Re-transcribes the protected local recording")
    }

    private func sessionRow(_ session: CaptureSession) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: statusSymbol(for: session.processingStatus))
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.speakInk)
                .frame(width: 42, height: 42)
                .background(Color.speakSurface, in: Circle())

            VStack(alignment: .leading, spacing: 5) {
                Text(session.originalTranscription)
                    .font(.body.weight(.medium))
                    .foregroundStyle(Color.speakInk)
                    .lineLimit(2)
                Text("\(session.captureSource.displayName) · \(session.createdAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(Color.speakMuted)
                Text(session.processingStatus == .complete
                     ? "\(session.extractedItemCount) saved"
                     : session.processingStatus.rawValue.capitalized)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.speakMuted)
            }

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.speakMuted)
                .padding(.top, 12)
        }
        .contentShape(Rectangle())
    }

    private func recover(_ draft: CaptureDraftStore.Draft) {
        guard recoveringDraftID == nil else { return }
        guard let repository else {
            errorMessage = "Local storage is unavailable. Your recording is still safe."
            return
        }

        recoveringDraftID = draft.id
        CaptureDraftStore.markProcessing(id: draft.id)
        Task { @MainActor in
            do {
                let recoveredText = try await CaptureAudioRecovery.transcribe(draft)
                _ = try await repository.createCaptureResult(
                    text: recoveredText,
                    source: draft.captureSource,
                    createdAt: draft.startedAt,
                    schedulesReminders: true
                )
                CaptureDraftStore.clear(id: draft.id)
                recoveringDraftID = nil
                showSuccess("Capture recovered")
            } catch {
                CaptureDraftStore.markFailed(
                    id: draft.id,
                    message: error.localizedDescription
                )
                recoveringDraftID = nil
                errorMessage = "Recovery didn’t finish, but the recording is still safe. \(error.localizedDescription)"
            }
        }
    }

    private func reloadDrafts() {
        recoveryDrafts = CaptureDraftStore.recoverableAudioDrafts(minimumAge: 0)
    }

    private func showSuccess(_ message: String) {
        withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
            successNotice = message
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.4))
            withAnimation(.easeOut(duration: 0.2)) {
                if successNotice == message { successNotice = nil }
            }
        }
    }

    private func statusSymbol(for status: ProcessingStatus) -> String {
        switch status {
        case .complete: "checkmark"
        case .pending: "clock"
        case .organizing: "arrow.triangle.2.circlepath"
        case .failed: "exclamationmark"
        }
    }
}

struct CompletedLogView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.thoughtRepository) private var repository
    @Query(
        filter: #Predicate<CapturedItem> { item in
            item.completedAt != nil && item.isArchived == false
        },
        sort: \CapturedItem.completedAt,
        order: .reverse
    ) private var completedItems: [CapturedItem]

    @State private var selectedItem: CapturedItem?
    @State private var errorMessage: String?

    private var completedToday: [CapturedItem] {
        completedItems.filter { item in
            guard let date = item.completedAt else { return false }
            return Calendar.autoupdatingCurrent.isDateInToday(date)
        }
    }

    private var completedYesterday: [CapturedItem] {
        completedItems.filter { item in
            guard let date = item.completedAt else { return false }
            return Calendar.autoupdatingCurrent.isDateInYesterday(date)
        }
    }

    private var completedThisWeek: [CapturedItem] {
        let calendar = Calendar.autoupdatingCurrent
        let sevenDaysAgo = calendar.date(byAdding: .day, value: -7, to: calendar.startOfDay(for: .now)) ?? .distantPast
        return completedItems.filter { item in
            guard let date = item.completedAt else { return false }
            return date >= sevenDaysAgo
                && !calendar.isDateInToday(date)
                && !calendar.isDateInYesterday(date)
        }
    }

    private var completedEarlier: [CapturedItem] {
        let sevenDaysAgo = Calendar.autoupdatingCurrent.date(
            byAdding: .day,
            value: -7,
            to: Calendar.autoupdatingCurrent.startOfDay(for: .now)
        ) ?? .distantPast
        return completedItems.filter { ($0.completedAt ?? .distantPast) < sevenDaysAgo }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    if completedItems.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Nothing completed yet")
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(Color.speakInk)
                            Text("Finished tasks will remain safely available here.")
                                .foregroundStyle(Color.speakMuted)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 42)
                    } else {
                        completedSection("Today", items: completedToday)
                        completedSection("Yesterday", items: completedYesterday)
                        completedSection("Previous 7 days", items: completedThisWeek)
                        completedSection("Earlier", items: completedEarlier)
                    }
                }
                .padding(.horizontal, 22)
                .padding(.top, 16)
                .padding(.bottom, 34)
            }
            .scrollIndicators(.hidden)
            .navigationTitle("Completed")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $selectedItem) { item in
                ItemEditorView(item: item)
            }
            .repositoryErrorAlert($errorMessage)
            .speakScreenStyle()
        }
    }

    @ViewBuilder
    private func completedSection(_ title: String, items: [CapturedItem]) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(title.uppercased())
                    Spacer()
                    Text("\(items.count)")
                }
                .font(.caption.weight(.medium))
                .tracking(1.2)
                .foregroundStyle(Color.speakMuted)

                VStack(spacing: 0) {
                    Divider().overlay(Color.speakDivider)
                    ForEach(items) { item in
                        CapturedItemRow(
                            item: item,
                            trailingDetail: item.completedAt?.formatted(date: .omitted, time: .shortened),
                            onToggleCompleted: { restore(item) },
                            onEdit: { selectedItem = item }
                        )
                        .padding(.vertical, 12)
                        Divider().overlay(Color.speakDivider)
                    }
                }
            }
        }
    }

    private func restore(_ item: CapturedItem) {
        guard let repository else {
            errorMessage = "Local storage is unavailable."
            return
        }

        do {
            try withAnimation(.easeInOut(duration: 0.2)) {
                try repository.setCompleted(item, completed: false)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct ReminderSettingsView: View {
    private enum AccessState: Equatable {
        case checking
        case ready
        case needsPermission
        case denied
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var accessState = AccessState.checking
    @State private var alertsEnabled = false
    @State private var soundsEnabled = false
    @State private var scheduledSummaryEnabled = false
    @State private var pendingCount = 0
    @State private var isTesting = false
    @State private var testMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("REMINDERS")
                            .font(.caption.weight(.medium))
                            .tracking(1.6)
                            .foregroundStyle(Color.speakMuted)
                        Text(statusTitle)
                            .font(.largeTitle.weight(.semibold))
                            .foregroundStyle(Color.speakInk)
                        Text(statusDetail)
                            .foregroundStyle(Color.speakMuted)
                    }

                    VStack(spacing: 0) {
                        statusRow("Alerts", ready: alertsEnabled)
                        Divider().overlay(Color.speakDivider)
                        statusRow("Sound", ready: soundsEnabled)
                        Divider().overlay(Color.speakDivider)
                        HStack {
                            Text("Scheduled")
                            Spacer()
                            Text("\(pendingCount)")
                                .foregroundStyle(Color.speakMuted)
                        }
                        .padding(.vertical, 15)
                    }
                    .padding(.horizontal, 18)
                    .background(Color.speakSurface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(Color.speakDivider, lineWidth: 1)
                    }

                    if scheduledSummaryEnabled {
                        Label(
                            "Notification Summary may delay ordinary alerts. Explicit Speak It reminders are still saved, but Focus settings can control when you see them.",
                            systemImage: "moon"
                        )
                        .font(.subheadline)
                        .foregroundStyle(Color.speakMuted)
                    }

                    if let testMessage {
                        Text(testMessage)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Color.speakInk)
                    }

                    Button {
                        runTest()
                    } label: {
                        Label(
                            isTesting ? "Testing…" : testButtonTitle,
                            systemImage: "bell.badge"
                        )
                        .font(.headline)
                        .foregroundStyle(Color.speakInverseInk)
                        .frame(maxWidth: .infinity, minHeight: 54)
                    }
                            .buttonStyle(.speakIt)
                    .disabled(isTesting)
                    .background(Color.speakInverseSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                    if accessState == .denied || !alertsEnabled || !soundsEnabled {
                        Button("Open Notification Settings") {
                            if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                                openURL(url)
                            }
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.speakInk)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(Color.speakSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(Color.speakDivider, lineWidth: 1)
                        }
                    }
                }
                .padding(22)
            }
            .scrollIndicators(.hidden)
            .speakScreenStyle()
            .navigationTitle("Reminder check")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await refresh() }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                Task { await refresh() }
            }
        }
    }

    private var statusTitle: String {
        switch accessState {
        case .checking: "Checking…"
        case .ready: "Notifications ready"
        case .needsPermission: "Allow notifications"
        case .denied: "Notifications are off"
        }
    }

    private var statusDetail: String {
        switch accessState {
        case .checking: "Checking your iPhone settings."
        case .ready: "Send a five-second test to confirm alerts on this iPhone."
        case .needsPermission: "Speak It will only notify you when you explicitly ask for a reminder."
        case .denied: "Enable alerts and sound so timed thoughts can reach you."
        }
    }

    private var testButtonTitle: String {
        accessState == .needsPermission ? "Allow and test" : "Test in 5 seconds"
    }

    private func statusRow(_ title: String, ready: Bool) -> some View {
        HStack {
            Text(title)
            Spacer()
            Image(systemName: ready ? "checkmark.circle.fill" : "xmark.circle")
                .foregroundStyle(ready ? Color.speakInk : Color.speakMuted)
        }
        .padding(.vertical, 15)
    }

    private func runTest() {
        isTesting = true
        testMessage = nil
        Task { @MainActor in
            let result = await ReminderScheduler.scheduleDeliveryTest()
            switch result {
            case .scheduled:
                testMessage = "Test scheduled. Keep this screen open for five seconds."
            case .needsPermission:
                testMessage = "Permission is still needed."
            case .denied:
                testMessage = "Notifications are off. Open Notification Settings below."
            case .failed:
                testMessage = "The test couldn’t be scheduled. Try Notification Settings below."
            }
            isTesting = false
            await refresh()
        }
    }

    @MainActor
    private func refresh() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        alertsEnabled = settings.alertSetting == .enabled
        soundsEnabled = settings.soundSetting == .enabled
        scheduledSummaryEnabled = settings.scheduledDeliverySetting == .enabled
        pendingCount = await center.pendingNotificationRequests()
            .filter { $0.identifier.hasPrefix("SpeakIt.") }
            .count

        accessState = switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            alertsEnabled && soundsEnabled ? .ready : .denied
        case .notDetermined:
            .needsPermission
        case .denied:
            .denied
        @unknown default:
            .needsPermission
        }
    }
}

struct ICloudSyncSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.thoughtRepository) private var repository
    @AppStorage(ICloudSyncState.enabledKey) private var isEnabled = false
    @State private var isSyncing = false
    @State private var statusMessage: String?
    @State private var statusIsError = false

    private var isSignedIn: Bool { ICloudSyncState.isSignedIn }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Sync with iCloud", isOn: syncBinding)
                        .disabled(!isSignedIn)

                    if !isSignedIn {
                        Label(
                            "Sign in to iCloud in Settings to enable sync.",
                            systemImage: "icloud.slash"
                        )
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    }

                    if isEnabled {
                        Button {
                            syncNow()
                        } label: {
                            HStack {
                                Text("Sync now")
                                Spacer()
                                if isSyncing { ProgressView() }
                            }
                        }
                        .disabled(isSyncing)
                    }
                } header: {
                    Text("No Speak It account needed")
                } footer: {
                    Text("Your iPhone remains the primary copy. Speak It stores one encrypted-by-Apple library file in your private iCloud Drive container and keeps capture working when you are offline.")
                }

                if let statusMessage {
                    Section {
                        Label(
                            statusMessage,
                            systemImage: statusIsError ? "exclamationmark.triangle" : "checkmark.circle"
                        )
                        .foregroundStyle(statusIsError ? Color.orange : Color.speakMuted)
                    }
                }
            }
            .navigationTitle("iCloud Sync")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var syncBinding: Binding<Bool> {
        Binding(
            get: { isEnabled },
            set: { newValue in
                guard !newValue || isSignedIn else { return }
                isEnabled = newValue
                statusMessage = newValue ? "Sync is on" : "Sync is off"
                statusIsError = false
                if newValue { syncNow() }
            }
        )
    }

    private func syncNow() {
        guard let repository, !isSyncing else { return }
        isSyncing = true
        Task { @MainActor in
            let result = await repository.reconcileICloudSync()
            isSyncing = false
            statusMessage = result.userMessage
            statusIsError = !result.isSuccess
        }
    }
}

struct SpeakItPrivacyView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                privacyRow(
                    symbol: "person.crop.circle.badge.xmark",
                    title: "No account required",
                    detail: "Speak It works without a profile, email address, or sign-in."
                )
                privacyRow(
                    symbol: "iphone",
                    title: "Your library stays private",
                    detail: "Thoughts, tasks, and preferences are stored on this iPhone. If you turn on iCloud Sync, an encrypted-by-Apple copy is also kept in your private iCloud Drive container."
                )
                privacyRow(
                    symbol: "waveform",
                    title: "Recovery audio is temporary",
                    detail: "While you speak, a protected recording stays only on this iPhone. It is deleted as soon as your thought is saved. If capture is interrupted, you can retry or delete it from Capture history."
                )
                privacyRow(
                    symbol: "apple.logo",
                    title: "Speech recognition is provided by Apple",
                    detail: "Depending on your device and language, Apple speech recognition may use an internet connection."
                )
                privacyRow(
                    symbol: "bell",
                    title: "Reminders are opt-in",
                    detail: "Speak It requests notification access only when a captured thought needs a timed reminder."
                )
                privacyRow(
                    symbol: "location",
                    title: "Location is only for place reminders",
                    detail: "Speak It uses your location when you set Home or Work, when you use your current location, and when a thought says “here”. Your places and place reminders stay on this iPhone — they are never sent to analytics and are not included in iCloud Sync. Searching for an address or naming a place you pinned asks Apple Maps, so that one lookup goes to Apple, the same as it would in Maps."
                )
                privacyRow(
                    symbol: "chart.bar.xaxis",
                    title: "Anonymous analytics are content-free",
                    detail: "If enabled in Settings, Speak It measures actions such as captures saved, tasks completed, and subscription steps. It never sends recordings, transcripts, task titles, memory text, names, email addresses, or search words. You can turn this off at any time."
                )
            }
            .navigationTitle("Privacy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func privacyRow(
        symbol: String,
        title: String,
        detail: String
    ) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .medium))
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.body.weight(.medium))
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 5)
    }
}

struct TodayView_Previews: PreviewProvider {
    @MainActor
    static var previews: some View {
        let preview = PreviewData.make()
        return NavigationStack {
            TodayView(onCapture: {})
        }
        .modelContainer(preview.container)
        .environment(\.thoughtRepository, preview.repository)
        .environmentObject(SubscriptionStore())
    }
}
