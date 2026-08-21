import SwiftUI

struct WelcomeView: View {
    let onFirstCapture: () -> Void
    let onSkip: () -> Void
    let onLoadExamples: () -> Void

    @State private var hasAppeared = false

    var body: some View {
        ZStack {
            Color.speakBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    SpeakItWordmark()
                    Spacer()
                    Text("NO ACCOUNT")
                        .font(.caption)
                        .foregroundStyle(Color.speakMuted)
                }

                Spacer()

                VStack(spacing: 28) {
                    ListeningOrb(phase: .ready, level: 0)
                        .scaleEffect(hasAppeared ? 1 : 0.84)
                        .opacity(hasAppeared ? 1 : 0)

                    VStack(spacing: 10) {
                        Text("Speak it.\nIt’s handled.")
                            .font(.largeTitle.weight(.semibold))
                            .multilineTextAlignment(.center)

                        Text("Say anything you need to do or remember. Speak It figures out where it belongs.")
                            .font(.body)
                            .foregroundStyle(Color.speakMuted)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 330)
                    }

                    HStack(spacing: 0) {
                        welcomeBeat(icon: "waveform", title: "Speak")
                        connector
                        welcomeBeat(icon: "sparkles", title: "Organized")
                        connector
                        welcomeBeat(icon: "checkmark", title: "Remembered")
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 16)
                    .background(.black, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Speak, organized, remembered")

                    Text("Try “Buy toothpaste,” or use your own words.")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(Color.speakMuted)
                        .multilineTextAlignment(.center)
                }

                Spacer()

                VStack(spacing: 14) {
                    Button(action: onFirstCapture) {
                        Text("Try it now")
                            .font(.headline)
                            .foregroundStyle(Color.speakInverseInk)
                            .frame(maxWidth: .infinity, minHeight: 56)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.speakIt)
                    .background(Color.speakInverseSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .accessibilityIdentifier("welcome.tryItNow")

                    Button("Explore first", action: onSkip)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.speakMuted)
                        .buttonStyle(.speakIt)
                        .accessibilityIdentifier("welcome.exploreFirst")

#if DEBUG
                    Button(action: onLoadExamples) {
                        Label("Load test examples", systemImage: "sparkles")
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.speakInk)
                    .buttonStyle(.speakIt)
                    .accessibilityHint("Adds ten sample captures without using the microphone")
#endif
                }
            }
            .padding(.horizontal, 26)
            .padding(.top, 16)
            .padding(.bottom, 20)
            .foregroundStyle(Color.speakInk)
        }
        .onAppear {
            withAnimation(.spring(response: 0.7, dampingFraction: 0.82)) {
                hasAppeared = true
            }
        }
    }

    private var connector: some View {
        Rectangle()
            .fill(.white.opacity(0.18))
            .frame(height: 1)
            .frame(maxWidth: .infinity)
    }

    private func welcomeBeat(icon: String, title: String) -> some View {
        VStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 34, height: 34)
                .background(.white.opacity(0.11), in: Circle())

            Text(title)
                .font(.caption2.weight(.medium))
        }
        .frame(width: 82)
    }
}

struct WelcomeView_Previews: PreviewProvider {
    static var previews: some View {
        WelcomeView(onFirstCapture: {}, onSkip: {}, onLoadExamples: {})
    }
}

/// The first capture is the onboarding: this one quiet hand-off explains the
/// result the person just saw instead of front-loading another tutorial page.
struct FirstCaptureGuideView: View {
    let onDone: () -> Void

    var body: some View {
        ZStack {
            Color.speakBackground.ignoresSafeArea()

            GeometryReader { geometry in
                ScrollView {
                    VStack(spacing: 0) {
                        HStack {
                            SpeakItWordmark()
                            Spacer()
                            Button("Done", action: onDone)
                                .font(.subheadline.weight(.semibold))
                                .buttonStyle(.speakIt)
                                .accessibilityIdentifier("firstCaptureGuide.done")
                        }

                        Spacer(minLength: 24)

                        VStack(spacing: 24) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 30, weight: .semibold))
                                .foregroundStyle(Color.speakInverseInk)
                                .frame(width: 76, height: 76)
                                .background(Color.speakInverseSurface, in: Circle())

                            VStack(spacing: 9) {
                                Text("That’s the whole idea.")
                                    .font(.title.weight(.semibold))
                                    .multilineTextAlignment(.center)

                                Text("Speak It keeps the original capture, then routes each thought to the place it belongs.")
                                    .font(.body)
                                    .foregroundStyle(Color.speakMuted)
                                    .multilineTextAlignment(.center)
                                    .frame(maxWidth: 340)
                            }

                            VStack(spacing: 12) {
                                destinationCard(
                                    symbol: "checkmark.circle",
                                    title: "Today is for action",
                                    detail: "Tasks, reminders, overdue work, and anything you plan to do."
                                )
                                destinationCard(
                                    symbol: "books.vertical",
                                    title: "Memory is for knowledge",
                                    detail: "Ideas, people, notes, and useful context you want to find later."
                                )
                            }
                            .frame(maxWidth: 390)
                        }

                        Spacer(minLength: 28)

                        Button(action: onDone) {
                            Text("Continue")
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
                        .accessibilityIdentifier("firstCaptureGuide.continue")
                    }
                    .frame(minHeight: max(0, geometry.size.height))
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                    .padding(.bottom, 20)
                    .foregroundStyle(Color.speakInk)
                }
                .scrollIndicators(.hidden)
                .scrollBounceBehavior(.basedOnSize)
            }
        }
    }

    private func destinationCard(
        symbol: String,
        title: String,
        detail: String
    ) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 40, height: 40)
                .background(Color.speakInk.opacity(0.07), in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(Color.speakMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
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
        .accessibilityElement(children: .combine)
    }
}

struct FirstCaptureGuideView_Previews: PreviewProvider {
    static var previews: some View {
        FirstCaptureGuideView(onDone: {})
    }
}
