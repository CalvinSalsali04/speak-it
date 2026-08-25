import Accessibility
import AppIntents
import AVFoundation
import Speech
import SwiftUI

enum CaptureAnywhereMethod: String, CaseIterable, Identifiable {
    case lockScreen
    case homeScreen
    case controlCenter
    case actionButton
    case backTap
    case siri

    var id: String { rawValue }

    var title: String {
        switch self {
        case .lockScreen: "Lock Screen"
        case .homeScreen: "Home Screen Widget"
        case .controlCenter: "Control Center"
        case .actionButton: "Action Button"
        case .backTap: "Back Tap"
        case .siri: "Siri"
        }
    }

    var shortInstruction: String {
        switch self {
        case .lockScreen: "Tap once"
        case .homeScreen: "Tap the widget"
        case .controlCenter: "Swipe down, then tap"
        case .actionButton: "Press and hold"
        case .backTap: "Double-tap the back"
        case .siri: "Just say it — no setup"
        }
    }

    var systemImage: String {
        switch self {
        case .lockScreen: "lock.rectangle"
        case .homeScreen: "rectangle.grid.2x2"
        case .controlCenter: "switch.2"
        case .actionButton: "button.programmable"
        case .backTap: "hand.tap"
        case .siri: "waveform.circle"
        }
    }

    var summary: String {
        switch self {
        case .lockScreen:
            "One tap on your Lock Screen and Speak It is already listening. Works on every iPhone."
        case .homeScreen:
            "A big Speak It button next to your apps. Tap it and it's already listening."
        case .controlCenter:
            "Swipe down from the top-right corner and tap Speak It from any screen."
        case .actionButton:
            "Press and hold the button on the side of your iPhone. The fastest way there is."
        case .backTap:
            "Double-tap the back of your iPhone — it works even through most cases, from any screen."
        case .siri:
            "Nothing to set up. Just say the phrase and Speak It starts listening."
        }
    }

