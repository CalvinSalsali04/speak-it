import SwiftUI
import UIKit

enum CaptureInitialMode: Equatable, Sendable {
    case voice
    case text
}

enum TutorialCaptureMission: String, Equatable, Sendable {
    case action
    case idea
    case quickAccess

    /// Where this practice sits in the tutorial the person is counting.
    ///
    /// It used to say "PRACTICE 1 OF 2", which counted only the recordings and
    /// left every other tutorial screen unnumbered. The whole walkthrough now
    /// shares one spine.
    var step: TutorialStep {
        switch self {
        case .action: .practiceTask
        case .idea: .practiceIdea
        case .quickAccess: .captureAnywhere
        }
    }

    var title: String {
        switch self {
        case .action: "Try a task connected to a person"
        case .idea: "Now try something worth developing"
        case .quickAccess: "Use the iPhone trigger you just chose"
        }
    }

    var example: String {
        switch self {
        case .action:
#if DEBUG
            // Exercise the sentence break produced by live dictation in the
            // first-run UI test. This exact rendering previously created a
            // phantom "Tomorrow at nine" event and detached Maya's follow-up.
            if ProcessInfo.processInfo.arguments.contains("--ui-testing-spoken-time-break") {
                return "Tomorrow at nine. Ask Maya about the proposal."
            }
#endif
            return "Tomorrow at 9, ask Maya about the proposal."
        case .idea: return "I had an idea for weekly planning to read itself back to me."
        case .quickAccess: return "This is my capture anywhere test."
        }
    }

    var contextualPhrases: [String] {
        switch self {
        case .action: [example, "Maya", "ask Maya about the proposal"]
        case .idea: [example, "I had an idea", "weekly planning", "read itself back to me"]
        case .quickAccess: [example, "capture anywhere"]
        }
    }

    func repairVoiceTranscript(_ transcript: String) -> String {
        let corrections: [SpeechCorrection]
        switch self {
        case .action:
            // Apple commonly hears the unfamiliar name in this exact context
            // as the possessive "my". Repair the surrounding phrase instead
            // of every occurrence of "my", so somebody saying "ask my boss"
            // still keeps precisely what they said.
            corrections = [
                SpeechCorrection(heardPhrase: "ask my about", preferredPhrase: "ask Maya about"),
                SpeechCorrection(heardPhrase: "ask may about", preferredPhrase: "ask Maya about"),
                SpeechCorrection(heardPhrase: "ask Mia about", preferredPhrase: "ask Maya about"),
                SpeechCorrection(heardPhrase: "ask Mya about", preferredPhrase: "ask Maya about")
            ]
        case .idea:
            corrections = [
                SpeechCorrection(
                    heardPhrase: "I had an ideal for weekly planning",
                    preferredPhrase: "I had an idea for weekly planning"
                )
            ]
        case .quickAccess:
            corrections = []
        }
        return SpeechVocabularyStore.apply(corrections, to: transcript)
    }

    /// The row this practice step can actually teach from, or `nil` when the
    /// capture did not produce the shape the lesson needs.
    ///
    /// Every step after a practice capture points at a real row on a real
    /// screen — "here it is on Today", "here is Maya in People", "your idea is
    /// in Memory". The tutorial used to anchor to whatever came back, so an
    /// off-script sentence sent it to a screen the row is not on, where no
    /// teaching card renders and the only control left is Exit. Saying `nil`
    /// here is what lets the practice screen offer another try instead of
    /// walking the person into a dead end.
    ///
    /// This is the single definition of "the practice worked". `RootView` uses
    /// it to decide whether to advance, and `CaptureView` uses it to decide
    /// whether to ask again, so the two cannot disagree.
    @MainActor
    func satisfiedItem(in result: CaptureCreationResult) -> CapturedItem? {
        switch self {
        case .action:
            // The lesson is "a task connected to a person", and the three steps
            // after it walk to that person's page. Both halves have to be real.
            return result.items.first {
                $0.itemType == .personFollowUp && Self.personName(for: $0) != nil
            } ?? result.items.first {
                $0.itemType.isActionable && Self.personName(for: $0) != nil
            }
        case .idea:
            return result.items.first { $0.itemType == .idea }
        case .quickAccess:
            // Nothing downstream points at this row. Any saved capture already
            // proves the outside-the-app trigger did its job.
            return result.items.first
        }
    }

    @MainActor
    private static func personName(for item: CapturedItem) -> String? {
        let name = MemoryPersonNameResolver.name(for: item) ?? item.personName
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Why this capture cannot carry the step, in the person's terms.
    ///
    /// Names what the step needs rather than what they did wrong. The capture
    /// itself was saved and is never called a mistake — it is practice data
    /// that costs nothing and is deleted at the end either way.
    var missedPracticeDetail: String {
        switch self {
        case .action:
            "The next steps follow a task to the person it belongs to, so this one needs a name and something to do."
        case .idea:
            "The next step opens the idea stages, so this one needs something you are thinking about rather than a task."
        case .quickAccess:
            ""
        }
    }
}

struct CaptureView: View {
    /// Scroll anchor for the live transcript, so it keeps the newest words in
    /// view as they arrive.
    private static let transcriptTailID = "capture.transcriptTail"

    private enum CaptureMode {
        case voice
        case text
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.thoughtRepository) private var repository
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityVoiceOverEnabled) private var accessibilityVoiceOverEnabled
    @EnvironmentObject private var subscriptionStore: SubscriptionStore

    let onSaved: () -> Void
    private let startsInTextMode: Bool
    private let autoStartsVoiceCapture: Bool
    private let autoDismissesSingleItemConfirmation: Bool
    private let showsGuidedExamples: Bool
    private let tutorialMission: TutorialCaptureMission?
    private let performance: CapturePerformanceTrace?
    private let onSaveSucceeded: (CaptureCreationResult) -> Void
    private let onCancelled: () -> Void
    private let onTutorialEnded: () -> Void

    @StateObject private var transcriber = SpeechTranscriber()
    @State private var mode: CaptureMode
    @State private var typedText = ""
    @State private var errorMessage: String?
    @State private var captureNotice: String?
    @State private var voiceNotice: String?
    @State private var isSaving = false
    @State private var showsSavedConfirmation = false
    @State private var savedConfirmationTitle = "Remembered"
    @State private var savedConfirmationSymbol = "checkmark"
    @State private var savedConfirmationDetail = "Memory"
    @State private var savedResult: CaptureCreationResult?
    /// The safe, already-persisted attempt that a new voice capture will
    /// replace only after the retry itself saves successfully.
    @State private var retryingUnclearResult: CaptureCreationResult?
    @State private var showsCaptureReview = false
    @State private var showsCloseOptions = false
    @State private var closesAfterSave = false
    @State private var hasAutoStarted = false
    @State private var activeDraftID: UUID?
    @State private var captureStartedAt: Date?
    @State private var confirmationDismissTask: Task<Void, Never>?
    @State private var noSpeechTimeoutTask: Task<Void, Never>?
    @State private var draftCheckpointTask: Task<Void, Never>?
    @State private var isRecoveringAudio = false
    @State private var showsFreeLimit = false
    @FocusState private var isTextFocused: Bool

