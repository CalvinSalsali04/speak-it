import SwiftUI

/// Speak It's ink-and-paper take on thinking orbs and border beams.
/// The outer contour responds to real audio; the traveling edge means work is
/// in progress, never a percentage or a promise that words are already saved.
struct ListeningOrb: View {
    enum Phase {
        case ready
        case listening
        case processing
    }

    let phase: Phase
    let level: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    private var normalizedLevel: CGFloat {
        level.isFinite ? min(max(level, 0), 1) : 0
    }

    private var isAnimated: Bool {
        !reduceMotion && scenePhase == .active && phase != .ready
    }

    var body: some View {
        // Removing the timeline entirely gives Reduce Motion and the resting
        // screen no continuous work. Environment changes take effect live.
        Group {
            if isAnimated {
                TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
                    artwork(time: context.date.timeIntervalSinceReferenceDate)
                }
            } else {
                artwork(time: 0)
            }
        }
        .frame(width: 230, height: 230)
        .accessibilityHidden(true)
    }

    private func artwork(time: Double) -> some View {
        let amplitude = isAnimated && phase == .listening ? normalizedLevel : 0
        let motion = time.truncatingRemainder(dividingBy: 120) * .pi / 3

        return ZStack {
            // Soft depth from a native gradient in the app’s semantic ink color.
            Circle()
                .fill(RadialGradient(
                    colors: [Color.speakInk.opacity(0.075), .clear],
                    center: .center, startRadius: 38, endRadius: 109
                ))
                .frame(width: 218, height: 218)

            ForEach(0..<4, id: \.self) { index in
                InkContour(
                    time: motion + Double(index) * 0.65,
                    deformation: phase == .ready ? 0 : 2 + amplitude * 7,
                    radiusInset: CGFloat(index) * 11
                )
                .stroke(
                    Color.speakInk.opacity(0.12 + Double(3 - index) * 0.055),
                    lineWidth: index == 0 ? 1.2 : 0.8
                )
                .frame(width: 190, height: 190)
                .scaleEffect(1 + amplitude * 0.07)
            }

            if phase == .processing {
                Circle()
                    .strokeBorder(
                        AngularGradient(
                            stops: [
                                .init(color: .clear, location: 0),
                                .init(color: Color.speakInk.opacity(0.12), location: 0.55),
                                .init(color: Color.speakInk.opacity(0.8), location: 0.88),
                                .init(color: .clear, location: 1)
                            ],
                            center: .center,
                            startAngle: .degrees(motion * 180 / .pi),
                            endAngle: .degrees(motion * 180 / .pi + 360)
                        ),
                        lineWidth: 1.8
                    )
                    .frame(width: 112, height: 112)
            }

            Circle()
                .fill(Color.speakInverseSurface)
                .overlay {
                    Circle().strokeBorder(
                        LinearGradient(
                            colors: [Color.speakInverseInk.opacity(0.3), .clear],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ), lineWidth: 1
                    )
                }
                .frame(width: 72, height: 72)
                .shadow(color: Color.speakInk.opacity(0.12), radius: 16, y: 4)
                .scaleEffect(1 + amplitude * 0.12)

            Image(systemName: phase == .processing ? "ellipsis" : "waveform")
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(Color.speakInverseInk)
        }
        .animation(isAnimated ? .easeOut(duration: 0.16) : nil, value: amplitude)
    }
}

/// A bounded, seamless contour. Two harmonics give the rings a fluid quality
/// while leaving ample separation from the central control and its hit area.
private struct InkContour: Shape {
    var time: Double
    var deformation: CGFloat
    var radiusInset: CGFloat

    var animatableData: CGFloat {
        get { deformation }
        set { deformation = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let radius = min(rect.width, rect.height) / 2 - 10 - radiusInset
        var path = Path()
        for step in 0..<120 {
            let angle = Double(step) / 120 * .pi * 2
            let wave = sin(angle * 3 + time) * 0.6
                + cos(angle * 2 - time) * 0.4
            let distance = radius + CGFloat(wave) * deformation
            let point = CGPoint(
                x: rect.midX + CGFloat(cos(angle)) * distance,
                y: rect.midY + CGFloat(sin(angle)) * distance
            )
            if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }
}

#Preview("Capture states") {
    VStack(spacing: 0) {
        ListeningOrb(phase: .ready, level: 0)
        ListeningOrb(phase: .listening, level: 0.65)
        ListeningOrb(phase: .processing, level: 0)
    }
    .frame(maxWidth: .infinity)
    .speakScreenStyle()
}


/// A brief liquid settle after persistence succeeds. Receipt text and actions
/// appear immediately; duplicates and outcomes needing review stay still.
struct SavedCaptureSeal: View {
    let symbol: String
    let celebratesSave: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var settled = false

    private var permitsMotion: Bool {
        celebratesSave && !reduceMotion && scenePhase == .active
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.speakInk.opacity(0.18), lineWidth: 1)
                .frame(width: 150, height: 150)

            SettlingInk(progress: settled || !permitsMotion ? 1 : 0)
                .fill(Color.speakInverseSurface)
                .frame(width: 136, height: 136)
                .shadow(color: Color.speakInk.opacity(0.18), radius: 28)

            Image(systemName: symbol)
                .font(.system(size: 42, weight: .medium))
                .foregroundStyle(Color.speakInverseInk)
        }
        .frame(width: 150, height: 150)
        .animation(
            permitsMotion ? .spring(response: 0.55, dampingFraction: 0.82) : nil,
            value: settled
        )
        .onAppear { settled = true }
        .onChange(of: permitsMotion) { _, allowed in
            // Never replay a success when returning from the background.
            if !allowed { settled = true }
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}

/// Two joined ink lobes relax into the existing 104-point receipt circle.
/// A single filled path keeps the liquid edge crisp without blur filters.
private struct SettlingInk: Shape {
    var progress: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let remaining = 1 - min(max(progress, 0), 1)
        let scale = min(rect.width, rect.height) / 136
        var path = Path()
        for step in 0..<120 {
            let angle = Double(step) / 120 * .pi * 2
            let radius = (52 + remaining * (14 * CGFloat(cos(2 * angle)) - 4)) * scale
            let point = CGPoint(
                x: rect.midX + radius * CGFloat(cos(angle)),
                y: rect.midY + radius * CGFloat(sin(angle))
            )
            if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }
}
