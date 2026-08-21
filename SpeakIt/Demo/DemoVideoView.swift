#if DEBUG
import SwiftUI

@MainActor
struct DemoVideoRoot: View {
    private let preview: PreviewEnvironment
    @StateObject private var subscriptionStore = SubscriptionStore()

    init() {
        preview = PreviewData.make()
    }

    var body: some View {
        DemoVideoView()
            .modelContainer(preview.container)
            .environment(\.thoughtRepository, preview.repository)
            .environmentObject(subscriptionStore)
    }
}

private struct DemoVideoView: View {
    fileprivate enum Chapter: Int, CaseIterable {
        case intro
        case welcome
        case voice
        case remembered
        case today
        case library
        case typing
        case anywhere
        case fallback
        case setup
        case outro

        var duration: Duration {
            switch self {
            case .intro: .seconds(6)
            case .welcome: .seconds(6)
            case .voice: .seconds(8)
            case .remembered: .seconds(3)
            case .today: .seconds(7)
            case .library: .seconds(8)
            case .typing: .seconds(7)
            case .anywhere: .seconds(9)
            case .fallback: .seconds(7)
            case .setup: .seconds(9)
            case .outro: .seconds(8)
            }
        }

    }

    @State private var chapter: Chapter = .intro

    init() {
        let startsAtAnywhere = ProcessInfo.processInfo.arguments.contains("--demo-start-anywhere")
        _chapter = State(initialValue: startsAtAnywhere ? .anywhere : .intro)
    }

    var body: some View {
        ZStack {
            scene
                .id(chapter)
                .transition(.opacity.combined(with: .scale(scale: 0.992)))

        }
        .ignoresSafeArea(edges: chapter == .intro || chapter == .outro ? .all : [])
        .preferredColorScheme(chapter.prefersDark ? .dark : .light)
        .task {
            let chapters = Chapter.allCases
            let startIndex = chapters.firstIndex(of: chapter) ?? chapters.startIndex
            for index in chapters.indices.dropLast() where index >= startIndex {
                guard !Task.isCancelled else { return }
                try? await Task.sleep(for: chapters[index].duration)
                guard !Task.isCancelled else { return }
                withAnimation(.easeInOut(duration: 0.55)) {
                    chapter = chapters[index + 1]
                }
            }
        }
    }

    @ViewBuilder
    private var scene: some View {
        switch chapter {
        case .intro:
            DemoTitleCard()
        case .welcome:
            WelcomeView(onFirstCapture: {}, onSkip: {}, onLoadExamples: {})
        case .voice:
            DemoVoiceCaptureView()
        case .remembered:
            DemoRememberedView()
        case .today:
            DemoAppScreen(selected: .today) {
                NavigationStack {
                    TodayView(onCapture: {})
                }
            }
        case .library:
            DemoAppScreen(selected: .library) {
                NavigationStack {
                    LibraryView(onCapture: {})
                }
            }
        case .typing:
            DemoTypingView()
        case .anywhere:
            DemoAnywhereView()
        case .fallback:
            DemoFallbackView()
        case .setup:
            CaptureAnywhereSetupView()
                .disabled(true)
        case .outro:
            DemoOutroView()
        }
    }
}

private extension DemoVideoView.Chapter {
    var prefersDark: Bool {
        switch self {
        case .intro, .welcome, .voice, .remembered, .anywhere, .outro:
            true
        case .today, .library, .typing, .fallback, .setup:
            false
        }
    }
}

private struct DemoTitleCard: View {
    @State private var appeared = false

    var body: some View {
        ZStack {
            Color.black

            VStack(spacing: 34) {
                DemoPulseMark(size: 170, showsCheck: false)
                    .scaleEffect(appeared ? 1 : 0.78)
                    .opacity(appeared ? 1 : 0)

                VStack(spacing: 12) {
                    Text("Speak It")
                        .font(.system(size: 42, weight: .semibold))
                        .tracking(-0.6)
                    Text("Say it. Save it. Let it go.")
                        .font(.title3)
                        .foregroundStyle(.white.opacity(0.58))
                }
                .offset(y: appeared ? 0 : 18)
                .opacity(appeared ? 1 : 0)
            }
            .foregroundStyle(.white)
        }
        .onAppear {
            withAnimation(.spring(response: 0.9, dampingFraction: 0.82)) {
                appeared = true
            }
        }
    }
}