    private var trimmedTypedText: String {
        typedText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var tutorialAwareVoiceTranscript: String {
        tutorialMission?.repairVoiceTranscript(transcriber.transcript) ?? transcriber.transcript
    }

    init(
        initialMode: CaptureInitialMode = .voice,
        autoStartsVoiceCapture: Bool = false,
        initialText: String = "",
        performance: CapturePerformanceTrace? = nil,
        autoDismissesSingleItemConfirmation: Bool = true,
        showsGuidedExamples: Bool = false,
        tutorialMission: TutorialCaptureMission? = nil,
        onSaveSucceeded: @escaping (CaptureCreationResult) -> Void = { _ in },
        onCancelled: @escaping () -> Void = {},
        onTutorialEnded: @escaping () -> Void = {},
        onSaved: @escaping () -> Void
    ) {
        self.onSaved = onSaved
        startsInTextMode = initialMode == .text
        self.autoStartsVoiceCapture = autoStartsVoiceCapture && initialMode == .voice
        self.autoDismissesSingleItemConfirmation = autoDismissesSingleItemConfirmation
        self.showsGuidedExamples = showsGuidedExamples
        self.tutorialMission = tutorialMission
        self.performance = performance
        self.onSaveSucceeded = onSaveSucceeded
        self.onCancelled = onCancelled
        self.onTutorialEnded = onTutorialEnded
        _mode = State(initialValue: initialMode == .text ? .text : .voice)
        _typedText = State(initialValue: initialText)
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.speakBackground.ignoresSafeArea()

                VStack(spacing: 0) {
                    // The real header is overlaid on the fixed shell below. This
                    // placeholder keeps content from sitting underneath it.
                    Color.clear.frame(height: 68)

                    Group {
                        if showsSavedConfirmation {
                            savedView
                                .transition(.scale(scale: 0.88).combined(with: .opacity))
                        } else if mode == .voice {
                            voiceView
                                .transition(.opacity.combined(with: .scale(scale: 0.97)))
                        } else {
                            typingView
                                .transition(.opacity)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .foregroundStyle(Color.speakInk)
            }
            // GeometryReader owns the proposed window size rather than taking
            // the oversized editor's ideal size. That gives the overlay a real
            // top edge even while the keyboard shortens the available height.
            .frame(
                width: max(0, geometry.size.width),
                height: max(0, geometry.size.height),
                alignment: .top
            )
            .overlay(alignment: .top) {
                header
                    .background(Color.speakBackground)
            }
        }
        .interactiveDismissDisabled(
            transcriber.isListening || isSaving || isRecoveringAudio || activeDraftID != nil
        )
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { isTextFocused = false }
                    .fontWeight(.semibold)
            }
        }
        .repositoryErrorAlert($errorMessage)
        .sheet(isPresented: $showsCaptureReview) {
            if let savedResult {
                NavigationStack {
                    CaptureSessionReviewView(session: savedResult.session)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { showsCaptureReview = false }
                            }
                        }
                }
            }
        }
        .sheet(isPresented: $showsFreeLimit) {
            SpeakItProView(context: .freeLimit)
        }
        .confirmationDialog(
            "Keep this thought?",
            isPresented: $showsCloseOptions,
            titleVisibility: .visible
        ) {
            Button("Save & Close") { saveAndClose() }
            Button("Discard", role: .destructive) { discardAndClose() }
            Button("Keep Editing") {}
        } message: {
            Text("Your words are still a draft. Save them before closing, or discard them deliberately.")
        }
        .onDisappear {
            confirmationDismissTask?.cancel()
            noSpeechTimeoutTask?.cancel()
            flushPendingCheckpoint()
            transcriber.cancel()
            if !showsSavedConfirmation {
                Task { await CaptureActivityManager.cancelListening() }
            }
        }
        .onChange(of: transcriber.state) { _, newState in
            switch newState {
            case .listening:
                // This transition now occurs on the first real microphone
                // buffer, so the cue is safe to speak after—not merely an
                // animation that can race Core Audio/model startup.
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                if accessibilityVoiceOverEnabled {
                    UIAccessibility.post(notification: .announcement, argument: "Listening")
                }
                performance?.markMicrophoneReady()
                armNoSpeechTimeout()
                Task { await CaptureActivityManager.beginListening() }
            case .finalizing:
                performance?.markEndOfSpeechDetected(
                    lastSpeechAt: transcriber.lastVoiceActivityAt,
                    at: transcriber.speechEndpointDetectedAt ?? CapturePerformanceClock.now
                )
            case .unavailable:
                noSpeechTimeoutTask?.cancel()
                Task { await CaptureActivityManager.cancelListening() }
                continueByTyping(
                    notice: "Voice recognition isn’t available here. You can keep going by typing."
                )
            case .failed:
                noSpeechTimeoutTask?.cancel()
                Task { await CaptureActivityManager.cancelListening() }
                if hasRecoverableActiveAudio {
                    recoverActiveAudio()
                } else {
                    continueByTyping(
                        notice: "Voice had trouble starting. Your thought can still be saved by typing."
                    )
                }
            default:
                if newState != .requestingPermission {
                    noSpeechTimeoutTask?.cancel()
                }
                break
            }
        }
        .onChange(of: transcriber.transcript) { _, newTranscript in
            if !newTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                noSpeechTimeoutTask?.cancel()
                voiceNotice = nil
                let repaired = tutorialMission?.repairVoiceTranscript(newTranscript) ?? newTranscript
                scheduleCheckpoint(repaired, source: .inAppVoice)
            }
        }
        .onChange(of: transcriber.isWaitingForContinuation) { _, isWaiting in
            guard isWaiting, accessibilityVoiceOverEnabled else { return }
            UIAccessibility.post(
                notification: .announcement,
                argument: "Still listening. Take your time, or tap the pulse when you're finished."
            )
        }
        .onChange(of: typedText) { _, newText in
            if newText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               let activeDraft,
               !CaptureDraftStore.hasRecoveryAudio(for: activeDraft) {
                draftCheckpointTask?.cancel()
                draftCheckpointTask = nil
                discardActiveDraft()
            } else {
                scheduleCheckpoint(newText, source: .inAppText)
            }
        }
        .task {
            if startsInTextMode {
                try? await Task.sleep(for: .milliseconds(140))
                isTextFocused = true
            } else if autoStartsVoiceCapture, !hasAutoStarted {
                hasAutoStarted = true
                try? await Task.sleep(for: .milliseconds(180))
                guard !Task.isCancelled, mode == .voice else { return }
                await startVoiceCapture()
            }
        }
    }

    private var header: some View {
        HStack {
            if tutorialMission != nil {
                Button("End tutorial", action: endTutorial)
                    .font(.subheadline.weight(.semibold))
                    .frame(minHeight: 44)
                    .buttonStyle(.speakIt)
                    .foregroundStyle(Color.speakMuted)
                    .disabled(isCaptureTransitionBusy)
                    .accessibilityHint("Stops practice and opens the real app")
                    .accessibilityIdentifier("tutorial.capture.end")
            } else {
                Button(action: requestClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .medium))
                        .frame(width: 44, height: 44)
                        .background(Color.speakInk.opacity(0.08), in: Circle())
                }
                .buttonStyle(.speakIt)
                .foregroundStyle(Color.speakInk)
                .disabled(isCaptureTransitionBusy)
                .accessibilityLabel("Close capture")
                .accessibilityIdentifier("capture.close")
            }

            Spacer()
        }
        .overlay { SpeakItWordmark().allowsHitTesting(false) }
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

    @ViewBuilder
    private var voiceView: some View {
        if tutorialMission != nil {
            ScrollView {
                voiceContent
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
        } else {
            voiceContent
        }
    }

    private var voiceContent: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 20)

            if tutorialMission != nil {
                practiceBanner
            }

            Button(action: handleVoiceButton) {
                ListeningOrb(
                    phase: orbPhase,
                    level: transcriber.audioLevel
                )
            }
            .buttonStyle(.speakIt)
            .disabled(
                transcriber.state == .requestingPermission ||
                    transcriber.state == .finalizing ||
                    isSaving ||
                    isRecoveringAudio
            )
            .accessibilityLabel(voiceButtonAccessibilityLabel)
            .accessibilityHint(voiceButtonAccessibilityHint)
            .scaleEffect(tutorialMission == nil ? 1 : 0.72)
            .frame(height: tutorialMission == nil ? 230 : 166)

            VStack(spacing: 8) {
                Text(voiceTitle)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Color.speakInk)

                Text(voiceSubtitle)
                    .font(.subheadline)
                    .foregroundStyle(Color.speakMuted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 290)
            }
            .accessibilityElement(children: .combine)

            // Follows the newest words.
            //
            // The box holds about five lines. Past that the transcript kept
            // growing above a fixed viewport that never moved, so anyone
            // speaking a long thought watched their own words scroll out of
            // sight and had no way to see what was being heard — on the one
            // screen the whole product is built around.
            ScrollViewReader { proxy in
                ScrollView {
                    Text(tutorialAwareVoiceTranscript.isEmpty ? " " : tutorialAwareVoiceTranscript)
                        .font(.title3)
                        .foregroundStyle(Color.speakInk.opacity(0.84))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 330)
                        .padding(.horizontal)
                        .id(Self.transcriptTailID)
                }
                .onChange(of: tutorialAwareVoiceTranscript) { _, _ in
                    // Not animated: at speaking speed this fires on nearly
                    // every partial result, and animating each one turns a
                    // steady follow into a jitter.
                    proxy.scrollTo(Self.transcriptTailID, anchor: .bottom)
                }
            }
            .frame(
                maxHeight: tutorialMission != nil && transcriber.transcript.isEmpty
                    ? 30
                    : 126
            )
            .accessibilityLabel("Live transcription")
            .accessibilityValue(tutorialAwareVoiceTranscript)

            if showsGuidedExamples,
               tutorialMission == nil,
               transcriber.transcript.isEmpty,
               !isRecoveringAudio {
                guidedExamplesCard
            }

            Spacer()

            if transcriber.state == .permissionDenied {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .tint(Color.speakInk)
            }

            Button {
                switchToTyping()
            } label: {
                Label("Type instead", systemImage: "keyboard")
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 11)
                    .background(Color.speakInk.opacity(0.08), in: Capsule())
            }
            .buttonStyle(.speakIt)
            .foregroundStyle(Color.speakInk)
            .disabled(transcriber.state == .finalizing || isSaving || isRecoveringAudio)
            .accessibilityHint("Switches from voice capture to a text field")
            .accessibilityIdentifier("capture.typeInstead")
            .padding(.bottom, 34)
        }
        .padding(.horizontal, 20)
    }

    @ViewBuilder
    private var typingView: some View {
        if tutorialMission != nil {
            ScrollView {
                typingContent
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
        } else {
            typingContent
        }
    }

    private var typingContent: some View {
        VStack(alignment: .leading, spacing: 22) {
            Spacer(minLength: 26)

            if tutorialMission != nil {
                practiceBanner
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("What’s on your mind?")
                    .font(.largeTitle.weight(.semibold))
                    .foregroundStyle(Color.speakInk)

                HStack(spacing: 12) {
                    Text("Write naturally. You can organize it later.")
                        .foregroundStyle(Color.speakMuted)

                    Spacer(minLength: 8)

                    if isTextFocused {
                        Button("Done") {
                            isTextFocused = false
                        }
                        .font(.subheadline.weight(.semibold))
                        .buttonStyle(.speakIt)
                        .accessibilityLabel("Finish typing")
                        .accessibilityIdentifier("capture.finishTyping")
                    }
                }
            }

            if let captureNotice {
                Label(captureNotice, systemImage: "waveform.slash")
                    .font(.subheadline)
                    .foregroundStyle(Color.speakInk.opacity(0.72))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.speakSurface, in: RoundedRectangle(cornerRadius: 16))
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            TextEditor(text: $typedText)
                .focused($isTextFocused)
                .font(.title3)
                .textInputAutocapitalization(.sentences)
                .autocorrectionDisabled(false)
                .keyboardType(.default)
                .foregroundStyle(Color.speakInk)
                .tint(Color.speakInk)
                .scrollContentBackground(.hidden)
                .scrollDismissesKeyboard(.interactively)
                .padding(16)
                .frame(minHeight: 210, maxHeight: 300)
                .background(Color.speakSurface, in: RoundedRectangle(cornerRadius: 24))
                .overlay {
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(Color.speakDivider, lineWidth: 1)
                }
                .overlay(alignment: .topLeading) {
                    if typedText.isEmpty {
                        Text("Something you don’t want to forget…")
                            .font(.title3)
                            .foregroundStyle(Color.speakMuted.opacity(0.72))
                            .padding(.horizontal, 21)
                            .padding(.vertical, 24)
                            .allowsHitTesting(false)
                    }
                }
                .accessibilityLabel("Thought to save")
                .accessibilityIdentifier("capture.text")

            Button(action: saveTypedThought) {
                Text(isSaving ? "Saving…" : "Save thought")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(Color.speakInverseSurface)
            .foregroundStyle(Color.speakInverseInk)
            .disabled(trimmedTypedText.isEmpty || repository == nil || isSaving)
            .accessibilityIdentifier("capture.save")

            Button {
                isTextFocused = false
                captureNotice = nil
                withAnimation(.spring(response: 0.4, dampingFraction: 0.86)) {
                    mode = .voice
                }
            } label: {
                Label("Speak instead", systemImage: "waveform")
                    .font(.subheadline.weight(.medium))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.speakIt)
            .foregroundStyle(Color.speakInk)
            .accessibilityIdentifier("capture.speakInstead")

            Text("Next time, touch and hold Speak It on your Home Screen, then choose Type a thought.")
                .font(.caption)
                .foregroundStyle(Color.speakMuted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

            Spacer()
        }
        .padding(.horizontal, 22)
    }

    private var savedView: some View {
        VStack(spacing: 20) {
            Spacer()

            ZStack {
                Circle()
                    .stroke(Color.speakInk.opacity(0.18), lineWidth: 1)
                    .frame(width: 150, height: 150)
                Circle()
                    .fill(Color.speakInverseSurface)
                    .frame(width: 104, height: 104)
                    .shadow(color: Color.speakInk.opacity(0.18), radius: 28)
                Image(systemName: savedConfirmationSymbol)
                    .font(.system(size: 42, weight: .medium))
                    .foregroundStyle(Color.speakInverseInk)
            }
            Text(savedConfirmationTitle)
                .font(.largeTitle.weight(.semibold))
            Text(savedConfirmationDetail)
                .foregroundStyle(Color.speakMuted)

            if let savedResult, savedResult.hasItems {
                CapturedItemRow(
                    item: savedResult.primaryItem,
                    showsCompletionControl: false,
                    showsCreatedDate: false,
                    onToggleCompleted: {},
                    onEdit: {
                        confirmationDismissTask?.cancel()
                        showsCaptureReview = true
                    }
                )
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(maxWidth: 350)
                .background(
                    Color.speakSurface,
                    in: RoundedRectangle(cornerRadius: 20, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.speakDivider, lineWidth: 1)
                }
                .accessibilityHint("Shows the final organized item")
                .onAppear {
                    performance?.markOrganizedRowVisible(result: savedResult)
                }
            }

            if tutorialPracticeMissed, let tutorialMission {
                VStack(spacing: 10) {
                    // The practice screen's banner is not on this screen, so the
                    // sentence the step is built around has to be restated here
                    // or "try again" gives nothing to try.
                    Text("“\(tutorialMission.example)”")
                        .font(.subheadline)
                        .foregroundStyle(Color.speakInk.opacity(0.82))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, 2)
                        .accessibilityIdentifier("tutorial.missedExample")

                    Button(action: retryTutorialPractice) {
                        Label("Try again", systemImage: "arrow.counterclockwise")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 54)
                    }
                    .buttonStyle(.speakIt)
                    .foregroundStyle(Color.speakInverseInk)
                    .background(
                        Color.speakInverseSurface,
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                    )
                    .accessibilityHint("Removes this practice attempt and returns to the step")
                    .accessibilityIdentifier("tutorial.practiceRetry")

                    Button(action: useTutorialExample) {
                        Text("Use this example")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.speakInk)
                            .frame(maxWidth: .infinity, minHeight: 46)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.speakIt)
                    .accessibilityHint("Saves the example sentence for you and continues")
                    .accessibilityIdentifier("tutorial.practiceUseExample")
                }
                .padding(.top, 8)
                .frame(maxWidth: 330)
            } else if let savedResult, savedResult.needsInterpretationConfirmation {
                VStack(spacing: 10) {
                    Button(action: retryUnclearCapture) {
                        Label("Try saying it again", systemImage: "waveform")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 54)
                    }
                    .buttonStyle(.speakIt)
                    .foregroundStyle(Color.speakInverseInk)
                    .background(
                        Color.speakInverseSurface,
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                    )
                    .accessibilityHint("Keeps this attempt safe until the new one is saved")
                    .accessibilityIdentifier("capture.clarificationRetry")

                    Button {
                        confirmationDismissTask?.cancel()
                        showsCaptureReview = true
                    } label: {
                        Text("Review what I understood")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.speakInk)
                            .frame(maxWidth: .infinity, minHeight: 46)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.speakIt)

                    Button(action: finishSavedCapture) {
                        Text("Keep it as saved")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.speakMuted)
                            .frame(maxWidth: .infinity, minHeight: 46)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.speakIt)

                    // Offered only for a thought that stopped mid-sentence.
                    // Everywhere else, a capture the app merely failed to
                    // understand still holds words worth keeping, and putting a
                    // one-tap delete under them invites throwing away the very
                    // thing this app promises to preserve. A fragment is the
                    // one case where the person knows there is nothing there.
                    if isUnfinishedThought {
                        Button(role: .destructive, action: discardUnfinishedCapture) {
                            Text("Discard it")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color.speakWarning)
                                .frame(maxWidth: .infinity, minHeight: 46)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.speakIt)
                        .accessibilityHint("Deletes this unfinished capture. Nothing is saved.")
                        .accessibilityIdentifier("capture.discardUnfinished")
                    }
                }
                .padding(.top, 8)
                .frame(maxWidth: 330)
            } else if let savedResult,
                      savedResult.itemCount > 1 || savedResult.needsReviewCount > 0 {
                VStack(spacing: 10) {
                    Button {
                        confirmationDismissTask?.cancel()
                        showsCaptureReview = true
                    } label: {
                        Label("Review what was saved", systemImage: "list.bullet.rectangle")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 54)
                    }
                    .buttonStyle(.speakIt)
                    .foregroundStyle(Color.speakInverseInk)
                    .background(
                        Color.speakInverseSurface,
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                    )

                    Button(action: finishSavedCapture) {
                        Text("Done")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.speakInk)
                            .frame(maxWidth: .infinity, minHeight: 46)
                            .contentShape(Rectangle())
                    }
                        .buttonStyle(.speakIt)
                }
                .padding(.top, 8)
                .frame(maxWidth: 330)
            } else if savedResult != nil, requiresExplicitSavedConfirmation {
                Button(action: finishSavedCapture) {
                    Text("Continue")
                        .font(.headline)
                        .foregroundStyle(Color.speakInverseInk)
                        .frame(maxWidth: .infinity, minHeight: 54)
                        .contentShape(Rectangle())
                }
                    .buttonStyle(.speakIt)
                    .frame(maxWidth: 330)
                    .background(
                        Color.speakInverseSurface,
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                    )
                    .accessibilityIdentifier("capture.confirmationContinue")
            }

            Spacer()
        }
        .padding(.horizontal, 24)
    }

    /// Shown only for a normal guided first capture. Tutorial missions keep
    /// their exact phrase in `practiceBanner` until the capture is submitted.
    private var guidedExamplesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("TRY SAYING")
                .font(.caption2.weight(.semibold))
                .kerning(1.1)
                .foregroundStyle(Color.speakMuted)

            VStack(alignment: .leading, spacing: 7) {
                Text("“Remind me to call Mom tomorrow at 6”")
                Text("“Buy milk, eggs, and toothpaste”")
                Text("“Priya’s birthday is December 4th”")
            }
            .font(.subheadline)
            .foregroundStyle(Color.speakInk.opacity(0.82))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            Color.speakSurface,
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.speakDivider, lineWidth: 1)
        }
        .frame(maxWidth: 330)
        .transition(.opacity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Try saying a reminder, shopping list, or fact")
    }

    private var practiceBanner: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let tutorialMission {
                TutorialStepHeader(step: tutorialMission.step)

                Divider().overlay(Color.speakDivider)

                Text(tutorialMission.title)
                    .font(.subheadline)
                    .foregroundStyle(Color.speakMuted)

                Text("“\(tutorialMission.example)”")
                    .font(.headline)
                    .foregroundStyle(Color.speakInk)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("tutorial.missionExample")

                Text("Say it naturally, or use your own words.")
                    .font(.footnote)
                    .foregroundStyle(Color.speakMuted)
                    .fixedSize(horizontal: false, vertical: true)

                // Always offered, whatever is on screen.
                //
                // These used to be gated on the transcript and the text field
                // being empty, so a cough, a false start, or one stray word
                // took the way out away — and this is the control the flow
                // promises is always there. During practice nothing is at
                // stake: replacing a half-said sentence with the example is
                // exactly what somebody reaching for this button wants.
                if mode == .voice {
                    Button {
                        transcriber.cancel()
                        typedText = tutorialMission.example
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.86)) {
                            mode = .text
                        }
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(220))
                            isTextFocused = true
                        }
                    } label: {
                        Text("Type this example")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.speakIt)
                    .accessibilityIdentifier("tutorial.useExample")
                } else {
                    Button {
                        typedText = tutorialMission.example
                        isTextFocused = true
                    } label: {
                        Text("Use this example")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.speakIt)
                    .accessibilityIdentifier("tutorial.useExample")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.speakSurface, in: RoundedRectangle(cornerRadius: 18))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("tutorial.practiceBanner")
    }

    private func endTutorial() {
        confirmationDismissTask?.cancel()
        noSpeechTimeoutTask?.cancel()
        draftCheckpointTask?.cancel()
        transcriber.cancel()
        discardActiveDraft()
        onTutorialEnded()
    }

    private var orbPhase: ListeningOrb.Phase {
        if isRecoveringAudio { return .processing }
        return switch transcriber.state {
        case .listening:
            .listening
        case .requestingPermission, .finalizing:
            .processing
        default:
            .ready
        }
    }

    private var voiceTitle: String {
        if isRecoveringAudio { return "Recovering your words…" }
        return switch transcriber.state {
        case .idle: "Tap to speak"
        case .requestingPermission:
            transcriber.isPreparingEnhancedRecognition
                ? "Preparing accurate recognition…"
                : "Getting ready…"
        case .listening:
            transcriber.isWaitingForContinuation ? "Still listening…" : "Listening"
        case .finalizing: "Saving your thought…"
        case .permissionDenied: "Microphone access is off"
        case .unavailable: "Speech recognition is unavailable"
        case .failed: "Couldn’t hear that"
        }
    }

    private var voiceSubtitle: String {
        if isRecoveringAudio {
            return "The temporary recording is safe on this iPhone."
        }
        if let voiceNotice {
            return voiceNotice
        }

        return switch transcriber.state {
        case .idle: "Say anything you don’t want to forget."
        case .requestingPermission:
            transcriber.isPreparingEnhancedRecognition
                ? "One-time voice setup stays on this iPhone."
                : "Speak It only listens while you’re capturing."
        case .listening:
            transcriber.isWaitingForContinuation
                ? "Take your time. Keep speaking, or tap the pulse when you’re finished."
                : "Just speak. I’ll save after a natural pause."
        case .finalizing: "The original words are saved first."
        case .permissionDenied: "Allow microphone and speech recognition, or type instead."
        case .unavailable: "You can still capture this thought by typing."
        case .failed: "Try once more, or continue by typing."
        }
    }

    private var voiceButtonAccessibilityLabel: String {
        transcriber.isListening ? "Finish recording now" : "Start voice capture"
    }

    private var voiceButtonAccessibilityHint: String {
        transcriber.isListening
            ? "Finishes immediately; otherwise Speak It waits longer when your words sound unfinished"
            : "Requests permission if needed, then begins listening"
    }

    private func handleVoiceButton() {
        if transcriber.isListening {
            guard !transcriber.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                voiceNotice = "I’m listening — say your thought, then pause."
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
                return
            }
            transcriber.stopAndFinalize { finalText in
                save(finalText, source: .inAppVoice)
            }
        } else {
            voiceNotice = nil
            Task {
                await startVoiceCapture()
            }
        }
    }

    private func startVoiceCapture() async {
        guard mode == .voice else { return }
        ensureDraft(source: .inAppVoice)
        let recoveryURL = activeDraft.flatMap { try? CaptureDraftStore.prepareAudioURL(for: $0) }
        await transcriber.start(
            recoveryAudioURL: recoveryURL,
            contextualPhrases: tutorialMission?.contextualPhrases ?? [],
            prefersEnhancedRecognition: tutorialMission != nil
        ) { finalText in
            save(finalText, source: .inAppVoice)
        }
    }

    private var activeDraft: CaptureDraftStore.Draft? {
        guard let activeDraftID else { return nil }
        return CaptureDraftStore.draft(id: activeDraftID)
    }

    private var hasRecoverableActiveAudio: Bool {
        guard transcriber.hasDetectedAudioInput, let activeDraft else { return false }
        return CaptureDraftStore.hasRecoveryAudio(for: activeDraft)
    }

    private func recoverActiveAudio() {
        guard !isRecoveringAudio, let draft = activeDraft else { return }
        noSpeechTimeoutTask?.cancel()
        isRecoveringAudio = true
        transcriber.resetAfterFailure()
        CaptureDraftStore.markProcessing(id: draft.id)

        Task { @MainActor in
            do {
                let recoveredText = try await CaptureAudioRecovery.transcribe(draft)
                isRecoveringAudio = false
                save(recoveredText, source: .inAppVoice)
            } catch {
                isRecoveringAudio = false
                CaptureDraftStore.markFailed(id: draft.id, error: error)
                continueByTyping(
                    notice: "Your recording is safe. Type this thought now, or recover it later from Today."
                )
            }
        }
    }

    private func armNoSpeechTimeout() {
        noSpeechTimeoutTask?.cancel()
        noSpeechTimeoutTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled,
                  transcriber.isListening,
                  transcriber.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return
            }

            if hasRecoverableActiveAudio {
                recoverActiveAudio()
            } else {
                transcriber.cancel()
                discardActiveDraft()
                if let quality = transcriber.lastAudioQuality, quality.isVeryQuiet {
                    voiceNotice = "That was very quiet. Bring the iPhone closer and try once more."
                } else if let quality = transcriber.lastAudioQuality, quality.isLikelyClipped {
                    voiceNotice = "That was too loud for the microphone. Move it a little farther away."
                } else {
                    voiceNotice = "I didn’t hear speech. Tap when you’re ready, or type instead."
                }
                if let quality = transcriber.lastAudioQuality {
                    SpeakItAnalytics.track(.speechCaptureQuality(quality, producedWords: false))
                }
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
                Task { await CaptureActivityManager.cancelListening() }
            }
        }
    }

    private func switchToTyping() {
        captureNotice = nil
        let partialTranscript = tutorialAwareVoiceTranscript
        if !partialTranscript.isEmpty {
            typedText = partialTranscript
        }

        // `startVoiceCapture` may still be waiting on its launch delay or on a
        // permission prompt. Cancelling here invalidates the transcriber's
        // active start ID, so either path cannot begin listening behind the
        // typing interface after the person has already changed modes.
        let wasStartingOrListening = transcriber.state == .requestingPermission
            || transcriber.isListening
        if wasStartingOrListening {
            transcriber.cancel()
            Task { await CaptureActivityManager.cancelListening() }
        } else if transcriber.state != .idle {
            transcriber.resetAfterFailure()
        }

        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
            mode = .text
        }
        if let activeDraftID {
            CaptureDraftStore.updateSource(id: activeDraftID, source: .inAppText)
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(220))
            isTextFocused = true
        }
    }

    private func continueByTyping(notice: String) {
        let partialTranscript = tutorialAwareVoiceTranscript
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !partialTranscript.isEmpty {
            typedText = partialTranscript
        }
        transcriber.resetAfterFailure()
        captureNotice = notice

        withAnimation(.spring(response: 0.4, dampingFraction: 0.86)) {
            mode = .text
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(220))
            isTextFocused = true
        }
    }

    private func saveTypedThought() {
        isTextFocused = false
        performance?.beginTextSave()
        save(trimmedTypedText, source: .inAppText)
    }

    private func save(_ text: String, source: CaptureSource) {
        let repairedText = source == .inAppVoice
            ? tutorialMission?.repairVoiceTranscript(text) ?? text
            : text
        let normalizedText = repairedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedText.isEmpty else {
            errorMessage = "Speak a little longer, or type the thought instead."
            return
        }
        guard let repository else {
            SpeakItAnalytics.track(.captureFailed(
                source: source == .inAppVoice ? .voice : .text,
                category: "storage"
            ))
            errorMessage = "Local storage is unavailable."
            return
        }
        if source == .inAppVoice {
            if let quality = transcriber.lastAudioQuality {
                SpeakItAnalytics.track(.speechCaptureQuality(quality, producedWords: true))
            }
            performance?.updateSource(.voice)
            let finalizedAt = transcriber.finalTranscriptAt ?? CapturePerformanceClock.now
            performance?.markEndOfSpeechDetected(
                lastSpeechAt: transcriber.lastVoiceActivityAt,
                at: transcriber.speechEndpointDetectedAt ?? finalizedAt
            )
            performance?.markTranscriptFinalized(at: finalizedAt)
        }
        subscriptionStore.refreshFreeAllowance()
        // A clarification retry is exempt, because it replaces an attempt that
        // was already charged — the `!replacesRetrySource` condition below
        // guarantees it cannot charge a second time. Without this, the app
        // invited the person to "try saying it again" on their tenth capture
        // and then refused the retry it had just asked for.
        guard tutorialMission != nil
                || retryingUnclearResult != nil
                || subscriptionStore.canCreateCapture
        else {
            isTextFocused = false
            // Move the words into the editor rather than cancelling. Cancelling
            // clears the transcript, so what the person had just finished
            // saying vanished off the screen at the same moment the paywall
            // appeared, with nothing telling them where it went.
            let spoken = tutorialAwareVoiceTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
            if !spoken.isEmpty, trimmedTypedText.isEmpty {
                typedText = spoken
                mode = .text
            }
            transcriber.cancel()
            // The Live Activity is still advertising "Listening" at this point,
            // and nothing else ends it — no lifecycle sweep runs on this path —
            // so the Lock Screen kept claiming Speak It was recording after it
            // had stopped and shown a paywall.
            Task { await CaptureActivityManager.cancelListening() }
            SpeakItAnalytics.track(.freeLimitReached(used: subscriptionStore.freeCapturesUsed))
            showsFreeLimit = true
            return
        }

        draftCheckpointTask?.cancel()
        draftCheckpointTask = nil
        if let activeDraftID {
            CaptureDraftStore.update(id: activeDraftID, transcript: normalizedText)
        }
        isSaving = true
        Task { @MainActor in
            do {
                let persistenceSource: CaptureSource = tutorialMission == nil
                    ? source
                    : .tutorial
                let result = try await repository.createCaptureResult(
                    text: normalizedText,
                    source: persistenceSource,
                    createdAt: captureStartedAt ?? .now,
                    schedulesReminders: tutorialMission == nil,
                    performance: performance
                )
                let retrySource = retryingUnclearResult
                let replacesRetrySource = retrySource.map {
                    result.createdNewCapture && $0.session.id != result.session.id
                } ?? false
                if result.createdNewCapture {
                    // Cancelling, completing or withdrawing manages existing
                    // content rather than storing a new thought, so it does not
                    // spend one of the ten free captures.
                    // A clarification retry replaces an already-charged
                    // attempt, so the person never spends two captures for
                    // helping Speak It understand one thought.
                    if result.consumesFreeCapture, !replacesRetrySource {
                        subscriptionStore.recordSuccessfulCapture()
                    }
                    if tutorialMission == nil {
                        SpeakItAnalytics.track(.captureSaved(
                            source: source == .inAppVoice ? .voice : .text,
                            itemCount: result.itemCount,
                            needsReviewCount: result.needsReviewCount,
                            plan: subscriptionStore.hasProAccess ? .pro : .free
                        ))
                    }
                }
                if replacesRetrySource, let retrySource {
                    do {
                        // The retry was durable before this deletion starts.
                        // If deletion fails, both versions remain recoverable
                        // and the person is told instead of losing either one.
                        for item in retrySource.items {
                            try repository.delete(item)
                        }
                    } catch {
                        errorMessage = "The new version was saved, but the earlier attempt is still in Needs review."
                    }
                }
                retryingUnclearResult = nil
                isSaving = false
                discardActiveDraft()
                typedText = ""
                savedResult = result
                onSaveSucceeded(result)
                // Whether this practice can carry the steps that follow. It has
                // to be read from `result` rather than `tutorialPracticeMissed`,
                // because the rest of this function runs before SwiftUI has
                // published the `savedResult` write above.
                let missedTutorialPractice = tutorialMission
                    .map { $0.satisfiedItem(in: result) == nil } ?? false
                // An operation reports what it did. Saying "Remembered" after
                // cancelling something is the app describing the wrong action.
                if missedTutorialPractice, let tutorialMission {
                    // Deliberately ahead of every other outcome, including an
                    // operation result. During practice, "what this step needs"
                    // is the only thing the person can act on.
                    savedConfirmationTitle = "Almost — one more go"
                    savedConfirmationSymbol = "arrow.counterclockwise"
                    savedConfirmationDetail = tutorialMission.missedPracticeDetail
                } else if let outcome = result.operationOutcome {
                    let copy = CaptureOperationCopy.make(for: outcome)
                    savedConfirmationTitle = copy.title
                    savedConfirmationSymbol = copy.symbol
                    savedConfirmationDetail = result.hasItems
                        ? "\(copy.detail) \(result.itemCount) saved \(result.itemCount == 1 ? "item" : "items") below."
                        : copy.detail
                } else if result.needsInterpretationConfirmation {
                    savedConfirmationTitle = "Can you clarify?"
                    savedConfirmationSymbol = "questionmark"
                    savedConfirmationDetail = clarificationDetail(for: result)
                } else {
                    savedConfirmationTitle = result.isDuplicate ? "Already captured" : "Remembered"
                    savedConfirmationSymbol = result.isDuplicate ? "equal" : "checkmark"
                    savedConfirmationDetail = confirmationDetail(for: result)
                }
                if result.needsInterpretationConfirmation {
                    UINotificationFeedbackGenerator().notificationOccurred(.warning)
                } else if result.isDuplicate {
                    UISelectionFeedbackGenerator().selectionChanged()
                } else {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                }
                withAnimation(.spring(response: 0.45, dampingFraction: 0.72)) {
                    showsSavedConfirmation = true
                }
                Task {
                    if result.needsInterpretationConfirmation {
                        await CaptureActivityManager.showProblem(
                            title: "Needs clarification",
                            detail: "Open Speak It to try again or review what was saved."
                        )
                    } else {
                        await CaptureActivityManager.showRemembered(
                            normalizedText,
                            context: savedConfirmationDetail
                        )
                    }
                }

                // A missed practice is the one confirmation that must wait for a
                // decision. Closing or auto-dismissing past it is what used to
                // strand the tutorial on a screen with nothing to tap.
                if closesAfterSave, !missedTutorialPractice {
                    closesAfterSave = false
                    finishSavedCapture()
                    return
                }
                closesAfterSave = false

                if !missedTutorialPractice,
                   result.itemCount == 1,
                   result.needsReviewCount == 0,
                   !requiresExplicitSavedConfirmation {
                    confirmationDismissTask?.cancel()
                    confirmationDismissTask = Task { @MainActor in
                        try? await Task.sleep(for: .seconds(3.6))
                        guard !Task.isCancelled else { return }
                        finishSavedCapture()
                    }
                }
            } catch {
                isSaving = false
                closesAfterSave = false
                SpeakItAnalytics.track(.captureFailed(
                    source: source == .inAppVoice ? .voice : .text,
                    category: "organization"
                ))
                errorMessage = error.localizedDescription
            }
        }
    }

    private func confirmationDetail(for result: CaptureCreationResult) -> String {
        guard result.createdNewCapture else {
            return "No duplicate was added"
        }

        let context = result.receiptContext
        if tutorialMission != nil {
            return "Practice · doesn’t use a free capture\nNext, see exactly where it went"
        }
        guard !subscriptionStore.hasProAccess else { return context }
        switch subscriptionStore.freeCapturesRemaining {
        case 2:
            return "\(context)\n2 free captures left"
        case 1:
            return "\(context)\n1 free capture left"
        case 0:
            return "\(context)\nLast free capture used"
        default:
            return context
        }
    }

    private func clarificationDetail(for result: CaptureCreationResult) -> String {
        guard result.itemCount == 1,
              let requirement = result.primaryItem.clarificationRequirement else {
            return "I’m not completely sure I understood that. Your original words are safe."
        }

        switch requirement {
        case .time:
            return "I understood the thought, but not when. Try again with the time."
        case .person:
            return "I understood the follow-up, but not who it’s about."
        case .type:
            return "I’m not sure whether this is something to do or something to remember."
        case .splitDecision:
            return "I’m not sure whether that was one thought or more."
        case .confirmation:
            return "I’m not completely sure I understood that. Your original words are safe."
        // What the interpreter actually could not settle, said in the person's
        // own terms. Before version 4 recorded it, every one of these arrived
        // here as `.type` or `.confirmation` and was answered with a question
        // about the wrong thing.
        case .missingAction:
            return "I heard the reminder, but not what to do. Try again with the action."
        case .ambiguousPerson:
            return "I understood the thought, but not who it’s about."
        case .reportedSpeech:
            return "That sounded like someone else’s words. Your original words are safe."
        case .ambiguousActor:
            return "I couldn’t tell whether that was yours to do."
        case .ambiguousTemporalScope:
            return "I heard a day but not a decision. Try again with the one you meant."
        case .incompleteThought:
            return "It sounded like that thought wasn’t finished. Your words are safe — pick it up where you left off."
        case .unsupportedLocationTrigger, .unsupportedConditionTrigger,
             .locationTrigger, .combinedTimeAndPlace, .pendingOperation:
            return "This needs a quick review. Your original words are safe."
        }
    }

    /// True when the interpreter said the sentence itself stopped, rather than
    /// that it could not read a finished one.
    private var isUnfinishedThought: Bool {
        guard let savedResult, savedResult.itemCount == 1 else { return false }
        return savedResult.primaryItem.clarificationRequirement == .incompleteThought
    }

    /// Throws away a capture that never became a thought.
    ///
    /// Deliberately the only delete offered from this screen. `delete` removes
    /// the whole session when the fragment is its only row, so nothing is left
    /// orphaned behind it.
    private func discardUnfinishedCapture() {
        guard let savedResult, let repository else { return }
        confirmationDismissTask?.cancel()
        try? repository.delete(savedResult.primaryItem)
        self.savedResult = nil
        withAnimation(.spring(response: 0.42, dampingFraction: 0.84)) {
            showsSavedConfirmation = false
        }
    }

    /// True when a practice capture saved, but is not the shape this tutorial
    /// step teaches from.
    ///
    /// The capture itself is fine and is already durable. What it cannot do is
    /// carry the steps that follow, all of which point at a specific row on a
    /// specific screen.
    private var tutorialPracticeMissed: Bool {
        guard let tutorialMission, let savedResult else { return false }
        return tutorialMission.satisfiedItem(in: savedResult) == nil
    }

    /// Clears the practice attempt and returns to the practice screen.
    ///
    /// Deleting is safe and deliberate here in a way it never is for a real
    /// capture: this row is tutorial data, it spent none of the ten free
    /// captures, and every practice row is deleted when the tutorial ends
    /// anyway. Leaving it behind would put a stray "hello testing" in the
    /// person's real library on their first minute in the app.
    private func discardTutorialPractice() {
        guard let savedResult, let repository else { return }
        for item in savedResult.items {
            try? repository.delete(item)
        }
    }

    private func retryTutorialPractice() {
        confirmationDismissTask?.cancel()
        discardTutorialPractice()
        savedResult = nil
        typedText = ""
        captureNotice = nil
        voiceNotice = nil
        transcriber.cancel()
        withAnimation(.spring(response: 0.42, dampingFraction: 0.84)) {
            showsSavedConfirmation = false
        }
    }

    /// Takes the exact sentence the step is built around, so the person always
    /// has a way through that cannot miss.
    private func useTutorialExample() {
        guard let tutorialMission else { return }
        let example = tutorialMission.example
        confirmationDismissTask?.cancel()
        discardTutorialPractice()
        savedResult = nil
        captureNotice = nil
        voiceNotice = nil
        transcriber.cancel()
        typedText = example
        mode = .text
        withAnimation(.spring(response: 0.42, dampingFraction: 0.84)) {
            showsSavedConfirmation = false
        }
        Task { @MainActor in
            // Let the confirmation finish leaving before the next save puts it
            // back, so the person sees one transition rather than a flicker.
            try? await Task.sleep(for: .milliseconds(260))
            guard !showsSavedConfirmation else { return }
            save(example, source: .inAppText)
        }
    }

    private func retryUnclearCapture() {
        guard let savedResult else { return }

        confirmationDismissTask?.cancel()
        retryingUnclearResult = savedResult
        transcriber.cancel()
        typedText = ""
        captureNotice = nil
        voiceNotice = "Try saying it a different way, or include the missing detail."
        mode = .voice
        self.savedResult = nil

        withAnimation(.spring(response: 0.42, dampingFraction: 0.84)) {
            showsSavedConfirmation = false
        }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(260))
            guard retryingUnclearResult != nil, !showsSavedConfirmation else { return }
            await startVoiceCapture()
        }
    }

    private var isCaptureTransitionBusy: Bool {
        isSaving || isRecoveringAudio || transcriber.state == .requestingPermission
            || transcriber.state == .finalizing
    }

    private var requiresExplicitSavedConfirmation: Bool {
        !autoDismissesSingleItemConfirmation || accessibilityVoiceOverEnabled
    }

    private var hasUnsavedCaptureContent: Bool {
        !trimmedTypedText.isEmpty
            || !transcriber.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || hasRecoverableActiveAudio
    }

    private func requestClose() {
        if showsSavedConfirmation {
            finishSavedCapture()
        } else if hasUnsavedCaptureContent {
            isTextFocused = false
            showsCloseOptions = true
        } else {
            discardAndClose()
        }
    }

    private func saveAndClose() {
        closesAfterSave = true
        isTextFocused = false

        if mode == .text {
            save(trimmedTypedText, source: .inAppText)
        } else if transcriber.isListening {
            let partial = transcriber.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            if !partial.isEmpty {
                transcriber.stopAndFinalize { finalText in
                    save(finalText, source: .inAppVoice)
                }
            } else if hasRecoverableActiveAudio {
                transcriber.cancel()
                recoverActiveAudio()
            }
        } else {
            let transcript = transcriber.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            if !transcript.isEmpty {
                save(transcript, source: .inAppVoice)
            } else if hasRecoverableActiveAudio {
                recoverActiveAudio()
            }
        }
    }

    private func discardAndClose() {
        closesAfterSave = false
        draftCheckpointTask?.cancel()
        draftCheckpointTask = nil
        discardActiveDraft()
        transcriber.cancel()
        onCancelled()
        dismiss()
    }

    private func checkpoint(_ text: String, source: CaptureSource) {
        ensureDraft(source: source)
        guard let activeDraftID else { return }
        CaptureDraftStore.update(id: activeDraftID, transcript: text)
    }

    private func scheduleCheckpoint(_ text: String, source: CaptureSource) {
        // Keep JSON encoding and UserDefaults writes out of the per-keystroke
        // path while retaining a short crash-recovery window.
        draftCheckpointTask?.cancel()
        draftCheckpointTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(220))
            guard !Task.isCancelled else { return }
            checkpoint(text, source: source)
            draftCheckpointTask = nil
        }
    }

    private func flushPendingCheckpoint() {
        draftCheckpointTask?.cancel()
        draftCheckpointTask = nil
        guard let activeDraftID else { return }
        let text = mode == .text ? typedText : transcriber.transcript
        CaptureDraftStore.update(id: activeDraftID, transcript: text)
    }

    private func ensureDraft(source: CaptureSource) {
        if let activeDraftID {
            CaptureDraftStore.updateSource(id: activeDraftID, source: source)
            return
        }
        let draft = CaptureDraftStore.begin(source: source)
        activeDraftID = draft.id
        captureStartedAt = draft.startedAt
    }

    private func discardActiveDraft() {
        draftCheckpointTask?.cancel()
        draftCheckpointTask = nil
        if let activeDraftID {
            CaptureDraftStore.clear(id: activeDraftID)
        }
        activeDraftID = nil
        captureStartedAt = nil
    }

    private func finishSavedCapture() {
        confirmationDismissTask?.cancel()
        onSaved()
        dismiss()
    }
}

struct CaptureView_Previews: PreviewProvider {
    @MainActor
    static var previews: some View {
        let preview = PreviewData.make(seed: false)
        return CaptureView(onSaved: {})
            .modelContainer(preview.container)
            .environment(\.thoughtRepository, preview.repository)
            .environmentObject(SubscriptionStore())
    }
}
