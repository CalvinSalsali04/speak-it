import SwiftUI
import UserNotifications

extension Notification.Name {
    static let speakItUseTestPrompt = Notification.Name("SpeakIt.useTestPrompt")
}

enum AccountProfileKeys {
    static let hasProfile = "SpeakIt.account.hasProfile"
    static let name = "SpeakIt.account.name"
    static let email = "SpeakIt.account.email"
}

struct AccountSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.thoughtRepository) private var repository
    @EnvironmentObject private var subscriptionStore: SubscriptionStore

    @AppStorage(AccountProfileKeys.hasProfile) private var hasProfile = false
    @AppStorage(AccountProfileKeys.name) private var profileName = ""
    @AppStorage(AccountProfileKeys.email) private var profileEmail = ""
    @AppStorage("SpeakIt.appearance") private var appearanceRawValue = SpeakItAppearance.firstInstallDefault.rawValue
    @AppStorage(SpeakItAnalytics.enabledKey) private var analyticsEnabled = true
    @AppStorage(LockScreenTodayVisibility.showsTaskNamesKey)
    private var showsLockScreenTaskNames = false

    @State private var showsAccountSetup = false
    @State private var showsPro = false
    @State private var showsCaptureSetup = false
    @State private var showsReadiness = false
    @State private var showsReminderSettings = false
    @State private var showsCompleted = false
    @State private var showsCaptureHistory = false
    @State private var showsVocabulary = false
    @State private var showsPlaces = false
    @State private var morningBriefEnabled = HabitDefaults.morningBriefEnabled
    @State private var morningBriefTime = HabitDefaults.morningBriefDate()
    @State private var isUpdatingMorningBrief = false
    @State private var morningBriefNotice: String?
    @State private var showsICloudSync = false
    @State private var showsPrivacy = false
    @State private var confirmsProfileRemoval = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    accountHeader

                    if hasProfile {
                        Button("Edit profile") { showsAccountSetup = true }
                        Button("Remove profile from this iPhone", role: .destructive) {
                            confirmsProfileRemoval = true
                        }
                    } else {
                        Button {
                            showsAccountSetup = true
                        } label: {
                            Label("Create your profile", systemImage: "person.crop.circle.badge.plus")
                        }
                    }
                }

                Section {
                    NavigationLink {
                        LearnSpeakItView()
                    } label: {
                        HStack(spacing: 14) {
                            settingsSymbol("book.closed")
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Learn Speak It")
                                    .foregroundStyle(Color.speakInk)
                                Text("Examples and short guides you can revisit anytime")
                                    .font(.footnote)
                                    .foregroundStyle(Color.speakMuted)
                            }
                        }
                    }
                    .accessibilityIdentifier("settings.learn-speak-it")
                }

                Section("Plan") {
                    Button {
                        showsPro = true
                    } label: {
                        HStack(spacing: 14) {
                            settingsSymbol(
                                subscriptionStore.hasProAccess ? "checkmark.seal.fill" : "sparkles"
                            )
                            VStack(alignment: .leading, spacing: 3) {
                                Text(subscriptionStore.hasProAccess ? "Speak It Pro" : "Speak It Free")
                                    .foregroundStyle(Color.speakInk)
                                Text(planDetail)
                                    .font(.footnote)
                                    .foregroundStyle(Color.speakMuted)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.speakMuted)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.speakIt)
                    .accessibilityIdentifier("settings.plan")

                    if !subscriptionStore.hasProAccess {
                        VStack(alignment: .leading, spacing: 8) {
                            ProgressView(
                                value: Double(subscriptionStore.freeCapturesUsed),
                                total: Double(FreePlanAllowance.lifetimeCaptureLimit)
                            )
                            .tint(Color.speakInk)

                            HStack {
                                Text("\(subscriptionStore.freeCapturesRemaining) captures remaining")
                                Spacer()
                                Text("Free captures do not renew")
                            }
                            .font(.caption)
                            .foregroundStyle(Color.speakMuted)
                        }
                        .padding(.vertical, 4)
                    }

                    if ReferralProgramConfiguration.isEnabled {
                        NavigationLink {
                            ReferralProgramView()
                        } label: {
                            HStack(spacing: 14) {
                                settingsSymbol("gift")
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("Give a month. Get a month.")
                                        .foregroundStyle(Color.speakInk)
                                    Text("Invite a friend and earn verified App Store rewards")
                                        .font(.footnote)
                                        .foregroundStyle(Color.speakMuted)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                        .accessibilityIdentifier("settings.referrals")
                    } else {
                        ShareLink(
                            item: SpeakItSharing.message,
                            subject: Text("Speak It")
                        ) {
                            HStack(spacing: 14) {
                                settingsSymbol("square.and.arrow.up")
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("Share Speak It")
                                        .foregroundStyle(Color.speakInk)
                                    Text("Send Speak It to someone who would find it useful.")
                                        .font(.footnote)
                                        .foregroundStyle(Color.speakMuted)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "square.and.arrow.up")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Color.speakMuted)
                            }
                        }
                        .accessibilityIdentifier("settings.share-speak-it")
                    }
                }

                Section("Appearance") {
                    Picker("Theme", selection: $appearanceRawValue) {
                        ForEach(SpeakItAppearance.allCases) { appearance in
                            Label(appearance.title, systemImage: appearance.symbol)
                                .tag(appearance.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Capture & reminders") {
                    settingsButton("Make Speak It ready", symbol: "checklist") {
                        showsReadiness = true
                    }
                    settingsButton("Capture anywhere", symbol: "waveform") {
                        showsCaptureSetup = true
                    }
                    settingsButton("Reminder check", symbol: "bell") {
                        showsReminderSettings = true
                    }
                    settingsButton("Names & phrases", symbol: "textformat.abc") {
                        showsVocabulary = true
                    }
                    settingsButton("Places", symbol: "house") {
                        showsPlaces = true
                    }
                    morningBriefRow
                }

                Section("Activity") {
                    settingsButton("Completed", symbol: "checkmark.circle") {
                        showsCompleted = true
                    }
                    settingsButton("Capture history", symbol: "clock.arrow.circlepath") {
                        showsCaptureHistory = true
                    }
                }

                Section("Data & privacy") {
                    if ICloudSyncState.isCapabilityConfigured {
                        settingsButton("iCloud sync", symbol: "icloud") {
                            showsICloudSync = true
                        }
                    }
                    settingsButton("Privacy", symbol: "hand.raised") {
                        showsPrivacy = true
                    }

                    Toggle(isOn: $analyticsEnabled) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Share anonymous app analytics")
                                .foregroundStyle(Color.speakInk)
                            Text("Helps improve reliability and understand which features are useful. Never includes what you say or type.")
                                .font(.footnote)
                                .foregroundStyle(Color.speakMuted)
                        }
                    }
                    .tint(Color.speakToggleTint)
                    .accessibilityIdentifier("settings.anonymous-analytics")

                    Toggle(isOn: $showsLockScreenTaskNames) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Show task names on the Lock Screen")
                                .foregroundStyle(Color.speakInk)
                            // Names every surface the promise actually covers.
                            // It used to say only "the Lock Screen widget",
                            // while StandBy, the capture receipt and Siri each
                            // read task text on a locked phone.
                            Text("Off by default. On the Lock Screen, in StandBy, and on capture receipts, Speak It shows only how many things are open — so a locked iPhone never reveals what they are. Home Screen widgets always show names, and a reminder notification shows the task it is reminding you about; iOS decides whether that is visible while locked.")
                                .font(.footnote)
                                .foregroundStyle(Color.speakMuted)
                        }
                    }
                    .tint(Color.speakToggleTint)
                    .accessibilityIdentifier("settings.lock-screen-task-names")
                }