private struct DemoVoiceCaptureView: View {
    private let transcript = "Remind me to send Maya the launch notes tomorrow morning."

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0)) { timeline in
            let elapsed = timeline.date.timeIntervalSinceReferenceDate
            let level = CGFloat((sin(elapsed * 6.8) + sin(elapsed * 3.7) + 2) / 4)

            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 0) {
                    HStack {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .medium))
                            .frame(width: 38, height: 38)
                            .background(.white.opacity(0.08), in: Circle())
                        Spacer()
                        Text("Speak It")
                            .font(.caption.weight(.semibold))
                            .tracking(-0.1)
                            .foregroundStyle(.white.opacity(0.58))
                        Spacer()
                        Color.clear.frame(width: 38, height: 38)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)

                    Spacer()

                    ListeningOrb(phase: .listening, level: level)

                    VStack(spacing: 8) {
                        Text("Listening")
                            .font(.title2.weight(.semibold))
                        Text("Just speak. I’ll save after a natural pause.")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.58))
                    }

                    Text(transcript)
                        .font(.title3)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white.opacity(0.84))
                        .frame(maxWidth: 330)
                        .padding(.top, 30)

                    Spacer()

                    Label("Type instead", systemImage: "keyboard")
                        .font(.subheadline.weight(.medium))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 11)
                        .background(.white.opacity(0.08), in: Capsule())
                        .padding(.bottom, 34)
                }
                .foregroundStyle(.white)
            }
        }
    }
}

private struct DemoRememberedView: View {
    @State private var appeared = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 22) {
                DemoPulseMark(size: 164, showsCheck: true)
                    .scaleEffect(appeared ? 1 : 0.76)
                    .opacity(appeared ? 1 : 0)
                Text("Remembered")
                    .font(.largeTitle.weight(.semibold))
                Text("You can let it go now.")
                    .foregroundStyle(.white.opacity(0.58))
            }
            .foregroundStyle(.white)
        }
        .onAppear {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.72)) {
                appeared = true
            }
        }
    }
}

private enum DemoDestination {
    case today
    case library
}

private struct DemoAppScreen<Content: View>: View {
    let selected: DemoDestination
    @ViewBuilder let content: () -> Content

    var body: some View {
        ZStack(alignment: .bottom) {
            content()
                .safeAreaInset(edge: .bottom) {
                    Color.clear.frame(height: 86)
                }

            HStack(spacing: 8) {
                dockLabel("Today", isSelected: selected == .today)

                ZStack {
                    Circle()
                        .fill(Color.speakInverseSurface)
                        .frame(width: 58, height: 58)
                        .shadow(color: .black.opacity(0.14), radius: 14, y: 8)
                    Image(systemName: "waveform")
                        .font(.system(size: 21, weight: .medium))
                        .foregroundStyle(Color.speakInverseInk)
                }
                .frame(maxWidth: .infinity)

                dockLabel("Memory", isSelected: selected == .library)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.speakSurface, in: RoundedRectangle(cornerRadius: 25))
            .overlay {
                RoundedRectangle(cornerRadius: 25)
                    .stroke(Color.speakDivider, lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.09), radius: 22, y: 10)
            .padding(.horizontal, 22)
            .padding(.bottom, 8)
        }
    }

    private func dockLabel(_ title: String, isSelected: Bool) -> some View {
        Text(title)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(isSelected ? Color.speakInk : Color.speakMuted)
            .frame(maxWidth: .infinity, minHeight: 44)
    }
}

private struct DemoTypingView: View {
    private let thought = "Book the studio for Friday’s product shoot"
    @State private var characterCount = 0
    @State private var saved = false

