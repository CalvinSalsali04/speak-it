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
                    Text("SPEAK IT")
                        .font(.caption.weight(.medium))
                        .tracking(2.8)
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
                        Text("Say it.\nIt’s remembered.")
                            .font(.largeTitle.weight(.semibold))
                            .multilineTextAlignment(.center)

                        Text("Speak naturally. Speak It saves the words, separates multiple thoughts, and puts each one where it belongs.")
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