    var testInstruction: String {
        switch self {
        case .lockScreen:
            "Lock your iPhone, tap the Speak It widget, and say a short thought."
        case .homeScreen:
            "Go to your Home Screen, tap the Speak It Capture widget, and say a short thought."
        case .controlCenter:
            "Open Control Center, tap Speak It, and say a short thought."
        case .actionButton:
            "Press and hold the Action Button, then say a short thought."
        case .backTap:
            "From the Home Screen or another app, double-tap the back, then say a short thought."
        case .siri:
            "Say “Capture with Speak It”, then say a short thought."
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
    @State private var showsOtherMethods = false
    @State private var hasAppliedOnboardingRecommendation = false

    let showsOnboardingProgress: Bool
    let onFinished: (() -> Void)?

    init(
        showsOnboardingProgress: Bool = false,
        onFinished: (() -> Void)? = nil
    ) {
        self.showsOnboardingProgress = showsOnboardingProgress
        self.onFinished = onFinished
    }

    private var supportsControlCenterControl: Bool {
        if #available(iOS 18.0, *) { return true }
        return false
    }

    /// The single method this iPhone is best served by. Action Button wins on
    /// hardware that has one; Back Tap is the everyday pick everywhere else
    /// because it works from any screen with no reachable button.
    private var recommendedMethod: CaptureAnywhereMethod {
        SpeakItHardware.supportsActionButton ? .actionButton : .backTap
    }

    /// Every method the user can actually finish setting up on this iPhone.
    private var availableMethods: [CaptureAnywhereMethod] {
        var methods: [CaptureAnywhereMethod] = [recommendedMethod]
        let others: [CaptureAnywhereMethod] = [
            .actionButton, .backTap, .lockScreen, .controlCenter, .homeScreen, .siri
        ]
        for method in others where !methods.contains(method) {
            switch method {
            case .actionButton:
                if SpeakItHardware.supportsActionButton { methods.append(method) }
            case .controlCenter:
                if supportsControlCenterControl { methods.append(method) }
            default:
                methods.append(method)
            }
        }
        return methods
    }

    /// Methods this iPhone can't offer, shown so nobody wonders what exists on
    /// other devices, each with the reason it's missing here.
    private var unavailableMethods: [CaptureAnywhereMethod] {
        var unavailable: [CaptureAnywhereMethod] = []
        if !SpeakItHardware.supportsActionButton {
            unavailable.append(.actionButton)
        }
        if !supportsControlCenterControl {
            unavailable.append(.controlCenter)
        }
        return unavailable
    }

    private func unavailableReason(for method: CaptureAnywhereMethod) -> String {
        switch method {
        case .actionButton:
            "Needs an iPhone 15 Pro or newer with the Action Button on the side."
        case .controlCenter:
            "Needs iOS 18 or later. Update in Settings → General → Software Update."
        default:
            ""
        }
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
                    Button(setupCompleted ? "Done" : "Done for now") {
                        finishOrDismiss()
                    }
                    .accessibilityHint("Setup is optional and can be finished later in Settings")
                    .accessibilityIdentifier("captureAnywhere.done")
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
            if showsOnboardingProgress, !hasAppliedOnboardingRecommendation {
                hasAppliedOnboardingRecommendation = true
                methodRawValue = recommendedMethod.rawValue
            } else if !availableMethods.contains(where: { $0.rawValue == methodRawValue }) {
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
            Text(showsOnboardingProgress ? "RECOMMENDED SETUP" : "CAPTURE ANYWHERE")
                .font(.caption.weight(.medium))
                .tracking(1.8)
                .foregroundStyle(Color.speakMuted)

            Text(showsOnboardingProgress ? "Set up \(recommendedMethod.title)" : "One gesture. Then speak.")
                .font(.largeTitle.weight(.semibold))
                .foregroundStyle(Color.speakInk)

            Text(
                showsOnboardingProgress
                    ? "\(recommendedMethod.shortInstruction) from any screen. You can skip this and return later."
                    : "Choose one quick way to capture from any screen. You can change it later."
            )
                .font(.body)
                .foregroundStyle(Color.speakMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var methodPicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(selectedMethod == recommendedMethod ? "BEST FOR THIS IPHONE" : "YOUR CHOICE")
                .font(.caption.weight(.medium))
                .tracking(1.5)
                .foregroundStyle(Color.speakMuted)

            methodButton(
                selectedMethod,
                isRecommended: selectedMethod == recommendedMethod
            )

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showsOtherMethods.toggle()
                }
            } label: {
                HStack {
                    Text("Choose a different way")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Image(systemName: showsOtherMethods ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.bold))
                }
                .foregroundStyle(Color.speakInk)
                .contentShape(Rectangle())
            }
            .buttonStyle(.speakIt)
            .accessibilityValue(showsOtherMethods ? "Expanded" : "Collapsed")
            .accessibilityIdentifier("captureAnywhere.otherMethods")

            if showsOtherMethods {
                VStack(spacing: 10) {
                    ForEach(availableMethods.filter { $0 != selectedMethod }) { method in
                        methodButton(
                            method,
                            isRecommended: method == recommendedMethod
                        )
                    }

                    if !unavailableMethods.isEmpty {
                        Text("NOT ON THIS IPHONE")
                            .font(.caption.weight(.medium))
                            .tracking(1.5)
                            .foregroundStyle(Color.speakMuted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 4)

                        ForEach(unavailableMethods) { method in
                            unavailableMethodRow(method, reason: unavailableReason(for: method))
                        }
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
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
                showsOtherMethods = false
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
        .accessibilityIdentifier("captureAnywhere.method.\(method.rawValue)")
    }

    private func unavailableMethodRow(
        _ method: CaptureAnywhereMethod,
        reason: String
    ) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: method.systemImage)
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 42, height: 42)
                .background(Color.speakInk.opacity(0.05), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(method.title)
                    .font(.headline)
                Text(reason)
                    .font(.subheadline)
                    .opacity(0.72)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)
        }
        .foregroundStyle(Color.speakMuted)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.speakSurface.opacity(0.6), in: RoundedRectangle(cornerRadius: 21, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 21, style: .continuous)
                .stroke(Color.speakDivider, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("captureAnywhere.unavailable.\(method.rawValue)")
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

            Button {
                showsVoiceTest = true
            } label: {
                Text("Allow")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.speakInk)
                    .padding(.horizontal, 12)
                    .frame(minWidth: 72, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.speakIt)
            .background(Color.speakInk.opacity(0.08), in: Capsule())
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
        case .homeScreen:
            homeScreenSetupCard
        case .controlCenter:
            controlCenterSetupCard
        case .actionButton:
            actionButtonSetupCard
        case .backTap:
            backTapSetupCard
        case .siri:
            siriSetupCard
        }
    }

    private var lockScreenSetupCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            setupHeader

            LockScreenIllustration()
                .frame(maxWidth: .infinity)

