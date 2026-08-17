import EventKit
import EventKitUI
import MessageUI
import SwiftUI
import UserNotifications

struct ItemEditorView: View {
    private enum NotificationDeliveryState: Equatable {
        case checking
        case ready
        case needsPermission
        case denied
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.thoughtRepository) private var repository

    let item: CapturedItem

    /// Resolved once on open. The asterisk has to stay on the field the person
    /// arrived to fill, so it must not re-derive from the item — or from live
    /// edits — and hop to a different row mid-edit.
    private let requirement: ClarificationRequirement?

    @State private var title: String
    @State private var itemType: ItemType
    @State private var category: ItemCategory
    @State private var priority: ItemPriority
    @State private var hasDueDate: Bool
    @State private var dueDate: Date
    @State private var hasReminder: Bool
    @State private var reminderDate: Date
    @State private var repeats: Bool
    @State private var recurrenceFrequency: RecurrenceFrequency
    @State private var recurrenceInterval: Int
    @State private var recurrenceAfterCompletion: Bool
    @State private var personName: String
    @State private var needsClarification: Bool
    @State private var errorMessage: String?
    @State private var showsDeleteConfirmation = false
    @State private var showsCalendarComposer = false
    @State private var showsMessageComposer = false
    @State private var integrationNotice: String?
    /// What this place reminder is currently waiting on, or `nil` when it is not
    /// a place reminder or nothing is missing. Recomputed rather than stored,
    /// because it depends on live permission and on a Home the person may set
    /// without ever leaving this screen.
    @State private var locationBlocker: LocationReminderBlocker?
    @State private var notificationDeliveryState = NotificationDeliveryState.checking
    @State private var isNamingPlace = false
    @State private var capturedPlaceName: String?
    @State private var placeNamingFailed = false

    /// The trigger as the person is currently editing it. `nil` once they
    /// remove it, which is why `hadLocationIntent` is kept separately — without
    /// it, "removed" and "never had one" would be the same value and Save could
    /// not tell whether to clear the stored trigger or leave it alone.
    @State private var editedLocationIntent: LocationIntent?
    private let hadLocationIntent: Bool

    init(item: CapturedItem) {
        self.item = item
        self.requirement = item.clarificationRequirement
        self.hadLocationIntent = item.locationIntent != nil
        _editedLocationIntent = State(initialValue: item.locationIntent)
        _title = State(initialValue: item.displayTitle)
        _itemType = State(initialValue: item.itemType)
        _category = State(initialValue: item.category)
        _priority = State(initialValue: item.priority)
        _hasDueDate = State(initialValue: item.dueDate != nil)
        _dueDate = State(initialValue: item.dueDate ?? .now)
        _hasReminder = State(initialValue: item.reminderDate != nil)
        _reminderDate = State(initialValue: item.reminderDate ?? item.dueDate ?? .now)
        let recurrence = RecurrenceStore.rule(for: item.id)
        _repeats = State(initialValue: recurrence != nil)
        _recurrenceFrequency = State(initialValue: recurrence?.frequency ?? .weekly)
        _recurrenceInterval = State(initialValue: recurrence?.interval ?? 1)
        _recurrenceAfterCompletion = State(initialValue: recurrence?.anchor == .completionDate)
        _personName = State(initialValue: item.personName ?? "")
        _needsClarification = State(initialValue: item.needsClarification)
    }