#if DEBUG
                Section {
                    NavigationLink {
                        SpeechAccuracyLabView()
                    } label: {
                        Label("Measure speech accuracy", systemImage: "waveform.badge.magnifyingglass")
                    }

                    NavigationLink {
                        TestCustomerJourneyView(onUsePrompt: useTestPrompt)
                    } label: {
                        Label("Pretend to be a new customer", systemImage: "person.crop.circle.badge.clock")
                    }

                    if subscriptionStore.isDeveloperCustomerJourneyActive {
                        Label(
                            "Customer journey is active",
                            systemImage: "checkmark.circle.fill"
                        )
                        .foregroundStyle(Color.speakMuted)
                    }
                } header: {
                    Text("Developer testing")
                } footer: {
                    Text("Developer controls are removed automatically from App Store builds.")
                }
#endif
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color.speakBackground)
            .navigationTitle("Account & Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task { subscriptionStore.refreshFreeAllowance() }
        .onChange(of: showsLockScreenTaskNames) { _, _ in
            // Republishing carries the new choice into the snapshot the widget
            // reads, and already reloads the Today timelines.
            repository?.publishSharedTodaySnapshot()
        }
        .onChange(of: analyticsEnabled) { _, isEnabled in
            guard isEnabled else { return }
            SpeakItAnalytics.recordAppOpen(
                plan: subscriptionStore.hasProAccess ? .pro : .free
            )
        }
        .sheet(isPresented: $showsAccountSetup) {
            AccountSetupView()
        }
        .sheet(isPresented: $showsPro) {
            SpeakItProView(context: .account)
        }
        .sheet(isPresented: $showsCaptureSetup) {
            CaptureAnywhereSetupView()
        }
        .sheet(isPresented: $showsReadiness) {
            SpeakItReadinessView()
        }
        .sheet(isPresented: $showsReminderSettings) {
            ReminderSettingsView()
        }
        .sheet(isPresented: $showsCompleted) {
            CompletedLogView()
        }
        .sheet(isPresented: $showsCaptureHistory) {
            CaptureHistoryView()
        }
        .sheet(isPresented: $showsVocabulary) {
            SpeechVocabularyView()
        }
        .sheet(isPresented: $showsPlaces) {
            NavigationStack { SavedPlacesView() }
        }
        .sheet(isPresented: $showsICloudSync) {
            ICloudSyncSettingsView()
        }
        .sheet(isPresented: $showsPrivacy) {
            SpeakItPrivacyView()
        }
        .confirmationDialog(
            "Remove this profile?",
            isPresented: $confirmsProfileRemoval,
            titleVisibility: .visible
        ) {
            Button("Remove profile", role: .destructive, action: removeProfile)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your thoughts and subscription will not be deleted.")
        }
    }

    private var accountHeader: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.speakInverseSurface)
                    .frame(width: 58, height: 58)
                if hasProfile, let initial = profileName.first {
                    Text(String(initial).uppercased())
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(Color.speakInverseInk)
                } else {
                    Image(systemName: "person.fill")
                        .font(.system(size: 21, weight: .medium))
                        .foregroundStyle(Color.speakInverseInk)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(hasProfile ? profileName : "Your Speak It")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.speakInk)
                Text(hasProfile ? profileEmail : "Create an optional profile after you’ve tried the app.")
                    .font(.subheadline)
                    .foregroundStyle(Color.speakMuted)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 8)
    }

    private var planDetail: String {
        if subscriptionStore.hasProAccess { return "Unlimited capture is active" }
        let remaining = subscriptionStore.freeCapturesRemaining
        return "\(remaining) of \(FreePlanAllowance.lifetimeCaptureLimit) free captures remaining"
    }

    /// The one habit notification, beside the reminder preferences it
    /// resembles and nowhere else: a silent "2 due today · 1 overdue" at a
    /// wall-clock time. Off until switched on here; Today never asks.
    private var morningBriefRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: $morningBriefEnabled) {
                HStack(spacing: 14) {
                    settingsSymbol("sun.horizon")
                    Text("Morning brief")
                        .foregroundStyle(Color.speakInk)
                }
            }
            .tint(Color.speakToggleTint)
            .disabled(isUpdatingMorningBrief)
            .accessibilityIdentifier("settings.morning-brief")
            .accessibilityHint("A silent notification each morning with how many things are due.")

            if morningBriefEnabled {
                HStack(spacing: 14) {
                    Color.clear.frame(width: 30, height: 1)
                    DatePicker(selection: $morningBriefTime, displayedComponents: .hourAndMinute) {
                        Text("Time")
                            .foregroundStyle(Color.speakInk)
                    }
                    .accessibilityIdentifier("settings.morning-brief-time")
                }
            }

            Text(morningBriefNotice ?? "A silent note with what’s due, only on mornings that have something.")
                .font(.footnote)
                .foregroundStyle(morningBriefNotice == nil ? Color.speakMuted : Color.speakWarning)
        }
        .onAppear {
            // The brief can switch itself off after five unanswered mornings,
            // and permission can be revoked in iPhone Settings while it is on.
            // Neither is re-read while a switch-on is still waiting on the
            // permission prompt, or the row would snap back under the alert.
            guard !isUpdatingMorningBrief else { return }
            morningBriefEnabled = HabitDefaults.morningBriefEnabled
            guard morningBriefEnabled else { return }
            Task { @MainActor in
                let settings = await UNUserNotificationCenter.current().notificationSettings()
                if settings.authorizationStatus == .denied {
                    morningBriefNotice = "Notifications are off for Speak It, so no brief will arrive until they are on in iPhone Settings."
                }
            }
        }
        .onChange(of: morningBriefEnabled) { _, newValue in
            setMorningBrief(enabled: newValue)
        }
        .onChange(of: morningBriefTime) { _, newValue in
            HabitDefaults.setMorningBriefTime(from: newValue)
            repository?.refreshMorningBrief()
        }
    }

    private func setMorningBrief(enabled: Bool) {
        guard enabled != HabitDefaults.morningBriefEnabled else { return }
        morningBriefNotice = nil
        if enabled {
            isUpdatingMorningBrief = true
            Task { @MainActor in
                let authorized = await ReminderScheduler.requestNotificationAuthorizationIfNeeded()
                if authorized {
                    HabitDefaults.morningBriefEnabled = true
                    SpeakItAnalytics.track(.morningBriefEnabled(source: .settings))
                    repository?.refreshMorningBrief()
                } else {
                    morningBriefEnabled = false
                    morningBriefNotice = "Notifications are off for Speak It. Turn them on in iPhone Settings first."
                }
                isUpdatingMorningBrief = false
            }
        } else {
            HabitDefaults.morningBriefEnabled = false
            SpeakItAnalytics.track(.morningBriefDisabled(source: .settings))
            repository?.refreshMorningBrief()
        }
    }

    private func settingsButton(
        _ title: String,
        symbol: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                settingsSymbol(symbol)
                Text(title)
                    .foregroundStyle(Color.speakInk)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.speakMuted)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.speakIt)
        .accessibilityIdentifier("settings.\(title.lowercased().replacingOccurrences(of: " ", with: "-"))")
    }

    private func settingsSymbol(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(Color.speakInk)
            .frame(width: 30, height: 30)
            .background(Color.speakInk.opacity(0.07), in: RoundedRectangle(cornerRadius: 9))
    }

    private func removeProfile() {
        hasProfile = false
        profileName = ""
        profileEmail = ""
    }

