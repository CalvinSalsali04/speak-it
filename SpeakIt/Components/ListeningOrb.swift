import SwiftUI

struct ListeningOrb: View {
    enum Phase {
        case ready
        case listening
        case processing
    }

    let phase: Phase
    let level: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var isBreathing = false

    private var normalizedLevel: CGFloat {
        min(max(level, 0), 1)
    }

    var body: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .stroke(
                        Color.speakInk.opacity(ringOpacity(for: index)),
                        lineWidth: 1
                    )
                    .frame(width: 168, height: 168)
                    .scaleEffect(ringScale(for: index))
            }

            Circle()
                .fill(Color.speakInverseSurface)
                .frame(width: 72, height: 72)
                .shadow(
                    color: Color.speakInk.opacity(phase == .listening ? 0.24 : 0.14),
                    radius: phase == .listening ? 32 : 22
                )
                .scaleEffect(coreScale)

            Image(systemName: phase == .processing ? "ellipsis" : "waveform")
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(Color.speakInverseInk)
                .contentTransition(.symbolEffect(.replace))
        }
        .frame(width: 230, height: 230)
        // The rings ride live microphone amplitude, so this is continuous
        // movement for as long as somebody is speaking.
        .animation(reduceMotion ? nil : .spring(response: 0.22, dampingFraction: 0.70), value: normalizedLevel)
        .animation(.easeInOut(duration: 0.28), value: phase)
        .onAppear {
            // The one animation every capture goes through, and it never stops.
            // Reduce Motion gets the resting geometry instead; the phase
            // cross-fade above still separates ready, listening and processing,
            // so nothing the orb communicates is lost. This follows the guard
            // `TapMarker` and `ActionButtonIllustration` already use.
            guard !reduceMotion else {
                isBreathing = false
                return
            }
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                isBreathing = true
            }
        }
        .accessibilityHidden(true)
    }

    private var coreScale: CGFloat {
        switch phase {
        case .ready:
            isBreathing ? 1.05 : 0.96
        case .listening:
            1 + normalizedLevel * 0.12
        case .processing:
            isBreathing ? 0.96 : 0.88
        }
    }

    private func ringScale(for index: Int) -> CGFloat {
        let spacing = CGFloat(index) * 0.13
        switch phase {
        case .ready:
            return 0.84 + spacing + (isBreathing ? 0.055 : 0)
        case .listening:
            return 0.88 + spacing + normalizedLevel * (0.14 + CGFloat(index) * 0.045)
        case .processing:
            return 0.84 + spacing + (isBreathing ? 0.07 : 0)
        }
    }

    private func ringOpacity(for index: Int) -> Double {
        let base = phase == .listening ? 0.54 : 0.24
        return max(0.08, base - Double(index) * 0.08)
    }
}
