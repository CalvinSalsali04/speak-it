import EventKit
import EventKitUI
import MessageUI
import SwiftUI
import SwiftData
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
    /// Set only while the first-run tutorial sent the person here, so the
    /// editor can say which step it is standing in for. The sheet covers the
    /// tutorial banner, and without this the person is left holding an ordinary
    /// edit form with no sign that the tutorial is still waiting behind it.
    let tutorialStep: TutorialStep?

    private var showsTutorialGuidance: Bool { tutorialStep != nil }

    /// Resolved once on open. The asterisk has to stay on the field the person
    /// arrived to fill, so it must not re-derive from the item — or from live
    /// edits — and hop to a different row mid-edit.
    private let requirement: ClarificationRequirement?

    /// Set when this review row is standing in for a broad cancel or complete
    /// the person asked for but that Speak It never executes automatically.
    /// When present it replaces the ordinary edit form outright: there is
    /// nothing to classify here, only a request to confirm or decline. See
    /// Docs/FINAL_RELEASE_AUDIT.md F-1.
    private let pendingOperation: PendingOperationStore.StoredPendingOperation?
    private let captureChoiceState: CaptureOperationState?
    @State private var showsPendingOperationConfirmation = false
    @Query private var captureChoiceRows: [CapturedItem]
    // Query keeps insertion/deletion observable; reading the repository's full
    // snapshots here also observes in-place changes while this sheet is open.
    private var captureChoiceReading: Result<[CapturedItem], Error> {
        let liveIDs = Set(captureChoiceRows.map(\.id))
        return Result {
            try (repository?.pendingCaptureOperationChoices(for: item) ?? [])
                .filter { liveIDs.contains($0.id) }
        }
    }

    @State private var title: String
    @State private var itemType: ItemType
    @State private var category: ItemCategory
    @State private var priority: ItemPriority
    @State private var hasDueDate: Bool
    @State private var dueDate: Date
    @State private var dueDateHasTime: Bool
    @State private var hasReminder: Bool
    @State private var reminderDate: Date
    @State private var repeats: Bool
    @State private var recurrenceFrequency: RecurrenceFrequency
    @State private var recurrenceInterval: Int
    @State private var recurrenceAfterCompletion: Bool
    @FocusState private var personIsFocused: Bool
    @State private var personName: String
    @State private var confirmedRequiredValue = false
    @State private var choseTimeInstead = false
    @State private var needsClarification: Bool
    @State private var errorMessage: String?
    @State private var showsRecognitionHint = false
    @State private var pendingRecognitionPhrase: String?
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

    /// The form's values as it opened.
    ///
    /// Compared against the live `@State` to answer one question: has the
    /// person typed anything they would lose? Held as a snapshot rather than
    /// re-read from `item`, because the item is mutated by Save and by the
    /// capture-review screen, and this has to mean "since this form appeared".
    private struct OpeningValues: Equatable {
        let title: String
        let itemType: ItemType
        let category: ItemCategory
        let priority: ItemPriority
        let hasDueDate: Bool
        let dueDate: Date
        let dueDateHasTime: Bool
        let hasReminder: Bool
        let reminderDate: Date
        let repeats: Bool
        let recurrenceFrequency: RecurrenceFrequency
        let recurrenceInterval: Int
        let recurrenceAfterCompletion: Bool
        let personName: String
        let needsClarification: Bool
        let locationIntent: LocationIntent?
    }
    @State private var openingValues: OpeningValues

    /// True once anything on the form differs from how it opened.
    ///
    /// This screen exists to repair what the recognizer misheard, and a
    /// downward drag starting anywhere on the Form — including on the Title
    /// field at the very top — used to dismiss it and throw all of that away
    /// with no warning at all.
    private var hasUnsavedChanges: Bool {
        pendingRecognitionPhrase != nil || openingValues != OpeningValues(
            title: title,
            itemType: itemType,
            category: category,
            priority: priority,
            hasDueDate: hasDueDate,
            dueDate: dueDate,
            dueDateHasTime: dueDateHasTime,
            hasReminder: hasReminder,
            reminderDate: reminderDate,
            repeats: repeats,
            recurrenceFrequency: recurrenceFrequency,
            recurrenceInterval: recurrenceInterval,
            recurrenceAfterCompletion: recurrenceAfterCompletion,
            personName: personName,
            needsClarification: needsClarification,
            locationIntent: editedLocationIntent
        )
    }

    init(item: CapturedItem, tutorialStep: TutorialStep? = nil) {
        self.item = item
        self.tutorialStep = tutorialStep
        self.pendingOperation = PendingOperationStore.record(for: item.id)
        let operationState = CaptureOperationState.read(from: item.captureSession?.operationStateData)
        self.captureChoiceState = operationState?.phase == .pendingChoice
            && operationState?.reviewItemID == item.id
            ? operationState : nil
        let choiceIDs = self.captureChoiceState?.candidateIDs ?? []
        _captureChoiceRows = Query(filter: #Predicate<CapturedItem> { choiceIDs.contains($0.id) })
        self.requirement = item.clarificationRequirement
        self.hadLocationIntent = item.locationIntent != nil
        _editedLocationIntent = State(initialValue: item.locationIntent)
        _title = State(initialValue: item.displayTitle)
        _itemType = State(initialValue: item.itemType)
        _category = State(initialValue: item.category)
        _priority = State(initialValue: item.priority)
        let initialDueDate = item.dueDate ?? .now
        let initialReminderDate = item.reminderDate ?? initialDueDate
        _hasDueDate = State(initialValue: item.dueDate != nil)
        _dueDate = State(initialValue: initialDueDate)
        _dueDateHasTime = State(initialValue: !item.isDateOnly)
        _hasReminder = State(initialValue: item.reminderDate != nil)
        _reminderDate = State(initialValue: initialReminderDate)
        let recurrence = RecurrenceStore.rule(for: item.id)
        _repeats = State(initialValue: recurrence != nil)
        _recurrenceFrequency = State(initialValue: recurrence?.frequency ?? .weekly)
        _recurrenceInterval = State(initialValue: recurrence?.interval ?? 1)
        _recurrenceAfterCompletion = State(initialValue: recurrence?.anchor == .completionDate)
        _personName = State(initialValue: item.personName ?? "")
        _needsClarification = State(initialValue: item.needsClarification)
        _openingValues = State(initialValue: OpeningValues(
            title: item.displayTitle,
            itemType: item.itemType,
            category: item.category,
            priority: item.priority,
            hasDueDate: item.dueDate != nil,
            dueDate: initialDueDate,
            dueDateHasTime: !item.isDateOnly,
            hasReminder: item.reminderDate != nil,
            reminderDate: initialReminderDate,
            repeats: recurrence != nil,
            recurrenceFrequency: recurrence?.frequency ?? .weekly,
            recurrenceInterval: recurrence?.interval ?? 1,
            recurrenceAfterCompletion: recurrence?.anchor == .completionDate,
            personName: item.personName ?? "",
            needsClarification: item.needsClarification,
            locationIntent: item.locationIntent
        ))
    }

    var body: some View {
        if let captureChoiceState {
            captureOperationChoiceView(captureChoiceState)
        } else if let pendingOperation {
            pendingOperationConfirmationView(pendingOperation)
        } else {
            editorForm
        }
    }

    private func captureOperationChoiceView(
        _ state: CaptureOperationState
    ) -> some View {
        let reading = captureChoiceReading
        let captureChoiceCandidates = (try? reading.get()) ?? []
        return NavigationStack {
            List {
                Section {
                    Text(state.pendingSavedRevision == nil ? "Which saved reminder did you mean?"
                        : state.candidateIDs.isEmpty ? "The saved item wasn't found" : "Which saved item should change?")
                        .font(.headline)
                    Text(state.targetWords ?? state.sourceQuote)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if let intent = state.pendingSavedRevision {
                    Section("Requested change") {
                        Text(intent.removesAlert == true ? "Remove the alert; keep the saved task and deadline" : intent.replacementAction ?? "Move to \(intent.timingText ?? "the requested day")")
                            .accessibilityIdentifier("savedChoice.requestedDelta")
                        if state.candidateIDs.isEmpty {
                            Text("“\(intent.targetWords)” is unchanged. Keep this request until you can identify the saved item.")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                if case .failure(let error) = reading {
                    Section {
                        Text("Saved items couldn't be read. Your change request is kept.")
                        Text(error.localizedDescription).foregroundStyle(.secondary)
                    }
                } else if !state.candidateIDs.isEmpty, captureChoiceCandidates.isEmpty {
                    Section {
                        Text("The saved items changed since this capture. The requested edit is still here; the saved items are unchanged.")
                            .foregroundStyle(.secondary)
                    }
                }
                Section(state.pendingSavedRevision == nil ? "Saved reminders" : "Saved items") {
                    ForEach(captureChoiceCandidates, id: \.id) { candidate in
                        Button {
                            perform(dismissAfterward: true) {
                                try repository?.choosePendingCaptureOperation(
                                    item, targetID: candidate.id
                                )
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(candidate.displayTitle).font(.body.weight(.medium))
                                Text(ItemPresentation.savedTargetDetail(for: candidate))
                                    .font(.caption).foregroundStyle(.secondary)
                                if candidate.originalTextSegment != candidate.displayTitle {
                                    Text(candidate.originalTextSegment).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .accessibilityLabel("\(state.pendingSavedRevision == nil ? "Cancel" : "Update") \(candidate.displayTitle). \(ItemPresentation.savedTargetDetail(for: candidate))")
                        .accessibilityIdentifier("savedChoice.target.\(candidate.id.uuidString)")
#if DEBUG
                        .contextMenu {
                            if ProcessInfo.processInfo.arguments.contains("--ui-testing"),
                               ProcessInfo.processInfo.arguments.contains("--enable-live-saved-revision-qa"),
                               UUID(uuidString:ProcessInfo.processInfo.environment["SPEAKIT_UI_QA_STORE_ID"] ?? "") != nil,
                               candidate.id == UUID(uuidString:"A1000000-0000-4000-8000-000000000003") {
                                Button("Simulate saved item edit") {
                                    perform(dismissAfterward:false) {
                                        try (repository as? SwiftDataThoughtRepository)?.mutateSavedRevisionChoiceQA()
                                    }
                                }.accessibilityIdentifier("qa.savedChoice.edit")
                            }
                        }
#endif
                    }
                }
                Section {
                    Button(state.pendingSavedRevision == nil ? "Keep both reminders" : "Leave saved items unchanged") {
                        perform(dismissAfterward: true) {
                            try repository?.dismissPendingOperation(item)
                        }
                    }
                    .frame(minHeight: 44)
                }
            }
            .navigationTitle(state.pendingSavedRevision == nil ? "Choose reminder" : "Choose saved item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .repositoryErrorAlert($errorMessage)
        }
    }

    private var editorForm: some View {
        NavigationStack {
            Form {
                if let tutorialStep {
                    Section {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "hand.tap")
                                .font(.system(size: 15, weight: .semibold))
                                .frame(width: 34, height: 34)
                                .background(Color.speakInk.opacity(0.09), in: Circle())

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Change the thought here")
                                    .font(.subheadline.weight(.semibold))
                                Text("Edit the highlighted title, then tap Save—or continue without changing it. Either one returns you to the tutorial.")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(.vertical, 4)
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("tutorial.editor.guidance")
                    } header: {
                        TutorialStepHeader(step: tutorialStep, style: .compact)
                            .textCase(nil)
                            .padding(.bottom, 4)
                    }
                }

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
                                        : (BareHourQuestion(item: item) == nil
                                            ? requirement.editorPrompt
                                            : "Choose morning or evening below")
                                )
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityElement(children: .combine)
                        if !isRequirementResolved, let confirmation = requiredValueConfirmation {
                            Button(confirmation) { confirmedRequiredValue = true }
                                .frame(minHeight: 44)
                                .accessibilityIdentifier("editor.confirmRequiredValue")
                        }
                        if requirement == .splitDecision {
                            Button("Keep as one thought") {
                                perform(dismissAfterward: true) {
                                    guard let repository else {
                                        throw RepositoryError.saveFailed("Local storage is unavailable.")
                                    }
                                    try repository.keepAsOneThought(item)
                                }
                            }
                            .frame(minHeight: 44)
                            .disabled(hasUnsavedChanges)
                            .accessibilityHint("Confirms only that these words belong together. Other review requirements stay saved.")
                            .accessibilityIdentifier("editor.keepAsOneThought")
                            if hasUnsavedChanges {
                                Text("Save your edits before confirming this is one thought.")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        if !isRequirementResolved, requirement.editorField == .locationTrigger
                            || requirement.editorField == .combinedTimeAndPlace {
                            Button("Use a time instead") {
                                editedLocationIntent = nil; choseTimeInstead = true
                                hasDueDate = false; hasReminder = false
                                confirmedRequiredValue = false
                            }
                            .frame(minHeight: 44)
                            .accessibilityIdentifier("editor.useTimeInstead")
                        }
                    }
                }

                if let question = BareHourQuestion(item: item) {
                    Section {
                        Text("Was that \(question.hour) in the morning or evening?")
                            .font(.subheadline.weight(.semibold))
                        HStack(spacing: 12) {
                            Button("\(question.hour) AM") {
                                answerBareHour(.morning, question: question)
                            }
                            .frame(maxWidth: .infinity, minHeight: 44)
                            Button("\(question.hour) PM") {
                                answerBareHour(.evening, question: question)
                            }
                            .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.speakIt)
                    } footer: {
                        Text("Only this item's reminder time changes. Your original words stay saved.")
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

                if requirement?.editorField == .person {
                    Section("Who is this about?") { personField }
                        .task { personIsFocused = true }
                }
                if requirement?.editorField == .time { timingSection }

                Section(requirement?.editorField == .ambiguousObject ? "Which item?" : "Thought") {
                    TextField("Title", text: $title, axis: .vertical)
                        .textInputAutocapitalization(.sentences)
                        .autocorrectionDisabled(false)
                        .padding(showsTutorialGuidance ? 10 : 0)
                        .background(
                            Color.speakInk.opacity(showsTutorialGuidance ? 0.08 : 0),
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                        )
                        .overlay {
                            if showsTutorialGuidance {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(Color.speakInk, lineWidth: 2)
                            }
                        }
                        .accessibilityLabel("Item title")
                        .accessibilityHint(
                            showsTutorialGuidance
                                ? "Highlighted practice field. Change any words, then tap Save"
                                : (requirement?.editorField == .ambiguousObject
                                    ? "Name the item this action refers to. Its saved date stays the same."
                                    : "")
                        )
                        .accessibilityIdentifier(
                            showsTutorialGuidance ? "tutorial.editor.title" : "editor.title"
                        )

                    if tutorialStep == nil, item.captureSession?.captureSource != .tutorial,
                       title != openingValues.title || personName != openingValues.personName {
                        Button { showsRecognitionHint = true } label: {
                            Label("Help recognize a word", systemImage: "textformat.abc")
                        }
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("editor.recognitionHint")
                        if let pendingRecognitionPhrase {
                            Text("Voice hint: \(pendingRecognitionPhrase). Remembered when you save.")
                                .font(.footnote)
                                .foregroundStyle(Color.speakMuted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

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

                if requirement?.editorField != .time { timingSection }

                if let intent = editedLocationIntent {
                    locationSection(intent)
                }

                Section("Details") {
                    if requirement?.editorField != .person { personField }
                    // Named for what the person was actually shown. Today's
                    // section, the row badge and `ItemPresentation` all say
                    // "Needs review"; this control said "Needs clarification",
                    // which is our word, not theirs — and for a gap no single
                    // field can answer this toggle is the only way out, so the
                    // one control they have to find was the one thing not
                    // called what they were looking for.
                    Toggle("Needs review", isOn: $needsClarification)
                        .tint(Color.speakToggleTint)
                        .accessibilityHint("Turn off once this thought looks right to you")
                        .accessibilityIdentifier("editor.needsReview")
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
                        // The words themselves are the content here, and an
                        // explicit label replaces them rather than introducing
                        // them — so VoiceOver read "Original thought" and never
                        // the thought. On the one screen whose whole purpose is
                        // showing what was actually said, that is the thing a
                        // VoiceOver user most needs to hear. The section header
                        // already provides the introduction.
                        .accessibilityLabel(
                            "Original thought. \(item.captureSession?.originalTranscription ?? item.originalTextSegment)"
                        )

                    LabeledContent(
                        "Captured",
                        value: item.createdAt.formatted(date: .abbreviated, time: .shortened)
                    )
                    if let source = item.captureSession?.captureSource {
                        LabeledContent("Source", value: source.displayName)
                    }

                    if let session = item.captureSession {
                        NavigationLink {
                            CaptureSessionReviewView(
                                session: session,
                                // Split, Merge, Undo and Organize again all
                                // rewrite or delete this very item, while this
                                // form still holds the values it read in `init`.
                                // Popping back and tapping Save wrote those
                                // stale values over the result, undoing the
                                // operation the person had just performed.
                                onStructuralChange: { dismiss() }
                            )
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
                        // "Restore" on its own, because there is no Inbox in
                        // this product to restore to. Memory's swipe action
                        // already calls it that, and naming a third destination
                        // here sent people looking for a screen that does not
                        // exist.
                        Label(
                            item.isArchived ? "Restore" : "Archive",
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
            // The drag has to stop working before it can throw work away. Cancel
            // is still there and still discards — deliberately, because that is
            // an explicit choice — but a swipe that starts on the Title field is
            // not one.
            .interactiveDismissDisabled(hasUnsavedChanges)
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
                    Button(showsTutorialGuidance ? "Not now" : "Cancel") { dismiss() }
                        .accessibilityIdentifier(
                            showsTutorialGuidance ? "tutorial.editor.notNow" : "editor.cancel"
                        )
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
                    // Dismiss first, delete after.
                    //
                    // For a single-thought capture — the common case — `delete`
                    // removes the *session*, and the cascade rule on
                    // `CaptureSession.items` invalidates this very item. The
                    // sheet takes about a third of a second to animate out, and
                    // this body keeps reading `item.isCompleted`,
                    // `item.isArchived` and `item.captureSession` the whole
                    // time — on a model whose backing data is gone. Letting the
                    // dismissal finish first means nothing re-reads it.
                    guard let repository else {
                        errorMessage = "Local storage is unavailable."
                        return
                    }
                    let doomed = item
                    dismiss()
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(420))
                        do {
                            try repository.delete(doomed)
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes the item and its original capture when no other items use it. This cannot be undone.")
            }
            .sheet(isPresented: $showsRecognitionHint) {
                RecognitionHintView { pendingRecognitionPhrase = $0 }
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

    /// Stands in for the whole editor when this row exists only to confirm or
    /// decline a held broad cancel or complete. There is no title, type, or
    /// date to classify — offering those fields is what previously left the
    /// person with no way to actually confirm the thing the receipt promised.
    @ViewBuilder
    private func pendingOperationConfirmationView(
        _ pending: PendingOperationStore.StoredPendingOperation
    ) -> some View {
        NavigationStack {
            VStack(spacing: 20) {
                Spacer()
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(Color.speakWarning)
                Text(pendingOperationTitle(pending))
                    .font(.title2.weight(.semibold))
                    .multilineTextAlignment(.center)
                Text(item.displayTitle)
                    .font(.subheadline)
                    .foregroundStyle(Color.speakMuted)
                    .multilineTextAlignment(.center)
                Spacer()

                Button(role: .destructive) {
                    showsPendingOperationConfirmation = true
                } label: {
                    Text(pendingOperationActionLabel(pending))
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 54)
                }
                .buttonStyle(.speakIt)

                Button("Never mind") {
                    perform(dismissAfterward: true) {
                        try repository?.dismissPendingOperation(item)
                    }
                }
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 46)
                .buttonStyle(.speakIt)
            }
            .padding(24)
            .navigationTitle("Confirm")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .confirmationDialog(
                pendingOperationTitle(pending),
                isPresented: $showsPendingOperationConfirmation,
                titleVisibility: .visible
            ) {
                Button(pendingOperationActionLabel(pending), role: .destructive) {
                    perform(dismissAfterward: true) {
                        try repository?.confirmPendingOperation(item)
                    }
                }
                Button("Never mind", role: .cancel) {}
            } message: {
                Text("This cannot be undone.")
            }
            .repositoryErrorAlert($errorMessage)
        }
    }

    private func pendingOperationTitle(
        _ pending: PendingOperationStore.StoredPendingOperation
    ) -> String {
        let count = pending.candidateIDs.count
        let subject = count == 1 ? "1 item" : "\(count) items"
        switch pending.operation {
        case .cancel: return "Cancel \(subject)?"
        case .complete: return "Mark \(subject) complete?"
        case .reschedule, .revise, .create, .retract: return "Confirm this?"
        }
    }

    private func pendingOperationActionLabel(
        _ pending: PendingOperationStore.StoredPendingOperation
    ) -> String {
        switch pending.operation {
        case .cancel: return "Cancel everything"
        case .complete: return "Mark everything complete"
        case .reschedule, .revise, .create, .retract: return "Confirm"
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
        let isRequired = requirement?.editorField == marker
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
    private var personField: some View {
        HStack {
                        if requirement?.editorField == .person {
                            requiredLabel("Person", when: .person)
                                .layoutPriority(1)
                        }
                        TextField(
                            requirement?.editorField == .person ? "Name" : "Person (optional)",
                            text: $personName
                        )
                        .multilineTextAlignment(
                            requirement?.editorField == .person ? .trailing : .leading
                        )
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled(false)
                        .textContentType(.name)
                        .focused($personIsFocused)
                    }
    }

    private var unchangedClockBoundaryRelation: String? {
        guard dueDate == item.dueDate, dueDateHasTime == !item.isDateOnly,
              !item.clockBoundaryNeedsReview(), let boundary = item.temporalIntent?.clockBoundary else { return nil }
        switch boundary {
        case .after: return "After"
        case .before: return "Before"
        case .unrecognized: return nil
        }
    }

    private var timingSection: some View {
        Section("Timing") {
                    Toggle("Has a due date", isOn: $hasDueDate)
                        .tint(Color.speakToggleTint)
                        .accessibilityHint("Turn off to keep this item unscheduled")

                    if hasDueDate {
                        if dueDate == item.dueDate, dueDateHasTime == !item.isDateOnly,
                           item.temporalIntent?.clockBoundary != nil {
                            Text(ItemPresentation.clockBoundaryLabel(for: item) ?? "Time needs review")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        if dueDate == item.dueDate, dueDateHasTime == !item.isDateOnly,
                           item.temporalIntent?.deadlineBoundary != nil {
                            Text(ItemPresentation.endOfDayDeadlineLabel(for: item) ?? "Deadline time needs review")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        Toggle("Has a time", isOn: $dueDateHasTime)
                            .tint(Color.speakToggleTint)
                            .accessibilityHint("Turn off when only the day matters")

                        DatePicker(
                            unchangedClockBoundaryRelation ?? "Due",
                            selection: $dueDate,
                            displayedComponents: dueDateHasTime
                                ? [.date, .hourAndMinute]
                                : [.date]
                        )

                        if isDueDateOverdue {
                            Label("Overdue", systemImage: "clock.badge.exclamationmark")
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(Color.speakWarning)
                        }
                    }

                    Toggle(isOn: $hasReminder) {
                        requiredLabel("Remind me", when: .time)
                    }
                    .tint(Color.speakToggleTint)
                    .accessibilityHint("Schedules an alert for this thought")
                    .accessibilityIdentifier("editor.remindAtTime")

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
                            .tint(Color.speakToggleTint)

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
    }

    private func locationSection(_ intent: LocationIntent) -> some View {
        Section {
            LabeledContent("Place", value: intent.place.displayName)

            Picker("Trigger", selection: locationEventBinding) {
                Text("When I arrive").tag(LocationEvent.arrive)
                Text("When I leave").tag(LocationEvent.leave)
            }

            Toggle("Every time", isOn: locationRepeatsBinding)
                .tint(Color.speakToggleTint)
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
    private var requiredValueConfirmation: String? {
        switch requirement?.editorField {
        case .person: return personName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : "Confirm this person"
        case .type:
            if (requirement == .missingAction || requirement == .incompleteThought), itemType.isActionable { return nil }
            return itemType == .unclear ? nil : itemType.isActionable ? "This is my task" : "Keep this in Memory"
        case .time: return requirement == .ambiguousTemporalScope && hasDueDate ? "Use this day" : hasReminder ? "Use this time" : nil
        case .confirmation: return "Confirm this is right"
        default: return nil
        }
    }
    private var isRequirementSatisfied: Bool {
        switch requirement?.editorField {
        case .time:
            if requirement == .ambiguousTemporalScope {
                return (hasDueDate && (hasDueDate != openingValues.hasDueDate || dueDate != openingValues.dueDate || confirmedRequiredValue))
                    || (hasReminder && (hasReminder != openingValues.hasReminder || reminderDate != openingValues.reminderDate || confirmedRequiredValue))
            }
            return hasReminder && (hasReminder != openingValues.hasReminder || reminderDate != openingValues.reminderDate || confirmedRequiredValue)
        case .person:
            return !personName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && (personName != openingValues.personName || confirmedRequiredValue)
        case .type:
            if requirement == .missingAction || requirement == .incompleteThought {
                return !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    && (title != openingValues.title || (itemType == .note && (itemType != openingValues.itemType || confirmedRequiredValue)))
            }
            return itemType != .unclear && (itemType != openingValues.itemType || confirmedRequiredValue)
        case .ambiguousObject:
            return !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && title.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber })
                    != openingValues.title.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        case .unsupportedLocationTrigger, .unsupportedConditionTrigger:
            return hasReminder || hasDueDate
        case .locationTrigger, .combinedTimeAndPlace:
            return editedLocationIntent == nil && choseTimeInstead && (hasReminder || hasDueDate)
        case .confirmation: return confirmedRequiredValue
        case .splitDecision, .pendingOperation, .none: return false
        case .missingAction, .ambiguousPerson, .reportedSpeech,
             .ambiguousActor, .ambiguousTemporalScope, .incompleteThought,
             .organizationIncomplete: return false
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

    /// The type this edit should be saved as.
    ///
    /// Scheduling a note by hand is the person saying it is something to do.
    /// A date read out of a sentence never promotes a fact — see
    /// `CapturedItem.isTimeCommitted` — but a date typed into this screen is
    /// not inferred, it is asked for, and leaving the type alone would file the
    /// item in Memory with a deadline nothing ever surfaces.
    private var scheduledItemType: ItemType {
        // Changing the type by hand is the most explicit thing the person has
        // said about where this belongs, so it wins outright. Without this the
        // promotion below silently undid it, and a dated row could never be
        // moved to Memory at all: pick Note, save, and it came back a task.
        guard itemType == item.itemType else { return itemType }
        guard hasDueDate || hasReminder, !itemType.isActionable else { return itemType }
        return .task
    }

    private func save() {
        perform(dismissAfterward: true) {
            guard let repository else {
                throw RepositoryError.saveFailed("Local storage is unavailable.")
            }
            let semantics = ItemEditSemanticReconciler.reconcile(
                title: title,
                itemType: scheduledItemType,
                category: category,
                personName: personName,
                originalTitle: item.displayTitle,
                originalItemType: item.itemType,
                originalCategory: item.category,
                originalPersonName: item.personName
            )
            try repository.update(
                item,
                with: ItemEdits(
                    title: semantics.title,
                    itemType: semantics.itemType,
                    category: semantics.category,
                    dueDate: editedDueDate,
                    reminderDate: hasReminder ? reminderDate : nil,
                    priority: priority,
                    personName: semantics.personName,
                    needsClarification: needsClarification,
                    recurrenceRule: editedRecurrenceRule,
                    locationIntent: locationIntentEdit,
                    dueDateHasTime: editedDueDateHasTime,
                    clarifiedGap: isRequirementSatisfied ? item.semanticGapRawValue.flatMap(SemanticGap.init(rawValue:)) : nil
                )
            )
            if tutorialStep == nil, item.captureSession?.captureSource != .tutorial,
               let pendingRecognitionPhrase {
                SpeechVocabularyStore.confirmRecognitionPhrase(pendingRecognitionPhrase)
            }
        }
    }

    private func answerBareHour(
        _ answer: BareHourQuestion.Answer, question: BareHourQuestion
    ) {
        perform(dismissAfterward: true) {
            guard let repository, let date = question.date(for: answer) else {
                throw RepositoryError.saveFailed("That time is unavailable on the saved day.")
            }
            try repository.update(item, with: ItemEdits(
                title: item.displayTitle, itemType: item.itemType,
                category: item.category, dueDate: date, reminderDate: date,
                priority: item.priority, personName: item.personName,
                needsClarification: false,
                recurrenceRule: RecurrenceStore.rule(for: item.id),
                dueDateHasTime: true
            ))
        }
    }

    /// A date-only picker still binds a `Date`, whose internal representation
    /// contains an hour. Normalize that implementation detail before saving so
    /// it cannot reappear as a user-requested midnight deadline.
    private var editedDueDate: Date? {
        if hasDueDate {
            return dueDateHasTime
                ? dueDate
                : Calendar.autoupdatingCurrent.startOfDay(for: dueDate)
        }
        return hasReminder ? reminderDate : nil
    }

    private var editedDueDateHasTime: Bool {
        // An explicit reminder always contributes a real clock time, even when
        // the task's separate due value is only a day.
        hasReminder || (hasDueDate && dueDateHasTime)
    }

    private var isDueDateOverdue: Bool {
        guard hasDueDate, !item.isCompleted else { return false }
        return TodayActionTiming.group(
            for: editedDueDate,
            isDateOnly: !dueDateHasTime,
            deadlineIntent: editedDueDate == item.dueDate && dueDateHasTime == !item.isDateOnly
                ? item.temporalIntent : nil
        ) == .overdue
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

    /// The same memoized reading the row glyph and the scheduler use, so the
    /// editor explains the alert that will actually fire and does not re-run
    /// the whole capture pipeline on every render.
    private var inferredReminderDelivery: ReminderDelivery {
        ItemPresentation.effectiveReminderDelivery(for: item)
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