            setupStep(
                1,
                title: "Hold your finger on the Lock Screen",
                detail: "Keep pressing until the screen shrinks, then tap Customize → Lock Screen."
            )
            setupStep(
                2,
                title: "Tap the box under the clock",
                detail: "Search Speak It, tap Speak It Capture to add it, then tap Done at the top."
            )
            setupStep(
                3,
                title: "Tap it once and speak",
                detail: "Speak It opens already listening and saves when you pause.",
                showsConnector: false
            )
        }
        .setupCardStyle()
    }

    private var actionButtonSetupCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            setupHeader

            ActionButtonIllustration()
                .frame(maxWidth: .infinity)

            setupStep(
                1,
                title: "Set the button to Shortcut",
                detail: "Three taps in Settings."
            ) {
                GuidedSequenceView(screens: SetupSequences.actionButton)
            }
            setupStep(
                2,
                title: "Press and hold the side button",
                detail: "Speak It opens already listening and saves when you pause.",
                showsConnector: false
            )
        }
        .setupCardStyle()
    }

    private var homeScreenSetupCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            setupHeader

            HomeScreenIllustration()
                .frame(maxWidth: .infinity)

            if #available(iOS 18.0, *) {
                setupStep(
                    1,
                    title: "Hold your finger on the Home Screen",
                    detail: "When the apps start wiggling, tap Edit in the top-left, then Add Widget."
                )
            } else {
                setupStep(
                    1,
                    title: "Hold your finger on the Home Screen",
                    detail: "When the apps start wiggling, tap + in the top-left corner."
                )
            }
            setupStep(
                2,
                title: "Search for Speak It",
                detail: "Choose Speak It Capture, tap Add Widget, then put it where your thumb can reach."
            )
            setupStep(
                3,
                title: "Tap the widget and speak",
                detail: "Speak It opens already listening and saves when you pause.",
                showsConnector: false
            )
        }
        .setupCardStyle()
    }

    private var controlCenterSetupCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            setupHeader

            ControlCenterIllustration()
                .frame(maxWidth: .infinity)

            setupStep(
                1,
                title: "Swipe down from the top-right corner",
                detail: "Hold your finger on an empty spot, then tap Add a Control at the bottom."
            )
            setupStep(
                2,
                title: "Search for Speak It",
                detail: "Tap the Speak It control to add it, then drag it where your thumb can reach."
            )
            setupStep(
                3,
                title: "Tap it once and speak",
                detail: "Speak It opens already listening and saves when you pause.",
                showsConnector: false
            )
        }
        .setupCardStyle()
    }

    private var backTapSetupCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            setupHeader

            BackTapIllustration()
                .frame(maxWidth: .infinity)

            setupStep(
                1,
                title: "Tap Add Shortcut below",
                detail: "In Shortcuts, hold the new tile and choose New Shortcut. This takes about ten seconds."
            ) {
                VStack(alignment: .leading, spacing: 14) {
                    ShortcutsLink()
                        .shortcutsLinkStyle(.automaticOutline)

                    GuidedSequenceView(screens: SetupSequences.addShortcut)
                }
            }

            if #available(iOS 26.0, *) {
                setupStep(
                    2,
                    title: "Open Touch settings",
                    detail: "Tap the button below. Go back once, then scroll to Back Tap at the bottom."
                ) {
                    VStack(alignment: .leading, spacing: 14) {
                        openAccessibilityButton

                        GuidedSequenceView(screens: SetupSequences.backTapFromDeepLink)
                    }
                }
            } else {
                setupStep(
                    2,
                    title: "Turn on Back Tap",
                    detail: "It's at the bottom of Touch settings."
                ) {
                    GuidedSequenceView(screens: SetupSequences.backTapFromSettings)
                }
            }

            setupStep(
                3,
                title: "Pick Capture with Speak It",
                detail: "Scroll all the way down. It's the last section.",
                showsConnector: false
            ) {
                GuidedSequenceView(screens: SetupSequences.pickSpeakItCapture)
            }
        }
        .setupCardStyle()
    }

    private var siriSetupCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            setupHeader

            SiriIllustration()
                .frame(maxWidth: .infinity)

            setupStep(
                1,
                title: "There's nothing to set up",
                detail: "Siri already knows Speak It. It works from the Lock Screen, other apps, and with AirPods."
            )
            setupStep(
                2,
                title: "Say “Capture with Speak It”",
                detail: "Speak It opens already listening and saves when you pause. You can also say “Remember this with Speak It.”",
                showsConnector: false
            )
        }
        .setupCardStyle()
    }

    private var setupHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            setupLabel(selectedMethod == .siri ? "READY NOW" : "ONE-TIME SETUP")
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
                        finishOrDismiss()
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
                    .accessibilityIdentifier("captureAnywhere.test")

                    Button("Finish later") {
                        finishOrDismiss()
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
                Text("Every option opens Speak It already listening, so pick whichever feels most natural. The Action Button is fastest when your iPhone has one. Back Tap works from any screen without looking. Lock Screen and Control Center are one tap away. Siri needs no setup at all.")
                if selectedMethod == .backTap {
                    Text("Back Tap needs the one-tap Shortcuts step because Apple only lists personal shortcuts there. If a double-tap is ever missed, tap slightly firmer with a fingertip near the middle of the back.")
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
        finishOrDismiss()
    }

    private func finishOrDismiss() {
        onFinished?()
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
        setupStep(number, title: title, detail: detail, showsConnector: showsConnector) {
            EmptyView()
        }
    }

    /// Everything belonging to a step — including its button — is rendered
    /// inside the step's own column, so a control can never look like it
    /// belongs to the step above it.
    private func setupStep<Content: View>(
        _ number: Int,
        title: String,
        detail: String,
        showsConnector: Bool = true,
        @ViewBuilder content: () -> Content
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
                        .frame(width: 1)
                        .frame(minHeight: 12, maxHeight: .infinity)
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

                content()
                    .padding(.top, 8)
            }
            .padding(.bottom, showsConnector ? 16 : 0)
        }
    }
}