    var body: some View {
        ZStack {
            Color.speakBackground.ignoresSafeArea()

            if saved {
                VStack(spacing: 20) {
                    DemoPulseMark(size: 150, showsCheck: true, darkOnLight: true)
                    Text("Remembered")
                        .font(.largeTitle.weight(.semibold))
                    Text("Automatically organized in Work.")
                        .foregroundStyle(Color.speakMuted)
                }
                .transition(.scale(scale: 0.88).combined(with: .opacity))
            } else {
                VStack(alignment: .leading, spacing: 22) {
                    Spacer(minLength: 50)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("What’s on your mind?")
                            .font(.largeTitle.weight(.semibold))
                        Text("Write naturally. Speak It organizes it later.")
                            .foregroundStyle(Color.speakMuted)
                    }

                    Text(String(thought.prefix(characterCount)))
                        .font(.title3)
                        .frame(maxWidth: .infinity, minHeight: 210, alignment: .topLeading)
                        .padding(18)
                        .background(Color.speakSurface, in: RoundedRectangle(cornerRadius: 24))
                        .overlay {
                            RoundedRectangle(cornerRadius: 24)
                                .stroke(Color.speakDivider, lineWidth: 1)
                        }

                    Text("Save thought")
                        .font(.headline)
                        .foregroundStyle(Color.speakInverseInk)
                        .frame(maxWidth: .infinity, minHeight: 54)
                        .background(Color.speakInverseSurface, in: RoundedRectangle(cornerRadius: 18))

                    Label("Speak instead", systemImage: "waveform")
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity)

                    Spacer()
                }
                .padding(.horizontal, 22)
                .transition(.opacity)
            }
        }
        .task {
            for count in 0...thought.count {
                characterCount = count
                try? await Task.sleep(for: .milliseconds(48))
            }
            try? await Task.sleep(for: .seconds(1.4))
            withAnimation(.spring(response: 0.5, dampingFraction: 0.76)) {
                saved = true
            }
        }
    }
}

private struct DemoAnywhereView: View {
    private enum CaptureState {
        case ready
        case listening
        case remembered
    }

    @State private var state: CaptureState = .ready
    @State private var tapPulse = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 34) {
                Spacer()

                ZStack {
                    RoundedRectangle(cornerRadius: 58, style: .continuous)
                        .stroke(.white.opacity(0.18), lineWidth: 1)
                        .frame(width: 210, height: 390)

                    VStack(spacing: 22) {
                        Image(systemName: "hand.tap")
                            .font(.system(size: 42, weight: .light))
                            .scaleEffect(tapPulse ? 1.15 : 0.94)
                            .opacity(state == .ready ? 1 : 0.32)

                        DemoPulseMark(
                            size: 118,
                            showsCheck: state == .remembered
                        )
                        .scaleEffect(state == .listening ? 1.08 : 0.94)

                        Image(systemName: state == .listening ? "waveform" : "iphone.radiowaves.left.and.right")
                            .font(.title2)
                            .foregroundStyle(.white.opacity(0.58))
                    }
                }

                VStack(spacing: 9) {
                    Text(title)
                        .font(.largeTitle.weight(.semibold))
                        .multilineTextAlignment(.center)
                    Text(subtitle)
                        .font(.body)
                        .foregroundStyle(.white.opacity(0.58))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 330)
                }

                Text("No app hunting. No lost thought.")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.42))

                Spacer()
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 24)
        }
        .task {
            await CaptureActivityManager.beginListening()

            withAnimation(.easeInOut(duration: 0.55).repeatCount(3, autoreverses: true)) {
                tapPulse = true
            }
            try? await Task.sleep(for: .seconds(1.6))
            withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                state = .listening
            }

            try? await Task.sleep(for: .seconds(3.1))
            withAnimation(.spring(response: 0.45, dampingFraction: 0.72)) {
                state = .remembered
            }
            await CaptureActivityManager.showRemembered("Buy flowers for Mom on the way home")
        }
    }

    private var title: String {
        switch state {
        case .ready: "Double tap."
        case .listening: "Speak naturally."
        case .remembered: "Remembered."
        }
    }

    private var subtitle: String {
        switch state {
        case .ready: "The back of your iPhone becomes a capture button."
        case .listening: "“Buy flowers for Mom on the way home.”"
        case .remembered: "Saved locally and organized automatically."
        }
    }
}

private struct DemoFallbackView: View {
    @State private var appeared = false