#if DEBUG
    private func useTestPrompt(_ prompt: String) {
        dismiss()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(160))
            NotificationCenter.default.post(name: .speakItUseTestPrompt, object: prompt)
        }
    }
#endif
}

private struct AccountSetupView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AccountProfileKeys.hasProfile) private var hasProfile = false
    @AppStorage(AccountProfileKeys.name) private var storedName = ""
    @AppStorage(AccountProfileKeys.email) private var storedEmail = ""

    @State private var name: String
    @State private var email: String
    @FocusState private var focusedField: Field?

    private enum Field {
        case name
        case email
    }

    init() {
        _name = State(initialValue: UserDefaults.standard.string(forKey: AccountProfileKeys.name) ?? "")
        _email = State(initialValue: UserDefaults.standard.string(forKey: AccountProfileKeys.email) ?? "")
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            email.contains("@") && email.contains(".")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                        .textContentType(.name)
                        .textInputAutocapitalization(.words)
                        .focused($focusedField, equals: .name)
                    TextField("Email", text: $email)
                        .textContentType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .email)
                } header: {
                    Text(hasProfile ? "Your profile" : "Create your profile")
                } footer: {
                    // The behaviour is permanent, so it is stated as permanent.
                    // "During this beta" was the only use of the word in the
                    // app, on a screen App Review reaches on the way to Restore
                    // Purchases.
                    Text("Profile details stay on this iPhone. Purchases and iCloud remain securely connected through your Apple Account.")
                }

                Section {
                    Button(hasProfile ? "Save changes" : "Create profile") {
                        // Read before the write below flips it, so edits to an
                        // existing profile do not count as new profiles.
                        let isFirstTimeCreation = !hasProfile

                        storedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        storedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                        hasProfile = true

                        if isFirstTimeCreation {
                            SpeakItAnalytics.track(.profileCreated)
                        }
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.speakBackground)
            .navigationTitle(hasProfile ? "Edit Profile" : "Create Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focusedField = nil }
                }
            }
            .onAppear {
                if !hasProfile { focusedField = .name }
            }
        }
    }
}

#if DEBUG
struct SpeechBenchmarkCase: Identifiable, Equatable {
    let id: String
    let category: String
    let instruction: String
    let expected: String
    let criticalPhrases: [String]

    static let productSet: [Self] = [
        Self(
            id: "common-reminder",
            category: "Everyday",
            instruction: "Use your normal speaking voice.",
            expected: "Remind me tomorrow to call Sarah about the car keys",
            criticalPhrases: ["tomorrow", "Sarah", "car keys"]
        ),
        Self(
            id: "calendar-time",
            category: "Dates and times",
            instruction: "Say the whole sentence without pausing after Tuesday.",
            expected: "Schedule the dentist for Tuesday at four thirty",
            criticalPhrases: ["dentist", "Tuesday", "four thirty"]
        ),
        Self(
            id: "alarm-time",
            category: "Dates and times",
            instruction: "Use your normal speaking voice.",
            expected: "Set an alarm for six fifteen tomorrow morning",
            criticalPhrases: ["six fifteen", "tomorrow morning"]
        ),
        Self(
            id: "name-siobhan",
            category: "Names",
            instruction: "Pronounce the name as you naturally would.",
            expected: "Text Siobhan about the revised proposal",
            criticalPhrases: ["Siobhan", "revised proposal"]
        ),
        Self(
            id: "names-niamh-xavier",
            category: "Names",
            instruction: "Pronounce both names naturally.",
            expected: "Ask Niamh to send the invoice to Xavier",
            criticalPhrases: ["Niamh", "invoice", "Xavier"]
        ),
        Self(
            id: "names-nguyen-priya",
            category: "Names and time",
            instruction: "Use your normal speaking voice.",
            expected: "Lunch with Nguyen and Priya on Friday at noon",
            criticalPhrases: ["Nguyen", "Priya", "Friday", "noon"]
        ),
        Self(
            id: "quantities",
            category: "Numbers",
            instruction: "Keep a short pause between each item.",
            expected: "Buy twelve eggs two avocados and thirty one candles",
            criticalPhrases: ["twelve eggs", "two avocados", "thirty one candles"]
        ),
        Self(
            id: "self-correction",
            category: "Corrections",
            instruction: "Say the correction naturally in one take.",
            expected: "Call Maya at five no make that six thirty",
            criticalPhrases: ["Maya", "five", "six thirty"]
        ),
        Self(
            id: "final-word",
            category: "Final words",
            instruction: "Finish normally; do not exaggerate the last word.",
            expected: "Remember the spare key is behind the blue planter",
            criticalPhrases: ["spare key", "blue planter"]
        ),
        Self(
            id: "opening-word",
            category: "Opening words",
            instruction: "Begin as soon as the screen says Listening.",
            expected: "Urgent submit the permit application before Thursday",
            criticalPhrases: ["urgent", "permit application", "Thursday"]
        ),
        Self(
            id: "multi-action",
            category: "Longer capture",
            instruction: "Speak at a comfortable conversational pace.",
            expected: "Pick up the prescription then drop off the dry cleaning after work",
            criticalPhrases: ["prescription", "dry cleaning", "after work"]
        ),
        Self(
            id: "quiet-voice",
            category: "Quiet voice",
            instruction: "Speak more quietly than usual, but still naturally.",
            expected: "When I leave work remind me to buy milk for breakfast",
            criticalPhrases: ["leave work", "buy milk", "breakfast"]
        )
    ]
}

