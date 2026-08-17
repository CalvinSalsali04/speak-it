import SwiftUI

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
    @State private var showsReminderSettings = false
    @State private var showsCompleted = false
    @State private var showsCaptureHistory = false
    @State private var showsVocabulary = false
    @State private var showsPlaces = false
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
                    .tint(Color.speakInk)
                    .accessibilityIdentifier("settings.anonymous-analytics")

                    Toggle(isOn: $showsLockScreenTaskNames) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Show task names on the Lock Screen")
                                .foregroundStyle(Color.speakInk)
                            Text("Off by default. The Lock Screen widget shows only how many things are open, so a locked iPhone never reveals what they are. Home Screen widgets always show names.")
                                .font(.footnote)
                                .foregroundStyle(Color.speakMuted)
                        }
                    }
                    .tint(Color.speakInk)
                    .accessibilityIdentifier("settings.lock-screen-task-names")
                }

#if DEBUG
                Section {
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
                    Text("During this beta, profile details stay on this iPhone. Purchases and iCloud remain securely connected through your Apple Account.")
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
        .onAppear { subscriptionStore.refreshFreeAllowance() }
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
            detail: "Open Account & Settings → Capture anywhere to choose one method and test it. Speak It recommends the Action Button on supported iPhones and the Lock Screen everywhere else. Control Center and Back Tap are also available.",
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
            detail: "Speak It stores the original capture locally before organizing it. Temporary recovery audio is deleted after a successful save. Anonymous analytics never include recordings, transcripts, titles, names, email addresses, or search words. Open Capture history if an interrupted capture needs attention.",
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