    var body: some View {
        ZStack {
            Color.speakBackground.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 9) {
                    Text("NO DYNAMIC ISLAND?")
                        .font(.caption.weight(.medium))
                        .tracking(1.6)
                        .foregroundStyle(Color.speakMuted)
                    Text("Nothing gets left behind.")
                        .font(.largeTitle.weight(.semibold))
                    Text("iOS automatically moves the same live capture state to the Lock Screen and an unlocked confirmation banner.")
                        .foregroundStyle(Color.speakMuted)
                }

                VStack(spacing: 16) {
                    HStack(spacing: 16) {
                        DemoPulseMark(size: 54, showsCheck: true)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Speak It")
                                .font(.caption2.weight(.semibold))
                                .tracking(-0.1)
                                .foregroundStyle(.white.opacity(0.48))
                            Text("Remembered")
                                .font(.headline)
                            Text("Buy flowers for Mom on the way home")
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.64))
                                .lineLimit(2)
                        }

                        Spacer()

                        Image(systemName: "checkmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.black)
                            .frame(width: 36, height: 36)
                            .background(.white, in: Circle())
                    }
                    .foregroundStyle(.white)
                    .padding(18)
                    .background(.black, in: RoundedRectangle(cornerRadius: 24))

                    HStack(spacing: 12) {
                        Image(systemName: "bell.badge")
                            .frame(width: 34, height: 34)
                            .background(Color.speakSurface, in: Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Confirmation banner")
                                .font(.subheadline.weight(.semibold))
                            Text("Visible while the phone is unlocked")
                                .font(.footnote)
                                .foregroundStyle(Color.speakMuted)
                        }
                        Spacer()
                    }
                    .padding(16)
                    .background(Color.speakSurface, in: RoundedRectangle(cornerRadius: 20))
                    .overlay {
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(Color.speakDivider, lineWidth: 1)
                    }
                }
                .scaleEffect(appeared ? 1 : 0.92)
                .opacity(appeared ? 1 : 0)

                Spacer()

                Label("One design. Every supported iPhone.", systemImage: "iphone.gen3")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 54)
                    .foregroundStyle(Color.speakInverseInk)
                    .background(Color.speakInverseSurface, in: RoundedRectangle(cornerRadius: 18))
            }
            .padding(.horizontal, 22)
            .padding(.top, 76)
            .padding(.bottom, 28)
        }
        .onAppear {
            withAnimation(.spring(response: 0.7, dampingFraction: 0.82)) {
                appeared = true
            }
        }
    }
}

private struct DemoOutroView: View {
    @State private var appeared = false

    var body: some View {
        ZStack {
            Color.black

            VStack(spacing: 34) {
                DemoPulseMark(size: 148, showsCheck: true)

                VStack(spacing: 12) {
                    Text("A thought should take\nseconds to save.")
                        .font(.system(size: 38, weight: .semibold))
                        .multilineTextAlignment(.center)
                    Text("Speak It")
                        .font(.title3.weight(.medium))
                        .tracking(1.4)
                        .foregroundStyle(.white.opacity(0.58))
                }

                HStack(spacing: 8) {
                    featurePill("Voice")
                    featurePill("Double Tap")
                    featurePill("Private")
                }
            }
            .foregroundStyle(.white)
            .scaleEffect(appeared ? 1 : 0.94)
            .opacity(appeared ? 1 : 0)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.8)) {
                appeared = true
            }
        }
    }

    private func featurePill(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.caption2.weight(.semibold))
            .tracking(1)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.white.opacity(0.09), in: Capsule())
    }
}

private struct DemoPulseMark: View {
    let size: CGFloat
    let showsCheck: Bool
    var darkOnLight = false

    private var ink: Color { darkOnLight ? .black : .white }

    var body: some View {
        ZStack {
            Circle()
                .stroke(ink.opacity(0.16), lineWidth: 1)
                .frame(width: size, height: size)
            Circle()
                .stroke(ink.opacity(0.34), lineWidth: 1)
                .frame(width: size * 0.72, height: size * 0.72)
            Circle()
                .fill(ink)
                .frame(width: size * 0.44, height: size * 0.44)
                .shadow(color: ink.opacity(0.22), radius: size * 0.14)

            if showsCheck {
                Image(systemName: "checkmark")
                    .font(.system(size: size * 0.19, weight: .bold))
                    .foregroundStyle(darkOnLight ? .white : .black)
            }
        }
    }
}
#endif