struct SpeechBenchmarkScore: Equatable {
    let wordErrors: Int
    let referenceWordCount: Int
    let criticalHits: Int
    let criticalCount: Int
    let isExact: Bool

    var contentAccuracy: Double {
        guard referenceWordCount > 0 else { return 0 }
        return max(0, 1 - Double(wordErrors) / Double(referenceWordCount))
    }

    var criticalAccuracy: Double {
        guard criticalCount > 0 else { return 0 }
        return Double(criticalHits) / Double(criticalCount)
    }
}

enum SpeechBenchmarkScorer {
    static func score(
        expected: String,
        observed: String,
        criticalPhrases: [String]
    ) -> SpeechBenchmarkScore {
        let reference = normalizedTokens(in: expected)
        let hypothesis = normalizedTokens(in: observed)
        let hits = criticalPhrases.reduce(into: 0) { count, phrase in
            if contains(normalizedTokens(in: phrase), in: hypothesis) {
                count += 1
            }
        }
        return SpeechBenchmarkScore(
            wordErrors: editDistance(reference, hypothesis),
            referenceWordCount: reference.count,
            criticalHits: hits,
            criticalCount: criticalPhrases.count,
            isExact: reference == hypothesis
        )
    }

    static func normalizedTokens(in text: String) -> [String] {
        let rawTokens = text
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .replacingOccurrences(of: "’", with: "'")
            .split(whereSeparator: { character in
                !character.isLetter && !character.isNumber && character != "'"
            })
            .map(String.init)

        let numberValues = [
            "zero": 0, "one": 1, "two": 2, "three": 3, "four": 4,
            "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9,
            "ten": 10, "eleven": 11, "twelve": 12, "thirteen": 13,
            "fourteen": 14, "fifteen": 15, "sixteen": 16, "seventeen": 17,
            "eighteen": 18, "nineteen": 19
        ]
        let tensValues = [
            "twenty": 20, "thirty": 30, "forty": 40, "fifty": 50,
            "sixty": 60, "seventy": 70, "eighty": 80, "ninety": 90
        ]

        var normalized: [String] = []
        var index = 0
        while index < rawTokens.count {
            let token = rawTokens[index]
            if (token == "a" || token == "p"),
               index + 1 < rawTokens.count,
               rawTokens[index + 1] == "m" {
                normalized.append(token + "m")
                index += 2
            } else if let tens = tensValues[token] {
                if index + 1 < rawTokens.count,
                   let ones = numberValues[rawTokens[index + 1]],
                   (1...9).contains(ones) {
                    normalized.append(String(tens + ones))
                    index += 2
                } else {
                    normalized.append(String(tens))
                    index += 1
                }
            } else if let number = numberValues[token] {
                normalized.append(String(number))
                index += 1
            } else {
                normalized.append(token)
                index += 1
            }
        }
        return normalized
    }

    private static func contains(_ needle: [String], in haystack: [String]) -> Bool {
        guard !needle.isEmpty, needle.count <= haystack.count else { return false }
        for start in 0...(haystack.count - needle.count) {
            if Array(haystack[start..<(start + needle.count)]) == needle {
                return true
            }
        }
        return false
    }

    private static func editDistance(_ reference: [String], _ hypothesis: [String]) -> Int {
        guard !reference.isEmpty else { return hypothesis.count }
        guard !hypothesis.isEmpty else { return reference.count }

        var previous = Array(0...hypothesis.count)
        for (referenceIndex, referenceToken) in reference.enumerated() {
            var current = Array(repeating: 0, count: hypothesis.count + 1)
            current[0] = referenceIndex + 1
            for (hypothesisIndex, hypothesisToken) in hypothesis.enumerated() {
                let substitution = previous[hypothesisIndex]
                    + (referenceToken == hypothesisToken ? 0 : 1)
                current[hypothesisIndex + 1] = min(
                    min(
                        previous[hypothesisIndex + 1] + 1,
                        current[hypothesisIndex] + 1
                    ),
                    substitution
                )
            }
            previous = current
        }
        return previous[hypothesis.count]
    }
}

private struct SpeechBenchmarkMeasurement: Codable, Identifiable, Equatable {
    let id: UUID
    let recordedAt: Date
    let caseID: String
    let category: String
    let expected: String
    let observed: String
    let wordErrors: Int
    let referenceWordCount: Int
    let criticalHits: Int
    let criticalCount: Int
    let isExact: Bool
    let profile: SpeechCaptureAudioProfile
    let requestedRecognizer: SpeechBenchmarkRecognizerMode
    let recognitionEngine: SpeechRecognitionEngine?
    let quality: SpeechCaptureAudioQuality?
}

private enum SpeechBenchmarkRecognizerMode: String, CaseIterable, Codable, Identifiable {
    case enhanced
    case legacy

    var id: String { rawValue }

    var title: String {
        switch self {
        case .enhanced: "Enhanced dictation"
        case .legacy: "Legacy comparison"
        }
    }
}

private enum SpeechBenchmarkStore {
    private static let key = "SpeakIt.debug.speechBenchmarkMeasurements"
    private static let maximumMeasurements = 500

