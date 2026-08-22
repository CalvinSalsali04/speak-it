import SwiftUI
import UIKit

enum CaptureInitialMode: Equatable, Sendable {
    case voice
    case text
}

struct CaptureView: View {
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
    private let performance: CapturePerformanceTrace?
    private let onSaveSucceeded: () -> Void
    private let onCancelled: () -> Void

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

    init(
        initialMode: CaptureInitialMode = .voice,
        autoStartsVoiceCapture: Bool = false,
        initialText: String = "",
        performance: CapturePerformanceTrace? = nil,
        autoDismissesSingleItemConfirmation: Bool = true,
        showsGuidedExamples: Bool = false,
        onSaveSucceeded: @escaping () -> Void = {},
        onCancelled: @escaping () -> Void = {},
        onSaved: @escaping () -> Void
    ) {
        self.onSaved = onSaved
        startsInTextMode = initialMode == .text
        self.autoStartsVoiceCapture = autoStartsVoiceCapture && initialMode == .voice
        self.autoDismissesSingleItemConfirmation = autoDismissesSingleItemConfirmation
        self.showsGuidedExamples = showsGuidedExamples
        self.performance = performance
        self.onSaveSucceeded = onSaveSucceeded
        self.onCancelled = onCancelled
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
                scheduleCheckpoint(newTranscript, source: .inAppVoice)
            }
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

            Spacer()

            SpeakItWordmark()

            Spacer()

            Color.clear.frame(width: 38, height: 38)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

    private var voiceView: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 20)

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

            ScrollView {
                Text(transcriber.transcript.isEmpty ? " " : transcriber.transcript)
                    .font(.title3)
                    .foregroundStyle(Color.speakInk.opacity(0.84))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 330)
                    .padding(.horizontal)
            }
            .frame(maxHeight: 126)
            .accessibilityLabel("Live transcription")
            .accessibilityValue(transcriber.transcript)

            if showsGuidedExamples,
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

    private var typingView: some View {
        VStack(alignment: .leading, spacing: 22) {
            Spacer(minLength: 26)

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

            if let savedResult,
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

                    Button("Done", action: finishSavedCapture)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.speakInk)
                        .frame(maxWidth: .infinity, minHeight: 46)
                        .buttonStyle(.speakIt)
                }
                .padding(.top, 8)
                .frame(maxWidth: 330)
            } else if savedResult != nil, requiresExplicitSavedConfirmation {
                Button("Continue", action: finishSavedCapture)
                    .font(.headline)
                    .foregroundStyle(Color.speakInverseInk)
                    .frame(maxWidth: 330, minHeight: 54)
                    .buttonStyle(.speakIt)
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

    /// Shown only for the guided first capture, and only until words arrive.
    /// One example per destination, so the person's first attempt can be any
    /// of the three things the app actually does with a thought.
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
        .accessibilityLabel(
            "Try saying: Remind me to call Mom tomorrow at 6. Buy milk, eggs, and toothpaste. Or, Priya's birthday is December 4th."
        )
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
        case .requestingPermission: "Getting ready…"
        case .listening: "Listening"
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
        case .requestingPermission: "Speak It only listens while you’re capturing."
        case .listening: "Just speak. I’ll save after a natural pause."
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
            ? "Finishes immediately; otherwise Speak It finishes after a natural pause"
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
        await transcriber.start(recoveryAudioURL: recoveryURL) { finalText in
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
                voiceNotice = "I didn’t hear anything. Tap when you’re ready, or type instead."
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
                Task { await CaptureActivityManager.cancelListening() }
            }
        }
    }

    private func switchToTyping() {
        captureNotice = nil
        let partialTranscript = transcriber.transcript
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
        let partialTranscript = transcriber.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
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
        let normalizedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
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
            performance?.updateSource(.voice)
            let finalizedAt = transcriber.finalTranscriptAt ?? CapturePerformanceClock.now
            performance?.markEndOfSpeechDetected(
                lastSpeechAt: transcriber.lastVoiceActivityAt,
                at: transcriber.speechEndpointDetectedAt ?? finalizedAt
            )
            performance?.markTranscriptFinalized(at: finalizedAt)
        }
        subscriptionStore.refreshFreeAllowance()
        guard subscriptionStore.canCreateCapture else {
            isTextFocused = false
            transcriber.cancel()
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
                let result = try await repository.createCaptureResult(
                    text: normalizedText,
                    source: source,
                    createdAt: captureStartedAt ?? .now,
                    schedulesReminders: true,
                    performance: performance
                )
                if result.createdNewCapture {
                    // Cancelling, completing or withdrawing manages existing
                    // content rather than storing a new thought, so it does not
                    // spend one of the ten free captures.
                    if result.consumesFreeCapture {
                        subscriptionStore.recordSuccessfulCapture()
                    }
                    SpeakItAnalytics.track(.captureSaved(
                        source: source == .inAppVoice ? .voice : .text,
                        itemCount: result.itemCount,
                        needsReviewCount: result.needsReviewCount,
                        plan: subscriptionStore.hasProAccess ? .pro : .free
                    ))
                }
                isSaving = false
                discardActiveDraft()
                typedText = ""
                savedResult = result
                onSaveSucceeded()
                // An operation reports what it did. Saying "Remembered" after
                // cancelling something is the app describing the wrong action.
                if let outcome = result.operationOutcome {
                    let copy = CaptureOperationCopy.make(for: outcome)
                    savedConfirmationTitle = copy.title
                    savedConfirmationSymbol = copy.symbol
                    savedConfirmationDetail = copy.detail
                } else {
                    savedConfirmationTitle = result.isDuplicate ? "Already captured" : "Remembered"
                    savedConfirmationSymbol = result.isDuplicate ? "equal" : "checkmark"
                    savedConfirmationDetail = confirmationDetail(for: result)
                }
                if result.isDuplicate {
                    UISelectionFeedbackGenerator().selectionChanged()
                } else {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                }
                withAnimation(.spring(response: 0.45, dampingFraction: 0.72)) {
                    showsSavedConfirmation = true
                }
                Task {
                    await CaptureActivityManager.showRemembered(
                        normalizedText,
                        context: savedConfirmationDetail
                    )
                }

                if closesAfterSave {
                    closesAfterSave = false
                    finishSavedCapture()
                    return
                }

                if result.itemCount == 1,
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