// MARK: - Illustrations

/// A pulsing double-ring that marks exactly where to tap in an illustration.
private struct TapMarker: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulsing = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.speakInk.opacity(0.35), lineWidth: 1.5)
                .frame(width: 34, height: 34)
                .scaleEffect(pulsing ? 1.35 : 1)
                .opacity(pulsing ? 0 : 1)
            Circle()
                .stroke(Color.speakInk.opacity(0.6), lineWidth: 1.5)
                .frame(width: 22, height: 22)
            Circle()
                .fill(Color.speakInk)
                .frame(width: 10, height: 10)
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) {
                pulsing = true
            }
        }
    }
}

/// The back of an iPhone with the double-tap spot marked. Shown instead of a
/// photo so it adapts to dark mode and Dynamic Type–adjacent scaling.
private struct BackTapIllustration: View {
    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.speakInk.opacity(0.05))
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.speakDivider, lineWidth: 1.5)

                // Camera cluster marks this as the BACK of the phone.
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.speakInk.opacity(0.08))
                    .frame(width: 42, height: 42)
                    .overlay {
                        VStack(spacing: 5) {
                            Circle().stroke(Color.speakInk.opacity(0.4), lineWidth: 2).frame(width: 12, height: 12)
                            Circle().stroke(Color.speakInk.opacity(0.4), lineWidth: 2).frame(width: 12, height: 12)
                        }
                    }
                    .offset(x: -34, y: -56)

                TapMarker()
                    .offset(y: 14)

                Text("×2")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.speakInk)
                    .offset(x: 30, y: 40)
            }
            .frame(width: 122, height: 172)

            Text("Two quick taps on the back — case on is fine")
                .font(.caption)
                .foregroundStyle(Color.speakMuted)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Illustration: double-tap the middle of the back of your iPhone")
    }
}

/// The side of an iPhone with the Action Button highlighted.
private struct ActionButtonIllustration: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHolding = false

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.speakInk.opacity(0.05))
                    .frame(width: 122, height: 172)
                    .offset(x: 18)
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.speakDivider, lineWidth: 1.5)
                    .frame(width: 122, height: 172)
                    .offset(x: 18)

                // The two longer controls establish the volume-button side of
                // the phone. They stay still while the small Action Button
                // above them visibly presses inward.
                Capsule()
                    .fill(Color.speakMuted.opacity(0.55))
                    .frame(width: 4, height: 28)
                    .offset(x: -42, y: 5)
                Capsule()
                    .fill(Color.speakMuted.opacity(0.55))
                    .frame(width: 4, height: 36)
                    .offset(x: -42, y: 48)

                // Resting just outside the case, then moving flush with the
                // side, matches the real press direction. The marker shares
                // the exact center so it never floats below or over the label.
                Capsule()
                    .fill(Color.speakInk)
                    .frame(width: 6, height: 30)
                    .offset(x: isHolding ? -41 : -46, y: -52)

                Circle()
                    .stroke(Color.speakInk.opacity(0.5), lineWidth: 1.5)
                    .frame(width: 34, height: 34)
                    .scaleEffect(isHolding ? 0.72 : 1)
                    .opacity(isHolding ? 0.2 : 0.72)
                    .offset(x: isHolding ? -41 : -46, y: -52)
            }
            .frame(width: 220, height: 172)
            .onAppear {
                guard !reduceMotion else {
                    isHolding = true
                    return
                }
                withAnimation(.easeInOut(duration: 0.85).repeatForever(autoreverses: true)) {
                    isHolding = true
                }
            }

            Text("Press and hold the small button above the volume keys")
                .font(.caption)
                .foregroundStyle(Color.speakMuted)
                .multilineTextAlignment(.center)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Illustration: press and hold the Action Button on the upper-left edge of your iPhone")
    }
}

/// A miniature Lock Screen with the widget slot under the clock highlighted.
private struct LockScreenIllustration: View {
    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.speakInk.opacity(0.05))
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.speakDivider, lineWidth: 1.5)

                VStack(spacing: 8) {
                    Text("9:41")
                        .font(.system(size: 34, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.speakInk.opacity(0.7))

                    HStack(spacing: 6) {
                        widgetSlot(highlighted: true)
                        widgetSlot(highlighted: false)
                        widgetSlot(highlighted: false)
                    }

                    Spacer()
                }
                .padding(.top, 26)

                TapMarker()
                    .offset(x: -32, y: -10)
            }
            .frame(width: 122, height: 172)

            Text("Your widget lives right under the clock")
                .font(.caption)
                .foregroundStyle(Color.speakMuted)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Illustration: the Speak It widget sits in the row under the Lock Screen clock")
    }

    private func widgetSlot(highlighted: Bool) -> some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(highlighted ? Color.speakInk.opacity(0.16) : Color.speakInk.opacity(0.06))
            .frame(width: 26, height: 26)
            .overlay {
                if highlighted {
                    Image(systemName: "waveform")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.speakInk)
                }
            }
    }
}