    static var measurements: [SpeechBenchmarkMeasurement] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([SpeechBenchmarkMeasurement].self, from: data)) ?? []
    }

    static func append(_ measurement: SpeechBenchmarkMeasurement) -> [SpeechBenchmarkMeasurement] {
        var updated = measurements
        updated.append(measurement)
        updated = Array(updated.suffix(maximumMeasurements))
        if let data = try? JSONEncoder().encode(updated) {
            UserDefaults.standard.set(data, forKey: key)
        }
        return updated
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}

private struct SpeechBenchmarkSummary {
    let measurements: [SpeechBenchmarkMeasurement]

    var contentAccuracy: Double {
        let referenceWords = measurements.reduce(0) { $0 + $1.referenceWordCount }
        guard referenceWords > 0 else { return 0 }
        let errors = measurements.reduce(0) { $0 + $1.wordErrors }
        return max(0, 1 - Double(errors) / Double(referenceWords))
    }

    var criticalAccuracy: Double {
        let criticalCount = measurements.reduce(0) { $0 + $1.criticalCount }
        guard criticalCount > 0 else { return 0 }
        return Double(measurements.reduce(0) { $0 + $1.criticalHits })
            / Double(criticalCount)
    }

    var exactRate: Double {
        guard !measurements.isEmpty else { return 0 }
        return Double(measurements.filter(\.isExact).count) / Double(measurements.count)
    }

    var evidenceLabel: String {
        switch measurements.count {
        case 0..<12: "Too little data"
        case 12..<30: "Early signal"
        case 30..<100: "Directionally useful"
        default: "Credible local benchmark"
        }
    }
}

@MainActor
private struct SpeechAccuracyLabView: View {
    @StateObject private var transcriber = SpeechTranscriber()
    @AppStorage(SpeechCaptureAudioProfile.selectionDefaultsKey)
    private var profileRawValue = SpeechCaptureAudioProfile.spokenAudio.rawValue
    @State private var recognizerMode = SpeechBenchmarkRecognizerMode.enhanced
    @State private var caseIndex = 0
    @State private var activeCaseID: String?
    @State private var measurements = SpeechBenchmarkStore.measurements
    @State private var lastMeasurement: SpeechBenchmarkMeasurement?

    private var benchmarkCase: SpeechBenchmarkCase {
        SpeechBenchmarkCase.productSet[caseIndex % SpeechBenchmarkCase.productSet.count]
    }

    private var selectedProfile: SpeechCaptureAudioProfile {
        SpeechCaptureAudioProfile(rawValue: profileRawValue) ?? .spokenAudio
    }

    private var currentProfileMeasurements: [SpeechBenchmarkMeasurement] {
        measurements.filter {
            $0.profile == selectedProfile && $0.requestedRecognizer == recognizerMode
        }
    }

    private var summary: SpeechBenchmarkSummary {
        SpeechBenchmarkSummary(measurements: currentProfileMeasurements)
    }

    private var isBusy: Bool {
        switch transcriber.state {
        case .requestingPermission, .listening, .finalizing: true
        default: false
        }
    }