    var body: some View {
        NavigationStack {
            Form {
                if let requirement {
                    Section {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            // Resolves in place the moment the field below is
                            // filled, so the ask never contradicts the form.
                            if isRequirementResolved {
                                Image(systemName: "checkmark")
                                    .font(.footnote.weight(.bold))
                                    .foregroundStyle(Color.speakMuted)
                            } else {
                                Text("*")
                                    .font(.body.weight(.bold))
                                    .foregroundStyle(Color.speakWarning)
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(isRequirementResolved ? "Ready to save" : requirement.listLabel)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(isRequirementResolved ? Color.speakMuted : Color.speakInk)
                                Text(
                                    isRequirementResolved
                                        ? "Saving takes this out of Needs review."
                                        : requirement.editorPrompt
                                )
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                }

                // The way out of a place reminder is offered here rather than
                // only in Settings. Someone who says "remind me when I get home"
                // before ever setting a Home should not have to leave the
                // thought, find the setting, and come back to it — the gap and
                // the fix belong on the same screen.
                if let locationBlocker {
                    Section {
                        locationFix(for: locationBlocker)
                    } footer: {
                        Text(
                            locationBlocker.editorPrompt(
                                for: item.locationIntent?.place ?? .currentLocation
                            )
                        )
                    }
                }

                if editedLocationIntent != nil,
                   editedLocationIntent?.isRetired != true,
                   locationBlocker == nil,
                   notificationDeliveryState != .ready {
                    Section {
                        notificationDeliveryFix
                    } footer: {
                        Text("Location can detect the crossing, but Speak It also needs notification access to show the reminder.")
                    }
                }

                // Naming a frozen "here" is offered, never done automatically:
                // the lookup sends the coordinate to Apple, so it stays the
                // person's decision rather than a side effect of speaking.
                if canNameCapturedPlace {
                    Section {
                        Button {
                            Task { await nameCapturedPlace() }
                        } label: {
                            HStack {
                                Label("Name this place", systemImage: "mappin.and.ellipse")
                                Spacer()
                                if isNamingPlace { ProgressView() }
                            }
                        }
                        .disabled(isNamingPlace)
                    } footer: {
                        Text(placeNamingFooter)
                    }
                }

                Section("Thought") {
                    TextField("Title", text: $title, axis: .vertical)
                        .textInputAutocapitalization(.sentences)
                        .autocorrectionDisabled(false)
                        .accessibilityLabel("Item title")

                    Picker(selection: $itemType) {
                        ForEach(ItemType.allCases) { type in
                            Label(type.displayName, systemImage: type.systemImage)
                                .tag(type)
                        }
                    } label: {
                        requiredLabel("Type", when: .type)
                    }

                    Picker("Category", selection: $category) {
                        ForEach(ItemCategory.allCases) { category in
                            Text(category.displayName).tag(category)
                        }
                    }

                    Picker("Priority", selection: $priority) {
                        ForEach(ItemPriority.allCases) { priority in
                            Text(priority.displayName).tag(priority)
                        }
                    }
                }

                Section("Timing") {
                    Toggle("Has a due date", isOn: $hasDueDate)
                        .accessibilityHint("Turn off to keep this item unscheduled")

                    if hasDueDate {
                        DatePicker(
                            "Due",
                            selection: $dueDate,
                            displayedComponents: [.date, .hourAndMinute]
                        )
                    }

                    Toggle(isOn: $hasReminder) {
                        requiredLabel("Remind me", when: .time)
                    }
                    .accessibilityHint("Schedules an alert for this thought")

                    if hasReminder {
                        DatePicker(
                            "Reminder time",
                            selection: $reminderDate,
                            in: Date.now...,
                            displayedComponents: [.date, .hourAndMinute]
                        )

                        if inferredReminderDelivery == .alarm {
                            Label(
                                "This is an alarm because you explicitly asked for one.",
                                systemImage: "alarm"
                            )
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        }
                    }

                    if itemType.isActionable {
                        Toggle("Repeat", isOn: $repeats)

                        if repeats {
                            Picker("Frequency", selection: $recurrenceFrequency) {
                                ForEach(RecurrenceFrequency.allCases, id: \.self) { frequency in
                                    Text(recurrenceTitle(frequency)).tag(frequency)
                                }
                            }

                            Stepper(
                                "Every \(recurrenceInterval) \(recurrenceUnit)",
                                value: $recurrenceInterval,
                                in: 1...30
                            )

                            Picker("Next occurrence", selection: $recurrenceAfterCompletion) {
                                Text("From schedule").tag(false)
                                Text("After completion").tag(true)
                            }
                        }
                    }
                }

                if let intent = editedLocationIntent {
                    locationSection(intent)
                }

                Section("Details") {
                    HStack {
                        if requirement == .person {
                            requiredLabel("Person", when: .person)
                                .layoutPriority(1)
                        }
                        TextField(
                            requirement == .person ? "Name" : "Person (optional)",
                            text: $personName
                        )
                        .multilineTextAlignment(requirement == .person ? .trailing : .leading)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled(false)
                        .textContentType(.name)
                    }
                    Toggle("Needs clarification", isOn: $needsClarification)
                }

                if canContinueInAnotherApp {
                    Section {
                        if calendarStartDate != nil {
                            Button {
                                showsCalendarComposer = true
                            } label: {
                                Label("Add to Calendar", systemImage: "calendar.badge.plus")
                            }
                        }

                        if let communicationDraft {
                            Button {
                                showsMessageComposer = true
                            } label: {
                                Label(
                                    communicationDraft.recipientName.map { "Prepare message to \($0)" }
                                        ?? "Prepare message",
                                    systemImage: "message"
                                )
                            }
                            .disabled(!MessageComposeSheet.canSendText)
                        }

                        if let integrationNotice {
                            Label(integrationNotice, systemImage: "checkmark.circle.fill")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    } header: {
                        Text("Continue")
                    } footer: {
                        Text(integrationFooter)
                    }
                }

                Section("Originally captured") {
                    Text(item.captureSession?.originalTranscription ?? item.originalTextSegment)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .accessibilityLabel("Original thought")

                    LabeledContent(
                        "Captured",
                        value: item.createdAt.formatted(date: .abbreviated, time: .shortened)
                    )
                    if let source = item.captureSession?.captureSource {
                        LabeledContent("Source", value: source.displayName)
                    }

                    if let session = item.captureSession {
                        NavigationLink {
                            CaptureSessionReviewView(session: session)
                        } label: {
                            requiredLabel(
                                session.items.count > 1
                                    ? "Review \(session.items.count) extracted items"
                                    : "Split or reorganize this capture",
                                when: .splitDecision,
                                systemImage: "square.stack.3d.up"
                            )
                        }
                    }
                }

                Section("Actions") {
                    Button {
                        perform {
                            try repository?.setCompleted(item, completed: !item.isCompleted)
                        }
                    } label: {
                        Label(
                            item.isCompleted ? "Mark incomplete" : "Mark complete",
                            systemImage: item.isCompleted ? "arrow.uturn.backward.circle" : "checkmark.circle"
                        )
                    }

                    Button {
                        perform(dismissAfterward: true) {
                            try repository?.setArchived(item, archived: !item.isArchived)
                        }
                    } label: {
                        Label(
                            item.isArchived ? "Restore to Inbox" : "Archive",
                            systemImage: item.isArchived ? "tray.and.arrow.up" : "archivebox"
                        )
                    }

                    Button(role: .destructive) {
                        showsDeleteConfirmation = true
                    } label: {
                        Label("Delete permanently", systemImage: "trash")
                    }
                }
            }
            .navigationTitle("Edit Thought")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                refreshLocationBlocker()
                await refreshNotificationDeliveryState()
            }
            // Both of the things a place reminder waits on can change while this
            // screen is open: Home can be set on the pushed picker, and access
            // can be granted from the system prompt. Either one re-reads.
            .onReceive(
                NotificationCenter.default.publisher(for: SavedPlaceStore.didChangeNotification)
            ) { _ in
                refreshLocationBlocker()
            }
            .onReceive(
                NotificationCenter.default.publisher(
                    for: UIApplication.didBecomeActiveNotification
                )
            ) { _ in
                refreshLocationBlocker()
                Task { await refreshNotificationDeliveryState() }
            }
            .onReceive(
                NotificationCenter.default.publisher(
                    for: LocationReminderMonitor.authorizationDidChangeNotification
                )
            ) { _ in
                refreshLocationBlocker()
            }
            // Supplying the missing input is the whole point of opening a flagged
            // item, so it clears the flag rather than leaving the person to find
            // the toggle themselves. One-directional and visible: undoing the
            // edit does not silently re-flag, and the toggle shows what happened.
            .onChange(of: isRequirementSatisfied) { _, satisfied in
                guard satisfied, needsClarification else { return }
                needsClarification = false
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .confirmationDialog(
                "Delete this thought permanently?",
                isPresented: $showsDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    perform(dismissAfterward: true) {
                        try repository?.delete(item)
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes the item and its original capture when no other items use it. This cannot be undone.")
            }
            .sheet(isPresented: $showsCalendarComposer) {
                CalendarEventComposer(
                    isPresented: $showsCalendarComposer,
                    title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                    startDate: calendarStartDate ?? .now,
                    notes: item.captureSession?.originalTranscription ?? item.originalTextSegment
                ) { saved in
                    if saved { integrationNotice = "Added to Calendar" }
                }
            }
            .sheet(isPresented: $showsMessageComposer) {
                MessageComposeSheet(
                    isPresented: $showsMessageComposer,
                    body: communicationDraft?.body ?? ""
                ) { result in
                    handleMessageResult(result)
                }
            }
            .repositoryErrorAlert($errorMessage)
        }
    }

    private var calendarStartDate: Date? {
        guard itemType.isActionable else { return nil }
        if hasDueDate { return dueDate }
        if hasReminder { return reminderDate }
        return nil
    }

    private var communicationDraft: CommunicationDraft? {
        CommunicationDraftBuilder.draft(title: title, personName: personName)
    }

    /// A field label that carries the required marker when this editor was opened
    /// for that specific gap. The asterisk clears the moment the field is filled,
    /// so the person can see they have answered it before saving.
    @ViewBuilder
    private func requiredLabel(
        _ text: String,
        when marker: ClarificationRequirement,
        systemImage: String? = nil
    ) -> some View {
        let isRequired = requirement == marker
        HStack(spacing: 4) {
            if let systemImage {
                Label(text, systemImage: systemImage)
            } else {
                Text(text)
            }

            if isRequired {
                // Stays put once answered, greyed rather than gone, so the
                // person can see they addressed the thing they came here for.
                Text("*")
                    .font(.body.weight(.bold))
                    .foregroundStyle(isRequirementResolved ? Color.speakMuted : Color.speakWarning)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityLabel(isRequired && !isRequirementResolved ? "\(text), required" : text)
    }

    /// The place trigger, stated plainly and made editable.
    ///
    /// Before this existed the editor showed a live place reminder as
    /// "Remind me: off" with no Location row anywhere, so the one screen meant
    /// for managing an item was also the screen that denied the item had a
    /// trigger at all. The person could not see which place, which crossing, or
    /// whether it repeated, and the only way to stop it was to delete the whole
    /// thought.
    @ViewBuilder
    private func locationSection(_ intent: LocationIntent) -> some View {
        Section {
            LabeledContent("Place", value: intent.place.displayName)

            Picker("Trigger", selection: locationEventBinding) {
                Text("When I arrive").tag(LocationEvent.arrive)
                Text("When I leave").tag(LocationEvent.leave)
            }

            Toggle("Every time", isOn: locationRepeatsBinding)
                .accessibilityHint(
                    "On reminds you every time you cross this place. Off reminds you once."
                )

            LabeledContent("Status") {
                Text(locationStatusText)
                    .foregroundStyle(locationBlocker == nil ? Color.speakMuted : Color.speakWarning)
            }

            Button(role: .destructive) {
                editedLocationIntent = nil
            } label: {
                Text("Remove place reminder")
            }
            .accessibilityHint("Keeps the thought and stops reminding you at this place")
        } header: {
            Text("Place")
        } footer: {
            Text(locationSectionFooter(intent))
        }
    }

    private var locationEventBinding: Binding<LocationEvent> {
        Binding(
            get: { editedLocationIntent?.event ?? .arrive },
            set: { editedLocationIntent?.event = $0 }
        )
    }

    private var locationRepeatsBinding: Binding<Bool> {
        Binding(
            get: { editedLocationIntent?.repeats ?? false },
            set: { editedLocationIntent?.repeats = $0 }
        )
    }

    /// Never claims a reminder is active while something is blocking it — the
    /// whole point of naming the blocker here is that "on" and "actually being
    /// watched by iOS" are different states.
    private var locationStatusText: String {
        if let locationBlocker { return locationBlocker.listLabel }
        if let firedAt = editedLocationIntent?.firedAt,
           editedLocationIntent?.repeats == false {
            return "Delivered \(firedAt.formatted(date: .abbreviated, time: .shortened))"
        }
        switch notificationDeliveryState {
        case .checking: return "Checking notifications"
        case .needsPermission: return "Needs notification permission"
        case .denied: return "Notifications off"
        case .ready: break
        }
        return "Active"
    }

    @ViewBuilder
    private var notificationDeliveryFix: some View {
        switch notificationDeliveryState {
        case .checking:
            HStack {
                ProgressView()
                Text("Checking notification access…")
            }
        case .needsPermission:
            Button {
                Task {
                    _ = await ReminderScheduler.requestNotificationAuthorizationIfNeeded()
                    await refreshNotificationDeliveryState()
                }
            } label: {
                Label("Allow notifications", systemImage: "bell.badge")
            }
        case .denied:
            Button {
                guard let url = URL(string: UIApplication.openNotificationSettingsURLString) else {
                    return
                }
                UIApplication.shared.open(url)
            } label: {
                Label("Open Notification Settings", systemImage: "gear")
            }
        case .ready:
            EmptyView()
        }
    }

    @MainActor
    private func refreshNotificationDeliveryState() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        notificationDeliveryState = switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: .ready
        case .notDetermined: .needsPermission
        case .denied: .denied
        @unknown default: .needsPermission
        }
    }

    private func locationSectionFooter(_ intent: LocationIntent) -> String {
        if intent.repeats {
            return "Speak It reminds you every time you \(intent.event.verbPhrase) \(intent.place.displayName)."
        }
        return "Speak It reminds you the next time you \(intent.event.verbPhrase) \(intent.place.displayName), then stops."
    }

    /// What Save should do to the stored trigger.
    private var locationIntentEdit: LocationIntentEdit {
        guard hadLocationIntent else { return .unchanged }
        guard let editedLocationIntent else { return .remove }
        return .update(editedLocationIntent)
    }

    /// True for a resolved "here" that has no name yet. A saved place already
    /// has one, and an unresolved snapshot has no coordinate to look up.
    private var canNameCapturedPlace: Bool {
        guard let intent = item.locationIntent,
              intent.place == .currentLocation,
              let resolved = intent.resolvedPlace else { return false }
        return resolved.matchedName == nil && capturedPlaceName == nil
    }

    private var placeNamingFooter: String {
        if placeNamingFailed {
            return "Speak It couldn't find a name for this spot. The reminder still works — it uses the exact place you were standing."
        }
        return "Optional. Speak It asks Apple Maps what this spot is called, so the reminder can say “when you leave McMaster University” instead of “here”. The reminder already works without it."
    }

    private func nameCapturedPlace() async {
        isNamingPlace = true
        defer { isNamingPlace = false }
        let name = await repository?.nameCurrentLocationSnapshot(itemID: item.id)
        if let name {
            capturedPlaceName = name
            placeNamingFailed = false
        } else {
            placeNamingFailed = true
        }
    }

    private func refreshLocationBlocker() {
        // A combined place-and-time request is not waiting on a place, so
        // offering "Set Home" would point at the wrong gap entirely.
        guard item.isLocationTriggered, !item.constrainsBothPlaceAndTime else {
            locationBlocker = nil
            return
        }
        locationBlocker = item.locationBlocker(
            authorization: LocationReminderMonitor.shared.authorization
        )
    }

    /// The one action that actually unblocks this reminder.
    ///
    /// Each blocker has a different answer, so this never shows a generic "fix
    /// it" affordance. A missing Home is set here and now; a missing permission
    /// is asked for; a revoked one has to go to Settings, and says so rather
    /// than pretending the app can grant itself access.
    @ViewBuilder
    private func locationFix(for blocker: LocationReminderBlocker) -> some View {
        switch blocker {
        case .missingHome, .missingWork:
            let reference: PlaceReference = blocker == .missingHome ? .home : .work
            NavigationLink {
                PlaceSetupView(reference: reference)
            } label: {
                Label(
                    "Set \(reference.displayName) location",
                    systemImage: blocker == .missingHome ? "house" : "briefcase"
                )
            }
            .accessibilityHint("Sets where \(reference.displayName) is, then returns to this reminder")

        case .permissionRequired, .alwaysPermissionRequired,
             .permissionRevoked, .preciseLocationRequired:
            // Which of these can still be answered in-app depends on what iOS
            // has already been asked, not on the blocker alone: the Always
            // prompt is shown once per install, and a button wired to a spent
            // prompt does nothing at all.
            switch LocationReminderMonitor.shared.authorizationStep {
            case .requestWhenInUse:
                Button {
                    LocationReminderMonitor.shared.requestAuthorization()
                } label: {
                    Label("Allow location access", systemImage: "location")
                }
            case .requestAlways:
                Button {
                    LocationReminderMonitor.shared.requestAuthorization()
                } label: {
                    Label("Allow background location", systemImage: "location.fill")
                }
            case .openSettings, .none:
                Button {
                    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                    UIApplication.shared.open(url)
                } label: {
                    Label("Open Settings", systemImage: "gear")
                }
            }

        // Nothing here can fix these: a named place needs search (not built
        // yet), "here" needed a coordinate at capture time, and the device
        // limits are the device's. The footer still names the reason.
        case .ambiguousPlace, .placeNotFound, .locationUnavailable,
             .monitoringUnavailable, .monitoringLimitReached, .monitoringFailed:
            EmptyView()
        }
    }

    /// Whether the gap this editor was opened for has been filled in, judged
    /// against the live edits rather than the saved item.
    private var isRequirementSatisfied: Bool {
        switch requirement {
        case .time: hasReminder
        case .person: !personName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .type: itemType != .unclear
        // Captured before place reminders existed, so the way out is still
        // giving it a time instead.
        case .unsupportedLocationTrigger: hasReminder || hasDueDate
        // A place reminder is unblocked by granting permission or configuring
        // Home — neither of which happens on this form — so nothing here clears
        // it. Adding a time is still a legitimate way out.
        case .locationTrigger: hasReminder || hasDueDate
        // The request named a place *and* a time and only one can be enforced,
        // so the way out is committing to one of them. Setting a time here is
        // that commitment: it schedules the clock half, and the place half stays
        // unmonitored rather than firing alongside it.
        case .combinedTimeAndPlace: hasReminder
        // Both are resolved elsewhere — on the split screen, or by the person
        // turning off "Needs clarification" — so neither clears from this form.
        case .splitDecision, .confirmation, .none: false
        }
    }

    /// Satisfying the field is one way out; clearing the flag by hand is the
    /// other, and it has to count for the cases no single field can answer.
    private var isRequirementResolved: Bool {
        isRequirementSatisfied || !needsClarification
    }

    private var canContinueInAnotherApp: Bool {
        calendarStartDate != nil || communicationDraft != nil
    }

    private var integrationFooter: String {
        if communicationDraft != nil {
            return "Speak It can prepare the text and remind you at the scheduled time. iOS always asks you to approve sending; a sent message completes this task."
        }
        return "The event opens in Apple’s editor and is added only after you tap Add."
    }

    private func handleMessageResult(_ result: MessageComposeResult) {
        guard result == .sent else { return }
        integrationNotice = "Message sent · task completed"
        guard !item.isCompleted else { return }
        perform(dismissAfterward: true) {
            try repository?.setCompleted(item, completed: true)
        }
    }

    private func save() {
        perform(dismissAfterward: true) {
            guard let repository else {
                throw RepositoryError.saveFailed("Local storage is unavailable.")
            }
            try repository.update(
                item,
                with: ItemEdits(
                    title: title,
                    itemType: itemType,
                    category: category,
                    dueDate: hasDueDate ? dueDate : (hasReminder ? reminderDate : nil),
                    reminderDate: hasReminder ? reminderDate : nil,
                    priority: priority,
                    personName: personName,
                    needsClarification: needsClarification,
                    recurrenceRule: editedRecurrenceRule,
                    locationIntent: locationIntentEdit
                )
            )
        }
    }

    private var editedRecurrenceRule: RecurrenceRule? {
        guard repeats, itemType.isActionable else { return nil }
        let weekdays = recurrenceFrequency == .weekly
            ? [Calendar.autoupdatingCurrent.component(.weekday, from: hasDueDate ? dueDate : .now)]
            : []
        return RecurrenceRule(
            frequency: recurrenceFrequency,
            interval: recurrenceInterval,
            weekdays: weekdays,
            anchor: recurrenceAfterCompletion ? .completionDate : .scheduledDate
        )
    }

    private var recurrenceUnit: String {
        let singular: String
        switch recurrenceFrequency {
        case .daily: singular = "day"
        case .weekly: singular = "week"
        case .monthly: singular = "month"
        case .yearly: singular = "year"
        }
        return recurrenceInterval == 1 ? singular : "\(singular)s"
    }

    private func recurrenceTitle(_ frequency: RecurrenceFrequency) -> String {
        switch frequency {
        case .daily: "Daily"
        case .weekly: "Weekly"
        case .monthly: "Monthly"
        case .yearly: "Yearly"
        }
    }

    private var inferredReminderDelivery: ReminderDelivery {
        ThoughtOrganizer.organize(
            item.captureSession?.originalTranscription ?? item.originalTextSegment,
            referenceDate: item.createdAt
        ).reminderDelivery
    }

    private func perform(dismissAfterward: Bool = false, _ action: () throws -> Void) {
        guard repository != nil else {
            errorMessage = "Local storage is unavailable."
            return
        }

        do {
            try action()
            if dismissAfterward { dismiss() }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct CommunicationDraft: Equatable {
    let recipientName: String?
    let body: String
}

enum CommunicationDraftBuilder {
    static func draft(title: String, personName: String?) -> CommunicationDraft? {
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedTitle.range(
            of: #"\b(?:text|message)\b"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil else { return nil }

        let candidateName = personName?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedName = candidateName?.isEmpty == false ? candidateName : nil
        let greeting = normalizedName.map { "Hi \($0)" }

        let aboutRange = normalizedTitle.range(
            of: #"\babout\s+"#,
            options: [.regularExpression, .caseInsensitive]
        )
        let thatRange = normalizedTitle.range(
            of: #"\bthat\s+"#,
            options: [.regularExpression, .caseInsensitive]
        )

        let body: String
        if let aboutRange {
            let detail = cleanDetail(String(normalizedTitle[aboutRange.upperBound...]))
            let prefix = greeting.map { "\($0), I wanted to follow up about " }
                ?? "I wanted to follow up about "
            body = finish(prefix + detail)
        } else if let thatRange {
            let detail = cleanDetail(String(normalizedTitle[thatRange.upperBound...]))
            let prefix = greeting.map { "\($0), " } ?? ""
            body = finish(prefix + detail)
        } else {
            body = greeting.map { "\($0)," } ?? ""
        }

        return CommunicationDraft(recipientName: normalizedName, body: body)
    }

    private static func cleanDetail(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
    }

    private static func finish(_ value: String) -> String {
        guard let last = value.last, !last.isPunctuation else { return value }
        return value + "."
    }
}

@MainActor
private struct MessageComposeSheet: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let body: String
    let onResult: (MessageComposeResult) -> Void

    static var canSendText: Bool { MFMessageComposeViewController.canSendText() }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIViewController(context: Context) -> MFMessageComposeViewController {
        let controller = MFMessageComposeViewController()
        controller.messageComposeDelegate = context.coordinator
        controller.body = body
        return controller
    }

    func updateUIViewController(
        _ uiViewController: MFMessageComposeViewController,
        context: Context
    ) {}

    final class Coordinator: NSObject, MFMessageComposeViewControllerDelegate, @unchecked Sendable {
        private let parent: MessageComposeSheet

        init(parent: MessageComposeSheet) {
            self.parent = parent
        }

        nonisolated func messageComposeViewController(
            _ controller: MFMessageComposeViewController,
            didFinishWith result: MessageComposeResult
        ) {
            Task { @MainActor in
                parent.isPresented = false
                parent.onResult(result)
            }
        }
    }
}

@MainActor
private struct CalendarEventComposer: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let title: String
    let startDate: Date
    let notes: String
    let onComplete: (Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIViewController(context: Context) -> EKEventEditViewController {
        let eventStore = EKEventStore()
        let event = EKEvent(eventStore: eventStore)
        event.title = title
        event.startDate = startDate
        event.endDate = startDate.addingTimeInterval(30 * 60)
        event.notes = notes

        let controller = EKEventEditViewController()
        controller.eventStore = eventStore
        controller.event = event
        controller.editViewDelegate = context.coordinator
        return controller
    }

    func updateUIViewController(
        _ uiViewController: EKEventEditViewController,
        context: Context
    ) {}

    final class Coordinator: NSObject, EKEventEditViewDelegate, @unchecked Sendable {
        private let parent: CalendarEventComposer

        init(parent: CalendarEventComposer) {
            self.parent = parent
        }

        nonisolated func eventEditViewController(
            _ controller: EKEventEditViewController,
            didCompleteWith action: EKEventEditViewAction
        ) {
            Task { @MainActor in
                parent.isPresented = false
                parent.onComplete(action == .saved)
            }
        }
    }
}