/// A miniature Control Center grid with the Speak It control highlighted.
private struct ControlCenterIllustration: View {
    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.speakInk.opacity(0.05))
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.speakDivider, lineWidth: 1.5)

                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        tile(highlighted: false)
                        tile(highlighted: false)
                    }
                    HStack(spacing: 8) {
                        tile(highlighted: true)
                        tile(highlighted: false)
                    }
                }

                TapMarker()
                    .offset(x: -22, y: 22)
            }
            .frame(width: 122, height: 172)

            Text("Swipe down from the top-right, then tap the waveform")
                .font(.caption)
                .foregroundStyle(Color.speakMuted)
                .multilineTextAlignment(.center)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Illustration: the Speak It control in the Control Center grid")
    }

    private func tile(highlighted: Bool) -> some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(highlighted ? Color.speakInk.opacity(0.16) : Color.speakInk.opacity(0.06))
            .frame(width: 40, height: 40)
            .overlay {
                if highlighted {
                    Image(systemName: "waveform")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.speakInk)
                }
            }
    }
}

/// A miniature Home Screen with the wide Speak It Capture widget highlighted.
private struct HomeScreenIllustration: View {
    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.speakInk.opacity(0.05))
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.speakDivider, lineWidth: 1.5)

                VStack(spacing: 10) {
                    HStack(spacing: 10) {
                        ForEach(0..<4, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(Color.speakInk.opacity(0.06))
                                .frame(width: 17, height: 17)
                        }
                    }

                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.speakInk.opacity(0.14))
                        .frame(width: 98, height: 44)
                        .overlay {
                            HStack(spacing: 6) {
                                Image(systemName: "waveform")
                                    .font(.system(size: 13, weight: .semibold))
                                Text("Speak It")
                                    .font(.system(size: 11, weight: .semibold))
                            }
                            .foregroundStyle(Color.speakInk)
                        }

                    HStack(spacing: 10) {
                        ForEach(0..<4, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(Color.speakInk.opacity(0.06))
                                .frame(width: 17, height: 17)
                        }
                    }
                }

                TapMarker()
                    .offset(x: 34, y: 0)
            }
            .frame(width: 122, height: 172)

            Text("One big button next to your apps")
                .font(.caption)
                .foregroundStyle(Color.speakMuted)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Illustration: the Speak It Capture widget among your Home Screen apps")
    }
}

/// Siri phrase illustration — a spoken phrase, nothing to configure.
private struct SiriIllustration: View {
    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.speakInk.opacity(0.05))
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.speakDivider, lineWidth: 1.5)

                VStack(spacing: 14) {
                    Image(systemName: "waveform")
                        .font(.system(size: 26, weight: .medium))
                        .foregroundStyle(Color.speakInk.opacity(0.7))

                    Text("“Capture with\nSpeak It”")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.speakInk)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(width: 122, height: 172)

            Text("Works hands-free, even with AirPods")
                .font(.caption)
                .foregroundStyle(Color.speakMuted)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Illustration: say Capture with Speak It to Siri")
    }
}

// MARK: - Guided sequences

/// One row inside a mocked iOS screen.
private struct SetupMockRow: Identifiable {
    enum Style { case plain, dim, header, highlighted }

    var id: String { title }
    let title: String
    let style: Style
    var symbol: String?
    var showsCheck = false

    static func plain(_ title: String, symbol: String? = nil) -> SetupMockRow {
        SetupMockRow(title: title, style: .plain, symbol: symbol)
    }

    static func dim(_ title: String, symbol: String? = nil) -> SetupMockRow {
        SetupMockRow(title: title, style: .dim, symbol: symbol)
    }

    static func header(_ title: String) -> SetupMockRow {
        SetupMockRow(title: title, style: .header)
    }

    static func highlighted(
        _ title: String,
        symbol: String? = nil,
        showsCheck: Bool = false
    ) -> SetupMockRow {
        SetupMockRow(title: title, style: .highlighted, symbol: symbol, showsCheck: showsCheck)
    }
}

/// One frame of a guided sequence: a small drawing of the iOS screen the
/// person is looking at, with the single thing to touch marked.
private struct SetupMockScreen: Identifiable {
    var id: String { caption }
    let caption: String
    var badge = "TAP"
    var backTitle: String?
    var highlightsBack = false
    var navTitle: String?
    var trailingTitle: String?
    var highlightsTrailing = false
    var rows: [SetupMockRow] = []
    /// Draws a scrollbar pinned to the bottom, so "this is far down a long
    /// list" is visible rather than only described.
    var showsScrollHint = false
    var hidesChevrons = false
    /// The row of round App Shortcut tiles Shortcuts shows on an app's page.
    var tiles: [SetupMockTile] = []
    /// The context menu that appears when a tile is held, drawn overlapping
    /// the tile bar the way iOS presents it.
    var menu: [SetupMockRow] = []
}