    var body: some View {
        List {
            Section {
                Picker("Microphone processing", selection: $profileRawValue) {
                    ForEach(SpeechCaptureAudioProfile.allCases) { profile in
                        Text(profile.title).tag(profile.rawValue)
                    }
                }
                .disabled(isBusy)

                Picker("Recognizer", selection: $recognizerMode) {
                    ForEach(SpeechBenchmarkRecognizerMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .disabled(isBusy)

                if currentProfileMeasurements.isEmpty {
                    Text("No scored recordings for this profile yet.")
                        .foregroundStyle(Color.speakMuted)
                } else {
                    LabeledContent(
                        "Content accuracy",
                        value: summary.contentAccuracy.formatted(.percent.precision(.fractionLength(1)))
                    )
                    LabeledContent(
                        "Critical details",
                        value: summary.criticalAccuracy.formatted(.percent.precision(.fractionLength(1)))
                    )
                    LabeledContent(
                        "Exact transcripts",
                        value: summary.exactRate.formatted(.percent.precision(.fractionLength(1)))
                    )
                    LabeledContent("Evidence", value: summary.evidenceLabel)
                }
            } header: {
                Text("Measured accuracy")
            } footer: {
                Text("The score ignores punctuation, capitalization, accents, and common spoken-number formatting. Critical details separately score names, dates, times, and quantities. Fewer than 30 recordings is only an early signal; 100 or more is the credible target.")
            }

            Section {
                Text(benchmarkCase.expected)
                    .font(.title3.weight(.semibold))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                Text(benchmarkCase.instruction)
                    .font(.footnote)
                    .foregroundStyle(Color.speakMuted)

                if !transcriber.transcript.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("HEARD")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(Color.speakMuted)
                        Text(transcriber.transcript)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 4)
                }

                captureButton

                if !isBusy {
                    Button("Skip this phrase") {
                        caseIndex = (caseIndex + 1) % SpeechBenchmarkCase.productSet.count
                        lastMeasurement = nil
                    }
                }
            } header: {
                Text("\(benchmarkCase.category) · Phrase \(caseIndex + 1) of \(SpeechBenchmarkCase.productSet.count)")
            } footer: {
                Text("Read the phrase exactly. Do not tap Record until you are ready; begin only after Speak It says Listening.")
            }

            if let lastMeasurement {
                let score = SpeechBenchmarkScore(
                    wordErrors: lastMeasurement.wordErrors,
                    referenceWordCount: lastMeasurement.referenceWordCount,
                    criticalHits: lastMeasurement.criticalHits,
                    criticalCount: lastMeasurement.criticalCount,
                    isExact: lastMeasurement.isExact
                )
                Section("Last result") {
                    LabeledContent(
                        "Content accuracy",
                        value: score.contentAccuracy.formatted(.percent.precision(.fractionLength(1)))
                    )
                    LabeledContent(
                        "Critical details",
                        value: "\(score.criticalHits) of \(score.criticalCount)"
                    )
                    LabeledContent(
                        "Recognizer",
                        value: lastMeasurement.recognitionEngine?.rawValue ?? "unknown"
                    )
                    Text(lastMeasurement.observed.isEmpty ? "No words recognized" : lastMeasurement.observed)
                        .foregroundStyle(Color.speakMuted)
                        .textSelection(.enabled)
                }
            }

            if !measurements.isEmpty {
                Section {
                    ShareLink(item: report) {
                        Label("Export benchmark report", systemImage: "square.and.arrow.up")
                    }
                    Button("Reset all measurements", role: .destructive) {
                        SpeechBenchmarkStore.clear()
                        measurements = []
                        lastMeasurement = nil
                    }
                } footer: {
                    Text("Measurements and recognized text stay in this developer build's local settings unless you export them. Audio is never retained by the lab or included in the report.")
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.speakBackground)
        .navigationTitle("Speech Accuracy Lab")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { transcriber.cancel() }
    }

    @ViewBuilder
    private var captureButton: some View {
        switch transcriber.state {
        case .requestingPermission:
            Button("Preparing recognizer…") {}
                .disabled(true)
        case .listening:
            Button {
                transcriber.stopAndFinalize(record)
            } label: {
                Label("Stop and score", systemImage: "stop.fill")
            }
        case .finalizing:
            Button("Scoring…") {}
                .disabled(true)
        case .permissionDenied:
            Text("Microphone and Speech Recognition permission are required.")
                .foregroundStyle(.red)
        case .unavailable:
            Text("Speech recognition is unavailable for the current locale.")
                .foregroundStyle(.red)
        case let .failed(message):
            VStack(alignment: .leading, spacing: 8) {
                Text(message).foregroundStyle(.red)
                Button("Try again") {
                    transcriber.resetAfterFailure()
                    startCapture()
                }
            }
        case .idle:
            Button(action: startCapture) {
                Label("Record this phrase", systemImage: "mic.fill")
            }
        }
    }

    private func startCapture() {
        let currentCase = benchmarkCase
        activeCaseID = currentCase.id
        lastMeasurement = nil
        Task {
            await transcriber.start(
                contextualPhrases: [],
                prefersEnhancedRecognition: true,
                forcesLegacyRecognitionForBenchmark: recognizerMode == .legacy,
                onAutomaticFinalization: record
            )
            switch transcriber.state {
            case .requestingPermission, .listening, .finalizing:
                break
            default:
                activeCaseID = nil
            }
        }
    }

    private func record(_ observed: String) {
        let currentCase = benchmarkCase
        guard activeCaseID == currentCase.id else { return }
        activeCaseID = nil

        let score = SpeechBenchmarkScorer.score(
            expected: currentCase.expected,
            observed: observed,
            criticalPhrases: currentCase.criticalPhrases
        )
        let measurement = SpeechBenchmarkMeasurement(
            id: UUID(),
            recordedAt: .now,
            caseID: currentCase.id,
            category: currentCase.category,
            expected: currentCase.expected,
            observed: observed,
            wordErrors: score.wordErrors,
            referenceWordCount: score.referenceWordCount,
            criticalHits: score.criticalHits,
            criticalCount: score.criticalCount,
            isExact: score.isExact,
            profile: selectedProfile,
            requestedRecognizer: recognizerMode,
            recognitionEngine: transcriber.recognitionEngine,
            quality: transcriber.lastAudioQuality
        )
        measurements = SpeechBenchmarkStore.append(measurement)
        lastMeasurement = measurement
        caseIndex = (caseIndex + 1) % SpeechBenchmarkCase.productSet.count
    }

    private var report: String {
        let rows = measurements.map { measurement in
            [
                measurement.recordedAt.ISO8601Format(),
                measurement.profile.rawValue,
                measurement.requestedRecognizer.rawValue,
                measurement.recognitionEngine?.rawValue ?? "unknown",
                measurement.caseID,
                "\(measurement.wordErrors)/\(measurement.referenceWordCount) word errors",
                "\(measurement.criticalHits)/\(measurement.criticalCount) critical",
                "expected: \(measurement.expected)",
                "observed: \(measurement.observed)"
            ].joined(separator: " | ")
        }
        return ([
            "Speak It Speech Accuracy Lab",
            "Measurements: \(measurements.count)",
            "Generated: \(Date.now.ISO8601Format())",
            ""
        ] + rows).joined(separator: "\n")
    }
}

private struct TestCustomerJourneyView: View {
    struct Prompt: Identifiable {
        let id: Int
        let text: String
        let expectedResult: String
    }

    @EnvironmentObject private var subscriptionStore: SubscriptionStore
    @AppStorage(AccountProfileKeys.hasProfile) private var hasProfile = false
    @AppStorage(AccountProfileKeys.name) private var profileName = ""
    @AppStorage(AccountProfileKeys.email) private var profileEmail = ""
    @AppStorage("SpeakIt.hasDismissedProDiscovery") private var dismissedDiscovery = false
    @AppStorage(SpeechCaptureAudioProfile.selectionDefaultsKey)
    private var speechAudioProfileRawValue = SpeechCaptureAudioProfile.spokenAudio.rawValue
    @State private var latestSpeechQuality = SpeechCaptureDiagnosticsStore.latest

    let onUsePrompt: (String) -> Void

    private let prompts = [
        Prompt(id: 1, text: "Remind me tomorrow at 9 AM to call Sarah about the car keys.", expectedResult: "A scheduled task in Today"),
        Prompt(id: 2, text: "Idea for a voice journal that creates a weekly workout recap.", expectedResult: "An idea in Memory"),
        Prompt(id: 3, text: "Alex’s favorite coffee is an oat milk latte.", expectedResult: "People context in Memory"),
        Prompt(id: 4, text: "Buy milk and pick up the dry cleaning after work.", expectedResult: "Two separate tasks"),
        Prompt(id: 5, text: "Every Monday and Thursday at 8 AM, remind me to go to the gym.", expectedResult: "A recurring reminder"),
        Prompt(id: 6, text: "The spare house key is inside the blue kitchen drawer.", expectedResult: "Useful reference in Memory"),
        Prompt(id: 7, text: "High priority: send the revised proposal to Maya by Friday at noon.", expectedResult: "A prioritized scheduled task"),
        Prompt(id: 8, text: "Maybe build a packing checklist that changes based on the weather.", expectedResult: "A new idea in Memory"),
        Prompt(id: 9, text: "Water the plants three days after I complete this task.", expectedResult: "Completion-based recurrence"),
        Prompt(id: 10, text: "Jordan is allergic to peanuts and prefers quiet restaurants.", expectedResult: "Important person context")
    ]

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(subscriptionStore.hasProAccess ? "Test Pro customer" : "Test Free customer")
                                .font(.headline)
                            Text("\(subscriptionStore.freeCapturesUsed) of \(FreePlanAllowance.lifetimeCaptureLimit) free captures used")
                                .font(.subheadline)
                                .foregroundStyle(Color.speakMuted)
                        }
                        Spacer()
                        Text(subscriptionStore.hasProAccess ? "PRO" : "FREE")
                            .font(.caption2.weight(.bold))
                            .tracking(0.8)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 6)
                            .foregroundStyle(Color.speakInverseInk)
                            .background(Color.speakInverseSurface, in: Capsule())
                    }

                    ProgressView(
                        value: Double(subscriptionStore.freeCapturesUsed),
                        total: Double(FreePlanAllowance.lifetimeCaptureLimit)
                    )
                    .tint(Color.speakInk)
                }
                .padding(.vertical, 6)
            } footer: {
                Text("This changes only account and plan-testing state. Your existing thoughts are never erased.")
            }

            Section("Start") {
                Button {
                    hasProfile = false
                    profileName = ""
                    profileEmail = ""
                    dismissedDiscovery = false
                    subscriptionStore.startDeveloperCustomerJourney()
                } label: {
                    Label("Start as a brand-new free user", systemImage: "arrow.counterclockwise")
                }

                Button {
                    if !subscriptionStore.isDeveloperCustomerJourneyActive {
                        subscriptionStore.startDeveloperCustomerJourney()
                    }
                    subscriptionStore.setDeveloperFreeCapturesUsed(
                        FreePlanAllowance.lifetimeCaptureLimit - 1
                    )
                } label: {
                    Label("Jump to one capture remaining", systemImage: "forward.end")
                }

                Button {
                    if !subscriptionStore.isDeveloperCustomerJourneyActive {
                        subscriptionStore.startDeveloperCustomerJourney()
                    }
                    subscriptionStore.setDeveloperFreeCapturesUsed(
                        FreePlanAllowance.lifetimeCaptureLimit
                    )
                } label: {
                    Label("Jump directly to the upgrade moment", systemImage: "lock")
                }
            }

            Section {
                Picker("Microphone processing", selection: $speechAudioProfileRawValue) {
                    ForEach(SpeechCaptureAudioProfile.allCases) { profile in
                        Text(profile.title).tag(profile.rawValue)
                    }
                }

                if let quality = latestSpeechQuality {
                    LabeledContent(
                        "Last recognizer",
                        value: quality.recognitionEngine?.rawValue ?? "unknown"
                    )
                    LabeledContent(
                        "Last signal",
                        value: "RMS \(quality.rmsDecibels.formatted(.number.precision(.fractionLength(1)))) dB · peak \(quality.peakDecibels.formatted(.number.precision(.fractionLength(1)))) dB"
                    )
                    LabeledContent(
                        "Clipped samples",
                        value: quality.clippedSampleFraction.formatted(.percent.precision(.fractionLength(2)))
                    )
                    LabeledContent("Audio length", value: "\(quality.durationMilliseconds) ms")
                } else {
                    Text("Make one voice capture to record the first content-free signal measurement.")
                        .foregroundStyle(Color.speakMuted)
                }

                Button("Refresh last measurement") {
                    latestSpeechQuality = SpeechCaptureDiagnosticsStore.latest
                }
            } header: {
                Text("Voice recognition A/B")
            } footer: {
                Text("Spoken audio is the product baseline. Raw measurement and voice processed exist only in developer builds so the same phrases can be compared on a real iPhone. These measurements contain no recording or transcript.")
            }

            Section {
                ForEach(prompts) { prompt in
                    Button {
                        onUsePrompt(prompt.text)
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("\(prompt.id). \(prompt.text)")
                                .foregroundStyle(Color.speakInk)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(prompt.expectedResult)
                                .font(.caption)
                                .foregroundStyle(Color.speakMuted)
                        }
                        .padding(.vertical, 5)
                    }
                    .buttonStyle(.speakIt)
                }
            } header: {
                Text("Free-user prompts")
            } footer: {
                Text("Tap a prompt to open a real text capture. Save it, then return here for the next prompt. After the tenth, tap Capture once more to see the limit and upgrade flow.")
            }

            if subscriptionStore.isDeveloperCustomerJourneyActive {
                Section {
                    Button("End customer test and use App Store state", role: .destructive) {
                        subscriptionStore.endDeveloperCustomerJourney()
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.speakBackground)
        .navigationTitle("Test Customer Journey")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            subscriptionStore.refreshFreeAllowance()
            latestSpeechQuality = SpeechCaptureDiagnosticsStore.latest
        }
    }
}
#endif
private enum LearnSpeakItGroup: String, CaseIterable {
    case start = "Start here"
    case speak = "Things you can say"
    case reach = "Capture and continue"
    case trust = "Trust and recovery"
}

