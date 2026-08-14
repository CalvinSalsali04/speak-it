import Accessibility
import AppIntents
import AVFoundation
import Speech
import SwiftUI

enum CaptureAnywhereMethod: String, CaseIterable, Identifiable {
    case lockScreen
    case controlCenter
    case actionButton
    case backTap

    var id: String { rawValue }

    var title: String {
        switch self {
        case .lockScreen: "Lock Screen"
        case .controlCenter: "Control Center"
        case .actionButton: "Action Button"
        case .backTap: "Back Tap"
        }
    }

    var shortInstruction: String {
        switch self {
        case .lockScreen: "Tap once"
        case .controlCenter: "Swipe, then tap"
        case .actionButton: "Press and hold"
        case .backTap: "Double tap"
        }
    }

    var systemImage: String {
        switch self {
        case .lockScreen: "lock.rectangle"
        case .controlCenter: "switch.2"
        case .actionButton: "button.programmable"
        case .backTap: "hand.tap"
        }
    }

    var summary: String {
        switch self {
        case .lockScreen:
            "One tap and Speak It opens already listening. The most reliable option on every iPhone."
        case .controlCenter:
            "A native Speak It control that is available from any screen without creating a Shortcut."
        case .actionButton:
            "The fastest option on this iPhone. Press and hold to open Speak It already listening."
        case .backTap:
            "Double tap the back of your iPhone to open Speak It already listening. iOS can occasionally miss the gesture."
        }
    }

    var testInstruction: String {
        switch self {
        case .lockScreen:
            "Lock your iPhone, tap the Speak It widget, and say a short thought."
        case .controlCenter:
            "Open Control Center, tap Speak It, and say a short thought."
        case .actionButton:
            "Press and hold the Action Button, then say a short thought."
        case .backTap:
            "From the Home Screen or another app, double tap the back, then say a short thought."
        }
    }
}

enum SpeakItHardware {
    static var supportsActionButton: Bool {
        let simulatorIdentifier = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"]
        return supportsActionButton(modelIdentifier: simulatorIdentifier ?? modelIdentifier)
    }

    static func supportsActionButton(modelIdentifier: String) -> Bool {
        guard modelIdentifier.hasPrefix("iPhone") else { return false }
        let version = modelIdentifier.dropFirst("iPhone".count).split(separator: ",")
        guard version.count == 2,
              let major = Int(version[0]),
              let minor = Int(version[1]) else { return false }

        // iPhone16,1 and iPhone16,2 are the 15 Pro models. Every iPhone17,*
        // generation and newer uses the Action Button as well.
        return major > 16 || (major == 16 && (minor == 1 || minor == 2))
    }

    private static var modelIdentifier: String {
        var info = utsname()
        uname(&info)
        let capacity = MemoryLayout.size(ofValue: info.machine)
        return withUnsafePointer(to: &info.machine) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: capacity) {
                String(cString: $0)
            }
        }
    }
}