private struct SetupMockTile: Identifiable {
    var id: String { title }
    let title: String
    let symbol: String
    var highlighted = false
}

private struct SetupMockScreenView: View {
    let screen: SetupMockScreen

    var body: some View {
        VStack(spacing: 0) {
            if screen.backTitle != nil || screen.navTitle != nil || screen.trailingTitle != nil {
                navBar
                Divider().overlay(Color.speakDivider)
            }

            if !screen.tiles.isEmpty {
                tileSection
            } else {
                ForEach(Array(screen.rows.enumerated()), id: \.element.id) { index, row in
                    rowView(row)

                    if index < screen.rows.count - 1 {
                        Divider().overlay(Color.speakDivider).padding(.leading, 12)
                    }
                }
            }
        }
        .background(Color.speakInk.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.speakDivider, lineWidth: 1)
        }
        .overlay(alignment: .trailing) {
            if screen.showsScrollHint {
                scrollHint
            }
        }
    }

    private var navBar: some View {
        HStack(spacing: 6) {
            if let backTitle = screen.backTitle {
                HStack(spacing: 1) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 10, weight: .bold))
                    Text(backTitle)
                        .font(.footnote.weight(screen.highlightsBack ? .semibold : .regular))
                        .lineLimit(1)
                }
                .foregroundStyle(screen.highlightsBack ? Color.speakInk : Color.speakMuted)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(
                    screen.highlightsBack ? Color.speakInk.opacity(0.10) : Color.clear,
                    in: Capsule()
                )

                if screen.highlightsBack {
                    badgePill
                }
            }

            Spacer(minLength: 4)

            if let navTitle = screen.navTitle {
                Text(navTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.speakInk)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            if let trailingTitle = screen.trailingTitle {
                if screen.highlightsTrailing {
                    badgePill
                }

                Text(trailingTitle)
                    .font(.footnote.weight(screen.highlightsTrailing ? .semibold : .regular))
                    .foregroundStyle(screen.highlightsTrailing ? Color.speakInk : Color.speakMuted)
                    .lineLimit(1)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        screen.highlightsTrailing ? Color.speakInk.opacity(0.10) : Color.clear,
                        in: Capsule()
                    )
            }
        }
        .padding(.horizontal, 10)
        .frame(minHeight: 32)
    }

    @ViewBuilder
    private func rowView(_ row: SetupMockRow) -> some View {
        if row.style == .header {
            HStack {
                Text(row.title)
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(Color.speakMuted.opacity(0.8))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 4)
        } else {
            HStack(spacing: 8) {
                if let symbol = row.symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 16)
                        .foregroundStyle(color(for: row.style))
                }

                Text(row.title)
                    .font(.footnote.weight(row.style == .highlighted ? .semibold : .regular))
                    .foregroundStyle(color(for: row.style))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                Spacer(minLength: 6)

                if row.style == .highlighted {
                    badgePill
                    Image(systemName: row.showsCheck ? "checkmark" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.speakInk)
                } else if !screen.hidesChevrons {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.speakMuted.opacity(0.45))
                }
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 34)
            .background(row.style == .highlighted ? Color.speakInk.opacity(0.09) : Color.clear)
        }
    }

    /// The Shortcuts tile bar, with the held tile marked and — on the frame
    /// after the hold — the context menu overlapping it, as iOS draws it.
    private var tileSection: some View {
        VStack(alignment: .leading, spacing: -10) {
            HStack(alignment: .top, spacing: 10) {
                ForEach(screen.tiles) { tile in
                    VStack(spacing: 6) {
                        ZStack {
                            Circle()
                                .fill(Color.speakInk.opacity(tile.highlighted ? 0.14 : 0.06))
                                .frame(width: 38, height: 38)

                            Image(systemName: tile.symbol)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(tile.highlighted ? Color.speakInk : Color.speakMuted)

                            if tile.highlighted {
                                Circle()
                                    .stroke(Color.speakInk.opacity(0.55), lineWidth: 1.5)
                                    .frame(width: 48, height: 48)
                            }
                        }
                        .frame(width: 48, height: 48)

                        Text(tile.title)
                            .font(.system(size: 9, weight: tile.highlighted ? .semibold : .regular))
                            .foregroundStyle(tile.highlighted ? Color.speakInk : Color.speakMuted)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)

                        if tile.highlighted, screen.menu.isEmpty {
                            badgePill
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity)

            if !screen.menu.isEmpty {
                menuCard
                    .padding(.leading, 26)
                    .padding(.bottom, 10)
            }
        }
    }

    private var menuCard: some View {
        VStack(spacing: 0) {
            ForEach(Array(screen.menu.enumerated()), id: \.element.id) { index, row in
                HStack(spacing: 10) {
                    Image(systemName: row.symbol ?? "circle")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 16)

                    Text(row.title)
                        .font(.footnote.weight(row.style == .highlighted ? .semibold : .regular))
                        .lineLimit(1)

                    Spacer(minLength: 8)

                    if row.style == .highlighted {
                        badgePill
                    }
                }
                .foregroundStyle(row.style == .highlighted ? Color.speakInk : Color.speakMuted)
                .padding(.horizontal, 12)
                .frame(minHeight: 34)
                .background(row.style == .highlighted ? Color.speakInk.opacity(0.10) : Color.clear)

                if index < screen.menu.count - 1 {
                    Divider().overlay(Color.speakDivider).padding(.leading, 12)
                }
            }
        }
        .frame(maxWidth: 230, alignment: .leading)
        .background(Color.speakSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.speakDivider, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.14), radius: 7, y: 3)
    }

    private var badgePill: some View {
        Text(screen.badge)
            .font(.system(size: 8, weight: .bold))
            .tracking(0.6)
            .foregroundStyle(Color.speakInverseInk)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color.speakInverseSurface, in: Capsule())
    }

    private var scrollHint: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            Capsule()
                .fill(Color.speakMuted.opacity(0.45))
                .frame(width: 3, height: 26)
        }
        .padding(.vertical, 8)
        .padding(.trailing, 3)
    }

    private func color(for style: SetupMockRow.Style) -> Color {
        switch style {
        case .highlighted: Color.speakInk
        case .plain: Color.speakInk.opacity(0.75)
        case .dim, .header: Color.speakMuted.opacity(0.75)
        }
    }
}