private struct LearnSpeakItLesson: Identifiable, Hashable {
    let id: String
    let group: LearnSpeakItGroup
    let symbol: String
    let title: String
    let summary: String
    let detail: String
    let examples: [String]

    static let all: [LearnSpeakItLesson] = [
        .init(
            id: "getting-started",
            group: .start,
            symbol: "waveform",
            title: "Getting started",
            summary: "Speak naturally, then check the saved result.",
            detail: "Tap the waveform, say one thought in your own words, and pause. Speak It keeps the original capture before organizing it. Tap the organized row on the Remembered screen whenever you want to review or correct it.",
            examples: [
                "Buy toothpaste",
                "Remember Daniel prefers oat milk"
            ]
        ),
        .init(
            id: "today-memory",
            group: .start,
            symbol: "arrow.left.arrow.right.circle",
            title: "Today and Memory",
            summary: "Actions go to Today; knowledge goes to Memory.",
            detail: "Today holds tasks, reminders, events, and anything you plan to do. Memory keeps ideas, people, notes, and useful facts you may want to find later. If Speak It is unsure, the thought goes to Needs review instead of being guessed silently.",
            examples: [
                "Call the dentist tomorrow",
                "Remember the spare key is in the blue drawer"
            ]
        ),
        .init(
            id: "review-correct",
            group: .start,
            symbol: "pencil.and.list.clipboard",
            title: "Review and correct",
            summary: "Change the organized result without losing what you said.",
            detail: "Open any row in Today or Memory to adjust its title, type, priority, date, person, or category. The original capture remains read-only underneath, so a correction never erases your words. Anything Speak It is unsure about waits in Needs review instead of pretending to be certain.",
            examples: []
        ),
        .init(
            id: "multiple-thoughts",
            group: .speak,
            symbol: "square.stack.3d.up",
            title: "Multiple thoughts at once",
            summary: "You can keep talking instead of capturing each thought separately.",
            detail: "Speak It can separate unrelated actions and memories from one capture while preserving the original wording as a single session. Review appears automatically when several items were saved.",
            examples: [
                "Buy milk, call Mom tomorrow, and remember Alex likes golf"
            ]
        ),
        .init(
            id: "reminders-alarms",
            group: .speak,
            symbol: "bell.badge",
            title: "Reminders and alarms",
            summary: "Ask for the kind of attention you actually want.",
            detail: "A phrase such as ‘remind me’ creates a normal notification. Explicit alarm wording such as ‘wake me’ or ‘set an alarm’ requests a stronger alarm on supported iPhones. Permission is requested only when that feature is first needed.",
            examples: [
                "Remind me to call Mom tomorrow at 5",
                "Wake me tomorrow at 7",
                "Remind me every Monday at 9 to file the report"
            ]
        ),
        .init(
            id: "places",
            group: .speak,
            symbol: "location",
            title: "Place reminders",
            summary: "Ask to be reminded when you arrive or leave.",
            detail: "Set Home, Work, or another saved place when Speak It asks. Location stays on this iPhone. A place reminder remains in Needs review until its place and required permission are ready, so it never looks active when it cannot work.",
            examples: [
                "Remind me when I get home to start the laundry",
                "Remind me when I leave work to buy milk"
            ]
        ),
        .init(
            id: "capture-anywhere",
            group: .reach,
            symbol: "iphone.radiowaves.left.and.right",
            title: "Capture from anywhere",
            summary: "Reach Speak It without finding the app first.",
            detail: "Open Account & Settings → Capture anywhere to choose one method and test it. Speak It recommends the Action Button on supported iPhones and the Lock Screen everywhere else. Control Center, a Home Screen Capture widget, and Back Tap are also available.",
            examples: []
        ),
        .init(
            id: "widgets",
            group: .reach,
            symbol: "rectangle.grid.2x2",
            title: "Widgets",
            summary: "Capture quickly or see Today at a glance.",
            detail: "Add Speak It Capture to the Home Screen or Lock Screen for one-tap voice capture. Add Speak It Today to see open tasks and complete them from supported Home Screen widgets. Lock Screen task names stay hidden unless you explicitly turn them on in Account & Settings.",
            examples: []
        ),
        .init(
            id: "calendar-handoffs",
            group: .reach,
            symbol: "calendar.badge.plus",
            title: "Calendar and other apps",
            summary: "Speak It prepares an action; you stay in control of sending it.",
            detail: "Open a timed task or event and choose Add to Calendar. Apple’s event editor lets you review the title, time, duration, and calendar before anything is added. Person follow-ups can similarly prepare a message that iOS sends only after your approval.",
            examples: [
                "Dentist appointment Friday at 2"
            ]
        ),
        .init(
            id: "privacy-recovery",
            group: .trust,
            symbol: "lock.shield",
            title: "Privacy and recovery",
            summary: "Your words stay recoverable without becoming analytics.",
            detail: "Speak It stores and organizes the original capture locally. Typing and organization work offline; depending on your device and language, Apple speech recognition may use an internet connection. Temporary recovery audio is deleted after a successful save. Anonymous analytics never include recordings, transcripts, titles, names, email addresses, or search words. Open Capture history if an interrupted capture needs attention.",
            examples: []
        ),
        .init(
            id: "free-and-pro",
            group: .trust,
            symbol: "checkmark.seal",
            title: "Free and Pro",
            summary: "Try the complete product before deciding whether to subscribe.",
            detail: "Your first 10 captures include the full Speak It experience and never renew. Pro removes that capture limit. Everything you already saved stays available if you do not subscribe. Apple handles payment and Pro access, and Restore Purchases reconnects an eligible purchase made with the same Apple Account.",
            examples: []
        )
    ]
}