struct CaptureAnywhereSetupView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("SpeakIt.shortcutSetupCompleted") private var setupCompleted = false
    @AppStorage("SpeakIt.captureAnywhereMethod") private var methodRawValue = ""
    @AppStorage("SpeakIt.captureSetupTestBeganAt") private var testBeganAt = 0.0
    @AppStorage(CaptureActivationStore.lastInvocationKey) private var lastInvocation = 0.0
    @AppStorage(CaptureActivationStore.lastMicrophoneReadyKey) private var lastMicrophoneReady = 0.0
    @AppStorage(CaptureActivationStore.lastSuccessKey) private var lastSuccess = 0.0
    @AppStorage(CaptureActivationStore.lastFailureKey) private var lastFailure = 0.0
    @AppStorage(CaptureActivationStore.lastStartupDurationKey) private var lastStartupDuration = 0.0

    @State private var settingsErrorMessage: String?
    @State private var showsVoiceTest = false

    let showsOnboardingProgress: Bool

    init(showsOnboardingProgress: Bool = false) {
        self.showsOnboardingProgress = showsOnboardingProgress
    }

    private var recommendedMethod: CaptureAnywhereMethod {
        SpeakItHardware.supportsActionButton ? .actionButton : .lockScreen
    }

    private var availableMethods: [CaptureAnywhereMethod] {
        var methods: [CaptureAnywhereMethod] = SpeakItHardware.supportsActionButton
            ? [.actionButton, .lockScreen]
            : [.lockScreen]
        if #available(iOS 18.0, *) {
            methods.append(.controlCenter)
        }
        methods.append(.backTap)
        return methods
    }

    private var selectedMethod: CaptureAnywhereMethod {
        guard let stored = CaptureAnywhereMethod(rawValue: methodRawValue),
              availableMethods.contains(stored) else {
            return recommendedMethod
        }
        return stored
    }

    private var isTesting: Bool { testBeganAt > 0 }
    private var didDetectInvocation: Bool { isTesting && lastInvocation >= testBeganAt }
    private var didDetectReadyMicrophone: Bool {
        isTesting && lastMicrophoneReady >= testBeganAt
    }
    private var didDetectFailure: Bool {
        isTesting && lastFailure >= testBeganAt && lastFailure > lastMicrophoneReady
    }
    private var didVerifySave: Bool { isTesting && lastSuccess >= testBeganAt }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    methodPicker

                    if !hasVoiceAccess {
                        voiceAccessCard
                    }

                    setupCard
                    testCard
                    help
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 36)
            }
            .scrollIndicators(.hidden)
            .speakScreenStyle()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(showsOnboardingProgress ? "Later" : "Done") {
                        dismiss()
                    }
                }
            }
            .alert("Couldn’t open Accessibility", isPresented: Binding(
                get: { settingsErrorMessage != nil },
                set: { if !$0 { settingsErrorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { settingsErrorMessage = nil }
            } message: {
                Text(settingsErrorMessage ?? "Please open Accessibility in Settings.")
            }
        }
        .fullScreenCover(isPresented: $showsVoiceTest) {
            CaptureView {
                showsVoiceTest = false
            }
        }
        .onAppear {
            if !availableMethods.contains(where: { $0.rawValue == methodRawValue }) {
                methodRawValue = recommendedMethod.rawValue
            }
            recognizeSuccessfulTest()
        }
        .onChange(of: lastSuccess) { _, _ in
            recognizeSuccessfulTest()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(showsOnboardingProgress ? "FIRST THOUGHT SAVED" : "CAPTURE ANYWHERE")
                .font(.caption.weight(.medium))
                .tracking(1.8)
                .foregroundStyle(Color.speakMuted)

            Text(showsOnboardingProgress ? "Now make it instant." : "One gesture. Then speak.")
                .font(.largeTitle.weight(.semibold))
                .foregroundStyle(Color.speakInk)

            Text("Choose one way to reach Speak It outside the app. You can add the others later.")
                .font(.body)
                .foregroundStyle(Color.speakMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var methodPicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("BEST FOR THIS IPHONE")
                .font(.caption.weight(.medium))
                .tracking(1.5)
                .foregroundStyle(Color.speakMuted)

            methodButton(recommendedMethod, isRecommended: true)

            Text("OTHER WAYS")
                .font(.caption.weight(.medium))
                .tracking(1.5)
                .foregroundStyle(Color.speakMuted)
                .padding(.top, 4)

            ForEach(availableMethods.filter { $0 != recommendedMethod }) { method in
                methodButton(method, isRecommended: false)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func methodButton(
        _ method: CaptureAnywhereMethod,
        isRecommended: Bool
    ) -> some View {
        let isSelected = selectedMethod == method

        return Button {
            guard selectedMethod != method else { return }
            withAnimation(.easeInOut(duration: 0.18)) {
                methodRawValue = method.rawValue
                testBeganAt = 0
                setupCompleted = false
            }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: method.systemImage)
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 42, height: 42)
                    .background(
                        isSelected ? Color.white.opacity(0.12) : Color.speakInk.opacity(0.07),
                        in: Circle()
                    )

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 7) {
                        Text(method.title)
                            .font(.headline)
                        if isRecommended {
                            Text("RECOMMENDED")
                                .font(.system(size: 9, weight: .bold))
                                .tracking(0.8)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 4)
                                .background(
                                    isSelected ? Color.white.opacity(0.12) : Color.speakInk.opacity(0.07),
                                    in: Capsule()
                                )
                        }
                    }

                    Text(method.shortInstruction)
                        .font(.subheadline)
                        .opacity(0.64)
                }

                Spacer(minLength: 8)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18, weight: .semibold))
            }
            .foregroundStyle(isSelected ? Color.speakInverseInk : Color.speakInk)
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
            .background(
                isSelected ? Color.speakInverseSurface : Color.speakSurface,
                in: RoundedRectangle(cornerRadius: 21, style: .continuous)
            )
            .overlay {
                if !isSelected {
                    RoundedRectangle(cornerRadius: 21, style: .continuous)
                        .stroke(Color.speakDivider, lineWidth: 1)
                }
            }
        }
        .buttonStyle(.speakIt)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var voiceAccessCard: some View {
        HStack(spacing: 14) {
            Image(systemName: "mic")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Color.speakInverseInk)
                .frame(width: 38, height: 38)
                .background(Color.speakInverseSurface, in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text("Allow voice access first")
                    .font(.headline)
                    .foregroundStyle(Color.speakInk)
                Text("Try one capture so iPhone can ask while Speak It is open.")
                    .font(.subheadline)
                    .foregroundStyle(Color.speakMuted)
            }

            Spacer(minLength: 6)

            Button("Allow") {
                showsVoiceTest = true
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color.speakInk)
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .background(Color.speakInk.opacity(0.08), in: Capsule())
            .buttonStyle(.speakIt)
        }
        .padding(18)
        .setupCardStyle()
    }

    private var hasVoiceAccess: Bool {
        SFSpeechRecognizer.authorizationStatus() == .authorized &&
            AVAudioApplication.shared.recordPermission == .granted
    }

    @ViewBuilder
    private var setupCard: some View {
        switch selectedMethod {
        case .lockScreen:
            lockScreenSetupCard
        case .controlCenter:
            controlCenterSetupCard
        case .actionButton:
            actionButtonSetupCard
        case .backTap:
            backTapSetupCard
        }
    }

    private var lockScreenSetupCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            setupHeader
            setupStep(
                1,
                title: "Long-press your Lock Screen",
                detail: "Tap Customize, then choose Lock Screen."
            )
            setupStep(
                2,
                title: "Tap the widget area",
                detail: "Find Speak It and add Speak It Capture. Tap Done."
            )
            setupStep(
                3,
                title: "Tap once and speak",
                detail: "Speak It opens already listening and saves after your natural pause.",
                showsConnector: false
            )
        }
        .setupCardStyle()
    }

    private var actionButtonSetupCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            setupHeader
            setupStep(
                1,
                title: "Open Settings → Action Button",
                detail: "Swipe until the action says Shortcut."
            )
            setupStep(
                2,
                title: "Choose Speak It Capture",
                detail: "The finished action is already supplied by Speak It."
            )
            setupStep(
                3,
                title: "Press and hold to speak",
                detail: "Speak It opens already listening and saves after your natural pause.",
                showsConnector: false
            )
        }
        .setupCardStyle()
    }

    private var controlCenterSetupCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            setupHeader
            setupStep(
                1,
                title: "Open Control Center",
                detail: "Touch and hold an empty area, then tap Add a Control."
            )
            setupStep(
                2,
                title: "Search for Speak It",
                detail: "Choose the Speak It control and place it wherever your thumb naturally reaches."
            )
            setupStep(
                3,
                title: "Tap once and speak",
                detail: "Speak It opens already listening and saves after your natural pause.",
                showsConnector: false
            )
        }
        .setupCardStyle()
    }

    private var backTapSetupCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            setupHeader
            setupStep(
                1,
                title: "Add the tiny Back Tap shortcut",
                detail: "Open Shortcuts. On Speak It Capture, tap ••• → Use in New Shortcut → Done."
            )

            ShortcutsLink()
                .shortcutsLinkStyle(.automaticOutline)

            if #available(iOS 26.0, *) {
                openAccessibilityButton
                setupStep(
                    2,
                    title: "Go back to Touch",
                    detail: "Tap ‹ Touch at the top-left, scroll to Back Tap, then open Double Tap."
                )
            } else {
                setupStep(
                    2,
                    title: "Open Accessibility → Touch",
                    detail: "Scroll to Back Tap, then open Double Tap."
                )
            }

            setupStep(
                3,
                title: "Choose Speak It Capture",
                detail: "Find it under Shortcuts. Double tap to open Speak It already listening.",
                showsConnector: false
            )
        }
        .setupCardStyle()
    }

    private var setupHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            setupLabel("ONE-TIME SETUP")
            Text(selectedMethod.summary)
                .font(.subheadline)
                .foregroundStyle(Color.speakMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var testCard: some View {
        Group {
            if didVerifySave {
                VStack(spacing: 16) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.black)
                        .frame(width: 56, height: 56)
                        .background(.white, in: Circle())

                    VStack(spacing: 4) {
                        Text("Connected and remembered")
                            .font(.title3.weight(.semibold))
                        Text("Your outside-the-app capture saved successfully.")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.64))
                            .multilineTextAlignment(.center)
                    }

                    Button(action: finishSetup) {
                        Text("Finish setup")
                            .font(.headline)
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.speakIt)
                    .background(.white, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                }
                .foregroundStyle(.white)
                .padding(22)
                .frame(maxWidth: .infinity)
                .background(.black, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
                .accessibilityElement(children: .contain)
            } else if isTesting {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 14) {
                        ZStack {
                            Circle()
                                .stroke(.white.opacity(0.18), lineWidth: 1)
                                .frame(width: 48, height: 48)
                            Circle()
                                .fill(.white)
                                .frame(width: 26, height: 26)
                            Image(systemName: testStatusSymbol)
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.black)
                        }

                        VStack(alignment: .leading, spacing: 3) {
                            Text(testStatusTitle)
                                .font(.headline)
                            Text(testStatusDetail)
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.64))
                                .fixedSize(horizontal: false, vertical: true)

                            if didDetectReadyMicrophone {
                                Text("Microphone ready in \(lastStartupDuration.formatted(.number.precision(.fractionLength(1))))s")
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.white.opacity(0.46))
                            }
                        }
                    }

                    Button("Restart test") {
                        beginTest()
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .buttonStyle(.speakIt)

                    Button("Finish later") {
                        dismiss()
                    }
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.58))
                    .buttonStyle(.speakIt)
                }
                .foregroundStyle(.white)
                .padding(22)
                .background(.black, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Prove it works")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(Color.speakInk)
                        Text("Don’t leave setup guessing. Speak It will confirm after a real outside-the-app thought is saved.")
                            .font(.subheadline)
                            .foregroundStyle(Color.speakMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Button(action: beginTest) {
                        Text("I added it — test now")
                            .font(.headline)
                            .foregroundStyle(Color.speakInverseInk)
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.speakIt)
                    .background(
                        Color.speakInverseSurface,
                        in: RoundedRectangle(cornerRadius: 17, style: .continuous)
                    )

                    Button("Finish later") {
                        dismiss()
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.speakMuted)
                    .buttonStyle(.speakIt)
                }
                .setupCardStyle()
            }
        }
    }

    @available(iOS 26.0, *)
    private var openAccessibilityButton: some View {
        Button {
            Task { await openAccessibilitySettings() }
        } label: {
            Label("Open near Back Tap", systemImage: "arrow.up.forward.app")
                .font(.headline)
                .foregroundStyle(Color.speakInverseInk)
                .frame(maxWidth: .infinity, minHeight: 52)
        }
        .buttonStyle(.speakIt)
        .background(
            Color.speakInverseSurface,
            in: RoundedRectangle(cornerRadius: 17, style: .continuous)
        )
        .accessibilityHint("Opens inside Touch settings, near the route to Back Tap")
    }

    @available(iOS 26.0, *)
    @MainActor
    private func openAccessibilitySettings() async {
        do {
            try await AccessibilitySettings.openSettings(for: .assistiveTouch)
        } catch {
            settingsErrorMessage = "Open Settings → Accessibility → Touch → Back Tap."
        }
    }

    private var help: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 10) {
                Text("Every option opens Speak It already listening. Lock Screen is simplest; Action Button is fastest on supported iPhones; Back Tap is convenient but iOS may occasionally miss the gesture.")
                if selectedMethod == .backTap {
                    Text("Apple only exposes personal shortcuts in Back Tap, which is why that option needs one extra Shortcuts step.")
                }
            }
            .font(.footnote)
            .foregroundStyle(Color.speakMuted)
            .padding(.top, 10)
        } label: {
            Text("Which option should I use?")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color.speakInk)
        }
        .tint(Color.speakInk)
    }

    private func beginTest() {
        withAnimation(.easeInOut(duration: 0.2)) {
            testBeganAt = Date.now.timeIntervalSince1970
            setupCompleted = false
        }
    }

    private var testStatusSymbol: String {
        if didDetectFailure { return "exclamationmark" }
        if didDetectReadyMicrophone { return "waveform" }
        if didDetectInvocation { return "ellipsis" }
        return selectedMethod.systemImage
    }

    private var testStatusTitle: String {
        if didDetectFailure { return "Microphone didn’t start" }
        if didDetectReadyMicrophone { return "Microphone is listening" }
        if didDetectInvocation { return "Trigger detected" }
        return "Test it now"
    }

    private var testStatusDetail: String {
        if didDetectFailure {
            return "Unlock your iPhone and try once more. Your setup is still saved."
        }
        if didDetectReadyMicrophone {
            return "Finish speaking. We’ll confirm only after your thought saves."
        }
        if didDetectInvocation {
            return "Speak It received the shortcut and is activating the microphone."
        }
        return selectedMethod.testInstruction
    }

    private func recognizeSuccessfulTest() {
        guard didVerifySave else { return }
        withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
            setupCompleted = true
        }
    }

    private func finishSetup() {
        setupCompleted = true
        testBeganAt = 0
        dismiss()
    }

    private func setupLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.medium))
            .tracking(1.5)
            .foregroundStyle(Color.speakMuted)
    }

    private func setupStep(
        _ number: Int,
        title: String,
        detail: String,
        showsConnector: Bool = true
    ) -> some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 0) {
                Text("\(number)")
                    .font(.caption.bold())
                    .foregroundStyle(Color.speakInverseInk)
                    .frame(width: 30, height: 30)
                    .background(Color.speakInverseSurface, in: Circle())

                if showsConnector {
                    Rectangle()
                        .fill(Color.speakDivider)
                        .frame(width: 1, height: 42)
                }
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(Color.speakInk)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(Color.speakMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.bottom, showsConnector ? 12 : 0)
        }
        .accessibilityElement(children: .combine)
    }
}

private extension View {
    func setupCardStyle() -> some View {
        self
            .padding(20)
            .background(Color.speakSurface, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .stroke(Color.speakDivider, lineWidth: 1)
            }
    }
}