/// Plays a short sequence of mocked screens on a loop, so the navigation
/// between them is shown rather than described. Reduce Motion turns the same
/// frames into a static, numbered stack.
private struct GuidedSequenceView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    let screens: [SetupMockScreen]

    @State private var index = 0
    /// Stops the loop for good once the person swipes: they have taken over,
    /// and a page moving under their thumb is the fastest way to lose them.
    @State private var advancesOnItsOwn = true
    @State private var lastAutoAdvancedTo = 0

    private var safeIndex: Int { min(index, max(screens.count - 1, 0)) }

    private var spokenSummary: String {
        screens.enumerated()
            .map { "Step \($0.offset + 1): \($0.element.caption)" }
            .joined(separator: ". ")
    }

    var body: some View {
        Group {
            if reduceMotion || screens.count == 1 {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(Array(screens.enumerated()), id: \.element.id) { position, screen in
                        frame(screen, position: position)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ZStack(alignment: .top) {
                        // An invisible stack of every frame fixes the slot to
                        // the tallest one, so paging never shifts the page.
                        ZStack(alignment: .top) {
                            ForEach(Array(screens.enumerated()), id: \.element.id) { _, screen in
                                SetupMockScreenView(screen: screen)
                            }
                        }
                        .hidden()

                        TabView(selection: $index) {
                            ForEach(Array(screens.enumerated()), id: \.element.id) { position, screen in
                                SetupMockScreenView(screen: screen)
                                    .frame(maxHeight: .infinity, alignment: .top)
                                    .tag(position)
                            }
                        }
                        .tabViewStyle(.page(indexDisplayMode: .never))
                    }

                    caption(for: screens[safeIndex], position: safeIndex)

                    dots
                }
                .onReceive(
                    Timer.publish(every: 2.6, on: .main, in: .common).autoconnect()
                ) { _ in
                    // Holds still while the person is off in Settings doing the
                    // step, so they come back to the frame they left.
                    guard advancesOnItsOwn, scenePhase == .active else { return }

                    let next = (safeIndex + 1) % screens.count
                    lastAutoAdvancedTo = next
                    withAnimation(.easeInOut(duration: 0.35)) {
                        index = next
                    }
                }
                .onChange(of: index) { _, newValue in
                    if newValue != lastAutoAdvancedTo {
                        advancesOnItsOwn = false
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenSummary)
    }

    private func frame(_ screen: SetupMockScreen, position: Int) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            SetupMockScreenView(screen: screen)
            caption(for: screen, position: position)
        }
    }

    private func caption(for screen: SetupMockScreen, position: Int) -> some View {
        HStack(alignment: .top, spacing: 7) {
            Text("\(position + 1)")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Color.speakInverseInk)
                .frame(width: 16, height: 16)
                .background(Color.speakInverseSurface, in: Circle())

            Text(screen.caption)
                .font(.caption)
                .foregroundStyle(Color.speakMuted)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        // Absorbs one- versus two-line captions so the loop stays still.
        .frame(minHeight: 32, alignment: .top)
    }

    private var dots: some View {
        HStack(spacing: 5) {
            ForEach(0..<screens.count, id: \.self) { position in
                Button {
                    advancesOnItsOwn = false
                    withAnimation(.easeInOut(duration: 0.25)) {
                        index = position
                    }
                } label: {
                    Capsule()
                        .fill(position == safeIndex ? Color.speakInk : Color.speakDivider)
                        .frame(width: position == safeIndex ? 14 : 5, height: 5)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 4)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.speakIt)
            }
        }
        .padding(.vertical, -10)
    }
}