private struct LearnSpeakItView: View {
    var body: some View {
        List {
            Section {
                Text("Learn one useful thing at a time. These guides are always here when you want them.")
                    .font(.subheadline)
                    .foregroundStyle(Color.speakMuted)
                    .listRowBackground(Color.speakSurface)
            }

            ForEach(LearnSpeakItGroup.allCases, id: \.self) { group in
                Section(group.rawValue) {
                    ForEach(LearnSpeakItLesson.all.filter { $0.group == group }) { lesson in
                        NavigationLink {
                            LearnSpeakItLessonView(lesson: lesson)
                        } label: {
                            Label {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(lesson.title)
                                        .foregroundStyle(Color.speakInk)
                                    Text(lesson.summary)
                                        .font(.footnote)
                                        .foregroundStyle(Color.speakMuted)
                                        .lineLimit(2)
                                }
                            } icon: {
                                Image(systemName: lesson.symbol)
                                    .foregroundStyle(Color.speakInk)
                            }
                        }
                        .accessibilityIdentifier("learn.\(lesson.id)")
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.speakBackground)
        .navigationTitle("Learn Speak It")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            SpeakItAnalytics.track(.learnSpeakItOpened)
        }
    }
}

private struct LearnSpeakItLessonView: View {
    let lesson: LearnSpeakItLesson

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Image(systemName: lesson.symbol)
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(Color.speakInverseInk)
                    .frame(width: 56, height: 56)
                    .background(Color.speakInverseSurface, in: RoundedRectangle(cornerRadius: 18))

                VStack(alignment: .leading, spacing: 8) {
                    Text(lesson.title)
                        .font(.largeTitle.weight(.semibold))
                        .foregroundStyle(Color.speakInk)
                    Text(lesson.summary)
                        .font(.title3)
                        .foregroundStyle(Color.speakMuted)
                }

                Text(lesson.detail)
                    .font(.body)
                    .foregroundStyle(Color.speakInk)
                    .fixedSize(horizontal: false, vertical: true)

                if !lesson.examples.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("TRY SAYING")
                            .font(.caption.weight(.medium))
                            .tracking(1.4)
                            .foregroundStyle(Color.speakMuted)

                        ForEach(lesson.examples, id: \.self) { example in
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: "quote.bubble")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Color.speakMuted)
                                    .padding(.top, 3)
                                Text(example)
                                    .font(.body.weight(.medium))
                                    .foregroundStyle(Color.speakInk)
                                Spacer(minLength: 0)
                            }
                            .padding(16)
                            .background(
                                Color.speakSurface,
                                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .stroke(Color.speakDivider, lineWidth: 1)
                            }
                        }
                    }
                }
            }
            .padding(22)
        }
        .scrollIndicators(.hidden)
        .background(Color.speakBackground.ignoresSafeArea())
        .navigationTitle(lesson.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
