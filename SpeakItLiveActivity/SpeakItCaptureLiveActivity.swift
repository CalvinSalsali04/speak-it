import ActivityKit
import SwiftUI
import WidgetKit

struct SpeakItCaptureLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: CaptureActivityAttributes.self) { context in
            lockScreenView(context: context)
                .activityBackgroundTint(.black)
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    MemoryPulseMark(phase: context.state.phase, size: 48)
                        .padding(.leading, 4)
                }

                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 2) {
                        Text("SPEAK IT")
                            .font(.caption2.weight(.semibold))
                            .tracking(1.8)
                            .foregroundStyle(.white.opacity(0.52))
                        Text(context.state.title)
                            .font(.headline)
                            .foregroundStyle(.white)
                    }
                }

                DynamicIslandExpandedRegion(.trailing) {
                    Image(systemName: statusSymbol(for: context.state.phase))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(.white.opacity(0.10), in: Circle())
                        .padding(.trailing, 4)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.state.detail)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.72))
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 6)
                        .padding(.top, 6)
                }
            } compactLeading: {
                MemoryPulseMark(phase: context.state.phase, size: 23)
            } compactTrailing: {
                Image(systemName: statusSymbol(for: context.state.phase))
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
            } minimal: {
                MemoryPulseMark(phase: context.state.phase, size: 22)
            }
            .keylineTint(.white.opacity(0.38))
        }
    }

    private func lockScreenView(
        context: ActivityViewContext<CaptureActivityAttributes>
    ) -> some View {
        HStack(spacing: 16) {
            MemoryPulseMark(phase: context.state.phase, size: 54)

            VStack(alignment: .leading, spacing: 4) {
                Text("SPEAK IT")
                    .font(.caption2.weight(.semibold))
                    .tracking(1.8)
                    .foregroundStyle(.white.opacity(0.48))
                Text(context.state.title)
                    .font(.headline)
                    .foregroundStyle(.white)
                Text(context.state.detail)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.64))
                    .lineLimit(2)
            }

            Spacer(minLength: 12)

            Image(systemName: statusSymbol(for: context.state.phase))
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.black)
                .frame(width: 36, height: 36)
                .background(.white, in: Circle())
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Speak It, \(context.state.title). \(context.state.detail)")
    }

    private func statusSymbol(
        for phase: CaptureActivityAttributes.ContentState.Phase
    ) -> String {
        switch phase {
        case .listening: "waveform"
        case .organizing: "ellipsis"
        case .remembered: "checkmark"
        case .problem: "exclamationmark"
        }
    }
}

private struct MemoryPulseMark: View {
    let phase: CaptureActivityAttributes.ContentState.Phase
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .stroke(.white.opacity(0.16), lineWidth: 1)
                .frame(width: size, height: size)

            Circle()
                .stroke(.white.opacity(0.34), lineWidth: 1)
                .frame(width: size * 0.72, height: size * 0.72)

            Circle()
                .fill(.white)
                .frame(width: size * 0.42, height: size * 0.42)

            if phase != .listening {
                Image(systemName: phaseSymbol)
                    .font(.system(size: size * 0.19, weight: .bold))
                    .foregroundStyle(.black)
            }
        }
    }

    private var phaseSymbol: String {
        switch phase {
        case .listening: "waveform"
        case .organizing: "ellipsis"
        case .remembered: "checkmark"
        case .problem: "exclamationmark"
        }
    }
}