/// The mocked screens behind each method's guided steps.
private enum SetupSequences {
    private static let shortcutsTiles: [SetupMockTile] = [
        SetupMockTile(title: "Speak It\nCapture", symbol: "waveform", highlighted: true),
        SetupMockTile(title: "Dictate a\nThought", symbol: "quote.bubble"),
        SetupMockTile(title: "Complete\nNext", symbol: "checkmark.circle")
    ]

    static let addShortcut: [SetupMockScreen] = [
        SetupMockScreen(
            caption: "Touch and hold the Speak It Capture tile",
            badge: "HOLD",
            navTitle: "Speak It",
            tiles: shortcutsTiles
        ),
        SetupMockScreen(
            caption: "Tap New Shortcut — it saves as “Capture with Speak It”",
            navTitle: "Speak It",
            tiles: shortcutsTiles,
            menu: [
                .plain("Add to Home Screen", symbol: "plus.app"),
                .highlighted("New Shortcut", symbol: "square.stack.3d.up")
            ]
        )
    ]

    /// Used when the app can deep-link into Touch settings: the person lands
    /// one screen deep and has to come back up first.
    static let backTapFromDeepLink: [SetupMockScreen] = [
        SetupMockScreen(
            caption: "You land here — tap ‹ Touch to go back",
            backTitle: "Touch",
            highlightsBack: true,
            navTitle: "AssistiveTouch",
            rows: [
                .dim("AssistiveTouch"),
                .dim("Customize Top Level Menu"),
                .dim("Idle Opacity")
            ]
        ),
        SetupMockScreen(
            caption: "Scroll to the bottom, tap Back Tap",
            navTitle: "Touch",
            rows: [
                .dim("Haptic Touch"),
                .dim("Tap to Wake"),
                .highlighted("Back Tap")
            ],
            showsScrollHint: true
        ),
        SetupMockScreen(
            caption: "Tap Double Tap",
            navTitle: "Back Tap",
            rows: [
                .highlighted("Double Tap"),
                .plain("Triple Tap")
            ]
        )
    ]

    /// Used before iOS 26, where the person walks in from Settings themselves.
    static let backTapFromSettings: [SetupMockScreen] = [
        SetupMockScreen(
            caption: "Settings → Accessibility",
            navTitle: "Settings",
            rows: [
                .dim("General", symbol: "gear"),
                .highlighted("Accessibility", symbol: "accessibility"),
                .dim("Control Center", symbol: "switch.2")
            ]
        ),
        SetupMockScreen(
            caption: "Tap Touch",
            navTitle: "Accessibility",
            rows: [
                .dim("Display & Text Size"),
                .dim("Motion"),
                .highlighted("Touch")
            ]
        ),
        SetupMockScreen(
            caption: "Scroll to the bottom, tap Back Tap",
            navTitle: "Touch",
            rows: [
                .dim("Haptic Touch"),
                .dim("Tap to Wake"),
                .highlighted("Back Tap")
            ],
            showsScrollHint: true
        ),
        SetupMockScreen(
            caption: "Tap Double Tap",
            navTitle: "Back Tap",
            rows: [
                .highlighted("Double Tap"),
                .plain("Triple Tap")
            ]
        )
    ]

    static let pickSpeakItCapture: [SetupMockScreen] = [
        SetupMockScreen(
            caption: "Keep scrolling past the system actions",
            navTitle: "Double Tap",
            rows: [
                .dim("None"),
                .dim("Screenshot"),
                .dim("Magnifier")
            ]
        ),
        SetupMockScreen(
            caption: "At the very bottom, under SHORTCUTS",
            navTitle: "Double Tap",
            rows: [
                .dim("Spotlight"),
                .dim("Voice Control"),
                .header("SHORTCUTS"),
                .highlighted("Capture with Speak It", showsCheck: true)
            ],
            showsScrollHint: true
        )
    ]

    static let actionButton: [SetupMockScreen] = [
        SetupMockScreen(
            caption: "Open Settings, tap Action Button",
            navTitle: "Settings",
            rows: [
                .dim("General", symbol: "gear"),
                .highlighted("Action Button", symbol: "button.programmable"),
                .dim("Camera", symbol: "camera")
            ]
        ),
        SetupMockScreen(
            caption: "Swipe sideways until it says Shortcut",
            badge: "SWIPE",
            navTitle: "Action Button",
            rows: [
                .dim("Silent Mode"),
                .dim("Camera"),
                .highlighted("Shortcut")
            ]
        ),
        SetupMockScreen(
            caption: "Choose Speak It Capture",
            navTitle: "Choose a Shortcut",
            rows: [
                .dim("Open Camera"),
                .highlighted("Speak It Capture", symbol: "waveform", showsCheck: true)
            ],
            showsScrollHint: true
        )
    ]
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
